`timescale 1ns/1ps

module stage2c_reset_release_checker #(
    parameter DATA_WIDTH = 12
)(
    input  wire                        clk,
    input  wire                        async_rst_n,
    input  wire                        local_rst_n,
    input  wire                        sample_valid,
    input  wire [(2*DATA_WIDTH)-1:0]   sample_pair,
    input  wire                        accepted_sample_valid,
    input  wire [(2*DATA_WIDTH)-1:0]   accepted_sample_pair,
    input  wire                        sample_decision_valid,
    input  wire                        health_state_any,
    input  wire                        health_event_any,
    input  wire                        fault_valid,
    input  wire                        fault_latched,
    input  wire                        pwm_raw,
    input  wire                        pwm_out,
    input  wire [3:0]                  fsm_state,
    input  wire                        axi_ready_any,
    input  wire                        axi_bvalid,
    input  wire                        axi_rvalid,
    input  wire [31:0]                 axi_rdata,
    input  wire                        axi_aw_hold_valid,
    input  wire                        axi_w_hold_valid,
    input  wire                        axi_reg_wr_en,
    input  wire                        axi_reg_rd_en
);
    integer release_edge_count;
    integer expected_accept_count;
    integer observed_accept_count;
    reg accepted_since_release;
    reg expected_accept_now;
    reg [(2*DATA_WIDTH)-1:0] expected_pair_now;

    task automatic fail(input string reason);
        begin
            $fatal(1, "STAGE2C CHECK FAILED: %s", reason);
        end
    endtask

    task automatic check_true(input string reason, input logic condition);
        begin
            if (condition !== 1'b1)
                fail(reason);
        end
    endtask

    initial begin
        release_edge_count = 0;
        expected_accept_count = 0;
        observed_accept_count = 0;
        accepted_since_release = 1'b0;
        expected_accept_now = 1'b0;
        expected_pair_now = {(2*DATA_WIDTH){1'b0}};
    end

    always @(negedge async_rst_n) begin
        release_edge_count = 0;
        expected_accept_count = 0;
        observed_accept_count = 0;
        accepted_since_release = 1'b0;
        #1;
        check_true("local reset did not assert asynchronously",
                   local_rst_n === 1'b0);
        check_true("accepted state did not clear on reset assertion",
                   (accepted_sample_valid === 1'b0) &&
                   (accepted_sample_pair === {(2*DATA_WIDTH){1'b0}}));
        check_true("decision state did not clear on reset assertion",
                   sample_decision_valid === 1'b0);
        check_true("health state or event did not clear on reset assertion",
                   (health_state_any === 1'b0) &&
                   (health_event_any === 1'b0));
        check_true("fault state did not clear on reset assertion",
                   (fault_valid === 1'b0) && (fault_latched === 1'b0));
        check_true("protection output was not safe on reset assertion",
                   (pwm_raw === 1'b0) && (pwm_out === 1'b0) &&
                   (fsm_state === 4'd0));
        check_true("AXI ready asserted during reset assertion",
                   axi_ready_any === 1'b0);
        check_true("AXI response state was not safe on reset assertion",
                   (axi_bvalid === 1'b0) &&
                   (axi_rvalid === 1'b0) &&
                   (axi_rdata === 32'd0));
        check_true("AXI held request state was not clear on reset assertion",
                   (axi_aw_hold_valid === 1'b0) &&
                   (axi_w_hold_valid === 1'b0));
        check_true("AXI register strobe asserted on reset assertion",
                   (axi_reg_wr_en === 1'b0) &&
                   (axi_reg_rd_en === 1'b0));
    end

    always @(posedge clk) begin
        check_true("async reset must be 0 or 1",
                   (async_rst_n === 1'b0) || (async_rst_n === 1'b1));
        check_true("local reset must be 0 or 1",
                   (local_rst_n === 1'b0) || (local_rst_n === 1'b1));
        check_true("sample_valid must be 0 or 1",
                   (sample_valid === 1'b0) || (sample_valid === 1'b1));

        if (async_rst_n === 1'b0) begin
            release_edge_count = 0;
            expected_accept_count = 0;
            observed_accept_count = 0;
            accepted_since_release = 1'b0;
        end else begin
            if (release_edge_count < 2)
                check_true("local reset released early",
                           local_rst_n === 1'b0);
            else
                check_true("local reset failed to release after two stages",
                           local_rst_n === 1'b1);
            release_edge_count = release_edge_count + 1;
        end

        expected_accept_now = (async_rst_n === 1'b1) &&
                              (local_rst_n === 1'b1) &&
                              (sample_valid === 1'b1);
        expected_pair_now = sample_pair;

        #1;

        if (local_rst_n === 1'b0) begin
            if (accepted_sample_valid !== 1'b0)
                fail("accepted transaction during reset-release window");
            check_true("accepted pair was not zero during reset-release window",
                       accepted_sample_pair === {(2*DATA_WIDTH){1'b0}});
            check_true("decision advanced during reset-release window",
                       sample_decision_valid === 1'b0);
            if ((fault_valid !== 1'b0) || (fault_latched !== 1'b0) ||
                (health_event_any !== 1'b0))
                fail("fault or event asserted during reset-release window");
            check_true("health advanced during reset-release window",
                       (health_state_any === 1'b0) &&
                       (health_event_any === 1'b0));
            check_true("protection output unsafe during reset-release window",
                       (pwm_raw === 1'b0) && (pwm_out === 1'b0) &&
                       (fsm_state === 4'd0));
            check_true("AXI ready asserted during reset-release window",
                       axi_ready_any === 1'b0);
            check_true("AXI response state unsafe during reset-release window",
                       (axi_bvalid === 1'b0) &&
                       (axi_rvalid === 1'b0) &&
                       (axi_rdata === 32'd0));
            check_true("AXI held request state survived reset-release window",
                       (axi_aw_hold_valid === 1'b0) &&
                       (axi_w_hold_valid === 1'b0));
            check_true("AXI register strobe asserted during reset-release window",
                       (axi_reg_wr_en === 1'b0) &&
                       (axi_reg_rd_en === 1'b0));
        end

        if (expected_accept_now) begin
            expected_accept_count = expected_accept_count + 1;
            if (accepted_sample_valid !== 1'b1)
                fail("accepted transaction dropped after reset release");
            check_true("accepted sample pair lost atomicity",
                       accepted_sample_pair === expected_pair_now);
            observed_accept_count = observed_accept_count + 1;
            accepted_since_release = 1'b1;
        end else if (accepted_sample_valid !== 1'b0) begin
            if ((local_rst_n !== 1'b1) || (async_rst_n !== 1'b1))
                fail("accepted transaction during reset-release window");
            else if (!accepted_since_release)
                fail("stale accepted transaction replayed after reset");
            else
                fail("duplicate first transaction after reset");
        end

        check_true("accepted transaction count mismatch",
                   observed_accept_count == expected_accept_count);
    end
endmodule
