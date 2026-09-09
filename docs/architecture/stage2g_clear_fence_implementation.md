# Stage 2G request/evaluation-fenced clear

The existing control W1P clear request at offset `0x00` is preserved. In
`FAULT_LATCHED`, a request captures `clear_pending`; it is not an immediate
state transition and it is not a software acknowledgement authority.

## Retirement ordering

Policy decisions occur on the ACLK edge that consumes `fault_eval_*`.

```text
1. An evaluation retiring on the request edge is earlier than the new request.
2. The request is captured after that retirement and cannot be resolved by it.
3. The first valid evaluation on a strictly later ACLK edge resolves the request.
4. A destination delivery before the request may resolve it if its retirement is later.
```

This is a retirement fence, not a global pipeline-empty test and not a numeric
sequence comparison. Repeated or held requests while pending are coalesced.
After either acceptance or rejection, `clear_pending` is cleared and a new
request is required.

All clear-resolution identity fields use `[SEQUENCE_WIDTH-1:0]`, where the
production binding is `SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH` for supported widths
16 through 32. Because the fence never compares identities, `max -> 0` wrap
does not affect request ordering; the width matrix exercises a resolution at
zero followed by RESET_WAIT qualification at one.

## Resolution rules

The fresh post-request evaluation is accepted only when:

```text
clear_pending
&& fault_eval_valid
&& fault_eval_bitmap == 0
&& fault_eval_integrity_clean
&& !reset
```

A valid nonzero or non-clean evaluation rejects the request, keeps the episode
latched, and keeps the safe gate asserted. With no later evaluation,
`clear_pending` remains set and the controller remains `FAULT_LATCHED` and
safe indefinitely.

Acceptance clears all episode fields and enters `RESET_WAIT`. It asserts the
safe gate for the entire resolution cycle and cannot also arm. Only a later
clean healthy evaluation exits `RESET_WAIT` to `ARMED`; a later clean fault
latches a new episode immediately. A source disappearing before or after a
request never acts as an implicit clear.

## Priority and reset

The policy ordering is:

```text
RESET > FAULT > CLEAR > HEALTHY_PROGRESS
```

Reset asynchronously clears `clear_pending`, first/live/seen fields, and all
evaluation valid stages, then forces `RESET_WAIT` and the safe output. Reset
therefore wins over a fault, a clear request, or any in-flight transaction.

## Safety boundary

`pwm_disable` is asserted in `RESET_WAIT`, `FAULT_LATCHED`, and while a clear
resolution is being observed. `pwm_out` is released only after a subsequent
eligible healthy evaluation arms the controller. Neither W1C history, delayed
diagnostic counters, normalized telemetry, nor source removal can release it.
