`timescale 1ns/1ps

module tb_stage2i_b2_ready_aware_stimulus;
    reg aclk = 1'b0;
    reg adc_src_clk = 1'b0;
    reg aclk_aresetn = 1'b0;
    reg adc_src_aresetn = 1'b0;
    reg [31:0] control_word_aclk = 32'd0;
    reg dst_ready = 1'b1;

    wire [31:0] status_word_aclk;
    wire sample_valid;
    wire sample_ready;
    wire [11:0] sample_ch1;
    wire [11:0] sample_ch2;
    wire producer_active;
    wire [6:0] producer_remaining;
    wire producer_accept;
    wire command_pending_src;
    wire dst_sample_valid;
    wire [11:0] dst_sample_ch1;
    wire [11:0] dst_sample_ch2;
    wire [31:0] dst_sample_sequence;

    integer accepted_count = 0;
    integer delivered_count = 0;
    integer expected_count = 0;
    integer failures = 0;
    integer accepted_before_zero = 0;
    integer timeout;
    reg command_epoch = 1'b0;
    reg saw_real_fifo_stall = 1'b0;
    reg stall_active = 1'b0;
    reg [23:0] stalled_payload = 24'd0;
    reg [11:0] expected_ch1 [0:255];
    reg [11:0] expected_ch2 [0:255];

    always #5 aclk = ~aclk;
    always #4 adc_src_clk = ~adc_src_clk;

    stage2i_b2_ready_aware_stimulus dut (
        .aclk(aclk),
        .aclk_aresetn(aclk_aresetn),
        .adc_src_clk(adc_src_clk),
        .adc_src_aresetn(adc_src_aresetn),
        .control_word_aclk(control_word_aclk),
        .status_word_aclk(status_word_aclk),
        .sample_valid(sample_valid),
        .sample_ready(sample_ready),
        .sample_ch1(sample_ch1),
        .sample_ch2(sample_ch2),
        .producer_active(producer_active),
        .producer_remaining(producer_remaining),
        .producer_accept(producer_accept),
        .command_pending_src(command_pending_src)
    );

    stage2g_adc_sample_cdc_bridge #(
        .DATA_WIDTH(12),
        .FIFO_ADDR_WIDTH(3),
        .SEQUENCE_WIDTH(32),
        .COUNTER_WIDTH(32)
    ) production_bridge (
        .src_clk(adc_src_clk),
        .src_rst_n(adc_src_aresetn),
        .src_sample_valid(sample_valid),
        .src_sample_ready(sample_ready),
        .src_sample_ch1(sample_ch1),
        .src_sample_ch2(sample_ch2),
        .dst_clk(aclk),
        .dst_rst_n(aclk_aresetn),
        .dst_ready(dst_ready),
        .dst_sample_valid(dst_sample_valid),
        .dst_sample_ch1(dst_sample_ch1),
        .dst_sample_ch2(dst_sample_ch2),
        .dst_sample_sequence(dst_sample_sequence),
        .dst_sample_integrity_clean(),
        .fifo_underflow_attempt(),
        .source_accept_count_gray(),
        .backpressure_cycle_count_gray(),
        .source_protocol_violation_count_gray(),
        .source_drop_count_gray(),
        .fifo_overflow_attempt_count_gray(),
        .counter_saturation_event_count_gray(),
        .last_source_sequence_gray()
    );

    task automatic fail(input [8*160-1:0] message);
        begin
            $display("FAIL %0s", message);
            failures = failures + 1;
        end
    endtask

    task automatic append_expected(
        input [11:0] ch1,
        input [11:0] ch2,
        input integer count
    );
        integer index;
        begin
            for (index = 0; index < count; index = index + 1) begin
                expected_ch1[expected_count] = ch1;
                expected_ch2[expected_count] = ch2;
                expected_count = expected_count + 1;
            end
        end
    endtask

    task automatic issue_command(
        input [11:0] ch1,
        input [11:0] ch2,
        input [6:0] count
    );
        begin
            @(negedge aclk);
            command_epoch = ~command_epoch;
            control_word_aclk = {command_epoch, count, ch2, ch1};
            timeout = 0;
            while (status_word_aclk[0] !== command_epoch && timeout < 200) begin
                @(posedge aclk);
                timeout = timeout + 1;
            end
            if (timeout >= 200)
                fail("command acknowledgment timeout");
        end
    endtask

    task automatic wait_for_counts(
        input integer accepted_target,
        input integer delivered_target
    );
        begin
            timeout = 0;
            while ((accepted_count < accepted_target ||
                    delivered_count < delivered_target) && timeout < 4000) begin
                @(posedge aclk);
                timeout = timeout + 1;
            end
            if (timeout >= 4000)
                fail("accept/delivery count timeout");
        end
    endtask

    always @(posedge adc_src_clk) begin
        if (adc_src_aresetn) begin
            if (sample_valid && sample_ready) begin
                if (accepted_count >= expected_count) begin
                    fail("unexpected source acceptance");
                end else if (sample_ch1 !== expected_ch1[accepted_count] ||
                             sample_ch2 !== expected_ch2[accepted_count]) begin
                    fail("command CDC changed source payload");
                end
                accepted_count = accepted_count + 1;
            end

            if (sample_valid && !sample_ready) begin
                saw_real_fifo_stall = 1'b1;
                if (stall_active && {sample_ch1, sample_ch2} !== stalled_payload)
                    fail("payload changed while valid and not ready");
                stalled_payload = {sample_ch1, sample_ch2};
                stall_active = 1'b1;
            end else begin
                stall_active = 1'b0;
            end

            if (producer_accept !== (sample_valid && sample_ready))
                fail("producer_accept is not the accepted transaction pulse");
        end
    end

    always @(posedge aclk) begin
        if (aclk_aresetn && dst_sample_valid) begin
            if (delivered_count >= expected_count) begin
                fail("unexpected destination delivery");
            end else if (dst_sample_ch1 !== expected_ch1[delivered_count] ||
                         dst_sample_ch2 !== expected_ch2[delivered_count]) begin
                fail("production FIFO changed payload or ordering");
            end
            if (dst_sample_sequence !== delivered_count[31:0])
                fail("destination sequence is not exact");
            delivered_count = delivered_count + 1;
        end
    end

    initial begin
        repeat (6) @(posedge aclk);
        aclk_aresetn = 1'b1;
        repeat (2) @(posedge adc_src_clk);
        adc_src_aresetn = 1'b1;
        repeat (8) @(posedge aclk);

        if (sample_valid !== 1'b0 || producer_active !== 1'b0 ||
            producer_remaining !== 7'd0 || status_word_aclk[31:24] !== 8'hB2)
            fail("reset or profile status is not deterministic");

        append_expected(12'h123, 12'hABC, 1);
        issue_command(12'h123, 12'hABC, 7'd1);
        wait_for_counts(1, 1);

        // Queue a repeated command while the first long burst is active.
        append_expected(12'h456, 12'h789, 96);
        issue_command(12'h456, 12'h789, 7'd96);
        append_expected(12'h00F, 12'hF00, 5);
        issue_command(12'h00F, 12'hF00, 7'd5);
        wait_for_counts(102, 102);

        // Zero count is a defined acknowledged no-op.
        accepted_before_zero = accepted_count;
        issue_command(12'hAAA, 12'h555, 7'd0);
        repeat (30) @(posedge adc_src_clk);
        if (accepted_count != accepted_before_zero || sample_valid ||
            producer_active || producer_remaining != 0)
            fail("zero burst generated a transaction");

        // Holding the real destination consumer inactive fills the production
        // FIFO, deasserts its actual source ready, and then resumes legally.
        @(negedge aclk);
        dst_ready = 1'b0;
        append_expected(12'h321, 12'h654, 20);
        issue_command(12'h321, 12'h654, 7'd20);
        repeat (80) @(posedge adc_src_clk);
        if (!saw_real_fifo_stall)
            fail("real production FIFO backpressure was not reached");
        if (accepted_count >= 122)
            fail("producer did not stop accepting while FIFO was full");
        @(negedge aclk);
        dst_ready = 1'b1;
        wait_for_counts(122, 122);

        repeat (40) @(posedge adc_src_clk);
        if (accepted_count != 122 || delivered_count != 122)
            fail("one command produced duplicate acceptance or delivery");
        repeat (8) @(posedge aclk);
        if (status_word_aclk[18:11] !== 8'd122)
            fail("synchronized accepted-count status is incoherent");
        if (status_word_aclk[3] !== 1'b0)
            fail("legal commands raised overwrite error");
        if (command_pending_src || status_word_aclk[2] ||
            producer_active || sample_valid)
            fail("producer did not return to deterministic idle");

        if (failures != 0) begin
            $display("STAGE2I_B2_TEST_PRODUCER_VERIFICATION=FAIL_%0d", failures);
            $fatal(1);
        end
        $display("TEST_PRODUCER_RESET=PASS");
        $display("TEST_PRODUCER_STALL_BEHAVIOR=PASS");
        $display("TEST_PRODUCER_EXACT_ACCEPT_COUNT=PASS");
        $display("TEST_PRODUCER_REPEATED_COMMAND=PASS");
        $display("TEST_PRODUCER_ZERO_BURST=PASS");
        $display("COMMAND_CONFIG_CDC_INTEGRITY=PASS");
        $display("BACKPRESSURE_INDUCTION_METHOD=REAL_PRODUCTION_ASYNC_FIFO_FILL");
        $display("STAGE2I_B2_TEST_PRODUCER_VERIFICATION=PASS");
        $finish;
    end
endmodule
