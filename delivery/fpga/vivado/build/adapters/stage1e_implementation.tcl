# Stage 1E implementation adapter contract framework v1.
#
# This source-only adapter defines request/result shapes for the ordered
# implementation operations. It intentionally contains no runtime backend.
# It can prepare an inert request and validate externally supplied evidence,
# but it cannot execute a tool operation or make an acceptance decision.

namespace eval ::stage1e::implementation {
    variable request_schema_version stage1e-implementation-adapter-request-v1
    variable result_schema_version stage1e-implementation-adapter-result-v1
    variable consumption_schema_version \
        stage1e-implementation-capability-consumption-v1
    variable operation_order {
        opt_design
        place_design
        route_design
        implementation_reports
    }
    variable request_identity_fields {
        schema_version
        status
        execution_id
        synthesis_result_identity
        authorization_record_identity
        capability
        operation_order
        runtime_backend
        execution_permitted
        acceptance_decision
        artifact_authority
        board_authority
    }
    variable result_identity_fields {
        schema_version
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
    variable evidence_roles {
        operation_evidence
        report_evidence
        authorization_consumption_evidence
    }
    variable log_roles {
        implementation_log
        message_inventory
        controller_trace
    }
    variable hash_roles {
        implementation_run
        timing_report
        utilization_report
        drc_report
        methodology_report
        checkpoint
        evidence_inventory
        logs_inventory
    }
}

proc ::stage1e::implementation::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E IMPLEMENTATION_ADAPTER $code] $message
}

proc ::stage1e::implementation::_require_dictionary {value label} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise SCHEMA_INVALID "$label is not a dictionary: $dictionary_error"
    }
    return 1
}

proc ::stage1e::implementation::_require_fields {record fields label} {
    _require_dictionary $record $label
    foreach field $fields {
        if {![dict exists $record $field]} {
            _raise CONTRACT_INCOMPLETE "$label is missing field: $field"
        }
        if {[dict get $record $field] eq {}} {
            _raise CONTRACT_INCOMPLETE "$label has an empty field: $field"
        }
    }
    return 1
}

proc ::stage1e::implementation::_require_exact_fields {
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

proc ::stage1e::implementation::_require_equal {expected actual label} {
    if {$expected ne $actual} {
        _raise CONTRACT_MISMATCH \
            "$label mismatch: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::implementation::_require_exact_list {
    expected
    actual
    label
} {
    set expected [list {*}$expected]
    set actual [list {*}$actual]
    if {$expected ne $actual} {
        _raise CONTRACT_MISMATCH \
            "$label differs: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::implementation::_require_sha256 {value label} {
    set value [string tolower $value]
    if {![regexp {^[0-9a-f]{64}$} $value] ||
        $value eq [string repeat 0 64]} {
        _raise IDENTITY_INVALID \
            "$label is not a non-placeholder SHA-256 identity."
    }
    return $value
}

proc ::stage1e::implementation::_identity_payload {fields record} {
    set payload {}
    foreach field $fields {
        if {![dict exists $record $field]} {
            _raise CONTRACT_INCOMPLETE \
                "Identity payload is missing field: $field"
        }
        append payload [list $field] {=} [list [dict get $record $field]] "\n"
    }
    return $payload
}

proc ::stage1e::implementation::compute_identity {fields record} {
    if {![llength [info commands ::stage1d::source_check::sha256_text]]} {
        _raise DEPENDENCY_MISSING \
            {Stage 1D source-check SHA-256 provider is unavailable.}
    }
    return [::stage1d::source_check::sha256_text \
        [_identity_payload $fields $record]]
}

proc ::stage1e::implementation::_validate_identity_hash {
    fields
    record
    label
} {
    _require_fields $record {identity_sha256} $label
    set actual [_require_sha256 [dict get $record identity_sha256] \
        "$label identity_sha256"]
    set expected [compute_identity $fields $record]
    _require_equal $expected $actual "$label canonical identity"
    return $expected
}

proc ::stage1e::implementation::prepare_request {
    phase3_framework
    preparation_result
} {
    variable request_schema_version
    variable request_identity_fields
    variable operation_order
    if {![llength [info commands \
            ::stage1e::phase3_implementation_controller::_validate_preparation_result]]} {
        _raise DEPENDENCY_MISSING \
            {Stage 1E Phase 3 controller validator is unavailable.}
    }
    ::stage1e::phase3_implementation_controller::_validate_preparation_result \
        $phase3_framework $preparation_result
    set request [dict create \
        schema_version $request_schema_version \
        status PREPARED_NOT_EXECUTED \
        execution_id [dict get $preparation_result execution_id] \
        synthesis_result_identity [dict get $preparation_result \
            synthesis_result_identity] \
        authorization_record_identity [dict get $preparation_result \
            implementation_authorization_identity] \
        capability IMPLEMENTATION \
        operation_order $operation_order \
        runtime_backend ABSENT \
        execution_permitted 0 \
        acceptance_decision NOT_OWNED \
        artifact_authority NONE \
        board_authority NONE]
    dict set request identity_sha256 \
        [compute_identity $request_identity_fields $request]
    return $request
}

proc ::stage1e::implementation::validate_request {
    phase3_framework
    request
} {
    variable request_schema_version
    variable request_identity_fields
    variable operation_order
    _require_exact_fields $request [linsert $request_identity_fields 1 \
        identity_sha256] {Implementation adapter request}
    _require_equal $request_schema_version [dict get $request \
        schema_version] {Implementation adapter request schema}
    _require_equal PREPARED_NOT_EXECUTED [dict get $request status] \
        {Implementation adapter request status}
    foreach field {
        identity_sha256
        synthesis_result_identity
        authorization_record_identity
    } {
        _require_sha256 [dict get $request $field] \
            "Implementation adapter request $field"
    }
    _require_equal IMPLEMENTATION [dict get $request capability] \
        {Implementation adapter request capability}
    _require_exact_list $operation_order [dict get $request operation_order] \
        {Implementation adapter request operation order}
    _require_equal ABSENT [dict get $request runtime_backend] \
        {Implementation adapter runtime backend}
    _require_equal 0 [dict get $request execution_permitted] \
        {Implementation adapter execution permission}
    _require_equal NOT_OWNED [dict get $request acceptance_decision] \
        {Implementation adapter acceptance boundary}
    foreach field {artifact_authority board_authority} {
        _require_equal NONE [dict get $request $field] \
            "Implementation adapter request $field"
    }
    _validate_identity_hash $request_identity_fields $request \
        {Implementation adapter request}
    return 1
}

proc ::stage1e::implementation::_validate_consumption_shape {record} {
    variable consumption_schema_version
    variable consumption_identity_fields
    _require_exact_fields $record [linsert $consumption_identity_fields 1 \
        identity_sha256] {Implementation authorization consumption}
    _require_equal $consumption_schema_version [dict get $record \
        schema_version] {Implementation authorization consumption schema}
    foreach field {
        identity_sha256
        authorization_record_identity
        authorization_identity
        evidence_identity
    } {
        _require_sha256 [dict get $record $field] \
            "Implementation authorization consumption $field"
    }
    _require_equal IMPLEMENTATION [dict get $record capability] \
        {Implementation authorization consumption capability}
    if {[dict get $record prior_state] ni {UNCONSUMED CONSUMED_ONCE} ||
        [dict get $record new_state] ni {UNCONSUMED CONSUMED_ONCE}} {
        _raise CONTRACT_MISMATCH \
            {Implementation authorization consumption has an unknown state.}
    }
    _require_equal IMMEDIATELY_BEFORE_FIRST_ADAPTER_OPERATION \
        [dict get $record consume_point] \
        {Implementation authorization consumption point}
    _validate_identity_hash $consumption_identity_fields $record \
        {Implementation authorization consumption}
    return 1
}

proc ::stage1e::implementation::_validate_operation_results {
    result_status
    operation_results
} {
    variable operation_order
    _require_dictionary $operation_results \
        {Implementation adapter operation results}
    _require_exact_list $operation_order [dict keys $operation_results] \
        {Implementation adapter result phase order}
    set failure_seen 0
    foreach operation $operation_order {
        set result [dict get $operation_results $operation]
        _require_exact_fields $result {
            status
            evidence_identity
            log_identity
            hash_identity
        } "Implementation operation result $operation"
        if {[dict get $result status] ni {
                COMPLETED FAILED BLOCKED NOT_RUN
            }} {
            _raise CONTRACT_MISMATCH \
                "Implementation operation $operation has an unknown status."
        }
        foreach field {evidence_identity log_identity hash_identity} {
            _require_sha256 [dict get $result $field] \
                "Implementation operation $operation $field"
        }
        if {$failure_seen && [dict get $result status] ne {NOT_RUN}} {
            _raise PHASE_ORDER_INVALID \
                "Implementation operation $operation ran after a stop result."
        }
        if {[dict get $result status] in {FAILED BLOCKED}} {
            set failure_seen 1
        }
    }
    if {$result_status eq {COMPLETED}} {
        foreach operation $operation_order {
            _require_equal COMPLETED [dict get $operation_results $operation \
                status] "Completed adapter result operation $operation"
        }
    } elseif {!$failure_seen} {
        _raise CONTRACT_MISMATCH \
            {Non-completed adapter result lacks a failed or blocked phase.}
    }
    return 1
}

proc ::stage1e::implementation::_validate_identity_dictionary {
    dictionary
    roles
    label
} {
    _require_exact_fields $dictionary $roles $label
    foreach role $roles {
        _require_sha256 [dict get $dictionary $role] "$label $role"
    }
    return 1
}

proc ::stage1e::implementation::validate_result {
    phase3_framework
    result
} {
    variable result_schema_version
    variable result_identity_fields
    variable evidence_roles
    variable log_roles
    variable hash_roles
    if {![llength [info commands \
            ::stage1e::phase3_implementation_controller::validate_framework]]} {
        _raise DEPENDENCY_MISSING \
            {Stage 1E Phase 3 framework validator is unavailable.}
    }
    ::stage1e::phase3_implementation_controller::validate_framework \
        $phase3_framework
    set required_fields [dict get $phase3_framework adapter_contract \
        required_return_fields]
    _require_exact_fields $result $required_fields \
        {Implementation adapter result}
    _require_equal $result_schema_version [dict get $result schema_version] \
        {Implementation adapter result schema}
    if {[dict get $result status] ni [dict get $phase3_framework \
            adapter_contract terminal_statuses]} {
        _raise CONTRACT_MISMATCH \
            {Implementation adapter result has an unknown terminal status.}
    }
    foreach field {
        identity_sha256
        synthesis_result_identity
        implementation_run_identity
    } {
        _require_sha256 [dict get $result $field] \
            "Implementation adapter result $field"
    }
    if {[string trim [dict get $result execution_id]] eq {} ||
        [string toupper [dict get $result execution_id]] in {
            UNKNOWN MISSING STALE
        }} {
        _raise IDENTITY_INVALID \
            {Implementation adapter execution_id is missing or blocking.}
    }
    _validate_consumption_shape [dict get $result \
        authorization_consumption]
    _validate_operation_results [dict get $result status] [dict get $result \
        operation_results]
    _validate_identity_dictionary [dict get $result evidence] \
        $evidence_roles {Implementation adapter evidence}
    _validate_identity_dictionary [dict get $result logs] \
        $log_roles {Implementation adapter logs}
    _require_exact_list $hash_roles [dict get $phase3_framework adapter_contract \
        required_hash_roles] {Implementation adapter hash-role contract}
    _validate_identity_dictionary [dict get $result hashes] \
        $hash_roles {Implementation adapter hashes}
    _require_equal [string tolower [dict get $result \
        implementation_run_identity]] [string tolower [dict get $result \
        hashes implementation_run]] \
        {Implementation adapter run hash binding}
    _require_equal [string tolower [dict get $result \
        authorization_consumption evidence_identity]] [string tolower \
        [dict get $result evidence authorization_consumption_evidence]] \
        {Implementation adapter consumption evidence binding}
    _require_equal [::stage1d::source_check::sha256_text \
        [dict get $result evidence]] [string tolower [dict get $result \
        hashes evidence_inventory]] \
        {Implementation adapter evidence inventory hash}
    _require_equal [::stage1d::source_check::sha256_text \
        [dict get $result logs]] [string tolower [dict get $result \
        hashes logs_inventory]] \
        {Implementation adapter logs inventory hash}
    _require_equal NOT_OWNED [dict get $result acceptance_decision] \
        {Implementation adapter acceptance decision}
    foreach field {artifact_authority board_authority} {
        _require_equal NONE [dict get $result $field] \
            "Implementation adapter $field"
    }
    _validate_identity_hash $result_identity_fields $result \
        {Implementation adapter result}
    return 1
}

proc ::stage1e::implementation::normalize_result {
    phase3_framework
    result
} {
    validate_result $phase3_framework $result
    return [dict create \
        status [dict get $result status] \
        evidence [dict get $result evidence] \
        logs [dict get $result logs] \
        hashes [dict get $result hashes]]
}
