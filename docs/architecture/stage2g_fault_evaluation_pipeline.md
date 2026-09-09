# Stage 2G fault-evaluation pipeline

## Transaction definition

The policy consumer receives one registered transaction for each eligible
accepted atomic raw CDC destination delivery. An internal FIFO prefetch into
the bridge's elastic register is not a policy transaction:

```text
fault_eval_valid
fault_eval_sequence[SEQUENCE_WIDTH-1:0]
fault_eval_bitmap[5:0]
fault_eval_code[7:0]
fault_eval_integrity_clean
```

`fault_eval_valid` is completion validity, not fault presence. A zero bitmap
with valid asserted is a healthy evaluation. The compatibility signal remains
`fault_valid = fault_eval_valid && (fault_eval_bitmap != 0)` and is never used
to identify a healthy retirement.

## Fixed schedule

The schedule is fixed in ACLK and accepts one transaction per edge:

| Offset | Operation | Registered identity |
|---:|---|---|
| 0 | Capture atomically delivered `{CH1, CH2}` and source/destination integrity | `accepted_sample_pair`, `accepted_sample_sequence`, `accepted_integrity_clean` |
| 1 | Capture unsigned raw comparator decisions and health events | `decision_*`, `decision_sequence`, `decision_integrity_clean` |
| 2 | Register bitmap, compatibility code, sequence, and integrity | `fault_eval_*` |
| 3 | Consume the aligned transaction in the episode controller | state and safe-output decision |

```text
INTERNAL_FIFO_PREFETCH_EVENT=IMPLEMENTATION_DETAIL_NOT_POLICY_AUTHORITY
ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT=DST_SAMPLE_VALID_ACCEPTED_EDGE
STAGE2B_N0=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT
STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT
FAULT_EVALUATION_LATENCY_CONTRACT=FIXED_3_ACLK_EDGES_DELIVERY_TO_POLICY_DECISION_II1
PIPELINE_INITIATION_INTERVAL=1
```

Every valid stage is flushed by the existing local reset. No pre-reset valid
bit or evaluation can retire after reset. `SEQUENCE_WIDTH` is bound to
`OBS_SEQUENCE_WIDTH` and supports 16 through 32 bits. Sequence values use
modulo-`2**SEQUENCE_WIDTH` arithmetic; the clear fence uses retirement order
and does not compare sequence numbers, so wrap is ordinary aligned traffic.

## Integrity attachment

The source companion observes offer stability while `valid && !ready` and
stores the result beside the accepted FIFO payload. At the destination, both
Stage 2E and Stage 2G instantiate the shared parameterized
`stage2e_transaction_sequence_classifier`. An expected delivery is clean and
increments expected. A first nonzero delivery is stale and retains expected
zero. Duplicate and reorder/stale deliveries are dirty and retain expected. A
forward gap is dirty and resynchronizes expected to delivered plus one. Only
the next matching transaction restores eligibility. The combined integrity
bit then travels with sequence and bitmap through every pipeline stage.

Delayed Gray-synchronized counters, historical W1C sticky bits, saturation,
overflow without acceptance, and underflow without delivery remain
status-only. They are not substituted for transaction identity and cannot gate
arming, latching, clear, or safe-output release. Stage 2F normalized telemetry
is an observational fork of the same accepted raw destination delivery and is
not connected to this pipeline.

## Cause bitmap and code

The primitive bitmap is:

```text
bit 0 CH1_OVERCURRENT
bit 1 CH2_OVERCURRENT
bit 2 SENSOR_MISMATCH_OR_DIFFERENTIAL
bit 3 SENSOR_OPEN
bit 4 SENSOR_SATURATION
bit 5 SENSOR_STUCK
```

The complete bitmap preserves simultaneous information. The compatibility
code is derived only from the bitmap using:

```text
OC_WITH_ANY_SENSOR > OVERCURRENT > SENSOR_SATURATION > SENSOR_OPEN
  > SENSOR_STUCK > SENSOR_MISMATCH > NONE
```

Thus CH1+CH2, overcurrent plus any health cause, and all six causes remain
distinguishable internally even though the existing 8-bit code selects one
compatibility priority.
