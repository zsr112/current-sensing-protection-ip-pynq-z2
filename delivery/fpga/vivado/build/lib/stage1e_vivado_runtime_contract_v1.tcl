# Stage 1E PRT02-C Vivado runtime common contract v1.
#
# This module validates versioned Tcl record contracts and the separate
# canonical JSON authorization-consumption receipt. It creates no identity,
# qualification, authorization grant, implementation result, or acceptance
# decision.

set ::stage1e_vivado_runtime_contract_module_root \
    [file dirname [file normalize [info script]]]
if {![llength [info commands ::stage1e::canonical_json_v1::parse_bytes]]} {
    source [file join $::stage1e_vivado_runtime_contract_module_root \
        stage1e_runtime_canonical_json_v1.tcl]
}
if {![llength [info commands ::stage1e::envelope_contract_v1::load]]} {
    source [file join $::stage1e_vivado_runtime_contract_module_root \
        stage1e_runtime_envelope_contract_v1.tcl]
}
if {![llength [info commands ::stage1e::atomic_publication_v1::publish]]} {
    source [file join $::stage1e_vivado_runtime_contract_module_root \
        stage1e_runtime_atomic_publication_v1.tcl]
}
unset ::stage1e_vivado_runtime_contract_module_root

namespace eval ::stage1e::vivado_runtime_contract_v1 {
    variable interface_version stage1e-vivado-runtime-common-interface-v1
    variable configured 0
    variable record_contract {}
    variable command_contract {}
    variable property_map {}
    variable receipt_schema {}
    variable receipt_registry {}
    variable receipt_schema_path {}
}

proc ::stage1e::vivado_runtime_contract_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::vivado_runtime_contract_v1::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E PRT02C VIVADO_RUNTIME_CONTRACT $code] $message
}

proc ::stage1e::vivado_runtime_contract_v1::require_dictionary {
    value label
} {
    if {[catch {dict size $value} detail]} {
        _raise SCHEMA_INVALID "$label is not a dictionary: $detail"
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::require_exact_fields {
    record fields label
} {
    require_dictionary $record $label
    set expected [lsort -dictionary $fields]
    set actual [lsort -dictionary [dict keys $record]]
    if {$expected ne $actual} {
        _raise EXACT_FIELDS \
            "$label fields differ: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::require_equal {
    expected actual label
} {
    if {$expected ne $actual} {
        _raise CONTRACT_MISMATCH \
            "$label mismatch: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::require_exact_list {
    expected actual label
} {
    set expected [list {*}$expected]
    set actual [list {*}$actual]
    if {$expected ne $actual} {
        _raise CONTRACT_MISMATCH \
            "$label differs: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::require_one_of {
    value allowed label
} {
    if {[lsearch -exact $allowed $value] < 0} {
        _raise ENUM_INVALID "$label has invalid value: $value"
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::require_sha256 {value label} {
    if {![regexp {^[0-9a-f]{64}$} $value] ||
            $value eq [string repeat 0 64]} {
        _raise IDENTITY_INVALID "$label is not a canonical SHA-256 value."
    }
    return $value
}

proc ::stage1e::vivado_runtime_contract_v1::canonical_path {path} {
    set path [string map {\\ /} $path]
    if {[file pathtype $path] ne {absolute}} {
        _raise PATH_INVALID "Path is not absolute: $path"
    }
    foreach wildcard [list {*} {?} {[} {]}] {
        if {[string first $wildcard $path] >= 0} {
            _raise PATH_INVALID "Path is not literal: $path"
        }
    }
    set components [file split $path]
    foreach component $components {
        if {$component in {. ..}} {
            _raise PATH_INVALID "Path contains a traversal component: $path"
        }
    }
    return [string map {\\ /} [file join {*}$components]]
}

proc ::stage1e::vivado_runtime_contract_v1::path_is_within {
    candidate root
} {
    set candidate [canonical_path $candidate]
    set root [canonical_path $root]
    if {$::tcl_platform(platform) eq {windows}} {
        set candidate [string tolower $candidate]
        set root [string tolower $root]
    }
    return [expr {$candidate eq $root ||
        [string first "[string trimright $root /]/" $candidate] == 0}]
}

proc ::stage1e::vivado_runtime_contract_v1::read_dictionary {path} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise INPUT_MISSING "Contract dictionary is missing: $path"
    }
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    try {
        set value [read $channel]
    } finally {
        close $channel
    }
    require_dictionary $value "Contract dictionary $path"
    return $value
}

proc ::stage1e::vivado_runtime_contract_v1::_require_unique_list {
    values label
} {
    set seen {}
    foreach value $values {
        if {$value eq {}} {
            _raise CONTRACT_INVALID "$label contains an empty value."
        }
        if {[dict exists $seen $value]} {
            _raise CONTRACT_INVALID "$label contains duplicate value: $value"
        }
        dict set seen $value 1
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_record_contract {
    contract
} {
    require_exact_fields $contract {
        schema_version contract_state interface_versions records enums
        controller_state_machine assembly_boundary operation_contract
        phys_opt_contract collector_boundary authority_boundary
        qualification_boundary
    } {Vivado runtime record contract}
    require_equal stage1e-vivado-runtime-record-contract-v1 \
        [dict get $contract schema_version] {Record contract schema}
    require_equal FOUNDATION_IMPLEMENTED_REVIEW_REQUIRED \
        [dict get $contract contract_state] {Record contract state}

    set interfaces [dict get $contract interface_versions]
    require_exact_fields $interfaces {
        common controller adapter observer runner session receipt_schema
    } {Record contract interfaces}
    foreach {field expected} {
        common stage1e-vivado-runtime-common-interface-v1
        controller stage1e-production-vivado-controller-interface-v1
        adapter stage1e-production-vivado-adapter-interface-v1
        observer stage1e-production-vivado-observer-interface-v1
        runner stage1e-production-vivado-runner-interface-v1
        session stage1e-production-vivado-session-interface-v1
        receipt_schema stage1e-vivado-authorization-consumption-receipt-v1
    } {
        require_equal $expected [dict get $interfaces $field] \
            "Record contract interface $field"
    }

    set required_records {
        session_context assembly_inventory_entry assembly_inventory
        controller_request controller_state
        controller_transition controller_decision
        authorization_consumption_result tool_observation
        license_observation object_observation property_observation
        command_observation operation_node_observation run_relationship
        forbidden_operation_observation downstream_boundary_observation
        observer_snapshot native_state runner_phase_request
        operation_ledger_entry operation_ledger runner_phase_result
        collector_handoff vivado_component_result session_result
        failure_record receipt
        runtime_authority_boundary
    }
    set records [dict get $contract records]
    require_exact_list [lsort -dictionary $required_records] \
        [lsort -dictionary [dict keys $records]] {Record type set}
    dict for {name definition} $records {
        require_exact_fields $definition {semantic_owner fields} \
            "Record definition $name"
        set fields [dict get $definition fields]
        if {![llength $fields]} {
            _raise CONTRACT_INVALID "Record $name has no fields."
        }
        _require_unique_list $fields "Record $name fields"
    }

    set enums [dict get $contract enums]
    require_exact_fields $enums {
        snapshot_points controller_states controller_decisions
        phase_statuses logical_operations handoff_modes observation_states
        comparisons availability_states assembly_validation_states
        forbidden_marker_states downstream_evidence_states
        current_run_expected_states process_effect_states
        process_effect_owners authorization_effects
    } {Record contract enums}
    dict for {name values} $enums {
        _require_unique_list $values "Enum $name"
    }

    set states [dict get $enums controller_states]
    set transitions [dict get $contract controller_state_machine]
    require_exact_list [lsort -dictionary $states] \
        [lsort -dictionary [dict keys $transitions]] \
        {Controller state-machine keys}
    dict for {from targets} $transitions {
        _require_unique_list $targets "Controller targets from $from"
        foreach target $targets {
            require_one_of $target $states "Controller target from $from"
            if {$target eq $from} {
                _raise CONTRACT_INVALID \
                    "Controller state machine contains a self-transition: $from"
            }
        }
    }

    set assembly [dict get $contract assembly_boundary]
    require_exact_fields $assembly {
        assembly_validation_state dependency_closure_state closure_scope
        ordered_roles
    } {Assembly boundary}
    foreach {field expected} {
        assembly_validation_state PRT02C_FIXED_ASSEMBLY_VALIDATED
        dependency_closure_state NOT_PROVEN
        closure_scope PRT02C_DIRECT_ASSEMBLY_ONLY
    } {
        require_equal $expected [dict get $assembly $field] \
            "Assembly boundary $field"
    }
    require_exact_list {
        COMMON_CONTRACT ADAPTER CONTROLLER VIVADO_CAPABILITY_OBSERVER RUNNER
        SESSION_ASSEMBLY
    } [dict get $assembly ordered_roles] {Assembly ordered roles}

    set operations [dict get $contract operation_contract]
    require_exact_fields $operations {
        dispatch_mechanism implementation_run synthesis_run project_name
        sources_fileset jobs operation_order runner_operations target_steps
        predecessors retry_policy replay_policy alternate_mechanism_policy
    } {Operation contract}
    foreach {field expected} {
        dispatch_mechanism STAGED_PROJECT_MODE_IMPL_1
        implementation_run impl_1
        synthesis_run synth_1
        project_name current_protection_ip_pynq_z2_stage1e
        sources_fileset sources_1
        jobs 2
        retry_policy PROHIBITED
        replay_policy PROHIBITED
        alternate_mechanism_policy PROHIBITED
    } {
        require_equal $expected [dict get $operations $field] \
            "Operation contract $field"
    }
    require_exact_list {
        opt_design place_design route_design implementation_reports
    } [dict get $operations operation_order] {Logical operation graph}
    require_exact_list {opt_design place_design route_design} \
        [dict get $operations runner_operations] {Runner operations}
    require_exact_list {opt_design place_design route_design} \
        [dict get $operations target_steps] {Runner target steps}

    set phys [dict get $contract phys_opt_contract]
    require_exact_fields $phys {
        configured_state authorized sequence directive predecessor
        invocation_policy required_snapshot_points enabled_action
        invoked_action missing_action unknown_action stale_action
        unreadable_action conflicting_action runtime_repair
    } {Physical optimization contract}
    foreach {field expected} {
        configured_state DISABLED authorized 0 sequence 0 directive NONE
        predecessor place_design invocation_policy PROHIBITED
        enabled_action BLOCK invoked_action BLOCK missing_action BLOCK
        unknown_action BLOCK stale_action BLOCK unreadable_action BLOCK
        conflicting_action BLOCK runtime_repair PROHIBITED
    } {
        require_equal $expected [dict get $phys $field] \
            "Physical optimization $field"
    }
    require_exact_list {
        TOOL_PREFLIGHT PRE_CONSUME POST_PLACE POST_ROUTE TERMINAL
    } [dict get $phys required_snapshot_points] \
        {Physical optimization snapshot points}

    set collector [dict get $contract collector_boundary]
    require_exact_fields $collector {
        implementation_state normal_mode failure_mode terminal_status
        failure_category failure_code failure_phase candidate_effect
    } {Collector boundary}
    foreach {field expected} {
        implementation_state NOT_IMPLEMENTED
        normal_mode ROUTED_REPORTING
        failure_mode FAILURE_EVIDENCE_ONLY
        terminal_status BLOCKED
        failure_category DEPENDENCY_CLOSURE
        failure_code PRODUCTION_COLLECTOR_NOT_IMPLEMENTED
        failure_phase REPORT_COLLECTION
        candidate_effect NOT_CREATED
    } {
        require_equal $expected [dict get $collector $field] \
            "Collector boundary $field"
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_command_contract {
    contract
} {
    require_exact_fields $contract {
        schema_version contract_state vivado_version dispatch_mechanism
        project_mode_run synthesis_run jobs query_roles control_roles
        report_availability_roles forbidden_commands command_ownership
        wait_timeout_contract current_run_contract qualification_boundary
    } {Vivado command contract}
    foreach {field expected} {
        schema_version stage1e-vivado-runtime-command-contract-v1
        contract_state VIVADO_2024_1_QUALIFICATION_REQUIRED
        vivado_version 2024.1
        dispatch_mechanism STAGED_PROJECT_MODE_IMPL_1
        project_mode_run impl_1
        synthesis_run synth_1
        jobs 2
    } {
        require_equal $expected [dict get $contract $field] \
            "Command contract $field"
    }
    set wait_timeout [dict get $contract wait_timeout_contract]
    require_exact_fields $wait_timeout {
        source_unit vivado_unit unit_seconds projection minimum_minutes
        maximum_minutes argument_form incompatible_action
    } {Wait timeout contract}
    foreach {field expected} {
        source_unit SECONDS vivado_unit MINUTES unit_seconds 60
        projection EXACT_DIVISION_REQUIRED minimum_minutes 1
        maximum_minutes 10080
        incompatible_action BLOCK_BEFORE_AUTHORIZATION_CONSUMPTION
    } {
        require_equal $expected [dict get $wait_timeout $field] \
            "Wait timeout contract $field"
    }
    require_exact_list {-timeout EXACT_TIMEOUT_MINUTES impl_1} \
        [dict get $wait_timeout argument_form] {Wait timeout argument form}
    set current_run [dict get $contract current_run_contract]
    require_exact_fields $current_run {
        TOOL_PREFLIGHT PRE_CONSUME POST_OPT POST_PLACE POST_ROUTE TERMINAL
    } {Current-run phase contract}
    dict for {phase definition} $current_run {
        require_exact_fields $definition {
            expected_state allowed_cardinality expected_run unavailable_action
        } "Current-run contract $phase"
        set required [expr {$phase in {TOOL_PREFLIGHT PRE_CONSUME} ?
            {NONE_REQUIRED} : {IMPL_1_REQUIRED}}]
        set cardinality [expr {$required eq {NONE_REQUIRED} ? {0} : {1}}]
        set run [expr {$required eq {NONE_REQUIRED} ? {NONE} : {impl_1}}]
        require_equal $required [dict get $definition expected_state] \
            "Current-run expected state $phase"
        require_exact_list [list $cardinality] \
            [dict get $definition allowed_cardinality] \
            "Current-run cardinality $phase"
        require_equal $run [dict get $definition expected_run] \
            "Current-run expected run $phase"
        require_equal BLOCK [dict get $definition unavailable_action] \
            "Current-run unavailable action $phase"
    }
    set query_roles [dict get $contract query_roles]
    set required_query_roles {
        TOOL_VERSION_SHORT TOOL_SOFTWARE_BUILD TOOL_IP_BUILD
        LICENSE_IMPLEMENTATION CURRENT_PROJECT CURRENT_RUN CURRENT_DESIGN
        IMPL_RUN SYNTH_RUN SOURCES_FILESET TARGET_PART TARGET_BOARD_PART
        PROPERTY_READ COMMAND_EXISTENCE
    }
    require_exact_list [lsort -dictionary $required_query_roles] \
        [lsort -dictionary [dict keys $query_roles]] {Query role set}
    set query_ordinals {}
    dict for {role definition} $query_roles {
        require_exact_fields $definition {
            ordinal command literal_arguments object_role cardinality owner
            effect qualification_state
        } "Query role $role"
        require_equal OBSERVER [dict get $definition owner] \
            "Query owner $role"
        require_equal READ_ONLY [dict get $definition effect] \
            "Query effect $role"
        require_equal VIVADO_2024_1_QUALIFICATION_REQUIRED \
            [dict get $definition qualification_state] \
            "Query qualification $role"
        lappend query_ordinals [dict get $definition ordinal]
    }
    _require_unique_list $query_ordinals {Query ordinals}
    foreach {role ordinal} {
        TOOL_VERSION_SHORT 1 TOOL_SOFTWARE_BUILD 2 TOOL_IP_BUILD 3
        LICENSE_IMPLEMENTATION 4 CURRENT_PROJECT 5 CURRENT_RUN 6
        CURRENT_DESIGN 7 IMPL_RUN 8 SYNTH_RUN 9 SOURCES_FILESET 10
        TARGET_PART 11 TARGET_BOARD_PART 12 PROPERTY_READ 13
        COMMAND_EXISTENCE 14
    } {
        require_equal $ordinal [dict get $query_roles $role ordinal] \
            "Query role ordinal $role"
    }

    set controls [dict get $contract control_roles]
    set required_controls {
        OPT_LAUNCH OPT_WAIT PLACE_LAUNCH PLACE_WAIT ROUTE_LAUNCH ROUTE_WAIT
        ROUTED_OPEN
    }
    require_exact_list [lsort -dictionary $required_controls] \
        [lsort -dictionary [dict keys $controls]] {Control role set}
    set control_ordinals {}
    dict for {role definition} $controls {
        require_exact_fields $definition {
            ordinal command literal_arguments logical_operation target_step
            owner effect qualification_state
        } "Control role $role"
        require_equal RUNNER [dict get $definition owner] \
            "Control owner $role"
        require_equal VIVADO_2024_1_QUALIFICATION_REQUIRED \
            [dict get $definition qualification_state] \
            "Control qualification $role"
        lappend control_ordinals [dict get $definition ordinal]
    }
    _require_unique_list $control_ordinals {Control ordinals}
    foreach {role ordinal} {
        OPT_LAUNCH 15 OPT_WAIT 16 PLACE_LAUNCH 17 PLACE_WAIT 18
        ROUTE_LAUNCH 19 ROUTE_WAIT 20 ROUTED_OPEN 21
    } {
        require_equal $ordinal [dict get $controls $role ordinal] \
            "Control role ordinal $role"
    }
    foreach {role command arguments operation target} {
        OPT_LAUNCH launch_runs {impl_1 -to_step opt_design -jobs 2}
            opt_design opt_design
        OPT_WAIT wait_on_run {-timeout EXACT_TIMEOUT_MINUTES impl_1} \
            opt_design opt_design
        PLACE_LAUNCH launch_runs {impl_1 -to_step place_design -jobs 2}
            place_design place_design
        PLACE_WAIT wait_on_run {-timeout EXACT_TIMEOUT_MINUTES impl_1} \
            place_design place_design
        ROUTE_LAUNCH launch_runs {impl_1 -to_step route_design -jobs 2}
            route_design route_design
        ROUTE_WAIT wait_on_run {-timeout EXACT_TIMEOUT_MINUTES impl_1} \
            route_design route_design
        ROUTED_OPEN open_run {impl_1} implementation_reports route_design
    } {
        set definition [dict get $controls $role]
        require_equal $command [dict get $definition command] \
            "Control command $role"
        require_exact_list $arguments [dict get $definition literal_arguments] \
            "Control arguments $role"
        require_equal $operation [dict get $definition logical_operation] \
            "Control operation $role"
        require_equal $target [dict get $definition target_step] \
            "Control target $role"
    }

    set reports [dict get $contract report_availability_roles]
    set required_reports {
        TIMING_SUMMARY UTILIZATION DRC METHODOLOGY CLOCK_INTERACTION
        CONSTRAINT_COVERAGE MESSAGE_SOURCE TIMING_EXCEPTION_SOURCE CLOCKS CDC
    }
    require_exact_list [lsort -dictionary $required_reports] \
        [lsort -dictionary [dict keys $reports]] {Report availability role set}
    set report_ordinals {}
    foreach {role ordinal command} {
        TIMING_SUMMARY 22 report_timing_summary
        UTILIZATION 23 report_utilization
        DRC 24 report_drc
        METHODOLOGY 25 report_methodology
        CLOCK_INTERACTION 26 report_clock_interaction
        CONSTRAINT_COVERAGE 27 report_timing
        MESSAGE_SOURCE 28 report_route_status
        TIMING_EXCEPTION_SOURCE 29 report_exceptions
        CLOCKS 30 report_clocks
        CDC 31 report_cdc
    } {
        set definition [dict get $reports $role]
        require_exact_fields $definition {ordinal command} \
            "Report availability role $role"
        require_equal $ordinal [dict get $definition ordinal] \
            "Report role ordinal $role"
        require_equal $command [dict get $definition command] \
            "Report role command $role"
        lappend report_ordinals $ordinal
    }
    _require_unique_list $report_ordinals {Report ordinals}
    require_exact_list {
        1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
        24 25 26 27 28 29 30 31
    } [lsort -integer [concat $query_ordinals $control_ordinals \
        $report_ordinals]] {Global command observation ordinals}

    set forbidden [dict get $contract forbidden_commands]
    _require_unique_list $forbidden {Forbidden commands}
    foreach command {
        opt_design place_design phys_opt_design route_design power_opt_design
        create_run reset_run delete_runs eval uplevel source package
        write_bitstream write_hw_platform write_xsa export_hardware
        open_hw_manager connect_hw_server program_hw_devices board_access
    } {
        if {[lsearch -exact $forbidden $command] < 0} {
            _raise CONTRACT_INVALID \
                "Forbidden command is missing from the contract: $command"
        }
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_property_map {map} {
    require_exact_fields $map {
        schema_version contract_state vivado_version snapshot_points
        object_selectors normalization_rules properties graph_bindings
        qualification_boundary
    } {Vivado property map}
    foreach {field expected} {
        schema_version stage1e-vivado-runtime-property-map-v1
        contract_state VIVADO_2024_1_QUALIFICATION_REQUIRED
        vivado_version 2024.1
    } {
        require_equal $expected [dict get $map $field] \
            "Property map $field"
    }
    require_exact_list {
        TOOL_PREFLIGHT PRE_CONSUME POST_OPT POST_PLACE POST_ROUTE TERMINAL
    } [dict get $map snapshot_points] {Property-map snapshot points}
    set selectors [dict get $map object_selectors]
    require_exact_list [lsort -dictionary {
        CURRENT_PROJECT SOURCES_FILESET IMPL_RUN SYNTH_RUN
    }] [lsort -dictionary [dict keys $selectors]] {Object selector set}
    dict for {selector definition} $selectors {
        require_exact_fields $definition {
            query_role expected_cardinality unavailable_action
        } "Object selector $selector"
        require_equal BLOCK [dict get $definition unavailable_action] \
            "Object selector unavailable action $selector"
    }
    set normalizations [dict get $map normalization_rules]
    _require_unique_list $normalizations {Normalization rules}
    set properties [dict get $map properties]
    if {![dict size $properties]} {
        _raise CONTRACT_INVALID {Vivado property map is empty.}
    }
    set ordinals {}
    set property_pairs {}
    dict for {key definition} $properties {
        require_exact_fields $definition {
            ordinal object_selector property_name expected_type
            normalization_rule expected_source expected_value
            expected_by_snapshot required_snapshot_points unavailable_action
            qualification_state
        } "Property definition $key"
        require_one_of [dict get $definition object_selector] \
            [dict keys $selectors] "Property selector $key"
        require_one_of [dict get $definition normalization_rule] \
            $normalizations "Property normalization $key"
        require_equal BLOCK [dict get $definition unavailable_action] \
            "Property unavailable action $key"
        require_equal VIVADO_2024_1_QUALIFICATION_REQUIRED \
            [dict get $definition qualification_state] \
            "Property qualification $key"
        set required [dict get $definition required_snapshot_points]
        _require_unique_list $required "Property snapshot list $key"
        foreach phase $required {
            require_one_of $phase [dict get $map snapshot_points] \
                "Property snapshot $key"
        }
        if {[dict get $definition expected_source] eq {PHASE_TABLE}} {
            require_dictionary [dict get $definition expected_by_snapshot] \
                "Property phase table $key"
            foreach phase $required {
                if {![dict exists [dict get $definition expected_by_snapshot] \
                        $phase]} {
                    _raise CONTRACT_INVALID \
                        "Property phase table $key lacks $phase."
                }
            }
        } elseif {[dict size [dict get $definition expected_by_snapshot]] != 0} {
            _raise CONTRACT_INVALID \
                "Non-phase property $key has an unexpected phase table."
        }
        lappend ordinals [dict get $definition ordinal]
        set pair [list [dict get $definition object_selector] \
            [dict get $definition property_name]]
        if {[dict exists $property_pairs $pair]} {
            _raise CONTRACT_INVALID \
                "Property map contains an alias/duplicate selector pair: $pair"
        }
        dict set property_pairs $pair $key
    }
    _require_unique_list $ordinals {Property ordinals}

    set graph [dict get $map graph_bindings]
    require_exact_list [lsort -dictionary {
        opt_design place_design phys_opt_design route_design
    }] [lsort -dictionary [dict keys $graph]] {Graph binding nodes}
    dict for {operation binding} $graph {
        require_exact_fields $binding {
            enabled directive status pre_hook post_hook
        } "Graph binding $operation"
        dict for {role property_key} $binding {
            if {![dict exists $properties $property_key]} {
                _raise CONTRACT_INVALID \
                    "Graph binding $operation/$role names unknown property $property_key"
            }
        }
    }
    foreach key {
        PHYS_OPT_ENABLED PHYS_OPT_DIRECTIVE PHYS_OPT_STATUS
        PHYS_OPT_PRE_HOOK PHYS_OPT_POST_HOOK
    } {
        if {![dict exists $properties $key]} {
            _raise CONTRACT_INVALID \
                "Physical optimization readback property is missing: $key"
        }
        require_exact_list {
            TOOL_PREFLIGHT PRE_CONSUME POST_PLACE POST_ROUTE TERMINAL
        } [dict get $properties $key required_snapshot_points] \
            "Physical optimization readback points $key"
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::_load_receipt_schema {path} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise INPUT_MISSING "Receipt schema is missing: $path"
    }
    set bytes [::stage1e::canonical_json_v1::read_file_bytes $path]
    set schema [::stage1e::canonical_json_v1::parse_bytes $bytes]
    ::stage1e::envelope_contract_v1::assert_meta_node $schema {$}
    require_equal stage1e-schema-subset-v1 \
        [::stage1e::canonical_json_v1::node_value \
            [::stage1e::canonical_json_v1::object_get $schema {$schema}]] \
        {Receipt schema subset}
    require_equal stage1e-vivado-authorization-consumption-receipt-v1 \
        [::stage1e::canonical_json_v1::node_value \
            [::stage1e::canonical_json_v1::object_get $schema {$id}]] \
        {Receipt schema identity}
    return $schema
}

proc ::stage1e::vivado_runtime_contract_v1::configure {
    records commands properties receipt_path
} {
    variable configured
    variable record_contract
    variable command_contract
    variable property_map
    variable receipt_schema
    variable receipt_registry
    variable receipt_schema_path
    validate_record_contract $records
    validate_command_contract $commands
    validate_property_map $properties
    set loaded_receipt [_load_receipt_schema $receipt_path]
    set normalized_receipt_path [file normalize $receipt_path]
    if {$configured} {
        require_equal $record_contract $records {Repeated record contract}
        require_equal $command_contract $commands {Repeated command contract}
        require_equal $property_map $properties {Repeated property map}
        require_equal $receipt_schema_path $normalized_receipt_path \
            {Repeated receipt schema path}
        return 1
    }
    set record_contract $records
    set command_contract $commands
    set property_map $properties
    set receipt_schema $loaded_receipt
    set receipt_schema_path $normalized_receipt_path
    set receipt_registry [dict create \
        stage1e-vivado-authorization-consumption-receipt-v1 $loaded_receipt]
    set configured 1
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::configure_from_build_root {
    build_root
} {
    set build_root [file normalize $build_root]
    set records [read_dictionary [file join $build_root config \
        stage1e_vivado_runtime_record_contract_v1.dict]]
    set commands [read_dictionary [file join $build_root config \
        stage1e_vivado_runtime_command_contract_v1.dict]]
    set properties [read_dictionary [file join $build_root config \
        stage1e_vivado_runtime_property_map_v1.dict]]
    set receipt_path [file join $build_root lib \
        stage1e_runtime_vivado_authorization_consumption_receipt_v1.schema.json]
    configure $records $commands $properties $receipt_path
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::require_configured {} {
    variable configured
    if {!$configured} {
        _raise NOT_CONFIGURED \
            {Vivado runtime contracts have not been configured.}
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::record_contract {} {
    variable record_contract
    require_configured
    return $record_contract
}

proc ::stage1e::vivado_runtime_contract_v1::command_contract {} {
    variable command_contract
    require_configured
    return $command_contract
}

proc ::stage1e::vivado_runtime_contract_v1::wait_timeout_minutes {
    timeout_seconds
} {
    variable command_contract
    require_configured
    set contract [dict get $command_contract wait_timeout_contract]
    set unit [dict get $contract unit_seconds]
    if {![string is integer -strict $timeout_seconds] ||
            $timeout_seconds < 1 || $timeout_seconds % $unit != 0} {
        _raise TIMEOUT_INVALID \
            "Vivado phase timeout must be a positive whole-minute value: $timeout_seconds"
    }
    set minutes [expr {$timeout_seconds / $unit}]
    if {$minutes < [dict get $contract minimum_minutes] ||
            $minutes > [dict get $contract maximum_minutes]} {
        _raise TIMEOUT_INVALID \
            "Vivado phase timeout minutes are outside the closed contract: $minutes"
    }
    return $minutes
}

proc ::stage1e::vivado_runtime_contract_v1::property_map {} {
    variable property_map
    require_configured
    return $property_map
}

proc ::stage1e::vivado_runtime_contract_v1::record_fields {record_type} {
    variable record_contract
    require_configured
    if {![dict exists $record_contract records $record_type]} {
        _raise RECORD_UNKNOWN "Unknown Vivado runtime record: $record_type"
    }
    return [dict get $record_contract records $record_type fields]
}

proc ::stage1e::vivado_runtime_contract_v1::require_record {
    record_type record {label {}}
} {
    if {$label eq {}} { set label "Vivado runtime $record_type" }
    require_exact_fields $record [record_fields $record_type] $label
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::copy_exact {
    record_type record {label {}}
} {
    require_record $record_type $record $label
    set copy {}
    foreach field [record_fields $record_type] {
        dict set copy $field [dict get $record $field]
    }
    return $copy
}

proc ::stage1e::vivado_runtime_contract_v1::validate_assembly_inventory {
    inventory
} {
    variable record_contract
    require_record assembly_inventory $inventory
    foreach {field expected} {
        schema_version stage1e-prt02c-fixed-assembly-inventory-v1
        assembly_validation_state PRT02C_FIXED_ASSEMBLY_VALIDATED
        dependency_closure_state NOT_PROVEN
        closure_scope PRT02C_DIRECT_ASSEMBLY_ONLY
    } {
        require_equal $expected [dict get $inventory $field] \
            "Assembly inventory $field"
    }
    foreach field {session_module_path module_root build_root} {
        set value [dict get $inventory $field]
        require_equal [canonical_path $value] $value \
            "Assembly inventory canonical $field"
    }
    require_equal [file dirname [dict get $inventory session_module_path]] \
        [dict get $inventory module_root] {Assembly module root}
    require_equal [file dirname [file dirname \
        [dict get $inventory module_root]]] [dict get $inventory build_root] \
        {Assembly build root}
    set entries [dict get $inventory entries]
    set expected_roles [dict get $record_contract assembly_boundary ordered_roles]
    if {[llength $entries] != [llength $expected_roles]} {
        _raise ASSEMBLY_INVALID \
            {Assembly inventory does not contain exactly six entries.}
    }
    set roles {}
    set paths {}
    set ordinal 0
    foreach entry $entries expected_role $expected_roles {
        incr ordinal
        require_record assembly_inventory_entry $entry
        require_equal $ordinal [dict get $entry ordinal] \
            {Assembly inventory entry ordinal}
        require_equal $expected_role [dict get $entry role] \
            {Assembly inventory entry role}
        if {[dict get $entry interface_version] eq {}} {
            _raise ASSEMBLY_INVALID \
                "Assembly interface is empty: [dict get $entry role]"
        }
        set path [dict get $entry path]
        require_equal [canonical_path $path] $path \
            "Assembly canonical path [dict get $entry role]"
        if {![path_is_within $path [dict get $inventory build_root]]} {
            _raise ASSEMBLY_INVALID \
                "Assembly path escapes the build root: $path"
        }
        if {![file exists $path] || ![file isfile $path]} {
            _raise ASSEMBLY_INVALID \
                "Assembly path is not a regular file: $path"
        }
        lappend roles [dict get $entry role]
        lappend paths $path
    }
    _require_unique_list $roles {Assembly inventory roles}
    _require_unique_list $paths {Assembly inventory paths}
    require_equal [dict get $inventory session_module_path] \
        [dict get [lindex $entries end] path] {Assembly Session source path}
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_runtime_authority_boundary {
    boundary
} {
    variable record_contract
    require_record runtime_authority_boundary $boundary
    dict for {field expected} [dict get $record_contract authority_boundary] {
        require_equal $expected [dict get $boundary $field] \
            "Runtime authority boundary $field"
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::runtime_authority_boundary {} {
    variable record_contract
    require_configured
    set boundary [dict get $record_contract authority_boundary]
    set result [dict create \
        qualification_decision [dict get $boundary qualification_decision] \
        authorization_issue [dict get $boundary authorization_issue] \
        authorization_consumption \
            [dict get $boundary authorization_consumption] \
        engineering_acceptance \
            [dict get $boundary engineering_acceptance] \
        bitstream_xsa_generation \
            [dict get $boundary bitstream_xsa_generation] \
        artifact_collection [dict get $boundary artifact_collection] \
        publication [dict get $boundary publication] \
        hardware_manager [dict get $boundary hardware_manager] \
        board_access [dict get $boundary board_access]]
    validate_runtime_authority_boundary $result
    return $result
}

proc ::stage1e::vivado_runtime_contract_v1::validate_session_context {
    context
} {
    require_record session_context $context
    require_equal stage1e-vivado-session-context-v1 \
        [dict get $context schema_version] {Session context schema}
    if {[dict get $context session_id] eq {} ||
            [dict get $context host_process_reference] eq {}} {
        _raise SESSION_INVALID {Session context has an empty binding.}
    }
    canonical_path [dict get $context current_workspace_path]
    foreach {field expected} {
        assembly_scope_state PRT02C_DIRECT_ASSEMBLY_DECLARED
        closure_scope PRT02C_DIRECT_ASSEMBLY_ONLY
        source_binding_state MATCH
        runtime_binding_state MATCH
        policy_binding_state MATCH
        configuration_binding_state MATCH
        qualification_availability VIVADO_2024_1_QUALIFICATION_REQUIRED
        qualification_binding_state MATCH
        environment_binding_state MATCH
        workspace_binding_state MATCH
        synthesis_binding_state MATCH
        dependency_closure_state NOT_PROVEN
        command_contract_state VIVADO_2024_1_QUALIFICATION_REQUIRED
        property_map_state VIVADO_2024_1_QUALIFICATION_REQUIRED
    } {
        require_equal $expected [dict get $context $field] \
            "Session context $field"
    }
    foreach field {
        allowed_operation_contract_identity
        forbidden_operation_contract_identity
    } {
        require_sha256 [dict get $context $field] "Session context $field"
    }
    require_equal PRODUCTION_COLLECTOR_NOT_IMPLEMENTED \
        [dict get $context report_contract_reference] \
        {Session report contract reference}
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::_validate_interface_bindings {
    bindings
} {
    set roles {
        entry_point controller adapter request_envelope result_envelope
        failure_record runtime_schema report message host_requirements
        canonicalization hash_provider atomic_publication
    }
    require_exact_fields $bindings $roles {Request interface contracts}
    foreach role $roles {
        set binding [dict get $bindings $role]
        require_exact_fields $binding {contract_version contract_identity} \
            "Request interface binding $role"
        require_sha256 [dict get $binding contract_identity] \
            "Request interface identity $role"
    }
    foreach {role expected} {
        entry_point stage1e-production-runtime-entry-point-contract-v1
        controller stage1e-production-vivado-controller-interface-v1
        adapter stage1e-production-vivado-adapter-interface-v1
        request_envelope stage1e-production-runtime-request-envelope-v1
        result_envelope stage1e-production-runtime-result-envelope-v1
        failure_record stage1e-runtime-failure-record-v1
        runtime_schema stage1e-vivado-runtime-record-contract-v1
        report stage1e-production-report-contract-not-implemented-v1
        message stage1e-production-message-contract-not-implemented-v1
        host_requirements stage1e-host-boundary-contract-v1
        canonicalization stage1e-runtime-canonical-json-interface-v1
        hash_provider stage1e-runtime-sha256-provider-interface-v1
        atomic_publication stage1e-runtime-atomic-publication-interface-v1
    } {
        require_equal $expected [dict get $bindings $role contract_version] \
            "Request interface version $role"
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::_validate_graph {graph} {
    require_exact_fields $graph {
        opt_design place_design phys_opt_design route_design
        implementation_reports
    } {Configured operation graph}
    set expected [dict create \
        opt_design {ENABLED 1 1 Default synthesis REQUIRED} \
        place_design {ENABLED 1 2 Default opt_design REQUIRED} \
        phys_opt_design {DISABLED 0 0 NONE place_design PROHIBITED} \
        route_design {ENABLED 1 3 Default place_design REQUIRED} \
        implementation_reports \
            {ENABLED 1 4 READ_ONLY route_design REQUIRED}]
    dict for {operation values} $expected {
        set node [dict get $graph $operation]
        require_exact_fields $node {
            configured_state authorized sequence directive predecessor
            invocation_policy
        } "Configured graph node $operation"
        lassign $values state authorized sequence directive predecessor policy
        foreach {field value} [list \
                configured_state $state authorized $authorized \
                sequence $sequence directive $directive \
                predecessor $predecessor invocation_policy $policy] {
            require_equal $value [dict get $node $field] \
                "Configured graph $operation/$field"
        }
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::_validate_request_authority {
    boundary
} {
    require_exact_fields $boundary {
        qualification_decision authorization_issue engineering_acceptance
        bitstream_xsa_generation artifact_collection publication
        hardware_manager board_access
    } {Request authority boundary}
    foreach field {
        qualification_decision authorization_issue bitstream_xsa_generation
        artifact_collection publication hardware_manager board_access
    } {
        require_equal NONE [dict get $boundary $field] \
            "Request authority $field"
    }
    require_equal CONTROLLER_POLICY_REVIEW_ONLY \
        [dict get $boundary engineering_acceptance] \
        {Request engineering acceptance boundary}
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_controller_request {
    request
} {
    variable record_contract
    require_record controller_request $request
    foreach {field expected} {
        schema_version stage1e-production-vivado-controller-request-v1
        source_schema_version stage1e-production-runtime-request-envelope-v1
        request_state SEALED
        record_contract_version stage1e-vivado-runtime-record-contract-v1
        command_contract_version stage1e-vivado-runtime-command-contract-v1
        property_map_version stage1e-vivado-runtime-property-map-v1
    } {
        require_equal $expected [dict get $request $field] \
            "Controller request $field"
    }
    foreach field {
        request_identity source_identity runtime_backend_identity
        policy_identity configuration_identity qualification_identity
        environment_identity workspace_identity synthesis_result_identity
        dependency_closure_identity
    } {
        require_sha256 [dict get $request $field] "Controller request $field"
    }
    canonical_path [dict get $request sealed_request_path]
    if {[dict get $request execution_id] eq {} ||
            [dict get $request attempt_id] eq {}} {
        _raise REQUEST_INVALID {Execution or attempt binding is empty.}
    }
    validate_session_context [dict get $request session_context]
    _validate_interface_bindings [dict get $request interface_contracts]

    set implementation [dict get $request implementation_contract]
    require_exact_fields $implementation {
        target top part board_part run_name strategy opt_design_directive
        place_design_directive phys_opt_design_directive
        route_design_directive jobs seed_policy incremental_policy
        imported_checkpoint_policy operation_order effective_step_graph
        pre_hook_state post_hook_state configured_readback effective_readback
        report_roles conditional_report_rules mismatch_action
    } {Request implementation contract}
    foreach {field expected} {
        target protection_system_wrapper top protection_system_wrapper
        part xc7z020clg400-1
        board_part tul.com.tw:pynq-z2:part0:1.0
        run_name impl_1 strategy Vivado_Implementation_Defaults
        opt_design_directive Default place_design_directive Default
        phys_opt_design_directive NONE route_design_directive Default
        jobs 2 seed_policy TOOL_DEFAULT_RECORDED_BY_READBACK
        incremental_policy DISABLED imported_checkpoint_policy PROHIBITED
        pre_hook_state NONE post_hook_state NONE
        configured_readback REQUIRED effective_readback REQUIRED
        mismatch_action BLOCK
    } {
        require_equal $expected [dict get $implementation $field] \
            "Implementation contract $field"
    }
    require_exact_list {
        opt_design place_design route_design implementation_reports
    } [dict get $implementation operation_order] \
        {Request operation order}
    _validate_graph [dict get $implementation effective_step_graph]
    require_exact_list {
        TIMING_SUMMARY UTILIZATION DRC METHODOLOGY CLOCK_INTERACTION
        CONSTRAINT_COVERAGE MESSAGE_INVENTORY TIMING_EXCEPTION_INVENTORY
        EFFECTIVE_GRAPH_READBACK
    } [dict get $implementation report_roles] {Request report roles}
    require_exact_list {} [dict get $implementation conditional_report_rules] \
        {Request conditional report rules}

    set authorization [dict get $request authorization]
    require_exact_fields $authorization {
        authorization_identity capability issue_state consumption_state
        execution_id source_identity runtime_backend_identity policy_identity
        configuration_identity qualification_identity environment_identity
        workspace_identity synthesis_result_identity
        allowed_operation_contract_identity
        forbidden_operation_contract_identity consumption_record_path
        consumption_owner reuse_policy artifact_authority
        publication_authority hardware_manager_authority board_authority
    } {Request authorization}
    require_sha256 [dict get $authorization authorization_identity] \
        {Authorization identity}
    foreach {field expected} {
        capability IMPLEMENTATION issue_state AUTHORIZED
        consumption_state UNCONSUMED consumption_owner CONTROLLER
        reuse_policy PROHIBITED artifact_authority NONE
        publication_authority NONE hardware_manager_authority NONE
        board_authority NONE
    } {
        require_equal $expected [dict get $authorization $field] \
            "Authorization $field"
    }
    foreach field {
        source_identity runtime_backend_identity policy_identity
        configuration_identity qualification_identity environment_identity
        workspace_identity synthesis_result_identity
    } {
        require_equal [dict get $request $field] \
            [dict get $authorization $field] "Authorization binding $field"
    }
    require_equal [dict get $request execution_id] \
        [dict get $authorization execution_id] \
        {Authorization execution binding}
    set context [dict get $request session_context]
    foreach field {
        allowed_operation_contract_identity
        forbidden_operation_contract_identity
    } {
        require_sha256 [dict get $authorization $field] \
            "Authorization $field"
        require_equal [dict get $context $field] \
            [dict get $authorization $field] \
            "Authorization session binding $field"
    }
    canonical_path [dict get $authorization consumption_record_path]

    set evidence [dict get $request evidence_contract]
    require_exact_fields $evidence {
        request_path host_observation_result_path launch_result_path
        vivado_capability_result_path authorization_consumption_record_path
        operation_ledger_path vivado_log_path vivado_journal_path
        report_ledger_path report_root parser_result_path
        canonical_inventory_path forbidden_boundary_result_path
        component_result_root host_result_path vivado_result_path
        first_failure_path terminal_diagnostic_path final_result_path
        publication_mode overwrite_policy execution_id workspace_identity
        missing_state_policy
    } {Request evidence contract}
    foreach field [dict keys $evidence] {
        if {[string match *_path $field] || $field in {
                report_root component_result_root}} {
            canonical_path [dict get $evidence $field]
        }
    }
    foreach {field expected} {
        publication_mode APPEND_ONLY overwrite_policy PROHIBITED
        missing_state_policy EXPLICIT
    } {
        require_equal $expected [dict get $evidence $field] \
            "Evidence contract $field"
    }
    require_equal [dict get $request execution_id] \
        [dict get $evidence execution_id] {Evidence execution binding}
    require_equal [dict get $request workspace_identity] \
        [dict get $evidence workspace_identity] {Evidence workspace binding}
    require_equal [dict get $authorization consumption_record_path] \
        [dict get $evidence authorization_consumption_record_path] \
        {Authorization receipt path binding}
    require_equal [dict get $request sealed_request_path] \
        [dict get $evidence request_path] {Sealed request path binding}

    set launch [dict get $request launch_contract]
    require_exact_fields $launch {
        vivado_executable_path vivado_executable_identity
        expected_vivado_version expected_vivado_build cwd workspace_root
        xil_root source_root request_root evidence_root log_root journal_root
        temporary_root cache_root command_template argument_vector
        environment_contract_identity process_observation_contract_identity
        encoding locale time_zone no_fallback
    } {Request launch contract}
    foreach field {
        vivado_executable_path cwd workspace_root xil_root source_root
        request_root evidence_root log_root journal_root temporary_root
        cache_root
    } {
        canonical_path [dict get $launch $field]
    }
    foreach field {
        vivado_executable_identity environment_contract_identity
        process_observation_contract_identity
    } {
        require_sha256 [dict get $launch $field] "Launch contract $field"
    }
    foreach {field expected} {
        expected_vivado_version 2024.1 encoding UTF-8 locale INVARIANT
        time_zone UTC no_fallback 1
    } {
        require_equal $expected [dict get $launch $field] \
            "Launch contract $field"
    }
    require_equal [dict get $context current_workspace_path] \
        [dict get $launch cwd] {Session workspace path binding}

    set timeouts [dict get $request timeout_contract]
    require_exact_fields $timeouts {
        startup_seconds child_discovery_seconds entry_validation_seconds
        tool_preflight_seconds opt_design_seconds place_design_seconds
        route_design_seconds report_attempt_seconds serialization_seconds
        heartbeat_silence_seconds graceful_termination_seconds
        total_lifetime_seconds
    } {Request timeout contract}
    dict for {name value} $timeouts {
        if {![string is integer -strict $value] || $value < 1} {
            _raise REQUEST_INVALID "Timeout is not positive: $name=$value"
        }
    }
    foreach field {opt_design_seconds place_design_seconds route_design_seconds} {
        wait_timeout_minutes [dict get $timeouts $field]
    }
    _validate_request_authority [dict get $request authority_boundary]
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_failure {failure} {
    variable record_contract
    require_record failure_record $failure
    set enums [dict get $record_contract enums]
    require_one_of [dict get $failure terminal_status] {FAILED BLOCKED} \
        {Failure terminal status}
    require_one_of [dict get $failure authorization_effect] \
        [dict get $enums authorization_effects] {Failure authorization effect}
    require_equal STATE_UNKNOWN [dict get $failure process_effect] \
        {Vivado failure process effect}
    require_equal HOST_RESULT_NOT_CONNECTED \
        [dict get $failure process_effect_owner] \
        {Vivado failure process-effect owner}
    require_equal NOT_CREATED [dict get $failure candidate_effect] \
        {Failure candidate effect}
    if {![string is integer -strict \
            [dict get $failure first_failure_ordinal]] ||
            [dict get $failure first_failure_ordinal] < 1} {
        _raise FAILURE_INVALID {Failure ordinal is invalid.}
    }
    if {[dict get $failure message] eq {}} {
        _raise FAILURE_INVALID {Failure message is empty.}
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::make_failure {
    terminal_status category code component phase ordinal authorization_effect
    process_effect evidence_state retry_disposition message references
} {
    set failure [dict create \
        terminal_status $terminal_status \
        failure_category $category \
        failure_code $code \
        failure_component $component \
        failure_phase $phase \
        first_failure_ordinal $ordinal \
        authorization_effect $authorization_effect \
        process_effect $process_effect \
        process_effect_owner HOST_RESULT_NOT_CONNECTED \
        evidence_state $evidence_state \
        retry_disposition $retry_disposition \
        candidate_effect NOT_CREATED \
        message $message \
        causal_evidence_references $references]
    validate_failure $failure
    return $failure
}

proc ::stage1e::vivado_runtime_contract_v1::validate_failure_sequence {
    first_failure secondary_failures
} {
    if {$first_failure eq {NONE}} {
        if {[llength $secondary_failures] != 0} {
            _raise FAILURE_INVALID \
                {Secondary failures exist without a first failure.}
        }
        return 1
    }
    validate_failure $first_failure
    set prior [dict get $first_failure first_failure_ordinal]
    foreach failure $secondary_failures {
        validate_failure $failure
        set ordinal [dict get $failure first_failure_ordinal]
        if {$ordinal <= $prior} {
            _raise FAILURE_INVALID \
                {Failure ordinals are not strictly increasing.}
        }
        set prior $ordinal
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::snapshot_reference {
    request phase ordinal
} {
    return "vivado-snapshot/[dict get $request execution_id]/[dict get $request attempt_id]/[dict get $request session_context session_id]/$ordinal/$phase"
}

proc ::stage1e::vivado_runtime_contract_v1::decision_reference {
    request ordinal state operation
} {
    return "vivado-controller/[dict get $request execution_id]/[dict get $request attempt_id]/$ordinal/$state/$operation"
}

proc ::stage1e::vivado_runtime_contract_v1::command_observation_expectations {} {
    variable command_contract
    require_configured
    set expectations {}
    dict for {role definition} [dict get $command_contract query_roles] {
        lappend expectations [dict create \
            ordinal [dict get $definition ordinal] role $role \
            command_name [dict get $definition command] owner OBSERVER \
            permission READ_ONLY]
    }
    dict for {role definition} [dict get $command_contract control_roles] {
        lappend expectations [dict create \
            ordinal [dict get $definition ordinal] role $role \
            command_name [dict get $definition command] owner RUNNER \
            permission PROJECT_MODE_CONTROL]
    }
    dict for {role definition} \
            [dict get $command_contract report_availability_roles] {
        lappend expectations [dict create \
            ordinal [dict get $definition ordinal] role $role \
            command_name [dict get $definition command] \
            owner PRODUCTION_COLLECTOR_NOT_IMPLEMENTED \
            permission EXISTENCE_OBSERVATION_ONLY]
    }
    return [lsort -integer -index 1 $expectations]
}

proc ::stage1e::vivado_runtime_contract_v1::validate_snapshot {snapshot} {
    variable record_contract
    variable command_contract
    require_record observer_snapshot $snapshot
    require_equal stage1e-production-vivado-observer-snapshot-v1 \
        [dict get $snapshot schema_version] {Observer snapshot schema}
    require_one_of [dict get $snapshot phase] \
        [dict get $record_contract enums snapshot_points] \
        {Observer snapshot phase}
    if {![string is integer -strict [dict get $snapshot observation_ordinal]] ||
            [dict get $snapshot observation_ordinal] < 1} {
        _raise SNAPSHOT_INVALID {Observer snapshot ordinal is invalid.}
    }
    require_record tool_observation [dict get $snapshot tool_observation]
    require_record license_observation [dict get $snapshot license_observation]
    foreach observation [dict get $snapshot object_observations] {
        require_record object_observation $observation
    }
    foreach observation [dict get $snapshot property_observations] {
        require_record property_observation $observation
    }
    set command_observations [dict get $snapshot command_observations]
    set expected_commands [command_observation_expectations]
    if {[llength $command_observations] != [llength $expected_commands]} {
        _raise SNAPSHOT_INVALID \
            {Observer command observation count differs from the contract.}
    }
    foreach observation $command_observations expected $expected_commands {
        require_record command_observation $observation
        foreach field {ordinal role command_name owner permission} {
            require_equal [dict get $expected $field] \
                [dict get $observation $field] \
                "Command observation $field"
        }
        require_one_of [dict get $observation availability] \
            {AVAILABLE UNAVAILABLE} {Command observation availability}
        require_equal VIVADO_2024_1_QUALIFICATION_REQUIRED \
            [dict get $observation qualification_state] \
            {Command observation qualification}
    }
    _validate_graph [dict get $snapshot configured_graph]
    require_exact_fields [dict get $snapshot observed_graph] {
        opt_design place_design phys_opt_design route_design
    } {Observed operation graph}
    dict for {operation observation} [dict get $snapshot observed_graph] {
        require_record operation_node_observation $observation
    }
    set relationship [dict get $snapshot run_relationship]
    require_record run_relationship $relationship
    set expected_run [dict get $command_contract current_run_contract \
        [dict get $snapshot phase]]
    require_equal [dict get $expected_run expected_state] \
        [dict get $relationship current_run_expected_state] \
        {Current-run expected state}
    require_one_of [dict get $relationship current_run_query_state] \
        {AVAILABLE UNAVAILABLE AMBIGUOUS} {Current-run query state}
    if {![string is integer -strict \
            [dict get $relationship current_run_cardinality]] ||
            [dict get $relationship current_run_cardinality] < 0} {
        _raise SNAPSHOT_INVALID {Current-run cardinality is invalid.}
    }
    require_one_of [dict get $relationship current_run_comparison] \
        {MATCH MISMATCH UNKNOWN} {Current-run comparison}
    require_one_of [dict get $relationship comparison] \
        {MATCH MISMATCH UNKNOWN} {Run-relationship comparison}
    set query_state [dict get $relationship current_run_query_state]
    set cardinality [dict get $relationship current_run_cardinality]
    set observed [dict get $relationship current_run_observed]
    set expected_value [dict get $expected_run expected_run]
    set expected_cardinalities [dict get $expected_run allowed_cardinality]
    set expected_comparison UNKNOWN
    if {$query_state eq {AVAILABLE}} {
        if {$cardinality > 1} {
            _raise SNAPSHOT_INVALID \
                {An available current-run query has ambiguous cardinality.}
        }
        if {$cardinality == 0} {
            require_equal NONE $observed {Zero-cardinality current run}
        } elseif {$observed in {NONE AMBIGUOUS}} {
            _raise SNAPSHOT_INVALID \
                {A single current run lacks an exact observed run name.}
        }
        set expected_comparison [expr {
            [lsearch -exact $expected_cardinalities $cardinality] >= 0 &&
            $observed eq $expected_value ? {MATCH} : {MISMATCH}}]
    } elseif {$query_state eq {AMBIGUOUS}} {
        if {$cardinality <= 1 || $observed ne {AMBIGUOUS}} {
            _raise SNAPSHOT_INVALID \
                {An ambiguous current-run query lacks multiple observations.}
        }
    } elseif {$observed ne {NONE} || $cardinality != 0} {
        _raise SNAPSHOT_INVALID \
            {An unavailable current-run query contains observed run data.}
    }
    require_equal $expected_comparison \
        [dict get $relationship current_run_comparison] \
        {Current-run comparison semantics}
    set forbidden [dict get $snapshot forbidden_operation_observation]
    require_record forbidden_operation_observation $forbidden
    foreach field {
        result physical_optimization_state direct_implementation_state
        mixed_mechanism_state extra_operation_state downstream_command_state
        downstream_output_state
    } {
        require_one_of [dict get $forbidden $field] {CLEAR DETECTED UNKNOWN} \
            "Forbidden marker state $field"
    }
    set downstream [dict get $snapshot downstream_boundary_observation]
    require_record downstream_boundary_observation $downstream
    foreach field {bitstream_xsa artifact publication hardware_manager \
            board_access} {
        require_one_of [dict get $downstream $field] \
            {ABSENT DETECTED UNKNOWN} "Downstream evidence state $field"
    }
    require_one_of [dict get $downstream result] {CLEAR BLOCKED} \
        {Downstream boundary result}
    require_one_of [dict get $snapshot overall_state] {CLEAR BLOCKED UNKNOWN} \
        {Observer overall state}
    if {[dict get $snapshot overall_state] eq {CLEAR} &&
            [llength [dict get $snapshot blocking_reasons]] != 0} {
        _raise SNAPSHOT_INVALID \
            {A clear observer snapshot contains blocking reasons.}
    }
    if {[dict get $snapshot overall_state] ne {CLEAR} &&
            [llength [dict get $snapshot blocking_reasons]] == 0} {
        _raise SNAPSHOT_INVALID \
            {A non-clear observer snapshot lacks blocking reasons.}
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_ledger {ledger} {
    variable record_contract
    require_record operation_ledger $ledger
    require_equal stage1e-vivado-operation-ledger-v1 \
        [dict get $ledger schema_version] {Operation ledger schema}
    require_equal STAGED_PROJECT_MODE_IMPL_1 \
        [dict get $ledger dispatch_mechanism] {Ledger dispatch mechanism}
    require_equal IMMUTABLE_APPEND_ONLY [dict get $ledger immutable_state] \
        {Ledger immutable state}
    require_equal 0 [dict get $ledger retry_count] {Ledger retry count}
    require_equal NONE [dict get $ledger mixed_mechanism_state] \
        {Ledger mixed mechanism state}
    set entries [dict get $ledger entries]
    if {[llength $entries] != 4} {
        _raise LEDGER_INVALID {Operation ledger must contain four entries.}
    }
    set expected_operations [dict get $record_contract \
        operation_contract operation_order]
    set expected_sequence 0
    set terminal_seen 0
    set observed_terminal ACTIVE
    foreach entry $entries expected_operation $expected_operations {
        incr expected_sequence
        require_record operation_ledger_entry $entry
        require_equal $expected_sequence [dict get $entry sequence] \
            {Operation ledger sequence}
        require_equal $expected_operation [dict get $entry logical_operation] \
            {Operation ledger operation}
        if {[dict get $entry logical_operation] eq {phys_opt_design}} {
            _raise LEDGER_INVALID \
                {Physical optimization cannot be an executable ledger phase.}
        }
        require_equal 0 [dict get $entry retry_count] \
            {Operation ledger entry retry count}
        set phase_status [dict get $entry phase_status]
        require_one_of $phase_status \
            [dict get $record_contract enums phase_statuses] \
            {Operation ledger phase status}
        if {$terminal_seen && $phase_status ne {NOT_RUN}} {
            _raise LEDGER_INVALID \
                {A later operation ran after a terminal ledger phase.}
        }
        if {$phase_status in {FAILED BLOCKED}} {
            set terminal_seen 1
            set observed_terminal $phase_status
        } elseif {$phase_status eq {NOT_RUN}} {
            set terminal_seen 1
        } elseif {$phase_status ne {COMPLETED}} {
            _raise LEDGER_INVALID \
                {A persisted ledger contains a nonterminal active phase.}
        }
    }
    set declared_terminal [dict get $ledger terminal_state]
    if {$observed_terminal in {FAILED BLOCKED}} {
        require_equal $observed_terminal $declared_terminal \
            {Operation ledger terminal state}
    } else {
        require_equal ACTIVE $declared_terminal \
            {Operation ledger active state}
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_phase_request {request} {
    require_record runner_phase_request $request
    require_equal stage1e-production-vivado-runner-phase-request-v1 \
        [dict get $request schema_version] {Runner phase request schema}
    validate_controller_request [dict get $request controller_request]
    validate_snapshot [dict get $request prior_snapshot]
    require_equal [dict get $request prior_snapshot_reference] \
        [dict get $request prior_snapshot snapshot_reference] \
        {Runner prior snapshot reference}
    foreach field {request_identity execution_id attempt_id workspace_identity \
            session_id} {
        require_equal [dict get $request $field] \
            [dict get $request prior_snapshot $field] \
            "Runner prior snapshot binding $field"
    }
    validate_ledger [dict get $request operation_ledger]
    foreach {field expected} {
        run_name impl_1 timeout_state NOT_EXPIRED
        command_contract_version stage1e-vivado-runtime-command-contract-v1
        property_map_version stage1e-vivado-runtime-property-map-v1
    } {
        require_equal $expected [dict get $request $field] \
            "Runner phase request $field"
    }
    require_record controller_decision [dict get $request controller_decision]
    require_equal PROCEED [dict get $request controller_decision decision] \
        {Runner controller decision}
    wait_timeout_minutes [dict get $request timeout_seconds]
    validate_runtime_authority_boundary [dict get $request authority_boundary]
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_phase_result {result} {
    require_record runner_phase_result $result
    require_equal stage1e-production-vivado-runner-phase-result-v1 \
        [dict get $result schema_version] {Runner phase result schema}
    validate_snapshot [dict get $result observer_snapshot]
    validate_ledger [dict get $result operation_ledger]
    require_equal 0 [dict get $result retry_count] {Runner result retry count}
    require_equal NOT_CREATED [dict get $result candidate_effect] \
        {Runner result candidate effect}
    validate_failure_sequence [dict get $result first_failure] \
        [dict get $result secondary_failures]
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_handoff {handoff} {
    require_record collector_handoff $handoff
    require_equal stage1e-vivado-collector-handoff-v1 \
        [dict get $handoff schema_version] {Collector handoff schema}
    require_one_of [dict get $handoff mode] \
        {ROUTED_REPORTING FAILURE_EVIDENCE_ONLY} {Collector handoff mode}
    validate_ledger [dict get $handoff operation_ledger]
    validate_runtime_authority_boundary [dict get $handoff downstream_authority]
    if {[dict get $handoff mode] eq {ROUTED_REPORTING}} {
        foreach {field expected} {
            run_name impl_1 routed_design_state OPENED_SAME_ROUTED_RUN
            route_phase_state COMPLETED failed_phase NONE
            handoff_state READY
        } {
            require_equal $expected [dict get $handoff $field] \
                "Routed collector handoff $field"
        }
    } else {
        foreach {field expected} {
            routed_design_state MISSING
            route_phase_state NOT_COMPLETED
            handoff_state FAILURE_EVIDENCE_ONLY
        } {
            require_equal $expected [dict get $handoff $field] \
                "Failure handoff $field"
        }
        if {[dict get $handoff failed_phase] eq {NONE} ||
                [llength [dict get $handoff failure_references]] == 0} {
            _raise HANDOFF_INVALID \
                {Failure handoff lacks a failed phase or failure reference.}
        }
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_component_result {result} {
    require_record vivado_component_result $result
    require_equal stage1e-vivado-component-result-v1 \
        [dict get $result schema_version] {Vivado component result schema}
    require_one_of [dict get $result terminal_status] {FAILED BLOCKED} \
        {Vivado component terminal status}
    require_equal CONSUMED_ONCE [dict get $result authorization_effect] \
        {Vivado component authorization effect}
    validate_ledger [dict get $result operation_ledger]
    validate_handoff [dict get $result collector_handoff]
    validate_failure_sequence [dict get $result first_failure] \
        [dict get $result secondary_failures]
    require_equal [dict get $result first_failure terminal_status] \
        [dict get $result terminal_status] \
        {Vivado component failure terminal status}
    require_equal STATE_UNKNOWN [dict get $result process_effect] \
        {Vivado component process effect}
    require_equal HOST_RESULT_NOT_CONNECTED \
        [dict get $result process_effect_owner] \
        {Vivado component process-effect owner}
    foreach {field expected} {
        evidence_completeness PARTIAL_PRESERVED
        candidate_effect NOT_CREATED
        collector_state NOT_IMPLEMENTED
        parser_state NOT_IMPLEMENTED
        dependency_closure_state NOT_PROVEN
        qualification_state VIVADO_2024_1_QUALIFICATION_REQUIRED
        public_runtime_path_state DISCONNECTED
        backend_capability_state MOCK_ONLY
        backend_review_state REVIEW_REQUIRED
    } {
        require_equal $expected [dict get $result $field] \
            "Vivado component result $field"
    }
    validate_runtime_authority_boundary [dict get $result authority_boundary]
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::validate_session_result {result} {
    require_record session_result $result
    require_equal stage1e-production-vivado-session-result-v1 \
        [dict get $result schema_version] {Vivado Session result schema}
    require_one_of [dict get $result terminal_status] {FAILED BLOCKED} \
        {Vivado Session terminal status}
    validate_receipt [dict get $result authorization_receipt]
    validate_ledger [dict get $result operation_ledger]
    validate_handoff [dict get $result collector_handoff]
    validate_component_result [dict get $result component_result]
    foreach snapshot [dict get $result snapshots] {
        validate_snapshot $snapshot
    }
    require_equal [dict get $result controller_state] \
        [dict get $result component_result controller_state] \
        {Vivado Session controller state}
    require_equal [dict get $result operation_ledger] \
        [dict get $result collector_handoff operation_ledger] \
        {Vivado Session handoff ledger}
    require_equal [dict get $result operation_ledger] \
        [dict get $result component_result operation_ledger] \
        {Vivado Session component ledger}
    set references {}
    foreach snapshot [dict get $result snapshots] {
        lappend references [dict get $snapshot snapshot_reference]
    }
    require_exact_list $references \
        [dict get $result component_result capability_snapshot_references] \
        {Vivado Session snapshot references}
    require_equal [dict get $result component_result terminal_status] \
        [dict get $result terminal_status] {Vivado Session component status}
    require_equal NOT_CREATED [dict get $result candidate_effect] \
        {Vivado Session candidate effect}
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::_receipt_payload_fields {} {
    set fields [record_fields receipt]
    set index [lsearch -exact $fields receipt_identity]
    return [lreplace $fields $index $index]
}

proc ::stage1e::vivado_runtime_contract_v1::_receipt_node_from_dict {
    record include_identity
} {
    variable receipt_schema
    if {$include_identity} {
        require_record receipt $record
    } else {
        require_exact_fields $record [_receipt_payload_fields] \
            {Authorization receipt payload}
    }
    set pairs {}
    foreach name_node [::stage1e::canonical_json_v1::array_values \
            [::stage1e::canonical_json_v1::object_get \
                $receipt_schema x-stage1e-canonical-order]] {
        set name [::stage1e::canonical_json_v1::node_value $name_node]
        if {!$include_identity && $name eq {receipt_identity}} { continue }
        set value [dict get $record $name]
        if {$name eq {consumption_ordinal}} {
            set node [::stage1e::canonical_json_v1::new_integer $value]
        } else {
            set node [::stage1e::canonical_json_v1::new_string $value]
        }
        lappend pairs $name $node
    }
    return [::stage1e::canonical_json_v1::new_object $pairs]
}

proc ::stage1e::vivado_runtime_contract_v1::_receipt_dict_from_node {node} {
    variable receipt_schema
    set record {}
    foreach name_node [::stage1e::canonical_json_v1::array_values \
            [::stage1e::canonical_json_v1::object_get \
                $receipt_schema x-stage1e-canonical-order]] {
        set name [::stage1e::canonical_json_v1::node_value $name_node]
        dict set record $name [::stage1e::canonical_json_v1::node_value \
            [::stage1e::canonical_json_v1::object_get $node $name]]
    }
    return $record
}

proc ::stage1e::vivado_runtime_contract_v1::validate_receipt {receipt} {
    require_record receipt $receipt
    foreach {field expected} {
        schema_version stage1e-vivado-authorization-consumption-receipt-v1
        receipt_state SEALED capability IMPLEMENTATION issue_state AUTHORIZED
        prior_consumption_state UNCONSUMED consumption_state CONSUMED_ONCE
        consumption_ordinal 1 consumption_owner CONTROLLER
        reuse_policy PROHIBITED publication_mode APPEND_ONLY
        overwrite_policy PROHIBITED authorization_effect CONSUMED_ONCE
        qualification_decision_authority NONE
        authorization_issue_authority NONE
        engineering_acceptance_authority NONE artifact_authority NONE
        publication_authority NONE hardware_manager_authority NONE
        board_authority NONE candidate_effect NOT_CREATED
    } {
        require_equal $expected [dict get $receipt $field] \
            "Authorization receipt $field"
    }
    foreach field {
        receipt_identity request_identity authorization_identity
        source_identity runtime_backend_identity policy_identity
        configuration_identity qualification_identity environment_identity
        workspace_identity synthesis_result_identity
        allowed_operation_contract_identity
        forbidden_operation_contract_identity
    } {
        require_sha256 [dict get $receipt $field] \
            "Authorization receipt $field"
    }
    foreach field {sealed_request_path receipt_path} {
        canonical_path [dict get $receipt $field]
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v1::attach_receipt_identity {
    payload
} {
    variable receipt_schema
    variable receipt_registry
    require_configured
    set payload_node [_receipt_node_from_dict $payload 0]
    set full_node [::stage1e::envelope_contract_v1::add_identity \
        $payload_node $receipt_schema $receipt_registry receipt_identity]
    set receipt [_receipt_dict_from_node $full_node]
    validate_receipt $receipt
    return $receipt
}

proc ::stage1e::vivado_runtime_contract_v1::receipt_bytes {receipt} {
    variable receipt_schema
    variable receipt_registry
    validate_receipt $receipt
    set node [_receipt_node_from_dict $receipt 1]
    ::stage1e::canonical_json_v1::validate $node $receipt_schema \
        $receipt_schema $receipt_registry
    set expected [::stage1e::envelope_contract_v1::record_identity \
        $node $receipt_schema $receipt_registry receipt_identity]
    require_equal $expected [dict get $receipt receipt_identity] \
        {Authorization receipt identity}
    return [::stage1e::canonical_json_v1::canonical_bytes \
        $node $receipt_schema $receipt_registry]
}

proc ::stage1e::vivado_runtime_contract_v1::parse_receipt_bytes {bytes} {
    variable receipt_schema
    variable receipt_registry
    require_configured
    set node [::stage1e::canonical_json_v1::parse_canonical \
        $bytes $receipt_schema $receipt_registry]
    set receipt [_receipt_dict_from_node $node]
    validate_receipt $receipt
    set expected [::stage1e::envelope_contract_v1::record_identity \
        $node $receipt_schema $receipt_registry receipt_identity]
    require_equal $expected [dict get $receipt receipt_identity] \
        {Reopened authorization receipt identity}
    return $receipt
}

proc ::stage1e::vivado_runtime_contract_v1::read_receipt {path} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise RECEIPT_MISSING "Authorization receipt is missing: $path"
    }
    set bytes [::stage1e::atomic_publication_v1::read_binary $path]
    return [parse_receipt_bytes $bytes]
}

proc ::stage1e::vivado_runtime_contract_v1::receipt_reference {receipt} {
    return "[canonical_path [dict get $receipt receipt_path]]#[dict get $receipt receipt_identity]"
}
