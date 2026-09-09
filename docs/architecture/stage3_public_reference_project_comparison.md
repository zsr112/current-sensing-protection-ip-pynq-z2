# Stage 3 public reference project comparison

Date: 2026-08-05
Scope: interface and integration research; no production adoption

## Classification policy

Public repositories are evidence about possible implementation patterns, not
automatic authority for this project's source, safety, or physical measurement
contract. The allowed classifications are:

| Classification | Meaning |
|---|---|
| `OFFICIAL_INTERFACE_AUTHORITY` | Vendor manual or component datasheet authoritative for the named interface/electrical fact |
| `OFFICIAL_IMPLEMENTATION_REFERENCE` | Vendor-maintained example useful for implementation study but not this project's production contract |
| `OFFICIAL_SOFTWARE_INTEGRATION_REFERENCE` | Vendor-maintained software/device-tree integration reference; not a complete FPGA implementation |
| `COMMUNITY_INTEGRATION_REFERENCE` | Community integration example useful for software/FPGA pattern comparison |
| `COMMUNITY_EXPERIMENT_ONLY` | Community experiment with limited reusable contract evidence |

Only the Digilent reference manual, AD7476A datasheet, and INA240 datasheet are
classified as `OFFICIAL_INTERFACE_AUTHORITY`, and only for their named
products. None of the listed public references is production hardware
authority for this repository.

## Project classifications

| Project | Pinned reference | Classification | Relevant pattern | Authority limit |
|---|---|---|---|---|
| Digilent `vivado-library` PmodAD1 | <https://github.com/Digilent/vivado-library/tree/master/ip/Pmods/PmodAD1_v1_0> | `OFFICIAL_IMPLEMENTATION_REFERENCE` | Vendor IP captures two serial data lanes under shared CS/SCLK and exposes the latest pair through AXI-oriented integration | Example IP structure does not define this project's atomic ready/valid, independent-clock CDC, sequence, error, reset, or fault contracts |
| Analog Devices AD7476A Pmod FPGA reference page | <https://wiki.analog.com/resources/fpga/xilinx/pmod/ad7476a> | `OFFICIAL_IMPLEMENTATION_REFERENCE` | Official FPGA reference-design page for implementation research | Page reference is not a production source pin and does not establish this project's atomic pair transaction, CDC, or fault policy |
| Analog Devices AD7476A Pmod XPS/IP-core artifact slot | <https://github.com/analogdevicesinc/hdl/tree/ccd4e2868e0b959998f36af60eba11db89e58f65> | `OFFICIAL_IMPLEMENTATION_REFERENCE` | Pinned HDL repository checked for a stable AD7476A Pmod artifact | No stable AD7476A Pmod artifact was located at the pinned state; this slot is non-authoritative |
| Analog Devices AD7476A Pmod Linux/device-tree integration | <https://github.com/analogdevicesinc/linux/commit/2c5b84b20a6a8a1c1b29248a5790d4bc6475a2d2> | `OFFICIAL_SOFTWARE_INTEGRATION_REFERENCE` | Linux/device-tree and software binding context only | Linux device-tree is not a complete FPGA implementation source and does not supply this project's atomic pair transaction, CDC, or fault policy |
| `amilashanaka/PYNQ_PMOD_AD1` | <https://github.com/amilashanaka/PYNQ_PMOD_AD1/tree/5951b0f41f1d73cf94f594feca6601173aa0b580> | `COMMUNITY_INTEGRATION_REFERENCE` | Python/MMIO polling around Digilent PmodAD1 IP | Polling software is not a real-time path and the repository is not hardware authority |
| `riccardonicolaidis/Sampler_Pmod_AD1` | <https://github.com/riccardonicolaidis/Sampler_Pmod_AD1/tree/98a47be9b8448bcc1b5a40da25e2c09b2582d0b9> | `COMMUNITY_EXPERIMENT_ONLY` | Dual-MISO HDL sampling and UART-oriented experiment | Experimental integration does not establish production transaction, CDC, safety, or measurement authority |
| `amilashanaka/PMOD_AD1_DMA` | <https://github.com/amilashanaka/PMOD_AD1_DMA/tree/761cee9ee9f5a13af50e26a615989569e43878ec> | `COMMUNITY_INTEGRATION_REFERENCE` | Digilent streaming output connected to AXI DMA | DMA is an optional telemetry pattern and must not become mandatory for protection |

The Analog Devices `util_pmod_adc` design at commit `233cc111...` is not used
as the requested AD7476A/Pmod AD1 reference: it targets AD7091R-based CFTL
Pmods. Treating it as a Digilent Pmod AD1 implementation would be a device
identity error.

```text
ADI_AD7476A_PMOD_FPGA_REFERENCE_PAGE=OFFICIAL_IMPLEMENTATION_REFERENCE
ADI_AD7476A_PMOD_XPS_OR_IPCORE_ARTIFACT=NO_STABLE_ARTIFACT_PIN_LOCATED
ADI_AD7476A_PMOD_LINUX_DEVICE_TREE=OFFICIAL_SOFTWARE_INTEGRATION_REFERENCE
```

The reference profile has a deliberate protection-domain limitation:

```text
REFERENCE_BIDIRECTIONAL_NEGATIVE_OVERCURRENT_SUPPORTED_BY_CURRENT_RAW_PATH=NO
REFERENCE_PROFILE_IS_END_TO_END_PROTECTION_COMPATIBLE=NO
REFERENCE_PROFILE_REQUIRES_FUTURE_PROTECTION_DOMAIN_DECISION=YES
LINUX_DEVICE_TREE_IS_NOT_COMPLETE_FPGA_IMPLEMENTATION=YES
FUTURE_STAGE4_END_TO_END_VALIDATION_REQUIREMENTS=POSITIVE_AND_NEGATIVE_OVERCURRENT_RAW_OR_VERSIONED_PROTECTION_PHYSICAL_TRANSFER_CALIBRATION_AND_FAULT_ISOLATION
```

Positive current raises raw code and may cross an upper threshold. Negative
current lowers raw code and is not symmetrically detected by current
greater-than raw thresholds. Stage 2G/raw RTL is unchanged. Future alternatives
are a unidirectional rising-code source, dual upper/lower raw thresholds,
absolute signed-magnitude protection, directional signed thresholds, or an
independent analog comparator/hardware fault output. Stage 4 must validate the
selected alternative end to end under a versioned safety contract.

## Contract comparison

`Documented` means the reference provides a relevant mechanism in its own
context. `Not supplied` means this project must retain or add its own contract;
it is not necessarily a defect in the reference project.

| Contract | Current project | Digilent PmodAD1 | ADI AD7476A Pmod | PYNQ_PMOD_AD1 | Sampler_Pmod_AD1 | PMOD_AD1_DMA |
|---|---|---|---|---|---|---|
| Sample atomicity | `{sequence,ch1,ch2}` is one Stage 2D FIFO word | Latest two-channel pair is packed for readout; no project sequence contract | SPI/IIO sample organization; no current-project atomic contract | Inherits polled Digilent pair | Dual-lane experiment; no accepted-transaction proof | Stream/DMA framing; no current-project atomic sequence authority |
| Source transaction definition | Rising-edge `valid && ready`, both channels stable | IP-specific acquisition/readout | SPI conversion/IIO buffer semantics | Python/MMIO poll | Local sampler/UART semantics | Stream transfer and DMA semantics |
| Ready/valid | Explicit producer contract | Not the current project's source ready/valid contract | SPI/IIO interfaces differ | No real-time source handshake in Python | No compatible contract demonstrated | AXI-Stream handshake exists after capture, not necessarily at ADC source boundary |
| Backpressure | Producer holds complete pair stable; observed and counted | Example-specific | SPI/IIO buffering-specific | Poll rate dependent | Experiment-specific | AXI-Stream/DMA can backpressure downstream; cannot backpressure or gate fault path |
| Independent source clock | Supported by Stage 2D | Not a replacement for Stage 2D CDC | Reference-specific clocks | Usually tied to block design/software context | Local clocks only | Stream clocking/DMA context differs |
| Reset release | Asynchronous assertion and controlled per-domain release | IP-specific | Framework-specific | Inherits design, not current contract | Experiment-specific | DMA and stream reset do not replace current reset contract |
| CDC | Atomic async FIFO with Gray-pointer constraints | No authority to replace it | No authority to replace it | No authority to replace it | No authority to replace it | DMA is not the source-to-protection CDC |
| Sequence identity | 32-bit sequence travels with both raw channels | No equivalent current-project sequence | IIO metadata is not the Stage 2D identity | Polled values lack this identity contract | UART framing is not equivalent | DMA buffer position is not the accepted-source sequence contract |
| Error observability | Stage 2E source violation, drop, FIFO, duplicate, gap, reorder/stale counters | Example status only | Framework diagnostics differ | Software exceptions/polling only | Experiment diagnostics only | DMA status is supplemental, not Stage 2E equivalence |
| Production source authority | Safe-inert placeholder; profile `UNCONFIGURED` | None for this repository | None for this repository | None | None | None |
| Software readout | Existing raw MMIO; future coherent sequence retry | AXI-readable latest data | IIO-oriented | Python polling | UART host path | DMA buffer consumption |
| DMA dependence | Not required; fault path is direct raw RTL | Not required by the base comparison | Framework-dependent, not current fault path | No | No | Central to telemetry example, but optional here |

## Reuse disposition

The following ideas may be reused after independent review:

- shared CS/SCLK with two serial data lanes for simultaneous pairing;
- vendor timing/state-machine patterns for AD7476A capture;
- AXI-readable or streaming telemetry after the source transaction is safely
  formed;
- Python convenience access for non-real-time observation; and
- optional DMA for bulk telemetry after the protection branch.

The following current contracts are not replaced:

```text
ATOMIC_STAGE2D_CDC_REPLACED=NO
FREE_RUNNING_SAMPLE_REGISTERS_REPLACE_ATOMIC_TRANSACTION=NO
DMA_MANDATORY_FOR_PROTECTION_PATH=NO
PYTHON_IN_REALTIME_FAULT_PATH=NO
COMMUNITY_REPOSITORY_IS_HARDWARE_AUTHORITY=NO
PRODUCTION_SOURCE_PROFILE=UNCONFIGURED
```

## Source-authority boundary

Official interface sources:

- Digilent Pmod AD1 reference manual:
  <https://digilent.com/reference/pmod/pmodad1/reference-manual>
- Analog Devices AD7476A/AD7477A/AD7478A datasheet:
  <https://www.analog.com/media/en/technical-documentation/data-sheets/AD7476A_7477A_7478A.pdf>
- Texas Instruments INA240 datasheet:
  <https://www.ti.com/lit/ds/symlink/ina240.pdf>

These establish the Pmod/device interface facts used in the reference profile.
They do not establish the project wiring, source profile, analog range, safety,
calibration, physical accuracy, or production selection.

```text
PUBLIC_REFERENCE_PROJECT_COMPARISON=PASS
REFERENCE_PROFILE_PRODUCTION_SELECTED=NO
REFERENCE_PROFILE_DOES_NOT_CONSTRAIN_FINAL_HARDWARE_SELECTION=YES
PURCHASE_AUTHORIZATION=NO
```
