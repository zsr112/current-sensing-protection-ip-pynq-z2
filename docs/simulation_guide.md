# Simulation Guide

## Requirements

Use Icarus Verilog with SystemVerilog 2012 support and vvp. On Windows, the validated local route is MSYS2 bash with the mingw64 Icarus tools on PATH.

## Run

From the repository root:

    bash sim/run_iverilog.sh all

The runner compiles 12 RTL/header sources against ten canonical testbenches. Its expected summary is PASS=10 FAIL=0. Generated files are placed under sim/build and sim/waves and are ignored; remove those directories after a validation session when a source-only tree is required.

## Coverage

The suite covers PWM boundaries, dual comparison, moving average, sensor health, classifier priority, fault FSM, core integration, register behavior, direct register-controlled integration, and AXI-Lite transport.

Passing simulation does not prove Vivado synthesis, implementation, timing, hardware behavior, or board safety.
