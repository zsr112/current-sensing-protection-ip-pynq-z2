module reset_release_sync (
    input  wire clk,
    input  wire async_rst_n,
    output wire sync_rst_n
);
    // Fixed at two stages so an invalid synchronizer depth cannot be selected.
    // Both stages assert low asynchronously; ones then advance only on clk.
    (* ASYNC_REG = "TRUE" *) reg [1:0] release_pipe;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n)
            release_pipe <= 2'b00;
        else
            release_pipe <= {release_pipe[0], 1'b1};
    end

    assign sync_rst_n = release_pipe[1];
endmodule
