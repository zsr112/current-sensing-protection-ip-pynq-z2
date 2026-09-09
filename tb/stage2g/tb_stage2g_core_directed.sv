`timescale 1ns/1ps

module tb_stage2g_core_directed;
    localparam DATA_WIDTH = 12;
    localparam CNT_WIDTH = 8;
    localparam HEALTH_CNT_WIDTH = 4;

    reg clk = 1'b0;
    reg rst_n = 1'b1;
    reg sample_valid = 1'b0;
    reg [31:0] sample_sequence = 32'd0;
    reg sample_source_integrity_clean = 1'b1;
    reg sample_destination_integrity_clean = 1'b1;
    reg pwm_enable = 1'b1;
    reg clear_fault = 1'b0;
    reg [DATA_WIDTH-1:0] i_ch1 = 12'd0;
    reg [DATA_WIDTH-1:0] i_ch2 = 12'd0;
    reg [DATA_WIDTH-1:0] th_oc_ch1 = 12'd1000;
    reg [DATA_WIDTH-1:0] th_oc_ch2 = 12'd1000;
    reg [DATA_WIDTH-1:0] th_diff = 12'd100;
    reg [DATA_WIDTH-1:0] th_open = 12'd0;
    reg [DATA_WIDTH-1:0] th_sat = 12'd4095;
    reg [DATA_WIDTH-1:0] th_stuck_delta = 12'd0;
    reg [HEALTH_CNT_WIDTH-1:0] th_persist = 4'hf;
    reg [CNT_WIDTH-1:0] period = 8'd20;
    reg [CNT_WIDTH-1:0] duty = 8'd10;

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
    wire [31:0] fault_eval_sequence;
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
    wire [31:0] clear_resolution_sequence;

    integer failures = 0;
    integer cycle_count = 0;

    always #5 clk = ~clk;

    stage2g_protection_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(CNT_WIDTH),
        .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid),
        .sample_sequence(sample_sequence),
        .sample_source_integrity_clean(sample_source_integrity_clean),
        .sample_destination_integrity_clean(
            sample_destination_integrity_clean),
        .pwm_enable(pwm_enable), .clear_fault(clear_fault),
        .i_ch1(i_ch1), .i_ch2(i_ch2), .th_oc_ch1(th_oc_ch1),
        .th_oc_ch2(th_oc_ch2), .th_diff(th_diff), .th_open(th_open),
        .th_sat(th_sat), .th_stuck_delta(th_stuck_delta),
        .th_persist(th_persist), .period(period), .duty(duty),
        .pwm_raw(pwm_raw), .pwm_out(pwm_out), .oc_any(oc_any),
        .oc_both(oc_both), .mismatch_flag(mismatch_flag),
        .sensor_open_flag(sensor_open_flag),
        .sensor_sat_flag(sensor_sat_flag),
        .sensor_stuck_flag(sensor_stuck_flag), .fault_valid(fault_valid),
        .fault_latched(fault_latched), .fault_code(fault_code),
        .fault_code_latched(fault_code_latched), .fsm_state(fsm_state),
        .abs_diff(abs_diff), .fault_eval_valid(fault_eval_valid),
        .fault_eval_sequence(fault_eval_sequence),
        .fault_eval_bitmap(fault_eval_bitmap),
        .fault_eval_code(fault_eval_code),
        .fault_eval_integrity_clean(fault_eval_integrity_clean),
        .clear_pending(clear_pending), .first_fault_code(first_fault_code),
        .first_fault_bitmap(first_fault_bitmap),
        .live_fault_bitmap(live_fault_bitmap),
        .fault_seen_bitmap(fault_seen_bitmap),
        .first_fault_event(first_fault_event),
        .clear_resolution_event(clear_resolution_event),
        .clear_accept_event(clear_accept_event),
        .clear_resolution_sequence(clear_resolution_sequence)
    );

    task automatic check;
        input [8*64-1:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                $display("FAIL: cycle=%0d %0s actual=%h expected=%h",
                         cycle_count, name, actual, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic tick;
        begin
            @(posedge clk);
            #1;
            cycle_count = cycle_count + 1;
        end
    endtask

    task automatic idle;
        begin
            sample_valid = 1'b0;
            clear_fault = 1'b0;
            tick();
        end
    endtask

    task automatic send_sample;
        input [31:0] seq_value;
        input [DATA_WIDTH-1:0] ch1;
        input [DATA_WIDTH-1:0] ch2;
        input source_integrity;
        input destination_integrity;
        begin
            sample_valid = 1'b1;
            sample_sequence = seq_value;
            i_ch1 = ch1;
            i_ch2 = ch2;
            sample_source_integrity_clean = source_integrity;
            sample_destination_integrity_clean = destination_integrity;
            tick();
            sample_valid = 1'b0;
        end
    endtask

    task automatic send_clear;
        begin
            clear_fault = 1'b1;
            tick();
            clear_fault = 1'b0;
        end
    endtask

    task automatic drain;
        input integer count;
        integer index;
        begin
            for (index = 0; index < count; index = index + 1)
                idle();
        end
    endtask

    initial begin
        // Establish an asynchronous reset edge, then verify the safe reset
        // state and the exact three-edge delivery-to-policy schedule.
        #1 rst_n = 1'b0;
        #2;
        check("reset_state", fsm_state, 4'd2);
        check("reset_safe", pwm_out, 1'b0);
        check("reset_pending", clear_pending, 1'b0);
        rst_n = 1'b1;

        // First healthy transaction: edge 0 capture, edge 1 decision,
        // edge 2 evaluation, edge 3 ARMED policy retirement.
        send_sample(32'd0, 12'd200, 12'd200, 1'b1, 1'b1);
        check("healthy_edge0_eval", fault_eval_valid, 1'b0);
        idle();
        check("healthy_edge1_eval", fault_eval_valid, 1'b0);
        idle();
        check("healthy_edge2_eval_valid", fault_eval_valid, 1'b1);
        check("healthy_edge2_eval_bitmap", fault_eval_bitmap, 6'd0);
        check("healthy_edge2_eval_seq", fault_eval_sequence, 32'd0);
        idle();
        check("healthy_policy_state", fsm_state, 4'd0);
        check("healthy_policy_safe", dut.pwm_disable, 1'b0);

        // A simultaneous CH1+CH2 overcurrent is one first fault with both
        // primitive bits retained and the compatibility OC code.
        send_sample(32'd1, 12'd2000, 12'd2000, 1'b1, 1'b1);
        drain(2);
        check("fault_eval_bitmap_oc_both", fault_eval_bitmap, 6'b000011);
        check("fault_eval_code_oc_both", fault_eval_code, 8'h01);
        idle();
        check("fault_latched_oc_both", fault_latched, 1'b1);
        check("first_bitmap_oc_both", first_fault_bitmap, 6'b000011);
        check("first_code_oc_both", first_fault_code, 8'h01);
        check("safe_oc_both", pwm_out, 1'b0);

        // A later differential cause updates live/seen but cannot overwrite
        // the immutable first cause.
        send_sample(32'd2, 12'd500, 12'd200, 1'b1, 1'b1);
        drain(3);
        check("later_diff_live", live_fault_bitmap, 6'b000100);
        check("later_diff_seen", fault_seen_bitmap, 6'b000111);
        check("later_diff_first", first_fault_bitmap, 6'b000011);
        check("later_diff_first_code", first_fault_code, 8'h01);

        // A non-clean fault is visible as an evaluation but is not a physical
        // cause and cannot alter the episode fields.
        send_sample(32'd3, 12'd2500, 12'd2500, 1'b0, 1'b1);
        drain(2);
        check("nonclean_eval_valid", fault_eval_valid, 1'b1);
        check("nonclean_eval_integrity", fault_eval_integrity_clean, 1'b0);
        idle();
        check("nonclean_first_unchanged", first_fault_bitmap, 6'b000011);
        check("nonclean_seen_unchanged", fault_seen_bitmap, 6'b000111);

        // Clear is request/evaluation fenced. No sample leaves the request
        // pending; a later healthy evaluation enters RESET_WAIT and remains
        // safe until another healthy evaluation arms the episode.
        send_clear();
        check("clear_pending_captured", clear_pending, 1'b1);
        drain(2);
        check("clear_pending_no_sample", clear_pending, 1'b1);
        send_sample(32'd4, 12'd200, 12'd200, 1'b1, 1'b1);
        drain(3);
        check("clear_resolution_event", clear_resolution_event, 1'b1);
        check("clear_resolution_accept", clear_accept_event, 1'b1);
        check("clear_resolution_state", fsm_state, 4'd2);
        check("clear_resolution_safe", pwm_out, 1'b0);
        idle();
        check("reset_wait_no_implicit_arm", fsm_state, 4'd2);
        send_sample(32'd5, 12'd200, 12'd200, 1'b1, 1'b1);
        drain(3);
        check("post_clear_healthy_armed", fsm_state, 4'd0);
        check("post_clear_safe_release", dut.pwm_disable, 1'b0);

        // Reset flushes an occupied pipeline and prevents stale retirement.
        send_sample(32'd6, 12'd2000, 12'd2000, 1'b1, 1'b1);
        @(negedge clk);
        rst_n = 1'b0;
        #1;
        check("mid_pipeline_reset_state", fsm_state, 4'd2);
        rst_n = 1'b1;
        drain(5);
        check("no_stale_post_reset_fault", fault_latched, 1'b0);
        check("no_stale_post_reset_eval", fault_eval_valid, 1'b0);

        // A clean fault on the first eligible RESET_WAIT transaction latches
        // directly, while a non-clean first transaction remains in wait.
        send_sample(32'd0, 12'd2000, 12'd2000, 1'b0, 1'b1);
        drain(3);
        check("first_nonclean_reset_wait", fsm_state, 4'd2);
        check("first_nonclean_safe", pwm_out, 1'b0);
        send_sample(32'd1, 12'd2000, 12'd2000, 1'b1, 1'b1);
        drain(3);
        check("fault_first_reset_wait", fsm_state, 4'd1);
        check("fault_first_reset_wait_latched", fault_latched, 1'b1);
        check("fault_first_reset_wait_bitmap", first_fault_bitmap, 6'b000011);

        // Destination classification is owned outside this direct core. A
        // stale first delivery and its resynchronizing gap arrive non-clean;
        // only the following clean delivery is policy-eligible and can arm.
        rst_n = 1'b0;
        #1;
        rst_n = 1'b1;
        send_sample(32'd7, 12'd200, 12'd200, 1'b1, 1'b0);
        drain(3);
        check("sequence_gap_stays_wait", fsm_state, 4'd2);
        send_sample(32'd8, 12'd200, 12'd200, 1'b1, 1'b0);
        drain(3);
        check("sequence_gap_resync_stays_wait", fsm_state, 4'd2);
        send_sample(32'd9, 12'd200, 12'd200, 1'b1, 1'b1);
        drain(3);
        check("sequence_gap_recovery_arms", fsm_state, 4'd0);

        if (failures != 0) begin
            $display("STAGE2G_CORE_DIRECTED=FAIL_%0d", failures);
            $fatal(1);
        end
        $display("STAGE2G_CORE_DIRECTED=PASS");
        $display("FAULT_EVALUATION_LATENCY_ACLK=3");
        $display("RESET_RACE_TESTS=PASS");
        $display("CLEAR_FENCE_DIRECTED=PASS");
        $finish;
    end
endmodule
