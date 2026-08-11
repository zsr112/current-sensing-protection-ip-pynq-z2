# Vivado Rebuild Guide

Use Vivado 2024.1 with the PYNQ-Z2 board files installed. Set `PROTECTION_IP_VIVADO_BUILD_ROOT` to an external empty writable directory.

From the repository root, run the Tcl entrypoints in this order:

1. `vivado/tcl/create_pynq_z2_project_stage1_boardpart.tcl`
2. `vivado/tcl/package_protection_ip_stage2_axi_lite.tcl`
3. `vivado/tcl/create_pynq_z2_stage2_bd.tcl`

This is the complete supported public reconstruction route. No legacy pre-board, debug, or controlled-stimulus entrypoint is included. The route creates the project, packages the IP, creates and validates the SAFE_INERT block design, and saves the block design. It does not run synthesis, implementation, routing, bitstream generation, hardware export, or board actions.

A fresh build creates new unvalidated project metadata and does not inherit the accepted BIT/HWH proof. The accepted programming authority remains under `deploy/pynq/artifacts/`.
