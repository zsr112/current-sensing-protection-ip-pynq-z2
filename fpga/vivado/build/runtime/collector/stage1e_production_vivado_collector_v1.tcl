# Stage 1E PRT02-D production Vivado Collector candidate v1.
#
# The Collector consumes only an exact PRT02-C handoff, owns the closed report
# command surface and append-only attempt records, and writes native evidence.
# It owns no implementation scheduling, parsing, identity issue, finding
# disposition, policy review, engineering acceptance, candidate, artifact, or
# board authority. Actual Vivado command forms remain unqualified; non-Vivado
# validation uses the fixed synthetic facade only.

set ::stage1e_collector_dir [file dirname [info script]]
set ::stage1e_collector_build [file dirname [file dirname \
    $::stage1e_collector_dir]]
if {![llength [info commands \
        ::stage1e::evidence_pipeline_contract_v1::validate_record]]} {
    source [file join $::stage1e_collector_build lib \
        stage1e_evidence_pipeline_contract_v1.tcl]
}
if {![llength [info commands \
        ::stage1e::production_evidence_serializer_v1::publish_record]]} {
    source [file join $::stage1e_collector_build runtime identity \
        stage1e_production_evidence_serializer_v1.tcl]
}

namespace eval ::stage1e::production_vivado_collector_v1 {
    variable interface_version stage1e-production-vivado-collector-interface-v1
}
unset ::stage1e_collector_dir
unset ::stage1e_collector_build

proc ::stage1e::production_vivado_collector_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_vivado_collector_v1::_raise {code message} {
    return -code error -errorcode [list STAGE1E EVIDENCE COLLECTOR $code] \
        $message
}

proc ::stage1e::production_vivado_collector_v1::_canonical_path {path} {
    return [::stage1e::vivado_runtime_contract_v1::canonical_path $path]
}

proc ::stage1e::production_vivado_collector_v1::_path_within {path root} {
    return [::stage1e::vivado_runtime_contract_v1::path_is_within $path $root]
}

proc ::stage1e::production_vivado_collector_v1::_observation {ordinal phase} {
    set milliseconds [clock clicks -milliseconds]
    set utc [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]
    return "LOCAL=$ordinal;MONOTONIC_MS=$milliseconds;UTC=$utc;PHASE=$phase"
}

proc ::stage1e::production_vivado_collector_v1::_event_path {
    request event_ordinal kind
} {
    set leaf [format {event-%04d-%s.json} $event_ordinal \
        [string tolower $kind]]
    return [_canonical_path [file join \
        [dict get $request report_event_root] $leaf]]
}

proc ::stage1e::production_vivado_collector_v1::_reservation_path {
    request role role_attempt
} {
    set definition \
        [::stage1e::evidence_pipeline_contract_v1::role_definition $role]
    set leaf [format {reservation-%02d-%s-attempt-%d.json} \
        [dict get $definition ordinal] [string tolower $role] $role_attempt]
    return [_canonical_path [file join \
        [dict get $request report_event_root] $leaf]]
}

proc ::stage1e::production_vivado_collector_v1::_reserve_output {
    request role role_attempt
} {
    set definition \
        [::stage1e::evidence_pipeline_contract_v1::role_definition $role]
    set path [_reservation_path $request $role $role_attempt]
    set reservation [dict create \
        schema_version stage1e-report-output-reservation-v1 \
        reservation_reference $path \
        role_ordinal [dict get $definition ordinal] report_role $role \
        role_attempt $role_attempt \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        producer_session_reference \
            [dict get $request producer_session producer_session_reference] \
        requested_path [dict get $request role_output_paths $role] \
        reservation_state EXCLUSIVE_NO_OVERWRITE \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    ::stage1e::production_evidence_serializer_v1::publish_record \
        report_output_reservation $reservation $path \
        [dict get $request report_root]
    return $reservation
}

proc ::stage1e::production_vivado_collector_v1::_content_observation {
    request role state {bytes {}}
} {
    return [::stage1e::evidence_pipeline_contract_v1::integrity_observation \
        $role $request $state $bytes]
}

proc ::stage1e::production_vivado_collector_v1::_observe_output {
    request role output_path
} {
    if {![file exists $output_path] || ![file isfile $output_path]} {
        return [dict create observed_path NONE byte_state MISSING \
            byte_count -1 integrity_state UNAVAILABLE_WITH_REASON \
            observation [_content_observation $request $role \
                UNAVAILABLE_WITH_REASON]]
    }
    set observed [_canonical_path $output_path]
    set bytes [::stage1e::atomic_publication_v1::read_binary $observed]
    set count [string length $bytes]
    set byte_state [expr {$count == 0 ? {ZERO_BYTE} : {PRESENT}}]
    return [dict create observed_path $observed byte_state $byte_state \
        byte_count $count integrity_state VERIFIED_SHA256 \
        observation [_content_observation $request $role VERIFIED_SHA256 \
            $bytes]]
}

proc ::stage1e::production_vivado_collector_v1::_validate_paths {request} {
    set report_root [_canonical_path [dict get $request report_root]]
    set event_root [_canonical_path [dict get $request report_event_root]]
    if {![file exists $report_root] || ![file isdirectory $report_root]} {
        _raise REPORT_ROOT_INVALID \
            {Collector report root must exist and be a directory.}
    }
    if {![file exists $event_root] || ![file isdirectory $event_root] ||
            ![_path_within $event_root $report_root]} {
        _raise EVENT_ROOT_INVALID \
            {Collector event root must exist beneath the report root.}
    }
    set final_paths [list [dict get $request report_ledger_path] \
        [dict get $request collector_result_path]]
    set seen {}
    set role_paths [dict get $request role_output_paths]
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields \
        $role_paths \
        [::stage1e::evidence_pipeline_contract_v1::collector_roles] \
        {Collector role output paths}
    foreach role [::stage1e::evidence_pipeline_contract_v1::collector_roles] {
        lappend final_paths [dict get $role_paths $role]
    }
    foreach path $final_paths {
        if {[file pathtype $path] ne {absolute}} {
            _raise OUTPUT_PATH_INVALID \
                {Collector output paths must be literal absolute paths.}
        }
        foreach wildcard [list {*} {?} {[} {]}] {
            if {[string first $wildcard $path] >= 0} {
                _raise OUTPUT_PATH_INVALID \
                    {Collector output paths cannot contain wildcard tokens.}
            }
        }
        set canonical [_canonical_path $path]
        if {![_path_within $canonical $report_root]} {
            _raise OUTPUT_PATH_ESCAPE \
                "Collector output path is outside the report root: $path"
        }
        if {[dict exists $seen [string tolower $canonical]]} {
            _raise OUTPUT_PATH_DUPLICATE \
                "Collector output path is duplicated: $path"
        }
        dict set seen [string tolower $canonical] 1
        if {[file exists $canonical]} {
            _raise OUTPUT_PATH_COLLISION \
                "Collector output path already exists: $path"
        }
        set parent [file dirname $canonical]
        if {![file exists $parent] || ![file isdirectory $parent]} {
            _raise OUTPUT_PARENT_INVALID \
                "Collector output parent does not exist: $parent"
        }
    }
    return 1
}

proc ::stage1e::production_vivado_collector_v1::_validate_roles {request} {
    set collector_roles \
        [::stage1e::evidence_pipeline_contract_v1::collector_roles]
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields \
        [dict get $request command_availability] $collector_roles \
        {Collector command-availability projection}
    foreach role $collector_roles {
        ::stage1e::evidence_pipeline_contract_v1::require_one_of \
            [dict get $request command_availability $role] \
            {AVAILABLE UNAVAILABLE AMBIGUOUS} \
            "Collector command availability $role"
    }
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields \
        [dict get $request conditional_decisions] {CONDITIONAL_BUS_SKEW} \
        {Collector conditional decisions}
    ::stage1e::evidence_pipeline_contract_v1::require_one_of \
        [dict get $request conditional_decisions CONDITIONAL_BUS_SKEW] \
        {REQUIRED NOT_REQUIRED CONDITION_UNKNOWN} \
        {Collector conditional bus-skew decision}
    return 1
}

proc ::stage1e::production_vivado_collector_v1::_validate_adopted {request} {
    set expected [::stage1e::evidence_pipeline_contract_v1::adopted_roles]
    set observed {}
    foreach item [dict get $request adopted_evidence] {
        lappend observed [dict get $item role]
        foreach field {
            request_identity execution_id attempt_id workspace_identity
        } {
            ::stage1e::evidence_pipeline_contract_v1::require_equal \
                [dict get $request $field] [dict get $item $field] \
                "Collector adopted role [dict get $item role] binding $field"
        }
        ::stage1e::evidence_pipeline_contract_v1::require_equal CURRENT \
            [dict get $item foreign_state] \
            "Collector adopted role [dict get $item role] current state"
        if {[dict get $item observed_path] ne {NONE}} {
            if {[dict get $item integrity_state] ne {VERIFIED_SHA256} ||
                    ![file exists [dict get $item observed_path]] ||
                    ![file isfile [dict get $item observed_path]]} {
                _raise ADOPTED_INTEGRITY_UNAVAILABLE \
                    "Adopted file role [dict get $item role] lacks exact integrity."
            }
            set bytes [::stage1e::atomic_publication_v1::read_binary \
                [dict get $item observed_path]]
            set observation [dict get $item content_sha256_observation]
            if {[string length $bytes] != [dict get $observation byte_count] ||
                    [::stage1e::canonical_json_v1::digest_bytes $bytes] ne
                        [dict get $observation content_sha256]} {
                _raise ADOPTED_INTEGRITY_MISMATCH \
                    "Adopted file role [dict get $item role] bytes changed."
            }
        } elseif {[dict get $item evidence_state] eq {PRESENT} &&
                [dict get $item integrity_state] eq \
                    {UNAVAILABLE_WITH_REASON}} {
            _raise ADOPTED_INTEGRITY_UNAVAILABLE \
                "Required adopted role [dict get $item role] lacks integrity."
        }
    }
    ::stage1e::evidence_pipeline_contract_v1::require_equal $expected $observed \
        {Collector adopted role order}
    return 1
}

proc ::stage1e::production_vivado_collector_v1::validate_request {request} {
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        collector_request $request
    foreach field {
        attempt_deadline_state reporting_deadline_state total_deadline_state
    } {
        ::stage1e::evidence_pipeline_contract_v1::require_equal NOT_EXPIRED \
            [dict get $request $field] "Collector $field"
    }
    set session [dict get $request producer_session]
    foreach field {
        request_identity execution_id attempt_id workspace_identity session_id
    } {
        ::stage1e::evidence_pipeline_contract_v1::require_equal \
            [dict get $request $field] [dict get $session $field] \
            "Collector producer-session binding $field"
    }
    ::stage1e::evidence_pipeline_contract_v1::require_equal \
        [dict get $request current_design_state] \
        [dict get $session current_design_state] \
        {Collector producer-session current design state}
    _validate_roles $request
    _validate_adopted $request
    _validate_paths $request
    return 1
}

proc ::stage1e::production_vivado_collector_v1::_invoke_vivado_role {
    role output_path
} {
    switch -- $role {
        TIMING_SUMMARY {
            report_timing_summary -file $output_path
        }
        TIMING_PATH_GROUPS {
            report_timing -max_paths 100 -sort_by group -file $output_path
        }
        CLOCK_INTERACTION {
            report_clock_interaction -file $output_path
        }
        CLOCKS_GENERATED_CLOCKS {
            report_clocks -file $output_path
        }
        CONSTRAINT_COVERAGE {
            report_exceptions -coverage -file $output_path
        }
        CHECK_TIMING {
            check_timing -verbose -file $output_path
        }
        TIMING_EXCEPTION_SOURCE {
            report_exceptions -all -file $output_path
        }
        CONDITIONAL_BUS_SKEW {
            report_bus_skew -file $output_path
        }
        UTILIZATION {
            report_utilization -file $output_path
        }
        DRC {
            report_drc -file $output_path
        }
        METHODOLOGY {
            report_methodology -file $output_path
        }
        CDC {
            report_cdc -details -file $output_path
        }
        MESSAGE_SOURCE {
            report_route_status -file $output_path
        }
        default {
            _raise REPORT_ROLE_UNKNOWN "Unknown Collector role '$role'."
        }
    }
    return SUCCESS
}

proc ::stage1e::production_vivado_collector_v1::_invoke_fixture_role {
    role output_path
} {
    switch -- $role {
        TIMING_SUMMARY {
            return [::stage1e::evidence_collector_command_model_v1::timing_summary \
                $output_path]
        }
        TIMING_PATH_GROUPS {
            return [::stage1e::evidence_collector_command_model_v1::timing_path_groups \
                $output_path]
        }
        CLOCK_INTERACTION {
            return [::stage1e::evidence_collector_command_model_v1::clock_interaction \
                $output_path]
        }
        CLOCKS_GENERATED_CLOCKS {
            return [::stage1e::evidence_collector_command_model_v1::clocks \
                $output_path]
        }
        CONSTRAINT_COVERAGE {
            return [::stage1e::evidence_collector_command_model_v1::constraint_coverage \
                $output_path]
        }
        CHECK_TIMING {
            return [::stage1e::evidence_collector_command_model_v1::check_timing \
                $output_path]
        }
        TIMING_EXCEPTION_SOURCE {
            return [::stage1e::evidence_collector_command_model_v1::timing_exceptions \
                $output_path]
        }
        CONDITIONAL_BUS_SKEW {
            return [::stage1e::evidence_collector_command_model_v1::bus_skew \
                $output_path]
        }
        UTILIZATION {
            return [::stage1e::evidence_collector_command_model_v1::utilization \
                $output_path]
        }
        DRC {
            return [::stage1e::evidence_collector_command_model_v1::drc \
                $output_path]
        }
        METHODOLOGY {
            return [::stage1e::evidence_collector_command_model_v1::methodology \
                $output_path]
        }
        CDC {
            return [::stage1e::evidence_collector_command_model_v1::cdc \
                $output_path]
        }
        MESSAGE_SOURCE {
            return [::stage1e::evidence_collector_command_model_v1::messages \
                $output_path]
        }
        default {
            _raise REPORT_ROLE_UNKNOWN "Unknown Collector role '$role'."
        }
    }
}

proc ::stage1e::production_vivado_collector_v1::_invoke {
    facade role output_path
} {
    switch -- $facade {
        PRODUCTION_VIVADO {
            return [_invoke_vivado_role $role $output_path]
        }
        SYNTHETIC_FIXTURE {
            return [_invoke_fixture_role $role $output_path]
        }
        default {
            _raise COMMAND_FACADE_INVALID \
                {Collector command facade is outside the closed internal set.}
        }
    }
}

proc ::stage1e::production_vivado_collector_v1::_open_event {
    request reservation event_ordinal
} {
    set role [dict get $reservation report_role]
    set role_attempt [dict get $reservation role_attempt]
    set definition \
        [::stage1e::evidence_pipeline_contract_v1::role_definition $role]
    set event_path [_event_path $request $event_ordinal OPEN]
    set event [dict create \
        schema_version stage1e-report-attempt-open-event-v1 \
        event_type OPEN event_reference $event_path \
        event_ordinal $event_ordinal \
        role_ordinal [dict get $definition ordinal] report_role $role \
        role_attempt $role_attempt \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        producer_session_reference \
            [dict get $request producer_session producer_session_reference] \
        producer_phase REPORT_COLLECTION \
        current_design_state [dict get $request current_design_state] \
        exact_command_role [dict get $definition command_facade_role] \
        exact_command_name [dict get $definition command_name] \
        exact_command_options [dict get $definition ordered_options] \
        requested_path [dict get $request role_output_paths $role] \
        reservation_reference [dict get $reservation reservation_reference] \
        start_observation [_observation $event_ordinal ATTEMPT_OPEN] \
        deadline_state NOT_EXPIRED \
        identity_state PENDING_IDENTITY_PROVIDER \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    ::stage1e::production_evidence_serializer_v1::publish_record \
        report_attempt_open_event $event $event_path \
        [dict get $request report_root]
    return $event
}

proc ::stage1e::production_vivado_collector_v1::_terminal_event {
    request open status event_ordinal output_observation command_result
    failure_reference continuation_state
} {
    set event_path [_event_path $request $event_ordinal TERMINAL]
    set event [dict create \
        schema_version stage1e-report-attempt-terminal-event-v1 \
        event_type TERMINAL event_reference $event_path \
        event_ordinal $event_ordinal \
        open_event_reference [dict get $open event_reference] \
        role_ordinal [dict get $open role_ordinal] \
        report_role [dict get $open report_role] \
        role_attempt [dict get $open role_attempt] \
        request_identity [dict get $open request_identity] \
        execution_id [dict get $open execution_id] \
        attempt_id [dict get $open attempt_id] \
        workspace_identity [dict get $open workspace_identity] \
        producer_session_reference \
            [dict get $open producer_session_reference] \
        reservation_reference [dict get $open reservation_reference] \
        attempt_status $status \
        observed_path [dict get $output_observation observed_path] \
        byte_state [dict get $output_observation byte_state] \
        byte_count [dict get $output_observation byte_count] \
        integrity_state [dict get $output_observation integrity_state] \
        content_sha256_observation \
            [dict get $output_observation observation] \
        publication_receipt_reference UNAVAILABLE_WITH_REASON \
        command_result $command_result \
        end_observation [_observation $event_ordinal ATTEMPT_TERMINAL] \
        failure_reference $failure_reference \
        continuation_state $continuation_state \
        identity_state PENDING_IDENTITY_PROVIDER \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    set receipt [::stage1e::production_evidence_serializer_v1::publish_record \
        report_attempt_terminal_event $event $event_path \
        [dict get $request report_root]]
    return [dict create event $event receipt $receipt]
}

proc ::stage1e::production_vivado_collector_v1::_logical_record {
    open completion completion_kind
} {
    set terminal_reference NONE
    set interruption_reference NONE
    if {$completion_kind eq {TERMINAL}} {
        set terminal_reference [dict get $completion event_reference]
        set status [dict get $completion attempt_status]
        set observed_path [dict get $completion observed_path]
    } elseif {$completion_kind eq {INTERRUPTION}} {
        set interruption_reference [dict get $completion event_reference]
        set status INTERRUPTED
        set observed_path NONE
    } else {
        _raise LOGICAL_COMPLETION_INVALID \
            "Unknown logical completion kind '$completion_kind'."
    }
    set record [dict create \
        schema_version stage1e-report-attempt-logical-record-v1 \
        role_ordinal [dict get $open role_ordinal] \
        report_role [dict get $open report_role] \
        role_attempt [dict get $open role_attempt] \
        request_identity [dict get $open request_identity] \
        execution_id [dict get $open execution_id] \
        attempt_id [dict get $open attempt_id] \
        workspace_identity [dict get $open workspace_identity] \
        producer_session_reference \
            [dict get $open producer_session_reference] \
        reservation_reference [dict get $open reservation_reference] \
        open_event_reference [dict get $open event_reference] \
        terminal_event_reference $terminal_reference \
        interruption_event_reference $interruption_reference \
        attempt_status $status requested_path [dict get $open requested_path] \
        observed_path $observed_path \
        failure_reference [dict get $completion failure_reference]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        report_attempt_logical_record $record
    return $record
}

proc ::stage1e::production_vivado_collector_v1::_raw_item {
    request role evidence_state parser_state observed_path byte_state byte_count
    failure_reference condition_state integrity_observation
    publication_receipt_reference
} {
    set definition \
        [::stage1e::evidence_pipeline_contract_v1::role_definition $role]
    set source_references {}
    if {$observed_path ne {NONE}} { lappend source_references $observed_path }
    set item [dict create \
        schema_version stage1e-raw-evidence-item-v1 \
        ordinal [dict get $definition ordinal] role $role \
        requirement_state [dict get $definition requirement_state] \
        condition_state $condition_state \
        acquisition_owner [dict get $definition acquisition_owner] \
        evidence_state $evidence_state parser_state $parser_state \
        producer_session_reference \
            [dict get $request producer_session producer_session_reference] \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        requested_path [dict get $request role_output_paths $role] \
        observed_path $observed_path byte_state $byte_state \
        byte_count $byte_count \
        integrity_state [dict get $integrity_observation integrity_state] \
        content_sha256_observation $integrity_observation \
        publication_receipt_reference $publication_receipt_reference \
        format_profile [dict get $definition format_profile] \
        identity_state PENDING_IDENTITY_PROVIDER \
        identity_reference UNAVAILABLE_WITH_REASON \
        source_references $source_references \
        failure_reference $failure_reference foreign_state CURRENT]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        raw_evidence_item $item
    return $item
}

proc ::stage1e::production_vivado_collector_v1::_preflight_block_reason {
    request
} {
    if {[dict get $request conditional_decisions CONDITIONAL_BUS_SKEW] eq \
            {CONDITION_UNKNOWN}} {
        return CONDITIONAL_BUS_SKEW_CONDITION_UNKNOWN
    }
    foreach role [::stage1e::evidence_pipeline_contract_v1::collector_roles] {
        set definition \
            [::stage1e::evidence_pipeline_contract_v1::role_definition $role]
        if {[dict get $definition requirement_state] eq {CONDITIONAL} &&
                [dict get $request conditional_decisions $role] eq \
                    {NOT_REQUIRED}} {
            continue
        }
        if {[dict get $request command_availability $role] ne {AVAILABLE}} {
            return "COMMAND_[dict get $request command_availability $role]_$role"
        }
    }
    set handoff [dict get $request c_handoff]
    if {[dict get $handoff mode] eq {ROUTED_REPORTING} &&
            [dict get $request current_design_state] ne {OPENED_ROUTED_IMPL_1}} {
        return ROUTED_DESIGN_STATE_INVALID
    }
    if {[dict get $handoff mode] eq {FAILURE_EVIDENCE_ONLY} &&
            [dict get $request current_design_state] ne \
                {QUALIFIED_FAILURE_SAFE_VIEW}} {
        return FAILURE_SAFE_DESIGN_STATE_UNPROVEN
    }
    return NONE
}

proc ::stage1e::production_vivado_collector_v1::_blocked_role_records {
    request reason
} {
    set raw [dict get $request adopted_evidence]
    foreach role [::stage1e::evidence_pipeline_contract_v1::collector_roles] {
        set condition NOT_APPLICABLE
        if {$role eq {CONDITIONAL_BUS_SKEW}} {
            set condition [dict get $request conditional_decisions $role]
        }
        set state BLOCKED
        if {$reason eq {FAILURE_SAFE_DESIGN_STATE_UNPROVEN}} {
            set state UNAVAILABLE_FOR_STATE
        } elseif {$condition eq {NOT_REQUIRED}} {
            set state NOT_REQUIRED
        }
        set failure "1#COLLECTION:$reason"
        set integrity_state [expr {$state eq {NOT_REQUIRED} ?
            {NOT_APPLICABLE} : {UNAVAILABLE_WITH_REASON}}]
        set observation [_content_observation $request $role $integrity_state]
        lappend raw [_raw_item $request $role $state NOT_PARSED NONE \
            UNAVAILABLE -1 $failure $condition $observation \
            UNAVAILABLE_WITH_REASON]
    }
    return $raw
}

proc ::stage1e::production_vivado_collector_v1::_finalize {
    request reservations open_events terminal_events interruption_events
    logical_attempts raw_items terminal_status first_failure secondary_failures
    ledger_state preflight_state preflight_failure failure_category
    failure_code failure_phase
} {
    set ledger [dict create \
        schema_version stage1e-report-attempt-ledger-v1 \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        producer_session_reference \
            [dict get $request producer_session producer_session_reference] \
        report_contract_version stage1e-production-report-contract-v1 \
        reservations $reservations reservation_count [llength $reservations] \
        open_events $open_events terminal_events $terminal_events \
        interruption_events $interruption_events \
        logical_attempts $logical_attempts \
        event_count [expr {[llength $open_events] +
            [llength $terminal_events] + [llength $interruption_events]}] \
        preflight_state $preflight_state \
        preflight_failure_reference $preflight_failure \
        immutable_state IMMUTABLE_APPEND_ONLY retry_count 0 \
        terminal_state $ledger_state \
        identity_state PENDING_IDENTITY_PROVIDER \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    set raw_state COMPLETE
    if {$terminal_status ne {COMPLETED}} { set raw_state PARTIAL }
    set raw_inventory [dict create \
        schema_version stage1e-raw-evidence-inventory-v1 \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        producer_session_reference \
            [dict get $request producer_session producer_session_reference] \
        report_contract_version stage1e-production-report-contract-v1 \
        items $raw_items item_count [llength $raw_items] \
        inventory_state $raw_state identity_state PENDING_IDENTITY_PROVIDER \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    set coverage {}
    foreach item $raw_items {
        lappend coverage "[dict get $item role]=[dict get $item evidence_state]"
    }
    set result [dict create \
        schema_version stage1e-production-collector-result-v1 \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        producer_session_reference \
            [dict get $request producer_session producer_session_reference] \
        terminal_status $terminal_status \
        entry_mode [dict get $request c_handoff mode] \
        report_contract_version stage1e-production-report-contract-v1 \
        report_ledger_reference [_canonical_path \
            [dict get $request report_ledger_path]] \
        raw_evidence_inventory $raw_inventory role_coverage $coverage \
        first_failure_reference $first_failure \
        secondary_failure_references $secondary_failures \
        failure_category $failure_category failure_code $failure_code \
        failure_phase $failure_phase \
        evidence_state [expr {$terminal_status eq {COMPLETED} ?
            {COMPLETE} : {PARTIAL_PRESERVED}}] \
        identity_state PENDING_IDENTITY_PROVIDER \
        candidate_effect NOT_CREATED \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        report_ledger $ledger
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        collector_result $result
    ::stage1e::production_evidence_serializer_v1::publish_record \
        report_ledger $ledger [dict get $request report_ledger_path] \
        [dict get $request report_root]
    ::stage1e::production_evidence_serializer_v1::publish_record \
        collector_result $result [dict get $request collector_result_path] \
        [dict get $request report_root]
    return [dict create collector_result $result report_ledger $ledger]
}

proc ::stage1e::production_vivado_collector_v1::_collect {
    request facade
} {
    validate_request $request
    set block_reason [_preflight_block_reason $request]
    if {$block_reason ne {NONE}} {
        set failure "1#COLLECTION:$block_reason"
        return [_finalize $request {} {} {} {} {} \
            [_blocked_role_records $request $block_reason] \
            BLOCKED $failure {} BLOCKED BLOCKED $failure \
            COLLECTION $block_reason REPORT_COLLECTION]
    }

    set reservations {}
    set open_events {}
    set terminal_events {}
    set logical_attempts {}
    set raw_items [dict get $request adopted_evidence]
    set event_ordinal 0
    set first_failure NONE
    set secondary_failures {}
    set terminal_status COMPLETED
    set stop_all 0
    set failed_roles {}
    foreach role [::stage1e::evidence_pipeline_contract_v1::collector_roles] {
        set definition \
            [::stage1e::evidence_pipeline_contract_v1::role_definition $role]
        set output_path [dict get $request role_output_paths $role]
        set condition NOT_APPLICABLE
        if {$role eq {CONDITIONAL_BUS_SKEW}} {
            set condition [dict get $request conditional_decisions $role]
            if {$condition eq {NOT_REQUIRED}} {
                set observation \
                    [_content_observation $request $role NOT_APPLICABLE]
                lappend raw_items [_raw_item $request $role NOT_REQUIRED \
                    NOT_APPLICABLE NONE UNAVAILABLE -1 NONE $condition \
                    $observation UNAVAILABLE_WITH_REASON]
                continue
            }
        }
        set dependencies [dict get $definition continuation_dependencies]
        set dependency_failed 0
        foreach dependency $dependencies {
            if {[lsearch -exact $failed_roles $dependency] >= 0} {
                set dependency_failed 1
            }
        }
        if {$stop_all || $dependency_failed} {
            set reason [expr {$stop_all ? {STOP_ALL_REMAINING} :
                {CONTINUATION_DEPENDENCY_FAILED}}]
            set failure "[expr {$event_ordinal + 1}]#COLLECTION:$role:$reason"
            set observation [_content_observation $request $role \
                UNAVAILABLE_WITH_REASON]
            lappend raw_items [_raw_item $request $role BLOCKED NOT_PARSED \
                NONE UNAVAILABLE -1 $failure $condition $observation \
                UNAVAILABLE_WITH_REASON]
            continue
        }

        set reservation [_reserve_output $request $role 1]
        lappend reservations $reservation
        incr event_ordinal
        set open [_open_event $request $reservation $event_ordinal]
        lappend open_events $open
        set command_code [catch {_invoke $facade $role $output_path} \
            command_result command_options]
        if {$command_code} {
            set errorcode [dict get $command_options -errorcode]
            if {[lrange $errorcode 0 3] eq \
                    {STAGE1E FIXTURE REPORT PRODUCER_TERMINATED}} {
                set failure "$event_ordinal#COLLECTION:$role:INTERRUPTED"
                if {$first_failure eq {NONE}} { set first_failure $failure }
                return [dict create state PRODUCER_TERMINATED \
                    request $request open_events $open_events \
                    reservations $reservations \
                    terminal_events $terminal_events \
                    logical_attempts $logical_attempts raw_items $raw_items \
                    event_ordinal $event_ordinal first_failure $first_failure \
                    secondary_failures $secondary_failures \
                    interrupted_open_event $open]
            }
            set output_observation \
                [_observe_output $request $role $output_path]
            set status FAILED
            set continuation CONTINUE_INDEPENDENT_SAFE_ROLES
            if {[lrange $errorcode 0 3] eq \
                    {STAGE1E FIXTURE REPORT INTEGRITY_LOSS} ||
                    [lrange $errorcode 0 3] eq \
                    {STAGE1E FIXTURE REPORT BLOCKED}} {
                set status BLOCKED
                set continuation STOP_ALL_REMAINING
                set stop_all 1
                set terminal_status BLOCKED
            } elseif {$terminal_status ne {BLOCKED}} {
                set terminal_status FAILED
            }
            lappend failed_roles $role
            set failure "[expr {$event_ordinal + 1}]#COLLECTION:$role:$status"
            if {$first_failure eq {NONE}} {
                set first_failure $failure
            } else {
                lappend secondary_failures $failure
            }
            incr event_ordinal
            set terminal_bundle [_terminal_event $request $open $status \
                $event_ordinal $output_observation COMMAND_ERROR $failure \
                $continuation]
            set terminal [dict get $terminal_bundle event]
            lappend terminal_events $terminal
            lappend logical_attempts \
                [_logical_record $open $terminal TERMINAL]
            set receipt_reference \
                [::stage1e::production_evidence_serializer_v1::receipt_reference \
                    [dict get $terminal_bundle receipt]]
            lappend raw_items [_raw_item $request $role $status NOT_PARSED \
                [dict get $output_observation observed_path] \
                [dict get $output_observation byte_state] \
                [dict get $output_observation byte_count] $failure $condition \
                [dict get $output_observation observation] $receipt_reference]
            continue
        }

        set output_observation [_observe_output $request $role $output_path]
        set status COLLECTED
        set failure NONE
        set continuation CONTINUE_INDEPENDENT_SAFE_ROLES
        if {[dict get $output_observation byte_state] eq {MISSING}} {
            set status MISSING
            set terminal_status FAILED
            lappend failed_roles $role
            set failure "[expr {$event_ordinal + 1}]#COLLECTION:$role:MISSING"
        } elseif {[dict get $output_observation byte_state] eq {ZERO_BYTE}} {
            set status BLOCKED
            set terminal_status BLOCKED
            set stop_all 1
            set continuation STOP_ALL_REMAINING
            lappend failed_roles $role
            set failure \
                "[expr {$event_ordinal + 1}]#COLLECTION:$role:ZERO_BYTE"
        }
        if {$failure ne {NONE}} {
            if {$first_failure eq {NONE}} {
                set first_failure $failure
            } else {
                lappend secondary_failures $failure
            }
        }
        incr event_ordinal
        set terminal_bundle [_terminal_event $request $open $status \
            $event_ordinal $output_observation $command_result $failure \
            $continuation]
        set terminal [dict get $terminal_bundle event]
        lappend terminal_events $terminal
        lappend logical_attempts [_logical_record $open $terminal TERMINAL]
        set evidence_state [expr {$status eq {COLLECTED} ? {PRESENT} : $status}]
        set receipt_reference \
            [::stage1e::production_evidence_serializer_v1::receipt_reference \
                [dict get $terminal_bundle receipt]]
        lappend raw_items [_raw_item $request $role $evidence_state \
            NOT_PARSED [dict get $output_observation observed_path] \
            [dict get $output_observation byte_state] \
            [dict get $output_observation byte_count] $failure $condition \
            [dict get $output_observation observation] $receipt_reference]
    }
    set ledger_state $terminal_status
    if {$terminal_status eq {COMPLETED}} {
        set failure_category NONE
        set failure_code NONE
        set failure_phase NONE
    } else {
        set failure_category COLLECTION
        set failure_code REPORT_COLLECTION_INCOMPLETE
        set failure_phase REPORT_COLLECTION
    }
    return [_finalize $request $reservations $open_events $terminal_events {} \
        $logical_attempts $raw_items $terminal_status $first_failure \
        $secondary_failures $ledger_state CLEAR NONE $failure_category \
        $failure_code $failure_phase]
}

proc ::stage1e::production_vivado_collector_v1::collect {request} {
    validate_request $request
    set reason ACTUAL_VIVADO_REPORT_COMMANDS_NOT_QUALIFIED
    set failure "1#REPORT_COLLECTION:$reason"
    return [_finalize $request {} {} {} {} {} \
        [_blocked_role_records $request $reason] BLOCKED $failure {} BLOCKED \
        BLOCKED $failure TOOL_CAPABILITY $reason REPORT_COLLECTION]
}

proc ::stage1e::production_vivado_collector_v1::collect_fixture {request} {
    ::stage1e::evidence_pipeline_contract_v1::require_equal \
        FIXTURE_MODEL_VALIDATED [dict get $request execution_model_state] \
        {Synthetic Collector execution model}
    return [_collect $request SYNTHETIC_FIXTURE]
}
