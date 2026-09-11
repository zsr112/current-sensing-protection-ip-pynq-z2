`timescale 1ns/1ps

module stage2c_checker_fixture #(
    parameter integer FAULT_ID = 0
);
    reg clk = 1'b0;
    reg async_rst_n = 1'b1;
    reg local_rst_n = 1'b0;
    reg sample_valid = 1'b0;
    reg [23:0] sample_pair = 24'd0;
    reg accepted_sample_valid = 1'b0;
    reg [23:0] accepted_sample_pair = 24'd0;
    reg sample_decision_valid = 1'b0;
    reg health_state_any = 1'b0;
    reg health_event_any = 1'b0;
    reg fault_valid = 1'b0;
    reg fault_latched = 1'b0;
    reg pwm_raw = 1'b0;
    reg pwm_out = 1'b0;
    reg [3:0] fsm_state = 4'd0;
    reg axi_ready_any = 1'b0;
    reg axi_bvalid = 1'b0;
    reg axi_rvalid = 1'b0;
    reg [31:0] axi_rdata = 32'd0;
    reg axi_aw_hold_valid = 1'b0;
    reg axi_w_hold_valid = 1'b0;
    reg axi_reg_wr_en = 1'b0;
    reg axi_reg_rd_en = 1'b0;

    always #5 clk = ~clk;

    stage2c_reset_release_checker u_checker (
        .clk(clk),
        .async_rst_n(async_rst_n),
        .local_rst_n(local_rst_n),
        .sample_valid(sample_valid),
        .sample_pair(sample_pair),
        .accepted_sample_valid(accepted_sample_valid),
        .accepted_sample_pair(accepted_sample_pair),
        .sample_decision_valid(sample_decision_valid),
        .health_state_any(health_state_any),
        .health_event_any(health_event_any),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .pwm_raw(pwm_raw),
        .pwm_out(pwm_out),
        .fsm_state(fsm_state),
        .axi_ready_any(axi_ready_any),
        .axi_bvalid(axi_bvalid),
        .axi_rvalid(axi_rvalid),
        .axi_rdata(axi_rdata),
        .axi_aw_hold_valid(axi_aw_hold_valid),
        .axi_w_hold_valid(axi_w_hold_valid),
        .axi_reg_wr_en(axi_reg_wr_en),
        .axi_reg_rd_en(axi_reg_rd_en)
    );

    initial begin
        if (FAULT_ID == 6) begin
            pwm_raw = 1'b1;
            pwm_out = 1'b1;
        end
        #1 async_rst_n = 1'b0;
        #1 async_rst_n = 1'b1;

        case (FAULT_ID)
            1: begin
                #1 local_rst_n = 1'b1;
            end

            2: begin
                #1 accepted_sample_valid = 1'b1;
            end

            3: begin
                @(posedge clk);
                @(posedge clk);
                #1 local_rst_n = 1'b1;
                @(negedge clk);
                accepted_sample_valid = 1'b1;
                accepted_sample_pair = 24'h123456;
            end

            4: begin
                @(posedge clk);
                @(posedge clk);
                #1 local_rst_n = 1'b1;
                @(negedge clk);
                sample_valid = 1'b1;
                sample_pair = 24'hABCDEF;
                accepted_sample_valid = 1'b1;
                accepted_sample_pair = 24'hABCDEF;
                @(negedge clk);
                sample_valid = 1'b0;
                accepted_sample_valid = 1'b1;
            end

            5: begin
                #1 begin
                    fault_valid = 1'b1;
                    health_event_any = 1'b1;
                end
            end

            6: begin
                // Unsafe PWM is present when asynchronous reset is asserted.
            end

            7: begin
                #1 begin
                    pwm_raw = 1'b1;
                    pwm_out = 1'b1;
                end
            end

            8: begin
                #1 begin
                    axi_bvalid = 1'b1;
                    axi_rvalid = 1'b1;
                    axi_rdata = 32'hDEADBEEF;
                end
            end

            9: begin
                #1 begin
                    axi_aw_hold_valid = 1'b1;
                    axi_w_hold_valid = 1'b1;
                    axi_reg_wr_en = 1'b1;
                    axi_reg_rd_en = 1'b1;
                end
            end

            default: begin
                @(posedge clk);
                @(posedge clk);
                #1 local_rst_n = 1'b1;
                repeat (3) @(posedge clk);
                $display("STAGE2C_CHECKER_TRUE=PASS");
                $finish;
            end
        endcase

        #100;
        $display("UNEXPECTED_PASS FAULT_ID=%0d", FAULT_ID);
        $finish;
    end
endmodule

module tb_stage2c_checker_true;
    stage2c_checker_fixture #(.FAULT_ID(0)) fixture();
endmodule

module tb_stage2c_checker_early_release;
    stage2c_checker_fixture #(.FAULT_ID(1)) fixture();
endmodule

module tb_stage2c_checker_accept_during_release;
    stage2c_checker_fixture #(.FAULT_ID(2)) fixture();
endmodule

module tb_stage2c_checker_stale_replay;
    stage2c_checker_fixture #(.FAULT_ID(3)) fixture();
endmodule

module tb_stage2c_checker_duplicate_first;
    stage2c_checker_fixture #(.FAULT_ID(4)) fixture();
endmodule

module tb_stage2c_checker_fault_during_release;
    stage2c_checker_fixture #(.FAULT_ID(5)) fixture();
endmodule

module tb_stage2c_checker_pwm_unsafe_on_reset;
    stage2c_checker_fixture #(.FAULT_ID(6)) fixture();
endmodule

module tb_stage2c_checker_pwm_unsafe_during_release;
    stage2c_checker_fixture #(.FAULT_ID(7)) fixture();
endmodule

module tb_stage2c_checker_axi_response_during_release;
    stage2c_checker_fixture #(.FAULT_ID(8)) fixture();
endmodule

module tb_stage2c_checker_axi_state_during_release;
    stage2c_checker_fixture #(.FAULT_ID(9)) fixture();
endmodule
