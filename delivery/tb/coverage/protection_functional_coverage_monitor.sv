`timescale 1ns/1ps

module protection_functional_coverage_monitor (
  input logic        clk,
  input logic        rst_n,
  input logic        sample_valid,
  input logic        pwm_enable,
  input logic        clear_fault,
  input logic [11:0] i_ch1,
  input logic [11:0] i_ch2,
  input logic [11:0] th_oc_ch1,
  input logic [11:0] th_oc_ch2,
  input logic [11:0] th_diff,
  input logic [11:0] th_open,
  input logic [11:0] th_sat,
  input logic [11:0] th_stuck_delta,
  input logic [3:0]  th_persist,
  input logic        pwm_raw,
  input logic        pwm_out,
  input logic        oc_any,
  input logic        oc_both,
  input logic        mismatch_flag,
  input logic        classifier_oc_any,
  input logic        classifier_oc_both,
  input logic        classifier_mismatch,
  input logic        classifier_open,
  input logic        classifier_sat,
  input logic        classifier_stuck,
  input logic        sensor_open_flag,
  input logic        sensor_sat_flag,
  input logic        sensor_stuck_flag,
  input logic        fault_valid,
  input logic        fault_latched,
  input logic [7:0]  fault_code,
  input logic [7:0]  fault_code_latched,
  input logic [3:0]  fsm_state
);
  import protection_functional_coverage_pkg::*;

  localparam logic [7:0] FAULT_NONE              = 8'h00;
  localparam logic [7:0] FAULT_OVERCURRENT       = 8'h01;
  localparam logic [7:0] FAULT_SENSOR_MISMATCH   = 8'h02;
  localparam logic [7:0] FAULT_SENSOR_OPEN       = 8'h03;
  localparam logic [7:0] FAULT_SENSOR_SATURATION = 8'h04;
  localparam logic [7:0] FAULT_SENSOR_STUCK      = 8'h05;
  localparam logic [7:0] FAULT_OC_WITH_SENSOR    = 8'h06;

  localparam logic [3:0] ST_NORMAL        = 4'd0;
  localparam logic [3:0] ST_FAULT_LATCHED = 4'd1;
  localparam logic [3:0] ST_RESET_WAIT    = 4'd2;

  localparam logic [2:0] FC_PWM_DISABLED_LOW = 3'd0;
  localparam logic [2:0] FC_PWM_NORMAL_FOLLOW = 3'd1;
  localparam logic [2:0] FC_PWM_FAULT_SAFE_LOW = 3'd2;
  localparam logic [2:0] FC_PWM_WAIT_SAFE_LOW = 3'd3;
  localparam logic [2:0] FC_PWM_UNSAFE = 3'd4;
  localparam logic [2:0] FC_PWM_NORMAL_RECOVERY_HOLD_LOW = 3'd5;

  logic        oc_ch1_observed;
  logic        oc_ch2_observed;
  logic [11:0] abs_diff_observed;
  logic [11:0] min_current;
  logic [11:0] max_current;
  logic [3:0]  observed_fault_type;
  logic [1:0]  ch1_relation;
  logic [1:0]  ch2_relation;
  logic [1:0]  diff_relation;
  logic [1:0]  open_relation;
  logic [1:0]  sat_relation;
  logic [1:0]  stuck_delta_relation;
  logic [2:0]  pwm_safe_state;
  logic [1:0]  sample_valid_mode;
  logic [2:0]  health_status;
  logic [11:0] delta_ch1;
  logic [11:0] delta_ch2;
  logic [11:0] max_delta;

  logic [2:0] sampled_clear_outcome;
  logic [7:0] sampled_clear_campaign_code;
  logic       sampled_clear_campaign_active;
  logic [1:0] sampled_retention_kind;
  logic [7:0] sampled_retained_code;
  logic [3:0] sampled_reg_operation;
  logic [2:0] sampled_reg_class;
  logic [1:0] sampled_reg_effect;
  logic [3:0] sampled_reg_wstrb;
  logic [1:0] sampled_fsm_transition;
  logic       sampled_fsm_transition_valid;

  logic       ref_prev_sample_valid;
  logic [11:0] ref_prev_ch1;
  logic [11:0] ref_prev_ch2;
  logic [3:0] ref_open_cnt;
  logic [3:0] ref_sat_cnt;
  logic [3:0] ref_stuck_cnt;
  logic       ref_open_flag;
  logic       ref_sat_flag;
  logic       ref_stuck_flag;
  logic       ref_open_event;
  logic       ref_sat_event;
  logic       ref_stuck_event;
  logic       ref_decision_valid;
  logic       ref_decision_oc_ch1;
  logic       ref_decision_oc_ch2;
  logic       ref_decision_mismatch;

  logic [3:0] next_open_cnt;
  logic [3:0] next_sat_cnt;
  logic [3:0] next_stuck_cnt;
  logic       expected_open_flag;
  logic       expected_sat_flag;
  logic       expected_stuck_flag;
  logic       next_open_event;
  logic       next_sat_event;
  logic       next_stuck_event;
  logic       edge_sample_valid;
  logic [11:0] edge_i_ch1;
  logic [11:0] edge_i_ch2;
  logic [11:0] edge_th_oc_ch1;
  logic [11:0] edge_th_oc_ch2;
  logic [11:0] edge_th_diff;
  logic [11:0] edge_th_open;
  logic [11:0] edge_th_sat;
  logic [11:0] edge_th_stuck_delta;
  logic [3:0]  edge_th_persist;
  logic [11:0] edge_delta_ch1;
  logic [11:0] edge_delta_ch2;
  logic [11:0] edge_max_delta;
  logic       edge_classifier_oc_ch1;
  logic       edge_classifier_oc_ch2;
  logic       edge_classifier_mismatch;
  logic       edge_classifier_open;
  logic       edge_classifier_sat;
  logic       edge_classifier_stuck;
  logic       edge_actual_classifier_oc_any;
  logic       edge_actual_classifier_oc_both;
  logic       edge_actual_classifier_mismatch;
  logic       edge_actual_classifier_open;
  logic       edge_actual_classifier_sat;
  logic       edge_actual_classifier_stuck;
  logic       sampled_health_valid;
  logic [1:0] sampled_health_open_relation;
  logic [1:0] sampled_health_sat_relation;
  logic [1:0] sampled_health_stuck_delta_relation;
  logic       edge_expected_fault_valid;
  logic [7:0] edge_expected_fault_code;
  logic       edge_fsm_fault_valid;
  logic       edge_clear_fault;
  logic       prev_checked_fsm_valid;
  logic [3:0] prev_checked_fsm_state;
  logic       recovery_observed;
  logic       clear_campaign_active;
  logic [7:0] clear_campaign_fault_code;

  integer fault_checked_samples;
  integer threshold_checked_samples;
  integer fsm_checked_samples;
  integer clear_checked_samples;
  integer retention_checked_samples;
  integer health_checked_samples;
  integer register_checked_samples;

  function automatic logic [1:0] relation12(
    input logic [11:0] value,
    input logic [11:0] threshold
  );
    begin
      if (value < threshold)
        relation12 = FC_REL_BELOW;
      else if (value == threshold)
        relation12 = FC_REL_EQUAL;
      else
        relation12 = FC_REL_ABOVE;
    end
  endfunction

  function automatic logic [3:0] inc_sat4(input logic [3:0] value);
    begin
      inc_sat4 = (value == 4'hF) ? value : value + 1'b1;
    end
  endfunction

  function automatic logic [7:0] expected_classifier_code(
    input logic expected_oc_any,
    input logic expected_oc_both,
    input logic expected_mismatch,
    input logic expected_open,
    input logic expected_sat,
    input logic expected_stuck
  );
    begin
      if (expected_oc_any &&
          (expected_mismatch || expected_open || expected_sat || expected_stuck))
        expected_classifier_code = FAULT_OC_WITH_SENSOR;
      else if (expected_oc_both || expected_oc_any)
        expected_classifier_code = FAULT_OVERCURRENT;
      else if (expected_sat)
        expected_classifier_code = FAULT_SENSOR_SATURATION;
      else if (expected_open)
        expected_classifier_code = FAULT_SENSOR_OPEN;
      else if (expected_stuck)
        expected_classifier_code = FAULT_SENSOR_STUCK;
      else if (expected_mismatch)
        expected_classifier_code = FAULT_SENSOR_MISMATCH;
      else
        expected_classifier_code = FAULT_NONE;
    end
  endfunction

  always_comb begin
    oc_ch1_observed = (i_ch1 > th_oc_ch1);
    oc_ch2_observed = (i_ch2 > th_oc_ch2);
    abs_diff_observed = (i_ch1 >= i_ch2) ? (i_ch1 - i_ch2) : (i_ch2 - i_ch1);
    min_current = (i_ch1 <= i_ch2) ? i_ch1 : i_ch2;
    max_current = (i_ch1 >= i_ch2) ? i_ch1 : i_ch2;

    ch1_relation = relation12(i_ch1, th_oc_ch1);
    ch2_relation = relation12(i_ch2, th_oc_ch2);
    diff_relation = relation12(abs_diff_observed, th_diff);
    open_relation = relation12(min_current, th_open);
    sat_relation = relation12(max_current, th_sat);

    delta_ch1 = (i_ch1 >= ref_prev_ch1) ? (i_ch1 - ref_prev_ch1) : (ref_prev_ch1 - i_ch1);
    delta_ch2 = (i_ch2 >= ref_prev_ch2) ? (i_ch2 - ref_prev_ch2) : (ref_prev_ch2 - i_ch2);
    max_delta = (delta_ch1 >= delta_ch2) ? delta_ch1 : delta_ch2;
    stuck_delta_relation = relation12(max_delta, th_stuck_delta);

    case (edge_expected_fault_code)
      FAULT_OVERCURRENT: begin
        if (edge_classifier_oc_ch1 && edge_classifier_oc_ch2)
          observed_fault_type = FC_FT_DUAL_OC;
        else if (edge_classifier_oc_ch1)
          observed_fault_type = FC_FT_CH1_OC;
        else
          observed_fault_type = FC_FT_CH2_OC;
      end
      FAULT_SENSOR_MISMATCH:   observed_fault_type = FC_FT_MISMATCH;
      FAULT_SENSOR_OPEN:       observed_fault_type = FC_FT_SENSOR_OPEN;
      FAULT_SENSOR_SATURATION: observed_fault_type = FC_FT_SENSOR_SAT;
      FAULT_SENSOR_STUCK:      observed_fault_type = FC_FT_SENSOR_STUCK;
      FAULT_OC_WITH_SENSOR:    observed_fault_type = FC_FT_OC_WITH_SENSOR;
      default:                 observed_fault_type = FC_FT_NONE;
    endcase

    if (fsm_state == ST_FAULT_LATCHED)
      pwm_safe_state = pwm_out ? FC_PWM_UNSAFE : FC_PWM_FAULT_SAFE_LOW;
    else if (fsm_state == ST_RESET_WAIT)
      pwm_safe_state = pwm_out ? FC_PWM_UNSAFE : FC_PWM_WAIT_SAFE_LOW;
    else if (!pwm_enable)
      pwm_safe_state = pwm_out ? FC_PWM_UNSAFE : FC_PWM_DISABLED_LOW;
    else if (pwm_out == pwm_raw)
      pwm_safe_state = FC_PWM_NORMAL_FOLLOW;
    else if (!pwm_out && pwm_raw)
      // The FSM intentionally retains pwm_disable for the completion edge
      // that changes RESET_WAIT to NORMAL; it releases on the next clock.
      pwm_safe_state = FC_PWM_NORMAL_RECOVERY_HOLD_LOW;
    else
      pwm_safe_state = FC_PWM_UNSAFE;

    case ({sensor_open_flag, sensor_sat_flag, sensor_stuck_flag})
      3'b000: health_status = FC_HEALTH_STATUS_NONE;
      3'b100: health_status = FC_HEALTH_STATUS_OPEN;
      3'b010: health_status = FC_HEALTH_STATUS_SAT;
      3'b001: health_status = FC_HEALTH_STATUS_STUCK;
      default: health_status = FC_HEALTH_STATUS_MULTIPLE;
    endcase
  end

  // FCG-01: fault type and the real classifier code contract.
  covergroup cg_fault_type;
    option.per_instance = 1;
    cp_fault_type: coverpoint observed_fault_type {
      bins no_fault       = {FC_FT_NONE};
      bins ch1_oc         = {FC_FT_CH1_OC};
      bins ch2_oc         = {FC_FT_CH2_OC};
      bins dual_oc        = {FC_FT_DUAL_OC};
      bins mismatch       = {FC_FT_MISMATCH};
      bins sensor_open    = {FC_FT_SENSOR_OPEN};
      bins sensor_sat     = {FC_FT_SENSOR_SAT};
      bins sensor_stuck   = {FC_FT_SENSOR_STUCK};
      bins oc_with_sensor = {FC_FT_OC_WITH_SENSOR};
    }
    cp_fault_code: coverpoint fault_code {
      bins none           = {FAULT_NONE};
      bins overcurrent    = {FAULT_OVERCURRENT};
      bins mismatch       = {FAULT_SENSOR_MISMATCH};
      bins open_fault     = {FAULT_SENSOR_OPEN};
      bins saturation     = {FAULT_SENSOR_SATURATION};
      bins stuck          = {FAULT_SENSOR_STUCK};
      bins oc_with_sensor = {FAULT_OC_WITH_SENSOR};
      illegal_bins undefined_code = default;
    }
  endgroup

  // FCG-02: strict '>' threshold semantics for CH1, CH2 and differential.
  covergroup cg_threshold_boundaries;
    option.per_instance = 1;
    cp_ch1_relation: coverpoint ch1_relation {
      bins below = {FC_REL_BELOW}; bins equal = {FC_REL_EQUAL}; bins above = {FC_REL_ABOVE};
    }
    cp_ch1_decision: coverpoint oc_ch1_observed { bins no_trip = {0}; bins trip = {1}; }
    ch1_relation_x_decision: cross cp_ch1_relation, cp_ch1_decision {
      illegal_bins below_trip = binsof(cp_ch1_relation.below) && binsof(cp_ch1_decision.trip);
      illegal_bins equal_trip = binsof(cp_ch1_relation.equal) && binsof(cp_ch1_decision.trip);
      illegal_bins above_no_trip = binsof(cp_ch1_relation.above) && binsof(cp_ch1_decision.no_trip);
    }

    cp_ch2_relation: coverpoint ch2_relation {
      bins below = {FC_REL_BELOW}; bins equal = {FC_REL_EQUAL}; bins above = {FC_REL_ABOVE};
    }
    cp_ch2_decision: coverpoint oc_ch2_observed { bins no_trip = {0}; bins trip = {1}; }
    ch2_relation_x_decision: cross cp_ch2_relation, cp_ch2_decision {
      illegal_bins below_trip = binsof(cp_ch2_relation.below) && binsof(cp_ch2_decision.trip);
      illegal_bins equal_trip = binsof(cp_ch2_relation.equal) && binsof(cp_ch2_decision.trip);
      illegal_bins above_no_trip = binsof(cp_ch2_relation.above) && binsof(cp_ch2_decision.no_trip);
    }

    cp_diff_relation: coverpoint diff_relation {
      bins below = {FC_REL_BELOW}; bins equal = {FC_REL_EQUAL}; bins above = {FC_REL_ABOVE};
    }
    cp_diff_decision: coverpoint mismatch_flag { bins no_trip = {0}; bins trip = {1}; }
    diff_relation_x_decision: cross cp_diff_relation, cp_diff_decision {
      illegal_bins below_trip = binsof(cp_diff_relation.below) && binsof(cp_diff_decision.trip);
      illegal_bins equal_trip = binsof(cp_diff_relation.equal) && binsof(cp_diff_decision.trip);
      illegal_bins above_no_trip = binsof(cp_diff_relation.above) && binsof(cp_diff_decision.no_trip);
    }
  endgroup

  // FCG-03/04/06: legal FSM states/transitions and PWM safety relation.
  covergroup cg_fsm_pwm;
    option.per_instance = 1;
    cp_fsm_state: coverpoint fsm_state {
      bins normal = {ST_NORMAL};
      bins fault_latched = {ST_FAULT_LATCHED};
      bins reset_wait = {ST_RESET_WAIT};
      illegal_bins invalid_state = {[4'd3:4'd15]};
    }
    cp_fsm_transition: coverpoint sampled_fsm_transition iff (sampled_fsm_transition_valid) {
      bins normal_to_fault = {2'd0};
      bins fault_to_wait = {2'd1};
      bins wait_to_normal = {2'd2};
      bins wait_to_fault = {2'd3};
    }
    cp_pwm_safe_state: coverpoint pwm_safe_state {
      bins disabled_low = {FC_PWM_DISABLED_LOW};
      bins normal_follow = {FC_PWM_NORMAL_FOLLOW};
      bins fault_safe_low = {FC_PWM_FAULT_SAFE_LOW};
      bins wait_safe_low = {FC_PWM_WAIT_SAFE_LOW};
      bins normal_recovery_hold_low = {FC_PWM_NORMAL_RECOVERY_HOLD_LOW};
      illegal_bins unsafe = {FC_PWM_UNSAFE};
    }
    // XSim 2024.1 rejects binsof() references to a coverpoint illegal bin.
    // The unsafe value is already illegal above; these ignores remove only
    // state/PWM combinations excluded by the implemented FSM/gate contract.
    fsm_state_x_pwm_safe_state: cross cp_fsm_state, cp_pwm_safe_state {
      ignore_bins normal_non_normal_safety =
        binsof(cp_fsm_state.normal) &&
        (binsof(cp_pwm_safe_state.fault_safe_low) ||
         binsof(cp_pwm_safe_state.wait_safe_low));
      ignore_bins latched_non_latched_safety =
        binsof(cp_fsm_state.fault_latched) &&
        (binsof(cp_pwm_safe_state.disabled_low) ||
         binsof(cp_pwm_safe_state.normal_follow) ||
         binsof(cp_pwm_safe_state.wait_safe_low) ||
         binsof(cp_pwm_safe_state.normal_recovery_hold_low));
      ignore_bins wait_non_wait_safety =
        binsof(cp_fsm_state.reset_wait) &&
        (binsof(cp_pwm_safe_state.disabled_low) ||
         binsof(cp_pwm_safe_state.normal_follow) ||
         binsof(cp_pwm_safe_state.fault_safe_low) ||
         binsof(cp_pwm_safe_state.normal_recovery_hold_low));
    }
  endgroup

  // FCG-05 and fault_type x clear_outcome.
  covergroup cg_clear_recovery;
    option.per_instance = 1;
    cp_clear_outcome: coverpoint sampled_clear_outcome {
      bins live_rejected = {FC_CLEAR_LIVE_REJECTED};
      bins no_clear_retained = {FC_CLEAR_NO_CLEAR_RETAINED};
      bins legal_clear = {FC_CLEAR_LEGAL};
      bins repeated_clear = {FC_CLEAR_REPEATED};
      bins recovery_complete = {FC_CLEAR_RECOVERY_COMPLETE};
    }
    cp_clear_campaign_fault_class: coverpoint sampled_clear_campaign_code {
      bins overcurrent = {FAULT_OVERCURRENT};
      bins sensor_or_mismatch = {FAULT_SENSOR_MISMATCH, FAULT_SENSOR_OPEN,
                                 FAULT_SENSOR_SATURATION, FAULT_SENSOR_STUCK,
                                 FAULT_OC_WITH_SENSOR};
      illegal_bins no_campaign = {FAULT_NONE};
    }
    cp_clear_campaign_active: coverpoint sampled_clear_campaign_active {
      bins active = {1'b1};
      illegal_bins inactive = {1'b0};
    }
    clear_campaign_fault_class_x_clear_outcome:
      cross cp_clear_campaign_fault_class, cp_clear_outcome;
  endgroup

  // FCG-07 and fault_type x first_fault_latched_code.
  covergroup cg_first_fault_retention;
    option.per_instance = 1;
    cp_retention_kind: coverpoint sampled_retention_kind {
      bins first_captured = {FC_RET_FIRST_CAPTURED};
      bins later_not_overwrite = {FC_RET_LATER_NOT_OVERWRITE};
      bins new_after_recovery = {FC_RET_NEW_AFTER_RECOVERY};
    }
    cp_retained_code: coverpoint sampled_retained_code {
      bins overcurrent = {FAULT_OVERCURRENT};
      bins mismatch = {FAULT_SENSOR_MISMATCH};
      bins health_or_combined = {FAULT_SENSOR_OPEN, FAULT_SENSOR_SATURATION,
                                 FAULT_SENSOR_STUCK, FAULT_OC_WITH_SENSOR};
    }
    fault_type_x_first_fault_latched_code: cross cp_retention_kind, cp_retained_code;
  endgroup

  // FCG-08: valid/gap modes, health flags and configured boundaries.
  covergroup cg_sample_health;
    option.per_instance = 1;
    cp_sample_valid: coverpoint sampled_health_valid {
      bins invalid = {0}; bins valid = {1};
    }
    cp_sample_mode: coverpoint sample_valid_mode {
      bins invalid = {FC_SAMPLE_INVALID};
      bins after_gap = {FC_SAMPLE_AFTER_GAP};
      bins continuous = {FC_SAMPLE_CONTINUOUS};
      bins gap_start = {FC_SAMPLE_GAP_START};
    }
    cp_open_relation: coverpoint sampled_health_open_relation
      iff (sampled_health_valid) {
      bins below = {FC_REL_BELOW}; bins equal = {FC_REL_EQUAL}; bins above = {FC_REL_ABOVE};
    }
    cp_sat_relation: coverpoint sampled_health_sat_relation
      iff (sampled_health_valid) {
      bins below = {FC_REL_BELOW}; bins equal = {FC_REL_EQUAL}; bins above = {FC_REL_ABOVE};
    }
    cp_stuck_delta_relation: coverpoint sampled_health_stuck_delta_relation
      iff (sampled_health_valid) {
      bins below = {FC_REL_BELOW}; bins equal = {FC_REL_EQUAL}; bins above = {FC_REL_ABOVE};
    }
    cp_health_status: coverpoint health_status {
      bins none = {FC_HEALTH_STATUS_NONE};
      bins open_fault = {FC_HEALTH_STATUS_OPEN};
      bins saturation = {FC_HEALTH_STATUS_SAT};
      bins stuck = {FC_HEALTH_STATUS_STUCK};
      bins multiple = {FC_HEALTH_STATUS_MULTIPLE};
    }
    sample_mode_x_health_status: cross cp_sample_mode, cp_health_status;
  endgroup

  // FCG-09: AXI/register operation, WSTRB and observed effect.
  covergroup cg_register_behavior;
    option.per_instance = 1;
    cp_register_operation: coverpoint sampled_reg_operation {
      bins ctrl_disabled = {FC_REG_CTRL_DISABLED};
      bins clear_only = {FC_REG_CLEAR_ONLY};
      bins enable = {FC_REG_ENABLE};
      bins th_oc1 = {FC_REG_TH_OC1};
      bins th_oc2 = {FC_REG_TH_OC2};
      bins th_diff = {FC_REG_TH_DIFF};
      bins pwm_period = {FC_REG_PWM_PERIOD};
      bins pwm_duty = {FC_REG_PWM_DUTY};
      bins status_read = {FC_REG_STATUS_READ};
      bins fault_read = {FC_REG_FAULT_READ};
      bins unknown_reserved = {FC_REG_UNKNOWN};
      bins wstrb_behavior = {FC_REG_WSTRB};
    }
    cp_reg_class: coverpoint sampled_reg_class {
      bins control = {FC_REG_CLASS_CONTROL};
      bins threshold = {FC_REG_CLASS_THRESHOLD};
      bins pwm_config = {FC_REG_CLASS_PWM_CONFIG};
      bins status_read = {FC_REG_CLASS_STATUS};
      bins fault_read = {FC_REG_CLASS_FAULT};
      bins unknown_reserved = {FC_REG_CLASS_UNKNOWN};
      bins strobe = {FC_REG_CLASS_STROBE};
    }
    cp_observed_control_effect: coverpoint sampled_reg_effect {
      bins applied = {FC_REG_EFFECT_APPLIED};
      bins observed = {FC_REG_EFFECT_OBSERVED};
      bins no_effect_expected = {FC_REG_EFFECT_NO_EFFECT};
    }
    cp_wstrb: coverpoint sampled_reg_wstrb {
      bins zero = {4'b0000};
      bins full = {4'b1111};
      bins partial = {[4'b0001:4'b1110]};
    }
    register_operation_x_observed_control_effect: cross cp_reg_class, cp_observed_control_effect {
      // These ignored combinations are semantically void under the current
      // register contract; they are not exclusions of DUT implementation.
      ignore_bins write_class_not_applied =
        (binsof(cp_reg_class.control) ||
         binsof(cp_reg_class.threshold) ||
         binsof(cp_reg_class.pwm_config)) &&
        (binsof(cp_observed_control_effect.observed) ||
         binsof(cp_observed_control_effect.no_effect_expected));
      ignore_bins read_class_not_observed =
        (binsof(cp_reg_class.status_read) ||
         binsof(cp_reg_class.fault_read)) &&
        (binsof(cp_observed_control_effect.applied) ||
         binsof(cp_observed_control_effect.no_effect_expected));
      ignore_bins unknown_not_no_effect =
        binsof(cp_reg_class.unknown_reserved) &&
        (binsof(cp_observed_control_effect.applied) ||
         binsof(cp_observed_control_effect.observed));
      ignore_bins strobe_not_write_effect =
        binsof(cp_reg_class.strobe) &&
        binsof(cp_observed_control_effect.observed);
    }
  endgroup

  cg_fault_type              fault_type_cov;
  cg_threshold_boundaries    threshold_cov;
  cg_fsm_pwm                 fsm_pwm_cov;
  cg_clear_recovery          clear_cov;
  cg_first_fault_retention   retention_cov;
  cg_sample_health           sample_health_cov;
  cg_register_behavior       register_cov;

  initial begin
    fault_checked_samples = 0;
    threshold_checked_samples = 0;
    fsm_checked_samples = 0;
    clear_checked_samples = 0;
    retention_checked_samples = 0;
    health_checked_samples = 0;
    register_checked_samples = 0;
    recovery_observed = 1'b0;
    clear_campaign_active = 1'b0;
    clear_campaign_fault_code = FAULT_NONE;
    sampled_clear_campaign_code = FAULT_NONE;
    sampled_clear_campaign_active = 1'b0;
    prev_checked_fsm_valid = 1'b0;
    sampled_fsm_transition_valid = 1'b0;
    fault_type_cov = new();
    threshold_cov = new();
    fsm_pwm_cov = new();
    clear_cov = new();
    retention_cov = new();
    sample_health_cov = new();
    register_cov = new();
  end

  task automatic check_contract(input string label, input logic condition);
    begin
      assert (condition === 1'b1)
        else $fatal(1, "FUNCTIONAL COVERAGE CHECK FAILED: %s", label);
    end
  endtask

  task automatic sample_fault_type_checked;
    begin
      check_contract("fault sample outside reset", rst_n);
      check_contract(
        "classifier overcurrent pipeline contract",
        edge_actual_classifier_oc_any ===
          (edge_classifier_oc_ch1 || edge_classifier_oc_ch2) &&
        edge_actual_classifier_oc_both ===
          (edge_classifier_oc_ch1 && edge_classifier_oc_ch2)
      );
      check_contract(
        "classifier mismatch pipeline contract",
        edge_actual_classifier_mismatch === edge_classifier_mismatch
      );
      check_contract(
        "classifier health pipeline contract",
        edge_actual_classifier_open === edge_classifier_open &&
        edge_actual_classifier_sat === edge_classifier_sat &&
        edge_actual_classifier_stuck === edge_classifier_stuck
      );
      check_contract(
        "classifier fault_valid contract",
        fault_valid === edge_expected_fault_valid
      );
      check_contract(
        "classifier fault_code priority contract",
        fault_code === edge_expected_fault_code
      );

      case (observed_fault_type)
        FC_FT_NONE:
          check_contract("no-fault origin", fault_code === FAULT_NONE);
        FC_FT_CH1_OC:
          check_contract(
            "CH1 overcurrent origin",
            fault_code === FAULT_OVERCURRENT &&
            edge_classifier_oc_ch1 && !edge_classifier_oc_ch2
          );
        FC_FT_CH2_OC:
          check_contract(
            "CH2 overcurrent origin",
            fault_code === FAULT_OVERCURRENT &&
            !edge_classifier_oc_ch1 && edge_classifier_oc_ch2
          );
        FC_FT_DUAL_OC:
          check_contract(
            "dual overcurrent origin",
            fault_code === FAULT_OVERCURRENT &&
            edge_classifier_oc_ch1 && edge_classifier_oc_ch2
          );
        FC_FT_MISMATCH:
          check_contract("mismatch code mapping", fault_code === FAULT_SENSOR_MISMATCH);
        FC_FT_SENSOR_OPEN:
          check_contract("open code mapping", fault_code === FAULT_SENSOR_OPEN);
        FC_FT_SENSOR_SAT:
          check_contract("saturation code mapping", fault_code === FAULT_SENSOR_SATURATION);
        FC_FT_SENSOR_STUCK:
          check_contract("stuck code mapping", fault_code === FAULT_SENSOR_STUCK);
        FC_FT_OC_WITH_SENSOR:
          check_contract("combined code mapping", fault_code === FAULT_OC_WITH_SENSOR);
        default:
          check_contract("defined fault origin", 1'b0);
      endcase

      fault_checked_samples = fault_checked_samples + 1;
      fault_type_cov.sample();
    end
  endtask

  task automatic sample_threshold_checked;
    begin
      check_contract("threshold sample outside reset", rst_n);
      check_contract(
        "oc_any comparator contract",
        oc_any === (oc_ch1_observed || oc_ch2_observed)
      );
      check_contract(
        "oc_both comparator contract",
        oc_both === (oc_ch1_observed && oc_ch2_observed)
      );
      check_contract(
        "mismatch comparator contract",
        mismatch_flag === (abs_diff_observed > th_diff)
      );
      check_contract(
        "CH1 relation/decision contract",
        oc_ch1_observed === (ch1_relation == FC_REL_ABOVE)
      );
      check_contract(
        "CH2 relation/decision contract",
        oc_ch2_observed === (ch2_relation == FC_REL_ABOVE)
      );
      check_contract(
        "DIFF relation/decision contract",
        mismatch_flag === (diff_relation == FC_REL_ABOVE)
      );

      threshold_checked_samples = threshold_checked_samples + 1;
      threshold_cov.sample();
    end
  endtask

  task automatic sample_fsm_pwm_checked;
    begin
      check_contract("FSM sample outside reset", rst_n);
      check_contract(
        "FSM legal state encoding",
        fsm_state == ST_NORMAL ||
        fsm_state == ST_FAULT_LATCHED ||
        fsm_state == ST_RESET_WAIT
      );

      sampled_fsm_transition_valid = 1'b0;
      if (prev_checked_fsm_valid) begin
        case (prev_checked_fsm_state)
          ST_NORMAL: begin
            if (fsm_state == ST_FAULT_LATCHED) begin
              check_contract("NORMAL to FAULT requires live fault", edge_fsm_fault_valid);
              sampled_fsm_transition = 2'd0;
              sampled_fsm_transition_valid = 1'b1;
            end else begin
              check_contract(
                "NORMAL legal successor",
                fsm_state == ST_NORMAL && !edge_fsm_fault_valid
              );
            end
          end

          ST_FAULT_LATCHED: begin
            if (fsm_state == ST_RESET_WAIT) begin
              check_contract("FAULT to WAIT requires clear", edge_clear_fault);
              sampled_fsm_transition = 2'd1;
              sampled_fsm_transition_valid = 1'b1;
            end else begin
              check_contract(
                "FAULT legal successor",
                fsm_state == ST_FAULT_LATCHED && !edge_clear_fault
              );
            end
          end

          ST_RESET_WAIT: begin
            if (fsm_state == ST_FAULT_LATCHED) begin
              check_contract("WAIT to FAULT requires live fault", edge_fsm_fault_valid);
              sampled_fsm_transition = 2'd3;
              sampled_fsm_transition_valid = 1'b1;
            end else if (fsm_state == ST_NORMAL) begin
              check_contract(
                "WAIT to NORMAL requires removed source and released clear",
                !edge_fsm_fault_valid && !edge_clear_fault
              );
              sampled_fsm_transition = 2'd2;
              sampled_fsm_transition_valid = 1'b1;
            end else begin
              check_contract(
                "WAIT legal successor",
                fsm_state == ST_RESET_WAIT && !edge_fsm_fault_valid
              );
            end
          end

          default:
            check_contract("previous checked FSM state legal", 1'b0);
        endcase
      end

      case (fsm_state)
        ST_NORMAL: begin
          check_contract("NORMAL latch clear", !fault_latched);
          check_contract("NORMAL code clear", fault_code_latched == FAULT_NONE);
          if (!pwm_enable)
            check_contract("disabled PWM safe-low", !pwm_out);
          else if (prev_checked_fsm_valid &&
                   prev_checked_fsm_state == ST_RESET_WAIT)
            check_contract("recovery completion PWM hold-low", !pwm_out);
          else
            check_contract("healthy enabled PWM follows raw", pwm_out === pwm_raw);
        end

        ST_FAULT_LATCHED: begin
          check_contract("FAULT latch asserted", fault_latched);
          check_contract("FAULT code retained", fault_code_latched != FAULT_NONE);
          check_contract("FAULT PWM safe-low", !pwm_out);
        end

        ST_RESET_WAIT: begin
          check_contract("WAIT latch asserted", fault_latched);
          check_contract("WAIT code retained", fault_code_latched != FAULT_NONE);
          check_contract("WAIT PWM safe-low", !pwm_out);
        end

        default:
          check_contract("FSM state checker default", 1'b0);
      endcase

      check_contract("PWM classification is safe", pwm_safe_state != FC_PWM_UNSAFE);
      fsm_checked_samples = fsm_checked_samples + 1;
      fsm_pwm_cov.sample();
      prev_checked_fsm_state = fsm_state;
      prev_checked_fsm_valid = 1'b1;
    end
  endtask

  task automatic sample_health_checked;
    begin
      check_contract("health sample outside reset", rst_n);
      check_contract("open flag reference model", sensor_open_flag === expected_open_flag);
      check_contract("saturation flag reference model", sensor_sat_flag === expected_sat_flag);
      check_contract("stuck flag reference model", sensor_stuck_flag === expected_stuck_flag);

      case (sample_valid_mode)
        FC_SAMPLE_INVALID:
          check_contract(
            "invalid sample mode",
            !edge_sample_valid && !ref_prev_sample_valid
          );
        FC_SAMPLE_AFTER_GAP:
          check_contract(
            "after-gap sample mode",
            edge_sample_valid && !ref_prev_sample_valid
          );
        FC_SAMPLE_CONTINUOUS:
          check_contract(
            "continuous sample mode",
            edge_sample_valid && ref_prev_sample_valid
          );
        FC_SAMPLE_GAP_START:
          check_contract(
            "gap-start sample mode",
            !edge_sample_valid && ref_prev_sample_valid
          );
        default:
          check_contract("defined sample-valid mode", 1'b0);
      endcase

      if (edge_sample_valid) begin
        check_contract(
          "open boundary contract",
          (sampled_health_open_relation != FC_REL_ABOVE) ===
          ((edge_i_ch1 <= edge_th_open) ||
           (edge_i_ch2 <= edge_th_open))
        );
        check_contract(
          "saturation boundary contract",
          (sampled_health_sat_relation != FC_REL_BELOW) ===
          ((edge_i_ch1 >= edge_th_sat) ||
           (edge_i_ch2 >= edge_th_sat))
        );
        check_contract(
          "stuck boundary contract",
          (sampled_health_stuck_delta_relation != FC_REL_ABOVE) ===
          (((edge_i_ch1 >= ref_prev_ch1) ?
            (edge_i_ch1 - ref_prev_ch1) :
            (ref_prev_ch1 - edge_i_ch1)) <= edge_th_stuck_delta &&
           ((edge_i_ch2 >= ref_prev_ch2) ?
            (edge_i_ch2 - ref_prev_ch2) :
            (ref_prev_ch2 - edge_i_ch2)) <= edge_th_stuck_delta)
        );
      end

      health_checked_samples = health_checked_samples + 1;
      sample_health_cov.sample();
    end
  endtask

  task automatic sample_clear_checked(
    input logic [2:0] outcome,
    input logic [7:0] expected_campaign_code
  );
    begin
      check_contract("clear sample outside reset", rst_n);
      check_contract(
        "clear campaign expected code is a defined fault",
        expected_campaign_code > FAULT_NONE &&
        expected_campaign_code <= FAULT_OC_WITH_SENSOR
      );

      if (outcome != FC_CLEAR_RECOVERY_COMPLETE) begin
        check_contract("clear campaign starts from a latched fault", fault_code_latched != FAULT_NONE);
        if (!clear_campaign_active) begin
          clear_campaign_active = 1'b1;
          clear_campaign_fault_code = fault_code_latched;
        end
        check_contract(
          "clear campaign retains the original latched code",
          fault_code_latched === clear_campaign_fault_code
        );
      end else begin
        check_contract("recovery completes an active clear campaign", clear_campaign_active);
      end

      check_contract(
        "clear campaign expected class matches captured class",
        clear_campaign_fault_code === expected_campaign_code
      );
      if (expected_campaign_code == FAULT_OVERCURRENT)
        check_contract(
          "overcurrent clear campaign fault class preserved",
          clear_campaign_fault_code === FAULT_OVERCURRENT
        );

      sampled_clear_outcome = outcome;
      sampled_clear_campaign_code = clear_campaign_fault_code;
      sampled_clear_campaign_active = clear_campaign_active;

      case (outcome)
        FC_CLEAR_LIVE_REJECTED: begin
          check_contract("live-clear source remains active", fault_valid);
          check_contract(
            "live-clear remains safely latched",
            fsm_state == ST_FAULT_LATCHED && fault_latched &&
            fault_code_latched != FAULT_NONE && !pwm_out
          );
        end

        FC_CLEAR_NO_CLEAR_RETAINED: begin
          check_contract("removed source is inactive", !fault_valid);
          check_contract(
            "source removal without clear retains latch",
            fsm_state == ST_FAULT_LATCHED && fault_latched &&
            fault_code_latched != FAULT_NONE && !pwm_out
          );
        end

        FC_CLEAR_LEGAL: begin
          check_contract("legal clear has no live source", !fault_valid);
          check_contract(
            "legal clear enters safe RESET_WAIT",
            fsm_state == ST_RESET_WAIT && fault_latched &&
            fault_code_latched != FAULT_NONE && !pwm_out
          );
        end

        FC_CLEAR_REPEATED: begin
          check_contract("repeated clear has no live source", !fault_valid);
          check_contract(
            "repeated clear remains safe in RESET_WAIT",
            fsm_state == ST_RESET_WAIT && fault_latched &&
            fault_code_latched != FAULT_NONE && !pwm_out
          );
        end

        FC_CLEAR_RECOVERY_COMPLETE: begin
          check_contract("recovery complete source inactive", !fault_valid);
          check_contract(
            "recovery complete returns safe NORMAL",
            fsm_state == ST_NORMAL && !fault_latched &&
            fault_code_latched == FAULT_NONE
          );
        end

        default:
          check_contract("defined clear outcome", 1'b0);
      endcase

      clear_checked_samples = clear_checked_samples + 1;
      clear_cov.sample();
      if (outcome == FC_CLEAR_RECOVERY_COMPLETE) begin
        recovery_observed = 1'b1;
        clear_campaign_active = 1'b0;
        clear_campaign_fault_code = FAULT_NONE;
      end
    end
  endtask

  task automatic sample_retention_checked(input logic [1:0] kind);
    begin
      check_contract("retention sample outside reset", rst_n);
      sampled_retention_kind = kind;
      sampled_retained_code = fault_code_latched;

      case (kind)
        FC_RET_FIRST_CAPTURED:
          check_contract(
            "first fault captured with matching live code",
            fsm_state == ST_FAULT_LATCHED && fault_valid && fault_latched &&
            fault_code_latched != FAULT_NONE &&
            fault_code_latched == fault_code
          );

        FC_RET_LATER_NOT_OVERWRITE:
          check_contract(
            "later different fault does not overwrite first code",
            fsm_state == ST_FAULT_LATCHED && fault_valid && fault_latched &&
            fault_code != FAULT_NONE &&
            fault_code_latched != fault_code
          );

        FC_RET_NEW_AFTER_RECOVERY: begin
          check_contract("new first fault follows checked recovery", recovery_observed);
          check_contract(
            "new first fault captured after recovery",
            fsm_state == ST_FAULT_LATCHED && fault_valid && fault_latched &&
            fault_code_latched != FAULT_NONE &&
            fault_code_latched == fault_code
          );
        end

        default:
          check_contract("defined retention kind", 1'b0);
      endcase

      retention_checked_samples = retention_checked_samples + 1;
      retention_cov.sample();
    end
  endtask

  task automatic sample_register_checked(
    input logic [3:0] operation,
    input logic [2:0] operation_class,
    input logic [1:0] effect,
    input logic [3:0] strobe,
    input logic       behavior_proven
  );
    begin
      check_contract("register sample outside reset", rst_n);
      check_contract("register operation checker passed", behavior_proven);

      case (operation)
        FC_REG_CTRL_DISABLED,
        FC_REG_CLEAR_ONLY,
        FC_REG_ENABLE: begin
          check_contract(
            "control operation metadata",
            operation_class == FC_REG_CLASS_CONTROL &&
            effect == FC_REG_EFFECT_APPLIED && strobe != 4'b0000
          );
        end

        FC_REG_TH_OC1,
        FC_REG_TH_OC2,
        FC_REG_TH_DIFF: begin
          check_contract(
            "threshold operation metadata",
            operation_class == FC_REG_CLASS_THRESHOLD &&
            effect == FC_REG_EFFECT_APPLIED && strobe != 4'b0000
          );
        end

        FC_REG_PWM_PERIOD,
        FC_REG_PWM_DUTY: begin
          check_contract(
            "PWM configuration metadata",
            operation_class == FC_REG_CLASS_PWM_CONFIG &&
            effect == FC_REG_EFFECT_APPLIED && strobe != 4'b0000
          );
        end

        FC_REG_STATUS_READ: begin
          check_contract(
            "STATUS read metadata",
            operation_class == FC_REG_CLASS_STATUS &&
            effect == FC_REG_EFFECT_OBSERVED && strobe == 4'b0000
          );
        end

        FC_REG_FAULT_READ: begin
          check_contract(
            "FAULT_CODE read metadata",
            operation_class == FC_REG_CLASS_FAULT &&
            effect == FC_REG_EFFECT_OBSERVED && strobe == 4'b0000
          );
        end

        FC_REG_UNKNOWN: begin
          check_contract(
            "unknown-address metadata",
            operation_class == FC_REG_CLASS_UNKNOWN &&
            effect == FC_REG_EFFECT_NO_EFFECT
          );
        end

        FC_REG_WSTRB: begin
          check_contract("WSTRB operation class", operation_class == FC_REG_CLASS_STROBE);
          if (strobe == 4'b0000)
            check_contract("zero WSTRB has no effect", effect == FC_REG_EFFECT_NO_EFFECT);
          else
            check_contract("nonzero WSTRB applies write", effect == FC_REG_EFFECT_APPLIED);
        end

        default:
          check_contract("defined register operation", 1'b0);
      endcase

      sampled_reg_operation = operation;
      sampled_reg_class = operation_class;
      sampled_reg_effect = effect;
      sampled_reg_wstrb = strobe;
      register_checked_samples = register_checked_samples + 1;
      register_cov.sample();
    end
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      ref_prev_sample_valid = 1'b0;
      ref_prev_ch1 = 12'd0;
      ref_prev_ch2 = 12'd0;
      ref_open_cnt = 4'd0;
      ref_sat_cnt = 4'd0;
      ref_stuck_cnt = 4'd0;
      ref_open_flag = 1'b0;
      ref_sat_flag = 1'b0;
      ref_stuck_flag = 1'b0;
      ref_open_event = 1'b0;
      ref_sat_event = 1'b0;
      ref_stuck_event = 1'b0;
      ref_decision_valid = 1'b0;
      ref_decision_oc_ch1 = 1'b0;
      ref_decision_oc_ch2 = 1'b0;
      ref_decision_mismatch = 1'b0;
      edge_expected_fault_valid = 1'b0;
      edge_expected_fault_code = FAULT_NONE;
      prev_checked_fsm_valid = 1'b0;
      sampled_fsm_transition_valid = 1'b0;
      recovery_observed = 1'b0;
      clear_campaign_active = 1'b0;
      clear_campaign_fault_code = FAULT_NONE;
      sampled_clear_campaign_code = FAULT_NONE;
      sampled_clear_campaign_active = 1'b0;
    end else begin
      edge_fsm_fault_valid = fault_valid;
      edge_clear_fault = clear_fault;
      edge_sample_valid = sample_valid;
      edge_i_ch1 = i_ch1;
      edge_i_ch2 = i_ch2;
      edge_th_oc_ch1 = th_oc_ch1;
      edge_th_oc_ch2 = th_oc_ch2;
      edge_th_diff = th_diff;
      edge_th_open = th_open;
      edge_th_sat = th_sat;
      edge_th_stuck_delta = th_stuck_delta;
      edge_th_persist = th_persist;
      edge_delta_ch1 = (edge_i_ch1 >= ref_prev_ch1) ?
        (edge_i_ch1 - ref_prev_ch1) : (ref_prev_ch1 - edge_i_ch1);
      edge_delta_ch2 = (edge_i_ch2 >= ref_prev_ch2) ?
        (edge_i_ch2 - ref_prev_ch2) : (ref_prev_ch2 - edge_i_ch2);
      edge_max_delta = (edge_delta_ch1 >= edge_delta_ch2) ?
        edge_delta_ch1 : edge_delta_ch2;

      edge_classifier_oc_ch1 =
        ref_decision_valid && ref_decision_oc_ch1;
      edge_classifier_oc_ch2 =
        ref_decision_valid && ref_decision_oc_ch2;
      edge_classifier_mismatch =
        ref_decision_valid && ref_decision_mismatch;
      edge_classifier_open = ref_decision_valid && ref_open_event;
      edge_classifier_sat = ref_decision_valid && ref_sat_event;
      edge_classifier_stuck = ref_decision_valid && ref_stuck_event;
      edge_actual_classifier_oc_any = classifier_oc_any;
      edge_actual_classifier_oc_both = classifier_oc_both;
      edge_actual_classifier_mismatch = classifier_mismatch;
      edge_actual_classifier_open = classifier_open;
      edge_actual_classifier_sat = classifier_sat;
      edge_actual_classifier_stuck = classifier_stuck;
      edge_expected_fault_valid =
        edge_actual_classifier_oc_any ||
        edge_actual_classifier_mismatch || edge_actual_classifier_open ||
        edge_actual_classifier_sat || edge_actual_classifier_stuck;
      edge_expected_fault_code = expected_classifier_code(
        edge_actual_classifier_oc_any,
        edge_actual_classifier_oc_both,
        edge_actual_classifier_mismatch,
        edge_actual_classifier_open,
        edge_actual_classifier_sat,
        edge_actual_classifier_stuck
      );

      if (edge_sample_valid && ref_prev_sample_valid)
        sample_valid_mode = FC_SAMPLE_CONTINUOUS;
      else if (edge_sample_valid)
        sample_valid_mode = FC_SAMPLE_AFTER_GAP;
      else if (ref_prev_sample_valid)
        sample_valid_mode = FC_SAMPLE_GAP_START;
      else
        sample_valid_mode = FC_SAMPLE_INVALID;

      next_open_cnt = ref_open_cnt;
      next_sat_cnt = ref_sat_cnt;
      next_stuck_cnt = ref_stuck_cnt;
      expected_open_flag = ref_open_flag;
      expected_sat_flag = ref_sat_flag;
      expected_stuck_flag = ref_stuck_flag;
      next_open_event = 1'b0;
      next_sat_event = 1'b0;
      next_stuck_event = 1'b0;
      sampled_health_valid = edge_sample_valid;
      sampled_health_open_relation = relation12(
        (edge_i_ch1 <= edge_i_ch2) ? edge_i_ch1 : edge_i_ch2,
        edge_th_open
      );
      sampled_health_sat_relation = relation12(
        (edge_i_ch1 >= edge_i_ch2) ? edge_i_ch1 : edge_i_ch2,
        edge_th_sat
      );
      sampled_health_stuck_delta_relation = relation12(
        edge_max_delta,
        edge_th_stuck_delta
      );

      if (edge_sample_valid) begin
        next_open_cnt =
          (edge_i_ch1 <= edge_th_open ||
           edge_i_ch2 <= edge_th_open) ?
          inc_sat4(ref_open_cnt) : 4'd0;
        next_sat_cnt =
          (edge_i_ch1 >= edge_th_sat ||
           edge_i_ch2 >= edge_th_sat) ?
          inc_sat4(ref_sat_cnt) : 4'd0;
        next_stuck_cnt =
          (edge_delta_ch1 <= edge_th_stuck_delta &&
           edge_delta_ch2 <= edge_th_stuck_delta) ?
          inc_sat4(ref_stuck_cnt) : 4'd0;
        expected_open_flag = (ref_open_cnt >= edge_th_persist);
        expected_sat_flag = (ref_sat_cnt >= edge_th_persist);
        expected_stuck_flag = (ref_stuck_cnt >= edge_th_persist);
        next_open_event =
          (edge_i_ch1 <= edge_th_open ||
           edge_i_ch2 <= edge_th_open) &&
          (ref_open_cnt >= edge_th_persist);
        next_sat_event =
          (edge_i_ch1 >= edge_th_sat ||
           edge_i_ch2 >= edge_th_sat) &&
          (ref_sat_cnt >= edge_th_persist);
        next_stuck_event =
          (edge_delta_ch1 <= edge_th_stuck_delta &&
           edge_delta_ch2 <= edge_th_stuck_delta) &&
          (ref_stuck_cnt >= edge_th_persist);
      end

      #1;
      sample_fault_type_checked();
      sample_threshold_checked();
      sample_fsm_pwm_checked();
      sample_health_checked();

      ref_open_cnt = next_open_cnt;
      ref_sat_cnt = next_sat_cnt;
      ref_stuck_cnt = next_stuck_cnt;
      ref_open_flag = expected_open_flag;
      ref_sat_flag = expected_sat_flag;
      ref_stuck_flag = expected_stuck_flag;
      ref_open_event = next_open_event;
      ref_sat_event = next_sat_event;
      ref_stuck_event = next_stuck_event;
      ref_decision_valid = edge_sample_valid;
      if (edge_sample_valid) begin
        ref_decision_oc_ch1 = edge_i_ch1 > edge_th_oc_ch1;
        ref_decision_oc_ch2 = edge_i_ch2 > edge_th_oc_ch2;
        ref_decision_mismatch =
          ((edge_i_ch1 >= edge_i_ch2) ?
           (edge_i_ch1 - edge_i_ch2) :
           (edge_i_ch2 - edge_i_ch1)) > edge_th_diff;
      end
      ref_prev_sample_valid = edge_sample_valid;
      if (edge_sample_valid) begin
        ref_prev_ch1 = edge_i_ch1;
        ref_prev_ch2 = edge_i_ch2;
      end
    end
  end

  task automatic report_summary;
    begin
      check_contract("fault coverage received checked samples", fault_checked_samples > 0);
      check_contract("threshold coverage received checked samples", threshold_checked_samples > 0);
      check_contract("FSM coverage received checked samples", fsm_checked_samples > 0);
      check_contract("clear coverage received checked samples", clear_checked_samples > 0);
      check_contract("retention coverage received checked samples", retention_checked_samples > 0);
      check_contract("health coverage received checked samples", health_checked_samples > 0);
      check_contract("register coverage received checked samples", register_checked_samples > 0);
      $display(
        "FCOV CHECKER_GATED_SAMPLES fault=%0d threshold=%0d fsm=%0d clear=%0d retention=%0d health=%0d register=%0d",
        fault_checked_samples,
        threshold_checked_samples,
        fsm_checked_samples,
        clear_checked_samples,
        retention_checked_samples,
        health_checked_samples,
        register_checked_samples
      );
      $display("FCOV cg_fault_type=%0.2f", fault_type_cov.get_inst_coverage());
      $display("FCOV cg_threshold_boundaries=%0.2f", threshold_cov.get_inst_coverage());
      $display("FCOV cg_fsm_pwm=%0.2f", fsm_pwm_cov.get_inst_coverage());
      $display("FCOV cg_clear_recovery=%0.2f", clear_cov.get_inst_coverage());
      $display("FCOV cg_first_fault_retention=%0.2f", retention_cov.get_inst_coverage());
      $display("FCOV cg_sample_health=%0.2f", sample_health_cov.get_inst_coverage());
      $display("FCOV cg_register_behavior=%0.2f", register_cov.get_inst_coverage());
    end
  endtask
endmodule
