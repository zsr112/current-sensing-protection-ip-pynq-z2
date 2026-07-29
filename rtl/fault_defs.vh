`ifndef FAULT_DEFS_VH
`define FAULT_DEFS_VH

// Fault code map for the current-sensing digital protection IP.
`define FAULT_NONE              8'h00
`define FAULT_OVERCURRENT       8'h01
`define FAULT_SENSOR_MISMATCH   8'h02
`define FAULT_SENSOR_OPEN       8'h03
`define FAULT_SENSOR_SATURATION 8'h04
`define FAULT_SENSOR_STUCK      8'h05
`define FAULT_OC_WITH_SENSOR    8'h06

`endif
