`timescale 1ns/1ps
module tb_sensor_health_monitor;
  reg clk = 0, rst_n = 0, sample_valid = 0;
  reg [11:0] i1 = 12'd1000, i2 = 12'd1000;
  wire open_f, sat_f, stuck_f;
  wire default_open_f, default_sat_f, default_stuck_f;

  always #5 clk = ~clk;

  sensor_health_monitor #(.DATA_WIDTH(12), .CNT_WIDTH(4)) dut(
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .i_ch1(i1), .i_ch2(i2),
    .th_open(12'd10), .th_sat(12'd4090), .th_stuck_delta(12'd1), .th_persist(4'd3),
    .sensor_open_flag(open_f), .sensor_sat_flag(sat_f), .sensor_stuck_flag(stuck_f));

  sensor_health_monitor #(.DATA_WIDTH(12), .CNT_WIDTH(4)) default_like_dut(
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .i_ch1(i1), .i_ch2(i2),
    .th_open(12'd0), .th_sat(12'hFFF), .th_stuck_delta(12'd0), .th_persist(4'hF),
    .sensor_open_flag(default_open_f), .sensor_sat_flag(default_sat_f), .sensor_stuck_flag(default_stuck_f));

  task automatic check_flags(input string label, input exp_open, input exp_sat, input exp_stuck);
    begin
      #1;
      if (open_f !== exp_open || sat_f !== exp_sat || stuck_f !== exp_stuck) begin
        $fatal(1,
          "%s mismatch: open=%0b sat=%0b stuck=%0b expected open=%0b sat=%0b stuck=%0b",
          label, open_f, sat_f, stuck_f, exp_open, exp_sat, exp_stuck);
      end
    end
  endtask

  task automatic check_default_like(input string label, input exp_open, input exp_sat, input exp_stuck);
    begin
      #1;
      if (default_open_f !== exp_open || default_sat_f !== exp_sat || default_stuck_f !== exp_stuck) begin
        $fatal(1,
          "%s default-like mismatch: open=%0b sat=%0b stuck=%0b expected open=%0b sat=%0b stuck=%0b",
          label, default_open_f, default_sat_f, default_stuck_f, exp_open, exp_sat, exp_stuck);
      end
    end
  endtask

  task automatic sample(input [11:0] a, input [11:0] b);
    begin
      @(negedge clk);
      i1 = a;
      i2 = b;
      sample_valid = 1'b1;
      @(negedge clk);
      sample_valid = 1'b0;
      #1;
    end
  endtask

  task automatic idle_cycles(input integer cycles);
    integer n;
    begin
      @(negedge clk);
      sample_valid = 1'b0;
      for (n = 0; n < cycles; n = n + 1)
        @(posedge clk);
      #1;
    end
  endtask

  task automatic apply_reset;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      sample_valid = 1'b0;
      i1 = 12'd1000;
      i2 = 12'd1010;
      @(posedge clk);
      #1;
      check_flags("reset clears health flags", 1'b0, 1'b0, 1'b0);
      check_default_like("reset clears default-like health flags", 1'b0, 1'b0, 1'b0);
      repeat (2) @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
      #1;
    end
  endtask

  task automatic clear_with_moving_normal(input string label);
    begin
      sample(12'd1000, 12'd1010);
      sample(12'd1005, 12'd1016);
      check_flags(label, 1'b0, 1'b0, 1'b0);
    end
  endtask

  initial begin
    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    $display("SENSOR_HEALTH contract: counters and flags update only on sample_valid");
    $display("SENSOR_HEALTH contract: flags compare the previous counter value, so assert/recover one valid sample after the counter boundary");

    sample(12'd1000, 12'd1010);
    sample(12'd1015, 12'd1020);
    sample(12'd1030, 12'd1040);
    check_flags("moving normal input should not flag", 1'b0, 1'b0, 1'b0);

    sample(12'd0, 12'd900);
    sample(12'd0, 12'd900);
    sample(12'd0, 12'd900);
    check_flags("open persist boundary not yet visible", 1'b0, 1'b0, 1'b0);
    sample(12'd0, 12'd900);
    check_flags("open fault visible after persistence boundary", 1'b1, 1'b0, 1'b0);
    sample(12'd1000, 12'd1010);
    check_flags("open and accumulated stuck remain for first valid recovery sample", 1'b1, 1'b0, 1'b1);
    sample(12'd1005, 12'd1016);
    check_flags("open fault recovers after valid normal samples", 1'b0, 1'b0, 1'b0);

    sample(12'd4095, 12'd4080);
    sample(12'd4095, 12'd4080);
    sample(12'd4095, 12'd4080);
    check_flags("saturation persist boundary not yet visible", 1'b0, 1'b0, 1'b0);
    sample(12'd4095, 12'd4080);
    check_flags("saturation fault visible after persistence boundary", 1'b0, 1'b1, 1'b0);
    sample(12'd1000, 12'd1010);
    check_flags("saturation and accumulated stuck remain for first valid recovery sample", 1'b0, 1'b1, 1'b1);
    sample(12'd1005, 12'd1016);
    check_flags("saturation fault recovers after valid normal samples", 1'b0, 1'b0, 1'b0);

    sample(12'd1500, 12'd1600);
    sample(12'd1501, 12'd1601);
    sample(12'd1502, 12'd1602);
    sample(12'd1503, 12'd1603);
    check_flags("delta <= stuck threshold not yet visible before boundary", 1'b0, 1'b0, 1'b0);
    sample(12'd1504, 12'd1604);
    check_flags("delta <= stuck threshold triggers stuck", 1'b0, 1'b0, 1'b1);
    sample(12'd1510, 12'd1610);
    check_flags("stuck flag remains for first moving recovery sample", 1'b0, 1'b0, 1'b1);
    sample(12'd1520, 12'd1620);
    check_flags("stuck fault recovers after delta > threshold samples", 1'b0, 1'b0, 1'b0);

    sample(12'd1800, 12'd1900);
    sample(12'd1800, 12'd1900);
    sample(12'd1800, 12'd1900);
    sample(12'd1800, 12'd1900);
    sample(12'd1800, 12'd1900);
    check_flags("stable normal current can be classified as stuck with aggressive thresholds", 1'b0, 1'b0, 1'b1);
    sample(12'd1810, 12'd1910);
    sample(12'd1820, 12'd1920);
    check_flags("stable-normal stuck classification clears after motion", 1'b0, 1'b0, 1'b0);

    sample(12'd2100, 12'd2200);
    sample(12'd2100, 12'd2200);
    idle_cycles(8);
    check_flags("sample_valid low does not advance stuck counter", 1'b0, 1'b0, 1'b0);
    sample(12'd2100, 12'd2200);
    check_flags("intermittent valid still below stuck visible boundary", 1'b0, 1'b0, 1'b0);
    sample(12'd2100, 12'd2200);
    sample(12'd2100, 12'd2200);
    check_flags("intermittent valid counts only valid samples toward stuck", 1'b0, 1'b0, 1'b1);
    sample(12'd2110, 12'd2210);
    sample(12'd2120, 12'd2220);
    check_flags("intermittent stuck scenario recovers", 1'b0, 1'b0, 1'b0);

    sample(12'd0, 12'd4095);
    sample(12'd0, 12'd4095);
    sample(12'd0, 12'd4095);
    sample(12'd0, 12'd4095);
    sample(12'd0, 12'd4095);
    check_flags("open saturation and stuck can assert together", 1'b1, 1'b1, 1'b1);

    rst_n = 1'b0;
    @(posedge clk);
    #1;
    check_flags("reset during health fault clears primary flags", 1'b0, 1'b0, 1'b0);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    clear_with_moving_normal("after reset moving normal remains clear");

    sample(12'd2000, 12'd2010);
    sample(12'd2000, 12'd2010);
    sample(12'd2000, 12'd2010);
    sample(12'd2000, 12'd2010);
    sample(12'd2000, 12'd2010);
    sample(12'd2000, 12'd2010);
    check_default_like("default-like max persist suppresses stuck in short bring-up run", 1'b0, 1'b0, 1'b0);

    apply_reset();
    sample(12'd1000, 12'd1010);
    check_flags("post-reset normal sample clear", 1'b0, 1'b0, 1'b0);

    $display("tb_sensor_health_monitor PASS");
    $finish;
  end
endmodule
