# Stage 1E Controlled Runtime Layer v1

This directory contains the admitted preparation-only runtime foundation and
the PRT02-A production entry-point/envelope candidate for a future Stage 1E
Implementation Run2. The overall backend remains `MOCK_ONLY`; the candidate
does not make production dispatch available. This layer cannot launch Vivado,
execute an implementation operation, qualify a host, create or consume
authorization, decide acceptance, collect FPGA artifacts, publish FPGA
artifacts, or access a board.

Responsibility is split as follows:

- `launcher/`: validates a mock launch request and delegates to injected
  process and environment callbacks without changing authorization state.
- `runner/`: enforces the fixed operation order and delegates operations to
  injected mock callbacks without deciding PASS.
- `collector/`: retains the historical mock collector and adds the disconnected
  PRT02-D versioned Vivado-side Collector candidate. The latter owns a closed
  report-command map and append-only attempt evidence, but its real Vivado
  command forms are unqualified and are never used by repository tests.
- `parser/`: retains the historical mock parser and adds the disconnected
  PRT02-D exact-inventory Parser candidate. It parses versioned synthetic
  fixtures without directory discovery, Vivado invocation, dispositions, or
  favorable defaults for unknown values.
- `identity/`: retains the historical mock identity helpers and adds the
  PRT02-D structural evidence serializer. The serializer delegates canonical
  bytes and no-overwrite publication to the admitted PRT02-A providers and
  does not issue a production identity.
- `observer/`: validates observations supplied by a mock environment/process
  callback and rejects stale observations.
- `entrypoint/`: provides the sole two-input production assembly boundary. It
  validates a sealed canonical request, records the controlled assembly load
  ledger with `ENTRY_POINT` as its unique root, and publishes only a terminal
  `BLOCKED` result while the production controller and downstream runtime
  components are absent. Its dependency-closure state is
  `PARTIAL_FOUNDATION`, never `CLOSED`.
- `assembly/`: provides PRT02-E Host, Vivado, and post-process pre-dispatch
  load-ledger validators. These validators are review-candidate utilities and
  are not loaded by the public entry point or any accepted A/B/C/D candidate.

The versioned request, result, and failure schemas plus the PowerShell/Tcl
canonical JSON, envelope-contract, and atomic-publication modules live in
`../lib/`. They define exact fields, schema-owned canonical order, UTF-8
without BOM, cross-language identity bytes, and sibling no-overwrite
publication. They create only concrete request/result envelope identities;
they do not create or approve source, backend, qualification, environment,
workspace, synthesis, dependency-closure, or authorization identities.

The effective operation graph is limited to `opt_design`, `place_design`,
`route_design`, and implementation reports. `phys_opt_design` is explicitly
disabled and prohibited. Production runtime activation requires a later
reviewed backend, identity closure, Q0-Q5 qualification, and a separately
issued one-use implementation authorization.

PRT02-A is an envelope and entry-assembly foundation only. It is not
Production Runtime Ready, Run2 Ready, or Authorization Ready.
Its forbidden-boundary scan state is `NOT_EVALUATED`, not `CLEAR`; all related
authority fields remain `NONE`. Request semantics keep logs, journals, and
request files under the evidence root; temporary and cache state under the
workspace root; and source, workspace, and evidence roots pairwise disjoint.

PRT02-B adds a disconnected Host Boundary Foundation for non-Vivado process
qualification. The versioned production launcher candidate is
`launcher/stage1e_production_runtime_launcher_v1.psm1`; its read-only host
observer candidate is
`observer/host/stage1e_production_host_observer_v1.psm1`. They are exercised
only by fixed internal test harnesses and are not imported by the public entry
point.

The Host Boundary Foundation uses the reviewed C# Win32 provider and
PowerShell adapter in `../lib/` to create one exact process suspended, assign
and verify a kill-on-close/no-breakaway Job Object before one resume, retain
the process and primary-thread handles, and use a `STARTUPINFOEX` handle list so
only child stdin-read, stdout-write, and stderr-write are inherited. A Job
completion port is associated before process creation; its monotonic native
events are reconciled with current membership snapshots and directly opened or
retained process-instance evidence. The Job active-process limit is the exact
sum of declared topology maxima, bounded by the HOST requirement of 32.

The launcher supplies an explicit allow-listed child environment and literal
cwd, checks total/startup deadlines before creation and again before resume,
supervises heartbeat silence and total lifetime with monotonic time, and makes
one final bounded heartbeat read after complete process-tree termination.
Missing process facts or a terminal trailing heartbeat partial block without a
candidate. It preserves the first failure and publishes canonical no-overwrite
host preflight, process-ledger, timeout/termination-ledger, and terminal
host-result records. `PROCESS_RUNNING` is append-only ledger state only and is
prohibited from the sealed terminal host result.

The host schemas are `stage1e_runtime_host_*_v1.schema.json`; their contract
adapter is `../lib/stage1e_host_boundary_contract_v1.psm1`. They preserve only
supplied symbolic request/runtime/environment/workspace/dependency references
and create no host or backend identity. Qualification, authorization issue or
consumption, engineering acceptance, FPGA artifact work, publication,
hardware-manager use, and board access remain outside this boundary.

PRT02-B validates literal/component path containment, root separation, and
existing reparse-point rejection as foundation checks. Complete Windows path
hardening for junctions, symlinks, short names, trailing dots/spaces, case
ambiguity, and volume identity remains a future HOST-contract qualification
dependency. Vivado executable/wrapper qualification, production controller
integration, Vivado-side runtime roles, dependency closure, Q0-Q5,
authorization, Run2, artifact, and board work also remain unavailable.

PRT02-C adds a disconnected Vivado Runtime Control Foundation. Its append-only
production candidates are the versioned controller and adapter under
`../controller/` and `../adapters/`, the read-only Vivado capability observer
under `observer/vivado/`, and the staged Project Mode runner plus subordinate
session assembly under `runner/`. The controller alone may publish and consume
the separate sealed one-use authorization receipt. The runner alone contains
the reviewed `impl_1` scheduling forms for `opt_design`, `place_design`, and
`route_design`, followed by opening only that routed run for a collector
handoff. The public PRT02-A entry point and PRT02-B host launcher do not load or
invoke these candidates.

Each phase wait uses the closed `wait_on_run -timeout <minutes> impl_1` shape.
The adapter preserves the sealed phase budget in seconds; the controller
accepts it only when it projects exactly to a positive whole-minute Vivado
timeout, with incompatible values blocking before authorization consumption.
Runner native-state records are derived from the accepted observer snapshots,
so capability/property queries remain observer-owned.

The Session captures its own source path, module root, and build root at source
load. It publishes an ordered six-role inventory that the controller compares
to the exact PRT02-C sources and interface versions before continuing. This is
only `PRT02C_FIXED_ASSEMBLY_VALIDATED` within
`PRT02C_DIRECT_ASSEMBLY_ONLY`; dependency closure remains `NOT_PROVEN` and is
not a PRT02-E result.

The PRT02-C observer uses fixed read-only queries and exact property names at
`TOOL_PREFLIGHT`, `PRE_CONSUME`, `POST_OPT`, `POST_PLACE`, `POST_ROUTE`, and
`TERMINAL`. Unknown, missing, stale, unreadable, ambiguous, or conflicting
state blocks. Forbidden markers serialize only as `CLEAR`, `DETECTED`, or
`UNKNOWN`, while downstream evidence serializes only as `ABSENT`, `DETECTED`,
or `UNKNOWN`; uncertainty is never rewritten as detection. Query, control, and
report availability observations use the explicit frozen global ordinals
1-31, sorted independently of Tcl dictionary insertion order. The run
relationship binds `current_run` exactly: no current run is permitted at
preflight/pre-consume, and only `impl_1` is accepted at every post-phase and
terminal point. Physical optimization remains disabled, unauthorized,
unsequenced, directive `NONE`, and invocation-prohibited; neither the runner
nor its operation ledger exposes a physical-optimization phase.

Expected opt/place/route launch, wait, timeout, readback, forbidden-operation,
observer-uncertainty, and routed-open failures return validated terminal
Session and Vivado component records with a `FAILURE_EVIDENCE_ONLY` handoff.
The exact ledger is preserved, later phases remain `NOT_RUN`, and no later run
or phase is attempted. Runner failure ordinals are derived from the permitting
controller decision and accepted only as the next controller transition.
Vivado records never claim a Host process state: `process_effect` is
`STATE_UNKNOWN`, owned by `HOST_RESULT_NOT_CONNECTED` until a sealed PRT02-B
Host Result is integrated.

PRT02-C itself remains immutable and therefore still emits its historical
`BLOCKED / DEPENDENCY_CLOSURE / PRODUCTION_COLLECTOR_NOT_IMPLEMENTED` marker
in `REPORT_COLLECTION`, with no candidate created. PRT02-D consumes that exact
handoff only through a separate, disconnected adapter; it does not rewrite or
replace the C result.

PRT02-D adds the disconnected Evidence Pipeline Foundation: exact versioned
REPORT, MESSAGE, parser-profile, and evidence-record contracts; a closed
Collector candidate; an exact-inventory Parser candidate; a structural
serializer; and append-only evidence controller/adapter candidates. The
REPORT taxonomy contains seven adopted roles and thirteen Collector roles.
Each report attempt preserves an open event before its fixed command, a
terminal or interruption event, no retry, exact current-attempt binding, and
first/secondary failure order. Conditional bus-skew state is supplied only by
controller configuration; an unknown condition blocks.

Before an open event, the Collector atomically publishes an exclusive,
no-overwrite reservation that binds the exact attempt-specific output path.
Every file-backed raw item carries a byte count, lowercase SHA-256 integrity
observation bound to request/execution/attempt/workspace/session/role, and a
publication-receipt reference. The Parser reopens the exact binary bytes and
the Collector terminal receipt; same-size mutations, refreshed counts without
the original digest, and foreign integrity bindings block.

All D parser profiles are `FIXTURE_PROFILE_ONLY` and explicitly require
`VIVADO_2024_1_FORMAT_QUALIFICATION_REQUIRED`. Canonical message, DRC,
methodology, timing, clock/CDC, timing-exception, and utilization inventories
preserve missing, unknown, foreign, truncated, unsupported, and conflicting
facts without converting them to zero. The evidence set references the full
operation and report-attempt ledgers separately from their validated compact
projections and carries the Vivado component, explicit Host-disconnected, and
forbidden-boundary records without overloading a PRT02-A field.

All fourteen evidence-set references are closed structured records with exact
role, record type, path or explicit non-file state, current-attempt binding,
integrity observation, receipt, and availability. Projection rows are derived
from reopened sealed ledgers; callers cannot supply an alleged full row set.
Structural-review inputs contain only the sealed evidence-set reference and
authority `NONE`, so `MATCH`, `CLEAR`, and `COMPLETE` conclusions are derived
from reopened records. Timing and clock values use explicit `PRESENT` or
`UNKNOWN` state, including valid negative timing values without a sentinel.
Raw contract loading rejects duplicate keys before Tcl dictionary access.

A complete synthetic fixture can reach
`EVIDENCE_STRUCTURAL_REVIEW_COMPLETE`, but the controller then stops exactly
at `BLOCKED / POLICY_REVIEW /
PRODUCTION_POLICY_REVIEW_NOT_IMPLEMENTED / REVIEW`, with
`candidate_effect NOT_CREATED`. Evidence identity remains
`PENDING_IDENTITY_PROVIDER` or `UNAVAILABLE_WITH_REASON`. No finding is
dispositioned and no implementation-result candidate is created.

Actual Vivado 2024.1 report commands/options and output formats remain
unqualified. The production Collector entry therefore returns
`BLOCKED / TOOL_CAPABILITY /
ACTUAL_VIVADO_REPORT_COMMANDS_NOT_QUALIFIED / REPORT_COLLECTION` and invokes
zero report commands; only the closed test entry accepts
`FIXTURE_MODEL_VALIDATED`. Policy review, finding dispositions, final REPORT/MESSAGE
identity bindings, Host-to-Vivado integration, final production dependency closure,
backend identity v2 migration, authorization issue, Q0-Q5, Run2, artifact
generation/publication, hardware-manager use, and board access remain
unavailable. The backend remains `MOCK_ONLY / REVIEW_REQUIRED`, and the public
runtime path remains disconnected.

PRT02-E implements the disconnected Runtime Dependency Closure Foundation.
The machine-readable contracts under `../config/` declare exactly eight
ordered direct roles and ten ordered subordinate contracts across
`HOST_POWERSHELL`, `VIVADO_TCL`, and `HOST_POSTPROCESS_TCL`. They contain
source paths and interface declarations only: populated file digests are
prohibited, and neither a source identity nor a runtime-backend identity is
created.

The dependency tools under `../dependency/` use the PowerShell AST, a
conservative admitted-subset Tcl scanner, structured JSON/config/vendor
inspection, and three fresh-process non-Vivado safe-load scenarios. Their
review-candidate result is
`DISCONNECTED_CANDIDATE_CLOSURE_VALIDATED`, meaning the reviewed declaration
matches static discovery, the Tcl trace projections match exactly, and the
Host evidence is explicitly split into observed events and rehearsal. It is not a
final production pre-dispatch trace, and final production dependency closure
is not yet proven.

The final source-review amendments compare exact requester/target/edge/
provider/interface-command/interface-version/attempt/order/predicate
occurrences and emit every `ATTEMPTED` record before its module, source,
provider, or controlled-read action. Nested loads therefore retain parent
attempt, child pair, parent terminal chronology. PowerShell imports are
resolved semantically. Tcl command substitutions are scanned inside quoted
words while braced substitutions remain literal; every admitted `source` path
is structurally reduced from fixed `[info script]`, `file dirname`, `file
normalize`, and `file join` forms to one contained declared node. Dynamic,
conditional, environment-selected, wildcard, cwd-dependent, evaluator, and
source-time `exit` forms block.

Provider declarations bind an exact interface command. Static ownership proves
each contracted Tcl command has one fully-qualified proc definition and each
PowerShell command has one local effective module export from its declared
source; missing, duplicate, wrong-source, overwritten, ambient, or substituted
definitions block. JSON discovery resolves every local and external `$ref` to
one exact schema ID and complete JSON Pointer target, including escape and
canonical array-index validation. Duplicate-key and canonical-order rejection
remain enforced for JSON and Tcl-dictionary configuration. Host direct schema
reads that cannot be safely intercepted are kept in a separate
`DECLARED_ASSEMBLY_REHEARSAL`; they are not presented as an observed safe-load
trace and do not prove exact Host closure.

The direct `IDENTITY_SERIALIZER` interface owner is the PRT02-D serializer.
Its Tcl module is loaded process-locally in both the disconnected Vivado
Collector scenario and the disconnected Host/post-process scenario; no single
runtime instance is claimed to cross process boundaries. Canonicalization,
codec, hashing, and atomic publication remain subordinate process-local
library uses. The single `HASH_PROVIDER` contract is implemented by the
admitted canonical-JSON PowerShell and Tcl providers and is bootstrap-checked
against standard vectors and the independent platform SHA-256 implementation.
The accepted PowerShell primitive does not accept the empty mandatory-array
call, so the versioned E-owned `HASH_ADAPTER_POWERSHELL` supplies that public
review-only API without changing parameter metadata or accepted source. The
comparison is provider/API independent but may share the platform
cryptographic backend.
`source_check.tcl` is explicitly `HISTORICAL_NON_PRODUCTION` and is not
production-reachable.

The three pre-dispatch ledger validators derive Expected from the frozen
domain graph, reopen a sealed ledger and publication receipt, verify all eight
record fields plus identity bindings and byte integrity, and reject arbitrary
caller-supplied Expected/Actual arrays. They report
`PRE_DISPATCH_INTEGRATION_NOT_CONNECTED`; they are intentionally not wired to
the public runtime. The public A-to-B boundary, Host-to-Vivado launch, real
PRT02-D report-command path, identity/manifest creation, policy review,
authorization, Q0-Q5, Run2, artifact work, hardware-manager use, and board
access all remain unavailable. Vivado 2024.1 command and report qualification
is still required, and the backend remains `MOCK_ONLY / REVIEW_REQUIRED`.

PRT03 adds a connected non-Vivado assembly-readiness foundation. The only
selected public root is the append-only v2 script under `entrypoint/v2/`; the
accepted v1 entry point remains a protected PRT02-A input. The v2 interface
still accepts exactly `-RequestPath` and `-ExpectedRequestIdentity`, derives
the repository root from its own path, and exposes no fixture selector.

The independent PRT03 activation graph inventories 10 PRT03-owned production
sources and 23 exact dependency edges. It is a separate graph combined with a
validated reference to the accepted PRT02-E A-E graph; it does not claim to be
part of that accepted graph. Static discovery rejects missing, extra, dynamic,
undeclared, wrong-owner, wrong-interface, and alternate-root dependencies.

The selected Host assembly performs one natural root operation containing five
fixed child module imports. Attempts are recorded before action and terminals
after action, so the sealed Direct ledger contains 12 events and 6 terminal
records with non-adjacent parent chronology. Actual is sealed before Expected
is read from the PRT03 graph. The exact Direct state is
`PRT03_DIRECT_CONNECTED_ASSEMBLY_VALIDATED`; accepted A-E behavior is reported
separately as `AE_ACCEPTED_DISCONNECTED_CLOSURE_REFERENCED`, and unavailable
full live observation remains
`HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN`.

The internal non-Vivado fixture publishes one sealed PowerShell-to-Tcl handoff
for request, execution, attempt, source, workspace, evidence-root, and Host
result bindings. The accepted C command model, D evidence pipeline, and E
validators consume that one context. D marks the sealed Host result present,
and the final fixture result is derived only after sealed C, D, and E records
are reopened. The exact fixture binding state is
`HOST_C_D_E_BINDINGS_MATCH`; its terminal stop remains `BLOCKED /
POLICY_REVIEW / PRODUCTION_POLICY_REVIEW_NOT_IMPLEMENTED`, with no candidate.

The public path publishes a canonical no-overwrite structured activation-stop
record and SHA-256 receipt. The v1-compatible outer phase is `ENTRY_ASSEMBLY`;
the exact subphase is `ACTIVATION_PRECHECK`. The stop remains `BLOCKED /
IDENTITY_BINDING / RUNTIME_BACKEND_IDENTITY_V2_NOT_CREATED`, with authorization
`NOT_TOUCHED`, production process `NOT_STARTED`, and candidate `NOT_CREATED`.

The contract declares only the target capability
`PRODUCTION_IMPLEMENTED`. The Controller derives
`capability_candidate PRODUCTION_IMPLEMENTED` from 10 independent graph,
ledger, registry, protected-byte, bound-fixture, no-effect, and unavailable-live-
ledger conditions, with `review_state REVIEW_REQUIRED`. The final reviewed
execution report owns the resulting capability decision. Vivado and
post-process live ledgers remain unavailable, so
`FINAL_TOOL_BOUND_PRE_DISPATCH_CLOSURE_NOT_PROVEN`, blocked public dispatch,
and `RUN2_NOT_AUTHORIZED` remain mandatory. No PRT03 production source locates
or launches Vivado, freezes identities, consumes production authorization, or
performs qualification, candidate, artifact, hardware-manager, or board work.

PRT04 adds the Run2 source/runtime/policy/configuration freeze-review
candidate. It does not change any accepted PRT02 or PRT03 production source.
The candidate Runtime Backend Identity v2 contract is implemented by
`../lib/stage1e_runtime_backend_identity_v2.schema.json` and
`../identity/stage1e_runtime_backend_identity_v2.psm1`. It has exactly eight
ordered Direct Runtime roles, selects only the PRT03 Entry Point v2, and owns
exactly ten ordered subordinate contracts with 59 subordinate sources and 67
unique Direct-plus-subordinate sources. The FRAMEWORK manifest explicitly
binds `stage1e_phase3_implementation_framework_v3.dict` as
`FRAMEWORK_V3_CONTRACT` with the
`stage1e-phase3-implementation-framework-v3` interface. The manifest keeps
canonicalization, codec, hashing, atomic publication, Provider
registry, PRT02-E closure, and PRT03 activation as explicit child bindings;
`source_check.tcl` remains historical and unreachable.

The v2 candidate keeps source capability, runtime review, qualification, and
authorization as separate dimensions: `PRODUCTION_IMPLEMENTED /
REVIEW_REQUIRED / NOT_AVAILABLE / NONE`. PRT02-E remains
`DISCONNECTED_CANDIDATE_CLOSURE_VALIDATED`; PRT03 remains
`CONNECTED_RUNTIME_ASSEMBLY_READINESS_FOUNDATION`. Host full-transitive live
closure, Vivado and post-process pre-dispatch ledgers, and final tool-bound
closure remain unavailable. Consequently, `CURRENT_REVIEWED` is invalid for
this candidate and production dispatch remains blocked.

Policy, warning policy, configuration, and framework v3 are human-review
candidates only. They permit `opt_design`, `place_design`, `route_design`, and
read-only implementation reports. `phys_opt_design` is disabled, unauthorized,
sequence zero, directive `NONE`, invocation-prohibited, and requires property
readback plus a zero-invocation ledger. Incremental implementation, imported
checkpoints, fallback, artifact production/publication, hardware-manager use,
and board access remain prohibited.

The sole REPORT role authority is `stage1e_report_contract_v1.dict`, whose
exact ordered 20 roles use `CONDITIONAL_BUS_SKEW`. Parsed inventories and the
`OPERATION_LEDGER`/`REPORT_ATTEMPT_LEDGER` evidence ledgers are separate from
that role order.

The canonical Run1 inventory contains 19 findings and 17 unresolved human
decisions. No disposition is accepted automatically. The two exact
`Timing 38-436` phase rows and the two informational CDC rows are candidate
routes only; 13 findings remain evidence-insufficient and two require a fix.
Unknown and unresolved dispositions block.

Because all PRT04 bytes are uncommitted in this handoff, the freeze-review
candidate creates no source, runtime, policy, warning, configuration, review,
qualification, or authorization identity. The post-commit finalizer accepts
only `PREVIEW_ONLY`, requires an exact approved commit, empty Git porcelain,
the complete 19-path approved inventory, the committed execution-report hash,
33 suites/634 cases/zero failures, 106 protected sources/zero mismatches, and
a separate human-decision record, and can
write only to a new external evidence root. It never modifies repository
source, invokes Vivado, issues `CURRENT_REVIEWED`, or issues Q1. The next gate
is `HUMAN FREEZE REVIEW`.

PRT05 closes the authority-path semantic cycle without changing the 19-path
source inventory or granting authority in committed source. The Finalizer now
retains `PREVIEW_ONLY` and adds only the explicit
`ISSUE_SOURCE_FREEZE_REVIEW` and
`ISSUE_RUNTIME_REVIEW_AND_QUALIFICATION` modes. Q1 owns the immutable
`SOURCE_FREEZE_REVIEWED` record and leaves the backend `REVIEW_REQUIRED` with
qualification `NOT_AVAILABLE`. Q5, after exact Q2-Q4 and Host/Vivado/
post-process/final tool-bound evidence validates, owns the immutable Runtime
Review Record, Runtime Backend v2 `CURRENT_REVIEWED`, qualification identity
`QUALIFIED_AVAILABLE`, and terminal `QUALIFIED_NOT_AUTHORIZED` record.

The Runtime Backend v2 schema contains the internal authority, source-freeze,
live-evidence, Runtime-review, qualification, terminal, and atomic-envelope
contracts. Its PowerShell Provider exports canonical payload, digest,
validator, serializer, parser, and derived-construction functions. Committed
source checks require an explicitly bound literal Git executable. Production
records use strict UTF-8 without BOM, deterministic schema order, self-
excluding SHA-256 identities, create-new external publication, reopen
validation, and atomic directory rename. Q5 is one indivisible record set;
partial or overwrite publication fails closed.

Authority records distinguish source-freeze review, Q0-Q5 qualification,
Run2, and board scopes. Neither Q1 nor Q5 can authorize Run2. The default
committed state remains qualification execution unauthorized, Runtime review
`REVIEW_REQUIRED`, qualification `NOT_AVAILABLE`, and implementation,
artifact, publication, and board authority `NONE`. A new WP03 execution must
restart from Q0 after PRT05 review, commit, push, and regeneration of all
reviewed inputs; the blocked historical WP03 execution cannot be upgraded or
reused.
