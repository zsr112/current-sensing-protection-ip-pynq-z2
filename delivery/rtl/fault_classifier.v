`include "fault_defs.vh"

module fault_classifier(
    input  wire clk,
    input  wire rst_n,
    input  wire oc_any,
    input  wire oc_both,
    input  wire mismatch_flag,
    input  wire sensor_open_flag,
    input  wire sensor_sat_flag,
    input  wire sensor_stuck_flag,
    output reg  fault_valid,
    output reg  [7:0] fault_code
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_valid <= 1'b0;
            fault_code  <= `FAULT_NONE;
        end else begin
            fault_valid <= oc_any | mismatch_flag | sensor_open_flag | sensor_sat_flag | sensor_stuck_flag;

            if (oc_any && (mismatch_flag || sensor_open_flag || sensor_sat_flag || sensor_stuck_flag))
                fault_code <= `FAULT_OC_WITH_SENSOR;
            else if (oc_both || oc_any)
                fault_code <= `FAULT_OVERCURRENT;
            else if (sensor_sat_flag)
                fault_code <= `FAULT_SENSOR_SATURATION;
            else if (sensor_open_flag)
                fault_code <= `FAULT_SENSOR_OPEN;
            else if (sensor_stuck_flag)
                fault_code <= `FAULT_SENSOR_STUCK;
            else if (mismatch_flag)
                fault_code <= `FAULT_SENSOR_MISMATCH;
            else
                fault_code <= `FAULT_NONE;
        end
    end
endmodule

// Stage 2G transaction register.  Its input is the edge-1 raw comparator and
// health decision; this register is edge 2 of the frozen delivery-to-policy
// schedule.  A zero bitmap is still a valid completed evaluation.
module stage2g_fault_evaluation_pipeline #(
    parameter SEQUENCE_WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        evaluation_input_valid,
    input  wire [SEQUENCE_WIDTH-1:0] evaluation_input_sequence,
    input  wire        evaluation_input_integrity_clean,
    input  wire        cause_ch1_overcurrent,
    input  wire        cause_ch2_overcurrent,
    input  wire        cause_sensor_mismatch,
    input  wire        cause_sensor_open,
    input  wire        cause_sensor_saturation,
    input  wire        cause_sensor_stuck,
    output reg         fault_eval_valid,
    output reg  [SEQUENCE_WIDTH-1:0] fault_eval_sequence,
    output reg  [5:0]  fault_eval_bitmap,
    output reg  [7:0]  fault_eval_code,
    output reg         fault_eval_integrity_clean
);
    wire [5:0] evaluation_bitmap;

    generate
        if ((SEQUENCE_WIDTH < 16) || (SEQUENCE_WIDTH > 32)) begin :
            g_invalid_sequence_width
            STAGE2G_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_16_TO_32
                u_parameter_error();
        end
    endgenerate

    assign evaluation_bitmap = {
        cause_sensor_stuck,
        cause_sensor_saturation,
        cause_sensor_open,
        cause_sensor_mismatch,
        cause_ch2_overcurrent,
        cause_ch1_overcurrent
    };

    function [7:0] priority_encode_bitmap;
        input [5:0] bitmap;
        reg any_overcurrent;
        reg any_sensor;
        begin
            any_overcurrent = |bitmap[1:0];
            any_sensor = |bitmap[5:2];
            if (any_overcurrent && any_sensor)
                priority_encode_bitmap = `FAULT_OC_WITH_SENSOR;
            else if (any_overcurrent)
                priority_encode_bitmap = `FAULT_OVERCURRENT;
            else if (bitmap[4])
                priority_encode_bitmap = `FAULT_SENSOR_SATURATION;
            else if (bitmap[3])
                priority_encode_bitmap = `FAULT_SENSOR_OPEN;
            else if (bitmap[5])
                priority_encode_bitmap = `FAULT_SENSOR_STUCK;
            else if (bitmap[2])
                priority_encode_bitmap = `FAULT_SENSOR_MISMATCH;
            else
                priority_encode_bitmap = `FAULT_NONE;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_eval_valid <= 1'b0;
            fault_eval_sequence <= {SEQUENCE_WIDTH{1'b0}};
            fault_eval_bitmap <= 6'd0;
            fault_eval_code <= `FAULT_NONE;
            fault_eval_integrity_clean <= 1'b0;
        end else begin
            fault_eval_valid <= evaluation_input_valid;
            if (evaluation_input_valid) begin
                fault_eval_sequence <= evaluation_input_sequence;
                fault_eval_bitmap <= evaluation_bitmap;
                fault_eval_code <= priority_encode_bitmap(
                    evaluation_bitmap);
                fault_eval_integrity_clean <=
                    evaluation_input_integrity_clean;
            end else begin
                fault_eval_sequence <= {SEQUENCE_WIDTH{1'b0}};
                fault_eval_bitmap <= 6'd0;
                fault_eval_code <= `FAULT_NONE;
                fault_eval_integrity_clean <= 1'b0;
            end
        end
    end
endmodule
