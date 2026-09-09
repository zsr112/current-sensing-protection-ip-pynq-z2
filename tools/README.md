# Repository Tools

## Purpose

`tools/` is the home for repository-wide automation that spans multiple
engineering domains. Appropriate uses include repeatable checks, analysis,
inventory generation, documentation validation, governance validation, and CI
or release orchestration.

This directory does not grant execution authority and does not contain a tool
merely because that tool is a script.

## Allowed Responsibilities

Future tools may provide:

- repository-structure and prohibited-path checks;
- Markdown link and repository-relative reference analysis;
- source/document inventory and inbound-reference reports;
- read-only Git/source-state preflight reporting;
- cross-domain consistency checks;
- governance metadata validation; and
- CI orchestration that calls authoritative domain entry points.

Tools should be deterministic, reviewable, fail clearly, avoid ambient external
state, and keep generated output in ignored or explicitly external locations.
Read-only analysis should be the default where mutation is unnecessary.

## Domain Boundary

`tools/` must not replace or absorb:

- `sim/`, which owns simulation-domain commands, source lists, build outputs,
  and waveform outputs; or
- `fpga/vivado/build/`, which owns Vivado build controllers, adapters,
  lifecycle libraries, configs, mutation logic, provenance checks, and their
  Tcl tests.

Similarly, software tests remain under `sw/tests/` and RTL testbenches remain
under `tb/`. A repository-wide wrapper may invoke a domain entry point, but it
must not silently duplicate or redefine the domain contract.

## Identity and Safety Rules

1. Adding a tool changes the Git tree and may require a new source freeze.
2. If a tool becomes an execution input, include it in the applicable versioned
   source/controller inventory and refresh qualification/authorization as
   required.
3. Do not weaken `fpga/vivado/build/lib/source_check.tcl` or substitute a
   convenience clean-tree check for the authoritative Stage 1E gate.
4. Do not read ignored/generated material as an implicit controlled input.
5. Mutation, cleanup, release, and external publication require explicit scope
   and authorization.
6. Checks must distinguish static validation, runtime execution, engineering
   acceptance, and artifact publication.

## Current Tools

`check_external_data_authorities.py` performs read-only validation of the
machine-readable external authority contract. It checks required paths, types,
immutable bytes/SHA-256 values, directory markers, and accepted Stage 1E
artifact identities. It also verifies the local public snapshot Git HEAD/tree,
clean branch, unique `origin` URL and local `origin/main`, public provenance, public self-verifier,
deploy release verifier, and BIT/HWH identities. It never moves, deletes,
unpacks, or rewrites external data. Its tests live in
`tests/test_check_external_data_authorities.py`.

`build_current_release.py` selects the current-use release deterministically,
builds it in same-volume staging, verifies it, and atomically publishes one
expanded directory. Its default path contract is the public snapshot
`deploy/` subtree; the existing-target guard prevents in-place overwrite, so a
future full public-snapshot regeneration must use its controlled staging path.
`verify_current_release.py` is the standard-library,
read-only verifier copied into that release. The builder binds persistent
runtime files to the Stage 1G board-validated Git commit and selects the sole
BIT/HWH pair through the external authority contract. Their tests live in
`tests/test_build_current_release.py` and
`tests/test_verify_current_release.py`.
