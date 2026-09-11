# Stage 1E implementation report collector interface v1.
#
# The collector invokes injected mock callbacks and records every attempt. It
# neither executes Vivado report commands nor waives findings or missing data.

namespace eval ::stage1e::runtime_collector {
    variable report_roles {
        TIMING_SUMMARY
        UTILIZATION
        DRC
        METHODOLOGY
        CLOCK_INTERACTION
        CONSTRAINT_COVERAGE
        MESSAGE_INVENTORY
        TIMING_EXCEPTION_INVENTORY
        EFFECTIVE_GRAPH_READBACK
    }
    variable request_fields {
        schema_version
        mode
        runtime_backend_identity
        execution_binding
        report_roles
        callbacks
        artifact_authority
        board_authority
    }
    variable result_fields {status path sha256 bytes message}
}

proc ::stage1e::runtime_collector::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E RUNTIME_COLLECTOR $code] $message
}

proc ::stage1e::runtime_collector::report_roles {} {
    variable report_roles
    return $report_roles
}

proc ::stage1e::runtime_collector::validate_request {request} {
    variable request_fields
    variable report_roles
    ::stage1e::runtime_schema::require_exact_fields $request $request_fields \
        {Runtime collector request}
    if {[dict get $request schema_version] ne \
            {stage1e-runtime-collector-request-v1}} {
        _raise SCHEMA_INVALID {Runtime collector request schema mismatch.}
    }
    if {[dict get $request mode] ne {MOCK_ONLY}} {
        _raise DISPATCH_UNAVAILABLE \
            {Production report collection is unavailable.}
    }
    foreach field {runtime_backend_identity execution_binding} {
        ::stage1e::runtime_schema::require_identity [dict get $request $field] \
            "Runtime collector $field"
    }
    ::stage1e::runtime_schema::require_exact_list $report_roles \
        [dict get $request report_roles] {Runtime collector report roles}
    ::stage1e::runtime_schema::require_exact_fields \
        [dict get $request callbacks] $report_roles \
        {Runtime collector callbacks}
    foreach field {artifact_authority board_authority} {
        if {[dict get $request $field] ne {NONE}} {
            _raise AUTHORITY_INVALID "Runtime collector $field must be NONE."
        }
    }
    return 1
}

proc ::stage1e::runtime_collector::collect_mock {request} {
    variable result_fields
    validate_request $request
    set ledger {}
    set reports {}
    set ordinal 0
    set terminal_status COMPLETED
    foreach role [dict get $request report_roles] {
        incr ordinal
        set callback [dict get $request callbacks $role]
        set callback_status [catch {
            uplevel #0 [list {*}$callback $role $request]
        } result callback_options]
        if {$callback_status != 0} {
            set result [dict create status FAILED path NONE \
                sha256 NONE bytes 0 message $result]
        } else {
            ::stage1e::runtime_schema::require_exact_fields $result \
                $result_fields "Mock report result for $role"
        }
        set status [dict get $result status]
        if {$status ni {COLLECTED FAILED MISSING}} {
            _raise RESULT_INVALID "Invalid report status for $role: $status"
        }
        if {$status eq {COLLECTED}} {
            ::stage1e::runtime_schema::require_identity \
                [dict get $result sha256] "Mock report identity for $role"
        } else {
            set terminal_status FAILED
        }
        dict set reports $role $result
        lappend ledger [dict create ordinal $ordinal role $role \
            status $status path [dict get $result path] \
            sha256 [dict get $result sha256] \
            message [dict get $result message] \
            execution_binding [dict get $request execution_binding] \
            runtime_backend_identity \
                [dict get $request runtime_backend_identity]]
    }
    return [dict create \
        schema_version stage1e-runtime-collector-result-v1 \
        mode MOCK_ONLY \
        status $terminal_status \
        reports $reports \
        report_ledger $ledger \
        waiver_decision NOT_OWNED \
        acceptance_decision NOT_OWNED \
        artifact_authority NONE \
        board_authority NONE]
}
