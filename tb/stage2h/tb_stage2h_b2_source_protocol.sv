`timescale 1ns/1ps

// This fixture detects any second source stall-state machine by comparing the
// shared observer result, accepted FIFO sideband, diagnostics, and policy.
module tb_stage2h_b2_source_protocol;
    localparam DATA_WIDTH = 12;
    localparam SEQUENCE_WIDTH = 32;

    reg src_clk = 1'b0;
    reg dst_clk = 1'b0;
    always #4 src_clk = ~src_clk;
    always #5 dst_clk = ~dst_clk;

    reg src_rst_n = 1'b0;
    reg dst_rst_n = 1'b0;
    reg src_sample_valid = 1'b0;
    wire src_sample_ready;
    reg [DATA_WIDTH-1:0] src_sample_ch1 = 12'd0;
    reg [DATA_WIDTH-1:0] src_sample_ch2 = 12'd0;

    wire dst_sample_valid;
    wire [DATA_WIDTH-1:0] dst_sample_ch1;
    wire [DATA_WIDTH-1:0] dst_sample_ch2;
    wire [SEQUENCE_WIDTH-1:0] dst_sample_sequence;
    wire dst_sample_integrity_clean;
    wire fifo_underflow_attempt;

    wire [31:0] source_accept_count_gray;
    wire [31:0] backpressure_cycle_count_gray;
    wire [31:0] source_protocol_violation_count_gray;
    wire [31:0] source_drop_count_gray;
    wire [31:0] fifo_overflow_attempt_count_gray;
    wire [31:0] counter_saturation_event_count_gray;
    wire [SEQUENCE_WIDTH-1:0] last_source_sequence_gray;

    wire [31:0] synced_source_accept_count;
    wire [31:0] synced_backpressure_cycle_count;
    wire [31:0] synced_source_protocol_violation_count;
    wire [31:0] synced_source_drop_count;
    wire [31:0] synced_fifo_overflow_attempt_count;
    wire [31:0] synced_counter_saturation_event_count;
    wire [SEQUENCE_WIDTH-1:0] synced_last_source_sequence;

    wire destination_expected_delivery;
    wire destination_duplicate_delivery;
    wire destination_stale_first_delivery;
    wire destination_sequence_gap;
    wire destination_reorder_or_stale;
    wire [SEQUENCE_WIDTH-1:0] destination_sequence_delta;

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
    wire [SEQUENCE_WIDTH-1:0] obs_last_source_sequence;
    wire [SEQUENCE_WIDTH-1:0] obs_last_destination_sequence;
    wire [9:0] obs_sticky_status;
    wire [9:0] obs_status_w1c_clear;

    wire [31:0] policy_rdata;
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

    integer failures = 0;
    integer accepted_transactions = 0;
    integer guard;

    stage2g_adc_sample_cdc_bridge #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_ADDR_WIDTH(3),
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .COUNTER_WIDTH(32)
    ) u_bridge (
        .src_clk(src_clk),
        .src_rst_n(src_rst_n),
        .src_sample_valid(src_sample_valid),
        .src_sample_ready(src_sample_ready),
        .src_sample_ch1(src_sample_ch1),
        .src_sample_ch2(src_sample_ch2),
        .dst_clk(dst_clk),
        .dst_rst_n(dst_rst_n),
        .dst_ready(1'b1),
        .dst_sample_valid(dst_sample_valid),
        .dst_sample_ch1(dst_sample_ch1),
        .dst_sample_ch2(dst_sample_ch2),
        .dst_sample_sequence(dst_sample_sequence),
        .dst_sample_integrity_clean(dst_sample_integrity_clean),
        .fifo_underflow_attempt(fifo_underflow_attempt),
        .source_accept_count_gray(source_accept_count_gray),
        .backpressure_cycle_count_gray(backpressure_cycle_count_gray),
        .source_protocol_violation_count_gray(
            source_protocol_violation_count_gray),
        .source_drop_count_gray(source_drop_count_gray),
        .fifo_overflow_attempt_count_gray(
            fifo_overflow_attempt_count_gray),
        .counter_saturation_event_count_gray(
            counter_saturation_event_count_gray),
        .last_source_sequence_gray(last_source_sequence_gray)
    );

    source_observability_cdc #(
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .COUNTER_WIDTH(32)
    ) u_source_observability_cdc (
        .dst_clk(dst_clk),
        .dst_rst_n(dst_rst_n),
        .source_accept_count_gray(source_accept_count_gray),
        .backpressure_cycle_count_gray(backpressure_cycle_count_gray),
        .source_protocol_violation_count_gray(
            source_protocol_violation_count_gray),
        .source_drop_count_gray(source_drop_count_gray),
        .fifo_overflow_attempt_count_gray(
            fifo_overflow_attempt_count_gray),
        .counter_saturation_event_count_gray(
            counter_saturation_event_count_gray),
        .last_source_sequence_gray(last_source_sequence_gray),
        .source_accept_count(synced_source_accept_count),
        .backpressure_cycle_count(synced_backpressure_cycle_count),
        .source_protocol_violation_count(
            synced_source_protocol_violation_count),
        .source_drop_count(synced_source_drop_count),
        .fifo_overflow_attempt_count(
            synced_fifo_overflow_attempt_count),
        .counter_saturation_event_count(
            synced_counter_saturation_event_count),
        .last_source_sequence(synced_last_source_sequence)
    );

    transaction_destination_observer #(
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .COUNTER_WIDTH(32)
    ) u_observer (
        .clk(dst_clk),
        .rst_n(dst_rst_n),
        .delivery_valid(dst_sample_valid),
        .delivery_sequence(dst_sample_sequence),
        .fifo_underflow_attempt(fifo_underflow_attempt),
        .source_accept_count_in(synced_source_accept_count),
        .backpressure_cycle_count_in(synced_backpressure_cycle_count),
        .source_protocol_violation_count_in(
            synced_source_protocol_violation_count),
        .source_drop_count_in(synced_source_drop_count),
        .fifo_overflow_attempt_count_in(
            synced_fifo_overflow_attempt_count),
        .source_counter_saturation_count_in(
            synced_counter_saturation_event_count),
        .last_source_sequence_in(synced_last_source_sequence),
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
        .last_source_sequence(obs_last_source_sequence),
        .last_destination_sequence(obs_last_destination_sequence),
        .expected_delivery(destination_expected_delivery),
        .duplicate_delivery(destination_duplicate_delivery),
        .stale_first_delivery(destination_stale_first_delivery),
        .sequence_gap(destination_sequence_gap),
        .reorder_or_stale(destination_reorder_or_stale),
        .sequence_delta(destination_sequence_delta),
        .sticky_status(obs_sticky_status)
    );

    stage2g_protection_ip_reg_controlled #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(16),
        .ADDR_WIDTH(8),
        .REG_DATA_WIDTH(32),
        .HEALTH_CNT_WIDTH(8),
        .OBS_SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH)
    ) u_policy (
        .clk(dst_clk),
        .rst_n(dst_rst_n),
        .sample_valid(dst_sample_valid),
        .sample_sequence(dst_sample_sequence),
        .sample_source_integrity_clean(dst_sample_integrity_clean),
        .sample_destination_integrity_clean(
            destination_expected_delivery),
        .wr_en(1'b0),
        .rd_en(1'b0),
        .addr(8'd0),
        .wdata(32'd0),
        .wstrb(4'd0),
        .rdata(policy_rdata),
        .i_ch1(dst_sample_ch1),
        .i_ch2(dst_sample_ch2),
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

    task automatic fail;
        input [8*120-1:0] label;
        begin
            $display("B2 SOURCE FAILED: %0s", label);
            failures = failures + 1;
        end
    endtask

    task automatic check_bit;
        input [8*120-1:0] label;
        input actual;
        input expected;
        begin
            if (actual !== expected) begin
                $display("B2 SOURCE %0s actual=%b expected=%b",
                         label, actual, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic wait_dst_edges;
        input integer count;
        integer index;
        begin
            for (index = 0; index < count; index = index + 1)
                @(posedge dst_clk);
            #1;
        end
    endtask

    task automatic reset_path;
        begin
            src_sample_valid = 1'b0;
            src_rst_n = 1'b0;
            dst_rst_n = 1'b0;
            repeat (3) @(posedge src_clk);
            repeat (3) @(posedge dst_clk);
            #1;
            check_bit("reset source stall state",
                      u_bridge.u_source_observer.stall_pending, 1'b0);
            check_bit("reset source integrity",
                      u_bridge.u_source_observer.
                          transaction_integrity_clean, 1'b1);
            check_bit("reset policy safe", pwm_out, 1'b0);
            src_rst_n = 1'b1;
            dst_rst_n = 1'b1;
            repeat (5) @(posedge src_clk);
            repeat (5) @(posedge dst_clk);
            #1;
        end
    endtask

    task automatic send_accepted_offer;
        input integer stall_mode;
        input [DATA_WIDTH-1:0] initial_ch1;
        input [DATA_WIDTH-1:0] initial_ch2;
        input [DATA_WIDTH-1:0] accepted_ch1;
        input [DATA_WIDTH-1:0] accepted_ch2;
        input expected_clean;
        input expected_violation;
        input [8*80-1:0] label;
        reg [31:0] accept_before;
        reg [31:0] violation_before;
        reg [31:0] drop_before;
        reg [SEQUENCE_WIDTH-1:0] accepted_sequence;
        begin
            accept_before =
                u_bridge.u_source_observer.source_accept_count;
            violation_before =
                u_bridge.u_source_observer.
                    source_protocol_violation_count;
            drop_before = u_bridge.u_source_observer.source_drop_count;

            if (stall_mode != 0)
                force u_bridge.src_sample_ready = 1'b0;

            @(negedge src_clk);
            src_sample_ch1 = initial_ch1;
            src_sample_ch2 = initial_ch2;
            src_sample_valid = 1'b1;

            if (stall_mode != 0) begin
                @(posedge src_clk);
                #1;
                check_bit({label, " stall entered"},
                          u_bridge.u_source_observer.stall_pending, 1'b1);
                @(negedge src_clk);
                if (stall_mode == 2) begin
                    src_sample_ch1 = accepted_ch1;
                    src_sample_ch2 = accepted_ch2;
                end
                @(posedge src_clk);
                #1;
                if (stall_mode == 2)
                    check_bit({label, " violation recorded"},
                              u_bridge.u_source_observer.
                                  stall_violation_recorded, 1'b1);
                @(negedge src_clk);
                release u_bridge.src_sample_ready;
            end else begin
                src_sample_ch1 = accepted_ch1;
                src_sample_ch2 = accepted_ch2;
            end

            guard = 0;
            while (!src_sample_ready) begin
                @(negedge src_clk);
                guard = guard + 1;
                if (guard > 40) begin
                    fail({label, " source ready timeout"});
                    disable send_accepted_offer;
                end
            end
            #1;
            accepted_sequence = u_bridge.source_sequence;
            check_bit({label, " direct observer integrity"},
                      u_bridge.u_source_observer.
                          transaction_integrity_clean,
                      expected_clean);
            @(posedge src_clk);
            #1;
            if (u_bridge.u_source_observer.source_accept_count !==
                accept_before + 1)
                fail({label, " source accept diagnostic"});
            if (u_bridge.u_source_observer.
                    source_protocol_violation_count !==
                violation_before + expected_violation)
                fail({label, " source violation diagnostic"});
            if (u_bridge.u_source_observer.source_drop_count !==
                drop_before + expected_violation)
                fail({label, " source drop diagnostic"});
            @(negedge src_clk);
            src_sample_valid = 1'b0;

            guard = 0;
            while (!dst_sample_valid) begin
                @(negedge dst_clk);
                guard = guard + 1;
                if (guard > 80) begin
                    fail({label, " FIFO delivery timeout"});
                    disable send_accepted_offer;
                end
            end
            #1;
            if (dst_sample_sequence !== accepted_sequence)
                fail({label, " FIFO sequence sideband"});
            if (dst_sample_ch1 !== accepted_ch1 ||
                dst_sample_ch2 !== accepted_ch2)
                fail({label, " FIFO accepted payload"});
            check_bit({label, " FIFO integrity sideband"},
                      dst_sample_integrity_clean, expected_clean);
            check_bit({label, " destination expected"},
                      destination_expected_delivery, 1'b1);

            @(posedge dst_clk);
            #1;
            check_bit({label, " eval edge 0"}, fault_eval_valid, 1'b0);
            @(posedge dst_clk);
            #1;
            check_bit({label, " eval edge 1"}, fault_eval_valid, 1'b0);
            @(posedge dst_clk);
            #1;
            check_bit({label, " eval edge 2"}, fault_eval_valid, 1'b1);
            if (fault_eval_sequence !== accepted_sequence)
                fail({label, " policy sequence identity"});
            check_bit({label, " downstream policy integrity"},
                      fault_eval_integrity_clean, expected_clean);
            @(posedge dst_clk);
            #1;
            check_bit({label, " eval single-cycle"}, fault_eval_valid,
                      1'b0);
            accepted_transactions = accepted_transactions + 1;
        end
    endtask

    task automatic withdraw_stalled_offer;
        input [DATA_WIDTH-1:0] ch1_value;
        input [DATA_WIDTH-1:0] ch2_value;
        reg [31:0] accept_before;
        reg [31:0] violation_before;
        begin
            accept_before =
                u_bridge.u_source_observer.source_accept_count;
            violation_before =
                u_bridge.u_source_observer.
                    source_protocol_violation_count;
            force u_bridge.src_sample_ready = 1'b0;
            @(negedge src_clk);
            src_sample_ch1 = ch1_value;
            src_sample_ch2 = ch2_value;
            src_sample_valid = 1'b1;
            @(posedge src_clk);
            #1;
            check_bit("withdraw stall entered",
                      u_bridge.u_source_observer.stall_pending, 1'b1);
            @(negedge src_clk);
            src_sample_valid = 1'b0;
            #1;
            check_bit("withdraw current violation event",
                      u_bridge.u_source_observer.
                          source_protocol_violation_event, 1'b1);
            @(posedge src_clk);
            #1;
            release u_bridge.src_sample_ready;
            if (u_bridge.u_source_observer.source_accept_count !==
                accept_before)
                fail("withdrawal unexpectedly accepted a transaction");
            if (u_bridge.u_source_observer.
                    source_protocol_violation_count !==
                violation_before + 1)
                fail("withdrawal diagnostic violation count");
            check_bit("withdraw clears stall state",
                      u_bridge.u_source_observer.stall_pending, 1'b0);
            wait_dst_edges(8);
            check_bit("withdraw produces no FIFO transaction",
                      dst_sample_valid, 1'b0);
        end
    endtask

    task automatic reset_during_stall;
        begin
            force u_bridge.src_sample_ready = 1'b0;
            @(negedge src_clk);
            src_sample_ch1 = 12'd777;
            src_sample_ch2 = 12'd778;
            src_sample_valid = 1'b1;
            @(posedge src_clk);
            #1;
            check_bit("reset-during-stall entered",
                      u_bridge.u_source_observer.stall_pending, 1'b1);
            src_rst_n = 1'b0;
            dst_rst_n = 1'b0;
            #1;
            check_bit("reset-during-stall clears pending",
                      u_bridge.u_source_observer.stall_pending, 1'b0);
            check_bit("reset-during-stall clears violation",
                      u_bridge.u_source_observer.
                          stall_violation_recorded, 1'b0);
            check_bit("reset-during-stall restores clean result",
                      u_bridge.u_source_observer.
                          transaction_integrity_clean, 1'b1);
            src_sample_valid = 1'b0;
            release u_bridge.src_sample_ready;
            repeat (3) @(posedge src_clk);
            repeat (3) @(posedge dst_clk);
            src_rst_n = 1'b1;
            dst_rst_n = 1'b1;
            repeat (5) @(posedge src_clk);
            repeat (5) @(posedge dst_clk);
            #1;
        end
    endtask

    initial begin
        reset_path();

        send_accepted_offer(0, 12'd200, 12'd200, 12'd200, 12'd200,
                            1'b1, 1'b0, "immediate clean");
        if (fsm_state !== 4'd0)
            fail("immediate clean transaction did not arm policy");

        send_accepted_offer(1, 12'd210, 12'd211, 12'd210, 12'd211,
                            1'b1, 1'b0, "stable stalled");

        send_accepted_offer(2, 12'd3500, 12'd3500, 12'd220, 12'd221,
                            1'b0, 1'b1, "mutated stalled");
        wait_dst_edges(8);
        if (!obs_sticky_status[1] ||
            obs_source_protocol_violation_count == 0)
            fail("source diagnostic telemetry did not record mutation");

        // The diagnostic sticky/counter remains set, but the next accepted
        // clean offer must carry a clean FIFO bit and remain policy eligible.
        send_accepted_offer(0, 12'd230, 12'd231, 12'd230, 12'd231,
                            1'b1, 1'b0, "clean after mutation");
        if (!obs_sticky_status[1])
            fail("clean transaction unexpectedly cleared diagnostics");

        withdraw_stalled_offer(12'd240, 12'd241);
        wait_dst_edges(8);
        if (obs_source_protocol_violation_count < 2)
            fail("withdrawal did not reach destination diagnostics");
        send_accepted_offer(0, 12'd250, 12'd251, 12'd250, 12'd251,
                            1'b1, 1'b0, "clean after withdrawal");

        reset_during_stall();
        if (u_bridge.u_source_observer.
                source_protocol_violation_count !== 0 ||
            obs_sticky_status !== 10'd0)
            fail("reset during stall did not clear diagnostic state");
        send_accepted_offer(0, 12'd260, 12'd261, 12'd260, 12'd261,
                            1'b1, 1'b0, "clean after reset stall");
        if (fsm_state !== 4'd0)
            fail("clean post-reset transaction did not arm policy");

        if (failures != 0) begin
            $display("STAGE2H_B2_SOURCE_PROTOCOL=FAIL_%0d", failures);
            $fatal(1);
        end
        $display("SOURCE_PROTOCOL_BEHAVIOR=PASS");
        $display("SOURCE_DIAGNOSTIC_POLICY_INTEGRITY_AGREEMENT=PASS");
        $display("SOURCE_POLICY_RESULT_FROM_DIRECT_PROTOCOL_STATE=YES");
        $display("SOURCE_POLICY_RESULT_FROM_COUNTERS=NO");
        $display("SOURCE_POLICY_RESULT_FROM_STICKY_STATUS=NO");
        $display("SOURCE_ACCEPTED_TRANSACTIONS=%0d", accepted_transactions);
        $finish;
    end
endmodule
