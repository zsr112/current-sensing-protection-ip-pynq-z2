module moving_avg_filter #(
    parameter DATA_WIDTH  = 12,
    parameter WINDOW_LOG2 = 3
)(
    input  wire clk,
    input  wire rst_n,
    input  wire valid_in,
    input  wire [DATA_WIDTH-1:0] data_in,
    output reg  valid_out,
    output reg  [DATA_WIDTH-1:0] data_out
);
    localparam WINDOW_SIZE = (1 << WINDOW_LOG2);
    localparam SUM_WIDTH   = DATA_WIDTH + WINDOW_LOG2 + 1;

    reg [DATA_WIDTH-1:0] window_mem [0:WINDOW_SIZE-1];
    reg [WINDOW_LOG2-1:0] wr_ptr;
    reg [WINDOW_LOG2:0] fill_count;
    reg [SUM_WIDTH-1:0] sum;

    integer i;
    reg [SUM_WIDTH-1:0] sum_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= {WINDOW_LOG2{1'b0}};
            fill_count <= {(WINDOW_LOG2+1){1'b0}};
            sum        <= {SUM_WIDTH{1'b0}};
            valid_out  <= 1'b0;
            data_out   <= {DATA_WIDTH{1'b0}};
            for (i = 0; i < WINDOW_SIZE; i = i + 1)
                window_mem[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            valid_out <= 1'b0;
            if (valid_in) begin
                sum_next = sum + data_in - window_mem[wr_ptr];
                window_mem[wr_ptr] <= data_in;
                wr_ptr <= wr_ptr + 1'b1;
                sum <= sum_next;

                if (fill_count < WINDOW_SIZE)
                    fill_count <= fill_count + 1'b1;

                valid_out <= 1'b1;
                if (fill_count < WINDOW_SIZE)
                    data_out <= sum_next / (fill_count + 1'b1);
                else
                    data_out <= sum_next >> WINDOW_LOG2;
            end
        end
    end
endmodule
