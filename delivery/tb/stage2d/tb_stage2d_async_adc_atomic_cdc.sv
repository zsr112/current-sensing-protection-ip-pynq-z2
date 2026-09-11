`timescale 1ns/1ps
`include "fault_defs.vh"

module tb_stage2d_async_adc_atomic_cdc;
    localparam DATA_WIDTH = 12;
    localparam FIFO_ADDR_WIDTH = 3;
    localparam FIFO_DEPTH = (1 << FIFO_ADDR_WIDTH);
    localparam MAX_EVENTS = 65536;
    localparam [DATA_WIDTH-1:0] PAIR_XOR = 12'h5A5;

    reg src_clk = 1'b0;
    reg dst_clk = 1'b0;
    integer src_half_period = 7;
    integer dst_half_period = 5;

    reg async_rst_n = 1'b0;
    wire src_rst_n;
    wire dst_rst_n;

    reg src_sample_valid = 1'b0;
    wire src_sample_ready;
    reg [DATA_WIDTH-1:0] src_sample_ch1 = {DATA_WIDTH{1'b0}};
    reg [DATA_WIDTH-1:0] src_sample_ch2 = PAIR_XOR;

    reg dst_ready = 1'b1;
    wire dst_sample_valid;
    wire [DATA_WIDTH-1:0] dst_sample_ch1;
    wire [DATA_WIDTH-1:0] dst_sample_ch2;

    reg pwm_enable = 1'b0;
    reg clear_fault = 1'b0;
    reg [DATA_WIDTH-1:0] th_oc_ch1 = {DATA_WIDTH{1'b1}};
    reg [DATA_WIDTH-1:0] th_oc_ch2 = {DATA_WIDTH{1'b1}};
    reg [DATA_WIDTH-1:0] th_diff = {DATA_WIDTH{1'b1}};
    reg [DATA_WIDTH-1:0] th_open = {DATA_WIDTH{1'b0}};
    reg [DATA_WIDTH-1:0] th_sat = {DATA_WIDTH{1'b1}};
    reg [DATA_WIDTH-1:0] th_stuck_delta = {DATA_WIDTH{1'b0}};
    reg [7:0] th_persist = 8'd1;

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

    reg [(2*DATA_WIDTH)-1:0] expected_payload [0:MAX_EVENTS-1];
    integer expected_epoch [0:MAX_EVENTS-1];
    integer expected_dst_cycle_at_accept [0:MAX_EVENTS-1];
    reg expected_measure_latency [0:MAX_EVENTS-1];
    time expected_accept_time [0:MAX_EVENTS-1];
    integer scoreboard_write_index = 0;
    integer scoreboard_read_index = 0;
    integer scoreboard_epoch = 0;
    integer accepted_total = 0;
    integer delivered_total = 0;
    integer reset_discarded_total = 0;
    integer destination_cycle = 0;
    integer cdc_latency_min_cycles = 32'h7fffffff;
    integer cdc_latency_max_cycles = 0;
    time cdc_latency_min_ns = 64'h7fffffffffffffff;
    time cdc_latency_max_ns = 0;
    integer random_stress_accepted_start;
    integer random_stress_transactions = 0;
    integer scenario_count = 0;
    integer error_count = 0;
    reg measure_cdc_latency = 1'b0;

    always begin
        #(src_half_period) src_clk = ~src_clk;
    end

    always begin
        #(dst_half_period) dst_clk = ~dst_clk;
    end

    reset_release_sync u_src_reset_release (
        .clk(src_clk),
        .async_rst_n(async_rst_n),
        .sync_rst_n(src_rst_n)
    );

    reset_release_sync u_dst_reset_release (
        .clk(dst_clk),
        .async_rst_n(async_rst_n),
        .sync_rst_n(dst_rst_n)
    );

    adc_sample_cdc_bridge #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH)
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
        .dst_sample_ch2(dst_sample_ch2)
    );

    protection_core_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(16),
        .HEALTH_CNT_WIDTH(8)
    ) dut_core (
        .clk(dst_clk),
        .rst_n(dst_rst_n),
        .sample_valid(dst_sample_valid),
        .pwm_enable(pwm_enable),
        .clear_fault(clear_fault),
        .i_ch1(dst_sample_ch1),
        .i_ch2(dst_sample_ch2),
        .th_oc_ch1(th_oc_ch1),
        .th_oc_ch2(th_oc_ch2),
        .th_diff(th_diff),
        .th_open(th_open),
        .th_sat(th_sat),
        .th_stuck_delta(th_stuck_delta),
        .th_persist(th_persist),
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
        .abs_diff(abs_diff)
    );

    task automatic fail;
        input [8*160-1:0] message;
        begin
            error_count = error_count + 1;
            $display("STAGE2D CHECK FAILED: %0s", message);
            $fatal(1);
            $finish;
        end
    endtask

    task automatic check_true;
        input [8*160-1:0] label;
        input condition;
        begin
            if (condition !== 1'b1)
                fail(label);
        end
    endtask

    task automatic scenario_pass;
        input [8*8-1:0] scenario_id;
        begin
            scenario_count = scenario_count + 1;
            $display("%0s=PASS", scenario_id);
        end
    endtask

    task automatic drive_dst_ready;
        input ready_value;
        begin
            @(negedge dst_clk);
            dst_ready = ready_value;
        end
    endtask

    function automatic [DATA_WIDTH-1:0] paired_channel;
        input [DATA_WIDTH-1:0] channel_1;
        begin
            paired_channel = channel_1 ^ PAIR_XOR;
        end
    endfunction

    always @(posedge src_clk) begin
        if (src_rst_n && src_sample_valid && src_sample_ready) begin
            if (scoreboard_write_index >= MAX_EVENTS)
                fail("scoreboard source capacity exceeded");
            if (src_sample_ch2 !== paired_channel(src_sample_ch1))
                fail("source payload violates channel transform");
            expected_payload[scoreboard_write_index] = {
                src_sample_ch1, src_sample_ch2
            };
            expected_epoch[scoreboard_write_index] = scoreboard_epoch;
            expected_dst_cycle_at_accept[scoreboard_write_index] =
                destination_cycle;
            expected_measure_latency[scoreboard_write_index] =
                measure_cdc_latency;
            expected_accept_time[scoreboard_write_index] = $time;
            scoreboard_write_index = scoreboard_write_index + 1;
            accepted_total = accepted_total + 1;
        end
        if (!src_rst_n && src_sample_ready)
            fail("source ready asserted during local reset");
        if (dut_bridge.u_fifo.wr_fire && dut_bridge.u_fifo.wr_full)
            fail("write occurred while FIFO full");
    end

    always @(posedge dst_clk) begin : destination_monitor
        integer latency_cycles;
        time latency_ns;
        reg [(2*DATA_WIDTH)-1:0] delivered_payload;
        destination_cycle = destination_cycle + 1;
        if (!dst_rst_n && dst_sample_valid)
            fail("destination delivery asserted during local reset");
        if (dut_bridge.u_fifo.rd_fire && dut_bridge.u_fifo.rd_empty)
            fail("read occurred while FIFO empty");
        if (dst_sample_valid) begin
            delivered_payload = {dst_sample_ch1, dst_sample_ch2};
            if (!dst_ready)
                fail("destination pulse asserted without readiness");
            if (scoreboard_read_index >= scoreboard_write_index)
                fail("phantom or duplicate destination delivery");
            if (delivered_payload !==
                expected_payload[scoreboard_read_index])
                fail("destination payload mismatch, tearing, or reorder");
            if (dst_sample_ch2 !== paired_channel(dst_sample_ch1))
                fail("destination channel transform detects tearing");
            if (expected_epoch[scoreboard_read_index] != scoreboard_epoch)
                fail("stale payload replayed from a reset epoch");
            latency_cycles = destination_cycle -
                expected_dst_cycle_at_accept[scoreboard_read_index];
            latency_ns = $time - expected_accept_time[scoreboard_read_index];
            if (expected_measure_latency[scoreboard_read_index]) begin
                if (latency_cycles < cdc_latency_min_cycles)
                    cdc_latency_min_cycles = latency_cycles;
                if (latency_cycles > cdc_latency_max_cycles)
                    cdc_latency_max_cycles = latency_cycles;
                if (latency_ns < cdc_latency_min_ns)
                    cdc_latency_min_ns = latency_ns;
                if (latency_ns > cdc_latency_max_ns)
                    cdc_latency_max_ns = latency_ns;
            end
            scoreboard_read_index = scoreboard_read_index + 1;
            delivered_total = delivered_total + 1;
            #1;
            if (dut_core.accepted_sample_valid !== 1'b1)
                fail("Stage 2B accepted valid did not follow destination delivery");
            if (dut_core.accepted_sample_pair !==
                delivered_payload)
                fail("Stage 2B accepted pair differs from delivered word");
        end
    end

    always @(negedge async_rst_n) begin
        reset_discarded_total = reset_discarded_total +
            (scoreboard_write_index - scoreboard_read_index);
        scoreboard_read_index = scoreboard_write_index;
        scoreboard_epoch = scoreboard_epoch + 1;
    end

    task automatic set_default_thresholds;
        begin
            th_oc_ch1 = {DATA_WIDTH{1'b1}};
            th_oc_ch2 = {DATA_WIDTH{1'b1}};
            th_diff = {DATA_WIDTH{1'b1}};
            th_open = {DATA_WIDTH{1'b0}};
            th_sat = {DATA_WIDTH{1'b1}};
            th_stuck_delta = {DATA_WIDTH{1'b0}};
            th_persist = 8'd1;
        end
    endtask

    task automatic assert_async_reset;
        input integer low_time_ns;
        begin
            src_sample_valid = 1'b0;
            clear_fault = 1'b0;
            if (async_rst_n === 1'b1) begin
                @(negedge dst_clk);
                #1 async_rst_n = 1'b0;
            end else begin
                async_rst_n = 1'b0;
            end
            #(low_time_ns);
            check_true("source local reset asynchronously asserted",
                       src_rst_n === 1'b0);
            check_true("destination local reset asynchronously asserted",
                       dst_rst_n === 1'b0);
            check_true("FIFO full clears on reset",
                       dut_bridge.u_fifo.wr_full === 1'b0);
            check_true("FIFO empty after reset",
                       dut_bridge.u_fifo.rd_empty === 1'b1);
        end
    endtask

    task automatic release_reset_wait_both;
        begin
            async_rst_n = 1'b1;
            wait (src_rst_n === 1'b1);
            wait (dst_rst_n === 1'b1);
            @(negedge dst_clk);
        end
    endtask

    task automatic reset_and_release;
        begin
            assert_async_reset(3);
            release_reset_wait_both();
        end
    endtask

    task automatic send_one;
        input [DATA_WIDTH-1:0] channel_1;
        begin
            wait (src_rst_n === 1'b1);
            @(negedge src_clk);
            src_sample_ch1 = channel_1;
            src_sample_ch2 = paired_channel(channel_1);
            src_sample_valid = 1'b1;
            @(posedge src_clk);
            while (src_sample_ready !== 1'b1)
                @(posedge src_clk);
            @(negedge src_clk);
            src_sample_valid = 1'b0;
        end
    endtask

    task automatic send_stream;
        input integer count;
        input integer first_value;
        integer index;
        begin
            wait (src_rst_n === 1'b1);
            @(negedge src_clk);
            src_sample_valid = 1'b1;
            for (index = 0; index < count; index = index + 1) begin
                src_sample_ch1 = (first_value + index) &
                                 ((1 << DATA_WIDTH) - 1);
                src_sample_ch2 = paired_channel(src_sample_ch1);
                @(posedge src_clk);
                while (src_sample_ready !== 1'b1)
                    @(posedge src_clk);
                @(negedge src_clk);
            end
            src_sample_valid = 1'b0;
        end
    endtask

    task automatic wait_scoreboard_empty;
        integer guard;
        begin
            guard = 0;
            while ((scoreboard_read_index != scoreboard_write_index) ||
                   dut_core.accepted_sample_valid ||
                   dut_core.sample_decision_valid || fault_valid) begin
                @(posedge dst_clk);
                #1;
                guard = guard + 1;
                if (guard > 20000)
                    fail("scoreboard drain timeout");
            end
        end
    endtask

    task automatic wait_for_delivery_after;
        input integer previous_delivered;
        integer guard;
        begin
            guard = 0;
            while (delivered_total <= previous_delivered) begin
                @(posedge dst_clk);
                guard = guard + 1;
                if (guard > 2000)
                    fail("destination delivery timeout");
            end
        end
    endtask

    task automatic expect_no_delivery_cycles;
        input integer cycles;
        integer initial_delivered;
        integer index;
        begin
            initial_delivered = delivered_total;
            for (index = 0; index < cycles; index = index + 1)
                @(posedge dst_clk);
            check_true("unexpected destination transaction",
                       delivered_total == initial_delivered);
        end
    endtask

    task automatic expect_fault_latency_three;
        input [DATA_WIDTH-1:0] channel_1;
        input [7:0] expected_code;
        begin
            send_one(channel_1);
            wait (dst_sample_valid === 1'b1);
            @(posedge dst_clk); #1;
            check_true("fault not latched at N0", !fault_latched);
            @(posedge dst_clk); #1;
            check_true("fault not latched at N1", !fault_latched);
            @(posedge dst_clk); #1;
            check_true("fault not latched at N2", !fault_latched);
            @(posedge dst_clk); #1;
            check_true("fault latched at Stage 2B N3", fault_latched);
            check_true("fault code at Stage 2B N3",
                       fault_code_latched == expected_code);
        end
    endtask

    task automatic prepare_frequency_case;
        input integer new_src_half;
        input integer new_dst_half;
        begin
            src_half_period = new_src_half;
            dst_half_period = new_dst_half;
            reset_and_release();
            set_default_thresholds();
            drive_dst_ready(1'b1);
        end
    endtask

    integer before_accepted;
    integer before_delivered;
    integer index;
    integer reset_iteration;
    integer stress_batch;
    integer stress_value;

    initial begin
        begin : waveform_output
            string wave_dir;
            if (!$value$plusargs("CSIP_WAVE_DIR=%s", wave_dir)) wave_dir = ".";
            $dumpfile({wave_dir, "/stage2d_async_adc_atomic_cdc.vcd"});
        end
        $dumpvars(0, tb_stage2d_async_adc_atomic_cdc);
        set_default_thresholds();
        #2;
        release_reset_wait_both();

        // SC01: source slower than destination.
        prepare_frequency_case(11, 3);
        send_stream(12, 12'h040);
        wait_scoreboard_empty();
        scenario_pass("SC01");

        // SC02: source faster than destination, exercising ready/backpressure.
        prepare_frequency_case(2, 9);
        send_stream(48, 12'h100);
        wait_scoreboard_empty();
        scenario_pass("SC02");

        // SC03: non-integer clock ratio.
        prepare_frequency_case(4, 7);
        send_stream(24, 12'h180);
        wait_scoreboard_empty();
        scenario_pass("SC03");

        // SC04: four launch phase offsets against an unchanged destination.
        prepare_frequency_case(5, 8);
        measure_cdc_latency = 1'b1;
        for (index = 1; index <= 4; index = index + 1) begin
            #(index);
            send_one(12'h200 + index);
            wait_scoreboard_empty();
        end
        measure_cdc_latency = 1'b0;
        scenario_pass("SC04");

        // SC05: same nominal frequency with an asynchronous launch phase.
        prepare_frequency_case(5, 5);
        #3;
        send_stream(16, 12'h240);
        wait_scoreboard_empty();
        scenario_pass("SC05");

        // SC06: one transaction exactly once.
        before_accepted = accepted_total;
        before_delivered = delivered_total;
        send_one(12'h2A0);
        wait_scoreboard_empty();
        check_true("single source acceptance", accepted_total == before_accepted + 1);
        check_true("single destination delivery", delivered_total == before_delivered + 1);
        scenario_pass("SC06");

        // SC07: back-to-back source transactions.
        send_stream(20, 12'h2C0);
        wait_scoreboard_empty();
        scenario_pass("SC07");

        // SC08: held-high valid means one transaction per ready edge.
        before_accepted = accepted_total;
        send_stream(32, 12'h300);
        wait_scoreboard_empty();
        check_true("held-high valid acceptance count",
                   accepted_total == before_accepted + 32);
        scenario_pass("SC08");

        // SC09: maximum contract rate with valid continuously asserted.
        prepare_frequency_case(2, 3);
        before_accepted = accepted_total;
        send_stream(256, 12'h380);
        wait_scoreboard_empty();
        check_true("maximum sustained stream preserved",
                   accepted_total == before_accepted + 256);
        scenario_pass("SC09");

        // SC10: repeated FIFO wrap-around.
        send_stream(5 * FIFO_DEPTH + 3, 12'h500);
        wait_scoreboard_empty();
        scenario_pass("SC10");

        // SC11: strong channel transform on many pair values.
        send_stream(128, 12'h600);
        wait_scoreboard_empty();
        scenario_pass("SC11");

        // SC12: payload changes on every accepted source cycle.
        prepare_frequency_case(3, 4);
        send_stream(96, 12'h700);
        wait_scoreboard_empty();
        scenario_pass("SC12");

        // SC13: destination pause holds all accepted data for ordered resume.
        drive_dst_ready(1'b0);
        fork
            send_stream(FIFO_DEPTH, 12'h800);
        join
        expect_no_delivery_cycles(8);
        drive_dst_ready(1'b1);
        wait_scoreboard_empty();
        scenario_pass("SC13");

        // SC14: full blocks the ninth word and never overwrites.
        reset_and_release();
        drive_dst_ready(1'b0);
        before_accepted = accepted_total;
        send_stream(FIFO_DEPTH, 12'h880);
        @(negedge src_clk);
        check_true("FIFO full deasserts source ready", src_sample_ready === 1'b0);
        src_sample_ch1 = 12'h8F0;
        src_sample_ch2 = paired_channel(src_sample_ch1);
        src_sample_valid = 1'b1;
        repeat (4) @(posedge src_clk);
        check_true("full FIFO accepts no overwrite",
                   accepted_total == before_accepted + FIFO_DEPTH);
        drive_dst_ready(1'b1);
        wait (src_sample_ready === 1'b1);
        @(posedge src_clk);
        @(negedge src_clk);
        src_sample_valid = 1'b0;
        wait_scoreboard_empty();
        check_true("blocked word accepted after space",
                   accepted_total == before_accepted + FIFO_DEPTH + 1);
        scenario_pass("SC14");

        // SC15: source local reset releases first and may queue safely.
        src_half_period = 2;
        dst_half_period = 13;
        assert_async_reset(3);
        async_rst_n = 1'b1;
        wait (src_rst_n === 1'b1);
        check_true("source release precedes destination", dst_rst_n === 1'b0);
        before_delivered = delivered_total;
        send_one(12'h910);
        wait (dst_rst_n === 1'b1);
        wait_for_delivery_after(before_delivered);
        wait_scoreboard_empty();
        scenario_pass("SC15");

        // SC16: destination local reset releases first and remains empty.
        src_half_period = 13;
        dst_half_period = 2;
        assert_async_reset(3);
        async_rst_n = 1'b1;
        wait (dst_rst_n === 1'b1);
        check_true("destination release precedes source", src_rst_n === 1'b0);
        expect_no_delivery_cycles(4);
        wait (src_rst_n === 1'b1);
        send_one(12'h920);
        wait_scoreboard_empty();
        scenario_pass("SC16");

        // SC17: near-simultaneous release at unrelated phases.
        prepare_frequency_case(5, 6);
        #1;
        send_one(12'h930);
        wait_scoreboard_empty();
        scenario_pass("SC17");

        // SC18: asynchronous reset during active crossing cancels the epoch.
        prepare_frequency_case(2, 11);
        drive_dst_ready(1'b0);
        send_stream(6, 12'h940);
        before_delivered = delivered_total;
        #3;
        assert_async_reset(2);
        release_reset_wait_both();
        drive_dst_ready(1'b1);
        expect_no_delivery_cycles(12);
        check_true("reset crossing produces no ghost",
                   delivered_total == before_delivered);
        scenario_pass("SC18");

        // SC19: reset while FIFO nonempty makes stale RAM unreachable.
        drive_dst_ready(1'b0);
        send_stream(FIFO_DEPTH - 1, 12'h960);
        check_true("FIFO nonempty before reset",
                   !dut_bridge.u_fifo.rd_empty ||
                   scoreboard_write_index > scoreboard_read_index);
        reset_and_release();
        drive_dst_ready(1'b1);
        expect_no_delivery_cycles(10);
        scenario_pass("SC19");

        // SC20: first post-reset word appears once, with no replay before it.
        reset_and_release();
        before_delivered = delivered_total;
        expect_no_delivery_cycles(8);
        send_one(12'h980);
        wait_scoreboard_empty();
        check_true("first post-reset transaction exactly once",
                   delivered_total == before_delivered + 1);
        expect_no_delivery_cycles(8);
        scenario_pass("SC20");

        // SC21: an in-flight word uses threshold state stable at destination N0.
        reset_and_release();
        drive_dst_ready(1'b0);
        th_oc_ch1 = 12'd3000;
        th_oc_ch2 = 12'd3000;
        send_one(12'd3500);
        th_oc_ch1 = 12'd4000;
        th_oc_ch2 = 12'd4000;
        repeat (2) @(posedge dst_clk);
        drive_dst_ready(1'b1);
        wait_scoreboard_empty();
        repeat (4) @(posedge dst_clk);
        check_true("in-flight threshold update follows destination contract",
                   !fault_latched);
        scenario_pass("SC21");

        // SC22: overcurrent retains the frozen N0-to-N3 latency.
        reset_and_release();
        set_default_thresholds();
        th_oc_ch1 = 12'd3000;
        th_oc_ch2 = 12'd4095;
        expect_fault_latency_three(12'd3500, `FAULT_OVERCURRENT);
        scenario_pass("SC22");

        // SC23: a safe accepted pair produces no classifier event.
        reset_and_release();
        set_default_thresholds();
        th_oc_ch1 = 12'd3000;
        th_oc_ch2 = 12'd3000;
        send_one(12'd500);
        wait_scoreboard_empty();
        repeat (5) @(posedge dst_clk);
        check_true("safe sample remains safe", !fault_latched && !fault_valid);
        scenario_pass("SC23");

        // SC24: open persistence consumes delivered transactions only.
        reset_and_release();
        set_default_thresholds();
        send_one(12'd0);
        send_one(12'd0);
        wait_scoreboard_empty();
        repeat (5) @(posedge dst_clk);
        check_true("open fault latched", fault_latched);
        check_true("open fault code", fault_code_latched == `FAULT_SENSOR_OPEN);
        scenario_pass("SC24");

        // SC25: saturation persistence consumes the same atomic pair.
        reset_and_release();
        set_default_thresholds();
        send_one(12'hFFF);
        send_one(12'hFFF);
        wait_scoreboard_empty();
        repeat (5) @(posedge dst_clk);
        check_true("saturation fault latched", fault_latched);
        check_true("saturation fault code",
                   fault_code_latched == `FAULT_SENSOR_SATURATION);
        scenario_pass("SC25");

        // SC26: stuck persistence is counted by accepted destination words.
        reset_and_release();
        set_default_thresholds();
        send_one(12'd1000);
        send_one(12'd1000);
        send_one(12'd1000);
        wait_scoreboard_empty();
        repeat (5) @(posedge dst_clk);
        check_true("stuck fault latched", fault_latched);
        check_true("stuck fault code", fault_code_latched == `FAULT_SENSOR_STUCK);
        scenario_pass("SC26");

        // SC27: consecutive deliveries intentionally exercise held-high Stage 2B valid.
        reset_and_release();
        set_default_thresholds();
        drive_dst_ready(1'b0);
        send_stream(6, 12'hA20);
        drive_dst_ready(1'b1);
        before_delivered = delivered_total;
        wait_for_delivery_after(before_delivered);
        wait_scoreboard_empty();
        check_true("continuous delivery accepted all transactions",
                   delivered_total == before_delivered + 6);
        scenario_pass("SC27");

        // SC28: source sequence wraps modulo DATA_WIDTH without reorder.
        send_stream(20, 12'hFF8);
        wait_scoreboard_empty();
        scenario_pass("SC28");

        // SC29: long randomized asynchronous clocks, pauses, and reset epochs.
        random_stress_accepted_start = accepted_total;
        stress_value = 0;
        for (reset_iteration = 0; reset_iteration < 16;
             reset_iteration = reset_iteration + 1) begin
            src_half_period = $urandom_range(2, 9);
            dst_half_period = $urandom_range(2, 11);
            reset_and_release();
            drive_dst_ready(1'b1);
            stress_batch = $urandom_range(60, 100);
            for (index = 0; index < stress_batch; index = index + 1) begin
                if (($urandom_range(0, 15) == 0) &&
                    ((scoreboard_write_index - scoreboard_read_index) <
                     FIFO_DEPTH - 1)) begin
                    @(negedge dst_clk);
                    dst_ready = 1'b0;
                    repeat ($urandom_range(1, 4)) @(posedge dst_clk);
                    @(negedge dst_clk);
                    dst_ready = 1'b1;
                end
                send_one(stress_value[DATA_WIDTH-1:0]);
                stress_value = (stress_value + 1) & 12'hFFF;
            end
            if (reset_iteration[0]) begin
                #($urandom_range(1, 7));
                assert_async_reset($urandom_range(2, 6));
                release_reset_wait_both();
            end else begin
                wait_scoreboard_empty();
            end
        end
        wait_scoreboard_empty();
        random_stress_transactions = accepted_total -
                                     random_stress_accepted_start;
        check_true("random stress transaction volume",
                   random_stress_transactions >= 1000);
        scenario_pass("SC29");

        // SC30: final phase/frequency sweep and clean drain.
        for (index = 0; index < 12; index = index + 1) begin
            src_half_period = 2 + (index % 7);
            dst_half_period = 3 + ((index * 3) % 8);
            #(1 + (index % 5));
            send_stream(12, 12'hB00 + (index * 12));
        end
        wait_scoreboard_empty();
        check_true("final scoreboard drained",
                   scoreboard_write_index == scoreboard_read_index);
        check_true("accounting exact",
                   accepted_total == delivered_total + reset_discarded_total);
        scenario_pass("SC30");

        check_true("all positive scenarios executed", scenario_count == 30);
        check_true("no checker errors", error_count == 0);
        $display("STAGE2D_POSITIVE_SCENARIOS=PASS_30_OF_30");
        $display("RANDOM_STRESS_TRANSACTIONS=%0d", random_stress_transactions);
        $display("SCOREBOARD_ACCEPTED=%0d", accepted_total);
        $display("SCOREBOARD_DELIVERED=%0d", delivered_total);
        $display("SCOREBOARD_RESET_DISCARDED=%0d", reset_discarded_total);
        $display("SCOREBOARD_PENDING=%0d",
                 scoreboard_write_index - scoreboard_read_index);
        $display("CDC_LATENCY_MIN_DST_CYCLES=%0d", cdc_latency_min_cycles);
        $display("CDC_LATENCY_MAX_DST_CYCLES=%0d", cdc_latency_max_cycles);
        $display("CDC_LATENCY_MIN_NS=%0d", cdc_latency_min_ns);
        $display("CDC_LATENCY_MAX_NS=%0d", cdc_latency_max_ns);
        $display("STAGE2B_DESTINATION_LATENCY_CYCLES=3");
        $display("ALL TESTS PASSED: tb_stage2d_async_adc_atomic_cdc");
        $finish;
    end

    initial begin
        #5000000;
        fail("global simulation timeout");
    end
endmodule
