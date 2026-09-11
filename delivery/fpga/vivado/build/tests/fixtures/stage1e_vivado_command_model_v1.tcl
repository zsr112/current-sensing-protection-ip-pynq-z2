# Standalone Tcl command model for PRT02-C validation.
#
# This fixture supplies a closed mock of the reviewed query and staged Project
# Mode control surface. It does not source or discover a Vivado package.

namespace eval ::stage1e::vivado_command_model_v1 {
    variable model {}
    variable properties {}
    variable command_log {}
    variable pending_target NONE
    variable faults {}
    variable post_wait_faults {}
    variable post_wait_current_runs {}
    variable hidden_commands {}
    variable report_commands {
        report_timing_summary report_utilization report_drc
        report_methodology report_clock_interaction report_timing
        report_route_status report_exceptions report_clocks report_cdc
    }
}

proc ::stage1e::vivado_command_model_v1::_canonical_path {path} {
    set path [string map {\\ /} $path]
    return [string map {\\ /} [file join {*}[file split $path]]]
}

proc ::stage1e::vivado_command_model_v1::_key {object property} {
    return "$object|$property"
}

proc ::stage1e::vivado_command_model_v1::_put {object property value} {
    variable properties
    dict set properties [_key $object $property] $value
}

proc ::stage1e::vivado_command_model_v1::_get {object property} {
    variable properties
    variable faults
    set key [_key $object $property]
    if {[dict exists $faults missing_properties $key]} {
        error "Synthetic property is unavailable: $property/$object"
    }
    if {![dict exists $properties $key]} {
        error "Synthetic property is undefined: $property/$object"
    }
    return [dict get $properties $key]
}

proc ::stage1e::vivado_command_model_v1::_log {kind command arguments} {
    variable command_log
    lappend command_log [dict create kind $kind command $command \
        arguments $arguments ordinal [expr {[llength $command_log] + 1}]]
}

proc ::stage1e::vivado_command_model_v1::reset {workspace} {
    variable model
    variable properties
    variable command_log
    variable pending_target
    variable faults
    variable post_wait_faults
    variable post_wait_current_runs
    restore_commands
    set workspace [_canonical_path $workspace]
    set model [dict create \
        workspace $workspace \
        project project:current_protection_ip_pynq_z2_stage1e \
        fileset fileset:sources_1 \
        implementation_run run:impl_1 \
        synthesis_run run:synth_1 \
        part part:xc7z020clg400-1 \
        board_part board:tul.com.tw:pynq-z2:part0:1.0 \
        current_run {} \
        current_design {}]
    set properties {}
    set command_log {}
    set pending_target NONE
    set faults [dict create \
        impl_cardinality 1 synth_cardinality 1 project_cardinality 1 \
        fileset_cardinality 1 part_cardinality 1 board_cardinality 1 \
        license_state PASS wait_timeout NONE phase_failure NONE \
        launch_failure NONE open_failure 0 current_run_query_error 0 \
        missing_properties {}]
    set post_wait_faults {}
    set post_wait_current_runs {}

    set project [dict get $model project]
    _put $project NAME current_protection_ip_pynq_z2_stage1e
    _put $project DIRECTORY $workspace
    _put $project PART xc7z020clg400-1
    _put $project BOARD_PART tul.com.tw:pynq-z2:part0:1.0
    _put $project STAGE1E.DIRECT_IMPLEMENTATION_MARKER NONE
    _put $project STAGE1E.EXTRA_OPERATION_MARKER NONE
    _put $project STAGE1E.DOWNSTREAM_COMMAND_MARKER NONE
    _put $project STAGE1E.DOWNSTREAM_OUTPUT_MARKER NONE

    set fileset [dict get $model fileset]
    _put $fileset TOP protection_system_wrapper

    set implementation [dict get $model implementation_run]
    _put $implementation NAME impl_1
    _put $implementation STRATEGY Vivado_Implementation_Defaults
    _put $implementation PARENT synth_1
    _put $implementation SRCSET sources_1
    _put $implementation PART xc7z020clg400-1
    _put $implementation NEEDS_REFRESH 0
    _put $implementation INCREMENTAL_CHECKPOINT {}
    _put $implementation AUTO_INCREMENTAL_CHECKPOINT 0
    _put $implementation STATUS NOT_STARTED
    _put $implementation PROGRESS 0
    _put $implementation CURRENT_STEP NONE
    _put $implementation STEPS.OPT_DESIGN.IS_ENABLED 1
    _put $implementation STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default
    _put $implementation STEPS.OPT_DESIGN.STATUS NOT_RUN
    _put $implementation STEPS.OPT_DESIGN.TCL.PRE {}
    _put $implementation STEPS.OPT_DESIGN.TCL.POST {}
    _put $implementation STEPS.OPT_DESIGN.ARGS.SEED TOOL_DEFAULT
    _put $implementation STEPS.PLACE_DESIGN.IS_ENABLED 1
    _put $implementation STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Default
    _put $implementation STEPS.PLACE_DESIGN.STATUS NOT_RUN
    _put $implementation STEPS.PLACE_DESIGN.TCL.PRE {}
    _put $implementation STEPS.PLACE_DESIGN.TCL.POST {}
    _put $implementation STEPS.PHYS_OPT_DESIGN.IS_ENABLED 0
    _put $implementation STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE NONE
    _put $implementation STEPS.PHYS_OPT_DESIGN.STATUS NOT_RUN
    _put $implementation STEPS.PHYS_OPT_DESIGN.TCL.PRE {}
    _put $implementation STEPS.PHYS_OPT_DESIGN.TCL.POST {}
    _put $implementation STEPS.ROUTE_DESIGN.IS_ENABLED 1
    _put $implementation STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Default
    _put $implementation STEPS.ROUTE_DESIGN.STATUS NOT_RUN
    _put $implementation STEPS.ROUTE_DESIGN.TCL.PRE {}
    _put $implementation STEPS.ROUTE_DESIGN.TCL.POST {}

    set synthesis [dict get $model synthesis_run]
    _put $synthesis NAME synth_1
    _put $synthesis STATUS COMPLETE
    _put $synthesis NEEDS_REFRESH 0
    return 1
}

proc ::stage1e::vivado_command_model_v1::set_fault {name value} {
    variable faults
    variable model
    set allowed {
        impl_cardinality synth_cardinality project_cardinality
        fileset_cardinality part_cardinality board_cardinality license_state
        wait_timeout phase_failure stale_run stale_synthesis phys_enabled
        phys_invoked phys_hook direct_marker extra_marker downstream_command
        downstream_output launch_failure open_failure
    }
    if {[lsearch -exact $allowed $name] < 0} {
        error "Unknown command-model fault: $name"
    }
    dict set faults $name $value
    set implementation [dict get $model implementation_run]
    set synthesis [dict get $model synthesis_run]
    set project [dict get $model project]
    switch -- $name {
        stale_run { _put $implementation NEEDS_REFRESH $value }
        stale_synthesis { _put $synthesis NEEDS_REFRESH $value }
        phys_enabled {
            _put $implementation STEPS.PHYS_OPT_DESIGN.IS_ENABLED $value
        }
        phys_invoked {
            _put $implementation STEPS.PHYS_OPT_DESIGN.STATUS \
                [expr {$value ? {COMPLETE} : {NOT_RUN}}]
        }
        phys_hook {
            _put $implementation STEPS.PHYS_OPT_DESIGN.TCL.PRE \
                [expr {$value ? {synthetic_phys_hook.tcl} : {}}]
        }
        direct_marker {
            _put $project STAGE1E.DIRECT_IMPLEMENTATION_MARKER \
                [expr {$value ? {DETECTED} : {NONE}}]
        }
        extra_marker {
            _put $project STAGE1E.EXTRA_OPERATION_MARKER \
                [expr {$value ? {DETECTED} : {NONE}}]
        }
        downstream_command {
            _put $project STAGE1E.DOWNSTREAM_COMMAND_MARKER \
                [expr {$value ? {DETECTED} : {NONE}}]
        }
        downstream_output {
            _put $project STAGE1E.DOWNSTREAM_OUTPUT_MARKER \
                [expr {$value ? {DETECTED} : {NONE}}]
        }
    }
    return 1
}

proc ::stage1e::vivado_command_model_v1::set_post_wait_fault {
    target name value
} {
    variable post_wait_faults
    if {$target ni {opt_design place_design route_design}} {
        error "Unknown post-wait target: $target"
    }
    if {$name ni {direct_marker extra_marker downstream_command
            downstream_output phys_enabled phys_invoked phys_hook
            missing_direct_marker missing_extra_marker
            missing_downstream_command missing_downstream_output
            missing_physical_state}} {
        error "Unknown post-wait fault: $name"
    }
    dict lappend post_wait_faults $target [list $name $value]
    return 1
}

proc ::stage1e::vivado_command_model_v1::set_post_wait_current_run {
    target mode
} {
    variable post_wait_current_runs
    if {$target ni {opt_design place_design route_design} ||
            $mode ni {IMPL_1 NONE OTHER MULTIPLE UNAVAILABLE}} {
        error "Unknown post-wait current-run fault: $target/$mode"
    }
    dict set post_wait_current_runs $target $mode
    return 1
}

proc ::stage1e::vivado_command_model_v1::_apply_marker_fault {name value} {
    variable model
    set project [dict get $model project]
    set implementation [dict get $model implementation_run]
    switch -- $name {
        direct_marker - extra_marker - downstream_command -
        downstream_output - phys_enabled - phys_invoked - phys_hook {
            set_fault $name $value
        }
        missing_direct_marker {
            missing_property $project STAGE1E.DIRECT_IMPLEMENTATION_MARKER
        }
        missing_extra_marker {
            missing_property $project STAGE1E.EXTRA_OPERATION_MARKER
        }
        missing_downstream_command {
            missing_property $project STAGE1E.DOWNSTREAM_COMMAND_MARKER
        }
        missing_downstream_output {
            missing_property $project STAGE1E.DOWNSTREAM_OUTPUT_MARKER
        }
        missing_physical_state {
            missing_property $implementation \
                STEPS.PHYS_OPT_DESIGN.IS_ENABLED
        }
    }
}

proc ::stage1e::vivado_command_model_v1::_apply_post_wait_faults {target} {
    variable post_wait_faults
    variable post_wait_current_runs
    variable faults
    variable model
    if {[dict exists $post_wait_faults $target]} {
        foreach fault [dict get $post_wait_faults $target] {
            lassign $fault name value
            _apply_marker_fault $name $value
        }
    }
    set mode IMPL_1
    if {[dict exists $post_wait_current_runs $target]} {
        set mode [dict get $post_wait_current_runs $target]
    }
    dict set faults current_run_query_error 0
    switch -- $mode {
        IMPL_1 { dict set model current_run [list impl_1] }
        NONE { dict set model current_run {} }
        OTHER { dict set model current_run [list impl_alternate] }
        MULTIPLE {
            dict set model current_run [list impl_1 impl_alternate]
        }
        UNAVAILABLE {
            dict set model current_run {}
            dict set faults current_run_query_error 1
        }
    }
}

proc ::stage1e::vivado_command_model_v1::missing_property {
    object property
} {
    variable faults
    dict set faults missing_properties [_key $object $property] 1
    return 1
}

proc ::stage1e::vivado_command_model_v1::set_property_value {
    object property value
} {
    _put $object $property $value
    return 1
}

proc ::stage1e::vivado_command_model_v1::object {role} {
    variable model
    set mapping [dict create \
        CURRENT_PROJECT project SOURCES_FILESET fileset IMPL_RUN \
        implementation_run SYNTH_RUN synthesis_run TARGET_PART part \
        TARGET_BOARD_PART board_part]
    if {![dict exists $mapping $role]} {
        error "Unknown command-model object role: $role"
    }
    return [dict get $model [dict get $mapping $role]]
}

proc ::stage1e::vivado_command_model_v1::command_log {} {
    variable command_log
    return $command_log
}

proc ::stage1e::vivado_command_model_v1::control_log {} {
    variable command_log
    set result {}
    foreach entry $command_log {
        if {[dict get $entry kind] eq {CONTROL}} { lappend result $entry }
    }
    return $result
}

proc ::stage1e::vivado_command_model_v1::hide_command {name} {
    variable hidden_commands
    set allowed {
        version get_license_info current_project current_run current_design
        get_runs get_filesets get_parts get_board_parts get_property
        launch_runs wait_on_run open_run report_timing_summary
        report_utilization report_drc report_methodology
        report_clock_interaction report_timing report_route_status
        report_exceptions report_clocks report_cdc
    }
    if {[lsearch -exact $allowed $name] < 0 ||
            ![llength [info commands ::$name]]} {
        error "Cannot hide command-model command: $name"
    }
    set hidden ::stage1e::vivado_command_model_v1::hidden_$name
    rename ::$name $hidden
    dict set hidden_commands $name $hidden
    return 1
}

proc ::stage1e::vivado_command_model_v1::restore_commands {} {
    variable hidden_commands
    dict for {name hidden} $hidden_commands {
        if {[llength [info commands $hidden]] &&
                ![llength [info commands ::$name]]} {
            rename $hidden ::$name
        }
    }
    set hidden_commands {}
    return 1
}

proc ::version {argument} {
    ::stage1e::vivado_command_model_v1::_log QUERY version [list $argument]
    switch -- $argument {
        -short { return 2024.1 }
        -build { return 5076996 }
        -ipbuild { return 5075265 }
        default { error "Unsupported synthetic version argument: $argument" }
    }
}

proc ::get_license_info {flag feature} {
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log QUERY get_license_info \
        [list $flag $feature]
    if {$flag ne {-feature} || $feature ne {Implementation}} {
        error {Synthetic license query differs from the closed contract.}
    }
    set state [dict get $faults license_state]
    return [dict create feature Implementation status $state \
        implementation_feature_available [expr {$state eq {PASS} ? 1 : 0}]]
}

proc ::current_project {argument} {
    variable ::stage1e::vivado_command_model_v1::model
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log QUERY current_project \
        [list $argument]
    if {$argument ne {-quiet}} { error {Unsupported current_project form.} }
    set count [dict get $faults project_cardinality]
    if {$count == 0} { return {} }
    if {$count == 1} { return [list [dict get $model project]] }
    return [list [dict get $model project] project:duplicate]
}

proc ::current_run {argument} {
    variable ::stage1e::vivado_command_model_v1::model
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log QUERY current_run \
        [list $argument]
    if {$argument ne {-quiet}} { error {Unsupported current_run form.} }
    if {[dict get $faults current_run_query_error]} {
        error {Synthetic current_run query is unavailable.}
    }
    return [dict get $model current_run]
}

proc ::current_design {argument} {
    variable ::stage1e::vivado_command_model_v1::model
    ::stage1e::vivado_command_model_v1::_log QUERY current_design \
        [list $argument]
    if {$argument ne {-quiet}} { error {Unsupported current_design form.} }
    return [dict get $model current_design]
}

proc ::get_runs {quiet run_name} {
    variable ::stage1e::vivado_command_model_v1::model
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log QUERY get_runs \
        [list $quiet $run_name]
    if {$quiet ne {-quiet}} { error {Synthetic get_runs requires -quiet.} }
    if {$run_name eq {impl_1}} {
        set count [dict get $faults impl_cardinality]
        set object [dict get $model implementation_run]
    } elseif {$run_name eq {synth_1}} {
        set count [dict get $faults synth_cardinality]
        set object [dict get $model synthesis_run]
    } else {
        return {}
    }
    if {$count == 0} { return {} }
    if {$count == 1} { return [list $object] }
    return [list $object "${object}:duplicate"]
}

proc ::get_filesets {quiet name} {
    variable ::stage1e::vivado_command_model_v1::model
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log QUERY get_filesets \
        [list $quiet $name]
    if {$quiet ne {-quiet} || $name ne {sources_1}} {
        error {Synthetic get_filesets differs from the closed contract.}
    }
    set count [dict get $faults fileset_cardinality]
    if {$count == 0} { return {} }
    if {$count == 1} { return [list [dict get $model fileset]] }
    return [list [dict get $model fileset] fileset:duplicate]
}

proc ::get_parts {quiet name} {
    variable ::stage1e::vivado_command_model_v1::model
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log QUERY get_parts \
        [list $quiet $name]
    if {$quiet ne {-quiet} || $name ne {xc7z020clg400-1}} {
        error {Synthetic get_parts differs from the closed contract.}
    }
    set count [dict get $faults part_cardinality]
    if {$count == 0} { return {} }
    if {$count == 1} { return [list [dict get $model part]] }
    return [list [dict get $model part] part:duplicate]
}

proc ::get_board_parts {quiet name} {
    variable ::stage1e::vivado_command_model_v1::model
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log QUERY get_board_parts \
        [list $quiet $name]
    if {$quiet ne {-quiet} ||
            $name ne {tul.com.tw:pynq-z2:part0:1.0}} {
        error {Synthetic get_board_parts differs from the closed contract.}
    }
    set count [dict get $faults board_cardinality]
    if {$count == 0} { return {} }
    if {$count == 1} { return [list [dict get $model board_part]] }
    return [list [dict get $model board_part] board:duplicate]
}

proc ::get_property {property object} {
    ::stage1e::vivado_command_model_v1::_log QUERY get_property \
        [list $property $object]
    return [::stage1e::vivado_command_model_v1::_get $object $property]
}

proc ::launch_runs {run_name args} {
    variable ::stage1e::vivado_command_model_v1::model
    variable ::stage1e::vivado_command_model_v1::pending_target
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log CONTROL launch_runs \
        [linsert $args 0 $run_name]
    if {$run_name ne {impl_1} || [llength $args] != 4 ||
            [lindex $args 0] ne {-to_step} ||
            [lindex $args 2] ne {-jobs} || [lindex $args 3] ne {2}} {
        error {Synthetic launch differs from the closed Project Mode form.}
    }
    set target [lindex $args 1]
    set implementation [dict get $model implementation_run]
    set opt [::stage1e::vivado_command_model_v1::_get $implementation \
        STEPS.OPT_DESIGN.STATUS]
    set place [::stage1e::vivado_command_model_v1::_get $implementation \
        STEPS.PLACE_DESIGN.STATUS]
    set route [::stage1e::vivado_command_model_v1::_get $implementation \
        STEPS.ROUTE_DESIGN.STATUS]
    if {$pending_target ne {NONE}} {
        error {Synthetic run already has one pending target.}
    }
    if {$target eq {opt_design}} {
        if {$opt ne {NOT_RUN} || $place ne {NOT_RUN} || $route ne {NOT_RUN}} {
            error {Synthetic optimization target is repeated or reordered.}
        }
        set status_property STEPS.OPT_DESIGN.STATUS
    } elseif {$target eq {place_design}} {
        if {$opt ne {COMPLETE} || $place ne {NOT_RUN} || $route ne {NOT_RUN}} {
            error {Synthetic placement target is skipped, repeated, or reordered.}
        }
        set status_property STEPS.PLACE_DESIGN.STATUS
    } elseif {$target eq {route_design}} {
        if {$opt ne {COMPLETE} || $place ne {COMPLETE} ||
                $route ne {NOT_RUN}} {
            error {Synthetic routing target is skipped, repeated, or reordered.}
        }
        set status_property STEPS.ROUTE_DESIGN.STATUS
    } else {
        error "Synthetic launch target is prohibited: $target"
    }
    dict set model current_run [list impl_1]
    if {[dict get $faults launch_failure] eq $target} {
        error "Synthetic launch failure: $target"
    }
    set pending_target $target
    ::stage1e::vivado_command_model_v1::_put $implementation \
        $status_property RUNNING
    ::stage1e::vivado_command_model_v1::_put $implementation STATUS RUNNING
    ::stage1e::vivado_command_model_v1::_put $implementation CURRENT_STEP \
        [string toupper $target]
    return LAUNCHED
}

proc ::wait_on_run {flag timeout_minutes run_name} {
    variable ::stage1e::vivado_command_model_v1::model
    variable ::stage1e::vivado_command_model_v1::pending_target
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log CONTROL wait_on_run \
        [list $flag $timeout_minutes $run_name]
    if {$flag ne {-timeout} ||
            ![string is integer -strict $timeout_minutes] ||
            $timeout_minutes < 1 || $timeout_minutes > 10080 ||
            $run_name ne {impl_1} || $pending_target eq {NONE}} {
        error {Synthetic wait has no exact pending impl_1 target.}
    }
    if {[dict get $faults wait_timeout] eq $pending_target} {
        return TIMEOUT
    }
    if {[dict get $faults phase_failure] eq $pending_target} {
        error "Synthetic phase failure: $pending_target"
    }
    set implementation [dict get $model implementation_run]
    switch -- $pending_target {
        opt_design {
            ::stage1e::vivado_command_model_v1::_put $implementation \
                STEPS.OPT_DESIGN.STATUS COMPLETE
            ::stage1e::vivado_command_model_v1::_put $implementation \
                STATUS OPT_COMPLETE
            ::stage1e::vivado_command_model_v1::_put $implementation PROGRESS 33
        }
        place_design {
            ::stage1e::vivado_command_model_v1::_put $implementation \
                STEPS.PLACE_DESIGN.STATUS COMPLETE
            ::stage1e::vivado_command_model_v1::_put $implementation \
                STATUS PLACE_COMPLETE
            ::stage1e::vivado_command_model_v1::_put $implementation PROGRESS 66
        }
        route_design {
            if {[::stage1e::vivado_command_model_v1::_get $implementation \
                    STEPS.PHYS_OPT_DESIGN.IS_ENABLED] eq {1} ||
                    [::stage1e::vivado_command_model_v1::_get $implementation \
                        STEPS.PHYS_OPT_DESIGN.TCL.PRE] ne {}} {
                ::stage1e::vivado_command_model_v1::_put $implementation \
                    STEPS.PHYS_OPT_DESIGN.STATUS COMPLETE
            }
            ::stage1e::vivado_command_model_v1::_put $implementation \
                STEPS.ROUTE_DESIGN.STATUS COMPLETE
            ::stage1e::vivado_command_model_v1::_put $implementation \
                STATUS ROUTE_COMPLETE
            ::stage1e::vivado_command_model_v1::_put $implementation PROGRESS 100
        }
    }
    ::stage1e::vivado_command_model_v1::_apply_post_wait_faults \
        $pending_target
    set pending_target NONE
    return RETURNED
}

proc ::open_run {run_name} {
    variable ::stage1e::vivado_command_model_v1::model
    variable ::stage1e::vivado_command_model_v1::faults
    ::stage1e::vivado_command_model_v1::_log CONTROL open_run [list $run_name]
    if {$run_name ne {impl_1}} {
        error {Synthetic open_run permits only impl_1.}
    }
    set implementation [dict get $model implementation_run]
    if {[::stage1e::vivado_command_model_v1::_get $implementation \
            STEPS.ROUTE_DESIGN.STATUS] ne {COMPLETE}} {
        error {Synthetic routed run is not complete.}
    }
    if {[dict get $faults open_failure]} {
        error {Synthetic routed-open failure.}
    }
    dict set model current_run [list impl_1]
    dict set model current_design [list impl_1]
    return OPENED
}

proc ::stage1e::vivado_command_model_v1::_report_prohibited {name args} {
    _log FORBIDDEN $name $args
    error "Report command execution is outside PRT02-C: $name"
}

foreach ::stage1e_vivado_report_command \
        $::stage1e::vivado_command_model_v1::report_commands {
    proc ::$::stage1e_vivado_report_command {args} \
        [string map [list @NAME@ $::stage1e_vivado_report_command] {
            return [::stage1e::vivado_command_model_v1::_report_prohibited \
                @NAME@ $args]
        }]
}
unset ::stage1e_vivado_report_command
