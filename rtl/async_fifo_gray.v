module async_fifo_gray #(
    // Contract: DATA_WIDTH >= 1 and ADDR_WIDTH >= 2. DEPTH is therefore a
    // power of two and at least four. The production bridge supplies the
    // complete sequence-plus-channel payload width and fixes ADDR_WIDTH=3.
    parameter DATA_WIDTH = 56,
    parameter ADDR_WIDTH = 3
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    output wire                  wr_ready,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_overflow_attempt,

    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire                  rd_empty,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_underflow_attempt
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    localparam PTR_WIDTH = ADDR_WIDTH + 1;

    // Keep the small dual-clock store as registers. The destination bridge
    // captures its combinational read into an explicit ACLK-domain boundary,
    // and the implementation XDC resolves these stable source cells exactly.
    (* ram_style = "registers" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg [PTR_WIDTH-1:0] wr_bin;
    // The Gray pointer registers are the frozen CDC constraint source
    // objects. KEEP prevents Vivado from merging an MSB with its equivalent
    // binary pointer bit before implementation-only XDC is applied.
    (* KEEP = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray;
    reg                 wr_full;
    reg [PTR_WIDTH-1:0] rd_bin;
    (* KEEP = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PTR_WIDTH-1:0] rd_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PTR_WIDTH-1:0] rd_gray_sync2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PTR_WIDTH-1:0] wr_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PTR_WIDTH-1:0] wr_gray_sync2;

    // Elaboration must fail closed when a caller violates the supported
    // geometry.  The deliberately undefined module names are also stable
    // diagnostics consumed by the Stage 2D negative tests.
    generate
        if (DATA_WIDTH < 1) begin : g_invalid_data_width
            STAGE2D_PARAMETER_ERROR_DATA_WIDTH_MUST_BE_AT_LEAST_1
                u_parameter_error();
        end
        if (ADDR_WIDTH < 2) begin : g_invalid_addr_width
            STAGE2D_PARAMETER_ERROR_FIFO_ADDR_WIDTH_MUST_BE_AT_LEAST_2
                u_parameter_error();
        end
    endgenerate

    wire wr_fire;
    wire rd_fire;
    wire [PTR_WIDTH-1:0] wr_bin_next;
    wire [PTR_WIDTH-1:0] wr_gray_next;
    wire [PTR_WIDTH-1:0] rd_bin_next;
    wire [PTR_WIDTH-1:0] rd_gray_next;
    wire [PTR_WIDTH-1:0] wr_full_compare;
    wire wr_full_next;

    assign wr_ready = wr_rst_n && !wr_full;
    // wr_en is an actual operation enable supplied by the bridge after
    // ready/valid acceptance. It is intentionally not raw producer valid:
    // valid && !ready is legal backpressure, not an overflow attempt.
    assign wr_fire = wr_en && !wr_full;
    assign wr_overflow_attempt = wr_rst_n && wr_en && wr_full;
    assign wr_bin_next = wr_bin + wr_fire;
    assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    assign wr_full_compare = {
        ~rd_gray_sync2[PTR_WIDTH-1:PTR_WIDTH-2],
        rd_gray_sync2[PTR_WIDTH-3:0]
    };
    assign wr_full_next = (wr_gray_next == wr_full_compare);

    // The synchronized write pointer makes a word visible only after the
    // source write has completed. The selected memory word remains stable
    // until the synchronized read pointer permits that address to be reused.
    assign rd_empty = !rd_rst_n || (rd_gray == wr_gray_sync2);
    assign rd_fire = rd_en && !rd_empty;
    assign rd_underflow_attempt = rd_rst_n && rd_en && rd_empty;
    assign rd_bin_next = rd_bin + rd_fire;
    assign rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;
    assign rd_data = mem[rd_bin[ADDR_WIDTH-1:0]];

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin <= {PTR_WIDTH{1'b0}};
            wr_gray <= {PTR_WIDTH{1'b0}};
            wr_full <= 1'b0;
        end else begin
            if (wr_fire)
                mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
            wr_full <= wr_full_next;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin <= {PTR_WIDTH{1'b0}};
            rd_gray <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_bin <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync1 <= {PTR_WIDTH{1'b0}};
            rd_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            wr_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end
endmodule
