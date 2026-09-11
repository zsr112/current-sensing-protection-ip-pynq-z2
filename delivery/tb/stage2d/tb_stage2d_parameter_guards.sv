module tb_stage2d_invalid_fifo_data_width;
    wire ready;
    wire empty;
    wire [0:0] data;
    async_fifo_gray #(.DATA_WIDTH(0), .ADDR_WIDTH(2)) dut (
        .wr_clk(1'b0), .wr_rst_n(1'b0), .wr_en(1'b0),
        .wr_ready(ready), .wr_data(1'b0), .rd_clk(1'b0),
        .rd_rst_n(1'b0), .rd_en(1'b0), .rd_empty(empty), .rd_data(data));
endmodule

module tb_stage2d_invalid_fifo_addr_width;
    wire ready;
    wire empty;
    wire data;
    async_fifo_gray #(.DATA_WIDTH(1), .ADDR_WIDTH(1)) dut (
        .wr_clk(1'b0), .wr_rst_n(1'b0), .wr_en(1'b0),
        .wr_ready(ready), .wr_data(1'b0), .rd_clk(1'b0),
        .rd_rst_n(1'b0), .rd_en(1'b0), .rd_empty(empty), .rd_data(data));
endmodule

module tb_stage2d_invalid_bridge_data_width;
    wire ready;
    wire valid;
    wire [0:0] ch1;
    wire [0:0] ch2;
    adc_sample_cdc_bridge #(.DATA_WIDTH(0), .FIFO_ADDR_WIDTH(2)) dut (
        .src_clk(1'b0), .src_rst_n(1'b0), .src_sample_valid(1'b0),
        .src_sample_ready(ready), .src_sample_ch1(1'b0), .src_sample_ch2(1'b0),
        .dst_clk(1'b0), .dst_rst_n(1'b0), .dst_ready(1'b0),
        .dst_sample_valid(valid), .dst_sample_ch1(ch1), .dst_sample_ch2(ch2));
endmodule

module tb_stage2d_invalid_bridge_fifo_addr_width;
    wire ready;
    wire valid;
    wire ch1;
    wire ch2;
    adc_sample_cdc_bridge #(.DATA_WIDTH(1), .FIFO_ADDR_WIDTH(1)) dut (
        .src_clk(1'b0), .src_rst_n(1'b0), .src_sample_valid(1'b0),
        .src_sample_ready(ready), .src_sample_ch1(1'b0), .src_sample_ch2(1'b0),
        .dst_clk(1'b0), .dst_rst_n(1'b0), .dst_ready(1'b0),
        .dst_sample_valid(valid), .dst_sample_ch1(ch1), .dst_sample_ch2(ch2));
endmodule
