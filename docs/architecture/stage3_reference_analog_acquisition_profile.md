# Stage 3 reference analog acquisition profile

Date: 2026-08-05
Profile: `PYNQ_Z2_PMOD_AD1_DUAL_INA240_REFERENCE_V1`
Status: engineering comparison only

## Authority boundary

This document makes one analog chain concrete enough for engineering
comparison. It is not a production selection, purchasing decision, physical
accuracy result, board-calibration record, or dependency of Stage 2.

```text
REFERENCE_ANALOG_PROFILE_STATUS=REFERENCE_ONLY_NON_AUTHORITATIVE
REFERENCE_PROFILE_PRODUCTION_SELECTED=NO
REFERENCE_PROFILE_PHYSICAL_ACCURACY_CLAIM=NO
REFERENCE_PROFILE_BOARD_CALIBRATION_CLAIM=NO
REFERENCE_PROFILE_DOES_NOT_CONSTRAIN_FINAL_HARDWARE_SELECTION=YES
REFERENCE_PROFILE_STAGE2_DEPENDENCY=NO
PURCHASE_AUTHORIZATION=NO
PRODUCTION_PROFILE_FREEZE=NO
FINAL_HARDWARE_SELECTION_GATE=STAGE3_ARCHITECTURE_AND_HARDWARE_REVIEW
```

The machine-readable counterpart is
`spec/stage3_reference_analog_profile.json`. Official manuals and datasheets
are authorities only for the named component interfaces and electrical
characteristics. They do not authorize this assembled chain for the project.

## Reference candidate

```text
PROFILE_ID=PYNQ_Z2_PMOD_AD1_DUAL_INA240_REFERENCE_V1
PROFILE_STATUS=REFERENCE_ONLY_NON_AUTHORITATIVE
HOST=PYNQ-Z2
ADC_MODULE=Digilent Pmod AD1
ADC_DEVICE=dual AD7476A
ADC_CHANNELS=2_SIMULTANEOUS
ADC_RESOLUTION_BITS=12
ADC_OUTPUT_CODING=STRAIGHT_NATURAL_BINARY
ADC_INPUT_RANGE=0_TO_VDD
ADC_NOMINAL_THROUGHPUT=UP_TO_1_MSPS_PER_CHANNEL
DIGITAL_INTERFACE=SHARED_CS_SHARED_SCLK_TWO_SERIAL_DATA_OUTPUTS
CURRENT_SENSE_AFE=DUAL_SHUNT_PLUS_INA240
BIDIRECTIONAL_BIAS=NOMINAL_MIDSCALE_REFERENCE
```

The Pmod AD1 contains two AD7476A-class converters clocked under shared chip
select and serial clock, with separate serial data outputs. That organization
is useful for preserving a simultaneous channel pair at the source boundary.
The integration must still define one source transaction, ready/valid behavior,
sequence assignment, reset release, error observation, and the adapter into the
existing Stage 2D atomic CDC. Public example IP does not supply those project
contracts automatically.

## Reference chain

```text
current path
  -> four-terminal low-inductance shunt
  -> application-appropriate input protection/filter
  -> INA240 current-sense amplifier
  -> nominal 1.65-V bidirectional bias
  -> output RC / anti-alias / clamp
  -> Pmod AD1 channel
  -> dual AD7476A serial capture
  -> source ready/valid adapter
  -> existing Stage 2D atomic CDC
       |-- raw protection path
       `-- parallel signed code-count telemetry
```

Two independent shunt/amplifier paths feed the two ADC channels. The serial
capture must emit channel 1, channel 2, and a single sequence identity as one
accepted source transaction. It must not expose free-running per-channel
registers that software or downstream logic can observe from different sample
instants.

The raw protection branch retains unsigned raw thresholds and current health
semantics. The telemetry branch can use the Stage 2F digital profile
`UNSIGNED_WITH_ZERO_CODE` with a nominal midscale zero and explicit channel
polarities only after a real source profile is reviewed. This reference profile
does not activate that production selection.

## Illustrative electrical calculation

The following values are a design-space calculation, not a frozen schematic or
accuracy result:

```text
CURRENT_RANGE_EXAMPLE=PLUS_MINUS_5_A
SHUNT_EXAMPLE=5_MILLIOHM_FOUR_TERMINAL
AMPLIFIER_EXAMPLE=INA240A2_GAIN_50
ADC_SUPPLY_REFERENCE_EXAMPLE=3.3_V_NOMINAL
ZERO_CURRENT_BIAS_EXAMPLE=1.65_V_NOMINAL
OUTPUT_RANGE_AT_PLUS_MINUS_5_A_EXAMPLE=0.4_TO_2.9_V_NOMINAL
NOMINAL_CURRENT_PER_LSB_EXAMPLE=APPROX_3.22_MA
ILLUSTRATIVE_ONLY=YES
CALIBRATED=NO
PRODUCTION_SELECTED=NO
PHYSICAL_ACCURACY_EVIDENCE=NO
```

First-principles nominal calculation:

```text
shunt voltage at 5 A       = 5 A * 0.005 ohm = 0.025 V
amplifier output excursion = 0.025 V * 50     = 1.25 V
biased output endpoints    = 1.65 V +/- 1.25 V = 0.40 V, 2.90 V
ADC volts per LSB          = 3.3 V / 4096       = 0.8057 mV
current per LSB            = 3.3 V / (4096 * 50 * 0.005 ohm)
                           = 0.0032227 A, about 3.22 mA
```

The AD7476A conversion scale is tied to its `VDD`; the Pmod AD1 is not a
precision-external-reference ADC module. Supply variation therefore contributes
directly to code-to-current scale error unless the supply is measured or the
complete chain is calibrated. The nominal calculation also omits shunt
tolerance and self-heating, amplifier gain/offset/drift, bias error, RC loading,
ADC offset/gain/linearity/noise, layout, common-mode transients, and channel
matching. It cannot support a physical accuracy claim.

## Analog design questions left open

Before this chain could become a hardware candidate, Stage 3 review would need
to establish:

- maximum bus voltage, current, transient energy, and acceptable shunt loss;
- shunt power rating, pulse rating, Kelvin routing, inductance, and thermal
  environment;
- INA240 variant, supply rails, common-mode envelope, input protection, output
  swing/headroom, bias source impedance, and stability;
- anti-alias bandwidth relative to sampling and protection response needs;
- clamp behavior and whether it can inject unsafe current into the Pmod input;
- PYNQ-Z2/Pmod voltage, ground, connector, and timing compatibility;
- AD7476A acquisition settling, SCLK timing, VDD quality, and throughput margin;
- isolation requirements and safe laboratory connection practices;
- tolerance, temperature, repeatability, and calibration error budgets; and
- board identity, calibration record format, and traceable acceptance method.

```text
LOW_VOLTAGE_CURRENT_LIMITED_LAB_REFERENCE_ONLY=YES
SEPARATE_ELECTRICAL_SAFETY_REVIEW_REQUIRED=YES
```

No mains, high-energy battery, high-side common-mode, or isolated measurement
use is authorized by this reference.

## Future hardware path comparison

No option is selected here. Values are qualitative until requirements and
specific parts are approved.

| Criterion | A. Pmod AD1 + dual INA240/shunts | B. Pmod AD1 + integrated Hall modules | C. Custom simultaneous ADC + precision reference | D. Software-only physical conversion from raw samples |
|---|---|---|---|---|
| Range | Set by shunt, gain, bias, and headroom; illustrative +/-5 A only | Module-specific, often wider but fixed by sensor | Customizable through AFE and ADC selection | Inherits whichever acquisition hardware exists |
| Resolution | 12-bit ADC; effective resolution reduced by noise and unused headroom | 12-bit ADC plus Hall output noise/offset limitations | Potentially higher nominal and effective resolution | Cannot recover resolution absent in raw data |
| Bandwidth | INA240/filter/AD7476A chain can be comparatively fast | Hall module bandwidth varies and may be lower | Can be designed to requirement | No change to acquisition bandwidth; adds non-real-time processing latency |
| Latency | Serial conversion/capture plus existing CDC | Similar ADC path plus sensor delay | Architecture-specific; can optimize deterministic capture | Software scheduling latency; unsuitable as fault-path authority |
| Channel simultaneity | Two AD7476A channels share timing and expose separate data outputs | Depends on two module paths feeding the dual ADC | Can select true simultaneous-sampling ADC | Preserves only the simultaneity present in raw acquisition |
| Isolation | None inherent | Some Hall modules offer magnetic isolation; module ratings must be verified | Can add isolation deliberately | None added |
| Insertion loss | Shunt `I^2R` loss and heating | Often low conductor resistance | Depends on shunt or sensor choice | None beyond existing hardware |
| Common-mode tolerance | INA240 supports enhanced PWM rejection but exact limits remain application-specific | Module-specific and potentially isolated | Can select AFE/isolation to requirement | Inherits hardware limitation |
| Reference stability | AD7476A scale follows VDD | Same Pmod VDD dependency | Precision external reference can improve stability | Can compensate only if reference/supply data is available |
| Temperature drift | Shunt + amplifier + bias + ADC chain | Hall offset/sensitivity drift can dominate | Can select low-drift parts and add temperature sensing | Can correct characterized drift but cannot invent characterization |
| Calibration burden | Per-board zero/gain and channel matching likely | Module zero/sensitivity and installation calibration likely | Still requires validation; may reduce nominal uncertainty | Highest software provenance burden; same physical calibration evidence required |
| PYNQ-Z2 integration | Moderate; existing public examples are useful references | Moderate analog wiring plus same ADC capture | Highest FPGA/PCB/driver effort | Low incremental FPGA effort after raw telemetry exists |
| Cost | Low-to-moderate prototype BOM | Module-dependent, often moderate | Highest non-recurring and PCB cost | Lowest incremental hardware cost |
| Availability | Pmod and INA240 availability must be checked at selection time | Varies substantially by module quality/vendor | Depends on selected ADC/reference and custom board lead time | No new hardware, but still depends on existing acquisition source |
| Safety | Shunt connection needs explicit low-energy limits and review | Isolation claims require certified module review | Can be engineered for safety but requires full hardware review | Does not change electrical safety |

Path D is not an analog acquisition substitute. It is included because future
physical conversion can remain software-only while raw FPGA protection stays
unchanged. It still needs an authoritative ADC/AFE/sensor profile and
calibration evidence to claim amperes.

## Integration requirements retained from Stage 2B through Stage 2E

Any future source adapter must preserve:

```text
SOURCE_TRANSACTION=CHANNEL_1_CHANNEL_2_AND_SEQUENCE_ATOMIC
READY_VALID_CONTRACT=PRESERVED
INDEPENDENT_SOURCE_CLOCK=SUPPORTED
RESET_RELEASE_CONTRACT=PRESERVED
CDC=EXISTING_STAGE2D_ATOMIC_FIFO
SEQUENCE_IDENTITY=PRESERVED
ERROR_OBSERVABILITY=EXISTING_STAGE2E_CONTRACT_PRESERVED
DMA_MANDATORY_FOR_PROTECTION_PATH=NO
PYTHON_IN_REALTIME_FAULT_PATH=NO
```

DMA may be an optional telemetry transport after the real-time branches, but it
cannot replace the atomic CDC or become a prerequisite for fault evaluation.

## Official component references

- Digilent, Pmod AD1 reference manual:
  <https://digilent.com/reference/pmod/pmodad1/reference-manual>
- Analog Devices, AD7476A/AD7477A/AD7478A datasheet:
  <https://www.analog.com/media/en/technical-documentation/data-sheets/AD7476A_7477A_7478A.pdf>
- Texas Instruments, INA240 datasheet:
  <https://www.ti.com/lit/ds/symlink/ina240.pdf>

These sources establish component-level facts only. Selection, schematic,
layout, safety, calibration, purchasing, and production authority remain open
until `STAGE3_ARCHITECTURE_AND_HARDWARE_REVIEW`.

## Bidirectional protection boundary

```text
REFERENCE_BIDIRECTIONAL_NEGATIVE_OVERCURRENT_SUPPORTED_BY_CURRENT_RAW_PATH=NO
REFERENCE_PROFILE_IS_END_TO_END_PROTECTION_COMPATIBLE=NO
REFERENCE_PROFILE_REQUIRES_FUTURE_PROTECTION_DOMAIN_DECISION=YES
```

The nominal midscale reference is bidirectional, but the current raw path is
an unsigned current-greater-than upper-threshold policy. Positive current
raises raw code and may cross the upper threshold; negative current lowers raw
code and is not symmetrically detected. Stage 2G/raw RTL remains unchanged.
Future Stage 3 alternatives are a unidirectional rising-code source, dual
upper/lower raw thresholds, absolute signed-magnitude protection, directional
signed thresholds, or an independent analog comparator/hardware fault output.
The selected choice requires a future versioned safety contract. Stage 4 must
validate both current directions, threshold authority, reset/fault behavior,
analog isolation, calibrated physical transfer, and board-bound acceptance.

```text
FUTURE_STAGE4_END_TO_END_VALIDATION_REQUIREMENTS=POSITIVE_AND_NEGATIVE_OVERCURRENT_RAW_OR_VERSIONED_PROTECTION_PHYSICAL_TRANSFER_CALIBRATION_AND_FAULT_ISOLATION
```

The Analog Devices taxonomy is split into an official FPGA reference page, an
XPS/IP-core artifact slot, and a Linux/device-tree software integration pin.
The Linux/device-tree reference is software integration only and is not a
complete FPGA implementation source:

```text
LINUX_DEVICE_TREE_IS_NOT_COMPLETE_FPGA_IMPLEMENTATION=YES
ADI_REFERENCE_PIN_CLASSIFICATION=PASS
```
