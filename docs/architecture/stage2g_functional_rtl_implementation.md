# Stage 2G functional RTL implementation

This document describes the implementation on
`codex/stage2g-reset-wait-first-fault-policy-implementation`, based on
`ef6a990b154edd03b0b144d7d7cd0e41303dc095`. It implements the frozen Stage 2G
transaction and episode policy without changing the software ABI, the
existing AXI offsets, or the external top-level ports.

## Authority and placement

```text
STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT
STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION
RAW_PROTECTION_THRESHOLD_DOMAIN=UNSIGNED_RAW_CODE_COMPATIBILITY
NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO
```

The production asynchronous wrapper still receives an atomic channel pair
from `u_adc_sample_cdc_bridge`. Its Stage 2G companion,
`stage2g_adc_sample_cdc_bridge`, carries one source-offer integrity bit in the
same FIFO word. The destination sequence check is performed in
`stage2g_protection_core` on the delivered word by the same shared classifier
instantiated by the Stage 2E destination observer. Gray-counter,
sticky-status, and register paths remain diagnostic paths.

The implementation modules are companion definitions in the existing RTL
files. The original module names and port lists remain available for prior
Stage 2B through 2F fixtures and compatibility checks:

| File | Stage 2G definition | Role |
|---|---|---|
| `rtl/adc_sample_cdc_bridge.v` | `stage2g_adc_sample_cdc_bridge` | Atomic payload plus source integrity |
| `rtl/fault_classifier.v` | `stage2g_fault_evaluation_pipeline` | Registered aligned evaluation |
| `rtl/protection_fsm.v` | `stage2g_fault_episode_controller` | Episode, clear fence, and safe hold |
| `rtl/protection_core_top.v` | `stage2g_protection_core` | Raw capture, comparator/health alignment |
| `rtl/protection_ip_top_reg_controlled.v` | `stage2g_protection_ip_reg_controlled` | Existing register bank to Stage 2G core |
| `rtl/protection_ip_top_axi_lite.v` | `stage2g_protection_ip_axi_lite` | Existing AXI protocol and offsets |
| `rtl/transaction_destination_observer.v` | `stage2e_transaction_sequence_classifier` | Shared Stage 2E/Stage 2G modulo sequence classification |

The public `protection_ip_top_async_adc_axi_lite` port list is unchanged. No
new public registers are exposed; first/live/seen fields are internal debug
signals and their visibility is deferred to Stage 2H.

## Sequence-width and integrity hardening

The full Stage 2G sequence path is parameterized. The production binding is:

```text
FAULT_EVAL_SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH
SUPPORTED_SEQUENCE_WIDTHS=16_TO_32
SEQUENCE_ARITHMETIC=MODULO_2_POW_SEQUENCE_WIDTH
```

Captured, decision, expected, delta, evaluation, and clear-resolution fields
all use `[SEQUENCE_WIDTH-1:0]`. The shared classifier exactly preserves Stage
2E semantics: first nonzero is stale without resynchronization; duplicates
and reorder/stale retain expected; a forward gap is dirty and resynchronizes
to delivered plus one. Details are frozen in
`stage2g_sequence_width_contract_addendum.md`.

## Episode state and output authority

The explicit state encoding is `RESET_WAIT=2`, `ARMED=0`, and
`FAULT_LATCHED=1`. Reset asserts the safe gate and enters `RESET_WAIT`.

* The first clean zero evaluation arms immediately.
* The first clean nonzero evaluation latches immediately, including when it is
  the first eligible transaction after reset or clear.
* A non-clean evaluation remains safe and does not create a physical cause.
* Source disappearance, rejected clear, later causes, and diagnostic status do
  not release the gate.
* Legal clear enters `RESET_WAIT`; the resolution transaction itself cannot
  arm or release the output. A later clean healthy evaluation is required.

Legal clear ends the internal episode but does not report public recovery.
`public_fault_latched_compat` and `public_fault_code_compat` continue to drive
the existing STATUS and FAULT_CODE register inputs while
`post_clear_recovery_pending` records the internal boundary. The compatibility
latch/code persist through no-sample and non-clean post-clear RESET_WAIT,
clear only on the later clean healthy transition to ARMED, and are replaced by
a clean new fault before re-arm. Reset clears both internal and public state.
The detailed frozen boundary is in
`docs/architecture/stage2g_public_recovery_contract_addendum.md`.

The real asynchronous AXI fixture monitors every ACLK edge. It proves visible
PWM activity before fault, zero output through fault, W1P clear, and PWM
re-enable in RESET_WAIT, then activity only after the later healthy evaluation
enters ARMED. The observed unsafe-pulse count is zero.

The controller captures `first_fault_code` and `first_fault_bitmap` once per
episode. Clean latched evaluations replace `live_fault_bitmap` and OR into
`fault_seen_bitmap`. Non-clean evaluations leave all three episode fields
unchanged. Persistent faults do not retrigger the first-fault event, while a
fault in a later episode can start a new event.

## Independent replay

The review source archive contains immutable frozen-base interface/register
fingerprints. `check_stage2g_implementation.py --no-git-check` consumes those
fingerprints and never executes Git. The clean-room replay extracts the archive
into an empty temporary directory with no `.git` metadata and runs that mode;
repository fallback is forbidden.

## Non-claims and preserved status

This is functional digital RTL only. It adds no watchdog, ADC/AFE selection,
physical scaling, calibration, synthesis/implementation result, bitstream, or
board qualification. The frozen audit/status authority remains:

```text
RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```
