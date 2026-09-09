# Stage 1E PRT02-D evidence structural-review controller candidate v1.
#
# This append-only controller owns structural completeness only. It cannot
# disposition findings, apply production policy, decide implementation
# acceptance, create identities, or create an implementation-result candidate.

set ::stage1e_evidence_controller_dir [file dirname [info script]]
set ::stage1e_evidence_controller_build \
    [file dirname $::stage1e_evidence_controller_dir]
if {![llength [info commands \
        ::stage1e::evidence_pipeline_contract_v1::validate_record]]} {
    source [file join $::stage1e_evidence_controller_build lib \
        stage1e_evidence_pipeline_contract_v1.tcl]
}
if {![llength [info commands \
        ::stage1e::production_evidence_serializer_v1::publish_record]]} {
    source [file join $::stage1e_evidence_controller_build runtime identity \
        stage1e_production_evidence_serializer_v1.tcl]
}

namespace eval ::stage1e::production_evidence_controller_v1 {
    variable interface_version stage1e-production-evidence-controller-interface-v1
}
unset ::stage1e_evidence_controller_dir
unset ::stage1e_evidence_controller_build

proc ::stage1e::production_evidence_controller_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_evidence_controller_v1::_raise {code message} {
    return -code error -errorcode [list STAGE1E EVIDENCE CONTROLLER $code] \
        $message
}

proc ::stage1e::production_evidence_controller_v1::interruption_fields {} {
    return {process_effect interruption_observation failure_reference}
}

proc ::stage1e::production_evidence_controller_v1::record_interruption {
    collector_snapshot input
} {
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields \
        $collector_snapshot {
            state request open_events terminal_events logical_attempts raw_items
            reservations event_ordinal first_failure secondary_failures
            interrupted_open_event
        } {Interrupted Collector snapshot}
    ::stage1e::evidence_pipeline_contract_v1::require_equal \
        PRODUCER_TERMINATED [dict get $collector_snapshot state] \
        {Interrupted Collector state}
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields $input \
        [interruption_fields] {Report interruption input}
    set request [dict get $collector_snapshot request]
    set open [dict get $collector_snapshot interrupted_open_event]
    set event_ordinal [expr {[dict get $collector_snapshot event_ordinal] + 1}]
    set event_path [file join [dict get $request report_event_root] \
        [format {event-%04d-interruption.json} $event_ordinal]]
    set event_path \
        [::stage1e::vivado_runtime_contract_v1::canonical_path $event_path]
    set event [dict create \
        schema_version stage1e-report-interruption-event-v1 \
        event_type INTERRUPTION event_reference $event_path \
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
        interruption_state INTERRUPTED \
        interruption_observation [dict get $input interruption_observation] \
        process_effect [dict get $input process_effect] \
        failure_reference [dict get $input failure_reference] \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    ::stage1e::production_evidence_serializer_v1::publish_record \
        report_interruption_event $event $event_path \
        [dict get $request report_root]
    return $event
}

proc ::stage1e::production_evidence_controller_v1::_completeness_from_set {
    evidence_set evidence_set_reference
} {
    set state COMPLETE
    set blocking {}
    set issues {}
    if {[dict get $evidence_set inventory_state] ne {COMPLETE}} {
        set state PARTIAL
    }
    foreach item [dict get $evidence_set items] {
        if {[dict get $item completeness_effect] eq {BLOCKING}} {
            lappend blocking [dict get $item role]
            lappend issues "ROLE:[dict get $item role]:[dict get $item evidence_state]:[dict get $item parser_state]"
        }
    }
    foreach comparison [dict get $evidence_set projection_comparisons] {
        if {[dict get $comparison comparison_state] ne {MATCH}} {
            set state PARTIAL
            lappend issues \
                "PROJECTION:[dict get $comparison ledger_role]:MISMATCH"
        }
    }
    set result [dict create \
        schema_version stage1e-evidence-completeness-result-v1 \
        request_identity [dict get $evidence_set request_identity] \
        execution_id [dict get $evidence_set execution_id] \
        attempt_id [dict get $evidence_set attempt_id] \
        workspace_identity [dict get $evidence_set workspace_identity] \
        evidence_set_reference $evidence_set_reference \
        completeness_state $state blocking_roles $blocking \
        issue_references $issues structural_only STRUCTURAL_ONLY \
        candidate_effect NOT_CREATED \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        evidence_completeness_result $result
    return $result
}

proc ::stage1e::production_evidence_controller_v1::completeness {
    evidence_set_reference
} {
    ::stage1e::production_evidence_serializer_v1::validate_reference \
        $evidence_set_reference EVIDENCE_SET
    ::stage1e::evidence_pipeline_contract_v1::require_equal \
        evidence_set_inventory [dict get $evidence_set_reference record_type] \
        {Completeness evidence-set record type}
    set evidence_set \
        [::stage1e::production_evidence_serializer_v1::open_reference \
            $evidence_set_reference]
    return [_completeness_from_set $evidence_set $evidence_set_reference]
}

proc ::stage1e::production_evidence_controller_v1::_reference_map {
    evidence_set
} {
    set references {}
    foreach reference [dict get $evidence_set full_ledger_references] {
        set role [dict get $reference reference_role]
        if {[dict exists $references $role]} {
            _raise DUPLICATE_REFERENCE \
                "Evidence set duplicates sealed-reference role '$role'."
        }
        ::stage1e::production_evidence_serializer_v1::validate_reference \
            $reference $role $evidence_set
        dict set references $role $reference
    }
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields \
        $references \
        [::stage1e::production_evidence_serializer_v1::reference_role_order] \
        {Structural-review sealed references}
    return $references
}

proc ::stage1e::production_evidence_controller_v1::_open_expected {
    references role record_type
} {
    set reference [dict get $references $role]
    ::stage1e::evidence_pipeline_contract_v1::require_equal $record_type \
        [dict get $reference record_type] \
        "Structural-review reference type $role"
    return [::stage1e::production_evidence_serializer_v1::open_reference \
        $reference]
}

proc ::stage1e::production_evidence_controller_v1::_derived_states {
    evidence_set completeness
} {
    set references [_reference_map $evidence_set]
    set operation [_open_expected $references FULL_OPERATION_LEDGER \
        fixture_operation_ledger]
    set report_ledger [_open_expected $references FULL_REPORT_ATTEMPT_LEDGER \
        report_ledger]
    set collector [_open_expected $references COLLECTOR_RESULT \
        collector_result]
    set parser [_open_expected $references PARSER_RESULT parser_result]
    set vivado [_open_expected $references VIVADO_COMPONENT_RESULT \
        fixture_structural_evidence]
    set forbidden [_open_expected $references FORBIDDEN_BOUNDARY_EVIDENCE \
        fixture_structural_evidence]

    set host_reference [dict get $references HOST_RESULT_OR_DISCONNECTED]
    if {[dict get $host_reference location_state] eq \
            {EXPLICIT_DISCONNECTED} &&
            [dict get $host_reference availability_state] eq \
                {DISCONNECTED_EXPLICIT}} {
        set host_state DISCONNECTED_EXPLICIT
    } elseif {[dict get $host_reference availability_state] eq {PRESENT}} {
        set host_state PRESENT
    } else {
        set host_state UNAVAILABLE
    }

    set projection_state MATCH
    set expected_roles {OPERATION_LEDGER REPORT_ATTEMPT_LEDGER}
    set expected_references {
        FULL_OPERATION_LEDGER FULL_REPORT_ATTEMPT_LEDGER
    }
    ::stage1e::evidence_pipeline_contract_v1::require_equal 2 \
        [llength [dict get $evidence_set projection_comparisons]] \
        {Structural-review projection comparison count}
    set index 0
    foreach supplied [dict get $evidence_set projection_comparisons] {
        set ledger_role [lindex $expected_roles $index]
        set reference_role [lindex $expected_references $index]
        ::stage1e::evidence_pipeline_contract_v1::require_equal $ledger_role \
            [dict get $supplied ledger_role] \
            {Structural-review projection order}
        ::stage1e::evidence_pipeline_contract_v1::require_equal \
            [dict get $references $reference_role] \
            [dict get $supplied full_ledger_reference] \
            {Structural-review projection full-ledger reference}
        set derived \
            [::stage1e::production_evidence_serializer_v1::compare_projection \
                [dict get $supplied full_ledger_reference] \
                [dict get $supplied compact_rows]]
        if {$derived ne $supplied ||
                [dict get $derived comparison_state] ne {MATCH}} {
            set projection_state MISMATCH
        }
        incr index
    }

    set operation_state COMPLETE
    if {[dict get $operation fixture_state] ne {FIXTURE_ONLY} ||
            [dict get $operation ledger_state] ne \
                {SEALED_CURRENT_ATTEMPT} ||
            [dict get $operation entry_count] == 0} {
        set operation_state PARTIAL
    }
    set request_provenance [dict get $vivado request_provenance_state]
    set phys_opt_state [dict get $vivado phys_opt_prohibition_state]

    set collector_state COMPLETE
    if {[dict get $report_ledger terminal_state] ne {COMPLETED} ||
            [dict get $collector terminal_status] ne {COMPLETED} ||
            [dict get $collector report_ledger_reference] ne
                [dict get $references FULL_REPORT_ATTEMPT_LEDGER literal_path]} {
        set collector_state PARTIAL
    }

    set parser_state COMPLETE
    if {[dict get $parser terminal_state] ne {COMPLETE}} {
        set parser_state [dict get $parser terminal_state]
    }
    foreach {role type} {
        MESSAGE_INVENTORY message_inventory
        DRC_INVENTORY drc_inventory
        METHODOLOGY_INVENTORY methodology_inventory
        TIMING_INVENTORY timing_inventory
        CLOCK_CDC_INVENTORY clock_cdc_inventory
        TIMING_EXCEPTION_INVENTORY timing_exception_inventory
        UTILIZATION_INVENTORY utilization_inventory
    } {
        set inventory [_open_expected $references $role $type]
        if {[dict get $inventory parse_state] ne {COMPLETE}} {
            set parser_state [dict get $inventory parse_state]
        }
        set expected "$role=[dict get $references $role literal_path]"
        if {[lsearch -exact [dict get $parser inventory_references] \
                $expected] < 0} {
            set parser_state PARTIAL
        }
    }

    set forbidden_state CLEAR
    if {[dict get $forbidden forbidden_operation_state] ne {CLEAR} ||
            [dict get $forbidden downstream_output_state] ne {CLEAR}} {
        set forbidden_state BLOCKED
    }

    ::stage1e::production_evidence_serializer_v1::validate_failure_order \
        [dict get $collector first_failure_reference] \
        [dict get $collector secondary_failure_references]
    ::stage1e::production_evidence_serializer_v1::validate_failure_order \
        [dict get $parser first_failure_reference] \
        [dict get $parser secondary_failure_references]
    if {[dict get $collector first_failure_reference] ne {NONE}} {
        set first [dict get $collector first_failure_reference]
        set secondary [dict get $collector secondary_failure_references]
    } else {
        set first [dict get $parser first_failure_reference]
        set secondary [dict get $parser secondary_failure_references]
    }

    return [dict create references $references \
        request_provenance_state $request_provenance \
        host_result_state $host_state operation_ledger_state $operation_state \
        phys_opt_prohibition_state $phys_opt_state \
        collector_ledger_state $collector_state \
        parser_inventory_state $parser_state \
        role_completeness_state [dict get $completeness completeness_state] \
        projection_agreement_state $projection_state \
        failure_order_state PRESERVED forbidden_scan_state $forbidden_state \
        first_failure_reference $first \
        secondary_failure_references $secondary]
}

proc ::stage1e::production_evidence_controller_v1::review_input_fields {} {
    return {
        evidence_set_reference authority_boundary
    }
}

proc ::stage1e::production_evidence_controller_v1::_review_record {
    evidence_set review_state terminal_status category code
    request_provenance host_result operation_state phys_opt_state
    collector_state parser_state role_state projection_state failure_order
    forbidden_state first_failure secondary_failures policy_state
} {
    set record [dict create \
        schema_version stage1e-evidence-structural-review-result-v1 \
        request_identity [dict get $evidence_set request_identity] \
        execution_id [dict get $evidence_set execution_id] \
        attempt_id [dict get $evidence_set attempt_id] \
        workspace_identity [dict get $evidence_set workspace_identity] \
        review_state $review_state terminal_status $terminal_status \
        failure_category $category failure_code $code failure_phase REVIEW \
        request_provenance_state $request_provenance \
        host_result_state $host_result \
        operation_ledger_state $operation_state \
        phys_opt_prohibition_state $phys_opt_state \
        collector_ledger_state $collector_state \
        parser_inventory_state $parser_state \
        role_completeness_state $role_state \
        projection_agreement_state $projection_state \
        failure_order_state $failure_order \
        forbidden_scan_state $forbidden_state authority_state NONE \
        first_failure_reference $first_failure \
        secondary_failure_references $secondary_failures \
        candidate_effect NOT_CREATED policy_review_state $policy_state \
        identity_state PENDING_IDENTITY_PROVIDER \
        authority_boundary \
            [::stage1e::evidence_pipeline_contract_v1::authority_none]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        evidence_structural_review_result $record
    return $record
}

proc ::stage1e::production_evidence_controller_v1::review {input} {
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields $input \
        [review_input_fields] {Evidence structural-review input}
    ::stage1e::evidence_pipeline_contract_v1::validate_authority \
        [dict get $input authority_boundary]
    set evidence_set_reference [dict get $input evidence_set_reference]
    ::stage1e::production_evidence_serializer_v1::validate_reference \
        $evidence_set_reference EVIDENCE_SET
    ::stage1e::evidence_pipeline_contract_v1::require_equal \
        evidence_set_inventory [dict get $evidence_set_reference record_type] \
        {Structural-review evidence-set record type}
    set evidence_set \
        [::stage1e::production_evidence_serializer_v1::open_reference \
            $evidence_set_reference]
    set completeness \
        [_completeness_from_set $evidence_set $evidence_set_reference]
    set derived [_derived_states $evidence_set $completeness]
    set projection_state [dict get $derived projection_agreement_state]
    set role_state [dict get $derived role_completeness_state]
    set first [dict get $derived first_failure_reference]
    set secondary [dict get $derived secondary_failure_references]

    if {[dict get $derived collector_ledger_state] ne {COMPLETE}} {
        if {$first eq {NONE}} { set first 1#COLLECTION:COLLECTOR_LEDGER_BLOCKED }
        set review [_review_record $evidence_set COLLECTOR_BLOCKED BLOCKED \
            COLLECTION COLLECTOR_LEDGER_INCOMPLETE \
            [dict get $derived request_provenance_state] \
            [dict get $derived host_result_state] \
            [dict get $derived operation_ledger_state] \
            [dict get $derived phys_opt_prohibition_state] \
            [dict get $derived collector_ledger_state] \
            [dict get $derived parser_inventory_state] $role_state \
            $projection_state [dict get $derived failure_order_state] \
            [dict get $derived forbidden_scan_state] $first $secondary \
            NOT_REACHED]
        return [dict create completeness $completeness review $review]
    }
    if {[dict get $derived parser_inventory_state] ne {COMPLETE}} {
        if {$first eq {NONE}} { set first 1#PARSING:PARSER_INVENTORY_BLOCKED }
        set review [_review_record $evidence_set PARSER_BLOCKED BLOCKED \
            PARSING PARSER_INVENTORY_INCOMPLETE \
            [dict get $derived request_provenance_state] \
            [dict get $derived host_result_state] \
            [dict get $derived operation_ledger_state] \
            [dict get $derived phys_opt_prohibition_state] \
            [dict get $derived collector_ledger_state] \
            [dict get $derived parser_inventory_state] $role_state \
            $projection_state [dict get $derived failure_order_state] \
            [dict get $derived forbidden_scan_state] $first $secondary \
            NOT_REACHED]
        return [dict create completeness $completeness review $review]
    }
    set structural_clear [expr {
        [dict get $completeness completeness_state] eq {COMPLETE} &&
        [dict get $derived request_provenance_state] eq {MATCH} &&
        [dict get $derived host_result_state] in \
            {PRESENT DISCONNECTED_EXPLICIT} &&
        [dict get $derived operation_ledger_state] eq {COMPLETE} &&
        [dict get $derived phys_opt_prohibition_state] eq {CLEAR} &&
        [dict get $derived forbidden_scan_state] eq {CLEAR} &&
        $projection_state eq {MATCH}}]
    if {!$structural_clear} {
        if {$first eq {NONE}} {
            set first 1#EVIDENCE_INCOMPLETE:STRUCTURAL_GATE_BLOCKED
        }
        set review [_review_record $evidence_set EVIDENCE_INCOMPLETE BLOCKED \
            EVIDENCE_INCOMPLETE REQUIRED_EVIDENCE_INCOMPLETE \
            [dict get $derived request_provenance_state] \
            [dict get $derived host_result_state] \
            [dict get $derived operation_ledger_state] \
            [dict get $derived phys_opt_prohibition_state] \
            [dict get $derived collector_ledger_state] \
            [dict get $derived parser_inventory_state] $role_state \
            $projection_state [dict get $derived failure_order_state] \
            [dict get $derived forbidden_scan_state] $first $secondary \
            NOT_REACHED]
        return [dict create completeness $completeness review $review]
    }

    set policy_failure \
        1#POLICY_REVIEW:PRODUCTION_POLICY_REVIEW_NOT_IMPLEMENTED
    set review [_review_record $evidence_set \
        EVIDENCE_STRUCTURAL_REVIEW_COMPLETE BLOCKED POLICY_REVIEW \
        PRODUCTION_POLICY_REVIEW_NOT_IMPLEMENTED \
        MATCH [dict get $derived host_result_state] COMPLETE CLEAR COMPLETE \
        COMPLETE COMPLETE MATCH PRESERVED CLEAR $policy_failure {} \
        NOT_IMPLEMENTED]
    return [dict create completeness $completeness review $review]
}

proc ::stage1e::production_evidence_controller_v1::publish_review {
    result completeness_path review_path boundary_path
} {
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields $result \
        {completeness review} {Evidence review result set}
    set completeness_receipt \
        [::stage1e::production_evidence_serializer_v1::publish_record \
            evidence_completeness_result [dict get $result completeness] \
            $completeness_path $boundary_path]
    set review_receipt \
        [::stage1e::production_evidence_serializer_v1::publish_record \
            evidence_structural_review_result [dict get $result review] \
            $review_path $boundary_path]
    return [dict create completeness_receipt $completeness_receipt \
        review_receipt $review_receipt]
}
