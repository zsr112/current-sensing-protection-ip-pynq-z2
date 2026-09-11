# Coordinated Windows Board Session

Use the current `READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS` clean build for this
digital campaign. `SAFE_INERT` supports platform/MMIO checks but cannot drive
the eight fault/PWM scenarios. A different profile has different artifact hashes;
both profiles must remain identified separately.

`build_stage2_board_session.py` verifies the physical artifact manifest, every
referenced artifact/report, and the exact clean physical source checkout. It
records a separate clean tooling commit, all package file hashes, full physical
source input hashes, and the actual Vivado version. It does not require a
published branch or substitute local source identity for physical build identity.

The operator runs `start_stage2_board_session.ps1` with the new ZIP and its
expected SHA256. SSH and sudo handle passwords interactively; no password is
passed through the test harness. The script validates the remote ZIP before
extraction into a new temporary directory, then starts the board service on
loopback through SSH local forwarding. Existing directories are never reused.

The host runs `stage2_board_session_host.py` with that package root, a new
evidence root, and the Vivado executable. Each fixed board action is ordered,
bound to the execution ID, logged before advancement, and rejected on replay.
The service accepts no arbitrary MMIO address or shell command. PWM is disabled
on abort, normal completion, and session timeout.

Each scenario saves two independent raw ILA CSV files, actual probe/trigger
settings, ILA properties, tool logs, metadata, inputs/actions, and a receipt.
Source and destination windows use different clocks and are not represented as
a common timestamp trace. The host waits for verified arming before applying
the stimulus. Capture timeouts preserve partial files.

The eight scenarios are normal PWM, CH1 overcurrent, CH2 overcurrent,
differential fault, live clear rejection, sample-source removal, first clean
sample entering RESET_WAIT, and the subsequent clean sample restoring PWM.
Two supporting runs add source backpressure and the established six-family C2
sequence/analyzer. The absence scenario is controlled removal of the synthetic
digital sample source; it is not physical analog ADC disconnection evidence.

Record the board model as an operator declaration and the actual JTAG die
separately. JTAG identifies `xc7z020`, not the package/speed grade. Board UTC is
untrusted until independently established; execution order and host UTC remain
the chronology authority. Python/PYNQ/image versions and overlay clocks are read
from the live board before execution.

Do not replace the current Windows BLOCKED record or generate a final ZIP/tag
until all eight scenarios, supporting analysis, evidence hashes, final regression,
and delivery audit have passed. Runtime preparation and a clean hardware build
alone are not board verification or formal acceptance.

Before a new campaign, run `tools/run_stage2_board_plan_rtl.py --output <new-root>`.
It replays the C2 protection stimuli against the actual production core with
the board's default thresholds. Saturation retains the earlier dual-overcurrent
first cause (bitmap 3, code 1) while live causes become bitmap 19. Stuck detection
requires an initial history sample and 256 stable comparisons, hence 257 samples
after the changed prelude. These are stimulus/oracle corrections, not RTL changes.

After a complete board PASS, `run_windows_final_verification.py` runs the full
digital and tool regression in another external root. `build_windows_board_release.py`
then creates the `windows-board-evidence-release-v1` selected snapshot. The existing
current-release verifier dispatches this explicit schema to the board-evidence
verifier; the frozen SAFE_INERT deployment contract remains independently checked.
The snapshot carries byte-exact BIT/HWH/LTX and raw CSV, portable evidence
derivatives with original/delivered hashes, and separate physical/board/release
source identities. Its offline verifier does not need Git, Vivado or a board.
