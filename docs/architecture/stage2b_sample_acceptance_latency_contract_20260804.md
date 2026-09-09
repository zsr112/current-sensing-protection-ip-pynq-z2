# Stage 2B sample acceptance digital latency contract

Date: 2026-08-04
Baseline: `c5f89c6c1463f504d3a5e3f10a87cdbf0188ffaf`
Selected architecture: `ACCEPTED_TRANSACTION_PIPELINE_WITH_ALIGNED_HEALTH_EVENTS`

This document defines clocked RTL latency only. It is not ADC-to-power-stage,
analog, board, or physical response latency.

## 1. Event notation

Let edge K be the edge at which raw `sample_valid=1` and the raw pair is
accepted.

| Contract event | Actual Stage 2B event |
|---|---|
| N0 | Edge K observes and captures the raw valid/pair |
| N1 | Immediately after K, accepted pair/valid are visible to the comparator and health consumer stage |
| N2a | Edge K+1 captures the comparator decision and registers health events/state for that accepted transaction |
| N2b | Edge K+2 updates registered `fault_valid/fault_code` from the aligned comparator and health result |
| N3 | Edge K+3 updates the FSM fault latch/code |
| N4 | Same post-edge interval as N3; registered `pwm_disable` drives `pwm_out` safe-low combinationally |

N3 and N4 are coincident in the implemented RTL. N1 is registered visibility
after N0 rather than another elapsed clock. N2 is split into N2a/N2b because
the real implementation aligns registered per-transaction health events
before the existing registered classifier.

## 2. Comparator-derived paths

The overcurrent and mismatch equations are unchanged and use strict `>`.

```text
K    (N0/N1): accept pair
K+1  (N2a):   capture comparator result for that pair
K+2  (N2b):   classifier fault_valid/code visible
K+3  (N3/N4): fault latch/code and safe output visible
```

| Path | Stage 1/Stage 2A from presented pair | Stage 2B from N0 | Change |
|---|---:|---:|---|
| overcurrent classifier | 0 cycles | 2 cycles | `+2_CYCLES` |
| overcurrent latch/safe | 1 cycle | 3 cycles | `+2_CYCLES` |
| mismatch classifier | 0 cycles | 2 cycles | `+2_CYCLES` |
| mismatch latch/safe | 1 cycle | 3 cycles | `+2_CYCLES` |

Machine value:

```text
OVERCURRENT_LATENCY=N0_TO_N3_N4_3_CYCLES
SAFE_OUTPUT_LATENCY=N0_TO_N4_3_CYCLES_COMPARATOR_PATH
```

## 3. Sensor-health paths

The health persistence equations and accepted-sample count are unchanged.
From a zero counter, a continuously qualifying condition still becomes visible
on qualifying accepted sample `th_persist+1` because the flag compares the old
counter value.

Let K be N0 for the accepted transaction whose qualifying condition and old
persistence counter produce a registered health event when consumed:

```text
K    (N0/N1): accept the triggering pair
K+1  (N2a):   health event becomes visible; comparator snapshot aligns
K+2  (N2b):   classifier health fault/code becomes visible
K+3  (N3/N4): fault latch/code and safe output become visible
```

| Path | Accepted qualifying count | Stage 1/Stage 2A trigger-to-safe | Stage 2B N0-to-safe | Change |
|---|---:|---:|---:|---|
| sensor open | unchanged | 2 cycles | 3 cycles | `+1_CYCLE` |
| sensor saturation | unchanged | 2 cycles | 3 cycles | `+1_CYCLE` |
| sensor stuck | unchanged | 2 cycles | 3 cycles | `+1_CYCLE` |

Gaps do not advance health counters. They can increase elapsed wall-clock
cycles, so latency from the first qualifying sample is
`PATH_DEPENDENT_ON_VALID_GAPS`; latency from the accepted triggering
transaction remains exactly three clocks to latch/safe.

```text
SENSOR_OPEN_LATENCY=TRIGGER_ACCEPT_N0_TO_N3_N4_3_CYCLES
SENSOR_SATURATION_LATENCY=TRIGGER_ACCEPT_N0_TO_N3_N4_3_CYCLES
SENSOR_STUCK_LATENCY=TRIGGER_ACCEPT_N0_TO_N3_N4_3_CYCLES
```

The retained diagnostic flag still compares the old counter exactly as
before. It can remain high on the first non-qualifying recovery transaction.
That state does not alter latency because the classifier consumes the separate
transaction event, which also requires the current pair to qualify.

Relative to `575488440808ba503fed0f3daca1bce396c00338`:

```text
PERSISTENCE_TRIGGER_SAMPLE_COUNT_CHANGED=NO
DIGITAL_LATENCY_CHANGED=NO
```

## 4. Back-to-back and gap throughput

The pipeline accepts one transaction per high-valid edge. It can capture T2,
align T1, classify T0, and latch an earlier visible event on the same edge.
There is no throughput penalty after fill.

An invalid edge inserts a bubble. The final accepted transaction before a gap
still reaches N2b/N3; subsequent raw changes do not enter the accepted stage.
No transaction is duplicated or replayed.

## 5. Clear and recovery latency

Once the classifier has registered live-low, the existing FSM timing is
unchanged for default `RESET_WAIT_CYCLES=4`:

| Edge | State/action after edge |
|---|---|
| E0 | Clear in `ST_FAULT_LATCHED` enters `ST_RESET_WAIT`, count 0; latch/code/safe state retained |
| E1 | First eligible clear-low/live-low edge, count 1 |
| E2 | Count 2 |
| E3 | Count 3 |
| E4 | State becomes NORMAL and latch/code clear; `pwm_disable` remains asserted |
| E5 | NORMAL edge releases registered `pwm_disable`; output may resume according to `pwm_raw` |

```text
CLEAR_RECOVERY_LATENCY=E0_TO_LATCH_CLEAR_4_CYCLES;E0_TO_GATE_RELEASE_5_CYCLES
CLEAR_RECOVERY_CHANGE=UNCHANGED
```

If a genuinely new accepted fault transaction is pending, it may produce a
new event according to the N0-N4 pipeline. The stale-replay guarantee applies
both when no new transaction is accepted and when the first fresh accepted
transaction is non-qualifying. Retained pair or diagnostic health state alone
cannot produce a new event.

## 6. Reset boundary

Reset clears both valid stages, the pair register, comparator decision
registers, health/classifier/FSM state, and PWM state. A valid on the first
rising edge after reset release is N0 for the first transaction. Its safe
response, if faulting, follows the same three-cycle N0-to-N4 contract.

Destination-safe reset release remains an unresolved CDC proof item.

## 7. Threshold stability boundary

Comparator and health thresholds are not captured into the accepted tuple.
They must remain stable for an in-flight accepted transaction through N2a so
the comparator snapshot and health event use one configuration version.

```text
IN_FLIGHT_THRESHOLD_STABILITY_REQUIREMENT=DEFINED
THRESHOLD_VERSIONING_IMPLEMENTED=NO
```
