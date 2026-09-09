# Stage 1E PRT02-D evidence-pipeline adapter candidate v1.
#
# This append-only adapter maps the immutable PRT02-C handoff to D records.
# It supplies no defaultable execution values and owns no authorization,
# finding disposition, policy review, acceptance, identity, or candidate.

set ::stage1e_evidence_adapter_dir [file dirname [info script]]
set ::stage1e_evidence_adapter_build [file dirname $::stage1e_evidence_adapter_dir]
if {![llength [info commands \
        ::stage1e::evidence_pipeline_contract_v1::validate_record]]} {
    source [file join $::stage1e_evidence_adapter_build lib \
        stage1e_evidence_pipeline_contract_v1.tcl]
}

namespace eval ::stage1e::production_evidence_adapter_v1 {
    variable interface_version stage1e-production-evidence-adapter-interface-v1
}
unset ::stage1e_evidence_adapter_dir
unset ::stage1e_evidence_adapter_build

proc ::stage1e::production_evidence_adapter_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_evidence_adapter_v1::_raise {code message} {
    return -code error -errorcode [list STAGE1E EVIDENCE ADAPTER $code] \
        $message
}

proc ::stage1e::production_evidence_adapter_v1::collector_input_fields {} {
    return {
        operation_ledger_reference report_root report_event_root
        report_ledger_path collector_result_path role_output_paths
        conditional_decisions command_availability attempt_deadline_state
        reporting_deadline_state total_deadline_state execution_model_state
        producer_session adopted_evidence authority_boundary
    }
}

proc ::stage1e::production_evidence_adapter_v1::make_collector_request {
    c_handoff input
} {
    ::stage1e::vivado_runtime_contract_v1::validate_handoff $c_handoff
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields $input \
        [collector_input_fields] {Evidence adapter Collector input}
    set request [dict create \
        schema_version stage1e-production-collector-request-v1 \
        request_identity [dict get $c_handoff request_identity] \
        execution_id [dict get $c_handoff execution_id] \
        attempt_id [dict get $c_handoff attempt_id] \
        workspace_identity [dict get $c_handoff workspace_identity] \
        session_id [dict get $c_handoff session_id] \
        collector_interface stage1e-production-vivado-collector-interface-v1 \
        report_contract_version stage1e-production-report-contract-v1 \
        message_contract_version stage1e-production-message-contract-v1 \
        parser_profiles_contract_version \
            stage1e-parser-format-profiles-contract-v1 \
        evidence_record_contract_version stage1e-evidence-record-contract-v1 \
        c_handoff $c_handoff \
        operation_ledger_reference \
            [dict get $input operation_ledger_reference] \
        current_design_state [dict get $c_handoff current_design_state] \
        report_root [dict get $input report_root] \
        report_event_root [dict get $input report_event_root] \
        report_ledger_path [dict get $input report_ledger_path] \
        collector_result_path [dict get $input collector_result_path] \
        role_output_paths [dict get $input role_output_paths] \
        conditional_decisions [dict get $input conditional_decisions] \
        command_availability [dict get $input command_availability] \
        attempt_deadline_state [dict get $input attempt_deadline_state] \
        reporting_deadline_state [dict get $input reporting_deadline_state] \
        total_deadline_state [dict get $input total_deadline_state] \
        execution_model_state [dict get $input execution_model_state] \
        producer_session [dict get $input producer_session] \
        adopted_evidence [dict get $input adopted_evidence] \
        authority_boundary [dict get $input authority_boundary]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        collector_request $request
    return $request
}

proc ::stage1e::production_evidence_adapter_v1::parser_input_fields {} {
    return {
        parser_attempt_ordinal parser_output_root parser_result_path
        inventory_paths input_seal_state historical_source_state
        authority_boundary
    }
}

proc ::stage1e::production_evidence_adapter_v1::make_parser_request {
    raw_inventory input
} {
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        raw_evidence_inventory $raw_inventory
    ::stage1e::evidence_pipeline_contract_v1::require_exact_fields $input \
        [parser_input_fields] {Evidence adapter Parser input}
    set request [dict create \
        schema_version stage1e-production-parser-request-v1 \
        request_identity [dict get $raw_inventory request_identity] \
        execution_id [dict get $raw_inventory execution_id] \
        attempt_id [dict get $raw_inventory attempt_id] \
        workspace_identity [dict get $raw_inventory workspace_identity] \
        parser_interface stage1e-production-evidence-parser-interface-v1 \
        parser_attempt_ordinal [dict get $input parser_attempt_ordinal] \
        report_contract_version stage1e-production-report-contract-v1 \
        message_contract_version stage1e-production-message-contract-v1 \
        format_profiles_contract_version \
            stage1e-parser-format-profiles-contract-v1 \
        raw_evidence_inventory $raw_inventory \
        parser_output_root [dict get $input parser_output_root] \
        parser_result_path [dict get $input parser_result_path] \
        inventory_paths [dict get $input inventory_paths] \
        input_seal_state [dict get $input input_seal_state] \
        historical_source_state [dict get $input historical_source_state] \
        authority_boundary [dict get $input authority_boundary]]
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        parser_request $request
    return $request
}

proc ::stage1e::production_evidence_adapter_v1::normalize_collector_result {
    result
} {
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        collector_result $result
    return $result
}

proc ::stage1e::production_evidence_adapter_v1::normalize_parser_result {
    result
} {
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        parser_result $result
    return $result
}

proc ::stage1e::production_evidence_adapter_v1::normalize_evidence_set {
    inventory
} {
    ::stage1e::evidence_pipeline_contract_v1::validate_record \
        evidence_set_inventory $inventory
    return $inventory
}
