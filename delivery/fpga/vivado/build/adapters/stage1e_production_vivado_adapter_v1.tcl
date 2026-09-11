# Stage 1E PRT02-C production Vivado adapter candidate v1.
#
# The adapter performs exact representation only. It supplies no defaults,
# owns no authorization transition, and makes no acceptance decision.

set ::stage1e_production_vivado_adapter_root \
    [file dirname [file normalize [info script]]]
if {![llength [info commands \
        ::stage1e::vivado_runtime_contract_v1::validate_controller_request]]} {
    source [file join $::stage1e_production_vivado_adapter_root .. lib \
        stage1e_vivado_runtime_contract_v1.tcl]
}
unset ::stage1e_production_vivado_adapter_root

namespace eval ::stage1e::production_vivado_adapter_v1 {
    variable interface_version stage1e-production-vivado-adapter-interface-v1
    variable source_request_fields {
        schema_version request_identity request_state execution_id attempt_id
        source_identity runtime_backend_identity policy_identity
        configuration_identity qualification_identity environment_identity
        workspace_identity synthesis_result_identity
        dependency_closure_identity interface_contracts authorization
        implementation_contract launch_contract evidence_contract
        timeout_contract authority_boundary
    }
}

proc ::stage1e::production_vivado_adapter_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_vivado_adapter_v1::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E PRT02C VIVADO_ADAPTER $code] $message
}

proc ::stage1e::production_vivado_adapter_v1::_node_to_tcl {node} {
    set type [::stage1e::canonical_json_v1::node_type $node]
    if {$type in {string integer boolean}} {
        return [::stage1e::canonical_json_v1::node_value $node]
    }
    if {$type eq {array}} {
        set result {}
        foreach item [::stage1e::canonical_json_v1::array_values $node] {
            lappend result [_node_to_tcl $item]
        }
        return $result
    }
    if {$type eq {object}} {
        set result {}
        foreach name [::stage1e::canonical_json_v1::object_keys $node] {
            dict set result $name [_node_to_tcl \
                [::stage1e::canonical_json_v1::object_get $node $name]]
        }
        return $result
    }
    _raise REPRESENTATION_INVALID "Unsupported JSON node type: $type"
}

proc ::stage1e::production_vivado_adapter_v1::_require_source_fields {
    request_node
} {
    variable source_request_fields
    if {[::stage1e::canonical_json_v1::node_type $request_node] ne {object}} {
        _raise SOURCE_REQUEST_INVALID {Sealed request node is not an object.}
    }
    set expected [lsort -dictionary $source_request_fields]
    set actual [lsort -dictionary \
        [::stage1e::canonical_json_v1::object_keys $request_node]]
    if {$expected ne $actual} {
        _raise SOURCE_REQUEST_INVALID \
            "Sealed request fields differ: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::production_vivado_adapter_v1::project_request {
    request_node sealed_request_path session_context
} {
    _require_source_fields $request_node
    ::stage1e::vivado_runtime_contract_v1::validate_session_context \
        $session_context
    set source [_node_to_tcl $request_node]
    set projection [dict create \
        schema_version stage1e-production-vivado-controller-request-v1 \
        source_schema_version [dict get $source schema_version] \
        request_identity [dict get $source request_identity] \
        sealed_request_path \
            [::stage1e::vivado_runtime_contract_v1::canonical_path \
                $sealed_request_path] \
        request_state [dict get $source request_state] \
        execution_id [dict get $source execution_id] \
        attempt_id [dict get $source attempt_id] \
        source_identity [dict get $source source_identity] \
        runtime_backend_identity [dict get $source runtime_backend_identity] \
        policy_identity [dict get $source policy_identity] \
        configuration_identity [dict get $source configuration_identity] \
        qualification_identity [dict get $source qualification_identity] \
        environment_identity [dict get $source environment_identity] \
        workspace_identity [dict get $source workspace_identity] \
        synthesis_result_identity \
            [dict get $source synthesis_result_identity] \
        dependency_closure_identity \
            [dict get $source dependency_closure_identity] \
        interface_contracts [dict get $source interface_contracts] \
        authorization [dict get $source authorization] \
        implementation_contract [dict get $source implementation_contract] \
        launch_contract [dict get $source launch_contract] \
        evidence_contract [dict get $source evidence_contract] \
        timeout_contract [dict get $source timeout_contract] \
        authority_boundary [dict get $source authority_boundary] \
        session_context $session_context \
        record_contract_version stage1e-vivado-runtime-record-contract-v1 \
        command_contract_version stage1e-vivado-runtime-command-contract-v1 \
        property_map_version stage1e-vivado-runtime-property-map-v1]
    ::stage1e::vivado_runtime_contract_v1::validate_controller_request \
        $projection
    return [::stage1e::vivado_runtime_contract_v1::copy_exact \
        controller_request $projection]
}

proc ::stage1e::production_vivado_adapter_v1::normalize_snapshot {snapshot} {
    ::stage1e::vivado_runtime_contract_v1::validate_snapshot $snapshot
    return [::stage1e::vivado_runtime_contract_v1::copy_exact \
        observer_snapshot $snapshot]
}

proc ::stage1e::production_vivado_adapter_v1::normalize_phase_result {result} {
    ::stage1e::vivado_runtime_contract_v1::validate_phase_result $result
    return [::stage1e::vivado_runtime_contract_v1::copy_exact \
        runner_phase_result $result]
}

proc ::stage1e::production_vivado_adapter_v1::normalize_handoff {handoff} {
    ::stage1e::vivado_runtime_contract_v1::validate_handoff $handoff
    return [::stage1e::vivado_runtime_contract_v1::copy_exact \
        collector_handoff $handoff]
}

proc ::stage1e::production_vivado_adapter_v1::normalize_component_result {
    result
} {
    ::stage1e::vivado_runtime_contract_v1::validate_component_result $result
    return [::stage1e::vivado_runtime_contract_v1::copy_exact \
        vivado_component_result $result]
}

proc ::stage1e::production_vivado_adapter_v1::_phase_contract {operation} {
    switch -- $operation {
        opt_design {
            return [dict create sequence 1 predecessor synthesis \
                target_step opt_design timeout_field opt_design_seconds \
                required_prior_phase PRE_CONSUME]
        }
        place_design {
            return [dict create sequence 2 predecessor opt_design \
                target_step place_design timeout_field place_design_seconds \
                required_prior_phase POST_OPT]
        }
        route_design {
            return [dict create sequence 3 predecessor place_design \
                target_step route_design timeout_field route_design_seconds \
                required_prior_phase POST_PLACE]
        }
        default {
            _raise OPERATION_INVALID \
                "Adapter cannot represent runner operation: $operation"
        }
    }
}

proc ::stage1e::production_vivado_adapter_v1::make_phase_request {
    controller_request controller_decision receipt ledger prior_snapshot
    operation
} {
    ::stage1e::vivado_runtime_contract_v1::validate_controller_request \
        $controller_request
    ::stage1e::vivado_runtime_contract_v1::require_record \
        controller_decision $controller_decision
    ::stage1e::vivado_runtime_contract_v1::validate_receipt $receipt
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    ::stage1e::vivado_runtime_contract_v1::validate_snapshot $prior_snapshot
    set phase [_phase_contract $operation]
    ::stage1e::vivado_runtime_contract_v1::require_equal PROCEED \
        [dict get $controller_decision decision] {Controller phase decision}
    ::stage1e::vivado_runtime_contract_v1::require_equal $operation \
        [dict get $controller_decision operation] \
        {Controller phase operation}
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        [dict get $phase required_prior_phase] [dict get $prior_snapshot phase] \
        {Runner prior snapshot phase}
    foreach field {
        request_identity execution_id attempt_id workspace_identity
    } {
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            [dict get $controller_request $field] [dict get $receipt $field] \
            "Receipt request binding $field"
    }
    set request [dict create \
        schema_version stage1e-production-vivado-runner-phase-request-v1 \
        controller_request $controller_request \
        request_identity [dict get $controller_request request_identity] \
        execution_id [dict get $controller_request execution_id] \
        attempt_id [dict get $controller_request attempt_id] \
        workspace_identity [dict get $controller_request workspace_identity] \
        session_id [dict get $controller_request session_context session_id] \
        sequence [dict get $phase sequence] \
        logical_operation $operation \
        exact_predecessor [dict get $phase predecessor] \
        target_step [dict get $phase target_step] \
        run_name impl_1 \
        jobs [dict get $controller_request implementation_contract jobs] \
        controller_decision $controller_decision \
        authorization_receipt_path [dict get $receipt receipt_path] \
        authorization_receipt_identity [dict get $receipt receipt_identity] \
        prior_snapshot_reference [dict get $prior_snapshot snapshot_reference] \
        prior_snapshot $prior_snapshot \
        operation_ledger $ledger \
        timeout_seconds [dict get $controller_request timeout_contract \
            [dict get $phase timeout_field]] \
        timeout_state NOT_EXPIRED \
        command_contract_version \
            [dict get $controller_request command_contract_version] \
        property_map_version \
            [dict get $controller_request property_map_version] \
        authority_boundary \
            [::stage1e::vivado_runtime_contract_v1::runtime_authority_boundary]]
    ::stage1e::vivado_runtime_contract_v1::validate_phase_request $request
    return [::stage1e::vivado_runtime_contract_v1::copy_exact \
        runner_phase_request $request]
}
