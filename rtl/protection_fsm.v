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
