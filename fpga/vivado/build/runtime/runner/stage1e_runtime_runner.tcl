# Stage 1E controlled runtime runner v1.
#
# Only mock callback dispatch is present. This module does not invoke Vivado,
# consume authorization, broaden the operation graph, or decide acceptance.

namespace eval ::stage1e::runtime_runner {
    variable request_fields {
        schema_version
        mode
        runtime_backend_identity
        policy_identity
        configuration_identity
        authorization_state
        operation_order
        effective_step_graph
        callbacks
        artifact_authority
        board_authority
    }
    variable callback_result_fields {status evidence logs hashes}
}

proc ::stage1e::runtime_runner::_raise {code message} {
    return -code error -errorcode [list STAGE1E RUNTIME_RUNNER $code] $message
}

proc ::stage1e::runtime_runner::_require_dependencies {} {
    foreach command {
        ::stage1e::runtime_schema::require_exact_fields
        ::stage1e::runtime_schema::require_exact_list
        ::stage1e::runtime_schema::require_identity
        ::stage1e::runtime_schema::validate_effective_graph
    } {
        if {![llength [info commands $command]]} {
            _raise DEPENDENCY_MISSING "Required command is unavailable: $command"
        }
    }
}

proc ::stage1e::runtime_runner::validate_request {request} {
    variable request_fields
    _require_dependencies
    ::stage1e::runtime_schema::require_exact_fields $request $request_fields \
        {Runtime runner request}
    if {[dict get $request schema_version] ne \
            {stage1e-runtime-runner-request-v1}} {
        _raise SCHEMA_INVALID {Runtime runner request schema mismatch.}
    }
    if {[dict get $request mode] ne {MOCK_ONLY}} {
        _raise DISPATCH_UNAVAILABLE \
            {Production implementation dispatch is unavailable.}
    }
    if {[dict get $request authorization_state] ne \
            {NOT_APPLICABLE_MOCK}} {
        _raise AUTHORITY_INVALID \
            {The mock runner does not consume or represent authorization.}
    }
    foreach field {
        runtime_backend_identity policy_identity configuration_identity
    } {
        ::stage1e::runtime_schema::require_identity [dict get $request $field] \
            "Runtime runner $field"
    }
    set operations [::stage1e::runtime_schema::allowed_operations]
    ::stage1e::runtime_schema::require_exact_list $operations \
        [dict get $request operation_order] {Runtime runner operation order}
    ::stage1e::runtime_schema::validate_effective_graph \
        [dict get $request effective_step_graph]
    set callbacks [dict get $request callbacks]
    ::stage1e::runtime_schema::require_exact_fields $callbacks $operations \
        {Runtime runner callbacks}
    foreach operation $operations {
        if {![llength [dict get $callbacks $operation]]} {
            _raise CALLBACK_INVALID "Empty callback for operation: $operation"
        }
    }
    foreach field {artifact_authority board_authority} {
        if {[dict get $request $field] ne {NONE}} {
            _raise AUTHORITY_INVALID "Runtime runner $field must be NONE."
        }
    }
    return 1
}

proc ::stage1e::runtime_runner::run_mock {request} {
    variable callback_result_fields
    validate_request $request
    set operation_results {}
    set terminal_status COMPLETED
    foreach operation [dict get $request operation_order] {
        set callback [dict get $request callbacks $operation]
        set callback_status [catch {
            uplevel #0 [list {*}$callback $operation $request]
        } result callback_options]
        if {$callback_status != 0} {
            dict set operation_results $operation [dict create \
                status FAILED evidence {} logs {} hashes {} \
                failure_message $result]
            set terminal_status FAILED
            break
        }
        ::stage1e::runtime_schema::require_exact_fields $result \
            $callback_result_fields "Mock result for $operation"
        set status [dict get $result status]
        if {$status ni {COMPLETED FAILED BLOCKED}} {
            _raise RESULT_INVALID "Invalid mock status for $operation: $status"
        }
        dict set operation_results $operation $result
        if {$status ne {COMPLETED}} {
            set terminal_status $status
            break
        }
    }
    return [dict create \
        schema_version stage1e-runtime-runner-result-v1 \
        mode MOCK_ONLY \
        status $terminal_status \
        operation_results $operation_results \
        authorization_consumption NOT_OWNED \
        acceptance_decision NOT_OWNED \
        artifact_authority NONE \
        board_authority NONE]
}
