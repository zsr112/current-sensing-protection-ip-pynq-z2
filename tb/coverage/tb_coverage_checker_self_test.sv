`timescale 1ns/1ps

module coverage_checker_self_test_case #(
  parameter logic CHECK_VALUE = 1'b1,
  parameter string CASE_NAME = "TRUE_CASE",
  parameter logic EXPECT_PASS = 1'b1
);
  task automatic check_true(input string label, input logic condition);
    begin
      if (condition !== 1'b1)
        $fatal(1, "FUNCTIONAL COVERAGE CHECK FAILED: %s", label);
    end
  endtask

  initial begin
    if (EXPECT_PASS) begin
      check_true(CASE_NAME, CHECK_VALUE);
      $display("%s=PASS", CASE_NAME);
    end else begin
      $display("%s=EXPECTED_FAIL", CASE_NAME);
      check_true(CASE_NAME, CHECK_VALUE);
      $display("%s=UNEXPECTED_PASS", CASE_NAME);
    end
    $finish;
  end
endmodule

module tb_coverage_checker_self_test_true;
  coverage_checker_self_test_case #(
    .CHECK_VALUE(1'b1),
    .CASE_NAME("TRUE_CASE"),
    .EXPECT_PASS(1'b1)
  ) test_case ();
endmodule

module tb_coverage_checker_self_test_false;
  coverage_checker_self_test_case #(
    .CHECK_VALUE(1'b0),
    .CASE_NAME("FALSE_CASE"),
    .EXPECT_PASS(1'b0)
  ) test_case ();
endmodule

module tb_coverage_checker_self_test_x;
  coverage_checker_self_test_case #(
    .CHECK_VALUE(1'bx),
    .CASE_NAME("X_CASE"),
    .EXPECT_PASS(1'b0)
  ) test_case ();
endmodule

module tb_coverage_checker_self_test_z;
  coverage_checker_self_test_case #(
    .CHECK_VALUE(1'bz),
    .CASE_NAME("Z_CASE"),
    .EXPECT_PASS(1'b0)
  ) test_case ();
endmodule
