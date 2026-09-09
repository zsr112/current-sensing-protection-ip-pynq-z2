`timescale 1ns/1ps

module stage2d_checker_fixture #(
    parameter CASE_ID = 0
);
    localparam [11:0] XOR_MASK = 12'h5A5;
    wire [23:0] p1 = {12'h101, (12'h101 ^ XOR_MASK)};
    wire [23:0] p2 = {12'h102, (12'h102 ^ XOR_MASK)};
    wire [23:0] p3 = {12'h103, (12'h103 ^ XOR_MASK)};
    wire [23:0] torn = {12'h101, 12'h000};

    stage2d_atomic_cdc_checker u_checker();

    initial begin
        u_checker.reset_epoch();
        case (CASE_ID)
            0: begin
                u_checker.source_accept(p1);
                u_checker.source_accept(p2);
                u_checker.destination_deliver(p1);
                u_checker.destination_deliver(p2);
                u_checker.observe_fifo_access(1'b0, 1'b1, 1'b0, 1'b0);
                u_checker.observe_pointer_sync_use(1'b0);
                u_checker.observe_stage2b_trigger(1'b1, 1'b1, 1'b1);
                u_checker.observe_reset_domains(1'b1, 1'b1);
                u_checker.finalize();
                $display("TRUE_CASE=PASS");
                $finish;
            end
            1: begin
                $display("TEARING_CASE=EXPECTED_FAIL");
                u_checker.source_accept(p1);
                u_checker.destination_deliver(torn);
            end
            2: begin
                $display("DUPLICATE_CASE=EXPECTED_FAIL");
                u_checker.source_accept(p1);
                u_checker.source_accept(p2);
                u_checker.destination_deliver(p1);
                u_checker.destination_deliver(p1);
            end
            3: begin
                $display("DROP_CASE=EXPECTED_FAIL");
                u_checker.source_accept(p1);
                u_checker.finalize();
            end
            4: begin
                $display("PHANTOM_CASE=EXPECTED_FAIL");
                u_checker.destination_deliver(p3);
            end
            5: begin
                $display("OUT_OF_ORDER_CASE=EXPECTED_FAIL");
                u_checker.source_accept(p1);
                u_checker.source_accept(p2);
                u_checker.destination_deliver(p2);
            end
            6: begin
                $display("READ_EMPTY_CASE=EXPECTED_FAIL");
                u_checker.observe_fifo_access(1'b1, 1'b1, 1'b0, 1'b0);
            end
            7: begin
                $display("WRITE_FULL_CASE=EXPECTED_FAIL");
                u_checker.observe_fifo_access(1'b0, 1'b0, 1'b1, 1'b1);
            end
            8: begin
                $display("STALE_REPLAY_CASE=EXPECTED_FAIL");
                u_checker.source_accept(p1);
                u_checker.reset_epoch();
                u_checker.destination_deliver(p1);
            end
            9: begin
                $display("FIRST_DUPLICATE_CASE=EXPECTED_FAIL");
                u_checker.source_accept(p1);
                u_checker.destination_deliver(p1);
                u_checker.destination_deliver(p1);
            end
            10: begin
                $display("EARLY_POINTER_CASE=EXPECTED_FAIL");
                u_checker.observe_pointer_sync_use(1'b1);
            end
            11: begin
                $display("NONEMPTY_TRIGGER_CASE=EXPECTED_FAIL");
                u_checker.observe_stage2b_trigger(1'b1, 1'b0, 1'b1);
            end
            12: begin
                $display("WRONG_RESET_DOMAIN_CASE=EXPECTED_FAIL");
                u_checker.observe_reset_domains(1'b0, 1'b1);
            end
            default: begin
                $fatal(1, "Unknown checker self-test case");
            end
        endcase
        $display("CHECKER_CASE_%0d=UNEXPECTED_PASS", CASE_ID);
        $finish;
    end
endmodule

module tb_stage2d_checker_true;
    stage2d_checker_fixture #(.CASE_ID(0)) fixture();
endmodule
module tb_stage2d_checker_tearing;
    stage2d_checker_fixture #(.CASE_ID(1)) fixture();
endmodule
module tb_stage2d_checker_duplicate;
    stage2d_checker_fixture #(.CASE_ID(2)) fixture();
endmodule
module tb_stage2d_checker_drop;
    stage2d_checker_fixture #(.CASE_ID(3)) fixture();
endmodule
module tb_stage2d_checker_phantom;
    stage2d_checker_fixture #(.CASE_ID(4)) fixture();
endmodule
module tb_stage2d_checker_out_of_order;
    stage2d_checker_fixture #(.CASE_ID(5)) fixture();
endmodule
module tb_stage2d_checker_read_empty;
    stage2d_checker_fixture #(.CASE_ID(6)) fixture();
endmodule
module tb_stage2d_checker_write_full;
    stage2d_checker_fixture #(.CASE_ID(7)) fixture();
endmodule
module tb_stage2d_checker_stale_replay;
    stage2d_checker_fixture #(.CASE_ID(8)) fixture();
endmodule
module tb_stage2d_checker_first_duplicate;
    stage2d_checker_fixture #(.CASE_ID(9)) fixture();
endmodule
module tb_stage2d_checker_early_pointer;
    stage2d_checker_fixture #(.CASE_ID(10)) fixture();
endmodule
module tb_stage2d_checker_nonempty_trigger;
    stage2d_checker_fixture #(.CASE_ID(11)) fixture();
endmodule
module tb_stage2d_checker_wrong_reset_domain;
    stage2d_checker_fixture #(.CASE_ID(12)) fixture();
endmodule
