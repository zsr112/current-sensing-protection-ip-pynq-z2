# Independent rereview contract: Stage 2G transaction boundary

Review this package as architecture hardening, not as a functional RTL merge.
The source base is `94b400ad3a713f4fdaf7b0e347c40baeab28a924` and
the review diff starts at `af0c604d9de9fa4a6b659940be2d41f9fbc170bd`.
The branch must contain no functional RTL, AXI, software, threshold, synthesis,
implementation, bitstream, or board changes.

## Review questions

1. Does one explicit `fault_eval` retire for every eligible accepted atomic raw CDC destination delivery,
   including a valid zero-bitmap healthy result?
2. Are valid, sequence, bitmap, code, and integrity aligned through the exact
   0/1/2/3 ACLK pipeline with fixed three-edge latency and II=1?
3. Is current `fault_valid` correctly documented as registered nonzero presence
   rather than evaluation valid?
4. Does reset flush all pending valid stages so no pre-reset evaluation can
   retire post-reset?
5. Does a clear request create `clear_pending`, exclude same-edge/pre-request
   retirement, and resolve on the first strictly later retirement?
6. Is clear progress bounded under continuous II=1 traffic without requiring a
   globally empty pipeline, while no-sample behavior remains latched and safe?
7. Do nonzero and non-clean resolution reject, clean zero accept, and both
   consume pending without duplicate episode ends?
8. Does a successful resolution enter `RESET_WAIT` without arming or releasing
   safe output on that same transaction?
9. Is the ACLK fault-evaluation retirement edge the only policy decision cycle
   for `RESET > FAULT > CLEAR > HEALTHY_PROGRESS`?
10. Is transaction integrity built from a carried source offer-stability bit
    plus the delivered transaction's destination expected-sequence result?
11. Are delayed counters, sticky W1C history, saturation, underflow without
    delivery, and overflow without acceptance status-only and unable to gate
    safety progress?
12. Are prior episode, first-cause, simultaneous-cause, raw-authority, Stage 2H
    visibility, two-gap, and Stage 2 incomplete decisions preserved?

## Required disposition

Report every machine-contract decision as exactly one of `APPROVED`,
`DEFERRED_TO_STAGE2H`, `OWNER_DECISION_REQUIRED`, or `NOT_APPLICABLE`. No
unresolved point may be hidden in prose. A positive rereview authorizes only a
later implementation plan; it does not start Stage 2G implementation, close a
contract gap, or declare Stage 2 complete.
