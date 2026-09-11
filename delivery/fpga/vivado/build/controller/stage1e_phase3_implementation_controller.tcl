# Stage 1E Phase 3 controlled-implementation controller framework v1.
#
# This file is source-only and preparation-only. It validates declarative
# contracts, qualification and one-use authorization bindings, predecessor
# identity, evidence lifecycle, and synthetic post-run evidence. It provides
# no Vivado backend and cannot execute implementation, create FPGA artifacts,
# publish artifacts, or access a board.

namespace eval ::stage1e::phase3_implementation_controller {
    variable framework_schema_version \
        stage1e-phase3-implementation-framework-v1
    variable capability_schema_version \
        stage1e-implementation-capability-v1
    variable preparation_context_schema_version \
        stage1e-phase3-implementation-preparation-context-v1
    variable preparation_result_schema_version \
        stage1e-phase3-implementation-preparation-result-v1
    variable policy_identity_schema_version \
        stage1e-implementation-policy-identity-v1
    variable evidence_lifecycle_schema_version \
        stage1e-phase3-evidence-lifecycle-v1
    variable consumption_schema_version \
        stage1e-implementation-capability-consumption-v1
    variable review_bundle_schema_version \
        stage1e-implementation-review-bundle-v1
    variable synthesis_identity_schema_version \
        stage1e-synthesis-result-identity-v1
    variable implementation_result_schema_version \
        stage1e-implementation-result-identity-v1
    variable operation_order {
        opt_design
        place_design
        route_design
        implementation_reports
    }
    variable controller_phase_order {
        QUALIFICATION_CONSUMPTION
        AUTHORIZATION_VALIDATION
        SYNTHESIS_PREDECESSOR_VERIFICATION
        OPT_DESIGN
        PLACE_DESIGN
        ROUTE_DESIGN
        IMPLEMENTATION_REPORTS
        EVIDENCE_CLOSURE
        RESULT_IDENTITY_CANDIDATE
    }
    variable forbidden_operations {
        phys_opt_design
        power_opt_design
        write_bitstream
        write_hw_platform
        write_xsa
        export_hardware
        artifact_candidate_preparation
        artifact_collection
        artifact_publication
        open_hw_manager
        connect_hw_server
        program_hw_devices
        board_access
    }
    variable preparation_result_identity_fields {
        schema_version
        status
        execution_id
        source_identity
        workspace_identity
        environment_identity
        synthesis_result_identity
        qualification_identity
        implementation_authorization_identity
        implementation_policy_identity
        capability
        authorization_consume_state
        operation_plan
        phase_order
        evidence_lifecycle_identity
        implementation_execution_permitted
        runtime_dispatch_available
        artifact_authority
        board_authority
    }
    variable policy_identity_fields {
        schema_version
        policy_id
        policy_document
        vivado_version
        target
        part
        board_part
        canonical_policy_sha256
        effective_configuration_sha256
    }
    variable evidence_lifecycle_identity_fields {
        schema_version
        execution_id
        evidence_root_identity
        initial_state
        current_execution_only
        prior_execution_evidence_present
        preserve_on_failure
    }
    variable consumption_identity_fields {
        schema_version
        authorization_record_identity
        authorization_identity
        capability
        execution_id
        prior_state
        new_state
        consume_point
        evidence_identity
    }
    variable review_bundle_identity_fields {
        schema_version
        execution_id
        implementation_run_identity
        implementation_policy_identity
        timing_report_identity
        utilization_report_identity
        drc_identity
        methodology_identity
        checkpoint_identity
        warning_review_identity
        decision
        review_authority
    }
}

proc ::stage1e::phase3_implementation_controller::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E PHASE3_IMPLEMENTATION_CONTROLLER $code] $message
}

proc ::stage1e::phase3_implementation_controller::_require_dictionary {
    value
    label
} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise SCHEMA_INVALID "$label is not a dictionary: $dictionary_error"
    }
    return 1
}

proc ::stage1e::phase3_implementation_controller::_require_fields {
    record
    fields
    label
} {
    _require_dictionary $record $label
    foreach field $fields {
        if {![dict exists $record $field]} {
            _raise IDENTITY_INCOMPLETE "$label is missing field: $field"
        }
        if {[dict get $record $field] eq {}} {
            _raise IDENTITY_INCOMPLETE "$label has an empty field: $field"
        }
    }
    return 1
}

proc ::stage1e::phase3_implementation_controller::_require_exact_fields {
    record
    fields
    label
} {
    _require_fields $record $fields $label
    set actual [lsort -dictionary [dict keys $record]]
    set expected [lsort -dictionary $fields]
    if {$actual ne $expected} {
        _raise SCHEMA_INVALID \
            "$label fields differ: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::phase3_implementation_controller::_require_equal {
    expected
    actual
    label
} {
    if {$expected ne $actual} {
        _raise IDENTITY_MISMATCH \
            "$label mismatch: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::phase3_implementation_controller::_require_exact_list {
    expected
    actual
    label
} {
    set expected [list {*}$expected]
    set actual [list {*}$actual]
    if {$expected ne $actual} {
        _raise SCHEMA_INVALID \
            "$label differs: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::phase3_implementation_controller::_require_sha256 {
    value
    label
} {
    set value [string tolower $value]
    if {![regexp {^[0-9a-f]{64}$} $value] ||
        $value eq [string repeat 0 64]} {
        _raise IDENTITY_INVALID \
            "$label is not a non-placeholder SHA-256 identity."
    }
    return $value
}

proc ::stage1e::phase3_implementation_controller::_require_identity_value {
    value
    label
} {
    if {[string toupper $value] in {
        UNKNOWN
        MISSING
        STALE
        NOT_FROZEN
        NOT_PRODUCED
        NOT_APPLICABLE
    }} {
        _raise IDENTITY_INVALID "$label is a blocking identity value."
    }
    return [_require_sha256 $value $label]
}

proc ::stage1e::phase3_implementation_controller::_require_dependencies {} {
    foreach command {
        ::stage1d::source_check::sha256_text
        ::stage1e::artifact_closure_schema::validate_qualification_identity
        ::stage1e::artifact_closure_schema::validate_authorization_binding
        ::stage1e::artifact_closure_schema::validate_implementation_result
        ::stage1e::artifact_closure_schema::compute_identity
    } {
        if {![llength [info commands $command]]} {
            _raise DEPENDENCY_MISSING \
                "Required identity validator is unavailable: $command"
        }
    }
    return 1
}

proc ::stage1e::phase3_implementation_controller::_identity_payload {
    fields
    record
} {
    set payload {}
    foreach field $fields {
        if {![dict exists $record $field]} {
            _raise IDENTITY_INCOMPLETE \
                "Identity payload is missing field: $field"
        }
        append payload [list $field] {=} [list [dict get $record $field]] "\n"
    }
    return $payload
}

proc ::stage1e::phase3_implementation_controller::compute_identity {
    fields
    record
} {
    if {![llength [info commands ::stage1d::source_check::sha256_text]]} {
        _raise DEPENDENCY_MISSING \
            {Stage 1D source-check SHA-256 provider is unavailable.}
    }
    return [::stage1d::source_check::sha256_text \
        [_identity_payload $fields $record]]
}

proc ::stage1e::phase3_implementation_controller::_validate_identity_hash {
    fields
    record
    label
} {
    _require_fields $record {identity_sha256} $label
    set observed [_require_sha256 [dict get $record identity_sha256] \
        "$label identity_sha256"]
    set expected [compute_identity $fields $record]
    _require_equal $expected $observed "$label canonical identity"
    return $expected
}

proc ::stage1e::phase3_implementation_controller::_contract {
    framework
    name
} {
    if {![dict exists $framework $name]} {
        _raise SCHEMA_INVALID "Phase 3 framework lacks contract: $name"
    }
    set contract [dict get $framework $name]
    _require_dictionary $contract "Phase 3 contract $name"
    return $contract
}

proc ::stage1e::phase3_implementation_controller::validate_framework {
    framework
} {
    variable framework_schema_version
    variable capability_schema_version
    variable operation_order
    variable controller_phase_order
    variable forbidden_operations

    _require_exact_fields $framework {
        schema_version
        framework_identity
        authorization_boundary
        qualification_dependency
        capability_contract
        controller_contract
        adapter_contract
        identity_integration
        provenance_guard
        validation_contract
    } {Phase 3 framework}
    _require_equal $framework_schema_version [dict get $framework \
        schema_version] {Phase 3 framework schema_version}

    set identity [dict get $framework framework_identity]
    _require_exact_fields $identity {
        framework_id
        framework_status
        baseline_git_commit
        reference_synthesis_execution_id
        reference_synthesis_result_identity
        target
        part
        board_part
        vivado_version
        software_build
        ip_build
        hash_algorithm
    } {Phase 3 framework identity}
    _require_equal stage1e_phase3_implementation_framework_v1 \
        [dict get $identity framework_id] {Phase 3 framework identifier}
    _require_equal PREPARATION_ONLY [dict get $identity framework_status] \
        {Phase 3 framework status}
    if {![regexp -nocase {^[0-9a-f]{40}$} \
            [dict get $identity baseline_git_commit]]} {
        _raise IDENTITY_INVALID \
            {Phase 3 framework baseline is not a full Git commit.}
    }
    _require_sha256 [dict get $identity \
        reference_synthesis_result_identity] \
        {Reference synthesis result identity}
    _require_equal SHA256 [dict get $identity hash_algorithm] \
        {Phase 3 hash algorithm}

    set boundary [dict get $framework authorization_boundary]
    _require_exact_fields $boundary {
        schema_version
        preparation_only
        declaration_is_permission
        implementation_execution_authorized
        runtime_backend_present
        artifact_candidate_authorized
        artifact_collection_authorized
        artifact_publication_authorized
        bitstream_generation_authorized
        xsa_generation_authorized
        board_access_authorized
        downstream_authority
    } {Phase 3 authorization boundary}
    _require_equal 1 [dict get $boundary preparation_only] \
        {Phase 3 preparation-only boundary}
    foreach flag {
        declaration_is_permission
        implementation_execution_authorized
        runtime_backend_present
        artifact_candidate_authorized
        artifact_collection_authorized
        artifact_publication_authorized
        bitstream_generation_authorized
        xsa_generation_authorized
        board_access_authorized
    } {
        _require_equal 0 [dict get $boundary $flag] \
            "Phase 3 authorization boundary $flag"
    }
    _require_equal NONE [dict get $boundary downstream_authority] \
        {Phase 3 downstream authority}

    set qualification [dict get $framework qualification_dependency]
    _require_exact_fields $qualification {
        schema_version
        required_qualification_schema
        gate_order
        required_gate_result
        required_decision
        required_binding_fields
        missing_action
        stale_action
        mismatch_action
        unknown_action
    } {Phase 3 qualification dependency}
    _require_equal qualification_identity_v1 [dict get $qualification \
        required_qualification_schema] {Required qualification schema}
    _require_exact_list {Q0 Q1 Q2 Q3 Q4 Q5} \
        [dict get $qualification gate_order] {Qualification gate order}
    _require_equal PASS [dict get $qualification required_gate_result] \
        {Qualification gate result}
    _require_equal PASS [dict get $qualification required_decision] \
        {Qualification decision}
    _require_exact_list {
        qualification_identity
        execution_identity
        workspace_identity
        environment_identity
        source_identity
        synthesis_result_identity
    } [dict get $qualification required_binding_fields] \
        {Qualification binding fields}
    foreach action {missing_action stale_action mismatch_action unknown_action} {
        _require_equal BLOCK [dict get $qualification $action] \
            "Qualification fail-closed action $action"
    }

    set capability [dict get $framework capability_contract]
    _require_exact_fields $capability {
        schema_version
        capability
        contract_state
        allowed_operations
        forbidden_operations
        authorization_requirements
        consumption_policy
        fail_closed_rules
    } {IMPLEMENTATION capability contract}
    _require_equal $capability_schema_version [dict get $capability \
        schema_version] {IMPLEMENTATION capability schema}
    _require_equal IMPLEMENTATION [dict get $capability capability] \
        {Capability name}
    _require_equal DECLARED_NOT_GRANTED [dict get $capability contract_state] \
        {Capability contract state}
    set operations [dict get $capability allowed_operations]
    _require_exact_fields $operations $operation_order \
        {Allowed implementation operations}
    set expected_order 0
    foreach operation $operation_order {
        incr expected_order
        set definition [dict get $operations $operation]
        set required_fields {order producer_phase required_predecessor}
        if {$operation eq {implementation_reports}} {
            lappend required_fields reports
        }
        _require_exact_fields $definition $required_fields \
            "Implementation operation $operation"
        _require_equal $expected_order [dict get $definition order] \
            "Implementation operation order $operation"
        _require_equal PHASE3_IMPLEMENTATION [dict get $definition \
            producer_phase] "Implementation producer phase $operation"
        if {$operation eq {implementation_reports}} {
            _require_exact_list {
                TIMING_SUMMARY
                UTILIZATION
                DRC
                METHODOLOGY
                CLOCK_INTERACTION
                CONSTRAINT_COVERAGE
                MESSAGE_INVENTORY
            } [dict get $definition reports] \
                {Required implementation reports}
        }
    }
    _require_exact_list $forbidden_operations [dict get $capability \
        forbidden_operations] {Forbidden implementation operations}

    set requirements [dict get $capability authorization_requirements]
    _require_exact_fields $requirements {
        authorization_schema
        required_status
        required_capability
        required_consume_state
        required_binding_fields
        implementation_policy_schema
        run_schema
        wildcard_bindings_allowed
        external_override_allowed
    } {IMPLEMENTATION authorization requirements}
    _require_equal stage1e-implementation-authorization-binding-v1 \
        [dict get $requirements authorization_schema] \
        {Implementation authorization schema}
    _require_equal AUTHORIZED [dict get $requirements required_status] \
        {Implementation authorization status}
    _require_equal IMPLEMENTATION [dict get $requirements \
        required_capability] {Implementation authorization capability}
    _require_equal UNCONSUMED [dict get $requirements \
        required_consume_state] {Implementation authorization consume state}
    _require_exact_list [dict get $qualification required_binding_fields] \
        [dict get $requirements required_binding_fields] \
        {Implementation authorization binding fields}
    _require_equal stage1e-implementation-policy-identity-v1 \
        [dict get $requirements implementation_policy_schema] \
        {Implementation policy identity schema}
    _require_equal stage1e-implementation-run-identity-v1 \
        [dict get $requirements run_schema] \
        {Implementation run identity schema}
    foreach flag {wildcard_bindings_allowed external_override_allowed} {
        _require_equal 0 [dict get $requirements $flag] \
            "Implementation authorization $flag"
    }

    set consumption [dict get $capability consumption_policy]
    _require_exact_fields $consumption {
        schema_version
        initial_state
        final_state
        consume_point
        consumer
        atomic_transition_required
        consumption_evidence_required
        preparation_consumes_capability
        reuse_allowed
        retry_reuse_allowed
        consumed_or_unknown_action
    } {IMPLEMENTATION consumption policy}
    _require_equal UNCONSUMED [dict get $consumption initial_state] \
        {Implementation consumption initial state}
    _require_equal CONSUMED_ONCE [dict get $consumption final_state] \
        {Implementation consumption final state}
    _require_equal IMMEDIATELY_BEFORE_FIRST_ADAPTER_OPERATION \
        [dict get $consumption consume_point] \
        {Implementation capability consume point}
    _require_equal stage1e-implementation-capability-consumption-v1 \
        [dict get $consumption schema_version] \
        {Implementation consumption schema}
    _require_equal STAGE1E_PHASE3_CONTROLLER [dict get $consumption \
        consumer] {Implementation capability consumer}
    foreach flag {atomic_transition_required consumption_evidence_required} {
        _require_equal 1 [dict get $consumption $flag] \
            "Implementation consumption $flag"
    }
    foreach flag {
        preparation_consumes_capability
        reuse_allowed
        retry_reuse_allowed
    } {
        _require_equal 0 [dict get $consumption $flag] \
            "Implementation consumption $flag"
    }
    _require_equal BLOCK [dict get $consumption consumed_or_unknown_action] \
        {Consumed or unknown capability action}
    set fail_closed [dict get $capability fail_closed_rules]
    _require_exact_fields $fail_closed {
        missing_authorization
        stale_authorization
        mismatched_authorization
        unknown_authorization
        missing_qualification
        stale_qualification
        mismatched_qualification
        unknown_qualification
        missing_predecessor
        mismatched_predecessor
        out_of_order_operation
        unknown_operation
        forbidden_operation
        missing_evidence
        missing_hash
        capability_reuse
    } {IMPLEMENTATION fail-closed rules}
    dict for {rule action} $fail_closed {
        _require_equal BLOCK $action "Capability fail-closed rule $rule"
    }

    set controller [dict get $framework controller_contract]
    _require_exact_fields $controller {
        schema_version
        controller_source
        controller_source_sha256
        preparation_context_schema
        preparation_result_schema
        review_bundle_schema
        phase_order
        responsibilities
        evidence_lifecycle
        runtime_dispatch_available
        directly_authorizes_artifacts
        directly_authorizes_board_access
    } {Phase 3 controller contract}
    _require_sha256 [dict get $controller controller_source_sha256] \
        {Phase 3 controller source identity}
    _require_equal \
        fpga/vivado/build/controller/stage1e_phase3_implementation_controller.tcl \
        [dict get $controller controller_source] \
        {Phase 3 controller source path}
    _require_equal stage1e-phase3-implementation-preparation-context-v1 \
        [dict get $controller preparation_context_schema] \
        {Phase 3 preparation context schema}
    _require_equal stage1e-phase3-implementation-preparation-result-v1 \
        [dict get $controller preparation_result_schema] \
        {Phase 3 preparation result schema}
    _require_equal stage1e-implementation-review-bundle-v1 \
        [dict get $controller review_bundle_schema] \
        {Phase 3 review bundle schema}
    _require_exact_list $controller_phase_order [dict get $controller \
        phase_order] {Phase 3 controller phase order}
    _require_exact_list {
        CONSUME_QUALIFICATION_IDENTITY
        VALIDATE_IMPLEMENTATION_AUTHORIZATION
        ENFORCE_PHASE_ORDER
        VERIFY_SYNTHESIS_PREDECESSOR
        MANAGE_EVIDENCE_LIFECYCLE
        PRODUCE_IMPLEMENTATION_RESULT_IDENTITY_CANDIDATE
    } [dict get $controller responsibilities] \
        {Phase 3 controller responsibilities}
    set lifecycle [dict get $controller evidence_lifecycle]
    _require_exact_fields $lifecycle {
        schema_version
        required_initial_state
        current_execution_only
        preserve_on_failure
        partial_evidence_is_acceptance
        missing_or_stale_evidence_action
    } {Phase 3 evidence lifecycle contract}
    _require_equal EMPTY_ACCEPTED [dict get $lifecycle \
        required_initial_state] {Phase 3 evidence initial state}
    foreach flag {current_execution_only preserve_on_failure} {
        _require_equal 1 [dict get $lifecycle $flag] \
            "Phase 3 evidence lifecycle $flag"
    }
    _require_equal 0 [dict get $lifecycle partial_evidence_is_acceptance] \
        {Phase 3 partial-evidence acceptance boundary}
    _require_equal BLOCK [dict get $lifecycle \
        missing_or_stale_evidence_action] \
        {Phase 3 missing evidence action}
    foreach flag {
        runtime_dispatch_available
        directly_authorizes_artifacts
        directly_authorizes_board_access
    } {
        _require_equal 0 [dict get $controller $flag] \
            "Phase 3 controller $flag"
    }

    set adapter [dict get $framework adapter_contract]
    _require_exact_fields $adapter {
        schema_version
        adapter_source
        adapter_source_sha256
        request_schema
        result_schema
        operation_order
        required_return_fields
        terminal_statuses
        required_hash_roles
        acceptance_decision_owner
        adapter_acceptance_decision
        runtime_backend_present
        direct_vivado_invocation_allowed
        direct_artifact_authorization_allowed
        direct_board_authorization_allowed
    } {Implementation adapter contract}
    _require_sha256 [dict get $adapter adapter_source_sha256] \
        {Implementation adapter source identity}
    _require_equal fpga/vivado/build/adapters/stage1e_implementation.tcl \
        [dict get $adapter adapter_source] \
        {Implementation adapter source path}
    _require_equal stage1e-implementation-adapter-request-v1 \
        [dict get $adapter request_schema] \
        {Implementation adapter request schema}
    _require_equal stage1e-implementation-adapter-result-v1 \
        [dict get $adapter result_schema] \
        {Implementation adapter result schema}
    _require_exact_list $operation_order [dict get $adapter operation_order] \
        {Implementation adapter operation order}
    _require_exact_list {
        schema_version
        identity_sha256
        status
        execution_id
        synthesis_result_identity
        implementation_run_identity
        authorization_consumption
        operation_results
        evidence
        logs
        hashes
        acceptance_decision
        artifact_authority
        board_authority
    } [dict get $adapter required_return_fields] \
        {Implementation adapter return fields}
    _require_exact_list {COMPLETED FAILED BLOCKED} [dict get $adapter \
        terminal_statuses] {Implementation adapter terminal statuses}
    _require_exact_list {
        implementation_run
        timing_report
        utilization_report
        drc_report
        methodology_report
        checkpoint
        evidence_inventory
        logs_inventory
    } [dict get $adapter required_hash_roles] \
        {Implementation adapter hash roles}
    _require_equal CONTROLLER_AND_REVIEW_POLICY [dict get $adapter \
        acceptance_decision_owner] {Implementation acceptance owner}
    _require_equal NOT_OWNED [dict get $adapter \
        adapter_acceptance_decision] {Adapter acceptance boundary}
    foreach flag {
        runtime_backend_present
        direct_vivado_invocation_allowed
        direct_artifact_authorization_allowed
        direct_board_authorization_allowed
    } {
        _require_equal 0 [dict get $adapter $flag] \
            "Implementation adapter $flag"
    }

    set integration [dict get $framework identity_integration]
    _require_exact_fields $integration {
        schema_version
        predecessor_schema
        successor_schema
        same_execution_required
        same_source_required
        exact_synthesis_identity_required
        required_predecessor_fields
        required_result_fields
        required_result_acceptance_state
        historical_predecessor_substitution_allowed
        previous_retry_checkpoint_allowed
        reference_identity_is_runtime_predecessor
        mismatch_action
    } {Phase 3 identity integration}
    _require_equal stage1e-synthesis-result-identity-v1 \
        [dict get $integration predecessor_schema] \
        {Implementation predecessor schema}
    _require_equal stage1e-implementation-result-identity-v1 \
        [dict get $integration successor_schema] \
        {Implementation result schema}
    foreach flag {
        same_execution_required
        same_source_required
        exact_synthesis_identity_required
    } {
        _require_equal 1 [dict get $integration $flag] \
            "Phase 3 identity integration $flag"
    }
    foreach flag {
        historical_predecessor_substitution_allowed
        previous_retry_checkpoint_allowed
        reference_identity_is_runtime_predecessor
    } {
        _require_equal 0 [dict get $integration $flag] \
            "Phase 3 identity integration $flag"
    }
    _require_equal CANDIDATE [dict get $integration \
        required_result_acceptance_state] \
        {Implementation result acceptance state}
    _require_exact_list {
        schema_version
        identity_sha256
        execution_id
        acceptance_state
        source_identity_sha256
        run_name
        run_status
        top_module
        part
        board_part
    } [dict get $integration required_predecessor_fields] \
        {Synthesis predecessor fields}
    _require_exact_list {
        schema_version
        identity_sha256
        execution_id
        source_identity
        synthesis_result_identity
        implementation_run_identity
        implementation_policy_identity
        timing_report_identity
        utilization_report_identity
        drc_identity
        methodology_identity
        checkpoint_identity
        acceptance_state
    } [dict get $integration required_result_fields] \
        {Implementation result identity fields}
    _require_equal BLOCK [dict get $integration mismatch_action] \
        {Implementation identity mismatch action}

    set provenance [dict get $framework provenance_guard]
    _require_exact_fields $provenance {
        schema_version
        algorithm
        canonicalization
        sources
        missing_action
        mismatch_action
    } {Phase 3 provenance guard}
    _require_equal SHA256 [dict get $provenance algorithm] \
        {Phase 3 provenance algorithm}
    if {[dict size [dict get $provenance sources]] == 0} {
        _raise PROVENANCE_INCOMPLETE \
            {Phase 3 provenance source inventory is empty.}
    }
    dict for {path entry} [dict get $provenance sources] {
        _require_exact_fields $entry {role sha256} \
            "Phase 3 provenance source $path"
        _require_sha256 [dict get $entry sha256] \
            "Phase 3 provenance identity $path"
    }
    foreach action {missing_action mismatch_action} {
        _require_equal BLOCK [dict get $provenance $action] \
            "Phase 3 provenance $action"
    }
    foreach {contract_name path_field hash_field} {
        controller_contract controller_source controller_source_sha256
        adapter_contract adapter_source adapter_source_sha256
    } {
        set contract [dict get $framework $contract_name]
        set path [dict get $contract $path_field]
        if {![dict exists $provenance sources $path]} {
            _raise PROVENANCE_INCOMPLETE \
                "Phase 3 provenance omits contract source: $path"
        }
        _require_equal [string tolower [dict get $contract $hash_field]] \
            [string tolower [dict get $provenance sources $path sha256]] \
            "Phase 3 contract provenance binding $path"
    }

    set validation [dict get $framework validation_contract]
    _require_exact_fields $validation {
        schema_version
        required_suites
        unknown_or_missing_identity_action
        vivado_invocation_allowed
        implementation_execution_allowed
        artifact_generation_allowed
        board_access_allowed
    } {Phase 3 validation contract}
    foreach flag {
        vivado_invocation_allowed
        implementation_execution_allowed
        artifact_generation_allowed
        board_access_allowed
    } {
        _require_equal 0 [dict get $validation $flag] \
            "Phase 3 validation $flag"
    }
    _require_equal BLOCK [dict get $validation \
        unknown_or_missing_identity_action] \
        {Phase 3 unknown identity action}
    _require_exact_list {
        MARKDOWN_STRUCTURE
        TCL_SYNTAX
        CAPABILITY_SCHEMA
        CONTROLLER_CONTRACT
        ADAPTER_CONTRACT
        IDENTITY_BINDING
        FAIL_CLOSED_BEHAVIOR
        PROVENANCE_GUARD
        REGRESSION
    } [dict get $validation required_suites] \
        {Phase 3 validation suites}
    return 1
}

proc ::stage1e::phase3_implementation_controller::_validate_policy_identity {
    framework
    policy
} {
    variable policy_identity_schema_version
    variable policy_identity_fields
    _require_exact_fields $policy [linsert $policy_identity_fields 1 \
        identity_sha256] {Implementation policy identity}
    _require_equal $policy_identity_schema_version [dict get $policy \
        schema_version] {Implementation policy identity schema}
    foreach field {
        identity_sha256
        canonical_policy_sha256
        effective_configuration_sha256
    } {
        _require_identity_value [dict get $policy $field] \
            "Implementation policy $field"
    }
    set framework_identity [dict get $framework framework_identity]
    _require_equal stage1e_implementation_policy_v1 [dict get $policy \
        policy_id] {Implementation policy identifier}
    _require_equal docs/design/stage1e_implementation_policy_v1.md \
        [dict get $policy policy_document] {Implementation policy document}
    foreach field {vivado_version target part board_part} {
        _require_equal [dict get $framework_identity $field] \
            [dict get $policy $field] "Implementation policy $field"
    }
    set policy_path [dict get $policy policy_document]
    set policy_source [dict get $framework provenance_guard sources $policy_path]
    _require_equal [string tolower [dict get $policy_source sha256]] \
        [string tolower [dict get $policy canonical_policy_sha256]] \
        {Implementation policy source binding}
    _validate_identity_hash $policy_identity_fields $policy \
        {Implementation policy identity}
    return 1
}

proc ::stage1e::phase3_implementation_controller::_validate_evidence_lifecycle {
    evidence
    execution_id
} {
    variable evidence_lifecycle_schema_version
    variable evidence_lifecycle_identity_fields
    _require_exact_fields $evidence [linsert \
        $evidence_lifecycle_identity_fields 1 identity_sha256] \
        {Phase 3 evidence lifecycle}
    _require_equal $evidence_lifecycle_schema_version [dict get $evidence \
        schema_version] {Phase 3 evidence lifecycle schema}
    _require_equal $execution_id [dict get $evidence execution_id] \
        {Evidence lifecycle execution binding}
    _require_identity_value [dict get $evidence evidence_root_identity] \
        {Evidence root identity}
    _require_equal EMPTY_ACCEPTED [dict get $evidence initial_state] \
        {Evidence lifecycle initial state}
    _require_equal 1 [dict get $evidence current_execution_only] \
        {Evidence current-execution binding}
    _require_equal 0 [dict get $evidence prior_execution_evidence_present] \
        {Prior-execution evidence presence}
    _require_equal 1 [dict get $evidence preserve_on_failure] \
        {Evidence failure preservation}
    _validate_identity_hash $evidence_lifecycle_identity_fields $evidence \
        {Phase 3 evidence lifecycle}
    return 1
}

proc ::stage1e::phase3_implementation_controller::_validate_predecessor {
    framework
    predecessor
    execution_id
    source_identity
    synthesis_result_identity
} {
    variable synthesis_identity_schema_version
    set integration [dict get $framework identity_integration]
    _require_fields $predecessor [dict get $integration \
        required_predecessor_fields] {Synthesis predecessor}
    _require_equal $synthesis_identity_schema_version [dict get $predecessor \
        schema_version] {Synthesis predecessor schema}
    _require_identity_value [dict get $predecessor identity_sha256] \
        {Synthesis predecessor identity}
    _require_equal $synthesis_result_identity [string tolower \
        [dict get $predecessor identity_sha256]] \
        {Synthesis predecessor result binding}
    _require_equal $execution_id [dict get $predecessor execution_id] \
        {Synthesis predecessor execution binding}
    _require_equal $source_identity [string tolower [dict get $predecessor \
        source_identity_sha256]] {Synthesis predecessor source binding}
    _require_equal CANDIDATE [dict get $predecessor acceptance_state] \
        {Synthesis predecessor acceptance state}
    _require_equal synth_1 [dict get $predecessor run_name] \
        {Synthesis predecessor run name}
    _require_equal {synth_design Complete!} [dict get $predecessor run_status] \
        {Synthesis predecessor run status}
    set identity [dict get $framework framework_identity]
    foreach field {top_module part board_part} {
        set expected_field $field
        if {$field eq {top_module}} {
            set expected_field target
        }
        _require_equal [dict get $identity $expected_field] \
            [dict get $predecessor $field] \
            "Synthesis predecessor $field"
    }
    return 1
}

proc ::stage1e::phase3_implementation_controller::validate_preparation_context {
    artifact_framework
    phase3_framework
    context
} {
    variable preparation_context_schema_version
    _require_dependencies
    validate_framework $phase3_framework
    ::stage1e::artifact_closure_schema::validate_framework \
        $artifact_framework
    _require_exact_fields $context {
        schema_version
        execution_id
        source_identity
        workspace_identity
        environment_identity
        synthesis_predecessor
        qualification_identity
        implementation_authorization
        implementation_policy_identity
        evidence_lifecycle
    } {Phase 3 preparation context}
    _require_equal $preparation_context_schema_version [dict get $context \
        schema_version] {Phase 3 preparation context schema}
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {} ||
        [string toupper $execution_id] in {UNKNOWN MISSING STALE}} {
        _raise IDENTITY_INVALID \
            {Phase 3 preparation execution_id is missing or blocking.}
    }
    foreach field {source_identity workspace_identity environment_identity} {
        dict set context $field [_require_identity_value \
            [dict get $context $field] "Phase 3 context $field"]
    }

    set qualification [dict get $context qualification_identity]
    set authorization [dict get $context implementation_authorization]
    ::stage1e::artifact_closure_schema::validate_qualification_identity \
        $artifact_framework $qualification
    ::stage1e::artifact_closure_schema::validate_authorization_binding \
        $artifact_framework $qualification $authorization
    _require_equal $execution_id [dict get $qualification \
        execution_identity] {Qualification execution binding}
    foreach field {workspace_identity environment_identity source_identity} {
        _require_equal [dict get $context $field] [string tolower \
            [dict get $qualification $field]] \
            "Qualification context binding $field"
    }
    set synthesis_result_identity [string tolower [dict get $qualification \
        synthesis_result_identity]]
    _validate_predecessor $phase3_framework [dict get $context \
        synthesis_predecessor] $execution_id [dict get $context \
        source_identity] $synthesis_result_identity
    _validate_policy_identity $phase3_framework [dict get $context \
        implementation_policy_identity]
    _validate_evidence_lifecycle [dict get $context evidence_lifecycle] \
        $execution_id
    return 1
}

proc ::stage1e::phase3_implementation_controller::_operation_plan {
    framework
} {
    variable operation_order
    set plan {}
    foreach operation $operation_order {
        set definition [dict get $framework capability_contract \
            allowed_operations $operation]
        lappend plan [dict create \
            operation $operation \
            order [dict get $definition order] \
            producer_phase [dict get $definition producer_phase] \
            required_predecessor [dict get $definition \
                required_predecessor]]
    }
    return $plan
}

proc ::stage1e::phase3_implementation_controller::prepare {
    artifact_framework
    phase3_framework
    context
} {
    variable preparation_result_schema_version
    variable preparation_result_identity_fields
    variable controller_phase_order
    validate_preparation_context $artifact_framework $phase3_framework $context
    set qualification [dict get $context qualification_identity]
    set authorization [dict get $context implementation_authorization]
    set predecessor [dict get $context synthesis_predecessor]
    set result [dict create \
        schema_version $preparation_result_schema_version \
        status PREPARATION_VALIDATED_NOT_AUTHORIZED \
        execution_id [dict get $context execution_id] \
        source_identity [string tolower [dict get $context \
            source_identity]] \
        workspace_identity [string tolower [dict get $context \
            workspace_identity]] \
        environment_identity [string tolower [dict get $context \
            environment_identity]] \
        synthesis_result_identity [string tolower [dict get $predecessor \
            identity_sha256]] \
        qualification_identity [string tolower [dict get $qualification \
            identity_sha256]] \
        implementation_authorization_identity [string tolower \
            [dict get $authorization identity_sha256]] \
        implementation_policy_identity [string tolower [dict get $context \
            implementation_policy_identity identity_sha256]] \
        capability IMPLEMENTATION \
        authorization_consume_state UNCONSUMED \
        operation_plan [_operation_plan $phase3_framework] \
        phase_order $controller_phase_order \
        evidence_lifecycle_identity [string tolower [dict get $context \
            evidence_lifecycle identity_sha256]] \
        implementation_execution_permitted 0 \
        runtime_dispatch_available 0 \
        artifact_authority NONE \
        board_authority NONE]
    dict set result identity_sha256 \
        [compute_identity $preparation_result_identity_fields $result]
    return $result
}

proc ::stage1e::phase3_implementation_controller::_validate_preparation_result {
    framework
    result
} {
    variable preparation_result_schema_version
    variable preparation_result_identity_fields
    variable operation_order
    variable controller_phase_order
    _require_exact_fields $result [linsert \
        $preparation_result_identity_fields 1 identity_sha256] \
        {Phase 3 preparation result}
    _require_equal $preparation_result_schema_version [dict get $result \
        schema_version] {Phase 3 preparation result schema}
    _require_equal PREPARATION_VALIDATED_NOT_AUTHORIZED [dict get $result \
        status] {Phase 3 preparation result status}
    foreach field {
        identity_sha256
        source_identity
        workspace_identity
        environment_identity
        synthesis_result_identity
        qualification_identity
        implementation_authorization_identity
        implementation_policy_identity
        evidence_lifecycle_identity
    } {
        _require_identity_value [dict get $result $field] \
            "Phase 3 preparation result $field"
    }
    _require_equal IMPLEMENTATION [dict get $result capability] \
        {Phase 3 preparation capability}
    _require_equal UNCONSUMED [dict get $result \
        authorization_consume_state] \
        {Phase 3 preparation authorization consume state}
    set actual_operations {}
    foreach entry [dict get $result operation_plan] {
        _require_exact_fields $entry {
            operation order producer_phase required_predecessor
        } {Phase 3 operation-plan entry}
        lappend actual_operations [dict get $entry operation]
    }
    _require_exact_list $operation_order $actual_operations \
        {Phase 3 preparation operation order}
    _require_exact_list $controller_phase_order [dict get $result phase_order] \
        {Phase 3 preparation phase order}
    foreach flag {implementation_execution_permitted runtime_dispatch_available} {
        _require_equal 0 [dict get $result $flag] \
            "Phase 3 preparation result $flag"
    }
    foreach field {artifact_authority board_authority} {
        _require_equal NONE [dict get $result $field] \
            "Phase 3 preparation result $field"
    }
    _validate_identity_hash $preparation_result_identity_fields $result \
        {Phase 3 preparation result}
    return 1
}

proc ::stage1e::phase3_implementation_controller::_validate_consumption {
    framework
    preparation_result
    record
} {
    variable consumption_schema_version
    variable consumption_identity_fields
    _require_exact_fields $record [linsert $consumption_identity_fields 1 \
        identity_sha256] {IMPLEMENTATION capability consumption}
    _require_equal $consumption_schema_version [dict get $record \
        schema_version] {IMPLEMENTATION consumption schema}
    _require_equal [dict get $preparation_result \
        implementation_authorization_identity] [string tolower \
        [dict get $record authorization_record_identity]] \
        {IMPLEMENTATION consumption authorization record binding}
    _require_identity_value [dict get $record authorization_identity] \
        {IMPLEMENTATION consumption authorization identity}
    _require_equal IMPLEMENTATION [dict get $record capability] \
        {IMPLEMENTATION consumption capability}
    _require_equal [dict get $preparation_result execution_id] [dict get \
        $record execution_id] {IMPLEMENTATION consumption execution binding}
    set policy [dict get $framework capability_contract consumption_policy]
    _require_equal [dict get $policy initial_state] [dict get $record \
        prior_state] {IMPLEMENTATION consumption prior state}
    _require_equal [dict get $policy final_state] [dict get $record new_state] \
        {IMPLEMENTATION consumption new state}
    _require_equal [dict get $policy consume_point] [dict get $record \
        consume_point] {IMPLEMENTATION consumption point}
    _require_identity_value [dict get $record evidence_identity] \
        {IMPLEMENTATION consumption evidence identity}
    _validate_identity_hash $consumption_identity_fields $record \
        {IMPLEMENTATION capability consumption}
    return 1
}

proc ::stage1e::phase3_implementation_controller::_validate_review_bundle {
    preparation_result
    adapter_result
    review
} {
    variable review_bundle_schema_version
    variable review_bundle_identity_fields
    _require_exact_fields $review [linsert $review_bundle_identity_fields 1 \
        identity_sha256] {Implementation review bundle}
    _require_equal $review_bundle_schema_version [dict get $review \
        schema_version] {Implementation review bundle schema}
    _require_equal [dict get $preparation_result execution_id] [dict get \
        $review execution_id] {Implementation review execution binding}
    foreach field {
        identity_sha256
        implementation_run_identity
        implementation_policy_identity
        timing_report_identity
        utilization_report_identity
        drc_identity
        methodology_identity
        checkpoint_identity
        warning_review_identity
    } {
        _require_identity_value [dict get $review $field] \
            "Implementation review $field"
    }
    _require_equal [dict get $preparation_result \
        implementation_policy_identity] [string tolower [dict get $review \
        implementation_policy_identity]] \
        {Implementation review policy binding}
    set bindings {
        implementation_run_identity implementation_run
        timing_report_identity timing_report
        utilization_report_identity utilization_report
        drc_identity drc_report
        methodology_identity methodology_report
        checkpoint_identity checkpoint
    }
    foreach {review_field hash_role} $bindings {
        _require_equal [string tolower [dict get $adapter_result hashes \
            $hash_role]] [string tolower [dict get $review $review_field]] \
            "Implementation review adapter binding $review_field"
    }
    _require_equal PASS [dict get $review decision] \
        {Implementation review decision}
    if {[string trim [dict get $review review_authority]] eq {} ||
        [string toupper [dict get $review review_authority]] in {
            UNKNOWN MISSING STALE NOT_ASSIGNED
        }} {
        _raise IDENTITY_INVALID \
            {Implementation review authority is missing or blocking.}
    }
    _validate_identity_hash $review_bundle_identity_fields $review \
        {Implementation review bundle}
    return 1
}

proc ::stage1e::phase3_implementation_controller::produce_implementation_result_identity_candidate {
    artifact_framework
    phase3_framework
    preparation_result
    adapter_result
    review_bundle
} {
    variable implementation_result_schema_version
    _require_dependencies
    validate_framework $phase3_framework
    _validate_preparation_result $phase3_framework $preparation_result
    if {![llength [info commands \
            ::stage1e::implementation::validate_result]]} {
        _raise DEPENDENCY_MISSING \
            {Stage 1E implementation adapter validator is unavailable.}
    }
    ::stage1e::implementation::validate_result $phase3_framework \
        $adapter_result
    _require_equal COMPLETED [dict get $adapter_result status] \
        {Implementation adapter completion status}
    _require_equal [dict get $preparation_result execution_id] \
        [dict get $adapter_result execution_id] \
        {Implementation adapter execution binding}
    _require_equal [dict get $preparation_result \
        synthesis_result_identity] [string tolower [dict get $adapter_result \
        synthesis_result_identity]] \
        {Implementation adapter synthesis binding}
    _validate_consumption $phase3_framework $preparation_result \
        [dict get $adapter_result authorization_consumption]
    _validate_review_bundle $preparation_result $adapter_result $review_bundle

    set contract [dict get $artifact_framework \
        implementation_result_contract]
    set result [dict create \
        schema_version $implementation_result_schema_version \
        execution_id [dict get $preparation_result execution_id] \
        source_identity [dict get $preparation_result source_identity] \
        synthesis_result_identity [dict get $preparation_result \
            synthesis_result_identity] \
        implementation_run_identity [string tolower [dict get $review_bundle \
            implementation_run_identity]] \
        implementation_policy_identity [string tolower [dict get \
            $review_bundle implementation_policy_identity]] \
        timing_report_identity [string tolower [dict get $review_bundle \
            timing_report_identity]] \
        utilization_report_identity [string tolower [dict get $review_bundle \
            utilization_report_identity]] \
        drc_identity [string tolower [dict get $review_bundle drc_identity]] \
        methodology_identity [string tolower [dict get $review_bundle \
            methodology_identity]] \
        checkpoint_identity [string tolower [dict get $review_bundle \
            checkpoint_identity]] \
        acceptance_state CANDIDATE]
    dict set result identity_sha256 \
        [::stage1e::artifact_closure_schema::compute_identity \
            $contract $result]
    ::stage1e::artifact_closure_schema::validate_implementation_result \
        $artifact_framework $result
    return $result
}

proc ::stage1e::phase3_implementation_controller::validate_provenance {
    repository_root
    framework
} {
    _require_dependencies
    validate_framework $framework
    return [::stage1e::artifact_closure_schema::validate_provenance \
        $repository_root $framework]
}
