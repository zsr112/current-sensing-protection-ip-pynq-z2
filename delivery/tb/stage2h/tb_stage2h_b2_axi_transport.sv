`timescale 1ns/1ps

// This dual-wrapper fixture detects transport drift after both generations
// are reduced to one shared AW/W/B/AR/R mutable-state authority.
module tb_stage2h_b2_axi_transport;
    reg ACLK = 1'b0;
    always #5 ACLK = ~ACLK;

    reg ARESETN = 1'b0;
    reg [7:0] awaddr = 8'd0;
    reg awvalid = 1'b0;
    reg [31:0] wdata = 32'd0;
    reg [3:0] wstrb = 4'd0;
    reg wvalid = 1'b0;
    reg bready = 1'b0;
    reg [7:0] araddr = 8'd0;
    reg arvalid = 1'b0;
    reg rready = 1'b0;

    wire l_awready;
    wire l_wready;
    wire [1:0] l_bresp;
    wire l_bvalid;
    wire l_arready;
    wire [31:0] l_rdata;
    wire [1:0] l_rresp;
    wire l_rvalid;
    wire l_local_resetn;

    wire g_awready;
    wire g_wready;
    wire [1:0] g_bresp;
    wire g_bvalid;
    wire g_arready;
    wire [31:0] g_rdata;
    wire [1:0] g_rresp;
    wire g_rvalid;
    wire g_local_resetn;

    wire l_pwm_raw;
    wire l_pwm_out;
    wire l_fault_valid;
    wire l_fault_latched;
    wire [7:0] l_fault_code;
    wire [7:0] l_fault_code_latched;
    wire [3:0] l_fsm_state;
    wire [9:0] l_obs_clear;

    wire g_pwm_raw;
    wire g_pwm_out;
    wire g_fault_valid;
    wire g_fault_latched;
    wire [7:0] g_fault_code;
    wire [7:0] g_fault_code_latched;
    wire [3:0] g_fsm_state;
    wire [9:0] g_obs_clear;

    integer failures = 0;
    integer guard;
    integer parity_cycles = 0;

    protection_ip_top_axi_lite u_legacy (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .sample_valid(1'b0),
        .S_AXI_AWADDR(awaddr),
        .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(l_awready),
        .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(l_wready),
        .S_AXI_BRESP(l_bresp),
        .S_AXI_BVALID(l_bvalid),
        .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr),
        .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(l_arready),
        .S_AXI_RDATA(l_rdata),
        .S_AXI_RRESP(l_rresp),
        .S_AXI_RVALID(l_rvalid),
        .S_AXI_RREADY(rready),
        .i_ch1(12'd0),
        .i_ch2(12'd0),
        .obs_sticky_status(10'd0),
        .obs_source_accept_count(32'd0),
        .obs_destination_delivery_count(32'd0),
        .obs_backpressure_cycle_count(32'd0),
        .obs_source_protocol_violation_count(32'd0),
        .obs_source_drop_count(32'd0),
        .obs_fifo_overflow_attempt_count(32'd0),
        .obs_fifo_underflow_attempt_count(32'd0),
        .obs_duplicate_delivery_count(32'd0),
        .obs_sequence_gap_count(32'd0),
        .obs_reorder_or_stale_count(32'd0),
        .obs_aggregate_error_count(32'd0),
        .obs_last_source_sequence(32'd0),
        .obs_last_destination_sequence(32'd0),
        .obs_status_w1c_clear(l_obs_clear),
        .pwm_raw(l_pwm_raw),
        .pwm_out(l_pwm_out),
        .fault_valid(l_fault_valid),
        .fault_latched(l_fault_latched),
        .fault_code(l_fault_code),
        .fault_code_latched(l_fault_code_latched),
        .fsm_state(l_fsm_state),
        .local_resetn(l_local_resetn)
    );

    stage2g_protection_ip_axi_lite u_stage2g (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .sample_valid(1'b0),
        .sample_sequence(32'd0),
        .sample_source_integrity_clean(1'b1),
        .sample_destination_integrity_clean(1'b1),
        .S_AXI_AWADDR(awaddr),
        .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(g_awready),
        .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(g_wready),
        .S_AXI_BRESP(g_bresp),
        .S_AXI_BVALID(g_bvalid),
        .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr),
        .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(g_arready),
        .S_AXI_RDATA(g_rdata),
        .S_AXI_RRESP(g_rresp),
        .S_AXI_RVALID(g_rvalid),
        .S_AXI_RREADY(rready),
        .i_ch1(12'd0),
        .i_ch2(12'd0),
        .obs_sticky_status(10'd0),
        .obs_source_accept_count(32'd0),
        .obs_destination_delivery_count(32'd0),
        .obs_backpressure_cycle_count(32'd0),
        .obs_source_protocol_violation_count(32'd0),
        .obs_source_drop_count(32'd0),
        .obs_fifo_overflow_attempt_count(32'd0),
        .obs_fifo_underflow_attempt_count(32'd0),
        .obs_duplicate_delivery_count(32'd0),
        .obs_sequence_gap_count(32'd0),
        .obs_reorder_or_stale_count(32'd0),
        .obs_aggregate_error_count(32'd0),
        .obs_last_source_sequence(32'd0),
        .obs_last_destination_sequence(32'd0),
        .obs_status_w1c_clear(g_obs_clear),
        .pwm_raw(g_pwm_raw),
        .pwm_out(g_pwm_out),
        .fault_valid(g_fault_valid),
        .fault_latched(g_fault_latched),
        .fault_code(g_fault_code),
        .fault_code_latched(g_fault_code_latched),
        .fsm_state(g_fsm_state),
        .local_resetn(g_local_resetn)
    );

    task automatic fail;
        input [8*120-1:0] label;
        begin
            $display("B2 AXI FAILED: %0s", label);
            failures = failures + 1;
        end
    endtask

    task automatic check_equal;
        input [8*120-1:0] label;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                $display("B2 AXI %0s actual=%h expected=%h",
                         label, actual, expected);
                failures = failures + 1;
            end
        end
    endtask

    always @(posedge ACLK) begin
        #1;
        if ({l_awready, l_wready, l_bresp, l_bvalid,
             l_arready, l_rdata, l_rresp, l_rvalid, l_local_resetn} !==
            {g_awready, g_wready, g_bresp, g_bvalid,
             g_arready, g_rdata, g_rresp, g_rvalid, g_local_resetn})
            fail("legacy and Stage2G AXI outputs diverged");
        if ({u_legacy.u_axi_lite_register_transport.wr_en,
             u_legacy.u_axi_lite_register_transport.rd_en,
             u_legacy.u_axi_lite_register_transport.addr,
             u_legacy.u_axi_lite_register_transport.wdata,
             u_legacy.u_axi_lite_register_transport.wstrb} !==
            {u_stage2g.u_axi_lite_register_transport.wr_en,
             u_stage2g.u_axi_lite_register_transport.rd_en,
             u_stage2g.u_axi_lite_register_transport.addr,
             u_stage2g.u_axi_lite_register_transport.wdata,
             u_stage2g.u_axi_lite_register_transport.wstrb})
            fail("legacy and Stage2G register-side transport diverged");
        parity_cycles = parity_cycles + 1;
    end

    task automatic clear_master;
        begin
            awvalid = 1'b0;
            wvalid = 1'b0;
            wstrb = 4'd0;
            bready = 1'b0;
            arvalid = 1'b0;
            rready = 1'b0;
        end
    endtask

    task automatic reset_transport;
        begin
            @(negedge ACLK);
            ARESETN = 1'b0;
            clear_master();
            #1;
            if (l_bvalid || g_bvalid || l_rvalid || g_rvalid)
                fail("reset did not asynchronously clear response state");
            repeat (2) @(posedge ACLK);
            @(negedge ACLK);
            ARESETN = 1'b1;
            repeat (3) @(posedge ACLK);
            #1;
            if (!l_local_resetn || !g_local_resetn)
                fail("local reset release did not complete");
        end
    endtask

    task automatic finish_write_response;
        input integer hold_cycles;
        input [8*80-1:0] label;
        integer index;
        begin
            guard = 0;
            while (!(l_bvalid && g_bvalid)) begin
                @(posedge ACLK);
                #1;
                guard = guard + 1;
                if (guard > 30) begin
                    fail({label, " BVALID timeout"});
                    disable finish_write_response;
                end
            end
            check_equal({label, " legacy BRESP"}, {30'd0, l_bresp}, 0);
            check_equal({label, " Stage2G BRESP"}, {30'd0, g_bresp}, 0);
            for (index = 0; index < hold_cycles; index = index + 1) begin
                @(posedge ACLK);
                #1;
                if (!l_bvalid || !g_bvalid)
                    fail({label, " BVALID backpressure hold"});
            end
            @(negedge ACLK);
            bready = 1'b1;
            @(posedge ACLK);
            #1;
            if (l_bvalid || g_bvalid)
                fail({label, " BVALID did not retire"});
            @(negedge ACLK);
            bready = 1'b0;
        end
    endtask

    task automatic write_same_cycle;
        input [7:0] address;
        input [31:0] value;
        input [3:0] byte_enable;
        input integer hold_cycles;
        input [8*80-1:0] label;
        begin
            @(negedge ACLK);
            awaddr = address;
            wdata = value;
            wstrb = byte_enable;
            awvalid = 1'b1;
            wvalid = 1'b1;
            guard = 0;
            while (!(l_awready && g_awready && l_wready && g_wready)) begin
                @(negedge ACLK);
                guard = guard + 1;
                if (guard > 30) begin
                    fail({label, " AW/W ready timeout"});
                    disable write_same_cycle;
                end
            end
            @(posedge ACLK);
            #1;
            @(negedge ACLK);
            awvalid = 1'b0;
            wvalid = 1'b0;
            wstrb = 4'd0;
            finish_write_response(hold_cycles, label);
        end
    endtask

    task automatic write_aw_before_w;
        input [7:0] address;
        input [31:0] value;
        input [3:0] byte_enable;
        begin
            @(negedge ACLK);
            awaddr = address;
            awvalid = 1'b1;
            guard = 0;
            while (!(l_awready && g_awready)) begin
                @(negedge ACLK);
                guard = guard + 1;
                if (guard > 30) begin
                    fail("AW-before-W AW timeout");
                    disable write_aw_before_w;
                end
            end
            @(posedge ACLK);
            @(negedge ACLK);
            awvalid = 1'b0;
            wdata = value;
            wstrb = byte_enable;
            wvalid = 1'b1;
            guard = 0;
            while (!(l_wready && g_wready)) begin
                @(negedge ACLK);
                guard = guard + 1;
                if (guard > 30) begin
                    fail("AW-before-W W timeout");
                    disable write_aw_before_w;
                end
            end
            @(posedge ACLK);
            @(negedge ACLK);
            wvalid = 1'b0;
            wstrb = 4'd0;
            finish_write_response(0, "AW-before-W");
        end
    endtask

    task automatic write_w_before_aw;
        input [7:0] address;
        input [31:0] value;
        input [3:0] byte_enable;
        begin
            @(negedge ACLK);
            wdata = value;
            wstrb = byte_enable;
            wvalid = 1'b1;
            guard = 0;
            while (!(l_wready && g_wready)) begin
                @(negedge ACLK);
                guard = guard + 1;
                if (guard > 30) begin
                    fail("W-before-AW W timeout");
                    disable write_w_before_aw;
                end
            end
            @(posedge ACLK);
            @(negedge ACLK);
            wvalid = 1'b0;
            wstrb = 4'd0;
            awaddr = address;
            awvalid = 1'b1;
            guard = 0;
            while (!(l_awready && g_awready)) begin
                @(negedge ACLK);
                guard = guard + 1;
                if (guard > 30) begin
                    fail("W-before-AW AW timeout");
                    disable write_w_before_aw;
                end
            end
            @(posedge ACLK);
            @(negedge ACLK);
            awvalid = 1'b0;
            finish_write_response(0, "W-before-AW");
        end
    endtask

    task automatic read_address;
        input [7:0] address;
        output [31:0] value;
        input integer hold_cycles;
        input [8*80-1:0] label;
        integer index;
        reg [31:0] held_value;
        begin
            @(negedge ACLK);
            araddr = address;
            arvalid = 1'b1;
            rready = 1'b0;
            guard = 0;
            while (!(l_arready && g_arready)) begin
                @(negedge ACLK);
                guard = guard + 1;
                if (guard > 30) begin
                    fail({label, " ARREADY timeout"});
                    disable read_address;
                end
            end
            @(posedge ACLK);
            @(negedge ACLK);
            arvalid = 1'b0;
            guard = 0;
            while (!(l_rvalid && g_rvalid)) begin
                @(posedge ACLK);
                #1;
                guard = guard + 1;
                if (guard > 30) begin
                    fail({label, " RVALID timeout"});
                    disable read_address;
                end
            end
            if (l_rdata !== g_rdata)
                fail({label, " wrapper RDATA mismatch"});
            check_equal({label, " legacy RRESP"}, {30'd0, l_rresp}, 0);
            check_equal({label, " Stage2G RRESP"}, {30'd0, g_rresp}, 0);
            held_value = l_rdata;
            for (index = 0; index < hold_cycles; index = index + 1) begin
                @(posedge ACLK);
                #1;
                if (!l_rvalid || !g_rvalid || l_rdata !== held_value ||
                    g_rdata !== held_value)
                    fail({label, " RVALID/RDATA backpressure hold"});
            end
            value = held_value;
            @(negedge ACLK);
            rready = 1'b1;
            @(posedge ACLK);
            #1;
            if (l_rvalid || g_rvalid)
                fail({label, " RVALID did not retire"});
            @(negedge ACLK);
            rready = 1'b0;
        end
    endtask

    task automatic conservative_overlap;
        reg [31:0] read_value;
        begin
            @(negedge ACLK);
            awaddr = 8'h14;
            wdata = 32'h0000_0555;
            wstrb = 4'hf;
            awvalid = 1'b1;
            wvalid = 1'b1;
            araddr = 8'h14;
            arvalid = 1'b1;
            #1;
            if (!l_awready || !g_awready || !l_wready || !g_wready ||
                l_arready || g_arready)
                fail("write did not win conservative overlap");
            @(posedge ACLK);
            @(negedge ACLK);
            awvalid = 1'b0;
            wvalid = 1'b0;
            wstrb = 4'd0;
            guard = 0;
            while (!(l_bvalid && g_bvalid)) begin
                @(posedge ACLK);
                #1;
                if (l_arready || g_arready)
                    fail("read admitted before write response retired");
                guard = guard + 1;
                if (guard > 30) begin
                    fail("overlap BVALID timeout");
                    disable conservative_overlap;
                end
            end
            @(negedge ACLK);
            bready = 1'b1;
            @(posedge ACLK);
            @(negedge ACLK);
            bready = 1'b0;
            guard = 0;
            while (!(l_arready && g_arready)) begin
                @(negedge ACLK);
                guard = guard + 1;
                if (guard > 30) begin
                    fail("overlap ARREADY after write timeout");
                    disable conservative_overlap;
                end
            end
            @(posedge ACLK);
            @(negedge ACLK);
            arvalid = 1'b0;
            guard = 0;
            while (!(l_rvalid && g_rvalid)) begin
                @(posedge ACLK);
                #1;
                guard = guard + 1;
                if (guard > 30) begin
                    fail("overlap RVALID timeout");
                    disable conservative_overlap;
                end
            end
            read_value = l_rdata;
            check_equal("overlap write readback", read_value, 32'h0000_0555);
            @(negedge ACLK);
            rready = 1'b1;
            @(posedge ACLK);
            @(negedge ACLK);
            rready = 1'b0;
        end
    endtask

    task automatic reset_partial_aw;
        begin
            @(negedge ACLK);
            awaddr = 8'h14;
            awvalid = 1'b1;
            while (!(l_awready && g_awready)) @(negedge ACLK);
            @(posedge ACLK);
            @(negedge ACLK);
            awvalid = 1'b0;
            ARESETN = 1'b0;
            #1;
            if (l_bvalid || g_bvalid)
                fail("partial AW reset left response valid");
            repeat (2) @(posedge ACLK);
            @(negedge ACLK);
            ARESETN = 1'b1;
            repeat (3) @(posedge ACLK);
        end
    endtask

    task automatic reset_partial_w;
        begin
            @(negedge ACLK);
            wdata = 32'h0000_0666;
            wstrb = 4'hf;
            wvalid = 1'b1;
            while (!(l_wready && g_wready)) @(negedge ACLK);
            @(posedge ACLK);
            @(negedge ACLK);
            wvalid = 1'b0;
            wstrb = 4'd0;
            ARESETN = 1'b0;
            #1;
            if (l_bvalid || g_bvalid)
                fail("partial W reset left response valid");
            repeat (2) @(posedge ACLK);
            @(negedge ACLK);
            ARESETN = 1'b1;
            repeat (3) @(posedge ACLK);
        end
    endtask

    task automatic reset_outstanding_b;
        begin
            @(negedge ACLK);
            awaddr = 8'h14;
            wdata = 32'h0000_0777;
            wstrb = 4'hf;
            awvalid = 1'b1;
            wvalid = 1'b1;
            while (!(l_awready && g_awready && l_wready && g_wready))
                @(negedge ACLK);
            @(posedge ACLK);
            @(negedge ACLK);
            awvalid = 1'b0;
            wvalid = 1'b0;
            wstrb = 4'd0;
            while (!(l_bvalid && g_bvalid)) @(posedge ACLK);
            @(negedge ACLK);
            ARESETN = 1'b0;
            #1;
            if (l_bvalid || g_bvalid)
                fail("outstanding B reset did not clear BVALID");
            repeat (2) @(posedge ACLK);
            @(negedge ACLK);
            ARESETN = 1'b1;
            repeat (3) @(posedge ACLK);
        end
    endtask

    task automatic reset_partial_ar;
        begin
            @(negedge ACLK);
            araddr = 8'h14;
            arvalid = 1'b1;
            while (!(l_arready && g_arready)) @(negedge ACLK);
            @(posedge ACLK);
            @(negedge ACLK);
            arvalid = 1'b0;
            ARESETN = 1'b0;
            #1;
            if (l_rvalid || g_rvalid)
                fail("partial AR reset left response valid");
            repeat (2) @(posedge ACLK);
            @(negedge ACLK);
            ARESETN = 1'b1;
            repeat (3) @(posedge ACLK);
        end
    endtask

    task automatic reset_outstanding_r;
        begin
            @(negedge ACLK);
            araddr = 8'h14;
            arvalid = 1'b1;
            while (!(l_arready && g_arready)) @(negedge ACLK);
            @(posedge ACLK);
            @(negedge ACLK);
            arvalid = 1'b0;
            while (!(l_rvalid && g_rvalid)) @(posedge ACLK);
            @(negedge ACLK);
            ARESETN = 1'b0;
            #1;
            if (l_rvalid || g_rvalid)
                fail("outstanding R reset did not clear RVALID");
            repeat (2) @(posedge ACLK);
            @(negedge ACLK);
            ARESETN = 1'b1;
            repeat (3) @(posedge ACLK);
        end
    endtask

    reg [31:0] read_value;
    initial begin
        clear_master();
        reset_transport();

        read_address(8'h14, read_value, 0, "reset threshold");
        check_equal("reset threshold value", read_value, 32'd3000);

        write_same_cycle(8'h14, 32'h0000_0a11, 4'b0001, 0,
                         "same-cycle WSTRB");
        read_address(8'h14, read_value, 0, "same-cycle readback");
        check_equal("same-cycle WSTRB propagation", read_value,
                    32'h0000_0a11);

        write_same_cycle(8'h14, 32'h0000_0b22, 4'b0000, 0,
                         "zero WSTRB");
        read_address(8'h14, read_value, 0, "zero WSTRB readback");
        check_equal("zero WSTRB ignored", read_value, 32'h0000_0a11);

        write_aw_before_w(8'h14, 32'h0000_0999, 4'hf);
        read_address(8'h14, read_value, 0, "AW-before-W readback");
        check_equal("AW-before-W", read_value, 32'h0000_0999);

        write_w_before_aw(8'h14, 32'h0000_0888, 4'hf);
        read_address(8'h14, read_value, 0, "W-before-AW readback");
        check_equal("W-before-AW", read_value, 32'h0000_0888);

        write_same_cycle(8'h14, 32'h0000_0777, 4'hf, 3,
                         "B backpressure");
        read_address(8'h14, read_value, 3, "R backpressure");
        check_equal("R backpressure data", read_value, 32'h0000_0777);

        read_address(8'h64, read_value, 0, "undefined read");
        check_equal("undefined read value", read_value, 32'd0);
        write_same_cycle(8'h64, 32'hffff_ffff, 4'hf, 0,
                         "undefined write");
        read_address(8'h64, read_value, 0, "undefined write readback");
        check_equal("undefined write ignored", read_value, 32'd0);

        conservative_overlap();

        reset_partial_aw();
        reset_partial_w();
        reset_outstanding_b();
        reset_partial_ar();
        reset_outstanding_r();

        read_address(8'h14, read_value, 0, "post-reset default");
        check_equal("post-reset default threshold", read_value, 32'd3000);
        write_same_cycle(8'h14, 32'h0000_0666, 4'hf, 0,
                         "post-reset recovery write");
        read_address(8'h14, read_value, 0, "post-reset recovery read");
        check_equal("post-reset recovery", read_value, 32'h0000_0666);

        if (failures != 0) begin
            $display("STAGE2H_B2_AXI_TRANSPORT=FAIL_%0d", failures);
            $fatal(1);
        end
        $display("AXI_TRANSPORT_PARITY=PASS");
        $display("AXI_LEGACY_WRAPPER=PASS");
        $display("AXI_STAGE2G_WRAPPER=PASS");
        $display("AXI_PARITY_CYCLES=%0d", parity_cycles);
        $finish;
    end
endmodule
