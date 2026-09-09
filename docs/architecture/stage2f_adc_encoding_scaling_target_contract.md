# Stage 2F ADC encoding and scaling target contract

Date: 2026-08-05
Status: hardened architecture target; no functional implementation
Architecture: `RAW_CODE_PROTECTION_WITH_PARALLEL_SIGNED_NORMALIZED_TELEMETRY`

## Closure and non-claims

This contract defines the smallest justified digital foundation for interpreting
an explicitly selected ADC encoding. It does not select an ADC, AFE, current
sensor, physical unit, transfer function, or calibration method. It changes no
RTL, AXI register RTL, runtime software, or production Tcl.

```text
FROZEN_GAP=ADC_ENCODING_AND_PHYSICAL_SCALING
DIGITAL_FOUNDATION_SCOPE=EXPLICIT_ENCODING_AND_SIGNED_CODE_NORMALIZATION
DIGITAL_FOUNDATION_CLOSES_FROZEN_GAP=NO
PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS
PHYSICAL_CLOSURE_PREREQUISITE=APPROVED_ADC_AFE_SENSOR_PROFILE_OR_OWNER_APPROVED_SCOPE_CHANGE
PHYSICAL_ACCURACY_CLAIM=NOT_MADE
BOARD_CALIBRATION_CLAIM=NOT_MADE
STAGE2F_IMPLEMENTATION_STARTED=NO
STAGE2F_CONTRACT_GAP_CLOSED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```

Digital implementation evidence may eventually close digital subclaims in
`spec/stage2f_closure_boundary.json`. It cannot close the frozen combined gap
while physical scaling and calibration authority remain absent.

## Selected architecture and Stage 2G authority

The future compatibility architecture forks one accepted raw transaction only
after the existing atomic CDC destination delivery:

```text
atomic raw CDC destination delivery {sequence, raw_ch1, raw_ch2}
  |-- unchanged raw protection evaluation and raw readback
  `-- selected encoding -> nominal zero removal -> polarity
      -> parallel signed code-count telemetry
```

The fork does not add a ready signal, move a comparator, reinterpret a
threshold, or alter the FIFO payload. Sequence and both channels remain one
transaction.

```text
RAW_PATH_UNCHANGED=YES
PROTECTION_THRESHOLD_DOMAIN=UNSIGNED_RAW_CODE_COMPATIBILITY
STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT
STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION
NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO
NORMALIZED_RANGE_FLAGS_GATES_FAULT_POLICY=NO
NORMALIZED_CONFIGURATION_VALID_GATES_FAULT_POLICY=NO
NORMALIZED_DOMAIN_PROTECTION=FUTURE_VERSIONED_SAFETY_CONTRACT_REQUIRED
```

Stage 2G therefore remains functional when the production normalized telemetry
profile is unconfigured. Any future use of normalized codes or physical units
in protection requires a new versioned safety contract, threshold authority,
reset policy, failure policy, and independent review.

## Source profile and production boundary

The source-profile schema is
`spec/stage2f_adc_source_profile.schema.json`. The only digital encoding modes
are:

```text
UNSIGNED_WITH_ZERO_CODE
TWOS_COMPLEMENT
```

Offset binary is represented as `UNSIGNED_WITH_ZERO_CODE` with a midscale
`zero_code`; it is not a redundant third decoder mode. A configured digital
profile supplies one encoding, a consistent nominal zero code, an explicit
polarity for each channel, and a profile identity. It supplies no physical
unit or board-calibration claim.

`UNCONFIGURED` is reserved and cannot be the identity of a
`CONFIGURED_DIGITAL` profile. `production_selection=true` requires a
non-reserved identity, configured encoding, valid zero-code rule, and both
configured polarities.

The tracked production instance is
`spec/stage2f_adc_source_profile_unconfigured.json` and remains:

```text
CURRENT_PRODUCTION_PROFILE=UNCONFIGURED
CURRENT_PRODUCTION_NORMALIZED_TELEMETRY=UNAVAILABLE_UNCONFIGURED
RAW_PROTECTION_ACTIVE_BEHAVIOR=UNCHANGED
SIMULATION_PROFILES_MAY_SELECT_EXPLICIT_DIGITAL_ENCODINGS=YES
SIMULATION_PROFILE_IS_PHYSICAL_HARDWARE_EVIDENCE=NO
```

For this instance, `encoding=UNKNOWN`, `zero_code=null`, both channel
polarities are `UNKNOWN`, `physical_unit_status=UNKNOWN`, and
`production_selection=false`. No normalized transaction is advertised. Raw
transactions, if any are supplied by a later approved source integration,
continue through the unchanged raw protection path independently of telemetry
configuration.

## Encoding taxonomy and initial transform

For a 12-bit raw code `r` and configured channel polarity `p` in `{+1,-1}`,
evaluate with widened signed integer arithmetic:

```text
decode(r, UNSIGNED_WITH_ZERO_CODE, z) = unsigned(r) - z
decode(r, TWOS_COMPLEMENT, 0)         = sign_extend_12(r)
normalized_code                      = p * decode(r, encoding, zero_code)
```

For `UNSIGNED_WITH_ZERO_CODE`, `z` must be an integer in `0..4095`. For
`TWOS_COMPLEMENT`, `zero_code` must be `0`. The transform order is normative:

```text
INITIAL_DIGITAL_TRANSFORM=ENCODING_THEN_NOMINAL_ZERO_REMOVAL_THEN_POLARITY
NORMALIZED_UNIT=SIGNED_CODE_COUNT
NORMALIZED_WIDTH=13
PHYSICAL_UNIT=NOT_CONFIGURED
```

All legal 12-bit inputs fit exactly in a signed 13-bit result after polarity.
The initial transform therefore needs no divider, rounding rule, calibration
coefficient, or complex saturation policy. A future implementation must still
use explicitly widened intermediate values so that negation cannot wrap.

## Arithmetic scope

The initial Stage 2F implementation includes only encoding interpretation,
nominal zero-code removal, and channel polarity. These exclusions are
normative:

```text
ARBITRARY_RUNTIME_OFFSET=NO
ARBITRARY_RUNTIME_RATIONAL_GAIN=NO
GENERIC_SIGNED_DIVIDER=NO
GENERIC_RATIONAL_DIVIDER=NO
BOARD_CALIBRATION_ARITHMETIC=DEFERRED
CALIBRATION_ARITHMETIC=DEFERRED
DYNAMIC_CALIBRATION_FRAMEWORK=NO
MULTIPLE_CALIBRATION_IDENTITIES=NO
SOURCE_SPECIFIC_GENERATED_CONSTANT_TRANSFORM=DEFERRED_UNTIL_APPROVED_PHYSICAL_PROFILE
```

Nominal zero removal is an encoding property, not a measured board offset.
Polarity is a source wiring/meaning property, not a calibration coefficient.
If a later approved physical profile requires FPGA conversion, its bounded
source-specific constant transform must be selected and reviewed before widths,
rounding, saturation, latency, and accuracy claims are frozen. A generic
runtime divider is not the default.

## Latency and throughput

The audit does not invent a cycle count before the implementation architecture
is selected. The future implementation contract is:

```text
PIPELINE_LATENCY=IMPLEMENTATION_DERIVED_FIXED_CONSTANT
PIPELINE_INITIATION_INTERVAL=1
NO_DATA_DEPENDENT_LATENCY=YES
NO_BACKPRESSURE_TO_ATOMIC_CDC=YES
NO_TRANSACTION_DROP=YES
```

Implementation must first choose and pipeline the actual decode/zero/polarity
logic. It then publishes the fixed latency in `SCALE_CAPABILITY` metadata and
proves it in both Icarus and XSim. Consumers correlate `valid` and sequence;
they do not hard-code an audit-time delay. A sequence scoreboard must prove
one output for every eligible input, in order, with channel pairing intact and
initiation interval one under back-to-back accepted destination deliverys. An authorized
Vivado timing gate is required later, after RTL exists.

## Transaction, invalid-profile, and reset semantics

The conceptual normalizer input is the existing ACLK-domain destination-delivery pulse,
sequence, and two raw channels. The conceptual output is one validity pulse,
the same sequence, two signed 13-bit code counts, and transaction flags.

When a supported profile is configured, every destination delivery produces exactly one
normalized transaction after the published fixed latency. When the profile is
unconfigured or invalid, normalized telemetry is unavailable; no numeric zero
is presented as a valid normalized result. Raw protection still evaluates the
same accepted raw sample.

Reset assertion and synchronized ACLK release follow the existing boundary.
Reset flushes all future normalizer pipeline state, produces no phantom valid,
and never replays a pre-reset sequence. The first eligible post-reset raw
transaction is handled exactly once. No data-dependent retry or stall is
permitted.

`LATEST_NORMALIZED_FLAGS` may contain only same-transaction, non-sticky status
whose exact fields are frozen during implementation. Under the initial exact
13-bit transform, arithmetic overflow/range flags are not needed to protect
the result. Any future range meaning must distinguish digital arithmetic range
from ADC electrical range and must never gate the compatibility fault policy.

## Register and software semantics

This audit freezes no new address or bit field. Every published register from
`0x00` through `0x60` retains its current offset and behavior. In particular,
`I_CH1` and `I_CH2` remain zero-extended 12-bit raw codes; `TH_OC1` and
`TH_OC2` remain unsigned raw-code thresholds; `TH_DIFF` remains an unsigned
raw-code-difference threshold; and wide writes retain the frozen silent
low-12-bit truncation behavior.

The later interface is limited to these conceptual read-only outputs:

| Conceptual output | Required meaning |
|---|---|
| `SCALE_CAPABILITY` | Contract version, raw and normalized widths, supported encoding taxonomy, and implementation-derived fixed latency |
| `SCALE_PROFILE_STATUS` | Selected profile identity/state and configuration availability; non-sticky |
| `LATEST_NORMALIZED_CH1` | Sign-extended signed code count for channel 1 |
| `LATEST_NORMALIZED_CH2` | Sign-extended signed code count for channel 2 |
| `LATEST_NORMALIZED_SEQUENCE` | Atomic source sequence paired with both values and flags |
| `LATEST_NORMALIZED_FLAGS` | Same-transaction non-sticky flags with implementation-frozen meaning |

```text
CONCEPTUAL_REGISTER_ACCESS=READ_ONLY
NEW_REGISTER_OFFSETS_FINALIZED=NO
STICKY_NORMALIZATION_STATUS=NO
EXISTING_OFFSETS_THROUGH_0X60=UNCHANGED
REGISTER_FIELD_AND_OFFSET_FREEZE_OWNER=STAGE2H_SINGLE_SOURCE_REGISTER_GENERATION
```

Software obtains a coherent snapshot with this retry protocol:

```text
read LATEST_NORMALIZED_SEQUENCE
read LATEST_NORMALIZED_CH1, LATEST_NORMALIZED_CH2, LATEST_NORMALIZED_FLAGS
read LATEST_NORMALIZED_SEQUENCE again
accept only when both sequence reads match; otherwise retry
```

Python and C may expose explicit signed-code names and a sequence-consistent
read helper after implementation. They must retain existing raw APIs and must
not name normalized values as amperes or imply calibration. Threshold setters
remain in the raw domain.

## Stage 2G dependency contract

Stage 2G consumes the accepted destination delivery event and the unchanged raw protection
evaluation. It does not wait for, enable from, suppress from, or reinterpret
normalized telemetry.

```text
STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT
STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION
NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO
NORMALIZED_RANGE_FLAGS_GATES_FAULT_POLICY=NO
NORMALIZED_CONFIGURATION_VALID_GATES_FAULT_POLICY=NO
NORMALIZED_DOMAIN_PROTECTION=FUTURE_VERSIONED_SAFETY_CONTRACT_REQUIRED
```

The Stage 2G `RESET_WAIT` first-fault policy remains a separate frozen contract
gap. Signed telemetry is optional observability and cannot resolve that policy.

## Stage 2H deferrals

Stage 2F owns the behavioral meaning of future normalized code-count telemetry,
its implementation-derived latency metadata, and its coherent-read contract.
Stage 2H owns the single-source generation and final allocation of register
offsets, fields, RTL constants, C definitions, Python definitions, and
documentation. No address above `0x60` is allocated by this audit.

General runtime calibration, physical-unit register banks, IP-XACT generation,
broad renaming, and unrelated observability refactoring remain out of scope.

## Future Stage 2F-D boundary

```text
SUPPORTED_ENCODING_CAPABILITY_IMPLEMENTED=FUTURE_STAGE2F_D
PRODUCTION_PROFILE=UNCONFIGURED
NON_PRODUCTION_SIMULATION_PROFILES=SUPPORTED
CONTROLLED_DIGITAL_BOARD_VALIDATION_PROFILE=ALLOWED_NON_PRODUCTION
RAW_PROTECTION_PATH_ACTIVE_AND_UNCHANGED=YES
NORMALIZED_VALID_WHEN_UNCONFIGURED=NO
STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE=YES
```

Selecting a validation encoding exercises digital capability only. It never
selects production hardware, establishes physical accuracy, or authorizes a
physical unit.
