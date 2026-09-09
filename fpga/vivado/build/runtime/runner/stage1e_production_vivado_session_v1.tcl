# Stage 1E PRT02-C controlled Vivado-side session assembly candidate v1.
#
# This subordinate Tcl assembly is not a host-facing entry point. It reopens
# the same sealed two-input request, loads only fixed versioned modules, and
# preserves controller authority over every continuation decision.

set ::stage1e_production_vivado_session_source_path \
    [file normalize [info script]]
namespace eval ::stage1e::production_vivado_session_v1 {
    variable interface_version stage1e-production-vivado-session-interface-v1
    variable module_path $::stage1e_production_vivado_session_source_path
    variable module_root [file dirname $module_path]
    variable build_root [file normalize [file join $module_root .. ..]]
}
unset ::stage1e_production_vivado_session_source_path

if {![llength [info commands \
        ::stage1e::vivado_runtime_contract_v1::configure_from_build_root]]} {
    source [file join $::stage1e::production_vivado_session_v1::build_root lib \
        stage1e_vivado_runtime_contract_v1.tcl]
}
if {![llength [info commands \
        ::stage1e::production_vivado_adapter_v1::project_request]]} {
    source [file join $::stage1e::production_vivado_session_v1::build_root \
        adapters stage1e_production_vivado_adapter_v1.tcl]
}
if {![llength [info commands \
        ::stage1e::production_vivado_controller_v1::initialize]]} {
    source [file join $::stage1e::production_vivado_session_v1::build_root \
        controller stage1e_production_vivado_controller_v1.tcl]
}
if {![llength [info commands \
        ::stage1e::production_vivado_observer_v1::observe]]} {
    source [file join $::stage1e::production_vivado_session_v1::build_root \
        runtime observer vivado stage1e_production_vivado_observer_v1.tcl]
}
if {![llength [info commands \
        ::stage1e::production_vivado_runner_v1::execute_phase]]} {
    source [file join $::stage1e::production_vivado_session_v1::build_root \
        runtime runner stage1e_production_vivado_runner_v1.tcl]
}

proc ::stage1e::production_vivado_session_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_vivado_session_v1::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E PRT02C VIVADO_SESSION $code] $message
}

proc ::stage1e::production_vivado_session_v1::load_inventory {} {
    variable build_root
    variable module_path
    variable module_root
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
        $module_path]
    set roles {
        COMMON_CONTRACT ADAPTER CONTROLLER VIVADO_CAPABILITY_OBSERVER RUNNER
        SESSION_ASSEMBLY
    }
    set interfaces [list \
        [::stage1e::vivado_runtime_contract_v1::interface_version] \
        [::stage1e::production_vivado_adapter_v1::interface_version] \
        [::stage1e::production_vivado_controller_v1::interface_version] \
        [::stage1e::production_vivado_observer_v1::interface_version] \
        [::stage1e::production_vivado_runner_v1::interface_version] \
        [interface_version]]
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
        session_module_path \
            [::stage1e::vivado_runtime_contract_v1::canonical_path $module_path] \
        module_root \
            [::stage1e::vivado_runtime_contract_v1::canonical_path $module_root] \
        build_root \
            [::stage1e::vivado_runtime_contract_v1::canonical_path $build_root] \
        entries $entries]
    ::stage1e::vivado_runtime_contract_v1::validate_assembly_inventory \
        $inventory
    return $inventory
}

proc ::stage1e::production_vivado_session_v1::_load_request {
    request_path expected_request_identity
} {
    variable build_root
    set contract [::stage1e::envelope_contract_v1::load \
        [file join $build_root lib]]
    set canonical_path \
        [::stage1e::vivado_runtime_contract_v1::canonical_path $request_path]
    set first_bytes \
        [::stage1e::atomic_publication_v1::read_binary $canonical_path]
    set first_record [::stage1e::envelope_contract_v1::parse_request \
        $first_bytes $contract $expected_request_identity]
    set second_bytes \
        [::stage1e::atomic_publication_v1::read_binary $canonical_path]
    if {![::stage1e::canonical_json_v1::bytes_equal \
            $first_bytes $second_bytes]} {
        _raise REQUEST_CHANGED \
            {The sealed request changed between Vivado-side observations.}
    }
    set second_record [::stage1e::envelope_contract_v1::parse_request \
        $second_bytes $contract $expected_request_identity]
    if {![::stage1e::canonical_json_v1::node_equal \
            $first_record $second_record]} {
        _raise REQUEST_CHANGED \
            {The sealed request record changed between observations.}
    }
    return [dict create record $second_record path $canonical_path]
}

proc ::stage1e::production_vivado_session_v1::_require_state {
    state expected label
} {
    ::stage1e::production_vivado_controller_v1::validate_state $state
    ::stage1e::vivado_runtime_contract_v1::require_equal $expected \
        [dict get $state current_state] $label
    return 1
}

proc ::stage1e::production_vivado_session_v1::_phase {
    request state ledger receipt prior_snapshot operation observation_ordinal
} {
    lassign [::stage1e::production_vivado_controller_v1::permit_phase \
        $request $state $operation $prior_snapshot] permitted_state decision
    set phase_request \
        [::stage1e::production_vivado_adapter_v1::make_phase_request \
            $request $decision $receipt $ledger $prior_snapshot $operation]
    set result [::stage1e::production_vivado_runner_v1::execute_phase \
        $phase_request $observation_ordinal]
    set result [::stage1e::production_vivado_adapter_v1::normalize_phase_result \
        $result]
    lassign [::stage1e::production_vivado_controller_v1::accept_phase_result \
        $request $permitted_state $result] completed_state completed_decision
    return [dict create \
        state $completed_state \
        decision $completed_decision \
        result $result \
        ledger [dict get $result operation_ledger] \
        snapshot [dict get $result observer_snapshot]]
}

proc ::stage1e::production_vivado_session_v1::_is_terminal {state} {
    return [expr {[dict get $state current_state] in {
        FAILED BLOCKED VIVADO_COMPONENT_BLOCKED_AT_COLLECTOR
    }}]
}

proc ::stage1e::production_vivado_session_v1::_terminal_result {
    request state receipt ledger snapshots handoff
} {
    if {![_is_terminal $state]} {
        _raise INTERNAL_STATE \
            {A nonterminal controller state reached terminal-result assembly.}
    }
    ::stage1e::production_vivado_controller_v1::validate_state $state
    ::stage1e::vivado_runtime_contract_v1::validate_ledger $ledger
    set handoff \
        [::stage1e::production_vivado_adapter_v1::normalize_handoff $handoff]
    set component_result \
        [::stage1e::production_vivado_controller_v1::component_result \
            $request $state $ledger $snapshots $handoff]
    set component_result \
        [::stage1e::production_vivado_adapter_v1::normalize_component_result \
            $component_result]
    set terminal_status [dict get $component_result terminal_status]
    set result [dict create \
        schema_version stage1e-production-vivado-session-result-v1 \
        terminal_status $terminal_status \
        controller_state $state \
        authorization_receipt $receipt \
        operation_ledger $ledger \
        collector_handoff $handoff \
        snapshots $snapshots \
        component_result $component_result \
        candidate_effect NOT_CREATED]
    ::stage1e::vivado_runtime_contract_v1::validate_session_result $result
    return $result
}

proc ::stage1e::production_vivado_session_v1::_phase_terminal_result {
    request phase_result state receipt snapshots
} {
    set ledger [dict get $phase_result operation_ledger]
    set snapshot [dict get $phase_result observer_snapshot]
    set failure [dict get $state first_failure]
    set handoff \
        [::stage1e::production_vivado_runner_v1::failure_handoff \
            $request $ledger [dict get $phase_result logical_operation] \
            $failure [dict get $snapshot snapshot_reference]]
    return [_terminal_result $request $state $receipt $ledger $snapshots \
        $handoff]
}

proc ::stage1e::production_vivado_session_v1::run {
    request_path expected_request_identity session_context
} {
    variable build_root
    ::stage1e::vivado_runtime_contract_v1::configure_from_build_root $build_root
    ::stage1e::vivado_runtime_contract_v1::validate_session_context \
        $session_context
    set loaded [_load_request $request_path $expected_request_identity]
    set request [::stage1e::production_vivado_adapter_v1::project_request \
        [dict get $loaded record] [dict get $loaded path] $session_context]
    set state [::stage1e::production_vivado_controller_v1::initialize $request]
    set assembly_inventory [load_inventory]
    lassign [::stage1e::production_vivado_controller_v1::validate_assembly \
        $request $state $assembly_inventory] state assembly_decision
    _require_state $state PRT02C_ASSEMBLY_VALIDATED \
        {Session PRT02-C assembly state}

    set tool_snapshot [::stage1e::production_vivado_observer_v1::observe \
        $request TOOL_PREFLIGHT 1]
    set tool_snapshot \
        [::stage1e::production_vivado_adapter_v1::normalize_snapshot \
            $tool_snapshot]
    lassign [::stage1e::production_vivado_controller_v1::accept_tool_preflight \
        $request $state $tool_snapshot] state tool_decision
    _require_state $state TOOL_PREFLIGHT_OBSERVED \
        {Session tool-preflight state}

    set preconsume_snapshot \
        [::stage1e::production_vivado_observer_v1::observe \
            $request PRE_CONSUME 2]
    set preconsume_snapshot \
        [::stage1e::production_vivado_adapter_v1::normalize_snapshot \
            $preconsume_snapshot]
    lassign [::stage1e::production_vivado_controller_v1::accept_pre_consume \
        $request $state $preconsume_snapshot] state preconsume_decision
    _require_state $state PRE_CONSUME_OBSERVED {Session pre-consume state}

    set consumption \
        [::stage1e::production_vivado_controller_v1::consume_authorization \
            $request $state $preconsume_snapshot]
    set state [dict get $consumption controller_state]
    _require_state $state AUTHORIZATION_CONSUMED_ONCE \
        {Session authorization state}
    set receipt [dict get $consumption receipt]
    set ledger [::stage1e::production_vivado_runner_v1::initialize_ledger \
        $request $receipt]
    set snapshots [list $tool_snapshot $preconsume_snapshot]

    set opt [_phase $request $state $ledger $receipt $preconsume_snapshot \
        opt_design 3]
    set state [dict get $opt state]
    set ledger [dict get $opt ledger]
    set opt_snapshot [dict get $opt snapshot]
    lappend snapshots $opt_snapshot
    if {[_is_terminal $state]} {
        return [_phase_terminal_result $request [dict get $opt result] \
            $state $receipt $snapshots]
    }
    _require_state $state OPT_COMPLETED {Session optimization state}

    set place [_phase $request $state $ledger $receipt $opt_snapshot \
        place_design 4]
    set state [dict get $place state]
    set ledger [dict get $place ledger]
    set place_snapshot [dict get $place snapshot]
    lappend snapshots $place_snapshot
    if {[_is_terminal $state]} {
        return [_phase_terminal_result $request [dict get $place result] \
            $state $receipt $snapshots]
    }
    _require_state $state PLACE_COMPLETED {Session placement state}

    set route [_phase $request $state $ledger $receipt $place_snapshot \
        route_design 5]
    set state [dict get $route state]
    set ledger [dict get $route ledger]
    set route_snapshot [dict get $route snapshot]
    lappend snapshots $route_snapshot
    if {[_is_terminal $state]} {
        return [_phase_terminal_result $request [dict get $route result] \
            $state $receipt $snapshots]
    }
    _require_state $state ROUTE_COMPLETED {Session routing state}

    lassign \
        [::stage1e::production_vivado_controller_v1::permit_collector_handoff \
            $request $state $route_snapshot] state handoff_decision
    _require_state $state COLLECTOR_HANDOFF_READY \
        {Session collector-handoff state}
    set open_result \
        [::stage1e::production_vivado_runner_v1::open_and_handoff \
            $request $handoff_decision $ledger $route_snapshot 6]
    set handoff [dict get $open_result handoff]
    set terminal_snapshot [dict get $open_result terminal_snapshot]
    lappend snapshots $terminal_snapshot
    if {[dict get $open_result failure] ne {NONE}} {
        lassign \
            [::stage1e::production_vivado_controller_v1::accept_handoff_result \
                $request $state $open_result] state open_decision
        set ledger [dict get $open_result handoff operation_ledger]
        return [_terminal_result $request $state $receipt $ledger $snapshots \
            $handoff]
    }
    ::stage1e::production_vivado_controller_v1::accept_handoff_result \
        $request $state $open_result
    lassign [::stage1e::production_vivado_controller_v1::block_at_collector \
        $request $state $handoff] state collector_decision
    _require_state $state VIVADO_COMPONENT_BLOCKED_AT_COLLECTOR \
        {Session collector boundary state}
    set collector_failure [dict get $state first_failure]
    set ledger \
        [::stage1e::production_vivado_runner_v1::mark_collector_unavailable \
            $ledger $collector_decision $handoff $collector_failure]
    dict set handoff operation_ledger $ledger
    dict set handoff failure_references \
        [list "failure/[dict get $collector_failure failure_code]"]
    ::stage1e::vivado_runtime_contract_v1::validate_handoff $handoff
    return [_terminal_result $request $state $receipt $ledger $snapshots \
        $handoff]
}
