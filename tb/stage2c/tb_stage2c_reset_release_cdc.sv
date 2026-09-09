`timescale 1ns/1ps
`include "fault_defs.vh"

module tb_stage2c_reset_release_cdc;
    localparam DATA_WIDTH = 12;
    localparam HEALTH_CNT_WIDTH = 2;

    reg ACLK = 1'b0;
    reg ARESETN;
    reg sample_valid = 1'b0;
    reg [DATA_WIDTH-1:0] i_ch1 = {DATA_WIDTH{1'b0}};
    reg [DATA_WIDTH-1:0] i_ch2 = {DATA_WIDTH{1'b0}};

    reg [7:0] S_AXI_AWADDR = 8'd0;
    reg S_AXI_AWVALID = 1'b0;
    wire S_AXI_AWREADY;
    reg [31:0] S_AXI_WDATA = 32'd0;
    reg [3:0] S_AXI_WSTRB = 4'd0;
    reg S_AXI_WVALID = 1'b0;
    wire S_AXI_WREADY;
    wire [1:0] S_AXI_BRESP;
    wire S_AXI_BVALID;
    reg S_AXI_BREADY = 1'b0;
    reg [7:0] S_AXI_ARADDR = 8'd0;
    reg S_AXI_ARVALID = 1'b0;
    wire S_AXI_ARREADY;
    wire [31:0] S_AXI_RDATA;
    wire [1:0] S_AXI_RRESP;
    wire S_AXI_RVALID;
    reg S_AXI_RREADY = 1'b0;

    wire pwm_raw;
    wire pwm_out;
    wire fault_valid;
    wire fault_latched;
    wire [7:0] fault_code;
    wire [7:0] fault_code_latched;
    wire [3:0] fsm_state;

    wire local_rst_n;
    wire accepted_sample_valid =
        dut.u_reg_controlled_top.u_core.accepted_sample_valid;
    wire [(2*DATA_WIDTH)-1:0] accepted_sample_pair =
        dut.u_reg_controlled_top.u_core.accepted_sample_pair;
    wire sample_decision_valid =
        dut.u_reg_controlled_top.u_core.sample_decision_valid;
    wire health_state_any =
        dut.u_reg_controlled_top.u_core.sensor_open_flag |
        dut.u_reg_controlled_top.u_core.sensor_sat_flag |
        dut.u_reg_controlled_top.u_core.sensor_stuck_flag;
    wire health_event_any =
        dut.u_reg_controlled_top.u_core.sensor_open_event |
        dut.u_reg_controlled_top.u_core.sensor_sat_event |
        dut.u_reg_controlled_top.u_core.sensor_stuck_event;
    wire axi_ready_any = S_AXI_AWREADY | S_AXI_WREADY | S_AXI_ARREADY;

    always #5 ACLK = ~ACLK;

    protection_ip_top_axi_lite #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(16),
        .AXI_ADDR_WIDTH(8),
        .AXI_DATA_WIDTH(32),
        .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH)
    ) dut (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .sample_valid(sample_valid),
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
        .i_ch1(i_ch1),
        .i_ch2(i_ch2),
        .pwm_raw(pwm_raw),
        .pwm_out(pwm_out),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code(fault_code),
        .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state),
        .local_resetn(local_rst_n)
    );

    stage2c_reset_release_checker #(.DATA_WIDTH(DATA_WIDTH)) u_checker (
        .clk(ACLK),
        .async_rst_n(ARESETN),
        .local_rst_n(local_rst_n),
        .sample_valid(sample_valid),
        .sample_pair({i_ch1, i_ch2}),
        .accepted_sample_valid(accepted_sample_valid),
        .accepted_sample_pair(accepted_sample_pair),
        .sample_decision_valid(sample_decision_valid),
        .health_state_any(health_state_any),
        .health_event_any(health_event_any),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .pwm_raw(pwm_raw),
        .pwm_out(pwm_out),
        .fsm_state(fsm_state),
        .axi_ready_any(axi_ready_any),
        .axi_bvalid(S_AXI_BVALID),
        .axi_rvalid(S_AXI_RVALID),
        .axi_rdata(S_AXI_RDATA),
        .axi_aw_hold_valid(
            dut.u_axi_lite_register_transport.aw_hold_valid),
        .axi_w_hold_valid(
            dut.u_axi_lite_register_transport.w_hold_valid),
        .axi_reg_wr_en(dut.reg_wr_en),
        .axi_reg_rd_en(dut.reg_rd_en)
    );

    task automatic check_true(input string label, input logic condition);
        begin
            if (condition !== 1'b1) begin
                $display("STAGE2C DUT CHECK FAILED: %s", label);
                $fatal(1);
            end
        end
    endtask

    task automatic tick;
        begin
            @(posedge ACLK);
            #1;
        end
    endtask

    task automatic ticks(input integer count);
        integer index;
        begin
            for (index = 0; index < count; index = index + 1)
                tick();
        end
    endtask

    task automatic check_reset_safe(input string label);
        begin
            check_true({label, ": local reset low"}, local_rst_n === 1'b0);
            check_true({label, ": accepted state clear"},
                       (accepted_sample_valid === 1'b0) &&
                       (accepted_sample_pair === 24'd0));
            check_true({label, ": decision clear"},
                       sample_decision_valid === 1'b0);
            check_true({label, ": health clear"},
                       (health_state_any === 1'b0) &&
                       (health_event_any === 1'b0));
            check_true({label, ": fault clear"},
                       (fault_valid === 1'b0) &&
                       (fault_latched === 1'b0) &&
                       (fault_code_latched === `FAULT_NONE));
            check_true({label, ": output safe"},
                       (pwm_raw === 1'b0) && (pwm_out === 1'b0) &&
                       (fsm_state === 4'd0));
            check_true({label, ": AXI ready low"}, axi_ready_any === 1'b0);
            check_true({label, ": AXI response clear"},
                       (S_AXI_BVALID === 1'b0) &&
                       (S_AXI_RVALID === 1'b0) &&
                       (S_AXI_RDATA === 32'd0));
            check_true({label, ": AXI held request clear"},
                       (dut.u_axi_lite_register_transport.aw_hold_valid ===
                        1'b0) &&
                       (dut.u_axi_lite_register_transport.w_hold_valid ===
                        1'b0));
            check_true({label, ": AXI register strobes clear"},
                       (dut.reg_wr_en === 1'b0) &&
                       (dut.reg_rd_en === 1'b0));
        end
    endtask

    task automatic assert_reset_now;
        begin
            sample_valid = 1'b0;
            ARESETN = 1'b0;
            #1;
            check_reset_safe("async assertion");
        end
    endtask

    task automatic hold_reset_one_clock;
        begin
            tick();
            check_reset_safe("held reset");
        end
    endtask

    task automatic release_reset_two_stage;
        begin
            @(negedge ACLK);
            ARESETN = 1'b1;
            tick();
            check_true("release stage 1 remains reset", local_rst_n === 1'b0);
            tick();
            check_true("release stage 2 raises local reset", local_rst_n === 1'b1);
            check_true("release stages accept no sample",
                       accepted_sample_valid === 1'b0);
        end
    endtask

    task automatic reset_and_release;
        begin
            assert_reset_now();
            hold_reset_one_clock();
            release_reset_two_stage();
        end
    endtask

    task automatic accept_repeated(
        input integer count,
        input [DATA_WIDTH-1:0] ch1,
        input [DATA_WIDTH-1:0] ch2
    );
        integer index;
        begin
            @(negedge ACLK);
            sample_valid = 1'b1;
            i_ch1 = ch1;
            i_ch2 = ch2;
            for (index = 0; index < count; index = index + 1) begin
                tick();
                check_true("accepted valid follows current eligible edge",
                           accepted_sample_valid === 1'b1);
                check_true("accepted pair remains atomic",
                           accepted_sample_pair === {ch1, ch2});
                if (index != count - 1)
                    @(negedge ACLK);
            end
            @(negedge ACLK);
            sample_valid = 1'b0;
        end
    endtask

    task automatic accept_one(
        input [DATA_WIDTH-1:0] ch1,
        input [DATA_WIDTH-1:0] ch2
    );
        begin
            accept_repeated(1, ch1, ch2);
        end
    endtask

    task automatic axi_write(input [7:0] address, input [31:0] data);
        integer guard;
        begin
            @(negedge ACLK);
            S_AXI_AWADDR = address;
            S_AXI_AWVALID = 1'b1;
            S_AXI_WDATA = data;
            S_AXI_WSTRB = 4'hF;
            S_AXI_WVALID = 1'b1;
            guard = 0;
            while (!(S_AXI_AWREADY && S_AXI_WREADY)) begin
                tick();
                guard = guard + 1;
                if (guard > 20) begin
                    $display("STAGE2C DUT CHECK FAILED: AXI write request timeout");
                    $fatal(1);
                end
            end
            tick();
            S_AXI_AWVALID = 1'b0;
            S_AXI_WVALID = 1'b0;
            S_AXI_WSTRB = 4'd0;
            S_AXI_BREADY = 1'b1;
            guard = 0;
            while (!S_AXI_BVALID) begin
                tick();
                guard = guard + 1;
                if (guard > 20) begin
                    $display("STAGE2C DUT CHECK FAILED: AXI write response timeout");
                    $fatal(1);
                end
            end
            check_true("AXI write response OKAY", S_AXI_BRESP === 2'b00);
            tick();
            S_AXI_BREADY = 1'b0;
            S_AXI_AWADDR = 8'd0;
            S_AXI_WDATA = 32'd0;
        end
    endtask

    task automatic wait_pwm_high(input string label);
        integer guard;
        begin
            guard = 0;
            while (!((pwm_raw === 1'b1) && (pwm_out === 1'b1))) begin
                tick();
                guard = guard + 1;
                if (guard > 20) begin
                    $display("STAGE2C DUT CHECK FAILED: %s PWM high timeout", label);
                    $fatal(1);
                end
            end
        end
    endtask

    task automatic clear_axi_master;
        begin
            S_AXI_AWADDR = 8'd0;
            S_AXI_AWVALID = 1'b0;
            S_AXI_WDATA = 32'd0;
            S_AXI_WSTRB = 4'd0;
            S_AXI_WVALID = 1'b0;
            S_AXI_BREADY = 1'b0;
            S_AXI_ARADDR = 8'd0;
            S_AXI_ARVALID = 1'b0;
            S_AXI_RREADY = 1'b0;
        end
    endtask

    task automatic trigger_open_fault;
        begin
            accept_repeated(4, 12'd0, 12'd0);
            tick();
            check_true("open event created by fourth qualifying transaction",
                       dut.u_reg_controlled_top.u_core.sensor_open_event === 1'b1);
            tick();
            check_true("open event reached classifier", fault_valid === 1'b1);
            tick();
            check_true("open fault latched", fault_latched === 1'b1);
            check_true("open fault code", fault_code_latched === `FAULT_SENSOR_OPEN);
        end
    endtask

    task automatic phase_release_case(input integer delay_from_negedge_ns);
        begin
            sample_valid = 1'b0;
            @(negedge ACLK);
            #1 ARESETN = 1'b0;
            #1 check_reset_safe("phase-scan assertion");
            @(negedge ACLK);
            #(delay_from_negedge_ns) ARESETN = 1'b1;
            #0.1;
            check_true("phase-scan release does not change local reset asynchronously",
                       local_rst_n === 1'b0);
            tick();
            check_true("phase-scan first sampled edge remains reset",
                       local_rst_n === 1'b0);
            tick();
            check_true("phase-scan second sampled edge completes release",
                       local_rst_n === 1'b1);
            tick();
            check_true("phase-scan creates no transaction",
                       accepted_sample_valid === 1'b0);
        end
    endtask

    initial begin
        // Force a real high-to-low transition at time zero so every simulator
        // executes the asynchronous assertion path deterministically.
        ARESETN = 1'b1;
        #1 ARESETN = 1'b0;
        #1 check_reset_safe("power-on assertion");
        ticks(2);
        release_reset_two_stage();
        tick();
        check_true("power-on first functional edge idle",
                   accepted_sample_valid === 1'b0);
        $display("SC01=PASS");

        accept_one(12'd1000, 12'd1200);
        ticks(3);
        @(negedge ACLK);
        #2 assert_reset_now();
        $display("SC02=PASS");

        hold_reset_one_clock();
        release_reset_two_stage();
        accept_one(12'd3500, 12'd1000);
        check_true("SC03 transaction pending before reset",
                   accepted_sample_valid === 1'b1);
        assert_reset_now();
        hold_reset_one_clock();
        release_reset_two_stage();
        ticks(4);
        check_true("SC03 pending transaction not replayed",
                   (fault_valid === 1'b0) && (fault_latched === 1'b0));
        $display("SC03=PASS");

        reset_and_release();
        accept_repeated(2, 12'd0, 12'd0);
        tick();
        check_true("SC04 open persistence reached two",
                   dut.u_reg_controlled_top.u_core.u_health.open_cnt === 2'd2);
        assert_reset_now();
        check_true("SC04 persistence cleared asynchronously",
                   (dut.u_reg_controlled_top.u_core.u_health.open_cnt === 2'd0) &&
                   (dut.u_reg_controlled_top.u_core.u_health.sat_cnt === 2'd0) &&
                   (dut.u_reg_controlled_top.u_core.u_health.stuck_cnt === 2'd0));
        $display("SC04=PASS");

        hold_reset_one_clock();
        release_reset_two_stage();
        accept_one(12'd3500, 12'd1000);
        tick();
        tick();
        check_true("SC05 fault not latched early", fault_latched === 1'b0);
        tick();
        check_true("SC05 fault reached latch", fault_latched === 1'b1);
        assert_reset_now();
        check_true("SC05 latched fault cleared by reset",
                   (fault_latched === 1'b0) &&
                   (fault_code_latched === `FAULT_NONE));
        $display("SC05=PASS");

        hold_reset_one_clock();
        release_reset_two_stage();
        tick();
        check_true("SC06 valid-low release remains idle",
                   (accepted_sample_valid === 1'b0) &&
                   (fault_valid === 1'b0));
        $display("SC06=PASS");

        assert_reset_now();
        hold_reset_one_clock();
        @(negedge ACLK);
        ARESETN = 1'b1;
        sample_valid = 1'b1;
        i_ch1 = 12'd3500;
        i_ch2 = 12'd1000;
        tick();
        check_true("SC07 release-window pulse not accepted at stage 1",
                   accepted_sample_valid === 1'b0);
        @(negedge ACLK);
        sample_valid = 1'b0;
        tick();
        check_true("SC07 release-window pulse not accepted at stage 2",
                   accepted_sample_valid === 1'b0);
        tick();
        check_true("SC07 release-window pulse not replayed",
                   (accepted_sample_valid === 1'b0) &&
                   (fault_valid === 1'b0));
        $display("SC07=PASS");

        assert_reset_now();
        hold_reset_one_clock();
        @(negedge ACLK);
        ARESETN = 1'b1;
        sample_valid = 1'b1;
        i_ch1 = 12'd1000;
        i_ch2 = 12'd1200;
        tick();
        check_true("SC08 held valid not accepted at stage 1",
                   accepted_sample_valid === 1'b0);
        tick();
        check_true("SC08 held valid not accepted at stage 2",
                   accepted_sample_valid === 1'b0);
        tick();
        check_true("SC08 held valid accepted once on first functional edge",
                   (accepted_sample_valid === 1'b1) &&
                   (accepted_sample_pair === {12'd1000, 12'd1200}));
        @(negedge ACLK);
        sample_valid = 1'b0;
        tick();
        check_true("SC08 no duplicate after held valid drops",
                   accepted_sample_valid === 1'b0);
        $display("SC08=PASS");

        reset_and_release();
        accept_one(12'd1000, 12'd1200);
        ticks(4);
        check_true("SC09 immediate safe sample stays safe",
                   (fault_valid === 1'b0) && (fault_latched === 1'b0));
        $display("SC09=PASS");

        reset_and_release();
        accept_one(12'd3500, 12'd3500);
        check_true("SC10 N0 has no early latch", fault_latched === 1'b0);
        tick();
        check_true("SC10 N1 has no early latch", fault_latched === 1'b0);
        tick();
        check_true("SC10 N2 classifier valid but latch pending",
                   (fault_valid === 1'b1) && (fault_latched === 1'b0));
        tick();
        check_true("SC10 N3 overcurrent latch",
                   (fault_latched === 1'b1) &&
                   (fault_code_latched === `FAULT_OVERCURRENT));
        $display("SC10=PASS");

        reset_and_release();
        trigger_open_fault();
        $display("SC11=PASS");

        reset_and_release();
        axi_write(8'h14, 32'd4095);
        axi_write(8'h18, 32'd4095);
        accept_repeated(4, 12'd4095, 12'd4095);
        tick();
        check_true("SC12 saturation event created",
                   dut.u_reg_controlled_top.u_core.sensor_sat_event === 1'b1);
        tick();
        check_true("SC12 saturation reached classifier", fault_valid === 1'b1);
        tick();
        check_true("SC12 saturation fault latched",
                   (fault_latched === 1'b1) &&
                   (fault_code_latched === `FAULT_SENSOR_SATURATION));
        $display("SC12=PASS");

        reset_and_release();
        accept_repeated(5, 12'd1000, 12'd1200);
        tick();
        check_true("SC13 stuck event created",
                   dut.u_reg_controlled_top.u_core.sensor_stuck_event === 1'b1);
        tick();
        check_true("SC13 stuck reached classifier", fault_valid === 1'b1);
        tick();
        check_true("SC13 stuck fault latched",
                   (fault_latched === 1'b1) &&
                   (fault_code_latched === `FAULT_SENSOR_STUCK));
        $display("SC13=PASS");

        reset_and_release();
        trigger_open_fault();
        check_true("SC14 retained open flag existed before reset",
                   dut.u_reg_controlled_top.u_core.sensor_open_flag === 1'b1);
        assert_reset_now();
        check_true("SC14 retained health state removed",
                   (dut.u_reg_controlled_top.u_core.sensor_open_flag === 1'b0) &&
                   (dut.u_reg_controlled_top.u_core.u_health.open_cnt === 2'd0));
        hold_reset_one_clock();
        release_reset_two_stage();
        accept_one(12'd1000, 12'd1200);
        ticks(4);
        check_true("SC14 safe first pair does not replay retained state",
                   (fault_valid === 1'b0) && (fault_latched === 1'b0));
        $display("SC14=PASS");

        reset_and_release();
        accept_one(12'd3500, 12'd1000);
        tick();
        check_true("SC15 comparator decision pending",
                   (sample_decision_valid === 1'b1) &&
                   (dut.u_reg_controlled_top.u_core.decision_oc_any === 1'b1));
        assert_reset_now();
        hold_reset_one_clock();
        release_reset_two_stage();
        ticks(4);
        check_true("SC15 pending decision not replayed",
                   (fault_valid === 1'b0) && (fault_latched === 1'b0));
        $display("SC15=PASS");

        reset_and_release();
        accept_one(12'd3500, 12'd1000);
        check_true("SC16 accepted transaction pending",
                   accepted_sample_valid === 1'b1);
        assert_reset_now();
        check_true("SC16 pending accepted state cleared",
                   (accepted_sample_valid === 1'b0) &&
                   (accepted_sample_pair === 24'd0));
        hold_reset_one_clock();
        release_reset_two_stage();
        ticks(4);
        check_true("SC16 pending accepted transaction not replayed",
                   (fault_valid === 1'b0) && (fault_latched === 1'b0));
        $display("SC16=PASS");

        assert_reset_now();
        hold_reset_one_clock();
        @(negedge ACLK);
        ARESETN = 1'b1;
        tick();
        check_true("SC17 first pulse reached only release stage 1",
                   local_rst_n === 1'b0);
        #2 ARESETN = 1'b0;
        #1 check_reset_safe("SC17 second assertion restarts release");
        hold_reset_one_clock();
        release_reset_two_stage();
        tick();
        check_true("SC17 second pulse completes cleanly",
                   accepted_sample_valid === 1'b0);
        $display("SC17=PASS");

        @(negedge ACLK);
        #1 ARESETN = 1'b0;
        #1 check_reset_safe("SC18 two-nanosecond pulse assertion");
        #1 ARESETN = 1'b1;
        tick();
        check_true("SC18 short pulse release stage 1", local_rst_n === 1'b0);
        tick();
        check_true("SC18 short pulse release stage 2", local_rst_n === 1'b1);
        tick();
        check_true("SC18 short pulse creates no transaction",
                   accepted_sample_valid === 1'b0);
        $display("SC18=PASS");

        phase_release_case(1);
        phase_release_case(4);
        phase_release_case(6);
        phase_release_case(9);
        $display("SC19=PASS");

        // Assert raw reset between edges while a short-period PWM is actively
        // high. Reset must make both PWM nodes safe immediately, suppress any
        // stale pulse throughout synchronized release, and clear enable state.
        reset_and_release();
        axi_write(8'h20, 32'd4);
        axi_write(8'h24, 32'd3);
        axi_write(8'h00, 32'd1);
        wait_pwm_high("SC20 pre-reset");
        check_true("SC20 PWM enable established",
                   dut.u_reg_controlled_top.u_reg_bank.pwm_enable === 1'b1);
        #2 assert_reset_now();
        check_true("SC20 active PWM reset safe",
                   (pwm_raw === 1'b0) && (pwm_out === 1'b0));
        hold_reset_one_clock();
        release_reset_two_stage();
        check_true("SC20 PWM enable remains reset after release",
                   dut.u_reg_controlled_top.u_reg_bank.pwm_enable === 1'b0);
        ticks(8);
        check_true("SC20 no stale PWM pulse after release",
                   (pwm_raw === 1'b0) && (pwm_out === 1'b0));
        axi_write(8'h00, 32'd1);
        wait_pwm_high("SC20 explicit re-enable");
        $display("SC20=PASS");

        // AW-only state must clear asynchronously and must not create a stale
        // write response after synchronized release.
        reset_and_release();
        @(negedge ACLK);
        S_AXI_AWADDR = 8'h20;
        S_AXI_AWVALID = 1'b1;
        tick();
        check_true("SC21 AW-only request held",
                   (dut.u_axi_lite_register_transport.aw_hold_valid ===
                    1'b1) &&
                   (dut.u_axi_lite_register_transport.w_hold_valid ===
                    1'b0));
        S_AXI_AWVALID = 1'b0;
        #2 assert_reset_now();
        hold_reset_one_clock();
        release_reset_two_stage();
        ticks(2);
        check_true("SC21 no stale write response",
                   (S_AXI_BVALID === 1'b0) &&
                   (dut.reg_wr_en === 1'b0));
        clear_axi_master();
        $display("SC21=PASS");

        // W-only state follows the same fail-safe reset contract.
        reset_and_release();
        @(negedge ACLK);
        S_AXI_WDATA = 32'd7;
        S_AXI_WSTRB = 4'hF;
        S_AXI_WVALID = 1'b1;
        tick();
        check_true("SC22 W-only request held",
                   (dut.u_axi_lite_register_transport.aw_hold_valid ===
                    1'b0) &&
                   (dut.u_axi_lite_register_transport.w_hold_valid ===
                    1'b1));
        S_AXI_WVALID = 1'b0;
        S_AXI_WSTRB = 4'd0;
        #2 assert_reset_now();
        hold_reset_one_clock();
        release_reset_two_stage();
        ticks(2);
        check_true("SC22 no stale write response",
                   (S_AXI_BVALID === 1'b0) &&
                   (dut.reg_wr_en === 1'b0));
        clear_axi_master();
        $display("SC22=PASS");

        // Hold BVALID by withholding BREADY, then reset the pending response.
        reset_and_release();
        @(negedge ACLK);
        S_AXI_AWADDR = 8'h20;
        S_AXI_AWVALID = 1'b1;
        S_AXI_WDATA = 32'd9;
        S_AXI_WSTRB = 4'hF;
        S_AXI_WVALID = 1'b1;
        tick();
        check_true("SC23 write apply pulse pending",
                   dut.reg_wr_en === 1'b1);
        S_AXI_AWVALID = 1'b0;
        S_AXI_WVALID = 1'b0;
        S_AXI_WSTRB = 4'd0;
        tick();
        check_true("SC23 BVALID held while BREADY low",
                   (S_AXI_BVALID === 1'b1) &&
                   (S_AXI_BREADY === 1'b0));
        #2 assert_reset_now();
        hold_reset_one_clock();
        release_reset_two_stage();
        ticks(2);
        check_true("SC23 pending response did not replay",
                   S_AXI_BVALID === 1'b0);
        clear_axi_master();
        $display("SC23=PASS");

        // Reset after AR capture but before RVALID/RDATA publication.
        reset_and_release();
        @(negedge ACLK);
        S_AXI_ARADDR = 8'h20;
        S_AXI_ARVALID = 1'b1;
        tick();
        check_true("SC24 read capture pending",
                   (dut.reg_rd_en === 1'b1) &&
                   (dut.u_axi_lite_register_transport.rd_state === 2'd1) &&
                   (S_AXI_RVALID === 1'b0));
        S_AXI_ARVALID = 1'b0;
        #2 assert_reset_now();
        hold_reset_one_clock();
        release_reset_two_stage();
        ticks(2);
        check_true("SC24 captured read did not replay",
                   (S_AXI_RVALID === 1'b0) &&
                   (S_AXI_RDATA === 32'd0) &&
                   (dut.reg_rd_en === 1'b0));
        clear_axi_master();
        $display("SC24=PASS");

        // Hold RVALID by withholding RREADY, then reset response and data.
        reset_and_release();
        @(negedge ACLK);
        S_AXI_ARADDR = 8'h20;
        S_AXI_ARVALID = 1'b1;
        tick();
        S_AXI_ARVALID = 1'b0;
        tick();
        check_true("SC25 RVALID held while RREADY low",
                   (S_AXI_RVALID === 1'b1) &&
                   (S_AXI_RREADY === 1'b0) &&
                   (S_AXI_RDATA === 32'd1000));
        #2 assert_reset_now();
        hold_reset_one_clock();
        release_reset_two_stage();
        ticks(2);
        check_true("SC25 read response and data did not replay",
                   (S_AXI_RVALID === 1'b0) &&
                   (S_AXI_RDATA === 32'd0));
        clear_axi_master();
        $display("SC25=PASS");

        // A complete write request held through release is blocked while the
        // local reset is low, then accepted once as one fresh transaction.
        assert_reset_now();
        hold_reset_one_clock();
        S_AXI_AWADDR = 8'h20;
        S_AXI_AWVALID = 1'b1;
        S_AXI_WDATA = 32'd7;
        S_AXI_WSTRB = 4'hF;
        S_AXI_WVALID = 1'b1;
        release_reset_two_stage();
        check_true("SC26 no stale response at local release",
                   (S_AXI_BVALID === 1'b0) &&
                   (dut.u_axi_lite_register_transport.aw_hold_valid ===
                    1'b0) &&
                   (dut.u_axi_lite_register_transport.w_hold_valid ===
                    1'b0) &&
                   (dut.reg_wr_en === 1'b0));
        tick();
        check_true("SC26 held write accepted once",
                   dut.reg_wr_en === 1'b1);
        S_AXI_AWVALID = 1'b0;
        S_AXI_WVALID = 1'b0;
        S_AXI_WSTRB = 4'd0;
        tick();
        check_true("SC26 one fresh write response",
                   (S_AXI_BVALID === 1'b1) &&
                   (dut.u_reg_controlled_top.u_reg_bank.pwm_period === 16'd7));
        tick();
        check_true("SC26 response held without duplicate write",
                   (S_AXI_BVALID === 1'b1) &&
                   (dut.reg_wr_en === 1'b0));
        S_AXI_BREADY = 1'b1;
        tick();
        S_AXI_BREADY = 1'b0;
        ticks(2);
        check_true("SC26 no duplicate response",
                   (S_AXI_BVALID === 1'b0) &&
                   (dut.reg_wr_en === 1'b0));
        clear_axi_master();
        $display("SC26=PASS");

        // A read address held through release likewise creates exactly one
        // fresh response and no reset-era capture or replay.
        assert_reset_now();
        hold_reset_one_clock();
        S_AXI_ARADDR = 8'h20;
        S_AXI_ARVALID = 1'b1;
        release_reset_two_stage();
        check_true("SC27 no stale read at local release",
                   (S_AXI_RVALID === 1'b0) &&
                   (S_AXI_RDATA === 32'd0) &&
                   (dut.reg_rd_en === 1'b0));
        tick();
        check_true("SC27 held read captured once",
                   dut.reg_rd_en === 1'b1);
        S_AXI_ARVALID = 1'b0;
        tick();
        check_true("SC27 one fresh read response",
                   (S_AXI_RVALID === 1'b1) &&
                   (S_AXI_RDATA === 32'd1000));
        tick();
        check_true("SC27 response held without duplicate read",
                   (S_AXI_RVALID === 1'b1) &&
                   (dut.reg_rd_en === 1'b0));
        S_AXI_RREADY = 1'b1;
        tick();
        S_AXI_RREADY = 1'b0;
        ticks(2);
        check_true("SC27 no duplicate read response",
                   (S_AXI_RVALID === 1'b0) &&
                   (dut.reg_rd_en === 1'b0));
        clear_axi_master();
        $display("SC27=PASS");

        $display("ACTUAL_RESET_CLOCK_DOMAINS=1");
        $display("RESET_SYNCHRONIZERS=1");
        $display("ASYNC_ASSERT_SYNC_DEASSERT=PASS");
        $display("NO_ACCEPT_DURING_RESET_RELEASE=PASS");
        $display("NO_STALE_REPLAY_AFTER_RESET=PASS");
        $display("FIRST_POST_RESET_TRANSACTION_EXACTLY_ONCE=PASS");
        $display("ATOMIC_SAMPLE_PAIR_AFTER_RESET=PASS");
        $display("COMPARATOR_HEALTH_TRANSACTION_ALIGNMENT_PRESERVED=PASS");
        $display("ACTIVE_PWM_ASYNC_RESET=PASS");
        $display("INFLIGHT_AXI_RESET=PASS");
        $display("NON_RESET_LATENCY=N0_TO_N3_3_CYCLES_UNCHANGED");
        $display("SHORT_RESET_PULSE_SIM_CONTRACT=LOW_FOR_2NS_MINIMUM");
        $display("MULTI_CLOCK_SCENARIO=NOT_APPLICABLE_SINGLE_PROVEN_DOMAIN");
        $display("HIERARCHICAL_OBSERVATION=READ_ONLY");
        $display("HIERARCHICAL_WRITE=NO");
        $display("STAGE2C_POSITIVE_SCENARIOS=PASS_27_OF_27");
        $display("STAGE2C_RESET_RELEASE_CDC_DUT=PASS");
        $finish;
    end
endmodule
