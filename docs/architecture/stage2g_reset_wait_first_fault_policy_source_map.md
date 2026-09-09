# Stage 2G implementation source map

This implementation-era map extends the frozen architecture audit without
moving or rewriting its tag. The machine-readable companion is
`spec/stage2g_reset_wait_first_fault_policy_source_map.json`. The implementation
branch starts from `ef6a990b154edd03b0b144d7d7cd0e41303dc095`; recovery
observability hardening continues from
`7f332bac77b0433e241a769faf161855894a8b77`.

The machine map preserves the original 17 audit rows byte-for-byte in
`baseline_entries`. Ten `implementation_entries` identify the implemented
module, signals, clock/reset domain, producer, consumer, logic kind, pipeline
offset, reset behavior, visibility, and connected tests. The
`implemented_path_trace` follows both source-to-public-status and
source-to-safe-output paths.

## Fixed transaction schedule

| Edge from accepted destination delivery | Implementation | Aligned fields |
|---:|---|---|
| 0 | `stage2g_protection_core` captures raw pair and classifies destination sequence | pair, sequence, source/destination integrity |
| 1 | Raw comparator and health decisions are registered | decision causes, sequence, integrity |
| 2 | `stage2g_fault_evaluation_pipeline` registers one evaluation | valid, bitmap, code, sequence, integrity |
| 3 | `stage2g_fault_episode_controller` consumes the evaluation | episode state, clear fence, safe gate |

The latency is fixed at three ACLK edges with initiation interval one. A zero
bitmap remains a valid healthy evaluation. Reset flushes all three valid
stages, so no pre-reset evaluation retires afterward.

## Sequence-width path

```text
OBS_SEQUENCE_WIDTH
  -> stage2g_adc_sample_cdc_bridge.SEQUENCE_WIDTH
  -> stage2g_protection_ip_axi_lite.SEQUENCE_WIDTH
  -> stage2g_protection_ip_reg_controlled.SEQUENCE_WIDTH
  -> stage2g_protection_core.SEQUENCE_WIDTH
  -> stage2g_fault_evaluation_pipeline.SEQUENCE_WIDTH
  -> stage2g_fault_episode_controller.SEQUENCE_WIDTH
```

The supported production range is 16 through 32. Every captured, expected,
delta, decision, evaluation, and clear-resolution field is
`[SEQUENCE_WIDTH-1:0]`. The top-level binding is explicit:
`.SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH)`. Software observability registers remain
32 bits and naturally zero-extend shorter sequences; that ABI representation
is outside the internal Stage 2G identity width and adds no new offset.

## Classification authority

`stage2e_transaction_sequence_classifier` is defined beside and instantiated
by `transaction_destination_observer`. `stage2g_protection_core` instantiates
the same module. Stage 2E and Stage 2G therefore share the exact same expected,
duplicate, first-stale, forward-gap, and reorder/stale classification:

```text
expected:       clean; expected++
first nonzero:  stale/dirty; retain expected=0
duplicate:      dirty; retain expected
reorder/stale:  dirty; retain expected
forward gap:    dirty; expected=delivered+1
```

The delta sign is `sequence_delta[SEQUENCE_WIDTH-1]`. Arithmetic is modulo
`2**SEQUENCE_WIDTH`; clean wrap `max-1,max,0,1` and all recovery rules are
identical at widths 16, 24, and 32.

## Module ownership

| File | Functional ownership |
|---|---|
| `rtl/adc_sample_cdc_bridge.v` | Atomic sequence/raw-pair/source-integrity FIFO payload |
| `rtl/transaction_destination_observer.v` | Shared Stage 2E/Stage 2G classification authority and Stage 2E diagnostics |
| `rtl/protection_core_top.v` | Destination integrity state, edge-0/1 alignment, raw evaluation path |
| `rtl/fault_classifier.v` | Edge-2 aligned valid/sequence/bitmap/code/integrity register |
| `rtl/protection_fsm.v` | Edge-3 episode controller, request/evaluation clear fence, safe hold |
| `rtl/protection_ip_top_reg_controlled.v` | Existing register bank and parameterized Stage 2G core binding |
| `rtl/protection_ip_top_axi_lite.v` | Existing AXI transport and sequence-width propagation |
| `rtl/protection_ip_top_async_adc_axi_lite.v` | Production `OBS_SEQUENCE_WIDTH` binding and raw authority |

Legacy/public module port lists remain unchanged. The Stage 2G companions are
internal. Stage 2F normalization remains a parallel observational fork and
does not feed the shared classifier or episode controller.

## Public recovery boundary

The internal episode ends at legal clear acceptance, but the existing public
`STATUS.FAULT_LATCHED` and `FAULT_CODE` values are supplied by compatibility
state. They remain asserted/retained through post-clear `RESET_WAIT`, including
no-sample and non-clean evaluations. A later clean healthy evaluation entering
`ARMED` clears them. A clean fault before re-arm starts a new episode and
replaces the public code. See
`docs/architecture/stage2g_public_recovery_contract_addendum.md`.

```text
SOURCE_MAP_BASELINE_ENTRIES=PASS_17
SOURCE_MAP_IMPLEMENTATION_ENTRIES=PASS_10
SOURCE_MAP_IMPLEMENTED_PATH_TRACE=PASS
```

## Policy and diagnostics boundary

The policy-integrity bit is the carried source offer-stability result AND the
shared destination expected-delivery result for the same sequence. Delayed
Gray counters, sticky W1C status, counter saturation, overflow without
acceptance, and underflow without delivery remain status-only. The clear fence
uses retirement order rather than numeric sequence comparison, including at
wrap.

```text
RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```
