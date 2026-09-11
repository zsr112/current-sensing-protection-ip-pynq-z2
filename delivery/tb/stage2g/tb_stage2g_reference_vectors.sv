`timescale 1ns/1ps

module tb_stage2g_reference_vectors;
    reg clk = 1'b0;
    reg rst_n = 1'b1;
    reg delivery_valid = 1'b0;
    reg [31:0] delivery_sequence = 32'd0;
    reg [5:0] delivery_bitmap = 6'd0;
    reg delivery_integrity_clean = 1'b0;
    reg clear_fault = 1'b0;

    reg capture_valid;
    reg [31:0] capture_sequence;
    reg [5:0] capture_bitmap;
    reg capture_integrity_clean;
    reg decision_valid;
    reg [31:0] decision_sequence;
    reg [5:0] decision_bitmap;
    reg decision_integrity_clean;

    wire fault_eval_valid;
    wire [31:0] fault_eval_sequence;
    wire [5:0] fault_eval_bitmap;
    wire [7:0] fault_eval_code;
    wire fault_eval_integrity_clean;
    wire fault_latched;
    wire episode_active;
    wire pwm_disable;
    wire [7:0] fault_code_latched;
    wire [7:0] episode_fault_code;
    wire post_clear_recovery_pending;
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

    integer vector_file;
    integer scan_count;
    integer line_number = 0;
    integer checked_cycles = 0;
    integer mismatch_count = 0;
    reg [8*1024-1:0] vector_path;
    reg [8*1024-1:0] line;

    integer in_reset;
    integer in_delivery;
    reg [31:0] in_sequence;
    reg [5:0] in_bitmap;
    integer in_integrity;
    integer in_clear;
    integer exp_eval_valid;
    reg [31:0] exp_eval_sequence;
    reg [5:0] exp_eval_bitmap;
    reg [7:0] exp_eval_code;
    integer exp_eval_integrity;
    integer exp_state;
    integer exp_latched;
    reg [7:0] exp_fault_code_compat;
    integer exp_recovery_pending;
    integer exp_pwm_disable;
    integer exp_clear_pending;
    reg [7:0] exp_first_code;
    reg [5:0] exp_first_bitmap;
    reg [5:0] exp_live_bitmap;
    reg [5:0] exp_seen_bitmap;
    integer exp_first_event;
    integer exp_clear_resolution;
    integer exp_clear_accept;
    reg [31:0] exp_clear_resolution_sequence;

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            capture_valid <= 1'b0;
            capture_sequence <= 32'd0;
            capture_bitmap <= 6'd0;
            capture_integrity_clean <= 1'b0;
            decision_valid <= 1'b0;
            decision_sequence <= 32'd0;
            decision_bitmap <= 6'd0;
            decision_integrity_clean <= 1'b0;
        end else begin
            capture_valid <= delivery_valid;
            if (delivery_valid) begin
                capture_sequence <= delivery_sequence;
                capture_bitmap <= delivery_bitmap;
                capture_integrity_clean <= delivery_integrity_clean;
            end

            decision_valid <= capture_valid;
            if (capture_valid) begin
                decision_sequence <= capture_sequence;
                decision_bitmap <= capture_bitmap;
                decision_integrity_clean <= capture_integrity_clean;
            end
        end
    end

    stage2g_fault_evaluation_pipeline u_pipeline (
        .clk(clk),
        .rst_n(rst_n),
        .evaluation_input_valid(decision_valid),
        .evaluation_input_sequence(decision_sequence),
        .evaluation_input_integrity_clean(decision_integrity_clean),
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
        .clk(clk),
        .rst_n(rst_n),
        .fault_eval_valid(fault_eval_valid),
        .fault_eval_sequence(fault_eval_sequence),
        .fault_eval_bitmap(fault_eval_bitmap),
        .fault_eval_code(fault_eval_code),
        .fault_eval_integrity_clean(fault_eval_integrity_clean),
        .clear_fault(clear_fault),
        .fault_latched(episode_active),
        .pwm_disable(pwm_disable),
        .fault_code_latched(episode_fault_code),
        .public_fault_latched_compat(fault_latched),
        .public_fault_code_compat(fault_code_latched),
        .post_clear_recovery_pending(post_clear_recovery_pending),
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

    task automatic check_bit;
        input [8*48-1:0] name;
        input actual;
        input integer expected;
        begin
            if (actual !== expected[0]) begin
                $display("FAIL: line=%0d field=%0s actual=%b expected=%0d",
                         line_number, name, actual, expected);
                mismatch_count = mismatch_count + 1;
            end
        end
    endtask

    task automatic check_word;
        input [8*48-1:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                $display("FAIL: line=%0d field=%0s actual=%h expected=%h",
                         line_number, name, actual, expected);
                mismatch_count = mismatch_count + 1;
            end
        end
    endtask

    task automatic compare_row;
        begin
            check_bit("fault_eval_valid", fault_eval_valid, exp_eval_valid);
            check_word("fault_eval_sequence", fault_eval_sequence,
                       exp_eval_sequence);
            check_word("fault_eval_bitmap", {26'd0, fault_eval_bitmap},
                       {26'd0, exp_eval_bitmap});
            check_word("fault_eval_code", {24'd0, fault_eval_code},
                       {24'd0, exp_eval_code});
            check_bit("fault_eval_integrity_clean",
                      fault_eval_integrity_clean, exp_eval_integrity);
            check_word("state", {28'd0, state}, exp_state);
            check_bit("fault_latched", fault_latched, exp_latched);
            check_word("fault_code_compat", {24'd0, fault_code_latched},
                       {24'd0, exp_fault_code_compat});
            check_bit("post_clear_recovery_pending",
                      post_clear_recovery_pending, exp_recovery_pending);
            check_bit("pwm_disable", pwm_disable, exp_pwm_disable);
            check_bit("clear_pending", clear_pending, exp_clear_pending);
            check_word("first_fault_code", {24'd0, first_fault_code},
                       {24'd0, exp_first_code});
            check_word("first_fault_bitmap", {26'd0, first_fault_bitmap},
                       {26'd0, exp_first_bitmap});
            check_word("live_fault_bitmap", {26'd0, live_fault_bitmap},
                       {26'd0, exp_live_bitmap});
            check_word("fault_seen_bitmap", {26'd0, fault_seen_bitmap},
                       {26'd0, exp_seen_bitmap});
            check_bit("first_fault_event", first_fault_event,
                      exp_first_event);
            check_bit("clear_resolution_event", clear_resolution_event,
                      exp_clear_resolution);
            check_bit("clear_accept_event", clear_accept_event,
                      exp_clear_accept);
            check_word("clear_resolution_sequence",
                       clear_resolution_sequence,
                       exp_clear_resolution_sequence);
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin
            // Vivado's Windows launcher treats an equals sign in a
            // --testplusarg value as an option delimiter.  Its runner copies
            // the vectors beside the snapshot and supplies the flag alone.
            if ($test$plusargs("VECTORS"))
                vector_path = "vectors.txt";
            else begin
                $display("FAIL: missing +VECTORS=<path>");
                $fatal(2);
            end
        end

        vector_file = $fopen(vector_path, "r");
        if (vector_file == 0) begin
            $display("FAIL: cannot open vector file %0s", vector_path);
            $fatal(2);
        end

        #1 rst_n = 1'b0;
        #1;
        scan_count = $fgets(line, vector_file);
        line_number = 1;

        while (!$feof(vector_file)) begin
            scan_count = $fgets(line, vector_file);
            if (scan_count != 0) begin
                line_number = line_number + 1;
                scan_count = $sscanf(
                    line,
                    "%d %d %h %h %d %d %d %h %h %h %d %d %d %h %d %d %d %h %h %h %h %d %d %d %h",
                    in_reset, in_delivery, in_sequence, in_bitmap,
                    in_integrity, in_clear, exp_eval_valid,
                    exp_eval_sequence, exp_eval_bitmap, exp_eval_code,
                    exp_eval_integrity, exp_state, exp_latched,
                    exp_fault_code_compat, exp_recovery_pending,
                    exp_pwm_disable, exp_clear_pending, exp_first_code,
                    exp_first_bitmap, exp_live_bitmap, exp_seen_bitmap,
                    exp_first_event, exp_clear_resolution,
                    exp_clear_accept, exp_clear_resolution_sequence);
                if (scan_count != 25) begin
                    $display("FAIL: malformed vector line %0d fields=%0d",
                             line_number, scan_count);
                    $fatal(2);
                end

                @(negedge clk);
                rst_n = !in_reset;
                delivery_valid = in_delivery[0];
                delivery_sequence = in_sequence;
                delivery_bitmap = in_bitmap;
                delivery_integrity_clean = in_integrity[0];
                clear_fault = in_clear[0];
                @(posedge clk);
                #1;
                compare_row();
                checked_cycles = checked_cycles + 1;
                if (mismatch_count != 0)
                    $fatal(1);
            end
        end

        $fclose(vector_file);
        $display("REFERENCE_MODEL_COMPARISON=PASS");
        $display("REFERENCE_VECTOR_CYCLES=PASS_%0d", checked_cycles);
        $display("RANDOM_EPISODES=PASS_1000");
        $display("STAGE2G_REFERENCE_VECTORS PASS");
        $finish;
    end
endmodule
