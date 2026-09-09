# Attempt02 non-claim boundary

Attempt02 passed the host-only ILA binding preflight. It selected FPGA
`xc7z020_1`, ILA `hw_ila_1`, and cell
`protection_system_i/system_ila_stage2b_0/inst/ila_lib`; it mapped 11 logical
probes within 39 leaf probes.

The first `normal_pwm` capture then stopped before any ILA sample was uploaded
or CSV was written. Vivado 2024.1 reported:

`hw_ila property 'CONTROL.CAPTURE_MODE' is read-only`

The exact failure domain is
`HOST_ILA_CAPTURE_PROPERTY_INCOMPATIBLE_WITH_VIVADO_2024_1`. This is not a
device-selection, LTX-binding, ILA-identity, probe-mapping, accepted-artifact,
IP-function, or PWM-function failure.

The board process serialized `KeyboardInterrupt` at `normal_pwm` and exited
130. It produced no functional sequence, did not enter fault injection, and
left board MMIO and PWM-gate proof `NOT_PROVEN`. The functional verdict remains
`NOT_PROVEN`; there is no attempt02 ILA CSV.

Fail-closed cleanup passed. Final observations were `CTRL=0`, `STATUS=0`,
`FAULT_CODE=0`, GPIO `DATA=0x00400400`, and CH1/CH2 `1024/1024`. The board wall
clock is `UNTRUSTED`; monotonic ordering and the external operator record
govern chronology.

Attempt03 is a distinct execution attempt. It requires both
`STAGE1_ILA_BINDING_PREFLIGHT_PASS` and
`STAGE1_ILA_CAPTURE_CONFIGURATION_PREFLIGHT_PASS` before board Python may
start.
