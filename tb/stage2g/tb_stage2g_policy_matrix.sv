`timescale 1ns/1ps
`include "fault_defs.vh"

// Direct transaction/policy fixture.  The raw-core fixture covers comparator
// wiring; this fixture drives the six primitive causes directly so every
// bitmap and every temporal policy boundary is independently exercised.
module tb_stage2g_policy_matrix;
    reg clk = 1'b0;
    reg rst_n = 1'b1;
    always #5 clk = ~clk;

    reg delivery_valid = 1'b0;
    reg [31:0] delivery_sequence = 32'd0;
    reg [5:0] delivery_bitmap = 6'd0;
    reg delivery_integrity_clean = 1'b1;
    reg clear_request = 1'b0;

    reg capture_valid;
    reg [31:0] capture_sequence;
    reg [5:0] capture_bitmap;
    reg capture_integrity;
    reg decision_valid;
    reg [31:0] decision_sequence;
    reg [5:0] decision_bitmap;
    reg decision_integrity;

    wire fault_eval_valid;
    wire [31:0] fault_eval_sequence;
    wire [5:0] fault_eval_bitmap;
    wire [7:0] fault_eval_code;
    wire fault_eval_integrity_clean;
    wire fault_latched;
    wire pwm_disable;
    wire [7:0] fault_code_latched;
    wire [3:0] state;
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
    integer cycle = 0;
    integer sent_count = 0;
    integer eval_count = 0;
    integer first_event_count = 0;
    integer clear_resolution_count = 0;
    reg [31:0] sent_seq [0:511];
    reg [5:0] sent_bitmap [0:511];
    reg sent_integrity [0:511];
    integer sent_cycle [0:511];
    integer eval_source_index;
    reg [31:0] last_observed_eval_sequence = 32'd0;
    reg [5:0] last_observed_eval_bitmap = 6'd0;
    reg [3:0] previous_state = 4'd2;
    reg [7:0] previous_first_code = `FAULT_NONE;
    reg [5:0] previous_first_bitmap = 6'd0;
    reg [5:0] previous_seen_bitmap = 6'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            capture_valid <= 1'b0;
            capture_sequence <= 32'd0;
            capture_bitmap <= 6'd0;
            capture_integrity <= 1'b0;
            decision_valid <= 1'b0;
            decision_sequence <= 32'd0;
            decision_bitmap <= 6'd0;
            decision_integrity <= 1'b0;
        end else begin
            capture_valid <= delivery_valid;
            if (delivery_valid) begin
                capture_sequence <= delivery_sequence;
                capture_bitmap <= delivery_bitmap;
                capture_integrity <= delivery_integrity_clean;
            end
            decision_valid <= capture_valid;
            if (capture_valid) begin
                decision_sequence <= capture_sequence;
                decision_bitmap <= capture_bitmap;
                decision_integrity <= capture_integrity;
            end
        end
    end

    stage2g_fault_evaluation_pipeline u_pipeline (
        .clk(clk), .rst_n(rst_n),
        .evaluation_input_valid(decision_valid),
        .evaluation_input_sequence(decision_sequence),
        .evaluation_input_integrity_clean(decision_integrity),
        .cause_ch1_overcurrent(decision_valid && decision_bitmap[0]),
        .cause_ch2_overcurrent(decision_valid && decision_bitmap[1]),
        .cause_sensor_mismatch(decision_valid && decision_bitmap[2]),
        .cause_sensor_open(decision_valid && decision_bitmap[3]),
        .cause_sensor_saturation(decision_valid && decision_bitmap[4]),
        .cause_sensor_stuck(decision_valid && decision_bitmap[5]),
        .fault_eval_valid(fault_eval_valid),
        .fault_eval_sequence(fault_eval_sequence),
        .fault_eval_bitmap(fault_eval_bitmap),
        .fault_eval_code(fault_eval_code),
        .fault_eval_integrity_clean(fault_eval_integrity_clean)
    );

    stage2g_fault_episode_controller u_controller (
        .clk(clk), .rst_n(rst_n),
        .fault_eval_valid(fault_eval_valid),
        .fault_eval_sequence(fault_eval_sequence),
        .fault_eval_bitmap(fault_eval_bitmap),
        .fault_eval_code(fault_eval_code),
        .fault_eval_integrity_clean(fault_eval_integrity_clean),
        .clear_fault(clear_request),
        .fault_latched(fault_latched),
        .pwm_disable(pwm_disable),
        .fault_code_latched(fault_code_latched),
        .state(state),
        .clear_pending(clear_pending),
        .first_fault_code(first_fault_code),
        .first_fault_bitmap(first_fault_bitmap),
        .live_fault_bitmap(live_fault_bitmap),
        .fault_seen_bitmap(fault_seen_bitmap),
        .first_fault_event(first_fault_event),
        .clear_resolution_event(clear_resolution_event),
        .clear_accept_event(clear_accept_event),
        .clear_resolution_sequence(clear_resolution_sequence)
    );

    function [7:0] expected_code;
        input [5:0] bitmap;
        begin
            if ((|bitmap[1:0]) && (|bitmap[5:2]))
                expected_code = `FAULT_OC_WITH_SENSOR;
            else if (|bitmap[1:0])
                expected_code = `FAULT_OVERCURRENT;
            else if (bitmap[4])
                expected_code = `FAULT_SENSOR_SATURATION;
            else if (bitmap[3])
                expected_code = `FAULT_SENSOR_OPEN;
            else if (bitmap[5])
                expected_code = `FAULT_SENSOR_STUCK;
            else if (bitmap[2])
                expected_code = `FAULT_SENSOR_MISMATCH;
            else
                expected_code = `FAULT_NONE;
        end
    endfunction

    task automatic fail;
        input [8*96-1:0] label;
        begin
            $display("FAIL cycle=%0d %0s", cycle, label);
            failures = failures + 1;
        end
    endtask

    task automatic check_word;
        input [8*96-1:0] label;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                $display("FAIL cycle=%0d %0s actual=%h expected=%h",
                         cycle, label, actual, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_bit;
        input [8*96-1:0] label;
        input actual;
        input expected;
        begin
            if (actual !== expected) begin
                $display("FAIL cycle=%0d %0s actual=%b expected=%b",
                         cycle, label, actual, expected);
                failures = failures + 1;
            end
        end
    endtask

    // The checker runs after nonblocking assignments settle and therefore
    // observes the registered edge-2 evaluation and edge-3 policy decision.
    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            check_bit("reset_eval_invalid", fault_eval_valid, 1'b0);
            check_bit("reset_safe", pwm_disable, 1'b1);
            check_bit("reset_clear_pending", clear_pending, 1'b0);
        end else begin
            if (fault_eval_valid) begin
                if (eval_source_index >= sent_count) begin
                    fail("evaluation_without_destination_delivery");
                end else begin
                    check_word("evaluation_sequence", fault_eval_sequence,
                               sent_seq[eval_source_index]);
                    check_word("evaluation_bitmap", {26'd0, fault_eval_bitmap},
                               {26'd0, sent_bitmap[eval_source_index]});
                    check_word("evaluation_code", {24'd0, fault_eval_code},
                               {24'd0, expected_code(sent_bitmap[eval_source_index])});
                    check_bit("evaluation_integrity", fault_eval_integrity_clean,
                              sent_integrity[eval_source_index]);
                    if ((cycle - sent_cycle[eval_source_index]) != 2)
                        fail("evaluation_latency_not_two_edges");
                    last_observed_eval_sequence = fault_eval_sequence;
                    last_observed_eval_bitmap = fault_eval_bitmap;
                    eval_source_index = eval_source_index + 1;
                    eval_count = eval_count + 1;
                end
            end
            if (first_fault_event)
                first_event_count = first_event_count + 1;
            if (clear_resolution_event)
                clear_resolution_count = clear_resolution_count + 1;
            if (state != 4'd0 && !pwm_disable)
                fail("unsafe_output_outside_armed");
            if ((previous_state == 4'd1) && (state == 4'd1)) begin
                check_word("first_code_cycle_immutable",
                           {24'd0, first_fault_code},
                           {24'd0, previous_first_code});
                check_word("first_bitmap_cycle_immutable",
                           {26'd0, first_fault_bitmap},
                           {26'd0, previous_first_bitmap});
                if ((fault_seen_bitmap | previous_seen_bitmap) !=
                    fault_seen_bitmap)
                    fail("seen_bitmap_not_monotonic");
            end
        end
        previous_state = state;
        previous_first_code = first_fault_code;
        previous_first_bitmap = first_fault_bitmap;
        previous_seen_bitmap = fault_seen_bitmap;
        cycle = cycle + 1;
    end

    // An asserted local reset invalidates every outstanding delivery in the
    // checker just as it invalidates all three RTL valid stages.
    always @(negedge rst_n)
        eval_source_index = sent_count;

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic send;
        input [31:0] sequence_value;
        input [5:0] bitmap_value;
        input integrity_value;
        begin
            @(negedge clk);
            delivery_valid = 1'b1;
            delivery_sequence = sequence_value;
            delivery_bitmap = bitmap_value;
            delivery_integrity_clean = integrity_value;
            sent_seq[sent_count] = sequence_value;
            sent_bitmap[sent_count] = bitmap_value;
            sent_integrity[sent_count] = integrity_value;
            sent_cycle[sent_count] = cycle;
            sent_count = sent_count + 1;
            @(posedge clk);
            #2;
            delivery_valid = 1'b0;
        end
    endtask

    task automatic send_with_clear;
        input [31:0] sequence_value;
        input [5:0] bitmap_value;
        input integrity_value;
        begin
            @(negedge clk);
            delivery_valid = 1'b1;
            delivery_sequence = sequence_value;
            delivery_bitmap = bitmap_value;
            delivery_integrity_clean = integrity_value;
            clear_request = 1'b1;
            sent_seq[sent_count] = sequence_value;
            sent_bitmap[sent_count] = bitmap_value;
            sent_integrity[sent_count] = integrity_value;
            sent_cycle[sent_count] = cycle;
            sent_count = sent_count + 1;
            @(posedge clk);
            #2;
            delivery_valid = 1'b0;
            clear_request = 1'b0;
        end
    endtask

    task automatic idle;
        begin
            @(negedge clk);
            delivery_valid = 1'b0;
            clear_request = 1'b0;
            @(posedge clk);
            #2;
        end
    endtask

    task automatic clear_pulse;
        begin
            @(negedge clk);
            clear_request = 1'b1;
            @(posedge clk);
            #2;
            clear_request = 1'b0;
        end
    endtask

    task automatic held_clear;
        input integer count;
        integer n;
        begin
            @(negedge clk);
            clear_request = 1'b1;
            for (n = 0; n < count; n = n + 1) begin
                @(posedge clk);
                #2;
            end
            clear_request = 1'b0;
        end
    endtask

    task automatic reset_now;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            #1;
            rst_n = 1'b1;
            @(negedge clk);
            delivery_valid = 1'b0;
            clear_request = 1'b0;
        end
    endtask

    integer bitmap_index;
    integer n;
    initial begin
        // Asynchronous reset and indefinite no-sample safe hold.
        #1 rst_n = 1'b0;
        #2;
        check_word("initial_state", {28'd0, state}, 32'd2);
        check_bit("initial_safe", pwm_disable, 1'b1);
        rst_n = 1'b1;
        repeat (5) idle();
        check_word("no_sample_reset_wait", {28'd0, state}, 32'd2);

        // A dirty first transaction cannot arm or create a physical cause.
        send(32'h0000_0000, 6'h01, 1'b0);
        repeat (3) idle();
        check_word("dirty_first_wait", {28'd0, state}, 32'd2);
        check_bit("dirty_first_safe", pwm_disable, 1'b1);

        // The first clean healthy evaluation arms immediately.
        send(32'h0000_0001, 6'h00, 1'b1);
        repeat (3) idle();
        check_word("healthy_arms", {28'd0, state}, 32'd0);
        check_bit("healthy_releases", pwm_disable, 1'b0);

        // Every primitive bitmap, including zero, is delivered at II=1.
        for (bitmap_index = 0; bitmap_index < 64; bitmap_index = bitmap_index + 1)
            send(32'h0000_0100 + bitmap_index, bitmap_index[5:0], 1'b1);
        repeat (8) idle();
        if (eval_count < 66)
            fail("bitmap_matrix_dropped_evaluations");
        if (first_event_count != 1)
            fail("bitmap_matrix_retriggered_first_event");
        check_word("first_bitmap_immutable", {26'd0, first_fault_bitmap}, 32'd1);
        check_word("first_code_immutable", {24'd0, first_fault_code},
                   {24'd0, `FAULT_OVERCURRENT});
        check_word("seen_bitmap_or", {26'd0, fault_seen_bitmap}, 32'h3f);
        check_word("live_bitmap_latest", {26'd0, live_fault_bitmap}, 32'h3f);

        // A historical healthy evaluation may update live=0, but it is not a
        // future clear resolver and cannot be reused after a later request.
        send(32'h0000_01f0, 6'h00, 1'b1);
        repeat (3) idle();
        check_word("historical_healthy_live", {26'd0, live_fault_bitmap}, 32'd0);

        // A clear request with no evaluation is fenced indefinitely.
        clear_pulse();
        repeat (3) idle();
        check_bit("clear_no_sample_pending", clear_pending, 1'b1);
        check_word("clear_no_sample_latched", {28'd0, state}, 32'd1);
        check_bit("clear_no_sample_safe", pwm_disable, 1'b1);

        // Fault and non-clean evaluations reject the pending request; the
        // first later clean zero evaluation accepts it and enters RESET_WAIT.
        send(32'h0000_0200, 6'h02, 1'b1);
        repeat (3) idle();
        check_bit("clear_fault_rejected", clear_pending, 1'b0);
        check_word("clear_fault_stays_latched", {28'd0, state}, 32'd1);
        clear_pulse();
        send(32'h0000_0201, 6'h00, 1'b0);
        repeat (3) idle();
        check_bit("clear_nonclean_rejected", clear_pending, 1'b0);
        check_word("clear_nonclean_stays_latched", {28'd0, state}, 32'd1);
        clear_pulse();
        send(32'h0000_0202, 6'h00, 1'b1);
        repeat (3) idle();
        check_word("clear_healthy_reset_wait", {28'd0, state}, 32'd2);
        check_bit("clear_healthy_safe", pwm_disable, 1'b1);
        check_word("clear_sequence", clear_resolution_sequence, 32'h202);

        // The resolution transaction does not arm. A later healthy evaluation
        // does, and a fault immediately after recovery starts a new episode.
        send(32'h0000_0203, 6'h00, 1'b1);
        repeat (3) idle();
        check_word("post_clear_armed", {28'd0, state}, 32'd0);
        send(32'h0000_0204, 6'h20, 1'b1);
        repeat (3) idle();
        check_word("post_recovery_retrigger", {28'd0, state}, 32'd1);
        check_word("post_recovery_first", {26'd0, first_fault_bitmap}, 32'h20);

        // Same-edge request ordering under a continuous II=1 stream.  The
        // seq 0x400 retirement already present on the clear-request edge only
        // captures clear_pending; seq 0x401 resolves it one edge later.
        send(32'h0000_0400, 6'h01, 1'b1);
        send(32'h0000_0401, 6'h00, 1'b1);
        send(32'h0000_0402, 6'h00, 1'b1);
        send_with_clear(32'h0000_0403, 6'h00, 1'b1);
        check_bit("same_edge_request_pending", clear_pending, 1'b1);
        check_word("same_edge_request_still_latched", {28'd0, state}, 32'd1);
        send(32'h0000_0404, 6'h00, 1'b1);
        if (clear_resolution_count < 2)
            fail("same_edge_clear_did_not_resolve_later");
        check_word("same_edge_resolution_sequence",
                   clear_resolution_sequence, 32'h0000_0401);
        check_word("same_edge_clear_reset_wait", {28'd0, state}, 32'd2);
        check_bit("same_edge_resolution_safe", pwm_disable, 1'b1);
        repeat (2) idle();
        check_word("continuous_stream_later_healthy_arms",
                   {28'd0, state}, 32'd0);

        // Sequence identity remains aligned through modulo-32 wrap.
        send(32'hffff_fffe, 6'h00, 1'b1);
        send(32'hffff_ffff, 6'h01, 1'b1);
        send(32'h0000_0000, 6'h02, 1'b1);
        send(32'h0000_0001, 6'h04, 1'b1);
        repeat (8) idle();
        check_word("wrap_latest_sequence", last_observed_eval_sequence,
                   32'h0000_0001);
        check_word("wrap_latest_bitmap", {26'd0, last_observed_eval_bitmap},
                   32'h04);

        // Reset flushes capture, decision, and evaluation stages, and also
        // clears a pending request/episode. Repeat at each pipeline offset.
        for (n = 0; n < 3; n = n + 1) begin
            reset_now();
            send(32'h1000_0000 + n, 6'h01, 1'b1);
            if (n > 0) idle();
            if (n > 1) idle();
            @(negedge clk);
            rst_n = 1'b0;
            #1;
            check_word("mid_pipeline_reset_state", {28'd0, state}, 32'd2);
            check_bit("mid_pipeline_reset_safe", pwm_disable, 1'b1);
            check_bit("mid_pipeline_reset_eval_invalid",
                      fault_eval_valid, 1'b0);
            rst_n = 1'b1;
            repeat (5) idle();
            check_bit("mid_pipeline_no_stale_eval", fault_eval_valid, 1'b0);
            check_word("mid_pipeline_no_stale_fault", {28'd0, state}, 32'd2);
        end

        // Reset wins over an asserted clear and a retiring fault.
        reset_now();
        send(32'd0, 6'h00, 1'b1);
        repeat (3) idle();
        send(32'd1, 6'h01, 1'b1);
        repeat (3) idle();
        held_clear(2);
        @(negedge clk);
        rst_n = 1'b0;
        clear_request = 1'b1;
        #1;
        check_bit("reset_clear_pending", clear_pending, 1'b0);
        check_word("reset_clear_state", {28'd0, state}, 32'd2);
        check_bit("reset_clear_safe", pwm_disable, 1'b1);
        rst_n = 1'b1;

        if (failures != 0) begin
            $display("STAGE2G_POLICY_MATRIX=FAIL_%0d", failures);
            $fatal(1);
        end
        $display("STAGE2G_POLICY_MATRIX=PASS");
        $display("BITMAP_COMBINATIONS=PASS_64_OF_64");
        $display("PRIORITY_CODE_MATRIX=PASS_64_OF_64");
        $display("II1_ALIGNMENT=PASS");
        $display("CLEAR_FENCE_MATRIX=PASS");
        $display("RESET_PIPELINE_FLUSH_MATRIX=PASS");
        $finish;
    end
endmodule
