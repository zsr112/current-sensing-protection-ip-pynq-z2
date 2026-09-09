`timescale 1ns/1ps

module tb_stage2e_aggregate_saturation_equivalence;
    localparam integer COUNTER_WIDTH = 2;
    localparam integer COUNTER_MAX = (1 << COUNTER_WIDTH) - 1;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg delivery_valid = 1'b0;
    reg [15:0] delivery_sequence = 16'd0;
    reg fifo_underflow_attempt = 1'b0;
    reg [COUNTER_WIDTH-1:0] source_accept_count_in = 0;
    reg [COUNTER_WIDTH-1:0] backpressure_cycle_count_in = 0;
    reg [COUNTER_WIDTH-1:0] source_protocol_violation_count_in = 0;
    reg [COUNTER_WIDTH-1:0] source_drop_count_in = 0;
    reg [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count_in = 0;
    reg [COUNTER_WIDTH-1:0] source_counter_saturation_count_in = 0;
    reg [15:0] last_source_sequence_in = 16'd0;
    reg [9:0] status_w1c_clear = 10'd0;

    wire [COUNTER_WIDTH-1:0] aggregate_error_count;
    wire [9:0] sticky_status;

    integer aggregate_value;
    integer protocol_delta;
    integer overflow_delta;
    integer saturation_delta;
    integer local_error;
    integer local_saturation;
    integer expected_increment;
    integer expected_total;
    integer case_count = 0;
    reg [COUNTER_WIDTH+1:0] expected_increment_wide;
    reg [COUNTER_WIDTH+1:0] expected_extended_sum;
    reg [COUNTER_WIDTH-1:0] expected_next_count;
    reg expected_sum_saturates;
    reg expected_reaches_saturation;

    always #5 clk = ~clk;

    transaction_destination_observer #(
        .SEQUENCE_WIDTH(16),
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .delivery_valid(delivery_valid),
        .delivery_sequence(delivery_sequence),
        .fifo_underflow_attempt(fifo_underflow_attempt),
        .source_accept_count_in(source_accept_count_in),
        .backpressure_cycle_count_in(backpressure_cycle_count_in),
        .source_protocol_violation_count_in(
            source_protocol_violation_count_in),
        .source_drop_count_in(source_drop_count_in),
        .fifo_overflow_attempt_count_in(fifo_overflow_attempt_count_in),
        .source_counter_saturation_count_in(
            source_counter_saturation_count_in),
        .last_source_sequence_in(last_source_sequence_in),
        .status_w1c_clear(status_w1c_clear),
        .source_accept_count(),
        .destination_delivery_count(),
        .backpressure_cycle_count(),
        .source_protocol_violation_count(),
        .source_drop_count(),
        .fifo_overflow_attempt_count(),
        .fifo_underflow_attempt_count(),
        .duplicate_delivery_count(),
        .sequence_gap_count(),
        .reorder_or_stale_count(),
        .aggregate_error_count(aggregate_error_count),
        .last_source_sequence(),
        .last_destination_sequence(),
        .expected_delivery(),
        .duplicate_delivery(),
        .stale_first_delivery(),
        .sequence_gap(),
        .reorder_or_stale(),
        .sequence_delta(),
        .sticky_status(sticky_status)
    );

    task automatic fail(input [8*160-1:0] message);
        begin
            $display("FAIL: %0s", message);
            $finish(1);
        end
    endtask

    task apply_forced_input(
        input [COUNTER_WIDTH-1:0] protocol_value,
        input [COUNTER_WIDTH-1:0] overflow_value,
        input [COUNTER_WIDTH-1:0] saturation_value,
        input local_error_value,
        input local_saturation_value
    );
        begin
            force dut.source_protocol_delta = protocol_value;
            force dut.source_overflow_delta = overflow_value;
            force dut.source_saturation_delta = saturation_value;
            force dut.source_protocol_event = |protocol_value;
            force dut.source_overflow_event = |overflow_value;
            force dut.source_saturation_event = |saturation_value;
            force dut.local_error_event = local_error_value;
            force dut.local_nonaggregate_saturation_event =
                local_saturation_value;
        end
    endtask

    task apply_forced_pending_increment(
        input [COUNTER_WIDTH-1:0] protocol_value,
        input [COUNTER_WIDTH-1:0] overflow_value,
        input [COUNTER_WIDTH-1:0] saturation_value,
        input local_error_value,
        input local_saturation_value
    );
        begin
            force dut.aggregate_protocol_delta_pending = protocol_value;
            force dut.aggregate_overflow_delta_pending = overflow_value;
            force dut.aggregate_saturation_delta_pending = saturation_value;
            force dut.aggregate_local_error_pending = local_error_value;
            force dut.aggregate_local_saturation_pending =
                local_saturation_value;
        end
    endtask

    task automatic release_forced_input;
        begin
            release dut.source_protocol_delta;
            release dut.source_overflow_delta;
            release dut.source_saturation_delta;
            release dut.source_protocol_event;
            release dut.source_overflow_event;
            release dut.source_saturation_event;
            release dut.local_error_event;
            release dut.local_nonaggregate_saturation_event;
        end
    endtask

    task automatic release_forced_pending_increment;
        begin
            release dut.aggregate_protocol_delta_pending;
            release dut.aggregate_overflow_delta_pending;
            release dut.aggregate_saturation_delta_pending;
            release dut.aggregate_local_error_pending;
            release dut.aggregate_local_saturation_pending;
        end
    endtask

    task apply_forced_registered_increment(
        input [COUNTER_WIDTH+1:0] increment_value
    );
        begin
            force dut.aggregate_increment_pending = increment_value;
        end
    endtask

    task automatic release_forced_registered_increment;
        begin
            release dut.aggregate_increment_pending;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        for (aggregate_value = 0; aggregate_value <= COUNTER_MAX;
             aggregate_value = aggregate_value + 1) begin
            for (protocol_delta = 0; protocol_delta <= COUNTER_MAX;
                 protocol_delta = protocol_delta + 1) begin
                for (overflow_delta = 0; overflow_delta <= COUNTER_MAX;
                     overflow_delta = overflow_delta + 1) begin
                    for (saturation_delta = 0;
                         saturation_delta <= COUNTER_MAX;
                         saturation_delta = saturation_delta + 1) begin
                        for (local_error = 0; local_error <= 1;
                             local_error = local_error + 1) begin
                            for (local_saturation = 0;
                                 local_saturation <= 1;
                                 local_saturation = local_saturation + 1) begin
                                force dut.aggregate_error_count =
                                    aggregate_value[COUNTER_WIDTH-1:0];
                                expected_increment = protocol_delta +
                                    overflow_delta + saturation_delta +
                                    local_error + local_saturation;
                                expected_increment_wide = expected_increment;
                                expected_total = aggregate_value +
                                    expected_increment;
                                expected_extended_sum = expected_total;
                                expected_next_count =
                                    (expected_total >= COUNTER_MAX) ?
                                    COUNTER_MAX : expected_total;
                                expected_sum_saturates =
                                    expected_total >= COUNTER_MAX;
                                expected_reaches_saturation =
                                    (expected_increment != 0) &&
                                    (aggregate_value != COUNTER_MAX) &&
                                    (expected_total >= COUNTER_MAX);
                                apply_forced_pending_increment(
                                    protocol_delta[COUNTER_WIDTH-1:0],
                                    overflow_delta[COUNTER_WIDTH-1:0],
                                    saturation_delta[COUNTER_WIDTH-1:0],
                                    local_error[0], local_saturation[0]);
                                apply_forced_registered_increment(
                                    expected_increment_wide);
                                #1;
                                if (dut.aggregate_increment_sum !==
                                    expected_increment_wide)
                                    fail("registered increment input differs from operand sum");
                                if (dut.aggregate_extended_sum !==
                                    expected_extended_sum)
                                    fail("widened aggregate sum differs from arithmetic model");
                                if (dut.aggregate_pending_nonzero !==
                                    (expected_increment != 0))
                                    fail("aggregate increment presence differs from prior semantics");
                                if (dut.aggregate_sum_saturates !==
                                    expected_sum_saturates)
                                    fail("aggregate saturation decode differs from prior semantics");
                                if (dut.aggregate_next_count !==
                                    expected_next_count)
                                    fail("aggregate next count differs from prior saturating add");
                                if (dut.aggregate_reaches_saturation !==
                                    expected_reaches_saturation)
                                    fail("aggregate saturation event differs from prior comparison");
                                case_count = case_count + 1;
                            end
                        end
                    end
                end
            end
        end
        release dut.aggregate_error_count;
        release_forced_pending_increment();
        release_forced_registered_increment();
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        if (aggregate_error_count !== 2'd0)
            fail("directed cycle check did not restart from reset state");

        @(negedge clk);
        apply_forced_input(2'd2, 2'd0, 2'd0, 1'b0, 1'b0);
        @(posedge clk);
        #1;
        if (aggregate_error_count !== 2'd0)
            fail("aggregate register updated before the registered boundary");
        @(negedge clk);
        release_forced_input();
        apply_forced_input(2'd0, 2'd0, 2'd0, 1'b0, 1'b0);
        @(posedge clk);
        #1;
        if (aggregate_error_count !== 2'd0)
            fail("aggregate register updated before the arithmetic boundary");
        @(negedge clk);
        release_forced_input();
        apply_forced_input(2'd0, 2'd0, 2'd0, 1'b0, 1'b0);
        @(posedge clk);
        #1;
        if (aggregate_error_count !== 2'd2)
            fail("aggregate register did not consume the pipelined increment");
        @(negedge clk);
        release_forced_input();
        apply_forced_input(2'd1, 2'd0, 2'd0, 1'b0, 1'b0);
        @(posedge clk);
        #1;
        if (aggregate_error_count !== 2'd2)
            fail("aggregate register changed before the operand boundary");
        @(negedge clk);
        release_forced_input();
        apply_forced_input(2'd0, 2'd0, 2'd0, 1'b0, 1'b0);
        @(posedge clk);
        #1;
        if (!dut.aggregate_reaches_saturation)
            fail("exact-max transition did not assert after the arithmetic boundary");
        @(posedge clk);
        #1;
        if (aggregate_error_count !== 2'd3)
            fail("aggregate register did not saturate at exact max");
        @(negedge clk);
        release_forced_input();
        apply_forced_input(2'd0, 2'd0, 2'd0, 1'b0, 1'b0);
        @(posedge clk);
        #1;
        if (aggregate_error_count !== 2'd3)
            fail("zero increment changed a saturated aggregate register");
        release_forced_input();

        if (case_count != 1024)
            fail("exhaustive small-width case count differs from 1024");
        $display("AGGREGATE_SATURATION_EQUIVALENCE=PASS_1024_OF_1024");
        $display("AGGREGATE_CYCLE_SEMANTICS=PASS");
        $display("AGGREGATE_REGISTERED_INPUT_BOUNDARY=PASS");
        $display("AGGREGATE_REGISTERED_ARITHMETIC_BOUNDARY=PASS");
        $finish;
    end

    initial begin
        #20000;
        fail("timeout");
    end
endmodule
