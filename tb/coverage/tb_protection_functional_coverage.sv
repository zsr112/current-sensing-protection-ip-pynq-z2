`timescale 1ns/1ps
`include "fault_defs.vh"

module tb_protection_functional_coverage;
  import protection_functional_coverage_pkg::*;

  localparam logic [7:0] REG_CTRL       = 8'h00;
  localparam logic [7:0] REG_STATUS     = 8'h04;
  localparam logic [7:0] REG_FAULT_CODE = 8'h08;
  localparam logic [7:0] REG_TH_OC1     = 8'h14;
  localparam logic [7:0] REG_TH_OC2     = 8'h18;
  localparam logic [7:0] REG_TH_DIFF    = 8'h1C;
  localparam logic [7:0] REG_PWM_PERIOD = 8'h20;
  localparam logic [7:0] REG_PWM_DUTY   = 8'h24;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // Direct core instance: configurable health thresholds are needed to
  // exercise FCG-01..08 without changing the frozen RTL wrappers.
  logic        core_rst_n = 1'b0;
  logic        core_sample_valid = 1'b0;
  logic        core_pwm_enable = 1'b0;
  logic        core_clear_fault = 1'b0;
  logic [11:0] core_i_ch1 = 12'd500;
  logic [11:0] core_i_ch2 = 12'd550;
  logic [11:0] core_th_oc1 = 12'd1000;
  logic [11:0] core_th_oc2 = 12'd1000;
  logic [11:0] core_th_diff = 12'd100;
  logic [11:0] core_th_open = 12'd10;
  logic [11:0] core_th_sat = 12'd4090;
  logic [11:0] core_th_stuck_delta = 12'd1;
  logic [3:0]  core_th_persist = 4'd2;
  logic [7:0]  core_pwm_period = 8'd8;
  logic [7:0]  core_pwm_duty = 8'd3;
  wire         core_pwm_raw;
  wire         core_pwm_out;
  wire         core_oc_any;
  wire         core_oc_both;
  wire         core_mismatch;
  wire         core_open;
  wire         core_sat;
  wire         core_stuck;
  wire         core_fault_valid;
  wire         core_fault_latched;
  wire [7:0]   core_fault_code;
  wire [7:0]   core_fault_code_latched;
  wire [3:0]   core_fsm_state;
  wire [11:0]  core_abs_diff;

  protection_core_top #(
    .DATA_WIDTH(12),
    .CNT_WIDTH(8),
    .HEALTH_CNT_WIDTH(4)
  ) core_dut (
    .clk(clk),
    .rst_n(core_rst_n),
    .sample_valid(core_sample_valid),
    .pwm_enable(core_pwm_enable),
    .clear_fault(core_clear_fault),
    .i_ch1(core_i_ch1),
    .i_ch2(core_i_ch2),
    .th_oc_ch1(core_th_oc1),
    .th_oc_ch2(core_th_oc2),
    .th_diff(core_th_diff),
    .th_open(core_th_open),
    .th_sat(core_th_sat),
    .th_stuck_delta(core_th_stuck_delta),
    .th_persist(core_th_persist),
    .period(core_pwm_period),
    .duty(core_pwm_duty),
    .pwm_raw(core_pwm_raw),
    .pwm_out(core_pwm_out),
    .oc_any(core_oc_any),
    .oc_both(core_oc_both),
    .mismatch_flag(core_mismatch),
    .sensor_open_flag(core_open),
    .sensor_sat_flag(core_sat),
    .sensor_stuck_flag(core_stuck),
    .fault_valid(core_fault_valid),
    .fault_latched(core_fault_latched),
    .fault_code(core_fault_code),
    .fault_code_latched(core_fault_code_latched),
    .fsm_state(core_fsm_state),
    .abs_diff(core_abs_diff)
  );

  // Independent AXI instance: register operations are legal AXI-Lite
  // transactions and never hierarchical force/deposit operations.
  logic        axi_reset_n = 1'b0;
  logic        axi_sample_valid = 1'b0;
  logic [7:0]  axi_awaddr = 8'h00;
  logic        axi_awvalid = 1'b0;
  wire         axi_awready;
  logic [31:0] axi_wdata = 32'h0;
  logic [3:0]  axi_wstrb = 4'h0;
  logic        axi_wvalid = 1'b0;
  wire         axi_wready;
  wire [1:0]   axi_bresp;
  wire         axi_bvalid;
  logic        axi_bready = 1'b0;
  logic [7:0]  axi_araddr = 8'h00;
  logic        axi_arvalid = 1'b0;
  wire         axi_arready;
  wire [31:0]  axi_rdata;
  wire [1:0]   axi_rresp;
  wire         axi_rvalid;
  logic        axi_rready = 1'b0;
  logic [11:0] axi_i_ch1 = 12'd500;
  logic [11:0] axi_i_ch2 = 12'd550;
  wire         axi_pwm_raw;
  wire         axi_pwm_out;
  wire         axi_fault_valid;
  wire         axi_fault_latched;
  wire [7:0]   axi_fault_code;
  wire [7:0]   axi_fault_code_latched;
  wire [3:0]   axi_fsm_state;

  protection_ip_top_axi_lite axi_dut (
    .ACLK(clk),
    .ARESETN(axi_reset_n),
    .sample_valid(axi_sample_valid),
    .S_AXI_AWADDR(axi_awaddr),
    .S_AXI_AWVALID(axi_awvalid),
    .S_AXI_AWREADY(axi_awready),
    .S_AXI_WDATA(axi_wdata),
    .S_AXI_WSTRB(axi_wstrb),
    .S_AXI_WVALID(axi_wvalid),
    .S_AXI_WREADY(axi_wready),
    .S_AXI_BRESP(axi_bresp),
    .S_AXI_BVALID(axi_bvalid),
    .S_AXI_BREADY(axi_bready),
    .S_AXI_ARADDR(axi_araddr),
    .S_AXI_ARVALID(axi_arvalid),
    .S_AXI_ARREADY(axi_arready),
    .S_AXI_RDATA(axi_rdata),
    .S_AXI_RRESP(axi_rresp),
    .S_AXI_RVALID(axi_rvalid),
    .S_AXI_RREADY(axi_rready),
    .i_ch1(axi_i_ch1),
    .i_ch2(axi_i_ch2),
    .pwm_raw(axi_pwm_raw),
    .pwm_out(axi_pwm_out),
    .fault_valid(axi_fault_valid),
    .fault_latched(axi_fault_latched),
    .fault_code(axi_fault_code),
    .fault_code_latched(axi_fault_code_latched),
    .fsm_state(axi_fsm_state)
  );

  protection_functional_coverage_monitor coverage_monitor (
    .clk(clk),
    .rst_n(core_rst_n),
    .sample_valid(core_dut.accepted_sample_valid),
    .pwm_enable(core_pwm_enable),
    .clear_fault(core_clear_fault),
    .i_ch1(core_dut.accepted_ch1),
    .i_ch2(core_dut.accepted_ch2),
    .th_oc_ch1(core_th_oc1),
    .th_oc_ch2(core_th_oc2),
    .th_diff(core_th_diff),
    .th_open(core_th_open),
    .th_sat(core_th_sat),
    .th_stuck_delta(core_th_stuck_delta),
    .th_persist(core_th_persist),
    .pwm_raw(core_pwm_raw),
    .pwm_out(core_pwm_out),
    .oc_any(core_oc_any),
    .oc_both(core_oc_both),
    .mismatch_flag(core_mismatch),
    .classifier_oc_any(core_dut.classifier_oc_any),
    .classifier_oc_both(core_dut.classifier_oc_both),
    .classifier_mismatch(core_dut.classifier_mismatch_flag),
    .classifier_open(core_dut.classifier_sensor_open_flag),
    .classifier_sat(core_dut.classifier_sensor_sat_flag),
    .classifier_stuck(core_dut.classifier_sensor_stuck_flag),
    .sensor_open_flag(core_open),
    .sensor_sat_flag(core_sat),
    .sensor_stuck_flag(core_stuck),
    .fault_valid(core_fault_valid),
    .fault_latched(core_fault_latched),
    .fault_code(core_fault_code),
    .fault_code_latched(core_fault_code_latched),
    .fsm_state(core_fsm_state)
  );

  integer targeted_health_counter_saturation_paths = 0;

  task automatic check_true(input string label, input logic condition);
    begin
      if (condition !== 1'b1)
        $fatal(1, "FUNCTIONAL COVERAGE CHECK FAILED: %s", label);
    end
  endtask

  task automatic wait_cycles(input integer cycles);
    integer n;
    begin
      for (n = 0; n < cycles; n = n + 1) begin
        @(posedge clk);
        #1;
      end
    end
  endtask

  task automatic configure_core_nominal;
    begin
      core_sample_valid = 1'b0;
      core_pwm_enable = 1'b1;
      core_clear_fault = 1'b0;
      core_i_ch1 = 12'd500;
      core_i_ch2 = 12'd550;
      core_th_oc1 = 12'd1000;
      core_th_oc2 = 12'd1000;
      core_th_diff = 12'd100;
      core_th_open = 12'd10;
      core_th_sat = 12'd4090;
      core_th_stuck_delta = 12'd1;
      core_th_persist = 4'd2;
      core_pwm_period = 8'd8;
      core_pwm_duty = 8'd3;
    end
  endtask

  task automatic reset_core;
    begin
      @(negedge clk);
      core_rst_n = 1'b0;
      configure_core_nominal();
      wait_cycles(2);
      @(negedge clk);
      core_rst_n = 1'b1;
      wait_cycles(3);
    end
  endtask

  task automatic drive_core(input [11:0] a, input [11:0] b, input logic valid, input integer cycles);
    begin
      @(negedge clk);
      core_i_ch1 = a;
      core_i_ch2 = b;
      core_sample_valid = valid;
      wait_cycles(cycles);
    end
  endtask

  task automatic continuous_core_samples(input [11:0] a, input [11:0] b, input integer count);
    begin
      drive_core(a, b, 1'b1, count);
      @(negedge clk);
      core_sample_valid = 1'b0;
      wait_cycles(1);
    end
  endtask

  task automatic ramp_delta_one(input [11:0] a, input [11:0] b, input integer count);
    integer n;
    begin
      @(negedge clk);
      core_sample_valid = 1'b1;
      for (n = 0; n < count; n = n + 1) begin
        core_i_ch1 = a + n;
        core_i_ch2 = b + n;
        @(posedge clk);
        #1;
        @(negedge clk);
      end
      core_sample_valid = 1'b0;
      wait_cycles(1);
    end
  endtask

  task automatic drive_alternating_health(
    input [11:0] a0,
    input [11:0] b0,
    input [11:0] a1,
    input [11:0] b1,
    input integer count
  );
    integer n;
    begin
      @(negedge clk);
      core_sample_valid = 1'b1;
      for (n = 0; n < count; n = n + 1) begin
        if ((n % 2) == 0) begin
          core_i_ch1 = a0;
          core_i_ch2 = b0;
        end else begin
          core_i_ch1 = a1;
          core_i_ch2 = b1;
        end
        @(posedge clk);
        #1;
        @(negedge clk);
      end
      // Preload the next alternating value so a following task call cannot
      // introduce an unintended stable sample at the task boundary.
      if ((count % 2) == 0) begin
        core_i_ch1 = a0;
        core_i_ch2 = b0;
      end else begin
        core_i_ch1 = a1;
        core_i_ch2 = b1;
      end
      core_sample_valid = 1'b0;
      // Drain the final accepted transaction through the health stage before
      // the caller checks counters or begins an explicit gap.
      wait_cycles(1);
    end
  endtask

  task automatic check_fault_observables(
    input [7:0] expected_live_code,
    input [7:0] expected_latched_code,
    input string label
  );
    begin
      check_true({label, " fault_valid"}, core_fault_valid === 1'b1);
      check_true({label, " live code"}, core_fault_code === expected_live_code);
      check_true({label, " fault_latched"}, core_fault_latched === 1'b1);
      check_true({label, " retained code"}, core_fault_code_latched === expected_latched_code);
      check_true({label, " FAULT_LATCHED state"}, core_fsm_state === 4'd1);
      check_true({label, " PWM safe-low"}, core_pwm_out === 1'b0);
    end
  endtask

  task automatic check_health_flags(
    input logic expected_open,
    input logic expected_sat,
    input logic expected_stuck,
    input string label
  );
    begin
      check_true({label, " open flag"}, core_open === expected_open);
      check_true({label, " saturation flag"}, core_sat === expected_sat);
      check_true({label, " stuck flag"}, core_stuck === expected_stuck);
    end
  endtask

  task automatic exercise_health_gap_modes(
    input [11:0] a,
    input [11:0] b,
    input logic expected_open,
    input logic expected_sat,
    input logic expected_stuck,
    input string label
  );
    begin
      check_health_flags(expected_open, expected_sat, expected_stuck, {label, " before gap"});
      drive_core(a, b, 1'b0, 2);
      check_health_flags(expected_open, expected_sat, expected_stuck, {label, " invalid hold"});
      check_true({label, " invalid latch retained"}, core_fault_latched === 1'b1);
      check_true({label, " invalid PWM safe-low"}, core_pwm_out === 1'b0);
      drive_core(a, b, 1'b1, 1);
      wait_cycles(1);
      check_health_flags(expected_open, expected_sat, expected_stuck, {label, " after gap"});
      check_true({label, " after-gap latch retained"}, core_fault_latched === 1'b1);
      check_true({label, " after-gap PWM safe-low"}, core_pwm_out === 1'b0);
    end
  endtask

  task automatic mark_health_counter_saturation(
    input [1:0] counter_kind,
    input [7:0] expected_code,
    input string label
  );
    begin
      case (counter_kind)
        2'd0: begin
          check_true({label, " open counter held at max"}, core_dut.u_health.open_cnt === 4'hf);
          check_true({label, " open status asserted"}, core_open === 1'b1);
        end
        2'd1: begin
          check_true({label, " saturation counter held at max"}, core_dut.u_health.sat_cnt === 4'hf);
          check_true({label, " saturation status asserted"}, core_sat === 1'b1);
        end
        2'd2: begin
          check_true({label, " stuck counter held at max"}, core_dut.u_health.stuck_cnt === 4'hf);
          check_true({label, " stuck status asserted"}, core_stuck === 1'b1);
        end
        default:
          check_true({label, " defined counter kind"}, 1'b0);
      endcase
      check_fault_observables(expected_code, expected_code, label);
      targeted_health_counter_saturation_paths = targeted_health_counter_saturation_paths + 1;
    end
  endtask

  task automatic wait_for_latch(input [7:0] expected_code, input string label);
    integer guard;
    begin
      guard = 0;
      while (!core_fault_latched && guard < 20) begin
        wait_cycles(1);
        guard = guard + 1;
      end
      check_true({label, " fault_latched"}, core_fault_latched === 1'b1);
      check_true({label, " code"}, core_fault_code_latched === expected_code);
      check_true({label, " pwm safe-low"}, core_pwm_out === 1'b0);
    end
  endtask

  task automatic wait_for_live_fault_low(input string label);
    integer guard;
    begin
      guard = 0;
      while (core_fault_valid && guard < 20) begin
        wait_cycles(1);
        guard = guard + 1;
      end
      check_true({label, " fault_valid low"}, core_fault_valid === 1'b0);
    end
  endtask

  task automatic pulse_core_clear;
    begin
      @(negedge clk);
      core_clear_fault = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      core_clear_fault = 1'b0;
    end
  endtask

  task automatic wait_for_normal(input string label);
    integer guard;
    begin
      guard = 0;
      while (core_fsm_state != 4'd0 && guard < 20) begin
        wait_cycles(1);
        guard = guard + 1;
      end
      check_true({label, " normal"}, core_fsm_state === 4'd0);
      check_true({label, " latch cleared"}, core_fault_latched === 1'b0);
    end
  endtask

  task automatic mark_clear(
    input [2:0] outcome,
    input [7:0] expected_campaign_code
  );
    begin
      coverage_monitor.sample_clear_checked(outcome, expected_campaign_code);
    end
  endtask

  task automatic mark_retention(input [1:0] kind);
    begin
      coverage_monitor.sample_retention_checked(kind);
    end
  endtask

  task automatic remove_source_and_clear(input string label);
    begin
      drive_alternating_health(
        12'd500, 12'd550, 12'd503, 12'd553, 4
      );
      wait_for_live_fault_low(label);
      pulse_core_clear();
      wait_for_normal(label);
    end
  endtask

  task automatic drive_axi_idle;
    begin
      axi_awaddr = 8'h00;
      axi_awvalid = 1'b0;
      axi_wdata = 32'h0;
      axi_wstrb = 4'h0;
      axi_wvalid = 1'b0;
      axi_bready = 1'b0;
      axi_araddr = 8'h00;
      axi_arvalid = 1'b0;
      axi_rready = 1'b0;
    end
  endtask

  task automatic axi_write_strb(input [7:0] a, input [31:0] d, input [3:0] strb);
    integer guard;
    begin
      guard = 0;
      @(negedge clk);
      axi_awaddr = a;
      axi_awvalid = 1'b1;
      axi_wdata = d;
      axi_wstrb = strb;
      axi_wvalid = 1'b1;
      while (!(axi_awready && axi_wready)) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 20)
          $fatal(1, "AXI write handshake timeout addr=0x%02h", a);
      end
      @(posedge clk);
      #1;
      axi_awvalid = 1'b0;
      axi_wvalid = 1'b0;
      axi_wstrb = 4'h0;
      axi_bready = 1'b1;
      guard = 0;
      while (!axi_bvalid) begin
        @(posedge clk);
        #1;
        guard = guard + 1;
        if (guard > 20)
          $fatal(1, "AXI write response timeout addr=0x%02h", a);
      end
      check_true("AXI BRESP OKAY", axi_bresp == 2'b00);
      @(posedge clk);
      #1;
      axi_bready = 1'b0;
      axi_awaddr = 8'h00;
      axi_wdata = 32'h0;
    end
  endtask

  task automatic axi_write(input [7:0] a, input [31:0] d);
    begin
      axi_write_strb(a, d, 4'hF);
    end
  endtask

  task automatic axi_read(input [7:0] a, output [31:0] d);
    integer guard;
    begin
      guard = 0;
      @(negedge clk);
      axi_araddr = a;
      axi_arvalid = 1'b1;
      while (!axi_arready) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 20)
          $fatal(1, "AXI read address timeout addr=0x%02h", a);
      end
      @(posedge clk);
      #1;
      axi_arvalid = 1'b0;
      axi_rready = 1'b1;
      guard = 0;
      while (!axi_rvalid) begin
        @(posedge clk);
        #1;
        guard = guard + 1;
        if (guard > 20)
          $fatal(1, "AXI read data timeout addr=0x%02h", a);
      end
      d = axi_rdata;
      check_true("AXI RRESP OKAY", axi_rresp == 2'b00);
      @(posedge clk);
      #1;
      axi_rready = 1'b0;
      axi_araddr = 8'h00;
    end
  endtask

  task automatic mark_register_checked(
    input [3:0] operation,
    input [2:0] operation_class,
    input [1:0] effect,
    input [3:0] strobe,
    input string label,
    input logic behavior_proven
  );
    begin
      check_true(label, behavior_proven);
      coverage_monitor.sample_register_checked(
        operation,
        operation_class,
        effect,
        strobe,
        behavior_proven
      );
    end
  endtask

  task automatic reset_axi;
    begin
      @(negedge clk);
      axi_reset_n = 1'b0;
      axi_sample_valid = 1'b0;
      axi_i_ch1 = 12'd500;
      axi_i_ch2 = 12'd550;
      drive_axi_idle();
      wait_cycles(2);
      @(negedge clk);
      axi_reset_n = 1'b1;
      wait_cycles(3);
    end
  endtask

  logic [31:0] read_data;

  initial begin
    configure_core_nominal();
    drive_axi_idle();
    wait_cycles(2);
    reset_core();
    reset_axi();

    $display("FUNCTIONAL_COVERAGE_PILOT: round 1 canonical-scenario mapping");

    // FCG-06 disabled safe-low followed by healthy/enabled PWM behavior.
    core_pwm_enable = 1'b0;
    wait_cycles(3);
    check_true("disabled PWM safe-low", core_pwm_out === 1'b0);
    core_pwm_enable = 1'b1;
    wait_cycles(20);

    // FCG-02 below/equal/above boundaries with strict '>' behavior.
    core_th_persist = 4'hF;
    drive_core(12'd999, 12'd950, 1'b1, 2);
    check_true("below threshold no OC", !core_oc_any);
    drive_core(12'd1000, 12'd900, 1'b1, 2);
    check_true("equal OC and DIFF thresholds do not trip", !core_oc_any && !core_mismatch);
    drive_core(12'd900, 12'd1000, 1'b1, 2);
    check_true("CH2 equal threshold does not trip", !core_oc_any && !core_mismatch);
    drive_core(12'd1001, 12'd950, 1'b1, 1);
    wait_for_latch(`FAULT_OVERCURRENT, "CH1 overcurrent");
    mark_retention(FC_RET_FIRST_CAPTURED);

    // FCG-05 clear during a live fault remains safely latched.
    pulse_core_clear();
    wait_cycles(2);
    check_true("live clear rejected safely", core_fault_latched && core_pwm_out == 1'b0);
    mark_clear(FC_CLEAR_LIVE_REJECTED, `FAULT_OVERCURRENT);

    // FCG-07 a later different live code does not overwrite the first code.
    drive_core(12'd950, 12'd800, 1'b1, 4);
    check_true("later mismatch visible", core_fault_code == `FAULT_SENSOR_MISMATCH);
    check_true("first code retained", core_fault_code_latched == `FAULT_OVERCURRENT);
    mark_retention(FC_RET_LATER_NOT_OVERWRITE);

    drive_alternating_health(
      12'd500, 12'd550, 12'd503, 12'd553, 4
    );
    wait_for_live_fault_low("source removed without clear");
    check_true("latch retained without clear", core_fault_latched);
    mark_clear(FC_CLEAR_NO_CLEAR_RETAINED, `FAULT_OVERCURRENT);

    pulse_core_clear();
    check_true("legal clear enters RESET_WAIT", core_fsm_state == 4'd2);
    mark_clear(FC_CLEAR_LEGAL, `FAULT_OVERCURRENT);
    pulse_core_clear();
    check_true("repeated clear keeps RESET_WAIT safe", core_fsm_state == 4'd2 && core_pwm_out == 1'b0);
    mark_clear(FC_CLEAR_REPEATED, `FAULT_OVERCURRENT);
    wait_for_normal("recovery complete");
    mark_clear(FC_CLEAR_RECOVERY_COMPLETE, `FAULT_OVERCURRENT);
    wait_cycles(12);

    // A new first fault after recovery, this time originating on CH2.
    drive_core(12'd1000, 12'd1001, 1'b1, 1);
    wait_for_latch(`FAULT_OVERCURRENT, "CH2 overcurrent");
    mark_retention(FC_RET_NEW_AFTER_RECOVERY);
    remove_source_and_clear("CH2 recovery");

    // Mismatch-only and dual-overcurrent mappings.
    drive_core(12'd950, 12'd800, 1'b1, 1);
    wait_for_latch(`FAULT_SENSOR_MISMATCH, "mismatch only");
    remove_source_and_clear("mismatch recovery");
    drive_core(12'd1001, 12'd1002, 1'b1, 1);
    wait_for_latch(`FAULT_OVERCURRENT, "dual overcurrent");
    remove_source_and_clear("dual OC recovery");

    // FCG-08 open threshold equality and continuous-valid persistence.
    reset_core();
    core_th_oc1 = 12'hFFF;
    core_th_oc2 = 12'hFFF;
    core_th_diff = 12'hFFF;
    continuous_core_samples(12'd10, 12'd11, 6);
    wait_for_latch(`FAULT_SENSOR_OPEN, "sensor open");

    // Saturation threshold equality under a configuration that disables OC.
    reset_core();
    core_th_oc1 = 12'hFFF;
    core_th_oc2 = 12'hFFF;
    core_th_diff = 12'hFFF;
    continuous_core_samples(12'd4090, 12'd4089, 6);
    wait_for_latch(`FAULT_SENSOR_SATURATION, "sensor saturation");

    // Delta == stuck threshold is stable according to the RTL's <= contract.
    reset_core();
    core_th_oc1 = 12'hFFF;
    core_th_oc2 = 12'hFFF;
    core_th_diff = 12'hFFF;
    ramp_delta_one(12'd500, 12'd550, 7);
    wait_for_latch(`FAULT_SENSOR_STUCK, "sensor stuck");

    // Combined OC plus a sensor-style condition (mismatch is part of the
    // actual classifier condition) without inventing a new code.
    reset_core();
    drive_core(12'd0, 12'd1101, 1'b1, 4);
    wait_for_latch(`FAULT_OC_WITH_SENSOR, "OC with sensor condition");

    $display("FUNCTIONAL_COVERAGE_TARGETED: mismatch clear and retention closure");
    reset_core();
    core_th_persist = 4'hF;
    drive_core(12'd950, 12'd800, 1'b1, 2);
    wait_for_latch(`FAULT_SENSOR_MISMATCH, "targeted mismatch first fault");
    check_fault_observables(
      `FAULT_SENSOR_MISMATCH,
      `FAULT_SENSOR_MISMATCH,
      "targeted mismatch first capture"
    );
    mark_retention(FC_RET_FIRST_CAPTURED);

    pulse_core_clear();
    wait_cycles(2);
    check_fault_observables(
      `FAULT_SENSOR_MISMATCH,
      `FAULT_SENSOR_MISMATCH,
      "targeted mismatch live clear"
    );
    mark_clear(FC_CLEAR_LIVE_REJECTED, `FAULT_SENSOR_MISMATCH);

    drive_core(12'd1001, 12'd950, 1'b1, 3);
    check_fault_observables(
      `FAULT_OVERCURRENT,
      `FAULT_SENSOR_MISMATCH,
      "targeted mismatch later overcurrent"
    );
    mark_retention(FC_RET_LATER_NOT_OVERWRITE);

    drive_alternating_health(
      12'd500, 12'd550, 12'd503, 12'd553, 4
    );
    wait_for_live_fault_low("targeted mismatch source removal");
    check_true("targeted mismatch retained without clear", core_fault_latched === 1'b1);
    check_true("targeted mismatch no-clear PWM safe-low", core_pwm_out === 1'b0);
    mark_clear(FC_CLEAR_NO_CLEAR_RETAINED, `FAULT_SENSOR_MISMATCH);

    pulse_core_clear();
    check_true("targeted mismatch legal clear state", core_fsm_state === 4'd2);
    check_true("targeted mismatch legal clear latch", core_fault_latched === 1'b1);
    check_true("targeted mismatch legal clear PWM", core_pwm_out === 1'b0);
    mark_clear(FC_CLEAR_LEGAL, `FAULT_SENSOR_MISMATCH);
    pulse_core_clear();
    check_true("targeted mismatch repeated clear state", core_fsm_state === 4'd2);
    check_true("targeted mismatch repeated clear PWM", core_pwm_out === 1'b0);
    mark_clear(FC_CLEAR_REPEATED, `FAULT_SENSOR_MISMATCH);
    wait_for_normal("targeted mismatch recovery");
    check_true("targeted mismatch recovery code clear", core_fault_code_latched === `FAULT_NONE);
    mark_clear(FC_CLEAR_RECOVERY_COMPLETE, `FAULT_SENSOR_MISMATCH);

    drive_core(12'd950, 12'd800, 1'b1, 2);
    wait_for_latch(`FAULT_SENSOR_MISMATCH, "targeted mismatch recapture");
    mark_retention(FC_RET_NEW_AFTER_RECOVERY);
    check_fault_observables(
      `FAULT_SENSOR_MISMATCH,
      `FAULT_SENSOR_MISMATCH,
      "targeted mismatch new after recovery"
    );
    remove_source_and_clear("targeted mismatch final recovery");

    $display("FUNCTIONAL_COVERAGE_TARGETED: health retention, gaps, and saturation paths");
    reset_core();
    core_th_oc1 = 12'hfff;
    core_th_oc2 = 12'hfff;
    core_th_diff = 12'hfff;
    core_th_stuck_delta = 12'd0;
    drive_alternating_health(12'd5, 12'd500, 12'd6, 12'd503, 15);
    check_true("targeted open counter reached max", core_dut.u_health.open_cnt === 4'hf);
    wait_for_latch(`FAULT_SENSOR_OPEN, "targeted open first fault");
    mark_retention(FC_RET_FIRST_CAPTURED);
    drive_alternating_health(12'd5, 12'd500, 12'd6, 12'd503, 2);
    mark_health_counter_saturation(2'd0, `FAULT_SENSOR_OPEN, "targeted open saturation path");
    exercise_health_gap_modes(12'd6, 12'd503, 1'b1, 1'b0, 1'b0, "targeted open gap modes");

    core_th_oc2 = 12'd1000;
    drive_core(12'd5, 12'd1101, 1'b1, 3);
    check_fault_observables(
      `FAULT_OC_WITH_SENSOR,
      `FAULT_SENSOR_OPEN,
      "targeted health later combined fault"
    );
    mark_retention(FC_RET_LATER_NOT_OVERWRITE);

    core_th_oc2 = 12'hfff;
    drive_alternating_health(12'd500, 12'd550, 12'd503, 12'd553, 3);
    wait_for_live_fault_low("targeted open source removal");
    drive_core(12'd500, 12'd550, 1'b0, 1);
    check_health_flags(1'b0, 1'b0, 1'b0, "targeted cleared health hold");
    check_true("targeted health code retained without clear", core_fault_code_latched === `FAULT_SENSOR_OPEN);
    mark_clear(FC_CLEAR_NO_CLEAR_RETAINED, `FAULT_SENSOR_OPEN);
    pulse_core_clear();
    check_true("targeted health legal clear state", core_fsm_state === 4'd2);
    mark_clear(FC_CLEAR_LEGAL, `FAULT_SENSOR_OPEN);
    wait_for_normal("targeted health recovery");
    mark_clear(FC_CLEAR_RECOVERY_COMPLETE, `FAULT_SENSOR_OPEN);

    core_th_oc1 = 12'hfff;
    core_th_oc2 = 12'hfff;
    core_th_diff = 12'hfff;
    core_th_sat = 12'd4090;
    core_th_stuck_delta = 12'd0;
    drive_alternating_health(12'd4091, 12'd4080, 12'd4092, 12'd4082, 15);
    check_true("targeted saturation counter reached max", core_dut.u_health.sat_cnt === 4'hf);
    wait_for_latch(`FAULT_SENSOR_SATURATION, "targeted saturation new fault");
    mark_retention(FC_RET_NEW_AFTER_RECOVERY);
    drive_alternating_health(12'd4091, 12'd4080, 12'd4092, 12'd4082, 2);
    mark_health_counter_saturation(2'd1, `FAULT_SENSOR_SATURATION, "targeted saturation path");
    exercise_health_gap_modes(12'd4092, 12'd4082, 1'b0, 1'b1, 1'b0, "targeted saturation gap modes");

    reset_core();
    core_th_oc1 = 12'hfff;
    core_th_oc2 = 12'hfff;
    core_th_diff = 12'hfff;
    core_th_stuck_delta = 12'd0;
    drive_core(12'd500, 12'd550, 1'b1, 17);
    check_true("targeted stuck counter reached max", core_dut.u_health.stuck_cnt === 4'hf);
    drive_core(12'd500, 12'd550, 1'b1, 2);
    wait_for_latch(`FAULT_SENSOR_STUCK, "targeted stuck fault");
    mark_health_counter_saturation(2'd2, `FAULT_SENSOR_STUCK, "targeted stuck saturation path");
    exercise_health_gap_modes(12'd500, 12'd550, 1'b0, 1'b0, 1'b1, "targeted stuck gap modes");

    reset_core();
    core_th_oc1 = 12'hfff;
    core_th_oc2 = 12'hfff;
    core_th_diff = 12'hfff;
    core_th_stuck_delta = 12'd0;
    drive_alternating_health(12'd5, 12'd4091, 12'd6, 12'd4092, 6);
    wait_for_latch(`FAULT_SENSOR_SATURATION, "targeted multiple health status");
    check_health_flags(1'b1, 1'b1, 1'b0, "targeted multiple health status");
    exercise_health_gap_modes(12'd6, 12'd4092, 1'b1, 1'b1, 1'b0, "targeted multiple gap modes");

    reset_core();
    core_th_oc1 = 12'hfff;
    core_th_oc2 = 12'hfff;
    core_th_diff = 12'hfff;
    core_th_stuck_delta = 12'd0;
    drive_core(12'd500, 12'd550, 1'b1, 1);
    check_health_flags(1'b0, 1'b0, 1'b0, "targeted healthy sample before gap");
    drive_core(12'd500, 12'd550, 1'b0, 1);
    check_health_flags(1'b0, 1'b0, 1'b0, "targeted gap-start none");
    check_true("targeted healthy gap remains unlatched", core_fault_latched === 1'b0);

    check_true(
      "all sensor-health counter saturation paths checked",
      targeted_health_counter_saturation_paths == 3
    );
    $display("SENSOR_HEALTH_COUNTER_SATURATION_PATHS=PASS_3_OF_3");
    $display("FSM_TARGETED_BOUNDARY_CASES=PASS");
    $display("NEW_TARGETED_CHECKERS=PASS");

    $display("FUNCTIONAL_COVERAGE_PILOT: round 2 legal coverage-specific AXI scenarios");
    reset_axi();

    axi_write(REG_CTRL, 32'h0000_0000);
    axi_read(REG_CTRL, read_data);
    mark_register_checked(
      FC_REG_CTRL_DISABLED, FC_REG_CLASS_CONTROL, FC_REG_EFFECT_APPLIED, 4'hF,
      "CTRL disabled readback", read_data == 32'h0
    );

    axi_write(REG_CTRL, 32'h0000_0001);
    axi_read(REG_CTRL, read_data);
    mark_register_checked(
      FC_REG_ENABLE, FC_REG_CLASS_CONTROL, FC_REG_EFFECT_APPLIED, 4'hF,
      "CTRL enable readback", read_data == 32'h1
    );

    axi_write(REG_CTRL, 32'h0000_0002);
    axi_read(REG_CTRL, read_data);
    mark_register_checked(
      FC_REG_CLEAR_ONLY, FC_REG_CLASS_CONTROL, FC_REG_EFFECT_APPLIED, 4'hF,
      "clear-only does not retain enable", read_data == 32'h0
    );

    axi_write(REG_TH_OC1, 32'd1200);
    axi_read(REG_TH_OC1, read_data);
    mark_register_checked(
      FC_REG_TH_OC1, FC_REG_CLASS_THRESHOLD, FC_REG_EFFECT_APPLIED, 4'hF,
      "TH_OC1 write/read", read_data == 32'd1200
    );

    // Current RTL contract: any non-zero WSTRB applies the whole word.
    axi_write_strb(REG_TH_OC2, 32'd1300, 4'b0001);
    axi_read(REG_TH_OC2, read_data);
    mark_register_checked(
      FC_REG_TH_OC2, FC_REG_CLASS_THRESHOLD, FC_REG_EFFECT_APPLIED, 4'b0001,
      "TH_OC2 partial-WSTRB write/read", read_data == 32'd1300
    );
    mark_register_checked(
      FC_REG_WSTRB, FC_REG_CLASS_STROBE, FC_REG_EFFECT_APPLIED, 4'b0001,
      "partial WSTRB whole-word contract", read_data == 32'd1300
    );

    axi_write(REG_TH_DIFF, 32'd90);
    axi_read(REG_TH_DIFF, read_data);
    mark_register_checked(
      FC_REG_TH_DIFF, FC_REG_CLASS_THRESHOLD, FC_REG_EFFECT_APPLIED, 4'hF,
      "TH_DIFF write/read", read_data == 32'd90
    );

    axi_write(REG_PWM_PERIOD, 32'd12);
    axi_read(REG_PWM_PERIOD, read_data);
    mark_register_checked(
      FC_REG_PWM_PERIOD, FC_REG_CLASS_PWM_CONFIG, FC_REG_EFFECT_APPLIED, 4'hF,
      "PWM period write/read", read_data == 32'd12
    );

    axi_write(REG_PWM_DUTY, 32'd5);
    axi_read(REG_PWM_DUTY, read_data);
    mark_register_checked(
      FC_REG_PWM_DUTY, FC_REG_CLASS_PWM_CONFIG, FC_REG_EFFECT_APPLIED, 4'hF,
      "PWM duty write/read", read_data == 32'd5
    );

    axi_write_strb(REG_TH_OC1, 32'd2000, 4'b0000);
    axi_read(REG_TH_OC1, read_data);
    mark_register_checked(
      FC_REG_WSTRB, FC_REG_CLASS_STROBE, FC_REG_EFFECT_NO_EFFECT, 4'b0000,
      "zero WSTRB no write", read_data == 32'd1200
    );

    axi_read(REG_STATUS, read_data);
    mark_register_checked(
      FC_REG_STATUS_READ, FC_REG_CLASS_STATUS, FC_REG_EFFECT_OBSERVED, 4'h0,
      "healthy STATUS read", read_data[1:0] == 2'b00
    );
    axi_read(REG_FAULT_CODE, read_data);
    mark_register_checked(
      FC_REG_FAULT_READ, FC_REG_CLASS_FAULT, FC_REG_EFFECT_OBSERVED, 4'h0,
      "healthy FAULT_CODE read", read_data[7:0] == `FAULT_NONE
    );

    axi_write(8'hFC, 32'hFFFF_FFFF);
    axi_read(8'hFC, read_data);
    mark_register_checked(
      FC_REG_UNKNOWN, FC_REG_CLASS_UNKNOWN, FC_REG_EFFECT_NO_EFFECT, 4'hF,
      "unknown address reads zero", read_data == 32'h0
    );

    // Read STATUS and FAULT_CODE again with an actual threshold-driven fault.
    axi_sample_valid = 1'b1;
    axi_i_ch1 = 12'd1201;
    axi_i_ch2 = 12'd1200;
    wait_cycles(6);
    check_true("AXI instance threshold fault latched", axi_fault_latched);
    axi_read(REG_STATUS, read_data);
    mark_register_checked(
      FC_REG_STATUS_READ, FC_REG_CLASS_STATUS, FC_REG_EFFECT_OBSERVED, 4'h0,
      "fault STATUS read", read_data[1:0] == 2'b11
    );
    axi_read(REG_FAULT_CODE, read_data);
    mark_register_checked(
      FC_REG_FAULT_READ, FC_REG_CLASS_FAULT, FC_REG_EFFECT_OBSERVED, 4'h0,
      "fault code read", read_data[7:0] == `FAULT_OVERCURRENT
    );

    axi_i_ch1 = 12'd500;
    axi_i_ch2 = 12'd550;
    wait_cycles(4);
    axi_write(REG_CTRL, 32'h0000_0002);
    wait_cycles(8);
    check_true("AXI clear-only recovery", !axi_fault_latched);

    wait_cycles(3);
    coverage_monitor.report_summary();
    $display("FUNCTIONAL_COVERAGE_PILOT PASS");
    $finish;
  end
endmodule
