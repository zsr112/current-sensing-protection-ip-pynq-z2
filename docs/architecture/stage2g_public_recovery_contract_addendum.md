# Stage 2G public recovery observability implementation addendum

This implementation-era addendum narrows the meaning of the existing public
`STATUS.FAULT_LATCHED` and `FAULT_CODE` registers. It supplements, and does not
rewrite or relocate, the frozen Stage 2G architecture audit. No AXI offset,
public port, or software API changes are authorized.

## Recovery boundary

The controller has two related but deliberately distinct boundaries:

1. A legal clear acceptance ends the internal fault episode, clears internal
   first/live/seen episode fields, asserts the safe hold, and enters
   `RESET_WAIT`.
2. Public recovery completes only when a later clean healthy evaluation enters
   `ARMED`.

Between those boundaries, the existing public latch remains asserted and the
existing public code retains the prior first cause. This makes post-clear
`RESET_WAIT` distinguishable from recovered `ARMED` without adding a status
bit. No sample and non-clean evaluations retain this compatibility state. A
clean fault before re-arm starts a new internal episode and replaces the public
code with that episode's first cause.

The implementation names are `public_fault_latched_compat`,
`public_fault_code_compat`, and `post_clear_recovery_pending`. The pending field
is internal debug state; the public register bank continues to consume only the
existing latch and code outputs.

## Software contract

`sw/protection_ip_interface.py::recovery_is_verified()` is unchanged. RTL AXI
snapshots are passed to that predicate. It remains false for clear acceptance,
no-sample post-clear retention, non-clean post-clear retention, and a new fault
before re-arm. It becomes true only after a later clean healthy evaluation has
entered `ARMED`, cleared the existing public latch/code, and PWM remains
disabled in `CTRL` for software verification.

## Frozen markers

```text
INTERNAL_EPISODE_END=LEGAL_CLEAR_ACCEPTANCE
PUBLIC_RECOVERY_COMPLETE=LATER_CLEAN_HEALTHY_EVALUATION_ENTERING_ARMED
CLEAR_ACCEPTANCE_EQUALS_PUBLIC_RECOVERY_COMPLETE=NO
PUBLIC_STATUS_OWNER=EXISTING_STATUS_AND_FAULT_CODE_REGISTERS
NEW_RECOVERY_STATUS_BIT_ADDED=NO
SOFTWARE_RECOVERY_API_CHANGED=NO
STATUS_FAULT_LATCHED_DURING_POST_CLEAR_RESET_WAIT=1
FAULT_CODE_DURING_POST_CLEAR_RESET_WAIT=RETAIN_PRIOR_FIRST_CAUSE
NO_SAMPLE_POST_CLEAR_RECOVERY_VERIFIED=NO
NONCLEAN_POST_CLEAR_RECOVERY_VERIFIED=NO
LATER_HEALTHY_CLEARS_COMPATIBILITY_STATUS=PASS
POST_CLEAR_FAULT_REPLACES_WITH_NEW_FIRST_CAUSE=PASS
RESET_CLEARS_COMPATIBILITY_STATUS=PASS
RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```

No synthesis, implementation, bitstream, Hardware Manager, physical-unit, or
board claim is made by this addendum.
