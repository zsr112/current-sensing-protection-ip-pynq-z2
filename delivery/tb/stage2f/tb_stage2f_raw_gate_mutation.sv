`timescale 1ns/1ps

module tb_stage2f_raw_gate_mutation;
    reg ACLK = 1'b0;
    reg ARESETN = 1'b0;
    reg adc_src_clk = 1'b0;
    reg adc_sample_valid = 1'b0;
    reg [11:0] adc_sample_ch1 = 12'd4095;
    reg [11:0] adc_sample_ch2 = 12'd4095;
    reg [7:0] awaddr = 0, araddr = 0;
    reg awvalid = 0, wvalid = 0, arvalid = 0, bready = 1, rready = 1;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    wire adc_sample_ready;
    wire awready, wready, arready, bvalid, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    wire pwm_raw, pwm_out, fault_valid, fault_latched;
    wire [7:0] fault_code, fault_code_latched;
    wire [3:0] fsm_state;

    always #5 ACLK = ~ACLK;
    always #7 adc_src_clk = ~adc_src_clk;

    protection_ip_top_async_adc_axi_lite dut (
        .ACLK(ACLK), .ARESETN(ARESETN), .adc_src_clk(adc_src_clk),
        .adc_sample_valid(adc_sample_valid), .adc_sample_ready(adc_sample_ready),
        .adc_sample_ch1(adc_sample_ch1), .adc_sample_ch2(adc_sample_ch2),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready), .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid),
        .S_AXI_BREADY(bready), .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(arready), .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp),
        .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready), .pwm_raw(pwm_raw),
        .pwm_out(pwm_out), .fault_valid(fault_valid), .fault_latched(fault_latched),
        .fault_code(fault_code), .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state));

    integer i;
    integer accepted_count;

    // This observes the protection core's raw sample acceptance, not the
    // independent Stage 2E destination-delivery observer. A raw-path gate mutation must
    // therefore produce a connected semantic mismatch.
    always @(posedge ACLK) begin
        if (ARESETN && dut.u_destination_axi_lite.u_reg_controlled_top.u_core.accepted_sample_valid)
            accepted_count = accepted_count + 1;
    end

    initial begin
        accepted_count = 0;
        repeat (4) @(posedge ACLK);
        ARESETN = 1'b1;
        adc_sample_valid = 1'b1;
        for (i = 0; i < 30; i = i + 1)
            @(posedge adc_src_clk);
        adc_sample_valid = 1'b0;
        repeat (20) @(posedge ACLK);
        if (accepted_count == 0) begin
            $display("MUTATION_DETECTED=PASS_RAW_PATH_GATED");
            $finish(0);
        end
        $display("RAW_GATE_CONTROL=PASS accepted=%0d deliveries=%0d",
            accepted_count, dut.obs_destination_delivery_count);
        $finish(0);
    end
endmodule
