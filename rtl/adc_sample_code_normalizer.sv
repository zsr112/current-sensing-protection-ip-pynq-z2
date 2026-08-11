`include "generated/stage2f_adc_source_profile.svh"

// Stage 2F-D digital-only telemetry fork.  This module is intentionally
// parallel to the raw protection path and has no ready/backpressure input.
module adc_sample_code_normalizer #(
    parameter integer RAW_WIDTH = `STAGE2F_PROFILE_RAW_WIDTH,
    parameter integer SEQUENCE_WIDTH = 32,
    parameter integer NORMALIZED_WIDTH = `STAGE2F_PROFILE_NORMALIZED_WIDTH,
    parameter integer PROFILE_CONFIGURED = `STAGE2F_PROFILE_CONFIGURED,
    parameter [1:0] PROFILE_ENCODING = `STAGE2F_PROFILE_ENCODING,
    parameter [RAW_WIDTH-1:0] PROFILE_ZERO_CODE =
        `STAGE2F_PROFILE_ZERO_CODE,
    parameter integer CH1_POLARITY_NEGATIVE =
        `STAGE2F_PROFILE_CH1_POLARITY_NEGATIVE,
    parameter integer CH2_POLARITY_NEGATIVE =
        `STAGE2F_PROFILE_CH2_POLARITY_NEGATIVE
)(
    input wire ACLK,
    input wire local_resetn,
    input wire raw_delivery_valid,
    input wire [SEQUENCE_WIDTH-1:0] raw_sequence,
    input wire [RAW_WIDTH-1:0] raw_ch1,
    input wire [RAW_WIDTH-1:0] raw_ch2,
    output reg normalized_valid,
    output reg [SEQUENCE_WIDTH-1:0] normalized_sequence,
    output reg signed [NORMALIZED_WIDTH-1:0] normalized_ch1,
    output reg signed [NORMALIZED_WIDTH-1:0] normalized_ch2,
    output wire profile_configured,
    output wire profile_valid,
    output wire profile_encoding_supported,
    output wire profile_zero_code_valid,
    output wire profile_polarity_valid
);
    localparam [1:0] ENCODING_UNKNOWN = 2'd0;
    localparam [1:0] ENCODING_UNSIGNED_WITH_ZERO_CODE = 2'd1;
    localparam [1:0] ENCODING_TWOS_COMPLEMENT = 2'd2;

    wire encoding_supported;
    wire zero_code_valid;
    wire polarity_valid;

    assign encoding_supported =
        (PROFILE_ENCODING == ENCODING_UNSIGNED_WITH_ZERO_CODE) ||
        (PROFILE_ENCODING == ENCODING_TWOS_COMPLEMENT);
    assign zero_code_valid =
        (PROFILE_ENCODING == ENCODING_UNSIGNED_WITH_ZERO_CODE) ||
        ((PROFILE_ENCODING == ENCODING_TWOS_COMPLEMENT) &&
         (PROFILE_ZERO_CODE == {RAW_WIDTH{1'b0}}));
    assign polarity_valid =
        ((CH1_POLARITY_NEGATIVE == 0) || (CH1_POLARITY_NEGATIVE == 1)) &&
        ((CH2_POLARITY_NEGATIVE == 0) || (CH2_POLARITY_NEGATIVE == 1));
    assign profile_configured = (PROFILE_CONFIGURED != 0);
    assign profile_encoding_supported = encoding_supported;
    assign profile_zero_code_valid = zero_code_valid;
    assign profile_polarity_valid = polarity_valid;
    assign profile_valid = profile_configured && encoding_supported &&
                           zero_code_valid && polarity_valid;

    // These guards deliberately name undefined modules.  Invalid generated
    // constants fail at elaboration instead of silently producing telemetry.
    generate
        if (RAW_WIDTH != 12) begin : g_invalid_raw_width
            STAGE2F_PARAMETER_ERROR_RAW_WIDTH_MUST_BE_12 u_parameter_error();
        end
        if (NORMALIZED_WIDTH != 13) begin : g_invalid_normalized_width
            STAGE2F_PARAMETER_ERROR_NORMALIZED_WIDTH_MUST_BE_13
                u_parameter_error();
        end
        if (SEQUENCE_WIDTH < 1) begin : g_invalid_sequence_width
            STAGE2F_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_POSITIVE
                u_parameter_error();
        end
        if (PROFILE_CONFIGURED &&
            !((PROFILE_ENCODING == ENCODING_UNSIGNED_WITH_ZERO_CODE) ||
              (PROFILE_ENCODING == ENCODING_TWOS_COMPLEMENT))) begin : g_invalid_encoding
            STAGE2F_PARAMETER_ERROR_UNSUPPORTED_CONFIGURED_ENCODING
                u_parameter_error();
        end
        if (PROFILE_CONFIGURED &&
            (PROFILE_ENCODING == ENCODING_TWOS_COMPLEMENT) &&
            (PROFILE_ZERO_CODE != {RAW_WIDTH{1'b0}})) begin : g_invalid_zero_code
            STAGE2F_PARAMETER_ERROR_INVALID_CONFIGURED_ZERO_CODE
                u_parameter_error();
        end
        if (PROFILE_CONFIGURED &&
            !(((CH1_POLARITY_NEGATIVE == 0) ||
               (CH1_POLARITY_NEGATIVE == 1)) &&
              ((CH2_POLARITY_NEGATIVE == 0) ||
               (CH2_POLARITY_NEGATIVE == 1)))) begin : g_invalid_polarity
            STAGE2F_PARAMETER_ERROR_INVALID_CONFIGURED_POLARITY
                u_parameter_error();
        end
    endgenerate

    // The function uses a widened signed intermediate for both coding modes.
    // In particular, two's-complement 12'h800 is -2048 before polarity and
    // therefore becomes +2048 (representable in signed 13 bits) when reversed.
    function automatic signed [NORMALIZED_WIDTH-1:0] normalize_code;
        input [RAW_WIDTH-1:0] raw_code;
        input integer polarity_negative;
        reg signed [NORMALIZED_WIDTH-1:0] raw_wide;
        reg signed [NORMALIZED_WIDTH-1:0] zero_wide;
        reg signed [NORMALIZED_WIDTH-1:0] decoded;
        reg signed [NORMALIZED_WIDTH-1:0] polarity_value;
        begin
            raw_wide = $signed({1'b0, raw_code});
            zero_wide = $signed({1'b0, PROFILE_ZERO_CODE});
            decoded = {NORMALIZED_WIDTH{1'b0}};
            if (PROFILE_ENCODING == ENCODING_UNSIGNED_WITH_ZERO_CODE) begin
                decoded = raw_wide - zero_wide;
            end else if (PROFILE_ENCODING == ENCODING_TWOS_COMPLEMENT) begin
                decoded = $signed({raw_code[RAW_WIDTH-1], raw_code});
            end
            polarity_value = decoded;
            if (polarity_negative)
                polarity_value = $signed(-decoded);
            normalize_code = polarity_value;
        end
    endfunction

    // One registered stage gives fixed latency one ACLK and initiation
    // interval one.  Reset clears valid, identity, and payload state.
    always @(posedge ACLK or negedge local_resetn) begin
        if (!local_resetn) begin
            normalized_valid <= 1'b0;
            normalized_sequence <= {SEQUENCE_WIDTH{1'b0}};
            normalized_ch1 <= {NORMALIZED_WIDTH{1'b0}};
            normalized_ch2 <= {NORMALIZED_WIDTH{1'b0}};
        end else begin
            normalized_valid <= 1'b0;
            if (!profile_valid) begin
                normalized_sequence <= {SEQUENCE_WIDTH{1'b0}};
                normalized_ch1 <= {NORMALIZED_WIDTH{1'b0}};
                normalized_ch2 <= {NORMALIZED_WIDTH{1'b0}};
            end else if (raw_delivery_valid) begin
                normalized_valid <= 1'b1;
                normalized_sequence <= raw_sequence;
                normalized_ch1 <= normalize_code(
                    raw_ch1, CH1_POLARITY_NEGATIVE);
                normalized_ch2 <= normalize_code(
                    raw_ch2, CH2_POLARITY_NEGATIVE);
            end
        end
    end
endmodule
