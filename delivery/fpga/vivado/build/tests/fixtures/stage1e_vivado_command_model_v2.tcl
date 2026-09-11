# Faithful non-Vivado fixture for the captured Run2-HC Vivado 2024.1 evidence.
# It models real run-level Project Mode observations only; it intentionally
# cannot manufacture the synthetic per-step properties rejected by v2.

set ::stage1e_vivado_command_model_v2_dir [file dirname [info script]]
set ::stage1e_vivado_command_model_v2_build [file dirname [file dirname $::stage1e_vivado_command_model_v2_dir]]
if {![llength [info commands ::stage1e::vivado_runtime_contract_v2::real_property_projection]]} {
    source [file join $::stage1e_vivado_command_model_v2_build lib stage1e_vivado_runtime_contract_v2.tcl]
}
unset ::stage1e_vivado_command_model_v2_dir
unset ::stage1e_vivado_command_model_v2_build

namespace eval ::stage1e::vivado_command_model_v2 {
    variable interface_version stage1e-vivado-command-model-interface-v2
}

proc ::stage1e::vivado_command_model_v2::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::vivado_command_model_v2::_raise {code message} {
    return -code error -errorcode [list STAGE1E RUN2 FIXTURE_V2 $code] $message
}

proc ::stage1e::vivado_command_model_v2::property_set {} {
    return [::stage1e::vivado_runtime_contract_v2::real_property_projection]
}

proc ::stage1e::vivado_command_model_v2::new {} {
    set values {}
    foreach property [property_set] { dict set values $property {} }
    foreach {property value} {
        NAME impl_1
        PARENT synth_1
        PART xc7z020clg400-1
        NEEDS_REFRESH 0
        INCREMENTAL_CHECKPOINT {}
        AUTO_INCREMENTAL_CHECKPOINT 0
        STATUS {Not started}
        PROGRESS 0%
        CURRENT_STEP {}
        STEPS.OPT_DESIGN.IS_ENABLED 1
        STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default
        STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Default
        STEPS.PHYS_OPT_DESIGN.IS_ENABLED 0
        STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Default
        STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED 0
        STEPS.POWER_OPT_DESIGN.IS_ENABLED 0
        STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED 0
        STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Default
    } { dict set values $property $value }
    return [dict create schema_version stage1e-vivado-command-model-v2 \
        state PRE_IMPLEMENTATION properties $values transitions {} forbidden_operations {}]
}

proc ::stage1e::vivado_command_model_v2::_expected_target {model} {
    switch -- [dict get $model state] {
        PRE_IMPLEMENTATION { return opt_design }
        POST_OPT { return place_design }
        POST_PLACE { return route_design }
        default { return NONE }
    }
}

proc ::stage1e::vivado_command_model_v2::_snapshot_for {model phase} {
    set values [dict get $model properties]
    set contracts [dict get [::stage1e::vivado_runtime_contract_v2::property_map] phase_completion_contract]
    set contract [dict get $contracts $phase]
    return [dict create \
        phase $phase \
        run_identity [dict get $values NAME] \
        run_status [dict get $values STATUS] \
        progress [dict get $values PROGRESS] \
        current_step [dict get $values CURRENT_STEP] \
        checkpoint [dict get $contract required_checkpoint] \
        checkpoint_state PRESENT \
        checkpoint_identity [string repeat [expr {[dict get $contract ordinal] + 1}] 64] \
        forbidden_operations [dict get $model forbidden_operations]]
}

proc ::stage1e::vivado_command_model_v2::launch_to {model target} {
    if {$target ne [_expected_target $model]} { _raise PHASE_ORDER "Captured Project Mode transition cannot launch $target from [dict get $model state]." }
    dict lappend model transitions "ATTEMPT:$target"
    switch -- $target {
        opt_design {
            dict set model state POST_OPT
            dict set model properties STATUS {Not started place_design}
            dict set model properties PROGRESS 50%
            dict set model properties CURRENT_STEP place_design
        }
        place_design {
            dict set model state POST_PLACE
            dict set model properties STATUS {Not started route_design}
            dict set model properties PROGRESS 75%
            dict set model properties CURRENT_STEP route_design
        }
        route_design {
            dict set model state POST_ROUTE
            dict set model properties STATUS {route_design Complete!}
            dict set model properties PROGRESS 100%
            dict set model properties CURRENT_STEP route_design
        }
    }
    dict lappend model transitions "COMPLETED:$target"
    return [dict create model $model snapshot [_snapshot_for $model $target]]
}

proc ::stage1e::vivado_command_model_v2::pre_implementation_observation {model} {
    if {[dict get $model state] ne {PRE_IMPLEMENTATION}} { _raise SNAPSHOT_ORDER {Pre-implementation observation is no longer available.} }
    set values [dict get $model properties]
    return [dict create state PRE_IMPLEMENTATION run_identity [dict get $values NAME] \
        run_status [dict get $values STATUS] progress [dict get $values PROGRESS] \
        current_step [dict get $values CURRENT_STEP] property_set [property_set]]
}

proc ::stage1e::vivado_command_model_v2::with_conflict {model} {
    dict set model forbidden_operations {phys_opt_design}
    return $model
}

proc ::stage1e::vivado_command_model_v2::with_failed_timing {snapshot} {
    dict set snapshot run_status {route_design Complete, Failed Timing!}
    return $snapshot
}

proc ::stage1e::vivado_command_model_v2::with_synthetic_property {properties} {
    return [concat $properties [list STEPS.PLACE_DESIGN.STATUS]]
}
