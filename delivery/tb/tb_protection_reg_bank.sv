`timescale 1ns/1ps
`include "protection_register_map.svh"

module tb_protection_reg_bank;
  localparam [7:0] REG_CTRL       = `REG_CTRL;
  localparam [7:0] REG_STATUS     = `REG_STATUS;
  localparam [7:0] REG_FAULT_CODE = `REG_FAULT_CODE;
  localparam [7:0] REG_I_CH1      = `REG_I_CH1;
  localparam [7:0] REG_I_CH2      = `REG_I_CH2;
  localparam [7:0] REG_TH_OC1     = `REG_TH_OC1;
  localparam [7:0] REG_TH_OC2     = `REG_TH_OC2;
  localparam [7:0] REG_TH_DIFF    = `REG_TH_DIFF;
  localparam [7:0] REG_PWM_PERIOD = `REG_PWM_PERIOD;
  localparam [7:0] REG_PWM_DUTY   = `REG_PWM_DUTY;

  reg clk = 0, rst_n = 0, wr_en = 0, rd_en = 0;
  reg [7:0] addr = 0;
  reg [31:0] wr_data = 0;
  wire [31:0] rd_data;
  reg fault_valid_in = 0, fault_latched_in = 0;
  reg [7:0] fault_code_in = 8'h00;
  reg [11:0] i_ch1_mon = 12'd111, i_ch2_mon = 12'd222;
  wire pwm_enable, clear_fault_pulse;
  wire [11:0] th1, th2, thd;
  wire [15:0] period, duty;

  always #5 clk = ~clk;

  protection_reg_bank dut(
    .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .rd_en(rd_en), .addr(addr), .wr_data(wr_data), .rd_data(rd_data),
    .fault_valid(fault_valid_in), .fault_latched(fault_latched_in), .fault_code_latched(fault_code_in),
    .i_ch1_mon(i_ch1_mon), .i_ch2_mon(i_ch2_mon),
    .pwm_enable(pwm_enable), .clear_fault_pulse(clear_fault_pulse),
    .th_oc_ch1(th1), .th_oc_ch2(th2), .th_diff(thd), .pwm_period(period), .pwm_duty(duty)
  );

  task write_reg(input [7:0] a, input [31:0] d);
    begin
      @(negedge clk);
      addr = a;
      wr_data = d;
      rd_en = 1'b0;
      wr_en = 1'b1;
      @(negedge clk);
      wr_en = 1'b0;
    end
  endtask

  task check_read(input string label, input [7:0] a, input [31:0] expected);
    begin
      @(negedge clk);
      addr = a;
      wr_en = 1'b0;
      rd_en = 1'b1;
      #1;
      if (rd_data !== expected)
        $fatal(1, "%s read mismatch at 0x%02h: got 0x%08h expected 0x%08h", label, a, rd_data, expected);
      @(negedge clk);
      rd_en = 1'b0;
    end
  endtask

  task check_comb_read_no_rd_en(input string label, input [7:0] a, input [31:0] expected);
    begin
      @(negedge clk);
      addr = a;
      wr_en = 1'b0;
      rd_en = 1'b0;
      #1;
      if (rd_data !== expected)
        $fatal(1, "%s combinational read mismatch at 0x%02h with rd_en=0: got 0x%08h expected 0x%08h",
               label, a, rd_data, expected);
    end
  endtask

  task check_outputs(input string label, input exp_pwm_enable,
                     input [11:0] exp_th1, input [11:0] exp_th2, input [11:0] exp_thd,
                     input [15:0] exp_period, input [15:0] exp_duty);
    begin
      #1;
      if (pwm_enable !== exp_pwm_enable || th1 !== exp_th1 || th2 !== exp_th2 ||
          thd !== exp_thd || period !== exp_period || duty !== exp_duty) begin
        $fatal(1,
          "%s output mismatch: pwm_enable=%0b th1=%0d th2=%0d thd=%0d period=%0d duty=%0d",
          label, pwm_enable, th1, th2, thd, period, duty);
      end
    end
  endtask

  initial begin
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;

    check_outputs("reset defaults", 1'b0,
                  `TH_OC1_THRESHOLD_CH1_RESET,
                  `TH_OC2_THRESHOLD_CH2_RESET,
                  `TH_DIFF_THRESHOLD_RESET,
                  `PWM_PERIOD_VALUE_RESET,
                  `PWM_DUTY_VALUE_RESET);
    check_read("CTRL reset", REG_CTRL, `REG_CTRL_RESET);
    check_read("STATUS reset", REG_STATUS, `REG_STATUS_RESET);
    check_read("FAULT_CODE reset", REG_FAULT_CODE, `REG_FAULT_CODE_RESET);
    check_read("I_CH1 monitor", REG_I_CH1, 32'd111);
    check_read("I_CH2 monitor", REG_I_CH2, 32'd222);
    check_read("TH_OC1 reset", REG_TH_OC1, `REG_TH_OC1_RESET);
    check_read("TH_OC2 reset", REG_TH_OC2, `REG_TH_OC2_RESET);
    check_read("TH_DIFF reset", REG_TH_DIFF, `REG_TH_DIFF_RESET);
    check_read("PWM_PERIOD reset", REG_PWM_PERIOD, `REG_PWM_PERIOD_RESET);
    check_read("PWM_DUTY reset", REG_PWM_DUTY, `REG_PWM_DUTY_RESET);

    $display("REG_BANK contract: rd_data is combinational decode; rd_en does not gate readback");
    check_comb_read_no_rd_en("CTRL reset with rd_en low", REG_CTRL, `REG_CTRL_RESET);
    check_comb_read_no_rd_en("TH_OC1 reset with rd_en low", REG_TH_OC1, `REG_TH_OC1_RESET);
    check_comb_read_no_rd_en("TH_OC2 reset with rd_en low", REG_TH_OC2, `REG_TH_OC2_RESET);
    check_comb_read_no_rd_en("unknown address with rd_en low", 8'hFC, 32'h0000_0000);

    fault_valid_in = 1'b1;
    fault_latched_in = 1'b1;
    fault_code_in = 8'hA5;
    i_ch1_mon = 12'd333;
    i_ch2_mon = 12'd444;
    check_read("STATUS live inputs", REG_STATUS, 32'h0000_0003);
    check_read("FAULT_CODE live input", REG_FAULT_CODE, 32'h0000_00A5);
    check_read("I_CH1 live input", REG_I_CH1, 32'd333);
    check_read("I_CH2 live input", REG_I_CH2, 32'd444);
    check_comb_read_no_rd_en("STATUS live inputs with rd_en low", REG_STATUS, 32'h0000_0003);
    check_comb_read_no_rd_en("FAULT_CODE live input with rd_en low", REG_FAULT_CODE, 32'h0000_00A5);
    check_comb_read_no_rd_en("I_CH1 live input with rd_en low", REG_I_CH1, 32'd333);
    check_comb_read_no_rd_en("I_CH2 live input with rd_en low", REG_I_CH2, 32'd444);
    fault_valid_in = 1'b0;
    fault_latched_in = 1'b0;
    fault_code_in = 8'h00;
    i_ch1_mon = 12'd111;
    i_ch2_mon = 12'd222;

    write_reg(REG_CTRL, 32'h0000_0001);
    check_outputs("pwm enable write", 1'b1, 12'd3000, 12'd3000, 12'd200, 16'd1000, 16'd500);
    check_read("CTRL pwm_enable readback", REG_CTRL, 32'h0000_0001);

    write_reg(REG_TH_OC1, 32'hFFFF_04D2);
    write_reg(REG_TH_OC2, 32'hFFFF_0567);
    write_reg(REG_TH_DIFF, 32'hFFFF_0055);
    write_reg(REG_PWM_PERIOD, 32'hFFFF_00C8);
    write_reg(REG_PWM_DUTY, 32'hFFFF_0040);
    check_outputs("configured registers", 1'b1, 12'd1234, 12'd1383, 12'd85, 16'd200, 16'd64);
    check_read("TH_OC1 readback", REG_TH_OC1, 32'd1234);
    check_read("TH_OC2 readback", REG_TH_OC2, 32'd1383);
    check_read("TH_DIFF readback", REG_TH_DIFF, 32'd85);
    check_read("PWM_PERIOD readback", REG_PWM_PERIOD, 32'd200);
    check_read("PWM_DUTY readback", REG_PWM_DUTY, 32'd64);
    check_comb_read_no_rd_en("TH_OC1 readback with rd_en low", REG_TH_OC1, 32'd1234);
    check_comb_read_no_rd_en("TH_OC2 readback with rd_en low", REG_TH_OC2, 32'd1383);
    check_comb_read_no_rd_en("TH_DIFF readback with rd_en low", REG_TH_DIFF, 32'd85);
    check_comb_read_no_rd_en("PWM_PERIOD readback with rd_en low", REG_PWM_PERIOD, 32'd200);
    check_comb_read_no_rd_en("PWM_DUTY readback with rd_en low", REG_PWM_DUTY, 32'd64);

    write_reg(REG_CTRL, 32'h0000_0003);
    #1;
    if (pwm_enable !== 1'b1 || clear_fault_pulse !== 1'b1)
      $fatal(1, "CTRL[1] must generate a clear_fault_pulse while preserving CTRL[0]");
    if (rd_data[1] !== 1'b0)
      $fatal(1, "CTRL[1] must read as zero because it is a pulse field");
    @(posedge clk);
    #1;
    if (clear_fault_pulse !== 1'b0)
      $fatal(1, "clear_fault_pulse must self-clear after one clock");

    write_reg(REG_CTRL, 32'h0000_0002);
    #1;
    if (pwm_enable !== 1'b0 || clear_fault_pulse !== 1'b1)
      $fatal(1, "Repeated clear_fault_pulse must not create an invalid state");
    @(posedge clk);
    #1;
    if (clear_fault_pulse !== 1'b0)
      $fatal(1, "Repeated clear_fault_pulse must self-clear after one clock");
    check_read("CTRL after pulse-only write", REG_CTRL, 32'h0000_0000);

    write_reg(8'hFC, 32'hFFFF_FFFF);
    check_outputs("unknown write ignored", 1'b0, 12'd1234, 12'd1383, 12'd85, 16'd200, 16'd64);
    check_read("unknown address reads zero", 8'hFC, 32'h0000_0000);

    write_reg(8'h13, 32'h0000_0BAD);
    check_outputs("adjacent address before TH_OC1 ignored", 1'b0, 12'd1234, 12'd1383, 12'd85, 16'd200, 16'd64);
    check_read("adjacent address before TH_OC1 reads zero", 8'h13, 32'h0000_0000);
    write_reg(8'h15, 32'h0000_0BAD);
    check_outputs("adjacent address after TH_OC1 ignored", 1'b0, 12'd1234, 12'd1383, 12'd85, 16'd200, 16'd64);
    check_read("adjacent address after TH_OC1 reads zero", 8'h15, 32'h0000_0000);
    write_reg(8'h23, 32'h0000_0BAD);
    check_outputs("adjacent address before PWM_DUTY ignored", 1'b0, 12'd1234, 12'd1383, 12'd85, 16'd200, 16'd64);
    check_read("adjacent address before PWM_DUTY reads zero", 8'h23, 32'h0000_0000);
    write_reg(8'h25, 32'h0000_0BAD);
    check_outputs("adjacent address after PWM_DUTY ignored", 1'b0, 12'd1234, 12'd1383, 12'd85, 16'd200, 16'd64);
    check_read("adjacent address after PWM_DUTY reads zero", 8'h25, 32'h0000_0000);

    write_reg(REG_CTRL, 32'hFFFF_FFFD);
    #1;
    if (pwm_enable !== 1'b1 || clear_fault_pulse !== 1'b0)
      $fatal(1, "CTRL reserved bits must not create side effects when bit1 is zero");
    check_read("CTRL ignores reserved bits on readback", REG_CTRL, 32'h0000_0001);

    write_reg(REG_CTRL, 32'hFFFF_FFFC);
    #1;
    if (pwm_enable !== 1'b0 || clear_fault_pulse !== 1'b0)
      $fatal(1, "CTRL reserved bits must not create side effects when control bits are zero");
    check_read("CTRL reserved-only write reads as zero", REG_CTRL, 32'h0000_0000);

    $display("tb_protection_reg_bank PASS");
    $finish;
  end
endmodule
