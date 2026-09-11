# Stage 2G sequence-integrity hardening verification plan

Status: historical Stage 2G implementation plan. The current C2 runner uses
the connected B2 destination suite; immutable Git history retains the
superseded core-local sequence fixture and mutation matrix described below.

This implementation-era plan supplements the frozen Stage 2G architecture
audit. It validates the parameterized transaction identity, exact Stage 2E
classification semantics, production safe release, and independent source
archive replay. It does not authorize synthesis, implementation, bitstream,
Hardware Manager, or board action.

## Contract and static gates

The frozen episode, clear, latency, raw-authority, register, and non-claim
checks remain active. Amended machine checks additionally require:

```text
FAULT_EVAL_SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH
SUPPORTED_SEQUENCE_WIDTHS=16_TO_32
SEQUENCE_ARITHMETIC=MODULO_2_POW_SEQUENCE_WIDTH
POLICY_INTEGRITY_EQUALS_STAGE2E_TRANSACTION_CLASSIFICATION=PASS
```

The implementation checker rejects fixed `[31:0]` Stage 2G sequence ports,
missing `SEQUENCE_WIDTH` propagation, `sequence_delta[31]`, first-stale
resynchronization, missing width matrix tops, sequence resize warnings, and
Git access in archive mode. Frozen-base legacy interface and register-map
invariance is checked from immutable fingerprints, with Git used only by the
repository-mode cross-check.

## Width and equivalence matrix

`tb/stage2h/tb_stage2h_b2_destination_sequence.sv` runs the identical
functional matrix at widths 16, 24, and 32 in Icarus and XSim. Every delivery
compares all five Stage 2G classification outcomes against a complete Stage 2E
destination observer:

* first delivery zero;
* first delivery nonzero, the immediately following gap, and recovery;
* ordinary clean increment;
* forward gap and next matching recovery;
* duplicate and retained-expected recovery;
* reorder/stale and retained-expected recovery;
* clean `max-1,max,0,1` wrap;
* gap and duplicate across wrap;
* clear resolution at wrap; and
* RESET_WAIT qualification after wrap.

The fixture also elaborates the complete asynchronous AXI hierarchy and uses
`$bits` checks at each Stage 2G companion boundary. Compiler diagnostics that
indicate port/formal width mismatch, resize, truncation, extension, or invalid
selection fail the sequence case even if simulation would otherwise pass.

## Episode, clear, reset, and longevity

The existing core, 64-bitmap policy, and reference-vector fixtures retain:

* fixed edge-0/1/2/3 latency and II=1;
* zero bitmap as healthy completion;
* immutable first code and bitmap;
* live replacement and monotonic seen OR;
* simultaneous-cause bitmap preservation and priority;
* request/evaluation-fenced clear under continuous traffic;
* reset at every occupied pipeline stage;
* no stale post-reset retirement; and
* at least 1,000 completed randomized episodes.

The Python model independently tracks modulo-width expected sequence,
first-stale, duplicate, gap, reorder/stale, pipeline timing, episode state,
clear boundaries, reset, and safe output.

## Public recovery observability

The real production path exports `STATUS`, `FAULT_CODE`, `CTRL`, and raw-current
readbacks at each recovery boundary. The unchanged
`sw.protection_ip_interface.recovery_is_verified()` predicate is applied to
those RTL-derived snapshots. The required transition matrix is:

```text
INTERNAL_EPISODE_END=LEGAL_CLEAR_ACCEPTANCE
PUBLIC_RECOVERY_COMPLETE=LATER_CLEAN_HEALTHY_EVALUATION_ENTERING_ARMED
CLEAR_ACCEPTANCE_EQUALS_PUBLIC_RECOVERY_COMPLETE=NO
STATUS_FAULT_LATCHED_DURING_POST_CLEAR_RESET_WAIT=1
FAULT_CODE_DURING_POST_CLEAR_RESET_WAIT=RETAIN_PRIOR_FIRST_CAUSE
POST_CLEAR_RESET_WAIT_RECOVERY_VERIFIED=NO
NO_SAMPLE_POST_CLEAR_RECOVERY_VERIFIED=NO
NONCLEAN_POST_CLEAR_RECOVERY_VERIFIED=NO
ARMED_AFTER_LATER_HEALTHY_RECOVERY_VERIFIED=YES
LATER_HEALTHY_CLEARS_COMPATIBILITY_STATUS=PASS
POST_CLEAR_FAULT_REPLACES_WITH_NEW_FIRST_CAUSE=PASS
RESET_CLEARS_COMPATIBILITY_STATUS=PASS
SOFTWARE_RECOVERY_API_SEMANTICS_PRESERVED=PASS
```

The eight recovery-observability mutants are connected to this production
oracle: clear-time public latch/code loss, false post-clear recovery,
no-sample/non-clean retention loss, healthy clear loss, pre-rearm cause
replacement loss, and internal episode-active register wiring.

## Production safe release

`tb/stage2g/tb_stage2g_production_path.sv` drives the real asynchronous FIFO
and AXI write channel. An ACLK-edge monitor requires:

```text
visible PWM before fault
fault -> safe hold
W1P clear -> fenced RESET_WAIT
PWM re-enabled in RESET_WAIT -> raw carrier active, output still safe
later clean healthy evaluation -> ARMED
PWM output activity resumes only after ARMED
PRODUCTION_UNSAFE_PULSE_COUNT=0
```

## Connected mutations

The previous 28 connected RTL mutants remain mandatory in both simulators.
The sequence group adds actual source mutations for hard-coded widths, fixed
AXI formals, missing production propagation, bit-31 delta classification,
short-sequence extension, broken 16/24-bit wrap recovery, first-stale expected
advance, premature eligibility after first stale, Stage 2E/Stage 2G semantic
divergence, and ignored implicit width warnings. Controls must pass before any
mutant can count as killed; all mutated sources and hashes are retained.

## Clean-room source replay

The final clean-tree runner creates a Git source archive, then
`tools/replay_stage2g_source_archive.py` extracts it into a newly empty
temporary directory. The replay invokes:

```text
python tools/check_stage2g_implementation.py --root <extracted> --no-git-check
```

The checker consumes the packaged frozen-base fingerprints and cannot execute
Git in this mode. Required evidence is:

```text
SOURCE_ARCHIVE_STATIC_REPLAY=PASS
REPOSITORY_FALLBACK_USED=NO
```

## Completion matrix

After targeted checks, commit the hardening and run the clean-tree Stage 2G
runner with XSim, all mutations, and full prior-stage regression. Retain
canonical, software-interface, Stage 1E static, controlled-source-closure,
credential, manifest, remote-equality, and package replay evidence. The
preserved status remains:

```text
RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```
