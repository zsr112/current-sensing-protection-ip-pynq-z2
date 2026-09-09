`timescale 1ns/1ps

// Connected-mutation oracle.  A mutant is considered killed only when this
// transaction-level checker observes a real semantic mismatch.
module tb_stage2f_mutation;
    reg ACLK = 1'b0;
    reg local_resetn = 1'b0;
    reg raw_delivery_valid = 1'b0;
    reg [31:0] raw_sequence = 0;
    reg [11:0] raw_ch1 = 0;
    reg [11:0] raw_ch2 = 0;
    always #5 ACLK = ~ACLK;

    wire u_valid, t_valid, tr_valid, unconfigured_valid;
    wire [31:0] u_sequence, t_sequence, tr_sequence, unconfigured_sequence;
    wire signed [12:0] u_ch1, u_ch2, t_ch1, t_ch2, tr_ch1, tr_ch2;
    wire signed [12:0] unconfigured_ch1, unconfigured_ch2;

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd1),
        .PROFILE_ZERO_CODE(12'd2048), .CH1_POLARITY_NEGATIVE(0),
        .CH2_POLARITY_NEGATIVE(1)) u_unsigned (
        .ACLK(ACLK), .local_resetn(local_resetn),
        .raw_delivery_valid(raw_delivery_valid), .raw_sequence(raw_sequence),
        .raw_ch1(raw_ch1), .raw_ch2(raw_ch2), .normalized_valid(u_valid),
        .normalized_sequence(u_sequence), .normalized_ch1(u_ch1), .normalized_ch2(u_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd2),
        .PROFILE_ZERO_CODE(12'd0), .CH1_POLARITY_NEGATIVE(0),
        .CH2_POLARITY_NEGATIVE(0)) u_twos (
        .ACLK(ACLK), .local_resetn(local_resetn),
        .raw_delivery_valid(raw_delivery_valid), .raw_sequence(raw_sequence),
        .raw_ch1(raw_ch1), .raw_ch2(raw_ch2), .normalized_valid(t_valid),
        .normalized_sequence(t_sequence), .normalized_ch1(t_ch1), .normalized_ch2(t_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer #(.PROFILE_CONFIGURED(1), .PROFILE_ENCODING(2'd2),
        .PROFILE_ZERO_CODE(12'd0), .CH1_POLARITY_NEGATIVE(1),
        .CH2_POLARITY_NEGATIVE(1)) u_twos_reversed (
        .ACLK(ACLK), .local_resetn(local_resetn),
        .raw_delivery_valid(raw_delivery_valid), .raw_sequence(raw_sequence),
        .raw_ch1(raw_ch1), .raw_ch2(raw_ch2), .normalized_valid(tr_valid),
        .normalized_sequence(tr_sequence), .normalized_ch1(tr_ch1), .normalized_ch2(tr_ch2),
        .profile_configured(), .profile_valid(), .profile_encoding_supported(),
        .profile_zero_code_valid(), .profile_polarity_valid());

    adc_sample_code_normalizer unconfigured (
        .ACLK(ACLK), .local_resetn(local_resetn),
        .raw_delivery_valid(raw_delivery_valid), .raw_sequence(raw_sequence),
        .raw_ch1(raw_ch1), .raw_ch2(raw_ch2), .normalized_valid(unconfigured_valid),
        .normalized_sequence(unconfigured_sequence), .normalized_ch1(unconfigured_ch1),
        .normalized_ch2(unconfigured_ch2), .profile_configured(), .profile_valid(),
        .profile_encoding_supported(), .profile_zero_code_valid(),
        .profile_polarity_valid());

    integer failures = 0;
    integer expected_u1, expected_u2, expected_t1, expected_t2;
    integer expected_tr1, expected_tr2;
    integer expected_seq, expected_valid;
    integer raw1_i, raw2_i, seq_i, valid_i;

    function integer unsigned_expected;
        input integer raw;
        input integer negative;
        begin unsigned_expected = negative ? (2048 - raw) : (raw - 2048); end
    endfunction
    function integer twos_expected;
        input integer raw;
        input integer negative;
        integer value;
        begin
            value = (raw >= 2048) ? raw - 4096 : raw;
            twos_expected = negative ? -value : value;
        end
    endfunction

    task automatic check;
        begin
            if (u_valid !== expected_valid || t_valid !== expected_valid ||
                tr_valid !== expected_valid || unconfigured_valid !== 1'b0) begin
                failures = failures + 1;
            end
            if (expected_valid &&
                (u_sequence !== expected_seq || $signed(u_ch1) !== expected_u1 ||
                 $signed(u_ch2) !== expected_u2 || t_sequence !== expected_seq ||
                 $signed(t_ch1) !== expected_t1 || $signed(t_ch2) !== expected_t2 ||
                 tr_sequence !== expected_seq || $signed(tr_ch1) !== expected_tr1 ||
                 $signed(tr_ch2) !== expected_tr2)) begin
                failures = failures + 1;
            end
            if (unconfigured_sequence !== 0 || $signed(unconfigured_ch1) !== 0 ||
                $signed(unconfigured_ch2) !== 0)
                failures = failures + 1;
        end
    endtask

    task automatic drive;
        input integer valid_value;
        input integer sequence_value;
        input integer ch1_value;
        input integer ch2_value;
        begin
            raw1_i = ch1_value; raw2_i = ch2_value; seq_i = sequence_value;
            valid_i = valid_value;
            expected_valid = valid_value;
            expected_seq = sequence_value;
            expected_u1 = unsigned_expected(ch1_value, 0);
            expected_u2 = unsigned_expected(ch2_value, 1);
            expected_t1 = twos_expected(ch1_value, 0);
            expected_t2 = twos_expected(ch2_value, 0);
            expected_tr1 = twos_expected(ch1_value, 1);
            expected_tr2 = twos_expected(ch2_value, 1);
            @(negedge ACLK);
            raw_delivery_valid = valid_value;
            raw_sequence = sequence_value;
            raw_ch1 = ch1_value;
            raw_ch2 = ch2_value;
            @(posedge ACLK); #1;
            check();
        end
    endtask

    initial begin
        repeat (2) @(posedge ACLK);
        local_resetn = 1'b1;
        drive(1, 1, 2049, 2047);
        drive(1, 2, 12'h800, 12'hfff);
        drive(1, 3, 1000, 3000);
        drive(0, 4, 0, 0);
        drive(1, 10, 7, 9);
        drive(1, 11, 7, 9);
        drive(1, 20, 0, 0);

        // A pending transaction must be flushed by reset.
        drive(1, 30, 123, 321);
        @(negedge ACLK);
        local_resetn = 1'b0;
        raw_delivery_valid = 1'b0;
        @(posedge ACLK); #1;
        if (u_valid || t_valid || tr_valid || unconfigured_valid)
            failures = failures + 1;
        repeat (2) @(posedge ACLK);
        local_resetn = 1'b1;
        drive(1, 40, 2049, 2047);
        drive(0, 41, 0, 0);

        if (failures == 0) begin
            $display("MUTATION_SURVIVED=NO_MISMATCH");
            $finish(1);
        end
        $display("MUTATION_DETECTED=PASS failures=%0d", failures);
        $finish(0);
    end
endmodule
