# Current digital architecture and maintenance boundary

This is the current architecture entry for the v2r3 release line. Historical
review reports and v2r2 artifacts retain their original dates, source identities
and conclusions. v2r3 records its physical source, later publication tooling,
Vivado build, routed review, board session and final validation as separate,
hash-bound authorities.

The production top is `protection_ip_top_async_adc_axi_lite`. Its raw sample path
uses source ready/valid, an atomic asynchronous FIFO, accepted destination
`dst_sample_valid`, the Stage2G core in `protection_core_top`, fault evaluation,
the episode controller and the PWM gate. AXI software uses generated ABI 1.1
definitions. The normalizer's production profile remains `UNCONFIGURED`;
protection operates on unsigned raw ADC codes, not calibrated amperes.

`SAFE_INERT` (B1) permits platform/MMIO checks. B2
`READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS` supplies synthetic digital transactions
and source/destination ILA cores. Neither profile proves a real ADC/AFE or power
stage. Their physical artifacts and hashes are distinct.

| Boundary | Current evidence and meaning |
| --- | --- |
| No samples while ARMED | The portable characterization stays ARMED for 10,000 ACLK with PWM high for 5,000 cycles. There is no sample-age watchdog. This is a bounded observation, not physical disconnection evidence. |
| Dirty transactions | Dirty dual-overcurrent does not latch; a subsequent clean overcurrent latches and disables PWM. Transaction qualification is unchanged. |
| Source-removal board scenario | Synthetic source removal starts with a fault already latched. It does not prove automatic shutdown on sample loss from normal ARMED operation. |
| Local latency | Three ACLK edges from destination delivery to internal policy decision; not sensor-to-power-switch shutdown latency. |
| ABI constraints | Legacy WSTRB behavior, non-atomic multi-register reads and no atomic configuration commit remain. Configure with PWM disabled; diagnostic reads can span changing state. |
| Physical review | Retained CDC Critical findings need bounded engineering review for each new build. No zero-Critical or MTBF claim. |
| Board window | Historical short ILA captures use synthetic stimuli. Real ADC, external-pin PWM, power stage, persistent boot and soak remain unverified. |

Run the shared portable suite with
`python -B tools/run_portable_regression.py --output <fresh-external-output>`.
It runs generated drift/ABI checks, generator mutations, Python/software tests,
10 basic RTL testbenches, Stage2G directed/64-policy/model/CDC/16-24-32-bit tests,
connected mutations, runtime boundary characterization, B2 producer and C2 plan.
Its receipt explicitly marks vendor Tcl/XSim and board checks NOT_RUN.

From a verified selected export, use
`python -B tools/rebuild.py preflight --target portable|digital|vivado|all`.
The default is `all`. A dependency check cannot prove license checkout, routed
timing, board verification or formal acceptance. Full `digital` still requires
the Windows vendor Tcl/XSim toolchain; see
[rebuild instructions](../bringup/independent_rebuild.md).

SOURCE, BUILD, BOARD, FINAL and PUBLICATION identities are separate and linked
by manifests and `ACCEPTANCE.json`. Physical-source changes require a new source
export, Vivado build and board evidence. Later publication-only changes retain
their own commit and tool hashes and cannot replace the physical build inputs.
Old v2r2 evidence cannot be relabeled.

| v2r3 status boundary | State |
| --- | --- |
| Physical source | Commit `fb81a9a004bdcb900e5b678d8a424403aeafb602`, bound by `SOURCE_MANIFEST.json` |
| Vivado build and routed review | `CSIP-V2R3-BUILD-001`, PASS |
| PYNQ-Z2 board campaign | `CSIP-V2R3-BOARD-001`, PASS for eight required and two supporting synthetic-digital scenarios |
| Online portable CI | Ubuntu, macOS and Windows must all PASS on the recorded publication commit |
| Final validation | `CSIP-V2R3-FINAL-001` must bind Windows, Mac and online-CI evidence |
| Formal acceptance | `PROJECT_OWNER_ACCEPTED` is permitted only for `V2R3_DIGITAL_RELEASE` after every required basis check passes |

The same `.github/workflows/portable.yml` is included in the selected source and
copied unchanged by the release generator, so CI bytes are covered by SOURCE
and RELEASE manifests. Its driver detects an actual release and runs offline
`verify.py`, default `deploy/load.py`, isolated source extraction and portable
checks. A source checkout runs the full engineering ABI scope before export.
Selected export checks verify manifest and selection identities, require every
active consumer/oracle, and label omitted frozen historical snapshots OUT_OF_SCOPE.

The accepted scope remains digital. Real ADC input, actual calibration,
external-pin PWM, an external power stage, persistent boot, long-duration soak
and analog-system validation remain outside the v2r3 acceptance claim.
