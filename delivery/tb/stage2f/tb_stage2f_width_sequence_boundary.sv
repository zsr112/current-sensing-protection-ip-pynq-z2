`timescale 1ns/1ps
`include "generated/stage2f_adc_source_profile.svh"

module tb_stage2f_width_sequence_boundary;
    reg ACLK = 1'b0;
    reg ARESETN = 1'b0;
    reg adc_src_clk = 1'b0;

    reg valid_8 = 1'b0;
    reg [7:0] ch1_8 = 8'd0;
    reg [7:0] ch2_8 = 8'd0;
    wire ready_8;

    reg valid_12 = 1'b0;
    reg [11:0] ch1_12 = 12'd0;
    reg [11:0] ch2_12 = 12'd0;
    wire ready_12_16;
    wire ready_12_24;
    wire ready_12_32;

    reg valid_16 = 1'b0;
    reg [15:0] ch1_16 = 16'd0;
    reg [15:0] ch2_16 = 16'd0;
    wire ready_16;

    integer failures = 0;
    integer raw_8_deliveries = 0;
    integer raw_12_16_deliveries = 0;
    integer raw_12_24_deliveries = 0;
    integer raw_12_32_deliveries = 0;
    integer raw_16_deliveries = 0;

    always #5 ACLK = ~ACLK;
    always #7 adc_src_clk = ~adc_src_clk;

    task automatic fail_check;
        input [8*96-1:0] label;
        begin
            failures = failures + 1;
            $display("WIDTH SEQUENCE BOUNDARY FAIL: %0s", label);
        end
    endtask

    task automatic check_true;
        input [8*96-1:0] label;
        input condition;
        begin
            if (condition !== 1'b1)
                fail_check(label);
        end
    endtask

    protection_ip_top_async_adc_axi_lite #(
        .DATA_WIDTH(8), .OBS_SEQUENCE_WIDTH(16)
    ) dut_8_seq16 (
        .ACLK(ACLK), .ARESETN(ARESETN), .adc_src_clk(adc_src_clk),
        .adc_sample_valid(valid_8), .adc_sample_ready(ready_8),
        .adc_sample_ch1(ch1_8), .adc_sample_ch2(ch2_8),
        .S_AXI_AWADDR(8'd0), .S_AXI_AWVALID(1'b0), .S_AXI_AWREADY(),
        .S_AXI_WDATA(32'd0), .S_AXI_WSTRB(4'd0), .S_AXI_WVALID(1'b0),
        .S_AXI_WREADY(), .S_AXI_BRESP(), .S_AXI_BVALID(),
        .S_AXI_BREADY(1'b1), .S_AXI_ARADDR(8'd0),
        .S_AXI_ARVALID(1'b0), .S_AXI_ARREADY(), .S_AXI_RDATA(),
        .S_AXI_RRESP(), .S_AXI_RVALID(), .S_AXI_RREADY(1'b1),
        .pwm_raw(), .pwm_out(), .fault_valid(), .fault_latched(),
        .fault_code(), .fault_code_latched(), .fsm_state()
    );

    protection_ip_top_async_adc_axi_lite #(
        .DATA_WIDTH(12), .OBS_SEQUENCE_WIDTH(16)
    ) dut_12_seq16 (
        .ACLK(ACLK), .ARESETN(ARESETN), .adc_src_clk(adc_src_clk),
        .adc_sample_valid(valid_12), .adc_sample_ready(ready_12_16),
        .adc_sample_ch1(ch1_12), .adc_sample_ch2(ch2_12),
        .S_AXI_AWADDR(8'd0), .S_AXI_AWVALID(1'b0), .S_AXI_AWREADY(),
        .S_AXI_WDATA(32'd0), .S_AXI_WSTRB(4'd0), .S_AXI_WVALID(1'b0),
        .S_AXI_WREADY(), .S_AXI_BRESP(), .S_AXI_BVALID(),
        .S_AXI_BREADY(1'b1), .S_AXI_ARADDR(8'd0),
        .S_AXI_ARVALID(1'b0), .S_AXI_ARREADY(), .S_AXI_RDATA(),
        .S_AXI_RRESP(), .S_AXI_RVALID(), .S_AXI_RREADY(1'b1),
        .pwm_raw(), .pwm_out(), .fault_valid(), .fault_latched(),
        .fault_code(), .fault_code_latched(), .fsm_state()
    );

    protection_ip_top_async_adc_axi_lite #(
        .DATA_WIDTH(12), .OBS_SEQUENCE_WIDTH(24)
    ) dut_12_seq24 (
        .ACLK(ACLK), .ARESETN(ARESETN), .adc_src_clk(adc_src_clk),
        .adc_sample_valid(valid_12), .adc_sample_ready(ready_12_24),
        .adc_sample_ch1(ch1_12), .adc_sample_ch2(ch2_12),
        .S_AXI_AWADDR(8'd0), .S_AXI_AWVALID(1'b0), .S_AXI_AWREADY(),
        .S_AXI_WDATA(32'd0), .S_AXI_WSTRB(4'd0), .S_AXI_WVALID(1'b0),
        .S_AXI_WREADY(), .S_AXI_BRESP(), .S_AXI_BVALID(),
        .S_AXI_BREADY(1'b1), .S_AXI_ARADDR(8'd0),
        .S_AXI_ARVALID(1'b0), .S_AXI_ARREADY(), .S_AXI_RDATA(),
        .S_AXI_RRESP(), .S_AXI_RVALID(), .S_AXI_RREADY(1'b1),
        .pwm_raw(), .pwm_out(), .fault_valid(), .fault_latched(),
        .fault_code(), .fault_code_latched(), .fsm_state()
    );

    protection_ip_top_async_adc_axi_lite #(
        .DATA_WIDTH(12), .OBS_SEQUENCE_WIDTH(32)
    ) dut_12_seq32 (
        .ACLK(ACLK), .ARESETN(ARESETN), .adc_src_clk(adc_src_clk),
        .adc_sample_valid(valid_12), .adc_sample_ready(ready_12_32),
        .adc_sample_ch1(ch1_12), .adc_sample_ch2(ch2_12),
        .S_AXI_AWADDR(8'd0), .S_AXI_AWVALID(1'b0), .S_AXI_AWREADY(),
        .S_AXI_WDATA(32'd0), .S_AXI_WSTRB(4'd0), .S_AXI_WVALID(1'b0),
        .S_AXI_WREADY(), .S_AXI_BRESP(), .S_AXI_BVALID(),
        .S_AXI_BREADY(1'b1), .S_AXI_ARADDR(8'd0),
        .S_AXI_ARVALID(1'b0), .S_AXI_ARREADY(), .S_AXI_RDATA(),
        .S_AXI_RRESP(), .S_AXI_RVALID(), .S_AXI_RREADY(1'b1),
        .pwm_raw(), .pwm_out(), .fault_valid(), .fault_latched(),
        .fault_code(), .fault_code_latched(), .fsm_state()
    );

    protection_ip_top_async_adc_axi_lite #(
        .DATA_WIDTH(16), .OBS_SEQUENCE_WIDTH(32)
    ) dut_16_seq32 (
        .ACLK(ACLK), .ARESETN(ARESETN), .adc_src_clk(adc_src_clk),
        .adc_sample_valid(valid_16), .adc_sample_ready(ready_16),
        .adc_sample_ch1(ch1_16), .adc_sample_ch2(ch2_16),
        .S_AXI_AWADDR(8'd0), .S_AXI_AWVALID(1'b0), .S_AXI_AWREADY(),
        .S_AXI_WDATA(32'd0), .S_AXI_WSTRB(4'd0), .S_AXI_WVALID(1'b0),
        .S_AXI_WREADY(), .S_AXI_BRESP(), .S_AXI_BVALID(),
        .S_AXI_BREADY(1'b1), .S_AXI_ARADDR(8'd0),
        .S_AXI_ARVALID(1'b0), .S_AXI_ARREADY(), .S_AXI_RDATA(),
        .S_AXI_RRESP(), .S_AXI_RVALID(), .S_AXI_RREADY(1'b1),
        .pwm_raw(), .pwm_out(), .fault_valid(), .fault_latched(),
        .fault_code(), .fault_code_latched(), .fsm_state()
    );

    always @(posedge ACLK) begin
        #1;
        if (ARESETN) begin
            if (dut_8_seq16.dst_sample_valid) begin
                raw_8_deliveries = raw_8_deliveries + 1;
                check_true("8-bit raw channel 1",
                           dut_8_seq16.dst_sample_ch1 == 8'hA5);
                check_true("8-bit raw channel 2",
                           dut_8_seq16.dst_sample_ch2 == 8'h3C);
            end
            if (dut_12_seq16.dst_sample_valid)
                raw_12_16_deliveries = raw_12_16_deliveries + 1;
            if (dut_12_seq24.dst_sample_valid)
                raw_12_24_deliveries = raw_12_24_deliveries + 1;
            if (dut_12_seq32.dst_sample_valid)
                raw_12_32_deliveries = raw_12_32_deliveries + 1;
            if (dut_16_seq32.dst_sample_valid) begin
                raw_16_deliveries = raw_16_deliveries + 1;
                check_true("16-bit raw channel 1",
                           dut_16_seq32.dst_sample_ch1 == 16'hA55A);
                check_true("16-bit raw channel 2",
                           dut_16_seq32.dst_sample_ch2 == 16'h3CC3);
            end
            if (dut_8_seq16.normalized_sample_valid ||
                dut_8_seq16.normalized_sample_sequence != 0 ||
                dut_8_seq16.normalized_sample_ch1 != 0 ||
                dut_8_seq16.normalized_sample_ch2 != 0 ||
                dut_8_seq16.normalized_profile_configured ||
                dut_8_seq16.normalized_profile_valid ||
                dut_8_seq16.normalized_width_supported ||
                dut_8_seq16.normalized_profile_encoding_supported ||
                dut_8_seq16.normalized_profile_zero_code_valid ||
                dut_8_seq16.normalized_profile_polarity_valid)
                fail_check("8-bit unsupported normalization is not tied low");
            if (dut_16_seq32.normalized_sample_valid ||
                dut_16_seq32.normalized_sample_sequence != 0 ||
                dut_16_seq32.normalized_sample_ch1 != 0 ||
                dut_16_seq32.normalized_sample_ch2 != 0 ||
                dut_16_seq32.normalized_profile_configured ||
                dut_16_seq32.normalized_profile_valid ||
                dut_16_seq32.normalized_width_supported ||
                dut_16_seq32.normalized_profile_encoding_supported ||
                dut_16_seq32.normalized_profile_zero_code_valid ||
                dut_16_seq32.normalized_profile_polarity_valid)
                fail_check("16-bit unsupported normalization is not tied low");
        end
    end

    initial begin
        #1 ARESETN = 1'b0;
        #19 ARESETN = 1'b1;
        wait (ready_8 && ready_12_16 && ready_12_24 && ready_12_32 &&
              ready_16);

        check_true("12/16 width support",
                   dut_12_seq16.normalized_width_supported);
        check_true("12/24 width support",
                   dut_12_seq24.normalized_width_supported);
        check_true("12/32 width support",
                   dut_12_seq32.normalized_width_supported);
        check_true("12/16 configured profile",
                   dut_12_seq16.normalized_profile_configured &&
                   dut_12_seq16.normalized_profile_valid);
        check_true("12/24 configured profile",
                   dut_12_seq24.normalized_profile_configured &&
                   dut_12_seq24.normalized_profile_valid);
        check_true("12/32 configured profile",
                   dut_12_seq32.normalized_profile_configured &&
                   dut_12_seq32.normalized_profile_valid);

        @(negedge adc_src_clk);
        ch1_8 = 8'hA5;
        ch2_8 = 8'h3C;
        ch1_12 = 12'hA55;
        ch2_12 = 12'h3CC;
        ch1_16 = 16'hA55A;
        ch2_16 = 16'h3CC3;
        valid_8 = 1'b1;
        valid_12 = 1'b1;
        valid_16 = 1'b1;
        @(posedge adc_src_clk);
        @(negedge adc_src_clk);
        valid_8 = 1'b0;
        valid_12 = 1'b0;
        valid_16 = 1'b0;

        wait (raw_8_deliveries == 1 && raw_12_16_deliveries == 1 &&
              raw_12_24_deliveries == 1 && raw_12_32_deliveries == 1 &&
              raw_16_deliveries == 1);
        repeat (3) @(posedge ACLK);

        @(negedge ACLK);
        force dut_12_seq16.dst_sample_valid = 1'b1;
        force dut_12_seq16.dst_sample_sequence = 16'hA55A;
        force dut_12_seq16.dst_sample_ch1 = 12'h123;
        force dut_12_seq16.dst_sample_ch2 = 12'h456;
        force dut_12_seq24.dst_sample_valid = 1'b1;
        force dut_12_seq24.dst_sample_sequence = 24'hC3A55A;
        force dut_12_seq24.dst_sample_ch1 = 12'h123;
        force dut_12_seq24.dst_sample_ch2 = 12'h456;
        force dut_12_seq32.dst_sample_valid = 1'b1;
        force dut_12_seq32.dst_sample_sequence = 32'hC33CA55A;
        force dut_12_seq32.dst_sample_ch1 = 12'h123;
        force dut_12_seq32.dst_sample_ch2 = 12'h456;
        @(posedge ACLK);
        #1;
        check_true("16-bit normalized valid",
                   dut_12_seq16.normalized_sample_valid);
        check_true("24-bit normalized valid",
                   dut_12_seq24.normalized_sample_valid);
        check_true("32-bit normalized valid",
                   dut_12_seq32.normalized_sample_valid);
        check_true("16-bit sequence exact",
                   dut_12_seq16.normalized_sample_sequence == 16'hA55A);
        check_true("24-bit sequence exact",
                   dut_12_seq24.normalized_sample_sequence == 24'hC3A55A);
        check_true("32-bit sequence exact",
                   dut_12_seq32.normalized_sample_sequence == 32'hC33CA55A);
        check_true("channel 1 normalized",
                   $signed(dut_12_seq32.normalized_sample_ch1) == 13'sd291);
        check_true("channel 2 polarity normalized",
                   $signed(dut_12_seq32.normalized_sample_ch2) == -13'sd1110);
        @(negedge ACLK);
        release dut_12_seq16.dst_sample_valid;
        release dut_12_seq16.dst_sample_sequence;
        release dut_12_seq16.dst_sample_ch1;
        release dut_12_seq16.dst_sample_ch2;
        release dut_12_seq24.dst_sample_valid;
        release dut_12_seq24.dst_sample_sequence;
        release dut_12_seq24.dst_sample_ch1;
        release dut_12_seq24.dst_sample_ch2;
        release dut_12_seq32.dst_sample_valid;
        release dut_12_seq32.dst_sample_sequence;
        release dut_12_seq32.dst_sample_ch1;
        release dut_12_seq32.dst_sample_ch2;

        if (failures != 0)
            $fatal(1, "width/sequence failures=%0d", failures);
        $display("STAGE2F_BOUNDARY_PROFILE=%s",
                 `STAGE2F_PROFILE_IDENTITY);
        $display("DATA_WIDTH_8_RAW_PATH=PASS");
        $display("DATA_WIDTH_12_NORMALIZATION=PASS");
        $display("DATA_WIDTH_16_RAW_PATH=PASS");
        $display("OBS_SEQUENCE_WIDTH_16=PASS");
        $display("OBS_SEQUENCE_WIDTH_24=PASS");
        $display("OBS_SEQUENCE_WIDTH_32=PASS");
        $display("WIDTH_SEQUENCE_BOUNDARY=PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "width/sequence boundary timeout");
    end
endmodule
