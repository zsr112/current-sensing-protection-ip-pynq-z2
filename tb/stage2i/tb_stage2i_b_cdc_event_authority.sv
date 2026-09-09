`timescale 1ns/1ps
module tb_stage2i_b_cdc_event_authority;
    localparam DATA_WIDTH = 12;
    localparam SEQUENCE_WIDTH = 16;
    localparam FIFO_ADDR_WIDTH = 3;
    localparam MAX_SEQUENCE = (1 << SEQUENCE_WIDTH);

    reg src_clk = 1'b0;
    reg dst_clk = 1'b0;
    always #4 src_clk = ~src_clk;
    always #5 dst_clk = ~dst_clk;

    reg src_rst_n = 1'b0;
    reg dst_rst_n = 1'b0;
    reg src_sample_valid = 1'b0;
    wire src_sample_ready;
    reg [DATA_WIDTH-1:0] src_sample_ch1 = 0;
    reg [DATA_WIDTH-1:0] src_sample_ch2 = 0;
    reg dst_ready = 1'b1;
    wire dst_sample_valid;
    wire [DATA_WIDTH-1:0] dst_sample_ch1;
    wire [DATA_WIDTH-1:0] dst_sample_ch2;
    wire [SEQUENCE_WIDTH-1:0] dst_sample_sequence;
    wire dst_sample_integrity_clean;
    wire fifo_underflow_attempt;

    reg clear_fault = 1'b0;
    wire pwm_raw;
    wire pwm_out;
    wire oc_any;
    wire oc_both;
    wire mismatch_flag;
    wire sensor_open_flag;
    wire sensor_sat_flag;
    wire sensor_stuck_flag;
    wire fault_valid;
    wire fault_latched;
    wire [7:0] fault_code;
    wire [7:0] fault_code_latched;
    wire [3:0] fsm_state;
    wire [DATA_WIDTH-1:0] abs_diff;
    wire fault_eval_valid;
    wire [SEQUENCE_WIDTH-1:0] fault_eval_sequence;
    wire [5:0] fault_eval_bitmap;
    wire [7:0] fault_eval_code;
    wire fault_eval_integrity_clean;
    wire clear_pending;
    wire [7:0] first_fault_code;
    wire [5:0] first_fault_bitmap;
    wire [5:0] live_fault_bitmap;
    wire [5:0] fault_seen_bitmap;
    wire first_fault_event;
    wire clear_resolution_event;
    wire clear_accept_event;
    wire [SEQUENCE_WIDTH-1:0] clear_resolution_sequence;
    wire post_clear_recovery_pending;

    integer dst_cycle = 0;
    integer scenario_epoch = 0;
    integer source_accept_total = 0;
    integer prefetch_total = 0;
    integer delivery_total = 0;
    integer eval_available_total = 0;
    integer policy_consumption_total = 0;
    integer failures = 0;
    integer source_accept_cycle [0:MAX_SEQUENCE-1];
    integer source_accept_epoch [0:MAX_SEQUENCE-1];
    integer prefetch_cycle [0:MAX_SEQUENCE-1];
    integer prefetch_epoch [0:MAX_SEQUENCE-1];
    integer delivery_cycle [0:MAX_SEQUENCE-1];
    integer delivery_epoch [0:MAX_SEQUENCE-1];
    integer eval_available_cycle [0:MAX_SEQUENCE-1];
    integer eval_available_epoch [0:MAX_SEQUENCE-1];
    integer policy_cycle [0:MAX_SEQUENCE-1];
    integer policy_epoch [0:MAX_SEQUENCE-1];
    reg [DATA_WIDTH-1:0] delivered_ch1 [0:1023];
    reg [SEQUENCE_WIDTH-1:0] delivered_sequence [0:1023];

    reg monitor_prefetch;
    reg monitor_delivery;
    reg monitor_policy;
    reg [SEQUENCE_WIDTH-1:0] monitor_prefetch_sequence;
    reg [SEQUENCE_WIDTH-1:0] monitor_delivery_sequence;
    reg [SEQUENCE_WIDTH-1:0] monitor_policy_sequence;

    stage2g_adc_sample_cdc_bridge #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .COUNTER_WIDTH(32)
    ) dut_bridge (
        .src_clk(src_clk),
        .src_rst_n(src_rst_n),
        .src_sample_valid(src_sample_valid),
        .src_sample_ready(src_sample_ready),
        .src_sample_ch1(src_sample_ch1),
        .src_sample_ch2(src_sample_ch2),
        .dst_clk(dst_clk),
        .dst_rst_n(dst_rst_n),
        .dst_ready(dst_ready),
        .dst_sample_valid(dst_sample_valid),
        .dst_sample_ch1(dst_sample_ch1),
        .dst_sample_ch2(dst_sample_ch2),
        .dst_sample_sequence(dst_sample_sequence),
        .dst_sample_integrity_clean(dst_sample_integrity_clean),
        .fifo_underflow_attempt(fifo_underflow_attempt),
        .source_accept_count_gray(),
        .backpressure_cycle_count_gray(),
        .source_protocol_violation_count_gray(),
        .source_drop_count_gray(),
        .fifo_overflow_attempt_count_gray(),
        .counter_saturation_event_count_gray(),
        .last_source_sequence_gray()
    );

    stage2g_protection_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(16),
        .HEALTH_CNT_WIDTH(8),
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH)
    ) dut_core (
        .clk(dst_clk),
        .rst_n(dst_rst_n),
        .sample_valid(dst_sample_valid),
        .sample_sequence(dst_sample_sequence),
        .sample_source_integrity_clean(dst_sample_integrity_clean),
        .sample_destination_integrity_clean(1'b1),
        .pwm_enable(1'b1),
        .clear_fault(clear_fault),
        .i_ch1(dst_sample_ch1),
        .i_ch2(dst_sample_ch2),
        .th_oc_ch1(12'd1000),
        .th_oc_ch2(12'd1000),
        .th_diff(12'd4095),
        .th_open(12'd0),
        .th_sat(12'd4095),
        .th_stuck_delta(12'd0),
        .th_persist(8'hff),
        .period(16'd100),
        .duty(16'd50),
        .pwm_raw(pwm_raw),
        .pwm_out(pwm_out),
        .oc_any(oc_any),
        .oc_both(oc_both),
        .mismatch_flag(mismatch_flag),
        .sensor_open_flag(sensor_open_flag),
        .sensor_sat_flag(sensor_sat_flag),
        .sensor_stuck_flag(sensor_stuck_flag),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code(fault_code),
        .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state),
        .abs_diff(abs_diff),
        .fault_eval_valid(fault_eval_valid),
        .fault_eval_sequence(fault_eval_sequence),
        .fault_eval_bitmap(fault_eval_bitmap),
        .fault_eval_code(fault_eval_code),
        .fault_eval_integrity_clean(fault_eval_integrity_clean),
        .clear_pending(clear_pending),
        .first_fault_code(first_fault_code),
        .first_fault_bitmap(first_fault_bitmap),
        .live_fault_bitmap(live_fault_bitmap),
        .fault_seen_bitmap(fault_seen_bitmap),
        .first_fault_event(first_fault_event),
        .clear_resolution_event(clear_resolution_event),
        .clear_accept_event(clear_accept_event),
        .clear_resolution_sequence(clear_resolution_sequence),
        .post_clear_recovery_pending(post_clear_recovery_pending)
    );

    task automatic fail;
        input [8*160-1:0] message;
        begin
            failures = failures + 1;
            $display("CDC EVENT AUTHORITY FAILED: %0s", message);
            $fatal(1);
        end
    endtask

    task automatic check;
        input condition;
        input [8*160-1:0] message;
        begin
            if (condition !== 1'b1)
                fail(message);
        end
    endtask

    always @(posedge src_clk) begin : source_monitor
        integer sequence_value;
        if (src_rst_n && src_sample_valid && src_sample_ready) begin
            sequence_value = dut_bridge.u_source_observer.transaction_sequence;
            source_accept_cycle[sequence_value] = dst_cycle;
            source_accept_epoch[sequence_value] = scenario_epoch;
            source_accept_total = source_accept_total + 1;
            $display("TRACE epoch=%0d dst_cycle=%0d event=SOURCE_ACCEPT sequence=%0d",
                     scenario_epoch, dst_cycle, sequence_value);
        end
    end

    always @(posedge dst_clk) begin : destination_monitor
        dst_cycle = dst_cycle + 1;
        monitor_prefetch = dut_bridge.u_fifo.rd_fire;
        monitor_delivery = dst_sample_valid;
        monitor_policy = fault_eval_valid;
        monitor_prefetch_sequence =
            dut_bridge.fifo_read_data[2*DATA_WIDTH +: SEQUENCE_WIDTH];
        monitor_delivery_sequence = dst_sample_sequence;
        monitor_policy_sequence = fault_eval_sequence;

        if (!dst_rst_n && monitor_delivery)
            fail("destination delivery asserted while reset is active");

        if (monitor_prefetch) begin
            prefetch_cycle[monitor_prefetch_sequence] = dst_cycle;
            prefetch_epoch[monitor_prefetch_sequence] = scenario_epoch;
            prefetch_total = prefetch_total + 1;
            $display("TRACE epoch=%0d dst_cycle=%0d event=INTERNAL_FIFO_PREFETCH sequence=%0d source_accept_offset=%0d",
                     scenario_epoch, dst_cycle, monitor_prefetch_sequence,
                     dst_cycle - source_accept_cycle[monitor_prefetch_sequence]);
        end

        if (monitor_delivery) begin
            check(dut_core.sample_accept_event === 1'b1,
                  "Stage2B N0 did not equal destination delivery");
            check(prefetch_epoch[monitor_delivery_sequence] == scenario_epoch,
                  "delivery lacked a current-epoch prefetch");
            check(dst_cycle - prefetch_cycle[monitor_delivery_sequence] == 1,
                  "prefetch-to-delivery offset was not one ACLK");
            delivery_cycle[monitor_delivery_sequence] = dst_cycle;
            delivery_epoch[monitor_delivery_sequence] = scenario_epoch;
            delivered_sequence[delivery_total] = monitor_delivery_sequence;
            delivered_ch1[delivery_total] = dst_sample_ch1;
            delivery_total = delivery_total + 1;
            $display("TRACE epoch=%0d dst_cycle=%0d event=BRIDGE_DESTINATION_DELIVERY_STAGE2B_N0 sequence=%0d prefetch_offset=1",
                     scenario_epoch, dst_cycle, monitor_delivery_sequence);
        end

        if (monitor_policy) begin
            check(delivery_epoch[monitor_policy_sequence] == scenario_epoch,
                  "policy consumption lacked a current-epoch delivery");
            check(dst_cycle - delivery_cycle[monitor_policy_sequence] == 3,
                  "delivery-to-policy consumption offset was not three ACLK");
            policy_cycle[monitor_policy_sequence] = dst_cycle;
            policy_epoch[monitor_policy_sequence] = scenario_epoch;
            policy_consumption_total = policy_consumption_total + 1;
            $display("TRACE epoch=%0d dst_cycle=%0d event=POLICY_CONSUMPTION sequence=%0d delivery_offset=3 clear=%0d pending=%0d",
                     scenario_epoch, dst_cycle, monitor_policy_sequence,
                     clear_fault, clear_pending);
        end

        #1;
        if (monitor_delivery)
            check(dut_core.accepted_sample_valid === 1'b1,
                  "Stage2B accepted register did not capture delivery");

        if (fault_eval_valid) begin
            check(delivery_epoch[fault_eval_sequence] == scenario_epoch,
                  "fault evaluation lacked a current-epoch delivery");
            check(dst_cycle - delivery_cycle[fault_eval_sequence] == 2,
                  "delivery-to-fault-evaluation offset was not two ACLK");
            eval_available_cycle[fault_eval_sequence] = dst_cycle;
            eval_available_epoch[fault_eval_sequence] = scenario_epoch;
            eval_available_total = eval_available_total + 1;
            $display("TRACE epoch=%0d dst_cycle=%0d event=FAULT_EVAL_AVAILABLE sequence=%0d delivery_offset=2",
                     scenario_epoch, dst_cycle, fault_eval_sequence);
        end
    end

    task automatic reset_path;
        begin
            scenario_epoch = scenario_epoch + 1;
            @(negedge dst_clk);
            src_rst_n = 1'b0;
            dst_rst_n = 1'b0;
            src_sample_valid = 1'b0;
            dst_ready = 1'b1;
            clear_fault = 1'b0;
            repeat (3) @(posedge dst_clk);
            @(negedge dst_clk);
            src_rst_n = 1'b1;
            dst_rst_n = 1'b1;
            repeat (2) @(posedge dst_clk);
        end
    endtask

    task automatic send_word;
        input [DATA_WIDTH-1:0] ch1;
        input [DATA_WIDTH-1:0] ch2;
        integer guard;
        integer accepted;
        begin
            @(negedge src_clk);
            src_sample_ch1 = ch1;
            src_sample_ch2 = ch2;
            src_sample_valid = 1'b1;
            guard = 0;
            accepted = 0;
            while (!accepted) begin
                @(posedge src_clk);
                guard = guard + 1;
                if (src_sample_ready)
                    accepted = 1;
                if (guard > 200)
                    fail("source acceptance timeout");
            end
            @(negedge src_clk);
            src_sample_valid = 1'b0;
        end
    endtask

    task automatic send_continuous;
        input integer count;
        input integer base_value;
        integer accepted;
        integer guard;
        begin
            accepted = 0;
            guard = 0;
            @(negedge src_clk);
            src_sample_ch1 = base_value;
            src_sample_ch2 = base_value;
            src_sample_valid = 1'b1;
            while (accepted < count) begin
                @(posedge src_clk);
                guard = guard + 1;
                if (src_sample_ready) begin
                    accepted = accepted + 1;
                    @(negedge src_clk);
                    if (accepted < count) begin
                        src_sample_ch1 = base_value + accepted;
                        src_sample_ch2 = base_value + accepted;
                    end else begin
                        src_sample_valid = 1'b0;
                    end
                end
                if (guard > 1000)
                    fail("continuous source timeout");
            end
        end
    endtask

    task automatic wait_for_delivery;
        input [SEQUENCE_WIDTH-1:0] sequence_value;
        integer guard;
        begin
            guard = 0;
            while (delivery_epoch[sequence_value] !== scenario_epoch) begin
                @(posedge dst_clk);
                #2;
                guard = guard + 1;
                if (guard > 300)
                    fail("destination delivery timeout");
            end
        end
    endtask

    task automatic wait_for_prefetch;
        input [SEQUENCE_WIDTH-1:0] sequence_value;
        integer guard;
        begin
            guard = 0;
            while (prefetch_epoch[sequence_value] !== scenario_epoch) begin
                @(posedge dst_clk);
                #2;
                guard = guard + 1;
                if (guard > 300)
                    fail("FIFO prefetch timeout");
            end
        end
    endtask

    task automatic wait_for_eval_available;
        input [SEQUENCE_WIDTH-1:0] sequence_value;
        integer guard;
        begin
            guard = 0;
            while (eval_available_epoch[sequence_value] !== scenario_epoch) begin
                @(posedge dst_clk);
                #2;
                guard = guard + 1;
                if (guard > 300)
                    fail("fault evaluation timeout");
            end
        end
    endtask

    task automatic wait_for_policy;
        input [SEQUENCE_WIDTH-1:0] sequence_value;
        integer guard;
        begin
            guard = 0;
            while (policy_epoch[sequence_value] !== scenario_epoch) begin
                @(posedge dst_clk);
                #2;
                guard = guard + 1;
                if (guard > 300)
                    fail("policy consumption timeout");
            end
        end
    endtask

    task automatic wait_for_state;
        input [3:0] expected_state;
        integer guard;
        begin
            guard = 0;
            while (fsm_state !== expected_state) begin
                @(posedge dst_clk);
                #1;
                guard = guard + 1;
                if (guard > 300)
                    fail("policy state timeout");
            end
        end
    endtask

    task automatic prepare_latched;
        begin
            reset_path();
            send_word(12'd100, 12'd100);
            wait_for_policy(16'd0);
            wait_for_state(4'd0);
            send_word(12'd1500, 12'd1500);
            wait_for_policy(16'd1);
            wait_for_state(4'd1);
        end
    endtask

    task automatic wait_for_clear_accept;
        input [SEQUENCE_WIDTH-1:0] expected_sequence;
        integer guard;
        begin
            guard = 0;
            while (!clear_accept_event) begin
                @(posedge dst_clk);
                #1;
                guard = guard + 1;
                if (guard > 300)
                    fail("clear acceptance timeout");
            end
            check(clear_resolution_sequence == expected_sequence,
                  "clear resolved with the wrong evaluation sequence");
        end
    endtask

    integer base_delivery;
    integer index;
    integer accepted_before_full;

    initial begin
        // Single/empty-to-nonempty transaction and exact event offsets.
        reset_path();
        send_word(12'd100, 12'd100);
        wait_for_policy(16'd0);
        check(prefetch_cycle[0] + 1 == delivery_cycle[0],
              "single prefetch/delivery offset");
        check(delivery_cycle[0] + 2 == eval_available_cycle[0],
              "single delivery/evaluation offset");
        check(delivery_cycle[0] + 3 == policy_cycle[0],
              "single delivery/policy offset");
        $display("SINGLE_TRANSACTION_CYCLE_TRACE=PASS");
        $display("FIFO_EMPTY_TO_NONEMPTY=PASS");

        // Continuous source traffic proves back-to-back delivery and II=1.
        reset_path();
        send_continuous(12, 200);
        wait_for_policy(16'd11);
        for (index = 1; index < 12; index = index + 1) begin
            check(delivery_cycle[index] == delivery_cycle[index-1] + 1,
                  "continuous destination delivery was not one per ACLK");
            check(policy_cycle[index] == policy_cycle[index-1] + 1,
                  "continuous policy consumption was not II=1");
        end
        $display("BACK_TO_BACK_TRANSACTIONS=PASS");
        $display("CONTINUOUS_TRAFFIC=PASS");
        $display("PIPELINE_INITIATION_INTERVAL=1");

        // Destination pause/resume: no prefetch or delivery until ready.
        reset_path();
        @(negedge dst_clk);
        dst_ready = 1'b0;
        base_delivery = delivery_total;
        send_continuous(3, 300);
        repeat (6) @(posedge dst_clk);
        check(delivery_total == base_delivery,
              "destination pause allowed a delivery");
        check(prefetch_epoch[0] !== scenario_epoch,
              "destination pause allowed a prefetch");
        @(negedge dst_clk);
        dst_ready = 1'b1;
        wait_for_policy(16'd2);
        check(delivery_cycle[1] == delivery_cycle[0] + 1 &&
              delivery_cycle[2] == delivery_cycle[1] + 1,
              "destination resume did not restore one delivery per ACLK");
        $display("DESTINATION_PAUSE_RESUME=PASS");

        // Full/resume: the ninth offer stalls until destination progress.
        reset_path();
        @(negedge dst_clk);
        dst_ready = 1'b0;
        accepted_before_full = source_accept_total;
        fork
            send_continuous(9, 400);
            begin
                wait (source_accept_total == accepted_before_full + 8);
                repeat (5) @(posedge src_clk);
                check(src_sample_ready === 1'b0,
                      "full FIFO did not apply source backpressure");
                @(negedge dst_clk);
                dst_ready = 1'b1;
            end
        join
        wait_for_policy(16'd8);
        $display("FIFO_FULL_TO_RESUME=PASS");

        // Sequence wrap remains exact across prefetch and delivery.
        reset_path();
        @(negedge src_clk);
        dut_bridge.u_source_observer.source_sequence = 16'hfffe;
        send_continuous(3, 500);
        wait_for_policy(16'h0000);
        check(delivery_epoch[16'hfffe] == scenario_epoch &&
              delivery_epoch[16'hffff] == scenario_epoch &&
              delivery_epoch[16'h0000] == scenario_epoch,
              "sequence wrap delivery set incomplete");
        $display("SEQUENCE_WRAP=PASS_FFFE_FFFF_0000");

        // Reset after prefetch but before delivery flushes the elastic word.
        reset_path();
        send_word(12'h155, 12'h155);
        wait_for_prefetch(16'd0);
        base_delivery = delivery_total;
        @(negedge dst_clk);
        src_rst_n = 1'b0;
        dst_rst_n = 1'b0;
        scenario_epoch = scenario_epoch + 1;
        repeat (3) @(posedge dst_clk);
        check(delivery_total == base_delivery,
              "prefetched word delivered after reset assertion");
        @(negedge dst_clk);
        src_rst_n = 1'b1;
        dst_rst_n = 1'b1;
        repeat (4) @(posedge dst_clk);
        check(delivery_total == base_delivery,
              "stale prefetched word replayed after reset release");
        send_word(12'h2aa, 12'h2aa);
        wait_for_delivery(16'd0);
        check(delivered_ch1[delivery_total-1] == 12'h2aa,
              "first post-reset payload was not the fresh transaction");
        repeat (5) @(posedge dst_clk);
        check(delivery_total == base_delivery + 1,
              "first post-reset transaction was not delivered exactly once");
        $display("NO_GHOST_DESTINATION_DELIVERY_AFTER_RESET=PASS");
        $display("NO_STALE_PREFETCH_REPLAY_AFTER_RESET=PASS");
        $display("FIRST_POST_RESET_TRANSACTION_EXACTLY_ONCE=PASS");

        // Prefetch before clear, with delivery on the same edge as clear.
        prepare_latched();
        send_word(12'd100, 12'd100);
        wait_for_prefetch(16'd2);
        @(negedge dst_clk);
        clear_fault = 1'b1;
        @(posedge dst_clk);
        #1;
        check(delivery_epoch[16'd2] == scenario_epoch,
              "delivery did not coincide with clear request");
        @(negedge dst_clk);
        clear_fault = 1'b0;
        wait_for_clear_accept(16'd2);
        $display("PREFETCH_BEFORE_CLEAR_DELIVERY_SAME_CLEAR_EDGE=PASS");
        $display("DELIVERY_SAME_CLEAR_EDGE=PASS");

        // Clear request on prefetch edge, then delivery strictly afterward.
        prepare_latched();
        @(negedge dst_clk);
        dst_ready = 1'b0;
        send_word(12'd100, 12'd100);
        wait (dut_bridge.fifo_empty === 1'b0);
        @(negedge dst_clk);
        clear_fault = 1'b1;
        dst_ready = 1'b1;
        @(posedge dst_clk);
        #1;
        check(prefetch_epoch[16'd2] == scenario_epoch,
              "clear edge did not coincide with prefetch");
        check(delivery_epoch[16'd2] !== scenario_epoch,
              "delivery was not strictly after clear/prefetch edge");
        @(negedge dst_clk);
        clear_fault = 1'b0;
        wait_for_clear_accept(16'd2);
        $display("PREFETCH_BEFORE_CLEAR_DELIVERY_AFTER_CLEAR=PASS");

        // Delivery before clear; evaluation retires strictly after request.
        prepare_latched();
        send_word(12'd100, 12'd100);
        wait_for_delivery(16'd2);
        @(negedge dst_clk);
        clear_fault = 1'b1;
        @(posedge dst_clk);
        #1;
        check(clear_pending === 1'b1,
              "clear request after delivery did not become pending");
        @(negedge dst_clk);
        clear_fault = 1'b0;
        wait_for_clear_accept(16'd2);
        $display("DELIVERY_BEFORE_CLEAR=PASS");
        $display("EVALUATION_RETIREMENT_STRICTLY_AFTER_CLEAR=PASS");

        // A retirement on the same edge as a new clear request cannot resolve
        // that request; the next post-request retirement must resolve it.
        prepare_latched();
        send_word(12'd100, 12'd100);
        wait_for_eval_available(16'd2);
        @(negedge dst_clk);
        clear_fault = 1'b1;
        @(posedge dst_clk);
        #1;
        check(clear_accept_event === 1'b0,
              "same-edge pre-request retirement resolved clear");
        check(clear_pending === 1'b1,
              "same-edge clear request was not retained pending");
        @(negedge dst_clk);
        clear_fault = 1'b0;
        send_word(12'd100, 12'd100);
        wait_for_clear_accept(16'd3);
        $display("EVALUATION_RETIREMENT_SAME_CLEAR_EDGE=PASS");
        $display("PRE_REQUEST_RETIREMENT_RESOLVES_CLEAR=NO");
        $display("CLEAR_FENCE_ORDER=EVALUATION_RETIREMENT");

        $display("INTERNAL_FIFO_PREFETCH_EVENT=IMPLEMENTATION_DETAIL_NOT_POLICY_AUTHORITY");
        $display("ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT=DST_SAMPLE_VALID_ACCEPTED_EDGE");
        $display("STAGE2B_N0=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT");
        $display("STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT");
        $display("STAGE2G_DELIVERY_TO_POLICY_LATENCY_ACLK=3");
        $display("CDC_EVENT_AUTHORITY_CHARACTERIZATION=PASS");
        $display("SOURCE_ACCEPT_TOTAL=%0d", source_accept_total);
        $display("INTERNAL_PREFETCH_TOTAL=%0d", prefetch_total);
        $display("DESTINATION_DELIVERY_TOTAL=%0d", delivery_total);
        $display("FAULT_EVAL_AVAILABLE_TOTAL=%0d", eval_available_total);
        $display("POLICY_CONSUMPTION_TOTAL=%0d", policy_consumption_total);
        $finish;
    end
endmodule

