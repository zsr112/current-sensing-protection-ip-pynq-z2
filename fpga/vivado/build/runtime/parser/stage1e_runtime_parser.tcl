# Stage 1E canonical runtime parser interfaces v1.
#
# Parsing is structural only. The caller supplies phase and evidence binding;
# this module does not infer historical expectations, classify dispositions,
# grant waivers, or decide acceptance.

namespace eval ::stage1e::runtime_parser {
    variable message_fields {
        phase severity identifier text evidence_identity
    }
    variable timing_exception_fields {
        exception_id
        exception_type
        from_object
        to_object
        through_objects
        constraint_source
        evidence_identity
        review_state
    }
    variable phases {
        opt_design place_design route_design implementation_reports
    }
    variable severities {INFO WARNING CRITICAL_WARNING ERROR}
}

proc ::stage1e::runtime_parser::_raise {code message} {
    return -code error -errorcode [list STAGE1E RUNTIME_PARSER $code] $message
}

proc ::stage1e::runtime_parser::parse_message {record} {
    variable message_fields
    variable phases
    variable severities
    ::stage1e::runtime_schema::require_exact_fields $record $message_fields \
        {Runtime message record}
    set phase [dict get $record phase]
    set severity [dict get $record severity]
    if {$phase ni $phases} {
        _raise PHASE_INVALID "Unknown message phase: $phase"
    }
    if {$severity ni $severities} {
        _raise SEVERITY_INVALID "Unknown message severity: $severity"
    }
    ::stage1e::runtime_schema::require_identity \
        [dict get $record evidence_identity] {Message evidence identity}
    if {![regexp {^[A-Za-z0-9_.:-]+$} [dict get $record identifier]]} {
        _raise IDENTIFIER_INVALID {Message identifier is not canonical.}
    }
    return [dict create \
        schema_version stage1e-runtime-message-v1 \
        phase $phase \
        severity $severity \
        identifier [dict get $record identifier] \
        text [string trim [dict get $record text]] \
        evidence_identity [dict get $record evidence_identity] \
        disposition UNDISPOSITIONED \
        acceptance_decision NOT_OWNED]
}

proc ::stage1e::runtime_parser::parse_timing_exception {record} {
    variable timing_exception_fields
    ::stage1e::runtime_schema::require_exact_fields $record \
        $timing_exception_fields {Timing exception inventory record}
    ::stage1e::runtime_schema::require_identity \
        [dict get $record evidence_identity] \
        {Timing exception evidence identity}
    if {[dict get $record review_state] ne {PENDING_REVIEW}} {
        _raise REVIEW_STATE_INVALID \
            {New timing exception records must remain PENDING_REVIEW.}
    }
    return [dict create \
        schema_version stage1e-timing-exception-inventory-entry-v1 \
        exception_id [dict get $record exception_id] \
        exception_type [dict get $record exception_type] \
        from_object [dict get $record from_object] \
        to_object [dict get $record to_object] \
        through_objects [dict get $record through_objects] \
        constraint_source [dict get $record constraint_source] \
        evidence_identity [dict get $record evidence_identity] \
        review_state PENDING_REVIEW \
        acceptance_decision NOT_OWNED]
}
