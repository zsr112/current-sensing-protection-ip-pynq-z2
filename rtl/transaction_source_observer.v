module transaction_source_observer #(
    parameter DATA_WIDTH = 12,
    parameter SEQUENCE_WIDTH = 32,
    parameter COUNTER_WIDTH = 32
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      source_valid,
    input  wire                      source_ready,
    input  wire [DATA_WIDTH-1:0]     source_ch1,
    input  wire [DATA_WIDTH-1:0]     source_ch2,
    input  wire                      fifo_overflow_attempt,

    output wire [SEQUENCE_WIDTH-1:0] transaction_sequence,
    output wire                      transaction_integrity_clean,
    output reg  [SEQUENCE_WIDTH-1:0] last_source_sequence,
    (* KEEP = "TRUE" *)
    output reg  [SEQUENCE_WIDTH-1:0] last_source_sequence_gray,

    output reg [COUNTER_WIDTH-1:0] source_accept_count,
    output reg [COUNTER_WIDTH-1:0] backpressure_cycle_count,
    output reg [COUNTER_WIDTH-1:0] source_protocol_violation_count,
    output reg [COUNTER_WIDTH-1:0] source_drop_count,
    output reg [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count,
    output reg [COUNTER_WIDTH-1:0] counter_saturation_event_count,

    (* KEEP = "TRUE" *) output reg [COUNTER_WIDTH-1:0] source_accept_count_gray,
    (* KEEP = "TRUE" *) output reg [COUNTER_WIDTH-1:0] backpressure_cycle_count_gray,
    (* KEEP = "TRUE" *) output reg [COUNTER_WIDTH-1:0] source_protocol_violation_count_gray,
    (* KEEP = "TRUE" *) output reg [COUNTER_WIDTH-1:0] source_drop_count_gray,
    (* KEEP = "TRUE" *) output reg [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count_gray,
    (* KEEP = "TRUE" *) output reg [COUNTER_WIDTH-1:0] counter_saturation_event_count_gray
);
    localparam PAYLOAD_WIDTH = 2 * DATA_WIDTH;
    localparam [COUNTER_WIDTH-1:0] COUNTER_MAX = {COUNTER_WIDTH{1'b1}};
    localparam [COUNTER_WIDTH-1:0] COUNTER_MAX_MINUS_ONE =
        {COUNTER_WIDTH{1'b1}} - {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};

    reg [SEQUENCE_WIDTH-1:0] source_sequence;
    reg stall_pending;
    reg stall_violation_recorded;
    reg [PAYLOAD_WIDTH-1:0] stall_payload_snapshot;

    wire [PAYLOAD_WIDTH-1:0] source_payload;
    wire source_accept;
    wire backpressure_cycle;
    wire source_protocol_violation_event;
    wire any_counter_reaches_saturation;

    function [COUNTER_WIDTH-1:0] counter_increment;
        input [COUNTER_WIDTH-1:0] value;
        begin
            counter_increment = (value == COUNTER_MAX) ?
                                COUNTER_MAX : value + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
        end
    endfunction

    function [COUNTER_WIDTH-1:0] counter_binary_to_gray;
        input [COUNTER_WIDTH-1:0] value;
        begin
            counter_binary_to_gray = (value >> 1) ^ value;
        end
    endfunction

    function [SEQUENCE_WIDTH-1:0] sequence_binary_to_gray;
        input [SEQUENCE_WIDTH-1:0] value;
        begin
            sequence_binary_to_gray = (value >> 1) ^ value;
        end
    endfunction

    generate
        if (DATA_WIDTH < 1) begin : g_invalid_data_width
            STAGE2E_PARAMETER_ERROR_DATA_WIDTH_MUST_BE_AT_LEAST_1
                u_parameter_error();
        end
        if (SEQUENCE_WIDTH < 16) begin : g_invalid_sequence_width
            STAGE2E_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_AT_LEAST_16
                u_parameter_error();
        end
        if (COUNTER_WIDTH < 2) begin : g_invalid_counter_width
            STAGE2E_PARAMETER_ERROR_COUNTER_WIDTH_MUST_BE_AT_LEAST_2
                u_parameter_error();
        end
    endgenerate

    assign source_payload = {source_ch1, source_ch2};
    assign source_accept = rst_n && source_valid && source_ready;
    assign backpressure_cycle = rst_n && source_valid && !source_ready;
    assign transaction_sequence = source_sequence;

    // A violation is recorded once per stalled episode. The payload check is
    // also active on the eventual acceptance edge, because a producer must
    // hold the original word through that edge.
    assign source_protocol_violation_event =
        rst_n && stall_pending && !stall_violation_recorded &&
        (!source_valid || (source_payload != stall_payload_snapshot));
    assign transaction_integrity_clean =
        !(stall_violation_recorded || source_protocol_violation_event);

    assign any_counter_reaches_saturation =
        (source_accept && (source_accept_count == COUNTER_MAX_MINUS_ONE)) ||
        (backpressure_cycle &&
            (backpressure_cycle_count == COUNTER_MAX_MINUS_ONE)) ||
        (source_protocol_violation_event &&
            ((source_protocol_violation_count == COUNTER_MAX_MINUS_ONE) ||
             (source_drop_count == COUNTER_MAX_MINUS_ONE))) ||
        (fifo_overflow_attempt &&
            (fifo_overflow_attempt_count == COUNTER_MAX_MINUS_ONE));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_sequence <= {SEQUENCE_WIDTH{1'b0}};
            last_source_sequence <= {SEQUENCE_WIDTH{1'b0}};
            last_source_sequence_gray <= {SEQUENCE_WIDTH{1'b0}};
            stall_pending <= 1'b0;
            stall_violation_recorded <= 1'b0;
            stall_payload_snapshot <= {PAYLOAD_WIDTH{1'b0}};

            source_accept_count <= {COUNTER_WIDTH{1'b0}};
            backpressure_cycle_count <= {COUNTER_WIDTH{1'b0}};
            source_protocol_violation_count <= {COUNTER_WIDTH{1'b0}};
            source_drop_count <= {COUNTER_WIDTH{1'b0}};
            fifo_overflow_attempt_count <= {COUNTER_WIDTH{1'b0}};
            counter_saturation_event_count <= {COUNTER_WIDTH{1'b0}};

            source_accept_count_gray <= {COUNTER_WIDTH{1'b0}};
            backpressure_cycle_count_gray <= {COUNTER_WIDTH{1'b0}};
            source_protocol_violation_count_gray <= {COUNTER_WIDTH{1'b0}};
            source_drop_count_gray <= {COUNTER_WIDTH{1'b0}};
            fifo_overflow_attempt_count_gray <= {COUNTER_WIDTH{1'b0}};
            counter_saturation_event_count_gray <= {COUNTER_WIDTH{1'b0}};
        end else begin
            if (!stall_pending) begin
                if (source_valid && !source_ready) begin
                    stall_pending <= 1'b1;
                    stall_violation_recorded <= 1'b0;
                    stall_payload_snapshot <= source_payload;
                end
            end else begin
                if (source_protocol_violation_event)
                    stall_violation_recorded <= 1'b1;

                if (!source_valid || source_accept) begin
                    stall_pending <= 1'b0;
                    stall_violation_recorded <= 1'b0;
                end
            end

            if (source_accept) begin
                source_accept_count <= counter_increment(source_accept_count);
                source_accept_count_gray <= counter_binary_to_gray(
                    counter_increment(source_accept_count));
                last_source_sequence <= source_sequence;
                last_source_sequence_gray <= sequence_binary_to_gray(source_sequence);
                source_sequence <= source_sequence +
                    {{(SEQUENCE_WIDTH-1){1'b0}}, 1'b1};
            end

            if (backpressure_cycle) begin
                backpressure_cycle_count <=
                    counter_increment(backpressure_cycle_count);
                backpressure_cycle_count_gray <= counter_binary_to_gray(
                    counter_increment(backpressure_cycle_count));
            end

            if (source_protocol_violation_event) begin
                source_protocol_violation_count <=
                    counter_increment(source_protocol_violation_count);
                source_protocol_violation_count_gray <= counter_binary_to_gray(
                    counter_increment(source_protocol_violation_count));
                source_drop_count <= counter_increment(source_drop_count);
                source_drop_count_gray <= counter_binary_to_gray(
                    counter_increment(source_drop_count));
            end

            if (fifo_overflow_attempt) begin
                fifo_overflow_attempt_count <=
                    counter_increment(fifo_overflow_attempt_count);
                fifo_overflow_attempt_count_gray <= counter_binary_to_gray(
                    counter_increment(fifo_overflow_attempt_count));
            end

            if (any_counter_reaches_saturation) begin
                counter_saturation_event_count <=
                    counter_increment(counter_saturation_event_count);
                counter_saturation_event_count_gray <= counter_binary_to_gray(
                    counter_increment(counter_saturation_event_count));
            end
        end
    end
endmodule

// Metadata-aware compatibility wrapper. The shared observer owns both the
// diagnostic state and the direct transaction-correlated integrity result.
module stage2g_transaction_source_observer #(
    parameter DATA_WIDTH = 12,
    parameter SEQUENCE_WIDTH = 32,
    parameter COUNTER_WIDTH = 32
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      source_valid,
    input  wire                      source_ready,
    input  wire [DATA_WIDTH-1:0]     source_ch1,
    input  wire [DATA_WIDTH-1:0]     source_ch2,
    input  wire                      fifo_overflow_attempt,

    output wire [SEQUENCE_WIDTH-1:0] transaction_sequence,
    output wire                      transaction_integrity_clean,
    output wire [SEQUENCE_WIDTH-1:0] last_source_sequence,
    output wire [SEQUENCE_WIDTH-1:0] last_source_sequence_gray,
    output wire [COUNTER_WIDTH-1:0] source_accept_count,
    output wire [COUNTER_WIDTH-1:0] backpressure_cycle_count,
    output wire [COUNTER_WIDTH-1:0] source_protocol_violation_count,
    output wire [COUNTER_WIDTH-1:0] source_drop_count,
    output wire [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count,
    output wire [COUNTER_WIDTH-1:0] counter_saturation_event_count,
    output wire [COUNTER_WIDTH-1:0] source_accept_count_gray,
    output wire [COUNTER_WIDTH-1:0] backpressure_cycle_count_gray,
    output wire [COUNTER_WIDTH-1:0] source_protocol_violation_count_gray,
    output wire [COUNTER_WIDTH-1:0] source_drop_count_gray,
    output wire [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count_gray,
    output wire [COUNTER_WIDTH-1:0] counter_saturation_event_count_gray
);
    transaction_source_observer #(
        .DATA_WIDTH(DATA_WIDTH),
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) u_legacy_observer (
        .clk(clk), .rst_n(rst_n), .source_valid(source_valid),
        .source_ready(source_ready), .source_ch1(source_ch1),
        .source_ch2(source_ch2),
        .fifo_overflow_attempt(fifo_overflow_attempt),
        .transaction_sequence(transaction_sequence),
        .transaction_integrity_clean(transaction_integrity_clean),
        .last_source_sequence(last_source_sequence),
        .last_source_sequence_gray(last_source_sequence_gray),
        .source_accept_count(source_accept_count),
        .backpressure_cycle_count(backpressure_cycle_count),
        .source_protocol_violation_count(source_protocol_violation_count),
        .source_drop_count(source_drop_count),
        .fifo_overflow_attempt_count(fifo_overflow_attempt_count),
        .counter_saturation_event_count(counter_saturation_event_count),
        .source_accept_count_gray(source_accept_count_gray),
        .backpressure_cycle_count_gray(backpressure_cycle_count_gray),
        .source_protocol_violation_count_gray(
            source_protocol_violation_count_gray),
        .source_drop_count_gray(source_drop_count_gray),
        .fifo_overflow_attempt_count_gray(
            fifo_overflow_attempt_count_gray),
        .counter_saturation_event_count_gray(
            counter_saturation_event_count_gray)
    );
endmodule
