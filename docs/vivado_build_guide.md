# Vivado Build Guide

## Supported Baseline

The reconstruction inputs target Vivado 2024.1, PYNQ-Z2 board part tul.com.tw:pynq-z2:part0:1.0, and device xc7z020clg400-1.

## External Build Root

Set PROTECTION_IP_VIVADO_BUILD_ROOT to an empty external path represented here as <vivado-path>. Generated projects and IP output must remain outside <repo-root>.

## Reconstruction Order

1. Run vivado/tcl/create_pynq_z2_project_stage1_boardpart.tcl.
2. Run vivado/tcl/package_protection_ip_stage2_axi_lite.tcl.
3. Run vivado/tcl/create_pynq_z2_stage2_bd.tcl.
4. Review and, when appropriate, run the controlled-stimulus and Stage 2B debug Tcl inputs.
5. Perform synthesis, implementation, bitstream generation, and hardware export only as a separately controlled operation.

The Tcl copies retain the development-source build logic while replacing machine-local roots with PROTECTION_IP_VIVADO_BUILD_ROOT. The XDC is a reviewed pre-board placeholder and does not assign physical user pins.

## Artifact Meaning

A fresh build creates new, unvalidated artifacts. It does not reproduce the accepted artifact identity by assertion and does not inherit Stage 1G board proof. The accepted direct-deployment BIT/HWH pair remains only under deploy/pynq/artifacts.
