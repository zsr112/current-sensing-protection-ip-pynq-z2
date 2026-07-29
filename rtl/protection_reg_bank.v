module protection_reg_bank #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire wr_en,
    input  wire rd_en,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output reg  [DATA_WIDTH-1:0] rd_data,

    input  wire fault_valid,
    input  wire fault_latched,
    input  wire [7:0] fault_code_latched,
    input  wire [11:0] i_ch1_mon,
    input  wire [11:0] i_ch2_mon,
    output reg  pwm_enable,
    output reg  clear_fault_pulse,
    output reg  [11:0] th_oc_ch1,
    output reg  [11:0] th_oc_ch2,
    output reg  [11:0] th_diff,
    output reg  [15:0] pwm_period,
    output reg  [15:0] pwm_duty
);
    localparam REG_CTRL       = 8'h00;
    localparam REG_STATUS     = 8'h04;
    localparam REG_FAULT_CODE = 8'h08;
    localparam REG_I_CH1      = 8'h0C;
    localparam REG_I_CH2      = 8'h10;
    localparam REG_TH_OC1     = 8'h14;
    localparam REG_TH_OC2     = 8'h18;
    localparam REG_TH_DIFF    = 8'h1C;
    localparam REG_PWM_PERIOD = 8'h20;
    localparam REG_PWM_DUTY   = 8'h24;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_enable <= 1'b0;
            clear_fault_pulse <= 1'b0;
            th_oc_ch1 <= 12'd3000;
            th_oc_ch2 <= 12'd3000;
            th_diff   <= 12'd200;
            pwm_period <= 16'd1000;
            pwm_duty   <= 16'd500;
        end else begin
            clear_fault_pulse <= 1'b0;
            if (wr_en) begin
                case (addr)
                    REG_CTRL: begin
                        pwm_enable <= wr_data[0];
                        clear_fault_pulse <= wr_data[1];
                    end
                    REG_TH_OC1: th_oc_ch1 <= wr_data[11:0];
                    REG_TH_OC2: th_oc_ch2 <= wr_data[11:0];
                    REG_TH_DIFF: th_diff <= wr_data[11:0];
                    REG_PWM_PERIOD: pwm_period <= wr_data[15:0];
                    REG_PWM_DUTY: pwm_duty <= wr_data[15:0];
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (addr)
            REG_CTRL:       rd_data = {30'd0, 1'b0, pwm_enable};
            REG_STATUS:     rd_data = {30'd0, fault_latched, fault_valid};
            REG_FAULT_CODE: rd_data = {24'd0, fault_code_latched};
            REG_I_CH1:      rd_data = {20'd0, i_ch1_mon};
            REG_I_CH2:      rd_data = {20'd0, i_ch2_mon};
            REG_TH_OC1:     rd_data = {20'd0, th_oc_ch1};
            REG_TH_OC2:     rd_data = {20'd0, th_oc_ch2};
            REG_TH_DIFF:    rd_data = {20'd0, th_diff};
            REG_PWM_PERIOD: rd_data = {16'd0, pwm_period};
            REG_PWM_DUTY:   rd_data = {16'd0, pwm_duty};
            default:        rd_data = 32'd0;
        endcase
    end
endmodule
