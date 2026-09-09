`timescale 1ns/1ps
module tb_pwm_gen;
  reg clk = 0, rst_n = 0, enable = 0;
  reg [7:0] period = 8'd10, duty = 8'd4;
  wire pwm_raw;
  integer high_count, low_count;

  always #5 clk = ~clk;

  pwm_gen #(.CNT_WIDTH(8)) dut(
    .clk(clk), .rst_n(rst_n), .enable(enable), .period(period), .duty(duty), .pwm_raw(pwm_raw)
  );

  task measure_pwm(input [7:0] p, input [7:0] d, input integer cycles);
    begin
      @(negedge clk);
      enable = 1'b0;
      period = p;
      duty = d;
      repeat (2) begin
        @(posedge clk);
        #1;
      end

      @(negedge clk);
      enable = 1'b1;
      high_count = 0;
      low_count = 0;
      repeat (cycles) begin
        @(posedge clk);
        #1;
        if (pwm_raw)
          high_count = high_count + 1;
        else
          low_count = low_count + 1;
      end
    end
  endtask

  initial begin
    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    measure_pwm(8'd10, 8'd4, 30);
    if (high_count < 10 || high_count > 14)
      $fatal(1, "PWM normal high-count outside expected range: high=%0d low=%0d", high_count, low_count);

    @(negedge clk);
    enable = 1'b0;
    repeat (3) begin
      @(posedge clk);
      #1;
    end
    if (pwm_raw !== 1'b0)
      $fatal(1, "PWM must be low when disabled");

    measure_pwm(8'd0, 8'd4, 8);
    if (high_count !== 0 || low_count !== 8)
      $fatal(1, "PWM must be low when period is zero: high=%0d low=%0d", high_count, low_count);

    measure_pwm(8'd10, 8'd0, 20);
    if (high_count !== 0 || low_count !== 20)
      $fatal(1, "PWM must be low when duty is zero: high=%0d low=%0d", high_count, low_count);

    measure_pwm(8'd10, 8'd10, 20);
    if (high_count !== 20 || low_count !== 0)
      $fatal(1, "PWM must clamp duty equal to period as always-high: high=%0d low=%0d", high_count, low_count);

    measure_pwm(8'd10, 8'd15, 20);
    if (high_count !== 20 || low_count !== 0)
      $fatal(1, "PWM must clamp duty greater than period as always-high: high=%0d low=%0d", high_count, low_count);

    $display("tb_pwm_gen PASS");
    $finish;
  end
endmodule
