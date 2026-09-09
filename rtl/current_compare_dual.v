module current_compare_dual #(
    parameter DATA_WIDTH = 12
)(
    input  wire [DATA_WIDTH-1:0] i_ch1,
    input  wire [DATA_WIDTH-1:0] i_ch2,
    input  wire [DATA_WIDTH-1:0] th_oc_ch1,
    input  wire [DATA_WIDTH-1:0] th_oc_ch2,
    input  wire [DATA_WIDTH-1:0] th_diff,
    output wire oc_ch1,
    output wire oc_ch2,
    output wire oc_any,
    output wire oc_both,
    output wire mismatch_flag,
    output wire [DATA_WIDTH-1:0] abs_diff
);
    assign abs_diff = (i_ch1 >= i_ch2) ? (i_ch1 - i_ch2) : (i_ch2 - i_ch1);
    assign oc_ch1 = (i_ch1 > th_oc_ch1);
    assign oc_ch2 = (i_ch2 > th_oc_ch2);
    assign oc_any  = oc_ch1 | oc_ch2;
    assign oc_both = oc_ch1 & oc_ch2;
    assign mismatch_flag = (abs_diff > th_diff);
endmodule
