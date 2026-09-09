# Stage 1E PRT02-D production evidence Parser candidate v1.
#
# The Parser consumes only exact sealed raw-evidence inventory entries. It
# performs no directory discovery, wildcard selection, newest-file choice,
# Vivado invocation, report regeneration, disposition, acceptance, identity
# issue, or candidate construction. All implemented profiles are fixture-only
# and explicitly require later Vivado 2024.1 format qualification.

set ::stage1e_parser_dir [file dirname [info script]]
set ::stage1e_parser_build [file dirname [file dirname $::stage1e_parser_dir]]
if {![llength [info commands \
        ::stage1e::evidence_pipeline_contract_v1::validate_record]]} {
    source [file join $::stage1e_parser_build lib \
        stage1e_evidence_pipeline_contract_v1.tcl]
}
if {![llength [info commands \
        ::stage1e::production_evidence_serializer_v1::publish_record]]} {
    source [file join $::stage1e_parser_build runtime identity \
        stage1e_production_evidence_serializer_v1.tcl]
}

namespace eval ::stage1e::production_evidence_parser_v1 {
    variable interface_version stage1e-production-evidence-parser-interface-v1
}
unset ::stage1e_parser_dir
unset ::stage1e_parser_build

proc ::stage1e::production_evidence_parser_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_evidence_parser_v1::_raise {code message} {
    return -code error -errorcode [list STAGE1E EVIDENCE PARSER $code] \
        $message
}

proc ::stage1e::production_evidence_parser_v1::inventory_role_order {} {
    return {
        MESSAGE_INVENTORY DRC_INVENTORY METHODOLOGY_INVENTORY
        TIMING_INVENTORY CLOCK_CDC_INVENTORY
        TIMING_EXCEPTION_INVENTORY UTILIZATION_INVENTORY
    }
}

proc ::stage1e::production_evidence_parser_v1::_record_type_for_inventory {
    role
} {
    set types [dict create \
        MESSAGE_INVENTORY message_inventory \
        DRC_INVENTORY drc_inventory \
        METHODOLOGY_INVENTORY methodology_inventory \
        TIMING_INVENTORY timing_inventory \
        CLOCK_CDC_INVENTORY clock_cdc_inventory \
        TIMING_EXCEPTION_INVENTORY timing_exception_inventory \
        UTILIZATION_INVENTORY utilization_inventory]
    return [dict get $types $role]
}

proc ::stage1e::production_evidence_parser_v1::_schema_for_inventory {role} {
    set schemas [dict create \
        MESSAGE_INVENTORY stage1e-message-inventory-v1 \
        DRC_INVENTORY stage1e-drc-inventory-v1 \
        METHODOLOGY_INVENTORY stage1e-methodology-inventory-v1 \
        TIMING_INVENTORY stage1e-timing-inventory-v1 \
        CLOCK_CDC_INVENTORY stage1e-clock-cdc-inventory-v1 \
        TIMING_EXCEPTION_INVENTORY stage1e-timing-exception-inventory-v1 \
        UTILIZATION_INVENTORY stage1e-utilization-inventory-v1]
    return [dict get $schemas $role]
}

proc ::stage1e::production_evidence_parser_v1::_canonical_path {path} {
    return [::stage1e::vivado_runtime_contract_v1::canonical_path $path]
}

proc ::stage1e::production_evidence_parser_v1::_validate_paths {request} {
    set root [_canonical_path [dict get $request parser_output_root]]
    if {![file exists $root] || ![file isdirectory $root]} {
        _raise OUTPUT_ROOT_INVALID \
            {Parser output root must exist and be a directory.}
    }
    set paths [dict get $request inventory_paths]
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields $paths \
        [inventory_role_order] {Parser inventory output paths}
    set seen {}
    foreach path [concat [list [dict get $request parser_result_path]] \
            [dict values $paths]] {
        if {[file pathtype $path] ne {absolute}} {
            _raise OUTPUT_PATH_INVALID \
                {Parser output paths must be literal absolute paths.}
        }
        set canonical [_canonical_path $path]
        if {![::stage1e::vivado_runtime_contract_v1::path_is_within \
                $canonical $root]} {
            _raise OUTPUT_PATH_ESCAPE \
                "Parser output path is outside its boundary: $path"
        }
        set key [string tolower $canonical]
        if {[dict exists $seen $key]} {
            _raise OUTPUT_PATH_DUPLICATE \
                "Parser output path is duplicated: $path"
        }
        dict set seen $key 1
        if {[file exists $canonical]} {
            _raise OUTPUT_PATH_COLLISION \
                "Parser output path already exists: $path"
        }
        if {![file exists [file dirname $canonical]] ||
                ![file isdirectory [file dirname $canonical]]} {
            _raise OUTPUT_PARENT_INVALID \
                "Parser output parent does not exist: [file dirname $canonical]"
        }
    }
    return 1
}

proc ::stage1e::production_evidence_parser_v1::validate_request {request} {
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        parser_request $request
    _validate_paths $request
    return 1
}

proc ::stage1e::production_evidence_parser_v1::_read_exact {item} {
    set path [dict get $item observed_path]
    if {$path eq {NONE} || [file pathtype $path] ne {absolute} ||
            ![file exists $path] || ![file isfile $path]} {
        _raise INPUT_MISSING \
            "Declared raw evidence path is unavailable: $path"
    }
    set bytes [::stage1e::atomic_publication_v1::read_binary $path]
    if {[string length $bytes] != [dict get $item byte_count]} {
        _raise INPUT_SIZE_MISMATCH \
            "Declared byte count differs for [dict get $item role]."
    }
    if {[dict get $item integrity_state] ne {VERIFIED_SHA256}} {
        _raise INPUT_INTEGRITY_UNAVAILABLE \
            "Raw evidence integrity is unavailable for [dict get $item role]."
    }
    set observation [dict get $item content_sha256_observation]
    set observed_digest [::stage1e::canonical_json_v1::digest_bytes $bytes]
    if {$observed_digest ne [dict get $observation content_sha256]} {
        _raise INPUT_DIGEST_MISMATCH \
            "Raw evidence SHA-256 differs for [dict get $item role]."
    }
    if {[dict get $item acquisition_owner] eq {COLLECTOR}} {
        set reference [dict get $item publication_receipt_reference]
        if {![regexp {^(.+)#([0-9a-f]{64})$} $reference -> \
                receipt_path receipt_digest] ||
                ![file exists $receipt_path] || ![file isfile $receipt_path]} {
            _raise INPUT_RECEIPT_MISSING \
                "Collector evidence receipt is unavailable for [dict get $item role]."
        }
        set receipt_bytes \
            [::stage1e::atomic_publication_v1::read_binary $receipt_path]
        if {[::stage1e::canonical_json_v1::digest_bytes $receipt_bytes] ne \
                $receipt_digest} {
            _raise INPUT_RECEIPT_MISMATCH \
                "Collector evidence receipt changed for [dict get $item role]."
        }
        set terminal \
            [::stage1e::evidence_pipeline_contract_v1::parse_record_bytes \
                report_attempt_terminal_event $receipt_bytes]
        foreach field {
            report_role request_identity execution_id attempt_id
            workspace_identity producer_session_reference observed_path
        } item_field {
            role request_identity execution_id attempt_id
            workspace_identity producer_session_reference observed_path
        } {
            if {[dict get $terminal $field] ne [dict get $item $item_field]} {
                _raise INPUT_RECEIPT_BINDING_MISMATCH \
                    "Collector receipt differs in $field."
            }
        }
        if {[dict get $terminal content_sha256_observation] ne $observation} {
            _raise INPUT_RECEIPT_BINDING_MISMATCH \
                {Collector receipt does not bind the raw integrity observation.}
        }
    } elseif {![string match {SUPPLIED_INTEGRITY_OBSERVATION:*} \
            [dict get $item publication_receipt_reference]]} {
        _raise INPUT_RECEIPT_MISSING \
            "Adopted file integrity receipt is unavailable for [dict get $item role]."
    }
    return $bytes
}

proc ::stage1e::production_evidence_parser_v1::_profile_lines {
    item bytes
} {
    if {[string length $bytes] >= 3 &&
            [binary encode hex [string range $bytes 0 2]] eq {efbbbf}} {
        _raise INPUT_ENCODING {Fixture evidence contains a UTF-8 BOM.}
    }
    set text [::stage1e::canonical_json_v1::decode_utf8_strict $bytes]
    if {[string first "\r" $text] >= 0} {
        _raise INPUT_LINE_ENDING \
            {Fixture evidence does not use the qualified LF line ending.}
    }
    if {$text eq {} || [string index $text end] ne "\n"} {
        _raise INPUT_TRUNCATED \
            {Fixture evidence lacks its final LF and end marker boundary.}
    }
    set lines [split [string range $text 0 end-1] "\n"]
    if {[llength $lines] < 6 ||
            [lindex $lines 0] ne {STAGE1E_EVIDENCE_FIXTURE_V1} ||
            [lindex $lines end] ne {END_STAGE1E_EVIDENCE_FIXTURE_V1}} {
        _raise INPUT_TRUNCATED \
            {Fixture evidence header or end marker is missing.}
    }
    set profile_lines {}
    set role_lines {}
    set scope_lines {}
    foreach line $lines {
        if {[string match {PROFILE|*} $line]} { lappend profile_lines $line }
        if {[string match {ROLE|*} $line]} { lappend role_lines $line }
        if {[string match {SCOPE|*} $line]} { lappend scope_lines $line }
    }
    if {[llength $profile_lines] != 1 || [llength $role_lines] != 1 ||
            [llength $scope_lines] != 1} {
        _raise INPUT_CONFLICT \
            {Fixture profile, role, or scope signature is ambiguous.}
    }
    set profile [lindex [split [lindex $profile_lines 0] |] 1]
    set role [lindex [split [lindex $role_lines 0] |] 1]
    set scope [lindex [split [lindex $scope_lines 0] |] 1]
    if {$profile ne [dict get $item format_profile]} {
        _raise PROFILE_MISMATCH \
            {Raw inventory profile differs from the evidence signature.}
    }
    set definition \
        [::stage1e::evidence_pipeline_contract_v1::profile_definition $profile]
    if {[dict get $definition role] ne [dict get $item role] ||
            $role ne [dict get $item role]} {
        _raise PROFILE_MISMATCH \
            {Fixture profile or role does not match the exact inventory role.}
    }
    if {$scope ne {CURRENT_SYNTHETIC}} {
        _raise HISTORICAL_INPUT \
            {Historical or foreign fixture scope cannot become a current fact.}
    }
    set records [lrange $lines 4 end-1]
    return [dict create profile $profile records $records]
}

proc ::stage1e::production_evidence_parser_v1::_integer {value label} {
    if {![string is integer -strict $value]} {
        _raise FIELD_INVALID "$label is not a canonical integer."
    }
    return $value
}

proc ::stage1e::production_evidence_parser_v1::_nonnegative {
    value label
} {
    set value [_integer $value $label]
    if {$value < 0} { _raise FIELD_INVALID "$label must be nonnegative." }
    return $value
}

proc ::stage1e::production_evidence_parser_v1::_list_field {value} {
    if {$value in {NONE UNKNOWN}} { return [list $value] }
    return [split $value ,]
}

proc ::stage1e::production_evidence_parser_v1::_known_identifier {
    family raw
} {
    set message_contract \
        [::stage1e::evidence_pipeline_contract_v1::message_contract]
    if {![dict exists $message_contract known_fixture_identifiers $family]} {
        return 0
    }
    return [expr {[lsearch -exact \
        [dict get $message_contract known_fixture_identifiers $family] \
        $raw] >= 0}]
}

proc ::stage1e::production_evidence_parser_v1::_identifier_fields {
    family raw
} {
    if {[_known_identifier $family $raw]} {
        return [list $raw $raw KNOWN]
    }
    return [list UNKNOWN $raw UNKNOWN]
}

proc ::stage1e::production_evidence_parser_v1::_parse_message {
    tokens source_reference occurrence
} {
    if {[llength $tokens] != 10} {
        _raise RECORD_TRUNCATED {MESSAGE fixture record has the wrong field count.}
    }
    lassign [_identifier_fields MESSAGE [lindex $tokens 1]] \
        identifier raw_identifier identifier_state
    set severity [lindex $tokens 2]
    if {$severity ni {INFO WARNING CRITICAL_WARNING ERROR}} {
        set normalized_severity UNKNOWN
    } else {
        set normalized_severity $severity
    }
    set record [dict create \
        identifier $identifier raw_identifier $raw_identifier \
        identifier_state $identifier_state severity $normalized_severity \
        native_severity $severity producer_phase [lindex $tokens 3] \
        phase_evidence "$source_reference#[lindex $tokens 3]" \
        count [_nonnegative [lindex $tokens 4] {MESSAGE count}] \
        text [string map {_ { }} [lindex $tokens 5]] \
        source_kind [lindex $tokens 6] \
        source_location [lindex $tokens 8] \
        affected_context [lindex $tokens 7] \
        source_references [list $source_reference] \
        occurrence_references [list "$source_reference#$occurrence"] \
        completeness [lindex $tokens 9]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        message_record $record
    return $record
}

proc ::stage1e::production_evidence_parser_v1::_parse_drc {
    tokens source_reference
} {
    if {[llength $tokens] != 6} {
        _raise RECORD_TRUNCATED {DRC fixture record has the wrong field count.}
    }
    lassign [_identifier_fields DRC [lindex $tokens 1]] \
        identifier raw_identifier identifier_state
    set record [dict create \
        identifier $identifier raw_identifier $raw_identifier \
        identifier_state $identifier_state severity [lindex $tokens 2] \
        native_severity [lindex $tokens 2] \
        count [_nonnegative [lindex $tokens 3] {DRC count}] \
        affected_objects [_list_field [lindex $tokens 4]] \
        report_reference $source_reference \
        source_references [list $source_reference] \
        completeness [lindex $tokens 5]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record drc_record $record
    return $record
}

proc ::stage1e::production_evidence_parser_v1::_parse_methodology {
    tokens source_reference
} {
    if {[llength $tokens] != 8} {
        _raise RECORD_TRUNCATED \
            {METHODOLOGY fixture record has the wrong field count.}
    }
    lassign [_identifier_fields METHODOLOGY [lindex $tokens 1]] \
        identifier raw_identifier identifier_state
    set record [dict create \
        identifier $identifier raw_identifier $raw_identifier \
        identifier_state $identifier_state severity [lindex $tokens 2] \
        count [_nonnegative [lindex $tokens 3] {Methodology count}] \
        affected_objects [_list_field [lindex $tokens 4]] \
        category [lindex $tokens 5] source [lindex $tokens 6] \
        report_reference $source_reference completeness [lindex $tokens 7]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        methodology_record $record
    return $record
}

proc ::stage1e::production_evidence_parser_v1::_parse_timing {
    tokens source_reference
} {
    if {[llength $tokens] != 10} {
        _raise RECORD_TRUNCATED {TIMING fixture record has the wrong field count.}
    }
    set raw [lindex $tokens 4]
    set normalized [lindex $tokens 5]
    set completeness [lindex $tokens 9]
    if {$normalized eq {UNKNOWN}} {
        set normalized_state UNKNOWN
        set completeness UNKNOWN
    } else {
        set normalized_state PRESENT
        set normalized [_integer $normalized {Timing normalized value}]
    }
    set record [dict create \
        check_type [lindex $tokens 1] path_group [lindex $tokens 2] \
        metric [lindex $tokens 3] raw_value $raw \
        normalized_value_state $normalized_state \
        normalized_value $normalized unit [lindex $tokens 6] \
        failing_endpoints [_nonnegative [lindex $tokens 7] \
            {Timing failing endpoints}] \
        path_count [_nonnegative [lindex $tokens 8] {Timing path count}] \
        source_reference $source_reference completeness $completeness]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        timing_record $record
    return $record
}

proc ::stage1e::production_evidence_parser_v1::_parse_clock_cdc {
    tokens source_reference
} {
    if {[llength $tokens] != 16} {
        _raise RECORD_TRUNCATED \
            {CLOCK_CDC fixture record has the wrong field count.}
    }
    set period [lindex $tokens 10]
    set completeness [lindex $tokens 15]
    if {$period eq {UNKNOWN}} {
        set period_state UNKNOWN
        set completeness UNKNOWN
    } else {
        set period_state PRESENT
        set period [_integer $period {Clock period}]
    }
    set record [dict create \
        record_kind [lindex $tokens 1] identifier [lindex $tokens 2] \
        classification [lindex $tokens 3] severity [lindex $tokens 4] \
        source_clock [lindex $tokens 5] \
        destination_clock [lindex $tokens 6] \
        source_object [lindex $tokens 7] \
        destination_object [lindex $tokens 8] \
        relationship [lindex $tokens 9] \
        period_state $period_state period_ps $period \
        waveform_ps [lindex $tokens 11] master_clock [lindex $tokens 12] \
        count [_nonnegative [lindex $tokens 13] {Clock/CDC count}] \
        reset_observation [lindex $tokens 14] \
        source_reference $source_reference completeness $completeness]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        clock_cdc_record $record
    return $record
}

proc ::stage1e::production_evidence_parser_v1::_parse_exception {
    tokens source_reference
} {
    if {[llength $tokens] != 13} {
        _raise RECORD_TRUNCATED \
            {EXCEPTION fixture record has the wrong field count.}
    }
    set record [dict create \
        identifier [lindex $tokens 1] command [lindex $tokens 2] \
        exception_type [lindex $tokens 3] source [lindex $tokens 4] \
        from_expression [lindex $tokens 5] \
        to_expression [lindex $tokens 6] \
        through_expression [lindex $tokens 7] \
        resolved_objects [_list_field [lindex $tokens 8]] \
        clock_pair [lindex $tokens 9] coverage [lindex $tokens 10] \
        state [lindex $tokens 11] source_reference $source_reference \
        completeness [lindex $tokens 12]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        timing_exception_record $record
    return $record
}

proc ::stage1e::production_evidence_parser_v1::_parse_utilization {
    tokens source_reference
} {
    if {[llength $tokens] != 9} {
        _raise RECORD_TRUNCATED \
            {UTILIZATION fixture record has the wrong field count.}
    }
    set record [dict create \
        resource [lindex $tokens 1] raw_resource [lindex $tokens 2] \
        used [_nonnegative [lindex $tokens 3] {Utilization used}] \
        available [_nonnegative [lindex $tokens 4] {Utilization available}] \
        utilization_milli_percent [_nonnegative [lindex $tokens 5] \
            {Utilization milli-percent}] \
        canonical_unit [lindex $tokens 6] scope [lindex $tokens 7] \
        source_reference $source_reference completeness [lindex $tokens 8]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        utilization_record $record
    return $record
}

proc ::stage1e::production_evidence_parser_v1::_stronger_state {
    current candidate
} {
    set order {
        COMPLETE PARTIAL UNKNOWN_IDENTIFIER UNKNOWN_NUMERIC UNSUPPORTED_FORMAT
        TRUNCATED_INPUT CONFLICT
    }
    if {[lsearch -exact $order $candidate] >
            [lsearch -exact $order $current]} {
        return $candidate
    }
    return $current
}

proc ::stage1e::production_evidence_parser_v1::_issue_state {options} {
    set errorcode [dict get $options -errorcode]
    set token [lindex $errorcode end]
    switch -- $token {
        INPUT_TRUNCATED - RECORD_TRUNCATED { return TRUNCATED_INPUT }
        PROFILE_UNSUPPORTED - PROFILE_MISMATCH { return UNSUPPORTED_FORMAT }
        INPUT_CONFLICT { return CONFLICT }
        HISTORICAL_INPUT { return PARTIAL }
        default { return PARTIAL }
    }
}

proc ::stage1e::production_evidence_parser_v1::_conflicts {
    family records
} {
    set seen {}
    set conflicts {}
    foreach record $records {
        switch -- $family {
            MESSAGE_INVENTORY {
                set key "[dict get $record raw_identifier]|[dict get $record producer_phase]|[dict get $record affected_context]"
                set value [dict get $record count]
            }
            DRC_INVENTORY {
                set key [dict get $record raw_identifier]
                set value [dict get $record count]
            }
            TIMING_INVENTORY {
                if {[dict get $record metric] ni {WNS_PS WHS_PS}} { continue }
                if {[dict get $record normalized_value_state] eq {UNKNOWN}} {
                    continue
                }
                set key "[dict get $record check_type]|[dict get $record metric]"
                set value [dict get $record normalized_value]
            }
            default { continue }
        }
        if {[dict exists $seen $key] && [dict get $seen $key] ne $value} {
            lappend conflicts "CONFLICT:$family:$key"
        } else {
            dict set seen $key $value
        }
    }
    return $conflicts
}

proc ::stage1e::production_evidence_parser_v1::_inventory {
    role request attempt_reference source_references profiles state records
    issues
} {
    set base [dict create \
        schema_version [_schema_for_inventory $role] \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        parser_attempt_reference $attempt_reference \
        source_references $source_references format_profiles $profiles \
        parse_state $state records $records record_count [llength $records] \
        issue_references $issues]
    if {$role eq {TIMING_INVENTORY}} {
        set detail_state [expr {[llength [_conflicts $role $records]] > 0 ?
            {CONFLICT} : {MATCH}}]
        dict set base summary_detail_state $detail_state
    }
    dict set base identity_state PENDING_IDENTITY_PROVIDER
    dict set base authority_boundary \
        [::stage1e::evidence_pipeline_contract_v1::authority_none]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        [_record_type_for_inventory $role] $base
    return $base
}

proc ::stage1e::production_evidence_parser_v1::parse {request} {
    validate_request $request
    set attempt_reference \
        "parser-attempt:[dict get $request execution_id]:[dict get $request attempt_id]:[dict get $request parser_attempt_ordinal]"
    set records {}
    set sources {}
    set profiles {}
    set states {}
    set issues {}
    foreach role [inventory_role_order] {
        dict set records $role {}
        dict set sources $role {}
        dict set profiles $role {}
        dict set states $role COMPLETE
        dict set issues $role {}
    }
    set role_states {}
    set selected_profiles {}
    set global_state COMPLETE
    set issue_ordinal 0
    foreach item [dict get $request raw_evidence_inventory items] {
        set role [dict get $item role]
        set evidence_state [dict get $item evidence_state]
        set definition \
            [::stage1e::evidence_pipeline_contract_v1::role_definition $role]
        set outputs [dict get $definition parser_outputs]
        if {[dict get $item foreign_state] ne {CURRENT}} {
            dict set role_states $role PARTIAL
            set global_state [_stronger_state $global_state PARTIAL]
            incr issue_ordinal
            set issue "$issue_ordinal#$role:FOREIGN_OR_HISTORICAL_INPUT"
            foreach output $outputs {
                if {[dict exists $states $output]} {
                    dict set states $output PARTIAL
                    dict lappend issues $output $issue
                }
            }
            continue
        }
        if {$evidence_state eq {NOT_REQUIRED}} {
            dict set role_states $role NOT_APPLICABLE
            continue
        }
        if {$evidence_state ne {PRESENT}} {
            dict set role_states $role PARTIAL
            if {[dict get $item condition_state] ne {NOT_REQUIRED}} {
                set global_state [_stronger_state $global_state PARTIAL]
            }
            continue
        }
        set profile [dict get $item format_profile]
        if {[string match {STRUCTURAL_*} $profile]} {
            dict set role_states $role NOT_APPLICABLE
            continue
        }
        set role_state COMPLETE
        set parse_code [catch {
            set bytes [_read_exact $item]
            set parsed [_profile_lines $item $bytes]
        } parse_message parse_options]
        if {$parse_code} {
            set role_state [_issue_state $parse_options]
            set global_state [_stronger_state $global_state $role_state]
            incr issue_ordinal
            set issue "$issue_ordinal#$role:$role_state"
            foreach output $outputs {
                if {[dict exists $states $output]} {
                    dict set states $output \
                        [_stronger_state [dict get $states $output] $role_state]
                    dict lappend issues $output $issue
                    dict lappend sources $output [dict get $item observed_path]
                }
            }
            dict set role_states $role $role_state
            continue
        }
        lappend selected_profiles $profile
        foreach output $outputs {
            if {[dict exists $profiles $output]} {
                dict lappend profiles $output $profile
                dict lappend sources $output [dict get $item observed_path]
            }
        }
        set occurrence 0
        foreach line [dict get $parsed records] {
            incr occurrence
            set tokens [split $line |]
            set kind [lindex $tokens 0]
            set record_code [catch {
                switch -- $kind {
                    MESSAGE {
                        set parsed_record [_parse_message $tokens \
                            [dict get $item observed_path] $occurrence]
                        dict lappend records MESSAGE_INVENTORY $parsed_record
                        if {[dict get $parsed_record identifier_state] eq \
                                {UNKNOWN}} {
                            set role_state UNKNOWN_IDENTIFIER
                        }
                    }
                    DRC {
                        set parsed_record [_parse_drc $tokens \
                            [dict get $item observed_path]]
                        dict lappend records DRC_INVENTORY $parsed_record
                        if {[dict get $parsed_record identifier_state] eq \
                                {UNKNOWN}} {
                            set role_state UNKNOWN_IDENTIFIER
                        }
                    }
                    METHODOLOGY {
                        set parsed_record [_parse_methodology $tokens \
                            [dict get $item observed_path]]
                        dict lappend records METHODOLOGY_INVENTORY $parsed_record
                        if {[dict get $parsed_record identifier_state] eq \
                                {UNKNOWN}} {
                            set role_state UNKNOWN_IDENTIFIER
                        }
                    }
                    TIMING {
                        set parsed_record [_parse_timing $tokens \
                            [dict get $item observed_path]]
                        dict lappend records TIMING_INVENTORY $parsed_record
                        if {[dict get $parsed_record \
                                normalized_value_state] eq {UNKNOWN}} {
                            set role_state UNKNOWN_NUMERIC
                        } elseif {[dict get $parsed_record completeness] ne \
                                {COMPLETE}} {
                            set role_state PARTIAL
                        }
                    }
                    CLOCK_CDC {
                        set parsed_record [_parse_clock_cdc $tokens \
                            [dict get $item observed_path]]
                        dict lappend records CLOCK_CDC_INVENTORY $parsed_record
                        if {[dict get $parsed_record period_state] eq \
                                {UNKNOWN}} {
                            set role_state UNKNOWN_NUMERIC
                        }
                    }
                    EXCEPTION {
                        dict lappend records TIMING_EXCEPTION_INVENTORY \
                            [_parse_exception $tokens \
                                [dict get $item observed_path]]
                    }
                    UTILIZATION {
                        dict lappend records UTILIZATION_INVENTORY \
                            [_parse_utilization $tokens \
                                [dict get $item observed_path]]
                    }
                    JOURNAL { }
                    default {
                        _raise RECORD_KIND_UNKNOWN \
                            "Unknown fixture record kind '$kind'."
                    }
                }
            } record_message record_options]
            if {$record_code} {
                set record_state [_issue_state $record_options]
                set role_state [_stronger_state $role_state $record_state]
                incr issue_ordinal
                set issue "$issue_ordinal#$role:$record_state"
                foreach output $outputs {
                    if {[dict exists $states $output]} {
                        dict lappend issues $output $issue
                    }
                }
            }
        }
        if {$role_state eq {UNKNOWN_IDENTIFIER}} {
            incr issue_ordinal
            set issue "$issue_ordinal#$role:UNKNOWN_IDENTIFIER"
            foreach output $outputs {
                if {[dict exists $states $output]} {
                    dict lappend issues $output $issue
                    dict set states $output \
                        [_stronger_state [dict get $states $output] \
                            UNKNOWN_IDENTIFIER]
                }
            }
        }
        if {$role_state eq {UNKNOWN_NUMERIC}} {
            incr issue_ordinal
            set issue "$issue_ordinal#$role:UNKNOWN_NUMERIC"
            foreach output $outputs {
                if {[dict exists $states $output]} {
                    dict lappend issues $output $issue
                    dict set states $output \
                        [_stronger_state [dict get $states $output] \
                            UNKNOWN_NUMERIC]
                }
            }
        }
        set global_state [_stronger_state $global_state $role_state]
        dict set role_states $role $role_state
    }

    foreach family {MESSAGE_INVENTORY DRC_INVENTORY TIMING_INVENTORY} {
        set conflicts [_conflicts $family [dict get $records $family]]
        if {[llength $conflicts] > 0} {
            dict set states $family CONFLICT
            foreach conflict $conflicts {
                incr issue_ordinal
                dict lappend issues $family "$issue_ordinal#$conflict"
            }
            set global_state CONFLICT
        }
    }
    foreach role [inventory_role_order] {
        if {[dict get $states $role] eq {COMPLETE} &&
                [llength [dict get $records $role]] == 0} {
            dict set states $role PARTIAL
            incr issue_ordinal
            dict lappend issues $role "$issue_ordinal#$role:NO_RECORDS"
            set global_state [_stronger_state $global_state PARTIAL]
        }
    }

    set inventories {}
    set inventory_references {}
    set preserved 0
    foreach role [inventory_role_order] {
        set inventory [_inventory $role $request $attempt_reference \
            [dict get $sources $role] [dict get $profiles $role] \
            [dict get $states $role] [dict get $records $role] \
            [dict get $issues $role]]
        dict set inventories $role $inventory
        incr preserved [dict get $inventory record_count]
        set path [dict get $request inventory_paths $role]
        ::stage1e::production_evidence_serializer_v1::publish_record \
            [_record_type_for_inventory $role] $inventory $path \
            [dict get $request parser_output_root]
        lappend inventory_references "$role=[_canonical_path $path]"
    }

    set all_issues {}
    foreach role [inventory_role_order] {
        foreach issue [dict get $issues $role] { lappend all_issues $issue }
    }
    set first_failure NONE
    set secondary_failures {}
    if {[llength $all_issues] > 0} {
        set first_failure [lindex $all_issues 0]
        set secondary_failures [lrange $all_issues 1 end]
    }
    set attempt_sources {}
    foreach item [dict get $request raw_evidence_inventory items] {
        foreach reference [dict get $item source_references] {
            if {[lsearch -exact $attempt_sources $reference] < 0} {
                lappend attempt_sources $reference
            }
        }
    }
    set attempt [dict create \
        schema_version stage1e-parser-attempt-v1 \
        parser_attempt_reference $attempt_reference \
        parser_attempt_ordinal [dict get $request parser_attempt_ordinal] \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        parser_interface stage1e-production-evidence-parser-interface-v1 \
        start_observation \
            "PARSER_START:[dict get $request parser_attempt_ordinal]" \
        terminal_observation \
            "PARSER_TERMINAL:[dict get $request parser_attempt_ordinal]" \
        attempt_state $global_state source_references $attempt_sources \
        issue_references $all_issues immutable_state IMMUTABLE_APPEND_ONLY \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    set result [dict create \
        schema_version stage1e-production-parser-result-v1 \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        parser_attempt $attempt \
        parser_interface stage1e-production-evidence-parser-interface-v1 \
        terminal_state $global_state selected_profiles $selected_profiles \
        inventory_references $inventory_references \
        preserved_record_count $preserved \
        first_failure_reference $first_failure \
        secondary_failure_references $secondary_failures \
        identity_state PENDING_IDENTITY_PROVIDER candidate_effect NOT_CREATED \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        parser_result $result
    ::stage1e::production_evidence_serializer_v1::publish_record \
        parser_result $result [dict get $request parser_result_path] \
        [dict get $request parser_output_root]
    return [dict create parser_result $result inventories $inventories \
        role_states $role_states]
}
