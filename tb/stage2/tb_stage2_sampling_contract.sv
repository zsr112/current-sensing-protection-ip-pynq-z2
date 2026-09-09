`timescale 1ns/1ps
`include "fault_defs.vh"

module tb_stage2_sampling_contract;
  localparam integer DATA_WIDTH = 12;
  localparam integer HEALTH_CNT_WIDTH = 4;
  localparam [3:0] ST_NORMAL        = 4'd0;
  localparam [3:0] ST_FAULT_LATCHED = 4'd1;
  localparam [3:0] ST_RESET_WAIT    = 4'd2;

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
  wire [31:0] checker_invalid_hold_count;
  wire [31:0] checker_consecutive_valid_count;
  wire [31:0] checker_reset_release_first_sample_count;

  integer base_count;
  integer n;
  reg [11:0] saved_prev_ch1;
  reg [11:0] saved_prev_ch2;
  reg [3:0] saved_open_cnt;
  reg [3:0] saved_sat_cnt;
  reg [3:0] saved_stuck_cnt;

  always #5 clk = ~clk;

  protection_core_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .CNT_WIDTH(16),
    .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .sample_valid(sample_valid),
    .pwm_enable(pwm_enable),
    .clear_fault(clear_fault),
    .i_ch1(i_ch1),
    .i_ch2(i_ch2),
    .th_oc_ch1(th_oc_ch1),
    .th_oc_ch2(th_oc_ch2),
    .th_diff(th_diff),
    .th_open(th_open),
    .th_sat(th_sat),
    .th_stuck_delta(th_stuck_delta),
    .th_persist(th_persist),
    .period(pwm_period),
    .duty(pwm_duty),
    .pwm_raw(pwm_raw),
    .pwm_out(pwm_out),
    .oc_any(oc_any),
    .oc_both(oc_both),
    .mismatch_flag(mismatch_flag),
    .sensor_open_flag(sensor_open_flag),
    .sensor_sat_flag(sensor_sat_flag),
    .sensor_stuck_flag(sensor_stuck_flag),
    .fault_valid(fault_valid),
    .fault_latched(fault_latched),
    .fault_code(fault_code),
    .fault_code_latched(fault_code_latched),
    .fsm_state(fsm_state),
    .abs_diff(abs_diff)
  );

  stage2_sampling_contract_checker #(
    .DATA_WIDTH(DATA_WIDTH),
    .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH)
  ) u_contract_checker (
    .clk(clk),
    .rst_n(rst_n),
    .sample_valid(sample_valid),
    .clear_fault(clear_fault),
    .i_ch1(i_ch1),
    .i_ch2(i_ch2),
    .th_oc_ch1(th_oc_ch1),
    .th_oc_ch2(th_oc_ch2),
    .th_diff(th_diff),
    .oc_any(oc_any),
    .oc_both(oc_both),
    .mismatch_flag(mismatch_flag),
    .abs_diff(abs_diff),
    .sensor_open_flag(sensor_open_flag),
    .sensor_sat_flag(sensor_sat_flag),
    .sensor_stuck_flag(sensor_stuck_flag),
    .fault_valid(fault_valid),
    .fault_latched(fault_latched),
    .fault_code(fault_code),
    .fault_code_latched(fault_code_latched),
    .fsm_state(fsm_state),
    .pwm_out(pwm_out),
    // READ_ONLY_HIERARCHICAL_OBSERVATION=YES.  These are observation-only
    // connections; no procedural or continuous assignment targets DUT state.
    .health_prev_ch1(dut.u_health.prev_ch1),
    .health_prev_ch2(dut.u_health.prev_ch2),
    .health_open_cnt(dut.u_health.open_cnt),
    .health_sat_cnt(dut.u_health.sat_cnt),
    .health_stuck_cnt(dut.u_health.stuck_cnt),
    .accepted_count(checker_accepted_count),
    .invalid_hold_count(checker_invalid_hold_count),
    .consecutive_valid_count(checker_consecutive_valid_count),
    .reset_release_first_sample_count(checker_reset_release_first_sample_count)
  );

  task automatic check_true(input string label, input logic condition);
    begin
      if (condition !== 1'b1)
        $fatal(1, "STAGE2 DUT TEST FAILED: %s", label);
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
      th_sat = 12'hfff;
      th_stuck_delta = 12'd0;
      th_persist = 4'd2;
      pwm_period = 16'd4;
      pwm_duty = 16'd2;
    end
  endtask

  task automatic check_reset_outputs(input string label);
    begin
      check_true($sformatf("%s classifier", label),
        (fault_valid === 1'b0) && (fault_code === `FAULT_NONE));
      check_true($sformatf("%s latch", label),
        (fault_latched === 1'b0) &&
        (fault_code_latched === `FAULT_NONE) &&
        (fsm_state === ST_NORMAL));
      check_true($sformatf("%s health", label),
        (sensor_open_flag === 1'b0) &&
        (sensor_sat_flag === 1'b0) &&
        (sensor_stuck_flag === 1'b0));
      check_true($sformatf("%s safe output", label), pwm_out === 1'b0);
    end
  endtask

  task automatic assert_reset(
    input logic valid_value,
    input [11:0] sample1,
    input [11:0] sample2
  );
    begin
      @(negedge clk);
      sample_valid = valid_value;
      i_ch1 = sample1;
      i_ch2 = sample2;
      clear_fault = 1'b0;
      rst_n = 1'b0;
      #2;
      check_reset_outputs("asynchronous reset");
      @(posedge clk);
      #2;
      check_reset_outputs("clocked reset");
    end
  endtask

  task automatic reset_and_release_idle;
    begin
      assert_reset(1'b0, 12'd500, 12'd510);
      @(negedge clk);
      rst_n = 1'b1;
      sample_valid = 1'b0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd510;
      clear_fault = 1'b0;
      @(posedge clk);
      #2;
      check_true("idle reset release remains normal",
        (fault_valid === 1'b0) &&
        (fault_latched === 1'b0) &&
        (fsm_state === ST_NORMAL));
    end
  endtask

  task automatic single_valid_edge(input [11:0] sample1, input [11:0] sample2);
    begin
      @(negedge clk);
      i_ch1 = sample1;
      i_ch2 = sample2;
      sample_valid = 1'b1;
      @(posedge clk);
      #2;
      @(negedge clk);
      sample_valid = 1'b0;
    end
  endtask

  task automatic wait_for_latch(input [7:0] expected_code);
    integer guard;
    begin
      guard = 0;
      while (fault_latched !== 1'b1) begin
        @(posedge clk);
        #2;
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "STAGE2 DUT TEST FAILED: timeout waiting for latch");
      end
      check_true("latched fault code", fault_code_latched === expected_code);
      check_true("latched fault safe output", pwm_out === 1'b0);
    end
  endtask

  initial begin
    configure_nominal();

    // SC01: reset asserted with valid low.
    @(posedge clk);
    #2;
    check_reset_outputs("SC01");
    scenario_pass("SC01");

    // SC02: reset dominates a high valid and fault-valued data.
    @(negedge clk);
    sample_valid = 1'b1;
    i_ch1 = 12'd1300;
    i_ch2 = 12'd1320;
    @(posedge clk);
    #2;
    check_reset_outputs("SC02");
    scenario_pass("SC02");

    // SC03: valid may be accepted on the first rising edge after release.
    @(negedge clk);
    rst_n = 1'b1;
    sample_valid = 1'b1;
    i_ch1 = 12'd500;
    i_ch2 = 12'd510;
    @(posedge clk);
    #2;
    check_true("SC03 first sample stored",
      (dut.u_health.prev_ch1 === 12'd500) &&
      (dut.u_health.prev_ch2 === 12'd510));
    check_true("SC03 checker saw first-release sample",
      checker_reset_release_first_sample_count === 32'd1);
    scenario_pass("SC03");
    @(negedge clk);
    sample_valid = 1'b0;

    // SC04: one isolated valid pulse is one health acceptance.
    base_count = checker_accepted_count;
    single_valid_edge(12'd520, 12'd530);
    check_true("SC04 accepted once", checker_accepted_count === base_count + 1);
    check_true("SC04 stored isolated sample",
      (dut.u_health.prev_ch1 === 12'd520) &&
      (dut.u_health.prev_ch2 === 12'd530));
    scenario_pass("SC04");

    // SC05: two adjacent high edges are two samples.
    base_count = checker_accepted_count;
    @(negedge clk);
    sample_valid = 1'b1;
    i_ch1 = 12'd540;
    i_ch2 = 12'd550;
    @(posedge clk); #2;
    @(negedge clk);
    i_ch1 = 12'd560;
    i_ch2 = 12'd570;
    @(posedge clk); #2;
    check_true("SC05 two accepted samples", checker_accepted_count === base_count + 2);
    check_true("SC05 second sample stored",
      (dut.u_health.prev_ch1 === 12'd560) &&
      (dut.u_health.prev_ch2 === 12'd570));
    check_true("SC05 consecutive valid observed", checker_consecutive_valid_count >= 1);
    scenario_pass("SC05");
    @(negedge clk);
    sample_valid = 1'b0;

    // SC06: held-high valid accepts one new sample on every rising edge.
    base_count = checker_accepted_count;
    @(negedge clk);
    sample_valid = 1'b1;
    for (n = 0; n < 3; n = n + 1) begin
      i_ch1 = 12'd600 + n;
      i_ch2 = 12'd620 + n;
      @(posedge clk); #2;
      if (n != 2)
        @(negedge clk);
    end
    check_true("SC06 three held-high acceptances", checker_accepted_count === base_count + 3);
    check_true("SC06 final held-high sample stored",
      (dut.u_health.prev_ch1 === 12'd602) &&
      (dut.u_health.prev_ch2 === 12'd622));
    scenario_pass("SC06");
    @(negedge clk);
    sample_valid = 1'b0;

    // SC07: one invalid edge holds health history/counters, then resumes.
    single_valid_edge(12'd650, 12'd660);
    saved_prev_ch1 = dut.u_health.prev_ch1;
    saved_prev_ch2 = dut.u_health.prev_ch2;
    saved_open_cnt = dut.u_health.open_cnt;
    saved_sat_cnt = dut.u_health.sat_cnt;
    saved_stuck_cnt = dut.u_health.stuck_cnt;
    sample_valid = 1'b0;
    i_ch1 = 12'd700;
    i_ch2 = 12'd710;
    @(posedge clk); #2;
    check_true("SC07 invalid health hold",
      (dut.u_health.prev_ch1 === saved_prev_ch1) &&
      (dut.u_health.prev_ch2 === saved_prev_ch2) &&
      (dut.u_health.open_cnt === saved_open_cnt) &&
      (dut.u_health.sat_cnt === saved_sat_cnt) &&
      (dut.u_health.stuck_cnt === saved_stuck_cnt));
    single_valid_edge(12'd670, 12'd680);
    check_true("SC07 resume stores sample", dut.u_health.prev_ch1 === 12'd670);
    scenario_pass("SC07");

    // SC08: a longer gap also holds the complete registered health state.
    saved_prev_ch1 = dut.u_health.prev_ch1;
    saved_prev_ch2 = dut.u_health.prev_ch2;
    saved_open_cnt = dut.u_health.open_cnt;
    saved_sat_cnt = dut.u_health.sat_cnt;
    saved_stuck_cnt = dut.u_health.stuck_cnt;
    for (n = 0; n < 3; n = n + 1) begin
      if (n != 0)
        @(negedge clk);
      sample_valid = 1'b0;
      i_ch1 = 12'd720 + (n * 20);
      i_ch2 = 12'd730 + (n * 20);
      @(posedge clk); #2;
    end
    check_true("SC08 multi-gap health hold",
      (dut.u_health.prev_ch1 === saved_prev_ch1) &&
      (dut.u_health.prev_ch2 === saved_prev_ch2) &&
      (dut.u_health.open_cnt === saved_open_cnt) &&
      (dut.u_health.sat_cnt === saved_sat_cnt) &&
      (dut.u_health.stuck_cnt === saved_stuck_cnt));
    scenario_pass("SC08");

    // SC09: health state ignores invalid data, but the current comparator path
    // is intentionally characterized as not valid-gated and can latch a fault.
    configure_nominal();
    reset_and_release_idle();
    @(negedge clk);
    sample_valid = 1'b0;
    i_ch1 = 12'd1300;
    i_ch2 = 12'd1320;
    @(posedge clk); #2;
    check_true("SC09 invalid comparator reaches classifier",
      (oc_any === 1'b1) && (fault_valid === 1'b1));
    @(posedge clk); #2;
    check_true("SC09 invalid comparator fault latches",
      (fault_latched === 1'b1) &&
      (fault_code_latched === `FAULT_OVERCURRENT) &&
      (pwm_out === 1'b0));
    for (n = 0; n < 3; n = n + 1) begin
      if (n != 0)
        @(negedge clk);
      sample_valid = 1'b0;
      if ((n & 1) == 0) begin
        i_ch1 = 12'd100;
        i_ch2 = 12'd900;
      end else begin
        i_ch1 = 12'd1400;
        i_ch2 = 12'd1410;
      end
      @(posedge clk); #2;
      check_true("SC09 invalid health counters stay reset",
        (dut.u_health.open_cnt === 4'd0) &&
        (dut.u_health.sat_cnt === 4'd0) &&
        (dut.u_health.stuck_cnt === 4'd0));
    end
    $display("COMPARATOR_INVALID_GATING_GAP_OBSERVED=PASS");
    scenario_pass("SC09");

    // SC10-SC12: comparator thresholds are strict greater-than boundaries.
    configure_nominal();
    reset_and_release_idle();
    single_valid_edge(12'd999, 12'd950);
    repeat (2) begin @(posedge clk); #2; end
    check_true("SC10 threshold minus one safe",
      (oc_any === 1'b0) && (fault_latched === 1'b0));
    scenario_pass("SC10");

    single_valid_edge(12'd1000, 12'd950);
    repeat (2) begin @(posedge clk); #2; end
    check_true("SC11 threshold equality safe",
      (oc_any === 1'b0) && (fault_latched === 1'b0));
    scenario_pass("SC11");

    @(negedge clk);
    sample_valid = 1'b1;
    i_ch1 = 12'd1001;
    i_ch2 = 12'd950;
    @(posedge clk); #2;
    check_true("SC12 classifier recognition edge",
      (fault_valid === 1'b1) &&
      (fault_code === `FAULT_OVERCURRENT) &&
      (fault_latched === 1'b0));
    @(negedge clk);
    sample_valid = 1'b0;
    @(posedge clk); #2;
    check_true("SC12 next-edge latch and safe output",
      (fault_latched === 1'b1) &&
      (fault_code_latched === `FAULT_OVERCURRENT) &&
      (pwm_out === 1'b0));
    // A later mismatch changes the live code but not the first latched code.
    @(negedge clk);
    i_ch1 = 12'd800;
    i_ch2 = 12'd950;
    sample_valid = 1'b1;
    repeat (2) begin @(posedge clk); #2; @(negedge clk); end
    check_true("SC12 first-fault retention",
      fault_code_latched === `FAULT_OVERCURRENT);
    sample_valid = 1'b0;
    scenario_pass("SC12");

    // SC13: a real health fault persists across valid samples and reaches the
    // classifier/FSM through its two registered downstream stages.
    configure_health_fast();
    reset_and_release_idle();
    for (n = 0; n < 3; n = n + 1) begin
      @(negedge clk);
      sample_valid = 1'b1;
      i_ch1 = 12'd0;
      i_ch2 = 12'd500 + (n * 2);
      @(posedge clk); #2;
    end
    check_true("SC13 open flag visible after previous-counter boundary",
      sensor_open_flag === 1'b1);
    @(negedge clk);
    i_ch2 = 12'd506;
    @(posedge clk); #2;
    check_true("SC13 classifier sees registered health flag",
      (fault_valid === 1'b1) && (fault_code === `FAULT_SENSOR_OPEN));
    @(negedge clk);
    i_ch2 = 12'd508;
    @(posedge clk); #2;
    check_true("SC13 health fault latches and gates safe",
      (fault_latched === 1'b1) &&
      (fault_code_latched === `FAULT_SENSOR_OPEN) &&
      (sensor_open_flag === 1'b1) &&
      (pwm_out === 1'b0));
    // Generate a later saturation classification; the first latched open code
    // must remain while the FSM is latched.
    for (n = 0; n < 5; n = n + 1) begin
      @(negedge clk);
      i_ch1 = 12'hfff;
      i_ch2 = 12'd2000 + n;
      sample_valid = 1'b1;
      @(posedge clk); #2;
    end
    check_true("SC13 later health code does not overwrite first code",
      fault_code_latched === `FAULT_SENSOR_OPEN);
    scenario_pass("SC13");

    // SC14 and SC15: gap holds the exact history, and resumed valid samples
    // continue (rather than restart) persistence.
    configure_health_fast();
    reset_and_release_idle();
    single_valid_edge(12'd0, 12'd600);
    check_true("SC14 setup count", dut.u_health.open_cnt === 4'd1);
    saved_prev_ch1 = dut.u_health.prev_ch1;
    saved_prev_ch2 = dut.u_health.prev_ch2;
    for (n = 0; n < 3; n = n + 1) begin
      @(negedge clk);
      sample_valid = 1'b0;
      i_ch1 = 12'd1000 + n;
      i_ch2 = 12'd2000 - n;
      @(posedge clk); #2;
    end
    check_true("SC14 gap pauses health tracking",
      (dut.u_health.open_cnt === 4'd1) &&
      (dut.u_health.prev_ch1 === saved_prev_ch1) &&
      (dut.u_health.prev_ch2 === saved_prev_ch2) &&
      (sensor_open_flag === 1'b0));
    scenario_pass("SC14");

    single_valid_edge(12'd0, 12'd602);
    check_true("SC15 first resumed valid continues count",
      (dut.u_health.open_cnt === 4'd2) &&
      (sensor_open_flag === 1'b0));
    single_valid_edge(12'd0, 12'd604);
    check_true("SC15 resumed persistence becomes visible",
      (dut.u_health.open_cnt === 4'd3) &&
      (sensor_open_flag === 1'b1));
    scenario_pass("SC15");

    // SC16: clear on a safe accepted sample enters RESET_WAIT, retains the
    // first fault, keeps the output low, and recovers after four eligible edges.
    configure_nominal();
    reset_and_release_idle();
    @(negedge clk);
    sample_valid = 1'b1;
    i_ch1 = 12'd1300;
    i_ch2 = 12'd1320;
    @(posedge clk); #2;
    @(negedge clk);
    sample_valid = 1'b0;
    @(posedge clk); #2;
    check_true("SC16 setup latch",
      (fault_latched === 1'b1) &&
      (fault_code_latched === `FAULT_OVERCURRENT));
    @(negedge clk);
    i_ch1 = 12'd500;
    i_ch2 = 12'd510;
    sample_valid = 1'b1;
    clear_fault = 1'b1;
    @(posedge clk); #2;
    check_true("SC16 clear plus accepted safe sample enters wait",
      (fsm_state === ST_RESET_WAIT) &&
      (fault_latched === 1'b1) &&
      (fault_code_latched === `FAULT_OVERCURRENT) &&
      (fault_valid === 1'b0) &&
      (pwm_out === 1'b0));
    @(negedge clk);
    sample_valid = 1'b0;
    clear_fault = 1'b0;
    for (n = 0; n < 4; n = n + 1) begin
      @(posedge clk); #2;
      if (n < 3)
        check_true("SC16 recovery wait remains safe",
          (fault_latched === 1'b1) && (pwm_out === 1'b0));
    end
    check_true("SC16 recovery completes",
      (fsm_state === ST_NORMAL) &&
      (fault_latched === 1'b0) &&
      (fault_code_latched === `FAULT_NONE));
    scenario_pass("SC16");

    $display("READ_ONLY_HIERARCHICAL_OBSERVATION=YES");
    $display("HIERARCHICAL_WRITE=NO");
    $display("CHECKER_FOUR_STATE_SAFE=PASS");
    $display("INVALID_SAMPLE_IGNORE_CHECK=PASS");
    $display("INVALID_SAMPLE_IGNORE_SCOPE=SENSOR_HEALTH_STATE_ONLY");
    $display("BACK_TO_BACK_VALID_CHECK=PASS");
    $display("HELD_VALID_CHECK=PASS");
    $display("GAP_HOLD_OR_PAUSE_CHECK=PASS");
    $display("RESET_PRIORITY_CHECK=PASS");
    $display("RESET_RELEASE_FIRST_SAMPLE_CHECK=PASS");
    $display("THRESHOLD_BOUNDARY_CHECK=PASS");
    $display("FAULT_LATCH_TIMING_CHECK=PASS");
    $display("FIRST_FAULT_RETENTION_CHECK=PASS");
    $display("SAFE_OUTPUT_TIMING_CHECK=PASS");
    $display("SCENARIOS_PASS=16_OF_16");
    $display("STAGE2_SAMPLING_CONTRACT_DUT=PASS");
    $finish;
  end
endmodule
