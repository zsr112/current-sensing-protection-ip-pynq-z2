# Stage 2G sequence-width contract addendum

This implementation-era addendum narrows an ambiguity found during concrete
review of the functional Stage 2G RTL. It does not rewrite or move the frozen
architecture-audit tag. The active implementation contract is:

```text
FAULT_EVAL_SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH
SUPPORTED_SEQUENCE_WIDTHS=16_TO_32
SEQUENCE_ARITHMETIC=MODULO_2_POW_SEQUENCE_WIDTH
SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH
```

Every Stage 2G captured, decision, evaluation, expected, delta, and
clear-resolution sequence field is `[SEQUENCE_WIDTH-1:0]`. The production
asynchronous top binds the Stage 2G AXI companion with
`.SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH)`. The AXI and register-controlled
companions propagate that same value into `stage2g_protection_core`, which
propagates it into the evaluation pipeline and episode controller. Supported
values below 16 or above 32, and any Stage 2G/observability binding mismatch,
fail elaboration.

## Shared Stage 2E classification authority

`stage2e_transaction_sequence_classifier` in
`rtl/transaction_destination_observer.v` is the single combinational
classification authority used by both the unchanged Stage 2E destination
observer state machine and the Stage 2G policy-integrity path. For one
delivered transaction:

| Delivery | Classification | Expected-sequence update | Policy integrity |
|---|---|---|---|
| `sequence == expected` | expected | `expected + 1` | destination clean |
| first delivery and sequence is nonzero | stale/reorder | retain zero | dirty |
| same as the most recent delivery | duplicate | retain expected | dirty |
| positive half-range delta | forward gap | `delivered + 1` | dirty |
| negative half-range delta | reorder/stale | retain expected | dirty |

The immediately following value after a stale first nonzero delivery is a
forward gap, remains dirty, and resynchronizes. Only the next value matching
the resynchronized expected sequence restores eligibility. Arithmetic and
the delta sign test use `SEQUENCE_WIDTH`; the sign bit is
`sequence_delta[SEQUENCE_WIDTH-1]`.

## Wrap and clear ordering

Wrap is ordinary modulo arithmetic for widths 16, 24, and 32. The clean
sequence `max-1, max, 0, 1` remains clean. Gap, duplicate, and recovery rules
are unchanged across wrap. The clear fence does not compare sequence numbers:
it is ordered only by ACLK evaluation retirement, so wrap cannot move a
transaction across the request boundary.

## Verification and non-claims

The Icarus and XSim matrix exercises width propagation, Stage 2E equivalence,
first-delivery behavior, gap/duplicate/reorder recovery, wrap, clear at wrap,
and RESET_WAIT qualification at widths 16, 24, and 32. Compiler diagnostics
indicating Stage 2G port resizing or truncation fail the matrix. This addendum
adds no AXI offset, external port, software API, physical-unit claim,
calibration, liveness watchdog, synthesis result, bitstream, or board claim.

The preserved project status remains:

```text
RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```
