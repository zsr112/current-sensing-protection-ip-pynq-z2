`timescale 1ns/1ps
`include "fault_defs.vh"
`include "protection_register_map.svh"

module tb_protection_ip_top_axi_lite;
  localparam [3:0] ST_NORMAL = 4'd0;
  localparam [3:0] ST_FAULT_LATCHED = 4'd1;
  localparam [3:0] ST_RESET_WAIT = 4'd2;
  localparam [3:0] REC_IDLE = 4'd0;
  localparam [3:0] REC_WAIT_CLEAR_PULSE = 4'd1;
  localparam [3:0] REC_EXPECT_E0 = 4'd2;
  localparam [3:0] REC_EXPECT_E1 = 4'd3;
  localparam [3:0] REC_EXPECT_E2 = 4'd4;
  localparam [3:0] REC_EXPECT_E3 = 4'd5;
  localparam [3:0] REC_EXPECT_E4 = 4'd6;
  localparam [3:0] REC_EXPECT_E5 = 4'd7;
  localparam [3:0] REC_DONE = 4'd8;

  localparam REG_CTRL       = `REG_CTRL;
  localparam REG_STATUS     = `REG_STATUS;
  localparam REG_FAULT_CODE = `REG_FAULT_CODE;
  localparam REG_I_CH1      = `REG_I_CH1;
  localparam REG_I_CH2      = `REG_I_CH2;
  localparam REG_TH_OC1     = `REG_TH_OC1;
  localparam REG_TH_OC2     = `REG_TH_OC2;
  localparam REG_TH_DIFF    = `REG_TH_DIFF;
  localparam REG_PWM_PERIOD = `REG_PWM_PERIOD;
  localparam REG_PWM_DUTY   = `REG_PWM_DUTY;

  reg ACLK = 1'b0;
  reg ARESETN = 1'b0;
  reg sample_valid = 1'b0;

  reg [7:0] S_AXI_AWADDR = 8'h00;
  reg S_AXI_AWVALID = 1'b0;
  wire S_AXI_AWREADY;
  reg [31:0] S_AXI_WDATA = 32'h0;
  reg [3:0] S_AXI_WSTRB = 4'h0;
  reg S_AXI_WVALID = 1'b0;
  wire S_AXI_WREADY;
  wire [1:0] S_AXI_BRESP;
  wire S_AXI_BVALID;
  reg S_AXI_BREADY = 1'b0;

  reg [7:0] S_AXI_ARADDR = 8'h00;
  reg S_AXI_ARVALID = 1'b0;
  wire S_AXI_ARREADY;
  wire [31:0] S_AXI_RDATA;
  wire [1:0] S_AXI_RRESP;
  wire S_AXI_RVALID;
  reg S_AXI_RREADY = 1'b0;

  reg [11:0] i_ch1 = 12'd500;
  reg [11:0] i_ch2 = 12'd510;

  wire pwm_raw;
  wire pwm_out;
  wire fault_valid;
  wire fault_latched;
  wire [7:0] fault_code;
  wire [7:0] fault_code_latched;
  wire [3:0] fsm_state;

  integer high_count;
  integer rise_count;
  integer fast_high_count;
  integer fast_rise_count;
  integer slow_high_count;
  integer slow_rise_count;
  integer overlap_guard;
  reg [31:0] rd_value;
  reg target_monitor_armed = 1'b0;
  reg target_monitor_clear = 1'b0;
  reg [31:0] target_monitor_data = 32'h0;
  integer target_aw_count;
  integer target_w_count;
  integer target_b_count;
  integer target_reg_wr_count;
  integer target_clear_pulse_count;
  integer target_unexpected_write_count;
  reg target_recovery_track = 1'b0;
  reg target_recovery_arm = 1'b0;
  reg target_recovery_expect_pwm_disabled = 1'b1;
  reg [7:0] target_retained_code = `FAULT_NONE;
  reg [3:0] target_recovery_phase;
  integer target_recovery_cycle_count;
  reg target_recovery_sequence_error;
  string target_recovery_qid = "Q-SIM";

  always #5 ACLK = ~ACLK;

  protection_ip_top_axi_lite dut (
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
    .fsm_state(fsm_state)
  );

  always @(posedge ACLK or negedge ARESETN) begin
    if (!ARESETN || target_monitor_clear) begin
      target_aw_count <= 0;
      target_w_count <= 0;
      target_b_count <= 0;
      target_reg_wr_count <= 0;
      target_clear_pulse_count <= 0;
      target_unexpected_write_count <= 0;
    end else if (target_monitor_armed) begin
      if (S_AXI_AWVALID && S_AXI_AWREADY)
        target_aw_count <= target_aw_count + 1;
      if (S_AXI_WVALID && S_AXI_WREADY)
        target_w_count <= target_w_count + 1;
      if (S_AXI_BVALID && S_AXI_BREADY)
        target_b_count <= target_b_count + 1;
      if (dut.reg_wr_en) begin
        if (dut.reg_addr == REG_CTRL && dut.reg_wdata == target_monitor_data)
          target_reg_wr_count <= target_reg_wr_count + 1;
        else
          target_unexpected_write_count <= target_unexpected_write_count + 1;
      end
      if (dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse)
        target_clear_pulse_count <= target_clear_pulse_count + 1;
    end
  end

  task automatic q_axi_phase_fatal(input string reason);
    begin
      $fatal(1, "%s %s phase=%0d state=%0d count=%0d live=%0b latch=%0b code=0x%02h clear=%0b reg_wr=%0b disable=%0b enable=%0b raw=%0b out=%0b AW/W/B/reg/clear=%0d/%0d/%0d/%0d/%0d unexpected=%0d",
             target_recovery_qid, reason, target_recovery_phase, fsm_state,
             dut.u_reg_controlled_top.u_core.u_fsm.reset_wait_cnt, fault_valid, fault_latched,
             fault_code_latched, dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse,
             dut.reg_wr_en, dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable,
             dut.u_reg_controlled_top.u_reg_bank.pwm_enable, pwm_raw, pwm_out,
             target_aw_count, target_w_count, target_b_count, target_reg_wr_count,
             target_clear_pulse_count, target_unexpected_write_count);
    end
  endtask

  always @(posedge ACLK) begin
    #1;
    if (!ARESETN || target_monitor_clear || !target_recovery_track) begin
      target_recovery_phase = REC_IDLE;
      target_recovery_cycle_count = 0;
      target_recovery_sequence_error = 1'b0;
    end else if (target_recovery_arm) begin
      target_recovery_phase = REC_WAIT_CLEAR_PULSE;
      target_recovery_cycle_count = 0;
      target_recovery_sequence_error = 1'b0;
    end else if (target_recovery_phase !== REC_IDLE && target_recovery_phase !== REC_DONE) begin
      target_recovery_cycle_count = target_recovery_cycle_count + 1;
      if (target_recovery_cycle_count > 32) begin
        target_recovery_sequence_error = 1'b1;
        q_axi_phase_fatal("recovery phase exceeded bounded cycle guard");
      end

      case (target_recovery_phase)
        REC_WAIT_CLEAR_PULSE: begin
          if (dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse && !dut.reg_wr_en)
            target_recovery_phase = REC_EXPECT_E0;
          else if (dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse || fsm_state == ST_RESET_WAIT) begin
            target_recovery_sequence_error = 1'b1;
            q_axi_phase_fatal("WAIT_CLEAR_PULSE ordering mismatch");
          end
        end

        REC_EXPECT_E0: begin
          if (fsm_state == ST_RESET_WAIT && dut.u_reg_controlled_top.u_core.u_fsm.reset_wait_cnt == 16'd0 &&
              fault_latched && fault_code_latched == target_retained_code &&
              dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable && pwm_out == 1'b0 &&
              !dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse && !dut.reg_wr_en)
            target_recovery_phase = REC_EXPECT_E1;
          else begin
            target_recovery_sequence_error = 1'b1;
            q_axi_phase_fatal("EXPECT_E0 mismatch");
          end
        end

        REC_EXPECT_E1: begin
          if (fsm_state == ST_RESET_WAIT && dut.u_reg_controlled_top.u_core.u_fsm.reset_wait_cnt == 16'd1 &&
              fault_latched && fault_code_latched == target_retained_code &&
              dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable && pwm_out == 1'b0 &&
              !dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse && !dut.reg_wr_en)
            target_recovery_phase = REC_EXPECT_E2;
          else begin
            target_recovery_sequence_error = 1'b1;
            q_axi_phase_fatal("EXPECT_E1 mismatch");
          end
        end

        REC_EXPECT_E2: begin
          if (fsm_state == ST_RESET_WAIT && dut.u_reg_controlled_top.u_core.u_fsm.reset_wait_cnt == 16'd2 &&
              fault_latched && fault_code_latched == target_retained_code &&
              dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable && pwm_out == 1'b0 &&
              !dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse && !dut.reg_wr_en)
            target_recovery_phase = REC_EXPECT_E3;
          else begin
            target_recovery_sequence_error = 1'b1;
            q_axi_phase_fatal("EXPECT_E2 mismatch");
          end
        end

        REC_EXPECT_E3: begin
          if (fsm_state == ST_RESET_WAIT && dut.u_reg_controlled_top.u_core.u_fsm.reset_wait_cnt == 16'd3 &&
              fault_latched && fault_code_latched == target_retained_code &&
              dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable && pwm_out == 1'b0 &&
              !dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse && !dut.reg_wr_en)
            target_recovery_phase = REC_EXPECT_E4;
          else begin
            target_recovery_sequence_error = 1'b1;
            q_axi_phase_fatal("EXPECT_E3 mismatch");
          end
        end

        REC_EXPECT_E4: begin
          if (fsm_state == ST_NORMAL && dut.u_reg_controlled_top.u_core.u_fsm.reset_wait_cnt == 16'd3 &&
              !fault_latched && fault_code_latched == `FAULT_NONE &&
              dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable && pwm_out == 1'b0 &&
              !dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse && !dut.reg_wr_en)
            target_recovery_phase = REC_EXPECT_E5;
          else begin
            target_recovery_sequence_error = 1'b1;
            q_axi_phase_fatal("EXPECT_E4 atomic latch/code clear mismatch");
          end
        end

        REC_EXPECT_E5: begin
          if (fsm_state !== ST_NORMAL ||
              dut.u_reg_controlled_top.u_core.u_fsm.reset_wait_cnt !== 16'd0 ||
              fault_latched !== 1'b0 || fault_code_latched !== `FAULT_NONE ||
              dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable !== 1'b0 ||
              dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse || dut.reg_wr_en) begin
            target_recovery_sequence_error = 1'b1;
            q_axi_phase_fatal("EXPECT_E5 registered gate release mismatch");
          end else if (target_recovery_expect_pwm_disabled &&
                       (dut.u_reg_controlled_top.u_reg_bank.pwm_enable !== 1'b0 || pwm_raw !== 1'b0 || pwm_out !== 1'b0)) begin
            target_recovery_sequence_error = 1'b1;
            q_axi_phase_fatal("EXPECT_E5 clear-only PWM-disabled mismatch");
          end else if (!target_recovery_expect_pwm_disabled &&
                       (dut.u_reg_controlled_top.u_reg_bank.pwm_enable !== 1'b1 || pwm_out !== pwm_raw)) begin
            target_recovery_sequence_error = 1'b1;
            q_axi_phase_fatal("EXPECT_E5 compatibility-only pwm_out/pwm_raw mismatch");
          end else begin
            target_recovery_phase = REC_DONE;
          end
        end

        default: begin
          target_recovery_sequence_error = 1'b1;
          q_axi_phase_fatal("unknown recovery phase");
        end
      endcase
    end
  end

  task automatic wait_cycles(input integer cycles);
    integer n;
    begin
      for (n = 0; n < cycles; n = n + 1)
        @(posedge ACLK);
      #1;
    end
  endtask

  task automatic check_equal(input string name, input [31:0] actual, input [31:0] expected);
    begin
      if (actual !== expected) begin
        $display("FAIL: %s expected=0x%08h actual=0x%08h", name, expected, actual);
        $fatal(1);
      end
    end
  endtask

  task automatic check_true(input string name, input condition);
    begin
      if (!condition) begin
        $display("FAIL: %s", name);
        $fatal(1);
      end
    end
  endtask

  task automatic drive_axi_idle;
    begin
      S_AXI_AWADDR = 8'h00;
      S_AXI_AWVALID = 1'b0;
      S_AXI_WDATA = 32'h0;
      S_AXI_WSTRB = 4'h0;
      S_AXI_WVALID = 1'b0;
      S_AXI_BREADY = 1'b0;
      S_AXI_ARADDR = 8'h00;
      S_AXI_ARVALID = 1'b0;
      S_AXI_RREADY = 1'b0;
    end
  endtask

  task automatic axi_write_strb(input [7:0] a, input [31:0] d, input [3:0] strb);
    integer guard;
    begin
      guard = 0;

      @(negedge ACLK);
      S_AXI_AWADDR = a;
      S_AXI_AWVALID = 1'b1;
      S_AXI_WDATA = d;
      S_AXI_WSTRB = strb;
      S_AXI_WVALID = 1'b1;

      while (!(S_AXI_AWREADY && S_AXI_WREADY)) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: AXI write handshake timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      @(posedge ACLK);
      #1;
      S_AXI_AWVALID = 1'b0;
      S_AXI_WVALID = 1'b0;
      S_AXI_WSTRB = 4'h0;

      S_AXI_BREADY = 1'b1;
      guard = 0;
      while (!S_AXI_BVALID) begin
        @(posedge ACLK);
        #1;
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: AXI write response timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      check_equal("AXI write BRESP", {30'd0, S_AXI_BRESP}, 32'd0);
      @(posedge ACLK);
      #1;
      S_AXI_BREADY = 1'b0;
      S_AXI_AWADDR = 8'h00;
      S_AXI_WDATA = 32'h0;
    end
  endtask

  task automatic axi_write(input [7:0] a, input [31:0] d);
    begin
      axi_write_strb(a, d, 4'hF);
    end
  endtask

  task automatic axi_write_aw_then_w(input [7:0] a, input [31:0] d, input [3:0] strb, input integer gap_cycles);
    integer guard;
    begin
      guard = 0;
      @(negedge ACLK);
      S_AXI_AWADDR = a;
      S_AXI_AWVALID = 1'b1;
      while (!S_AXI_AWREADY) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: AW-before-W address timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      @(posedge ACLK);
      #1;
      S_AXI_AWVALID = 1'b0;
      S_AXI_AWADDR = 8'h00;
      wait_cycles(gap_cycles);

      guard = 0;
      @(negedge ACLK);
      S_AXI_WDATA = d;
      S_AXI_WSTRB = strb;
      S_AXI_WVALID = 1'b1;
      while (!S_AXI_WREADY) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: AW-before-W data timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      @(posedge ACLK);
      #1;
      S_AXI_WVALID = 1'b0;
      S_AXI_WSTRB = 4'h0;
      S_AXI_WDATA = 32'h0;

      guard = 0;
      S_AXI_BREADY = 1'b1;
      while (!S_AXI_BVALID) begin
        @(posedge ACLK);
        #1;
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: AW-before-W write response timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      check_equal("AW-before-W BRESP", {30'd0, S_AXI_BRESP}, 32'd0);
      @(posedge ACLK);
      #1;
      S_AXI_BREADY = 1'b0;
    end
  endtask

  task automatic axi_write_w_then_aw(input [7:0] a, input [31:0] d, input [3:0] strb, input integer gap_cycles);
    integer guard;
    begin
      guard = 0;
      @(negedge ACLK);
      S_AXI_WDATA = d;
      S_AXI_WSTRB = strb;
      S_AXI_WVALID = 1'b1;
      while (!S_AXI_WREADY) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: W-before-AW data timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      @(posedge ACLK);
      #1;
      S_AXI_WVALID = 1'b0;
      S_AXI_WSTRB = 4'h0;
      S_AXI_WDATA = 32'h0;
      wait_cycles(gap_cycles);

      guard = 0;
      @(negedge ACLK);
      S_AXI_AWADDR = a;
      S_AXI_AWVALID = 1'b1;
      while (!S_AXI_AWREADY) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: W-before-AW address timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      @(posedge ACLK);
      #1;
      S_AXI_AWVALID = 1'b0;
      S_AXI_AWADDR = 8'h00;

      guard = 0;
      S_AXI_BREADY = 1'b1;
      while (!S_AXI_BVALID) begin
        @(posedge ACLK);
        #1;
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: W-before-AW write response timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      check_equal("W-before-AW BRESP", {30'd0, S_AXI_BRESP}, 32'd0);
      @(posedge ACLK);
      #1;
      S_AXI_BREADY = 1'b0;
    end
  endtask

  task automatic axi_write_hold_bready(input [7:0] a, input [31:0] d, input [3:0] strb, input integer hold_cycles);
    integer guard;
    integer n;
    begin
      guard = 0;
      @(negedge ACLK);
      S_AXI_AWADDR = a;
      S_AXI_AWVALID = 1'b1;
      S_AXI_WDATA = d;
      S_AXI_WSTRB = strb;
      S_AXI_WVALID = 1'b1;
      S_AXI_BREADY = 1'b0;
      while (!(S_AXI_AWREADY && S_AXI_WREADY)) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: BREADY-hold write handshake timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      @(posedge ACLK);
      #1;
      S_AXI_AWVALID = 1'b0;
      S_AXI_WVALID = 1'b0;
      S_AXI_WSTRB = 4'h0;

      guard = 0;
      while (!S_AXI_BVALID) begin
        @(posedge ACLK);
        #1;
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: BVALID did not assert while BREADY was low addr=0x%02h", a);
          $fatal(1);
        end
      end
      for (n = 0; n < hold_cycles; n = n + 1) begin
        @(posedge ACLK);
        #1;
        check_true("BVALID must hold while BREADY is low", S_AXI_BVALID == 1'b1);
        check_equal("BRESP must stay OKAY while BREADY is low", {30'd0, S_AXI_BRESP}, 32'd0);
      end
      S_AXI_BREADY = 1'b1;
      @(posedge ACLK);
      #1;
      S_AXI_BREADY = 1'b0;
      S_AXI_AWADDR = 8'h00;
      S_AXI_WDATA = 32'h0;
    end
  endtask

  task automatic axi_read(input [7:0] a, output [31:0] d);
    integer guard;
    begin
      guard = 0;
      @(negedge ACLK);
      S_AXI_ARADDR = a;
      S_AXI_ARVALID = 1'b1;

      while (!S_AXI_ARREADY) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: AXI read address timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      @(posedge ACLK);
      #1;
      S_AXI_ARVALID = 1'b0;

      S_AXI_RREADY = 1'b1;
      guard = 0;
      while (!S_AXI_RVALID) begin
        @(posedge ACLK);
        #1;
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: AXI read data timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      d = S_AXI_RDATA;
      check_equal("AXI read RRESP", {30'd0, S_AXI_RRESP}, 32'd0);
      @(posedge ACLK);
      #1;
      S_AXI_RREADY = 1'b0;
      S_AXI_ARADDR = 8'h00;
    end
  endtask

  task automatic axi_read_hold_rready(input [7:0] a, output [31:0] d, input integer hold_cycles);
    integer guard;
    integer n;
    reg [31:0] stable_data;
    begin
      guard = 0;
      @(negedge ACLK);
      S_AXI_ARADDR = a;
      S_AXI_ARVALID = 1'b1;
      S_AXI_RREADY = 1'b0;

      while (!S_AXI_ARREADY) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: RREADY-hold read address timeout addr=0x%02h", a);
          $fatal(1);
        end
      end
      @(posedge ACLK);
      #1;
      S_AXI_ARVALID = 1'b0;

      guard = 0;
      while (!S_AXI_RVALID) begin
        @(posedge ACLK);
        #1;
        guard = guard + 1;
        if (guard > 20) begin
          $display("FAIL: RVALID did not assert while RREADY was low addr=0x%02h", a);
          $fatal(1);
        end
      end
      stable_data = S_AXI_RDATA;
      d = S_AXI_RDATA;
      check_equal("RREADY-hold RRESP", {30'd0, S_AXI_RRESP}, 32'd0);
      for (n = 0; n < hold_cycles; n = n + 1) begin
        @(posedge ACLK);
        #1;
        check_true("RVALID must hold while RREADY is low", S_AXI_RVALID == 1'b1);
        check_equal("RDATA must hold while RREADY is low", S_AXI_RDATA, stable_data);
      end
      S_AXI_RREADY = 1'b1;
      @(posedge ACLK);
      #1;
      S_AXI_RREADY = 1'b0;
      S_AXI_ARADDR = 8'h00;
    end
  endtask

  task automatic finish_reset_and_check_defaults;
    begin
      #1;
      drive_axi_idle();
      sample_valid = 1'b0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd510;
      repeat (3) @(posedge ACLK);
      #1;
      check_true("reset must clear BVALID", S_AXI_BVALID == 1'b0);
      check_true("reset must clear RVALID", S_AXI_RVALID == 1'b0);
      @(negedge ACLK);
      ARESETN = 1'b1;
      wait_cycles(4);
      axi_read(REG_STATUS, rd_value);
      check_equal("reset transaction status default", rd_value, 32'h0000_0000);
      axi_read(REG_FAULT_CODE, rd_value);
      check_equal("reset transaction fault code default", rd_value, 32'h0000_0000);
      axi_read(REG_TH_OC1, rd_value);
      check_equal("reset transaction TH_OC1 default", rd_value, 32'd3000);
    end
  endtask

  task automatic run_reset_during_transaction_tests;
    integer guard;
    begin
      $display("AXI reset stress: write/read in-flight reset scenarios");

      axi_write(REG_TH_OC1, 32'd1111);
      @(negedge ACLK);
      S_AXI_AWADDR = REG_TH_OC1;
      S_AXI_AWVALID = 1'b1;
      S_AXI_WVALID = 1'b0;
      S_AXI_WSTRB = 4'hF;
      @(posedge ACLK);
      #1;
      ARESETN = 1'b0;
      finish_reset_and_check_defaults();

      axi_write(REG_TH_OC1, 32'd2222);
      @(negedge ACLK);
      S_AXI_WDATA = 32'd1234;
      S_AXI_WSTRB = 4'hF;
      S_AXI_WVALID = 1'b1;
      S_AXI_AWVALID = 1'b0;
      @(posedge ACLK);
      #1;
      ARESETN = 1'b0;
      finish_reset_and_check_defaults();

      @(negedge ACLK);
      S_AXI_AWADDR = REG_TH_OC1;
      S_AXI_AWVALID = 1'b1;
      S_AXI_WDATA = 32'd2222;
      S_AXI_WSTRB = 4'hF;
      S_AXI_WVALID = 1'b1;
      S_AXI_BREADY = 1'b0;
      guard = 0;
      while (!(S_AXI_AWREADY && S_AXI_WREADY)) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) $fatal(1, "reset during BVALID setup handshake timeout");
      end
      @(posedge ACLK);
      #1;
      S_AXI_AWVALID = 1'b0;
      S_AXI_WVALID = 1'b0;
      S_AXI_WSTRB = 4'h0;
      guard = 0;
      while (!S_AXI_BVALID) begin
        @(posedge ACLK);
        #1;
        guard = guard + 1;
        if (guard > 20) $fatal(1, "reset during BVALID pending timeout");
      end
      ARESETN = 1'b0;
      finish_reset_and_check_defaults();

      axi_write(REG_TH_OC1, 32'd3333);
      @(negedge ACLK);
      S_AXI_ARADDR = REG_TH_OC1;
      S_AXI_ARVALID = 1'b1;
      S_AXI_RREADY = 1'b0;
      @(posedge ACLK);
      #1;
      ARESETN = 1'b0;
      finish_reset_and_check_defaults();

      axi_write(REG_TH_OC1, 32'd3333);
      @(negedge ACLK);
      S_AXI_ARADDR = REG_TH_OC1;
      S_AXI_ARVALID = 1'b1;
      S_AXI_RREADY = 1'b0;
      guard = 0;
      while (!S_AXI_ARREADY) begin
        @(posedge ACLK);
        guard = guard + 1;
        if (guard > 20) $fatal(1, "reset during RVALID setup address timeout");
      end
      @(posedge ACLK);
      #1;
      S_AXI_ARVALID = 1'b0;
      guard = 0;
      while (!S_AXI_RVALID) begin
        @(posedge ACLK);
        #1;
        guard = guard + 1;
        if (guard > 20) $fatal(1, "reset during RVALID pending timeout");
      end
      check_equal("RDATA before reset while RVALID pending", S_AXI_RDATA, 32'd3333);
      ARESETN = 1'b0;
      finish_reset_and_check_defaults();
    end
  endtask

  task automatic measure_pwm(input integer cycles, output integer high_total, output integer rising_edges);
    integer n;
    reg prev_pwm;
    begin
      high_total = 0;
      rising_edges = 0;
      prev_pwm = pwm_out;
      for (n = 0; n < cycles; n = n + 1) begin
        @(posedge ACLK);
        #1;
        if (pwm_out)
          high_total = high_total + 1;
        if (!prev_pwm && pwm_out)
          rising_edges = rising_edges + 1;
        prev_pwm = pwm_out;
      end
    end
  endtask

  task automatic q_axi_reset(input string qid);
    begin
      @(negedge ACLK);
      ARESETN = 1'b0;
      drive_axi_idle();
      sample_valid = 1'b0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd510;
      target_monitor_armed = 1'b0;
      target_monitor_clear = 1'b0;
      target_recovery_track = 1'b0;
      target_recovery_arm = 1'b0;
      repeat (2) @(posedge ACLK);
      #1;
      if (fault_latched || fault_valid || fault_code_latched !== `FAULT_NONE || fsm_state !== ST_NORMAL)
        $fatal(1, "%s AXI reset isolation failed", qid);
      @(negedge ACLK);
      ARESETN = 1'b1;
      wait_cycles(4);
    end
  endtask

  task automatic q_axi_arm_target(
    input string qid,
    input [31:0] expected_data,
    input recovery_track,
    input expect_pwm_disabled
  );
    begin
      @(negedge ACLK);
      target_monitor_armed = 1'b0;
      target_recovery_track = 1'b0;
      target_recovery_arm = 1'b0;
      target_monitor_data = expected_data;
      target_monitor_clear = 1'b1;
      @(posedge ACLK); #1;
      @(negedge ACLK);
      target_monitor_clear = 1'b0;
      target_retained_code = fault_code_latched;
      target_recovery_expect_pwm_disabled = expect_pwm_disabled;
      target_recovery_qid = qid;
      target_recovery_track = recovery_track;
      target_recovery_arm = recovery_track;
      target_monitor_armed = 1'b1;
      @(posedge ACLK); #1;
      @(negedge ACLK);
      target_recovery_arm = 1'b0;
    end
  endtask

  task automatic q_axi_disarm_and_check(input string qid);
    begin
      @(negedge ACLK);
      if (target_recovery_track && target_recovery_phase !== REC_DONE)
        $fatal(1, "%s disarmed before recovery phase DONE; phase=%0d", qid, target_recovery_phase);
      target_monitor_armed = 1'b0;
      target_recovery_track = 1'b0;
      target_recovery_arm = 1'b0;
      if (target_aw_count !== 1 || target_w_count !== 1 || target_b_count !== 1 ||
          target_reg_wr_count !== 1 || target_clear_pulse_count !== 1 || target_unexpected_write_count !== 0)
        $fatal(1, "%s target counts AW=%0d W=%0d B=%0d reg_wr=%0d clear=%0d unexpected=%0d",
               qid, target_aw_count, target_w_count, target_b_count, target_reg_wr_count,
               target_clear_pulse_count, target_unexpected_write_count);
    end
  endtask

  task automatic q_axi_issue_pattern(input integer pattern, input [31:0] ctrl_data);
    begin
      case (pattern)
        0: axi_write(REG_CTRL, ctrl_data);
        1: axi_write_aw_then_w(REG_CTRL, ctrl_data, 4'hF, 2);
        2: axi_write_w_then_aw(REG_CTRL, ctrl_data, 4'hF, 2);
        default: $fatal(1, "Q-SIM-14 unknown AXI arrival pattern %0d", pattern);
      endcase
    end
  endtask

  task automatic q_axi_safe_setup;
    begin
      axi_write(REG_CTRL, 32'h0000_0000);
      axi_write(REG_TH_OC1, 32'd3000);
      axi_write(REG_TH_OC2, 32'd3000);
      axi_write(REG_TH_DIFF, 32'd200);
      axi_write(REG_PWM_PERIOD, 32'd8);
      axi_write(REG_PWM_DUTY, 32'd4);
    end
  endtask

  task automatic q_axi_sample(input [11:0] a, input [11:0] b);
    begin
      @(negedge ACLK);
      i_ch1 = a;
      i_ch2 = b;
      sample_valid = 1'b1;
      @(posedge ACLK); #1;
      @(negedge ACLK);
      sample_valid = 1'b0;
      @(posedge ACLK); #1;
    end
  endtask

  task automatic q_axi_wait_live_low(input string qid);
    integer guard;
    begin
      guard = 0;
      while (dut.u_reg_controlled_top.u_core.accepted_sample_valid ||
             dut.u_reg_controlled_top.u_core.sample_decision_valid ||
             fault_valid) begin
        @(posedge ACLK); #1;
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "%s timeout waiting for registered live fault to clear", qid);
      end
      if (!fault_latched)
        $fatal(1, "%s live source removal incorrectly cleared fault_latched", qid);
    end
  endtask

  task automatic q_axi_make_stuck(input string qid);
    integer sample_cycle;
    integer guard;
    begin
      i_ch1 = 12'd500;
      i_ch2 = 12'd510;
      @(negedge ACLK); sample_valid = 1'b1;
      for (sample_cycle = 0; sample_cycle < 260; sample_cycle = sample_cycle + 1) begin
        @(posedge ACLK); #1;
      end
      @(negedge ACLK); sample_valid = 1'b0;
      guard = 0;
      while (!fault_latched) begin
        @(posedge ACLK); #1;
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "%s timeout creating persistent stuck through public samples", qid);
      end
      if (!dut.u_reg_controlled_top.u_core.sensor_stuck_flag || !fault_valid ||
          fault_code_latched !== `FAULT_SENSOR_STUCK || fsm_state !== ST_FAULT_LATCHED ||
          !dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable)
        $fatal(1, "%s persistent stuck setup mismatch", qid);
    end
  endtask

  task automatic q_axi_remove_stuck(input string qid);
    begin
      $display("%s current implementation characterization: two moving valid samples drive visible stuck-source removal", qid);
      q_axi_sample(12'd520, 12'd530);
      if (!dut.u_reg_controlled_top.u_core.sensor_stuck_flag ||
          dut.u_reg_controlled_top.u_core.u_health.stuck_cnt !== 8'd0)
        $fatal(1, "%s first moving sample did not reset history before visible clear", qid);
      q_axi_sample(12'd540, 12'd550);
      if (dut.u_reg_controlled_top.u_core.sensor_stuck_flag)
        $fatal(1, "%s second moving sample did not clear visible stuck behavior", qid);
      q_axi_wait_live_low(qid);
      if (fault_code_latched !== `FAULT_SENSOR_STUCK || fsm_state !== ST_FAULT_LATCHED ||
          !dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable)
        $fatal(1, "%s removed-source latch/code retention mismatch", qid);
    end
  endtask

  task automatic q_axi_make_overcurrent(input string qid);
    integer guard;
    begin
      q_axi_sample(12'd2500, 12'd2500);
      guard = 0;
      while (!fault_latched) begin
        @(posedge ACLK); #1;
        guard = guard + 1;
        if (guard > 12)
          $fatal(1, "%s timeout creating overcurrent", qid);
      end
      if (fault_code_latched !== `FAULT_OVERCURRENT || !dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable)
        $fatal(1, "%s overcurrent setup mismatch", qid);
    end
  endtask

  task automatic q_axi_remove_overcurrent(input string qid);
    begin
      q_axi_sample(12'd500, 12'd510);
      q_axi_wait_live_low(qid);
    end
  endtask

  task automatic q_axi_wait_recovery_and_check(input string qid);
    integer guard;
    begin
      guard = 0;
      while (target_recovery_phase !== REC_DONE) begin
        @(negedge ACLK);
        guard = guard + 1;
        if (guard > 40)
          $fatal(1, "%s timeout waiting for strict recovery phase DONE; phase=%0d", qid, target_recovery_phase);
      end
      if (target_recovery_sequence_error !== 1'b0)
        $fatal(1, "%s recovery phase DONE with sequence_error asserted", qid);
      @(posedge ACLK); #1;
      if (fsm_state !== ST_NORMAL ||
          dut.u_reg_controlled_top.u_core.u_fsm.reset_wait_cnt !== 16'd0 ||
          fault_latched || fault_code_latched !== `FAULT_NONE ||
          dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable ||
          dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse || dut.reg_wr_en)
        q_axi_phase_fatal("post-DONE protection/pulse/write stability mismatch");
      if (target_recovery_expect_pwm_disabled &&
          (dut.u_reg_controlled_top.u_reg_bank.pwm_enable || pwm_raw !== 1'b0 || pwm_out !== 1'b0))
        q_axi_phase_fatal("post-DONE clear-only PWM-disabled mismatch");
      if (!target_recovery_expect_pwm_disabled &&
          (!dut.u_reg_controlled_top.u_reg_bank.pwm_enable || pwm_out !== pwm_raw))
        q_axi_phase_fatal("post-DONE compatibility-only PWM mismatch");
      q_axi_disarm_and_check(qid);
    end
  endtask

  task automatic run_enh_axi_safe_normal_clear;
    begin
      $display("Q-SIM-09 AXI transport enhancement: full-width clear in safe NORMAL");
      q_axi_reset("Q-SIM-09 AXI safe NORMAL");
      q_axi_safe_setup();
      if (fault_valid || fault_latched || fault_code_latched !== `FAULT_NONE || fsm_state !== ST_NORMAL)
        $fatal(1, "Q-SIM-09 AXI safe-NORMAL precondition mismatch");
      q_axi_arm_target("Q-SIM-09 AXI safe NORMAL", 32'h0000_0002, 1'b0, 1'b1);
      q_axi_issue_pattern(0, 32'h0000_0002);
      @(posedge ACLK); #1;
      if (fault_valid || fault_latched || fault_code_latched !== `FAULT_NONE ||
          fsm_state !== ST_NORMAL || dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable ||
          dut.u_reg_controlled_top.u_reg_bank.clear_fault_pulse || dut.reg_wr_en ||
          dut.u_reg_controlled_top.u_reg_bank.pwm_enable || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-09 AXI safe-NORMAL clear produced a side effect");
      q_axi_disarm_and_check("Q-SIM-09 AXI safe NORMAL");
      axi_read(REG_CTRL, rd_value);
      check_equal("Q-SIM-09 AXI safe-NORMAL CTRL", rd_value, 32'h0000_0000);
      axi_read(REG_STATUS, rd_value);
      check_equal("Q-SIM-09 AXI safe-NORMAL STATUS", rd_value, 32'h0000_0000);
      axi_read(REG_FAULT_CODE, rd_value);
      check_equal("Q-SIM-09 AXI safe-NORMAL FAULT_CODE", rd_value, 32'h0000_0000);
    end
  endtask

  task automatic run_axi_lite_persistent_sensor_stuck_clear_only;
    integer n;
    integer guard;
    reg [7:0] history_before_clear;
    begin
      $display("[10D-G] START AXI-Lite persistent sensor-stuck invalid-clear stale-event suppression");
      $display("Q-SIM-01 updates the formal 10D-G task to the Stage 2B transaction contract");

      @(negedge ACLK);
      ARESETN = 1'b0;
      finish_reset_and_check_defaults();
      axi_read(REG_CTRL, rd_value);
      check_equal("10D-G reset keeps PWM disabled", rd_value, 32'h0000_0000);

      @(negedge ACLK);
      sample_valid = 1'b0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd500;
      axi_write(REG_TH_OC1, 32'd3000);
      axi_write(REG_TH_OC2, 32'd3000);
      axi_write(REG_TH_DIFF, 32'd200);
      axi_read(REG_STATUS, rd_value);
      check_equal("10D-G safe configured status", rd_value, 32'h0000_0000);

      for (n = 0; n < 260; n = n + 1) begin
        @(negedge ACLK);
        i_ch1 = 12'd500;
        i_ch2 = 12'd500;
        sample_valid = 1'b1;
        @(negedge ACLK);
        sample_valid = 1'b0;
        #1;
      end

      guard = 0;
      while (!fault_latched) begin
        @(posedge ACLK);
        #1;
        guard = guard + 1;
        if (guard > 32) begin
          $display("FAIL: 10D-G persistent sensor-stuck did not latch");
          $fatal(1);
        end
      end

      q_axi_wait_live_low("Q-SIM-01 [10D-G]");
      check_true("10D-G invalid gap clears live transaction event", fault_valid == 1'b0);
      check_true("10D-G persistent stuck fault_latched before clear-only", fault_latched == 1'b1);
      check_equal("10D-G persistent stuck latched code before clear-only", {24'd0, fault_code_latched}, {24'd0, `FAULT_SENSOR_STUCK});
      axi_read(REG_STATUS, rd_value);
      check_equal("10D-G retained latch STATUS before clear-only", rd_value, 32'h0000_0002);
      axi_read(REG_FAULT_CODE, rd_value);
      check_equal("10D-G persistent stuck FAULT_CODE before clear-only", rd_value, 32'h0000_0005);

      history_before_clear = dut.u_reg_controlled_top.u_core.u_health.stuck_cnt;
      q_axi_arm_target("Q-SIM-01 [10D-G]", 32'h0000_0002, 1'b0, 1'b1);
      axi_write(REG_CTRL, 32'h0000_0002);
      @(posedge ACLK); #1;
      if (dut.u_reg_controlled_top.u_core.u_health.stuck_cnt !== history_before_clear ||
          !dut.u_reg_controlled_top.u_core.sensor_stuck_flag || fault_valid ||
          !fault_latched || fault_code_latched !== `FAULT_SENSOR_STUCK ||
          fsm_state !== ST_RESET_WAIT || !dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable ||
          pwm_out !== 1'b0)
        $fatal(1, "10D-G clear changed retained health state or E0 protection");
      wait_cycles(9);
      q_axi_disarm_and_check("Q-SIM-01 [10D-G]");

      if (dut.u_reg_controlled_top.u_core.u_health.stuck_cnt !== history_before_clear ||
          !dut.u_reg_controlled_top.u_core.sensor_stuck_flag || fault_valid || fault_latched ||
          fault_code_latched !== `FAULT_NONE || fsm_state !== ST_NORMAL ||
          dut.u_reg_controlled_top.u_core.u_fsm.pwm_disable || pwm_out !== 1'b0)
        $fatal(1, "10D-G stale retained health state retriggered protection");
      check_true("10D-G retained health flag is not a live event", fault_valid == 1'b0);
      check_true("10D-G invalid clear releases stale latch", fault_latched == 1'b0);
      check_equal("10D-G invalid clear removes old code", {24'd0, fault_code_latched}, {24'd0, `FAULT_NONE});
      axi_read(REG_STATUS, rd_value);
      check_equal("10D-G clear STATUS after stale suppression", rd_value, 32'h0000_0000);
      axi_read(REG_FAULT_CODE, rd_value);
      check_equal("10D-G FAULT_CODE after stale suppression", rd_value, 32'h0000_0000);

      @(negedge ACLK);
      sample_valid = 1'b0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd500;
      $display("[10D-G] PASS AXI-Lite invalid-clear stale-event suppression");
    end
  endtask

  task automatic run_qsim03_qsim10_qsim14_same_cycle;
    begin
      $display("Q-SIM-03/Q-SIM-10/Q-SIM-14 same-cycle AW/W full-width clear-only recovery");
      q_axi_reset("Q-SIM-03/Q-SIM-10/Q-SIM-14 same-cycle");
      q_axi_safe_setup();
      q_axi_make_stuck("Q-SIM-03/Q-SIM-10/Q-SIM-14 same-cycle");
      q_axi_remove_stuck("Q-SIM-03/Q-SIM-10/Q-SIM-14 same-cycle");
      q_axi_arm_target("Q-SIM-14 same-cycle AW/W", 32'h0000_0002, 1'b1, 1'b1);
      q_axi_issue_pattern(0, 32'h0000_0002);
      q_axi_wait_recovery_and_check("Q-SIM-14 same-cycle AW/W");
      axi_read(REG_CTRL, rd_value);
      check_equal("Q-SIM-03 final CTRL", rd_value, 32'h0000_0000);
      axi_read(REG_STATUS, rd_value);
      check_equal("Q-SIM-03 final STATUS", rd_value, 32'h0000_0000);
      axi_read(REG_FAULT_CODE, rd_value);
      check_equal("Q-SIM-03 final FAULT_CODE", rd_value, 32'h0000_0000);
      if (dut.u_reg_controlled_top.u_reg_bank.pwm_enable || pwm_raw !== 1'b0 || pwm_out !== 1'b0)
        $fatal(1, "Q-SIM-10 gate release must not enable PWM");
    end
  endtask

  task automatic run_qsim14_split_pattern(input integer pattern, input string pattern_name);
    begin
      $display("Q-SIM-14 %s independent AW/W channel arrival characterization", pattern_name);
      q_axi_reset(pattern_name);
      q_axi_safe_setup();
      axi_write(REG_TH_OC1, 32'd1000);
      axi_write(REG_TH_OC2, 32'd1000);
      q_axi_make_overcurrent(pattern_name);
      q_axi_remove_overcurrent(pattern_name);
      q_axi_arm_target(pattern_name, 32'h0000_0002, 1'b1, 1'b1);
      q_axi_issue_pattern(pattern, 32'h0000_0002);
      q_axi_wait_recovery_and_check(pattern_name);
      axi_read(REG_CTRL, rd_value);
      check_equal("Q-SIM-14 split-pattern final CTRL", rd_value, 32'h0000_0000);
      axi_read(REG_STATUS, rd_value);
      check_equal("Q-SIM-14 split-pattern final STATUS", rd_value, 32'h0000_0000);
      axi_read(REG_FAULT_CODE, rd_value);
      check_equal("Q-SIM-14 split-pattern final FAULT_CODE", rd_value, 32'h0000_0000);
      if (dut.u_reg_controlled_top.u_reg_bank.pwm_enable || pwm_raw !== 1'b0 || pwm_out !== 1'b0)
        $fatal(1, "%s clear-only recovery did not keep PWM disabled", pattern_name);
    end
  endtask

  task automatic run_qsim11_axi_ctrl3_compatibility;
    begin
      $display("Q-SIM-11 AXI CTRL=0x3 compatibility characterization only");
      q_axi_reset("Q-SIM-11 AXI");
      q_axi_safe_setup();
      axi_write(REG_TH_OC1, 32'd1000);
      axi_write(REG_TH_OC2, 32'd1000);
      q_axi_make_overcurrent("Q-SIM-11 AXI");
      q_axi_remove_overcurrent("Q-SIM-11 AXI");
      q_axi_arm_target("Q-SIM-11 AXI compatibility characterization only", 32'h0000_0003, 1'b1, 1'b0);
      q_axi_issue_pattern(0, 32'h0000_0003);
      q_axi_wait_recovery_and_check("Q-SIM-11 AXI compatibility characterization only");
      axi_read(REG_CTRL, rd_value);
      check_equal("Q-SIM-11 AXI stored enable", rd_value, 32'h0000_0001);
      if (!dut.u_reg_controlled_top.u_reg_bank.pwm_enable || pwm_out !== pwm_raw)
        $fatal(1, "Q-SIM-11 AXI compatibility did not expose current pwm_raw phase after E5");
    end
  endtask

  initial begin
    $dumpfile("sim/waves/tb_protection_ip_top_axi_lite.vcd");
    $dumpvars(0, tb_protection_ip_top_axi_lite);

    wait_cycles(3);
    ARESETN = 1'b1;
    wait_cycles(4);

    axi_read(REG_STATUS, rd_value);
    check_equal("reset status", rd_value, 32'h0000_0000);
    axi_read(REG_FAULT_CODE, rd_value);
    check_equal("reset fault_code", rd_value, 32'h0000_0000);
    check_true("fault_latched should reset low", fault_latched == 1'b0);

    axi_read(`REG_REGISTER_MAP_VERSION, rd_value);
    check_equal("legacy path version discovery", rd_value, 32'h0000_0000);
    axi_read(`REG_CAPABILITIES_0, rd_value);
    check_equal("legacy path capabilities 0", rd_value, 32'h0000_0000);
    axi_read(`REG_CAPABILITIES_1, rd_value);
    check_equal("legacy path capabilities 1", rd_value, 32'h0000_0000);
    axi_read(`REG_POLICY_STATUS, rd_value);
    check_equal("legacy path policy status", rd_value, 32'h0000_0000);
    axi_read(`REG_FIRST_FAULT_BITMAP, rd_value);
    check_equal("legacy path first bitmap", rd_value, 32'h0000_0000);
    axi_read(`REG_LIVE_FAULT_BITMAP, rd_value);
    check_equal("legacy path live bitmap", rd_value, 32'h0000_0000);
    axi_read(`REG_FAULT_SEEN_BITMAP, rd_value);
    check_equal("legacy path seen bitmap", rd_value, 32'h0000_0000);
    axi_read(`REG_POLICY_EVALUATION_SEQUENCE, rd_value);
    check_equal("legacy path policy identity", rd_value, 32'h0000_0000);
    axi_write_strb(`REG_REGISTER_MAP_VERSION, 32'hFFFF_FFFF, 4'hF);
    axi_write_strb(`REG_POLICY_STATUS, 32'hFFFF_FFFF, 4'hF);
    axi_read(`REG_REGISTER_MAP_VERSION, rd_value);
    check_equal("legacy path discovery write ignored", rd_value, 32'h0000_0000);
    axi_read(`REG_POLICY_STATUS, rd_value);
    check_equal("legacy path policy write ignored", rd_value, 32'h0000_0000);

    $display("AXI contract: nonzero WSTRB writes the addressed register as a full word; WSTRB=0 does not write");
    $display("AXI contract: unmapped addresses return OKAY; writes are ignored and reads return zero");

    axi_write_strb(REG_TH_OC1, 32'h0000_0A23, 4'b1111);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("full WSTRB baseline write/read", rd_value, 32'h0000_0A23);

    axi_write_strb(REG_TH_OC1, 32'h0000_0A11, 4'b0001);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("partial WSTRB 0001 writes full low field", rd_value, 32'h0000_0A11);
    axi_write_strb(REG_TH_OC1, 32'h0000_0A22, 4'b0010);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("partial WSTRB 0010 writes full low field", rd_value, 32'h0000_0A22);
    axi_write_strb(REG_TH_OC1, 32'h0000_0A33, 4'b0100);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("partial WSTRB 0100 writes full low field", rd_value, 32'h0000_0A33);
    axi_write_strb(REG_TH_OC1, 32'h0000_0A44, 4'b1000);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("partial WSTRB 1000 writes full low field", rd_value, 32'h0000_0A44);
    axi_write_strb(REG_TH_OC1, 32'h0000_0A55, 4'b0011);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("partial WSTRB 0011 writes full low field", rd_value, 32'h0000_0A55);
    axi_write_strb(REG_TH_OC1, 32'h0000_0A66, 4'b1100);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("partial WSTRB 1100 writes full low field", rd_value, 32'h0000_0A66);
    axi_write_strb(REG_TH_OC1, 32'h0000_0A77, 4'b1111);
    axi_write_strb(REG_TH_OC1, 32'h0000_0123, 4'b0000);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("WSTRB 0000 must not update register", rd_value, 32'h0000_0A77);

    axi_write(REG_TH_OC2, 32'h0000_0888);
    axi_write_strb(8'hFC, 32'hFFFF_FFFF, 4'b1111);
    axi_read(REG_TH_OC2, rd_value);
    check_equal("illegal address write must not disturb TH_OC2", rd_value, 32'h0000_0888);
    axi_read(8'hFC, rd_value);
    check_equal("illegal address read returns zero", rd_value, 32'h0000_0000);

    axi_write_aw_then_w(REG_TH_DIFF, 32'h0000_0099, 4'b1111, 2);
    axi_read(REG_TH_DIFF, rd_value);
    check_equal("AW-before-W write readback", rd_value, 32'h0000_0099);
    axi_write_w_then_aw(REG_TH_DIFF, 32'h0000_00AA, 4'b1111, 2);
    axi_read(REG_TH_DIFF, rd_value);
    check_equal("W-before-AW write readback", rd_value, 32'h0000_00AA);
    axi_write_hold_bready(REG_PWM_PERIOD, 32'd12, 4'b1111, 3);
    axi_read(REG_PWM_PERIOD, rd_value);
    check_equal("BREADY hold write commits", rd_value, 32'd12);
    axi_read_hold_rready(REG_PWM_PERIOD, rd_value, 3);
    check_equal("RREADY hold readback", rd_value, 32'd12);

    axi_write(REG_TH_OC1, 32'd2100);
    axi_write(REG_TH_OC2, 32'd2200);
    axi_write(REG_TH_DIFF, 32'd123);
    axi_write(REG_PWM_PERIOD, 32'd10);
    axi_write(REG_PWM_DUTY, 32'd5);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("consecutive read TH_OC1", rd_value, 32'd2100);
    axi_read(REG_TH_OC2, rd_value);
    check_equal("consecutive read TH_OC2", rd_value, 32'd2200);
    axi_read(REG_TH_DIFF, rd_value);
    check_equal("consecutive read TH_DIFF", rd_value, 32'd123);
    axi_read(REG_PWM_PERIOD, rd_value);
    check_equal("consecutive read PWM_PERIOD", rd_value, 32'd10);
    axi_read(REG_PWM_DUTY, rd_value);
    check_equal("consecutive read PWM_DUTY", rd_value, 32'd5);

    axi_write(REG_PWM_PERIOD, 32'd8);
    axi_write(REG_PWM_DUTY, 32'd4);
    axi_write(REG_CTRL, 32'h0000_0001);
    wait_cycles(8);
    measure_pwm(32, high_count, rise_count);
    check_true("normal input should allow PWM output", high_count > 0);
    check_true("normal input should make PWM toggle", rise_count > 0);

    i_ch1 = 12'd1500;
    i_ch2 = 12'd1500;
    axi_write(REG_TH_OC1, 32'd2000);
    axi_write(REG_TH_OC2, 32'd2000);
    wait_cycles(8);
    check_true("AXI high threshold should avoid fault on same current", fault_latched == 1'b0);

    axi_write(REG_TH_OC1, 32'd1000);
    axi_write(REG_TH_OC2, 32'd1000);
    q_axi_sample(12'd1500, 12'd1500);
    wait_cycles(8);
    check_true("AXI low threshold should latch fault on same current", fault_latched == 1'b1);
    check_equal("overcurrent fault code", {24'd0, fault_code_latched}, {24'd0, `FAULT_OVERCURRENT});
    @(negedge ACLK);
    sample_valid = 1'b1;
    axi_write(REG_CTRL, 32'h0000_0003);
    wait_cycles(6);
    check_true("AXI clear_fault must not release protection while current is still over threshold", fault_latched == 1'b1);
    check_equal("fault code must remain latched while clear is blocked by active overcurrent", {24'd0, fault_code_latched}, {24'd0, `FAULT_OVERCURRENT});
    measure_pwm(16, high_count, rise_count);
    check_equal("PWM must remain forced low when AXI clear_fault is issued during active fault", high_count, 32'd0);

    @(negedge ACLK);
    sample_valid = 1'b0;
    q_axi_sample(12'd500, 12'd510);
    q_axi_wait_live_low("AXI active fault removal");
    axi_write(REG_CTRL, 32'h0000_0003);
    wait_cycles(10);
    check_true("clear_fault should recover before readback scenario", fault_latched == 1'b0);

    axi_write(REG_TH_OC1, 32'd2500);
    axi_write(REG_TH_OC2, 32'd2400);
    axi_write(REG_PWM_PERIOD, 32'd8);
    axi_write(REG_PWM_DUTY, 32'd2);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("AXI ch1 threshold readback", rd_value, 32'd2500);
    axi_read(REG_TH_OC2, rd_value);
    check_equal("AXI ch2 threshold readback", rd_value, 32'd2400);
    axi_read(REG_PWM_PERIOD, rd_value);
    check_equal("AXI PWM period readback", rd_value, 32'd8);
    axi_read(REG_PWM_DUTY, rd_value);
    check_equal("AXI PWM duty readback", rd_value, 32'd2);
    axi_read(REG_I_CH1, rd_value);
    check_equal("AXI current monitor ch1", rd_value, 32'd500);
    axi_read(REG_I_CH2, rd_value);
    check_equal("AXI current monitor ch2", rd_value, 32'd510);

    i_ch1 = 12'd2600;
    i_ch2 = 12'd2600;
    q_axi_sample(12'd2600, 12'd2600);
    wait_cycles(8);
    check_true("overcurrent should latch through AXI wrapper", fault_latched == 1'b1);
    axi_read(REG_STATUS, rd_value);
    check_true("AXI status should show fault_latched", rd_value[1] == 1'b1);
    axi_read(REG_FAULT_CODE, rd_value);
    check_equal("AXI fault_code after overcurrent", rd_value, {24'd0, `FAULT_OVERCURRENT});
    axi_read_hold_rready(REG_STATUS, rd_value, 3);
    check_true("AXI status readback stable under RREADY hold", rd_value[1] == 1'b1);
    axi_read_hold_rready(REG_FAULT_CODE, rd_value, 3);
    check_equal("AXI fault_code readback stable under RREADY hold", rd_value, {24'd0, `FAULT_OVERCURRENT});
    measure_pwm(24, high_count, rise_count);
    check_equal("PWM should be forced low during fault", high_count, 32'd0);

    i_ch1 = 12'd500;
    i_ch2 = 12'd510;
    axi_write(REG_CTRL, 32'h0000_0003);
    wait_cycles(10);
    check_true("AXI clear_fault should clear latched fault", fault_latched == 1'b0);
    check_equal("AXI clear_fault should clear code", {24'd0, fault_code_latched}, 32'd0);
    measure_pwm(32, high_count, rise_count);
    check_true("PWM should resume after AXI clear_fault", high_count > 0);

    axi_write(REG_TH_OC1, 32'd3000);
    axi_write(REG_TH_OC2, 32'd3000);
    axi_write(REG_PWM_PERIOD, 32'd8);
    axi_write(REG_PWM_DUTY, 32'd2);
    wait_cycles(16);
    measure_pwm(96, fast_high_count, fast_rise_count);

    axi_write(REG_PWM_PERIOD, 32'd16);
    axi_write(REG_PWM_DUTY, 32'd8);
    wait_cycles(16);
    measure_pwm(96, slow_high_count, slow_rise_count);
    check_true("AXI PWM duty update should increase high-time", slow_high_count > fast_high_count);
    check_true("AXI PWM period update should reduce rising edges", fast_rise_count > slow_rise_count);

    i_ch1 = 12'd100;
    i_ch2 = 12'd110;
    axi_write(REG_TH_OC1, 32'h0000_0100);
    axi_write(REG_TH_OC2, 32'd3000);
    axi_read(REG_TH_OC1, rd_value);
    check_equal("scenario 7 baseline ch1 threshold", rd_value, 32'h0000_0100);

    @(negedge ACLK);
    S_AXI_AWADDR = REG_PWM_PERIOD;
    S_AXI_AWVALID = 1'b1;
    S_AXI_WDATA = 32'd32;
    S_AXI_WSTRB = 4'hF;
    S_AXI_WVALID = 1'b1;
    S_AXI_BREADY = 1'b0;

    overlap_guard = 0;
    while (!(S_AXI_AWREADY && S_AXI_WREADY)) begin
      @(posedge ACLK);
      overlap_guard = overlap_guard + 1;
      if (overlap_guard > 20) begin
        $display("FAIL: scenario 7 write handshake timeout");
        $fatal(1);
      end
    end

    @(posedge ACLK);
    #1;
    S_AXI_AWVALID = 1'b0;
    S_AXI_WVALID = 1'b0;
    S_AXI_WSTRB = 4'h0;

    @(negedge ACLK);
    S_AXI_ARADDR = REG_TH_OC1;
    S_AXI_ARVALID = 1'b1;
    S_AXI_RREADY = 1'b0;
    #1;
    check_true("scenario 7 read should stall during write apply", S_AXI_ARREADY == 1'b0);

    @(posedge ACLK);
    #1;
    check_true("scenario 7 write should be waiting for BREADY", S_AXI_BVALID == 1'b1);
    check_true("scenario 7 read should stall while write response waits", S_AXI_ARREADY == 1'b0);

    S_AXI_BREADY = 1'b1;
    @(posedge ACLK);
    #1;
    S_AXI_BREADY = 1'b0;

    overlap_guard = 0;
    while (!S_AXI_ARREADY) begin
      @(posedge ACLK);
      #1;
      overlap_guard = overlap_guard + 1;
      if (overlap_guard > 20) begin
        $display("FAIL: scenario 7 read did not resume after write response");
        $fatal(1);
      end
    end

    @(posedge ACLK);
    #1;
    S_AXI_ARVALID = 1'b0;
    S_AXI_RREADY = 1'b1;

    overlap_guard = 0;
    while (!S_AXI_RVALID) begin
      @(posedge ACLK);
      #1;
      overlap_guard = overlap_guard + 1;
      if (overlap_guard > 20) begin
        $display("FAIL: scenario 7 read data timeout");
        $fatal(1);
      end
    end

    rd_value = S_AXI_RDATA;
    check_equal("scenario 7 readback should keep ch1 threshold address", rd_value, 32'h0000_0100);
    check_equal("scenario 7 RRESP", {30'd0, S_AXI_RRESP}, 32'd0);
    @(posedge ACLK);
    #1;
    S_AXI_RREADY = 1'b0;
    S_AXI_ARADDR = 8'h00;
    S_AXI_WDATA = 32'h0;

    axi_read(REG_PWM_PERIOD, rd_value);
    check_equal("scenario 7 overlapping write should still update pwm_period", rd_value, 32'd32);
    $display("SCENARIO 7 PASS: AXI read/write near-overlap conservative arbitration");

    run_reset_during_transaction_tests();
    run_axi_lite_persistent_sensor_stuck_clear_only();
    run_enh_axi_safe_normal_clear();
    run_qsim03_qsim10_qsim14_same_cycle();
    run_qsim14_split_pattern(1, "Q-SIM-14 AW-before-W");
    run_qsim14_split_pattern(2, "Q-SIM-14 W-before-AW");
    run_qsim11_axi_ctrl3_compatibility();

    $display("ALL TESTS PASSED: tb_protection_ip_top_axi_lite");
    $finish;
  end
endmodule
