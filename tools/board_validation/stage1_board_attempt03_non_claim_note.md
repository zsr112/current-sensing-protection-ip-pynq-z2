# Attempt03 Non-Claim Boundary

Attempt03 is closed as `NOT_PROVEN`. Its real binding preflight passed against
FPGA device `xc7z020_1` and ILA `hw_ila_1`, with the accepted `CELL_NAME`,
39 leaf probes, and 11 logical probes.

The following real capture-configuration preflight then exited with RC `1`.
Its Vivado log is 6,258 bytes. At runtime `PROBES.FILE` was empty, zero ILAs
matched a probes file, and no matching `hw_probes` were available. None of the
five property-capability plans started, and `CONTROL.CAPTURE_MODE` was not
inspected.

The exact failure domain is:

```text
HOST_CAPTURE_CONFIGURATION_PREFLIGHT_LTX_BINDING_OMISSION
```

This is not a BIT/LTX identity failure, an absent programmed ILA, a
`CONTROL.CAPTURE_MODE` failure, or a protection-IP functional failure.
Attempt03 did not start board Python, SSH, Overlay, MMIO/GPIO, fault
injection, or any ILA arm, trigger, wait, upload, or export operation.

The raw attempt03 failure evidence is preserved outside this execution
package. It is intentionally not copied into Attempt04 and must not be edited,
overwritten, deleted, or reused as a later attempt.
