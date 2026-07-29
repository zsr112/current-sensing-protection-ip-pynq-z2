module protection_core_top #(
    parameter DATA_WIDTH = 12,
    parameter CNT_WIDTH  = 16,
    parameter HEALTH_CNT_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sample_valid,
    input  wire pwm_enable,
    input  wire clear_fault,
    input  wire [DATA_WIDTH-1:0] i_ch1,
    input  wire [DATA_WIDTH-1:0] i_ch2,
    input  wire [DATA_WIDTH-1:0] th_oc_ch1,
    input  wire [DATA_WIDTH-1:0] th_oc_ch2,
    input  wire [DATA_WIDTH-1:0] th_diff,
    input  wire [DATA_WIDTH-1:0] th_open,
    input  wire [DATA_WIDTH-1:0] th_sat,
    input  wire [DATA_WIDTH-1:0] th_stuck_delta,
    input  wire [HEALTH_CNT_WIDTH-1:0] th_persist,
    input  wire [CNT_WIDTH-1:0] period,
    input  wire [CNT_WIDTH-1:0] duty,
    output wire pwm_raw,
    output wire pwm_out,
    output wire oc_any,
    output wire oc_both,
    output wire mismatch_flag,
    output wire sensor_open_flag,
    output wire sensor_sat_flag,
    output wire sensor_stuck_flag,
    output wire fault_valid,
    output wire fault_latched,
    output wire [7:0] fault_code,
    output wire [7:0] fault_code_latched,
    output wire [3:0] fsm_state,
    output wire [DATA_WIDTH-1:0] abs_diff
);
    wire oc_ch1, oc_ch2;
    wire pwm_disable;

    current_compare_dual #(.DATA_WIDTH(DATA_WIDTH)) u_cmp (
        .i_ch1(i_ch1), .i_ch2(i_ch2),
        .th_oc_ch1(th_oc_ch1), .th_oc_ch2(th_oc_ch2), .th_diff(th_diff),
        .oc_ch1(oc_ch1), .oc_ch2(oc_ch2), .oc_any(oc_any), .oc_both(oc_both),
        .mismatch_flag(mismatch_flag), .abs_diff(abs_diff)
    );

    sensor_health_monitor #(.DATA_WIDTH(DATA_WIDTH), .CNT_WIDTH(HEALTH_CNT_WIDTH)) u_health (
        .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid),
        .i_ch1(i_ch1), .i_ch2(i_ch2),
        .th_open(th_open), .th_sat(th_sat), .th_stuck_delta(th_stuck_delta), .th_persist(th_persist),
        .sensor_open_flag(sensor_open_flag), .sensor_sat_flag(sensor_sat_flag), .sensor_stuck_flag(sensor_stuck_flag)
    );

    fault_classifier u_classifier (
        .clk(clk), .rst_n(rst_n),
        .oc_any(oc_any), .oc_both(oc_both), .mismatch_flag(mismatch_flag),
        .sensor_open_flag(sensor_open_flag), .sensor_sat_flag(sensor_sat_flag), .sensor_stuck_flag(sensor_stuck_flag),
        .fault_valid(fault_valid), .fault_code(fault_code)
    );

    protection_fsm u_fsm (
        .clk(clk), .rst_n(rst_n),
        .fault_valid(fault_valid), .fault_code_in(fault_code), .clear_fault(clear_fault),
        .fault_latched(fault_latched), .pwm_disable(pwm_disable),
        .fault_code_latched(fault_code_latched), .state(fsm_state)
    );

    pwm_gen #(.CNT_WIDTH(CNT_WIDTH)) u_pwm (
        .clk(clk), .rst_n(rst_n), .enable(pwm_enable), .period(period), .duty(duty), .pwm_raw(pwm_raw)
    );

    pwm_gate u_gate (
        .pwm_raw(pwm_raw), .pwm_disable(pwm_disable), .pwm_out(pwm_out)
    );
endmodule
