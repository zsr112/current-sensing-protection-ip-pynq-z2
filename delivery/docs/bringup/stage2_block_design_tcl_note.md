# Stage 2 Block Design Tcl Note

## Purpose

This document records the Stage 2 block-design Tcl and its controlled
validation results. The generated `protection_system.bd` lives in the configured
external build root and is not tracked in Git.
The repository keeps only the reproducible Tcl and this explanatory note.

## Why Use The Packaged IP

The Stage 2 BD should instantiate
`zsr112.local:protection:protection_ip_axi_lite:0.3` from the generated IP
repository instead of directly adding the RTL module. The packaged IP carries
explicit AXI4-Lite, clock, reset, address, and file-group metadata, which is a
cleaner basis for Address Editor, later `.hwh` export, and PYNQ MMIO work.

## Minimal BD Structure

The proposed first-pass design is:

- `processing_system7_0`
- `proc_sys_reset_0`
- `smartconnect_0`
- `protection_ip_axi_lite_0`
- `xlconstant` stimulus for `adc_sample_valid`, `adc_sample_ch1`, and
  `adc_sample_ch2`

Clock/reset plan:

- PS `FCLK_CLK0` drives SmartConnect and `protection_ip_axi_lite_0/ACLK`.
- The same placeholder `FCLK_CLK0` drives
  `protection_ip_axi_lite_0/adc_src_clk`; the packaged interface still
  supports a future distinct source clock.
- PS `FCLK_RESET0_N` is active-low and drives `proc_sys_reset_0/ext_reset_in`.
- The BD Tcl explicitly checks that PS `FCLK_RESET0_N` is `ACTIVE_LOW`, that
  `proc_sys_reset_0/ext_reset_in` propagates to `ACTIVE_LOW`, and that the
  propagated `proc_sys_reset_0` `CONFIG.C_EXT_RESET_HIGH` value is `0`.
- `proc_sys_reset_0/peripheral_aresetn` is active-low and drives both
  `smartconnect_0/aresetn` and `protection_ip_axi_lite_0/ARESETN`.

## Reset Policy

Vivado 2024.1 treats `proc_sys_reset_0` `CONFIG.C_EXT_RESET_HIGH` as a
BD-propagated/read-only value in this flow. Directly forcing that cell
parameter produces a `BD 41-737` critical warning. The
`proc_sys_reset_0/ext_reset_in` pin polarity is also propagated/read-only before
connection. The Tcl therefore connects PS `FCLK_RESET0_N` to
`proc_sys_reset_0/ext_reset_in`, then fails unless the propagated pin polarity
is `ACTIVE_LOW` and `CONFIG.C_EXT_RESET_HIGH` is `0`. The assertion runs after
`validate_bd_design` and before `save_bd_design`, so a bad propagated reset
policy prevents saving the `.bd`. This keeps the reset polarity explicit
without depending on a hidden default or accepting a critical warning.

AXI plan:

- `processing_system7_0/M_AXI_GP0` connects to the SmartConnect slave side.
- The SmartConnect master side connects to `protection_ip_axi_lite_0/S_AXI`.

## First BD Run Finding

The first controlled Stage 2 BD run in Vivado 2024.1 failed early while creating
the AXI fabric because `xilinx.com:ip:axi_interconnect:1.7` was reported as an
unsupported IP in this BD flow. The failure happened during early BD creation;
there was no synthesis, implementation, bitstream generation, or hardware
export.

The revised Tcl uses SmartConnect instead. The partially written external Stage
1 Vivado project from the failed run should be archived and a clean Stage 1
project should be recreated before rerunning the Stage 2 BD Tcl, so later runs
do not inherit a half-created `protection_system.bd`.

A controlled rerun of the SmartConnect revision completed BD creation,
`validate_bd_design`, and `save_bd_design` without Vivado `ERROR` or
`CRITICAL WARNING` messages. The remaining Vivado warnings are non-blocking for
the first AXI4-Lite MMIO BD artifact:

- PS7 board automation leaves a user-strength `PCW_M_AXI_GP0_FREQMHZ` value
  while propagation sees the 100 MHz FCLK0 connection.
- SmartConnect low-area mode warns that WRAP bursts would DECERR. The planned
  PYNQ MMIO path is AXI4-Lite and should not require WRAP bursts.

## PS7 Board Preset Requirement

The Stage 2 BD must apply the PYNQ-Z2 processing-system board preset or board
automation. Only enabling `M_AXI_GP0` and `FCLK_CLK0` is not enough for a
complete PYNQ-Z2 PS block design.

The Tcl keeps FCLK0 at 100 MHz explicitly and lets Vivado propagate dependent
PS clock parameters such as the GP0 AXI frequency. Those propagated parameters
can be read-only in the BD flow and should not be forced independently.

The BD Tcl therefore treats these as required checks:

- DDR must be externalized.
- FIXED_IO must be externalized.
- `M_AXI_GP0` must exist.
- `FCLK_CLK0` must exist.
- `FCLK_RESET0_N` must exist.

If board automation fails, the script should stop and the Vivado 2024.1 GUI
automation command should be inspected before rerunning.

## Address Policy

`0x43C00000` is still a planning address. The final address must be confirmed
from Vivado Address Editor or the `assign_bd_address` result after the BD Tcl is
run.

The packaged IP uses an IP-XACT/BD range of `0x1000`. The RTL true decode
aperture remains `0x100` because `AXI_ADDR_WIDTH=8`. Accesses beyond the low 8
address bits can alias unless the RTL decode is widened later.

## Safe-inert stimulus profile

The production-referenced Tcl uses constants only for safe digital bring-up
plumbing:

- `adc_sample_valid = 0`
- `adc_sample_ch1 = 12'h400`
- `adc_sample_ch2 = 12'h400`

This is the `SAFE_INERT` profile: it cannot create a source transaction and it
does not represent functional ADC/AFE input, fault injection, calibration,
isolation, or sensor hardware. A future functional production profile must be
classified `FUNCTIONAL_READY_AWARE` and provide a valid source, consume ready,
prevent payload overwrite while ready is low, and produce bounded transaction
pulses.

The current clock and debug boundary is machine-bound as follows:

```text
FUNCTIONAL_ADC_STIMULUS=NO
CURRENT_ADC_SRC_CLK_EQUALS_ACLK=YES
ACLK_ILA_READY_OBSERVATION_VALID_ONLY_WHILE_CLOCKS_IDENTICAL=YES
ACLK_ILA_READY_OBSERVATION_BOUNDARY=DOCUMENTED
DISTINCT_ADC_CLOCK_REQUIRES_SOURCE_CLOCK_ILA_OR_SYNCHRONIZED_OBSERVATION=YES
DISTINCT_CLOCK_DEBUG_POLICY=SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION
DIRECT_ASYNC_READY_OBSERVATION_AS_CDC_PROOF=FORBIDDEN
```

ILA probe 11 is clocked by `ACLK`. Its ready observation is therefore valid as
acceptance evidence only because the current `adc_src_clk` and `ACLK` are the
same `FCLK_CLK0` net. If those clocks become distinct, use a source-domain ILA
or a deliberately synchronized observation. A direct asynchronous ready probe
is not CDC proof.

## Outputs And Safety

The first-pass BD does not connect `pwm_raw`, `pwm_out`, `fault_valid`,
`fault_latched`, `fault_code`, `fault_code_latched`, or `fsm_state` to real
board pins. Do not connect `pwm_out` to a real gate driver or power stage in
this stage. Use a later ILA, VIO, GPIO, or wrapper/stimulus plan for debug.

Recommended later ILA probes include S_AXI handshakes, `adc_sample_ch1`,
`adc_sample_ch2`, `adc_sample_valid`, `adc_sample_ready`, `fault_latched`,
`fault_code`, `pwm_out`, and `fsm_state`.

## Current Boundary

Controlled BD creation has been run only to create, validate, and save the
external `.bd` artifact. This step still does not generate `.bit`, `.hwh`,
`.xsa`, or `.ltx` files and does not prove PYNQ MMIO or board-level
validation. The next steps are to inspect Address Editor output and decide
whether to add Stage 2B ILA/debug Tcl before any synthesis or implementation.

## Wrapper Boundary

The current BD Tcl does not create output products, create an HDL wrapper, or
set the project top to a wrapper. Before synthesis, bitstream generation, or
`.hwh` export, a separate reviewed wrapper/output-product step is still needed.

## Run Boundary

Even after the BD Tcl runs successfully, the result should still not be
described as bitstream generation, PYNQ MMIO validation, or board-level
validation. It is only the next integration artifact before debug insertion,
address review, synthesis, implementation, and export.
