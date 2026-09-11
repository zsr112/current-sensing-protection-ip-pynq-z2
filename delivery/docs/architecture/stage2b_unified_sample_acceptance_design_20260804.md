# Stage 2B unified sample acceptance design

Date: 2026-08-04
Branch: `codex/stage2b-unified-sample-acceptance`
Base commit: `c5f89c6c1463f504d3a5e3f10a87cdbf0188ffaf`
Scope: first Stage 2B RTL item only; this is not full Stage 2 closure.

## 1. Audit basis

The design decision follows a complete read of these frozen Stage 2A sources:

- `docs/architecture/stage2_sampling_contract_cdc_spec_20260803.md`
- `docs/architecture/stage2_sampling_clock_reset_cdc_inventory_20260803.md`
- `docs/verification/stage2_sampling_cdc_audit_20260803.md`
- `docs/verification/stage2_sampling_contract_cdc_result_20260803.md`
- `docs/verification/stage2_sampling_contract_nonblocking_hardening_20260804.md`

The source audit covered every RTL module, all ten canonical Icarus
testbenches, the Stage 2A checker and SC09, the register-controlled and AXI
tops, the packaging/BD source connectivity, reset/clear/recovery logic, and
first-fault retention.

The public sample payload is the ordered pair `{i_ch1,i_ch2}`. Both channels
and `sample_valid` reach `protection_core_top` through the register-controlled
and AXI wrappers without transformation. The current construction is one
clock domain. No ADC CDC exists.

## 2. Current data flow and invalid-cycle fault path

Before Stage 2B, the two protection consumers do not share one acceptance
boundary:

```text
raw i_ch1/i_ch2 -----------------> current_compare_dual (combinational)
                                      |
                                      v
sample_valid -------------------- fault_classifier (registered every edge)
    |                                 |
    +-> sensor_health_monitor         v
        (updates only when valid)  protection_fsm -> pwm_gate
```

The `sample_valid` line shown beside the classifier is not connected to it.
The invalid-cycle fault path is therefore:

```text
sample_valid=0
  + external raw pair changes to a faulting value
  + comparator result changes immediately
  + classifier registers the comparator fault at the next edge
  + FSM latches it one edge later
  + pwm_disable makes pwm_out safe-low in that same post-edge interval
```

The health monitor independently holds `prev_ch*`, counters, and flags during
the invalid interval. Stage 2A SC09 proves this split behavior.

Every `fault_classifier` input was audited. `oc_any`, `oc_both`, and
`mismatch_flag` are derived from the current sample pair. The open,
saturation, and stuck flags are derived from accepted sample history. There is
no non-sample-derived classifier input in the present RTL, so transaction
gating these six sources does not mask an independent fault source.

## 3. Architecture comparison

| Criterion | A: direct transaction gating | B: explicit accepted transaction pipeline |
|---|---|---|
| Pair/valid atomicity | Logical only; depends on raw pair stability at the edge | Physical concatenated pair register and same-stage valid |
| Invalid external toggles | Comparator can toggle, but classifier can be gated | Raw toggles stop at the acceptance register |
| Gap after a health trigger | A simple classifier gate can miss a health flag that becomes visible on the last valid edge | A decision-valid alignment stage drains the last accepted transaction correctly |
| Back-to-back/held-high valid | Supported | Supported at one transaction per edge |
| Stale replay after clear | Requires careful per-source event gating | Decision valid plus per-transaction health events suppress retained pair/state replay |
| Fault priority | Existing priority can be retained, but cross-cycle inputs can remain mixed | Existing priority is retained within one aligned transaction |
| Digital latency | Comparator path can remain unchanged | Comparator and health paths gain explicit, measurable stages |
| Future atomic ADC boundary | Requires a later structural boundary | Future atomic CDC can drive the existing transaction ingress naturally |
| Change control | Fewer registers, but special health-gap handling is required | More registers, one coherent rule for every sample-derived source |

Direct gating without an additional alignment mechanism is rejected. The
health monitor updates its registered flags on the edge that consumes a
sample, while the classifier sees the old flags on that edge. If the next raw
cycle is invalid, gating the classifier only with that next `sample_valid`
would discard the health result. Adding delayed valid and comparator storage
to repair that case is functionally the explicit pipeline.

`ACCEPTED_TRANSACTION_PIPELINE_WITH_ALIGNED_HEALTH_EVENTS` is selected.

## 4. Proposed data flow and unique transaction definition

The boundary is implemented inside `protection_core_top` so existing Vivado
packaging source lists and frozen board files do not need to change.

```text
raw {i_ch1,i_ch2} + sample_valid
  -> accepted_sample_pair register + accepted_sample_valid
  -> current_compare_dual and sensor_health_monitor consume that same pair
  -> comparator decision register + sample_decision_valid
  -> fault_classifier consumes the aligned comparator snapshot and
     per-transaction health events only when sample_decision_valid=1
  -> protection_fsm -> pwm_gate
```

The executable definitions are:

```text
sample_accept_event := rising edge with rst_n=1 and sample_valid=1
accepted_sample_pair := one 2*DATA_WIDTH register loaded with {i_ch1,i_ch2}
accepted_sample_valid := validity of accepted_sample_pair in the consumer stage
```

The pair is one concatenated register, not two independently controlled data
paths. `accepted_sample_valid` is updated in the same clocked block. During a
gap the pair holds for observability and `accepted_sample_valid` clears, so the
held value cannot be replayed as a transaction.

The comparator snapshot and `sample_decision_valid` form a second aligned
stage. This stage is required because health results are registered. It makes
the classifier inputs for transaction T consist of:

```text
comparator decision captured from accepted pair T
+ health event derived while consuming accepted pair T
+ decision-valid for T
```

The retained `sensor_open_flag`, `sensor_sat_flag`, and `sensor_stuck_flag`
remain diagnostic state. They may still be high when the next accepted pair is
safe. The registered `sensor_*_event` signals are separate: an event is high
only if that same accepted pair still qualifies and the old persistence
counter has reached `th_persist`. Invalid consumer cycles clear all three
events. The classifier consumes these events and never directly consumes the
retained flags.

## 5. Modules and ports

| Module | Stage 2B effect |
|---|---|
| `protection_core_top` | Owns acceptance pair/valid, comparator decision alignment, and classifier source gating |
| `current_compare_dual` | Unchanged equations; input changes from raw pair to accepted pair |
| `sensor_health_monitor` | Retains existing counters/diagnostic flags and adds registered open/saturation/stuck events for the currently consumed accepted pair |
| `fault_classifier` | Unchanged priority and register behavior; core presents aligned source values or all-zero no-event values |
| `protection_fsm` | Unchanged latch, first-fault, clear, and recovery policy |
| register/AXI tops | Public ports unchanged; raw monitor readback remains observational and is not a protection consumer |
| BD/package wrappers | No Stage 2B modification |

Thresholds remain same-domain configuration inputs and are evaluated in the
comparator decision stage. Threshold versioning is not added to the sample
tuple in this round. Tests configure thresholds before accepting the sample to
which they apply.

Therefore all threshold/configuration values used by the comparator and
health monitor must remain stable for an in-flight accepted transaction, from
N0 through its N2a consumption. This is an integration requirement, not an
implemented versioning mechanism.

```text
IN_FLIGHT_THRESHOLD_STABILITY_REQUIREMENT=DEFINED
THRESHOLD_VERSIONING_IMPLEMENTED=NO
```

## 6. Timing

For one accepted transaction T followed by a gap:

```text
edge             K             K+1             K+2             K+3
raw valid/pair   T             gap             gap             gap
accepted stage   capture T     valid clears    idle            idle
consumer action                cmp snapshot T  classifier T    FSM latch T
                                health update T
fault_valid                                    visible
fault_latched                                                    visible
pwm safe-low                                                      visible
```

Back-to-back transactions use the same stages every cycle. At K+2, for
example, the classifier consumes T0 while the health/comparator alignment
stage consumes T1 and the acceptance stage captures T2. No bubble is required.

## 7. Reset, clear, gap, and valid semantics

### Reset

- Reset polarity and asynchronous assertion remain unchanged.
- `accepted_sample_pair` resets to all zero.
- `accepted_sample_valid`, `sample_decision_valid`, and comparator decision
  registers reset to zero/no-fault.
- Input samples and valid are ignored while reset is asserted.
- A high valid at the first rising edge after release is accepted at that edge
  and becomes the first registered accepted transaction.
- Reset-release CDC remains outside this round.

### Valid and gaps

- `sample_valid` is level-valid. Every high edge accepts one new pair.
- Consecutive high edges are distinct back-to-back transactions.
- A one-cycle or longer low interval inserts matching invalid bubbles; health
  history pauses and the final pre-gap transaction is allowed to drain.
- Raw pair changes during a gap cannot change the accepted pair or create a
  new classifier event.

### Clear and stale replay

The classifier is driven to no-event when `sample_decision_valid=0`. A retained
accepted pair, comparator snapshot, or diagnostic health flag is therefore
not a live event by itself. A valid decision can contain a health event only
when the event registered for that exact accepted pair is high. After a fault
has latched and the accepted pipeline has drained in an invalid interval,
clear enters the existing RESET_WAIT path without the old accepted fault
sample reappearing. A later fresh faulting valid sample is a new event and can
retrigger normally.

The FSM first-fault priority is unchanged: the first code is retained in
`ST_FAULT_LATCHED`; the existing policy that a live event can update the code
in `ST_RESET_WAIT` remains deferred.

## 8. Digital latency change

The detailed contract is in
`docs/architecture/stage2b_sample_acceptance_latency_contract_20260804.md`.
Relative to Stage 1/Stage 2A:

- comparator-derived latch/safe latency: `+2_CYCLES` from the raw acceptance
  edge;
- open/saturation/stuck latch/safe latency: `+1_CYCLE` from the accepted sample
  that makes the corresponding health flag visible;
- accepted-sample persistence counts: `UNCHANGED`;
- clear/RESET_WAIT recovery after registered live-low: `UNCHANGED`.

Relative to reviewed commit
`575488440808ba503fed0f3daca1bce396c00338`, adding per-transaction health
events changes neither the N0-N4 pipeline nor the qualifying sample boundary:

```text
PERSISTENCE_TRIGGER_SAMPLE_COUNT_CHANGED=NO
DIGITAL_LATENCY_CHANGED=NO
```

## 9. Independent health-event alignment correction

Independent review of `575488440808ba503fed0f3daca1bce396c00338` found that
the accepted pipeline still used
`sample_decision_valid && sensor_*_flag` as a classifier event. Because the
flag is updated from the old counter, a first safe transaction after
clear/recovery can reset the counter while the flag remains high for that
cycle. The old classifier wiring therefore replayed a stale open, saturation,
or stuck condition on a newly accepted safe pair.

The correction leaves the diagnostic flag equations unchanged and adds the
event equations alongside them:

```text
event := accepted_consumer_valid
         && current_pair_still_qualifies
         && old_persistence_counter >= th_persist
```

This preserves the original `th_persist+1` trigger transaction. It also
supports one transaction per clock, drains the last accepted pair through a
gap, and prevents either an invalid bubble or retained diagnostic state from
creating a transaction event.

## 10. Explicitly unhandled scope

- No asynchronous ADC CDC, FIFO, handshake, or independent synchronizer is
  implemented.
- No reset release CDC proof or structure change is made.
- No overflow/drop/duplicate/error telemetry is implemented.
- No ADC code format, scale, polarity, or AFE behavior is defined.
- No synthesis, implementation, bitstream, Hardware Manager, or board action
  is performed.
- Frozen Stage 1 assets and the PYNQ-Z2 delivery repository are unchanged.
- The frozen Stage 1 BD drives `sample_valid=0`; it is not a Stage 2B sample
  producer and would accept no transactions if this branch were later
  repackaged into that construction. Supplying a real valid transaction source
  belongs to the already-open ADC/ingress integration gap.
- RESET_WAIT first-fault campaign policy remains deferred.
