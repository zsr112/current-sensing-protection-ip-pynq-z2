`timescale 1ns/1ps
`include "fault_defs.vh"

module tb_protection_ip_top_reg_controlled;
  localparam [3:0] ST_NORMAL = 4'd0;
  localparam [3:0] ST_FAULT_LATCHED = 4'd1;
  localparam [3:0] ST_RESET_WAIT = 4'd2;

  localparam REG_CTRL       = 8'h00;
  localparam REG_STATUS     = 8'h04;
  localparam REG_FAULT_CODE = 8'h08;
  localparam REG_I_CH1      = 8'h0C;
  localparam REG_I_CH2      = 8'h10;
  localparam REG_TH_OC1     = 8'h14;
  localparam REG_TH_OC2     = 8'h18;
  localparam REG_TH_DIFF    = 8'h1C;
  localparam REG_PWM_PERIOD = 8'h20;
  localparam REG_PWM_DUTY   = 8'h24;

  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg sample_valid = 1'b0;
  reg wr_en = 1'b0;
  reg rd_en = 1'b0;
  reg [7:0] addr = 8'h00;
  reg [31:0] wdata = 32'h0;
  wire [31:0] rdata;
  reg [11:0] i_ch1 = 12'd500;
  reg [11:0] i_ch2 = 12'd510;

  wire pwm_raw;
  wire pwm_out;
  wire fault_valid;
  wire fault_latched;
  wire [7:0] fault_code;
  wire [7:0] fault_code_latched;
  wire [3:0] fsm_state;

  integer fast_high_count;
  integer fast_rise_count;
  integer slow_high_count;
  integer slow_rise_count;
  integer high_count;
  integer rise_count;
  reg [31:0] rd_value;
  reg target_monitor_armed = 1'b0;
  reg target_monitor_clear = 1'b0;
  reg [31:0] target_monitor_data = 32'h0;
  integer target_write_count;
  integer target_clear_pulse_count;
  integer target_unexpected_write_count;

  always #5 clk = ~clk;

  protection_ip_top_reg_controlled dut (
    .clk(clk),
    .rst_n(rst_n),
    .sample_valid(sample_valid),
    .wr_en(wr_en),
    .rd_en(rd_en),
    .addr(addr),
    .wdata(wdata),
    .rdata(rdata),
    .i_ch1(i_ch1),
    .i_ch2(i_ch2),
    .pwm_raw(pwm_raw),
    .pwm_out(pwm_out),
    .fault_valid(fault_valid),
    .fault_latched(fault_latched),
    .fault_code(fault_code),
    .fault_code_latched(fault_code_latched),
    .fsm_state(fsm_state)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n || target_monitor_clear) begin
      target_write_count <= 0;
      target_clear_pulse_count <= 0;
      target_unexpected_write_count <= 0;
    end else if (target_monitor_armed) begin
      if (wr_en) begin
        if (addr == REG_CTRL && wdata == target_monitor_data)
          target_write_count <= target_write_count + 1;
        else
          target_unexpected_write_count <= target_unexpected_write_count + 1;
      end
      if (dut.u_reg_bank.clear_fault_pulse)
        target_clear_pulse_count <= target_clear_pulse_count + 1;
    end
  end

  task automatic wait_cycles(input integer cycles);
    integer n;
    begin
      for (n = 0; n < cycles; n = n + 1)
        @(posedge clk);
      #1;
    end
  endtask

  task automatic reg_write(input [7:0] a, input [31:0] d);
    begin
      @(negedge clk);
      addr  = a;
      wdata = d;
      wr_en = 1'b1;
      rd_en = 1'b0;
      @(negedge clk);
      wr_en = 1'b0;
      wdata = 32'h0;
    end
  endtask

  task automatic reg_read(input [7:0] a, output [31:0] d);
    begin
      @(negedge clk);
      addr  = a;
      wr_en = 1'b0;
      rd_en = 1'b1;
      @(posedge clk);
      #1;
      d = rdata;
      @(negedge clk);
      rd_en = 1'b0;
    end
  endtask

  task automatic check_equal32(input string label, input [31:0] actual, input [31:0] expected);
    begin
      if (actual !== expected) begin
        $display("FAIL: %s expected=0x%08h actual=0x%08h", label, expected, actual);
        $fatal(1);
      end
    end
  endtask

  task automatic check_equal8(input string label, input [7:0] actual, input [7:0] expected);
    begin
      if (actual !== expected) begin
        $display("FAIL: %s expected=0x%02h actual=0x%02h", label, expected, actual);
        $fatal(1);
      end
    end
  endtask

  task automatic check_true(input string label, input condition);
    begin
      if (!condition) begin
        $display("FAIL: %s", label);
        $fatal(1);
      end
    end
  endtask

  task automatic measure_pwm(input integer cycles, output integer high_total, output integer rising_edges);
    integer n;
    reg prev_pwm;
    begin
      high_total = 0;
      rising_edges = 0;
      prev_pwm = pwm_out;
      for (n = 0; n < cycles; n = n + 1) begin
        @(posedge clk);
        #1;
        if (pwm_out)
          high_total = high_total + 1;
        if (!prev_pwm && pwm_out)
          rising_edges = rising_edges + 1;
        prev_pwm = pwm_out;
      end
    end
  endtask

  task automatic q_reg_arm_target(input [31:0] expected_data);
    begin
      @(negedge clk);
      target_monitor_armed = 1'b0;
      target_monitor_data = expected_data;
      target_monitor_clear = 1'b1;
      @(posedge clk); #1;
      @(negedge clk);
      target_monitor_clear = 1'b0;
      target_monitor_armed = 1'b1;
    end
  endtask

  task automatic q_reg_disarm_and_check(input string qid);
    begin
      @(negedge clk);
      target_monitor_armed = 1'b0;
      if (target_write_count !== 1 || target_clear_pulse_count !== 1 || target_unexpected_write_count !== 0)
        $fatal(1, "%s target monitor mismatch writes=%0d clear_pulses=%0d unexpected=%0d",
               qid, target_write_count, target_clear_pulse_count, target_unexpected_write_count);
    end
  endtask

  task automatic q_reg_reset(input string qid);
    begin
      @(negedge clk);
      rst_n = 1'b0;
      sample_valid = 1'b0;
      wr_en = 1'b0;
      rd_en = 1'b0;
      addr = 8'h00;
      wdata = 32'h0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd510;
      target_monitor_armed = 1'b0;
      target_monitor_clear = 1'b0;
      repeat (2) @(posedge clk);
      #1;
      if (fault_latched || fault_valid || fault_code_latched !== `FAULT_NONE || fsm_state !== ST_NORMAL)
        $fatal(1, "%s register-controlled reset isolation failed", qid);
      @(negedge clk);
      rst_n = 1'b1;
      wait_cycles(4);
    end
  endtask

  task automatic q_reg_sample(input [11:0] a, input [11:0] b);
    begin
      @(negedge clk);
      i_ch1 = a;
      i_ch2 = b;
      sample_valid = 1'b1;
      @(posedge clk); #1;
      @(negedge clk);
      sample_valid = 1'b0;
      @(posedge clk); #1;
    end
  endtask

  task automatic q_reg_wait_live_low(input string qid);
    integer guard;
    begin
      guard = 0;
      while (dut.u_core.accepted_sample_valid ||
             dut.u_core.sample_decision_valid || fault_valid) begin
        @(posedge clk); #1;
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "%s timeout waiting for registered live fault to clear", qid);
      end
      if (!fault_latched)
        $fatal(1, "%s live source removal incorrectly cleared fault_latched", qid);
    end
  endtask

  task automatic q_reg_safe_setup;
    begin
      reg_write(REG_CTRL, 32'h0000_0000);
      reg_write(REG_TH_OC1, 32'd3000);
      reg_write(REG_TH_OC2, 32'd3000);
      reg_write(REG_TH_DIFF, 32'd200);
      reg_write(REG_PWM_PERIOD, 32'd8);
      reg_write(REG_PWM_DUTY, 32'd4);
    end
  endtask

  task automatic q_reg_make_stuck(input string qid);
    integer sample_cycle;
    integer guard;
    begin
      i_ch1 = 12'd500;
      i_ch2 = 12'd510;
      @(negedge clk); sample_valid = 1'b1;
      for (sample_cycle = 0; sample_cycle < 260; sample_cycle = sample_cycle + 1) begin
        @(posedge clk); #1;
      end
      @(negedge clk); sample_valid = 1'b0;
      guard = 0;
      while (!fault_latched) begin
        @(posedge clk); #1;
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "%s timeout creating persistent stuck through public samples", qid);
      end
      if (!dut.u_core.sensor_stuck_flag || !fault_valid || fault_code_latched !== `FAULT_SENSOR_STUCK ||
          fsm_state !== ST_FAULT_LATCHED || !dut.u_core.u_fsm.pwm_disable)
        $fatal(1, "%s persistent stuck setup mismatch", qid);
    end
  endtask

  task automatic q_reg_remove_stuck(input string qid);
    begin
      $display("%s current implementation characterization: two moving valid samples drive visible stuck-source removal", qid);
      q_reg_sample(12'd520, 12'd530);
      if (!dut.u_core.sensor_stuck_flag || dut.u_core.u_health.stuck_cnt !== 8'd0)
        $fatal(1, "%s first moving sample did not reset history before visible clear", qid);
      q_reg_sample(12'd540, 12'd550);
      if (dut.u_core.sensor_stuck_flag)
        $fatal(1, "%s second moving sample did not clear visible stuck behavior", qid);
      q_reg_wait_live_low(qid);
      if (fault_code_latched !== `FAULT_SENSOR_STUCK || fsm_state !== ST_FAULT_LATCHED || !dut.u_core.u_fsm.pwm_disable)
        $fatal(1, "%s source removal did not retain latch/code protection", qid);
    end
  endtask

  task automatic q_reg_make_overcurrent(input string qid);
    integer guard;
    begin
      q_reg_sample(12'd2500, 12'd2500);
      guard = 0;
      while (!fault_latched) begin
        @(posedge clk); #1;
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "%s timeout creating overcurrent", qid);
      end
      if (fault_code_latched !== `FAULT_OVERCURRENT || !dut.u_core.u_fsm.pwm_disable)
        $fatal(1, "%s overcurrent setup mismatch", qid);
    end
  endtask

  task automatic q_reg_remove_overcurrent(input string qid);
    begin
      q_reg_sample(12'd500, 12'd510);
      q_reg_wait_live_low(qid);
    end
  endtask

  task automatic q_reg_clear_e0_e5(input string qid, input [31:0] ctrl_data, input [7:0] retained_code);
    begin
      if (fault_valid || !fault_latched || fault_code_latched !== retained_code)
        $fatal(1, "%s recovery precondition mismatch", qid);
      q_reg_arm_target(ctrl_data);
      reg_write(REG_CTRL, ctrl_data);
      @(posedge clk); #1;
      if (fsm_state !== ST_RESET_WAIT || dut.u_core.u_fsm.reset_wait_cnt !== 16'd0 || !fault_latched ||
          fault_code_latched !== retained_code || !dut.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0 ||
          dut.u_reg_bank.clear_fault_pulse || wr_en)
        $fatal(1, "%s E0 mismatch", qid);
      @(posedge clk); #1;
      if (fsm_state !== ST_RESET_WAIT || dut.u_core.u_fsm.reset_wait_cnt !== 16'd1 || !fault_latched ||
          fault_code_latched !== retained_code || !dut.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0 ||
          dut.u_reg_bank.clear_fault_pulse || wr_en)
        $fatal(1, "%s E1 mismatch", qid);
      @(posedge clk); #1;
      if (fsm_state !== ST_RESET_WAIT || dut.u_core.u_fsm.reset_wait_cnt !== 16'd2 || !fault_latched ||
          fault_code_latched !== retained_code || !dut.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0 ||
          dut.u_reg_bank.clear_fault_pulse || wr_en)
        $fatal(1, "%s E2 mismatch", qid);
      @(posedge clk); #1;
      if (fsm_state !== ST_RESET_WAIT || dut.u_core.u_fsm.reset_wait_cnt !== 16'd3 || !fault_latched ||
          fault_code_latched !== retained_code || !dut.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0 ||
          dut.u_reg_bank.clear_fault_pulse || wr_en)
        $fatal(1, "%s E3 mismatch", qid);
      @(posedge clk); #1;
      if (fsm_state !== ST_NORMAL || dut.u_core.u_fsm.reset_wait_cnt !== 16'd3 ||
          fault_latched || fault_code_latched !== `FAULT_NONE ||
          !dut.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0 || dut.u_reg_bank.clear_fault_pulse || wr_en)
        $fatal(1, "%s E4 atomic latch/code clear mismatch", qid);
      @(posedge clk); #1;
      if (fsm_state !== ST_NORMAL || dut.u_core.u_fsm.reset_wait_cnt !== 16'd0 ||
          fault_latched || fault_code_latched !== `FAULT_NONE ||
          dut.u_core.u_fsm.pwm_disable || dut.u_reg_bank.clear_fault_pulse || wr_en)
        $fatal(1, "%s E5 registered gate release mismatch", qid);
      if (!ctrl_data[0] && (dut.u_reg_bank.pwm_enable || pwm_raw !== 1'b0 || pwm_out !== 1'b0))
        $fatal(1, "%s E5 clear-only PWM-disabled mismatch", qid);
      if (ctrl_data[0] && (!dut.u_reg_bank.pwm_enable || pwm_out !== pwm_raw))
        $fatal(1, "%s E5 compatibility-only PWM behavior mismatch", qid);
      @(posedge clk); #1;
      if (fsm_state !== ST_NORMAL || dut.u_core.u_fsm.reset_wait_cnt !== 16'd0 ||
          fault_latched || fault_code_latched !== `FAULT_NONE ||
          dut.u_core.u_fsm.pwm_disable || dut.u_reg_bank.clear_fault_pulse || wr_en)
        $fatal(1, "%s post-E5 protection stability mismatch", qid);
      if (!ctrl_data[0] && (dut.u_reg_bank.pwm_enable || pwm_raw !== 1'b0 || pwm_out !== 1'b0))
        $fatal(1, "%s post-E5 clear-only stability mismatch", qid);
      if (ctrl_data[0] && (!dut.u_reg_bank.pwm_enable || pwm_out !== pwm_raw))
        $fatal(1, "%s post-E5 compatibility-only stability mismatch", qid);
      q_reg_disarm_and_check(qid);
    end
  endtask

  task automatic run_persistent_sensor_stuck_clear_only;
    integer n;
    integer guard;
    reg [7:0] history_before_clear;
    begin
      $display("[10D-E] persistent sensor-stuck invalid-clear stale-event suppression");
      $display("Q-SIM-01 updates the formal 10D-E task to the Stage 2B transaction contract");

      @(negedge clk);
      rst_n = 1'b0;
      sample_valid = 1'b0;
      wr_en = 1'b0;
      rd_en = 1'b0;
      addr = 8'h00;
      wdata = 32'h0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd500;
      wait_cycles(3);
      rst_n = 1'b1;
      wait_cycles(4);

      check_true("10D-E reset should clear fault_latched", fault_latched == 1'b0);
      check_equal8("10D-E reset should clear fault code", fault_code_latched, `FAULT_NONE);
      reg_read(REG_STATUS, rd_value);
      check_equal32("10D-E reset status", rd_value, 32'h0000_0000);
      reg_read(REG_CTRL, rd_value);
      check_equal32("10D-E reset keeps PWM disabled", rd_value, 32'h0000_0000);

      reg_write(REG_TH_OC1, 32'd3000);
      reg_write(REG_TH_OC2, 32'd3000);
      reg_write(REG_TH_DIFF, 32'd200);
      reg_read(REG_STATUS, rd_value);
      check_equal32("10D-E safe configured status", rd_value, 32'h0000_0000);

      for (n = 0; n < 260; n = n + 1) begin
        @(negedge clk);
        i_ch1 = 12'd500;
        i_ch2 = 12'd500;
        sample_valid = 1'b1;
        @(negedge clk);
        sample_valid = 1'b0;
        #1;
      end

      guard = 0;
      while (!fault_latched) begin
        @(posedge clk);
        #1;
        guard = guard + 1;
        if (guard > 32) begin
          $display("FAIL: 10D-E persistent sensor-stuck did not latch");
          $fatal(1);
        end
      end

      q_reg_wait_live_low("Q-SIM-01 [10D-E]");
      check_true("10D-E invalid gap clears live transaction event", fault_valid == 1'b0);
      check_true("10D-E persistent stuck fault_latched before clear-only", fault_latched == 1'b1);
      check_equal8("10D-E persistent stuck latched code before clear-only", fault_code_latched, `FAULT_SENSOR_STUCK);
      reg_read(REG_STATUS, rd_value);
      check_equal32("10D-E retained latch status before clear-only", rd_value, 32'h0000_0002);
      reg_read(REG_FAULT_CODE, rd_value);
      check_equal32("10D-E persistent stuck fault code before clear-only", rd_value, 32'h0000_0005);

      history_before_clear = dut.u_core.u_health.stuck_cnt;
      q_reg_arm_target(32'h0000_0002);
      reg_write(REG_CTRL, 32'h0000_0002);
      @(posedge clk); #1;
      if (dut.u_core.u_health.stuck_cnt !== history_before_clear || !dut.u_core.sensor_stuck_flag ||
          fault_valid || !fault_latched || fault_code_latched !== `FAULT_SENSOR_STUCK ||
          fsm_state !== ST_RESET_WAIT || !dut.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "10D-E clear changed retained health state or E0 protection");
      wait_cycles(9);
      q_reg_disarm_and_check("Q-SIM-01 [10D-E]");

      if (dut.u_core.u_health.stuck_cnt !== history_before_clear || !dut.u_core.sensor_stuck_flag ||
          fault_valid || fault_latched || fault_code_latched !== `FAULT_NONE ||
          fsm_state !== ST_NORMAL || dut.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "10D-E stale retained health state retriggered protection");
      check_true("10D-E retained health flag is not a live event", fault_valid == 1'b0);
      check_true("10D-E invalid clear releases stale latch", fault_latched == 1'b0);
      check_equal8("10D-E invalid clear removes old code", fault_code_latched, `FAULT_NONE);
      reg_read(REG_STATUS, rd_value);
      check_equal32("10D-E clear status after stale suppression", rd_value, 32'h0000_0000);
      reg_read(REG_FAULT_CODE, rd_value);
      check_equal32("10D-E fault code after stale suppression", rd_value, 32'h0000_0000);

      @(negedge clk);
      sample_valid = 1'b0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd500;
    end
  endtask

  task automatic run_qsim02_qsim03_qsim10_removed_source;
    integer observe_cycle;
    begin
      $display("Q-SIM-02/Q-SIM-03/Q-SIM-10 removed stuck, no-clear observation, then CTRL=0x2 recovery");
      q_reg_reset("Q-SIM-02/Q-SIM-03/Q-SIM-10");
      q_reg_safe_setup();
      q_reg_make_stuck("Q-SIM-02/Q-SIM-03/Q-SIM-10");
      q_reg_remove_stuck("Q-SIM-02/Q-SIM-03/Q-SIM-10");
      reg_read(REG_CTRL, rd_value);
      check_equal32("Q-SIM-02 pre-clear CTRL", rd_value, 32'h0000_0000);
      reg_read(REG_STATUS, rd_value);
      check_equal32("Q-SIM-02 pre-clear STATUS", rd_value, 32'h0000_0002);
      reg_read(REG_FAULT_CODE, rd_value);
      check_equal32("Q-SIM-02 pre-clear FAULT_CODE", rd_value, {24'd0, `FAULT_SENSOR_STUCK});
      for (observe_cycle = 0; observe_cycle < 6; observe_cycle = observe_cycle + 1) begin
        @(posedge clk); #1;
        if (fault_valid || !fault_latched || fault_code_latched !== `FAULT_SENSOR_STUCK ||
            !dut.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0)
          $fatal(1, "Q-SIM-02 register no-clear cycle %0d failed", observe_cycle);
      end
      q_reg_clear_e0_e5("Q-SIM-03/Q-SIM-10", 32'h0000_0002, `FAULT_SENSOR_STUCK);
      reg_read(REG_CTRL, rd_value);
      check_equal32("Q-SIM-03 final CTRL", rd_value, 32'h0000_0000);
      reg_read(REG_STATUS, rd_value);
      check_equal32("Q-SIM-03 final STATUS", rd_value, 32'h0000_0000);
      reg_read(REG_FAULT_CODE, rd_value);
      check_equal32("Q-SIM-03 final FAULT_CODE", rd_value, 32'h0000_0000);
      if (pwm_out !== 1'b0 || pwm_raw !== 1'b0 || dut.u_reg_bank.pwm_enable !== 1'b0)
        $fatal(1, "Q-SIM-10 clear-only recovery must leave PWM disabled");
    end
  endtask

  task automatic run_qsim09_register_normal_matrix;
    begin
      $display("Q-SIM-09 register clear in safe NORMAL and NORMAL plus live fault");
      q_reg_reset("Q-SIM-09 safe NORMAL");
      q_reg_safe_setup();
      q_reg_arm_target(32'h0000_0002);
      reg_write(REG_CTRL, 32'h0000_0002);
      @(posedge clk); #1;
      if (fsm_state !== ST_NORMAL || fault_latched || fault_code_latched !== `FAULT_NONE || dut.u_core.u_fsm.pwm_disable)
        $fatal(1, "Q-SIM-09 safe NORMAL clear produced a protection side effect");
      q_reg_disarm_and_check("Q-SIM-09 safe NORMAL");
      reg_read(REG_CTRL, rd_value);
      check_equal32("Q-SIM-09 clear-only keeps pwm_enable low", rd_value, 32'h0000_0000);

      q_reg_reset("Q-SIM-09 NORMAL plus live fault");
      q_reg_safe_setup();
      q_reg_arm_target(32'h0000_0002);
      @(negedge clk);
      i_ch1 = 12'd3500;
      i_ch2 = 12'd3500;
      sample_valid = 1'b1;
      addr = REG_CTRL;
      wdata = 32'h0000_0002;
      wr_en = 1'b1;
      @(posedge clk); #1;
      @(negedge clk);
      sample_valid = 1'b0;
      wr_en = 1'b0;
      wdata = 32'h0;
      if (!dut.u_core.accepted_sample_valid || fault_valid ||
          !dut.u_reg_bank.clear_fault_pulse || fsm_state !== ST_NORMAL ||
          fault_latched)
        $fatal(1, "Q-SIM-09 simultaneous accept/clear boundary witness failed");
      @(posedge clk); #1;
      if (!dut.u_core.sample_decision_valid || fault_valid || fault_latched)
        $fatal(1, "Q-SIM-09 accepted fault decision alignment failed");
      @(posedge clk); #1;
      if (!fault_valid || fault_code !== `FAULT_OVERCURRENT ||
          fsm_state !== ST_NORMAL || fault_latched)
        $fatal(1, "Q-SIM-09 accepted fault classifier timing failed");
      @(posedge clk); #1;
      if (!fault_latched || fault_code_latched !== `FAULT_OVERCURRENT ||
          fsm_state !== ST_FAULT_LATCHED || !dut.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-09 live fault was suppressed by simultaneous register clear pulse");
      q_reg_disarm_and_check("Q-SIM-09 NORMAL plus live fault");
    end
  endtask

  task automatic run_qsim11_ctrl3_compatibility;
    begin
      $display("Q-SIM-11 CTRL=0x3 compatibility characterization only");
      q_reg_reset("Q-SIM-11");
      q_reg_safe_setup();
      reg_write(REG_TH_OC1, 32'd1000);
      reg_write(REG_TH_OC2, 32'd1000);
      q_reg_make_overcurrent("Q-SIM-11");
      q_reg_remove_overcurrent("Q-SIM-11");
      q_reg_clear_e0_e5("Q-SIM-11 compatibility characterization only", 32'h0000_0003, `FAULT_OVERCURRENT);
      reg_read(REG_CTRL, rd_value);
      check_equal32("Q-SIM-11 stored enable compatibility readback", rd_value, 32'h0000_0001);
      if (dut.u_reg_bank.pwm_enable !== 1'b1 || pwm_out !== pwm_raw)
        $fatal(1, "Q-SIM-11 E5 compatibility behavior did not expose current pwm_raw phase through the released gate");
    end
  endtask

  task automatic run_qsim16_register_reset_vs_recovery;
    begin
      $display("Q-SIM-16 register-controlled RTL reset path versus normal recovery");
      q_reg_reset("Q-SIM-16 reset path");
      q_reg_safe_setup();
      reg_write(REG_TH_OC1, 32'd2000);
      reg_write(REG_TH_OC2, 32'd2000);
      reg_write(REG_PWM_PERIOD, 32'd12);
      q_reg_make_overcurrent("Q-SIM-16 reset path");
      @(negedge clk); rst_n = 1'b0;
      @(posedge clk); #1;
      if (fault_latched || fault_valid || fault_code_latched !== `FAULT_NONE ||
          fsm_state !== ST_NORMAL || dut.u_reg_bank.pwm_enable)
        $fatal(1, "Q-SIM-16 RTL reset path did not clear register/core protection state");
      @(negedge clk); rst_n = 1'b1;
      wait_cycles(4);
      reg_read(REG_TH_OC1, rd_value);
      check_equal32("Q-SIM-16 reset threshold default", rd_value, 32'd3000);
      reg_read(REG_PWM_PERIOD, rd_value);
      check_equal32("Q-SIM-16 reset period default", rd_value, 32'd1000);

      q_reg_reset("Q-SIM-16 normal recovery");
      q_reg_safe_setup();
      reg_write(REG_TH_OC1, 32'd2000);
      reg_write(REG_TH_OC2, 32'd2000);
      reg_write(REG_PWM_PERIOD, 32'd12);
      q_reg_make_overcurrent("Q-SIM-16 normal recovery");
      q_reg_remove_overcurrent("Q-SIM-16 normal recovery");
      q_reg_clear_e0_e5("Q-SIM-16 normal recovery", 32'h0000_0002, `FAULT_OVERCURRENT);
      reg_read(REG_TH_OC1, rd_value);
      check_equal32("Q-SIM-16 normal recovery preserves threshold", rd_value, 32'd2000);
      reg_read(REG_PWM_PERIOD, rd_value);
      check_equal32("Q-SIM-16 normal recovery preserves period", rd_value, 32'd12);
    end
  endtask

  initial begin
    $dumpfile("sim/waves/tb_protection_ip_top_reg_controlled.vcd");
    $dumpvars(0, tb_protection_ip_top_reg_controlled);

    wait_cycles(3);
    rst_n = 1'b1;
    wait_cycles(4);

    check_true("reset should clear fault_latched", fault_latched == 1'b0);
    check_equal8("reset should clear fault_code_latched", fault_code_latched, `FAULT_NONE);
    reg_read(REG_STATUS, rd_value);
    check_equal32("reset status", rd_value, 32'h0000_0000);

    reg_write(REG_PWM_PERIOD, 32'd8);
    reg_write(REG_PWM_DUTY, 32'd4);
    reg_write(REG_CTRL, 32'h0000_0001);
    wait_cycles(8);
    measure_pwm(32, high_count, rise_count);
    check_true("normal current should allow PWM activity", high_count > 0);
    check_true("normal current should keep PWM toggling", rise_count > 0);

    i_ch1 = 12'd1500;
    i_ch2 = 12'd1500;
    reg_write(REG_TH_OC1, 32'd2000);
    reg_write(REG_TH_OC2, 32'd2000);
    wait_cycles(8);
    check_true("high threshold should not latch same current sample", fault_latched == 1'b0);

    reg_write(REG_TH_OC1, 32'd1000);
    reg_write(REG_TH_OC2, 32'd1000);
    q_reg_sample(12'd1500, 12'd1500);
    wait_cycles(8);
    check_true("low threshold should latch same current sample", fault_latched == 1'b1);
    check_equal8("overcurrent fault code", fault_code_latched, `FAULT_OVERCURRENT);
    reg_read(REG_STATUS, rd_value);
    check_true("status should report fault_latched", rd_value[1] == 1'b1);
    reg_read(REG_FAULT_CODE, rd_value);
    check_equal32("fault_code register after overcurrent", rd_value, {24'd0, `FAULT_OVERCURRENT});

    measure_pwm(24, high_count, rise_count);
    check_equal32("PWM must be forced low during latched fault", high_count, 32'd0);

    i_ch1 = 12'd500;
    i_ch2 = 12'd510;
    reg_write(REG_CTRL, 32'h0000_0003);
    wait_cycles(10);
    check_true("clear_fault should clear latched fault after current recovers", fault_latched == 1'b0);
    check_equal8("clear_fault should clear latched fault code", fault_code_latched, `FAULT_NONE);
    measure_pwm(32, high_count, rise_count);
    check_true("PWM should resume after clear_fault and normal current", high_count > 0);

    reg_write(REG_TH_OC1, 32'd2500);
    reg_write(REG_TH_OC2, 32'd2500);
    reg_write(REG_PWM_PERIOD, 32'd8);
    reg_write(REG_PWM_DUTY, 32'd2);
    wait_cycles(16);
    measure_pwm(96, fast_high_count, fast_rise_count);

    reg_write(REG_PWM_PERIOD, 32'd16);
    reg_write(REG_PWM_DUTY, 32'd8);
    wait_cycles(16);
    measure_pwm(96, slow_high_count, slow_rise_count);
    check_true("PWM duty update should increase high-time count", slow_high_count > fast_high_count);
    check_true("PWM period update should reduce rising-edge count", fast_rise_count > slow_rise_count);

    reg_read(REG_TH_OC1, rd_value);
    check_equal32("ch1 threshold readback", rd_value, 32'd2500);
    reg_read(REG_TH_OC2, rd_value);
    check_equal32("ch2 threshold readback", rd_value, 32'd2500);
    reg_read(REG_PWM_PERIOD, rd_value);
    check_equal32("PWM period readback", rd_value, 32'd16);
    reg_read(REG_PWM_DUTY, rd_value);
    check_equal32("PWM duty readback", rd_value, 32'd8);
    reg_read(REG_I_CH1, rd_value);
    check_equal32("current monitor ch1 readback", rd_value, 32'd500);
    reg_read(REG_I_CH2, rd_value);
    check_equal32("current monitor ch2 readback", rd_value, 32'd510);

    i_ch1 = 12'd900;
    i_ch2 = 12'd910;
    reg_write(REG_TH_OC1, 32'd600);
    reg_write(REG_TH_OC2, 32'd600);
    q_reg_sample(12'd900, 12'd910);
    wait_cycles(8);
    reg_read(REG_STATUS, rd_value);
    check_true("status readback should show final overcurrent fault", rd_value[1] == 1'b1);
    reg_read(REG_FAULT_CODE, rd_value);
    check_equal32("fault_code readback should match final overcurrent", rd_value, {24'd0, `FAULT_OVERCURRENT});

    run_persistent_sensor_stuck_clear_only();
    run_qsim02_qsim03_qsim10_removed_source();
    run_qsim09_register_normal_matrix();
    run_qsim11_ctrl3_compatibility();
    run_qsim16_register_reset_vs_recovery();

    $display("ALL TESTS PASSED: tb_protection_ip_top_reg_controlled");
    $finish;
  end
endmodule
