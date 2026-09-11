`include "generated/protection_register_map.vh"

module protection_reg_bank #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter OBS_SEQUENCE_WIDTH = 32,
    parameter EXPLICIT_ABI_1_1 = 0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire wr_en,
    input  wire rd_en,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire [(DATA_WIDTH/8)-1:0] wr_strb,
    output reg  [DATA_WIDTH-1:0] rd_data,

    input  wire fault_valid,
    input  wire fault_latched,
    input  wire [7:0] fault_code_latched,
    input  wire [11:0] i_ch1_mon,
    input  wire [11:0] i_ch2_mon,
    input  wire [9:0] obs_sticky_status,
    input  wire [31:0] obs_source_accept_count,
    input  wire [31:0] obs_destination_delivery_count,
    input  wire [31:0] obs_backpressure_cycle_count,
    input  wire [31:0] obs_source_protocol_violation_count,
    input  wire [31:0] obs_source_drop_count,
    input  wire [31:0] obs_fifo_overflow_attempt_count,
    input  wire [31:0] obs_fifo_underflow_attempt_count,
    input  wire [31:0] obs_duplicate_delivery_count,
    input  wire [31:0] obs_sequence_gap_count,
    input  wire [31:0] obs_reorder_or_stale_count,
    input  wire [31:0] obs_aggregate_error_count,
    input  wire [31:0] obs_last_source_sequence,
    input  wire [31:0] obs_last_destination_sequence,
    input  wire [3:0] fsm_state,
    input  wire clear_pending,
    input  wire post_clear_recovery_pending,
    input  wire [5:0] first_fault_bitmap,
    input  wire [5:0] live_fault_bitmap,
    input  wire [5:0] fault_seen_bitmap,
    input  wire fault_eval_valid,
    input  wire [OBS_SEQUENCE_WIDTH-1:0] fault_eval_sequence,
    output reg  pwm_enable,
    output reg  clear_fault_pulse,
    output reg  [9:0] obs_status_w1c_clear,
    output reg  [11:0] th_oc_ch1,
    output reg  [11:0] th_oc_ch2,
    output reg  [11:0] th_diff,
    output reg  [15:0] pwm_period,
    output reg  [15:0] pwm_duty
);
    localparam [31:0] OBS_CAPABILITY_VALUE =
        `PROTECTION_OBS_CAPABILITY_VALUE(OBS_SEQUENCE_WIDTH);
    localparam [31:0] ABI_1_1_CAPABILITIES_1_VALUE =
        `PROTECTION_CAPABILITIES_1_VALUE(OBS_SEQUENCE_WIDTH);

    reg [31:0] policy_evaluation_sequence;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_enable <= 1'b0;
            clear_fault_pulse <= 1'b0;
            obs_status_w1c_clear <= 10'd0;
            th_oc_ch1 <= `PROTECTION_TH_OC1_THRESHOLD_CH1_RESET;
            th_oc_ch2 <= `PROTECTION_TH_OC2_THRESHOLD_CH2_RESET;
            th_diff   <= `PROTECTION_TH_DIFF_THRESHOLD_RESET;
            pwm_period <= `PROTECTION_PWM_PERIOD_VALUE_RESET;
            pwm_duty   <= `PROTECTION_PWM_DUTY_VALUE_RESET;
            policy_evaluation_sequence <= 32'd0;
        end else begin
            clear_fault_pulse <= 1'b0;
            obs_status_w1c_clear <= 10'd0;
            if (fault_eval_valid)
                policy_evaluation_sequence <=
                    {{(32-OBS_SEQUENCE_WIDTH){1'b0}}, fault_eval_sequence};
            if (wr_en) begin
                case (addr)
                    `PROTECTION_REG_CTRL: begin
                        pwm_enable <= wr_data[`PROTECTION_CTRL_PWM_ENABLE_LSB];
                        clear_fault_pulse <=
                            wr_data[`PROTECTION_CTRL_CLEAR_FAULT_LSB];
                    end
                    `PROTECTION_REG_TH_OC1:
                        th_oc_ch1 <= wr_data[
                            `PROTECTION_TH_OC1_THRESHOLD_CH1_MSB:
                            `PROTECTION_TH_OC1_THRESHOLD_CH1_LSB];
                    `PROTECTION_REG_TH_OC2:
                        th_oc_ch2 <= wr_data[
                            `PROTECTION_TH_OC2_THRESHOLD_CH2_MSB:
                            `PROTECTION_TH_OC2_THRESHOLD_CH2_LSB];
                    `PROTECTION_REG_TH_DIFF:
                        th_diff <= wr_data[
                            `PROTECTION_TH_DIFF_THRESHOLD_MSB:
                            `PROTECTION_TH_DIFF_THRESHOLD_LSB];
                    `PROTECTION_REG_PWM_PERIOD:
                        pwm_period <= wr_data[
                            `PROTECTION_PWM_PERIOD_VALUE_MSB:
                            `PROTECTION_PWM_PERIOD_VALUE_LSB];
                    `PROTECTION_REG_PWM_DUTY:
                        pwm_duty <= wr_data[
                            `PROTECTION_PWM_DUTY_VALUE_MSB:
                            `PROTECTION_PWM_DUTY_VALUE_LSB];
                    `PROTECTION_REG_OBS_STATUS_W1C: begin
                        if (wr_strb[0])
                            obs_status_w1c_clear[7:0] <= wr_data[7:0];
                        if (wr_strb[1])
                            obs_status_w1c_clear[8] <= wr_data[8];
                    end
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        rd_data = 32'd0;
        case (addr)
            `PROTECTION_REG_CTRL:
                rd_data[`PROTECTION_CTRL_PWM_ENABLE_LSB] = pwm_enable;
            `PROTECTION_REG_STATUS: begin
                rd_data[`PROTECTION_STATUS_FAULT_VALID_LSB] = fault_valid;
                rd_data[`PROTECTION_STATUS_FAULT_LATCHED_LSB] = fault_latched;
            end
            `PROTECTION_REG_FAULT_CODE:
                rd_data[`PROTECTION_FAULT_CODE_LATCHED_MSB:
                        `PROTECTION_FAULT_CODE_LATCHED_LSB] = fault_code_latched;
            `PROTECTION_REG_I_CH1:
                rd_data[`PROTECTION_I_CH1_MON_MSB:
                        `PROTECTION_I_CH1_MON_LSB] = i_ch1_mon;
            `PROTECTION_REG_I_CH2:
                rd_data[`PROTECTION_I_CH2_MON_MSB:
                        `PROTECTION_I_CH2_MON_LSB] = i_ch2_mon;
            `PROTECTION_REG_TH_OC1:
                rd_data[`PROTECTION_TH_OC1_THRESHOLD_CH1_MSB:
                        `PROTECTION_TH_OC1_THRESHOLD_CH1_LSB] = th_oc_ch1;
            `PROTECTION_REG_TH_OC2:
                rd_data[`PROTECTION_TH_OC2_THRESHOLD_CH2_MSB:
                        `PROTECTION_TH_OC2_THRESHOLD_CH2_LSB] = th_oc_ch2;
            `PROTECTION_REG_TH_DIFF:
                rd_data[`PROTECTION_TH_DIFF_THRESHOLD_MSB:
                        `PROTECTION_TH_DIFF_THRESHOLD_LSB] = th_diff;
            `PROTECTION_REG_PWM_PERIOD:
                rd_data[`PROTECTION_PWM_PERIOD_VALUE_MSB:
                        `PROTECTION_PWM_PERIOD_VALUE_LSB] = pwm_period;
            `PROTECTION_REG_PWM_DUTY:
                rd_data[`PROTECTION_PWM_DUTY_VALUE_MSB:
                        `PROTECTION_PWM_DUTY_VALUE_LSB] = pwm_duty;
            `PROTECTION_REG_OBS_CAPABILITY: rd_data = OBS_CAPABILITY_VALUE;
            `PROTECTION_REG_OBS_STATUS_W1C:
                rd_data[`PROTECTION_OBS_ANY_ERROR_MSB:
                        `PROTECTION_OBS_BACKPRESSURE_SEEN_LSB] = obs_sticky_status;
            `PROTECTION_REG_OBS_SOURCE_ACCEPT_COUNT:
                rd_data = obs_source_accept_count;
            `PROTECTION_REG_OBS_DESTINATION_DELIVERY_COUNT:
                rd_data = obs_destination_delivery_count;
            `PROTECTION_REG_OBS_BACKPRESSURE_CYCLE_COUNT:
                rd_data = obs_backpressure_cycle_count;
            `PROTECTION_REG_OBS_SOURCE_PROTOCOL_VIOLATION_COUNT:
                rd_data = obs_source_protocol_violation_count;
            `PROTECTION_REG_OBS_SOURCE_DROP_COUNT:
                rd_data = obs_source_drop_count;
            `PROTECTION_REG_OBS_FIFO_OVERFLOW_ATTEMPT_COUNT:
                rd_data = obs_fifo_overflow_attempt_count;
            `PROTECTION_REG_OBS_FIFO_UNDERFLOW_ATTEMPT_COUNT:
                rd_data = obs_fifo_underflow_attempt_count;
            `PROTECTION_REG_OBS_DUPLICATE_DELIVERY_COUNT:
                rd_data = obs_duplicate_delivery_count;
            `PROTECTION_REG_OBS_SEQUENCE_GAP_COUNT:
                rd_data = obs_sequence_gap_count;
            `PROTECTION_REG_OBS_REORDER_OR_STALE_COUNT:
                rd_data = obs_reorder_or_stale_count;
            `PROTECTION_REG_OBS_AGGREGATE_ERROR_COUNT:
                rd_data = obs_aggregate_error_count;
            `PROTECTION_REG_OBS_LAST_SOURCE_SEQUENCE:
                rd_data = obs_last_source_sequence;
            `PROTECTION_REG_OBS_LAST_DESTINATION_SEQUENCE:
                rd_data = obs_last_destination_sequence;
            `PROTECTION_REG_REGISTER_MAP_VERSION:
                if (EXPLICIT_ABI_1_1)
                    rd_data = `PROTECTION_REGISTER_MAP_VERSION_VALUE;
            `PROTECTION_REG_CAPABILITIES_0:
                if (EXPLICIT_ABI_1_1)
                    rd_data = `PROTECTION_CAPABILITIES_0_ABI_1_1_VALUE;
            `PROTECTION_REG_CAPABILITIES_1:
                if (EXPLICIT_ABI_1_1)
                    rd_data = ABI_1_1_CAPABILITIES_1_VALUE;
            `PROTECTION_REG_POLICY_STATUS:
                if (EXPLICIT_ABI_1_1) begin
                    rd_data[`PROTECTION_POLICY_STATUS_ARMED_READY_LSB] =
                        (fsm_state == `PROTECTION_POLICY_STATE_ST_ARMED);
                    rd_data[
                        `PROTECTION_POLICY_STATUS_FAULT_LATCHED_STATE_LSB] =
                        (fsm_state ==
                         `PROTECTION_POLICY_STATE_ST_FAULT_LATCHED);
                    rd_data[`PROTECTION_POLICY_STATUS_RESET_WAIT_STATE_LSB] =
                        (fsm_state ==
                         `PROTECTION_POLICY_STATE_ST_RESET_WAIT);
                    rd_data[`PROTECTION_POLICY_STATUS_CLEAR_PENDING_LSB] =
                        clear_pending;
                    rd_data[
                        `PROTECTION_POLICY_STATUS_POST_CLEAR_RECOVERY_PENDING_LSB] =
                        post_clear_recovery_pending;
                end
            `PROTECTION_REG_FIRST_FAULT_BITMAP:
                if (EXPLICIT_ABI_1_1)
                    rd_data = {{26{1'b0}}, first_fault_bitmap};
            `PROTECTION_REG_LIVE_FAULT_BITMAP:
                if (EXPLICIT_ABI_1_1)
                    rd_data = {{26{1'b0}}, live_fault_bitmap};
            `PROTECTION_REG_FAULT_SEEN_BITMAP:
                if (EXPLICIT_ABI_1_1)
                    rd_data = {{26{1'b0}}, fault_seen_bitmap};
            `PROTECTION_REG_POLICY_EVALUATION_SEQUENCE:
                if (EXPLICIT_ABI_1_1)
                    rd_data = policy_evaluation_sequence;
            default: ;
        endcase
    end
endmodule
