module pwm_gen #(
    parameter CNT_WIDTH = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    input  wire [CNT_WIDTH-1:0] period,
    input  wire [CNT_WIDTH-1:0] duty,
    output reg  pwm_raw
);
    reg [CNT_WIDTH-1:0] cnt;
    wire period_zero = (period == {CNT_WIDTH{1'b0}});
    wire [CNT_WIDTH-1:0] duty_clamped = (duty >= period) ? period : duty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= {CNT_WIDTH{1'b0}};
            pwm_raw <= 1'b0;
        end else if (!enable || period_zero) begin
            cnt     <= {CNT_WIDTH{1'b0}};
            pwm_raw <= 1'b0;
        end else begin
            if (cnt >= period - 1'b1)
                cnt <= {CNT_WIDTH{1'b0}};
            else
                cnt <= cnt + 1'b1;

            pwm_raw <= (cnt < duty_clamped);
        end
    end
endmodule
