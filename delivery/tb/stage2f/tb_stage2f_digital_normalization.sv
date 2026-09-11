`timescale 1ns/1ps

module tb_stage2f_digital_normalization;
    reg ACLK = 1'b0;
    reg local_resetn = 1'b0;
    reg raw_delivery_valid = 1'b0;
    reg [31:0] raw_sequence = 32'd0;
    reg [11:0] raw_ch1 = 12'd0;
    reg [11:0] raw_ch2 = 12'd0;

    always #5 ACLK = ~ACLK;

    wire u_valid;
    wire [31:0] u_sequence;
    wire signed [12:0] u_ch1;
    wire signed [12:0] u_ch2;
    wire u_configured, u_profile_valid, u_encoding_valid, u_zero_valid, u_polarity_valid;

    adc_sample_code_normalizer u_unconfigured (
        .ACLK(ACLK), .local_resetn(local_resetn),
        .raw_delivery_valid(raw_delivery_valid), .raw_sequence(raw_sequence),
        .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(u_valid), .normalized_sequence(u_sequence),
        .normalized_ch1(u_ch1), .normalized_ch2(u_ch2),
        .profile_configured(u_configured), .profile_valid(u_profile_valid),
        .profile_encoding_supported(u_encoding_valid),
        .profile_zero_code_valid(u_zero_valid),
        .profile_polarity_valid(u_polarity_valid)
    );

    wire u_mid_pos_valid, u_mid_rev_valid, u_zero_0_valid, u_zero_1_valid;
    wire u_zero_2047_valid, u_zero_4094_valid, u_zero_4095_valid;
    wire twos_pos_valid, twos_rev_valid;
    wire [31:0] u_mid_pos_sequence, u_mid_rev_sequence, u_zero_0_sequence;
    wire [31:0] u_zero_1_sequence, u_zero_2047_sequence, u_zero_4094_sequence;
    wire [31:0] u_zero_4095_sequence, twos_pos_sequence, twos_rev_sequence;
    wire signed [12:0] u_mid_pos_ch1, u_mid_pos_ch2, u_mid_rev_ch1, u_mid_rev_ch2;
    wire signed [12:0] u_zero_0_ch1, u_zero_0_ch2, u_zero_1_ch1, u_zero_1_ch2;
    wire signed [12:0] u_zero_2047_ch1, u_zero_2047_ch2, u_zero_4094_ch1, u_zero_4094_ch2;
    wire signed [12:0] u_zero_4095_ch1, u_zero_4095_ch2, twos_pos_ch1, twos_pos_ch2;
    wire signed [12:0] twos_rev_ch1, twos_rev_ch2;
    wire u_mid_pos_configured, u_mid_pos_profile_valid, u_mid_pos_encoding_valid;
    wire u_mid_pos_zero_valid, u_mid_pos_polarity_valid;

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd1),
        .PROFILE_ZERO_CODE(12'd2048), .CH1_POLARITY_NEGATIVE(0), .CH2_POLARITY_NEGATIVE(0))
        u_mid_pos (.ACLK(ACLK), .local_resetn(local_resetn), .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence), .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(u_mid_pos_valid), .normalized_sequence(u_mid_pos_sequence),
        .normalized_ch1(u_mid_pos_ch1), .normalized_ch2(u_mid_pos_ch2),
        .profile_configured(u_mid_pos_configured), .profile_valid(u_mid_pos_profile_valid),
        .profile_encoding_supported(u_mid_pos_encoding_valid), .profile_zero_code_valid(u_mid_pos_zero_valid),
        .profile_polarity_valid(u_mid_pos_polarity_valid));

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd1),
        .PROFILE_ZERO_CODE(12'd2048), .CH1_POLARITY_NEGATIVE(0), .CH2_POLARITY_NEGATIVE(1))
        u_mid_rev (.ACLK(ACLK), .local_resetn(local_resetn), .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence), .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(u_mid_rev_valid), .normalized_sequence(u_mid_rev_sequence),
        .normalized_ch1(u_mid_rev_ch1), .normalized_ch2(u_mid_rev_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd1),
        .PROFILE_ZERO_CODE(12'd0), .CH1_POLARITY_NEGATIVE(0), .CH2_POLARITY_NEGATIVE(1))
        u_zero_0 (.ACLK(ACLK), .local_resetn(local_resetn), .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence), .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(u_zero_0_valid), .normalized_sequence(u_zero_0_sequence),
        .normalized_ch1(u_zero_0_ch1), .normalized_ch2(u_zero_0_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd1),
        .PROFILE_ZERO_CODE(12'd1), .CH1_POLARITY_NEGATIVE(0), .CH2_POLARITY_NEGATIVE(1))
        u_zero_1 (.ACLK(ACLK), .local_resetn(local_resetn), .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence), .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(u_zero_1_valid), .normalized_sequence(u_zero_1_sequence),
        .normalized_ch1(u_zero_1_ch1), .normalized_ch2(u_zero_1_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd1),
        .PROFILE_ZERO_CODE(12'd2047), .CH1_POLARITY_NEGATIVE(0), .CH2_POLARITY_NEGATIVE(1))
        u_zero_2047 (.ACLK(ACLK), .local_resetn(local_resetn), .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence), .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(u_zero_2047_valid), .normalized_sequence(u_zero_2047_sequence),
        .normalized_ch1(u_zero_2047_ch1), .normalized_ch2(u_zero_2047_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd1),
        .PROFILE_ZERO_CODE(12'd4094), .CH1_POLARITY_NEGATIVE(0), .CH2_POLARITY_NEGATIVE(1))
        u_zero_4094 (.ACLK(ACLK), .local_resetn(local_resetn), .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence), .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(u_zero_4094_valid), .normalized_sequence(u_zero_4094_sequence),
        .normalized_ch1(u_zero_4094_ch1), .normalized_ch2(u_zero_4094_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd1),
        .PROFILE_ZERO_CODE(12'd4095), .CH1_POLARITY_NEGATIVE(0), .CH2_POLARITY_NEGATIVE(1))
        u_zero_4095 (.ACLK(ACLK), .local_resetn(local_resetn), .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence), .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(u_zero_4095_valid), .normalized_sequence(u_zero_4095_sequence),
        .normalized_ch1(u_zero_4095_ch1), .normalized_ch2(u_zero_4095_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd2),
        .PROFILE_ZERO_CODE(12'd0), .CH1_POLARITY_NEGATIVE(0), .CH2_POLARITY_NEGATIVE(0))
        twos_pos (.ACLK(ACLK), .local_resetn(local_resetn), .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence), .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(twos_pos_valid), .normalized_sequence(twos_pos_sequence),
        .normalized_ch1(twos_pos_ch1), .normalized_ch2(twos_pos_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd2),
        .PROFILE_ZERO_CODE(12'd0), .CH1_POLARITY_NEGATIVE(1), .CH2_POLARITY_NEGATIVE(1))
        twos_rev (.ACLK(ACLK), .local_resetn(local_resetn), .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence), .raw_ch1(raw_ch1), .raw_ch2(raw_ch2),
        .normalized_valid(twos_rev_valid), .normalized_sequence(twos_rev_sequence),
        .normalized_ch1(twos_rev_ch1), .normalized_ch2(twos_rev_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    integer previous_valid;
    integer previous_sequence;
    integer previous_ch1;
    integer previous_ch2;
    integer input_count;
    integer output_count;
    integer cycle_count;
    integer random_reset_count;
    integer failures;
    integer i;
    integer seed;
    integer value1;
    integer value2;

    function integer unsigned_value;
        input integer raw;
        input integer zero;
        input integer negative;
        begin
            unsigned_value = negative ? (zero - raw) : (raw - zero);
        end
    endfunction

    function integer twos_value;
        input integer raw;
        input integer negative;
        integer decoded;
        begin
            decoded = (raw >= 2048) ? (raw - 4096) : raw;
            twos_value = negative ? -decoded : decoded;
        end
    endfunction

    task automatic check_value;
        input [8*48-1:0] label;
        input integer actual_valid;
        input integer actual_sequence;
        input integer actual_ch1;
        input integer actual_ch2;
        input integer expected_valid;
        input integer expected_sequence;
        input integer expected_ch1;
        input integer expected_ch2;
        begin
            if (actual_valid !== expected_valid) begin
                $display("FAIL %0s valid actual=%0d expected=%0d", label, actual_valid, expected_valid);
                failures = failures + 1;
            end
            if (expected_valid && actual_valid) begin
                if (actual_sequence !== expected_sequence || actual_ch1 !== expected_ch1 || actual_ch2 !== expected_ch2) begin
                    $display("FAIL %0s transaction actual=(%0d,%0d,%0d) expected=(%0d,%0d,%0d)",
                        label, actual_sequence, actual_ch1, actual_ch2,
                        expected_sequence, expected_ch1, expected_ch2);
                    failures = failures + 1;
                end
            end
        end
    endtask

    task automatic check_cycle_outputs;
        integer expected_u_mid_pos_ch1;
        integer expected_u_mid_pos_ch2;
        integer expected_u_mid_rev_ch1;
        integer expected_u_mid_rev_ch2;
        integer expected_zero0_ch1;
        integer expected_zero0_ch2;
        integer expected_zero1_ch1;
        integer expected_zero1_ch2;
        integer expected_zero2047_ch1;
        integer expected_zero2047_ch2;
        integer expected_zero4094_ch1;
        integer expected_zero4094_ch2;
        integer expected_zero4095_ch1;
        integer expected_zero4095_ch2;
        integer expected_twos_pos_ch1;
        integer expected_twos_pos_ch2;
        integer expected_twos_rev_ch1;
        integer expected_twos_rev_ch2;
        begin
            expected_u_mid_pos_ch1 = unsigned_value(previous_ch1, 2048, 0);
            expected_u_mid_pos_ch2 = unsigned_value(previous_ch2, 2048, 0);
            expected_u_mid_rev_ch1 = unsigned_value(previous_ch1, 2048, 0);
            expected_u_mid_rev_ch2 = unsigned_value(previous_ch2, 2048, 1);
            expected_zero0_ch1 = unsigned_value(previous_ch1, 0, 0);
            expected_zero0_ch2 = unsigned_value(previous_ch2, 0, 1);
            expected_zero1_ch1 = unsigned_value(previous_ch1, 1, 0);
            expected_zero1_ch2 = unsigned_value(previous_ch2, 1, 1);
            expected_zero2047_ch1 = unsigned_value(previous_ch1, 2047, 0);
            expected_zero2047_ch2 = unsigned_value(previous_ch2, 2047, 1);
            expected_zero4094_ch1 = unsigned_value(previous_ch1, 4094, 0);
            expected_zero4094_ch2 = unsigned_value(previous_ch2, 4094, 1);
            expected_zero4095_ch1 = unsigned_value(previous_ch1, 4095, 0);
            expected_zero4095_ch2 = unsigned_value(previous_ch2, 4095, 1);
            expected_twos_pos_ch1 = twos_value(previous_ch1, 0);
            expected_twos_pos_ch2 = twos_value(previous_ch2, 0);
            expected_twos_rev_ch1 = twos_value(previous_ch1, 1);
            expected_twos_rev_ch2 = twos_value(previous_ch2, 1);

            check_value("unconfigured", u_valid, u_sequence, $signed(u_ch1), $signed(u_ch2),
                0, 0, 0, 0);
            check_value("u_mid_pos", u_mid_pos_valid, u_mid_pos_sequence, $signed(u_mid_pos_ch1), $signed(u_mid_pos_ch2),
                previous_valid, previous_sequence, expected_u_mid_pos_ch1, expected_u_mid_pos_ch2);
            check_value("u_mid_rev", u_mid_rev_valid, u_mid_rev_sequence, $signed(u_mid_rev_ch1), $signed(u_mid_rev_ch2),
                previous_valid, previous_sequence, expected_u_mid_rev_ch1, expected_u_mid_rev_ch2);
            check_value("u_zero_0", u_zero_0_valid, u_zero_0_sequence, $signed(u_zero_0_ch1), $signed(u_zero_0_ch2),
                previous_valid, previous_sequence, expected_zero0_ch1, expected_zero0_ch2);
            check_value("u_zero_1", u_zero_1_valid, u_zero_1_sequence, $signed(u_zero_1_ch1), $signed(u_zero_1_ch2),
                previous_valid, previous_sequence, expected_zero1_ch1, expected_zero1_ch2);
            check_value("u_zero_2047", u_zero_2047_valid, u_zero_2047_sequence, $signed(u_zero_2047_ch1), $signed(u_zero_2047_ch2),
                previous_valid, previous_sequence, expected_zero2047_ch1, expected_zero2047_ch2);
            check_value("u_zero_4094", u_zero_4094_valid, u_zero_4094_sequence, $signed(u_zero_4094_ch1), $signed(u_zero_4094_ch2),
                previous_valid, previous_sequence, expected_zero4094_ch1, expected_zero4094_ch2);
            check_value("u_zero_4095", u_zero_4095_valid, u_zero_4095_sequence, $signed(u_zero_4095_ch1), $signed(u_zero_4095_ch2),
                previous_valid, previous_sequence, expected_zero4095_ch1, expected_zero4095_ch2);
            check_value("twos_pos", twos_pos_valid, twos_pos_sequence, $signed(twos_pos_ch1), $signed(twos_pos_ch2),
                previous_valid, previous_sequence, expected_twos_pos_ch1, expected_twos_pos_ch2);
            check_value("twos_rev", twos_rev_valid, twos_rev_sequence, $signed(twos_rev_ch1), $signed(twos_rev_ch2),
                previous_valid, previous_sequence, expected_twos_rev_ch1, expected_twos_rev_ch2);
            if (previous_valid)
                output_count = output_count + 1;
        end
    endtask

    task automatic clock_cycle;
        input integer current_valid;
        input integer current_sequence;
        input integer current_ch1;
        input integer current_ch2;
        begin
            @(negedge ACLK);
            raw_delivery_valid = current_valid;
            raw_sequence = current_sequence;
            raw_ch1 = current_ch1;
            raw_ch2 = current_ch2;
            // The raw delivery is an ACLK-domain event sampled on this edge;
            // the normalizer's registered stage publishes its result after
            // the same edge.
            previous_valid = current_valid;
            previous_sequence = current_sequence;
            previous_ch1 = current_ch1;
            previous_ch2 = current_ch2;
            @(posedge ACLK);
            #1;
            check_cycle_outputs();
            if (current_valid)
                input_count = input_count + 1;
            cycle_count = cycle_count + 1;
        end
    endtask

    task automatic check_profile_status;
        begin
            if (u_configured !== 1'b0 || u_profile_valid !== 1'b0 ||
                u_encoding_valid !== 1'b0 || u_zero_valid !== 1'b0 ||
                u_polarity_valid !== 1'b1) begin
                $display("FAIL unconfigured profile status"); failures = failures + 1;
            end
            if (u_mid_pos_configured !== 1'b1 || u_mid_pos_profile_valid !== 1'b1 ||
                u_mid_pos_encoding_valid !== 1'b1 || u_mid_pos_zero_valid !== 1'b1 ||
                u_mid_pos_polarity_valid !== 1'b1) begin
                $display("FAIL configured profile status"); failures = failures + 1;
            end
        end
    endtask

    task automatic random_reset_point;
        begin
            @(negedge ACLK);
            raw_delivery_valid = 1'b0;
            local_resetn = 1'b0;
            previous_valid = 0;
            @(posedge ACLK);
            #1;
            if (u_valid || u_mid_pos_valid || twos_pos_valid || twos_rev_valid) begin
                $display("FAIL randomized reset did not suppress valid");
                failures = failures + 1;
            end
            @(negedge ACLK);
            local_resetn = 1'b1;
            raw_sequence = 0;
            raw_ch1 = 0;
            raw_ch2 = 0;
            previous_sequence = 0;
            previous_ch1 = 0;
            previous_ch2 = 0;
            @(posedge ACLK);
            #1;
            check_cycle_outputs();
            random_reset_count = random_reset_count + 1;
        end
    endtask

    initial begin
        failures = 0;
        input_count = 0;
        output_count = 0;
        cycle_count = 0;
        random_reset_count = 0;
        previous_valid = 0;
        previous_sequence = 0;
        previous_ch1 = 0;
        previous_ch2 = 0;
        #1;
        check_profile_status();

        // Reset before traffic and verify no output or stale payload.
        repeat (3) @(posedge ACLK);
        #1;
        if (u_valid || u_mid_pos_valid || twos_rev_valid || u_sequence !== 0 || $signed(u_ch1) !== 0) begin
            $display("FAIL reset state"); failures = failures + 1;
        end
        local_resetn = 1'b1;
        clock_cycle(0, 0, 0, 0);

        // Directed unsigned boundaries, including repeated payloads and
        // channel-asymmetric values.
        clock_cycle(1, 1, 0, 4095);
        clock_cycle(1, 2, 4095, 0);
        clock_cycle(1, 3, 2047, 2048);
        clock_cycle(1, 4, 2048, 2049);
        clock_cycle(1, 5, 2049, 2048);
        clock_cycle(1, 6, 2048, 2048);
        clock_cycle(1, 7, 2048, 2048);
        clock_cycle(0, 8, 0, 0);
        clock_cycle(1, 9, 4095, 4095);

        // Exhaustive raw-domain arithmetic for all required zero codes and
        // both channel polarity directions.
        for (i = 0; i < 4096; i = i + 1)
            clock_cycle(1, 10000 + i, i, 4095 - i);
        // Two's-complement sign transition and every raw code.
        for (i = 0; i < 4096; i = i + 1)
            clock_cycle(1, 20000 + i, i, (i * 37) & 12'hfff);

        // Reset with the pipeline occupied, then prove the first released
        // transaction appears exactly once.
        clock_cycle(1, 30000, 1234, 2345);
        @(negedge ACLK);
        raw_delivery_valid = 1'b0;
        local_resetn = 1'b0;
        @(posedge ACLK);
        #1;
        if (u_valid || u_mid_pos_valid || twos_rev_valid) begin
            $display("FAIL reset did not flush pending valid"); failures = failures + 1;
        end
        repeat (2) @(posedge ACLK);
        #1;
        local_resetn = 1'b1;
        previous_valid = 0;
        clock_cycle(1, 31000, 2049, 2047);
        clock_cycle(0, 31001, 0, 0);
        clock_cycle(0, 31002, 0, 0);

        // Deterministic randomized valid traffic with repeated payloads and
        // asymmetric channels.  A one-stage scoreboard proves II=1/no drop.
        seed = 32'h13579bdf;
        for (i = 0; i < 1200; i = i + 1) begin
            seed = (seed * 1103515245 + 12345) & 32'h7fffffff;
            value1 = (seed >> 4) & 12'hfff;
            seed = (seed * 1103515245 + 12345) & 32'h7fffffff;
            value2 = (seed >> 7) & 12'hfff;
            clock_cycle((seed & 3) != 0, 40000 + i, value1, value2);
            if (i == 137 || i == 733 || i == 1049)
                random_reset_point();
        end
        clock_cycle(0, 50000, 0, 0);
        clock_cycle(0, 50001, 0, 0);

        if (failures != 0) begin
            $display("STAGE2F_DIGITAL_NORMALIZATION=FAIL failures=%0d", failures);
            $finish(1);
        end
        $display("STAGE2F_DIRECTED=PASS");
        $display("STAGE2F_EXHAUSTIVE_ARITHMETIC=PASS_4096_CODES_X_REQUIRED_ZERO_CODES");
        $display("STAGE2F_RANDOM_TRANSACTIONS=PASS_1200_CYCLES");
        $display("STAGE2F_RANDOM_RESET_POINTS=PASS_%0d", random_reset_count);
        $display("STAGE2F_RESET=PASS");
        $display("STAGE2F_ALIGNMENT=PASS_SEQUENCE_CH1_CH2");
        $display("STAGE2F_NO_DROP=PASS_INPUT_CYCLES=%0d_OUTPUT_CYCLES=%0d", input_count, output_count);
        $display("STAGE2F_DIGITAL_NORMALIZATION=PASS");
        $finish(0);
    end
endmodule
