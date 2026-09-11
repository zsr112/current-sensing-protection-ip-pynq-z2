# Stage 2F-D Digital Normalization Verification

The implementation is validated as a digital telemetry fork. No synthesis,
implementation, bitstream, or board action is part of this result.

```text
PRODUCTION_PROFILE=UNCONFIGURED
NORMALIZED_UNIT=SIGNED_CODE_COUNT
STAGE2F_CONTRACT_GAP_CLOSED=NO
PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
CONFIGURED_CAPABILITY=GENERATED_HEADER_DEFAULT_INSTANCE
DIRECT_PARAMETER_TESTS=SUPPLEMENTAL_ONLY
DATA_WIDTH_COMPATIBILITY_POLICY=RAW_GENERIC_NORMALIZATION_ONLY_AT_12
OBS_SEQUENCE_WIDTH_PROPAGATION=EXACT
PYTHON_REFERENCE_VECTORS=CONNECTED_TO_ICARUS_AND_XSIM
DUPLICATE_JSON_KEYS=REJECTED
```

## Directed and Exhaustive Simulation

`tb/stage2f/tb_stage2f_digital_normalization.sv` checks the six non-production
profiles represented by configured instances, plus the generated unconfigured
production instance. It covers unsigned zero codes at 0, 1, 2047, 2048, 4094,
and 4095, channel-asymmetric values, both polarity directions, the complete
two's-complement sign boundary (`0x7ff` to `0x800`), all 4096 two's-complement
codes, and all 4096 unsigned raw codes for the required zero-code cases.
The same scoreboard drives back-to-back valid cycles, repeated payloads with
distinct sequence values, random gaps, reset while occupied, three reset points
interleaved with randomized traffic, and the first post-reset transaction.

The bench publishes these acceptance markers in both Icarus and XSim:

```text
STAGE2F_DIRECTED=PASS
STAGE2F_EXHAUSTIVE_ARITHMETIC=PASS_4096_CODES_X_REQUIRED_ZERO_CODES
STAGE2F_RANDOM_TRANSACTIONS=PASS_1200_CYCLES
STAGE2F_RANDOM_RESET_POINTS=PASS_3
STAGE2F_RESET=PASS
STAGE2F_ALIGNMENT=PASS_SEQUENCE_CH1_CH2
STAGE2F_NO_DROP=PASS_INPUT_CYCLES=9402_OUTPUT_CYCLES=9402
```

`tools/stage2f_normalization_reference.py` is an independent integer model. It
uses Python integer sign decoding and an explicit latency queue rather than
copying RTL expressions. `tools/tests/test_stage2f_profile_generator.py`
checks the sign boundaries, exhaustive domains, reset flush, profile schema,
and deterministic provenance output.

`tools/run_stage2f_generated_profile_rtl.py` creates an isolated RTL root for
each of the six tracked profile JSON files, generates the header, copies the
real normalizer, and runs a default-parameter instance. Provenance-bound Python
vectors containing reset, gaps, boundaries, repeated and back-to-back traffic
are consumed unchanged by Icarus and XSim. The result requires
`PYTHON_REFERENCE_TO_RTL_COMPARISON=PASS`; direct parameter tests are
supplemental only.

`tools/run_stage2f_width_sequence_boundary.py` compiles a configured generated
header against the production top at data widths 8, 12, and 16 and sequence
widths 16, 24, and 32. It proves raw delivery remains functional at the tested
legacy widths, normalization is available only at 12 bits, high sequence bits
propagate exactly, unsupported normalized state is tied low, and the
normalizer connections produce no implicit port resize warnings.

## Connected Mutation Fixtures

`tools/run_stage2f_mutations.py` compiles and runs 13 normalizer source
transformations and one raw-path gate transformation. Each is connected to a
transaction-level oracle in `tb/stage2f/tb_stage2f_mutation.sv` or
`tb/stage2f/tb_stage2f_raw_gate_mutation.sv`; predicate-only source literals
are not used. The matrix runs in Icarus and XSim and requires all 28 simulator
mutant results to be killed.

`tools/run_stage2f_generator_mutations.py` connects six generated-output
mutations through the real default-instance normalizer in both simulators.
`tools/run_stage2f_boundary_mutations.py` independently removes the top width
gate, bypasses an unsupported tie, and truncates the sequence binding; all six
simulator results must be killed. Generator parsing tests inject duplicate keys
at the schema, top-level profile, and nested polarity levels and require
fail-closed rejection.

## Raw-Path Invariance

`tools/run_stage2f_raw_path_invariance.py` materializes the frozen top from
base commit `3399e4fdc28f9d4c66cf90cb5c1dc1e386eda6ae`, aliases it beside the
working top, and drives both with identical asynchronous ADC traffic and AXI
threshold writes. The checker compares raw acceptance and payload identity,
threshold snapshots, comparator outputs, health flags and state, fault inputs
and outputs, PWM/FSM outputs, and all Stage 2E counters/sticky fields. Icarus
and XSim must both publish `RAW_PATH_INVARIANCE=PASS`.

## Static and Regression Gates

The Stage 2F validation runner also invokes the frozen 37-test contract audit
with Git-scope checking disabled, profile/reference Python tests, JSON/profile
validation, Stage 2B/2C/2D/2E simulation regressions, canonical regression,
Stage 1E packaging/base/debug static suites, Stage 2D/2E source closure,
documentation-path and credential scans, and `git diff --check`. The controlled
source closure includes the normalizer and generated profile header in every
production authority.

After the implementation commit, `tools/build_stage2f_digital_review.py`
accepts only a clean, commit-matched validation root. Its `evidence` command
creates the required commit-bound evidence and manifests; after the branch is
pushed, its `package` command requires local/remote equality and produces the
review ZIP plus external SHA-256 sidecar. The builder fully reads the source
archive and ZIP, verifies CRCs, rejects unsafe or duplicate paths, scans the
package for credential-like material, and validates the outer and nested
evidence manifests separately.

The frozen audit remains authoritative for the non-closure claims:
`STAGE2F_CONTRACT_GAP_CLOSED=NO`,
`PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS`,
`REMAINING_CONTRACT_GAPS=2`, and `STAGE2_COMPLETE=NO`.
