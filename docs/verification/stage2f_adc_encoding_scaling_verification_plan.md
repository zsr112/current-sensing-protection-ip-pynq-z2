# Stage 2F ADC encoding and scaling verification plan

Date: 2026-08-05
Status: hardened pre-implementation plan
Target: `RAW_CODE_PROTECTION_WITH_PARALLEL_SIGNED_NORMALIZED_TELEMETRY`

## Current audit acceptance

This audit contains no functional RTL. Current acceptance is static and proves
that the documents, inventories, source profile, closure boundary, and Stage 3
reference material agree. It does not run synthesis, implementation, bitstream,
Hardware Manager, board action, or a new functional simulation.

```text
STAGE2F_IMPLEMENTATION_STARTED=NO
STAGE2F_CONTRACT_GAP_CLOSED=NO
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
```

The tracked state passes `tools/stage2f_adc_contract_audit.py`. Each negative
fixture in `tools/tests/test_stage2f_adc_contract_audit.py` changes one
authority at a time and must fail closed.

## Cross-artifact negative fixtures

At minimum, isolated mutations must reject all of these contradictions:

1. physical gap claimed closed while physical unit remains unsupported;
2. digital foundation incorrectly reduces the remaining gap count;
3. telemetry-only normalization paired with Stage 2G normalized gating;
4. numeric latency conflicting with implementation-derived authority;
5. missing initiation interval under the no-ready input contract;
6. unbounded runtime offset paired with a fixed intermediate-width claim;
7. read-only status paired with sticky behavior and no complete clear semantics;
8. production `UNCONFIGURED` profile claimed as normalized functional;
9. reference profile promoted to production authority;
10. illustrative reference arithmetic labeled calibrated;
11. Pmod AD1 claimed to use a precision external ADC reference;
12. DMA made mandatory for the protection path;
13. a community repository classified as hardware authority;
14. the reference profile constraining final hardware selection; and
15. purchase authorization incorrectly implied.

Legacy integrity mutations also reject conflicting raw widths, conflicting
signedness, unsupported physical units, missing threshold authority, hardware
unknowns promoted to repository facts, duplicate parameter authority, and
incorrect Stage 2F implementation or closure claims.

## Machine-readable validation

All JSON files must parse with duplicate-key rejection. The source-profile
schema must retain its small required field set, closed object shape, encoding
taxonomy, and unconfigured constraints. The tracked instance must validate
without relying on an optional third-party `jsonschema` installation.

Cross-artifact checks require:

- frozen fact values and `REMAINING_CONTRACT_GAPS=2` in every authority;
- `ADC_ENCODING_AND_PHYSICAL_SCALING` preserved as the frozen gap;
- physical scale unsupported while hardware facts remain unknown;
- identical Stage 2G event and fault authorities in data-path, parameter, and
  document contracts;
- implementation-derived fixed latency, initiation interval one, no
  data-dependent latency, no CDC backpressure, and no drop;
- no runtime offset, rational gain, generic divider, or board-calibration
  arithmetic in the initial foundation;
- no new finalized offsets above `0x60` and no sticky normalization status;
- production normalized telemetry unavailable for the unconfigured profile;
- every Stage 3 reference non-claim and public-project classification intact.

## Future digital implementation claims

A later Stage 2F RTL change may prove only these digital claims:

1. selected encoding, nominal zero removal, and polarity produce the exact
   signed 13-bit code count;
2. one atomic sequence and both channels remain aligned through the transform;
3. the pipeline has one published fixed, data-independent latency and II=1;
4. no transaction is duplicated, reordered, detached, or dropped;
5. reset flushes pending telemetry without replay or phantom valid;
6. an unconfigured/invalid profile never presents a numeric value as valid;
7. raw protection, threshold semantics, raw readback, CDC ready behavior, and
   registers `0x00..0x60` remain unchanged;
8. conceptual read-only telemetry exposes signed code counts without physical
   or calibration claims.

It cannot establish ADC electrical behavior, AFE transfer, current range,
reference stability, sensor accuracy, board calibration, analog safety, or
physical accuracy.

## Independent reference model

The future testbench model uses mathematical integers and no RTL helper. Its
input transaction is:

```text
sequence, raw_ch1, raw_ch2,
profile_state, encoding, zero_code,
channel_1_polarity, channel_2_polarity
```

For each channel:

```text
UNSIGNED_WITH_ZERO_CODE: decoded = unsigned(raw) - zero_code
TWOS_COMPLEMENT:         decoded = sign_extend_12(raw), zero_code must be 0
normalized = polarity * decoded
```

The model output is `normalized_valid`, the same sequence, two signed 13-bit
counts, and exact same-transaction flags. It contains no offset calibration,
rational gain, division, rounding, saturation, or physical-unit conversion.

The scoreboard enqueues only on the accepted atomic CDC destination delivery. Once RTL chooses
an architecture, the expected due cycle is calculated from the published
capability latency. Consumers and functional logic use valid/sequence rather
than a hard-coded audit-time cycle count.

## Directed digital matrix

Run each applicable case on both channels and repeat asymmetric cases with
channels swapped:

| Area | Required cases |
|---|---|
| Unsigned zero | `zero_code` at 0, midscale, and 4095; raw exactly at zero; positive one LSB; negative one LSB where representable |
| Offset-binary representation | `encoding=UNSIGNED_WITH_ZERO_CODE`, `zero_code=2048`, raw `0x000`, `0x7FF`, `0x800`, `0x801`, and `0xFFF` |
| Two's complement | raw `0x000`, `0x001`, `0x7FF`, `0x800`, `0xFFE`, and `0xFFF`; prove sign extension and asymmetric endpoints |
| Polarity | Each directed case with increasing-code-positive and increasing-code-negative; exact widened negation |
| Width | Prove every legal result fits signed 13 bits, including negated two's-complement minimum |
| Profile validity | Unknown/unsupported encoding, missing zero, inconsistent two's-complement zero, unknown polarity, and unconfigured profile |
| Channel atomicity | Independent channel changes, equal payloads with different sequences, and deliberately different channel patterns |
| Raw thresholds | Existing raw values at `N-1`, `N`, and `N+1`; equality remains safe under strict greater-than regardless of telemetry |
| Readback | Raw zero extension, normalized sign extension, and sequence/channels/flags/sequence retry |

## Throughput, CDC, and reset matrix

Reuse the Stage 2D/2E asynchronous-clock producer and atomic FIFO contract.
Required cases include:

- isolated and back-to-back accepted transactions;
- continuous destination deliveries proving `PIPELINE_INITIATION_INTERVAL=1`;
- FIFO wraparound and prolonged source backpressure with stable held payload;
- randomized clock ratios and phases;
- equal consecutive payloads with distinct sequences;
- source-first, destination-first, near-simultaneous, and in-flight reset;
- reset with each future pipeline stage occupied;
- no pre-reset replay, phantom valid, sequence detach, channel swap, reorder, or
  drop;
- first eligible post-reset transaction exactly once; and
- unconfigured normalized telemetry unavailable while the raw protection
  scoreboard continues unchanged.

The implementation must prove in both Icarus and XSim:

```text
PIPELINE_LATENCY=ONE_PUBLISHED_IMPLEMENTATION_DERIVED_FIXED_CONSTANT
PIPELINE_INITIATION_INTERVAL=1
NO_DATA_DEPENDENT_LATENCY=YES
NO_BACKPRESSURE_TO_ATOMIC_CDC=YES
NO_TRANSACTION_DROP=YES
```

A later authorized Vivado timing gate is required because simulator cycle
accuracy is not routed timing evidence.

## Future connected behavior mutations

Connected mutants must enter the compiled data path; direct predicate self-tests
are supplemental only.

| Mutation | Required detection |
|---|---|
| Wrong encoding mode | Midscale and endpoint model mismatch |
| Wrong two's-complement sign bit | Negative one and minimum mismatch |
| Zero code off by one | Exact zero and neighboring one-LSB mismatch |
| Nominal zero removal omitted | Unsigned centered cases mismatch |
| Polarity ignored or inverted | Opposite-sign result mismatch |
| Narrow negation | Two's-complement minimum under negative polarity mismatch |
| Channel outputs swapped | Asymmetric pair mismatch |
| Sequence detached | Same-transaction scoreboard mismatch |
| Valid delayed/advanced independently | Published-latency scoreboard mismatch |
| II greater than one | Back-to-back sequence loss or stall |
| Telemetry backpressures destination delivery | Source/destination acceptance regression |
| Threshold compared in normalized domain | Raw `N-1/N/N+1` protection regression |
| Configuration validity gates fault policy | Raw protection regression under unconfigured profile |
| Reset flush removed | Phantom or stale normalized transaction |

## Static and regression matrix

The hardened audit runs:

- Stage 2F static audit and all isolated mutation tests;
- all existing Python interface tests;
- Stage 2E source closure;
- Stage 2D source, CDC-constraint, and profile closure;
- Stage 1E packaging, base-design, and debug-design static suites;
- JSON parse and source-profile schema validation;
- documentation path validation;
- `git diff --check` and credential scan;
- clean-worktree and stable-HEAD checks;
- final local/remote branch equality;
- evidence manifest validation; and
- ZIP full-read, CRC, outer-manifest, nested-evidence-manifest, source-archive,
  and external-sidecar validation.

No functional RTL simulation is required for this audit because functional RTL
is forbidden in scope.

## Physical non-acceptance

Even after a future digital implementation passes Icarus and XSim:

```text
PHYSICAL_CURRENT_UNIT=NOT_ESTABLISHED
BOARD_CALIBRATION_ACCURACY=NOT_ESTABLISHED
HARDWARE_ADC_BEHAVIOR=NOT_ESTABLISHED
PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS
```

Physical closure requires an approved production ADC/AFE/sensor profile,
source-specific transfer function, reference/supply policy, safety review,
error budget, controlled calibration procedure, traceable instruments, and
board-identity-bound evidence. The Stage 3 reference candidate supplies none
of those production authorities.

## Final boundary fixtures

The final boundary suite also rejects a digital capability that requires
production ADC selection, a Stage 2 freeze forbidden solely because production
is unconfigured, a configured profile whose identity equals `UNCONFIGURED`, a
production-selected profile using that reserved identity, a bidirectional
reference labeled compatible with the current raw path, and a Linux
device-tree pin labeled as a complete FPGA implementation. The tracked
unconfigured profile and one valid configured simulation profile must pass.

```text
configured profile identity equals UNCONFIGURED
production-selected profile uses reserved identity
REFERENCE_BIDIRECTIONAL_NEGATIVE_OVERCURRENT_SUPPORTED_BY_CURRENT_RAW_PATH=NO
REFERENCE_PROFILE_IS_END_TO_END_PROTECTION_COMPATIBLE=NO
REFERENCE_PROFILE_REQUIRES_FUTURE_PROTECTION_DOMAIN_DECISION=YES
```
