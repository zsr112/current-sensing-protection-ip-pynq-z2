# Stage 1E PRT02-C production Vivado capability observer candidate v1.
#
# Every tool interaction in this file is a fixed read-only query. The module
# does not repair run state, schedule a run, open a run, generate a report, or
# create a qualification decision.

set ::stage1e_production_vivado_observer_root \
    [file dirname [file normalize [info script]]]
if {![llength [info commands \
        ::stage1e::vivado_runtime_contract_v1::validate_snapshot]]} {
    source [file join $::stage1e_production_vivado_observer_root .. .. .. lib \
        stage1e_vivado_runtime_contract_v1.tcl]
}
unset ::stage1e_production_vivado_observer_root

namespace eval ::stage1e::production_vivado_observer_v1 {
    variable interface_version stage1e-production-vivado-observer-interface-v1
}

proc ::stage1e::production_vivado_observer_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_vivado_observer_v1::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E PRT02C VIVADO_OBSERVER $code] $message
}

proc ::stage1e::production_vivado_observer_v1::_query_version_short {} {
    set status [catch {version -short} value]
    return [dict create state [expr {$status ? {UNAVAILABLE} : {AVAILABLE}}] \
        value [expr {$status ? {NONE} : $value}]]
}

proc ::stage1e::production_vivado_observer_v1::_query_software_build {} {
    set status [catch {version -build} value]
    return [dict create state [expr {$status ? {UNAVAILABLE} : {AVAILABLE}}] \
        value [expr {$status ? {NONE} : $value}]]
}

proc ::stage1e::production_vivado_observer_v1::_query_ip_build {} {
    set status [catch {version -ipbuild} value]
    return [dict create state [expr {$status ? {UNAVAILABLE} : {AVAILABLE}}] \
        value [expr {$status ? {NONE} : $value}]]
}

proc ::stage1e::production_vivado_observer_v1::_query_license {} {
    set status [catch {get_license_info -feature Implementation} value]
    if {$status} {
        return [dict create state UNAVAILABLE value NONE]
    }
    return [dict create state AVAILABLE value $value]
}

proc ::stage1e::production_vivado_observer_v1::_query_current_project {} {
    set status [catch {current_project -quiet} value]
    return [dict create state [expr {$status ? {UNAVAILABLE} : {AVAILABLE}}] \
        value [expr {$status ? {} : $value}]]
}

proc ::stage1e::production_vivado_observer_v1::_query_current_run {} {
    set status [catch {current_run -quiet} value]
    if {$status} {
        return [dict create state UNAVAILABLE value {}]
    }
    set state [expr {[_cardinality $value] > 1 ?
        {AMBIGUOUS} : {AVAILABLE}}]
    return [dict create state $state value $value]
}

proc ::stage1e::production_vivado_observer_v1::_query_current_design {} {
    set status [catch {current_design -quiet} value]
    if {$status} {
        return [dict create state UNAVAILABLE value {}]
    }
    set state [expr {[_cardinality $value] > 1 ?
        {AMBIGUOUS} : {AVAILABLE}}]
    return [dict create state $state value $value]
}

proc ::stage1e::production_vivado_observer_v1::_query_impl_run {} {
    set status [catch {get_runs -quiet impl_1} value]
    return [dict create state [expr {$status ? {UNAVAILABLE} : {AVAILABLE}}] \
        value [expr {$status ? {} : $value}]]
}

proc ::stage1e::production_vivado_observer_v1::_query_synth_run {} {
    set status [catch {get_runs -quiet synth_1} value]
    return [dict create state [expr {$status ? {UNAVAILABLE} : {AVAILABLE}}] \
        value [expr {$status ? {} : $value}]]
}

proc ::stage1e::production_vivado_observer_v1::_query_sources_fileset {} {
    set status [catch {get_filesets -quiet sources_1} value]
    return [dict create state [expr {$status ? {UNAVAILABLE} : {AVAILABLE}}] \
        value [expr {$status ? {} : $value}]]
}

proc ::stage1e::production_vivado_observer_v1::_query_target_part {} {
    set status [catch {get_parts -quiet xc7z020clg400-1} value]
    return [dict create state [expr {$status ? {UNAVAILABLE} : {AVAILABLE}}] \
        value [expr {$status ? {} : $value}]]
}

proc ::stage1e::production_vivado_observer_v1::_query_target_board_part {} {
    set status [catch {
        get_board_parts -quiet tul.com.tw:pynq-z2:part0:1.0
    } value]
    return [dict create state [expr {$status ? {UNAVAILABLE} : {AVAILABLE}}] \
        value [expr {$status ? {} : $value}]]
}

proc ::stage1e::production_vivado_observer_v1::_query_objects {} {
    return [dict create \
        CURRENT_PROJECT [_query_current_project] \
        IMPL_RUN [_query_impl_run] \
        SYNTH_RUN [_query_synth_run] \
        SOURCES_FILESET [_query_sources_fileset] \
        TARGET_PART [_query_target_part] \
        TARGET_BOARD_PART [_query_target_board_part]]
}

proc ::stage1e::production_vivado_observer_v1::_cardinality {value} {
    return [llength [list {*}$value]]
}

proc ::stage1e::production_vivado_observer_v1::_object_observations {
    object_queries
} {
    set order {
        CURRENT_PROJECT IMPL_RUN SYNTH_RUN SOURCES_FILESET TARGET_PART
        TARGET_BOARD_PART
    }
    set observations {}
    set ordinal 0
    foreach role $order {
        incr ordinal
        set query [dict get $object_queries $role]
        set query_state [dict get $query state]
        set objects [dict get $query value]
        set cardinality [expr {$query_state eq {AVAILABLE} ?
            [_cardinality $objects] : 0}]
        set comparison [expr {$query_state eq {AVAILABLE} &&
            $cardinality == 1 ? {MATCH} :
            ($query_state eq {AVAILABLE} ? {MISMATCH} : {UNKNOWN})}]
        set observation [dict create \
            ordinal $ordinal \
            role $role \
            selector $role \
            query_state $query_state \
            cardinality $cardinality \
            expected_cardinality 1 \
            objects [expr {$query_state eq {AVAILABLE} ? $objects : {}}] \
            comparison $comparison]
        ::stage1e::vivado_runtime_contract_v1::require_record \
            object_observation $observation
        lappend observations $observation
    }
    return $observations
}

proc ::stage1e::production_vivado_observer_v1::_normalize {
    raw rule
} {
    switch -- $rule {
        EXACT_STRING {
            return [dict create state AVAILABLE value $raw]
        }
        BOOLEAN {
            if {[string tolower $raw] in {1 true enabled yes}} {
                return [dict create state AVAILABLE value 1]
            }
            if {[string tolower $raw] in {0 false disabled no}} {
                return [dict create state AVAILABLE value 0]
            }
            return [dict create state UNKNOWN value UNKNOWN]
        }
        INTEGER {
            if {[string is integer -strict $raw]} {
                return [dict create state AVAILABLE value $raw]
            }
            return [dict create state UNKNOWN value UNKNOWN]
        }
        EMPTY_TO_NONE {
            return [dict create state AVAILABLE \
                value [expr {$raw eq {} ? {NONE} : $raw}]]
        }
        STATUS_TOKEN {
            if {$raw eq {}} {
                return [dict create state AVAILABLE value NONE]
            }
            set value [string toupper [string trim $raw]]
            set value [string map {{ } _ {-} _ {!} {}} $value]
            while {[string first {__} $value] >= 0} {
                set value [string map {__ _} $value]
            }
            return [dict create state AVAILABLE value $value]
        }
        PATH_TOKEN {
            set status [catch {
                ::stage1e::vivado_runtime_contract_v1::canonical_path $raw
            } value]
            if {$status} {
                return [dict create state UNKNOWN value UNKNOWN]
            }
            return [dict create state AVAILABLE value $value]
        }
        default {
            _raise NORMALIZATION_INVALID \
                "Unknown property normalization rule: $rule"
        }
    }
}

proc ::stage1e::production_vivado_observer_v1::_path_equivalent {left right} {
    set left [string map {\\ /} [file normalize [string map {\\ /} $left]]]
    set right [string map {\\ /} [file normalize [string map {\\ /} $right]]]
    set left [file join {*}[file split $left]]
    set right [file join {*}[file split $right]]
    return [string equal -nocase $left $right]
}

proc ::stage1e::production_vivado_observer_v1::_expected_value {
    request phase definition
} {
    set source [dict get $definition expected_source]
    switch -- $source {
        CONTRACT_LITERAL {
            set value [dict get $definition expected_value]
        }
        SESSION_WORKSPACE {
            set value [dict get $request session_context \
                current_workspace_path]
        }
        REQUEST_PART {
            set value [dict get $request implementation_contract part]
        }
        REQUEST_BOARD_PART {
            set value [dict get $request implementation_contract board_part]
        }
        REQUEST_TOP {
            set value [dict get $request implementation_contract top]
        }
        REQUEST_STRATEGY {
            set value [dict get $request implementation_contract strategy]
        }
        REQUEST_OPT_DIRECTIVE {
            set value [dict get $request implementation_contract \
                opt_design_directive]
        }
        REQUEST_PLACE_DIRECTIVE {
            set value [dict get $request implementation_contract \
                place_design_directive]
        }
        REQUEST_ROUTE_DIRECTIVE {
            set value [dict get $request implementation_contract \
                route_design_directive]
        }
        PHASE_TABLE {
            set table [dict get $definition expected_by_snapshot]
            if {![dict exists $table $phase]} {
                _raise PROPERTY_CONTRACT_INVALID \
                    "Property phase table lacks phase: $phase"
            }
            set value [dict get $table $phase]
        }
        default {
            _raise PROPERTY_CONTRACT_INVALID \
                "Unknown expected-value source: $source"
        }
    }
    set normalized [_normalize $value [dict get $definition normalization_rule]]
    if {[dict get $normalized state] ne {AVAILABLE}} {
        _raise PROPERTY_CONTRACT_INVALID \
            "Expected property value cannot be normalized: $value"
    }
    return [dict get $normalized value]
}

proc ::stage1e::production_vivado_observer_v1::_property_observations {
    request phase object_queries
} {
    set map [::stage1e::vivado_runtime_contract_v1::property_map]
    set observations {}
    dict for {key definition} [dict get $map properties] {
        set selector [dict get $definition object_selector]
        set query [dict get $object_queries $selector]
        set objects [dict get $query value]
        set required [expr {[lsearch -exact \
            [dict get $definition required_snapshot_points] $phase] >= 0}]
        set raw_state UNAVAILABLE
        set raw_value NONE
        set normalized_state UNKNOWN
        set normalized_value UNKNOWN
        set query_state [dict get $query state]
        if {$query_state eq {AVAILABLE} && [_cardinality $objects] == 1} {
            set object [lindex [list {*}$objects] 0]
            set property_name [dict get $definition property_name]
            set property_status [catch {
                get_property $property_name $object
            } raw]
            if {!$property_status} {
                set raw_state AVAILABLE
                set raw_value [expr {$raw eq {} ? {EMPTY} : $raw}]
                set normalized [_normalize $raw \
                    [dict get $definition normalization_rule]]
                set normalized_state [dict get $normalized state]
                set normalized_value [dict get $normalized value]
            }
        } elseif {$query_state eq {AVAILABLE}} {
            set raw_state AMBIGUOUS
        }
        set expected [_expected_value $request $phase $definition]
        if {!$required} {
            set comparison NOT_APPLICABLE
        } elseif {$raw_state ne {AVAILABLE} ||
                $normalized_state ne {AVAILABLE}} {
            set comparison UNKNOWN
        } elseif {$normalized_value eq $expected} {
            set comparison MATCH
        } else {
            set comparison MISMATCH
        }
        set observation [dict create \
            ordinal [dict get $definition ordinal] \
            key $key \
            object_selector $selector \
            property_name [dict get $definition property_name] \
            expected_type [dict get $definition expected_type] \
            normalization_rule [dict get $definition normalization_rule] \
            raw_state $raw_state \
            raw_value $raw_value \
            normalized_state $normalized_state \
            normalized_value $normalized_value \
            expected_value $expected \
            comparison $comparison \
            unavailable_action [dict get $definition unavailable_action] \
            qualification_state [dict get $definition qualification_state]]
        ::stage1e::vivado_runtime_contract_v1::require_record \
            property_observation $observation
        lappend observations $observation
    }
    return [lsort -integer -index 1 $observations]
}

proc ::stage1e::production_vivado_observer_v1::_property_index {
    observations
} {
    set result {}
    foreach observation $observations {
        dict set result [dict get $observation key] $observation
    }
    return $result
}

proc ::stage1e::production_vivado_observer_v1::_command_available {name} {
    return [expr {[llength [info commands $name]] == 1 ?
        {AVAILABLE} : {UNAVAILABLE}}]
}

proc ::stage1e::production_vivado_observer_v1::_command_observations {} {
    set observations {}
    foreach expected \
            [::stage1e::vivado_runtime_contract_v1::command_observation_expectations] {
        set observation [dict create \
            ordinal [dict get $expected ordinal] \
            role [dict get $expected role] \
            command_name [dict get $expected command_name] \
            owner [dict get $expected owner] \
            permission [dict get $expected permission] \
            availability [_command_available [dict get $expected command_name]] \
            qualification_state \
                VIVADO_2024_1_QUALIFICATION_REQUIRED]
        ::stage1e::vivado_runtime_contract_v1::require_record \
            command_observation $observation
        lappend observations $observation
    }
    return [lsort -integer -index 1 $observations]
}

proc ::stage1e::production_vivado_observer_v1::_configured_node {
    request operation
} {
    return [dict get $request implementation_contract effective_step_graph \
        $operation]
}

proc ::stage1e::production_vivado_observer_v1::_observed_graph {
    request properties
} {
    set map [::stage1e::vivado_runtime_contract_v1::property_map]
    set result {}
    foreach operation {opt_design place_design phys_opt_design route_design} {
        set binding [dict get $map graph_bindings $operation]
        set enabled [dict get $properties [dict get $binding enabled]]
        set directive [dict get $properties [dict get $binding directive]]
        set status [dict get $properties [dict get $binding status]]
        set pre [dict get $properties [dict get $binding pre_hook]]
        set post [dict get $properties [dict get $binding post_hook]]
        set configured [_configured_node $request $operation]
        set enabled_value [dict get $enabled normalized_value]
        set observed_state [expr {$enabled_value eq {1} ? {ENABLED} :
            ($enabled_value eq {0} ? {DISABLED} : {UNKNOWN})}]
        set status_value [dict get $status normalized_value]
        set invocation [expr {$status_value in {COMPLETE RUNNING STARTED} ?
            {INVOKED} : ($status_value eq {NOT_RUN} ?
            {NOT_INVOKED} : {UNKNOWN})}]
        set comparisons [list \
            [dict get $enabled comparison] [dict get $directive comparison] \
            [dict get $status comparison] [dict get $pre comparison] \
            [dict get $post comparison]]
        set comparison [expr {[lsearch -exact $comparisons MISMATCH] >= 0 ?
            {MISMATCH} : ([lsearch -exact $comparisons UNKNOWN] >= 0 ?
            {UNKNOWN} : {MATCH})}]
        set node [dict create \
            configured_state [dict get $configured configured_state] \
            authorized [dict get $configured authorized] \
            sequence [dict get $configured sequence] \
            directive [dict get $configured directive] \
            predecessor [dict get $configured predecessor] \
            invocation_policy [dict get $configured invocation_policy] \
            observed_state $observed_state \
            observed_status $status_value \
            invocation_marker $invocation \
            pre_hook [dict get $pre normalized_value] \
            post_hook [dict get $post normalized_value] \
            comparison $comparison]
        ::stage1e::vivado_runtime_contract_v1::require_record \
            operation_node_observation $node
        dict set result $operation $node
    }
    return $result
}

proc ::stage1e::production_vivado_observer_v1::_tool_observation {
    request current_project current_run current_design
} {
    set version [_query_version_short]
    set build [_query_software_build]
    set ip_build [_query_ip_build]
    set cwd_status [catch {
        ::stage1e::vivado_runtime_contract_v1::canonical_path [pwd]
    } cwd]
    set observation [dict create \
        version_state [dict get $version state] \
        version [dict get $version value] \
        build_state [dict get $build state] \
        software_build [dict get $build value] \
        ip_build_state [dict get $ip_build state] \
        ip_build [dict get $ip_build value] \
        cwd_state [expr {$cwd_status ? {UNAVAILABLE} : {AVAILABLE}}] \
        cwd [expr {$cwd_status ? {NONE} : $cwd}] \
        current_project_state [dict get $current_project state] \
        current_project [expr {[_cardinality [dict get $current_project value]]
            == 1 ? [lindex [dict get $current_project value] 0] : {NONE}}] \
        current_run_state [dict get $current_run state] \
        current_run [expr {[_cardinality [dict get $current_run value]] == 1 ?
            [lindex [dict get $current_run value] 0] : {NONE}}] \
        current_design_state [dict get $current_design state] \
        current_design [expr {[_cardinality [dict get $current_design value]]
            == 1 ? [lindex [dict get $current_design value] 0] : {NONE}}]]
    ::stage1e::vivado_runtime_contract_v1::require_record \
        tool_observation $observation
    return $observation
}

proc ::stage1e::production_vivado_observer_v1::_license_observation {} {
    set query [_query_license]
    set command_state [_command_available get_license_info]
    set query_state [dict get $query state]
    set feature NONE
    set status UNKNOWN
    set available UNKNOWN
    if {$query_state eq {AVAILABLE} &&
            ![catch {dict size [dict get $query value]}]} {
        set value [dict get $query value]
        if {[dict exists $value feature] && [dict exists $value status] &&
                [dict exists $value implementation_feature_available]} {
            set feature [dict get $value feature]
            set status [dict get $value status]
            set available [dict get $value implementation_feature_available]
        } else {
            set query_state UNAVAILABLE
        }
    }
    set observation [dict create \
        command_available $command_state \
        query_state $query_state \
        feature $feature \
        status $status \
        implementation_feature_available $available \
        qualification_state VIVADO_2024_1_QUALIFICATION_REQUIRED]
    ::stage1e::vivado_runtime_contract_v1::require_record \
        license_observation $observation
    return $observation
}

proc ::stage1e::production_vivado_observer_v1::_run_relationship {
    phase object_queries properties current_run current_design
} {
    set command_contract \
        [::stage1e::vivado_runtime_contract_v1::command_contract]
    set impl [dict get $object_queries IMPL_RUN]
    set synth [dict get $object_queries SYNTH_RUN]
    set impl_count [expr {[dict get $impl state] eq {AVAILABLE} ?
        [_cardinality [dict get $impl value]] : 0}]
    set synth_count [expr {[dict get $synth state] eq {AVAILABLE} ?
        [_cardinality [dict get $synth value]] : 0}]
    set parent [dict get $properties IMPL_PARENT normalized_value]
    set refresh [dict get $properties IMPL_NEEDS_REFRESH normalized_value]
    set freshness [expr {$refresh eq {0} ? {FRESH} :
        ($refresh eq {1} ? {STALE} : {UNKNOWN})}]
    set run_value [dict get $current_run value]
    set run_count [_cardinality $run_value]
    set run_query_state [dict get $current_run state]
    set run_observed [expr {$run_count == 0 ? {NONE} :
        ($run_count == 1 ? [lindex $run_value 0] : {AMBIGUOUS})}]
    set expected [dict get $command_contract current_run_contract $phase]
    set expected_state [dict get $expected expected_state]
    set expected_run [dict get $expected expected_run]
    if {$run_query_state in {UNAVAILABLE AMBIGUOUS}} {
        set run_comparison UNKNOWN
    } elseif {[lsearch -exact [dict get $expected allowed_cardinality] \
            $run_count] < 0} {
        set run_comparison MISMATCH
    } elseif {$run_observed eq $expected_run} {
        set run_comparison MATCH
    } else {
        set run_comparison MISMATCH
    }
    set design_value [dict get $current_design value]
    set design_count [_cardinality $design_value]
    set design_state [expr {$design_count == 1 ?
        [lindex $design_value 0] : ($design_count > 1 ? {AMBIGUOUS} : {NONE})}]
    set open_state [expr {[dict get $current_design state] eq {AVAILABLE} &&
        $design_count == 1 && $design_state eq {impl_1} ?
        {OPENED_SAME_ROUTED_RUN} :
        ([dict get $current_design state] in {UNAVAILABLE AMBIGUOUS} ?
            {UNKNOWN} : {NOT_OPEN})}]
    set relationship_comparison MATCH
    if {[dict get $impl state] ne {AVAILABLE} ||
            [dict get $synth state] ne {AVAILABLE} ||
            $parent eq {UNKNOWN} || $freshness eq {UNKNOWN} ||
            $run_comparison eq {UNKNOWN}} {
        set relationship_comparison UNKNOWN
    } elseif {$impl_count != 1 || $synth_count != 1 ||
            $parent ne {synth_1} || $freshness ne {FRESH} ||
            $run_comparison ne {MATCH}} {
        set relationship_comparison MISMATCH
    }
    if {$phase eq {TERMINAL} && $open_state ne {OPENED_SAME_ROUTED_RUN}} {
        set relationship_comparison [expr {$open_state eq {UNKNOWN} ?
            {UNKNOWN} : {MISMATCH}}]
    }
    set relationship [dict create \
        implementation_run impl_1 \
        implementation_cardinality $impl_count \
        synthesis_run synth_1 \
        synthesis_cardinality $synth_count \
        predecessor_observed $parent \
        refresh_state $refresh \
        freshness_state $freshness \
        current_run_query_state $run_query_state \
        current_run_cardinality $run_count \
        current_run_observed $run_observed \
        current_run_expected_state $expected_state \
        current_run_comparison $run_comparison \
        current_design_state $design_state \
        route_open_state $open_state \
        comparison $relationship_comparison]
    ::stage1e::vivado_runtime_contract_v1::require_record \
        run_relationship $relationship
    return $relationship
}

proc ::stage1e::production_vivado_observer_v1::_marker_state {
    observation
} {
    if {[dict get $observation raw_state] ne {AVAILABLE} ||
            [dict get $observation normalized_state] ne {AVAILABLE}} {
        return UNKNOWN
    }
    return [expr {[dict get $observation normalized_value] eq {NONE} ?
        {CLEAR} : {DETECTED}}]
}

proc ::stage1e::production_vivado_observer_v1::_physical_state {
    properties
} {
    set values {}
    foreach key {
        PHYS_OPT_ENABLED PHYS_OPT_DIRECTIVE PHYS_OPT_STATUS
        PHYS_OPT_PRE_HOOK PHYS_OPT_POST_HOOK
    } {
        set observation [dict get $properties $key]
        if {[dict get $observation raw_state] ne {AVAILABLE} ||
                [dict get $observation normalized_state] ne {AVAILABLE}} {
            return UNKNOWN
        }
        lappend values [dict get $observation normalized_value]
    }
    if {$values eq {0 NONE NOT_RUN NONE NONE}} {
        return CLEAR
    }
    return DETECTED
}

proc ::stage1e::production_vivado_observer_v1::_forbidden_observation {
    properties observed_graph
} {
    set physical_state [_physical_state $properties]
    set direct [dict get $properties DIRECT_DISPATCH_MARKER]
    set extra [dict get $properties EXTRA_OPERATION_MARKER]
    set downstream_command [dict get $properties DOWNSTREAM_COMMAND_MARKER]
    set downstream_output [dict get $properties DOWNSTREAM_OUTPUT_MARKER]
    set direct_state [_marker_state $direct]
    set extra_state [_marker_state $extra]
    set downstream_command_state [_marker_state $downstream_command]
    set downstream_output_state [_marker_state $downstream_output]
    set coverage COMPLETE
    foreach observation [list $direct $extra $downstream_command \
            $downstream_output] {
        if {[dict get $observation raw_state] ne {AVAILABLE} ||
                [dict get $observation normalized_state] ne {AVAILABLE}} {
            set coverage INCOMPLETE
        }
    }
    set states [list $physical_state $direct_state $extra_state \
        $downstream_command_state $downstream_output_state]
    set result [expr {[lsearch -exact $states DETECTED] >= 0 ?
        {DETECTED} : ($coverage eq {COMPLETE} &&
        [lsearch -exact $states UNKNOWN] < 0 ? {CLEAR} : {UNKNOWN})}]
    set observation [dict create \
        schema_version stage1e-vivado-forbidden-operation-observation-v1 \
        result $result \
        physical_optimization_state $physical_state \
        direct_implementation_state $direct_state \
        mixed_mechanism_state $direct_state \
        extra_operation_state $extra_state \
        downstream_command_state $downstream_command_state \
        downstream_output_state $downstream_output_state \
        coverage_state $coverage \
        failure_references {}]
    ::stage1e::vivado_runtime_contract_v1::require_record \
        forbidden_operation_observation $observation
    return $observation
}

proc ::stage1e::production_vivado_observer_v1::_downstream_observation {
    forbidden
} {
    set command_state [dict get $forbidden downstream_command_state]
    set output_state [dict get $forbidden downstream_output_state]
    set result [expr {$command_state eq {CLEAR} && $output_state eq {CLEAR} ?
        {CLEAR} : {BLOCKED}}]
    set value [expr {$command_state eq {DETECTED} ||
        $output_state eq {DETECTED} ? {DETECTED} :
        ($command_state eq {UNKNOWN} || $output_state eq {UNKNOWN} ?
            {UNKNOWN} : {ABSENT})}]
    set observation [dict create \
        bitstream_xsa $value artifact $value publication $value \
        hardware_manager $value board_access $value result $result]
    ::stage1e::vivado_runtime_contract_v1::require_record \
        downstream_boundary_observation $observation
    return $observation
}

proc ::stage1e::production_vivado_observer_v1::observe {
    request phase observation_ordinal
} {
    ::stage1e::vivado_runtime_contract_v1::validate_controller_request $request
    set record_contract \
        [::stage1e::vivado_runtime_contract_v1::record_contract]
    ::stage1e::vivado_runtime_contract_v1::require_one_of $phase \
        [dict get $record_contract enums snapshot_points] \
        {Observer requested snapshot phase}
    if {![string is integer -strict $observation_ordinal] ||
            $observation_ordinal < 1} {
        _raise SNAPSHOT_INVALID {Observation ordinal must be positive.}
    }

    set object_queries [_query_objects]
    set current_run [_query_current_run]
    set current_design [_query_current_design]
    set property_observations \
        [_property_observations $request $phase $object_queries]
    set property_index [_property_index $property_observations]
    set object_observations [_object_observations $object_queries]
    set command_observations [_command_observations]
    set observed_graph [_observed_graph $request $property_index]
    set tool [_tool_observation $request \
        [dict get $object_queries CURRENT_PROJECT] $current_run $current_design]
    set license [_license_observation]
    set relationship [_run_relationship $phase $object_queries $property_index \
        $current_run $current_design]
    set forbidden [_forbidden_observation $property_index $observed_graph]
    set downstream [_downstream_observation $forbidden]

    set reasons {}
    foreach observation $object_observations {
        if {[dict get $observation comparison] ne {MATCH}} {
            lappend reasons \
                "OBJECT:[dict get $observation role]:[dict get $observation comparison]"
        }
    }
    foreach observation $property_observations {
        if {[dict get $observation comparison] in {MISMATCH UNKNOWN}} {
            lappend reasons \
                "PROPERTY:[dict get $observation key]:[dict get $observation comparison]"
        }
    }
    foreach {state_field value_field expected} {
        version_state version 2024.1
        build_state software_build REQUEST_BUILD
        ip_build_state ip_build NONEMPTY
        cwd_state cwd REQUEST_CWD
    } {
        if {[dict get $tool $state_field] ne {AVAILABLE}} {
            lappend reasons "TOOL:$value_field:UNAVAILABLE"
            continue
        }
        set observed [dict get $tool $value_field]
        if {$expected eq {REQUEST_BUILD}} {
            set expected [dict get $request launch_contract \
                expected_vivado_build]
        } elseif {$expected eq {REQUEST_CWD}} {
            set expected [dict get $request launch_contract cwd]
        }
        if {$expected eq {NONEMPTY}} {
            if {$observed eq {NONE} || $observed eq {}} {
                lappend reasons "TOOL:$value_field:EMPTY"
            }
        } elseif {$value_field eq {cwd} &&
                ![_path_equivalent $observed $expected]} {
            lappend reasons "TOOL:$value_field:MISMATCH"
        } elseif {$value_field ne {cwd} && $observed ne $expected} {
            lappend reasons "TOOL:$value_field:MISMATCH"
        }
    }
    if {[dict get $license command_available] ne {AVAILABLE} ||
            [dict get $license query_state] ne {AVAILABLE} ||
            [dict get $license feature] ne {Implementation} ||
            [dict get $license status] ne {PASS} ||
            [dict get $license implementation_feature_available] ne {1}} {
        lappend reasons LICENSE:IMPLEMENTATION:BLOCKED
    }
    foreach observation $command_observations {
        if {[dict get $observation owner] ne \
                {PRODUCTION_COLLECTOR_NOT_IMPLEMENTED} &&
                [dict get $observation availability] ne {AVAILABLE}} {
            lappend reasons \
                "COMMAND:[dict get $observation role]:UNAVAILABLE"
        }
    }
    if {[dict get $relationship comparison] ne {MATCH}} {
        lappend reasons RUN_RELATIONSHIP:MISMATCH
    }
    if {[dict get $forbidden result] ne {CLEAR}} {
        lappend reasons \
            "FORBIDDEN_OPERATION:[dict get $forbidden result]"
    }
    if {[dict get $downstream result] ne {CLEAR}} {
        lappend reasons DOWNSTREAM_BOUNDARY:BLOCKED
    }
    set overall [expr {[llength $reasons] == 0 ? {CLEAR} : {BLOCKED}}]
    set snapshot [dict create \
        schema_version stage1e-production-vivado-observer-snapshot-v1 \
        snapshot_reference \
            [::stage1e::vivado_runtime_contract_v1::snapshot_reference \
                $request $phase $observation_ordinal] \
        request_identity [dict get $request request_identity] \
        execution_id [dict get $request execution_id] \
        attempt_id [dict get $request attempt_id] \
        workspace_identity [dict get $request workspace_identity] \
        session_id [dict get $request session_context session_id] \
        phase $phase \
        observation_ordinal $observation_ordinal \
        command_contract_version \
            [dict get $request command_contract_version] \
        property_map_version [dict get $request property_map_version] \
        tool_observation $tool \
        license_observation $license \
        object_observations $object_observations \
        property_observations $property_observations \
        command_observations $command_observations \
        configured_graph \
            [dict get $request implementation_contract effective_step_graph] \
        observed_graph $observed_graph \
        run_relationship $relationship \
        forbidden_operation_observation $forbidden \
        downstream_boundary_observation $downstream \
        overall_state $overall \
        blocking_reasons $reasons]
    ::stage1e::vivado_runtime_contract_v1::validate_snapshot $snapshot
    return $snapshot
}
