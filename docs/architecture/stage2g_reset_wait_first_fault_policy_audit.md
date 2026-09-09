# Stage 2G RESET_WAIT, first-fault, and transaction-boundary architecture audit

Status: transaction boundary hardened and ready for independent rereview. This
audit is based on source commit `94b400ad3a713f4fdaf7b0e347c40baeab28a924`
and hardens the architecture contract at
`af0c604d9de9fa4a6b659940be2d41f9fbc170bd`. It does not implement Stage 2G
RTL.

## 1. Authority and scope

```text
STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT
STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION
NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO
NORMALIZED_RANGE_FLAGS_GATE_FAULT_POLICY=NO
NORMALIZED_CONFIGURATION_VALID_GATES_FAULT_POLICY=NO
RAW_PROTECTION_THRESHOLD_DOMAIN=UNSIGNED_RAW_CODE_COMPATIBILITY
```

The accepted raw destination delivery is one atomic sequence and channel-pair transaction. Raw
comparator and health evaluation remain the only physical protection authority.
The Stage 2F normalized stream is an observational fork and cannot arm, trip,
latch, clear, recover, release, delay, or suppress safe actuation.

This audit changes no RTL, external port, AXI behavior, software API, raw
threshold, synthesis input, or existing `0x00..0x60` register offset. New
conceptual visibility is deferred to Stage 2H.

## 2. Current pipeline and missing boundary

The exact source trace is in
`docs/architecture/stage2g_reset_wait_first_fault_policy_source_map.md`; its
machine-readable companion is
`spec/stage2g_reset_wait_first_fault_policy_source_map.json`.

The current ACLK pipeline is fixed:

```text
offset 0  accepted destination delivery and raw pair capture
offset 1  comparator/health decision capture
offset 2  registered classifier result
offset 3  FSM consumption of registered result
II        1 transaction per ACLK
```

Current `fault_valid` is a registered nonzero fault-presence result for one
evaluated transaction. It is not an evaluation-completion valid. A zero value
cannot distinguish a healthy retirement from no retirement. The current path
also lacks an aligned sequence, complete bitmap, and transaction integrity
result. These are contract gaps, not claims about implemented signals.

The current FSM resets to `ST_NORMAL`, advances its post-clear wait by clock
count, and accepts clear unconditionally in `ST_FAULT_LATCHED`. It has no
episode marker, clear-pending fence, or first/live/seen bitmap. The behavior
matrix in `spec/stage2g_reset_wait_first_fault_current_behavior.json` records
the completion-valid gap and clear/pipeline races explicitly.

## 3. Current behavior conclusions

The hardened audit preserves the previous findings and adds these boundary
findings:

| Scenario | Current result | Target requirement |
|---|---|---|
| Healthy evaluation versus pipeline idle | Both can present `fault_valid=0` | `fault_eval_valid` identifies every healthy or faulty retirement |
| Clear on a retirement edge | Latched-state clear ignores the retiring classifier result | Same-edge retirement is earlier and cannot resolve the new request |
| Clear between destination delivery and retirement | Clear may enter wait before that result reaches the FSM | The later retirement resolves the request |
| Continuous II=1 delivery | No `clear_pending` or fence exists | Next later retirement resolves; pipeline empty is irrelevant |
| Reset with pipeline work | Current valid stages reset, but have no explicit transaction identity | Flush all future transaction valid fields; no pre-reset retirement survives |

## 4. Formal fault-episode model

The target lifecycle remains:

```text
RESET -> RESET_WAIT -> ARMED -> FAULT_LATCHED
FAULT_LATCHED -> legal clear -> RESET_WAIT
RESET_WAIT -> ARMED or a new FAULT_LATCHED episode
```

`FAULT_EPISODE_START` is the first clean, nonzero `fault_eval` while not already
latched. `FAULT_EPISODE_ACTIVE` continues through persistent faults, later
causes, source removal, rejected clear, and clear pending. `FAULT_EPISODE_END`
is legal clear acceptance or reset assertion. Source removal alone never ends
an episode. A legal clear starts a new episode boundary and enters `RESET_WAIT`.

First code and first bitmap are captured once and immutable through the whole
episode. Later clean evaluations update the live bitmap and OR into the seen
bitmap. Persistent fault does not retrigger, and a post-recovery fault may
start a later episode.

```text
FIRST_FAULT_LATCH_PER_EPISODE=YES
FIRST_FAULT_IMMUTABLE_DURING_EPISODE=YES
PERSISTENT_FAULT_RETRIGGER=NO
LATER_FAULT_OVERWRITES_FIRST_CAUSE=NO
SUCCESSFUL_CLEAR_STARTS_NEW_EPISODE=YES
POST_RECOVERY_FAULT_CAN_LATCH_AGAIN=YES
```

## 5. Fault-evaluation transaction

The later implementation must retire this internal transaction in ACLK:

```text
fault_eval_valid
fault_eval_sequence[31:0]
fault_eval_bitmap[5:0]
fault_eval_code[7:0]
fault_eval_integrity_clean
```

One eligible accepted atomic raw CDC destination delivery creates exactly one retirement after the fixed
three-edge pipeline. Zero bitmap is a completed healthy evaluation:

```text
FAULT_PRESENT=fault_eval_valid && fault_eval_bitmap != 0
HEALTHY_EVALUATION=fault_eval_valid && fault_eval_bitmap == 0
FAULT_EVALUATION_VALID_AUTHORITY=ONE_PER_ATOMIC_RAW_CDC_DESTINATION_DELIVERY
FAULT_EVALUATION_LATENCY_CLASS=FIXED_3_ACLK_EDGES_DELIVERY_TO_POLICY_DECISION_II1
FAULT_EVALUATION_SEQUENCE_ALIGNED=YES
FAULT_EVALUATION_BITMAP_ALIGNED=YES
FAULT_EVALUATION_INTEGRITY_ALIGNED=YES
ZERO_BITMAP_IS_VALID_HEALTHY_EVALUATION=YES
CURRENT_FAULT_VALID_IS_EVALUATION_VALID=NO
```

Valid, sequence, bitmap, priority code, and integrity must be aligned. The
bitmap contains all primitive causes for the delivered channel pair; the code is
derived from that bitmap. The transaction path permits no drop, duplicate,
reorder, channel tearing, or cause tearing. It accepts one transaction each
ACLK. Reset invalidates every valid stage, so no pre-reset evaluation retires
after reset.

The modulo-2^32 sequence identifies aligned fields and diagnostics. The clear
fence uses retirement order rather than numeric sequence comparison, so wrap
does not change request ownership.

`RESET_WAIT` exits on one clean healthy retirement. A clean nonzero retirement
latches immediately. A non-clean retirement neither arms nor becomes a
physical fault cause, does not update first/live/seen state, and cannot accept
clear. The next independently clean retirement restores eligibility; there is
no software acknowledgement or global diagnostic epoch in this recovery.

```text
RESET_WAIT_POLICY=FIRST_ELIGIBLE_TRANSACTION_ARMS_IMMEDIATELY
HEALTHY_QUALIFICATION_COUNT=1
NO_SAMPLE_AFTER_RESET=REMAIN_RESET_WAIT_SAFE_INDEFINITELY
```

## 6. Fault authority and multiple-fault policy

The six primitive bitmap bits are CH1 overcurrent, CH2 overcurrent, mismatch,
sensor open, sensor saturation, and sensor stuck. Existing raw comparisons and
8-bit code values remain unchanged. Code selection is deterministic:

```text
OC_WITH_ANY_SENSOR > OVERCURRENT > SENSOR_SATURATION > SENSOR_OPEN
  > SENSOR_STUCK > SENSOR_MISMATCH > NONE
```

The selected code never substitutes for the complete bitmap. The internal
model is:

```text
first_fault_code    capture once at episode start
first_fault_bitmap  capture once at episode start
live_fault_bitmap   replace on every clean fault_eval
fault_seen_bitmap   OR every clean fault_eval within the episode
```

Non-clean evaluations do not mutate those fields. Public visibility remains
deferred to Stage 2H.

```text
SIMULTANEOUS_FAULT_PRIORITY=DETERMINISTIC
SIMULTANEOUS_FAULT_INFORMATION_PRESERVED=YES
```

## 7. Clear request fence

`CTRL[1]` at existing offset `0x00` remains a W1P request. In
`FAULT_LATCHED`, one request creates `clear_pending`. An evaluation already
retiring on the capture edge is ordered before the new request and does not
resolve it. The first `fault_eval_valid` on a strictly later ACLK edge is the
resolution transaction. This includes work delivered before the request but
retired after it.

```text
CLEAR_PROTOCOL=REQUEST_EVALUATION_FENCED
CLEAR_ACCEPT=clear_pending && fault_eval_valid &&
             fault_eval_bitmap == 0 && fault_eval_integrity_clean && !reset
CLEAR_REJECT=clear_pending && fault_eval_valid &&
             (fault_eval_bitmap != 0 || !fault_eval_integrity_clean)
PRE_REQUEST_EVALUATION_RESOLVES_CLEAR=NO
```

Acceptance and rejection both consume `clear_pending`; a rejection requires a
new request. Repeated or held requests while pending coalesce and cannot create
duplicate episode ends. Reset clears pending and all episode/pipeline state.
With no later evaluation, the controller stays `FAULT_LATCHED` and safe
indefinitely.

Under continuous II=1 traffic, the next retirement edge after request capture
resolves the request. There is no global pipeline-empty predicate, so healthy
continuous traffic cannot starve clear. A stale last-known healthy live bitmap
cannot accept clear because a fresh post-request retirement is mandatory.

A clean healthy resolution accepts clear and enters `RESET_WAIT`; it does not
also arm, leave `RESET_WAIT`, or release safe output. A later clean healthy
retirement is required for exit. A nonzero or non-clean resolution rejects and
leaves the episode latched and safe.

```text
CLEAR_PENDING_NO_SAMPLE=REMAIN_LATCHED_SAFE
CONTINUOUS_II1_CLEAR_PROGRESS=PASS
CLEAR_RESOLUTION_TRANSACTION_RELEASES_SAFE_OUTPUT=NO
POST_CLEAR_DESTINATION_STATE=RESET_WAIT
CLEAR_WHILE_ANY_LIVE_FAULT=REJECT
FAULT_AND_CLEAR_SAME_CYCLE=FAULT_PRIORITY
SOURCE_REMOVAL_WITHOUT_CLEAR=REMAIN_LATCHED
```

## 8. Policy decision cycle and reset

The policy decision cycle is the offset-3 ACLK edge where
`fault_eval_valid` and all aligned fields are consumed by the episode
controller:

```text
POLICY_DECISION_CLOCK=ACLK
POLICY_DECISION_CYCLE=FAULT_EVALUATION_RETIREMENT
RESET > FAULT > CLEAR > HEALTHY_PROGRESS
```

The FAULT priority applies to a clean nonzero retirement. A non-clean
retirement is not a physical fault; if clear is pending, it resolves as a clear
rejection. A accepted raw destination delivery that has not yet retired is handled by the request
fence, not by ambiguous same-cycle wording.

Reset dominates all branches, clears first/live/seen state and `clear_pending`,
flushes every pending evaluation valid, and restarts safe `RESET_WAIT` after
synchronized release. No pre-reset sequence, bitmap, code, or integrity result
may retire post-reset.

## 9. Stage 2E temporal integrity authority

`fault_eval_integrity_clean` is transaction-correlated. The minimum future
architecture combines:

1. A source offer-stability bit carried with sequence and both raw channels in
   the atomic FIFO payload.
2. The destination expected-sequence comparison attached on the delivered
   transaction's destination-delivery edge.

An accepted offer that changed while stalled carries a dirty source bit. A
withdrawn offer has no accepted transaction and remains diagnostic status only.
At the destination, an expected sequence is clean; a gap is dirty and resyncs
expected sequence to delivered plus one; duplicate or stale/reordered delivery
is dirty and retains the expected sequence. The next transaction that is
source-clean and matches the resulting expected sequence is independently
eligible.

The following classification is frozen:

| Stage 2E condition | Temporal class | Policy role |
|---|---|---|
| Source offer violation attached to an accepted transaction | TRANSACTION_CORRELATED_BLOCKER | Mark matching `fault_eval` non-clean |
| Destination duplicate/gap/reorder attached to delivery | TRANSACTION_CORRELATED_BLOCKER | Mark matching `fault_eval` non-clean |
| Source drop without acceptance | STATUS_ONLY | No direct policy gate |
| Delayed synchronized source counters | STATUS_ONLY | No direct policy gate |
| Overflow attempt without acceptance | STATUS_ONLY | No direct policy gate |
| Underflow attempt without delivery | STATUS_ONLY | No direct policy gate |
| Historical sticky W1C status | STATUS_ONLY | No direct policy gate |
| Counter saturation | STATUS_ONLY | No direct policy gate |
| Stage 2F source/profile telemetry mismatch | STATUS_ONLY | No raw-policy effect |
| No sample after reset or clear | STATUS_ONLY | State retention supplies the safe behavior |

There is no undefined `ERROR_IS_PENDING`. There is no global diagnostic
inhibit, and eventually consistent counters never qualify the current
transaction. Software W1C is diagnostic acknowledgement only and cannot grant
safety release.

```text
TRANSACTION_CORRELATED_INTEGRITY=EXPLICIT
EVENTUALLY_CONSISTENT_SOURCE_COUNTER_GATES_POLICY=NO
SOFTWARE_W1C_STICKY_GATES_POLICY=NO
STAGE2E_ERROR_CLASSIFICATION=PASS
```

## 10. Safe-output contract

```text
SAFE_ACTUATION_TRIGGER=RESET_OR_ANY_CLEAN_NONZERO_FAULT_EVAL
SAFE_ACTUATION_LATENCY_DOMAIN=FIXED_REGISTERED_ACLK_POLICY_PATH
SAFE_STATE_HOLD_CONDITION=RESET_WAIT_OR_FAULT_LATCHED_OR_CLEAR_PENDING
SAFE_STATE_RELEASE_CONDITION=LEGAL_CLEAR_TO_RESET_WAIT_THEN_LATER_CLEAN_HEALTHY_FAULT_EVAL
```

Later faults, source removal, rejected clear, pending clear, a clear resolution
transaction, normalized telemetry, delayed counters, and W1C status cannot
release safe output. The three-edge class is an internal implementation-derived
path, not a physical end-to-end latency claim.

## 11. Compatibility and Stage 2H boundary

The target is implementable without changing packaged external ports, current
offsets, software APIs, unsigned raw thresholds, or the Stage 2D atomic
transaction authority. Conceptual `CLEAR_PENDING`, first/live/seen bitmaps,
clear reject reason, and clear resolution sequence remain deferred to
`STAGE2H_SINGLE_SOURCE_REGISTER_MAP_CONVERGENCE`.

```text
REGISTER_VISIBILITY_OWNER=STAGE2H
NEW_AXI_OFFSETS_ADDED=NO
EXTERNAL_INTERFACE_CHANGE_REQUIRED=NO
STAGE2G_IMPLEMENTATION_STARTED=NO
RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```

## 12. Decision disposition

The machine contract contains all prior decisions plus the 13 hardening
decisions. Every behavior decision is `APPROVED`; register visibility alone is
`DEFERRED_TO_STAGE2H`. `open_owner_decisions` is empty. No unresolved decision
is hidden in prose, and this rereview readiness does not authorize RTL work or
close either remaining contract gap.
