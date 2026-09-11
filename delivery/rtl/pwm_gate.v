module pwm_gate #(
    parameter DISABLED_LEVEL = 1'b0
)(
    input  wire pwm_raw,
    input  wire pwm_disable,
    output wire pwm_out
);
    assign pwm_out = pwm_disable ? DISABLED_LEVEL : pwm_raw;
endmodule
