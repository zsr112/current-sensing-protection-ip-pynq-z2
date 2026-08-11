`include "fault_defs.vh"

module protection_fsm #(
    parameter RESET_WAIT_CYCLES = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire fault_valid,
    input  wire [7:0] fault_code_in,
    input  wire clear_fault,
    output reg  fault_latched,
    output reg  pwm_disable,
    output reg  [7:0] fault_code_latched,
    output reg  [3:0] state
);
    localparam ST_NORMAL        = 4'd0;
    localparam ST_FAULT_LATCHED = 4'd1;
    localparam ST_RESET_WAIT    = 4'd2;

    reg [15:0] reset_wait_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_NORMAL;
            reset_wait_cnt <= 16'd0;
            fault_latched <= 1'b0;
            pwm_disable <= 1'b0;
            fault_code_latched <= `FAULT_NONE;
        end else begin
            case (state)
                ST_NORMAL: begin
                    reset_wait_cnt <= 16'd0;
                    fault_latched <= 1'b0;
                    pwm_disable <= 1'b0;
                    fault_code_latched <= `FAULT_NONE;
                    if (fault_valid) begin
                        state <= ST_FAULT_LATCHED;
                        fault_latched <= 1'b1;
                        pwm_disable <= 1'b1;
                        fault_code_latched <= fault_code_in;
                    end
                end

                ST_FAULT_LATCHED: begin
                    fault_latched <= 1'b1;
                    pwm_disable <= 1'b1;
                    if (clear_fault) begin
                        state <= ST_RESET_WAIT;
                        reset_wait_cnt <= 16'd0;
                    end
                end

                ST_RESET_WAIT: begin
                    fault_latched <= 1'b1;
                    pwm_disable <= 1'b1;
                    if (fault_valid) begin
                        state <= ST_FAULT_LATCHED;
                        reset_wait_cnt <= 16'd0;
                        fault_code_latched <= fault_code_in;
                    end else if (!clear_fault) begin
                        if (reset_wait_cnt >= RESET_WAIT_CYCLES-1) begin
                            state <= ST_NORMAL;
                            fault_latched <= 1'b0;
                            fault_code_latched <= `FAULT_NONE;
                        end else begin
                            reset_wait_cnt <= reset_wait_cnt + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= ST_NORMAL;
                    pwm_disable <= 1'b1;
                end
            endcase
        end
    end
endmodule

// Stage 2G episode controller.  The registered fault-evaluation transaction
// is consumed here on edge 3 of the frozen pipeline.  Clear requests are
// fenced by retirement order: only an evaluation observed while
// clear_pending was already set can resolve the request.
module stage2g_fault_episode_controller #(
    parameter SEQUENCE_WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        fault_eval_valid,
    input  wire [SEQUENCE_WIDTH-1:0] fault_eval_sequence,
    input  wire [5:0]  fault_eval_bitmap,
    input  wire [7:0]  fault_eval_code,
    input  wire        fault_eval_integrity_clean,
    input  wire        clear_fault,
    output reg         fault_latched,
    output reg         pwm_disable,
    output wire [7:0]  fault_code_latched,
    output reg         public_fault_latched_compat,
    output reg  [7:0]  public_fault_code_compat,
    output reg         post_clear_recovery_pending,
    output reg  [3:0]  state,
    output reg         clear_pending,
    output reg  [7:0]  first_fault_code,
    output reg  [5:0]  first_fault_bitmap,
    output reg  [5:0]  live_fault_bitmap,
    output reg  [5:0]  fault_seen_bitmap,
    output reg         first_fault_event,
    output reg         clear_resolution_event,
    output reg         clear_accept_event,
    output reg  [SEQUENCE_WIDTH-1:0] clear_resolution_sequence
);
    localparam ST_ARMED         = 4'd0;
    localparam ST_FAULT_LATCHED = 4'd1;
    localparam ST_RESET_WAIT     = 4'd2;

    assign fault_code_latched = first_fault_code;

    generate
        if ((SEQUENCE_WIDTH < 16) || (SEQUENCE_WIDTH > 32)) begin :
            g_invalid_sequence_width
            STAGE2G_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_16_TO_32
                u_parameter_error();
        end
    endgenerate

    task automatic clear_episode_fields;
        begin
            first_fault_code <= `FAULT_NONE;
            first_fault_bitmap <= 6'd0;
            live_fault_bitmap <= 6'd0;
            fault_seen_bitmap <= 6'd0;
        end
    endtask

    task automatic start_fault_episode;
        begin
            state <= ST_FAULT_LATCHED;
            fault_latched <= 1'b1;
            public_fault_latched_compat <= 1'b1;
            public_fault_code_compat <= fault_eval_code;
            post_clear_recovery_pending <= 1'b0;
            pwm_disable <= 1'b1;
            clear_pending <= 1'b0;
            first_fault_code <= fault_eval_code;
            first_fault_bitmap <= fault_eval_bitmap;
            live_fault_bitmap <= fault_eval_bitmap;
            fault_seen_bitmap <= fault_eval_bitmap;
            first_fault_event <= 1'b1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_RESET_WAIT;
            fault_latched <= 1'b0;
            public_fault_latched_compat <= 1'b0;
            public_fault_code_compat <= `FAULT_NONE;
            post_clear_recovery_pending <= 1'b0;
            pwm_disable <= 1'b1;
            clear_pending <= 1'b0;
            first_fault_code <= `FAULT_NONE;
            first_fault_bitmap <= 6'd0;
            live_fault_bitmap <= 6'd0;
            fault_seen_bitmap <= 6'd0;
            first_fault_event <= 1'b0;
            clear_resolution_event <= 1'b0;
            clear_accept_event <= 1'b0;
            clear_resolution_sequence <= {SEQUENCE_WIDTH{1'b0}};
        end else begin
            first_fault_event <= 1'b0;
            clear_resolution_event <= 1'b0;
            clear_accept_event <= 1'b0;

            case (state)
                ST_RESET_WAIT: begin
                    fault_latched <= 1'b0;
                    pwm_disable <= 1'b1;
                    clear_pending <= 1'b0;
                    clear_episode_fields();

                    if (fault_eval_valid &&
                        fault_eval_integrity_clean) begin
                        if (fault_eval_bitmap != 6'd0)
                            start_fault_episode();
                        else begin
                            state <= ST_ARMED;
                            public_fault_latched_compat <= 1'b0;
                            public_fault_code_compat <= `FAULT_NONE;
                            post_clear_recovery_pending <= 1'b0;
                            pwm_disable <= 1'b0;
                        end
                    end
                end

                ST_ARMED: begin
                    fault_latched <= 1'b0;
                    public_fault_latched_compat <= 1'b0;
                    public_fault_code_compat <= `FAULT_NONE;
                    post_clear_recovery_pending <= 1'b0;
                    pwm_disable <= 1'b0;
                    clear_pending <= 1'b0;
                    clear_episode_fields();

                    if (fault_eval_valid &&
                        fault_eval_integrity_clean &&
                        (fault_eval_bitmap != 6'd0))
                        start_fault_episode();
                end

                ST_FAULT_LATCHED: begin
                    fault_latched <= 1'b1;
                    pwm_disable <= 1'b1;

                    if (clear_pending && fault_eval_valid) begin
                        clear_pending <= 1'b0;
                        clear_resolution_event <= 1'b1;
                        clear_resolution_sequence <=
                            fault_eval_sequence;

                        if (fault_eval_integrity_clean &&
                            (fault_eval_bitmap == 6'd0)) begin
                            state <= ST_RESET_WAIT;
                            fault_latched <= 1'b0;
                            post_clear_recovery_pending <= 1'b1;
                            pwm_disable <= 1'b1;
                            clear_accept_event <= 1'b1;
                            clear_episode_fields();
                        end else if (fault_eval_integrity_clean) begin
                            live_fault_bitmap <= fault_eval_bitmap;
                            fault_seen_bitmap <= fault_seen_bitmap |
                                                 fault_eval_bitmap;
                        end
                    end else begin
                        // A clean retirement updates episode-live state before
                        // a same-edge new request is captured.  That retirement
                        // is therefore never allowed to resolve the request.
                        if (fault_eval_valid &&
                            fault_eval_integrity_clean) begin
                            live_fault_bitmap <= fault_eval_bitmap;
                            fault_seen_bitmap <= fault_seen_bitmap |
                                                 fault_eval_bitmap;
                        end

                        if (!clear_pending && clear_fault)
                            clear_pending <= 1'b1;
                    end
                end

                default: begin
                    state <= ST_RESET_WAIT;
                    fault_latched <= 1'b0;
                    public_fault_latched_compat <= 1'b0;
                    public_fault_code_compat <= `FAULT_NONE;
                    post_clear_recovery_pending <= 1'b0;
                    pwm_disable <= 1'b1;
                    clear_pending <= 1'b0;
                    clear_episode_fields();
                end
            endcase
        end
    end
endmodule
