`timescale 1ns/1ps

// Stage 2A executable checker for the behavior that exists at the public
// protection_core_top boundary.  The health-state ports are connected by the
// dedicated testbench through read-only hierarchical observation.  This file
// never writes, forces, or deposits DUT state.
module stage2_sampling_contract_checker #(
  parameter integer DATA_WIDTH = 12,
  parameter integer HEALTH_CNT_WIDTH = 4
)(
  input  wire                         clk,
  input  wire                         rst_n,
  input  wire                         sample_valid,
  input  wire                         clear_fault,
  input  wire [DATA_WIDTH-1:0]        i_ch1,
  input  wire [DATA_WIDTH-1:0]        i_ch2,
  input  wire [DATA_WIDTH-1:0]        th_oc_ch1,
  input  wire [DATA_WIDTH-1:0]        th_oc_ch2,
  input  wire [DATA_WIDTH-1:0]        th_diff,
  input  wire                         oc_any,
  input  wire                         oc_both,
  input  wire                         mismatch_flag,
  input  wire [DATA_WIDTH-1:0]        abs_diff,
  input  wire                         sensor_open_flag,
  input  wire                         sensor_sat_flag,
  input  wire                         sensor_stuck_flag,
  input  wire                         fault_valid,
  input  wire                         fault_latched,
  input  wire [7:0]                   fault_code,
  input  wire [7:0]                   fault_code_latched,
  input  wire [3:0]                   fsm_state,
  input  wire                         pwm_out,
  input  wire [DATA_WIDTH-1:0]        health_prev_ch1,
  input  wire [DATA_WIDTH-1:0]        health_prev_ch2,
  input  wire [HEALTH_CNT_WIDTH-1:0]  health_open_cnt,
  input  wire [HEALTH_CNT_WIDTH-1:0]  health_sat_cnt,
  input  wire [HEALTH_CNT_WIDTH-1:0]  health_stuck_cnt,
  output reg  [31:0]                  accepted_count,
  output reg  [31:0]                  invalid_hold_count,
  output reg  [31:0]                  consecutive_valid_count,
  output reg  [31:0]                  reset_release_first_sample_count
);
  localparam [3:0] ST_NORMAL        = 4'd0;
  localparam [3:0] ST_FAULT_LATCHED = 4'd1;

  reg previous_sample_valid;
  reg reset_was_active;

  reg [DATA_WIDTH-1:0] pre_i_ch1;
  reg [DATA_WIDTH-1:0] pre_i_ch2;
  reg [DATA_WIDTH-1:0] pre_health_prev_ch1;
  reg [DATA_WIDTH-1:0] pre_health_prev_ch2;
  reg [HEALTH_CNT_WIDTH-1:0] pre_health_open_cnt;
  reg [HEALTH_CNT_WIDTH-1:0] pre_health_sat_cnt;
  reg [HEALTH_CNT_WIDTH-1:0] pre_health_stuck_cnt;
  reg pre_sensor_open_flag;
  reg pre_sensor_sat_flag;
  reg pre_sensor_stuck_flag;
  reg pre_fault_valid;
  reg [7:0] pre_fault_code;
  reg [7:0] pre_fault_code_latched;
  reg [3:0] pre_fsm_state;

  task automatic check_true(input string label, input logic condition);
    begin
      // Case inequality is intentional: false, X, and Z all fail.
      if (condition !== 1'b1)
        $fatal(1, "STAGE2 CONTRACT CHECK FAILED: %s", label);
    end
  endtask

  task automatic check_reset_state(input string label);
    begin
      check_true($sformatf("%s: health previous samples reset", label),
                 (health_prev_ch1 === {DATA_WIDTH{1'b0}}) &&
                 (health_prev_ch2 === {DATA_WIDTH{1'b0}}));
      check_true($sformatf("%s: health counters reset", label),
                 (health_open_cnt === {HEALTH_CNT_WIDTH{1'b0}}) &&
                 (health_sat_cnt === {HEALTH_CNT_WIDTH{1'b0}}) &&
                 (health_stuck_cnt === {HEALTH_CNT_WIDTH{1'b0}}));
      check_true($sformatf("%s: health flags reset", label),
                 (sensor_open_flag === 1'b0) &&
                 (sensor_sat_flag === 1'b0) &&
                 (sensor_stuck_flag === 1'b0));
      check_true($sformatf("%s: classifier reset", label),
                 (fault_valid === 1'b0) && (fault_code === 8'h00));
      check_true($sformatf("%s: latch reset", label),
                 (fault_latched === 1'b0) &&
                 (fault_code_latched === 8'h00) &&
                 (fsm_state === ST_NORMAL));
      check_true($sformatf("%s: safe output reset low", label), pwm_out === 1'b0);
    end
  endtask

  initial begin
    accepted_count = 32'd0;
    invalid_hold_count = 32'd0;
    consecutive_valid_count = 32'd0;
    reset_release_first_sample_count = 32'd0;
    previous_sample_valid = 1'b0;
    reset_was_active = 1'b0;
  end

  // Prove that the active-low reset assertion reaches the observable state
  // without waiting for a rising clock edge.
  always @(negedge rst_n) begin
    if (rst_n === 1'b0) begin
      #1;
      check_reset_state("asynchronous reset assertion");
    end
  end

  always @(posedge clk) begin
    check_true("rst_n must be 0 or 1",
               (rst_n === 1'b0) || (rst_n === 1'b1));
    check_true("sample_valid must be 0 or 1",
               (sample_valid === 1'b0) || (sample_valid === 1'b1));

    if (rst_n === 1'b0) begin
      #1;
      check_reset_state("clocked reset priority");
      accepted_count = 32'd0;
      invalid_hold_count = 32'd0;
      consecutive_valid_count = 32'd0;
      reset_release_first_sample_count = 32'd0;
      previous_sample_valid = 1'b0;
      reset_was_active = 1'b1;
    end else begin
      if (sample_valid === 1'b1) begin
        check_true("valid i_ch1 contains no X/Z", (^i_ch1 !== 1'bx));
        check_true("valid i_ch2 contains no X/Z", (^i_ch2 !== 1'bx));
      end

      // current_compare_dual is intentionally checked on every clock.  Its
      // current implementation is combinational and is not sample_valid-gated.
      if ((^i_ch1 !== 1'bx) && (^i_ch2 !== 1'bx) &&
          (^th_oc_ch1 !== 1'bx) && (^th_oc_ch2 !== 1'bx) &&
          (^th_diff !== 1'bx)) begin
        check_true("absolute difference equation",
          abs_diff === ((i_ch1 >= i_ch2) ? (i_ch1 - i_ch2) : (i_ch2 - i_ch1)));
        check_true("strict overcurrent threshold equation",
          oc_any === ((i_ch1 > th_oc_ch1) || (i_ch2 > th_oc_ch2)));
        check_true("dual overcurrent equation",
          oc_both === ((i_ch1 > th_oc_ch1) && (i_ch2 > th_oc_ch2)));
        check_true("strict mismatch threshold equation",
          mismatch_flag === (abs_diff > th_diff));
      end

      pre_i_ch1 = i_ch1;
      pre_i_ch2 = i_ch2;
      pre_health_prev_ch1 = health_prev_ch1;
      pre_health_prev_ch2 = health_prev_ch2;
      pre_health_open_cnt = health_open_cnt;
      pre_health_sat_cnt = health_sat_cnt;
      pre_health_stuck_cnt = health_stuck_cnt;
      pre_sensor_open_flag = sensor_open_flag;
      pre_sensor_sat_flag = sensor_sat_flag;
      pre_sensor_stuck_flag = sensor_stuck_flag;
      pre_fault_valid = fault_valid;
      pre_fault_code = fault_code;
      pre_fault_code_latched = fault_code_latched;
      pre_fsm_state = fsm_state;

      #1;

      if (sample_valid === 1'b1) begin
        accepted_count = accepted_count + 1'b1;
        check_true("valid edge stores channel 1 in health history",
                   health_prev_ch1 === pre_i_ch1);
        check_true("valid edge stores channel 2 in health history",
                   health_prev_ch2 === pre_i_ch2);
        if (previous_sample_valid === 1'b1)
          consecutive_valid_count = consecutive_valid_count + 1'b1;
        if (reset_was_active === 1'b1) begin
          reset_release_first_sample_count = reset_release_first_sample_count + 1'b1;
          check_true("first clock after reset accepts a high valid",
                     (health_prev_ch1 === pre_i_ch1) &&
                     (health_prev_ch2 === pre_i_ch2));
        end
      end else begin
        invalid_hold_count = invalid_hold_count + 1'b1;
        check_true("invalid edge holds health previous samples",
                   (health_prev_ch1 === pre_health_prev_ch1) &&
                   (health_prev_ch2 === pre_health_prev_ch2));
        check_true("invalid edge holds health counters",
                   (health_open_cnt === pre_health_open_cnt) &&
                   (health_sat_cnt === pre_health_sat_cnt) &&
                   (health_stuck_cnt === pre_health_stuck_cnt));
        check_true("invalid edge holds health flags",
                   (sensor_open_flag === pre_sensor_open_flag) &&
                   (sensor_sat_flag === pre_sensor_sat_flag) &&
                   (sensor_stuck_flag === pre_sensor_stuck_flag));
      end

      // The classifier is one registered stage ahead of the FSM.  A visible
      // fault in NORMAL must be latched, coded, and gate PWM at this edge.
      if ((pre_fsm_state === ST_NORMAL) && (pre_fault_valid === 1'b1)) begin
        check_true("visible fault latches on next FSM edge",
                   (fault_latched === 1'b1) &&
                   (fsm_state === ST_FAULT_LATCHED));
        check_true("latched code captures visible first fault",
                   fault_code_latched === pre_fault_code);
        check_true("safe output asserts with fault latch", pwm_out === 1'b0);
      end

      // clear_fault may move the FSM to RESET_WAIT, but the code and latch are
      // retained on that transition.  No later live code overwrites the first
      // code while the FSM remains in ST_FAULT_LATCHED.
      if (pre_fsm_state === ST_FAULT_LATCHED) begin
        check_true("latched state retains fault indication",
                   fault_latched === 1'b1);
        check_true("latched state retains first-fault code",
                   fault_code_latched === pre_fault_code_latched);
      end

      if (fault_latched === 1'b1)
        check_true("fault latch keeps pwm_out safe-low", pwm_out === 1'b0);

      previous_sample_valid = sample_valid;
      reset_was_active = 1'b0;
    end
  end
endmodule
