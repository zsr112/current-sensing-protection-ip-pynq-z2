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
