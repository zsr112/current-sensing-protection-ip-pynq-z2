module protection_ip_top_async_adc_axi_lite #(
    parameter DATA_WIDTH          = 12,
    parameter CNT_WIDTH           = 16,
    parameter AXI_ADDR_WIDTH      = 8,
    parameter AXI_DATA_WIDTH      = 32,
    parameter HEALTH_CNT_WIDTH    = 8,
    parameter ADC_FIFO_ADDR_WIDTH = 3,
    parameter OBS_SEQUENCE_WIDTH  = 32
)(
    input  wire ACLK,
    input  wire ARESETN,

    input  wire                  adc_src_clk,
    input  wire                  adc_sample_valid,
    output wire                  adc_sample_ready,
    input  wire [DATA_WIDTH-1:0] adc_sample_ch1,
    input  wire [DATA_WIDTH-1:0] adc_sample_ch2,

    input  wire [AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire S_AXI_AWVALID,
    output wire S_AXI_AWREADY,
    input  wire [AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire S_AXI_WVALID,
    output wire S_AXI_WREADY,
    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input  wire S_AXI_BREADY,

    input  wire [AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire S_AXI_ARVALID,
    output wire S_AXI_ARREADY,
    output wire [AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire S_AXI_RVALID,
    input  wire S_AXI_RREADY,

    output wire pwm_raw,
    output wire pwm_out,
    output wire fault_valid,
    output wire fault_latched,
    output wire [7:0] fault_code,
    output wire [7:0] fault_code_latched,
    output wire [3:0] fsm_state
);
    wire adc_src_local_rst_n;
    wire adc_dst_local_rst_n;
    wire dst_sample_valid;
    wire [DATA_WIDTH-1:0] dst_sample_ch1;
    wire [DATA_WIDTH-1:0] dst_sample_ch2;
    wire [OBS_SEQUENCE_WIDTH-1:0] dst_sample_sequence;
    wire fifo_underflow_attempt;

    wire [31:0] source_accept_count_gray;
    wire [31:0] backpressure_cycle_count_gray;
    wire [31:0] source_protocol_violation_count_gray;
    wire [31:0] source_drop_count_gray;
    wire [31:0] fifo_overflow_attempt_count_gray;
    wire [31:0] counter_saturation_event_count_gray;
    wire [OBS_SEQUENCE_WIDTH-1:0] last_source_sequence_gray;

    wire [31:0] synced_source_accept_count;
    wire [31:0] synced_backpressure_cycle_count;
    wire [31:0] synced_source_protocol_violation_count;
    wire [31:0] synced_source_drop_count;
    wire [31:0] synced_fifo_overflow_attempt_count;
    wire [31:0] synced_source_counter_saturation_count;
    wire [OBS_SEQUENCE_WIDTH-1:0] synced_last_source_sequence;

    wire [9:0] obs_sticky_status;
    wire [9:0] obs_status_w1c_clear;
    wire [31:0] obs_source_accept_count;
    wire [31:0] obs_destination_delivery_count;
    wire [31:0] obs_backpressure_cycle_count;
    wire [31:0] obs_source_protocol_violation_count;
    wire [31:0] obs_source_drop_count;
    wire [31:0] obs_fifo_overflow_attempt_count;
    wire [31:0] obs_fifo_underflow_attempt_count;
    wire [31:0] obs_duplicate_delivery_count;
    wire [31:0] obs_sequence_gap_count;
    wire [31:0] obs_reorder_or_stale_count;
    wire [31:0] obs_aggregate_error_count;
    wire [OBS_SEQUENCE_WIDTH-1:0] obs_last_source_sequence_internal;
    wire [OBS_SEQUENCE_WIDTH-1:0] obs_last_destination_sequence_internal;
    wire [31:0] obs_last_source_sequence;
    wire [31:0] obs_last_destination_sequence;

    generate
        if ((OBS_SEQUENCE_WIDTH < 16) || (OBS_SEQUENCE_WIDTH > 32)) begin :
            g_invalid_observability_sequence_width
            STAGE2E_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_16_TO_32
                u_parameter_error();
        end
    endgenerate

    // Assignment to the 32-bit software register naturally zero-extends
    // supported sequence widths below 32. Widths above 32 fail closed above.
    assign obs_last_source_sequence = obs_last_source_sequence_internal;
    assign obs_last_destination_sequence =
        obs_last_destination_sequence_internal;

    reset_release_sync u_adc_source_reset_release_sync (
        .clk(adc_src_clk),
        .async_rst_n(ARESETN),
        .sync_rst_n(adc_src_local_rst_n)
    );

    (* KEEP_HIERARCHY = "TRUE" *) adc_sample_cdc_bridge #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_ADDR_WIDTH(ADC_FIFO_ADDR_WIDTH),
        .SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH),
        .COUNTER_WIDTH(32)
    ) u_adc_sample_cdc_bridge (
        .src_clk(adc_src_clk),
        .src_rst_n(adc_src_local_rst_n),
        .src_sample_valid(adc_sample_valid),
        .src_sample_ready(adc_sample_ready),
        .src_sample_ch1(adc_sample_ch1),
        .src_sample_ch2(adc_sample_ch2),
        .dst_clk(ACLK),
        .dst_rst_n(adc_dst_local_rst_n),
        .dst_ready(1'b1),
        .dst_sample_valid(dst_sample_valid),
        .dst_sample_ch1(dst_sample_ch1),
        .dst_sample_ch2(dst_sample_ch2),
        .dst_sample_sequence(dst_sample_sequence),
        .fifo_underflow_attempt(fifo_underflow_attempt),
        .source_accept_count_gray(source_accept_count_gray),
        .backpressure_cycle_count_gray(backpressure_cycle_count_gray),
        .source_protocol_violation_count_gray(
            source_protocol_violation_count_gray),
        .source_drop_count_gray(source_drop_count_gray),
        .fifo_overflow_attempt_count_gray(
            fifo_overflow_attempt_count_gray),
        .counter_saturation_event_count_gray(
            counter_saturation_event_count_gray),
        .last_source_sequence_gray(last_source_sequence_gray)
    );

    (* KEEP_HIERARCHY = "TRUE" *) source_observability_cdc #(
        .SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH),
        .COUNTER_WIDTH(32)
    ) u_source_observability_cdc (
        .dst_clk(ACLK),
        .dst_rst_n(adc_dst_local_rst_n),
        .source_accept_count_gray(source_accept_count_gray),
        .backpressure_cycle_count_gray(backpressure_cycle_count_gray),
        .source_protocol_violation_count_gray(
            source_protocol_violation_count_gray),
        .source_drop_count_gray(source_drop_count_gray),
        .fifo_overflow_attempt_count_gray(
            fifo_overflow_attempt_count_gray),
        .counter_saturation_event_count_gray(
            counter_saturation_event_count_gray),
        .last_source_sequence_gray(last_source_sequence_gray),
        .source_accept_count(synced_source_accept_count),
        .backpressure_cycle_count(synced_backpressure_cycle_count),
        .source_protocol_violation_count(
            synced_source_protocol_violation_count),
        .source_drop_count(synced_source_drop_count),
        .fifo_overflow_attempt_count(
            synced_fifo_overflow_attempt_count),
        .counter_saturation_event_count(
            synced_source_counter_saturation_count),
        .last_source_sequence(synced_last_source_sequence)
    );

    transaction_destination_observer #(
        .SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH),
        .COUNTER_WIDTH(32)
    ) u_destination_observer (
        .clk(ACLK),
        .rst_n(adc_dst_local_rst_n),
        .delivery_valid(dst_sample_valid),
        .delivery_sequence(dst_sample_sequence),
        .fifo_underflow_attempt(fifo_underflow_attempt),
        .source_accept_count_in(synced_source_accept_count),
        .backpressure_cycle_count_in(synced_backpressure_cycle_count),
        .source_protocol_violation_count_in(
            synced_source_protocol_violation_count),
        .source_drop_count_in(synced_source_drop_count),
        .fifo_overflow_attempt_count_in(
            synced_fifo_overflow_attempt_count),
        .source_counter_saturation_count_in(
            synced_source_counter_saturation_count),
        .last_source_sequence_in(synced_last_source_sequence),
        .status_w1c_clear(obs_status_w1c_clear),
        .source_accept_count(obs_source_accept_count),
        .destination_delivery_count(obs_destination_delivery_count),
        .backpressure_cycle_count(obs_backpressure_cycle_count),
        .source_protocol_violation_count(
            obs_source_protocol_violation_count),
        .source_drop_count(obs_source_drop_count),
        .fifo_overflow_attempt_count(obs_fifo_overflow_attempt_count),
        .fifo_underflow_attempt_count(obs_fifo_underflow_attempt_count),
        .duplicate_delivery_count(obs_duplicate_delivery_count),
        .sequence_gap_count(obs_sequence_gap_count),
        .reorder_or_stale_count(obs_reorder_or_stale_count),
        .aggregate_error_count(obs_aggregate_error_count),
        .last_source_sequence(obs_last_source_sequence_internal),
        .last_destination_sequence(
            obs_last_destination_sequence_internal),
        .sticky_status(obs_sticky_status)
    );

    protection_ip_top_axi_lite #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(CNT_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH),
        .OBS_SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH)
    ) u_destination_axi_lite (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .sample_valid(dst_sample_valid),
        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),
        .i_ch1(dst_sample_ch1),
        .i_ch2(dst_sample_ch2),
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
        .obs_status_w1c_clear(obs_status_w1c_clear),
        .pwm_raw(pwm_raw),
        .pwm_out(pwm_out),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code(fault_code),
        .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state),
        .local_resetn(adc_dst_local_rst_n)
    );
endmodule
