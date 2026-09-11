# Stage 2H-B RTL architecture and module-boundary tradeoff

Date: 2026-08-08
Status: Stage 2H-B1 architecture audit complete; Stage 2H-B2 not started
Base: `601b0a07f3eb580b75c0f3b865cb6a910f706429`
Branch: `codex/stage2h-b1-rtl-architecture-module-boundary-audit`

## Outcome

The current production RTL has three duplicated mutable authorities worth
consolidating in Stage 2H-B2:

1. the legacy and Stage 2G AXI-Lite transport state machines;
2. destination sequence-integrity state in observability and protection; and
3. stalled source-offer integrity state in diagnostics and protection.

The first is a maintenance-risk reduction. The latter two remove cases where
production policy and observability can independently reach different answers
for the same transaction. All three targets are project-specific and small.
They preserve the packaged top, external ports, ABI 1.1, register semantics,
raw protection authority, three-cycle evaluation latency, clear fence, and
legacy compatibility path.

```text
SHARED_AXI_LITE_TRANSPORT=APPROVED
SINGLE_DESTINATION_SEQUENCE_STATE_AUTHORITY=APPROVED
SINGLE_SOURCE_PROTOCOL_STATE_AUTHORITY=APPROVED
ACLK_RESET_AUTHORITY=KEEP_CURRENT
FULL_STAGE2G_FILE_SPLIT_IN_B=NO_DEFER_TO_STAGE2H_C
ADC_CDC_BRIDGE_DEDUP_IN_B=DEFERRED
LEGACY_STAGE2G_CORE_UNIFICATION=REJECTED_OVERENGINEERING
LEGACY_STAGE2G_FSM_UNIFICATION=REJECTED_OVERENGINEERING
LEGACY_STAGE2G_CLASSIFIER_UNIFICATION=REJECTED_OVERENGINEERING
B2_RECOMMENDED_CHANGE_COUNT=3
GENERIC_RTL_FRAMEWORK_ADDED=NO
SYSTEMVERILOG_INTERFACE_MIGRATION_REQUIRED=NO
MODULE_RENAMING_REQUIRED=NO
EXTERNAL_PACKAGED_PORTS_CHANGE_REQUIRED=NO
PUBLIC_ABI_CHANGE_REQUIRED=NO
```

## Frozen boundary

```text
PRODUCTION_TOP=protection_ip_top_async_adc_axi_lite
PUBLIC_ABI=1.1
STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT
STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION
NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO
FAULT_EVAL_SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH
SUPPORTED_SEQUENCE_WIDTHS=16_TO_32
FAULT_EVALUATION_LATENCY_ACLK=3
CLEAR_PROTOCOL=REQUEST_EVALUATION_FENCED
PUBLIC_RECOVERY_COMPLETE=LATER_CLEAN_HEALTHY_EVALUATION_ENTERING_ARMED
LEGACY_COMPATIBILITY_PATH=SUPPORTED
STAGE2G_PRODUCTION_PATH=ABI_1_1_PATH
```

No B1 artifact changes functional RTL, generated register-map artifacts,
runtime software, public ABI, synthesis inputs, constraints, or board files.

## Production entrypoints

| Use | Repository authority | RTL entrypoint |
|---|---|---|
| Vivado project creation | `fpga/vivado/create_pynq_z2_project_stage1_boardpart.tcl` (`top_module`) and `fpga/vivado/create_pynq_z2_project_preboard.tcl` (`set_property top`) | `protection_ip_top_async_adc_axi_lite` |
| IP packaging | `fpga/vivado/package_protection_ip_stage2_axi_lite.tcl` | `protection_ip_top_async_adc_axi_lite` |
| Production Vivado runner | `fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl` during IP packaging | `protection_ip_top_async_adc_axi_lite` |
| Production system build | the same runner after block-design wrapper generation | `protection_system_wrapper`; the packaged IP inside it still uses `protection_ip_top_async_adc_axi_lite` |
| Production build configuration | `fpga/vivado/build/config/stage1e_phase2_synthesis_config_v1.dict` | `protection_ip_top_async_adc_axi_lite`, `DATA_WIDTH=12`, `OBS_SEQUENCE_WIDTH=32` |

Source-list inclusion is not production ownership. Vivado reads files that
also contain legacy modules, but only modules reachable from the selected top
belong to the production elaborated hierarchy.

## Actual production hierarchy

The default production configuration (`DATA_WIDTH=12`) elaborates:

```text
protection_ip_top_async_adc_axi_lite
|-- u_adc_source_reset_release_sync: reset_release_sync
|-- u_adc_sample_cdc_bridge: stage2g_adc_sample_cdc_bridge
|   |-- u_source_observer: transaction_source_observer
|   |-- u_source_integrity_tracker: stage2g_source_integrity_tracker
|   `-- u_fifo: async_fifo_gray
|-- g_stage2f_normalization_supported/u_adc_sample_code_normalizer:
|   adc_sample_code_normalizer
|-- u_source_observability_cdc: source_observability_cdc
|-- u_destination_observer: transaction_destination_observer
|   `-- u_sequence_classifier: stage2e_transaction_sequence_classifier
`-- u_destination_axi_lite: stage2g_protection_ip_axi_lite
    |-- u_reset_release_sync: reset_release_sync
    `-- u_reg_controlled_top: stage2g_protection_ip_reg_controlled
        |-- u_reg_bank: protection_reg_bank
        `-- u_core: stage2g_protection_core
            |-- u_sequence_classifier:
            |   stage2e_transaction_sequence_classifier
            |-- u_cmp: current_compare_dual
            |-- u_health: sensor_health_monitor
            |-- u_classifier: stage2g_fault_evaluation_pipeline
            |-- u_fsm: stage2g_fault_episode_controller
            |-- u_pwm: pwm_gen
            `-- u_gate: pwm_gate
```

For non-12-bit `DATA_WIDTH`, the normalizer instance is replaced by the
existing unsupported-width tie-off branch. That branch remains observational
and never gates raw protection policy.

## Module authority inventory

| Classification | Module | Responsibility |
|---|---|---|
| PRODUCTION | `protection_ip_top_async_adc_axi_lite` | Packaged boundary, source/destination composition, accepted raw destination delivery fanout |
| PRODUCTION | `stage2g_adc_sample_cdc_bridge` | Atomic raw CDC payload including source-integrity sideband |
| PRODUCTION | `stage2g_source_integrity_tracker` | Current independent source-offer integrity state; approved for consolidation |
| PRODUCTION | `adc_sample_code_normalizer` | Normalized telemetry fork only |
| PRODUCTION | `source_observability_cdc` | Gray diagnostic transfer into ACLK |
| PRODUCTION | `transaction_destination_observer` | Destination counters and sticky telemetry; currently also duplicate sequence state |
| PRODUCTION | `stage2g_protection_ip_axi_lite` | Production AXI wrapper; currently owns one duplicated transport implementation |
| PRODUCTION | `stage2g_protection_ip_reg_controlled` | ABI 1.1 register-bank to Stage 2G core composition |
| PRODUCTION | `stage2g_protection_core` | Raw capture, decision alignment, integrity attachment, policy pipeline composition |
| PRODUCTION | `stage2g_fault_evaluation_pipeline` | Registered raw fault evaluation result at latency offset 2 |
| PRODUCTION | `stage2g_fault_episode_controller` | Fault episode, clear fence, RESET_WAIT, compatibility state |
| SHARED | `reset_release_sync` | Fixed asynchronous-assert, two-edge synchronous release |
| SHARED | `transaction_source_observer` | Source sequence and diagnostic protocol/counter authority |
| SHARED | `async_fifo_gray` | FIFO pointer, memory, full/empty, and CDC transport authority |
| SHARED | `stage2e_transaction_sequence_classifier` | Combinational modulo sequence classification |
| SHARED | `protection_reg_bank` | Register controls, read mux, W1P/W1C behavior, ABI visibility |
| SHARED | `current_compare_dual` | Raw comparator and differential evaluation |
| SHARED | `sensor_health_monitor` | Raw sensor-health persistence state |
| SHARED | `pwm_gen` | PWM carrier state |
| SHARED | `pwm_gate` | Combinational fail-safe PWM gate |
| LEGACY_COMPATIBILITY | `adc_sample_cdc_bridge` | Stage 2D/2E payload without Stage 2G source-integrity bit |
| LEGACY_COMPATIBILITY | `protection_ip_top_axi_lite` | Legacy AXI/register/protection surface |
| LEGACY_COMPATIBILITY | `protection_ip_top_reg_controlled` | Legacy register-controlled composition |
| LEGACY_COMPATIBILITY | `protection_core_top` | Legacy protection pipeline |
| LEGACY_COMPATIBILITY | `fault_classifier` | Legacy registered fault-code classifier |
| LEGACY_COMPATIBILITY | `protection_fsm` | Legacy fault latch and recovery FSM |
| HISTORICAL_TEST_ONLY | `stage2g_transaction_source_observer` | Uninstantiated composition wrapper; referenced only by static Stage 2G inventory |
| HISTORICAL_TEST_ONLY | `moving_avg_filter` | Uninstantiated future enhancement; excluded from packaged IP |

## Duplicate mutable authority inventory

### AUTH_AXI_TRANSPORT

```text
AUTHORITY_ID=AUTH_AXI_TRANSPORT
CURRENT_IMPLEMENTATIONS=protection_ip_top_axi_lite,stage2g_protection_ip_axi_lite
STATE_OWNERS=wr_state,rd_state,AW/W holds,BVALID,RVALID,RDATA,register request registers in both modules
CONSUMERS=legacy register-controlled wrapper,Stage2G register-controlled wrapper
CAN_DIVERGE=YES
CURRENT_EQUIVALENCE_MECHANISM=manually mirrored RTL plus separate integration tests
CORRECTNESS_RISK=MEDIUM
MAINTENANCE_RISK=HIGH
REFACTOR_VALUE=HIGH
DECISION=APPROVED
```

The whole-module normalized token similarity is `97.0588%`. Restricting the
comparison to the AXI transport region, excluding the Stage 2G-only parameter
guard and different child instantiation, produces `745` tokens on each side
with `100.0000%` sequence similarity. Both modules independently implement
AW/W capture, conservative write-over-read arbitration, B response holding,
AR capture, R response holding, stall policy, and register request pulses.

The target is one `protection_axi_lite_register_transport` module, co-located
in `rtl/protection_ip_top_axi_lite.v` for B2. The two existing module names and
port lists remain as thin wrappers selecting their existing register-controlled
child. This avoids a Stage 2H-C source-layout change.

Smallest register-side contract:

| Signal | Direction from transport | Contract |
|---|---|---|
| `wr_en` | output | One ACLK pulse after a complete accepted AW/W pair; zero when `wstrb` is zero |
| `rd_en` | output | One ACLK pulse for each accepted AR request |
| `addr` | output | Byte address associated with the active register request |
| `wdata` | output | Held write data associated with `wr_en` |
| `wstrb` | output | Held write strobes associated with `wr_en` |
| `rdata` | input | Register-bank read data captured before asserting `RVALID` |

`ACLK` and the wrapper-owned synchronized local reset are transport control
inputs, not part of the register-side request contract. The wrappers retain
their current `reset_release_sync` instance and `local_resetn` output, so this
change does not move reset authority or alter release timing.

First-principles result:

```text
WHAT_REAL_FAILURE_OR_MAINTENANCE_RISK_DOES_IT_REMOVE=ONE_PATH_RECEIVING_AN_AXI_FIX_WHILE_THE_OTHER_RETAINS_OLD_PROTOCOL_OR_STALL_BEHAVIOR
IS_THE_RISK_ALREADY_ACCEPTABLY_COVERED=NO_SEPARATE_TESTS_DETECT_MANY_ERRORS_BUT_DO_NOT_REMOVE_DUAL_MAINTENANCE_AUTHORITY
DOES_THE_REFACTOR_REDUCE_NET_COMPLEXITY=YES_ONE_SMALL_EXISTING_POLICY_ADAPTER_REPLACES_TWO_COMPLETE_STATE_MACHINES
SHARED_AXI_LITE_TRANSPORT=APPROVED
```

### AUTH_DESTINATION_SEQUENCE_STATE

```text
AUTHORITY_ID=AUTH_DESTINATION_SEQUENCE_STATE
CURRENT_IMPLEMENTATIONS=transaction_destination_observer,stage2g_protection_core
STATE_OWNERS=expected_sequence/expected_sample_sequence,has_last_delivery/has_last_sample_delivery,last_destination_sequence/last_sample_sequence
CONSUMERS=destination observability counters and sticky state,Stage2G fault-policy integrity
CAN_DIVERGE=YES
CURRENT_EQUIVALENCE_MECHANISM=same accepted destination delivery,same reset,shared combinational classifier,explicit equivalence tests,duplicated sequential update logic
CORRECTNESS_RISK=HIGH
MAINTENANCE_RISK=HIGH
REFACTOR_VALUE=HIGH
DECISION=APPROVED
```

Both state owners reset to expected zero, no prior delivery, and last zero.
Both advance on the same accepted destination delivery. The observer advances on an expected
delivery or resynchronizes on a forward gap. The core performs the equivalent
update using `destination_sequence_clean || destination_sequence_gap`. Current
behavior is aligned, and `tb_stage2g_sequence_integrity_matrix` explicitly
compares Stage 2E and Stage 2G classification. The architecture nevertheless
allows a future edit to change one sequential owner without changing the
other. That is the same failure class as the historical first-nonzero/gap
policy-observability disagreement.

B2 should add one project-specific
`destination_sequence_integrity_tracker`, co-located in
`rtl/transaction_destination_observer.v`. It owns:

```text
expected_sequence
has_last_delivery
last_destination_sequence
```

Its transaction boundary is `delivery_valid` plus `delivery_sequence` from the
atomic raw CDC destination delivery, sampled in ACLK under `adc_dst_local_rst_n`. It uses
the existing `stage2e_transaction_sequence_classifier` and directly exposes:

```text
expected_delivery
duplicate_delivery
stale_first_delivery
sequence_gap
reorder_or_stale
sequence_delta
last_destination_sequence
```

The destination observer owns counters and W1C sticky telemetry only. The
Stage 2G protection path consumes the same-cycle `expected_delivery` decision
alongside the carried source-integrity bit; it does not consume counters,
sticky state, synchronized telemetry, or software-visible register state.

| Case | Classification | Expected-state update | Policy integrity |
|---|---|---|---|
| clean | `expected_delivery=1` | advance modulo `2**SEQUENCE_WIDTH` | clean if source integrity is also clean |
| first zero | clean | expected becomes one | clean if source integrity is also clean |
| first nonzero | `stale_first_delivery=1`, `reorder_or_stale=1` | retain zero; remember last delivery | dirty |
| duplicate | `duplicate_delivery=1` | retain expected | dirty |
| forward gap | `sequence_gap=1` | resynchronize to delivered plus one | dirty |
| stale/reorder | `reorder_or_stale=1` | retain expected | dirty |
| wrap | ordinary modulo equality and addition | max advances to zero | clean when expected; existing gap/stale half-range rule otherwise |

The tracker retains the current `16..32` width guard and asynchronous-assert
local reset semantics. Classification remains combinational for the delivered
transaction, so the fixed three-ACLK evaluation latency is unchanged.

First-principles result:

```text
WHAT_REAL_FAILURE_OR_MAINTENANCE_RISK_DOES_IT_REMOVE=POLICY_AND_OBSERVABILITY_CLASSIFYING_THE_SAME_DESTINATION_DELIVERY_FROM_DIFFERENT_MUTABLE_HISTORY
IS_THE_RISK_ALREADY_ACCEPTABLY_COVERED=NO_CURRENT_TESTS_ARE_STRONG_BUT_THE_HISTORICAL_DEFECT_AND_DUAL_STATE_MAKE_FUTURE_DIVERGENCE_A_REAL_RECURRING_RISK
DOES_THE_REFACTOR_REDUCE_NET_COMPLEXITY=YES_THREE_DUPLICATE_REGISTERS_AND_ONE_DUPLICATE_UPDATE_BLOCK_ARE_REMOVED_WITH_ONE_SMALL_TRACKER
SINGLE_DESTINATION_SEQUENCE_STATE_AUTHORITY=APPROVED
```

### AUTH_SOURCE_OFFER_PROTOCOL_STATE

```text
AUTHORITY_ID=AUTH_SOURCE_OFFER_PROTOCOL_STATE
CURRENT_IMPLEMENTATIONS=transaction_source_observer,stage2g_source_integrity_tracker
STATE_OWNERS=stall_pending,violation-recorded flag,stalled payload snapshot in both modules
CONSUMERS=source diagnostic counters and sticky telemetry,atomic FIFO source-integrity sideband consumed by policy
CAN_DIVERGE=YES
CURRENT_EQUIVALENCE_MECHANISM=same source signals and reset,separate Stage2E diagnostic tests,separate Stage2G dirty-offer policy tests
CORRECTNESS_RISK=HIGH
MAINTENANCE_RISK=MEDIUM_HIGH
REFACTOR_VALUE=HIGH
DECISION=APPROVED
```

The source observer already owns the complete stalled-offer protocol history.
The Stage 2G tracker repeats the same three state elements solely to produce a
transaction-carried clean/dirty bit. B2 should expose
`transaction_integrity_clean` from `transaction_source_observer`, computed
from its existing protocol state and current violation event. The Stage 2G
bridge samples that output into the accepted FIFO word. Its independent
`stage2g_source_integrity_tracker` production instance is removed.

Diagnostic counters remain diagnostic. Policy consumes only the direct
per-transaction integrity result from the shared protocol state; no counter,
sticky bit, CDC-decoded telemetry, or software-visible state gates policy.
The legacy bridge may leave the added output unconnected and retains all
existing behavior. The constraint-sensitive hierarchy
`u_adc_sample_cdc_bridge/u_source_observer` and its Gray registers remains
unchanged.

First-principles result:

```text
WHAT_REAL_FAILURE_OR_MAINTENANCE_RISK_DOES_IT_REMOVE=SOURCE_DIAGNOSTICS_AND_POLICY_ATTACHING_DIFFERENT_INTEGRITY_TO_THE_SAME_STALLED_OFFER
IS_THE_RISK_ALREADY_ACCEPTABLY_COVERED=NO_TESTS_COVER_EACH_RESULT_BUT_THERE_IS_NO_SINGLE_MUTABLE_PROTOCOL_AUTHORITY
DOES_THE_REFACTOR_REDUCE_NET_COMPLEXITY=YES_IT_REMOVES_THREE_DUPLICATE_REGISTERS_AND_THEIR_UPDATE_LOGIC_WITHOUT_A_NEW_FRAMEWORK
SINGLE_SOURCE_PROTOCOL_STATE_AUTHORITY=APPROVED
```

### AUTH_ADC_CDC_WRAPPER_ASSEMBLY

The complete legacy and Stage 2G bridge bodies have `93.2345%` normalized
token similarity. After removing only the intentional Stage 2G integrity-bit
declaration, packing/unpacking, and tracker instance, their common FIFO,
observer, last-delivery hold, ready/valid, and guard logic is `100.0000%`
similar.

This is not a reason to refactor in B. The mutable FIFO pointer/memory authority
is already shared in `async_fifo_gray`; source diagnostics are already shared
in `transaction_source_observer`. The remaining duplication is wrapper-level
payload assembly and last-delivery holding around intentionally different FIFO
payloads. A shared mode parameter or generic payload framework would touch
KEEP_HIERARCHY, the Stage 2D/2E compatibility bridge, exact constraint paths,
CDC proof boundaries, and multiple mature test suites for little net state
reduction.

```text
AUTHORITY_ID=AUTH_ADC_CDC_WRAPPER_ASSEMBLY
CURRENT_IMPLEMENTATIONS=adc_sample_cdc_bridge,stage2g_adc_sample_cdc_bridge
STATE_OWNERS=last_delivered_data_in_each_wrapper;FIFO_pointer_memory_and_status_state_already_shared_in_async_fifo_gray
CONSUMERS=Stage2D/Stage2E_compatibility_path,Stage2G_production_path
CAN_DIVERGE=YES
CURRENT_EQUIVALENCE_MECHANISM=shared_async_fifo_gray,shared_transaction_source_observer,narrow_hierarchy_constraints,and_directed_legacy_and_production_CDC_tests
CORRECTNESS_RISK=MEDIUM
MAINTENANCE_RISK=MEDIUM
REFACTOR_VALUE=LOW_AFTER_SHARED_FIFO_AND_SOURCE_STATE_ARE_ACCOUNTED_FOR
WHAT_REAL_FAILURE_OR_MAINTENANCE_RISK_DOES_IT_REMOVE=WRAPPER_READY_VALID_OR_LAST_DELIVERY_HOLD_DRIFT
IS_THE_RISK_ALREADY_ACCEPTABLY_COVERED=YES_FOR_B_THE_MUTABLE_FIFO_AUTHORITY_IS_SHARED_AND_BOTH_VARIANTS_HAVE_MATURE_CDC_TEST_AND_CONSTRAINT_BOUNDARIES
DOES_THE_REFACTOR_REDUCE_NET_COMPLEXITY=NO_NOT_WITHOUT_MODE_PARAMETERS_OR_A_GENERIC_PAYLOAD_WRAPPER
ADC_CDC_BRIDGE_DEDUP_IN_B=DEFERRED
```

## Reset-domain ownership audit

`ARESETN` has two legitimate clock-local release authorities:

1. `u_adc_source_reset_release_sync` releases the ADC source domain after two
   `adc_src_clk` edges.
2. `stage2g_protection_ip_axi_lite.u_reset_release_sync` releases the ACLK
   domain after two ACLK edges and exports `local_resetn` as
   `adc_dst_local_rst_n`.

Every ACLK-domain production consumer uses the second local reset: AXI state,
FIFO destination state, normalizer, observability CDC destination registers,
destination observer, register bank, Stage 2G capture/evaluation/controller
state, health monitor, and PWM generator. Reset assertion is asynchronous and
release is synchronized. Relative source/destination release remains
independent by clock domain, as required by the asynchronous FIFO.

The Stage 2D and Stage 2E XDC files constrain narrowly named FIFO pointer and
Gray observability paths. They do not depend on moving the ACLK reset
synchronizer to the production top. Existing reset verification directly
checks the AXI wrapper's two-edge release, request/response flushing, downstream
fanout, and reset-window transaction behavior.

Moving the synchronizer one hierarchy level upward would not remove a second
ACLK reset, add reuse, improve a constraint, or close an unverified release
gap. It would instead change hierarchy and static assumptions while preserving
the same net and semantics. B2's shared AXI transport leaves the synchronizer
in each external compatibility/production wrapper and feeds the resulting
local reset to the shared transport.

```text
ACLK_RESET_AUTHORITY=KEEP_CURRENT
RESET_RELEASE_SYNCHRONIZATION=ASYNC_ASSERT_TWO_ACLK_EDGE_SYNC_RELEASE
ACLK_LOCAL_RESET_COUNT_IN_PRODUCTION=1
MOVE_TO_PRODUCTION_TOP_BENEFIT_PROVEN=NO
```

## Mixed legacy and Stage 2G file ownership

| File | Mixed ownership | B-stage architecture consequence |
|---|---|---|
| `rtl/protection_ip_top_axi_lite.v` | legacy and Stage 2G AXI wrappers | Real duplicated transport authority; add the approved shared adapter in this file, but do not split every module |
| `rtl/protection_ip_top_reg_controlled.v` | legacy and Stage 2G composition wrappers | Different child/core contracts; source organization only |
| `rtl/protection_core_top.v` | legacy and Stage 2G cores | Materially different policy/integrity behavior; do not mode-parameterize |
| `rtl/protection_fsm.v` | legacy FSM and Stage 2G episode controller | Materially different clear/recovery semantics; do not unify |
| `rtl/fault_classifier.v` | legacy classifier and Stage 2G evaluation pipeline | Different metadata and timing contracts; do not unify |
| `rtl/adc_sample_cdc_bridge.v` | legacy and Stage 2G payload wrappers | Constraint-sensitive wrapper duplication; defer deduplication |
| `rtl/transaction_source_observer.v` | shared observer, Stage 2G integrity tracker, historical wrapper | Remove duplicate production state in B2; broad file layout remains Stage 2H-C |

Mixed source files are not themselves duplicate runtime hardware. A full split
would change many source lists, historical tests, static checks, and review
paths without reducing production mutable state. B2 may edit the existing
files only where needed for the three approved boundaries.

```text
FULL_STAGE2G_FILE_SPLIT_IN_B=NO_DEFER_TO_STAGE2H_C
```

## Overengineering dispositions

| Candidate | Disposition | Reason |
|---|---|---|
| SystemVerilog interface port bundling | REJECTED_OVERENGINEERING | No repeated connection defect justifies changing Verilog/Vivado boundaries and fixtures |
| Generic config/status bus | REJECTED_OVERENGINEERING | The project-specific register bank contract is explicit and stable |
| Generic pipeline abstraction | REJECTED_OVERENGINEERING | The three-edge raw evaluation pipeline has fixed semantic stages, not a reusable generic shape |
| Generic transaction framework | REJECTED_OVERENGINEERING | AXI transport and sequence classification need two small project-specific authorities |
| Full RTL module renaming | REJECTED_OVERENGINEERING | High binding/test churn with no behavior or state reduction |
| Removing `stage2g_*` names | REJECTED_OVERENGINEERING | Generation identity remains useful while compatibility modules coexist |
| Legacy/Stage 2G core unification | REJECTED_OVERENGINEERING | Different integrity, evaluation, episode, and compatibility semantics |
| Legacy/Stage 2G FSM unification | REJECTED_OVERENGINEERING | Mode parameters would hide distinct clear and recovery contracts |
| Legacy/Stage 2G classifier unification | REJECTED_OVERENGINEERING | Different registered outputs and transaction metadata |
| Whole `rtl/` reorganization | REJECTED_OVERENGINEERING_IN_B | Source/repository convergence belongs to Stage 2H-C |

## Stage 2H-A source-binding interaction

The live ABI source `spec/register_map.json` binds ten dynamic sources in
`stage2g_fault_episode_controller` and
`stage2g_fault_evaluation_pipeline`. The Stage 2H conformance contract also
checks their named `stage2g_protection_core.u_fsm` and `u_classifier`
connections.

| Proposed B2 change | Binding classification | Reason |
|---|---|---|
| Shared AXI-Lite transport | NO_BINDING_CHANGE | No bound policy module, signal, connection, offset, access, or reset value changes |
| Single destination sequence state | NO_BINDING_CHANGE | Evaluation outputs and controller connections remain in the same modules; only pre-evaluation integrity state moves |
| Single source protocol state | NO_BINDING_CHANGE | `fault_eval_integrity_clean` meaning is preserved; no bound source module or signal changes |
| ACLK reset authority kept | NO_BINDING_CHANGE | Bound clock/reset identity remains `ACLK` plus local active-low reset |
| CDC bridge dedup deferred | NO_BINDING_CHANGE | No implementation change |

No proposed B2 change reopens allocation, version, capabilities, register
reset, access policy, or software semantics. No Stage 2H-A metadata update is
required if B2 follows the co-located-module targets above.

## Minimum Stage 2H-B2 target

### B2-1 shared AXI-Lite transport

```text
FILES=rtl/protection_ip_top_axi_lite.v,affected AXI structural checks and tests
NEW_MODULE=protection_axi_lite_register_transport
REMOVED_DUPLICATE_LOGIC=one complete AW/W/B/AR/R/register-request state implementation
FROZEN_BEHAVIOR=all external ports,OKAY responses,conservative arbitration,request timing,WSTRB behavior,undefined address behavior,reset release
VERIFICATION_REQUIRED=existing legacy AXI stress plus Stage2G production wrapper transport parity
VERIFICATION_NOT_REQUIRED=new smoke-only suite,register allocation regeneration,full unrelated policy sweep,synthesis/timing/board
STAGE2H_A_BINDING_IMPACT=NO_BINDING_CHANGE
BUILD_SOURCE_LIST_IMPACT=NONE_MODULE_COLOCATED_IN_EXISTING_SOURCE
RISK=MEDIUM
```

### B2-2 single destination sequence state authority

```text
FILES=rtl/transaction_destination_observer.v,rtl/protection_ip_top_async_adc_axi_lite.v,rtl/protection_ip_top_axi_lite.v,rtl/protection_ip_top_reg_controlled.v,rtl/protection_core_top.v,affected Stage2E/Stage2G tests and static checks
NEW_MODULE=destination_sequence_integrity_tracker
REMOVED_DUPLICATE_STATE=stage2g_protection_core expected_sample_sequence,has_last_sample_delivery,last_sample_sequence and duplicate classifier instance/update logic
FROZEN_BEHAVIOR=modulo classification,16_TO_32 widths,accepted raw destination delivery authority,source AND destination integrity,three-cycle evaluation,clear fence,RESET_WAIT/public recovery
VERIFICATION_REQUIRED=fresh cross-width sequence and policy-observability agreement verification
VERIFICATION_NOT_REQUIRED=register allocation/version work,normalization tests unrelated to raw-path identity,synthesis/timing/board
STAGE2H_A_BINDING_IMPACT=NO_BINDING_CHANGE
BUILD_SOURCE_LIST_IMPACT=NONE_MODULE_COLOCATED_IN_EXISTING_SOURCE
RISK=MEDIUM_HIGH
```

### B2-3 single source offer-protocol state authority

```text
FILES=rtl/transaction_source_observer.v,rtl/adc_sample_cdc_bridge.v,affected Stage2E/Stage2G tests and static checks
NEW_MODULE=NONE_EXTEND_EXISTING_TRANSACTION_SOURCE_OBSERVER_AUTHORITY
REMOVED_DUPLICATE_STATE=stage2g_source_integrity_tracker stall_pending,violation_recorded,stall_payload_snapshot and update logic
FROZEN_BEHAVIOR=source sequence,counters,Gray paths,FIFO payload bit,dirty accepted-offer policy exclusion,legacy bridge behavior
VERIFICATION_REQUIRED=clean/stalled/mutated/dropped/accepted source episodes plus diagnostic-policy agreement and existing CDC source tests
VERIFICATION_NOT_REQUIRED=FIFO pointer redesign,XDC hierarchy change,register map work,synthesis/timing/board
STAGE2H_A_BINDING_IMPACT=NO_BINDING_CHANGE
BUILD_SOURCE_LIST_IMPACT=NONE
RISK=MEDIUM
```

## Future B2 verification boundary

Destination sequence consolidation requires fresh behavioral proof at
`SEQUENCE_WIDTH=16,24,32` for:

```text
clean stream
first zero
first nonzero
duplicate
forward gap and recovery
stale/reorder and recovery
modulo wrap
gap and duplicate across wrap
clear fence at and across wrap
RESET_WAIT qualification
policy and observability classification agreement
no latency change from destination delivery to evaluation/controller
```

Source protocol consolidation requires clean immediate acceptance, clean
stalled acceptance, one or multiple payload mutations during a stall, valid
withdrawal, eventual acceptance, reset during a stalled offer, diagnostic
counter/sticky agreement, and policy integrity agreement on the exact FIFO
word.

AXI transport consolidation must reuse the existing high-information tests:

```text
AW-before-W
W-before-AW
same-cycle AW/W
B backpressure
AR/R backpressure
read-vs-write conservative arbitration
reset with partial or outstanding requests/responses
WSTRB zero/nonzero semantics through the register bank
undefined address writes ignored and reads zero with OKAY response
legacy wrapper and Stage2G wrapper using the same adapter
```

The B2 proof boundary is directed RTL simulation and repository static checks
for the changed modules. A full XSim coverage rerun, synthesis, implementation,
timing, bitstream, or board run is not required solely by these architecture
changes. Existing broader suites may be reused when they are the cheapest
available proof, but B2 should not create a new low-information smoke family.

## Stage boundary dispositions

```text
DEFER_TO_STAGE2H_C=
  full Stage2G file split
  whole rtl directory organization
  source-list cleanup for uninstantiated compatibility modules
  broad module/file naming convergence

REJECTED_OVERENGINEERING=
  SystemVerilog interfaces
  generic config/status bus
  generic pipeline abstraction
  generic transaction framework
  full module renaming
  removal of stage2g names
  legacy/Stage2G core unification
  legacy/Stage2G FSM unification
  legacy/Stage2G classifier unification

NO_CHANGE_REQUIRED=
  packaged external top and ports
  public ABI 1.1 and register map
  register bank behavioral authority
  raw versus normalized policy boundary
  fault evaluation pipeline latency
  fault episode and clear protocol modules
  PWM generator and fail-safe gate
  async_fifo_gray implementation
  Stage2D/Stage2E CDC XDC authorities
```

## First-principles scope review

```text
FUNCTIONAL_RTL_MODIFIED_IN_B1=NO
GENERATED_REGISTER_ARTIFACTS_MODIFIED=NO
RUNTIME_SOFTWARE_MODIFIED=NO
PUBLIC_ABI_MODIFIED=NO
STAGE2H_B2_IMPLEMENTATION_STARTED=NO
SYNTHESIS_OR_IMPLEMENTATION_RUN=NO
TIMING_OR_BITSTREAM_OR_BOARD_WORK=NO
GENERIC_FRAMEWORK_PROPOSED=NO
ACCEPTED_CHANGES_REMOVE_REAL_DUPLICATE_MUTABLE_AUTHORITY=YES
ACCEPTED_CHANGES_REDUCE_NET_COMPLEXITY=YES
DEFERRED_OR_REJECTED_CHANGES_LACK_SUFFICIENT_NET_VALUE_IN_B=YES
MINIMUM_SUFFICIENT_ASSURANCE=PASS
NO_OVERENGINEERING=PASS
FIRST_PRINCIPLES_SCOPE_REVIEW=PASS
```
