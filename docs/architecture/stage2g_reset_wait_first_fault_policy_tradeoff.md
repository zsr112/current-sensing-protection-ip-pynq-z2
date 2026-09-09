# Stage 2G transaction-boundary policy tradeoff

This comparison freezes architecture before functional RTL. Scores are
relative: 5 is strongest for safety, determinism, compatibility,
observability, and extensibility; for burden columns, 5 is least burden. The
machine authority remains
`spec/stage2g_reset_wait_first_fault_policy.json`.

## RESET_WAIT arming

| Alternative | Safety | Determinism | Compatibility | Verification burden | RTL burden | Decision |
|---|---:|---:|---:|---:|---:|---|
| First clean eligible evaluation arms | 5 | 5 | 5 | 5 | 5 | SELECTED |
| N consecutive clean evaluations | 4 | 4 | 3 | 3 | 3 | Rejected without an owned N requirement |
| Hybrid sample window plus timeout | 3 | 2 | 2 | 2 | 2 | Rejected; no timeout owner exists |

The selected rule keeps `HEALTHY_QUALIFICATION_COUNT=1`. No sample means safe
`RESET_WAIT` indefinitely. A first clean fault latches instead of arming, and a
non-clean evaluation leaves the controller safe until the next clean
evaluation.

## Evaluation-valid boundary

| Alternative | Healthy completion explicit | Transaction alignment | Continuous II=1 | Decision |
|---|---:|---:|---:|---|
| Reuse current `fault_valid` | No | No | Ambiguous | Rejected: zero means healthy or idle |
| Infer health from held live bitmap | No | Partial | Stale-value risk | Rejected |
| Add aligned `fault_eval` transaction | Yes | Full | Native | SELECTED |

The selected transaction carries valid, 32-bit sequence, six-bit bitmap,
8-bit priority code, and integrity. It uses the existing fixed three-edge ACLK
pipeline with initiation interval one. It adds internal architecture fields,
not external ports or register offsets.

## Clear boundary

| Alternative | Safety | Bounded progress at II=1 | Same-edge ownership | Sequence-wrap burden | Decision |
|---|---:|---:|---:|---:|---|
| Require globally empty evaluation pipeline | 3 | 1 | Ambiguous | None | Rejected: can starve continuously |
| Accept from last-known live bitmap | 2 | 5 | Ambiguous | None | Rejected: stale healthy can race an in-flight fault |
| Sequence-watermark fence | 5 | 5 | Must be specified | High | Not selected |
| Retirement-ordered request fence | 5 | 5 | Explicit | None | SELECTED |

The selected fence captures one request in `FAULT_LATCHED`. An evaluation on
that edge is earlier and cannot resolve it. The first retirement on a strictly
later edge resolves it, even when that transaction was delivered before the request.
No numeric sequence comparison is used, so modulo wrap does not alter
ownership.

Acceptance requires a clean zero bitmap. Nonzero or non-clean resolution
rejects. Both outcomes consume `clear_pending`; repeated requests coalesce.
No later sample leaves the latch safe indefinitely. A successful resolution
enters `RESET_WAIT`, and a later clean healthy retirement is needed to arm.

## Continuous stream progress analysis

For a request captured at ACLK edge `R`, any transaction retiring at `R` is
pre-request. With II=1 traffic, the pipeline retires another transaction at
`R+1`; that first strictly later retirement resolves the request. Therefore:

```text
request-to-resolution bound under continuous retirement = 1 ACLK edge
global pipeline empty required = no
healthy continuous traffic can starve clear = no
faulting continuous traffic resolution = reject at R+1
non-clean continuous traffic resolution = reject at R+1
```

The bound is expressed in retirement edges, not physical sample acquisition
latency. With no retirement there is deliberately no progress and safe state
is retained.

## Integrity temporal authority

| Candidate authority | Same-transaction identity | CDC timing | Software dependence | Decision |
|---|---:|---:|---:|---|
| Source offer-stability bit carried in FIFO payload | Yes | Atomic with payload | None | SELECTED component |
| Destination expected-sequence comparison on accepted delivery | Yes | Already in ACLK | None | SELECTED component |
| Gray-synchronized source counters | No | Eventually consistent | None | STATUS_ONLY |
| Historical W1C sticky status | No | Historical | Yes for clear | STATUS_ONLY |
| Underflow/overflow attempt with no transaction | No transaction exists | Domain-local | None | STATUS_ONLY |

The two selected components combine into
`fault_eval_integrity_clean`. A matching non-clean evaluation cannot arm,
accept clear, become a physical cause, overwrite first cause, or update
live/seen state. The next source-clean transaction that satisfies the updated
destination expected-sequence rule is eligible. There is no global diagnostic
inhibit and no software-controlled release permission.

## First-cause representation

| Alternative | Cause preservation | Compatibility | Verification burden | Decision |
|---|---:|---:|---:|---|
| One priority code | 1 | 5 | 5 | Rejected |
| First code plus first bitmap | 4 | 5 | 4 | Minimum capture model |
| First code plus first/live/seen bitmaps | 5 | 4 | 3 | SELECTED internal model |

The existing 8-bit code stays compatible. First code and first bitmap are
immutable per episode; clean evaluations replace live and accumulate seen.
Non-clean evaluations update none of them. Visibility remains deferred to
Stage 2H.

## Selection result

The selected design has one explicit evaluation transaction, one retirement
decision point, one clear request fence, and one transaction-correlated
integrity bit. It avoids a timeout, pipeline-empty wait, numeric watermark,
global diagnostic epoch, software safety permission, new state abstraction,
or new public offset.

```text
FAULT_EVALUATION_TRANSACTION=EXPLICIT
CLEAR_PROTOCOL=REQUEST_EVALUATION_FENCED
CONTINUOUS_II1_CLEAR_PROGRESS=PASS
POLICY_DECISION_CYCLE=FAULT_EVALUATION_RETIREMENT
TRANSACTION_CORRELATED_INTEGRITY=EXPLICIT
NEW_AXI_OFFSETS_ADDED=NO
STAGE2G_IMPLEMENTATION_STARTED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```
