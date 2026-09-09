# Stage 1E PRT02-C production Vivado controller candidate v1.
#
# The controller owns validation, monotonic continuation decisions, and the
# one-use authorization-consumption publication. It contains no Vivado
# implementation or report command.

set ::stage1e_production_vivado_controller_path [file normalize [info script]]
set ::stage1e_production_vivado_controller_root \
    [file dirname $::stage1e_production_vivado_controller_path]
if {![llength [info commands \
        ::stage1e::vivado_runtime_contract_v1::validate_controller_request]]} {
    source [file join $::stage1e_production_vivado_controller_root .. lib \
        stage1e_vivado_runtime_contract_v1.tcl]
}

namespace eval ::stage1e::production_vivado_controller_v1 {
    variable interface_version \
        stage1e-production-vivado-controller-interface-v1
    variable module_path $::stage1e_production_vivado_controller_path
    variable module_root $::stage1e_production_vivado_controller_root
    variable build_root [file dirname $module_root]
}
unset ::stage1e_production_vivado_controller_path
unset ::stage1e_production_vivado_controller_root

proc ::stage1e::production_vivado_controller_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_vivado_controller_v1::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E PRT02C VIVADO_CONTROLLER $code] $message
}

proc ::stage1e::production_vivado_controller_v1::validate_state {state} {
    set contract [::stage1e::vivado_runtime_contract_v1::record_contract]
    ::stage1e::vivado_runtime_contract_v1::require_record \
        controller_state $state
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        stage1e-production-vivado-controller-state-v1 \
        [dict get $state schema_version] {Controller state schema}
    ::stage1e::vivado_runtime_contract_v1::require_one_of \
        [dict get $state current_state] \
        [dict get $contract enums controller_states] {Controller state}
    if {![string is integer -strict [dict get $state decision_ordinal]] ||
            [dict get $state decision_ordinal] < 1} {
        _raise STATE_INVALID {Controller decision ordinal is invalid.}
    }
    set expected_ordinal 0
    set observed_state NONE
    foreach transition [dict get $state transition_history] {
        incr expected_ordinal
        ::stage1e::vivado_runtime_contract_v1::require_record \
            controller_transition $transition
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            $expected_ordinal [dict get $transition ordinal] \
            {Controller transition ordinal}
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            $observed_state [dict get $transition from_state] \
            {Controller transition predecessor}
        set target [dict get $transition to_state]
        if {$observed_state ne {NONE}} {
            set permitted [dict get $contract controller_state_machine \
                $observed_state]
            ::stage1e::vivado_runtime_contract_v1::require_one_of \
                $target $permitted \
                "Controller transition from $observed_state"
        } else {
            ::stage1e::vivado_runtime_contract_v1::require_equal \
                REQUEST_VALIDATED $target {Initial controller state}
        }
        set observed_state $target
    }
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        [dict get $state decision_ordinal] $expected_ordinal \
        {Controller history length}
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        [dict get $state current_state] $observed_state \
        {Controller history terminal state}
    ::stage1e::vivado_runtime_contract_v1::validate_failure_sequence \
        [dict get $state first_failure] [dict get $state secondary_failures]
    set failure_ordinals {}
    if {[dict get $state first_failure] ne {NONE}} {
        foreach failure [linsert [dict get $state secondary_failures] 0 \
                [dict get $state first_failure]] {
            set failure_ordinal [dict get $failure first_failure_ordinal]
            if {$failure_ordinal > $expected_ordinal} {
                _raise STATE_INVALID \
                    {A controller failure ordinal exceeds the history length.}
            }
            set transition [lindex [dict get $state transition_history] \
                [expr {$failure_ordinal - 1}]]
            set expected_reference \
                "failure/$failure_ordinal/[dict get $failure failure_code]"
            ::stage1e::vivado_runtime_contract_v1::require_equal \
                $expected_reference [dict get $transition failure_reference] \
                {Controller failure transition reference}
            dict set failure_ordinals $failure_ordinal 1
        }
    }
    foreach transition [dict get $state transition_history] {
        set ordinal [dict get $transition ordinal]
        if {[dict get $transition failure_reference] ne {NONE} &&
                ![dict exists $failure_ordinals $ordinal]} {
            _raise STATE_INVALID \
                {A controller transition references an unrecorded failure.}
        }
    }
    ::stage1e::vivado_runtime_contract_v1::require_one_of \
        [dict get $state assembly_validation_state] \
        {NOT_EVALUATED PRT02C_FIXED_ASSEMBLY_VALIDATED} \
        {Controller assembly-validation state}
    ::stage1e::vivado_runtime_contract_v1::require_equal NOT_PROVEN \
        [dict get $state dependency_closure_state] \
        {Controller dependency-closure state}
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        PRT02C_DIRECT_ASSEMBLY_ONLY [dict get $state closure_scope] \
        {Controller closure scope}
    ::stage1e::vivado_runtime_contract_v1::require_equal NOT_CREATED \
        [dict get $state candidate_effect] {Controller candidate effect}
    return 1
}

proc ::stage1e::production_vivado_controller_v1::initialize {request} {
    ::stage1e::vivado_runtime_contract_v1::validate_controller_request $request
    set reference [::stage1e::vivado_runtime_contract_v1::decision_reference \
        $request 1 REQUEST_VALIDATED request_validation]
    set transition [dict create \
        ordinal 1 \
        from_state NONE \
        to_state REQUEST_VALIDATED \
        decision PROCEED \
        reason_code REQUEST_PROJECTION_EXACT \
        decision_reference $reference \
        failure_reference NONE]
    set state [dict create \
        schema_version stage1e-production-vivado-controller-state-v1 \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        current_state REQUEST_VALIDATED \
        transition_history [list $transition] \
        decision_ordinal 1 \
        continuation_decision PROCEED \
        authorization_effect NOT_TOUCHED \
        authorization_receipt_reference NONE \
        first_failure NONE \
        secondary_failures {} \
        candidate_effect NOT_CREATED \
        assembly_validation_state NOT_EVALUATED \
        dependency_closure_state NOT_PROVEN \
        closure_scope PRT02C_DIRECT_ASSEMBLY_ONLY]
    validate_state $state
    return $state
}

proc ::stage1e::production_vivado_controller_v1::_record_failure {
    state failure
} {
    ::stage1e::vivado_runtime_contract_v1::validate_failure $failure
    if {[dict get $state first_failure] eq {NONE}} {
        dict set state first_failure $failure
    } else {
        dict lappend state secondary_failures $failure
    }
    dict set state authorization_effect \
        [dict get $failure authorization_effect]
    return $state
}

proc ::stage1e::production_vivado_controller_v1::_transition {
    request state target operation decision reason snapshot_reference
    failure
} {
    validate_state $state
    foreach field {request_identity execution_id attempt_id} {
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            [dict get $request $field] [dict get $state $field] \
            "Controller state binding $field"
    }
    set contract [::stage1e::vivado_runtime_contract_v1::record_contract]
    set current [dict get $state current_state]
    if {![dict exists $contract controller_state_machine $current]} {
        _raise STATE_INVALID "Unknown controller source state: $current"
    }
    set permitted [dict get $contract controller_state_machine $current]
    if {[lsearch -exact $permitted $target] < 0} {
        _raise STATE_TRANSITION \
            "Controller transition is not permitted: $current -> $target"
    }
    set ordinal [expr {[dict get $state decision_ordinal] + 1}]
    set reference [::stage1e::vivado_runtime_contract_v1::decision_reference \
        $request $ordinal $target $operation]
    set failure_reference NONE
    if {$failure ne {NONE}} {
        ::stage1e::vivado_runtime_contract_v1::require_equal $ordinal \
            [dict get $failure first_failure_ordinal] \
            {Controller failure transition ordinal}
        set failure_reference "failure/[dict get $failure first_failure_ordinal]/[dict get $failure failure_code]"
        set state [_record_failure $state $failure]
    }
    set transition [dict create \
        ordinal $ordinal \
        from_state $current \
        to_state $target \
        decision $decision \
        reason_code $reason \
        decision_reference $reference \
        failure_reference $failure_reference]
    dict lappend state transition_history $transition
    dict set state current_state $target
    dict set state decision_ordinal $ordinal
    dict set state continuation_decision $decision
    set controller_decision [dict create \
        schema_version stage1e-vivado-controller-decision-v1 \
        decision_reference $reference \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        decision_ordinal $ordinal \
        current_state $target \
        operation $operation \
        decision $decision \
        reason_code $reason \
        authorization_receipt_reference \
            [dict get $state authorization_receipt_reference] \
        snapshot_reference $snapshot_reference \
        failure_reference $failure_reference \
        assembly_validation_state \
            [dict get $state assembly_validation_state] \
        dependency_closure_state [dict get $state dependency_closure_state] \
        closure_scope [dict get $state closure_scope]]
    ::stage1e::vivado_runtime_contract_v1::require_record \
        controller_decision $controller_decision
    validate_state $state
    return [list $state $controller_decision]
}

proc ::stage1e::production_vivado_controller_v1::transition {
    request state target operation decision reason snapshot_reference
    {failure NONE}
} {
    return [_transition $request $state $target $operation $decision $reason \
        $snapshot_reference $failure]
}

proc ::stage1e::production_vivado_controller_v1::expected_assembly_inventory {} {
    variable build_root
    set build_root \
        [::stage1e::vivado_runtime_contract_v1::canonical_path $build_root]
    set module_root [::stage1e::vivado_runtime_contract_v1::canonical_path \
        [file join $build_root runtime runner]]
    set session_path [::stage1e::vivado_runtime_contract_v1::canonical_path \
        [file join $module_root stage1e_production_vivado_session_v1.tcl]]
    set roles {
        COMMON_CONTRACT ADAPTER CONTROLLER VIVADO_CAPABILITY_OBSERVER RUNNER
        SESSION_ASSEMBLY
    }
    set paths [list \
        [file join $build_root lib stage1e_vivado_runtime_contract_v1.tcl] \
        [file join $build_root adapters \
            stage1e_production_vivado_adapter_v1.tcl] \
        [file join $build_root controller \
            stage1e_production_vivado_controller_v1.tcl] \
        [file join $build_root runtime observer vivado \
            stage1e_production_vivado_observer_v1.tcl] \
        [file join $build_root runtime runner \
            stage1e_production_vivado_runner_v1.tcl] \
        $session_path]
    set interfaces {
        stage1e-vivado-runtime-common-interface-v1
        stage1e-production-vivado-adapter-interface-v1
        stage1e-production-vivado-controller-interface-v1
        stage1e-production-vivado-observer-interface-v1
        stage1e-production-vivado-runner-interface-v1
        stage1e-production-vivado-session-interface-v1
    }
    set entries {}
    set ordinal 0
    foreach role $roles path $paths interface_version $interfaces {
        incr ordinal
        lappend entries [dict create ordinal $ordinal role $role \
            path [::stage1e::vivado_runtime_contract_v1::canonical_path $path] \
            interface_version $interface_version]
    }
    set inventory [dict create \
        schema_version stage1e-prt02c-fixed-assembly-inventory-v1 \
        assembly_validation_state PRT02C_FIXED_ASSEMBLY_VALIDATED \
        dependency_closure_state NOT_PROVEN \
        closure_scope PRT02C_DIRECT_ASSEMBLY_ONLY \
        session_module_path $session_path \
        module_root $module_root \
        build_root $build_root \
        entries $entries]
    ::stage1e::vivado_runtime_contract_v1::validate_assembly_inventory \
        $inventory
    return $inventory
}

proc ::stage1e::production_vivado_controller_v1::validate_assembly {
    request state inventory
} {
    ::stage1e::vivado_runtime_contract_v1::validate_controller_request $request
    validate_state $state
    ::stage1e::vivado_runtime_contract_v1::require_equal REQUEST_VALIDATED \
        [dict get $state current_state] {PRT02-C assembly source state}
    set context [dict get $request session_context]
    ::stage1e::vivado_runtime_contract_v1::validate_session_context $context
    ::stage1e::vivado_runtime_contract_v1::validate_assembly_inventory \
        $inventory
    set expected [expected_assembly_inventory]
    foreach field {
        schema_version assembly_validation_state dependency_closure_state
        closure_scope session_module_path module_root build_root
    } {
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            [dict get $expected $field] [dict get $inventory $field] \
            "PRT02-C assembly $field"
    }
    foreach actual_entry [dict get $inventory entries] \
            expected_entry [dict get $expected entries] {
        foreach field {ordinal role path interface_version} {
            ::stage1e::vivado_runtime_contract_v1::require_equal \
                [dict get $expected_entry $field] [dict get $actual_entry $field] \
                "PRT02-C assembly entry $field"
        }
    }
    dict set state assembly_validation_state \
        PRT02C_FIXED_ASSEMBLY_VALIDATED
    return [_transition $request $state PRT02C_ASSEMBLY_VALIDATED \
        prt02c_direct_assembly_validation PROCEED \
        PRT02C_FIXED_ASSEMBLY_VALIDATED \
        "session/[dict get $context session_id]/prt02c-direct-assembly" NONE]
}

proc ::stage1e::production_vivado_controller_v1::_snapshot_bindings {
    request snapshot expected_phase
} {
    ::stage1e::vivado_runtime_contract_v1::validate_snapshot $snapshot
    foreach field {
        request_identity execution_id attempt_id workspace_identity
    } {
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            [dict get $request $field] [dict get $snapshot $field] \
            "Observer snapshot binding $field"
    }
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        [dict get $request session_context session_id] \
        [dict get $snapshot session_id] {Observer snapshot session}
    ::stage1e::vivado_runtime_contract_v1::require_equal $expected_phase \
        [dict get $snapshot phase] {Observer snapshot phase}
    return 1
}

proc ::stage1e::production_vivado_controller_v1::_snapshot_block_failure {
    state category code phase snapshot
} {
    set authorization_effect [dict get $state authorization_effect]
    set retry REVIEW_BEFORE_NEW_LAUNCH
    if {$authorization_effect eq {CONSUMED_ONCE}} {
        set retry NEW_EXECUTION_REQUIRED
    }
    return [::stage1e::vivado_runtime_contract_v1::make_failure \
        BLOCKED $category $code CONTROLLER $phase \
        [expr {[dict get $state decision_ordinal] + 1}] \
        $authorization_effect STATE_UNKNOWN PARTIAL_PRESERVED $retry \
        "Observer snapshot blocked: [join [dict get $snapshot blocking_reasons] {, }]" \
        [list [dict get $snapshot snapshot_reference]]]
}

proc ::stage1e::production_vivado_controller_v1::accept_tool_preflight {
    request state snapshot
} {
    validate_state $state
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        PRT02C_ASSEMBLY_VALIDATED [dict get $state current_state] \
        {Tool-preflight source state}
    _snapshot_bindings $request $snapshot TOOL_PREFLIGHT
    if {[dict get $snapshot overall_state] ne {CLEAR}} {
        set failure [_snapshot_block_failure $state TOOL_CAPABILITY \
            VIVADO_TOOL_PREFLIGHT_BLOCKED VIVADO_PREFLIGHT $snapshot]
        return [_transition $request $state BLOCKED tool_preflight BLOCK \
            VIVADO_TOOL_PREFLIGHT_BLOCKED \
            [dict get $snapshot snapshot_reference] $failure]
    }
    return [_transition $request $state TOOL_PREFLIGHT_OBSERVED \
        tool_preflight PROCEED TOOL_PREFLIGHT_CLEAR \
        [dict get $snapshot snapshot_reference] NONE]
}

proc ::stage1e::production_vivado_controller_v1::accept_pre_consume {
    request state snapshot
} {
    validate_state $state
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        TOOL_PREFLIGHT_OBSERVED [dict get $state current_state] \
        {Pre-consume source state}
    _snapshot_bindings $request $snapshot PRE_CONSUME
    if {[dict get $snapshot overall_state] ne {CLEAR}} {
        set failure [_snapshot_block_failure $state CONFIGURATION_READBACK \
            PRE_CONSUME_READBACK_BLOCKED VIVADO_PREFLIGHT $snapshot]
        return [_transition $request $state BLOCKED pre_consume BLOCK \
            PRE_CONSUME_READBACK_BLOCKED \
            [dict get $snapshot snapshot_reference] $failure]
    }
    return [_transition $request $state PRE_CONSUME_OBSERVED \
        pre_consume PROCEED PRE_CONSUME_CLEAR \
        [dict get $snapshot snapshot_reference] NONE]
}

proc ::stage1e::production_vivado_controller_v1::_receipt_payload {
    request snapshot decision_reference
} {
    set authorization [dict get $request authorization]
    return [dict create \
        schema_version \
            stage1e-vivado-authorization-consumption-receipt-v1 \
        receipt_state SEALED \
        request_identity [dict get $request request_identity] \
        sealed_request_path [dict get $request sealed_request_path] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        authorization_identity \
            [dict get $authorization authorization_identity] \
        capability IMPLEMENTATION \
        issue_state AUTHORIZED \
        prior_consumption_state UNCONSUMED \
        consumption_state CONSUMED_ONCE \
        consumption_ordinal 1 \
        source_identity [dict get $request source_identity] \
        runtime_backend_identity [dict get $request runtime_backend_identity] \
        policy_identity [dict get $request policy_identity] \
        configuration_identity [dict get $request configuration_identity] \
        qualification_identity [dict get $request qualification_identity] \
        environment_identity [dict get $request environment_identity] \
        workspace_identity [dict get $request workspace_identity] \
        synthesis_result_identity \
            [dict get $request synthesis_result_identity] \
        allowed_operation_contract_identity \
            [dict get $authorization allowed_operation_contract_identity] \
        forbidden_operation_contract_identity \
            [dict get $authorization forbidden_operation_contract_identity] \
        pre_consume_snapshot_reference \
            [dict get $snapshot snapshot_reference] \
        controller_decision_reference $decision_reference \
        consumption_owner CONTROLLER \
        reuse_policy PROHIBITED \
        receipt_path [dict get $authorization consumption_record_path] \
        publication_mode APPEND_ONLY \
        overwrite_policy PROHIBITED \
        authorization_effect CONSUMED_ONCE \
        qualification_decision_authority NONE \
        authorization_issue_authority NONE \
        engineering_acceptance_authority NONE \
        artifact_authority NONE \
        publication_authority NONE \
        hardware_manager_authority NONE \
        board_authority NONE \
        candidate_effect NOT_CREATED]
}

proc ::stage1e::production_vivado_controller_v1::_consumption_failure {
    request state snapshot code message authorization_effect
} {
    set retry RETRY_PROHIBITED_PENDING_RUNTIME_FIX
    set evidence_state INTEGRITY_UNKNOWN
    if {$authorization_effect eq {CONSUMPTION_FAILED}} {
        set retry REVIEW_BEFORE_NEW_LAUNCH
        set evidence_state PARTIAL_PRESERVED
    }
    set failure [::stage1e::vivado_runtime_contract_v1::make_failure \
        BLOCKED AUTHORIZATION $code CONTROLLER AUTHORIZATION_CONSUMPTION \
        [expr {[dict get $state decision_ordinal] + 1}] \
        $authorization_effect STATE_UNKNOWN $evidence_state $retry \
        $message [list [dict get $snapshot snapshot_reference]]]
    lassign [_transition $request $state BLOCKED authorization_consumption \
        BLOCK $code [dict get $snapshot snapshot_reference] $failure] \
        blocked_state blocked_decision
    return [dict create \
        schema_version stage1e-vivado-authorization-consumption-result-v1 \
        controller_state $blocked_state \
        receipt NONE \
        receipt_reference NONE \
        publication_receipt NONE \
        decision $blocked_decision]
}

proc ::stage1e::production_vivado_controller_v1::consume_authorization {
    request state snapshot
} {
    validate_state $state
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        PRE_CONSUME_OBSERVED [dict get $state current_state] \
        {Authorization-consumption source state}
    _snapshot_bindings $request $snapshot PRE_CONSUME
    if {[dict get $snapshot overall_state] ne {CLEAR}} {
        return [_consumption_failure $request $state $snapshot \
            PRE_CONSUME_STATE_NOT_CLEAR \
            {Authorization cannot be consumed after a blocked observation.} \
            NOT_TOUCHED]
    }
    set path [dict get $request authorization consumption_record_path]
    if {[file exists $path]} {
        return [_consumption_failure $request $state $snapshot \
            AUTHORIZATION_RECEIPT_COLLISION \
            {The reserved authorization receipt path already exists.} \
            STATE_UNKNOWN]
    }
    set ordinal [expr {[dict get $state decision_ordinal] + 1}]
    set decision_reference \
        [::stage1e::vivado_runtime_contract_v1::decision_reference \
            $request $ordinal AUTHORIZATION_CONSUMED_ONCE \
            authorization_consumption]
    set payload [_receipt_payload $request $snapshot $decision_reference]
    set receipt [::stage1e::vivado_runtime_contract_v1::attach_receipt_identity \
        $payload]
    set bytes [::stage1e::vivado_runtime_contract_v1::receipt_bytes $receipt]
    set boundary [dict get $request launch_contract evidence_root]
    set publish_status [catch {
        ::stage1e::atomic_publication_v1::publish $path $bytes $boundary
    } publication publication_options]
    if {$publish_status != 0} {
        set error_code [dict get $publication_options -errorcode]
        set effect CONSUMPTION_FAILED
        if {[lsearch -exact $error_code COLLISION] >= 0 ||
                [file exists $path]} {
            set effect STATE_UNKNOWN
        }
        return [_consumption_failure $request $state $snapshot \
            AUTHORIZATION_RECEIPT_PUBLICATION_FAILED \
            "Authorization receipt publication failed: $publication" $effect]
    }
    set reopen_status [catch {
        ::stage1e::vivado_runtime_contract_v1::read_receipt $path
    } reopened reopen_options]
    if {$reopen_status != 0 || $reopened ne $receipt} {
        return [_consumption_failure $request $state $snapshot \
            AUTHORIZATION_RECEIPT_REOPEN_FAILED \
            {Published authorization receipt could not be reopened exactly.} \
            STATE_UNKNOWN]
    }
    lassign [_transition $request $state AUTHORIZATION_CONSUMED_ONCE \
        authorization_consumption PROCEED AUTHORIZATION_CONSUMED_ONCE \
        [dict get $snapshot snapshot_reference] NONE] consumed_state decision
    set receipt_reference \
        [::stage1e::vivado_runtime_contract_v1::receipt_reference $receipt]
    dict set consumed_state authorization_effect CONSUMED_ONCE
    dict set consumed_state authorization_receipt_reference $receipt_reference
    dict set decision authorization_receipt_reference $receipt_reference
    validate_state $consumed_state
    set result [dict create \
        schema_version stage1e-vivado-authorization-consumption-result-v1 \
        controller_state $consumed_state \
        receipt $receipt \
        receipt_reference $receipt_reference \
        publication_receipt $publication \
        decision $decision]
    ::stage1e::vivado_runtime_contract_v1::require_record \
        authorization_consumption_result $result
    return $result
}

proc ::stage1e::production_vivado_controller_v1::_phase_permit_contract {
    operation
} {
    switch -- $operation {
        opt_design {
            return [dict create source AUTHORIZATION_CONSUMED_ONCE \
                target OPT_PERMITTED snapshot PRE_CONSUME]
        }
        place_design {
            return [dict create source OPT_COMPLETED target PLACE_PERMITTED \
                snapshot POST_OPT]
        }
        route_design {
            return [dict create source PLACE_COMPLETED target ROUTE_PERMITTED \
                snapshot POST_PLACE]
        }
        default {
            _raise OPERATION_INVALID \
                "Controller cannot permit operation: $operation"
        }
    }
}

proc ::stage1e::production_vivado_controller_v1::permit_phase {
    request state operation snapshot
} {
    validate_state $state
    set contract [_phase_permit_contract $operation]
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        [dict get $contract source] [dict get $state current_state] \
        {Phase-permit source state}
    if {[dict get $state authorization_receipt_reference] eq {NONE}} {
        _raise AUTHORIZATION_REQUIRED \
            {Controller cannot permit a phase without a sealed receipt.}
    }
    _snapshot_bindings $request $snapshot [dict get $contract snapshot]
    if {[dict get $snapshot overall_state] ne {CLEAR}} {
        set failure [_snapshot_block_failure $state CONFIGURATION_READBACK \
            PHASE_CONTINUATION_SNAPSHOT_BLOCKED \
            [string toupper $operation] $snapshot]
        return [_transition $request $state BLOCKED $operation BLOCK \
            PHASE_CONTINUATION_SNAPSHOT_BLOCKED \
            [dict get $snapshot snapshot_reference] $failure]
    }
    return [_transition $request $state [dict get $contract target] \
        $operation PROCEED PHASE_EXACTLY_PERMITTED \
        [dict get $snapshot snapshot_reference] NONE]
}

proc ::stage1e::production_vivado_controller_v1::_phase_result_contract {
    operation
} {
    switch -- $operation {
        opt_design {
            return [dict create source OPT_PERMITTED target OPT_COMPLETED \
                phase POST_OPT category OPTIMIZATION failure_phase OPT_DESIGN]
        }
        place_design {
            return [dict create source PLACE_PERMITTED target PLACE_COMPLETED \
                phase POST_PLACE category PLACEMENT failure_phase PLACE_DESIGN]
        }
        route_design {
            return [dict create source ROUTE_PERMITTED target ROUTE_COMPLETED \
                phase POST_ROUTE category ROUTING failure_phase ROUTE_DESIGN]
        }
        default {
            _raise OPERATION_INVALID \
                "Controller cannot accept operation result: $operation"
        }
    }
}

proc ::stage1e::production_vivado_controller_v1::accept_phase_result {
    request state result
} {
    ::stage1e::vivado_runtime_contract_v1::validate_phase_result $result
    validate_state $state
    set operation [dict get $result logical_operation]
    set contract [_phase_result_contract $operation]
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        [dict get $contract source] [dict get $state current_state] \
        {Phase-result source state}
    foreach field {request_identity execution_id attempt_id workspace_identity} {
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            [dict get $request $field] [dict get $result $field] \
            "Phase-result binding $field"
    }
    set snapshot [dict get $result observer_snapshot]
    _snapshot_bindings $request $snapshot [dict get $contract phase]
    set phase_status [dict get $result phase_status]
    set forbidden [dict get $result forbidden_operation_result]
    if {$phase_status eq {COMPLETED} &&
            [dict get $snapshot overall_state] eq {CLEAR} &&
            [dict get $forbidden result] eq {CLEAR}} {
        return [_transition $request $state [dict get $contract target] \
            $operation PROCEED PHASE_COMPLETED_WITH_READBACK \
            [dict get $snapshot snapshot_reference] NONE]
    }
    set failure [dict get $result first_failure]
    if {$failure eq {NONE}} {
        set terminal [expr {$phase_status eq {FAILED} ? {FAILED} : {BLOCKED}}]
        set code [expr {$phase_status eq {FAILED} ?
            {VIVADO_PHASE_COMMAND_FAILED} : {VIVADO_PHASE_STATE_UNCERTAIN}}]
        set failure [::stage1e::vivado_runtime_contract_v1::make_failure \
            $terminal [dict get $contract category] $code RUNNER \
            [dict get $contract failure_phase] \
            [expr {[dict get $state decision_ordinal] + 1}] CONSUMED_ONCE \
            STATE_UNKNOWN PARTIAL_PRESERVED NEW_EXECUTION_REQUIRED \
            "Runner phase did not complete: $operation/$phase_status" \
            [list [dict get $snapshot snapshot_reference]]]
    }
    set target [expr {[dict get $failure terminal_status] eq {FAILED} ?
        {FAILED} : {BLOCKED}}]
    set decision [expr {$target eq {FAILED} ? {STOP} : {BLOCK}}]
    return [_transition $request $state $target $operation $decision \
        [dict get $failure failure_code] \
        [dict get $snapshot snapshot_reference] $failure]
}

proc ::stage1e::production_vivado_controller_v1::permit_collector_handoff {
    request state post_route_snapshot
} {
    validate_state $state
    ::stage1e::vivado_runtime_contract_v1::require_equal ROUTE_COMPLETED \
        [dict get $state current_state] {Collector-handoff source state}
    _snapshot_bindings $request $post_route_snapshot POST_ROUTE
    if {[dict get $post_route_snapshot overall_state] ne {CLEAR}} {
        set failure [_snapshot_block_failure $state CONFIGURATION_READBACK \
            POST_ROUTE_READBACK_BLOCKED REPORT_COLLECTION $post_route_snapshot]
        return [_transition $request $state BLOCKED implementation_reports \
            BLOCK POST_ROUTE_READBACK_BLOCKED \
            [dict get $post_route_snapshot snapshot_reference] $failure]
    }
    return [_transition $request $state COLLECTOR_HANDOFF_READY \
        implementation_reports PROCEED ROUTED_COLLECTOR_HANDOFF_PERMITTED \
        [dict get $post_route_snapshot snapshot_reference] NONE]
}

proc ::stage1e::production_vivado_controller_v1::accept_handoff_result {
    request state result
} {
    validate_state $state
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        COLLECTOR_HANDOFF_READY [dict get $state current_state] \
        {Routed-open result source state}
    ::stage1e::vivado_runtime_contract_v1::require_exact_fields $result {
        open_state handoff terminal_snapshot failure
    } {Routed-open result}
    set handoff [dict get $result handoff]
    set snapshot [dict get $result terminal_snapshot]
    ::stage1e::vivado_runtime_contract_v1::validate_handoff $handoff
    _snapshot_bindings $request $snapshot TERMINAL
    set failure [dict get $result failure]
    if {$failure eq {NONE}} {
        ::stage1e::vivado_runtime_contract_v1::require_equal \
            OPENED_SAME_ROUTED_RUN [dict get $result open_state] \
            {Routed-open result state}
        ::stage1e::vivado_runtime_contract_v1::require_equal ROUTED_REPORTING \
            [dict get $handoff mode] {Routed-open handoff mode}
        return [list $state NONE]
    }
    ::stage1e::vivado_runtime_contract_v1::validate_failure $failure
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        FAILURE_EVIDENCE_ONLY [dict get $handoff mode] \
        {Blocked routed-open handoff mode}
    set target [expr {[dict get $failure terminal_status] eq {FAILED} ?
        {FAILED} : {BLOCKED}}]
    set decision [expr {$target eq {FAILED} ? {STOP} : {BLOCK}}]
    return [_transition $request $state $target implementation_reports \
        $decision [dict get $failure failure_code] \
        [dict get $snapshot snapshot_reference] $failure]
}

proc ::stage1e::production_vivado_controller_v1::block_at_collector {
    request state handoff
} {
    validate_state $state
    ::stage1e::vivado_runtime_contract_v1::require_equal \
        COLLECTOR_HANDOFF_READY [dict get $state current_state] \
        {Collector boundary source state}
    ::stage1e::vivado_runtime_contract_v1::validate_handoff $handoff
    set failure [::stage1e::vivado_runtime_contract_v1::make_failure \
        BLOCKED DEPENDENCY_CLOSURE PRODUCTION_COLLECTOR_NOT_IMPLEMENTED \
        CONTROLLER REPORT_COLLECTION \
        [expr {[dict get $state decision_ordinal] + 1}] CONSUMED_ONCE \
        STATE_UNKNOWN PARTIAL_PRESERVED \
        RETRY_PROHIBITED_PENDING_RUNTIME_FIX \
        {The routed collector handoff is structurally ready, but the production Collector is not implemented.} \
        [list [dict get $handoff handoff_reference]]]
    return [_transition $request $state \
        VIVADO_COMPONENT_BLOCKED_AT_COLLECTOR implementation_reports BLOCK \
        PRODUCTION_COLLECTOR_NOT_IMPLEMENTED \
        [dict get $handoff handoff_reference] $failure]
}

proc ::stage1e::production_vivado_controller_v1::component_result {
    request state ledger snapshots handoff
} {
    validate_state $state
    ::stage1e::vivado_runtime_contract_v1::require_one_of \
        [dict get $state current_state] \
        {VIVADO_COMPONENT_BLOCKED_AT_COLLECTOR FAILED BLOCKED} \
        {Vivado component controller state}
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    ::stage1e::vivado_runtime_contract_v1::validate_handoff $handoff
    set snapshot_references {}
    foreach snapshot $snapshots {
        ::stage1e::vivado_runtime_contract_v1::validate_snapshot $snapshot
        lappend snapshot_references [dict get $snapshot snapshot_reference]
    }
    set first_failure [dict get $state first_failure]
    if {$first_failure eq {NONE}} {
        _raise STATE_INVALID \
            {A terminal Vivado component result requires a first failure.}
    }
    set terminal_status [dict get $first_failure terminal_status]
    set result [dict create \
        schema_version stage1e-vivado-component-result-v1 \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        session_id [dict get $request session_context session_id] \
        terminal_status $terminal_status \
        controller_state $state \
        authorization_effect [dict get $state authorization_effect] \
        operation_ledger $ledger \
        capability_snapshot_references $snapshot_references \
        collector_handoff $handoff \
        first_failure $first_failure \
        secondary_failures [dict get $state secondary_failures] \
        evidence_completeness PARTIAL_PRESERVED \
        candidate_effect NOT_CREATED \
        process_effect STATE_UNKNOWN \
        process_effect_owner HOST_RESULT_NOT_CONNECTED \
        collector_state NOT_IMPLEMENTED \
        parser_state NOT_IMPLEMENTED \
        dependency_closure_state NOT_PROVEN \
        qualification_state VIVADO_2024_1_QUALIFICATION_REQUIRED \
        public_runtime_path_state DISCONNECTED \
        backend_capability_state MOCK_ONLY \
        backend_review_state REVIEW_REQUIRED \
        authority_boundary \
            [::stage1e::vivado_runtime_contract_v1::runtime_authority_boundary]]
    ::stage1e::vivado_runtime_contract_v1::validate_component_result $result
    return $result
}
