`timescale 1ns/1ps
`include "fault_defs.vh"

module stage2b_sample_acceptance_checker #(
  parameter integer DATA_WIDTH = 12,
  parameter integer HEALTH_CNT_WIDTH = 4
)(
  input wire clk,
  input wire rst_n,
  input wire sample_valid,
  input wire clear_fault,
  input wire [DATA_WIDTH-1:0] i_ch1,
  input wire [DATA_WIDTH-1:0] i_ch2,
  input wire [DATA_WIDTH-1:0] th_oc_ch1,
  input wire [DATA_WIDTH-1:0] th_oc_ch2,
  input wire [DATA_WIDTH-1:0] th_diff,
  input wire [DATA_WIDTH-1:0] th_open,
  input wire [DATA_WIDTH-1:0] th_sat,
  input wire [DATA_WIDTH-1:0] th_stuck_delta,
  input wire [HEALTH_CNT_WIDTH-1:0] th_persist,
  input wire sample_accept_event,
  input wire [(2*DATA_WIDTH)-1:0] accepted_sample_pair,
  input wire accepted_sample_valid,
  input wire sample_decision_valid,
  input wire decision_oc_any,
  input wire decision_oc_both,
  input wire decision_mismatch_flag,
  input wire oc_any,
  input wire oc_both,
  input wire mismatch_flag,
  input wire [DATA_WIDTH-1:0] abs_diff,
  input wire sensor_open_flag,
  input wire sensor_sat_flag,
  input wire sensor_stuck_flag,
  input wire sensor_open_event,
  input wire sensor_sat_event,
  input wire sensor_stuck_event,
  input wire [DATA_WIDTH-1:0] health_prev_ch1,
  input wire [DATA_WIDTH-1:0] health_prev_ch2,
  input wire [HEALTH_CNT_WIDTH-1:0] health_open_cnt,
  input wire [HEALTH_CNT_WIDTH-1:0] health_sat_cnt,
  input wire [HEALTH_CNT_WIDTH-1:0] health_stuck_cnt,
  input wire fault_valid,
  input wire [7:0] fault_code,
  input wire fault_latched,
  input wire [7:0] fault_code_latched,
  input wire [3:0] fsm_state,
  input wire pwm_out,
  output reg [31:0] accepted_count,
  output reg [31:0] invalid_pair_hold_count,
  output reg [31:0] back_to_back_count,
  output reg [31:0] reset_release_first_accept_count
);
  localparam [3:0] ST_NORMAL = 4'd0;
  localparam [3:0] ST_FAULT_LATCHED = 4'd1;

  reg previous_input_valid;
  reg reset_was_active;
  reg [(2*DATA_WIDTH)-1:0] previous_raw_pair;

  reg pre_sample_valid;
  reg [(2*DATA_WIDTH)-1:0] pre_raw_pair;
  reg [(2*DATA_WIDTH)-1:0] pre_accepted_pair;
  reg pre_accepted_valid;
  reg pre_decision_valid;
  reg pre_decision_oc_any;
  reg pre_decision_oc_both;
  reg pre_decision_mismatch;
  reg pre_oc_any;
  reg pre_oc_both;
  reg pre_mismatch;
  reg pre_sensor_open;
  reg pre_sensor_sat;
  reg pre_sensor_stuck;
  reg pre_sensor_open_event;
  reg pre_sensor_sat_event;
  reg pre_sensor_stuck_event;
  reg [DATA_WIDTH-1:0] pre_th_open;
  reg [DATA_WIDTH-1:0] pre_th_sat;
  reg [DATA_WIDTH-1:0] pre_th_stuck_delta;
  reg [HEALTH_CNT_WIDTH-1:0] pre_th_persist;
  reg [DATA_WIDTH-1:0] pre_health_prev_ch1;
  reg [DATA_WIDTH-1:0] pre_health_prev_ch2;
  reg [HEALTH_CNT_WIDTH-1:0] pre_health_open_cnt;
  reg [HEALTH_CNT_WIDTH-1:0] pre_health_sat_cnt;
  reg [HEALTH_CNT_WIDTH-1:0] pre_health_stuck_cnt;
  reg pre_fault_valid;
  reg [7:0] pre_fault_code;
  reg [7:0] pre_fault_code_latched;
  reg [3:0] pre_fsm_state;
  reg expected_fault_valid;
  reg [7:0] expected_fault_code;
  reg expected_sensor_open_event;
  reg expected_sensor_sat_event;
  reg expected_sensor_stuck_event;

  task automatic check_true(input string label, input logic condition);
    begin
      if (condition !== 1'b1)
        $fatal(1, "STAGE2B CHECK FAILED: %s", label);
    end
  endtask

  function automatic [7:0] classify_code;
    input any_oc;
    input both_oc;
    input mismatch;
    input open_fault;
    input sat_fault;
    input stuck_fault;
    begin
      if (any_oc && (mismatch || open_fault || sat_fault || stuck_fault))
        classify_code = `FAULT_OC_WITH_SENSOR;
      else if (both_oc || any_oc)
        classify_code = `FAULT_OVERCURRENT;
      else if (sat_fault)
        classify_code = `FAULT_SENSOR_SATURATION;
      else if (open_fault)
        classify_code = `FAULT_SENSOR_OPEN;
      else if (stuck_fault)
        classify_code = `FAULT_SENSOR_STUCK;
      else if (mismatch)
        classify_code = `FAULT_SENSOR_MISMATCH;
      else
        classify_code = `FAULT_NONE;
    end
  endfunction

  task automatic check_reset_state;
    begin
      check_true("accepted pair reset",
                 accepted_sample_pair === {(2*DATA_WIDTH){1'b0}});
      check_true("accepted valid reset", accepted_sample_valid === 1'b0);
      check_true("decision stage reset",
                 (sample_decision_valid === 1'b0) &&
                 (decision_oc_any === 1'b0) &&
                 (decision_oc_both === 1'b0) &&
                 (decision_mismatch_flag === 1'b0));
      check_true("health state reset",
                 (health_prev_ch1 === {DATA_WIDTH{1'b0}}) &&
                 (health_prev_ch2 === {DATA_WIDTH{1'b0}}) &&
                 (health_open_cnt === {HEALTH_CNT_WIDTH{1'b0}}) &&
                 (health_sat_cnt === {HEALTH_CNT_WIDTH{1'b0}}) &&
                 (health_stuck_cnt === {HEALTH_CNT_WIDTH{1'b0}}) &&
                 (sensor_open_flag === 1'b0) &&
                 (sensor_sat_flag === 1'b0) &&
                 (sensor_stuck_flag === 1'b0) &&
                 (sensor_open_event === 1'b0) &&
                 (sensor_sat_event === 1'b0) &&
                 (sensor_stuck_event === 1'b0));
      check_true("classifier reset",
                 (fault_valid === 1'b0) && (fault_code === `FAULT_NONE));
      check_true("fault latch reset",
                 (fault_latched === 1'b0) &&
                 (fault_code_latched === `FAULT_NONE) &&
                 (fsm_state === ST_NORMAL));
      check_true("safe output reset", pwm_out === 1'b0);
    end
  endtask

  initial begin
    accepted_count = 32'd0;
    invalid_pair_hold_count = 32'd0;
    back_to_back_count = 32'd0;
    reset_release_first_accept_count = 32'd0;
    previous_input_valid = 1'b0;
    reset_was_active = 1'b0;
    previous_raw_pair = {(2*DATA_WIDTH){1'b0}};
  end

  always @(posedge clk) begin
    check_true("rst_n must be 0 or 1",
               (rst_n === 1'b0) || (rst_n === 1'b1));
    check_true("sample_valid must be 0 or 1",
               (sample_valid === 1'b0) || (sample_valid === 1'b1));

    pre_sample_valid = sample_valid;
    pre_raw_pair = {i_ch1, i_ch2};
    pre_accepted_pair = accepted_sample_pair;
    pre_accepted_valid = accepted_sample_valid;
    pre_decision_valid = sample_decision_valid;
    pre_decision_oc_any = decision_oc_any;
    pre_decision_oc_both = decision_oc_both;
    pre_decision_mismatch = decision_mismatch_flag;
    pre_oc_any = oc_any;
    pre_oc_both = oc_both;
    pre_mismatch = mismatch_flag;
    pre_sensor_open = sensor_open_flag;
    pre_sensor_sat = sensor_sat_flag;
    pre_sensor_stuck = sensor_stuck_flag;
    pre_sensor_open_event = sensor_open_event;
    pre_sensor_sat_event = sensor_sat_event;
    pre_sensor_stuck_event = sensor_stuck_event;
    pre_th_open = th_open;
    pre_th_sat = th_sat;
    pre_th_stuck_delta = th_stuck_delta;
    pre_th_persist = th_persist;
    pre_health_prev_ch1 = health_prev_ch1;
    pre_health_prev_ch2 = health_prev_ch2;
    pre_health_open_cnt = health_open_cnt;
    pre_health_sat_cnt = health_sat_cnt;
    pre_health_stuck_cnt = health_stuck_cnt;
    pre_fault_valid = fault_valid;
    pre_fault_code = fault_code;
    pre_fault_code_latched = fault_code_latched;
    pre_fsm_state = fsm_state;

    if (rst_n === 1'b0) begin
      #1;
      check_reset_state();
      accepted_count = 32'd0;
      invalid_pair_hold_count = 32'd0;
      back_to_back_count = 32'd0;
      reset_release_first_accept_count = 32'd0;
      previous_input_valid = 1'b0;
      previous_raw_pair = pre_raw_pair;
      reset_was_active = 1'b1;
    end else begin
      if (pre_sample_valid === 1'b1) begin
        check_true("valid i_ch1 contains no X/Z", (^i_ch1 !== 1'bx));
        check_true("valid i_ch2 contains no X/Z", (^i_ch2 !== 1'bx));
      end
      check_true("accepted valid is binary",
                 (pre_accepted_valid === 1'b0) ||
                 (pre_accepted_valid === 1'b1));
      check_true("decision valid is binary",
                 (pre_decision_valid === 1'b0) ||
                 (pre_decision_valid === 1'b1));

      check_true("accepted comparator absolute difference",
        abs_diff === ((accepted_sample_pair[(2*DATA_WIDTH)-1:DATA_WIDTH] >=
                      accepted_sample_pair[DATA_WIDTH-1:0]) ?
                     (accepted_sample_pair[(2*DATA_WIDTH)-1:DATA_WIDTH] -
                      accepted_sample_pair[DATA_WIDTH-1:0]) :
                     (accepted_sample_pair[DATA_WIDTH-1:0] -
                      accepted_sample_pair[(2*DATA_WIDTH)-1:DATA_WIDTH])));
      check_true("accepted comparator overcurrent equation",
        oc_any ===
          ((accepted_sample_pair[(2*DATA_WIDTH)-1:DATA_WIDTH] > th_oc_ch1) ||
           (accepted_sample_pair[DATA_WIDTH-1:0] > th_oc_ch2)));
      check_true("accepted comparator dual equation",
        oc_both ===
          ((accepted_sample_pair[(2*DATA_WIDTH)-1:DATA_WIDTH] > th_oc_ch1) &&
           (accepted_sample_pair[DATA_WIDTH-1:0] > th_oc_ch2)));
      check_true("accepted comparator mismatch equation",
                 mismatch_flag === (abs_diff > th_diff));

      expected_sensor_open_event = pre_accepted_valid &&
        ((pre_accepted_pair[(2*DATA_WIDTH)-1:DATA_WIDTH] <= pre_th_open) ||
         (pre_accepted_pair[DATA_WIDTH-1:0] <= pre_th_open)) &&
        (pre_health_open_cnt >= pre_th_persist);
      expected_sensor_sat_event = pre_accepted_valid &&
        ((pre_accepted_pair[(2*DATA_WIDTH)-1:DATA_WIDTH] >= pre_th_sat) ||
         (pre_accepted_pair[DATA_WIDTH-1:0] >= pre_th_sat)) &&
        (pre_health_sat_cnt >= pre_th_persist);
      expected_sensor_stuck_event = pre_accepted_valid &&
        (((pre_accepted_pair[(2*DATA_WIDTH)-1:DATA_WIDTH] >=
           pre_health_prev_ch1) ?
          (pre_accepted_pair[(2*DATA_WIDTH)-1:DATA_WIDTH] -
           pre_health_prev_ch1) :
          (pre_health_prev_ch1 -
           pre_accepted_pair[(2*DATA_WIDTH)-1:DATA_WIDTH])) <=
         pre_th_stuck_delta) &&
        (((pre_accepted_pair[DATA_WIDTH-1:0] >= pre_health_prev_ch2) ?
          (pre_accepted_pair[DATA_WIDTH-1:0] - pre_health_prev_ch2) :
          (pre_health_prev_ch2 -
           pre_accepted_pair[DATA_WIDTH-1:0])) <= pre_th_stuck_delta) &&
        (pre_health_stuck_cnt >= pre_th_persist);

      expected_fault_valid = pre_decision_valid &&
        (pre_decision_oc_any || pre_decision_mismatch ||
         pre_sensor_open_event || pre_sensor_sat_event ||
         pre_sensor_stuck_event);
      if (pre_decision_valid)
        expected_fault_code = classify_code(
          pre_decision_oc_any, pre_decision_oc_both,
          pre_decision_mismatch, pre_sensor_open_event,
          pre_sensor_sat_event, pre_sensor_stuck_event);
      else
        expected_fault_code = `FAULT_NONE;

      #1;

      check_true("sample_accept_event definition",
                 sample_accept_event === pre_sample_valid);
      check_true("accepted valid follows input valid",
                 accepted_sample_valid === pre_sample_valid);
      if (pre_sample_valid === 1'b1) begin
        accepted_count = accepted_count + 1'b1;
        check_true("accepted pair captures both channels atomically",
                   accepted_sample_pair === pre_raw_pair);
        if (previous_input_valid === 1'b1)
          back_to_back_count = back_to_back_count + 1'b1;
        if (reset_was_active === 1'b1) begin
          reset_release_first_accept_count =
            reset_release_first_accept_count + 1'b1;
          check_true("first post-reset accepted pair",
                     accepted_sample_pair === pre_raw_pair);
        end
      end else begin
        check_true("invalid edge holds accepted pair",
                   accepted_sample_pair === pre_accepted_pair);
        if (pre_raw_pair !== previous_raw_pair)
          invalid_pair_hold_count = invalid_pair_hold_count + 1'b1;
      end

      check_true("decision valid follows accepted valid",
                 sample_decision_valid === pre_accepted_valid);
      check_true("health events match the consumed accepted transaction",
                 (sensor_open_event === expected_sensor_open_event) &&
                 (sensor_sat_event === expected_sensor_sat_event) &&
                 (sensor_stuck_event === expected_sensor_stuck_event));
      if (pre_accepted_valid === 1'b1) begin
        check_true("decision captures accepted comparator",
                   (decision_oc_any === pre_oc_any) &&
                   (decision_oc_both === pre_oc_both) &&
                   (decision_mismatch_flag === pre_mismatch));
        check_true("health consumes accepted channel pair",
                   (health_prev_ch1 ===
                      pre_accepted_pair[(2*DATA_WIDTH)-1:DATA_WIDTH]) &&
                   (health_prev_ch2 ===
                      pre_accepted_pair[DATA_WIDTH-1:0]));
      end else begin
        check_true("invalid accepted stage clears health events",
                   !sensor_open_event && !sensor_sat_event &&
                   !sensor_stuck_event);
        check_true("invalid accepted stage holds decision snapshot",
                   (decision_oc_any === pre_decision_oc_any) &&
                   (decision_oc_both === pre_decision_oc_both) &&
                   (decision_mismatch_flag === pre_decision_mismatch));
        check_true("invalid accepted stage holds health history and counters",
                   (health_prev_ch1 === pre_health_prev_ch1) &&
                   (health_prev_ch2 === pre_health_prev_ch2) &&
                   (health_open_cnt === pre_health_open_cnt) &&
                   (health_sat_cnt === pre_health_sat_cnt) &&
                   (health_stuck_cnt === pre_health_stuck_cnt) &&
                   (sensor_open_flag === pre_sensor_open) &&
                   (sensor_sat_flag === pre_sensor_sat) &&
                   (sensor_stuck_flag === pre_sensor_stuck));
      end

      check_true("classifier registers only aligned transaction event",
                 fault_valid === expected_fault_valid);
      check_true("classifier code matches aligned transaction",
                 fault_code === expected_fault_code);

      if ((pre_fsm_state === ST_NORMAL) && (pre_fault_valid === 1'b1)) begin
        check_true("visible event latches on next FSM edge",
                   (fsm_state === ST_FAULT_LATCHED) &&
                   (fault_latched === 1'b1));
        check_true("first fault code captured",
                   fault_code_latched === pre_fault_code);
      end
      if (pre_fsm_state === ST_FAULT_LATCHED) begin
        check_true("latched state retains indication", fault_latched === 1'b1);
        check_true("latched state retains first code",
                   fault_code_latched === pre_fault_code_latched);
      end
      if (fault_latched === 1'b1)
        check_true("fault latch keeps output safe-low", pwm_out === 1'b0);

      previous_input_valid = pre_sample_valid;
      previous_raw_pair = pre_raw_pair;
      reset_was_active = 1'b0;
    end
  end
endmodule
