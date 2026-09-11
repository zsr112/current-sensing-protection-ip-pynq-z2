# Stage 2F-D Digital Normalization Implementation

This document describes the implementation that is parallel to the frozen raw
protection path. It does not replace the frozen Stage 2F audit or promote a
hardware source profile.

## Contract Identity

```text
IMPLEMENTATION_ID=STAGE2F_D_DIGITAL_ENCODING_NORMALIZATION
PRODUCTION_PROFILE=UNCONFIGURED
PRODUCTION_NORMALIZED_TELEMETRY=UNAVAILABLE
SUPPORTED_ENCODINGS=UNSIGNED_WITH_ZERO_CODE,TWOS_COMPLEMENT
NORMALIZED_WIDTH=13
NORMALIZED_SIGNEDNESS=SIGNED
NORMALIZED_UNIT=SIGNED_CODE_COUNT
STAGE2F_CONTRACT_GAP_CLOSED=NO
PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
CONFIGURED_CAPABILITY=GENERATED_HEADER_DEFAULT_INSTANCE
DIRECT_PARAMETER_TESTS=SUPPLEMENTAL_ONLY
DATA_WIDTH_COMPATIBILITY_POLICY=RAW_GENERIC_NORMALIZATION_ONLY_AT_12
OBS_SEQUENCE_WIDTH_PROPAGATION=EXACT
DUPLICATE_JSON_KEYS=REJECTED
```

The implementation is `rtl/adc_sample_code_normalizer.sv`. The production top
instantiates it immediately after the atomic destination delivery. Its
inputs are `dst_sample_valid`, `dst_sample_sequence`, `dst_sample_ch1`, and
`dst_sample_ch2`, with `adc_dst_local_rst_n` as the local reset. The normalizer
has no ready input and no connection to the raw protection consumer. All
normalized outputs and profile flags are internal named signals; Stage 2H owns
any public register ABI.

## Numerical Semantics

For `UNSIGNED_WITH_ZERO_CODE`, both raw and nominal zero are explicitly widened
to signed 13-bit intermediates before `raw - zero`. For
`TWOS_COMPLEMENT`, the 12-bit sign bit is extended directly before polarity is
applied. The polarity mapping is per channel:

```text
INCREASING_CODE_IS_POSITIVE -> +decoded
INCREASING_CODE_IS_NEGATIVE -> -decoded
```

The widened intermediate represents the reversed `12'h800` case as `+2048`.
No voltage, current, gain, offset calibration, or physical-unit conversion is
performed.

## Profile Authority

`spec/stage2f_adc_source_profile.schema.json` and the selected JSON profile are
the only profile authority. `tools/generate_stage2f_adc_profile.py` validates
the schema, rejects the reserved `UNCONFIGURED` identity for configured
profiles, and emits the deterministic include
`rtl/generated/stage2f_adc_source_profile.svh` with input and schema SHA-256
provenance. There are no runtime profile writes. The checked-in production
include is generated from
`spec/stage2f_adc_source_profile_unconfigured.json`; configured profiles are
validation-only inputs under `spec/stage2f_profiles/`.

The frozen source-profile schema remains unchanged. The separate implementation
authority binds every named validation profile to
`PRODUCTION_SELECTION=NO`, `PHYSICAL_UNIT_STATUS=NOT_CONFIGURED`,
`PHYSICAL_ACCURACY_CLAIM=NO`, and `BOARD_CALIBRATION_CLAIM=NO`; the static
checker requires the profile file set and identities to match that authority.

When the profile is unconfigured or invalid, the registered normalizer output
is never valid and its sequence and channels are zero. Raw destination delivery, raw
readback, thresholds, comparator behavior, health state, fault policy, reset,
and Stage 2E counters remain active exactly as before.

The packaged top retains its generic raw-path `DATA_WIDTH` contract. A generate
boundary instantiates normalization only when `DATA_WIDTH=12`, explicitly
binding `RAW_WIDTH=DATA_WIDTH`, `SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH`, and
`NORMALIZED_WIDTH=13`. At every other data width, no normalizer is active and
all normalized payload, valid, profile, and width-support signals are tied to
zero. `OBS_SEQUENCE_WIDTH` remains exact at 16, 24, and 32 bits in the supported
branch; there is no implicit normalizer port resizing.

The generator rejects duplicate keys in both schema and profile JSON objects,
including nested polarity objects. Configured capability is established by
generating a per-profile include into an isolated RTL root and instantiating the
real normalizer with its generated defaults. Direct parameter instances remain
useful arithmetic tests, but they are not the configured-profile authority.

## Authority Boundaries

`STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT` and
`STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION` remain unchanged.
Normalized validity, profile flags, and normalized range do not gate fault
policy. The implementation adds no AXI offsets, no physical-unit claim, no
generic divider, and no calibration arithmetic. Production ADC/AFE selection,
transfer-to-current scaling, and board calibration remain Stage 3/external
hardware decisions.
