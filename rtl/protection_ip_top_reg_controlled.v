module protection_ip_top_reg_controlled #(
    parameter DATA_WIDTH       = 12,
    parameter CNT_WIDTH        = 16,
    parameter ADDR_WIDTH       = 8,
    parameter REG_DATA_WIDTH   = 32,
    parameter HEALTH_CNT_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sample_valid,

    input  wire wr_en,
    input  wire rd_en,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [REG_DATA_WIDTH-1:0] wdata,
    output wire [REG_DATA_WIDTH-1:0] rdata,

    input  wire [DATA_WIDTH-1:0] i_ch1,
    input  wire [DATA_WIDTH-1:0] i_ch2,

    output wire pwm_raw,
    output wire pwm_out,
    output wire fault_valid,
    output wire fault_latched,
    output wire [7:0] fault_code,
    output wire [7:0] fault_code_latched,
    output wire [3:0] fsm_state
);
    localparam [DATA_WIDTH-1:0] TH_OPEN_DEFAULT        = {DATA_WIDTH{1'b0}};
    localparam [DATA_WIDTH-1:0] TH_SAT_DEFAULT         = {DATA_WIDTH{1'b1}};
    localparam [DATA_WIDTH-1:0] TH_STUCK_DELTA_DEFAULT = {DATA_WIDTH{1'b0}};
    localparam [HEALTH_CNT_WIDTH-1:0] TH_PERSIST_DEFAULT = {HEALTH_CNT_WIDTH{1'b1}};

    wire pwm_enable;
    wire clear_fault_pulse;
    wire [DATA_WIDTH-1:0] th_oc_ch1;
    wire [DATA_WIDTH-1:0] th_oc_ch2;
    wire [DATA_WIDTH-1:0] th_diff;
    wire [CNT_WIDTH-1:0] pwm_period;
    wire [CNT_WIDTH-1:0] pwm_duty;

    wire oc_any;
    wire oc_both;
    wire mismatch_flag;
    wire sensor_open_flag;
    wire sensor_sat_flag;
    wire sensor_stuck_flag;
    wire [DATA_WIDTH-1:0] abs_diff;

    protection_reg_bank #(
        .DATA_WIDTH(REG_DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_reg_bank (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .addr(addr),
        .wr_data(wdata),
        .rd_data(rdata),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code_latched(fault_code_latched),
        .i_ch1_mon(i_ch1),
        .i_ch2_mon(i_ch2),
        .pwm_enable(pwm_enable),
        .clear_fault_pulse(clear_fault_pulse),
        .th_oc_ch1(th_oc_ch1),
        .th_oc_ch2(th_oc_ch2),
        .th_diff(th_diff),
        .pwm_period(pwm_period),
        .pwm_duty(pwm_duty)
    );

    protection_core_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(CNT_WIDTH),
        .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH)
    ) u_core (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .pwm_enable(pwm_enable),
        .clear_fault(clear_fault_pulse),
        .i_ch1(i_ch1),
        .i_ch2(i_ch2),
        .th_oc_ch1(th_oc_ch1),
        .th_oc_ch2(th_oc_ch2),
        .th_diff(th_diff),
        .th_open(TH_OPEN_DEFAULT),
        .th_sat(TH_SAT_DEFAULT),
        .th_stuck_delta(TH_STUCK_DELTA_DEFAULT),
        .th_persist(TH_PERSIST_DEFAULT),
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
endmodule
