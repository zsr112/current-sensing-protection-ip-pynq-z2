# Attempt01 non-claim boundary

Attempt01 stopped at the `normal_pwm` host checkpoint before fault injection.
Its return code was 130 and its evidence identifies the host-side failure as:

`HOST_ILA_OBJECT_MATCHER_INCOMPATIBLE_WITH_ACTUAL_HW_MANAGER_NAMES`

The FPGA reported one ILA (`hw_ila_1`) whose `CELL_NAME` was
`protection_system_i/system_ila_stage2b_0/inst/ila_lib`. The old host matcher
compared the Hardware Manager object `NAME` against that `CELL_NAME`, so it
accepted zero candidates. This is not evidence that BIT, LTX, or ILA was
missing.

Attempt01's board-functional verdict remains `NOT_PROVEN`; it must not be
described as a protection-function failure or PASS. Fault injection did not
start and no functional sequence result was produced.

Fail-closed cleanup did pass. Its final observed state was `CTRL=0`,
`STATUS=0`, `FAULT_CODE=0`, GPIO `DATA=0x00400400`, and CH1/CH2 `1024/1024`.
The board wall clock was not trustworthy; the external operator/host receipt
is authoritative for the actual execution date.

Attempt02 was a distinct attempt and also remains `NOT_PROVEN`; see
`ATTEMPT02_NON_CLAIM.md`. Attempt03 requires both
`STAGE1_ILA_BINDING_PREFLIGHT_PASS` and
`STAGE1_ILA_CAPTURE_CONFIGURATION_PREFLIGHT_PASS` before board Python may
start.
