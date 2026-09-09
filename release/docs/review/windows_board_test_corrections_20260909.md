# Windows Board Test Corrections

The R2 and R3 campaigns used the fresh B2 Windows implementation
`S1E-B2-REBUILT-WINDOWS-20260909T000000Z`, not historical accepted hardware.
Both passed the eight required digital scenarios and source backpressure.
Neither is the final successful campaign: each stopped on a C2 test-oracle error.

| Attempt | Supplemental failure | Correction |
| --- | --- | --- |
| S1E-B2-BOARD-20260909-R2 | Saturation expected first bitmap 19/code 6 | Preserve the earlier overcurrent first bitmap 3/code 1; live/seen become 19 |
| S1E-B2-BOARD-20260909-R3 | Stuck stimulus ended after 256 samples | After a changed prelude, send 257 samples: one history sample plus 256 stable comparisons |

These corrections follow the existing first-fault and sensor persistence RTL.
No RTL, constraints, profile or hardware artifact changed. The production-core
replay `tools/run_stage2_board_plan_rtl.py` passed 20 checkpoints over 923 samples,
including the exact stuck boundary and all individual faults/recovery sequences.

The host now exports a triggered ILA window on a board assertion failure, waits
for the owned Vivado process tree to stop before hashing evidence, and preserves
nonzero board-service exit status. All 221 files indexed by the R3 aggregate
receipt match their hashes. R2 aggregate hashes must not be treated as sealed:
the old timeout path left a child process writing legacy capture logs after the
aggregate receipt was created. Its original files remain unchanged.

R4 is prepared as a new execution, `S1E-B2-BOARD-20260909-R4`. Its package SHA-256
is `1b97b2223162b1fc0aa0c4db8e218b83c95e1935bf98eb57f0d934c5a1394b66`.
R4 completed with all eight required and both supporting scenarios PASS. Its
225 evidence files reconcile, including raw captures for the corrected C2 case.
The original board receipt SHA-256 is
`85602e2f71b5950340fa680f4d6ea0f44ce95b5fc9d950e44bcd0c249cb71354`.
The final release workflow promotes this result over earlier current Windows
BLOCKED indexes only after regression and evidence checks. Historical ZIPs, tags
and accepted evidence remain unchanged.

The new selected snapshot workflow preserves byte-exact BIT/HWH/LTX and CSV,
records each portable derivative's original and delivered hashes, and separates
physical source, board tooling and release tooling identity. Its verifier replays
the raw ILA analysis without requiring Git. This engineering evidence format does
not grant formal acceptance and does not claim analog ADC or power-stage tests.
## Final Windows Tcl Regression Environment

The first post-R4 final regression failed in the Stage 1E execution architecture
fixture. Python's Windows environment dictionary uppercased `SystemRoot`, which
interfered with the Tcl child interpreter's environment-removal fixture. A second
failure came from inherited PowerShell 7 modules shadowing the Windows PowerShell
`Get-FileHash` implementation invoked by that fixture.

The regression launcher now canonicalizes the two relevant environment keys and
puts the native Windows PowerShell module directory first for its Tcl child.
Missing `SystemRoot` remains missing; custom module paths remain available.
The unchanged 130-assertion fixture passed with this launch environment. The
failed final-verification receipt remains external and unchanged; the corrected
full regression receives a separate execution ID. Hardware inputs and R4 board
evidence are unchanged by this tooling correction.
