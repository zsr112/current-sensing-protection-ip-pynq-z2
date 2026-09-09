# Windows Rebuild And Board Verification

This is the current Windows campaign, separate from historical accepted Stage 1
and Stage 2 records. The engineering branch is `codex/windows-rebuild-20260908`.

## Verified Board Campaign

Execution `S1E-B2-BOARD-20260909-R4` passed all eight required scenarios and both
supporting scenarios. The external board receipt is 68,022 bytes, SHA-256
`85602e2f71b5950340fa680f4d6ea0f44ce95b5fc9d950e44bcd0c249cb71354`.
Its 225 indexed files reconcile. Twenty original ILA CSV files contain 4,096
samples each; actual probe/trigger settings, logs and per-scenario receipts remain
with the original evidence. Analysis was independently repeated after collection.

| Scenario | Status |
| --- | --- |
| Normal PWM | PASS |
| CH1 overcurrent | PASS |
| CH2 overcurrent | PASS |
| Differential fault | PASS |
| Live clear rejection | PASS |
| Synthetic sample-source removal | PASS |
| Clear recovery / RESET_WAIT | PASS |
| Recovered PWM | PASS |
| Source backpressure | PASS |
| C2 individual faults, first-fault identity and recovery | PASS |

SSH user is `xilinx`; declared board is PYNQ-Z2, independently observed JTAG die
`xc7z020`. Board image is PynqLinux 3.0 Carlisle, Python 3.10.4, PYNQ 3.1.1.
The loaded overlay clocks are 100 MHz and 125 MHz, with register-map ABI 1.1.
Board wall-clock time is untrusted; host UTC and ordered actions establish chronology.
Final source/destination transaction counts are both 1,189, last sequences both
1,188, all integrity error counters zero, producer idle and CTRL zero (PWM disabled).

## Rebuilt Hardware

Physical execution: `S1E-B2-REBUILT-WINDOWS-20260909T000000Z`.
Source commit: `3cf68b27c7e30c1ac3729bd9f3b79598531d0be2`.
Source tree: `338bbcc360c82f2ce9b4e6747bc98a60e72ffd26`.
Vivado 2024.1, build 5076996. Profile: `READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS`.

| Artifact | SHA-256 |
| --- | --- |
| BIT | `2ef091e6550ba01d00cd677d9b9676fc38f3cdd4380d9925244fb705342ec518` |
| HWH | `0b011b48829ef1e29c917a83ecdbe1e96c012dd86fda4ac7cf4d5abcc4ee71fc` |
| LTX | `7f7c67eb6851ebaa2e9b67d1efd79a7591cb375ab855eae8450393dc4110dc21` |
| XSA (external provenance) | `e80324278450b0e1bccc713931d229adb025d9a1f30549029a77aab5eb010adf` |

The clean synthesis and routed implementation completed with exit 0. WNS is
0.902 ns, WHS 0.020 ns, WPWS 2.750 ns; failing and unconstrained internal endpoints
are zero. DRC retains PDCN-1569 x3 and RTSTAT-10 x1 warnings. Methodology retains
LUTAR-1 x4, TIMING-9 x1 and XDCB-5 x4 warnings. CDC retains CDC-4 Critical x1,
CDC-6 Warning x13, CDC-15 Warning x65, CDC-3 Info x54 and CDC-9 Info x3.

The [FIFO review](../review/windows_b2_cdc4_review_20260909.md) checks all 456
payload paths, eight Gray-pointer paths and 16 synchronizer stages. The evidence
does not justify an RTL or constraint correction; no severity was lowered and
no waiver introduced. DRC findings concern generated debug/SmartConnect logic;
LUTAR findings concern vendor debug-hub FIFO resets, XDCB findings vendor ILA query
efficiency, and TIMING-9 the reviewed custom FIFO. These engineering dispositions
do not establish quantitative metastability MTBF or formal acceptance.

## Release Gate And Scope

`run_windows_final_verification.py` binds final digital/tool regression to this
board receipt and a clean source commit. `build_windows_board_release.py` creates
the selected snapshot only after that receipt passes. Its original CSV and
artifact bytes are unchanged; portable derivatives carry both original and
delivered hashes. The standalone verifier reruns the raw ILA analysis without Git.
The hash-bound final build/audit receipts and new annotated release tag determine
`FINAL_RELEASE=READY`; this source document is not a substitute for those receipts.

REBUILT and BOARD_VERIFIED describe the new engineering evidence.
HISTORICAL_ACCEPTED describes only the preserved frozen baseline.
Formal acceptance of this new campaign is NOT_FORMALLY_ACCEPTED.
Physical analog ADC disconnection, calibrated current, external-pin PWM, real
power-stage/driver behavior, persistent boot/soak and formal acceptance are NOT_RUN.
The earlier B1 SAFE_INERT C1 check is platform/MMIO evidence only and is not used
as proof of these eight B2 scenarios.

The R2/R3 supplemental test failures and corrections are documented in
[Windows Board Test Corrections](../review/windows_board_test_corrections_20260909.md).
The full source modification inventory is in
[Windows Rebuild Changed Files](../review/windows_rebuild_changed_files_20260909.md).
