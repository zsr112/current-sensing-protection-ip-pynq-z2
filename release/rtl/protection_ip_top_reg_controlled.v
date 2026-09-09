module protection_ip_top_reg_controlled #(
    parameter DATA_WIDTH       = 12,
    parameter CNT_WIDTH        = 16,
    parameter ADDR_WIDTH       = 8,
    parameter REG_DATA_WIDTH   = 32,
    parameter HEALTH_CNT_WIDTH = 8,
    parameter OBS_SEQUENCE_WIDTH = 32
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sample_valid,

    input  wire wr_en,
    input  wire rd_en,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [REG_DATA_WIDTH-1:0] wdata,
    input  wire [(REG_DATA_WIDTH/8)-1:0] wstrb,
    output wire [REG_DATA_WIDTH-1:0] rdata,

    input  wire [DATA_WIDTH-1:0] i_ch1,
    input  wire [DATA_WIDTH-1:0] i_ch2,
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
    output wire [9:0] obs_status_w1c_clear,

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
        .ADDR_WIDTH(ADDR_WIDTH),
        .OBS_SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH),
        .EXPLICIT_ABI_1_1(0)
    ) u_reg_bank (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .addr(addr),
        .wr_data(wdata),
        .wr_strb(wstrb),
        .rd_data(rdata),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code_latched(fault_code_latched),
        .i_ch1_mon(i_ch1),
        .i_ch2_mon(i_ch2),
        .obs_sticky_status(obs_sticky_status),
        .obs_source_accept_count(obs_source_accept_count),
        .obs_destination_delivery_count(obs_destination_delivery_count),
        .obs_backpressure_cycle_count(obs_backpressure_cycle_count),
        .obs_source_protocol_violation_count(
            obs_source_protocol_violation_count),
        .obs_source_drop_count(obs_source_drop_count),
        .obs_fifo_overflow_attempt_count(obs_fifo_overflow_attempt_count),
        .obs_fifo_underflow_attempt_count(obs_fifo_underflow_attempt_count),
        .obs_duplicate_delivery_count(obs_duplicate_delivery_count),
        .obs_sequence_gap_count(obs_sequence_gap_count),
        .obs_reorder_or_stale_count(obs_reorder_or_stale_count),
        .obs_aggregate_error_count(obs_aggregate_error_count),
        .obs_last_source_sequence(obs_last_source_sequence),
        .obs_last_destination_sequence(obs_last_destination_sequence),
        .fsm_state(4'd0),
        .clear_pending(1'b0),
        .post_clear_recovery_pending(1'b0),
        .first_fault_bitmap(6'd0),
        .live_fault_bitmap(6'd0),
        .fault_seen_bitmap(6'd0),
        .fault_eval_valid(1'b0),
        .fault_eval_sequence({OBS_SEQUENCE_WIDTH{1'b0}}),
        .pwm_enable(pwm_enable),
        .clear_fault_pulse(clear_fault_pulse),
        .obs_status_w1c_clear(obs_status_w1c_clear),
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

// Internal metadata-aware destination used only by the packaged asynchronous
// wrapper.  The public protection_ip_top_reg_controlled port list above is
// intentionally unchanged for Stage 2B-2F and software compatibility.
module stage2g_protection_ip_reg_controlled #(
    parameter DATA_WIDTH       = 12,
    parameter CNT_WIDTH        = 16,
    parameter ADDR_WIDTH       = 8,
    parameter REG_DATA_WIDTH   = 32,
    parameter HEALTH_CNT_WIDTH = 8,
    parameter OBS_SEQUENCE_WIDTH = 32,
    parameter SEQUENCE_WIDTH = OBS_SEQUENCE_WIDTH
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sample_valid,
    input  wire [SEQUENCE_WIDTH-1:0] sample_sequence,
    input  wire sample_source_integrity_clean,
    input  wire sample_destination_integrity_clean,

    input  wire wr_en,
    input  wire rd_en,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [REG_DATA_WIDTH-1:0] wdata,
    input  wire [(REG_DATA_WIDTH/8)-1:0] wstrb,
    output wire [REG_DATA_WIDTH-1:0] rdata,

    input  wire [DATA_WIDTH-1:0] i_ch1,
    input  wire [DATA_WIDTH-1:0] i_ch2,
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
    output wire [9:0] obs_status_w1c_clear,

    output wire pwm_raw,
    output wire pwm_out,
    output wire fault_valid,
    output wire fault_latched,
    output wire [7:0] fault_code,
    output wire [7:0] fault_code_latched,
    output wire [3:0] fsm_state
);
    localparam [DATA_WIDTH-1:0] TH_OPEN_DEFAULT =
        {DATA_WIDTH{1'b0}};
    localparam [DATA_WIDTH-1:0] TH_SAT_DEFAULT =
        {DATA_WIDTH{1'b1}};
    localparam [DATA_WIDTH-1:0] TH_STUCK_DELTA_DEFAULT =
        {DATA_WIDTH{1'b0}};
    localparam [HEALTH_CNT_WIDTH-1:0] TH_PERSIST_DEFAULT =
        {HEALTH_CNT_WIDTH{1'b1}};

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

    // Stage 2H owns public visibility; these Stage 2G transaction and episode
    // fields remain internal debug/verification signals.
    (* MARK_DEBUG = "TRUE" *) wire fault_eval_valid;
    (* MARK_DEBUG = "TRUE" *) wire [SEQUENCE_WIDTH-1:0]
        fault_eval_sequence;
    (* MARK_DEBUG = "TRUE" *) wire [5:0] fault_eval_bitmap;
    (* MARK_DEBUG = "TRUE" *) wire [7:0] fault_eval_code;
    (* MARK_DEBUG = "TRUE" *) wire fault_eval_integrity_clean;
    (* MARK_DEBUG = "TRUE" *) wire clear_pending;
    (* MARK_DEBUG = "TRUE" *) wire [7:0] first_fault_code;
    (* MARK_DEBUG = "TRUE" *) wire [5:0] first_fault_bitmap;
    (* MARK_DEBUG = "TRUE" *) wire [5:0] live_fault_bitmap;
    (* MARK_DEBUG = "TRUE" *) wire [5:0] fault_seen_bitmap;
    wire first_fault_event;
    wire clear_resolution_event;
    wire clear_accept_event;
    wire [SEQUENCE_WIDTH-1:0] clear_resolution_sequence;
    (* MARK_DEBUG = "TRUE" *) wire post_clear_recovery_pending;

    generate
        if ((SEQUENCE_WIDTH < 16) || (SEQUENCE_WIDTH > 32)) begin :
            g_invalid_sequence_width
            STAGE2G_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_16_TO_32
                u_parameter_error();
        end
        if (SEQUENCE_WIDTH != OBS_SEQUENCE_WIDTH) begin :
            g_sequence_width_binding_mismatch
            STAGE2G_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_EQUAL_OBS_SEQUENCE_WIDTH
                u_parameter_error();
        end
    endgenerate

    protection_reg_bank #(
        .DATA_WIDTH(REG_DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .OBS_SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH),
        .EXPLICIT_ABI_1_1(1)
    ) u_reg_bank (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .addr(addr),
        .wr_data(wdata),
        .wr_strb(wstrb),
        .rd_data(rdata),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code_latched(fault_code_latched),
        .i_ch1_mon(i_ch1),
        .i_ch2_mon(i_ch2),
        .obs_sticky_status(obs_sticky_status),
        .obs_source_accept_count(obs_source_accept_count),
        .obs_destination_delivery_count(obs_destination_delivery_count),
        .obs_backpressure_cycle_count(obs_backpressure_cycle_count),
        .obs_source_protocol_violation_count(
            obs_source_protocol_violation_count),
        .obs_source_drop_count(obs_source_drop_count),
        .obs_fifo_overflow_attempt_count(
            obs_fifo_overflow_attempt_count),
        .obs_fifo_underflow_attempt_count(
            obs_fifo_underflow_attempt_count),
        .obs_duplicate_delivery_count(obs_duplicate_delivery_count),
        .obs_sequence_gap_count(obs_sequence_gap_count),
        .obs_reorder_or_stale_count(obs_reorder_or_stale_count),
        .obs_aggregate_error_count(obs_aggregate_error_count),
        .obs_last_source_sequence(obs_last_source_sequence),
        .obs_last_destination_sequence(obs_last_destination_sequence),
        .fsm_state(fsm_state),
        .clear_pending(clear_pending),
        .post_clear_recovery_pending(post_clear_recovery_pending),
        .first_fault_bitmap(first_fault_bitmap),
        .live_fault_bitmap(live_fault_bitmap),
        .fault_seen_bitmap(fault_seen_bitmap),
        .fault_eval_valid(fault_eval_valid),
        .fault_eval_sequence(fault_eval_sequence),
        .pwm_enable(pwm_enable),
        .clear_fault_pulse(clear_fault_pulse),
        .obs_status_w1c_clear(obs_status_w1c_clear),
        .th_oc_ch1(th_oc_ch1),
        .th_oc_ch2(th_oc_ch2),
        .th_diff(th_diff),
        .pwm_period(pwm_period),
        .pwm_duty(pwm_duty)
    );

    stage2g_protection_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(CNT_WIDTH),
        .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH),
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH)
    ) u_core (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_sequence(sample_sequence),
        .sample_source_integrity_clean(
            sample_source_integrity_clean),
        .sample_destination_integrity_clean(
            sample_destination_integrity_clean),
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
        .abs_diff(abs_diff),
        .fault_eval_valid(fault_eval_valid),
        .fault_eval_sequence(fault_eval_sequence),
        .fault_eval_bitmap(fault_eval_bitmap),
        .fault_eval_code(fault_eval_code),
        .fault_eval_integrity_clean(fault_eval_integrity_clean),
        .clear_pending(clear_pending),
        .first_fault_code(first_fault_code),
        .first_fault_bitmap(first_fault_bitmap),
        .live_fault_bitmap(live_fault_bitmap),
        .fault_seen_bitmap(fault_seen_bitmap),
        .first_fault_event(first_fault_event),
        .clear_resolution_event(clear_resolution_event),
        .clear_accept_event(clear_accept_event),
        .clear_resolution_sequence(clear_resolution_sequence),
        .post_clear_recovery_pending(post_clear_recovery_pending)
    );
endmodule
