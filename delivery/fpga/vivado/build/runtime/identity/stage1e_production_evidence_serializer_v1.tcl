# Stage 1E PRT02-D structural evidence serializer candidate v1.
#
# The serializer validates exact D records, delegates canonical JSON bytes to
# the admitted PRT02-A codec, and delegates no-overwrite publication to the
# admitted atomic publisher. It creates no identity, finding disposition,
# acceptance decision, or implementation-result candidate.

set ::stage1e_evidence_serializer_dir [file dirname [info script]]
set ::stage1e_evidence_serializer_build [file dirname [file dirname \
    $::stage1e_evidence_serializer_dir]]
if {![llength [info commands \
        ::stage1e::evidence_pipeline_contract_v1::validate_record]]} {
    source [file join $::stage1e_evidence_serializer_build lib \
        stage1e_evidence_pipeline_contract_v1.tcl]
}

namespace eval ::stage1e::production_evidence_serializer_v1 {
    variable interface_version stage1e-production-evidence-serializer-interface-v1
}
unset ::stage1e_evidence_serializer_dir
unset ::stage1e_evidence_serializer_build

proc ::stage1e::production_evidence_serializer_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_evidence_serializer_v1::_raise {code message} {
    return -code error -errorcode [list STAGE1E EVIDENCE SERIALIZER $code] \
        $message
}

proc ::stage1e::production_evidence_serializer_v1::canonical_bytes {
    record_type record
} {
    return [::stage1e::evidence_pipeline_contract_v1::canonical_record_bytes \
        $record_type $record]
}

proc ::stage1e::production_evidence_serializer_v1::verify_bytes {
    record_type bytes
} {
    ::stage1e::evidence_pipeline_contract_v1::parse_record_bytes \
        $record_type $bytes
    return 1
}

proc ::stage1e::production_evidence_serializer_v1::publish_record {
    record_type record final_path boundary_path
} {
    if {[file exists $final_path]} {
        _raise PUBLICATION_COLLISION \
            "Structural evidence destination already exists: $final_path"
    }
    set bytes [canonical_bytes $record_type $record]
    set verifier [list \
        ::stage1e::production_evidence_serializer_v1::verify_bytes \
        $record_type]
    return [::stage1e::atomic_publication_v1::publish \
        $final_path $bytes $boundary_path $verifier]
}

proc ::stage1e::production_evidence_serializer_v1::read_record {
    record_type path
} {
    set bytes [::stage1e::atomic_publication_v1::read_binary $path]
    return [::stage1e::evidence_pipeline_contract_v1::parse_record_bytes \
        $record_type $bytes]
}

proc ::stage1e::production_evidence_serializer_v1::_session_reference {
    binding
} {
    if {[dict exists $binding producer_session_reference]} {
        return [dict get $binding producer_session_reference]
    }
    if {[dict exists $binding producer_session producer_session_reference]} {
        return [dict get $binding producer_session producer_session_reference]
    }
    _raise REFERENCE_BINDING_INVALID \
        {Sealed-reference binding lacks a producer session.}
}

proc ::stage1e::production_evidence_serializer_v1::receipt_reference {
    receipt
} {
    return "[dict get $receipt final_path]#[dict get $receipt byte_sha256]"
}

proc ::stage1e::production_evidence_serializer_v1::reference_record_type {
    reference_role
} {
    set types [dict create \
        FULL_OPERATION_LEDGER fixture_operation_ledger \
        FULL_REPORT_ATTEMPT_LEDGER report_ledger \
        COLLECTOR_RESULT collector_result \
        PARSER_RESULT parser_result \
        MESSAGE_INVENTORY message_inventory \
        DRC_INVENTORY drc_inventory \
        METHODOLOGY_INVENTORY methodology_inventory \
        TIMING_INVENTORY timing_inventory \
        CLOCK_CDC_INVENTORY clock_cdc_inventory \
        TIMING_EXCEPTION_INVENTORY timing_exception_inventory \
        UTILIZATION_INVENTORY utilization_inventory \
        VIVADO_COMPONENT_RESULT fixture_structural_evidence \
        HOST_RESULT_OR_DISCONNECTED EXPLICIT_HOST_DISCONNECTED \
        FORBIDDEN_BOUNDARY_EVIDENCE fixture_structural_evidence \
        EVIDENCE_SET evidence_set_inventory]
    if {![dict exists $types $reference_role]} {
        _raise REFERENCE_ROLE_INVALID \
            "Unknown sealed-reference role '$reference_role'."
    }
    return [dict get $types $reference_role]
}

proc ::stage1e::production_evidence_serializer_v1::make_file_reference {
    reference_role record_type path binding
} {
    set canonical \
        [::stage1e::vivado_runtime_contract_v1::canonical_path $path]
    if {![file exists $canonical] || ![file isfile $canonical]} {
        _raise REFERENCE_MISSING \
            "Sealed reference file is missing: $canonical"
    }
    set bytes [::stage1e::atomic_publication_v1::read_binary $canonical]
    set record [::stage1e::evidence_pipeline_contract_v1::parse_record_bytes \
        $record_type $bytes]
    set observation \
        [::stage1e::evidence_pipeline_contract_v1::integrity_observation \
            $reference_role $binding VERIFIED_SHA256 $bytes]
    set reference [dict create \
        schema_version stage1e-sealed-evidence-reference-v1 \
        reference_role $reference_role record_type $record_type \
        location_state FILE literal_path $canonical \
        request_identity [dict get $binding request_identity] \
        execution_id [dict get $binding execution_id] \
        attempt_id [dict get $binding attempt_id] \
        workspace_identity [dict get $binding workspace_identity] \
        producer_session_reference [_session_reference $binding] \
        integrity_state VERIFIED_SHA256 \
        content_sha256_observation $observation \
        publication_receipt_reference \
            "$canonical#[dict get $observation content_sha256]" \
        availability_state PRESENT \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    validate_reference $reference $reference_role $binding
    return $reference
}

proc ::stage1e::production_evidence_serializer_v1::make_nonfile_reference {
    reference_role record_type location_state availability_state binding
} {
    if {$location_state ni {EXPLICIT_DISCONNECTED STRUCTURAL_NON_FILE}} {
        _raise REFERENCE_LOCATION_INVALID \
            {Non-file reference requires an explicit non-file location state.}
    }
    set observation \
        [::stage1e::evidence_pipeline_contract_v1::integrity_observation \
            $reference_role $binding NOT_APPLICABLE]
    set reference [dict create \
        schema_version stage1e-sealed-evidence-reference-v1 \
        reference_role $reference_role record_type $record_type \
        location_state $location_state literal_path NONE \
        request_identity [dict get $binding request_identity] \
        execution_id [dict get $binding execution_id] \
        attempt_id [dict get $binding attempt_id] \
        workspace_identity [dict get $binding workspace_identity] \
        producer_session_reference [_session_reference $binding] \
        integrity_state NOT_APPLICABLE \
        content_sha256_observation $observation \
        publication_receipt_reference UNAVAILABLE_WITH_REASON \
        availability_state $availability_state \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    validate_reference $reference $reference_role $binding
    return $reference
}

proc ::stage1e::production_evidence_serializer_v1::open_reference {
    reference
} {
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        sealed_evidence_reference $reference
    if {[dict get $reference location_state] ne {FILE}} { return {} }
    set path [dict get $reference literal_path]
    if {[file pathtype $path] ne {absolute} ||
            ![file exists $path] || ![file isfile $path]} {
        _raise REFERENCE_MISSING "Sealed reference file is missing: $path"
    }
    set canonical \
        [::stage1e::vivado_runtime_contract_v1::canonical_path $path]
    if {$canonical ne $path} {
        _raise REFERENCE_PATH_INVALID \
            {Sealed reference path is not canonical.}
    }
    set bytes [::stage1e::atomic_publication_v1::read_binary $path]
    set observation [dict get $reference content_sha256_observation]
    if {[string length $bytes] != [dict get $observation byte_count]} {
        _raise REFERENCE_SIZE_MISMATCH \
            "Sealed reference byte count differs: $path"
    }
    set digest [::stage1e::canonical_json_v1::digest_bytes $bytes]
    if {$digest ne [dict get $observation content_sha256]} {
        _raise REFERENCE_DIGEST_MISMATCH \
            "Sealed reference SHA-256 differs: $path"
    }
    set expected_receipt "$path#$digest"
    if {[dict get $reference publication_receipt_reference] ne \
            $expected_receipt} {
        _raise REFERENCE_RECEIPT_MISMATCH \
            {Sealed reference publication receipt does not match its bytes.}
    }
    set record [::stage1e::evidence_pipeline_contract_v1::parse_record_bytes \
        [dict get $reference record_type] $bytes]
    foreach field {request_identity execution_id attempt_id workspace_identity} {
        if {[dict exists $record $field] &&
                [dict get $record $field] ne [dict get $reference $field]} {
            _raise REFERENCE_BINDING_MISMATCH \
                "Sealed referenced record differs in $field."
        }
    }
    if {[dict exists $record producer_session_reference] &&
            [dict get $record producer_session_reference] ne
                [dict get $reference producer_session_reference]} {
        _raise REFERENCE_BINDING_MISMATCH \
            {Sealed referenced record differs in producer session.}
    }
    return $record
}

proc ::stage1e::production_evidence_serializer_v1::validate_reference {
    reference {expected_role {}} {expected_binding {}}
} {
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        sealed_evidence_reference $reference
    if {$expected_role ne {} &&
            [dict get $reference reference_role] ne $expected_role} {
        _raise REFERENCE_ROLE_MISMATCH \
            "Expected sealed-reference role '$expected_role'."
    }
    set role [dict get $reference reference_role]
    set expected_record_type [reference_record_type $role]
    if {[dict get $reference record_type] ne $expected_record_type} {
        _raise REFERENCE_RECORD_TYPE_MISMATCH \
            "Sealed-reference role '$role' requires record type '$expected_record_type'."
    }
    if {$expected_binding ne {}} {
        foreach field {
            request_identity execution_id attempt_id workspace_identity
        } {
            if {[dict get $reference $field] ne
                    [dict get $expected_binding $field]} {
                _raise REFERENCE_BINDING_MISMATCH \
                    "Sealed reference differs in $field."
            }
        }
        if {[dict get $reference producer_session_reference] ne
                [_session_reference $expected_binding]} {
            _raise REFERENCE_BINDING_MISMATCH \
                {Sealed reference differs in producer session.}
        }
    }
    if {[dict get $reference location_state] eq {EXPLICIT_DISCONNECTED}} {
        if {[dict get $reference availability_state] ne \
                {DISCONNECTED_EXPLICIT}} {
            _raise REFERENCE_AVAILABILITY_INVALID \
                {Disconnected reference lacks explicit disconnected state.}
        }
        return 1
    }
    if {[dict get $reference location_state] eq {STRUCTURAL_NON_FILE}} {
        if {[dict get $reference availability_state] ne {PRESENT}} {
            _raise REFERENCE_AVAILABILITY_INVALID \
                {Structural non-file reference is not present.}
        }
        return 1
    }
    open_reference $reference
    return 1
}

proc ::stage1e::production_evidence_serializer_v1::projection_row {
    ordinal role status reference
} {
    set row [dict create ordinal $ordinal role $role status $status \
        reference $reference]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        ledger_projection_row $row
    return $row
}

proc ::stage1e::production_evidence_serializer_v1::_derived_projection_rows {
    ledger_role record
} {
    set rows {}
    switch -- $ledger_role {
        OPERATION_LEDGER {
            foreach row [dict get $record entries] {
                ::stage1e::evidence_pipeline_contract_v1::validate_record \
                    ledger_projection_row $row
                lappend rows $row
            }
        }
        REPORT_ATTEMPT_LEDGER {
            foreach logical [dict get $record logical_attempts] {
                lappend rows [projection_row \
                    [dict get $logical role_ordinal] \
                    [dict get $logical report_role] \
                    [dict get $logical attempt_status] \
                    [dict get $logical open_event_reference]]
            }
        }
        default {
            _raise PROJECTION_ROLE_INVALID \
                "Unknown full-ledger projection role '$ledger_role'."
        }
    }
    return $rows
}

proc ::stage1e::production_evidence_serializer_v1::compare_projection {
    full_ledger_reference compact_rows
} {
    validate_reference $full_ledger_reference
    set reference_role [dict get $full_ledger_reference reference_role]
    switch -- $reference_role {
        FULL_OPERATION_LEDGER { set ledger_role OPERATION_LEDGER }
        FULL_REPORT_ATTEMPT_LEDGER { set ledger_role REPORT_ATTEMPT_LEDGER }
        default {
            _raise PROJECTION_ROLE_INVALID \
                "Reference '$reference_role' is not a full ledger."
        }
    }
    set full_record [open_reference $full_ledger_reference]
    set full_rows [_derived_projection_rows $ledger_role $full_record]
    foreach row $compact_rows {
        ::stage1e::evidence_pipeline_contract_v1::validate_record \
            ledger_projection_row $row
    }
    set state MATCH
    set details {}
    if {[llength $full_rows] != [llength $compact_rows]} {
        set state MISMATCH
        lappend details ROW_COUNT_MISMATCH
    }
    set maximum [expr {max([llength $full_rows], [llength $compact_rows])}]
    for {set index 0} {$index < $maximum} {incr index} {
        if {$index >= [llength $full_rows] ||
                $index >= [llength $compact_rows]} {
            continue
        }
        if {[lindex $full_rows $index] ne [lindex $compact_rows $index]} {
            set state MISMATCH
            lappend details "ROW_[expr {$index + 1}]_MISMATCH"
        }
    }
    set result [dict create \
        schema_version stage1e-ledger-projection-comparison-v1 \
        ledger_role $ledger_role \
        full_ledger_reference $full_ledger_reference \
        derived_full_rows $full_rows compact_rows $compact_rows \
        comparison_state $state mismatch_details $details]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        ledger_projection_comparison $result
    return $result
}

proc ::stage1e::production_evidence_serializer_v1::reference_role_order {} {
    return {
        FULL_OPERATION_LEDGER
        FULL_REPORT_ATTEMPT_LEDGER
        COLLECTOR_RESULT
        PARSER_RESULT
        MESSAGE_INVENTORY
        DRC_INVENTORY
        METHODOLOGY_INVENTORY
        TIMING_INVENTORY
        CLOCK_CDC_INVENTORY
        TIMING_EXCEPTION_INVENTORY
        UTILIZATION_INVENTORY
        VIVADO_COMPONENT_RESULT
        HOST_RESULT_OR_DISCONNECTED
        FORBIDDEN_BOUNDARY_EVIDENCE
    }
}

proc ::stage1e::production_evidence_serializer_v1::_ordered_references {
    reference_map binding
} {
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields \
        $reference_map [reference_role_order] {Evidence-set reference map}
    set result {}
    foreach role [reference_role_order] {
        set reference [dict get $reference_map $role]
        validate_reference $reference $role $binding
        lappend result $reference
    }
    return $result
}

proc ::stage1e::production_evidence_serializer_v1::_raw_by_role {
    inventory
} {
    set by_role {}
    foreach item [dict get $inventory items] {
        set role [dict get $item role]
        if {[dict exists $by_role $role]} {
            _raise DUPLICATE_ROLE \
                "Raw evidence inventory contains duplicate role '$role'."
        }
        dict set by_role $role $item
    }
    return $by_role
}

proc ::stage1e::production_evidence_serializer_v1::_parser_state_for {
    role raw parser_states
} {
    if {[dict exists $parser_states $role]} {
        return [dict get $parser_states $role]
    }
    return [dict get $raw parser_state]
}

proc ::stage1e::production_evidence_serializer_v1::build_evidence_set {
    raw_inventory parser_states reference_map projection_comparisons
} {
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        raw_evidence_inventory $raw_inventory
    ::stage1e::evidence_pipeline_contract_v1::require_dictionary \
        $parser_states {Parser role-state map}
    if {[llength $projection_comparisons] != 2} {
        _raise PROJECTION_SET_INVALID \
            {Evidence set requires operation and report projection comparisons.}
    }
    set comparison_roles {}
    set projections_clear 1
    foreach comparison $projection_comparisons {
        ::stage1e::evidence_pipeline_contract_v1::validate_record \
            ledger_projection_comparison $comparison
        lappend comparison_roles [dict get $comparison ledger_role]
        if {[dict get $comparison comparison_state] ne {MATCH}} {
            set projections_clear 0
        }
    }
    if {$comparison_roles ne {OPERATION_LEDGER REPORT_ATTEMPT_LEDGER}} {
        _raise PROJECTION_SET_INVALID \
            {Projection comparisons must be operation ledger then report ledger.}
    }
    set ordered_references [_ordered_references $reference_map $raw_inventory]
    set expected_projection_references [list \
        [dict get $reference_map FULL_OPERATION_LEDGER] \
        [dict get $reference_map FULL_REPORT_ATTEMPT_LEDGER]]
    set comparison_index 0
    foreach comparison $projection_comparisons {
        if {[dict get $comparison full_ledger_reference] ne
                [lindex $expected_projection_references $comparison_index]} {
            _raise PROJECTION_REFERENCE_MISMATCH \
                {Projection comparison does not use the evidence-set full ledger.}
        }
        incr comparison_index
    }

    set by_role [_raw_by_role $raw_inventory]
    set items {}
    set required_roles {}
    set conditional_roles {}
    set adopted_roles {}
    set present_roles {}
    set missing_roles {}
    set failed_roles {}
    set interrupted_roles {}
    set foreign_roles {}
    set unsupported_roles {}
    set conflict_roles {}
    set inventory_state COMPLETE
    set ordinal 0
    foreach role [::stage1e::evidence_pipeline_contract_v1::role_order] {
        incr ordinal
        set definition \
            [::stage1e::evidence_pipeline_contract_v1::role_definition $role]
        if {![dict exists $by_role $role]} {
            _raise ROLE_MISSING \
                "Raw evidence inventory omitted REPORT role '$role'."
        }
        set raw [dict get $by_role $role]
        set requirement [dict get $raw requirement_state]
        set condition [dict get $raw condition_state]
        set evidence_state [dict get $raw evidence_state]
        set parser_state [_parser_state_for $role $raw $parser_states]
        if {$requirement eq {CONDITIONAL}} {
            lappend conditional_roles $role
        } elseif {$requirement eq {ADOPTED_REQUIRED}} {
            lappend adopted_roles $role
        } elseif {$requirement eq {REQUIRED}} {
            lappend required_roles $role
        }
        if {$condition eq {REQUIRED} &&
                [lsearch -exact $required_roles $role] < 0} {
            lappend required_roles $role
        }
        switch -- $evidence_state {
            PRESENT { lappend present_roles $role }
            MISSING { lappend missing_roles $role }
            FAILED - BLOCKED { lappend failed_roles $role }
            INTERRUPTED { lappend interrupted_roles $role }
            FOREIGN_EXECUTION { lappend foreign_roles $role }
            UNSUPPORTED_FORMAT { lappend unsupported_roles $role }
            CONFLICT { lappend conflict_roles $role }
        }
        if {$parser_state eq {UNSUPPORTED_FORMAT}} {
            if {[lsearch -exact $unsupported_roles $role] < 0} {
                lappend unsupported_roles $role
            }
        }
        if {$parser_state eq {CONFLICT}} {
            if {[lsearch -exact $conflict_roles $role] < 0} {
                lappend conflict_roles $role
            }
        }
        set effect SATISFIED
        if {$condition eq {CONDITION_UNKNOWN}} {
            set effect BLOCKING
        } elseif {$condition eq {NOT_REQUIRED}} {
            set effect NOT_REQUIRED
        } elseif {$evidence_state ne {PRESENT} ||
                $parser_state ni {COMPLETE NOT_APPLICABLE}} {
            set effect BLOCKING
        }
        if {$effect eq {BLOCKING}} { set inventory_state PARTIAL }
        set reference NONE
        if {[llength [dict get $raw source_references]] > 0} {
            set reference [lindex [dict get $raw source_references] 0]
        }
        lappend items [dict create \
            ordinal $ordinal role $role requirement_state $requirement \
            condition_state $condition evidence_state $evidence_state \
            parser_state $parser_state producer_reference $reference \
            producer_session_reference \
                [dict get $raw producer_session_reference] \
            request_identity [dict get $raw request_identity] \
            execution_id [dict get $raw execution_id] \
            attempt_id [dict get $raw attempt_id] \
            workspace_identity [dict get $raw workspace_identity] \
            identity_state [dict get $raw identity_state] \
            identity_reference [dict get $raw identity_reference] \
            failure_reference [dict get $raw failure_reference] \
            foreign_state [dict get $raw foreign_state] \
            completeness_effect $effect]
    }
    if {!$projections_clear} { set inventory_state PARTIAL }
    foreach blocking [list $missing_roles $failed_roles $interrupted_roles \
            $foreign_roles $unsupported_roles $conflict_roles] {
        if {[llength $blocking] > 0} { set inventory_state PARTIAL }
    }
    set result [dict create \
        schema_version stage1e-evidence-set-inventory-v1 \
        request_identity [dict get $raw_inventory request_identity] \
        execution_id [dict get $raw_inventory execution_id] \
        attempt_id [dict get $raw_inventory attempt_id] \
        workspace_identity [dict get $raw_inventory workspace_identity] \
        producer_session_reference \
            [dict get $raw_inventory producer_session_reference] \
        report_contract_version stage1e-production-report-contract-v1 \
        required_roles $required_roles conditional_roles $conditional_roles \
        adopted_roles $adopted_roles present_roles $present_roles \
        missing_roles $missing_roles failed_roles $failed_roles \
        interrupted_roles $interrupted_roles \
        foreign_execution_roles $foreign_roles \
        unsupported_format_roles $unsupported_roles \
        conflict_roles $conflict_roles \
        full_ledger_references $ordered_references \
        projection_comparisons $projection_comparisons items $items \
        item_count [llength $items] inventory_state $inventory_state \
        identity_state PENDING_IDENTITY_PROVIDER candidate_effect NOT_CREATED \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        evidence_set_inventory $result
    return $result
}

proc ::stage1e::production_evidence_serializer_v1::validate_failure_order {
    first_reference secondary_references
} {
    if {$first_reference eq {NONE}} {
        if {[llength $secondary_references] != 0} {
            _raise FAILURE_ORDER_INVALID \
                {Secondary failures exist without a first failure.}
        }
        return 1
    }
    if {![regexp {^([1-9][0-9]*)#.+$} $first_reference -> prior]} {
        _raise FAILURE_ORDER_INVALID \
            {First failure reference lacks a positive ordinal prefix.}
    }
    foreach reference $secondary_references {
        if {![regexp {^([1-9][0-9]*)#.+$} $reference -> ordinal]} {
            _raise FAILURE_ORDER_INVALID \
                {Secondary failure reference lacks a positive ordinal prefix.}
        }
        if {$ordinal <= $prior} {
            _raise FAILURE_ORDER_INVALID \
                {Failure references are not in strictly increasing order.}
        }
        set prior $ordinal
    }
    return 1
}
