# Mocked runtime tests for Stage2I BIT/LTX binding and session cleanup.

set test_directory [file dirname [file normalize [info script]]]
set repository_root [file dirname $test_directory]
set tool_directory [file join $repository_root tools board_validation]
source [file join $tool_directory stage1_board_ila_common.tcl]

set ::stage2i_runtime_check_count 0
set ::stage2i_runtime_events {}
set ::stage2i_runtime_properties [dict create]
set ::stage2i_runtime_profile SAFE_INERT
set ::stage2i_force_bad_readback 0

proc runtime_assert {condition message} {
    incr ::stage2i_runtime_check_count
    if {![uplevel 1 [list expr $condition]]} {
        error "ASSERTION FAILED: $message"
    }
}

proc runtime_equal {actual expected message} {
    incr ::stage2i_runtime_check_count
    if {$actual ne $expected} {
        error "ASSERTION FAILED: $message: $actual != $expected"
    }
}

proc runtime_expect_error {script pattern message} {
    incr ::stage2i_runtime_check_count
    if {![catch {uplevel 1 $script} observed]} {
        error "ASSERTION FAILED: $message did not fail"
    }
    if {![string match $pattern $observed]} {
        error "ASSERTION FAILED: $message: $observed"
    }
}

proc fixture_probe_records {profile role hierarchy} {
    set records {}
    set contract [::stage1::core_contract $profile $role]
    foreach {index width} [dict get $contract probe_widths] {
        lappend records [dict create \
            object "${role}_probe_$index" \
            name "${hierarchy}/probe${index}_1" \
            width $width]
    }
    return $records
}

proc open_hw_manager {} {
    lappend ::stage2i_runtime_events OPEN_MANAGER
}
proc connect_hw_server {args} {
    lappend ::stage2i_runtime_events CONNECT_SERVER
}
proc open_hw_target {} {
    lappend ::stage2i_runtime_events OPEN_TARGET
}
proc close_hw_target {} {
    lappend ::stage2i_runtime_events CLOSE_TARGET
}
proc close_hw_manager {} {
    lappend ::stage2i_runtime_events CLOSE_MANAGER
}
proc refresh_hw_device {device} {
    lappend ::stage2i_runtime_events "REFRESH:$device"
}
proc set_property {property value object} {
    dict set ::stage2i_runtime_properties "$object:$property" $value
    lappend ::stage2i_runtime_events "SET:$property"
}
proc get_property {property object} {
    set key "$object:$property"
    if {![dict exists $::stage2i_runtime_properties $key]} {
        error "Fixture property is unavailable: $key"
    }
    set value [dict get $::stage2i_runtime_properties $key]
    if {$::stage2i_force_bad_readback && $property eq {PROBES.FILE}} {
        return "${value}.wrong"
    }
    return $value
}

rename ::stage1::runtime_device_records \
    ::stage1::runtime_device_records_original
proc ::stage1::runtime_device_records {} {
    return [list [dict create \
        object xc7z020_1 name xc7z020_1 part xc7z020clg400-1]]
}
rename ::stage1::runtime_ila_records \
    ::stage1::runtime_ila_records_original
proc ::stage1::runtime_ila_records {device} {
    set destination_hierarchy \
        protection_system_i/system_ila_stage2b_0/inst
    set destination [dict create \
        object hw_ila_destination \
        name hw_ila_destination \
        cell_name \
            protection_system_i/system_ila_stage2b_0/inst/ila_lib \
        probes [::fixture_probe_records \
            $::stage2i_runtime_profile destination $destination_hierarchy]]
    if {$::stage2i_runtime_profile eq {SAFE_INERT}} {
        return [list $destination]
    }
    set source_hierarchy \
        protection_system_i/system_ila_stage2i_b2_source_0/inst
    set source [dict create \
        object hw_ila_source \
        name hw_ila_source \
        cell_name \
            protection_system_i/system_ila_stage2i_b2_source_0/inst/ila_lib \
        probes [::fixture_probe_records \
            $::stage2i_runtime_profile source $source_hierarchy]]
    return [list $destination $source]
}

set fixture_path [file normalize [info script]]
set safe_binding [::stage1::open_bound_hardware \
    $fixture_path $fixture_path SAFE_INERT localhost:3121]
runtime_equal [dict keys [dict get $safe_binding ila_records]] destination \
    {SAFE_INERT binds only the destination core}
runtime_equal [llength [lsearch -all -exact \
    $::stage2i_runtime_events SET:PROGRAM.FILE]] 1 \
    {the explicit BIT path is bound once}
runtime_equal [llength [lsearch -all -exact \
    $::stage2i_runtime_events SET:PROBES.FILE]] 1 \
    {the explicit LTX PROBES path is bound once}
runtime_equal [llength [lsearch -all -exact \
    $::stage2i_runtime_events SET:FULL_PROBES.FILE]] 1 \
    {the explicit LTX FULL_PROBES path is bound once}
::stage1::close_bound_hardware
runtime_equal [lrange $::stage2i_runtime_events end-1 end] \
    {CLOSE_TARGET CLOSE_MANAGER} {successful binding closes both session layers}

set ::stage2i_runtime_events {}
set ::stage2i_runtime_properties [dict create]
set ::stage2i_runtime_profile \
    READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
set b2_binding [::stage1::open_bound_hardware \
    $fixture_path $fixture_path $::stage2i_runtime_profile localhost:3121]
runtime_equal [dict keys [dict get $b2_binding ila_records]] \
    {destination source} {B2 binds both exact cores by role}
runtime_equal [dict size [dict get \
    $b2_binding ila_records destination logical_probe_map]] 8 \
    {B2 destination core retains eight ACLK-domain logical probes}
runtime_equal [dict size [dict get \
    $b2_binding ila_records source logical_probe_map]] 8 \
    {B2 source core retains 8 logical probes}
::stage1::close_bound_hardware

set ::stage2i_runtime_events {}
set ::stage2i_runtime_properties [dict create]
set ::stage2i_force_bad_readback 1
runtime_expect_error {
    ::stage1::open_bound_hardware \
        $fixture_path $fixture_path \
        READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS localhost:3121
} {*PROBES.FILE readback mismatch*} \
    {a mismatched LTX readback fails before ILA selection}
::stage1::close_bound_hardware
set ::stage2i_force_bad_readback 0
runtime_equal [lrange $::stage2i_runtime_events end-1 end] \
    {CLOSE_TARGET CLOSE_MANAGER} {failed binding still closes both session layers}

runtime_assert {[llength [info commands program_hw_devices]] == 0} \
    {the fixture and common binding path define no programming command}
puts "STAGE2I_BIT_LTX_RUNTIME_FIXTURE_TESTS_PASS checks=$::stage2i_runtime_check_count"
