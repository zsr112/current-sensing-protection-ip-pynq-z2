namespace eval ::stage1d::phase_runner {
    variable allowed_statuses {PASS FAIL BLOCKED SKIPPED_DEPENDENCY}
    variable required_evidence_fields {
        phase_name
        status
        start_time
        end_time
        execution_identifier
        evidence_locations
        logs
        reports
        errors
        outputs
        artifact_references
    }
}

proc ::stage1d::phase_runner::_get_or_default {dictionary key default_value} {
    if {[dict exists $dictionary $key]} {
        return [dict get $dictionary $key]
    }
    return $default_value
}

proc ::stage1d::phase_runner::_error_record {error_code category phase_name message underlying_error} {
    return [dict create \
        error_code $error_code \
        category $category \
        phase_name $phase_name \
        message $message \
        underlying_error $underlying_error \
        evidence_references {} \
        recoverability NONE]
}

proc ::stage1d::phase_runner::_status_severity {status} {
    switch -- $status {
        PASS { return INFO }
        BLOCKED -
        SKIPPED_DEPENDENCY { return WARNING }
        default { return ERROR }
    }
}

proc ::stage1d::phase_runner::validate_evidence {
    evidence
    {expected_phase_name {}}
    {expected_execution_identifier {}}
} {
    variable allowed_statuses
    variable required_evidence_fields

    if {[catch {dict size $evidence} evidence_error]} {
        error "Phase evidence is not a dictionary: $evidence_error"
    }

    foreach required_field $required_evidence_fields {
        if {![dict exists $evidence $required_field]} {
            error "Phase evidence is missing required field: $required_field"
        }
    }

    set phase_name [dict get $evidence phase_name]
    if {$phase_name eq {}} {
        error {Phase evidence phase_name must not be empty.}
    }
    if {$expected_phase_name ne {} && $phase_name ne $expected_phase_name} {
        error "Phase evidence name mismatch: expected=$expected_phase_name actual=$phase_name"
    }

    set status [dict get $evidence status]
    if {[lsearch -exact $allowed_statuses $status] < 0} {
        error "Unsupported phase evidence status: $status"
    }

    foreach timestamp_field {start_time end_time} {
        set timestamp [dict get $evidence $timestamp_field]
        if {![regexp {^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$} $timestamp]} {
            error "Invalid UTC phase evidence timestamp in $timestamp_field: $timestamp"
        }
    }
    if {[string compare [dict get $evidence end_time] [dict get $evidence start_time]] < 0} {
        error {Phase evidence end_time precedes start_time.}
    }

    set execution_identifier [dict get $evidence execution_identifier]
    if {$execution_identifier eq {}} {
        error {Phase evidence execution_identifier must not be empty.}
    }
    if {$expected_execution_identifier ne {} && $execution_identifier ne $expected_execution_identifier} {
        error "Phase evidence execution identifier mismatch: expected=$expected_execution_identifier actual=$execution_identifier"
    }

    foreach list_field {
        evidence_locations
        logs
        reports
        errors
        artifact_references
    } {
        if {[catch {llength [dict get $evidence $list_field]} list_error]} {
            error "Phase evidence field $list_field is not a list: $list_error"
        }
    }
    if {[catch {dict size [dict get $evidence outputs]} outputs_error]} {
        error "Phase evidence outputs is not a dictionary: $outputs_error"
    }

    return 1
}

proc ::stage1d::phase_runner::run {
    state_variable
    logger_variable
    phase_name
    success_state
    callback
    context
} {
    variable allowed_statuses
    upvar 1 $state_variable state
    upvar 1 $logger_variable logger

    set execution_identifier [dict get $state execution_identifier]
    set execution_id_schema_version [dict get $state execution_id_schema_version]
    set controller_version [dict get $state controller_version]
    set controller_api_version [dict get $state controller_api_version]
    set phase_evidence_schema_version [dict get $context phase_evidence_schema_version]
    set start_time [::stage1d::logger::utc_timestamp]

    set start_log [::stage1d::logger::record \
        logger $phase_name INFO PHASE_START "Phase started: $phase_name" $start_time]
    ::stage1d::logger::emit $start_log

    set callback_command [linsert $callback end $context]
    set callback_status [catch {
        uplevel #0 $callback_command
    } callback_result callback_options]

    if {$callback_status != 0} {
        set status FAIL
        set callback_errors [list [_error_record \
            PHASE_CALLBACK_ERROR \
            CORE \
            $phase_name \
            "Unhandled phase callback error: $callback_result" \
            [_get_or_default $callback_options -errorinfo {}]]]
        set callback_result [dict create \
            status $status \
            evidence_locations {} \
            logs {} \
            reports {} \
            errors $callback_errors \
            outputs {} \
            artifact_references {}]
    } elseif {[catch {dict size $callback_result} dictionary_error]} {
        set status FAIL
        set callback_result [dict create \
            status $status \
            evidence_locations {} \
            logs {} \
            reports {} \
            errors [list [_error_record \
                INVALID_PHASE_RESULT \
                CORE \
                $phase_name \
                {Phase callback did not return a dictionary.} \
                $dictionary_error]] \
            outputs {} \
            artifact_references {}]
    } elseif {![dict exists $callback_result status]} {
        set status FAIL
        dict set callback_result status $status
        dict set callback_result errors [list [_error_record \
            MISSING_PHASE_STATUS \
            CORE \
            $phase_name \
            {Phase callback did not return status.} \
            {}]]
    } else {
        set status [dict get $callback_result status]
        if {[lsearch -exact $allowed_statuses $status] < 0} {
            set invalid_status $status
            set status FAIL
            dict set callback_result status $status
            dict set callback_result errors [list [_error_record \
                INVALID_PHASE_STATUS \
                CORE \
                $phase_name \
                "Unsupported phase status: $invalid_status" \
                {}]]
        }
    }

    set end_time [::stage1d::logger::utc_timestamp]
    set evidence [dict create \
        phase_evidence_schema_version $phase_evidence_schema_version \
        phase_name $phase_name \
        status $status \
        start_time $start_time \
        end_time $end_time \
        execution_id_schema_version $execution_id_schema_version \
        execution_identifier $execution_identifier \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        evidence_locations [_get_or_default $callback_result evidence_locations {}] \
        logs [_get_or_default $callback_result logs {}] \
        reports [_get_or_default $callback_result reports {}] \
        errors [_get_or_default $callback_result errors {}] \
        outputs [_get_or_default $callback_result outputs {}] \
        artifact_references [_get_or_default $callback_result artifact_references {}]]

    set validation_status [catch {
        validate_evidence $evidence $phase_name $execution_identifier
    } validation_error validation_options]
    if {$validation_status != 0} {
        set status FAIL
        set evidence [dict create \
            phase_evidence_schema_version $phase_evidence_schema_version \
            phase_name $phase_name \
            status $status \
            start_time $start_time \
            end_time $end_time \
            execution_id_schema_version $execution_id_schema_version \
            execution_identifier $execution_identifier \
            controller_version $controller_version \
            controller_api_version $controller_api_version \
            evidence_locations {} \
            logs {} \
            reports {} \
            errors [list [_error_record \
                INVALID_PHASE_EVIDENCE \
                CORE \
                $phase_name \
                "Phase evidence validation failed: $validation_error" \
                [_get_or_default $validation_options -errorinfo {}]]] \
            outputs {} \
            artifact_references {}]
        validate_evidence $evidence $phase_name $execution_identifier
    }

    if {$status eq {PASS}} {
        set target_state $success_state
    } elseif {$status eq {SKIPPED_DEPENDENCY}} {
        set target_state BLOCKED
    } else {
        set target_state $status
    }

    set transition_status [catch {
        ::stage1d::state_manager::transition state $target_state $evidence $end_time
    } transition_result transition_options]

    if {$transition_status != 0} {
        set status FAIL
        dict set evidence status $status
        dict lappend evidence errors [_error_record \
            STATE_TRANSITION_ERROR \
            STATE \
            $phase_name \
            "State transition failed: $transition_result" \
            [_get_or_default $transition_options -errorinfo {}]]

        set current_state [::stage1d::state_manager::current $state]
        if {[::stage1d::state_manager::can_transition $current_state FAIL]} {
            set fallback_status [catch {
                ::stage1d::state_manager::transition state FAIL $evidence $end_time
            } fallback_error]
            if {$fallback_status != 0} {
                dict lappend evidence errors [_error_record \
                    STATE_FAILURE_TRANSITION_ERROR \
                    STATE \
                    $phase_name \
                    "Unable to enter FAIL state: $fallback_error" \
                    {}]
            }
        }
    } else {
        dict set evidence state_transition $transition_result
    }

    set end_log [::stage1d::logger::record \
        logger \
        $phase_name \
        [_status_severity [dict get $evidence status]] \
        PHASE_END \
        "Phase completed with status [dict get $evidence status]: $phase_name" \
        $end_time]
    ::stage1d::logger::emit $end_log

    set evidence_logs [list $start_log]
    foreach callback_log [dict get $evidence logs] {
        lappend evidence_logs $callback_log
    }
    lappend evidence_logs $end_log
    dict set evidence logs $evidence_logs

    validate_evidence $evidence $phase_name $execution_identifier

    return $evidence
}
