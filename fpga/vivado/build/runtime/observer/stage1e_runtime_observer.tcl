# Stage 1E environment and process observation interface v1.
#
# Observations are supplied by an injected mock callback. The observer does
# not launch or terminate processes, inspect Vivado, qualify a workspace, or
# create a qualification identity.

namespace eval ::stage1e::runtime_observer {
    variable observation_fields {
        schema_version
        status
        environment_identity
        host_name
        os_description
        cwd
        xil_path
        launcher_lifetime
        child_process_observation
        dispatch_monitoring
        tool_observation
    }
}

proc ::stage1e::runtime_observer::_raise {code message} {
    return -code error -errorcode [list STAGE1E RUNTIME_OBSERVER $code] $message
}

proc ::stage1e::runtime_observer::validate {observation} {
    variable observation_fields
    ::stage1e::runtime_schema::require_exact_fields $observation \
        $observation_fields {Runtime environment observation}
    if {[dict get $observation schema_version] ne \
            {stage1e-runtime-environment-observation-v1}} {
        _raise SCHEMA_INVALID {Runtime environment observation schema mismatch.}
    }
    if {[dict get $observation status] ne {CURRENT}} {
        _raise OBSERVATION_STALE \
            {Runtime environment observation is not current.}
    }
    ::stage1e::runtime_schema::require_identity \
        [dict get $observation environment_identity] \
        {Runtime environment identity}
    foreach field {
        launcher_lifetime child_process_observation dispatch_monitoring
    } {
        if {[dict get $observation $field] ni {OBSERVED MOCK_OBSERVED}} {
            _raise OBSERVATION_INCOMPLETE \
                "Runtime observation field is incomplete: $field"
        }
    }
    set cwd [file normalize [dict get $observation cwd]]
    set xil [file normalize [dict get $observation xil_path]]
    if {![string equal -nocase [file tail $xil] {.Xil}]} {
        _raise CONTAINMENT_INVALID \
            {Observed runtime state directory is not the cwd .Xil directory.}
    }
    set cwd_components [file split $cwd]
    set xil_components [file split $xil]
    if {[llength $xil_components] < [llength $cwd_components]} {
        _raise CONTAINMENT_INVALID \
            {Observed .Xil location is outside the observed cwd.}
    }
    for {set index 0} {$index < [llength $cwd_components]} {incr index} {
        if {![string equal -nocase [lindex $cwd_components $index] \
                [lindex $xil_components $index]]} {
            _raise CONTAINMENT_INVALID \
                {Observed .Xil location is outside the observed cwd.}
        }
    }
    return 1
}

proc ::stage1e::runtime_observer::observe_mock {callback request} {
    if {![llength $callback]} {
        _raise CALLBACK_INVALID {Environment observer callback is empty.}
    }
    set callback_status [catch {
        uplevel #0 [list {*}$callback $request]
    } observation callback_options]
    if {$callback_status != 0} {
        return -options $callback_options $observation
    }
    validate $observation
    return $observation
}
