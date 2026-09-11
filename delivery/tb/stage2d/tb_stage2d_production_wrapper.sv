`timescale 1ns/1ps

module tb_stage2d_production_wrapper;
    reg ACLK = 1'b0;
    reg adc_src_clk = 1'b0;
    reg ARESETN = 1'b1;
    reg adc_sample_valid = 1'b0;
    wire adc_sample_ready;
    reg [11:0] adc_sample_ch1 = 12'd0;
    reg [11:0] adc_sample_ch2 = 12'h5A5;

    wire pwm_raw;
    wire pwm_out;
    wire fault_valid;
    wire fault_latched;
    wire [7:0] fault_code;
    wire [7:0] fault_code_latched;
    wire [3:0] fsm_state;

    integer delivery_count = 0;
    integer accepted_count = 0;
    reg [23:0] last_delivery = 24'd0;

    always #5 ACLK = ~ACLK;
    always #7 adc_src_clk = ~adc_src_clk;

    protection_ip_top_async_adc_axi_lite dut (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .adc_src_clk(adc_src_clk),
        .adc_sample_valid(adc_sample_valid),
        .adc_sample_ready(adc_sample_ready),
        .adc_sample_ch1(adc_sample_ch1),
        .adc_sample_ch2(adc_sample_ch2),
        .S_AXI_AWADDR(8'd0),
        .S_AXI_AWVALID(1'b0),
        .S_AXI_AWREADY(),
        .S_AXI_WDATA(32'd0),
        .S_AXI_WSTRB(4'd0),
        .S_AXI_WVALID(1'b0),
        .S_AXI_WREADY(),
        .S_AXI_BRESP(),
        .S_AXI_BVALID(),
        .S_AXI_BREADY(1'b1),
        .S_AXI_ARADDR(8'd0),
        .S_AXI_ARVALID(1'b0),
        .S_AXI_ARREADY(),
        .S_AXI_RDATA(),
        .S_AXI_RRESP(),
        .S_AXI_RVALID(),
        .S_AXI_RREADY(1'b1),
        .pwm_raw(pwm_raw),
        .pwm_out(pwm_out),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code(fault_code),
        .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state)
    );

    task automatic check_true;
        input [8*120-1:0] label;
        input condition;
        begin
            if (condition !== 1'b1) begin
                $display("STAGE2D WRAPPER CHECK FAILED: %0s", label);
                $fatal(1);
                $finish;
            end
        end
    endtask

    task automatic send_one;
        input [11:0] channel_1;
        begin
            @(negedge adc_src_clk);
            adc_sample_ch1 = channel_1;
            adc_sample_ch2 = channel_1 ^ 12'h5A5;
            adc_sample_valid = 1'b1;
            @(posedge adc_src_clk);
            while (adc_sample_ready !== 1'b1)
                @(posedge adc_src_clk);
            @(negedge adc_src_clk);
            adc_sample_valid = 1'b0;
        end
    endtask

    always @(posedge ACLK) begin
        if (dut.dst_sample_valid) begin
            $display("WRAPPER_DELIVERY time=%0t payload=%h", $time,
                     {dut.dst_sample_ch1, dut.dst_sample_ch2});
            delivery_count = delivery_count + 1;
            last_delivery = {dut.dst_sample_ch1, dut.dst_sample_ch2};
            #1;
            check_true("internal AXI destination accepts delivery",
                       dut.u_destination_axi_lite.u_reg_controlled_top.u_core.accepted_sample_valid);
            check_true("internal AXI destination pair remains atomic",
                       dut.u_destination_axi_lite.u_reg_controlled_top.u_core.accepted_sample_pair ===
                       last_delivery);
        end
    end

    always @(posedge adc_src_clk) begin
        if (dut.adc_src_local_rst_n && adc_sample_valid && adc_sample_ready) begin
            accepted_count = accepted_count + 1;
            $display("WRAPPER_ACCEPT time=%0t payload=%h", $time,
                     {adc_sample_ch1, adc_sample_ch2});
        end
    end

    integer before_delivery;
    initial begin
        #1 ARESETN = 1'b0;
        #3;
        ARESETN = 1'b1;
        wait (adc_sample_ready === 1'b1);
        $display("WRAPPER_READY time=%0t", $time);
        check_true("empty wrapper payload is reset-clean",
                   {dut.dst_sample_ch1, dut.dst_sample_ch2} == 24'd0);
        send_one(12'h123);
        wait (delivery_count == 1);
        check_true("first wrapper transaction exactly once", accepted_count == 1);
        check_true("first wrapper payload exact", last_delivery == {12'h123, 12'h486});
        repeat (3) @(posedge ACLK);
        check_true("idle wrapper payload holds last delivered pair",
                   {dut.dst_sample_ch1, dut.dst_sample_ch2} == last_delivery);

        // Accept a word and reset it before the destination can observe the
        // synchronized write pointer. The stale RAM word must not replay.
        before_delivery = delivery_count;
        send_one(12'h321);
        #1 ARESETN = 1'b0;
        #3;
        check_true("both wrapper resets assert asynchronously",
                   !dut.adc_src_local_rst_n && !dut.adc_dst_local_rst_n);
        ARESETN = 1'b1;
        wait (adc_sample_ready === 1'b1);
        repeat (10) @(posedge ACLK);
        check_true("wrapper reset produces no stale delivery",
                   delivery_count == before_delivery);
        check_true("wrapper reset clears held destination payload",
                   {dut.dst_sample_ch1, dut.dst_sample_ch2} == 24'd0);

        send_one(12'h456);
        wait (delivery_count == before_delivery + 1);
        repeat (4) @(posedge ACLK);
        check_true("post-reset wrapper word delivered once",
                   delivery_count == before_delivery + 1);
        check_true("post-reset wrapper payload exact",
                   last_delivery == {12'h456, 12'h1F3});
        $display("PRODUCTION_WRAPPER_INTEGRATION=PASS");
        $display("PRODUCTION_WRAPPER_RESET_EPOCH=PASS");
        $display("ALL TESTS PASSED: tb_stage2d_production_wrapper");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Stage 2D production wrapper timeout");
    end
endmodule
