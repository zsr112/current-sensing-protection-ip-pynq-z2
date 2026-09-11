`timescale 1ns/1ps
// Audit characterization, outside the immutable delivery. No vendor/board claim.
module tb_runtime_boundary;
  reg clk=0, rst_n=1, valid=0, clean=1;
  reg [11:0] ch1=1024, ch2=1025;
  reg [31:0] seq=0;
  wire pwm_out, latched;
  wire [3:0] state;
  integer high_count=0;
  always #5 clk=~clk;
  stage2g_protection_core dut(
    .clk(clk), .rst_n(rst_n), .sample_valid(valid), .sample_sequence(seq),
    .sample_source_integrity_clean(clean), .sample_destination_integrity_clean(1'b1),
    .pwm_enable(1'b1), .clear_fault(1'b0), .i_ch1(ch1), .i_ch2(ch2),
    .th_oc_ch1(12'd3000), .th_oc_ch2(12'd3000), .th_diff(12'd200),
    .th_open(12'd0), .th_sat(12'd4095), .th_stuck_delta(12'd0), .th_persist(8'd255),
    .period(16'd1000), .duty(16'd500), .pwm_out(pwm_out),
    .fault_latched(latched), .fsm_state(state)
  );
  initial begin
    #1 rst_n=0;
    repeat(5) @(negedge clk);
    rst_n=1;
    repeat(5) @(negedge clk);
    if(state!==2 || pwm_out!==0) $fatal(1,"startup safe hold missing");
    valid=1;
    @(negedge clk); valid=0; seq=1;
    repeat(8) @(negedge clk);
    if(state!==0 || latched!==0) $fatal(1,"not armed by healthy sample");
    repeat(10000) begin
      @(negedge clk);
      high_count=high_count+pwm_out;
      if(state!==0 || latched!==0) $fatal(1,"unexpected state change while idle");
    end
    if(high_count!=5000) $fatal(1,"unexpected PWM observation %d",high_count);
    $display("ARMED_NO_SAMPLE_10000_ACLK: state=ARMED pwm_high_cycles=%0d (no hardware sample timeout)",high_count);
    clean=0; ch1=3500; ch2=3500; valid=1;
    @(negedge clk); valid=0; seq=2;
    repeat(8) @(negedge clk);
    if(state!==0 || latched!==0) $fatal(1,"dirty evaluation unexpectedly latched");
    $display("DIRTY_OVERCURRENT_EVALUATION: state=ARMED fault_latched=0 (integrity rejection does not trip)");
    clean=1; valid=1;
    @(negedge clk); valid=0;
    repeat(8) @(negedge clk);
    if(state!==1 || latched!==1 || pwm_out!==0) $fatal(1,"clean overcurrent did not latch");
    $display("CLEAN_OVERCURRENT_EVALUATION: state=FAULT_LATCHED pwm_out=0");
    $display("RUNTIME_BOUNDARY_CHARACTERIZATION=PASS");
    $finish;
  end
endmodule
