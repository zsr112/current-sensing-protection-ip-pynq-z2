`timescale 1ns/1ps

// The runner places the frozen and implementation tops beside this bench
// under distinct module names.  Both instances receive identical clocks,
// reset, ADC traffic, and AXI threshold writes.
module tb_stage2f_raw_path_invariance;
    reg ACLK = 1'b0;
    reg ARESETN = 1'b0;
    reg adc_src_clk = 1'b0;
    reg adc_sample_valid = 1'b0;
    reg [11:0] adc_sample_ch1 = 12'd0;
    reg [11:0] adc_sample_ch2 = 12'd0;
    reg [7:0] awaddr = 8'd0;
    reg awvalid = 1'b0;
    reg [31:0] wdata = 32'd0;
    reg [3:0] wstrb = 4'd0;
    reg wvalid = 1'b0;
    reg bready = 1'b1;
    reg [7:0] araddr = 8'd0;
    reg arvalid = 1'b0;
    reg rready = 1'b1;

    wire ready_base, ready_impl;
    wire awready_base, awready_impl, wready_base, wready_impl;
    wire [1:0] bresp_base, bresp_impl, rresp_base, rresp_impl;
    wire bvalid_base, bvalid_impl, arready_base, arready_impl;
    wire [31:0] rdata_base, rdata_impl;
    wire rvalid_base, rvalid_impl;
    wire pwm_raw_base, pwm_raw_impl, pwm_out_base, pwm_out_impl;
    wire fault_valid_base, fault_valid_impl;
    wire fault_latched_base, fault_latched_impl;
    wire [7:0] fault_code_base, fault_code_impl;
    wire [7:0] fault_code_latched_base, fault_code_latched_impl;
    wire [3:0] fsm_state_base, fsm_state_impl;

    always #5 ACLK = ~ACLK;
    always #7 adc_src_clk = ~adc_src_clk;

    protection_ip_top_async_adc_axi_lite_base dut_base (
        .ACLK(ACLK), .ARESETN(ARESETN), .adc_src_clk(adc_src_clk),
        .adc_sample_valid(adc_sample_valid), .adc_sample_ready(ready_base),
        .adc_sample_ch1(adc_sample_ch1), .adc_sample_ch2(adc_sample_ch2),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(awready_base), .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready_base), .S_AXI_BRESP(bresp_base),
        .S_AXI_BVALID(bvalid_base), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(arready_base), .S_AXI_RDATA(rdata_base),
        .S_AXI_RRESP(rresp_base), .S_AXI_RVALID(rvalid_base),
        .S_AXI_RREADY(rready), .pwm_raw(pwm_raw_base),
        .pwm_out(pwm_out_base), .fault_valid(fault_valid_base),
        .fault_latched(fault_latched_base), .fault_code(fault_code_base),
        .fault_code_latched(fault_code_latched_base),
        .fsm_state(fsm_state_base));

    protection_ip_top_async_adc_axi_lite_impl dut_impl (
        .ACLK(ACLK), .ARESETN(ARESETN), .adc_src_clk(adc_src_clk),
        .adc_sample_valid(adc_sample_valid), .adc_sample_ready(ready_impl),
        .adc_sample_ch1(adc_sample_ch1), .adc_sample_ch2(adc_sample_ch2),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(awready_impl), .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready_impl), .S_AXI_BRESP(bresp_impl),
        .S_AXI_BVALID(bvalid_impl), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(arready_impl), .S_AXI_RDATA(rdata_impl),
        .S_AXI_RRESP(rresp_impl), .S_AXI_RVALID(rvalid_impl),
        .S_AXI_RREADY(rready), .pwm_raw(pwm_raw_impl),
        .pwm_out(pwm_out_impl), .fault_valid(fault_valid_impl),
        .fault_latched(fault_latched_impl), .fault_code(fault_code_impl),
        .fault_code_latched(fault_code_latched_impl),
        .fsm_state(fsm_state_impl));

    integer mismatch_count = 0;
    integer compare_cycles = 0;
    integer stimulus_index;
    reg mismatch_reported = 1'b0;

    task automatic compare_signal;
        input [8*96-1:0] signal_name;
        input signal_equal;
        begin
            if (!signal_equal) begin
                mismatch_count = mismatch_count + 1;
                if (!mismatch_reported) begin
                    $display("RAW_PATH_MISMATCH=%0s cycle=%0d", signal_name,
                        compare_cycles);
                    mismatch_reported = 1'b1;
                end
            end
        end
    endtask

    always @(posedge ACLK) begin
        #1;
        if (ARESETN) begin
            compare_cycles = compare_cycles + 1;
            compare_signal("adc_sample_ready", ready_base === ready_impl);
            compare_signal("raw_valid", dut_base.dst_sample_valid ===
                dut_impl.dst_sample_valid);
            compare_signal("raw_ch1", dut_base.dst_sample_ch1 ===
                dut_impl.dst_sample_ch1);
            compare_signal("raw_ch2", dut_base.dst_sample_ch2 ===
                dut_impl.dst_sample_ch2);
            compare_signal("raw_sequence", dut_base.dst_sample_sequence ===
                dut_impl.dst_sample_sequence);
            compare_signal("threshold_ch1", dut_base.u_destination_axi_lite.u_reg_controlled_top.th_oc_ch1 ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.th_oc_ch1);
            compare_signal("threshold_ch2", dut_base.u_destination_axi_lite.u_reg_controlled_top.th_oc_ch2 ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.th_oc_ch2);
            compare_signal("threshold_diff", dut_base.u_destination_axi_lite.u_reg_controlled_top.th_diff ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.th_diff);
            compare_signal("accepted_valid", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.accepted_sample_valid ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.accepted_sample_valid);
            compare_signal("accepted_pair", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.accepted_sample_pair ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.accepted_sample_pair);
            compare_signal("cmp_oc_ch1", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.oc_ch1 ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.oc_ch1);
            compare_signal("cmp_oc_ch2", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.oc_ch2 ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.oc_ch2);
            compare_signal("cmp_oc_any", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.oc_any ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.oc_any);
            compare_signal("cmp_oc_both", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.oc_both ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.oc_both);
            compare_signal("cmp_mismatch", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.mismatch_flag ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.mismatch_flag);
            compare_signal("cmp_abs_diff", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.abs_diff ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.u_cmp.abs_diff);
            compare_signal("health_open", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.sensor_open_flag ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.sensor_open_flag);
            compare_signal("health_sat", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.sensor_sat_flag ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.sensor_sat_flag);
            compare_signal("health_stuck", dut_base.u_destination_axi_lite.u_reg_controlled_top.u_core.sensor_stuck_flag ===
                dut_impl.u_destination_axi_lite.u_reg_controlled_top.u_core.sensor_stuck_flag);
            compare_signal("fault_valid", fault_valid_base === fault_valid_impl);
            compare_signal("fault_latched", fault_latched_base === fault_latched_impl);
            compare_signal("fault_code", fault_code_base === fault_code_impl);
            compare_signal("fault_code_latched", fault_code_latched_base === fault_code_latched_impl);
            compare_signal("fsm_state", fsm_state_base === fsm_state_impl);
            compare_signal("pwm_raw", pwm_raw_base === pwm_raw_impl);
            compare_signal("pwm_out", pwm_out_base === pwm_out_impl);
            compare_signal("obs_sticky", dut_base.obs_sticky_status === dut_impl.obs_sticky_status);
            compare_signal("obs_source_accept", dut_base.obs_source_accept_count === dut_impl.obs_source_accept_count);
            compare_signal("obs_delivery", dut_base.obs_destination_delivery_count === dut_impl.obs_destination_delivery_count);
            compare_signal("obs_backpressure", dut_base.obs_backpressure_cycle_count === dut_impl.obs_backpressure_cycle_count);
            compare_signal("obs_protocol", dut_base.obs_source_protocol_violation_count === dut_impl.obs_source_protocol_violation_count);
            compare_signal("obs_drop", dut_base.obs_source_drop_count === dut_impl.obs_source_drop_count);
            compare_signal("obs_overflow", dut_base.obs_fifo_overflow_attempt_count === dut_impl.obs_fifo_overflow_attempt_count);
            compare_signal("obs_underflow", dut_base.obs_fifo_underflow_attempt_count === dut_impl.obs_fifo_underflow_attempt_count);
            compare_signal("obs_duplicate", dut_base.obs_duplicate_delivery_count === dut_impl.obs_duplicate_delivery_count);
            compare_signal("obs_gap", dut_base.obs_sequence_gap_count === dut_impl.obs_sequence_gap_count);
            compare_signal("obs_reorder", dut_base.obs_reorder_or_stale_count === dut_impl.obs_reorder_or_stale_count);
            compare_signal("obs_aggregate", dut_base.obs_aggregate_error_count === dut_impl.obs_aggregate_error_count);
            compare_signal("obs_last_source", dut_base.obs_last_source_sequence_internal === dut_impl.obs_last_source_sequence_internal);
            compare_signal("obs_last_destination", dut_base.obs_last_destination_sequence_internal === dut_impl.obs_last_destination_sequence_internal);
        end
    end

    task automatic axi_write;
        input [7:0] address;
        input [31:0] data;
        begin
            @(negedge ACLK);
            awaddr = address;
            wdata = data;
            wstrb = 4'hf;
            awvalid = 1'b1;
            wvalid = 1'b1;
            while (!(awready_base && wready_base)) @(posedge ACLK);
            @(negedge ACLK);
            awvalid = 1'b0;
            wvalid = 1'b0;
            wstrb = 4'd0;
            repeat (4) @(posedge ACLK);
        end
    endtask

    initial begin
        repeat (5) @(posedge ACLK);
        @(negedge ACLK);
        ARESETN = 1'b1;
        repeat (5) @(posedge ACLK);
        axi_write(8'h14, 32'd1800);
        axi_write(8'h18, 32'd2300);
        axi_write(8'h1c, 32'd175);

        for (stimulus_index = 0; stimulus_index < 260; stimulus_index = stimulus_index + 1) begin
            @(negedge adc_src_clk);
            adc_sample_valid = (stimulus_index % 9) != 0;
            adc_sample_ch1 = (stimulus_index * 173 + 19) & 12'hfff;
            adc_sample_ch2 = (stimulus_index * 97 + 401) & 12'hfff;
        end
        @(negedge adc_src_clk);
        adc_sample_valid = 1'b0;
        repeat (160) @(posedge ACLK);

        if (mismatch_count == 0 && compare_cycles > 100)
            $display("RAW_PATH_INVARIANCE=PASS CYCLES=%0d", compare_cycles);
        else
            $display("RAW_PATH_INVARIANCE=FAIL MISMATCHES=%0d CYCLES=%0d",
                mismatch_count, compare_cycles);
        $finish(0);
    end
endmodule
