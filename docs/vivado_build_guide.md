# Vivado Structural Reconstruction Guide

Use Vivado 2024.1 with the PYNQ-Z2 board files installed. Set `PROTECTION_IP_VIVADO_BUILD_ROOT` to a fresh external empty short path.

From the repository root, run the single supported entrypoint:

```text
vivado -mode batch -source vivado/tcl/reconstruct_stage2_b1_safe_inert.tcl
```

This compact delivery adapter is derived from the current engineering production authority at `fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl`, bound to engineering commit `9c5e6f6ac7dc311f12755c8b1713433d35e39bff`. The older standalone project, package, and BD scripts are classified `HISTORICAL_ONLY` upstream and are not delivered as supported entrypoints.

The adapter packages the IP with relative generated-header dependencies and implementation-only CDC constraints, creates and validates the accepted B1 `SAFE_INERT` topology, generates block-design output products and `protection_system_wrapper`, and sets that wrapper as project top. It does not run synthesis, implementation, routing, bitstream generation, XSA export, Hardware Manager, or board actions.

The structural contract is recorded in `VIVADO_RECONSTRUCTION_AUTHORITY.json`. It includes protection IP at `0x43C00000`, AXI GPIO at `0x41200000`, GPIO-driven channel slices, `adc_sample_valid=0`, destination System ILA probe 11 for `adc_sample_ready`, and no B2 producer or source-domain ILA.

A fresh reconstruction does not inherit the accepted physical proof and is not expected to reproduce accepted physical artifact bytes. The reviewed programming authority remains the accepted BIT/HWH pair under `deploy/pynq/artifacts/`. Any fresh output remains unvalidated until separately synthesized, implemented, and validated under an approved engineering flow.
