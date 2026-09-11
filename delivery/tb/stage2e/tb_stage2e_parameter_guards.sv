module tb_stage2e_invalid_source_sequence_width;
    transaction_source_observer #(
        .DATA_WIDTH(1), .SEQUENCE_WIDTH(15), .COUNTER_WIDTH(2)
    ) dut (
        .clk(1'b0), .rst_n(1'b0), .source_valid(1'b0),
        .source_ready(1'b0), .source_ch1(1'b0), .source_ch2(1'b0),
        .fifo_overflow_attempt(1'b0)
    );
endmodule

module tb_stage2e_invalid_source_counter_width;
    transaction_source_observer #(
        .DATA_WIDTH(1), .SEQUENCE_WIDTH(16), .COUNTER_WIDTH(1)
    ) dut (
        .clk(1'b0), .rst_n(1'b0), .source_valid(1'b0),
        .source_ready(1'b0), .source_ch1(1'b0), .source_ch2(1'b0),
        .fifo_overflow_attempt(1'b0)
    );
endmodule

module tb_stage2e_invalid_cdc_sequence_width;
    source_observability_cdc #(
        .SEQUENCE_WIDTH(15), .COUNTER_WIDTH(2)
    ) dut (.dst_clk(1'b0), .dst_rst_n(1'b0));
endmodule

module tb_stage2e_invalid_cdc_counter_width;
    source_observability_cdc #(
        .SEQUENCE_WIDTH(16), .COUNTER_WIDTH(1)
    ) dut (.dst_clk(1'b0), .dst_rst_n(1'b0));
endmodule

module tb_stage2e_invalid_destination_sequence_width;
    transaction_destination_observer #(
        .SEQUENCE_WIDTH(15), .COUNTER_WIDTH(2)
    ) dut (.clk(1'b0), .rst_n(1'b0), .delivery_valid(1'b0),
        .delivery_sequence(15'd0), .fifo_underflow_attempt(1'b0),
        .source_accept_count_in(2'd0),
        .backpressure_cycle_count_in(2'd0),
        .source_protocol_violation_count_in(2'd0),
        .source_drop_count_in(2'd0),
        .fifo_overflow_attempt_count_in(2'd0),
        .source_counter_saturation_count_in(2'd0),
        .last_source_sequence_in(15'd0), .status_w1c_clear(10'd0));
endmodule

module tb_stage2e_invalid_destination_counter_width;
    transaction_destination_observer #(
        .SEQUENCE_WIDTH(16), .COUNTER_WIDTH(1)
    ) dut (.clk(1'b0), .rst_n(1'b0), .delivery_valid(1'b0),
        .delivery_sequence(16'd0), .fifo_underflow_attempt(1'b0),
        .source_accept_count_in(1'd0),
        .backpressure_cycle_count_in(1'd0),
        .source_protocol_violation_count_in(1'd0),
        .source_drop_count_in(1'd0),
        .fifo_overflow_attempt_count_in(1'd0),
        .source_counter_saturation_count_in(1'd0),
        .last_source_sequence_in(16'd0), .status_w1c_clear(10'd0));
endmodule
