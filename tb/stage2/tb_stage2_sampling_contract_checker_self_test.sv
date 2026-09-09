`timescale 1ns/1ps

module stage2_contract_predicate_self_test_case #(
  parameter logic CHECK_VALUE = 1'b1,
  parameter string CASE_NAME = "TRUE_CASE",
  parameter logic EXPECT_PASS = 1'b1
);
  task automatic check_true(input string label, input logic condition);
    begin
      if (condition !== 1'b1)
        $fatal(1, "STAGE2 CONTRACT CHECK FAILED: %s", label);
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

module tb_stage2_checker_true;
  stage2_contract_predicate_self_test_case #(
    .CHECK_VALUE(1'b1), .CASE_NAME("TRUE_CASE"), .EXPECT_PASS(1'b1)
  ) test_case ();
endmodule

module tb_stage2_checker_false;
  stage2_contract_predicate_self_test_case #(
    .CHECK_VALUE(1'b0), .CASE_NAME("FALSE_CASE"), .EXPECT_PASS(1'b0)
  ) test_case ();
endmodule

module tb_stage2_checker_x;
  stage2_contract_predicate_self_test_case #(
    .CHECK_VALUE(1'bx), .CASE_NAME("X_CASE"), .EXPECT_PASS(1'b0)
  ) test_case ();
endmodule

module tb_stage2_checker_z;
  stage2_contract_predicate_self_test_case #(
    .CHECK_VALUE(1'bz), .CASE_NAME("Z_CASE"), .EXPECT_PASS(1'b0)
  ) test_case ();
endmodule

// Main-checker fixtures prove that the actual input legality checks reject
// reset X/Z, sample_valid X, and valid sample X/Z.  All DUT-observation inputs
// are benign; each negative case terminates at the intended legality predicate.
module stage2_main_checker_negative_fixture #(
  parameter integer MODE = 0,
  parameter string CASE_NAME = "SAMPLE_VALID_X"
);
  reg clk = 1'b0;
  reg rst_n = 1'b1;
  reg sample_valid;
  reg [11:0] i_ch1;
  reg [11:0] i_ch2;
  wire [31:0] accepted_count;
  wire [31:0] invalid_hold_count;
  wire [31:0] consecutive_valid_count;
  wire [31:0] reset_release_first_sample_count;

  always #5 clk = ~clk;

  initial begin
    sample_valid = 1'b0;
    i_ch1 = 12'd500;
    i_ch2 = 12'd510;
    if (MODE == 0)
      sample_valid = 1'bx;
    else if (MODE == 1) begin
      sample_valid = 1'b1;
      i_ch1 = {12{1'bx}};
    end else if (MODE == 2) begin
      sample_valid = 1'b1;
      i_ch2 = {12{1'bz}};
    end else if (MODE == 3)
      rst_n = 1'bx;
    else
      rst_n = 1'bz;
    $display("%s=EXPECTED_FAIL", CASE_NAME);
  end

  stage2_sampling_contract_checker #(
    .DATA_WIDTH(12), .HEALTH_CNT_WIDTH(4)
  ) u_contract_checker (
    .clk(clk),
    .rst_n(rst_n),
    .sample_valid(sample_valid),
    .clear_fault(1'b0),
    .i_ch1(i_ch1),
    .i_ch2(i_ch2),
    .th_oc_ch1(12'd1000),
    .th_oc_ch2(12'd1000),
    .th_diff(12'd100),
    .oc_any(1'b0),
    .oc_both(1'b0),
    .mismatch_flag(1'b0),
    .abs_diff(12'd10),
    .sensor_open_flag(1'b0),
    .sensor_sat_flag(1'b0),
    .sensor_stuck_flag(1'b0),
    .fault_valid(1'b0),
    .fault_latched(1'b0),
    .fault_code(8'h00),
    .fault_code_latched(8'h00),
    .fsm_state(4'd0),
    .pwm_out(1'b0),
    .health_prev_ch1(12'd0),
    .health_prev_ch2(12'd0),
    .health_open_cnt(4'd0),
    .health_sat_cnt(4'd0),
    .health_stuck_cnt(4'd0),
    .accepted_count(accepted_count),
    .invalid_hold_count(invalid_hold_count),
    .consecutive_valid_count(consecutive_valid_count),
    .reset_release_first_sample_count(reset_release_first_sample_count)
  );

  initial begin
    #30;
    $display("%s=UNEXPECTED_PASS", CASE_NAME);
    $finish;
  end
endmodule

module tb_stage2_sample_valid_x;
  stage2_main_checker_negative_fixture #(
    .MODE(0), .CASE_NAME("SAMPLE_VALID_X")
  ) test_case ();
endmodule

module tb_stage2_valid_sample_x;
  stage2_main_checker_negative_fixture #(
    .MODE(1), .CASE_NAME("VALID_SAMPLE_X")
  ) test_case ();
endmodule

module tb_stage2_valid_sample_z;
  stage2_main_checker_negative_fixture #(
    .MODE(2), .CASE_NAME("VALID_SAMPLE_Z")
  ) test_case ();
endmodule

module tb_stage2_rst_n_x;
  stage2_main_checker_negative_fixture #(
    .MODE(3), .CASE_NAME("RST_N_X")
  ) test_case ();
endmodule

module tb_stage2_rst_n_z;
  stage2_main_checker_negative_fixture #(
    .MODE(4), .CASE_NAME("RST_N_Z")
  ) test_case ();
endmodule
