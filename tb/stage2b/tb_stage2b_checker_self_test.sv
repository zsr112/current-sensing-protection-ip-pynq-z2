`timescale 1ns/1ps

module stage2b_predicate_self_test_case #(
  parameter logic CHECK_VALUE = 1'b1,
  parameter string CASE_NAME = "TRUE_CASE",
  parameter logic EXPECT_PASS = 1'b1
);
  task automatic check_true(input string label, input logic condition);
    begin
      if (condition !== 1'b1)
        $fatal(1, "STAGE2B CHECK FAILED: %s", label);
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

module tb_stage2b_checker_true;
  stage2b_predicate_self_test_case #(
    .CHECK_VALUE(1'b1), .CASE_NAME("TRUE_CASE"), .EXPECT_PASS(1'b1)
  ) test_case ();
endmodule

module tb_stage2b_checker_false;
  stage2b_predicate_self_test_case #(
    .CHECK_VALUE(1'b0), .CASE_NAME("FALSE_CASE"), .EXPECT_PASS(1'b0)
  ) test_case ();
endmodule

module tb_stage2b_checker_x;
  stage2b_predicate_self_test_case #(
    .CHECK_VALUE(1'bx), .CASE_NAME("X_CASE"), .EXPECT_PASS(1'b0)
  ) test_case ();
endmodule

module tb_stage2b_checker_z;
  stage2b_predicate_self_test_case #(
    .CHECK_VALUE(1'bz), .CASE_NAME("Z_CASE"), .EXPECT_PASS(1'b0)
  ) test_case ();
endmodule

module stage2b_main_checker_negative_fixture #(
  parameter integer MODE = 0,
  parameter string CASE_NAME = "SB23_SAMPLE_VALID_X"
);
  reg clk = 1'b0;
  reg rst_n = 1'b1;
  reg sample_valid = 1'b0;
  reg [11:0] i_ch1 = 12'd500;
  reg [11:0] i_ch2 = 12'd510;
  wire [31:0] accepted_count;
  wire [31:0] invalid_pair_hold_count;
  wire [31:0] back_to_back_count;
  wire [31:0] reset_release_first_accept_count;

  always #5 clk = ~clk;

  initial begin
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

  stage2b_sample_acceptance_checker #(
    .DATA_WIDTH(12), .HEALTH_CNT_WIDTH(4)
  ) u_checker (
    .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid),
    .clear_fault(1'b0), .i_ch1(i_ch1), .i_ch2(i_ch2),
    .th_oc_ch1(12'd1000), .th_oc_ch2(12'd1000), .th_diff(12'd100),
    .th_open(12'd10), .th_sat(12'd4090), .th_stuck_delta(12'd0),
    .th_persist(4'd2),
    .sample_accept_event(sample_valid),
    .accepted_sample_pair({12'd500, 12'd510}),
    .accepted_sample_valid(1'b0), .sample_decision_valid(1'b0),
    .decision_oc_any(1'b0), .decision_oc_both(1'b0),
    .decision_mismatch_flag(1'b0), .oc_any(1'b0), .oc_both(1'b0),
    .mismatch_flag(1'b0), .abs_diff(12'd10),
    .sensor_open_flag(1'b0), .sensor_sat_flag(1'b0),
    .sensor_stuck_flag(1'b0), .sensor_open_event(1'b0),
    .sensor_sat_event(1'b0), .sensor_stuck_event(1'b0),
    .health_prev_ch1(12'd500),
    .health_prev_ch2(12'd510), .health_open_cnt(4'd0),
    .health_sat_cnt(4'd0), .health_stuck_cnt(4'd0),
    .fault_valid(1'b0), .fault_code(8'h00), .fault_latched(1'b0),
    .fault_code_latched(8'h00), .fsm_state(4'd0), .pwm_out(1'b0),
    .accepted_count(accepted_count),
    .invalid_pair_hold_count(invalid_pair_hold_count),
    .back_to_back_count(back_to_back_count),
    .reset_release_first_accept_count(reset_release_first_accept_count)
  );

  initial begin
    #30;
    $display("%s=UNEXPECTED_PASS", CASE_NAME);
    $finish;
  end
endmodule

module tb_stage2b_sample_valid_x;
  stage2b_main_checker_negative_fixture #(
    .MODE(0), .CASE_NAME("SB23_SAMPLE_VALID_X")
  ) test_case ();
endmodule

module tb_stage2b_valid_sample_x;
  stage2b_main_checker_negative_fixture #(
    .MODE(1), .CASE_NAME("SB24_VALID_SAMPLE_X")
  ) test_case ();
endmodule

module tb_stage2b_valid_sample_z;
  stage2b_main_checker_negative_fixture #(
    .MODE(2), .CASE_NAME("SB24_VALID_SAMPLE_Z")
  ) test_case ();
endmodule

module tb_stage2b_rst_n_x;
  stage2b_main_checker_negative_fixture #(
    .MODE(3), .CASE_NAME("SB25_RST_N_X")
  ) test_case ();
endmodule

module tb_stage2b_rst_n_z;
  stage2b_main_checker_negative_fixture #(
    .MODE(4), .CASE_NAME("SB25_RST_N_Z")
  ) test_case ();
endmodule
