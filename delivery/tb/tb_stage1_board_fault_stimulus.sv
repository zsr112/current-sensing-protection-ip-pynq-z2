`timescale 1ns/1ps
`include "fault_defs.vh"

module tb_stage1_board_fault_stimulus;
    localparam [23:0] GPIO_SAFE = {12'd1024, 12'd1024};
    localparam [23:0] GPIO_CH1_OC = {12'd3000, 12'd3001};
    localparam [23:0] GPIO_CH2_OC = {12'd3001, 12'd3000};
    localparam [23:0] GPIO_DIFF = {12'd1225, 12'd1024};

    localparam [7:0] REG_CTRL       = 8'h00;
    localparam [7:0] REG_STATUS     = 8'h04;
    localparam [7:0] REG_FAULT_CODE = 8'h08;
    localparam [7:0] REG_I_CH1      = 8'h0C;
    localparam [7:0] REG_I_CH2      = 8'h10;
    localparam [7:0] REG_TH_OC1     = 8'h14;
    localparam [7:0] REG_TH_OC2     = 8'h18;
    localparam [7:0] REG_TH_DIFF    = 8'h1C;
    localparam [7:0] REG_PWM_PERIOD = 8'h20;
    localparam [7:0] REG_PWM_DUTY   = 8'h24;

    reg clk;
    reg rst_n;
    reg sample_valid;
    reg wr_en;
    reg rd_en;
    reg [7:0] addr;
    reg [31:0] wdata;
    wire [31:0] rdata;
    reg [23:0] gpio_data;

    wire pwm_raw;
    wire pwm_out;
    wire fault_valid;
    wire fault_latched;
    wire [7:0] fault_code;
    wire [7:0] fault_code_latched;
    wire [3:0] fsm_state;

    integer failures;

    protection_ip_top_reg_controlled dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .addr(addr),
        .wdata(wdata),
        .rdata(rdata),
        .i_ch1(gpio_data[11:0]),
        .i_ch2(gpio_data[23:12]),
        .pwm_raw(pwm_raw),
        .pwm_out(pwm_out),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code(fault_code),
        .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state)
    );

    always #5 clk = ~clk;

    task wait_cycles;
        input integer count;
        integer index;
        begin
            for (index = 0; index < count; index = index + 1)
                @(posedge clk);
            #1;
        end
    endtask

    task reg_write;
        input [7:0] write_addr;
        input [31:0] write_data;
        begin
            @(negedge clk);
            addr = write_addr;
            wdata = write_data;
            wr_en = 1'b1;
            @(negedge clk);
            wr_en = 1'b0;
            wdata = 32'd0;
        end
    endtask

    task expect_reg;
        input [8*64-1:0] label_text;
        input [7:0] read_addr;
        input [31:0] expected;
        begin
            addr = read_addr;
            #1;
            if (rdata !== expected) begin
                $display("FAIL %0s: expected 0x%08h got 0x%08h",
                         label_text, expected, rdata);
                failures = failures + 1;
            end
        end
    endtask

    task expect_signal;
        input [8*64-1:0] label_text;
        input actual;
        input expected;
        begin
            if (actual !== expected) begin
                $display("FAIL %0s: expected %0b got %0b",
                         label_text, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task observe_pwm_passthrough;
        input [8*64-1:0] label_text;
        integer index;
        reg saw_low;
        reg saw_high;
        begin
            saw_low = 1'b0;
            saw_high = 1'b0;
            for (index = 0; index < 32; index = index + 1) begin
                @(posedge clk);
                #1;
                if (pwm_out !== pwm_raw) begin
                    $display("FAIL %0s: pwm_out=%0b pwm_raw=%0b",
                             label_text, pwm_out, pwm_raw);
                    failures = failures + 1;
                end
                saw_low = saw_low | ~pwm_raw;
                saw_high = saw_high | pwm_raw;
            end
            if (!(saw_low && saw_high)) begin
                $display("FAIL %0s: PWM did not show both levels", label_text);
                failures = failures + 1;
            end
        end
    endtask

    task observe_pwm_inhibited;
        input [8*64-1:0] label_text;
        integer index;
        reg saw_raw_high;
        begin
            saw_raw_high = 1'b0;
            for (index = 0; index < 32; index = index + 1) begin
                @(posedge clk);
                #1;
                saw_raw_high = saw_raw_high | pwm_raw;
                if (pwm_out !== 1'b0) begin
                    $display("FAIL %0s: pwm_out escaped safe-low", label_text);
                    failures = failures + 1;
                end
            end
            if (!saw_raw_high) begin
                $display("FAIL %0s: pwm_raw never went high", label_text);
                failures = failures + 1;
            end
        end
    endtask

    task clear_and_expect_recovery;
        input [8*64-1:0] label_text;
        begin
            reg_write(REG_CTRL, 32'h0000_0002);
            wait_cycles(12);
            expect_reg(label_text, REG_STATUS, 32'h0000_0000);
            expect_reg("fault code cleared", REG_FAULT_CODE, 32'h0000_0000);
            expect_reg("clear pulse reads zero", REG_CTRL, 32'h0000_0000);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        addr = 8'd0;
        wdata = 32'd0;
        gpio_data = GPIO_SAFE;
        failures = 0;

        wait_cycles(3);
        rst_n = 1'b1;
        wait_cycles(4);

        // Exact Scheme-A board word path:
        // GPIO[11:0] -> i_ch1 and GPIO[23:12] -> i_ch2.
        expect_reg("safe CH1 monitor", REG_I_CH1, 32'd1024);
        expect_reg("safe CH2 monitor", REG_I_CH2, 32'd1024);
        expect_reg("reset CTRL", REG_CTRL, 32'd0);
        expect_reg("healthy reset status", REG_STATUS, 32'd0);

        reg_write(REG_TH_OC1, 32'd3000);
        reg_write(REG_TH_OC2, 32'd3000);
        reg_write(REG_TH_DIFF, 32'd200);
        reg_write(REG_PWM_PERIOD, 32'd8);
        reg_write(REG_PWM_DUTY, 32'd4);

        // Negative: clear-only and repeated clear do not create a fault.
        reg_write(REG_CTRL, 32'h0000_0002);
        wait_cycles(10);
        expect_reg("clear-only remains healthy", REG_STATUS, 32'd0);
        reg_write(REG_CTRL, 32'h0000_0002);
        reg_write(REG_CTRL, 32'h0000_0002);
        wait_cycles(10);
        expect_reg("repeated clear remains healthy", REG_STATUS, 32'd0);

        // S0: healthy baseline and normal PWM pass-through.
        reg_write(REG_CTRL, 32'h0000_0001);
        observe_pwm_passthrough("S0 normal PWM pass-through");

        // S1: CH1-only overcurrent. Companion channel is exactly at threshold,
        // keeping differential below the configured limit.
        gpio_data = GPIO_CH1_OC;
        wait_cycles(5);
        expect_reg("S1 CH1 monitor", REG_I_CH1, 32'd3001);
        expect_reg("S1 CH2 monitor", REG_I_CH2, 32'd3000);
        expect_reg("S1 fault asserted", REG_STATUS, 32'h0000_0003);
        expect_reg("S1 overcurrent code", REG_FAULT_CODE,
                   {24'd0, `FAULT_OVERCURRENT});
        observe_pwm_inhibited("S1 PWM gate");

        // S2: clear while the source is live must not recover.
        reg_write(REG_CTRL, 32'h0000_0002);
        wait_cycles(10);
        expect_reg("S2 live clear rejected", REG_STATUS, 32'h0000_0003);
        expect_reg("S2 code retained", REG_FAULT_CODE,
                   {24'd0, `FAULT_OVERCURRENT});

        // S3: returning the existing GPIO source to its safe/default word is
        // the Scheme-A test-disable operation. Removal alone cannot clear.
        gpio_data = GPIO_SAFE;
        wait_cycles(5);
        expect_reg("S3 source removed latch retained", REG_STATUS,
                   32'h0000_0002);
        expect_reg("S3 code retained", REG_FAULT_CODE,
                   {24'd0, `FAULT_OVERCURRENT});

        // S4: clear after removal recovers, then PWM is separately enabled.
        clear_and_expect_recovery("S4 clear after removal");
        reg_write(REG_CTRL, 32'h0000_0001);
        observe_pwm_passthrough("S4 post-recovery PWM");
        reg_write(REG_CTRL, 32'h0000_0000);

        // S5: CH2-only overcurrent.
        reg_write(REG_CTRL, 32'h0000_0001);
        gpio_data = GPIO_CH2_OC;
        wait_cycles(5);
        expect_reg("S5 CH2 fault asserted", REG_STATUS, 32'h0000_0003);
        expect_reg("S5 CH2 overcurrent code", REG_FAULT_CODE,
                   {24'd0, `FAULT_OVERCURRENT});
        observe_pwm_inhibited("S5 PWM gate");
        gpio_data = GPIO_SAFE;
        wait_cycles(5);
        expect_reg("S5 removal alone retained latch", REG_STATUS,
                   32'h0000_0002);
        clear_and_expect_recovery("S5 recovery");

        // S6: differential-only fault with both channels below OC threshold.
        reg_write(REG_CTRL, 32'h0000_0001);
        gpio_data = GPIO_DIFF;
        wait_cycles(5);
        expect_reg("S6 differential fault asserted", REG_STATUS,
                   32'h0000_0003);
        expect_reg("S6 differential code", REG_FAULT_CODE,
                   {24'd0, `FAULT_SENSOR_MISMATCH});
        observe_pwm_inhibited("S6 PWM gate");
        gpio_data = GPIO_SAFE;
        wait_cycles(5);
        expect_reg("S6 removal alone retained latch", REG_STATUS,
                   32'h0000_0002);
        clear_and_expect_recovery("S6 recovery");

        // S7 is intentionally unsupported by the accepted artifact:
        // sample_valid is fixed low, so no sensor-health claim is made.
        expect_signal("sample_valid fixed low", sample_valid, 1'b0);

        // S8: return the existing input provider to its reviewed normal word.
        gpio_data = GPIO_SAFE;
        reg_write(REG_CTRL, 32'h0000_0000);
        wait_cycles(5);
        expect_reg("S8 CH1 restored", REG_I_CH1, 32'd1024);
        expect_reg("S8 CH2 restored", REG_I_CH2, 32'd1024);
        expect_reg("S8 normal status", REG_STATUS, 32'd0);
        expect_reg("S8 normal code", REG_FAULT_CODE, 32'd0);
        expect_reg("S8 PWM disabled", REG_CTRL, 32'd0);

        // Reset with the provider at its reviewed safe word returns all
        // protection/control state to the normal path.
        gpio_data = GPIO_CH1_OC;
        wait_cycles(5);
        expect_reg("pre-reset fault", REG_STATUS, 32'h0000_0003);
        rst_n = 1'b0;
        gpio_data = GPIO_SAFE;
        wait_cycles(3);
        rst_n = 1'b1;
        wait_cycles(5);
        expect_reg("post-reset CTRL", REG_CTRL, 32'd0);
        expect_reg("post-reset status", REG_STATUS, 32'd0);
        expect_reg("post-reset code", REG_FAULT_CODE, 32'd0);
        expect_signal("post-reset pwm_out safe-low", pwm_out, 1'b0);

        if (failures == 0) begin
            $display("STAGE1 BOARD FAULT STIMULUS TESTS PASSED");
            $finish;
        end

        $fatal(1, "STAGE1 BOARD FAULT STIMULUS TESTS FAILED: %0d", failures);
    end
endmodule
