# Windows Rebuild Changed Files

Comparison baseline: `0eb61178ece7f77d53d48655caf3a579fd477014`.
The final tagged commit and its exact tree are recorded by the release VERSION.
No hardware RTL, constraints or software runtime changed after the physical
source commit `3cf68b27c7e30c1ac3729bd9f3b79598531d0be2`.

| Change | File |
| --- | --- |
| Modified | README.md |
| Added | docs/bringup/windows_board_session.md |
| Modified | docs/project/current_project_status.md |
| Added | docs/project/windows_rebuild_status_20260909.md |
| Added | docs/review/windows_b2_cdc4_review_20260909.md |
| Added | docs/review/windows_board_test_corrections_20260909.md |
| Added | docs/review/windows_rebuild_changed_files_20260909.md |
| Modified | sim/run_iverilog.sh |
| Added | tb/stage2i/tb_stage2_board_c2_plan.sv |
| Modified | tb/tb_protection_ip_top_axi_lite.sv |
| Modified | tb/tb_protection_ip_top_reg_controlled.sv |
| Modified | tests/stage1_board_ila_binding_fixture_tests.tcl |
| Modified | tests/test_stage1_board_functional_validation.py |
| Added | tests/test_stage2_board_session.py |
| Added | tests/test_windows_board_release.py |
| Added | tools/board_validation/build_stage2_board_session.py |
| Modified | tools/board_validation/stage1_board_evidence_analyzer.py |
| Modified | tools/board_validation/stage1_board_functional_validation.py |
| Modified | tools/board_validation/stage1_board_ila_common.tcl |
| Added | tools/board_validation/stage2_board_capture_pair.tcl |
| Added | tools/board_validation/stage2_board_jtag_probe.tcl |
| Added | tools/board_validation/stage2_board_session.py |
| Added | tools/board_validation/stage2_board_session_host.py |
| Added | tools/board_validation/stage2_fifo_routed_audit.tcl |
| Added | tools/board_validation/start_stage2_board_session.ps1 |
| Modified | tools/build_current_release.py |
| Added | tools/build_windows_board_release.py |
| Added | tools/generate_rebuilt_evidence.py |
| Added | tools/preflight.py |
| Added | tools/run_stage2_board_plan_rtl.py |
| Modified | tools/run_stage2g_functional_rtl.py |
| Added | tools/run_windows_final_verification.py |
| Added | tools/runtime_config.py |
| Modified | tools/verify_current_release.py |
| Added | tools/verify_windows_board_release.py |

External outputs include fresh B1/B2 physical builds, board execution packages,
raw evidence, routed FIFO audit, final regression logs, selected delivery and
final audit receipts. Local START_BOARD wrappers handle interactive authentication;
they contain no passwords and are not shipped in the portable snapshot.
