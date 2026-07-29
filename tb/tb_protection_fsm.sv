`timescale 1ns/1ps
`include "fault_defs.vh"
module tb_protection_fsm;
  localparam [3:0] ST_NORMAL = 4'd0;
  localparam [3:0] ST_FAULT_LATCHED = 4'd1;
  localparam [3:0] ST_RESET_WAIT = 4'd2;

  reg clk=0, rst_n=0, fault_valid=0, clear_fault=0;
  reg [7:0] fault_code_in=`FAULT_NONE;
  wire fault_latched, pwm_disable; wire [7:0] code_latched; wire [3:0] state;

  reg rst_n_n1=0, fault_valid_n1=0, clear_fault_n1=0;
  reg [7:0] fault_code_in_n1=`FAULT_NONE;
  wire fault_latched_n1, pwm_disable_n1;
  wire [7:0] code_latched_n1;
  wire [3:0] state_n1;

  reg rst_n_n4=0, fault_valid_n4=0, clear_fault_n4=0;
  reg [7:0] fault_code_in_n4=`FAULT_NONE;
  wire fault_latched_n4, pwm_disable_n4;
  wire [7:0] code_latched_n4;
  wire [3:0] state_n4;

  always #5 clk=~clk;
  protection_fsm #(.RESET_WAIT_CYCLES(2)) dut(.clk(clk),.rst_n(rst_n),.fault_valid(fault_valid),.fault_code_in(fault_code_in),.clear_fault(clear_fault),
    .fault_latched(fault_latched),.pwm_disable(pwm_disable),.fault_code_latched(code_latched),.state(state));

  protection_fsm #(.RESET_WAIT_CYCLES(1)) dut_n1(.clk(clk),.rst_n(rst_n_n1),.fault_valid(fault_valid_n1),.fault_code_in(fault_code_in_n1),.clear_fault(clear_fault_n1),
    .fault_latched(fault_latched_n1),.pwm_disable(pwm_disable_n1),.fault_code_latched(code_latched_n1),.state(state_n1));

  protection_fsm #(.RESET_WAIT_CYCLES(4)) dut_n4(.clk(clk),.rst_n(rst_n_n4),.fault_valid(fault_valid_n4),.fault_code_in(fault_code_in_n4),.clear_fault(clear_fault_n4),
    .fault_latched(fault_latched_n4),.pwm_disable(pwm_disable_n4),.fault_code_latched(code_latched_n4),.state(state_n4));

  task automatic reset_main_dut;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      fault_valid = 1'b0;
      fault_code_in = `FAULT_NONE;
      clear_fault = 1'b0;
      repeat (2) @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk); #1;
    end
  endtask

  task automatic reset_n1_dut;
    begin
      @(negedge clk);
      rst_n_n1 = 1'b0;
      fault_valid_n1 = 1'b0;
      fault_code_in_n1 = `FAULT_NONE;
      clear_fault_n1 = 1'b0;
      repeat (2) @(posedge clk);
      @(negedge clk);
      rst_n_n1 = 1'b1;
      @(posedge clk); #1;
    end
  endtask

  task automatic reset_n4_dut;
    begin
      @(negedge clk);
      rst_n_n4 = 1'b0;
      fault_valid_n4 = 1'b0;
      fault_code_in_n4 = `FAULT_NONE;
      clear_fault_n4 = 1'b0;
      repeat (2) @(posedge clk);
      @(negedge clk);
      rst_n_n4 = 1'b1;
      @(posedge clk); #1;
    end
  endtask

  task automatic latch_n4(input [7:0] code_value, input string qid);
    begin
      @(negedge clk);
      fault_valid_n4 = 1'b1;
      fault_code_in_n4 = code_value;
      @(posedge clk); #1;
      if (state_n4 !== ST_FAULT_LATCHED || !fault_latched_n4 || !pwm_disable_n4 || code_latched_n4 !== code_value)
        $fatal(1, "%s N=4 fault setup failed", qid);
    end
  endtask

  task automatic run_qsim09_normal_matrix;
    begin
      $display("Q-SIM-09 clear in NORMAL matrix");

      reset_n4_dut();
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE || pwm_disable_n4)
        $fatal(1, "Q-SIM-09 live=0 clear=0 NORMAL case failed");

      @(negedge clk); clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE || pwm_disable_n4)
        $fatal(1, "Q-SIM-09 safe clear produced a NORMAL-state side effect");
      @(negedge clk); clear_fault_n4 = 1'b0;

      reset_n4_dut();
      @(negedge clk);
      fault_valid_n4 = 1'b1;
      fault_code_in_n4 = `FAULT_OVERCURRENT;
      @(posedge clk); #1;
      if (state_n4 !== ST_FAULT_LATCHED || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
        $fatal(1, "Q-SIM-09 live=1 clear=0 did not latch the new fault");

      reset_n4_dut();
      @(negedge clk);
      fault_valid_n4 = 1'b1;
      fault_code_in_n4 = `FAULT_SENSOR_MISMATCH;
      clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      if (state_n4 !== ST_FAULT_LATCHED || !fault_latched_n4 || code_latched_n4 !== `FAULT_SENSOR_MISMATCH || !pwm_disable_n4)
        $fatal(1, "Q-SIM-09 live fault did not take priority over simultaneous clear");
      @(negedge clk); clear_fault_n4 = 1'b0;
    end
  endtask

  task automatic run_qsim04_clear_live_then_safe;
    begin
      $display("Q-SIM-04 clear while live, source visible safe next cycle");
      reset_n4_dut();
      latch_n4(`FAULT_OVERCURRENT, "Q-SIM-04");
      @(negedge clk); clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      if (state_n4 !== ST_RESET_WAIT || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
        $fatal(1, "Q-SIM-04 E0 request was not retained safely");
      @(negedge clk);
      clear_fault_n4 = 1'b0;
      fault_valid_n4 = 1'b0;
      fault_code_in_n4 = `FAULT_NONE;
      @(posedge clk); #1;
      if (state_n4 !== ST_RESET_WAIT || dut_n4.reset_wait_cnt !== 16'd1 || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
        $fatal(1, "Q-SIM-04 first eligible edge was not based on visible live-low state");
      repeat (3) begin
        @(posedge clk); #1;
      end
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE || !pwm_disable_n4)
        $fatal(1, "Q-SIM-04 N=4 completion edge was incorrect");
      @(posedge clk); #1;
      if (pwm_disable_n4)
        $fatal(1, "Q-SIM-04 registered gate did not release on the following NORMAL edge");
    end
  endtask

  task automatic run_qsim12_default_wait_n4;
    begin
      $display("Q-SIM-12 exact provisional RESET_WAIT_CYCLES=4 E0-E5 characterization");
      reset_n4_dut();
      latch_n4(`FAULT_OVERCURRENT, "Q-SIM-12");
      @(negedge clk);
      fault_valid_n4 = 1'b0;
      fault_code_in_n4 = `FAULT_NONE;
      clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      if (state_n4 !== ST_RESET_WAIT || dut_n4.reset_wait_cnt !== 16'd0 || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
        $fatal(1, "Q-SIM-12 E0 mismatch");
      @(negedge clk); clear_fault_n4 = 1'b0;
      @(posedge clk); #1;
      if (state_n4 !== ST_RESET_WAIT || dut_n4.reset_wait_cnt !== 16'd1 || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
        $fatal(1, "Q-SIM-12 E1 mismatch");
      @(posedge clk); #1;
      if (state_n4 !== ST_RESET_WAIT || dut_n4.reset_wait_cnt !== 16'd2 || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
        $fatal(1, "Q-SIM-12 E2 mismatch");
      @(posedge clk); #1;
      if (state_n4 !== ST_RESET_WAIT || dut_n4.reset_wait_cnt !== 16'd3 || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
        $fatal(1, "Q-SIM-12 E3 mismatch");
      @(posedge clk); #1;
      if (state_n4 !== ST_NORMAL || dut_n4.reset_wait_cnt !== 16'd3 ||
          fault_latched_n4 || code_latched_n4 !== `FAULT_NONE || !pwm_disable_n4)
        $fatal(1, "Q-SIM-12 E4 atomic latch/code clear mismatch");
      @(posedge clk); #1;
      if (state_n4 !== ST_NORMAL || dut_n4.reset_wait_cnt !== 16'd0 ||
          fault_latched_n4 || code_latched_n4 !== `FAULT_NONE || pwm_disable_n4)
        $fatal(1, "Q-SIM-12 E5 registered pwm_disable release mismatch");
    end
  endtask

  task automatic run_qsim13_parameter_boundaries;
    begin
      $display("Q-SIM-13 current RTL parameter-boundary characterization N=1/2/4");

      reset_n1_dut();
      @(negedge clk);
      fault_valid_n1 = 1'b1;
      fault_code_in_n1 = `FAULT_OVERCURRENT;
      @(posedge clk); #1;
      if (!fault_latched_n1 || state_n1 !== ST_FAULT_LATCHED) $fatal(1, "Q-SIM-13 N=1 setup failed");
      @(negedge clk);
      fault_valid_n1 = 1'b0;
      fault_code_in_n1 = `FAULT_NONE;
      clear_fault_n1 = 1'b1;
      @(posedge clk); #1;
      if (state_n1 !== ST_RESET_WAIT || dut_n1.reset_wait_cnt !== 16'd0 || !fault_latched_n1 ||
          code_latched_n1 !== `FAULT_OVERCURRENT || !pwm_disable_n1)
        $fatal(1, "Q-SIM-13 N=1 E0 mismatch");
      @(negedge clk); clear_fault_n1 = 1'b0;
      @(posedge clk); #1;
      if (state_n1 !== ST_NORMAL || dut_n1.reset_wait_cnt !== 16'd0 ||
          fault_latched_n1 || code_latched_n1 !== `FAULT_NONE || !pwm_disable_n1)
        $fatal(1, "Q-SIM-13 N=1 completion mismatch");
      @(posedge clk); #1;
      if (state_n1 !== ST_NORMAL || fault_latched_n1 || code_latched_n1 !== `FAULT_NONE ||
          dut_n1.reset_wait_cnt !== 16'd0 || pwm_disable_n1)
        $fatal(1, "Q-SIM-13 N=1 gate release/stability mismatch");

      reset_main_dut();
      @(negedge clk);
      fault_valid = 1'b1;
      fault_code_in = `FAULT_SENSOR_MISMATCH;
      @(posedge clk); #1;
      if (!fault_latched || state !== ST_FAULT_LATCHED) $fatal(1, "Q-SIM-13 N=2 setup failed");
      @(negedge clk);
      fault_valid = 1'b0;
      fault_code_in = `FAULT_NONE;
      clear_fault = 1'b1;
      @(posedge clk); #1;
      if (state !== ST_RESET_WAIT || dut.reset_wait_cnt !== 16'd0 || !fault_latched ||
          code_latched !== `FAULT_SENSOR_MISMATCH || !pwm_disable)
        $fatal(1, "Q-SIM-13 N=2 E0 mismatch");
      @(negedge clk); clear_fault = 1'b0;
      @(posedge clk); #1;
      if (state !== ST_RESET_WAIT || dut.reset_wait_cnt !== 16'd1 || !fault_latched ||
          code_latched !== `FAULT_SENSOR_MISMATCH || !pwm_disable)
        $fatal(1, "Q-SIM-13 N=2 first eligible edge mismatch");
      @(posedge clk); #1;
      if (state !== ST_NORMAL || dut.reset_wait_cnt !== 16'd1 ||
          fault_latched || code_latched !== `FAULT_NONE || !pwm_disable)
        $fatal(1, "Q-SIM-13 N=2 completion mismatch");
      @(posedge clk); #1;
      if (state !== ST_NORMAL || fault_latched || code_latched !== `FAULT_NONE ||
          dut.reset_wait_cnt !== 16'd0 || pwm_disable)
        $fatal(1, "Q-SIM-13 N=2 gate release/stability mismatch");

      run_qsim12_default_wait_n4();
    end
  endtask

  task automatic run_enh_fsm_reset_dominance;
    begin
      $display("ENH FSM asynchronous reset dominance in LATCHED and active RESET_WAIT");

      reset_n4_dut();
      latch_n4(`FAULT_OVERCURRENT, "ENH reset dominance LATCHED");
      @(negedge clk);
      rst_n_n4 = 1'b0;
      #1;
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE ||
          dut_n4.reset_wait_cnt !== 16'd0 || pwm_disable_n4)
        $fatal(1, "ENH asynchronous reset did not dominate ST_FAULT_LATCHED");
      fault_valid_n4 = 1'b0;
      fault_code_in_n4 = `FAULT_NONE;
      clear_fault_n4 = 1'b0;
      @(negedge clk); rst_n_n4 = 1'b1;
      @(posedge clk); #1;
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE ||
          dut_n4.reset_wait_cnt !== 16'd0 || pwm_disable_n4)
        $fatal(1, "ENH stale LATCHED state revived after reset release");

      reset_n4_dut();
      latch_n4(`FAULT_SENSOR_MISMATCH, "ENH reset dominance RESET_WAIT");
      @(negedge clk);
      fault_valid_n4 = 1'b0;
      fault_code_in_n4 = `FAULT_NONE;
      clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault_n4 = 1'b0;
      @(posedge clk); #1;
      if (state_n4 !== ST_RESET_WAIT || dut_n4.reset_wait_cnt !== 16'd1 ||
          !fault_latched_n4 || code_latched_n4 !== `FAULT_SENSOR_MISMATCH || !pwm_disable_n4)
        $fatal(1, "ENH RESET_WAIT reset-dominance setup failed");
      @(negedge clk);
      rst_n_n4 = 1'b0;
      #1;
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE ||
          dut_n4.reset_wait_cnt !== 16'd0 || pwm_disable_n4)
        $fatal(1, "ENH asynchronous reset did not dominate active RESET_WAIT");
      @(negedge clk); rst_n_n4 = 1'b1;
      @(posedge clk); #1;
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE ||
          dut_n4.reset_wait_cnt !== 16'd0 || pwm_disable_n4)
        $fatal(1, "ENH stale recovery progress revived after reset release");
    end
  endtask

  task automatic run_qsim07_repeated_clear;
    begin
      $display("Q-SIM-07 repeated one-cycle clear pauses but does not reset progress");
      reset_n4_dut();
      latch_n4(`FAULT_OVERCURRENT, "Q-SIM-07");
      @(negedge clk); fault_valid_n4 = 1'b0; clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault_n4 = 1'b0;
      @(posedge clk); #1;
      if (dut_n4.reset_wait_cnt !== 16'd1) $fatal(1, "Q-SIM-07 initial progress mismatch");
      @(negedge clk); clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      if (state_n4 !== ST_RESET_WAIT || dut_n4.reset_wait_cnt !== 16'd1 || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
        $fatal(1, "Q-SIM-07 first repeated pulse changed progress or protection");
      @(negedge clk); clear_fault_n4 = 1'b0;
      @(posedge clk); #1;
      if (dut_n4.reset_wait_cnt !== 16'd2) $fatal(1, "Q-SIM-07 progress did not resume after first pulse");
      @(negedge clk); clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      if (state_n4 !== ST_RESET_WAIT || dut_n4.reset_wait_cnt !== 16'd2 || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
        $fatal(1, "Q-SIM-07 second repeated pulse changed progress or protection");
      @(negedge clk); clear_fault_n4 = 1'b0;
      @(posedge clk); #1;
      if (dut_n4.reset_wait_cnt !== 16'd3) $fatal(1, "Q-SIM-07 delayed E3 mismatch");
      @(posedge clk); #1;
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE || !pwm_disable_n4)
        $fatal(1, "Q-SIM-07 delayed completion edge mismatch");
      @(posedge clk); #1;
      if (pwm_disable_n4) $fatal(1, "Q-SIM-07 delayed E5 mismatch");
    end
  endtask

  task automatic run_qsim08_held_clear;
    integer hold_cycle;
    begin
      $display("Q-SIM-08 bounded held-high clear freezes wait progress");
      reset_n4_dut();
      latch_n4(`FAULT_OVERCURRENT, "Q-SIM-08");
      @(negedge clk); fault_valid_n4 = 1'b0; clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault_n4 = 1'b0;
      @(posedge clk); #1;
      if (dut_n4.reset_wait_cnt !== 16'd1) $fatal(1, "Q-SIM-08 initial progress mismatch");
      @(negedge clk); clear_fault_n4 = 1'b1;
      for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
        @(posedge clk); #1;
        if (state_n4 !== ST_RESET_WAIT || dut_n4.reset_wait_cnt !== 16'd1 || !fault_latched_n4 || code_latched_n4 !== `FAULT_OVERCURRENT || !pwm_disable_n4)
          $fatal(1, "Q-SIM-08 held-high cycle %0d did not freeze safely", hold_cycle);
      end
      @(negedge clk); clear_fault_n4 = 1'b0;
      repeat (3) @(posedge clk);
      #1;
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE || !pwm_disable_n4)
        $fatal(1, "Q-SIM-08 completion did not resume from retained progress");
      @(posedge clk); #1;
      if (pwm_disable_n4) $fatal(1, "Q-SIM-08 E5 mismatch");
    end
  endtask

  task automatic run_qsim06_policy_b_characterization;
    begin
      $display("Q-SIM-06 current RTL Policy B characterization only");
      reset_n4_dut();
      latch_n4(`FAULT_OVERCURRENT, "Q-SIM-06");
      @(negedge clk); fault_valid_n4 = 1'b0; clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault_n4 = 1'b0;
      @(posedge clk); #1;
      @(negedge clk);
      fault_valid_n4 = 1'b1;
      fault_code_in_n4 = `FAULT_SENSOR_MISMATCH;
      @(posedge clk); #1;
      if (state_n4 !== ST_FAULT_LATCHED || !fault_latched_n4 || code_latched_n4 !== `FAULT_SENSOR_MISMATCH || !pwm_disable_n4)
        $fatal(1, "Q-SIM-06 failed recovery did not update the latched code to live code B");
    end
  endtask

  task automatic run_qsim05_reassertion_boundaries;
    begin
      $display("Q-SIM-05 early, candidate-final, and post-completion reassertion boundaries");

      reset_n4_dut();
      latch_n4(`FAULT_OVERCURRENT, "Q-SIM-05 early");
      @(negedge clk); fault_valid_n4 = 1'b0; clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault_n4 = 1'b0;
      @(posedge clk); #1;
      @(negedge clk); fault_valid_n4 = 1'b1; fault_code_in_n4 = `FAULT_SENSOR_OPEN;
      @(posedge clk); #1;
      if (state_n4 !== ST_FAULT_LATCHED || !fault_latched_n4 || code_latched_n4 !== `FAULT_SENSOR_OPEN || !pwm_disable_n4)
        $fatal(1, "Q-SIM-05 early wait reassertion allowed an unsafe interval");

      reset_n4_dut();
      latch_n4(`FAULT_OVERCURRENT, "Q-SIM-05 final");
      @(negedge clk); fault_valid_n4 = 1'b0; clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault_n4 = 1'b0;
      repeat (3) @(posedge clk);
      #1;
      if (dut_n4.reset_wait_cnt !== 16'd3) $fatal(1, "Q-SIM-05 candidate-final setup mismatch");
      @(negedge clk); fault_valid_n4 = 1'b1; fault_code_in_n4 = `FAULT_SENSOR_SATURATION;
      @(posedge clk); #1;
      if (state_n4 !== ST_FAULT_LATCHED || !fault_latched_n4 || code_latched_n4 !== `FAULT_SENSOR_SATURATION || !pwm_disable_n4)
        $fatal(1, "Q-SIM-05 candidate completion edge did not give live fault priority");

      reset_n4_dut();
      latch_n4(`FAULT_OVERCURRENT, "Q-SIM-05 post-completion");
      @(negedge clk); fault_valid_n4 = 1'b0; clear_fault_n4 = 1'b1;
      @(posedge clk); #1;
      @(negedge clk); clear_fault_n4 = 1'b0;
      repeat (4) @(posedge clk);
      #1;
      if (state_n4 !== ST_NORMAL || fault_latched_n4 || code_latched_n4 !== `FAULT_NONE || !pwm_disable_n4)
        $fatal(1, "Q-SIM-05 post-completion E4 setup mismatch");
      @(negedge clk); fault_valid_n4 = 1'b1; fault_code_in_n4 = `FAULT_SENSOR_MISMATCH;
      @(posedge clk); #1;
      if (state_n4 !== ST_FAULT_LATCHED || !fault_latched_n4 || code_latched_n4 !== `FAULT_SENSOR_MISMATCH || !pwm_disable_n4)
        $fatal(1, "Q-SIM-05 post-completion visible fault did not keep protection asserted at E5");
    end
  endtask
  initial begin
    repeat(2) @(posedge clk); rst_n=1;
    @(negedge clk); fault_valid=1; fault_code_in=`FAULT_OVERCURRENT; @(posedge clk); #1;
    if (!fault_latched || !pwm_disable || code_latched !== `FAULT_OVERCURRENT) $fatal(1,"fault latch failed");
    @(negedge clk); clear_fault=1; @(posedge clk); #1;
    if (!fault_latched || !pwm_disable) $fatal(1,"clear_fault must not release protection while fault_valid is high");
    @(negedge clk); clear_fault=0; repeat(2) @(posedge clk); #1;
    if (!fault_latched || !pwm_disable) $fatal(1,"fault must remain latched while fault persists");
    @(negedge clk); fault_valid=0; clear_fault=1; @(posedge clk); #1;
    if (!pwm_disable) $fatal(1,"pwm must stay disabled during clear");
    @(negedge clk); clear_fault=0; repeat(3) @(posedge clk); #1;
    if (fault_latched || pwm_disable) $fatal(1,"fsm did not recover");

    run_qsim09_normal_matrix();
    run_qsim04_clear_live_then_safe();
    run_qsim13_parameter_boundaries();
    run_qsim07_repeated_clear();
    run_qsim08_held_clear();
    run_qsim06_policy_b_characterization();
    run_qsim05_reassertion_boundaries();
    run_enh_fsm_reset_dominance();

    $display("tb_protection_fsm PASS"); $finish;
  end
endmodule
