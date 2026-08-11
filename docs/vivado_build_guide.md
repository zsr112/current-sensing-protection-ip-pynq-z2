# Vivado Rebuild Guide

Use Vivado 2024.1 with the PYNQ-Z2 board files installed. Set `PROTECTION_IP_VIVADO_BUILD_ROOT` to an external empty writable directory.

Run the Tcl entrypoints in this order:

1. `vivado/tcl/create_pynq_z2_project_stage1_boardpart.tcl`
2. `vivado/tcl/package_protection_ip_stage2_axi_lite.tcl`
3. `vivado/tcl/create_pynq_z2_stage2_bd.tcl`
4. Optional reviewed debug/stimulus Tcl as required for inspection

These inputs do not run implementation automatically. A fresh build creates new unvalidated artifacts and does not inherit the accepted BIT/HWH proof. The accepted programming authority remains under `deploy/pynq/artifacts/`.
