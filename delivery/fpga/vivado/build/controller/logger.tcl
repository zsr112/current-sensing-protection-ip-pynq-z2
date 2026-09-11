namespace eval ::stage1d::logger {
    variable log_schema_version v1
    variable allowed_severities {INFO WARNING ERROR}
}

proc ::stage1d::logger::utc_timestamp {{epoch_seconds {}}} {
    if {$epoch_seconds eq {}} {
        set epoch_seconds [clock seconds]
    }
    return [clock format $epoch_seconds -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]
}

proc ::stage1d::logger::new {
    execution_identifier
    execution_id_schema_version
    controller_version
    controller_api_version
} {
    if {$execution_identifier eq {}} {
        error {Logger requires a nonempty execution identifier.}
    }
    return [dict create \
        execution_identifier $execution_identifier \
        execution_id_schema_version $execution_id_schema_version \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        next_sequence 1 \
        records {}]
}

proc ::stage1d::logger::record {logger_variable phase_name severity event_code message {timestamp {}}} {
    variable log_schema_version
    variable allowed_severities
    upvar 1 $logger_variable logger_state

    if {[lsearch -exact $allowed_severities $severity] < 0} {
        error "Unsupported log severity: $severity"
    }
    if {$phase_name eq {}} {
        error {Log phase_name must not be empty.}
    }
    if {![regexp {^[A-Z][A-Z0-9_]*$} $event_code]} {
        error "Invalid log event code: $event_code"
    }
    if {$timestamp eq {}} {
        set timestamp [utc_timestamp]
    }

    set sequence [dict get $logger_state next_sequence]
    set log_record [dict create \
        log_schema_version $log_schema_version \
        sequence $sequence \
        timestamp $timestamp \
        execution_id_schema_version [dict get $logger_state execution_id_schema_version] \
        execution_identifier [dict get $logger_state execution_identifier] \
        controller_version [dict get $logger_state controller_version] \
        controller_api_version [dict get $logger_state controller_api_version] \
        phase_name $phase_name \
        severity $severity \
        event_code $event_code \
        message $message]

    dict lappend logger_state records $log_record
    dict incr logger_state next_sequence
    return $log_record
}

proc ::stage1d::logger::emit {log_record} {
    puts [list STAGE1D_LOG $log_record]
}

proc ::stage1d::logger::records {logger_state} {
    return [dict get $logger_state records]
}
