module protection_ip_top_axi_lite #(
    parameter DATA_WIDTH       = 12,
    parameter CNT_WIDTH        = 16,
    parameter AXI_ADDR_WIDTH   = 8,
    parameter AXI_DATA_WIDTH   = 32,
    parameter HEALTH_CNT_WIDTH = 8
)(
    input  wire ACLK,
    input  wire ARESETN,
    input  wire sample_valid,

    input  wire [AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire S_AXI_AWVALID,
    output wire S_AXI_AWREADY,
    input  wire [AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire S_AXI_WVALID,
    output wire S_AXI_WREADY,
    output wire [1:0] S_AXI_BRESP,
    output reg  S_AXI_BVALID,
    input  wire S_AXI_BREADY,

    input  wire [AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire S_AXI_ARVALID,
    output wire S_AXI_ARREADY,
    output reg  [AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output reg  S_AXI_RVALID,
    input  wire S_AXI_RREADY,

    input  wire [DATA_WIDTH-1:0] i_ch1,
    input  wire [DATA_WIDTH-1:0] i_ch2,

    output wire pwm_raw,
    output wire pwm_out,
    output wire fault_valid,
    output wire fault_latched,
    output wire [7:0] fault_code,
    output wire [7:0] fault_code_latched,
    output wire [3:0] fsm_state
);
    localparam WR_COLLECT = 2'd0;
    localparam WR_APPLY   = 2'd1;
    localparam WR_RESP    = 2'd2;
    localparam RD_IDLE    = 2'd0;
    localparam RD_CAPTURE = 2'd1;
    localparam RD_RESP    = 2'd2;

    reg [1:0] wr_state;
    reg [1:0] rd_state;

    reg reg_wr_en;
    reg reg_rd_en;
    reg [AXI_ADDR_WIDTH-1:0] reg_write_addr;
    reg [AXI_ADDR_WIDTH-1:0] reg_read_addr;
    reg [AXI_DATA_WIDTH-1:0] reg_wdata;
    wire [AXI_DATA_WIDTH-1:0] reg_rdata;
    wire [AXI_ADDR_WIDTH-1:0] reg_addr;

    reg aw_hold_valid;
    reg w_hold_valid;
    reg [AXI_ADDR_WIDTH-1:0] awaddr_hold;
    reg [AXI_DATA_WIDTH-1:0] wdata_hold;
    reg [(AXI_DATA_WIDTH/8)-1:0] wstrb_hold;

    wire aw_accept;
    wire w_accept;
    wire ar_accept;
    wire aw_available;
    wire w_available;
    wire [AXI_ADDR_WIDTH-1:0] write_addr_next;
    wire [AXI_DATA_WIDTH-1:0] write_data_next;
    wire [(AXI_DATA_WIDTH/8)-1:0] write_strb_next;
    wire write_request_active;
    wire read_busy;

    assign S_AXI_BRESP = 2'b00;
    assign S_AXI_RRESP = 2'b00;
    assign write_request_active = (wr_state != WR_COLLECT) || S_AXI_BVALID ||
                                  aw_hold_valid || w_hold_valid ||
                                  S_AXI_AWVALID || S_AXI_WVALID;
    assign read_busy = (rd_state != RD_IDLE) || S_AXI_RVALID;
    assign S_AXI_AWREADY = (wr_state == WR_COLLECT) && !aw_hold_valid && !read_busy;
    assign S_AXI_WREADY  = (wr_state == WR_COLLECT) && !w_hold_valid && !read_busy;
    assign S_AXI_ARREADY = (rd_state == RD_IDLE) && !S_AXI_RVALID && !write_request_active;
    assign aw_accept = S_AXI_AWVALID && S_AXI_AWREADY;
    assign w_accept = S_AXI_WVALID && S_AXI_WREADY;
    assign ar_accept = S_AXI_ARVALID && S_AXI_ARREADY;
    assign aw_available = aw_hold_valid || aw_accept;
    assign w_available = w_hold_valid || w_accept;
    assign write_addr_next = aw_hold_valid ? awaddr_hold : S_AXI_AWADDR;
    assign write_data_next = w_hold_valid ? wdata_hold : S_AXI_WDATA;
    assign write_strb_next = w_hold_valid ? wstrb_hold : S_AXI_WSTRB;
    assign reg_addr = reg_wr_en ? reg_write_addr : reg_read_addr;

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            wr_state <= WR_COLLECT;
            rd_state <= RD_IDLE;
            S_AXI_BVALID <= 1'b0;
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA <= {AXI_DATA_WIDTH{1'b0}};
            reg_wr_en <= 1'b0;
            reg_rd_en <= 1'b0;
            reg_write_addr <= {AXI_ADDR_WIDTH{1'b0}};
            reg_read_addr <= {AXI_ADDR_WIDTH{1'b0}};
            reg_wdata <= {AXI_DATA_WIDTH{1'b0}};
            aw_hold_valid <= 1'b0;
            w_hold_valid <= 1'b0;
            awaddr_hold <= {AXI_ADDR_WIDTH{1'b0}};
            wdata_hold <= {AXI_DATA_WIDTH{1'b0}};
            wstrb_hold <= {(AXI_DATA_WIDTH/8){1'b0}};
        end else begin
            reg_wr_en <= 1'b0;
            reg_rd_en <= 1'b0;

            case (wr_state)
                WR_COLLECT: begin
                    if (aw_accept && !w_available) begin
                        awaddr_hold <= S_AXI_AWADDR;
                        aw_hold_valid <= 1'b1;
                    end

                    if (w_accept && !aw_available) begin
                        wdata_hold <= S_AXI_WDATA;
                        wstrb_hold <= S_AXI_WSTRB;
                        w_hold_valid <= 1'b1;
                    end

                    if (aw_available && w_available) begin
                        reg_write_addr <= write_addr_next;
                        reg_wdata <= write_data_next;
                        reg_wr_en <= |write_strb_next;
                        aw_hold_valid <= 1'b0;
                        w_hold_valid <= 1'b0;
                        wr_state <= WR_APPLY;
                    end
                end

                WR_APPLY: begin
                    S_AXI_BVALID <= 1'b1;
                    wr_state <= WR_RESP;
                end

                WR_RESP: begin
                    if (S_AXI_BVALID && S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                        wr_state <= WR_COLLECT;
                    end
                end

                default: begin
                    wr_state <= WR_COLLECT;
                    S_AXI_BVALID <= 1'b0;
                    aw_hold_valid <= 1'b0;
                    w_hold_valid <= 1'b0;
                end
            endcase

            case (rd_state)
                RD_IDLE: begin
                    if (ar_accept) begin
                        reg_read_addr <= S_AXI_ARADDR;
                        reg_rd_en <= 1'b1;
                        rd_state <= RD_CAPTURE;
                    end
                end

                RD_CAPTURE: begin
                    S_AXI_RDATA <= reg_rdata;
                    S_AXI_RVALID <= 1'b1;
                    rd_state <= RD_RESP;
                end

                RD_RESP: begin
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        S_AXI_RVALID <= 1'b0;
                        rd_state <= RD_IDLE;
                    end
                end

                default: begin
                    rd_state <= RD_IDLE;
                    S_AXI_RVALID <= 1'b0;
                end
            endcase
        end
    end

    protection_ip_top_reg_controlled #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(CNT_WIDTH),
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .REG_DATA_WIDTH(AXI_DATA_WIDTH),
        .HEALTH_CNT_WIDTH(HEALTH_CNT_WIDTH)
    ) u_reg_controlled_top (
        .clk(ACLK),
        .rst_n(ARESETN),
        .sample_valid(sample_valid),
        .wr_en(reg_wr_en),
        .rd_en(reg_rd_en),
        .addr(reg_addr),
        .wdata(reg_wdata),
        .rdata(reg_rdata),
        .i_ch1(i_ch1),
        .i_ch2(i_ch2),
        .pwm_raw(pwm_raw),
        .pwm_out(pwm_out),
        .fault_valid(fault_valid),
        .fault_latched(fault_latched),
        .fault_code(fault_code),
        .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state)
    );
endmodule
