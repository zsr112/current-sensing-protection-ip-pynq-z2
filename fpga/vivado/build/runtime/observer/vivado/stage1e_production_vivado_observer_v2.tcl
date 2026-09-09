# Stage 1E Run2 evidence-derived Vivado capability observer v2.
#
# All live commands are read-only. The observer never launches a run, opens a
# design, writes a checkpoint, or produces an acceptance decision.

set ::stage1e_vivado_observer_v2_dir [file dirname [info script]]
set ::stage1e_vivado_observer_v2_build [file dirname [file dirname [file dirname $::stage1e_vivado_observer_v2_dir]]]
if {![llength [info commands ::stage1e::vivado_runtime_contract_v2::property_map]]} {
    source [file join $::stage1e_vivado_observer_v2_build lib stage1e_vivado_runtime_contract_v2.tcl]
}
if {![llength [info commands ::stage1e::canonical_json_v1::digest_bytes]]} {
    source [file join $::stage1e_vivado_observer_v2_build lib stage1e_runtime_canonical_json_v1.tcl]
}
unset ::stage1e_vivado_observer_v2_dir
unset ::stage1e_vivado_observer_v2_build

namespace eval ::stage1e::production_vivado_observer_v2 {
    variable interface_version stage1e-production-vivado-observer-interface-v2
}

proc ::stage1e::production_vivado_observer_v2::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_vivado_observer_v2::_raise {code message} {
    return -code error -errorcode [list STAGE1E RUN2 OBSERVER_V2 $code] $message
}

proc ::stage1e::production_vivado_observer_v2::required_property_projection {} {
    return [::stage1e::vivado_runtime_contract_v2::real_property_projection]
}

proc ::stage1e::production_vivado_observer_v2::observe_fixture {properties snapshot} {
    ::stage1e::vivado_runtime_contract_v2::validate_property_inventory $properties 1
    set result [::stage1e::vivado_runtime_contract_v2::evaluate_phase_completion $snapshot]
    dict set result observation_model CAPTURED_VIVADO_2024_1_FIXTURE
    dict set result property_projection [lsort -dictionary $properties]
    return $result
}

proc ::stage1e::production_vivado_observer_v2::_exact_impl_run {} {
    if {![llength [info commands get_runs]] || ![llength [info commands get_property]]} {
        _raise VIVADO_COMMAND_UNAVAILABLE {Vivado read-only query commands are unavailable.}
    }
    set runs [get_runs -quiet impl_1]
    if {[llength $runs] != 1} {
        _raise IMPLEMENTATION_RUN_IDENTITY {Expected exactly one implementation run named impl_1.}
    }
    return [lindex $runs 0]
}

proc ::stage1e::production_vivado_observer_v2::_live_property_capture {impl_run} {
    set properties [required_property_projection]
    set values {}
    foreach property $properties {
        if {[catch {get_property $property $impl_run} value]} {
            _raise PROPERTY_MISSING "Captured Vivado 2024.1 property is unavailable: $property"
        }
        dict set values $property $value
    }
    ::stage1e::vivado_runtime_contract_v2::validate_property_inventory $properties 1
    return [dict create properties $properties values $values]
}

proc ::stage1e::production_vivado_observer_v2::_checkpoint_for_phase {phase} {
    set contract [::stage1e::vivado_runtime_contract_v2::phase_contract $phase]
    return [dict get $contract required_checkpoint]
}

proc ::stage1e::production_vivado_observer_v2::_file_identity {path} {
    if {![file exists $path] || ![file isfile $path]} { return MISSING }
    return [::stage1e::canonical_json_v1::digest_file $path]
}

proc ::stage1e::production_vivado_observer_v2::observe_live {
    phase run_directory forbidden_operations
} {
    set impl_run [_exact_impl_run]
    set capture [_live_property_capture $impl_run]
    set values [dict get $capture values]
    set checkpoint [_checkpoint_for_phase $phase]
    set checkpoint_path [file join $run_directory $checkpoint]
    set checkpoint_identity [_file_identity $checkpoint_path]
    set snapshot [dict create \
        phase $phase \
        run_identity [dict get $values NAME] \
        run_status [dict get $values STATUS] \
        progress [dict get $values PROGRESS] \
        current_step [dict get $values CURRENT_STEP] \
        checkpoint $checkpoint \
        checkpoint_state [expr {[file exists $checkpoint_path] ? {PRESENT} : {MISSING}}] \
        checkpoint_identity $checkpoint_identity \
        forbidden_operations $forbidden_operations]
    set result [::stage1e::vivado_runtime_contract_v2::evaluate_phase_completion $snapshot]
    dict set result observation_model LIVE_VIVADO_2024_1_READ_ONLY
    dict set result property_projection [dict get $capture properties]
    dict set result snapshot $snapshot
    return $result
}
