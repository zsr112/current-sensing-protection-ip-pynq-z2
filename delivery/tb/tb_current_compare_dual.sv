`timescale 1ns/1ps
module tb_current_compare_dual;
  reg [11:0] i1, i2, th1, th2, thd;
  wire oc1, oc2, oc_any, oc_both, mismatch;
  wire [11:0] abs_diff;

  current_compare_dual dut(
    .i_ch1(i1), .i_ch2(i2), .th_oc_ch1(th1), .th_oc_ch2(th2), .th_diff(thd),
    .oc_ch1(oc1), .oc_ch2(oc2), .oc_any(oc_any), .oc_both(oc_both),
    .mismatch_flag(mismatch), .abs_diff(abs_diff)
  );

  task check(input string label, input exp_oc1, input exp_oc2, input exp_mismatch, input [11:0] exp_abs_diff);
    begin
      #1;
      if (oc1 !== exp_oc1 || oc2 !== exp_oc2 ||
          oc_any !== (exp_oc1 | exp_oc2) ||
          oc_both !== (exp_oc1 & exp_oc2) ||
          mismatch !== exp_mismatch ||
          abs_diff !== exp_abs_diff) begin
        $fatal(1,
          "%s failed: oc1=%0b oc2=%0b oc_any=%0b oc_both=%0b mismatch=%0b abs_diff=%0d",
          label, oc1, oc2, oc_any, oc_both, mismatch, abs_diff);
      end
    end
  endtask

  initial begin
    th1 = 12'd1000;
    th2 = 12'd1000;
    thd = 12'd100;

    i1 = 12'd999;  i2 = 12'd950;  check("below threshold", 1'b0, 1'b0, 1'b0, 12'd49);
    i1 = 12'd1000; i2 = 12'd900;  check("equal threshold is not OC", 1'b0, 1'b0, 1'b0, 12'd100);
    i1 = 12'd1001; i2 = 12'd950;  check("strictly above threshold trips ch1", 1'b1, 1'b0, 1'b0, 12'd51);
    i1 = 12'd920;  i2 = 12'd1101; check("strictly above threshold trips ch2 and mismatch", 1'b0, 1'b1, 1'b1, 12'd181);
    i1 = 12'd1200; i2 = 12'd1300; check("dual OC with diff equal threshold", 1'b1, 1'b1, 1'b0, 12'd100);
    i1 = 12'd1200; i2 = 12'd1301; check("dual OC with diff above threshold", 1'b1, 1'b1, 1'b1, 12'd101);

    th1 = 12'd1500;
    th2 = 12'd1600;
    i1 = 12'd1400; i2 = 12'd1500; check("updated thresholds below", 1'b0, 1'b0, 1'b0, 12'd100);
    i1 = 12'd1501; i2 = 12'd1601; check("updated thresholds above", 1'b1, 1'b1, 1'b0, 12'd100);

    $display("tb_current_compare_dual PASS");
    $finish;
  end
endmodule
