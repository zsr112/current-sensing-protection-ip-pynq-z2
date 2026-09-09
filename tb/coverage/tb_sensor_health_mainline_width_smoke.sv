`timescale 1ns/1ps
`include "fault_defs.vh"

module tb_sensor_health_mainline_width_smoke;
  localparam integer HEALTH_CNT_WIDTH = 8;

  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic        sample_valid = 1'b0;
  logic [11:0] i_ch1 = 12'd500;
  logic [11:0] i_ch2 = 12'd550;
  wire         sensor_open_flag;
  wire         sensor_sat_flag;
  wire         sensor_stuck_flag;
  wire         fault_valid;
  wire [7:0]   fault_code;
  integer      no_wrap_paths_checked = 0;

  always #5 clk = ~clk;

  sensor_health_monitor #(
    .DATA_WIDTH(12),
    .CNT_WIDTH(HEALTH_CNT_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .sample_valid(sample_valid),
    .i_ch1(i_ch1),
    .i_ch2(i_ch2),
    .th_open(12'd0),
    .th_sat(12'hfff),
    .th_stuck_delta(12'd0),
    .th_persist(8'hff),
    .sensor_open_flag(sensor_open_flag),
    .sensor_sat_flag(sensor_sat_flag),
    .sensor_stuck_flag(sensor_stuck_flag)
  );

  fault_classifier classifier (
    .clk(clk),
    .rst_n(rst_n),
    .oc_any(1'b0),
    .oc_both(1'b0),
    .mismatch_flag(1'b0),
    .sensor_open_flag(sensor_open_flag),
    .sensor_sat_flag(sensor_sat_flag),
    .sensor_stuck_flag(sensor_stuck_flag),
    .fault_valid(fault_valid),
    .fault_code(fault_code)
  );

  task automatic check_true(input string label, input logic condition);
    begin
      if (condition !== 1'b1)
        $fatal(1, "8-BIT SENSOR HEALTH SMOKE CHECK FAILED: %s", label);
    end
  endtask

  task automatic sample_once(input logic [11:0] a, input logic [11:0] b);
    begin
      @(negedge clk);
      sample_valid = 1'b1;
      i_ch1 = a;
      i_ch2 = b;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic reset_dut;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      sample_valid = 1'b0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd550;
      repeat (2) @(posedge clk);
      #1;
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
      #1;
      check_true(
        "reset counters",
        dut.open_cnt === 8'h00 && dut.sat_cnt === 8'h00 &&
        dut.stuck_cnt === 8'h00
      );
      check_true(
        "reset status and fault",
        !sensor_open_flag && !sensor_sat_flag && !sensor_stuck_flag &&
        !fault_valid && fault_code === `FAULT_NONE
      );
    end
  endtask

  task automatic drive_open_samples(input integer count);
    integer n;
    begin
      for (n = 0; n < count; n = n + 1)
        sample_once(12'd0, ((n % 2) == 0) ? 12'd500 : 12'd503);
    end
  endtask

  task automatic drive_sat_samples(input integer count);
    integer n;
    begin
      for (n = 0; n < count; n = n + 1)
        sample_once(12'hfff, ((n % 2) == 0) ? 12'd500 : 12'd503);
    end
  endtask

  task automatic drive_stuck_samples(input integer count);
    integer n;
    begin
      for (n = 0; n < count; n = n + 1)
        sample_once(12'd500, 12'd550);
    end
  endtask

  task automatic check_recovery(input string label);
    begin
      sample_once(12'd600, 12'd650);
      sample_once(12'd610, 12'd660);
      check_true(
        {label, " counters and status recover"},
        dut.open_cnt === 8'h00 && dut.sat_cnt === 8'h00 &&
        dut.stuck_cnt === 8'h00 && !sensor_open_flag &&
        !sensor_sat_flag && !sensor_stuck_flag
      );
      sample_once(12'd620, 12'd670);
      check_true(
        {label, " classifier pipeline recovers"},
        !fault_valid && fault_code === `FAULT_NONE
      );
    end
  endtask

  initial begin
    reset_dut();
    drive_open_samples(255);
    check_true("open reaches 8'hff", dut.open_cnt === 8'hff);
    check_true("open status follows pre-update count", !sensor_open_flag && !fault_valid);
    sample_once(12'd0, 12'd503);
    check_true("open first extra update does not wrap", dut.open_cnt === 8'hff && sensor_open_flag);
    sample_once(12'd0, 12'd500);
    check_true(
      "open second extra update remains saturated with fault",
      dut.open_cnt === 8'hff && sensor_open_flag && fault_valid &&
      fault_code === `FAULT_SENSOR_OPEN
    );
    no_wrap_paths_checked = no_wrap_paths_checked + 1;
    $display("OPEN_COUNTER_SATURATION_NO_WRAP=PASS");
    check_recovery("open");

    reset_dut();
    drive_sat_samples(255);
    check_true("saturation reaches 8'hff", dut.sat_cnt === 8'hff);
    check_true("saturation status follows pre-update count", !sensor_sat_flag && !fault_valid);
    sample_once(12'hfff, 12'd503);
    check_true("saturation first extra update does not wrap", dut.sat_cnt === 8'hff && sensor_sat_flag);
    sample_once(12'hfff, 12'd500);
    check_true(
      "saturation second extra update remains saturated with fault",
      dut.sat_cnt === 8'hff && sensor_sat_flag && fault_valid &&
      fault_code === `FAULT_SENSOR_SATURATION
    );
    no_wrap_paths_checked = no_wrap_paths_checked + 1;
    $display("SAT_COUNTER_SATURATION_NO_WRAP=PASS");
    check_recovery("saturation");

    reset_dut();
    sample_once(12'd500, 12'd550);
    check_true("stuck priming sample is non-qualifying", dut.stuck_cnt === 8'h00);
    drive_stuck_samples(255);
    check_true("stuck reaches 8'hff", dut.stuck_cnt === 8'hff);
    check_true("stuck status follows pre-update count", !sensor_stuck_flag && !fault_valid);
    drive_stuck_samples(1);
    check_true("stuck first extra update does not wrap", dut.stuck_cnt === 8'hff && sensor_stuck_flag);
    drive_stuck_samples(1);
    check_true(
      "stuck second extra update remains saturated with fault",
      dut.stuck_cnt === 8'hff && sensor_stuck_flag && fault_valid &&
      fault_code === `FAULT_SENSOR_STUCK
    );
    no_wrap_paths_checked = no_wrap_paths_checked + 1;
    $display("STUCK_COUNTER_SATURATION_NO_WRAP=PASS");
    check_recovery("stuck");

    check_true("all 8-bit no-wrap paths", no_wrap_paths_checked == 3);
    $display("MAINLINE_PARAMETER_WIDTH=8");
    $display("EVIDENCE_CLASS=BEHAVIORAL_SMOKE_NOT_MAINLINE_INTEGRATION_COVERAGE");
    $display("SENSOR_HEALTH_MAINLINE_WIDTH=8");
    $display("SENSOR_HEALTH_8BIT_SMOKE=PASS_3_OF_3");
    $finish;
  end
endmodule
