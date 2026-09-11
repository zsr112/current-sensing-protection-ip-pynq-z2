# Stage 1E Phase 3 controller foundation v2.
#
# This append-only controller validates the controlled-runtime and v2 identity
# contracts. It cannot execute Q0-Q5, create or consume authorization, dispatch
# implementation, produce an implementation result, or grant downstream
# authority.

namespace eval ::stage1e::phase3_implementation_controller_v2 {
    variable framework_fields {
        schema_version
        framework_state
        boundary
        runtime_contract
        identity_schemas
        operation_contract
        validation_contract
        source_roles
    }
    variable required_source_roles {
        FRAMEWORK_V2
        RUNTIME_README
        RUNTIME_IDENTITY
        RUNTIME_SCHEMA
        RUNTIME_LAUNCHER
        RUNTIME_RUNNER
        RUNTIME_COLLECTOR
        RUNTIME_PARSER
        RUNTIME_OBSERVER
        CONTROLLER_V2
        ADAPTER_V2
        CONFIGURATION_V2
        WARNING_POLICY_V2
        IMPLEMENTATION_POLICY_V2
        TEST_SUPPORT
        STATIC_TESTS
        SCHEMA_TESTS
        NEGATIVE_TESTS
        MOCK_TESTS
        PROVENANCE_TESTS
        LAUNCHER_MOCK_TESTS
        REGRESSION_DRIVER
    }
}

proc ::stage1e::phase3_implementation_controller_v2::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E PHASE3_CONTROLLER_V2 $code] $message
}

proc ::stage1e::phase3_implementation_controller_v2::_require_dependencies {} {
    foreach command {
        ::stage1e::runtime_schema::require_exact_fields
        ::stage1e::runtime_schema::require_dictionary
        ::stage1e::runtime_schema::require_equal
        ::stage1e::runtime_schema::require_exact_list
        ::stage1e::runtime_schema::validate_effective_graph
        ::stage1e::runtime_schema::validate_runtime_backend_identity
        ::stage1e::runtime_schema::validate_policy_identity_v2
        ::stage1e::runtime_schema::validate_configuration_identity_v2
    } {
        if {![llength [info commands $command]]} {
            _raise DEPENDENCY_MISSING "Required command is unavailable: $command"
        }
    }
}

proc ::stage1e::phase3_implementation_controller_v2::validate_framework {
    framework
} {
    variable framework_fields
    variable required_source_roles
    _require_dependencies
    ::stage1e::runtime_schema::require_exact_fields $framework \
        $framework_fields {Phase 3 implementation framework v2}
    ::stage1e::runtime_schema::require_equal \
        stage1e-phase3-implementation-framework-v2 \
        [dict get $framework schema_version] {Framework schema}
    ::stage1e::runtime_schema::require_equal \
        FOUNDATION_ONLY_NOT_AUTHORIZED \
        [dict get $framework framework_state] {Framework state}

    set boundary [dict get $framework boundary]
    ::stage1e::runtime_schema::require_exact_fields $boundary {
        implementation_execution_authorized
        qualification_execution_authorized
        authorization_creation_authorized
        production_runtime_dispatch_available
        mock_runtime_dispatch_available
        artifact_authority
        board_authority
    } {Framework v2 boundary}
    foreach field {
        implementation_execution_authorized
        qualification_execution_authorized
        authorization_creation_authorized
        production_runtime_dispatch_available
    } {
        ::stage1e::runtime_schema::require_equal 0 \
            [dict get $boundary $field] "Framework boundary $field"
    }
    ::stage1e::runtime_schema::require_equal 1 \
        [dict get $boundary mock_runtime_dispatch_available] \
        {Framework mock runtime availability}
    foreach field {artifact_authority board_authority} {
        ::stage1e::runtime_schema::require_equal NONE \
            [dict get $boundary $field] "Framework boundary $field"
    }

    set runtime [dict get $framework runtime_contract]
    ::stage1e::runtime_schema::require_exact_fields $runtime {
        schema_version
        runtime_root
        launcher_mode
        runner_mode
        collector_mode
        parser_disposition_authority
        identity_authority
        observer_mode
        production_activation_state
    } {Framework v2 runtime contract}
    foreach {field expected} {
        schema_version stage1e-controlled-runtime-contract-v1
        runtime_root fpga/vivado/build/runtime
        launcher_mode MOCK_ONLY
        runner_mode MOCK_ONLY
        collector_mode MOCK_ONLY
        parser_disposition_authority NONE
        identity_authority SCHEMA_AND_SERIALIZATION_ONLY
        observer_mode MOCK_ONLY
        production_activation_state NOT_IMPLEMENTED
    } {
        ::stage1e::runtime_schema::require_equal $expected \
            [dict get $runtime $field] "Runtime contract $field"
    }

    set identities [dict get $framework identity_schemas]
    ::stage1e::runtime_schema::require_exact_fields $identities {
        runtime_backend_identity
        implementation_policy_identity
        implementation_configuration_identity
        execution_identity
        qualification_identity
        authorization_identity
    } {Framework v2 identity schemas}
    foreach {field expected} {
        runtime_backend_identity stage1e-runtime-backend-identity-v1
        implementation_policy_identity stage1e-implementation-policy-identity-v2
        implementation_configuration_identity stage1e-implementation-configuration-identity-v2
        execution_identity CREATED_BY_FUTURE_QUALIFICATION_ONLY
        qualification_identity CREATED_BY_FUTURE_Q0_Q5_ONLY
        authorization_identity CREATED_BY_SEPARATE_FUTURE_TASK_ONLY
    } {
        ::stage1e::runtime_schema::require_equal $expected \
            [dict get $identities $field] "Identity schema $field"
    }

    set operations [dict get $framework operation_contract]
    ::stage1e::runtime_schema::require_exact_fields $operations {
        allowed_operations
        forbidden_operations
        effective_step_graph
        effective_graph_readback_required
        configured_to_effective_mismatch_action
    } {Framework v2 operation contract}
    ::stage1e::runtime_schema::require_exact_list \
        [::stage1e::runtime_schema::allowed_operations] \
        [dict get $operations allowed_operations] \
        {Framework v2 allowed operations}
    ::stage1e::runtime_schema::require_exact_list \
        [::stage1e::runtime_schema::forbidden_operations] \
        [dict get $operations forbidden_operations] \
        {Framework v2 forbidden operations}
    ::stage1e::runtime_schema::validate_effective_graph \
        [dict get $operations effective_step_graph]
    ::stage1e::runtime_schema::require_equal 1 \
        [dict get $operations effective_graph_readback_required] \
        {Effective graph readback requirement}
    ::stage1e::runtime_schema::require_equal BLOCK \
        [dict get $operations configured_to_effective_mismatch_action] \
        {Effective graph mismatch action}

    set validation [dict get $framework validation_contract]
    ::stage1e::runtime_schema::require_exact_fields $validation {
        static_tests_required
        schema_tests_required
        negative_tests_required
        mock_runtime_tests_required
        provenance_tests_required
        vivado_invocation_allowed
    } {Framework v2 validation contract}
    foreach field {
        static_tests_required
        schema_tests_required
        negative_tests_required
        mock_runtime_tests_required
        provenance_tests_required
    } {
        ::stage1e::runtime_schema::require_equal 1 \
            [dict get $validation $field] "Validation contract $field"
    }
    ::stage1e::runtime_schema::require_equal 0 \
        [dict get $validation vivado_invocation_allowed] \
        {Validation contract Vivado boundary}

    set sources [dict get $framework source_roles]
    ::stage1e::runtime_schema::require_dictionary $sources \
        {Framework v2 source roles}
    ::stage1e::runtime_schema::require_exact_list \
        [lsort -dictionary $required_source_roles] \
        [lsort -dictionary [dict keys $sources]] \
        {Framework v2 source-role inventory}
    set seen_paths {}
    dict for {role path} $sources {
        if {[file pathtype $path] ne {relative} ||
            [lsearch -exact [file split [string map {\\ /} $path]] ..] >= 0} {
            _raise SOURCE_PATH_INVALID \
                "Framework source path is not repository relative: $path"
        }
        if {[lsearch -exact $seen_paths $path] >= 0} {
            _raise SOURCE_PATH_INVALID \
                "Framework source path is duplicated: $path"
        }
        lappend seen_paths $path
    }
    return 1
}

proc ::stage1e::phase3_implementation_controller_v2::load_framework {path} {
    _require_dependencies
    set framework [::stage1e::runtime_schema::read_dictionary $path]
    validate_framework $framework
    return $framework
}

proc ::stage1e::phase3_implementation_controller_v2::prepare_foundation {
    framework
    runtime_identity
    policy_identity
    configuration_identity
} {
    validate_framework $framework
    ::stage1e::runtime_schema::validate_runtime_backend_identity \
        $runtime_identity
    ::stage1e::runtime_schema::validate_policy_identity_v2 $policy_identity
    ::stage1e::runtime_schema::validate_configuration_identity_v2 \
        $configuration_identity

    set runtime_hash [dict get $runtime_identity identity_sha256]
    set policy_hash [dict get $policy_identity identity_sha256]
    ::stage1e::runtime_schema::require_equal $runtime_hash \
        [dict get $policy_identity runtime_backend_identity] \
        {Policy-to-runtime identity binding}
    ::stage1e::runtime_schema::require_equal $runtime_hash \
        [dict get $configuration_identity runtime_backend_identity] \
        {Configuration-to-runtime identity binding}
    ::stage1e::runtime_schema::require_equal $policy_hash \
        [dict get $configuration_identity policy_identity] \
        {Configuration-to-policy identity binding}
    foreach field {target part board_part} {
        ::stage1e::runtime_schema::require_equal \
            [dict get $policy_identity $field] \
            [dict get $configuration_identity $field] \
            "Policy-to-configuration binding $field"
    }

    return [dict create \
        schema_version stage1e-phase3-foundation-preparation-result-v2 \
        status FOUNDATION_READY_NOT_AUTHORIZED \
        runtime_backend_identity $runtime_hash \
        implementation_policy_identity $policy_hash \
        implementation_configuration_identity \
            [dict get $configuration_identity identity_sha256] \
        production_runtime_dispatch_available 0 \
        mock_runtime_dispatch_available 1 \
        qualification_identity NOT_CREATED \
        authorization_identity NOT_CREATED \
        implementation_execution_authorized 0 \
        implementation_result_identity NOT_CREATED \
        acceptance_decision NOT_APPLICABLE \
        artifact_authority NONE \
        board_authority NONE]
}
