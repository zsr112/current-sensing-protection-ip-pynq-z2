# Stage 1E PRT02-C staged Project Mode runner candidate v1.
#
# This is the only PRT02-C source that can reach the reviewed Project Mode
# scheduling primitives. It never issues a direct implementation operation,
# never creates or resets a run, and never issues a report command.

set ::stage1e_production_vivado_runner_root \
    [file dirname [file normalize [info script]]]
if {![llength [info commands \
        ::stage1e::vivado_runtime_contract_v1::validate_phase_request]]} {
    source [file join $::stage1e_production_vivado_runner_root .. .. lib \
        stage1e_vivado_runtime_contract_v1.tcl]
}
unset ::stage1e_production_vivado_runner_root

namespace eval ::stage1e::production_vivado_runner_v1 {
    variable interface_version stage1e-production-vivado-runner-interface-v1
}

proc ::stage1e::production_vivado_runner_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_vivado_runner_v1::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E PRT02C VIVADO_RUNNER $code] $message
}

proc ::stage1e::production_vivado_runner_v1::_receipt_for_request {
    request path expected_identity
} {
    set receipt [::stage1e::vivado_runtime_contract_v1::read_receipt $path]
    ::stage1e::vivado_runtime_contract_v1::require_equal $expected_identity \
        [dict get $receipt receipt_identity] {Runner receipt identity}
    foreach field {
        request_identity execution_id attempt_id source_identity
        runtime_backend_identity policy_identity configuration_identity
        qualification_identity environment_identity workspace_identity
        synthesis_result_identity
    } {
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            [dict get $request $field] [dict get $receipt $field] \
            "Runner receipt binding $field"
    }
    set authorization [dict get $request authorization]
    foreach field {
        authorization_identity allowed_operation_contract_identity
        forbidden_operation_contract_identity
    } {
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            [dict get $authorization $field] [dict get $receipt $field] \
            "Runner receipt authorization binding $field"
    }
    ::stage1e::vivado_runtime_contract_v1::require_equal CONSUMED_ONCE \
        [dict get $receipt consumption_state] {Runner receipt state}
    return $receipt
}

proc ::stage1e::production_vivado_runner_v1::_entry_template {
    sequence operation predecessor target scheduler receipt_reference
} {
    set entry [dict create \
        sequence $sequence \
        logical_operation $operation \
        exact_predecessor $predecessor \
        target_step $target \
        controller_decision_reference NONE \
        authorization_receipt_reference $receipt_reference \
        phase_status NOT_RUN \
        scheduler_mechanism $scheduler \
        run_name impl_1 \
        start_observation NONE \
        end_observation NONE \
        native_state_before NONE \
        native_state_after NONE \
        timeout_state NOT_STARTED \
        observer_snapshot_references {} \
        forbidden_operation_result NOT_EVALUATED \
        failure_references {} \
        launch_attempts 0 \
        wait_attempts 0 \
        open_attempts 0 \
        retry_count 0]
    ::stage1e::vivado_runtime_contract_v1::require_record \
        operation_ledger_entry $entry
    return $entry
}

proc ::stage1e::production_vivado_runner_v1::initialize_ledger {
    request receipt
} {
    ::stage1e::vivado_runtime_contract_v1::validate_controller_request $request
    ::stage1e::vivado_runtime_contract_v1::validate_receipt $receipt
    set receipt_reference \
        [::stage1e::vivado_runtime_contract_v1::receipt_reference $receipt]
    set entries [list \
        [_entry_template 1 opt_design synthesis opt_design \
            STAGED_PROJECT_MODE_IMPL_1 $receipt_reference] \
        [_entry_template 2 place_design opt_design place_design \
            STAGED_PROJECT_MODE_IMPL_1 $receipt_reference] \
        [_entry_template 3 route_design place_design route_design \
            STAGED_PROJECT_MODE_IMPL_1 $receipt_reference] \
        [_entry_template 4 implementation_reports route_design route_design \
            COLLECTOR_HANDOFF_ONLY $receipt_reference]]
    set ledger [dict create \
        schema_version stage1e-vivado-operation-ledger-v1 \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        session_id [dict get $request session_context session_id] \
        dispatch_mechanism STAGED_PROJECT_MODE_IMPL_1 \
        authorization_receipt_reference $receipt_reference \
        entries $entries \
        immutable_state IMMUTABLE_APPEND_ONLY \
        retry_count 0 \
        mixed_mechanism_state NONE \
        terminal_state ACTIVE]
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    return $ledger
}

proc ::stage1e::production_vivado_runner_v1::_phase_contract {operation} {
    switch -- $operation {
        opt_design {
            return [dict create sequence 1 predecessor synthesis \
                target opt_design decision_state OPT_PERMITTED \
                post_phase POST_OPT category OPTIMIZATION \
                failure_phase OPT_DESIGN status_property \
                STEPS.OPT_DESIGN.STATUS]
        }
        place_design {
            return [dict create sequence 2 predecessor opt_design \
                target place_design decision_state PLACE_PERMITTED \
                post_phase POST_PLACE category PLACEMENT \
                failure_phase PLACE_DESIGN status_property \
                STEPS.PLACE_DESIGN.STATUS]
        }
        route_design {
            return [dict create sequence 3 predecessor place_design \
                target route_design decision_state ROUTE_PERMITTED \
                post_phase POST_ROUTE category ROUTING \
                failure_phase ROUTE_DESIGN status_property \
                STEPS.ROUTE_DESIGN.STATUS]
        }
        default {
            _raise OPERATION_INVALID "Unsupported runner operation: $operation"
        }
    }
}

proc ::stage1e::production_vivado_runner_v1::_status_token {value} {
    if {$value eq {}} { return NONE }
    set value [string toupper [string trim $value]]
    set value [string map {{ } _ {-} _ {!} {}} $value]
    while {[string first {__} $value] >= 0} {
        set value [string map {__ _} $value]
    }
    return $value
}

proc ::stage1e::production_vivado_runner_v1::_snapshot_property {
    snapshot key
} {
    foreach observation [dict get $snapshot property_observations] {
        if {[dict get $observation key] ne $key} { continue }
        if {[dict get $observation normalized_state] ne {AVAILABLE}} {
            return [dict create state UNKNOWN value UNKNOWN]
        }
        return [dict create state AVAILABLE \
            value [dict get $observation normalized_value]]
    }
    return [dict create state UNKNOWN value UNKNOWN]
}

proc ::stage1e::production_vivado_runner_v1::_native_state {
    snapshot operation
} {
    ::stage1e::vivado_runtime_contract_v1::validate_snapshot $snapshot
    switch -- $operation {
        opt_design { set step_key OPT_STATUS }
        place_design { set step_key PLACE_STATUS }
        route_design { set step_key ROUTE_STATUS }
        implementation_reports { set step_key ROUTE_STATUS }
        default {
            _raise OPERATION_INVALID \
                "Unsupported native-state operation: $operation"
        }
    }
    set run [_snapshot_property $snapshot IMPL_STATUS]
    set step [_snapshot_property $snapshot $step_key]
    set tool [dict get $snapshot tool_observation]
    set state AVAILABLE
    if {[dict get $run state] ne {AVAILABLE} ||
            [dict get $step state] ne {AVAILABLE} ||
            [dict get $tool current_run_state] ne {AVAILABLE} ||
            [dict get $tool current_design_state] ne {AVAILABLE}} {
        set state UNKNOWN
    }
    set result [dict create \
        observation_state $state \
        run_status [_status_token [dict get $run value]] \
        step_status [_status_token [dict get $step value]] \
        current_run [dict get $tool current_run] \
        current_design [dict get $tool current_design]]
    ::stage1e::vivado_runtime_contract_v1::require_record native_state $result
    return $result
}

proc ::stage1e::production_vivado_runner_v1::_dispatch_opt {} {
    launch_runs impl_1 -to_step opt_design -jobs 2
}

proc ::stage1e::production_vivado_runner_v1::_dispatch_place {} {
    launch_runs impl_1 -to_step place_design -jobs 2
}

proc ::stage1e::production_vivado_runner_v1::_dispatch_route {} {
    launch_runs impl_1 -to_step route_design -jobs 2
}

proc ::stage1e::production_vivado_runner_v1::_wait_impl {timeout_minutes} {
    wait_on_run -timeout $timeout_minutes impl_1
}

proc ::stage1e::production_vivado_runner_v1::_open_routed_impl {} {
    open_run impl_1
}

proc ::stage1e::production_vivado_runner_v1::_validate_phase_order {
    ledger sequence operation
} {
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    set entries [dict get $ledger entries]
    set index 0
    foreach entry $entries {
        incr index
        set status [dict get $entry phase_status]
        if {$index < $sequence && $status ne {COMPLETED}} {
            _raise PHASE_ORDER \
                "Runner predecessor is not complete at sequence $index."
        }
        if {$index == $sequence} {
            if {[dict get $entry logical_operation] ne $operation ||
                    $status ne {NOT_RUN}} {
                _raise PHASE_ORDER \
                    "Runner phase is repeated, reordered, or mismatched: $operation"
            }
        }
        if {$index > $sequence && $status ne {NOT_RUN}} {
            _raise PHASE_ORDER \
                "A later runner phase changed before sequence $sequence."
        }
    }
    return 1
}

proc ::stage1e::production_vivado_runner_v1::_replace_entry {
    ledger sequence replacement
} {
    ::stage1e::vivado_runtime_contract_v1::require_record \
        operation_ledger_entry $replacement
    set entries [dict get $ledger entries]
    set entries [lreplace $entries [expr {$sequence - 1}] \
        [expr {$sequence - 1}] $replacement]
    dict set ledger entries $entries
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    return $ledger
}

proc ::stage1e::production_vivado_runner_v1::_phase_failure {
    phase_request contract terminal code message snapshot_reference
} {
    set failure_ordinal [expr {[dict get $phase_request controller_decision \
        decision_ordinal] + 1}]
    return [::stage1e::vivado_runtime_contract_v1::make_failure \
        $terminal [dict get $contract category] $code RUNNER \
        [dict get $contract failure_phase] $failure_ordinal CONSUMED_ONCE \
        STATE_UNKNOWN PARTIAL_PRESERVED NEW_EXECUTION_REQUIRED \
        $message [list $snapshot_reference]]
}

proc ::stage1e::production_vivado_runner_v1::execute_phase {
    phase_request observation_ordinal
} {
    ::stage1e::vivado_runtime_contract_v1::validate_phase_request $phase_request
    set request [dict get $phase_request controller_request]
    set operation [dict get $phase_request logical_operation]
    set contract [_phase_contract $operation]
    foreach {field expected} [list \
            sequence [dict get $contract sequence] \
            exact_predecessor [dict get $contract predecessor] \
            target_step [dict get $contract target] \
            run_name impl_1 jobs 2] {
        ::stage1e::vivado_runtime_contract_v1::require_equal $expected \
            [dict get $phase_request $field] "Runner phase $field"
    }
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        [dict get $contract decision_state] \
        [dict get $phase_request controller_decision current_state] \
        {Runner controller decision state}
    set receipt [_receipt_for_request $request \
        [dict get $phase_request authorization_receipt_path] \
        [dict get $phase_request authorization_receipt_identity]]
    set receipt_reference \
        [::stage1e::vivado_runtime_contract_v1::receipt_reference $receipt]
    set ledger [dict get $phase_request operation_ledger]
    _validate_phase_order $ledger [dict get $contract sequence] $operation

    set start_state [_native_state [dict get $phase_request prior_snapshot] \
        $operation]
    set timeout_minutes \
        [::stage1e::vivado_runtime_contract_v1::wait_timeout_minutes \
            [dict get $phase_request timeout_seconds]]
    set launch_attempts 1
    set wait_attempts 0
    switch -- $operation {
        opt_design {
            set launch_status [catch {_dispatch_opt} launch_value]
        }
        place_design {
            set launch_status [catch {_dispatch_place} launch_value]
        }
        route_design {
            set launch_status [catch {_dispatch_route} launch_value]
        }
    }
    set launch_state [expr {$launch_status ? {FAILED} : {RETURNED}}]
    set wait_state NOT_RUN
    set timeout_state NOT_EXPIRED
    set wait_status 0
    set wait_value NONE
    if {!$launch_status} {
        set wait_attempts 1
        set wait_status [catch {_wait_impl $timeout_minutes} wait_value]
        if {$wait_status} {
            set wait_state FAILED
        } elseif {$wait_value eq {TIMEOUT}} {
            set wait_state TIMEOUT
            set timeout_state EXPIRED
        } elseif {$wait_value eq {STATE_UNKNOWN}} {
            set wait_state STATE_UNKNOWN
        } else {
            set wait_state RETURNED
        }
    }
    set snapshot [::stage1e::production_vivado_observer_v1::observe \
        $request [dict get $contract post_phase] $observation_ordinal]
    set end_state [_native_state $snapshot $operation]
    set forbidden [dict get $snapshot forbidden_operation_observation]
    set phase_status COMPLETED
    set failure NONE
    if {$launch_status} {
        set phase_status FAILED
        set failure [_phase_failure $phase_request $contract FAILED \
            VIVADO_PROJECT_MODE_LAUNCH_FAILED \
            "Project Mode launch failed for $operation: $launch_value" \
            [dict get $snapshot snapshot_reference]]
    } elseif {$wait_status} {
        set phase_status FAILED
        set failure [_phase_failure $phase_request $contract FAILED \
            VIVADO_PROJECT_MODE_WAIT_FAILED \
            "Project Mode wait failed for $operation: $wait_value" \
            [dict get $snapshot snapshot_reference]]
    } elseif {$timeout_state eq {EXPIRED}} {
        set phase_status BLOCKED
        set failure_ordinal [expr {[dict get $phase_request \
            controller_decision decision_ordinal] + 1}]
        set failure [::stage1e::vivado_runtime_contract_v1::make_failure \
            BLOCKED TIMEOUT VIVADO_PHASE_TIMEOUT RUNNER \
            [dict get $contract failure_phase] $failure_ordinal CONSUMED_ONCE \
            STATE_UNKNOWN PARTIAL_PRESERVED NEW_EXECUTION_REQUIRED \
            "The bounded phase wait expired for $operation." \
            [list [dict get $snapshot snapshot_reference]]]
    } elseif {$wait_state eq {STATE_UNKNOWN} ||
            [dict get $snapshot overall_state] ne {CLEAR} ||
            [dict get $end_state observation_state] ne {AVAILABLE} ||
            [dict get $end_state step_status] ne {COMPLETE} ||
            [dict get $forbidden result] ne {CLEAR}} {
        set phase_status BLOCKED
        set category CONFIGURATION_READBACK
        set code VIVADO_PHASE_STATE_UNCERTAIN
        if {[dict get $forbidden result] eq {DETECTED}} {
            set category FORBIDDEN_OPERATION
            set code FORBIDDEN_OPERATION_OBSERVED
        }
        set failure_ordinal [expr {[dict get $phase_request \
            controller_decision decision_ordinal] + 1}]
        set failure [::stage1e::vivado_runtime_contract_v1::make_failure \
            BLOCKED $category $code RUNNER \
            [dict get $contract failure_phase] $failure_ordinal CONSUMED_ONCE \
            STATE_UNKNOWN PARTIAL_PRESERVED NEW_EXECUTION_REQUIRED \
            "Phase completion could not be proven for $operation." \
            [list [dict get $snapshot snapshot_reference]]]
    }

    set sequence [dict get $contract sequence]
    set prior_entry [lindex [dict get $ledger entries] \
        [expr {$sequence - 1}]]
    dict set prior_entry controller_decision_reference \
        [dict get $phase_request controller_decision decision_reference]
    dict set prior_entry authorization_receipt_reference $receipt_reference
    dict set prior_entry phase_status $phase_status
    dict set prior_entry start_observation \
        "runner/[dict get $request execution_id]/$sequence/start"
    dict set prior_entry end_observation \
        "runner/[dict get $request execution_id]/$sequence/end"
    dict set prior_entry native_state_before $start_state
    dict set prior_entry native_state_after $end_state
    dict set prior_entry timeout_state $timeout_state
    dict set prior_entry observer_snapshot_references \
        [list [dict get $phase_request prior_snapshot_reference] \
            [dict get $snapshot snapshot_reference]]
    dict set prior_entry forbidden_operation_result [dict get $forbidden result]
    dict set prior_entry failure_references \
        [expr {$failure eq {NONE} ? {} :
            [list "failure/[dict get $failure failure_code]"]}]
    dict set prior_entry launch_attempts $launch_attempts
    dict set prior_entry wait_attempts $wait_attempts
    if {$phase_status ne {COMPLETED}} {
        dict set ledger terminal_state $phase_status
    }
    set ledger [_replace_entry $ledger $sequence $prior_entry]
    set result [dict create \
        schema_version stage1e-production-vivado-runner-phase-result-v1 \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        session_id [dict get $request session_context session_id] \
        sequence $sequence \
        logical_operation $operation \
        target_step [dict get $contract target] \
        phase_status $phase_status \
        scheduler_mechanism STAGED_PROJECT_MODE_IMPL_1 \
        launch_state $launch_state \
        wait_state $wait_state \
        timeout_state $timeout_state \
        start_observation $start_state \
        end_observation $end_state \
        observer_snapshot $snapshot \
        operation_ledger $ledger \
        forbidden_operation_result $forbidden \
        first_failure $failure \
        secondary_failures {} \
        authorization_effect CONSUMED_ONCE \
        retry_count 0 \
        candidate_effect NOT_CREATED]
    ::stage1e::vivado_runtime_contract_v1::validate_phase_result $result
    return $result
}

proc ::stage1e::production_vivado_runner_v1::_handoff_reference {
    request mode
} {
    return "collector-handoff/[dict get $request execution_id]/[dict get $request attempt_id]/[dict get $request session_context session_id]/$mode"
}

proc ::stage1e::production_vivado_runner_v1::failure_handoff {
    request ledger failed_phase failure snapshot_reference
} {
    ::stage1e::vivado_runtime_contract_v1::validate_controller_request $request
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    ::stage1e::vivado_runtime_contract_v1::validate_failure $failure
    set handoff [dict create \
        schema_version stage1e-vivado-collector-handoff-v1 \
        handoff_reference [_handoff_reference $request FAILURE_EVIDENCE_ONLY] \
        mode FAILURE_EVIDENCE_ONLY \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        session_id [dict get $request session_context session_id] \
        run_name impl_1 \
        routed_design_state MISSING \
        route_phase_state NOT_COMPLETED \
        failed_phase $failed_phase \
        current_design_state TRUSTWORTHY_STATE_UNPROVEN \
        post_route_snapshot_reference $snapshot_reference \
        operation_ledger $ledger \
        authorization_receipt_reference \
            [dict get $ledger authorization_receipt_reference] \
        report_contract_reference \
            [dict get $request session_context report_contract_reference] \
        evidence_root [dict get $request launch_contract evidence_root] \
        downstream_authority \
            [::stage1e::vivado_runtime_contract_v1::runtime_authority_boundary] \
        handoff_state FAILURE_EVIDENCE_ONLY \
        failure_references \
            [list "failure/[dict get $failure failure_code]"]]
    ::stage1e::vivado_runtime_contract_v1::validate_handoff $handoff
    return $handoff
}

proc ::stage1e::production_vivado_runner_v1::open_and_handoff {
    request controller_decision ledger post_route_snapshot observation_ordinal
} {
    ::stage1e::vivado_runtime_contract_v1::validate_controller_request $request
    ::stage1e::vivado_runtime_contract_v1::require_record \
        controller_decision $controller_decision
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    ::stage1e::vivado_runtime_contract_v1::validate_snapshot $post_route_snapshot
    foreach {field expected} {
        decision PROCEED current_state COLLECTOR_HANDOFF_READY
        operation implementation_reports
    } {
        ::stage1e::vivado_runtime_contract_v1::require_equal $expected \
            [dict get $controller_decision $field] \
            "Collector-handoff controller decision $field"
    }
    set entries [dict get $ledger entries]
    foreach index {0 1 2} {
        ::stage1e::vivado_runtime_contract_v1::require_equal COMPLETED \
            [dict get [lindex $entries $index] phase_status] \
            {Collector-handoff predecessor status}
    }
    ::stage1e::vivado_runtime_contract_v1::require_equal NOT_RUN \
        [dict get [lindex $entries 3] phase_status] \
        {Collector-handoff report phase status}
    set receipt_path [dict get $request authorization consumption_record_path]
    set separator [string last # [dict get $ledger \
        authorization_receipt_reference]]
    set expected_receipt [string range \
        [dict get $ledger authorization_receipt_reference] \
        [expr {$separator + 1}] end]
    _receipt_for_request $request $receipt_path $expected_receipt
    set open_status [catch {_open_routed_impl} open_value]
    set terminal_snapshot [::stage1e::production_vivado_observer_v1::observe \
        $request TERMINAL $observation_ordinal]
    if {$open_status ||
            [dict get $terminal_snapshot overall_state] ne {CLEAR} ||
            [dict get $terminal_snapshot run_relationship route_open_state] ne \
                {OPENED_SAME_ROUTED_RUN}} {
        set terminal_status [expr {$open_status ? {FAILED} : {BLOCKED}}]
        set failure_code [expr {$open_status ? {ROUTED_RUN_OPEN_FAILED} :
            {ROUTED_RUN_OPEN_READBACK_BLOCKED}}]
        set failure_ordinal \
            [expr {[dict get $controller_decision decision_ordinal] + 1}]
        set failure [::stage1e::vivado_runtime_contract_v1::make_failure \
            $terminal_status WORKSPACE_STATE $failure_code RUNNER \
            REPORT_COLLECTION $failure_ordinal CONSUMED_ONCE STATE_UNKNOWN \
            PARTIAL_PRESERVED NEW_EXECUTION_REQUIRED \
            {The same completed routed impl_1 could not be opened and proven.} \
            [list [dict get $terminal_snapshot snapshot_reference]]]
        set ledger [mark_handoff_failure $ledger $controller_decision \
            $post_route_snapshot $terminal_snapshot $failure]
        set handoff [failure_handoff $request $ledger \
            implementation_reports $failure \
            [dict get $post_route_snapshot snapshot_reference]]
        return [dict create open_state BLOCKED handoff $handoff \
            terminal_snapshot $terminal_snapshot failure $failure]
    }
    set handoff [dict create \
        schema_version stage1e-vivado-collector-handoff-v1 \
        handoff_reference [_handoff_reference $request ROUTED_REPORTING] \
        mode ROUTED_REPORTING \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        session_id [dict get $request session_context session_id] \
        run_name impl_1 \
        routed_design_state OPENED_SAME_ROUTED_RUN \
        route_phase_state COMPLETED \
        failed_phase NONE \
        current_design_state OPENED_ROUTED_IMPL_1 \
        post_route_snapshot_reference \
            [dict get $post_route_snapshot snapshot_reference] \
        operation_ledger $ledger \
        authorization_receipt_reference \
            [dict get $ledger authorization_receipt_reference] \
        report_contract_reference \
            [dict get $request session_context report_contract_reference] \
        evidence_root [dict get $request launch_contract evidence_root] \
        downstream_authority \
            [::stage1e::vivado_runtime_contract_v1::runtime_authority_boundary] \
        handoff_state READY \
        failure_references {}]
    ::stage1e::vivado_runtime_contract_v1::validate_handoff $handoff
    return [dict create open_state OPENED_SAME_ROUTED_RUN handoff $handoff \
        terminal_snapshot $terminal_snapshot failure NONE]
}

proc ::stage1e::production_vivado_runner_v1::mark_handoff_failure {
    ledger controller_decision post_route_snapshot terminal_snapshot failure
} {
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    ::stage1e::vivado_runtime_contract_v1::require_record \
        controller_decision $controller_decision
    ::stage1e::vivado_runtime_contract_v1::validate_snapshot \
        $post_route_snapshot
    ::stage1e::vivado_runtime_contract_v1::validate_snapshot \
        $terminal_snapshot
    ::stage1e::vivado_runtime_contract_v1::validate_failure $failure
    set entry [lindex [dict get $ledger entries] 3]
    ::stage1e::vivado_runtime_contract_v1::require_equal NOT_RUN \
        [dict get $entry phase_status] {Routed-open ledger source state}
    dict set entry controller_decision_reference \
        [dict get $controller_decision decision_reference]
    dict set entry phase_status [dict get $failure terminal_status]
    dict set entry start_observation \
        [dict get $post_route_snapshot snapshot_reference]
    dict set entry end_observation \
        [dict get $terminal_snapshot snapshot_reference]
    dict set entry native_state_before ROUTED_IMPL_1_COMPLETED
    dict set entry native_state_after TRUSTWORTHY_STATE_UNPROVEN
    dict set entry timeout_state NOT_STARTED
    dict set entry observer_snapshot_references [list \
        [dict get $post_route_snapshot snapshot_reference] \
        [dict get $terminal_snapshot snapshot_reference]]
    dict set entry forbidden_operation_result \
        [dict get $terminal_snapshot forbidden_operation_observation result]
    dict set entry failure_references \
        [list "failure/[dict get $failure failure_code]"]
    dict set entry open_attempts 1
    dict set ledger terminal_state [dict get $failure terminal_status]
    set ledger [_replace_entry $ledger 4 $entry]
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    return $ledger
}

proc ::stage1e::production_vivado_runner_v1::mark_collector_unavailable {
    ledger controller_decision handoff failure
} {
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    ::stage1e::vivado_runtime_contract_v1::require_record \
        controller_decision $controller_decision
    ::stage1e::vivado_runtime_contract_v1::validate_handoff $handoff
    ::stage1e::vivado_runtime_contract_v1::validate_failure $failure
    set entry [lindex [dict get $ledger entries] 3]
    ::stage1e::vivado_runtime_contract_v1::require_equal NOT_RUN \
        [dict get $entry phase_status] {Collector ledger source state}
    dict set entry controller_decision_reference \
        [dict get $controller_decision decision_reference]
    dict set entry phase_status BLOCKED
    dict set entry start_observation [dict get $handoff handoff_reference]
    dict set entry end_observation PRODUCTION_COLLECTOR_NOT_IMPLEMENTED
    dict set entry native_state_before OPENED_ROUTED_IMPL_1
    dict set entry native_state_after OPENED_ROUTED_IMPL_1
    dict set entry timeout_state NOT_STARTED
    dict set entry observer_snapshot_references \
        [list [dict get $handoff post_route_snapshot_reference]]
    dict set entry forbidden_operation_result CLEAR
    dict set entry failure_references \
        [list "failure/[dict get $failure failure_code]"]
    dict set entry open_attempts 1
    dict set ledger terminal_state BLOCKED
    set ledger [_replace_entry $ledger 4 $entry]
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    return $ledger
}
