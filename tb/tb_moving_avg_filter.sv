`timescale 1ns/1ps
module tb_moving_avg_filter;
  reg clk=0, rst_n=0, valid_in=0;
  reg [7:0] data_in=0;
  wire valid_out;
  wire [7:0] data_out;
  always #5 clk=~clk;
  moving_avg_filter #(.DATA_WIDTH(8), .WINDOW_LOG2(2)) dut(.clk(clk),.rst_n(rst_n),.valid_in(valid_in),.data_in(data_in),.valid_out(valid_out),.data_out(data_out));
  task push(input [7:0] v); begin @(negedge clk); data_in=v; valid_in=1; @(negedge clk); valid_in=0; end endtask
  initial begin
    repeat(2) @(posedge clk); rst_n=1;
    push(8'd4);  @(posedge clk); if (data_out !== 8'd4)  $fatal(1,"avg1 failed: %0d", data_out);
    push(8'd8);  @(posedge clk); if (data_out !== 8'd6)  $fatal(1,"avg2 failed: %0d", data_out);
    push(8'd12); @(posedge clk); if (data_out !== 8'd8)  $fatal(1,"avg3 failed: %0d", data_out);
    push(8'd16); @(posedge clk); if (data_out !== 8'd10) $fatal(1,"avg4 failed: %0d", data_out);
    push(8'd20); @(posedge clk); if (data_out !== 8'd14) $fatal(1,"rolling avg failed: %0d", data_out);
    $display("tb_moving_avg_filter PASS"); $finish;
  end
endmodule
