`timescale 1ns/1ps
`include "fault_defs.vh"
module tb_protection_core_top;
  localparam [3:0] ST_NORMAL = 4'd0;
  localparam [3:0] ST_FAULT_LATCHED = 4'd1;
  localparam [3:0] ST_RESET_WAIT = 4'd2;

  reg clk = 0, rst_n = 0, sample_valid = 0, pwm_enable = 0, clear_fault = 0;
  reg [11:0] i1 = 12'd500, i2 = 12'd510;
  reg [11:0] th_oc1 = 12'd1000, th_oc2 = 12'd1000, th_diff = 12'd100;
  reg [11:0] th_open = 12'd5, th_sat = 12'd4090, th_stuck_delta = 12'd0;
  reg [7:0] th_persist = 8'd5;
  reg [15:0] pwm_period = 16'd10, pwm_duty = 16'd5;
  wire pwm_raw, pwm_out, oc_any, oc_both, mismatch, open_f, sat_f, stuck_f, fault_valid, fault_latched;
  wire [7:0] code, code_latched;
  wire [3:0] state;
  wire [11:0] abs_diff;
  integer latency_cycles;
  integer high_count;
  integer rise_count;

  always #5 clk = ~clk;

  protection_core_top dut(
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .pwm_enable(pwm_enable), .clear_fault(clear_fault),
    .i_ch1(i1), .i_ch2(i2), .th_oc_ch1(th_oc1), .th_oc_ch2(th_oc2), .th_diff(th_diff),
    .th_open(th_open), .th_sat(th_sat), .th_stuck_delta(th_stuck_delta), .th_persist(th_persist),
    .period(pwm_period), .duty(pwm_duty),
    .pwm_raw(pwm_raw), .pwm_out(pwm_out), .oc_any(oc_any), .oc_both(oc_both), .mismatch_flag(mismatch),
    .sensor_open_flag(open_f), .sensor_sat_flag(sat_f), .sensor_stuck_flag(stuck_f),
    .fault_valid(fault_valid), .fault_latched(fault_latched), .fault_code(code), .fault_code_latched(code_latched),
    .fsm_state(state), .abs_diff(abs_diff));

  task automatic configure_nominal;
    begin
      th_oc1 = 12'd1000;
      th_oc2 = 12'd1000;
      th_diff = 12'd100;
      th_open = 12'd5;
      th_sat = 12'd4090;
      th_stuck_delta = 12'd0;
      th_persist = 8'd5;
      pwm_period = 16'd10;
      pwm_duty = 16'd5;
    end
  endtask

  task automatic configure_health_fast_no_combo;
    begin
      th_oc1 = 12'hFFF;
      th_oc2 = 12'hFFF;
      th_diff = 12'hFFF;
      th_open = 12'd5;
      th_sat = 12'd4090;
      th_stuck_delta = 12'd0;
      th_persist = 8'd3;
      pwm_period = 16'd10;
      pwm_duty = 16'd5;
    end
  endtask

  task automatic configure_bringup_like;
    begin
      th_oc1 = 12'd1000;
      th_oc2 = 12'd1000;
      th_diff = 12'd100;
      th_open = 12'd0;
      th_sat = 12'hFFF;
      th_stuck_delta = 12'd0;
      th_persist = 8'hFF;
      pwm_period = 16'd10;
      pwm_duty = 16'd5;
    end
  endtask

  task automatic wait_cycles(input integer cycles);
    integer n;
    begin
      for (n = 0; n < cycles; n = n + 1)
        @(posedge clk);
      #1;
    end
  endtask

  task automatic reset_core;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      sample_valid = 1'b0;
      clear_fault = 1'b0;
      pwm_enable = 1'b1;
      i1 = 12'd500;
      i2 = 12'd510;
      configure_nominal();
      @(posedge clk);
      #1;
      if (fault_latched || code_latched !== `FAULT_NONE || fault_valid)
        $fatal(1, "reset did not clear protection state");
      repeat (2) @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
      wait_cycles(4);
    end
  endtask

  task automatic sample(input [11:0] a, input [11:0] b);
    begin
      @(negedge clk);
      i1 = a;
      i2 = b;
      sample_valid = 1'b1;
      @(negedge clk);
      sample_valid = 1'b0;
      #1;
    end
  endtask

  task automatic drive_current(input [11:0] a, input [11:0] b, input valid);
    begin
      @(negedge clk);
      i1 = a;
      i2 = b;
      sample_valid = valid;
      @(negedge clk);
      sample_valid = 1'b0;
      #1;
    end
  endtask

  task automatic check_no_latch(input string label, input integer cycles);
    begin
      wait_cycles(cycles);
      if (fault_latched || code_latched !== `FAULT_NONE) begin
        $fatal(1, "%s unexpected latch: latched=%0b code=0x%02h valid=%0b raw_code=0x%02h",
               label, fault_latched, code_latched, fault_valid, code);
      end
    end
  endtask

  task automatic wait_for_latch(input string label, input [7:0] exp_code);
    integer guard;
    begin
      guard = 0;
      while (!fault_latched) begin
        @(posedge clk);
        #1;
        guard = guard + 1;
        if (guard > 24)
          $fatal(1, "%s timeout waiting for fault_latched", label);
      end
      if (code_latched !== exp_code)
        $fatal(1, "%s code mismatch: got 0x%02h expected 0x%02h raw_code=0x%02h",
               label, code_latched, exp_code, code);
      if (pwm_out !== 1'b0)
        $fatal(1, "%s pwm_out must be safe-low after latch", label);
    end
  endtask

  task automatic expect_pwm_safe_low(input string label, input integer cycles);
    integer n;
    begin
      for (n = 0; n < cycles; n = n + 1) begin
        @(posedge clk);
        #1;
        if (pwm_out !== 1'b0)
          $fatal(1, "%s pwm_out escaped safe-low during latched fault", label);
      end
    end
  endtask

  task automatic pulse_clear;
    begin
      @(negedge clk);
      clear_fault = 1'b1;
      @(negedge clk);
      clear_fault = 1'b0;
      #1;
    end
  endtask

  task automatic clear_after_safe(input string label);
    begin
      drive_current(12'd500, 12'd510, 1'b1);
      wait_cycles(2);
      pulse_clear();
      wait_cycles(8);
      if (fault_latched || code_latched !== `FAULT_NONE)
        $fatal(1, "%s did not clear after safe input: latched=%0b code=0x%02h", label, fault_latched, code_latched);
    end
  endtask

  task wait_pwm_rising_edge;
    integer guard;
    reg prev_pwm;
    begin
      guard = 0;
      prev_pwm = pwm_out;
      while (!(prev_pwm == 1'b0 && pwm_out == 1'b1)) begin
        prev_pwm = pwm_out;
        @(posedge clk); #1;
        guard = guard + 1;
        if (guard > 80) $fatal(1,"timeout waiting for pwm_out rising edge");
      end
    end
  endtask

  task automatic inject_overcurrent_and_measure_latency(output integer cycles);
    integer guard;
    begin
      wait_pwm_rising_edge();
      @(negedge clk);
      i1 = 12'd1300;
      i2 = 12'd1320;
      sample_valid = 1'b1;
      cycles = 0;
      guard = 0;
      while (!(fault_latched && pwm_out === 1'b0)) begin
        @(posedge clk); #1;
        cycles = cycles + 1;
        guard = guard + 1;
          if (guard > 8) $fatal(1,"timeout waiting for protection response");
      end
      @(negedge clk);
      sample_valid = 1'b0;
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

  task automatic run_combo_fault(input string label, input [11:0] a, input [11:0] b, input [7:0] exp_code);
    begin
      reset_core();
      configure_nominal();
      drive_current(a, b, 1'b1);
      wait_for_latch(label, exp_code);
      expect_pwm_safe_low(label, 6);
    end
  endtask

  task automatic run_open_only;
    begin
      reset_core();
      configure_health_fast_no_combo();
      sample(12'd0, 12'd200);
      sample(12'd0, 12'd210);
      sample(12'd0, 12'd220);
      sample(12'd0, 12'd230);
      sample(12'd0, 12'd240);
      wait_for_latch("open only", `FAULT_SENSOR_OPEN);
    end
  endtask

  task automatic run_saturation_only;
    begin
      reset_core();
      configure_health_fast_no_combo();
      sample(12'd4095, 12'd4000);
      sample(12'd4095, 12'd4010);
      sample(12'd4095, 12'd4020);
      sample(12'd4095, 12'd4030);
      sample(12'd4095, 12'd4040);
      wait_for_latch("saturation only", `FAULT_SENSOR_SATURATION);
    end
  endtask

  task automatic run_stuck_only;
    begin
      reset_core();
      configure_health_fast_no_combo();
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      wait_for_latch("stuck only", `FAULT_SENSOR_STUCK);
    end
  endtask

  task automatic run_all_health_faults;
    begin
      reset_core();
      configure_health_fast_no_combo();
      sample(12'd0, 12'd4095);
      sample(12'd0, 12'd4095);
      sample(12'd0, 12'd4095);
      sample(12'd0, 12'd4095);
      sample(12'd0, 12'd4095);
      sample(12'd0, 12'd4095);
      wait_for_latch("all sensor health faults", `FAULT_SENSOR_SATURATION);
      if (!open_f || !sat_f || !stuck_f)
        $fatal(1, "all sensor health faults did not assert all flags: open=%0b sat=%0b stuck=%0b", open_f, sat_f, stuck_f);
    end
  endtask

  task automatic run_mismatch_plus_health;
    begin
      reset_core();
      configure_health_fast_no_combo();
      th_diff = 12'd100;
      sample(12'd0, 12'd200);
      wait_for_latch("mismatch plus delayed open health", `FAULT_SENSOR_MISMATCH);
    end
  endtask

  task automatic run_delayed_oc_stuck;
    begin
      reset_core();
      configure_nominal();
      th_stuck_delta = 12'd0;
      th_persist = 8'd3;
      sample(12'd1050, 12'd1000);
      sample(12'd1050, 12'd1000);
      sample(12'd1050, 12'd1000);
      sample(12'd1050, 12'd1000);
      sample(12'd1050, 12'd1000);
      wait_for_latch("overcurrent plus delayed stuck keeps first OC code", `FAULT_OVERCURRENT);
    end
  endtask

  task automatic q_wait_live_low(input string qid);
    integer guard;
    begin
      guard = 0;
      while (fault_valid) begin
        @(posedge clk); #1;
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "%s timeout waiting for registered fault_valid to clear", qid);
      end
      if (!fault_latched)
        $fatal(1, "%s source removal incorrectly cleared the FSM latch", qid);
    end
  endtask

  task automatic q_make_stuck_fault(input string qid, input pwm_setting);
    begin
      reset_core();
      configure_health_fast_no_combo();
      @(negedge clk);
      pwm_enable = pwm_setting;
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      sample(12'd500, 12'd510);
      wait_for_latch(qid, `FAULT_SENSOR_STUCK);
      if (!stuck_f || !fault_valid || state !== ST_FAULT_LATCHED || !dut.u_fsm.pwm_disable)
        $fatal(1, "%s public-input stuck setup was incomplete", qid);
    end
  endtask

  task automatic q_remove_stuck_source(input string qid);
    begin
      $display("%s current implementation characterization: two moving valid samples drive visible stuck-source removal", qid);
      sample(12'd520, 12'd530);
      if (!stuck_f || dut.u_health.stuck_cnt !== 8'd0)
        $fatal(1, "%s first moving valid sample must reset history before visible stuck clears", qid);
      sample(12'd540, 12'd550);
      if (stuck_f)
        $fatal(1, "%s second moving valid sample did not clear visible stuck behavior", qid);
      q_wait_live_low(qid);
      if (code_latched !== `FAULT_SENSOR_STUCK || state !== ST_FAULT_LATCHED || !dut.u_fsm.pwm_disable)
        $fatal(1, "%s source removal did not retain latch/code protection", qid);
    end
  endtask

  task automatic q_make_overcurrent_fault(input string qid);
    begin
      reset_core();
      configure_nominal();
      drive_current(12'd1300, 12'd1320, 1'b1);
      wait_for_latch(qid, `FAULT_OVERCURRENT);
      if (state !== ST_FAULT_LATCHED || !dut.u_fsm.pwm_disable)
        $fatal(1, "%s overcurrent setup state mismatch", qid);
    end
  endtask

  task automatic q_remove_overcurrent_source(input string qid);
    begin
      @(negedge clk);
      i1 = 12'd500;
      i2 = 12'd510;
      sample_valid = 1'b0;
      q_wait_live_low(qid);
      if (code_latched !== `FAULT_OVERCURRENT || state !== ST_FAULT_LATCHED)
        $fatal(1, "%s overcurrent source removal did not retain latch/code", qid);
    end
  endtask

  task automatic q_check_e0_e5_recovery(input string qid, input [7:0] retained_code);
    begin
      if (fault_valid || !fault_latched || code_latched !== retained_code)
        $fatal(1, "%s recovery precondition mismatch", qid);
      @(negedge clk); clear_fault = 1'b1;
      @(posedge clk); #1;
      if (state !== ST_RESET_WAIT || dut.u_fsm.reset_wait_cnt !== 16'd0 || !fault_latched || code_latched !== retained_code || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "%s E0 mismatch", qid);
      @(negedge clk); clear_fault = 1'b0;
      @(posedge clk); #1;
      if (state !== ST_RESET_WAIT || dut.u_fsm.reset_wait_cnt !== 16'd1 || !fault_latched || code_latched !== retained_code || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "%s E1 mismatch", qid);
      @(posedge clk); #1;
      if (state !== ST_RESET_WAIT || dut.u_fsm.reset_wait_cnt !== 16'd2 || !fault_latched || code_latched !== retained_code || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "%s E2 mismatch", qid);
      @(posedge clk); #1;
      if (state !== ST_RESET_WAIT || dut.u_fsm.reset_wait_cnt !== 16'd3 || !fault_latched || code_latched !== retained_code || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "%s E3 mismatch", qid);
      @(posedge clk); #1;
      if (state !== ST_NORMAL || dut.u_fsm.reset_wait_cnt !== 16'd3 ||
          fault_latched || code_latched !== `FAULT_NONE || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "%s E4 atomic latch/code clear mismatch", qid);
      @(posedge clk); #1;
      if (state !== ST_NORMAL || dut.u_fsm.reset_wait_cnt !== 16'd0 ||
          fault_latched || code_latched !== `FAULT_NONE || dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "%s E5 registered gate release or disabled-PWM mismatch", qid);
      if (pwm_enable !== 1'b0 || pwm_raw !== 1'b0)
        $fatal(1, "%s gate release must not be confused with PWM enable", qid);
      @(posedge clk); #1;
      if (state !== ST_NORMAL || dut.u_fsm.reset_wait_cnt !== 16'd0 ||
          fault_latched || code_latched !== `FAULT_NONE ||
          dut.u_fsm.pwm_disable || pwm_enable || pwm_raw !== 1'b0 || pwm_out !== 1'b0)
        $fatal(1, "%s post-E5 clear-only stability mismatch", qid);
    end
  endtask

  task automatic run_qsim02_stuck_removed_no_clear;
    integer observe_cycle;
    begin
      $display("Q-SIM-02 source removed, no clear");
      q_make_stuck_fault("Q-SIM-02", 1'b0);
      q_remove_stuck_source("Q-SIM-02");
      for (observe_cycle = 0; observe_cycle < 6; observe_cycle = observe_cycle + 1) begin
        @(posedge clk); #1;
        if (fault_valid || !fault_latched || code_latched !== `FAULT_SENSOR_STUCK || state !== ST_FAULT_LATCHED || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
          $fatal(1, "Q-SIM-02 no-clear observation cycle %0d failed", observe_cycle);
      end
    end
  endtask

  task automatic run_qsim03_qsim10_stuck_recovery;
    begin
      $display("Q-SIM-03/Q-SIM-10 moving-source recovery with clear-only and PWM disabled");
      q_make_stuck_fault("Q-SIM-03/Q-SIM-10", 1'b0);
      q_remove_stuck_source("Q-SIM-03/Q-SIM-10");
      q_check_e0_e5_recovery("Q-SIM-03/Q-SIM-10", `FAULT_SENSOR_STUCK);
    end
  endtask

  task automatic run_qsim04_clear_live_then_remove;
    reg [7:0] history_before_clear;
    begin
      $display("Q-SIM-04 clear while live, then remove the moving-source fault");
      q_make_stuck_fault("Q-SIM-04", 1'b0);
      history_before_clear = dut.u_health.stuck_cnt;
      @(negedge clk); clear_fault = 1'b1;
      @(posedge clk); #1;
      if (dut.u_health.stuck_cnt !== history_before_clear || !stuck_f || !fault_valid ||
          state !== ST_RESET_WAIT || !fault_latched || code_latched !== `FAULT_SENSOR_STUCK ||
          !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-04 live clear altered health history or protected state");
      @(negedge clk);
      clear_fault = 1'b0;
      #1;
      if (dut.u_health.stuck_cnt !== history_before_clear || !stuck_f || !fault_valid ||
          !fault_latched || code_latched !== `FAULT_SENSOR_STUCK ||
          !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-04 completed clear attempt altered persistent health history");
      q_remove_stuck_source("Q-SIM-04");
      if (state !== ST_FAULT_LATCHED || !fault_latched)
        $fatal(1, "Q-SIM-04 failed live recovery request did not remain latched");
      q_check_e0_e5_recovery("Q-SIM-04 retry after visible live-low", `FAULT_SENSOR_STUCK);
    end
  endtask

  task automatic run_qsim05_core_reassertion;
    begin
      $display("Q-SIM-05 core-input reassertion at early, candidate-final, and post-completion boundaries");

      q_make_overcurrent_fault("Q-SIM-05 early");
      @(negedge clk); pwm_enable = 1'b0;
      q_remove_overcurrent_source("Q-SIM-05 early");
      @(negedge clk); clear_fault = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault = 1'b0;
      @(posedge clk); #1;
      @(negedge clk); i1 = 12'd1300; i2 = 12'd1320;
      @(posedge clk); #1;
      if (!fault_valid || state !== ST_RESET_WAIT || !fault_latched || !dut.u_fsm.pwm_disable)
        $fatal(1, "Q-SIM-05 early reassertion pipeline visibility mismatch");
      @(posedge clk); #1;
      if (state !== ST_FAULT_LATCHED || !fault_latched || code_latched !== `FAULT_OVERCURRENT || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-05 early reassertion allowed unsafe release");

      q_make_overcurrent_fault("Q-SIM-05 candidate-final");
      @(negedge clk); pwm_enable = 1'b0;
      q_remove_overcurrent_source("Q-SIM-05 candidate-final");
      @(negedge clk); clear_fault = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault = 1'b0;
      repeat (2) @(posedge clk);
      #1;
      @(negedge clk); i1 = 12'd1300; i2 = 12'd1320;
      @(posedge clk); #1;
      if (!fault_valid || dut.u_fsm.reset_wait_cnt !== 16'd3 || state !== ST_RESET_WAIT || !dut.u_fsm.pwm_disable)
        $fatal(1, "Q-SIM-05 candidate-final pipeline setup mismatch");
      @(posedge clk); #1;
      if (state !== ST_FAULT_LATCHED || !fault_latched || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-05 visible fault did not block candidate completion edge");

      q_make_overcurrent_fault("Q-SIM-05 post-completion");
      @(negedge clk); pwm_enable = 1'b0;
      q_remove_overcurrent_source("Q-SIM-05 post-completion");
      @(negedge clk); clear_fault = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault = 1'b0;
      repeat (3) @(posedge clk);
      #1;
      @(negedge clk); i1 = 12'd1300; i2 = 12'd1320;
      @(posedge clk); #1;
      if (!fault_valid || state !== ST_NORMAL || fault_latched || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-05 post-completion E4 boundary mismatch");
      @(posedge clk); #1;
      if (state !== ST_FAULT_LATCHED || !fault_latched || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-05 post-completion visible fault allowed E5 gate release");
    end
  endtask

  task automatic run_qsim15_source_clear_alignment;
    begin
      $display("Q-SIM-15 simultaneous source transition and direct clear alignment");
      q_make_overcurrent_fault("Q-SIM-15");
      @(negedge clk);
      pwm_enable = 1'b0;
      i1 = 12'd500;
      i2 = 12'd510;
      sample_valid = 1'b0;
      clear_fault = 1'b1;
      @(posedge clk); #1;
      if (oc_any || open_f || sat_f || stuck_f || fault_valid || code !== `FAULT_NONE ||
          clear_fault !== 1'b1 || state !== ST_RESET_WAIT || !fault_latched ||
          code_latched !== `FAULT_OVERCURRENT || dut.u_fsm.reset_wait_cnt !== 16'd0 ||
          !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-15 source transition was incorrectly counted on E0");
      @(negedge clk); clear_fault = 1'b0;
      @(posedge clk); #1;
      if (oc_any || open_f || sat_f || stuck_f || fault_valid || code !== `FAULT_NONE || clear_fault ||
          dut.u_fsm.reset_wait_cnt !== 16'd1 || state !== ST_RESET_WAIT || !fault_latched ||
          code_latched !== `FAULT_OVERCURRENT || !dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-15 first eligible edge did not follow actual registered live-low visibility");
      repeat (3) @(posedge clk);
      #1;
      if (state !== ST_NORMAL || fault_latched || !dut.u_fsm.pwm_disable)
        $fatal(1, "Q-SIM-15 E4 mismatch");
      @(posedge clk); #1;
      if (dut.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-15 E5 disabled-PWM mismatch");
    end
  endtask

  task automatic run_qsim16_reset_vs_normal_recovery;
    begin
      $display("Q-SIM-16 RTL reset path versus moving-source recovery plus clear");
      q_make_stuck_fault("Q-SIM-16 reset path", 1'b0);
      @(negedge clk);
      rst_n = 1'b0;
      sample_valid = 1'b0;
      clear_fault = 1'b0;
      @(posedge clk); #1;
      if (state !== ST_NORMAL || fault_latched || code_latched !== `FAULT_NONE || fault_valid || stuck_f || dut.u_health.stuck_cnt !== 8'd0)
        $fatal(1, "Q-SIM-16 RTL reset path did not clear existing core/FSM health state");
      @(negedge clk); rst_n = 1'b1;
      wait_cycles(4);

      q_make_stuck_fault("Q-SIM-16 normal recovery", 1'b0);
      q_remove_stuck_source("Q-SIM-16 normal recovery");
      q_check_e0_e5_recovery("Q-SIM-16 normal recovery", `FAULT_SENSOR_STUCK);
    end
  endtask

  initial begin
    reset_core();

    $display("CORE_MATRIX contract: comparator faults are not gated by sample_valid; sensor health counters update only on sample_valid");
    $display("CORE_MATRIX contract: FSM latches the first visible fault_code until clear/reset");

    measure_pwm(32, high_count, rise_count);
    if (fault_latched) $fatal(1, "normal input unexpectedly latched");
    if (high_count <= 0 || rise_count <= 0) $fatal(1, "normal input should allow PWM activity");

    inject_overcurrent_and_measure_latency(latency_cycles);
    $display("PL_RESPONSE_LATENCY_CYCLES=%0d", latency_cycles);
    if (latency_cycles < 1 || latency_cycles > 3) $fatal(1,"unexpected PL response latency: %0d", latency_cycles);
    if (!fault_latched || code_latched !== `FAULT_OVERCURRENT) $fatal(1,"overcurrent did not latch");
    if (pwm_out !== 1'b0) $fatal(1,"pwm_out must be gated low after fault");

    @(negedge clk);
    clear_fault = 1'b1;
    @(posedge clk);
    #1;
    if (!fault_latched || pwm_out !== 1'b0) $fatal(1,"clear_fault must not recover while overcurrent persists");
    @(negedge clk);
    clear_fault = 1'b0;
    repeat(3) @(posedge clk);
    #1;
    if (!fault_latched || pwm_out !== 1'b0) $fatal(1,"fault must remain latched while current is still over threshold");
    clear_after_safe("clear after removed overcurrent");

    run_combo_fault("overcurrent ch1 only", 12'd1050, 12'd1000, `FAULT_OVERCURRENT);
    run_combo_fault("overcurrent ch2 only", 12'd1000, 12'd1050, `FAULT_OVERCURRENT);
    run_combo_fault("dual overcurrent", 12'd1100, 12'd1150, `FAULT_OVERCURRENT);
    run_combo_fault("mismatch only", 12'd800, 12'd950, `FAULT_SENSOR_MISMATCH);
    run_open_only();
    run_saturation_only();
    run_stuck_only();

    run_combo_fault("overcurrent plus mismatch", 12'd1100, 12'd900, `FAULT_OC_WITH_SENSOR);
    run_combo_fault("overcurrent plus open and mismatch", 12'd1300, 12'd0, `FAULT_OC_WITH_SENSOR);
    run_combo_fault("overcurrent plus saturation and mismatch", 12'd1300, 12'd4095, `FAULT_OC_WITH_SENSOR);
    run_delayed_oc_stuck();
    run_combo_fault("overcurrent plus multiple sensor-style indicators", 12'd1300, 12'd4095, `FAULT_OC_WITH_SENSOR);
    run_mismatch_plus_health();
    run_all_health_faults();
    run_combo_fault("all faults active at system input", 12'd1300, 12'd4095, `FAULT_OC_WITH_SENSOR);

    reset_core();
    configure_nominal();
    drive_current(12'd999, 12'd950, 1'b1);
    check_no_latch("threshold below boundary", 6);
    drive_current(12'd1000, 12'd950, 1'b1);
    check_no_latch("threshold equal boundary", 6);
    drive_current(12'd1001, 12'd950, 1'b1);
    wait_for_latch("threshold above boundary", `FAULT_OVERCURRENT);

    reset_core();
    configure_nominal();
    drive_current(12'd800, 12'd900, 1'b1);
    check_no_latch("mismatch equal boundary", 6);
    drive_current(12'd800, 12'd901, 1'b1);
    wait_for_latch("mismatch above boundary", `FAULT_SENSOR_MISMATCH);

    reset_core();
    configure_nominal();
    drive_current(12'd1300, 12'd1320, 1'b1);
    drive_current(12'd500, 12'd510, 1'b0);
    wait_for_latch("one-cycle overcurrent pulse latches", `FAULT_OVERCURRENT);

    reset_core();
    configure_nominal();
    @(posedge clk);
    #1;
    i1 = 12'd1300;
    i2 = 12'd1320;
    #2;
    i1 = 12'd500;
    i2 = 12'd510;
    check_no_latch("sub-cycle overcurrent glitch not sampled", 8);

    reset_core();
    configure_nominal();
    drive_current(12'd1300, 12'd1320, 1'b0);
    wait_for_latch("overcurrent path latches even with sample_valid low", `FAULT_OVERCURRENT);

    reset_core();
    configure_health_fast_no_combo();
    sample(12'd500, 12'd510);
    sample(12'd500, 12'd510);
    wait_cycles(8);
    check_no_latch("sample_valid low does not advance health stuck counter", 2);
    sample(12'd500, 12'd510);
    sample(12'd500, 12'd510);
    sample(12'd500, 12'd510);
    wait_for_latch("intermittent sample_valid eventually latches stuck", `FAULT_SENSOR_STUCK);

    reset_core();
    configure_nominal();
    drive_current(12'd1300, 12'd1320, 1'b1);
    wait_for_latch("reset-during-fault setup", `FAULT_OVERCURRENT);
    @(negedge clk);
    rst_n = 1'b0;
    i1 = 12'd500;
    i2 = 12'd510;
    sample_valid = 1'b0;
    clear_fault = 1'b0;
    @(posedge clk);
    #1;
    if (fault_latched || code_latched !== `FAULT_NONE)
      $fatal(1, "reset during fault did not clear protection state");
    @(negedge clk);
    rst_n = 1'b1;
    check_no_latch("post reset-during-fault safe input", 6);

    reset_core();
    configure_nominal();
    drive_current(12'd1300, 12'd1320, 1'b1);
    wait_for_latch("active clear setup", `FAULT_OVERCURRENT);
    pulse_clear();
    wait_cycles(6);
    if (!fault_latched || code_latched !== `FAULT_OVERCURRENT || pwm_out !== 1'b0)
      $fatal(1, "clear_fault while active fault incorrectly released protection");
    clear_after_safe("clear fault after active source removed");

    reset_core();
    configure_nominal();
    drive_current(12'd1300, 12'd1320, 1'b1);
    wait_for_latch("repeated event first overcurrent", `FAULT_OVERCURRENT);
    clear_after_safe("repeated event first clear");
    drive_current(12'd800, 12'd950, 1'b1);
    wait_for_latch("repeated event second mismatch", `FAULT_SENSOR_MISMATCH);
    clear_after_safe("repeated event second clear");

    reset_core();
    configure_bringup_like();
    sample(12'd500, 12'd510);
    sample(12'd500, 12'd510);
    sample(12'd500, 12'd510);
    sample(12'd500, 12'd510);
    sample(12'd500, 12'd510);
    check_no_latch("bring-up-like stuck settings do not quickly latch", 4);

    run_qsim02_stuck_removed_no_clear();
    run_qsim03_qsim10_stuck_recovery();
    run_qsim04_clear_live_then_remove();
    run_qsim05_core_reassertion();
    run_qsim15_source_clear_alignment();
    run_qsim16_reset_vs_normal_recovery();

    $display("tb_protection_core_top PASS");
    $finish;
  end
endmodule
