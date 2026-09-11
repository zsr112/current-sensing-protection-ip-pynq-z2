`timescale 1ns/1ps

// This connected fixture detects divergence between destination observability
// and policy after their mutable delivery history is consolidated.
module stage2h_b2_destination_sequence_matrix #(
    parameter SEQUENCE_WIDTH = 32
);
    localparam DATA_WIDTH = 12;
    localparam CNT_WIDTH = 16;
    localparam HEALTH_CNT_WIDTH = 4;
    localparam [SEQUENCE_WIDTH-1:0] SEQUENCE_MAX =
        {SEQUENCE_WIDTH{1'b1}};
    localparam [SEQUENCE_WIDTH-1:0] SEQUENCE_ONE =
        {{(SEQUENCE_WIDTH-1){1'b0}}, 1'b1};

    reg clk = 1'b0;
    reg rst_n = 1'b1;
    always #5 clk = ~clk;

    reg sample_valid = 1'b0;
    reg [SEQUENCE_WIDTH-1:0] sample_sequence =
        {SEQUENCE_WIDTH{1'b0}};
    reg sample_source_integrity_clean = 1'b1;
    reg [DATA_WIDTH-1:0] i_ch1 = 12'd200;
    reg [DATA_WIDTH-1:0] i_ch2 = 12'd200;

    reg wr_en = 1'b0;
    reg rd_en = 1'b0;
    reg [7:0] addr = 8'd0;
    reg [31:0] wdata = 32'd0;
    reg [3:0] wstrb = 4'd0;
    wire [31:0] rdata;

    wire expected_delivery;
    wire duplicate_delivery;
    wire stale_first_delivery;
    wire sequence_gap;
    wire reorder_or_stale;
    wire [SEQUENCE_WIDTH-1:0] sequence_delta;

    wire [31:0] obs_source_accept_count;
    wire [31:0] obs_destination_delivery_count;
    wire [31:0] obs_backpressure_cycle_count;
    wire [31:0] obs_source_protocol_violation_count;
    wire [31:0] obs_source_drop_count;
    wire [31:0] obs_fifo_overflow_attempt_count;
    wire [31:0] obs_fifo_underflow_attempt_count;
    wire [31:0] obs_duplicate_delivery_count;
    wire [31:0] obs_sequence_gap_count;
    wire [31:0] obs_reorder_or_stale_count;
    wire [31:0] obs_aggregate_error_count;
    wire [SEQUENCE_WIDTH-1:0] obs_last_source_sequence_internal;
    wire [SEQUENCE_WIDTH-1:0] obs_last_destination_sequence_internal;
    wire [31:0] obs_last_source_sequence;
    wire [31:0] obs_last_destination_sequence;
    wire [9:0] obs_sticky_status;
    wire [9:0] obs_status_w1c_clear;

    wire pwm_raw;
    wire pwm_out;
    wire fault_valid;
    wire fault_latched;
    wire [7:0] fault_code;
    wire [7:0] fault_code_latched;
    wire [3:0] fsm_state;

    wire fault_eval_valid;
    wire [SEQUENCE_WIDTH-1:0] fault_eval_sequence;
    wire fault_eval_integrity_clean;
    wire clear_pending;
    wire clear_accept_event;
    wire [SEQUENCE_WIDTH-1:0] clear_resolution_sequence;

    integer failures = 0;
    integer deliveries = 0;

    assign obs_last_source_sequence = obs_last_source_sequence_internal;
    assign obs_last_destination_sequence =
        obs_last_destination_sequence_internal;

    transaction_destination_observer #(
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .COUNTER_WIDTH(32)
    ) u_observer (
        .clk(clk),
        .rst_n(rst_n),
        .delivery_valid(sample_valid),
        .delivery_sequence(sample_sequence),
        .fifo_underflow_attempt(1'b0),
        .source_accept_count_in(32'd0),
        .backpressure_cycle_count_in(32'd0),
        .source_protocol_violation_count_in(32'd0),
        .source_drop_count_in(32'd0),
        .fifo_overflow_attempt_count_in(32'd0),
        .source_counter_saturation_count_in(32'd0),
        .last_source_sequence_in({SEQUENCE_WIDTH{1'b0}}),
        .status_w1c_clear(obs_status_w1c_clear),
        .source_accept_count(obs_source_accept_count),
        .destination_delivery_count(obs_destination_delivery_count),
        .backpressure_cycle_count(obs_backpressure_cycle_count),
        .source_protocol_violation_count(
            obs_source_protocol_violation_count),
        .source_drop_count(obs_source_drop_count),
        .fifo_overflow_attempt_count(obs_fifo_overflow_attempt_count),
        .fifo_underflow_attempt_count(obs_fifo_underflow_attempt_count),
        .duplicate_delivery_count(obs_duplicate_delivery_count),
        .sequence_gap_count(obs_sequence_gap_count),
        .reorder_or_stale_count(obs_reorder_or_stale_count),
        .aggregate_error_count(obs_aggregate_error_count),
        .last_source_sequence(obs_last_source_sequence_internal),
        .last_destination_sequence(obs_last_destination_sequence_internal),
        .expected_delivery(expected_delivery),
        .duplicate_delivery(duplicate_delivery),
        .stale_first_delivery(stale_first_delivery),
        .sequence_gap(sequence_gap),
        .reorder_or_stale(reorder_or_stale),
        .sequence_delta(sequence_delta),
        .sticky_status(obs_sticky_status)
    );

    stage2g_protection_ip_reg_controlled #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(CNT_WIDTH),
        .ADDR_WIDTH(8),
        .REG_DATA_WIDTH(32),
        .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH),
        .OBS_SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH)
    ) u_policy (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_sequence(sample_sequence),
        .sample_source_integrity_clean(sample_source_integrity_clean),
        .sample_destination_integrity_clean(expected_delivery),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .addr(addr),
        .wdata(wdata),
        .wstrb(wstrb),
        .rdata(rdata),
        .i_ch1(i_ch1),
        .i_ch2(i_ch2),
        .obs_sticky_status(obs_sticky_status),
        .obs_source_accept_count(obs_source_accept_count),
        .obs_destination_delivery_count(obs_destination_delivery_count),
        .obs_backpressure_cycle_count(obs_backpressure_cycle_count),
        .obs_source_protocol_violation_count(
            obs_source_protocol_violation_count),
        .obs_source_drop_count(obs_source_drop_count),
        .obs_fifo_overflow_attempt_count(obs_fifo_overflow_attempt_count),
        .obs_fifo_underflow_attempt_count(obs_fifo_underflow_attempt_count),
        .obs_duplicate_delivery_count(obs_duplicate_delivery_count),
        .obs_sequence_gap_count(obs_sequence_gap_count),
        .obs_reorder_or_stale_count(obs_reorder_or_stale_count),
        .obs_aggregate_error_count(obs_aggregate_error_count),
        .obs_last_source_sequence(obs_last_source_sequence),
        .obs_last_destination_sequence(obs_last_destination_sequence),
        .obs_status_w1c_clear(obs_status_w1c_clear),
        .pwm_raw(pwm_raw),
        .pwm_out(pwm_out),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code(fault_code),
        .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state)
    );

    assign fault_eval_valid = u_policy.fault_eval_valid;
    assign fault_eval_sequence = u_policy.fault_eval_sequence;
    assign fault_eval_integrity_clean =
        u_policy.fault_eval_integrity_clean;
    assign clear_pending = u_policy.clear_pending;
    assign clear_accept_event = u_policy.clear_accept_event;
    assign clear_resolution_sequence = u_policy.clear_resolution_sequence;

    task automatic fail;
        input [8*120-1:0] label;
        begin
            $display("B2 DEST WIDTH %0d FAILED: %0s",
                     SEQUENCE_WIDTH, label);
            failures = failures + 1;
        end
    endtask

    task automatic check_bit;
        input [8*120-1:0] label;
        input actual;
        input expected;
        begin
            if (actual !== expected) begin
                $display("B2 DEST WIDTH %0d %0s actual=%b expected=%b",
                         SEQUENCE_WIDTH, label, actual, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_word;
        input [8*120-1:0] label;
        input [SEQUENCE_WIDTH-1:0] actual;
        input [SEQUENCE_WIDTH-1:0] expected;
        begin
            if (actual !== expected) begin
                $display("B2 DEST WIDTH %0d %0s actual=%h expected=%h",
                         SEQUENCE_WIDTH, label, actual, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic reset_path;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            sample_valid = 1'b0;
            wr_en = 1'b0;
            rd_en = 1'b0;
            repeat (2) begin
                @(posedge clk);
                #1;
            end
            check_bit("reset safe output", pwm_out, 1'b0);
            if (fsm_state !== 4'd2)
                fail("reset state is not RESET_WAIT");
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task automatic seed_tracker;
        input [SEQUENCE_WIDTH-1:0] expected_value;
        input [SEQUENCE_WIDTH-1:0] last_value;
        input has_last_value;
        begin
            @(negedge clk);
            u_observer.u_sequence_integrity_tracker.expected_sequence =
                expected_value;
            u_observer.u_sequence_integrity_tracker.last_destination_sequence =
                last_value;
            u_observer.u_sequence_integrity_tracker.has_last_delivery =
                has_last_value;
        end
    endtask

    task automatic deliver;
        input [SEQUENCE_WIDTH-1:0] sequence_value;
        input source_clean;
        input expected_clean;
        input expected_duplicate;
        input expected_stale_first;
        input expected_gap;
        input expected_reorder;
        input [DATA_WIDTH-1:0] ch1_value;
        input [DATA_WIDTH-1:0] ch2_value;
        input [8*80-1:0] label;
        reg [31:0] delivery_before;
        reg [31:0] duplicate_before;
        reg [31:0] gap_before;
        reg [31:0] reorder_before;
        begin
            @(negedge clk);
            delivery_before = obs_destination_delivery_count;
            duplicate_before = obs_duplicate_delivery_count;
            gap_before = obs_sequence_gap_count;
            reorder_before = obs_reorder_or_stale_count;
            sample_sequence = sequence_value;
            sample_source_integrity_clean = source_clean;
            i_ch1 = ch1_value;
            i_ch2 = ch2_value;
            sample_valid = 1'b1;
            #1;

            check_bit({label, " expected"}, expected_delivery,
                      expected_clean);
            check_bit({label, " duplicate"}, duplicate_delivery,
                      expected_duplicate);
            check_bit({label, " stale-first"}, stale_first_delivery,
                      expected_stale_first);
            check_bit({label, " gap"}, sequence_gap, expected_gap);
            check_bit({label, " reorder"}, reorder_or_stale,
                      expected_reorder);
            check_bit({label, " policy direct classification"},
                      u_policy.sample_destination_integrity_clean,
                      expected_delivery);

            @(posedge clk);
            #1;
            check_bit({label, " eval edge 0"}, fault_eval_valid, 1'b0);
            if (obs_destination_delivery_count !== delivery_before + 1)
                fail({label, " delivery counter"});
            if (obs_duplicate_delivery_count !==
                duplicate_before + expected_duplicate)
                fail({label, " duplicate counter"});
            if (obs_sequence_gap_count !== gap_before + expected_gap)
                fail({label, " gap counter"});
            if (obs_reorder_or_stale_count !==
                reorder_before + expected_reorder)
                fail({label, " reorder counter"});

            @(negedge clk);
            sample_valid = 1'b0;
            @(posedge clk);
            #1;
            check_bit({label, " eval edge 1"}, fault_eval_valid, 1'b0);
            @(posedge clk);
            #1;
            check_bit({label, " eval edge 2"}, fault_eval_valid, 1'b1);
            check_word({label, " eval sequence"}, fault_eval_sequence,
                       sequence_value);
            check_bit({label, " eval integrity"},
                      fault_eval_integrity_clean,
                      source_clean && expected_clean);
            @(posedge clk);
            #1;
            check_bit({label, " eval single-cycle"}, fault_eval_valid,
                      1'b0);
            deliveries = deliveries + 1;
        end
    endtask

    task automatic request_clear;
        begin
            @(negedge clk);
            addr = 8'h00;
            wdata = 32'h0000_0002;
            wstrb = 4'hf;
            wr_en = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            wr_en = 1'b0;
            wstrb = 4'd0;
            @(posedge clk);
            #1;
            check_bit("clear request captured", clear_pending, 1'b1);
        end
    endtask

    initial begin
        // First zero, continuous clean delivery, source-dirty policy input,
        // duplicate, stale, and forward-gap resynchronization.
        reset_path();
        deliver({SEQUENCE_WIDTH{1'b0}}, 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "first zero");
        if (fsm_state !== 4'd0)
            fail("first zero did not enter ARMED");
        deliver(SEQUENCE_ONE, 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "continuous clean");
        deliver(SEQUENCE_WIDTH'(2), 1'b0,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "source dirty");
        deliver(SEQUENCE_WIDTH'(2), 1'b1,
                1'b0, 1'b1, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "duplicate");
        deliver(SEQUENCE_WIDTH'(3), 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "duplicate recovery");
        deliver(SEQUENCE_WIDTH'(2), 1'b1,
                1'b0, 1'b0, 1'b0, 1'b0, 1'b1,
                12'd200, 12'd200, "stale reorder");
        check_word("stale retains expected",
                   u_observer.u_sequence_integrity_tracker.expected_sequence,
                   SEQUENCE_WIDTH'(4));
        deliver(SEQUENCE_WIDTH'(6), 1'b1,
                1'b0, 1'b0, 1'b0, 1'b1, 1'b0,
                12'd200, 12'd200, "forward gap");
        deliver(SEQUENCE_WIDTH'(7), 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "gap recovery");

        // A first nonzero delivery retains expected zero. The next forward
        // gap resynchronizes, and only the following expected delivery arms.
        reset_path();
        deliver(SEQUENCE_WIDTH'(5), 1'b1,
                1'b0, 1'b0, 1'b1, 1'b0, 1'b1,
                12'd200, 12'd200, "first nonzero");
        check_word("first nonzero retains expected zero",
                   u_observer.u_sequence_integrity_tracker.expected_sequence,
                   {SEQUENCE_WIDTH{1'b0}});
        if (fsm_state !== 4'd2)
            fail("first nonzero left RESET_WAIT");
        deliver(SEQUENCE_WIDTH'(6), 1'b1,
                1'b0, 1'b0, 1'b0, 1'b1, 1'b0,
                12'd200, 12'd200, "first nonzero gap");
        check_word("gap resynchronizes expected",
                   u_observer.u_sequence_integrity_tracker.expected_sequence,
                   SEQUENCE_WIDTH'(7));
        if (fsm_state !== 4'd2)
            fail("gap resynchronization was policy eligible");
        deliver(SEQUENCE_WIDTH'(7), 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "first nonzero recovery");
        if (fsm_state !== 4'd0)
            fail("first nonzero recovery did not arm");

        // Natural wrap and cross-wrap gap, duplicate, and stale cases.
        reset_path();
        seed_tracker(SEQUENCE_MAX - SEQUENCE_ONE,
                     SEQUENCE_MAX - SEQUENCE_WIDTH'(2), 1'b1);
        deliver(SEQUENCE_MAX - SEQUENCE_ONE, 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "wrap max-1");
        deliver(SEQUENCE_MAX, 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "wrap max");
        deliver({SEQUENCE_WIDTH{1'b0}}, 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "wrap zero");
        deliver(SEQUENCE_ONE, 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "wrap one");

        reset_path();
        seed_tracker(SEQUENCE_MAX - SEQUENCE_ONE,
                     SEQUENCE_MAX - SEQUENCE_WIDTH'(2), 1'b1);
        deliver(SEQUENCE_ONE, 1'b1,
                1'b0, 1'b0, 1'b0, 1'b1, 1'b0,
                12'd200, 12'd200, "cross-wrap gap");
        deliver(SEQUENCE_WIDTH'(2), 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "cross-wrap gap recovery");

        reset_path();
        seed_tracker({SEQUENCE_WIDTH{1'b0}}, SEQUENCE_MAX, 1'b1);
        deliver(SEQUENCE_MAX, 1'b1,
                1'b0, 1'b1, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "cross-wrap duplicate");
        deliver({SEQUENCE_WIDTH{1'b0}}, 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "cross-wrap duplicate recovery");
        deliver(SEQUENCE_MAX, 1'b1,
                1'b0, 1'b0, 1'b0, 1'b0, 1'b1,
                12'd200, 12'd200, "cross-wrap stale");

        // Clear stays request/evaluation fenced. A clean resolution enters
        // RESET_WAIT; a dirty expected transaction cannot complete recovery.
        reset_path();
        deliver({SEQUENCE_WIDTH{1'b0}}, 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "clear arm");
        deliver(SEQUENCE_ONE, 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd3500, 12'd3500, "clear fault");
        if (fsm_state !== 4'd1 || !fault_latched)
            fail("fault did not latch before clear");
        request_clear();
        repeat (2) begin
            @(posedge clk);
            #1;
        end
        if (fsm_state !== 4'd1 || !clear_pending)
            fail("clear request was not evaluation fenced");
        deliver(SEQUENCE_WIDTH'(2), 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "clear resolution");
        if (fsm_state !== 4'd2 || !clear_accept_event)
            fail("clear resolution did not enter RESET_WAIT");
        check_word("clear resolution identity", clear_resolution_sequence,
                   SEQUENCE_WIDTH'(2));
        deliver(SEQUENCE_WIDTH'(3), 1'b0,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "post-clear dirty");
        if (fsm_state !== 4'd2)
            fail("dirty post-clear transaction armed policy");
        deliver(SEQUENCE_WIDTH'(4), 1'b1,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                12'd200, 12'd200, "post-clear recovery");
        if (fsm_state !== 4'd0)
            fail("later clean post-clear transaction did not arm");

        if (failures != 0) begin
            $display("STAGE2H_B2_DESTINATION_SEQUENCE=FAIL_%0d_WIDTH_%0d",
                     failures, SEQUENCE_WIDTH);
            $fatal(1);
        end
        $display("SEQUENCE_WIDTH_%0d=PASS", SEQUENCE_WIDTH);
        $display("DESTINATION_SEQUENCE_BEHAVIOR=PASS");
        $display("POLICY_OBSERVABILITY_SEQUENCE_CLASSIFICATION_AGREEMENT=PASS");
        $display("FAULT_EVALUATION_LATENCY_ACLK=3");
        $display("DESTINATION_DELIVERIES_WIDTH_%0d=%0d",
                 SEQUENCE_WIDTH, deliveries);
        $finish;
    end
endmodule

module tb_stage2h_b2_destination_sequence_16;
    stage2h_b2_destination_sequence_matrix #(.SEQUENCE_WIDTH(16)) u_matrix();
endmodule

module tb_stage2h_b2_destination_sequence_24;
    stage2h_b2_destination_sequence_matrix #(.SEQUENCE_WIDTH(24)) u_matrix();
endmodule

module tb_stage2h_b2_destination_sequence_32;
    stage2h_b2_destination_sequence_matrix #(.SEQUENCE_WIDTH(32)) u_matrix();
endmodule
