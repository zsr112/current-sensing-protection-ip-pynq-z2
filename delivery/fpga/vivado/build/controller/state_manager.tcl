namespace eval ::stage1d::state_manager {
    variable state_schema_version v1
    variable all_states {
        INIT
        INPUT_VALIDATION
        SOURCE_VERIFIED
        ENVIRONMENT_VERIFIED
        WORKSPACE_READY
        PROJECT_READY
        BD_READY
        DESIGN_VALIDATED
        WRAPPER_READY
        SYNTH_DONE
        IMPL_DONE
        ARTIFACT_READY
        MANIFEST_READY
        PASS
        FAIL
        BLOCKED
    }
    variable forward_transitions [dict create \
        INIT INPUT_VALIDATION \
        INPUT_VALIDATION SOURCE_VERIFIED \
        SOURCE_VERIFIED ENVIRONMENT_VERIFIED \
        ENVIRONMENT_VERIFIED WORKSPACE_READY \
        WORKSPACE_READY PROJECT_READY \
        PROJECT_READY BD_READY \
        BD_READY DESIGN_VALIDATED \
        DESIGN_VALIDATED WRAPPER_READY \
        WRAPPER_READY SYNTH_DONE \
        SYNTH_DONE IMPL_DONE \
        IMPL_DONE ARTIFACT_READY \
        ARTIFACT_READY MANIFEST_READY \
        MANIFEST_READY PASS]
}

proc ::stage1d::state_manager::new {
    execution_identifier
    execution_id_schema_version
    controller_version
    controller_api_version
} {
    variable state_schema_version

    if {$execution_identifier eq {}} {
        error {State manager requires a nonempty execution identifier.}
    }
    if {$execution_id_schema_version eq {}} {
        error {State manager requires an execution identifier schema version.}
    }

    return [dict create \
        state_schema_version $state_schema_version \
        execution_id_schema_version $execution_id_schema_version \
        execution_identifier $execution_identifier \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        current_state INIT \
        history {}]
}

proc ::stage1d::state_manager::current {state} {
    return [dict get $state current_state]
}

proc ::stage1d::state_manager::history {state} {
    return [dict get $state history]
}

proc ::stage1d::state_manager::is_known_state {state_name} {
    variable all_states
    return [expr {[lsearch -exact $all_states $state_name] >= 0}]
}

proc ::stage1d::state_manager::is_terminal {state_name} {
    return [expr {$state_name in {PASS FAIL BLOCKED}}]
}

proc ::stage1d::state_manager::can_transition {current_state next_state} {
    variable forward_transitions

    if {![is_known_state $current_state] || ![is_known_state $next_state]} {
        return 0
    }
    if {[is_terminal $current_state]} {
        return 0
    }
    if {$next_state in {FAIL BLOCKED}} {
        return 1
    }
    if {![dict exists $forward_transitions $current_state]} {
        return 0
    }
    return [expr {[dict get $forward_transitions $current_state] eq $next_state}]
}

proc ::stage1d::state_manager::_validate_evidence {state next_state evidence} {
    ::stage1d::phase_runner::validate_evidence $evidence

    set expected_execution_identifier [dict get $state execution_identifier]
    set actual_execution_identifier [dict get $evidence execution_identifier]
    if {$actual_execution_identifier ne $expected_execution_identifier} {
        error "Execution identifier mismatch: expected=$expected_execution_identifier actual=$actual_execution_identifier"
    }

    set status [dict get $evidence status]
    if {$next_state eq {FAIL} && $status ne {FAIL}} {
        error "Transition to FAIL requires FAIL evidence, got: $status"
    }
    if {$next_state eq {BLOCKED} && $status ni {BLOCKED SKIPPED_DEPENDENCY}} {
        error "Transition to BLOCKED requires BLOCKED or SKIPPED_DEPENDENCY evidence, got: $status"
    }
    if {$next_state ni {FAIL BLOCKED} && $status ne {PASS}} {
        error "Forward transition to $next_state requires PASS evidence, got: $status"
    }
}

proc ::stage1d::state_manager::transition {state_variable next_state evidence {transition_time {}}} {
    upvar 1 $state_variable state

    set current_state [dict get $state current_state]
    if {![is_known_state $next_state]} {
        error "Unknown next state: $next_state"
    }
    if {![can_transition $current_state $next_state]} {
        error "Illegal state transition: $current_state -> $next_state"
    }

    _validate_evidence $state $next_state $evidence
    if {$transition_time eq {}} {
        set transition_time [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]
    }

    set transition_record [dict create \
        prior_state $current_state \
        next_state $next_state \
        phase_name [dict get $evidence phase_name] \
        phase_status [dict get $evidence status] \
        execution_id_schema_version [dict get $state execution_id_schema_version] \
        execution_identifier [dict get $state execution_identifier] \
        controller_api_version [dict get $state controller_api_version] \
        transition_time $transition_time]

    dict set state current_state $next_state
    dict lappend state history $transition_record
    return $transition_record
}
