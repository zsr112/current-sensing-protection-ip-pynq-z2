`timescale 1ns/1ps
`include "generated/stage2f_adc_source_profile.svh"
`include "generated/stage2f_reference_vectors.svh"

module tb_stage2f_generated_profile_vectors;
    reg ACLK = 1'b0;
    reg local_resetn = 1'b0;
    reg raw_delivery_valid = 1'b0;
    reg [31:0] raw_sequence = 32'd0;
    reg [11:0] raw_ch1 = 12'd0;
    reg [11:0] raw_ch2 = 12'd0;

    wire normalized_valid;
    wire [31:0] normalized_sequence;
    wire signed [12:0] normalized_ch1;
    wire signed [12:0] normalized_ch2;
    wire profile_configured;
    wire profile_valid;
    wire profile_encoding_supported;
    wire profile_zero_code_valid;
    wire profile_polarity_valid;

    adc_sample_code_normalizer dut (
        .ACLK(ACLK),
        .local_resetn(local_resetn),
        .raw_delivery_valid(raw_delivery_valid),
        .raw_sequence(raw_sequence),
        .raw_ch1(raw_ch1),
        .raw_ch2(raw_ch2),
        .normalized_valid(normalized_valid),
        .normalized_sequence(normalized_sequence),
        .normalized_ch1(normalized_ch1),
        .normalized_ch2(normalized_ch2),
        .profile_configured(profile_configured),
        .profile_valid(profile_valid),
        .profile_encoding_supported(profile_encoding_supported),
        .profile_zero_code_valid(profile_zero_code_valid),
        .profile_polarity_valid(profile_polarity_valid)
    );

    always #5 ACLK = ~ACLK;

    string vector_path;
    integer vectors;
    integer fields;
    integer cycle_value;
    integer reset_value;
    integer valid_value;
    integer sequence_value;
    integer raw_ch1_value;
    integer raw_ch2_value;
    integer expected_valid;
    integer expected_sequence;
    integer expected_ch1;
    integer expected_ch2;
    integer actual_ch1;
    integer actual_ch2;
    integer rows = 0;
    integer failures = 0;

    task automatic fail_row;
        input [8*80-1:0] label;
        begin
            $display("GENERATED PROFILE VECTOR FAIL cycle=%0d label=%0s",
                     cycle_value, label);
            failures = failures + 1;
        end
    endtask

    initial begin
        vector_path = `STAGE2F_REFERENCE_VECTOR_FILE;
        if (`STAGE2F_PROFILE_CONFIGURED !== 1'b1)
            $fatal(1, "generated validation profile is not configured");
        if (`STAGE2F_PROFILE_RAW_WIDTH != 12)
            $fatal(1, "generated profile raw width is not 12");
        if (`STAGE2F_PROFILE_NORMALIZED_WIDTH != 13)
            $fatal(1, "generated profile normalized width is not 13");
        #1;
        if (!profile_configured || !profile_valid ||
            !profile_encoding_supported || !profile_zero_code_valid ||
            !profile_polarity_valid)
            $fatal(1, "generated profile status is invalid");

        vectors = $fopen(vector_path, "r");
        if (vectors == 0)
            $fatal(1, "unable to open vector file: %0s", vector_path);

        while (!$feof(vectors)) begin
            fields = $fscanf(
                vectors, "%d %d %d %d %d %d %d %d %d %d\n",
                cycle_value, reset_value, valid_value, sequence_value,
                raw_ch1_value, raw_ch2_value, expected_valid,
                expected_sequence, expected_ch1, expected_ch2
            );
            if (fields == 10) begin
                @(negedge ACLK);
                local_resetn = reset_value[0];
                raw_delivery_valid = valid_value[0];
                raw_sequence = sequence_value;
                raw_ch1 = raw_ch1_value[11:0];
                raw_ch2 = raw_ch2_value[11:0];
                @(posedge ACLK);
                #1;
                actual_ch1 = $signed(normalized_ch1);
                actual_ch2 = $signed(normalized_ch2);
                if (normalized_valid !== expected_valid[0])
                    fail_row("valid");
                if (normalized_sequence !== expected_sequence[31:0])
                    fail_row("sequence");
                if (actual_ch1 != expected_ch1)
                    fail_row("channel_1");
                if (actual_ch2 != expected_ch2)
                    fail_row("channel_2");
                rows = rows + 1;
            end else if (fields != -1) begin
                $fatal(1, "malformed vector row after cycle %0d", cycle_value);
            end
        end
        $fclose(vectors);
        if (failures != 0)
            $fatal(1, "generated profile vector failures=%0d", failures);
        $display("STAGE2F_GENERATED_PROFILE_IDENTITY=%s",
                 `STAGE2F_PROFILE_IDENTITY);
        $display("STAGE2F_GENERATED_PROFILE_SHA256=%s",
                 `STAGE2F_PROFILE_INPUT_SHA256);
        $display("STAGE2F_GENERATED_PROFILE_RTL=PASS PROFILE=%s ROWS=%0d",
                 `STAGE2F_PROFILE_IDENTITY, rows);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "generated profile vector timeout");
    end
endmodule
