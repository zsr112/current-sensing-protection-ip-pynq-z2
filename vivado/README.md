# Vivado Inputs

The Tcl, generated IP-XACT register metadata, and CDC constraints in this directory are the portable delivery reconstruction inputs. Set `PROTECTION_IP_VIVADO_BUILD_ROOT` to an external build root before running Vivado 2024.1.

The only supported entrypoints are project creation, Stage2 AXI-Lite IP packaging, and Stage2 SAFE_INERT block-design creation, in that order. Legacy pre-board, debug, and controlled-stimulus entrypoints are not part of this delivery.

The production block-design profile is SAFE_INERT. Rebuild output is new and unvalidated; use the accepted BIT/HWH pair in `deploy/` for the reviewed release.
