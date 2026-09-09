`timescale 1ns/1ps
`include "fault_defs.vh"
module tb_fault_classifier;
  reg clk = 0, rst_n = 0;
  reg oc_any = 0, oc_both = 0, mismatch = 0, open_f = 0, sat_f = 0, stuck_f = 0;
  wire fault_valid;
  wire [7:0] fault_code;

  always #5 clk = ~clk;

  fault_classifier dut(
    .clk(clk), .rst_n(rst_n), .oc_any(oc_any), .oc_both(oc_both), .mismatch_flag(mismatch),
    .sensor_open_flag(open_f), .sensor_sat_flag(sat_f), .sensor_stuck_flag(stuck_f),
    .fault_valid(fault_valid), .fault_code(fault_code));

  task automatic drive_case(input any_oc, input both_oc, input mm, input opn, input sat, input stuck);
    begin
      @(negedge clk);
      oc_any = any_oc;
      oc_both = both_oc;
      mismatch = mm;
      open_f = opn;
      sat_f = sat;
      stuck_f = stuck;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic check_case(input string label,
                            input any_oc, input both_oc, input mm, input opn, input sat, input stuck,
                            input exp_valid, input [7:0] exp_code);
    begin
      drive_case(any_oc, both_oc, mm, opn, sat, stuck);
      if (fault_valid !== exp_valid || fault_code !== exp_code) begin
        $fatal(1,
          "%s mismatch: valid=%0b code=0x%02h expected valid=%0b code=0x%02h inputs oc_any=%0b oc_both=%0b mismatch=%0b open=%0b sat=%0b stuck=%0b",
          label, fault_valid, fault_code, exp_valid, exp_code,
          any_oc, both_oc, mm, opn, sat, stuck);
      end
    end
  endtask

  task automatic apply_reset;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      oc_any = 1'b1;
      oc_both = 1'b1;
      mismatch = 1'b1;
      open_f = 1'b1;
      sat_f = 1'b1;
      stuck_f = 1'b1;
      @(posedge clk);
      #1;
      if (fault_valid !== 1'b0 || fault_code !== `FAULT_NONE)
        $fatal(1, "reset/default behavior failed: valid=%0b code=0x%02h", fault_valid, fault_code);
      @(negedge clk);
      rst_n = 1'b1;
      oc_any = 1'b0;
      oc_both = 1'b0;
      mismatch = 1'b0;
      open_f = 1'b0;
      sat_f = 1'b0;
      stuck_f = 1'b0;
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    repeat (2) @(posedge clk);
    apply_reset();

    $display("FAULT_CLASSIFIER contract: OC_WITH_SENSOR > OC > SATURATION > OPEN > STUCK > MISMATCH > NO_FAULT");
    $display("FAULT_CLASSIFIER contract: ch1-only and ch2-only overcurrent are indistinguishable here and both enter as oc_any=1, oc_both=0");

    check_case("no fault", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, `FAULT_NONE);
    check_case("mismatch only", 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, `FAULT_SENSOR_MISMATCH);
    check_case("open only", 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, `FAULT_SENSOR_OPEN);
    check_case("saturation only", 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, `FAULT_SENSOR_SATURATION);
    check_case("stuck only", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, `FAULT_SENSOR_STUCK);

    check_case("overcurrent ch1-only equivalent", 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, `FAULT_OVERCURRENT);
    check_case("overcurrent ch2-only equivalent", 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, `FAULT_OVERCURRENT);
    check_case("dual overcurrent", 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, `FAULT_OVERCURRENT);
    check_case("oc_both alone still maps to overcurrent", 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, `FAULT_OVERCURRENT);

    check_case("overcurrent plus mismatch", 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, `FAULT_OC_WITH_SENSOR);
    check_case("overcurrent plus open", 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, `FAULT_OC_WITH_SENSOR);
    check_case("overcurrent plus saturation", 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, `FAULT_OC_WITH_SENSOR);
    check_case("overcurrent plus stuck", 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, `FAULT_OC_WITH_SENSOR);
    check_case("overcurrent plus multiple health faults", 1'b1, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, `FAULT_OC_WITH_SENSOR);

    check_case("open plus saturation", 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, `FAULT_SENSOR_SATURATION);
    check_case("open plus stuck", 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, `FAULT_SENSOR_OPEN);
    check_case("saturation plus stuck", 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, `FAULT_SENSOR_SATURATION);
    check_case("mismatch plus saturation", 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, `FAULT_SENSOR_SATURATION);
    check_case("mismatch plus open", 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, `FAULT_SENSOR_OPEN);
    check_case("mismatch plus stuck", 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, `FAULT_SENSOR_STUCK);
    check_case("all sensor health faults", 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, `FAULT_SENSOR_SATURATION);
    check_case("all non-OC sensor indicators", 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, `FAULT_SENSOR_SATURATION);
    check_case("all faults active", 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, `FAULT_OC_WITH_SENSOR);

    apply_reset();
    check_case("post-reset no fault", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, `FAULT_NONE);

    $display("tb_fault_classifier PASS");
    $finish;
  end
endmodule
