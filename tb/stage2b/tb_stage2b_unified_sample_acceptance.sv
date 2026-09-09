`timescale 1ns/1ps
`include "fault_defs.vh"

module tb_stage2b_unified_sample_acceptance;
  localparam integer DATA_WIDTH = 12;
  localparam integer HEALTH_CNT_WIDTH = 4;
  localparam [3:0] ST_NORMAL = 4'd0;
  localparam [3:0] ST_FAULT_LATCHED = 4'd1;
  localparam [3:0] ST_RESET_WAIT = 4'd2;

  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg sample_valid = 1'b0;
  reg pwm_enable = 1'b1;
  reg clear_fault = 1'b0;
  reg [11:0] i_ch1 = 12'd500;
  reg [11:0] i_ch2 = 12'd510;
  reg [11:0] th_oc_ch1 = 12'd1000;
  reg [11:0] th_oc_ch2 = 12'd1000;
  reg [11:0] th_diff = 12'd100;
  reg [11:0] th_open = 12'd10;
  reg [11:0] th_sat = 12'd4090;
  reg [11:0] th_stuck_delta = 12'd0;
  reg [3:0] th_persist = 4'd15;
  reg [15:0] pwm_period = 16'd4;
  reg [15:0] pwm_duty = 16'd2;

  wire pwm_raw;
  wire pwm_out;
  wire oc_any;
  wire oc_both;
  wire mismatch_flag;
  wire sensor_open_flag;
  wire sensor_sat_flag;
  wire sensor_stuck_flag;
  wire fault_valid;
  wire fault_latched;
  wire [7:0] fault_code;
  wire [7:0] fault_code_latched;
  wire [3:0] fsm_state;
  wire [11:0] abs_diff;

  wire [31:0] checker_accepted_count;
  wire [31:0] checker_invalid_pair_hold_count;
  wire [31:0] checker_back_to_back_count;
  wire [31:0] checker_reset_release_first_accept_count;

  integer n;
  integer saved_open_cnt;
  integer saved_sat_cnt;
  integer saved_stuck_cnt;
  reg [23:0] saved_accepted_pair;
  reg [11:0] saved_health_ch1;
  reg [11:0] saved_health_ch2;

  always #5 clk = ~clk;

  protection_core_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .CNT_WIDTH(16),
    .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH)
  ) dut (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid),
    .pwm_enable(pwm_enable), .clear_fault(clear_fault),
    .i_ch1(i_ch1), .i_ch2(i_ch2),
    .th_oc_ch1(th_oc_ch1), .th_oc_ch2(th_oc_ch2),
    .th_diff(th_diff), .th_open(th_open), .th_sat(th_sat),
    .th_stuck_delta(th_stuck_delta), .th_persist(th_persist),
    .period(pwm_period), .duty(pwm_duty),
    .pwm_raw(pwm_raw), .pwm_out(pwm_out),
    .oc_any(oc_any), .oc_both(oc_both),
    .mismatch_flag(mismatch_flag),
    .sensor_open_flag(sensor_open_flag),
    .sensor_sat_flag(sensor_sat_flag),
    .sensor_stuck_flag(sensor_stuck_flag),
    .fault_valid(fault_valid), .fault_latched(fault_latched),
    .fault_code(fault_code), .fault_code_latched(fault_code_latched),
    .fsm_state(fsm_state), .abs_diff(abs_diff)
  );

  stage2b_sample_acceptance_checker #(
    .DATA_WIDTH(DATA_WIDTH),
    .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH)
  ) u_checker (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid),
    .clear_fault(clear_fault), .i_ch1(i_ch1), .i_ch2(i_ch2),
    .th_oc_ch1(th_oc_ch1), .th_oc_ch2(th_oc_ch2),
    .th_diff(th_diff), .th_open(th_open), .th_sat(th_sat),
    .th_stuck_delta(th_stuck_delta), .th_persist(th_persist),
    // READ_ONLY_HIERARCHICAL_OBSERVATION=YES. No checker or test process
    // assigns, forces, or deposits any DUT object.
    .sample_accept_event(dut.sample_accept_event),
    .accepted_sample_pair(dut.accepted_sample_pair),
    .accepted_sample_valid(dut.accepted_sample_valid),
    .sample_decision_valid(dut.sample_decision_valid),
    .decision_oc_any(dut.decision_oc_any),
    .decision_oc_both(dut.decision_oc_both),
    .decision_mismatch_flag(dut.decision_mismatch_flag),
    .oc_any(oc_any), .oc_both(oc_both),
    .mismatch_flag(mismatch_flag), .abs_diff(abs_diff),
    .sensor_open_flag(sensor_open_flag),
    .sensor_sat_flag(sensor_sat_flag),
    .sensor_stuck_flag(sensor_stuck_flag),
    .sensor_open_event(dut.sensor_open_event),
    .sensor_sat_event(dut.sensor_sat_event),
    .sensor_stuck_event(dut.sensor_stuck_event),
    .health_prev_ch1(dut.u_health.prev_ch1),
    .health_prev_ch2(dut.u_health.prev_ch2),
    .health_open_cnt(dut.u_health.open_cnt),
    .health_sat_cnt(dut.u_health.sat_cnt),
    .health_stuck_cnt(dut.u_health.stuck_cnt),
    .fault_valid(fault_valid), .fault_code(fault_code),
    .fault_latched(fault_latched),
    .fault_code_latched(fault_code_latched),
    .fsm_state(fsm_state), .pwm_out(pwm_out),
    .accepted_count(checker_accepted_count),
    .invalid_pair_hold_count(checker_invalid_pair_hold_count),
    .back_to_back_count(checker_back_to_back_count),
    .reset_release_first_accept_count(
      checker_reset_release_first_accept_count)
  );

  task automatic check_true(input string label, input logic condition);
    begin
      if (condition !== 1'b1)
        $fatal(1, "STAGE2B DUT TEST FAILED: %s", label);
    end
  endtask

  task automatic scenario_pass(input string scenario);
    begin
      $display("%s=PASS", scenario);
    end
  endtask

  task automatic configure_nominal;
    begin
      th_oc_ch1 = 12'd1000;
      th_oc_ch2 = 12'd1000;
      th_diff = 12'd100;
      th_open = 12'd10;
      th_sat = 12'd4090;
      th_stuck_delta = 12'd0;
      th_persist = 4'd15;
      pwm_period = 16'd4;
      pwm_duty = 16'd2;
    end
  endtask

  task automatic configure_health_fast;
    begin
      th_oc_ch1 = 12'hfff;
      th_oc_ch2 = 12'hfff;
      th_diff = 12'hfff;
      th_open = 12'd10;
      th_sat = 12'd4090;
      th_stuck_delta = 12'd0;
      th_persist = 4'd2;
      pwm_period = 16'd4;
      pwm_duty = 16'd2;
    end
  endtask

  task automatic drive_edge(
    input logic valid_value,
    input [11:0] sample1,
    input [11:0] sample2
  );
    begin
      @(negedge clk);
      sample_valid = valid_value;
      i_ch1 = sample1;
      i_ch2 = sample2;
      @(posedge clk);
      #2;
    end
  endtask

  task automatic reset_idle;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      sample_valid = 1'b0;
      clear_fault = 1'b0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd510;
      configure_nominal();
      @(posedge clk);
      #2;
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
      #2;
      check_true("reset release is normal",
        (fsm_state === ST_NORMAL) && !fault_latched && !fault_valid);
    end
  endtask

  task automatic drain_pipeline;
    integer guard;
    begin
      guard = 0;
      while (dut.accepted_sample_valid || dut.sample_decision_valid ||
             fault_valid) begin
        drive_edge(1'b0, i_ch1, i_ch2);
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "STAGE2B DUT TEST FAILED: pipeline drain timeout");
      end
    end
  endtask

  task automatic wait_for_latch(input [7:0] expected_code);
    integer guard;
    begin
      guard = 0;
      while (!fault_latched) begin
        drive_edge(1'b0, i_ch1, i_ch2);
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "STAGE2B DUT TEST FAILED: latch timeout");
      end
      check_true("fault latch expected code",
                 fault_code_latched === expected_code);
      check_true("fault latch safe output", pwm_out === 1'b0);
    end
  endtask

  task automatic make_overcurrent_latch;
    begin
      drive_edge(1'b1, 12'd1200, 12'd1200);
      wait_for_latch(`FAULT_OVERCURRENT);
      drain_pipeline();
      check_true("latched overcurrent pipeline drained",
                 fault_latched && !fault_valid);
    end
  endtask

  task automatic clear_recover_during_invalid;
    begin
      check_true("clear recovery precondition",
                 fault_latched && !fault_valid);
      @(negedge clk);
      sample_valid = 1'b0;
      i_ch1 = 12'd1500;
      i_ch2 = 12'd1510;
      clear_fault = 1'b1;
      @(posedge clk);
      #2;
      check_true("clear E0 enters reset wait",
        (fsm_state === ST_RESET_WAIT) && fault_latched &&
        (dut.u_fsm.reset_wait_cnt === 16'd0));
      @(negedge clk);
      clear_fault = 1'b0;
      for (n = 1; n <= 4; n = n + 1) begin
        sample_valid = 1'b0;
        if (n[0]) begin
          i_ch1 = 12'd50;
          i_ch2 = 12'd900;
        end else begin
          i_ch1 = 12'd1600;
          i_ch2 = 12'd1610;
        end
        @(posedge clk);
        #2;
        if (n < 4)
          check_true("clear recovery remains protected",
                     (fsm_state === ST_RESET_WAIT) && fault_latched &&
                     dut.u_fsm.pwm_disable);
        if (n != 4)
          @(negedge clk);
      end
      check_true("clear E4 clears latch atomically",
        (fsm_state === ST_NORMAL) && !fault_latched &&
        (fault_code_latched === `FAULT_NONE) && dut.u_fsm.pwm_disable);
      drive_edge(1'b0, 12'd1700, 12'd1710);
      check_true("clear E5 releases gate without stale replay",
        (fsm_state === ST_NORMAL) && !fault_latched && !fault_valid &&
        !dut.u_fsm.pwm_disable);
    end
  endtask

  task automatic make_sensor_open_latch;
    begin
      drive_edge(1'b1, 12'd0, 12'd500);
      drive_edge(1'b1, 12'd0, 12'd500);
      drive_edge(1'b1, 12'd0, 12'd500);
      drive_edge(1'b0, 12'd2000, 12'd2100);
      check_true("open trigger transaction event",
        dut.sample_decision_valid && dut.sensor_open_event &&
        !dut.sensor_sat_event && !dut.sensor_stuck_event &&
        sensor_open_flag && !fault_valid);
      drive_edge(1'b0, 12'd2100, 12'd2200);
      check_true("open aligned classifier event",
        fault_valid && (fault_code === `FAULT_SENSOR_OPEN) &&
        !fault_latched);
      drive_edge(1'b0, 12'd2200, 12'd2300);
      check_true("open event latches",
        fault_latched &&
        (fault_code_latched === `FAULT_SENSOR_OPEN) &&
        dut.u_fsm.pwm_disable && (pwm_out === 1'b0));
      drain_pipeline();
    end
  endtask

  task automatic make_sensor_saturation_latch;
    begin
      drive_edge(1'b1, 12'd4095, 12'd1000);
      drive_edge(1'b1, 12'd4095, 12'd1000);
      drive_edge(1'b1, 12'd4095, 12'd1000);
      drive_edge(1'b0, 12'd200, 12'd300);
      check_true("saturation trigger transaction event",
        dut.sample_decision_valid && !dut.sensor_open_event &&
        dut.sensor_sat_event && !dut.sensor_stuck_event &&
        sensor_sat_flag && !fault_valid);
      drive_edge(1'b0, 12'd300, 12'd400);
      check_true("saturation aligned classifier event",
        fault_valid && (fault_code === `FAULT_SENSOR_SATURATION) &&
        !fault_latched);
      drive_edge(1'b0, 12'd400, 12'd500);
      check_true("saturation event latches",
        fault_latched &&
        (fault_code_latched === `FAULT_SENSOR_SATURATION) &&
        dut.u_fsm.pwm_disable && (pwm_out === 1'b0));
      drain_pipeline();
    end
  endtask

  task automatic make_sensor_stuck_latch;
    begin
      drive_edge(1'b1, 12'd500, 12'd510);
      drive_edge(1'b1, 12'd500, 12'd510);
      drive_edge(1'b1, 12'd500, 12'd510);
      drive_edge(1'b1, 12'd500, 12'd510);
      drive_edge(1'b0, 12'd2000, 12'd2100);
      check_true("stuck trigger transaction event",
        dut.sample_decision_valid && !dut.sensor_open_event &&
        !dut.sensor_sat_event && dut.sensor_stuck_event &&
        sensor_stuck_flag && !fault_valid);
      drive_edge(1'b0, 12'd2100, 12'd2200);
      check_true("stuck aligned classifier event",
        fault_valid && (fault_code === `FAULT_SENSOR_STUCK) &&
        !fault_latched);
      drive_edge(1'b0, 12'd2200, 12'd2300);
      check_true("stuck event latches",
        fault_latched &&
        (fault_code_latched === `FAULT_SENSOR_STUCK) &&
        dut.u_fsm.pwm_disable && (pwm_out === 1'b0));
      drain_pipeline();
    end
  endtask

  task automatic consume_fresh_safe_pair(
    input [11:0] safe_ch1,
    input [11:0] safe_ch2,
    input logic expect_open_state,
    input logic expect_sat_state,
    input logic expect_stuck_state
  );
    begin
      drive_edge(1'b1, safe_ch1, safe_ch2);
      check_true("fresh safe pair accepted",
        dut.accepted_sample_valid &&
        (dut.accepted_sample_pair === {safe_ch1, safe_ch2}));
      drive_edge(1'b0, 12'd3000, 12'd3010);
      check_true("fresh safe transaction has no health event",
        dut.sample_decision_valid && !dut.sensor_open_event &&
        !dut.sensor_sat_event && !dut.sensor_stuck_event);
      check_true("retained diagnostic state is not an event",
        (sensor_open_flag === expect_open_state) &&
        (sensor_sat_flag === expect_sat_state) &&
        (sensor_stuck_flag === expect_stuck_state));
      drive_edge(1'b0, 12'd3100, 12'd3110);
      check_true("fresh safe transaction has no classifier event",
        !fault_valid && (fault_code === `FAULT_NONE));
      check_true("fresh safe transaction does not relatch",
        !fault_latched && (fault_code_latched === `FAULT_NONE) &&
        (fsm_state === ST_NORMAL) && !dut.u_fsm.pwm_disable &&
        (pwm_out === pwm_raw));
      drain_pipeline();
    end
  endtask

  task automatic clear_retained_health_state;
    begin
      drive_edge(1'b1, 12'd600, 12'd620);
      drive_edge(1'b1, 12'd700, 12'd730);
      drive_edge(1'b0, 12'd3000, 12'd3010);
      drive_edge(1'b0, 12'd3100, 12'd3110);
      check_true("moving safe transactions clear retained health state",
        !sensor_open_flag && !sensor_sat_flag && !sensor_stuck_flag &&
        !dut.sensor_open_event && !dut.sensor_sat_event &&
        !dut.sensor_stuck_event && !fault_valid && !fault_latched &&
        (fsm_state === ST_NORMAL) && !dut.u_fsm.pwm_disable);
      drain_pipeline();
    end
  endtask

  initial begin
    configure_nominal();

    // SB01: reset asserted with valid low.
    @(posedge clk);
    #2;
    check_true("SB01 accepted stage reset",
      !dut.accepted_sample_valid && !dut.sample_decision_valid &&
      (dut.accepted_sample_pair === 24'd0));
    scenario_pass("SB01");

    // SB02: reset dominates high valid and fault-valued input.
    @(negedge clk);
    sample_valid = 1'b1;
    i_ch1 = 12'd1500;
    i_ch2 = 12'd1510;
    @(posedge clk);
    #2;
    check_true("SB02 reset priority",
      !dut.accepted_sample_valid && !fault_valid && !fault_latched);
    scenario_pass("SB02");

    // SB03: first valid after reset release is accepted at that edge.
    @(negedge clk);
    rst_n = 1'b1;
    sample_valid = 1'b1;
    i_ch1 = 12'h123;
    i_ch2 = 12'h456;
    @(posedge clk);
    #2;
    check_true("SB03 first accepted pair",
      dut.accepted_sample_valid &&
      (dut.accepted_sample_pair === {12'h123, 12'h456}) &&
      (checker_reset_release_first_accept_count === 32'd1));
    scenario_pass("SB03");

    // SB04: isolated safe transaction.
    reset_idle();
    drive_edge(1'b1, 12'd500, 12'd510);
    drain_pipeline();
    check_true("SB04 isolated safe sample",
      (checker_accepted_count === 32'd1) && !fault_valid && !fault_latched);
    scenario_pass("SB04");

    // SB05: exact overcurrent pipeline timing.
    reset_idle();
    drive_edge(1'b1, 12'd1001, 12'd950); // N0
    check_true("SB05 N0 accepted only",
      dut.accepted_sample_valid && !dut.sample_decision_valid &&
      !fault_valid && !fault_latched);
    drive_edge(1'b0, 12'd3000, 12'd3000); // N2a, one elapsed cycle
    check_true("SB05 N2a comparator snapshot",
      dut.sample_decision_valid && dut.decision_oc_any &&
      !fault_valid && !fault_latched);
    drive_edge(1'b0, 12'd0, 12'd4095); // N2b, two elapsed cycles
    check_true("SB05 N2b classifier",
      fault_valid && (fault_code === `FAULT_OVERCURRENT) && !fault_latched);
    drive_edge(1'b0, 12'd3500, 12'd10); // N3/N4, three elapsed cycles
    check_true("SB05 N3/N4 latch and safe",
      fault_latched && (fault_code_latched === `FAULT_OVERCURRENT) &&
      dut.u_fsm.pwm_disable && (pwm_out === 1'b0));
    scenario_pass("SB05");

    // SB06: threshold-1, equality, and threshold+1 retain strict > math.
    reset_idle();
    drive_edge(1'b1, 12'd999, 12'd950);
    drain_pipeline();
    check_true("SB06 threshold minus one safe", !fault_latched);
    drive_edge(1'b1, 12'd1000, 12'd950);
    drain_pipeline();
    check_true("SB06 threshold equality safe", !fault_latched);
    drive_edge(1'b1, 12'd1001, 12'd950);
    wait_for_latch(`FAULT_OVERCURRENT);
    scenario_pass("SB06");

    // SB07: two adjacent valid edges preserve order and both transactions.
    reset_idle();
    drive_edge(1'b1, 12'h111, 12'h222);
    drive_edge(1'b1, 12'h333, 12'h444);
    check_true("SB07 second pair accepted while first is consumed",
      (dut.accepted_sample_pair === {12'h333, 12'h444}) &&
      (dut.u_health.prev_ch1 === 12'h111) &&
      (dut.u_health.prev_ch2 === 12'h222));
    drive_edge(1'b0, 12'hfff, 12'h000);
    check_true("SB07 second pair reaches health atomically",
      (dut.u_health.prev_ch1 === 12'h333) &&
      (dut.u_health.prev_ch2 === 12'h444) &&
      (checker_accepted_count === 32'd2) &&
      (checker_back_to_back_count === 32'd1));
    drain_pipeline();
    scenario_pass("SB07");

    // SB08: held-high valid accepts one changing pair on every edge.
    reset_idle();
    drive_edge(1'b1, 12'h101, 12'h201);
    drive_edge(1'b1, 12'h102, 12'h202);
    drive_edge(1'b1, 12'h103, 12'h203);
    check_true("SB08 latest held-high pair accepted",
      dut.accepted_sample_pair === {12'h103, 12'h203});
    drive_edge(1'b0, 12'hfff, 12'hfff);
    check_true("SB08 every held-high pair consumed",
      (checker_accepted_count === 32'd3) &&
      (checker_back_to_back_count === 32'd2) &&
      (dut.u_health.prev_ch1 === 12'h103) &&
      (dut.u_health.prev_ch2 === 12'h203));
    drain_pipeline();
    scenario_pass("SB08");

    // SB09: a one-cycle invalid gap holds the accepted pair.
    reset_idle();
    drive_edge(1'b1, 12'd500, 12'd510);
    drive_edge(1'b0, 12'd1800, 12'd1900);
    check_true("SB09 one-cycle gap isolates raw faulting pair",
      !dut.accepted_sample_valid &&
      (dut.accepted_sample_pair === {12'd500, 12'd510}) && !oc_any);
    drive_edge(1'b1, 12'd520, 12'd530);
    check_true("SB09 gap then valid captures fresh pair",
      dut.accepted_sample_pair === {12'd520, 12'd530});
    drain_pipeline();
    check_true("SB09 no gap fault", !fault_latched);
    scenario_pass("SB09");

    // SB10: a multi-cycle gap holds pair and health state.
    reset_idle();
    drive_edge(1'b1, 12'd600, 12'd610);
    drive_edge(1'b0, 12'd600, 12'd610);
    drain_pipeline();
    saved_accepted_pair = dut.accepted_sample_pair;
    saved_health_ch1 = dut.u_health.prev_ch1;
    saved_health_ch2 = dut.u_health.prev_ch2;
    saved_open_cnt = dut.u_health.open_cnt;
    saved_sat_cnt = dut.u_health.sat_cnt;
    saved_stuck_cnt = dut.u_health.stuck_cnt;
    for (n = 0; n < 4; n = n + 1) begin
      if (n[0])
        drive_edge(1'b0, 12'd2000 + n, 12'd10 + n);
      else
        drive_edge(1'b0, 12'd0 + n, 12'd4095 - n);
    end
    check_true("SB10 multi-gap complete hold",
      (dut.accepted_sample_pair === saved_accepted_pair) &&
      (dut.u_health.prev_ch1 === saved_health_ch1) &&
      (dut.u_health.prev_ch2 === saved_health_ch2) &&
      (dut.u_health.open_cnt === saved_open_cnt[3:0]) &&
      (dut.u_health.sat_cnt === saved_sat_cnt[3:0]) &&
      (dut.u_health.stuck_cnt === saved_stuck_cnt[3:0]));
    scenario_pass("SB10");

    // SB11: invalid raw faulting changes cannot create a new fault event.
    reset_idle();
    drive_edge(1'b1, 12'd500, 12'd510);
    drain_pipeline();
    for (n = 0; n < 6; n = n + 1) begin
      if (n[0])
        drive_edge(1'b0, 12'd1700, 12'd1710);
      else
        drive_edge(1'b0, 12'd50, 12'd900);
      check_true("SB11 invalid event suppression each edge",
        !fault_valid && !fault_latched && !dut.u_fsm.pwm_disable);
    end
    check_true("SB11 accepted comparator remains safe", !oc_any && !mismatch_flag);
    scenario_pass("SB11");

    // SB12: an existing latch retains through invalid gaps without new events.
    reset_idle();
    make_overcurrent_latch();
    for (n = 0; n < 4; n = n + 1) begin
      drive_edge(1'b0, 12'd50 + n, 12'd2000 - n);
      check_true("SB12 retention is not a new live event",
        !fault_valid && fault_latched &&
        (fault_code_latched === `FAULT_OVERCURRENT));
    end
    scenario_pass("SB12");

    // SB13: clear in an invalid interval cannot replay the accepted fault.
    reset_idle();
    make_overcurrent_latch();
    clear_recover_during_invalid();
    for (n = 0; n < 4; n = n + 1)
      drive_edge(1'b0, 12'd1800 + n, 12'd1810 + n);
    check_true("SB13 stale accepted sample stays suppressed",
      !fault_valid && !fault_latched && (fsm_state === ST_NORMAL) &&
      !dut.u_fsm.pwm_disable);
    scenario_pass("SB13");

    // SB14: a fresh faulting transaction after clear retriggers normally.
    reset_idle();
    make_overcurrent_latch();
    clear_recover_during_invalid();
    drive_edge(1'b1, 12'd1300, 12'd1310);
    wait_for_latch(`FAULT_OVERCURRENT);
    scenario_pass("SB14");

    // SB15: a fresh comparator-safe transaction after clear remains clear.
    reset_idle();
    make_overcurrent_latch();
    clear_recover_during_invalid();
    drive_edge(1'b1, 12'd500, 12'd510);
    drain_pipeline();
    check_true("SB15 comparator-safe transaction remains clear",
      !fault_valid && !fault_latched && (fsm_state === ST_NORMAL));
    scenario_pass("SB15");

    // SB16: health history pauses in a gap and resumes on first valid.
    reset_idle();
    configure_health_fast();
    drive_edge(1'b1, 12'd0, 12'd500);
    drive_edge(1'b0, 12'd2000, 12'd2100);
    check_true("SB16 first open count consumed",
      dut.u_health.open_cnt === 4'd1);
    for (n = 0; n < 3; n = n + 1)
      drive_edge(1'b0, 12'd1000 + n, 12'd3000 - n);
    check_true("SB16 gap pauses health count",
      (dut.u_health.open_cnt === 4'd1) &&
      (dut.u_health.prev_ch1 === 12'd0) &&
      (dut.u_health.prev_ch2 === 12'd500));
    drive_edge(1'b1, 12'd0, 12'd520);
    drive_edge(1'b0, 12'd3000, 12'd0);
    check_true("SB16 first valid resumes held history",
      (dut.u_health.open_cnt === 4'd2) &&
      (dut.u_health.prev_ch1 === 12'd0) &&
      (dut.u_health.prev_ch2 === 12'd520));
    drain_pipeline();
    scenario_pass("SB16");

    // SB17: both channels remain one atomic pair through adjacent stages.
    reset_idle();
    drive_edge(1'b1, 12'h123, 12'habc);
    drive_edge(1'b1, 12'h456, 12'h789);
    check_true("SB17 accepted concatenation is atomic",
      (dut.accepted_sample_pair === {12'h456, 12'h789}) &&
      (dut.u_health.prev_ch1 === 12'h123) &&
      (dut.u_health.prev_ch2 === 12'habc));
    drive_edge(1'b0, 12'hfff, 12'h000);
    check_true("SB17 second atomic pair reaches health",
      (dut.u_health.prev_ch1 === 12'h456) &&
      (dut.u_health.prev_ch2 === 12'h789));
    drain_pipeline();
    scenario_pass("SB17");

    // SB18: a later accepted mismatch does not overwrite the first latch.
    reset_idle();
    make_overcurrent_latch();
    drive_edge(1'b1, 12'd800, 12'd950);
    for (n = 0; n < 5; n = n + 1)
      drive_edge(1'b0, 12'd800, 12'd950);
    check_true("SB18 first fault retention",
      fault_latched && (fault_code_latched === `FAULT_OVERCURRENT));
    scenario_pass("SB18");

    // SB19: sensor-open persistence with gaps and exact trigger latency.
    reset_idle();
    configure_health_fast();
    drive_edge(1'b1, 12'd0, 12'd500);
    drive_edge(1'b0, 12'd1000, 12'd2000);
    drive_edge(1'b0, 12'd1100, 12'd2100);
    drive_edge(1'b1, 12'd0, 12'd520);
    drive_edge(1'b0, 12'd1200, 12'd2200);
    drive_edge(1'b0, 12'd1300, 12'd2300);
    check_true("SB19 two accepted open counts", dut.u_health.open_cnt === 4'd2);
    drive_edge(1'b1, 12'd0, 12'd540); // N0 trigger transaction
    check_true("SB19 N0 no health flag yet", !sensor_open_flag);
    drive_edge(1'b0, 12'd1400, 12'd2400); // N2a
    check_true("SB19 N2a open flag", sensor_open_flag && !fault_valid);
    drive_edge(1'b0, 12'd1500, 12'd2500); // N2b
    check_true("SB19 N2b classifier",
      fault_valid && (fault_code === `FAULT_SENSOR_OPEN) && !fault_latched);
    drive_edge(1'b0, 12'd1600, 12'd2600); // N3/N4
    check_true("SB19 N3/N4 latch/safe",
      fault_latched && (fault_code_latched === `FAULT_SENSOR_OPEN) &&
      (pwm_out === 1'b0));
    scenario_pass("SB19");

    // SB20: sensor-saturation persistence with gaps and exact latency.
    reset_idle();
    configure_health_fast();
    drive_edge(1'b1, 12'd4095, 12'd1000);
    drive_edge(1'b0, 12'd100, 12'd200);
    drive_edge(1'b0, 12'd200, 12'd300);
    drive_edge(1'b1, 12'd4095, 12'd1020);
    drive_edge(1'b0, 12'd300, 12'd400);
    drive_edge(1'b0, 12'd400, 12'd500);
    check_true("SB20 two accepted saturation counts",
      dut.u_health.sat_cnt === 4'd2);
    drive_edge(1'b1, 12'd4095, 12'd1040); // N0
    check_true("SB20 N0 no saturation flag yet", !sensor_sat_flag);
    drive_edge(1'b0, 12'd500, 12'd600); // N2a
    check_true("SB20 N2a saturation flag", sensor_sat_flag && !fault_valid);
    drive_edge(1'b0, 12'd600, 12'd700); // N2b
    check_true("SB20 N2b classifier",
      fault_valid && (fault_code === `FAULT_SENSOR_SATURATION) &&
      !fault_latched);
    drive_edge(1'b0, 12'd700, 12'd800); // N3/N4
    check_true("SB20 N3/N4 latch/safe",
      fault_latched &&
      (fault_code_latched === `FAULT_SENSOR_SATURATION) &&
      (pwm_out === 1'b0));
    scenario_pass("SB20");

    // SB21: sensor-stuck history persists through gaps with exact latency.
    reset_idle();
    configure_health_fast();
    drive_edge(1'b1, 12'd500, 12'd510); // establish history
    drive_edge(1'b0, 12'd2000, 12'd2100);
    drive_edge(1'b1, 12'd500, 12'd510); // stable count 1
    drive_edge(1'b0, 12'd2100, 12'd2200);
    drive_edge(1'b0, 12'd2200, 12'd2300);
    drive_edge(1'b1, 12'd500, 12'd510); // stable count 2
    drive_edge(1'b0, 12'd2300, 12'd2400);
    drive_edge(1'b0, 12'd2400, 12'd2500);
    check_true("SB21 two accepted stuck counts",
      dut.u_health.stuck_cnt === 4'd2);
    drive_edge(1'b1, 12'd500, 12'd510); // N0
    check_true("SB21 N0 no stuck flag yet", !sensor_stuck_flag);
    drive_edge(1'b0, 12'd2500, 12'd2600); // N2a
    check_true("SB21 N2a stuck flag", sensor_stuck_flag && !fault_valid);
    drive_edge(1'b0, 12'd2600, 12'd2700); // N2b
    check_true("SB21 N2b classifier",
      fault_valid && (fault_code === `FAULT_SENSOR_STUCK) && !fault_latched);
    drive_edge(1'b0, 12'd2700, 12'd2800); // N3/N4
    check_true("SB21 N3/N4 latch/safe",
      fault_latched && (fault_code_latched === `FAULT_SENSOR_STUCK) &&
      (pwm_out === 1'b0));
    scenario_pass("SB21");

    // SB22: back-to-back fault/safe/fault order is retained.
    reset_idle();
    drive_edge(1'b1, 12'd1200, 12'd1200);
    drive_edge(1'b1, 12'd500, 12'd510);
    drive_edge(1'b1, 12'd800, 12'd950);
    for (n = 0; n < 5; n = n + 1)
      drive_edge(1'b0, 12'd50 + n, 12'd3000 - n);
    check_true("SB22 three transactions and first fault order",
      (checker_accepted_count === 32'd3) &&
      (checker_back_to_back_count === 32'd2) && fault_latched &&
      (fault_code_latched === `FAULT_OVERCURRENT));
    scenario_pass("SB22");

    // HB01: retained open state cannot replay on one fresh safe transaction.
    reset_idle();
    configure_health_fast();
    make_sensor_open_latch();
    check_true("HB01 retained open state before clear",
      sensor_open_flag && !fault_valid);
    clear_recover_during_invalid();
    check_true("HB01 retained open state after clear",
      sensor_open_flag && !dut.sensor_open_event);
    consume_fresh_safe_pair(12'd500, 12'd510, 1'b1, 1'b0, 1'b1);
    scenario_pass("HB01");

    // HB02: retained saturation state cannot replay on a safe transaction.
    reset_idle();
    configure_health_fast();
    make_sensor_saturation_latch();
    check_true("HB02 retained saturation state before clear",
      sensor_sat_flag && !fault_valid);
    clear_recover_during_invalid();
    check_true("HB02 retained saturation state after clear",
      sensor_sat_flag && !dut.sensor_sat_event);
    consume_fresh_safe_pair(12'd500, 12'd510, 1'b0, 1'b1, 1'b1);
    scenario_pass("HB02");

    // HB03: retained stuck state cannot replay on a changed transaction.
    reset_idle();
    configure_health_fast();
    make_sensor_stuck_latch();
    check_true("HB03 retained stuck state before clear",
      sensor_stuck_flag && !fault_valid);
    clear_recover_during_invalid();
    check_true("HB03 retained stuck state after clear",
      sensor_stuck_flag && !dut.sensor_stuck_event);
    consume_fresh_safe_pair(12'd600, 12'd620, 1'b0, 1'b0, 1'b1);
    scenario_pass("HB03");

    // HB04: after safe state recovery, fresh qualifying transactions can
    // independently retrigger every health path at the unchanged boundary.
    reset_idle();
    configure_health_fast();
    make_sensor_open_latch();
    clear_recover_during_invalid();
    clear_retained_health_state();
    make_sensor_open_latch();

    reset_idle();
    configure_health_fast();
    make_sensor_saturation_latch();
    clear_recover_during_invalid();
    clear_retained_health_state();
    make_sensor_saturation_latch();

    reset_idle();
    configure_health_fast();
    make_sensor_stuck_latch();
    clear_recover_during_invalid();
    clear_retained_health_state();
    make_sensor_stuck_latch();
    scenario_pass("HB04");

    $display("READ_ONLY_HIERARCHICAL_OBSERVATION=YES");
    $display("HIERARCHICAL_WRITE=NO");
    $display("UNIFIED_SAMPLE_ACCEPTANCE_IMPLEMENTED=YES");
    $display("COMPARATOR_AND_HEALTH_SHARE_ACCEPTED_TRANSACTION=YES");
    $display("INVALID_EXTERNAL_SAMPLE_FAULT_SUPPRESSION=PASS");
    $display("INVALID_HEALTH_STATE_HOLD=PASS");
    $display("STALE_ACCEPTED_SAMPLE_RETRIGGER_SUPPRESSION=PASS");
    $display("HEALTH_EVENT_TRANSACTION_ALIGNMENT=PASS");
    $display("FRESH_SAFE_OPEN_TRANSACTION_NO_RETRIGGER=PASS");
    $display("FRESH_SAFE_SAT_TRANSACTION_NO_RETRIGGER=PASS");
    $display("FRESH_SAFE_STUCK_TRANSACTION_NO_RETRIGGER=PASS");
    $display("FRESH_QUALIFYING_HEALTH_TRANSACTION_RETRIGGER=PASS");
    $display("BACK_TO_BACK_TRANSACTION_ACCEPTANCE=PASS");
    $display("HELD_HIGH_VALID_TRANSACTION_ACCEPTANCE=PASS");
    $display("ATOMIC_SAMPLE_PAIR_CHECK=PASS");
    $display("RESET_RELEASE_FIRST_ACCEPTANCE=PASS");
    $display("FAULT_LATCH_TIMING_CHECK=PASS");
    $display("SAFE_OUTPUT_TIMING_CHECK=PASS");
    $display("OVERCURRENT_LATENCY=N0_TO_N3_N4_3_CYCLES");
    $display("SENSOR_OPEN_LATENCY=TRIGGER_ACCEPT_N0_TO_N3_N4_3_CYCLES");
    $display("SENSOR_SATURATION_LATENCY=TRIGGER_ACCEPT_N0_TO_N3_N4_3_CYCLES");
    $display("SENSOR_STUCK_LATENCY=TRIGGER_ACCEPT_N0_TO_N3_N4_3_CYCLES");
    $display("SAFE_OUTPUT_LATENCY=N0_TO_N4_3_CYCLES_COMPARATOR_PATH");
    $display("ORIGINAL_STAGE2B_SCENARIOS=PASS_22_OF_22");
    $display("HEALTH_EVENT_HARDENING_SCENARIOS=PASS_4_OF_4");
    $display("TOTAL_POSITIVE_SCENARIOS=PASS_26_OF_26");
    $display("STAGE2B_POSITIVE_SCENARIOS_PASS=22_OF_22");
    $display("STAGE2B_UNIFIED_SAMPLE_ACCEPTANCE_DUT=PASS");
    $finish;
  end
endmodule
