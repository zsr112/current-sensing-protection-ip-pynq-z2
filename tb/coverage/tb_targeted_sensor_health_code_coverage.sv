`timescale 1ns/1ps

module tb_targeted_sensor_health_code_coverage;
  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic        sample_valid = 1'b0;
  logic [11:0] i_ch1 = 12'd500;
  logic [11:0] i_ch2 = 12'd550;
  logic [11:0] th_open = 12'd10;
  logic [11:0] th_sat = 12'd4090;
  logic [11:0] th_stuck_delta = 12'd0;
  logic [3:0]  th_persist = 4'd2;
  wire         sensor_open_flag;
  wire         sensor_sat_flag;
  wire         sensor_stuck_flag;
  integer      saturation_paths_checked = 0;

  always #5 clk = ~clk;

  sensor_health_monitor #(
    .DATA_WIDTH(12),
    .CNT_WIDTH(4)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .sample_valid(sample_valid),
    .i_ch1(i_ch1),
    .i_ch2(i_ch2),
    .th_open(th_open),
    .th_sat(th_sat),
    .th_stuck_delta(th_stuck_delta),
    .th_persist(th_persist),
    .sensor_open_flag(sensor_open_flag),
    .sensor_sat_flag(sensor_sat_flag),
    .sensor_stuck_flag(sensor_stuck_flag)
  );

  task automatic check_true(input string label, input logic condition);
    begin
      if (condition !== 1'b1)
        $fatal(1, "TARGETED SENSOR HEALTH CHECK FAILED: %s", label);
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

  task automatic reset_dut;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      sample_valid = 1'b0;
      i_ch1 = 12'd500;
      i_ch2 = 12'd550;
      wait_cycles(2);
      @(negedge clk);
      rst_n = 1'b1;
      wait_cycles(1);
      check_true("reset open counter", dut.open_cnt === 4'h0);
      check_true("reset saturation counter", dut.sat_cnt === 4'h0);
      check_true("reset stuck counter", dut.stuck_cnt === 4'h0);
      check_true(
        "reset flags",
        !sensor_open_flag && !sensor_sat_flag && !sensor_stuck_flag
      );
    end
  endtask

  task automatic drive_alternating(
    input [11:0] a0,
    input [11:0] b0,
    input [11:0] a1,
    input [11:0] b1,
    input integer count
  );
    integer n;
    begin
      @(negedge clk);
      sample_valid = 1'b1;
      for (n = 0; n < count; n = n + 1) begin
        if ((n % 2) == 0) begin
          i_ch1 = a0;
          i_ch2 = b0;
        end else begin
          i_ch1 = a1;
          i_ch2 = b1;
        end
        @(posedge clk);
        #1;
        @(negedge clk);
      end
      if ((count % 2) == 0) begin
        i_ch1 = a0;
        i_ch2 = b0;
      end else begin
        i_ch1 = a1;
        i_ch2 = b1;
      end
    end
  endtask

  task automatic drive_constant(
    input [11:0] a,
    input [11:0] b,
    input integer count
  );
    begin
      @(negedge clk);
      sample_valid = 1'b1;
      i_ch1 = a;
      i_ch2 = b;
      wait_cycles(count);
    end
  endtask

  initial begin
    reset_dut();

    // Invalid samples hold both counters and registered status.
    @(negedge clk);
    sample_valid = 1'b0;
    i_ch1 = 12'd0;
    i_ch2 = 12'd4095;
    wait_cycles(2);
    check_true("invalid sample holds counters", dut.open_cnt == 0 && dut.sat_cnt == 0 && dut.stuck_cnt == 0);
    check_true("invalid sample holds flags", !sensor_open_flag && !sensor_sat_flag && !sensor_stuck_flag);

    // Exercise each side of both-channel open/saturation conditions and the
    // mixed stable/not-stable condition before the saturation campaigns.
    drive_alternating(12'd5, 12'd500, 12'd6, 12'd503, 2);
    drive_alternating(12'd500, 12'd5, 12'd503, 12'd6, 2);
    drive_alternating(12'd4091, 12'd500, 12'd4092, 12'd503, 2);
    drive_alternating(12'd500, 12'd4091, 12'd503, 12'd4092, 2);
    drive_alternating(12'd500, 12'd550, 12'd500, 12'd553, 2);

    reset_dut();
    drive_alternating(12'd5, 12'd500, 12'd6, 12'd503, 17);
    check_true("open counter saturates", dut.open_cnt === 4'hf);
    check_true("open counter does not wrap", sensor_open_flag && dut.open_cnt === 4'hf);
    saturation_paths_checked = saturation_paths_checked + 1;
    @(negedge clk);
    sample_valid = 1'b0;
    wait_cycles(2);
    check_true("open counter holds while invalid", dut.open_cnt === 4'hf && sensor_open_flag);
    drive_alternating(12'd500, 12'd550, 12'd503, 12'd553, 2);
    check_true("open counter reset path", dut.open_cnt === 4'h0 && !sensor_open_flag);

    reset_dut();
    drive_alternating(12'd4091, 12'd500, 12'd4092, 12'd503, 17);
    check_true("saturation counter saturates", dut.sat_cnt === 4'hf);
    check_true("saturation counter does not wrap", sensor_sat_flag && dut.sat_cnt === 4'hf);
    saturation_paths_checked = saturation_paths_checked + 1;
    @(negedge clk);
    sample_valid = 1'b0;
    wait_cycles(2);
    check_true("saturation counter holds while invalid", dut.sat_cnt === 4'hf && sensor_sat_flag);
    drive_alternating(12'd500, 12'd550, 12'd503, 12'd553, 2);
    check_true("saturation counter reset path", dut.sat_cnt === 4'h0 && !sensor_sat_flag);

    reset_dut();
    drive_constant(12'd500, 12'd550, 18);
    check_true("stuck counter saturates", dut.stuck_cnt === 4'hf);
    check_true("stuck counter does not wrap", sensor_stuck_flag && dut.stuck_cnt === 4'hf);
    saturation_paths_checked = saturation_paths_checked + 1;
    @(negedge clk);
    sample_valid = 1'b0;
    wait_cycles(2);
    check_true("stuck counter holds while invalid", dut.stuck_cnt === 4'hf && sensor_stuck_flag);
    drive_alternating(12'd500, 12'd550, 12'd503, 12'd553, 3);
    check_true("stuck counter reset path", dut.stuck_cnt === 4'h0 && !sensor_stuck_flag);

    check_true("all saturation paths", saturation_paths_checked == 3);
    $display("TARGETED_SENSOR_HEALTH_CODE_COVERAGE PASS");
    $display("SENSOR_HEALTH_COUNTER_SATURATION_PATHS=PASS_3_OF_3");
    $finish;
  end
endmodule
