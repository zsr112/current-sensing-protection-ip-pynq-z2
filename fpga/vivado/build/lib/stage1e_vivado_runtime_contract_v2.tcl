# Stage 1E Run2 Project Mode runtime contract v2.
#
# The contract accepts only observations proved from the captured Vivado
# 2024.1 run-property projection, exact run identity, and an actual generated
# checkpoint. The runner records chronology separately in its append-only
# phase journal; no supplied string is treated as a native Vivado event.

set ::stage1e_vivado_runtime_contract_v2_dir [file dirname [info script]]
set ::stage1e_vivado_runtime_contract_v2_build [file dirname $::stage1e_vivado_runtime_contract_v2_dir]

namespace eval ::stage1e::vivado_runtime_contract_v2 {
    variable interface_version stage1e-vivado-runtime-common-interface-v2
    variable map_path [file join $::stage1e_vivado_runtime_contract_v2_build config stage1e_vivado_runtime_property_map_v2.dict]
    variable map {}
}
unset ::stage1e_vivado_runtime_contract_v2_dir
unset ::stage1e_vivado_runtime_contract_v2_build

proc ::stage1e::vivado_runtime_contract_v2::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::vivado_runtime_contract_v2::_raise {code message} {
    return -code error -errorcode [list STAGE1E RUN2 RUNTIME_V2 $code] $message
}

proc ::stage1e::vivado_runtime_contract_v2::_read_dictionary {path} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise PROPERTY_MAP_MISSING "Property map is unavailable: $path"
    }
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation lf
    set text [read $channel]
    close $channel
    if {[catch {dict size $text}]} {
        _raise PROPERTY_MAP_INVALID "Property map is not a Tcl dictionary: $path"
    }
    return $text
}

proc ::stage1e::vivado_runtime_contract_v2::configure_from_build_root {build_root} {
    variable map_path
    variable map
    set candidate [file join $build_root config stage1e_vivado_runtime_property_map_v2.dict]
    set map [_read_dictionary $candidate]
    set map_path $candidate
    require_equal stage1e-vivado-runtime-property-map-v2 [dict get $map schema_version] {Property-map schema}
    return $map
}

proc ::stage1e::vivado_runtime_contract_v2::property_map {} {
    variable map
    variable map_path
    if {$map eq {}} { set map [_read_dictionary $map_path] }
    return $map
}

proc ::stage1e::vivado_runtime_contract_v2::require_dictionary {value label} {
    if {[catch {dict size $value}]} { _raise DICTIONARY_INVALID "$label must be a dictionary." }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v2::_same_list {left right} {
    return [expr {[llength $left] == [llength $right] && $left eq $right}]
}

proc ::stage1e::vivado_runtime_contract_v2::require_exact_fields {value expected label} {
    require_dictionary $value $label
    set actual [lsort -dictionary [dict keys $value]]
    set wanted [lsort -dictionary $expected]
    if {![_same_list $actual $wanted]} {
        _raise FIELD_SET_MISMATCH "$label fields differ from the closed contract."
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v2::require_equal {expected actual label} {
    if {$expected ne $actual} { _raise VALUE_MISMATCH "$label differs from the required value." }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v2::_require_unique {values label} {
    if {[llength [lsort -unique $values]] != [llength $values]} {
        _raise DUPLICATE_VALUE "$label contains a duplicate value."
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v2::real_property_projection {} {
    return [dict get [property_map] real_property_projection]
}

proc ::stage1e::vivado_runtime_contract_v2::synthetic_properties_prohibited {} {
    return [dict get [property_map] synthetic_properties_prohibited]
}

proc ::stage1e::vivado_runtime_contract_v2::validate_property_inventory {properties {exact 0}} {
    _require_unique $properties {Vivado property inventory}
    foreach prohibited [synthetic_properties_prohibited] {
        if {[lsearch -exact $properties $prohibited] >= 0} {
            _raise SYNTHETIC_PROPERTY_OBSERVED "Synthetic property is not valid production truth: $prohibited"
        }
    }
    set required [real_property_projection]
    foreach property $required {
        if {[lsearch -exact $properties $property] < 0} {
            _raise PROPERTY_MISSING "Captured Vivado property is missing: $property"
        }
    }
    if {$exact && ![_same_list [lsort -dictionary $properties] [lsort -dictionary $required]]} {
        _raise PROPERTY_PROJECTION_MISMATCH {Fixture property set differs from captured real-property projection.}
    }
    return 1
}

proc ::stage1e::vivado_runtime_contract_v2::_normalize_from_map {section raw label} {
    set pairs [dict get [property_map] normalization $section]
    foreach {captured normalized} $pairs {
        if {$raw eq $captured} { return $normalized }
    }
    _raise NORMALIZATION_UNKNOWN "$label is not a captured Vivado 2024.1 observation."
}

proc ::stage1e::vivado_runtime_contract_v2::normalize_status {raw} {
    return [_normalize_from_map status $raw STATUS]
}

proc ::stage1e::vivado_runtime_contract_v2::normalize_progress {raw} {
    return [_normalize_from_map progress $raw PROGRESS]
}

proc ::stage1e::vivado_runtime_contract_v2::normalize_current_step {raw} {
    return [_normalize_from_map current_step $raw CURRENT_STEP]
}

proc ::stage1e::vivado_runtime_contract_v2::phase_contract {phase} {
    set contracts [dict get [property_map] phase_completion_contract]
    if {![dict exists $contracts $phase]} { _raise PHASE_UNKNOWN "Unsupported Project Mode phase: $phase" }
    return [dict get $contracts $phase]
}

proc ::stage1e::vivado_runtime_contract_v2::validate_snapshot {snapshot} {
    require_exact_fields $snapshot [dict get [property_map] required_snapshot_fields] {Project Mode snapshot}
    set phase [dict get $snapshot phase]
    set contract [phase_contract $phase]
    require_equal impl_1 [dict get $snapshot run_identity] {Implementation run identity}
    require_equal [dict get $contract required_checkpoint] [dict get $snapshot checkpoint] {Checkpoint leaf name}
    require_equal PRESENT [dict get $snapshot checkpoint_state] {Checkpoint state}
    if {![regexp {^[0-9a-f]{64}$} [dict get $snapshot checkpoint_identity]]} {
        _raise CHECKPOINT_IDENTITY {Checkpoint identity is not an actual SHA-256 value.}
    }
    if {[llength [dict get $snapshot forbidden_operations]] != 0} {
        _raise FORBIDDEN_OPERATION_OBSERVED {Observed forbidden operation blocks phase completion.}
    }
    require_equal [dict get $contract expected_run_status] [normalize_status [dict get $snapshot run_status]] {Run-level transition}
    require_equal [dict get $contract expected_progress] [normalize_progress [dict get $snapshot progress]] {Percent progress}
    require_equal [dict get $contract expected_current_step] [normalize_current_step [dict get $snapshot current_step]] {CURRENT_STEP next target}
    return 1
}

proc ::stage1e::vivado_runtime_contract_v2::evaluate_phase_completion {snapshot} {
    if {[dict exists $snapshot phase] &&
            [dict get $snapshot phase] eq {route_design} &&
            [dict exists $snapshot run_status] &&
            [dict get $snapshot run_status] eq
                {route_design Complete, Failed Timing!}} {
        return [dict create state BLOCK action BLOCK \
            reason {Vivado route_design completed routing but failed timing closure (ROUTE_DESIGN_FAILED_TIMING).} \
            errorcode [list STAGE1E RUN2 RUNTIME_V2 \
                ROUTE_DESIGN_FAILED_TIMING]]
    }
    if {[catch {validate_snapshot $snapshot} reason options]} {
        return [dict create state BLOCK action BLOCK reason $reason errorcode [dict get $options -errorcode]]
    }
    return [dict create state CLEAR action PROCEED phase [dict get $snapshot phase] run_identity impl_1]
}

proc ::stage1e::vivado_runtime_contract_v2::validate_requested_graph {graph} {
    require_exact_fields $graph {enabled_operations launch_targets prohibited_operations incremental_implementation} {Requested implementation graph}
    set requested [dict get [property_map] requested_implementation_graph]
    require_equal [dict get $requested enabled_operations] [dict get $graph enabled_operations] {Enabled Project Mode operations}
    require_equal [dict get $requested launch_targets] [dict get $graph launch_targets] {Project Mode launch targets}
    require_equal [dict get $requested prohibited_operations] [dict get $graph prohibited_operations] {Prohibited operations}
    require_equal [dict get $requested incremental_implementation] [dict get $graph incremental_implementation] {Incremental implementation state}
    return 1
}
