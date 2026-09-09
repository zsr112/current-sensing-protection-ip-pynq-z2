`timescale 1ns/1ps
`include "protection_register_map.svh"

module tb_stage2e_axi_register_contract;
    reg ACLK = 0;
    always #5 ACLK = ~ACLK;
    reg ARESETN = 0;

    reg [7:0] awaddr = 0;
    reg awvalid = 0;
    wire awready;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    reg wvalid = 0;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 0;
    reg [7:0] araddr = 0;
    reg arvalid = 0;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready = 0;

    reg [9:0] sticky = 10'h2D5;
    wire [9:0] w1c_clear;
    reg [9:0] captured_clear = 0;
    integer checks = 0;

    protection_ip_top_axi_lite dut (
        .ACLK(ACLK), .ARESETN(ARESETN), .sample_valid(1'b0),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(awready), .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready), .S_AXI_BRESP(bresp),
        .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(arready), .S_AXI_RDATA(rdata),
        .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid),
        .S_AXI_RREADY(rready),
        .i_ch1(12'h123), .i_ch2(12'h456),
        .obs_sticky_status(sticky),
        .obs_source_accept_count(32'h0000_0011),
        .obs_destination_delivery_count(32'h0000_0022),
        .obs_backpressure_cycle_count(32'h0000_0033),
        .obs_source_protocol_violation_count(32'h0000_0044),
        .obs_source_drop_count(32'h0000_0055),
        .obs_fifo_overflow_attempt_count(32'h0000_0066),
        .obs_fifo_underflow_attempt_count(32'h0000_0077),
        .obs_duplicate_delivery_count(32'h0000_0088),
        .obs_sequence_gap_count(32'h0000_0099),
        .obs_reorder_or_stale_count(32'h0000_00AA),
        .obs_aggregate_error_count(32'h0000_00BB),
        .obs_last_source_sequence(32'h1234_5678),
        .obs_last_destination_sequence(32'h89AB_CDEF),
        .obs_status_w1c_clear(w1c_clear)
    );

    always @(posedge ACLK) begin
        if (!dut.local_rst_n)
            captured_clear <= 0;
        else
            captured_clear <= captured_clear | w1c_clear;
    end

    task automatic fail(input [8*100-1:0] message);
        begin
            $display("STAGE2E AXI CONTRACT FAILED: %0s", message);
            $fatal(1);
        end
    endtask

    task automatic check_condition(input [8*80-1:0] label, input condition);
        begin
            if (!condition)
                fail(label);
            checks = checks + 1;
        end
    endtask

    task automatic axi_read(input [7:0] address, output [31:0] value);
        integer guard;
        begin
            @(negedge ACLK);
            araddr = address;
            arvalid = 1;
            guard = 0;
            while (!arready) begin
                @(posedge ACLK);
                guard = guard + 1;
                if (guard > 20) fail("read address timeout");
            end
            @(posedge ACLK); #1;
            arvalid = 0;
            rready = 1;
            guard = 0;
            while (!rvalid) begin
                @(posedge ACLK); #1;
                guard = guard + 1;
                if (guard > 20) fail("read data timeout");
            end
            value = rdata;
            if (rresp !== 2'b00) fail("read response not OKAY");
            @(posedge ACLK); #1;
            rready = 0;
        end
    endtask

    task automatic axi_write(
        input [7:0] address,
        input [31:0] value,
        input [3:0] byte_enable
    );
        integer guard;
        begin
            @(negedge ACLK);
            awaddr = address;
            awvalid = 1;
            wdata = value;
            wstrb = byte_enable;
            wvalid = 1;
            guard = 0;
            while (!(awready && wready)) begin
                @(posedge ACLK);
                guard = guard + 1;
                if (guard > 20) fail("write handshake timeout");
            end
            @(posedge ACLK); #1;
            awvalid = 0;
            wvalid = 0;
            wstrb = 0;
            bready = 1;
            guard = 0;
            while (!bvalid) begin
                @(posedge ACLK); #1;
                guard = guard + 1;
                if (guard > 20) fail("write response timeout");
            end
            if (bresp !== 2'b00) fail("write response not OKAY");
            @(posedge ACLK); #1;
            bready = 0;
        end
    endtask

    task automatic check_read(input [7:0] address, input [31:0] expected);
        reg [31:0] value;
        begin
            axi_read(address, value);
            if (value !== expected) begin
                $display("AXI READ MISMATCH addr=%02x actual=%08x expected=%08x",
                         address, value, expected);
                fail("register read mismatch");
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        #2;
        repeat (3) @(posedge ACLK);
        ARESETN = 1;
        wait (dut.local_rst_n);
        repeat (2) @(posedge ACLK);

        check_read(`REG_OBS_CAPABILITY, 32'hE278_2001);
        check_read(`REG_OBS_STATUS_W1C, {22'd0, sticky});
        check_read(`REG_OBS_SOURCE_ACCEPT_COUNT, 32'h11);
        check_read(`REG_OBS_DESTINATION_DELIVERY_COUNT, 32'h22);
        check_read(`REG_OBS_BACKPRESSURE_CYCLE_COUNT, 32'h33);
        check_read(`REG_OBS_SOURCE_PROTOCOL_VIOLATION_COUNT, 32'h44);
        check_read(`REG_OBS_SOURCE_DROP_COUNT, 32'h55);
        check_read(`REG_OBS_FIFO_OVERFLOW_ATTEMPT_COUNT, 32'h66);
        check_read(`REG_OBS_FIFO_UNDERFLOW_ATTEMPT_COUNT, 32'h77);
        check_read(`REG_OBS_DUPLICATE_DELIVERY_COUNT, 32'h88);
        check_read(`REG_OBS_SEQUENCE_GAP_COUNT, 32'h99);
        check_read(`REG_OBS_REORDER_OR_STALE_COUNT, 32'hAA);
        check_read(`REG_OBS_AGGREGATE_ERROR_COUNT, 32'hBB);
        check_read(`REG_OBS_LAST_SOURCE_SEQUENCE, 32'h1234_5678);
        check_read(`REG_OBS_LAST_DESTINATION_SEQUENCE, 32'h89AB_CDEF);

        @(negedge ACLK);
        captured_clear = 0;
        axi_write(`REG_OBS_STATUS_W1C, 32'h0000_03FF, 4'b0000);
        repeat (2) @(posedge ACLK);
        check_condition("WSTRB zero generated W1C", captured_clear == 0);

        @(negedge ACLK);
        captured_clear = 0;
        axi_write(`REG_OBS_STATUS_W1C, 32'h0000_03FF, 4'b0001);
        repeat (2) @(posedge ACLK);
        check_condition("byte zero W1C mismatch", captured_clear == 10'h0FF);

        @(negedge ACLK);
        captured_clear = 0;
        axi_write(`REG_OBS_STATUS_W1C, 32'h0000_03FF, 4'b0010);
        repeat (2) @(posedge ACLK);
        check_condition("byte one W1C includes read-only ANY_ERROR",
                        captured_clear == 10'h100);

        axi_write(`REG_OBS_SOURCE_ACCEPT_COUNT, 32'hDEAD_BEEF, 4'hF);
        check_read(`REG_OBS_SOURCE_ACCEPT_COUNT, 32'h11);
        axi_write(`REG_OBS_CAPABILITY, 32'h0000_0000, 4'hF);
        check_read(`REG_OBS_CAPABILITY, 32'hE278_2001);
        check_read(8'h64, 32'h0000_0000);
        axi_write(8'h64, 32'hFFFF_FFFF, 4'hF);
        check_read(8'h64, 32'h0000_0000);

        check_condition("contract check count", checks == 22);
        $display("AXI_REGISTER_CONTRACT_TESTS=PASS_23_OF_23");
        $display("AXI_COUNTERS_READ_ONLY=PASS");
        $display("AXI_W1C_BYTE_STROBE=PASS");
        $display("AXI_UNDEFINED_ADDRESS_ZERO_OKAY=PASS");
        $finish;
    end

    initial begin
        #100000;
        fail("global timeout");
    end
endmodule
