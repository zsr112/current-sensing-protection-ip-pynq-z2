# Vivado Structural Reconstruction

The single supported public entrypoint is `tcl/reconstruct_stage2_b1_safe_inert.tcl`. Set `PROTECTION_IP_VIVADO_BUILD_ROOT` to a fresh external empty short path before running it with Vivado 2024.1.

The adapter is narrowly derived from the current engineering runner-v2 production semantics. It packages the IP portably, constructs and validates the accepted B1 `SAFE_INERT` topology, generates BD output products and the wrapper, and sets `protection_system_wrapper` as project top. Historical standalone engineering scripts are not supported public reconstruction authorities.

The adapter cannot select the B2 ready-aware synthetic producer profile and does not run synthesis, implementation, routing, bitstream generation, XSA export, or board actions. Fresh output is structurally reconstructed but unvalidated. Use the accepted BIT/HWH pair in `deploy/` for the reviewed release.
