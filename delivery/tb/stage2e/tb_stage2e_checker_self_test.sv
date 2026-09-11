`timescale 1ns/1ps

module stage2e_checker_fixture #(
    parameter CASE_ID = 0
);
    stage2e_transaction_observability_checker u_checker();

    initial begin
        case (CASE_ID)
            0: begin
                u_checker.observe_backpressure(1, 0, 0);
                u_checker.observe_withdrawal(1, 1, 1);
                u_checker.observe_payload_change(1, 1, 1);
                u_checker.observe_episode_count(1);
                u_checker.observe_duplicate_identity(1, 0, 0);
                u_checker.observe_duplicate_identity(0, 1, 1);
                u_checker.observe_atomic_fifo_word(1);
                u_checker.observe_accept_sequence(1, 32'd7, 32'd8);
                u_checker.observe_delivery_accounting(2, 2);
                u_checker.observe_gap(1, 1);
                u_checker.observe_sequence_relative_stale_or_reorder(1, 1);
                u_checker.observe_counter_cdc(1, 1, 0, 1);
                u_checker.observe_event_cdc(1, 0, 1, 1);
                u_checker.observe_saturation(
                    32'hFFFF_FFFF, 32'hFFFF_FFFF, 1);
                u_checker.observe_w1c_race(1, 1, 1);
                u_checker.observe_any_error_backpressure(1, 0);
                u_checker.observe_read_only_write(32'd9, 32'd9);
                u_checker.observe_reset_state(0, 0, 0);
                u_checker.observe_sequence_wrap(1, 0);
                $display("PREDICATE_TRUE_CASE=PASS");
                $display("CHECKER_PREDICATE_UNIT_TESTS=PASS");
                $finish;
            end
            1: begin
                $display("BACKPRESSURE_DROP_CASE=EXPECTED_FAIL");
                u_checker.observe_backpressure(1, 0, 1);
            end
            2: begin
                $display("WITHDRAWAL_CASE=EXPECTED_FAIL");
                u_checker.observe_withdrawal(1, 1, 0);
            end
            3: begin
                $display("PAYLOAD_CHANGE_CASE=EXPECTED_FAIL");
                u_checker.observe_payload_change(1, 1, 0);
            end
            4: begin
                $display("EPISODE_RECOUNT_CASE=EXPECTED_FAIL");
                u_checker.observe_episode_count(3);
            end
            5: begin
                $display("PAYLOAD_IDENTITY_CASE=EXPECTED_FAIL");
                u_checker.observe_duplicate_identity(1, 0, 1);
            end
            6: begin
                $display("NONATOMIC_SEQUENCE_CASE=EXPECTED_FAIL");
                u_checker.observe_atomic_fifo_word(0);
            end
            7: begin
                $display("ACCEPT_SEQUENCE_CASE=EXPECTED_FAIL");
                u_checker.observe_accept_sequence(1, 32'd4, 32'd4);
            end
            8: begin
                $display("DELIVERY_COUNT_CASE=EXPECTED_FAIL");
                u_checker.observe_delivery_accounting(2, 1);
            end
            9: begin
                $display("GAP_CASE=EXPECTED_FAIL");
                u_checker.observe_gap(1, 0);
            end
            10: begin
                $display("STALE_CASE=EXPECTED_FAIL");
                u_checker.observe_sequence_relative_stale_or_reorder(1, 0);
            end
            11: begin
                $display("BINARY_CDC_CASE=EXPECTED_FAIL");
                u_checker.observe_counter_cdc(0, 1, 1, 0);
            end
            12: begin
                $display("PULSE_CDC_CASE=EXPECTED_FAIL");
                u_checker.observe_event_cdc(0, 1, 1, 0);
            end
            13: begin
                $display("COUNTER_WRAP_CASE=EXPECTED_FAIL");
                u_checker.observe_saturation(
                    32'hFFFF_FFFF, 32'h0000_0000, 0);
            end
            14: begin
                $display("W1C_RACE_CASE=EXPECTED_FAIL");
                u_checker.observe_w1c_race(1, 1, 0);
            end
            15: begin
                $display("ANY_ERROR_BACKPRESSURE_CASE=EXPECTED_FAIL");
                u_checker.observe_any_error_backpressure(1, 1);
            end
            16: begin
                $display("WRITABLE_COUNTER_CASE=EXPECTED_FAIL");
                u_checker.observe_read_only_write(32'd3, 32'd99);
            end
            17: begin
                $display("RESET_NONZERO_CASE=EXPECTED_FAIL");
                u_checker.observe_reset_state(32'd1, 10'd0, 0);
            end
            18: begin
                $display("WRAP_MISCLASSIFIED_CASE=EXPECTED_FAIL");
                u_checker.observe_sequence_wrap(1, 1);
            end
            default: $fatal(1, "unknown checker fixture");
        endcase
        $display("CHECKER_CASE_%0d=UNEXPECTED_PASS", CASE_ID);
        $finish;
    end
endmodule

module tb_stage2e_checker_true;
    stage2e_checker_fixture #(.CASE_ID(0)) fixture();
endmodule
module tb_stage2e_checker_backpressure_drop;
    stage2e_checker_fixture #(.CASE_ID(1)) fixture();
endmodule
module tb_stage2e_checker_withdrawal;
    stage2e_checker_fixture #(.CASE_ID(2)) fixture();
endmodule
module tb_stage2e_checker_payload_change;
    stage2e_checker_fixture #(.CASE_ID(3)) fixture();
endmodule
module tb_stage2e_checker_episode_recount;
    stage2e_checker_fixture #(.CASE_ID(4)) fixture();
endmodule
module tb_stage2e_checker_payload_identity;
    stage2e_checker_fixture #(.CASE_ID(5)) fixture();
endmodule
module tb_stage2e_checker_nonatomic_sequence;
    stage2e_checker_fixture #(.CASE_ID(6)) fixture();
endmodule
module tb_stage2e_checker_accept_sequence;
    stage2e_checker_fixture #(.CASE_ID(7)) fixture();
endmodule
module tb_stage2e_checker_delivery_count;
    stage2e_checker_fixture #(.CASE_ID(8)) fixture();
endmodule
module tb_stage2e_checker_gap;
    stage2e_checker_fixture #(.CASE_ID(9)) fixture();
endmodule
module tb_stage2e_checker_stale;
    stage2e_checker_fixture #(.CASE_ID(10)) fixture();
endmodule
module tb_stage2e_checker_binary_cdc;
    stage2e_checker_fixture #(.CASE_ID(11)) fixture();
endmodule
module tb_stage2e_checker_pulse_cdc;
    stage2e_checker_fixture #(.CASE_ID(12)) fixture();
endmodule
module tb_stage2e_checker_counter_wrap;
    stage2e_checker_fixture #(.CASE_ID(13)) fixture();
endmodule
module tb_stage2e_checker_w1c_race;
    stage2e_checker_fixture #(.CASE_ID(14)) fixture();
endmodule
module tb_stage2e_checker_any_error_backpressure;
    stage2e_checker_fixture #(.CASE_ID(15)) fixture();
endmodule
module tb_stage2e_checker_writable_counter;
    stage2e_checker_fixture #(.CASE_ID(16)) fixture();
endmodule
module tb_stage2e_checker_reset_nonzero;
    stage2e_checker_fixture #(.CASE_ID(17)) fixture();
endmodule
module tb_stage2e_checker_wrap_misclassified;
    stage2e_checker_fixture #(.CASE_ID(18)) fixture();
endmodule
