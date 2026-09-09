# Stage 2H-C build, verification, and repository convergence tradeoff

Date: 2026-08-08
Status: Stage 2H-C1 audit complete; Stage 2H-C2 not started
Base: `7f2851b0e0366fdc0c692c4d65d85b7a5e12f4cf`
Parent freeze tag: `stage2h-b2-rtl-architecture-module-boundary-implementation-v1`
Branch: `codex/stage2h-c1-build-generation-verification-repository-audit`

## Outcome

The repository has sound live register-map and Stage 2F profile generation
authorities, and it does not need a new build system, source manifest, test
registry, repository graph, or RTL directory reorganization. Three grouped
Stage 2H-C2 changes are sufficient:

1. make the live v3 production runner the sole current production source and
   packaging authority, including generated IP-XACT register metadata;
2. migrate the current Stage 2G functional runner and direct-core fixture to
   the B2 topology, and remove the superseded core-local sequence matrix; and
3. make current source-closure/default verification consume live authorities
   while retaining closed-stage checks only as explicit historical oracles or
   tag-bound replay.

The audit found one functional packaging defect: the live production package
operation consumes the generated RTL register header but does not source or
apply `fpga/vivado/generated/protection_register_map_ipxact.tcl`. The separate
standalone packager applies that metadata, but it owns a second independently
maintained copy of the same production source list. Current package correctness
therefore depends on which entrypoint is used. C2 must fix the live runner and
remove the standalone path from current authority status.

```text
FUNCTIONAL_RTL_MODIFIED=NO
PUBLIC_ABI_MODIFIED=NO
RUNTIME_SOFTWARE_BEHAVIOR_MODIFIED=NO
STAGE2H_C2_IMPLEMENTATION_STARTED=NO
STAGE2H_D_STARTED=NO

PRODUCTION_BUILD_ENTRYPOINT_AUTHORITY=fpga/vivado/build/runtime/entrypoint/v3/stage1e_production_runtime_entrypoint_v3.ps1
PRODUCTION_SOURCE_LIST_AUTHORITY=::stage1e::production_vivado_runner_v2::_rtl_files
PRODUCTION_CONSTRAINT_LIST_AUTHORITY=::stage1e::production_vivado_runner_v2::_constraint_files

REGISTER_MAP_GENERATION_AUTHORITY_PRESERVED=YES
PARALLEL_MANUAL_REGISTER_MAP_AUTHORITY_COUNT=0
GENERATION_ENTRYPOINT_CONVERGENCE_REQUIRED=NO

CURRENT_REGRESSION_ENTRYPOINT_MODEL=RESPONSIBILITY_SCOPED_EXISTING_RUNNERS_WITH_STAGE2G_FUNCTIONAL_AS_CURRENT_RTL_ORCHESTRATOR_AND_NO_MEGA_RUNNER

STAGE2G_FUNCTIONAL_RUNNER_DISPOSITION=MIGRATE_TO_CURRENT_B2_TOPOLOGY
STAGE2G_CORE_DIRECTED_DISPOSITION=MIGRATE_TO_CURRENT_B2_TOPOLOGY
STAGE2G_SEQUENCE_MATRIX_DISPOSITION=SUPERSEDED_REMOVE_IN_C2
STAGE2G_SOURCE_CLOSURE_DISPOSITION=MIGRATE_TO_CURRENT_B2_TOPOLOGY
TOPOLOGY_BOUND_STAGE2G_VERIFICATION_DEBT_DECIDED=YES

RTL_FILE_REORGANIZATION_IN_C2=NONE
ADC_CDC_BRIDGE_DEDUP=DEFERRED_OR_NO_CHANGE
C2_RECOMMENDED_CHANGE_COUNT=3
```

## Frozen boundary

C2 may change build/source ownership, runner orchestration, test
classification, generation consumption, and package validation. It must not
change:

- the packaged top `protection_ip_top_async_adc_axi_lite`;
- external packaged ports, ABI 1.1, offsets, access semantics, capabilities,
  or runtime software behavior;
- raw protection, source/destination integrity, policy/recovery, latency,
  clear-fence, reset, CDC, or sequence-width behavior; or
- synthesis, implementation, timing, bitstream, board, or physical-scaling
  results during C1 or C2.

The Stage 2H-A binding metadata and generated output paths remain frozen.
Stage 2H-B module boundaries remain frozen. No functional RTL is in C2 scope.

## Current production authority

The exact current build path is:

```text
sealed Stage 1E execution request
  -> fpga/vivado/build/runtime/entrypoint/v3/
     stage1e_production_runtime_entrypoint_v3.ps1
  -> fpga/vivado/build/runtime/runner/
     stage1e_production_vivado_runner_v2.tcl
  -> package_protection_ip
  -> protection_ip_top_async_adc_axi_lite
  -> create_build_project / protection_system_wrapper
```

The PowerShell entrypoint validates a sealed request, requires a clean commit
and external fresh workspace/output roots, launches one supervised Vivado
2024.1 process, and reads the terminal result. The Tcl runner packages the
custom IP, creates the PYNQ-Z2 block design, generates the wrapper, validates
topology, and owns synthesis/implementation/artifact phases. C1 did not run
those phases.

The current source and constraint declarations are:

```text
PRODUCTION_SOURCE_LIST_AUTHORITY=
::stage1e::production_vivado_runner_v2::_rtl_files

PRODUCTION_CONSTRAINT_LIST_AUTHORITY=
::stage1e::production_vivado_runner_v2::_constraint_files
```

`_rtl_files` declares 21 files. `_constraint_files` declares the Stage 2D
atomic ADC CDC XDC and Stage 2E observability CDC XDC. These procedures are
already in the runner that performs the live package operation, so making them
authoritative adds no new metadata layer.

### Duplicate source-list disposition

| Declaration | Current assessment | C2 disposition |
|---|---|---|
| `production_vivado_runner_v2::_rtl_files` | Live production list | Keep as current authority |
| `package_protection_ip_stage2_axi_lite.tcl` `rtl_files` | Same package target, independent copy | Remove from current status; retain only if needed for frozen historical replay |
| `stage1e_phase2_synthesis_config_v1.dict` four packaging/source fields | Compatibility-era controller input, not consumed by v3 runtime | Classify historical replay-only; current checks must not treat it as live ownership |
| `stage1d_build_config.dict` source fields | Legacy compatibility build history | Historical/legacy only |
| Stage 2G and Stage 2H simulation lists | Testbench-specific elaboration sets | Legitimately target-specific; closure must prove required live production dependencies are not omitted |

The v3 entrypoint never reads
`stage1e_phase2_synthesis_config_v1.dict`. That dictionary remains useful for
frozen Stage 1E controller replay, but its repeated source paths are not a
current production authority.

### Package metadata defect

The live runner creates an IP-XACT memory map and address block, but currently
adds no register objects. Static counts in the live runner are:

```text
protection_register_map_ipxact=0
protection_register_map_apply_ipxact=0
ipx::add_register=0
```

The standalone packager correctly sources the generated Tcl and calls
`protection_register_map_apply_ipxact`. Existing
`stage2e_ipxact_metadata_scope_tests.tcl` proves only that historical
standalone path. It is not proof of the package produced by the live v3
runner.

C2 must source the generated IP-XACT file from the live runner, apply it to the
live `reg0` address block, validate the generated register count, and extend a
current package/source-closure check to cover that exact operation.

## Generation authorities

### Register map

The live authority remains:

```text
spec/register_map.json
spec/register_map.schema.json
tools/generate_register_map.py
```

The generator deterministically owns eight tracked outputs:

1. `rtl/generated/protection_register_map.vh`;
2. `sw/generated/protection_register_map.py`;
3. `sw/ps_register_demo/protection_ip_regs.h`;
4. `fpga/vivado/generated/protection_register_map_ipxact.tcl`;
5. `docs/implementation/register_map.md`;
6. `tb/generated/protection_register_map.svh`;
7. `spec/generated/protection_register_map_compatibility.json`; and
8. `spec/generated/protection_register_map_conformance.json`.

RTL, Python, C, SystemVerilog, documentation, compatibility, and conformance
consumers are connected. The only current production-consumption gap is the
live runner's missing IP-XACT application. Comments and validation tables in
older scripts are not mutable register-map authorities. No parallel manual
register-map authority was found.

The current drift command remains:

```text
python tools/generate_register_map.py --check
```

### Stage 2F compile-time profile

The production runner also consumes
`rtl/generated/stage2f_adc_source_profile.svh`. Its authority remains:

```text
spec/stage2f_adc_source_profile.schema.json
spec/stage2f_adc_source_profile_unconfigured.json
tools/generate_stage2f_adc_profile.py
```

This is one generator and one tracked output. It does not justify a generic
generation orchestrator. Its targeted drift command is:

```text
python tools/generate_stage2f_adc_profile.py --profile spec/stage2f_adc_source_profile_unconfigured.json --check
```

## Verification authority model

The repository should retain responsibility-scoped existing runners. A giant
runner would mix fast RTL checks, Vivado-static checks, software tests,
historical replay, coverage, release construction, and evidence packaging with
different environments and proof meanings.

| Responsibility | Primary current entrypoint | Supporting targeted entrypoints | Historical oracle/replay |
|---|---|---|---|
| RTL functional, policy, recovery, connected production path | `tools/run_stage2g_functional_rtl.py` after C2 migration | `tools/run_stage2h_b2_rtl_architecture.py`, `tools/run_stage2h_a2_2_verification.py` | Stage 2G frozen audit/source archive replay |
| AXI/register contract | Stage 2G functional runner current production-path and register tests | `sim/run_iverilog.sh all`, register-map checks | dated Stage 2D/2E runners |
| CDC/source transaction | Stage 2G functional runner connected production tests | Stage 2H-B2 source-integrity fixture and current XDC/source-closure tests | Stage 2D/2E evidence runners |
| Register-map/ABI | `tools/generate_register_map.py --check` and `tools/check_register_map_implementation.py` | Stage 2H A2-2 runner and software tests | Stage 2H-A source-archive replay/audit |
| Software | `python -m unittest discover -s sw/tests -p test_*.py -v` | repository unit tests | board observation scripts and dated review fixtures |
| Build/source closure | v3 runtime static tests plus migrated current source-closure check | dependency omission fixtures | Stage 1D/1E phase-controller and Stage 2D/2E frozen closure tests |
| IP-XACT/package | live runner package operation plus C2 current metadata-scope check | generator drift check | standalone packager and Stage 2E metadata-scope test |
| Release/package | `tools/build_current_release.py`, `tools/verify_current_release.py` | `tools/check_external_data_authorities.py`, Stage 1G deployment tests | board execution and review-bundle builders |
| Coverage | Stage 2H-D must establish integrated current coverage | focused B2 counts are verification, not coverage closure | `sim/run_xsim_coverage.ps1` is legacy/frozen coverage tooling |

The existing `.github/workflows/stage1g-posix-validation.yml` validates the
Stage 1G deployment surface only. It is not current RTL/build CI. C1 does not
add CI. Stage 2H-D owns the decision to wire the final integrated current
regression and coverage boundary into CI.

## Mandatory Stage 2G debt

### Functional runner

`tools/run_stage2g_functional_rtl.py` is still the intended current functional
RTL orchestrator, but it rejects any branch other than the old Stage 2G branch
and requires the old Stage 2G `main` identity. It also always constructs and
replays a Stage 2G source archive before functional tests. That replay is
historical evidence work, not a minimum current developer regression.

```text
STAGE2G_FUNCTIONAL_RUNNER_DISPOSITION=MIGRATE_TO_CURRENT_B2_TOPOLOGY
```

C2 must remove the frozen branch/base gate, keep an optional clean-worktree
check, use current B2 fixtures, and exclude archive replay and frozen-stage
oracles from the normal default. Explicit review/replay modes may retain them.

The PowerShell wrapper computes `$RepoRoot` but launches the relative path
`tools/run_stage2g_functional_rtl.py` from the ambient current directory. C2
must invoke the absolute repository-root path or set the subprocess working
directory. This is a concrete repository usability defect, not a defensive
response to a one-off shell typo.

### Direct-core fixture

`tb/stage2g/tb_stage2g_core_directed.sv` leaves the new
`sample_destination_integrity_clean` input floating. Its current run reaches
`STAGE2G_CORE_DIRECTED=FAIL_21`. The fixture still provides valuable direct
coverage of raw fault evaluation, reset and pipeline flushing, first-fault and
seen-fault behavior, source-integrity policy, clear fencing, and recovery.

```text
STAGE2G_CORE_DIRECTED_DISPOSITION=MIGRATE_TO_CURRENT_B2_TOPOLOGY
```

C2 must explicitly drive the destination-integrity input. The fixture must not
recreate destination sequence state inside the core.

### Sequence matrix

`tb/stage2g/tb_stage2g_sequence_integrity_matrix.sv` reaches removed
core-local destination sequence state and fails elaboration. The connected B2
fixture `tb/stage2h/tb_stage2h_b2_destination_sequence.sv` already covers
16/24/32-bit widths, first zero/nonzero, gaps, duplicates, stale/reorder,
modulo wrap, policy/observability classification agreement, clear/recovery,
and the three-ACLK latency.

```text
STAGE2G_SEQUENCE_MATRIX_DISPOSITION=SUPERSEDED_REMOVE_IN_C2
```

C2 must remove the obsolete fixture from the current tree/default runner and
reuse the B2 connected suite. No compatibility adapter should preserve removed
core-local state.

### Source closure

`stage2g_source_closure_tests.tcl` still proves useful source omission and
dependency-closure properties, but it reads the compatibility-era Stage 1E
phase-2 dictionary as current authority and requires the core to instantiate
the destination classifier. B2 correctly moved that classifier/state to the
destination tracker.

```text
STAGE2G_SOURCE_CLOSURE_DISPOSITION=MIGRATE_TO_CURRENT_B2_TOPOLOGY
```

C2 must point current closure at the live runner, preserve negative omission
checks and raw-path invariants, verify the tracker topology, and remove only
obsolete core-local assertions.

## Historical verification policy

Closed-stage checkers are immutable historical oracles. C2 must not add
future-stage exceptions to make them pass against the live tree.

The minimum policy is:

1. current default runners execute only live-topology tests;
2. a closed-stage checker that requires frozen files is run only through its
   existing source-archive replay or with its documented frozen commit/tag;
3. historical-only scripts and testbenches remain clearly excluded from
   current defaults; and
4. no generic version adapter or automatic checkout framework is added.

```text
HISTORICAL_ORACLE_MUTATED_TO_ACCEPT_FUTURE_TOPOLOGY=NO
HISTORICAL_CURRENT_STATUS_AMBIGUITY=NO
```

## Repository organization

The mixed-generation files named in B1 do not create a production ownership
ambiguity. Vivado source inclusion is not elaborated module ownership, and the
selected top plus module names distinguish current Stage 2G production modules
from legacy compatibility modules. Moving these files would churn build lists,
documentation, frozen Stage 2H-A bindings, source archives, and mature tests
without removing mutable authority.

```text
RTL_FILE_REORGANIZATION_IN_C2=NONE
```

The legacy and Stage 2G ADC CDC bridge modules share FIFO and source-observer
authorities. Their remaining wrapper differences reflect distinct payload
contracts and constraint-sensitive hierarchy. Keeping both in the same live
source list does not cause the selected top to instantiate the wrong bridge.

```text
ADC_CDC_BRIDGE_DEDUP=DEFERRED_OR_NO_CHANGE
```

## Tool and environment findings

Current workflows assume:

- Python 3.10 or later for current type syntax and standard-library APIs;
- Icarus Verilog and `vvp` on `PATH` for current RTL simulation;
- Vivado 2024.1 build 5076996, `xc7z020clg400-1`, and the PYNQ-Z2 board
  definition for production build work;
- `xtclsh.bat` from the selected Vivado installation for Vivado Tcl/static
  tests, rather than a standalone `tclsh` assumption;
- Windows PowerShell 5.1 for the current production entrypoint and wrappers;
- MSYS2 Bash for the legacy `sim/run_iverilog.sh` path on Windows; and
- fresh external build/evidence output directories.

The audited host has Python 3.12.10, Icarus 13.0, Windows PowerShell
5.1.26100.8875, MSYS2 Bash, and Vivado/xtclsh 2024.1. Standalone `tclsh` and
PowerShell 7 `pwsh` are not present. Current repository commands do not require
either one.

```text
C2_TOOLING_FIXES=REMOVE_STAGE2G_FROZEN_GIT_IDENTITY_GATE;MAKE_STAGE2G_POWERSHELL_WRAPPER_CWD_INDEPENDENT;KEEP_VIVADO_BIN_OVERRIDE_FOR_XTCLSH_XSIM
```

No generic shell wrapper or defensive quoting framework is justified.

## Transient artifact policy

No transient simulation, Python cache, Vivado project, waveform, or log file
is tracked. Existing ignored files demonstrate that `.gitignore` already
covers `__pycache__`, `.vvp`, `.vcd`, logs, Vivado products, and `outputs/`.
Current Stage 2G/2H runners accept explicit output roots and production Vivado
requires external fresh roots.

```text
TRANSIENT_ARTIFACT_POLICY=KEEP_EXISTING_IGNORE_RULES_AND_OUTPUT_DIRECTORY_ISOLATION_NO_CLEANUP_FRAMEWORK
```

C2 should not add recursive cleanup or hash-based cleanliness checks.

## Release and package boundary

The current release authorities are:

```text
tools/build_current_release.py
tools/verify_current_release.py
```

The builder selects the accepted Stage 1G board BIT/HWH authority, adds current
deployment/runtime material and generated software/docs, verifies staging, and
publishes atomically. The verifier proves release structure, identity,
provenance, and manifest coverage. Neither tool proves that the current Stage
2H RTL has been synthesized or board validated.

`tools/check_external_data_authorities.py` is supporting provenance validation.
`tools/board_validation/**`, Stage review builders, independent review-bundle
builders, and source-archive builders are historical evidence tooling. They do
not become normal build or functional correctness authorities.

```text
CURRENT_RELEASE_PACKAGE_AUTHORITY=tools/build_current_release.py;tools/verify_current_release.py
HISTORICAL_EVIDENCE_TOOLING_CLASSIFIED=YES
NEW_HASH_AUTHORITIES_ADDED=0
```

## Default developer validation

After C2, a normal relevant change should use the smallest applicable set:

1. run register-map or Stage 2F profile drift checks when those authorities or
   consumers change;
2. run the current Stage 2G functional runner without historical replay for
   RTL/policy/CDC/AXI changes;
3. run current live-runner source/package closure when build lists, packaging,
   constraints, or generated IP-XACT consumption change; and
4. run software unit tests when ABI/software consumers change.

Mutation, XSim parity, full legacy compatibility, coverage, release building,
historical replay, evidence ZIP creation, and archive hashing are escalation
checks selected by risk or a review gate, not universal per-edit defaults.

```text
DEFAULT_DEVELOPER_VALIDATION_MODEL=FAST_CHANGED_BOUNDARY_CHECKS_PLUS_CURRENT_RELEVANT_REGRESSION_PLUS_APPLICABLE_GENERATION_DRIFT
```

## C2 implementation target

### C2-CUR-01 - Production packaging and source authority

```text
CURRENT_PROBLEM=LIVE_V3_PACKAGE_OMITS_GENERATED_IPXACT_REGISTERS_AND_TWO_CURRENT_LOOKING_PATHS_OWN_THE_SAME_RTL_LIST
CURRENT_AUTHORITY=V3_RUNTIME_RUNNER_FOR_REAL_BUILD_BUT_STANDALONE_PACKAGER_FOR_IPXACT_METADATA
TARGET_AUTHORITY=PRODUCTION_VIVADO_RUNNER_V2_RTL_CONSTRAINT_AND_PACKAGE_PROCEDURES
BEHAVIORAL_RISK=LOW_NO_RTL_OR_ABI_CHANGE
BUILD_RISK=MEDIUM_PACKAGE_COMPONENT_XML_AND_SOURCE_CLOSURE_CHANGE
```

Affected current files/entrypoints are the live runner, current register-map
implementation checks, and one focused current package/source-closure test.
The standalone packager and phase-2 config are removed from current authority
status and retained only where frozen replay requires them.

Changed-boundary proof must show:

- the live runner resolves the intended 21 RTL files and two XDC files;
- generated IP-XACT is sourced and applied exactly once to `reg0`;
- generated register count and representative field/enum metadata match the
  generated artifact;
- omission of a required source, XDC, or generated IP-XACT input is rejected;
- no synthesis, implementation, bitstream, or board execution is needed for
  the static/package-mock boundary.

Existing Stage 2E IP-XACT mock logic and source-closure negative fixtures can
be reused without treating their historical entrypoint as current authority.

### C2-CUR-02 - Current Stage 2G functional regression

```text
CURRENT_PROBLEM=CURRENT_RUNNER_REJECTS_CURRENT_GIT_IDENTITY_AND_DEFAULTS_TO_TWO_BROKEN_TOPOLOGY_BOUND_FIXTURES
CURRENT_AUTHORITY=TOOLS_RUN_STAGE2G_FUNCTIONAL_RTL_PY
TARGET_AUTHORITY=SAME_RUNNER_WITH_CURRENT_B2_FIXTURES_AND_EXPLICIT_OPTIONAL_ESCALATION_MODES
BEHAVIORAL_RISK=LOW_FIXTURE_AND_ORCHESTRATION_ONLY
BUILD_RISK=LOW_NO_PRODUCTION_BUILD_INPUT_CHANGE
```

Affected files are the Python runner, its PowerShell wrapper, the direct-core
fixture, and the obsolete sequence matrix. The B2 connected destination
sequence fixture is reused.

Changed-boundary proof must show:

- the runner starts on the current branch/base without a frozen Stage 2G gate;
- the direct-core fixture drives both source and destination integrity inputs;
- B2 widths 16/24/32, wrap, policy/observability agreement, and latency run
  through the current suite;
- the obsolete core-local sequence matrix is unreachable and removed; and
- the wrapper works from a non-repository current directory.

### C2-CUR-03 - Current versus historical verification policy

```text
CURRENT_PROBLEM=CURRENT_DEFAULTS_CALL_FROZEN_ARCHIVE_AND_COMPATIBILITY_ERA_CLOSURE_PATHS_WITHOUT_CLEAR_PROOF_CLASSIFICATION
CURRENT_AUTHORITY=MIXED_STAGE2G_DEFAULT_ORCHESTRATION
TARGET_AUTHORITY=CURRENT_DEFAULTS_USE_LIVE_TOPOLOGY;FROZEN_CHECKS_USE_EXPLICIT_REPLAY_OR_TAG_CONTEXT
BEHAVIORAL_RISK=NONE_ORCHESTRATION_AND_CLASSIFICATION_ONLY
BUILD_RISK=LOW_STATIC_CLOSURE_CONSUMER_CHANGE
```

Affected entrypoints are the Stage 2G runner default suite, migrated Stage 2G
source closure, and concise current/historical invocation documentation.

Changed-boundary proof must show:

- every intended current test remains reachable;
- historical-only replay is intentionally absent from the default;
- explicit replay still identifies its frozen source context;
- current source closure reads the live runner rather than compatibility-era
  configs; and
- obsolete core-local classifier assertions are gone while real omission and
  dependency checks remain.

## Deferrals and no-change decisions

```text
C2_RECOMMENDED_CHANGE_COUNT=3

DEFER_TO_STAGE2H_D=INTEGRATED_FINAL_CURRENT_REGRESSION;CURRENT_COVERAGE_CLOSURE;RELEASE_CLOSURE;CI_ALIGNMENT_DECISION
DEFER_TO_STAGE2I=PHYSICAL_SCALING;EXTERNAL_ADC_AFE_CALIBRATION;POWER_STAGE_AND_EXTERNAL_HARDWARE_FACTS

NO_CHANGE_REQUIRED=REGISTER_MAP_GENERATOR;STAGE2F_PROFILE_GENERATOR;RTL_FILE_LAYOUT;ADC_CDC_BRIDGE_ASSEMBLY;ACLK_RESET_AUTHORITY;CURRENT_RELEASE_BUILDER_AND_VERIFIER;EXISTING_TRANSIENT_IGNORE_POLICY

REJECTED_OVERENGINEERING=UNIVERSAL_BUILD_SYSTEM;BAZEL_OR_CMAKE_MIGRATION;GENERIC_SOURCE_MANIFEST;GENERIC_TEST_REGISTRY;GENERIC_STAGE_VERSION_ADAPTER;GENERIC_ARTIFACT_GRAPH;REPOSITORY_WIDE_MODULE_RENAME;WHOLE_RTL_DIRECTORY_SPLIT;SINGLE_MEGA_RUNNER;RECURSIVE_EVIDENCE_HASH_PIPELINE;AUTOMATIC_HISTORICAL_GIT_CHECKOUT
```

## First-principles scope review

Each accepted C2 group removes a concrete failure or maintenance risk:

| Change | Real risk removed | Authority clarified/replaced | Net complexity |
|---|---|---|---|
| C2-CUR-01 | Live packages can omit generated register objects; duplicate source lists drift | Live runner replaces standalone/current-looking package authority | Reduced: one live source/package owner |
| C2-CUR-02 | Current runner fails before tests and invokes disconnected/removed topology | Existing Stage 2G runner remains current using B2 fixtures | Reduced: obsolete matrix removed, no new runner |
| C2-CUR-03 | Historical failures appear as current failures; closure proves old configs | Live topology for defaults, explicit replay for frozen oracles | Reduced: fewer default paths and no version framework |

```text
GENERIC_BUILD_FRAMEWORK_ADDED=NO
GENERIC_TEST_REGISTRY_ADDED=NO
GENERIC_REPOSITORY_GRAPH_ADDED=NO
NEW_HASH_AUTHORITIES_ADDED=0
LOW_INFORMATION_SMOKE_TEST_EXPANSION=NO
UNNECESSARY_DEFENSIVE_WRAPPERS_ADDED=0
MINIMUM_SUFFICIENT_ASSURANCE=PASS
FIRST_PRINCIPLES_SCOPE_REVIEW=PASS
```
