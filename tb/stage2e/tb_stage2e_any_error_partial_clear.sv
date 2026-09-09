`timescale 1ns/1ps

module tb_stage2e_any_error_partial_clear;
    localparam [9:0] STATUS_BACKPRESSURE = 10'h001;
    localparam [9:0] STATUS_SOURCE_PROTOCOL = 10'h002;
    localparam [9:0] STATUS_FIFO_OVERFLOW = 10'h008;
    localparam [9:0] STATUS_FIFO_UNDERFLOW = 10'h010;
    localparam [9:0] STATUS_ANY_ERROR = 10'h200;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg delivery_valid = 0;
    reg [31:0] delivery_sequence = 0;
    reg fifo_underflow_attempt = 0;
    reg [31:0] source_accept_count = 0;
    reg [31:0] backpressure_count = 0;
    reg [31:0] source_protocol_count = 0;
    reg [31:0] source_drop_count = 0;
    reg [31:0] fifo_overflow_count = 0;
    reg [31:0] source_saturation_count = 0;
    reg [9:0] status_w1c_clear = 0;
    wire [9:0] sticky_status;

    integer checks = 0;

    transaction_destination_observer dut (
        .clk(clk),
        .rst_n(rst_n),
        .delivery_valid(delivery_valid),
        .delivery_sequence(delivery_sequence),
        .fifo_underflow_attempt(fifo_underflow_attempt),
        .source_accept_count_in(source_accept_count),
        .backpressure_cycle_count_in(backpressure_count),
        .source_protocol_violation_count_in(source_protocol_count),
        .source_drop_count_in(source_drop_count),
        .fifo_overflow_attempt_count_in(fifo_overflow_count),
        .source_counter_saturation_count_in(source_saturation_count),
        .last_source_sequence_in(32'd0),
        .status_w1c_clear(status_w1c_clear),
        .sticky_status(sticky_status)
    );

    task automatic fail(input [8*96-1:0] message);
        begin
            $display("ANY_ERROR PARTIAL CLEAR FAILED: %0s", message);
            $fatal(1);
        end
    endtask

    task automatic clock_step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_status(
        input [8*64-1:0] label,
        input [9:0] expected
    );
        begin
            if (sticky_status !== expected) begin
                $display("STATUS MISMATCH %0s actual=%03x expected=%03x",
                         label, sticky_status, expected);
                fail(label);
            end
        end
    endtask

    task automatic clear_status(input [9:0] mask);
        begin
            @(negedge clk);
            status_w1c_clear = mask;
            clock_step();
            @(negedge clk);
            status_w1c_clear = 0;
        end
    endtask

    task automatic reset_observer;
        begin
            rst_n = 0;
            delivery_valid = 0;
            fifo_underflow_attempt = 0;
            source_accept_count = 0;
            backpressure_count = 0;
            source_protocol_count = 0;
            source_drop_count = 0;
            fifo_overflow_count = 0;
            source_saturation_count = 0;
            status_w1c_clear = 0;
            repeat (2) clock_step();
            @(negedge clk);
            rst_n = 1;
            clock_step();
        end
    endtask

    initial begin
        reset_observer();

        @(negedge clk);
        source_protocol_count = 1;
        clock_step();
        check_status("initial protocol cause",
                     STATUS_SOURCE_PROTOCOL | STATUS_ANY_ERROR);
        clear_status(STATUS_ANY_ERROR);
        check_status("ANY_ERROR-only clear changed maintained aggregate",
                     STATUS_SOURCE_PROTOCOL | STATUS_ANY_ERROR);
        checks = checks + 1;

        @(negedge clk);
        fifo_underflow_attempt = 1;
        clock_step();
        @(negedge clk);
        fifo_underflow_attempt = 0;
        clear_status(STATUS_SOURCE_PROTOCOL);
        check_status("one cause clear dropped aggregate with another cause",
                     STATUS_FIFO_UNDERFLOW | STATUS_ANY_ERROR);
        checks = checks + 1;

        clear_status(STATUS_FIFO_UNDERFLOW);
        check_status("all cause clear retained aggregate", 10'd0);
        checks = checks + 1;

        @(negedge clk);
        fifo_underflow_attempt = 1;
        clock_step();
        @(negedge clk);
        fifo_underflow_attempt = 0;
        fifo_overflow_count = 1;
        status_w1c_clear = STATUS_FIFO_UNDERFLOW;
        clock_step();
        @(negedge clk);
        status_w1c_clear = 0;
        check_status("same-cycle replacement cause was lost",
                     STATUS_FIFO_OVERFLOW | STATUS_ANY_ERROR);
        checks = checks + 1;

        reset_observer();
        @(negedge clk);
        backpressure_count = 1;
        clock_step();
        check_status("legal backpressure set ANY_ERROR", STATUS_BACKPRESSURE);
        checks = checks + 1;

        if (checks != 5)
            fail("check count");
        $display("ANY_ERROR_PARTIAL_CLEAR_TESTS=PASS_5_OF_5");
        $display("ANY_ERROR_MAINTAINED_POST_CLEAR_AGGREGATE=PASS");
        $display("ANY_ERROR_READ_ONLY_AGGREGATE=PASS");
        $finish;
    end

    initial begin
        #100000;
        fail("global timeout");
    end
endmodule
