namespace eval ::stage1d {}

set stage1d_build_root [file normalize [file dirname [info script]]]
set stage1d_controller_root [file join $stage1d_build_root controller]
set stage1d_library_root [file join $stage1d_build_root lib]
set stage1d_mutation_root [file join $stage1d_build_root mutation]
set stage1d_controller_modules [list \
    [file join $stage1d_controller_root argument_parser.tcl] \
    [file join $stage1d_controller_root configuration_loader.tcl] \
    [file join $stage1d_controller_root logger.tcl] \
    [file join $stage1d_controller_root state_manager.tcl] \
    [file join $stage1d_controller_root phase_runner.tcl] \
    [file join $stage1d_controller_root decision_engine.tcl] \
    [file join $stage1d_library_root source_check.tcl] \
    [file join $stage1d_controller_root delivery_bundle_loader.tcl] \
    [file join $stage1d_library_root environment_check.tcl] \
    [file join $stage1d_library_root workspace_manager.tcl] \
    [file join $stage1d_library_root vivado_project.tcl] \
    [file join $stage1d_library_root bd_flow.tcl] \
    [file join $stage1d_mutation_root stage1d_controlled_stimulus.tcl] \
    [file join $stage1d_controller_root controller_core.tcl]]

foreach stage1d_controller_module_path $stage1d_controller_modules {
    if {![file exists $stage1d_controller_module_path]} {
        error "Required controller module not found: [file tail $stage1d_controller_module_path]"
    }
    source $stage1d_controller_module_path
}

if {![namespace exists ::stage1d_controlled_stimulus]} {
    error {Required mutation namespace was not defined: ::stage1d_controlled_stimulus}
}
if {[llength [info procs ::stage1d_controlled_stimulus::apply]] != 1} {
    error {Required mutation procedure was not defined: ::stage1d_controlled_stimulus::apply}
}

set stage1d_main_status [catch {
    ::stage1d::controller_core::main $argv
} stage1d_main_result stage1d_main_options]

if {$stage1d_main_status != 0} {
    set stage1d_error_info {}
    if {[dict exists $stage1d_main_options -errorinfo]} {
        set stage1d_error_info [dict get $stage1d_main_options -errorinfo]
    }
    set stage1d_main_result [dict create \
        controller_version [::stage1d::controller_core::version] \
        controller_api_version [::stage1d::controller_core::api_version] \
        execution_id_schema_version [::stage1d::controller_core::execution_id_schema_version] \
        decision FAIL \
        reason_code CONTROLLER_BOOTSTRAP_ERROR \
        error_message $stage1d_main_result \
        error_info $stage1d_error_info \
        workspace_created 0 \
        vivado_invoked 0 \
        artifacts_generated 0 \
        manifest_published 0 \
        exit_code 1]
    puts stderr [list STAGE1D_BOOTSTRAP_ERROR $stage1d_main_result]
}

set ::stage1d::last_result $stage1d_main_result
puts [list STAGE1D_RESULT $stage1d_main_result]

if {[info exists ::env(STAGE1D_CONTROLLER_NO_EXIT)] && $::env(STAGE1D_CONTROLLER_NO_EXIT) eq {1}} {
    return
}

exit [dict get $stage1d_main_result exit_code]
