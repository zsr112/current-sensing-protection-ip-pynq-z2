# Stage 2F ADC encoding and scaling architecture audit

Date: 2026-08-05
Base commit: `301bb72cafa3957392e9a64a5e6b2e97c4466886`
Scope: architecture, contracts, inventories, verification, and reference research only

## Executive result

The current 12-bit RTL path consistently transports and compares unsigned raw
codes. It does not establish the encoding or physical meaning of a future ADC.
The production source is a safe-inert digital placeholder, and the production
source profile is explicitly unconfigured. No accepted sample is converted to
a signed telemetry value in the current production build.

The accepted facts remain:

```text
CURRENT_RAW_SAMPLE_WIDTH=12
CURRENT_RTL_INTERPRETATION=UNSIGNED
CURRENT_RAW_ENCODING=UNKNOWN
CURRENT_THRESHOLD_DOMAIN=UNSIGNED_RAW_CODE
TH_DIFF_DOMAIN=UNSIGNED_RAW_CODE_DIFFERENCE
RAW_READBACK=ZERO_EXTENDED_12_BIT
THRESHOLD_WRITE_RANGE_BEHAVIOR=SILENT_LOW_12_BIT_TRUNCATION
REAL_ADC_DEVICE=UNKNOWN
REAL_AFE_GAIN=UNKNOWN
REAL_SENSOR_SENSITIVITY=UNKNOWN
REAL_ZERO_CURRENT_CODE=UNKNOWN
REAL_CURRENT_RANGE=UNKNOWN
BOARD_CALIBRATION_DATA=NOT_AVAILABLE
PRODUCTION_INPUT_SOURCE=SAFE_INERT_DIGITAL_PLACEHOLDER
CURRENT_PRODUCTION_PROFILE=UNCONFIGURED
```

The hardened architecture preserves the existing accepted atomic raw CDC destination delivery and forks
it into the unchanged raw protection path and a future signed code-count
telemetry path. The initial digital transform is limited to selected encoding,
nominal zero-code removal, and polarity. It has no board-calibration arithmetic,
generic rational divider, physical unit, or normalized-domain fault policy.

```text
RAW_PATH_UNCHANGED=YES
PROTECTION_THRESHOLD_DOMAIN=UNSIGNED_RAW_CODE_COMPATIBILITY
NORMALIZED_UNIT=SIGNED_CODE_COUNT
PHYSICAL_UNIT=NOT_CONFIGURED
GENERIC_RATIONAL_DIVIDER=NO
BOARD_CALIBRATION_ARITHMETIC=DEFERRED
```

This audit changes no RTL, runtime software, register RTL, or production Tcl.
It does not close or rename the frozen Stage 2F gap:

```text
STAGE2F_IMPLEMENTATION_STARTED=NO
STAGE2F_CONTRACT_GAP_CLOSED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```

## Evidence and machine-readable records

The repository trace covers RTL, testbenches, Vivado sources, build profiles,
constraints, C and Python interfaces, register documentation, and frozen Stage
2B through Stage 2E results. The authoritative audit records are:

- `spec/stage2f_adc_fact_inventory.json`
- `spec/stage2f_adc_data_path_inventory.json`
- `spec/stage2f_scaling_parameter_authority.json`
- `spec/stage2f_closure_boundary.json`
- `spec/stage2f_adc_source_profile.schema.json`
- `spec/stage2f_adc_source_profile_unconfigured.json`

Facts, derived inferences, design decisions, external hardware unknowns, board
calibration requirements, and out-of-scope items remain separately classified.
An unsigned Verilog vector is evidence of current arithmetic behavior, not an
ADC output-coding fact.

## Current data path and preserved behavior

The machine-readable node trace is in
`spec/stage2f_adc_data_path_inventory.json`. The operative path is:

```text
safe-inert source
  -> ready/valid source boundary
  -> source transaction observer
  -> atomic FIFO {sequence, channel_1, channel_2}
  -> atomic raw CDC destination delivery in ACLK
       -> accepted raw pair -> raw compare/health/fault policy
       -> raw monitor readback
```

The FIFO word preserves the 32-bit sequence and both 12-bit channels as one
transaction. Current overcurrent comparison is strict unsigned greater-than.
Current mismatch comparison orders unsigned operands, subtracts the smaller
from the larger, and compares the 12-bit raw-code difference. Sensor-health
endpoints are raw digital policies, not proven analog fault meanings.

`I_CH1` and `I_CH2` expose zero-extended raw codes. `TH_OC1`, `TH_OC2`, and
`TH_DIFF` silently retain AXI write bits 11:0 and discard bits 31:12. C and
Python expose nonnegative integers and perform no signed decoding or physical
conversion. Existing offsets from `0x00` through `0x60` and all those semantics
remain unchanged.

## Closure boundary hardening

The frozen gap is still `ADC_ENCODING_AND_PHYSICAL_SCALING`. It is tracked as
two parts without reducing the frozen gap count:

```text
STAGE2F_DIGITAL_FOUNDATION_SCOPE=EXPLICIT_ENCODING_AND_SIGNED_CODE_NORMALIZATION
STAGE2F_PHYSICAL_CLOSURE_SCOPE=SOURCE_SPECIFIC_CODE_TO_CURRENT_SCALING_AND_CALIBRATION_AUTHORITY
DIGITAL_FOUNDATION_CLOSES_FROZEN_STAGE2F_GAP=NO
PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS
PHYSICAL_CLOSURE_PREREQUISITE=APPROVED_ADC_AFE_SENSOR_PROFILE_OR_OWNER_APPROVED_SCOPE_CHANGE
```

Digital foundation evidence can eventually prove explicit decoding, polarity,
transaction alignment, fixed latency, initiation interval one, and raw-path
compatibility. Physical closure additionally needs approved ADC/AFE/sensor
identities, a source-specific transfer function, reference or supply policy,
error budget, safety review, and board-identity-bound calibration evidence.
`spec/stage2f_closure_boundary.json` records each subclaim and the exact
evidence required. No digital subclaim is used as a substitute for a physical
claim.

## Source-profile boundary

The small source-profile schema owns only raw width, encoding, nominal zero,
per-channel polarity, identity, physical-unit status, state, and production
selection. Its useful digital taxonomy is:

```text
UNSIGNED_WITH_ZERO_CODE
TWOS_COMPLEMENT
```

Offset binary is not a third arithmetic mode. It is represented by
`encoding=UNSIGNED_WITH_ZERO_CODE` with a midscale `zero_code`. This preserves
source meaning without redundant decoder logic.

`UNCONFIGURED` is a reserved identity. A `CONFIGURED_DIGITAL` profile must use
a non-reserved identity, a configured encoding with a valid zero-code rule,
and explicit polarity on both channels. Production selection additionally
requires all of those configured semantics.

The tracked production instance remains nonfunctional for normalized
telemetry:

```text
CURRENT_PRODUCTION_PROFILE=UNCONFIGURED
CURRENT_PRODUCTION_NORMALIZED_TELEMETRY=UNAVAILABLE_UNCONFIGURED
RAW_PROTECTION_ACTIVE_BEHAVIOR=UNCHANGED
SIMULATION_PROFILES_MAY_SELECT_EXPLICIT_DIGITAL_ENCODINGS=YES
SIMULATION_PROFILE_IS_PHYSICAL_HARDWARE_EVIDENCE=NO
```

A simulation profile may prove digital arithmetic but cannot select production
hardware, establish a physical unit, or supply calibration evidence.

## Stage 2G dependency correction

Stage 2G depends on the raw transaction and raw protection result, not on the
unconfigured telemetry branch:

```text
STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT
STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION
NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO
NORMALIZED_RANGE_FLAGS_GATES_FAULT_POLICY=NO
NORMALIZED_CONFIGURATION_VALID_GATES_FAULT_POLICY=NO
NORMALIZED_DOMAIN_PROTECTION=FUTURE_VERSIONED_SAFETY_CONTRACT_REQUIRED
```

This removes the prior contradiction in which a telemetry-only path was also
described as a Stage 2G safety gate. Normalized valid, configuration, and range
metadata remain observability signals only.

## Latency, throughput, and register corrections

No exact cycle count is justified before the arithmetic implementation is
selected and timed. The required target is:

```text
PIPELINE_LATENCY=IMPLEMENTATION_DERIVED_FIXED_CONSTANT
PIPELINE_INITIATION_INTERVAL=1
NO_DATA_DEPENDENT_LATENCY=YES
NO_BACKPRESSURE_TO_ATOMIC_CDC=YES
NO_TRANSACTION_DROP=YES
```

The implementation must publish the derived constant in capability metadata,
prove initiation interval one in Icarus and XSim, preserve pair/sequence order,
and later pass an authorized Vivado timing gate. Consumers use output valid and
sequence identity rather than a hard-coded delay.

The conceptual read-only interface is limited to `SCALE_CAPABILITY`,
`SCALE_PROFILE_STATUS`, `LATEST_NORMALIZED_CH1`, `LATEST_NORMALIZED_CH2`,
`LATEST_NORMALIZED_SEQUENCE`, and `LATEST_NORMALIZED_FLAGS`. No new offsets
are frozen by this audit. Software obtains a consistent snapshot by reading
sequence, channels and flags, then sequence again, accepting only matching
sequence reads. No sticky normalization status is retained.

## Reference candidate boundary

`PYNQ_Z2_PMOD_AD1_DUAL_INA240_REFERENCE_V1` is a non-binding Stage 3
engineering comparison baseline. Official device documentation supports its
illustrative interface facts, while public FPGA projects show possible capture
and software integration patterns. None is production authority for this
repository.

```text
REFERENCE_ANALOG_PROFILE_STATUS=REFERENCE_ONLY_NON_AUTHORITATIVE
REFERENCE_PROFILE_PRODUCTION_SELECTED=NO
REFERENCE_PROFILE_PHYSICAL_ACCURACY_CLAIM=NO
REFERENCE_PROFILE_BOARD_CALIBRATION_CLAIM=NO
REFERENCE_PROFILE_DOES_NOT_CONSTRAIN_FINAL_HARDWARE_SELECTION=YES
REFERENCE_PROFILE_STAGE2_DEPENDENCY=NO
PURCHASE_AUTHORIZATION=NO
PRODUCTION_PROFILE_FREEZE=NO
REFERENCE_ANALOG_PROFILE=PYNQ_Z2_PMOD_AD1_DUAL_INA240_REFERENCE_V1
FINAL_HARDWARE_SELECTION_GATE=STAGE3_ARCHITECTURE_AND_HARDWARE_REVIEW
```

The reference chain, illustrative calculation, alternatives, safety limits,
and non-claims are documented in
`docs/architecture/stage3_reference_analog_acquisition_profile.md`. The public
references and their contract gaps are compared in
`docs/architecture/stage3_public_reference_project_comparison.md`.

## Audit conclusion

The hardened target is internally consistent: raw safety behavior stays
independent of telemetry configuration; the first digital implementation is
small enough to justify; latency and throughput are testable without an
invented cycle count; register semantics are conceptual rather than prematurely
allocated; and the physical/reference work cannot close the frozen gap or
authorize hardware. Physical accuracy and board calibration claims are not
made.

## Final Stage 2F-D boundary

The closure boundary separates digital capability from production source
selection. Stage 2 may freeze the digital contract with production still
unconfigured; explicit profiles are limited to non-production validation.

```text
DF-CAPABILITY-001=STAGE2_DIGITAL_ENCODING_CAPABILITY
PS-SELECTION-001=STAGE3_PRODUCTION_SOURCE_SELECTION
STAGE2_DIGITAL_FOUNDATION_REQUIRES_PRODUCTION_ADC_SELECTION=NO
STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE=YES
STAGE2_VALIDATION_PROFILES_MAY_SELECT_EXPLICIT_ENCODINGS=YES
STAGE2_VALIDATION_PROFILE_IS_PRODUCTION_SELECTION=NO
PRODUCTION_SOURCE_SELECTION_OWNER=STAGE3
PRODUCTION_NORMALIZED_TELEMETRY_WHILE_UNCONFIGURED=UNAVAILABLE
SUPPORTED_ENCODING_CAPABILITY_IMPLEMENTED=FUTURE_STAGE2F_D
PRODUCTION_PROFILE=UNCONFIGURED
NON_PRODUCTION_SIMULATION_PROFILES=SUPPORTED
CONTROLLED_DIGITAL_BOARD_VALIDATION_PROFILE=ALLOWED_NON_PRODUCTION
RAW_PROTECTION_PATH_ACTIVE_AND_UNCHANGED=YES
NORMALIZED_VALID_WHEN_UNCONFIGURED=NO
```

`DF-CAPABILITY-001` covers allowed encodings, exact signed code counts, raw
compatibility, and fail-closed behavior. `PS-SELECTION-001` remains open and
blocked on real ADC/AFE/sensor encoding, zero, polarity, and physical transfer
facts. A simulation or controlled digital-board profile is not production
selection and is not physical-accuracy evidence.

## Bidirectional reference limitation

The illustrative +/- reference cannot be labeled compatible with the current
raw protection path:

```text
REFERENCE_BIDIRECTIONAL_NEGATIVE_OVERCURRENT_SUPPORTED_BY_CURRENT_RAW_PATH=NO
REFERENCE_PROFILE_IS_END_TO_END_PROTECTION_COMPATIBLE=NO
REFERENCE_PROFILE_REQUIRES_FUTURE_PROTECTION_DOMAIN_DECISION=YES
```

Positive current raises raw code and may cross the upper threshold. Negative
current lowers raw code and is not symmetrically detected by a current
greater-than raw threshold. Stage 2G/raw RTL remains unchanged. Future choices
are a unidirectional rising-code source, dual upper/lower raw thresholds,
absolute signed-magnitude protection, directional signed thresholds, or an
independent analog comparator/hardware fault output. Stage 4 must validate the
chosen end-to-end protection domain under a versioned safety contract.
