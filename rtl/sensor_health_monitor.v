module sensor_health_monitor #(
    parameter DATA_WIDTH = 12,
    parameter CNT_WIDTH  = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sample_valid,
    input  wire [DATA_WIDTH-1:0] i_ch1,
    input  wire [DATA_WIDTH-1:0] i_ch2,
    input  wire [DATA_WIDTH-1:0] th_open,
    input  wire [DATA_WIDTH-1:0] th_sat,
    input  wire [DATA_WIDTH-1:0] th_stuck_delta,
    input  wire [CNT_WIDTH-1:0]  th_persist,
    output reg  sensor_open_flag,
    output reg  sensor_sat_flag,
    output reg  sensor_stuck_flag
);
    reg [DATA_WIDTH-1:0] prev_ch1, prev_ch2;
    reg [CNT_WIDTH-1:0] open_cnt, sat_cnt, stuck_cnt;

    wire ch1_open = (i_ch1 <= th_open);
    wire ch2_open = (i_ch2 <= th_open);
    wire ch1_sat  = (i_ch1 >= th_sat);
    wire ch2_sat  = (i_ch2 >= th_sat);

    wire [DATA_WIDTH-1:0] d1 = (i_ch1 >= prev_ch1) ? (i_ch1 - prev_ch1) : (prev_ch1 - i_ch1);
    wire [DATA_WIDTH-1:0] d2 = (i_ch2 >= prev_ch2) ? (i_ch2 - prev_ch2) : (prev_ch2 - i_ch2);
    wire both_stable = (d1 <= th_stuck_delta) && (d2 <= th_stuck_delta);

    function [CNT_WIDTH-1:0] inc_sat;
        input [CNT_WIDTH-1:0] v;
        begin
            inc_sat = (v == {CNT_WIDTH{1'b1}}) ? v : v + 1'b1;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_ch1 <= {DATA_WIDTH{1'b0}};
            prev_ch2 <= {DATA_WIDTH{1'b0}};
            open_cnt <= {CNT_WIDTH{1'b0}};
            sat_cnt  <= {CNT_WIDTH{1'b0}};
            stuck_cnt <= {CNT_WIDTH{1'b0}};
            sensor_open_flag  <= 1'b0;
            sensor_sat_flag   <= 1'b0;
            sensor_stuck_flag <= 1'b0;
        end else if (sample_valid) begin
            prev_ch1 <= i_ch1;
            prev_ch2 <= i_ch2;

            if (ch1_open || ch2_open) open_cnt <= inc_sat(open_cnt);
            else open_cnt <= {CNT_WIDTH{1'b0}};

            if (ch1_sat || ch2_sat) sat_cnt <= inc_sat(sat_cnt);
            else sat_cnt <= {CNT_WIDTH{1'b0}};

            if (both_stable) stuck_cnt <= inc_sat(stuck_cnt);
            else stuck_cnt <= {CNT_WIDTH{1'b0}};

            sensor_open_flag  <= (open_cnt  >= th_persist);
            sensor_sat_flag   <= (sat_cnt   >= th_persist);
            sensor_stuck_flag <= (stuck_cnt >= th_persist);
        end
    end
endmodule
