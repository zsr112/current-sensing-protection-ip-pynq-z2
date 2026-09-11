// Shared Stage 2E/Stage 2G delivery-sequence classification authority.
// The arithmetic is modulo 2**SEQUENCE_WIDTH.  A nonzero first delivery is
// stale, duplicates and stale/reordered deliveries retain expected_sequence,
// and only a forward gap resynchronizes to delivered+1.
module stage2e_transaction_sequence_classifier #(
    parameter SEQUENCE_WIDTH = 32
)(
    input  wire                      delivery_valid,
    input  wire [SEQUENCE_WIDTH-1:0] delivery_sequence,
    input  wire [SEQUENCE_WIDTH-1:0] expected_sequence,
    input  wire                      has_last_delivery,
    input  wire [SEQUENCE_WIDTH-1:0] last_destination_sequence,
    output wire                      expected_delivery,
    output wire                      duplicate_delivery,
    output wire                      stale_first_delivery,
    output wire                      sequence_gap,
    output wire                      reorder_or_stale,
    output wire [SEQUENCE_WIDTH-1:0] sequence_delta
);
    generate
        if ((SEQUENCE_WIDTH < 16) || (SEQUENCE_WIDTH > 32)) begin :
            g_invalid_sequence_width
            STAGE2E_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_16_TO_32
                u_parameter_error();
        end
    endgenerate

    assign sequence_delta = delivery_sequence - expected_sequence;
    assign expected_delivery = delivery_valid &&
        (delivery_sequence == expected_sequence);
    assign duplicate_delivery = delivery_valid && !expected_delivery &&
        has_last_delivery &&
        (delivery_sequence == last_destination_sequence);
    assign stale_first_delivery = delivery_valid && !expected_delivery &&
        !has_last_delivery;
    assign sequence_gap = delivery_valid && !expected_delivery &&
        !duplicate_delivery && !stale_first_delivery &&
        !sequence_delta[SEQUENCE_WIDTH-1];
    assign reorder_or_stale = delivery_valid && !expected_delivery &&
        !duplicate_delivery && !sequence_gap;
endmodule

// Single mutable delivery-history owner shared by observability and policy.
module destination_sequence_integrity_tracker #(
    parameter SEQUENCE_WIDTH = 32
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      delivery_valid,
    input  wire [SEQUENCE_WIDTH-1:0] delivery_sequence,
    output wire                      expected_delivery,
    output wire                      duplicate_delivery,
    output wire                      stale_first_delivery,
    output wire                      sequence_gap,
    output wire                      reorder_or_stale,
    output wire [SEQUENCE_WIDTH-1:0] sequence_delta,
    output reg  [SEQUENCE_WIDTH-1:0] last_destination_sequence
);
    reg [SEQUENCE_WIDTH-1:0] expected_sequence;
    reg has_last_delivery;

    generate
        if ((SEQUENCE_WIDTH < 16) || (SEQUENCE_WIDTH > 32)) begin :
            g_invalid_sequence_width
            STAGE2E_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_16_TO_32
                u_parameter_error();
        end
    endgenerate

    stage2e_transaction_sequence_classifier #(
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH)
    ) u_sequence_classifier (
        .delivery_valid(delivery_valid),
        .delivery_sequence(delivery_sequence),
        .expected_sequence(expected_sequence),
        .has_last_delivery(has_last_delivery),
        .last_destination_sequence(last_destination_sequence),
        .expected_delivery(expected_delivery),
        .duplicate_delivery(duplicate_delivery),
        .stale_first_delivery(stale_first_delivery),
        .sequence_gap(sequence_gap),
        .reorder_or_stale(reorder_or_stale),
        .sequence_delta(sequence_delta)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_sequence <= {SEQUENCE_WIDTH{1'b0}};
            has_last_delivery <= 1'b0;
            last_destination_sequence <= {SEQUENCE_WIDTH{1'b0}};
        end else if (delivery_valid) begin
            last_destination_sequence <= delivery_sequence;
            has_last_delivery <= 1'b1;
            if (expected_delivery)
                expected_sequence <= expected_sequence +
                    {{(SEQUENCE_WIDTH-1){1'b0}}, 1'b1};
            else if (sequence_gap)
                expected_sequence <= delivery_sequence +
                    {{(SEQUENCE_WIDTH-1){1'b0}}, 1'b1};
        end
    end
endmodule

module transaction_destination_observer #(
    parameter SEQUENCE_WIDTH = 32,
    parameter COUNTER_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    input wire delivery_valid,
    input wire [SEQUENCE_WIDTH-1:0] delivery_sequence,
    input wire fifo_underflow_attempt,

    input wire [COUNTER_WIDTH-1:0] source_accept_count_in,
    input wire [COUNTER_WIDTH-1:0] backpressure_cycle_count_in,
    input wire [COUNTER_WIDTH-1:0] source_protocol_violation_count_in,
    input wire [COUNTER_WIDTH-1:0] source_drop_count_in,
    input wire [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count_in,
    input wire [COUNTER_WIDTH-1:0] source_counter_saturation_count_in,
    input wire [SEQUENCE_WIDTH-1:0] last_source_sequence_in,

    input wire [9:0] status_w1c_clear,

    output wire [COUNTER_WIDTH-1:0] source_accept_count,
    output reg  [COUNTER_WIDTH-1:0] destination_delivery_count,
    output wire [COUNTER_WIDTH-1:0] backpressure_cycle_count,
    output wire [COUNTER_WIDTH-1:0] source_protocol_violation_count,
    output wire [COUNTER_WIDTH-1:0] source_drop_count,
    output wire [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count,
    output reg  [COUNTER_WIDTH-1:0] fifo_underflow_attempt_count,
    output reg  [COUNTER_WIDTH-1:0] duplicate_delivery_count,
    output reg  [COUNTER_WIDTH-1:0] sequence_gap_count,
    output reg  [COUNTER_WIDTH-1:0] reorder_or_stale_count,
    output reg  [COUNTER_WIDTH-1:0] aggregate_error_count,
    output wire [SEQUENCE_WIDTH-1:0] last_source_sequence,
    output wire [SEQUENCE_WIDTH-1:0] last_destination_sequence,
    output wire expected_delivery,
    output wire duplicate_delivery,
    output wire stale_first_delivery,
    output wire sequence_gap,
    output wire reorder_or_stale,
    output wire [SEQUENCE_WIDTH-1:0] sequence_delta,
    output reg  [9:0] sticky_status
);
    localparam [COUNTER_WIDTH-1:0] COUNTER_MAX = {COUNTER_WIDTH{1'b1}};
    localparam [COUNTER_WIDTH-1:0] COUNTER_MAX_MINUS_ONE =
        {COUNTER_WIDTH{1'b1}} - {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};

    localparam STATUS_BACKPRESSURE = 0;
    localparam STATUS_SOURCE_PROTOCOL = 1;
    localparam STATUS_SOURCE_DROP = 2;
    localparam STATUS_FIFO_OVERFLOW = 3;
    localparam STATUS_FIFO_UNDERFLOW = 4;
    localparam STATUS_DUPLICATE = 5;
    localparam STATUS_SEQUENCE_GAP = 6;
    localparam STATUS_REORDER_STALE = 7;
    localparam STATUS_COUNTER_SATURATED = 8;
    localparam STATUS_ANY_ERROR = 9;

    reg [COUNTER_WIDTH-1:0] previous_source_accept_count;
    reg [COUNTER_WIDTH-1:0] previous_backpressure_cycle_count;
    reg [COUNTER_WIDTH-1:0] previous_source_protocol_violation_count;
    reg [COUNTER_WIDTH-1:0] previous_source_drop_count;
    reg [COUNTER_WIDTH-1:0] previous_fifo_overflow_attempt_count;
    reg [COUNTER_WIDTH-1:0] previous_source_counter_saturation_count;

    wire source_backpressure_event;
    wire source_protocol_event;
    wire source_drop_event;
    wire source_overflow_event;
    wire source_saturation_event;
    wire [COUNTER_WIDTH-1:0] source_protocol_delta;
    wire [COUNTER_WIDTH-1:0] source_overflow_delta;
    wire [COUNTER_WIDTH-1:0] source_saturation_delta;

    wire duplicate_delivery_event;
    wire stale_first_delivery_event;
    wire sequence_gap_event;
    wire reorder_or_stale_event;

    wire destination_delivery_reaches_saturation;
    wire fifo_underflow_reaches_saturation;
    wire duplicate_reaches_saturation;
    wire gap_reaches_saturation;
    wire reorder_reaches_saturation;
    wire local_nonaggregate_saturation_event;
    wire aggregate_reaches_saturation;
    wire counter_saturation_event;
    wire local_error_event;
    // Source Gray decode, monotonic-delta arithmetic, and aggregate update are
    // separated by registered boundaries. The first stage captures operands;
    // the second forms their widened sum; the aggregate accumulator consumes
    // one queued sum per clock. Throughput remains one update per clock.
    reg [COUNTER_WIDTH-1:0] aggregate_protocol_delta_pending;
    reg [COUNTER_WIDTH-1:0] aggregate_overflow_delta_pending;
    reg [COUNTER_WIDTH-1:0] aggregate_saturation_delta_pending;
    reg aggregate_local_error_pending;
    reg aggregate_local_saturation_pending;
    reg [COUNTER_WIDTH+1:0] aggregate_increment_pending;
    wire [COUNTER_WIDTH+1:0] aggregate_increment_sum;
    wire aggregate_pending_nonzero;
    wire [COUNTER_WIDTH+1:0] aggregate_extended_sum;
    wire aggregate_sum_saturates;
    wire [COUNTER_WIDTH-1:0] aggregate_next_count;
    wire [8:0] post_clear_specific_status;
    wire post_clear_any_error;
    reg [9:0] event_status;

    function [COUNTER_WIDTH-1:0] counter_increment;
        input [COUNTER_WIDTH-1:0] value;
        begin
            counter_increment = (value == COUNTER_MAX) ?
                                COUNTER_MAX : value + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
        end
    endfunction

    generate
        if (SEQUENCE_WIDTH < 16) begin : g_invalid_sequence_width
            STAGE2E_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_AT_LEAST_16
                u_parameter_error();
        end
        if (COUNTER_WIDTH < 2) begin : g_invalid_counter_width
            STAGE2E_PARAMETER_ERROR_COUNTER_WIDTH_MUST_BE_AT_LEAST_2
                u_parameter_error();
        end
    endgenerate

    assign source_accept_count = source_accept_count_in;
    assign backpressure_cycle_count = backpressure_cycle_count_in;
    assign source_protocol_violation_count =
        source_protocol_violation_count_in;
    assign source_drop_count = source_drop_count_in;
    assign fifo_overflow_attempt_count = fifo_overflow_attempt_count_in;
    assign last_source_sequence = last_source_sequence_in;

    // Source counters never wrap. Ignore a transient lower decoded value and
    // wait for the registered Gray synchronizer to converge forward.
    assign source_backpressure_event =
        backpressure_cycle_count_in > previous_backpressure_cycle_count;
    assign source_protocol_event =
        source_protocol_violation_count_in >
        previous_source_protocol_violation_count;
    assign source_drop_event =
        source_drop_count_in > previous_source_drop_count;
    assign source_overflow_event =
        fifo_overflow_attempt_count_in > previous_fifo_overflow_attempt_count;
    assign source_saturation_event =
        source_counter_saturation_count_in >
        previous_source_counter_saturation_count;
    assign source_protocol_delta = source_protocol_event ?
        source_protocol_violation_count_in -
            previous_source_protocol_violation_count :
        {COUNTER_WIDTH{1'b0}};
    assign source_overflow_delta = source_overflow_event ?
        fifo_overflow_attempt_count_in -
            previous_fifo_overflow_attempt_count :
        {COUNTER_WIDTH{1'b0}};
    assign source_saturation_delta = source_saturation_event ?
        source_counter_saturation_count_in -
            previous_source_counter_saturation_count :
        {COUNTER_WIDTH{1'b0}};

    destination_sequence_integrity_tracker #(
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH)
    ) u_sequence_integrity_tracker (
        .clk(clk),
        .rst_n(rst_n),
        .delivery_valid(delivery_valid),
        .delivery_sequence(delivery_sequence),
        .expected_delivery(expected_delivery),
        .duplicate_delivery(duplicate_delivery),
        .stale_first_delivery(stale_first_delivery),
        .sequence_gap(sequence_gap),
        .reorder_or_stale(reorder_or_stale),
        .sequence_delta(sequence_delta),
        .last_destination_sequence(last_destination_sequence)
    );

    assign duplicate_delivery_event = duplicate_delivery;
    assign stale_first_delivery_event = stale_first_delivery;
    assign sequence_gap_event = sequence_gap;
    assign reorder_or_stale_event = reorder_or_stale;

    assign destination_delivery_reaches_saturation = delivery_valid &&
        (destination_delivery_count == COUNTER_MAX_MINUS_ONE);
    assign fifo_underflow_reaches_saturation = fifo_underflow_attempt &&
        (fifo_underflow_attempt_count == COUNTER_MAX_MINUS_ONE);
    assign duplicate_reaches_saturation = duplicate_delivery_event &&
        (duplicate_delivery_count == COUNTER_MAX_MINUS_ONE);
    assign gap_reaches_saturation = sequence_gap_event &&
        (sequence_gap_count == COUNTER_MAX_MINUS_ONE);
    assign reorder_reaches_saturation = reorder_or_stale_event &&
        (reorder_or_stale_count == COUNTER_MAX_MINUS_ONE);
    assign local_nonaggregate_saturation_event =
        destination_delivery_reaches_saturation ||
        fifo_underflow_reaches_saturation || duplicate_reaches_saturation ||
        gap_reaches_saturation || reorder_reaches_saturation;

    assign local_error_event = fifo_underflow_attempt ||
        duplicate_delivery_event || sequence_gap_event ||
        reorder_or_stale_event;
    assign aggregate_increment_sum =
        {{2{1'b0}}, aggregate_protocol_delta_pending} +
        {{2{1'b0}}, aggregate_overflow_delta_pending} +
        {{2{1'b0}}, aggregate_saturation_delta_pending} +
        {{(COUNTER_WIDTH+1){1'b0}}, aggregate_local_error_pending} +
        {{(COUNTER_WIDTH+1){1'b0}},
         aggregate_local_saturation_pending};
    assign aggregate_pending_nonzero = |aggregate_increment_pending;
    assign aggregate_extended_sum =
        {{2{1'b0}}, aggregate_error_count} +
        aggregate_increment_pending;
    // COUNTER_MAX is all ones, so a widened sum reaches saturation when an
    // upper bit is set or the low counter-width bits are exactly all ones.
    assign aggregate_sum_saturates =
        (|aggregate_extended_sum[COUNTER_WIDTH+1:COUNTER_WIDTH]) ||
        (&aggregate_extended_sum[COUNTER_WIDTH-1:0]);
    assign aggregate_next_count = aggregate_sum_saturates ?
        COUNTER_MAX : aggregate_extended_sum[COUNTER_WIDTH-1:0];
    assign aggregate_reaches_saturation =
        aggregate_pending_nonzero &&
        (aggregate_error_count != COUNTER_MAX) &&
        aggregate_sum_saturates;
    assign counter_saturation_event = source_saturation_event ||
        local_nonaggregate_saturation_event || aggregate_reaches_saturation;

    // ANY_ERROR is a read-only maintained aggregate. It reflects the
    // post-clear specific error causes and deliberately excludes legal
    // backpressure. A write to status_w1c_clear[9] therefore has no effect.
    assign post_clear_specific_status =
        (sticky_status[8:0] & ~status_w1c_clear[8:0]) |
        event_status[8:0];
    assign post_clear_any_error = |post_clear_specific_status[8:1];

    always @(*) begin
        event_status = 10'd0;
        event_status[STATUS_BACKPRESSURE] = source_backpressure_event;
        event_status[STATUS_SOURCE_PROTOCOL] = source_protocol_event;
        event_status[STATUS_SOURCE_DROP] = source_drop_event;
        event_status[STATUS_FIFO_OVERFLOW] = source_overflow_event;
        event_status[STATUS_FIFO_UNDERFLOW] = fifo_underflow_attempt;
        event_status[STATUS_DUPLICATE] = duplicate_delivery_event;
        event_status[STATUS_SEQUENCE_GAP] = sequence_gap_event;
        event_status[STATUS_REORDER_STALE] = reorder_or_stale_event;
        event_status[STATUS_COUNTER_SATURATED] = counter_saturation_event;
        event_status[STATUS_ANY_ERROR] = 1'b0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            destination_delivery_count <= {COUNTER_WIDTH{1'b0}};
            fifo_underflow_attempt_count <= {COUNTER_WIDTH{1'b0}};
            duplicate_delivery_count <= {COUNTER_WIDTH{1'b0}};
            sequence_gap_count <= {COUNTER_WIDTH{1'b0}};
            reorder_or_stale_count <= {COUNTER_WIDTH{1'b0}};
            aggregate_error_count <= {COUNTER_WIDTH{1'b0}};

            aggregate_protocol_delta_pending <=
                {COUNTER_WIDTH{1'b0}};
            aggregate_overflow_delta_pending <=
                {COUNTER_WIDTH{1'b0}};
            aggregate_saturation_delta_pending <=
                {COUNTER_WIDTH{1'b0}};
            aggregate_local_error_pending <= 1'b0;
            aggregate_local_saturation_pending <= 1'b0;
            aggregate_increment_pending <=
                {(COUNTER_WIDTH+2){1'b0}};
            sticky_status <= 10'd0;

            previous_source_accept_count <= {COUNTER_WIDTH{1'b0}};
            previous_backpressure_cycle_count <= {COUNTER_WIDTH{1'b0}};
            previous_source_protocol_violation_count <= {COUNTER_WIDTH{1'b0}};
            previous_source_drop_count <= {COUNTER_WIDTH{1'b0}};
            previous_fifo_overflow_attempt_count <= {COUNTER_WIDTH{1'b0}};
            previous_source_counter_saturation_count <=
                {COUNTER_WIDTH{1'b0}};
        end else begin
            sticky_status <= {post_clear_any_error,
                              post_clear_specific_status};

            if (source_accept_count_in > previous_source_accept_count)
                previous_source_accept_count <= source_accept_count_in;
            if (backpressure_cycle_count_in > previous_backpressure_cycle_count)
                previous_backpressure_cycle_count <=
                    backpressure_cycle_count_in;
            if (source_protocol_violation_count_in >
                previous_source_protocol_violation_count)
                previous_source_protocol_violation_count <=
                    source_protocol_violation_count_in;
            if (source_drop_count_in > previous_source_drop_count)
                previous_source_drop_count <= source_drop_count_in;
            if (fifo_overflow_attempt_count_in >
                previous_fifo_overflow_attempt_count)
                previous_fifo_overflow_attempt_count <=
                    fifo_overflow_attempt_count_in;
            if (source_counter_saturation_count_in >
                previous_source_counter_saturation_count)
                previous_source_counter_saturation_count <=
                    source_counter_saturation_count_in;

            if (delivery_valid) begin
                destination_delivery_count <=
                    counter_increment(destination_delivery_count);
            end

            if (fifo_underflow_attempt)
                fifo_underflow_attempt_count <=
                    counter_increment(fifo_underflow_attempt_count);
            if (duplicate_delivery_event)
                duplicate_delivery_count <=
                    counter_increment(duplicate_delivery_count);
            if (sequence_gap_event)
                sequence_gap_count <= counter_increment(sequence_gap_count);
            if (reorder_or_stale_event)
                reorder_or_stale_count <=
                    counter_increment(reorder_or_stale_count);
            // Capture current event deltas, then register their widened sum.
            // The accumulator consumes each queued sum exactly once.
            aggregate_protocol_delta_pending <= source_protocol_delta;
            aggregate_overflow_delta_pending <= source_overflow_delta;
            aggregate_saturation_delta_pending <= source_saturation_delta;
            aggregate_local_error_pending <= local_error_event;
            aggregate_local_saturation_pending <=
                local_nonaggregate_saturation_event;
            aggregate_increment_pending <= aggregate_increment_sum;

            if (aggregate_pending_nonzero)
                aggregate_error_count <= aggregate_next_count;
        end
    end
endmodule
