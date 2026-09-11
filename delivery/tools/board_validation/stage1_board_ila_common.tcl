# Common identity and binding helpers for Stage2I System ILA tools.
#
# This file defines procedures only. Sourcing it performs no hardware access.

namespace eval ::stage1 {
    variable safe_inert_profile {SAFE_INERT}
    variable ready_aware_profile \
        {READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS}
    variable expected_fpga_part {xc7z020clg400-1}
    variable safe_inert_destination_probe_widths {
        0 1
        1 1
        2 12
        3 12
        4 1
        5 1
        6 1
        7 1
        8 8
        9 8
        10 4
        11 1
    }
    variable ready_aware_destination_probe_widths {
        0 1
        1 1
        2 1
        3 1
        4 1
        5 8
        6 8
        7 4
    }
    variable source_probe_widths {
        0 1
        1 1
        2 12
        3 12
        4 1
        5 7
        6 1
        7 1
    }
    variable manager_open 0
    variable target_open 0
}

proc ::stage1::supported_profiles {} {
    variable safe_inert_profile
    variable ready_aware_profile
    return [list $safe_inert_profile $ready_aware_profile]
}

proc ::stage1::profile_core_roles {profile} {
    variable safe_inert_profile
    variable ready_aware_profile
    if {$profile eq $safe_inert_profile} {
        return {destination}
    }
    if {$profile eq $ready_aware_profile} {
        return {destination source}
    }
    error "Unsupported Stage2I implementation profile: $profile"
}

proc ::stage1::core_contract {profile role} {
    variable safe_inert_profile
    variable ready_aware_profile
    variable safe_inert_destination_probe_widths
    variable ready_aware_destination_probe_widths
    variable source_probe_widths
    set roles [profile_core_roles $profile]
    if {[lsearch -exact $roles $role] < 0} {
        error "ILA core role $role is not valid for profile $profile"
    }
    switch -- $role {
        destination {
            set probe_widths $safe_inert_destination_probe_widths
            if {$profile eq $ready_aware_profile} {
                set probe_widths $ready_aware_destination_probe_widths
            }
            return [dict create \
                role destination \
                cell_name_suffix \
                    {system_ila_stage2b_0/inst/ila_lib} \
                probe_widths $probe_widths \
                logical_probe_count [expr {[llength $probe_widths] / 2}]]
        }
        source {
            return [dict create \
                role source \
                cell_name_suffix \
                    {system_ila_stage2i_b2_source_0/inst/ila_lib} \
                probe_widths $source_probe_widths \
                logical_probe_count 8]
        }
        default {
            error "Unsupported Stage2I ILA core role: $role"
        }
    }
}

proc ::stage1::require_single {objects label} {
    if {[llength $objects] != 1} {
        error "Expected exactly one $label, observed [llength $objects]: $objects"
    }
    return [lindex $objects 0]
}

proc ::stage1::path_segments {value} {
    set normalized [string trim $value {/}]
    if {$normalized eq {}} {
        return {}
    }
    set segments [split $normalized {/}]
    if {[lsearch -exact $segments {}] >= 0} {
        return {}
    }
    return $segments
}

proc ::stage1::cell_name_matches {actual expected} {
    set actual_segments [path_segments $actual]
    set expected_segments [path_segments $expected]
    set actual_count [llength $actual_segments]
    set expected_count [llength $expected_segments]
    if {$expected_count == 0 || $actual_count < $expected_count} {
        return 0
    }
    set tail_start [expr {$actual_count - $expected_count}]
    return [expr {
        [lrange $actual_segments $tail_start end] eq $expected_segments
    }]
}

proc ::stage1::select_fpga_device_record {device_records} {
    variable expected_fpga_part
    set matches {}
    foreach record $device_records {
        foreach required {object name part} {
            if {![dict exists $record $required]} {
                error "Device record is missing $required: $record"
            }
        }
        # JTAG reports the silicon die, without package or speed grade.
        # A fully qualified part, when supplied, must still match exactly.
        set observed_part [string tolower [dict get $record part]]
        if {$observed_part eq $expected_fpga_part ||
            $observed_part eq {xc7z020}} {
            lappend matches $record
        }
    }
    return [require_single $matches \
        "programmable $expected_fpga_part FPGA device"]
}

proc ::stage1::logical_probe_index {probe_name} {
    if {[regexp {(^|/)probe([0-9]+)(_1)?$} \
            $probe_name -> separator index logical_suffix]} {
        return [expr {$index + 0}]
    }
    return -1
}

proc ::stage1::build_logical_probe_map {probe_records probe_widths} {
    if {[expr {[llength $probe_widths] % 2}] != 0} {
        error "Logical probe-width contract is malformed: $probe_widths"
    }
    array set expected_width $probe_widths
    set mapping [dict create]

    foreach record $probe_records {
        foreach required {object name width} {
            if {![dict exists $record $required]} {
                error "Probe record is missing $required: $record"
            }
        }
        set index [logical_probe_index [dict get $record name]]
        if {$index < 0} {
            continue
        }
        if {![info exists expected_width($index)]} {
            error "Unexpected logical probe$index for selected ILA core"
        }
        if {[dict exists $mapping $index]} {
            error "Duplicate logical probe$index objects: \
[dict get $mapping $index] and [dict get $record object]"
        }
        set width [dict get $record width]
        if {![string is integer -strict $width] ||
            $width != $expected_width($index)} {
            error "Logical probe$index width mismatch: \
$width != $expected_width($index)"
        }
        dict set mapping $index [dict get $record object]
    }

    foreach {index width} $probe_widths {
        if {![dict exists $mapping $index]} {
            error "Missing logical probe$index width $width"
        }
    }
    set expected_count [expr {[llength $probe_widths] / 2}]
    if {[dict size $mapping] != $expected_count} {
        error "Logical probe map count mismatch: \
[dict size $mapping] != $expected_count"
    }
    return $mapping
}

proc ::stage1::select_ila_records {ila_records profile} {
    set selected [dict create]
    foreach role [profile_core_roles $profile] {
        set contract [core_contract $profile $role]
        set expected_suffix [dict get $contract cell_name_suffix]
        set matches {}
        foreach record $ila_records {
            foreach required {object name cell_name probes} {
                if {![dict exists $record $required]} {
                    error "ILA record is missing $required: $record"
                }
            }
            if {[cell_name_matches \
                    [dict get $record cell_name] $expected_suffix]} {
                lappend matches $record
            }
        }
        set record [require_single $matches \
            "$role ILA with CELL_NAME suffix $expected_suffix"]
        if {[catch {
            set mapping [build_logical_probe_map \
                [dict get $record probes] \
                [dict get $contract probe_widths]]
        } mapping_error]} {
            error "ILA [dict get $record object] $role probe identity failed: \
$mapping_error"
        }
        dict set record logical_probe_map $mapping
        dict set record core_role $role
        dict set selected $role $record
    }
    if {[llength $ila_records] != [dict size $selected]} {
        error "Hardware ILA inventory contains an unexpected core: \
observed=[llength $ila_records] expected=[dict size $selected]"
    }
    return $selected
}

proc ::stage1::select_ila_record {ila_records profile role} {
    set records [select_ila_records $ila_records $profile]
    return [dict get $records $role]
}

proc ::stage1::runtime_device_records {} {
    set records {}
    foreach device [get_hw_devices] {
        lappend records [dict create \
            object $device \
            name [get_property NAME $device] \
            part [get_property PART $device]]
    }
    return $records
}

proc ::stage1::runtime_probe_records {ila} {
    set records {}
    foreach probe [get_hw_probes -of_objects $ila] {
        lappend records [dict create \
            object $probe \
            name [get_property NAME $probe] \
            width [get_property WIDTH $probe]]
    }
    return $records
}

proc ::stage1::runtime_ila_records {device} {
    set records {}
    foreach ila [get_hw_ilas -of_objects $device] {
        lappend records [dict create \
            object $ila \
            name [get_property NAME $ila] \
            cell_name [get_property CELL_NAME $ila] \
            probes [runtime_probe_records $ila]]
    }
    return $records
}

proc ::stage1::require_file_readback {device property expected_path} {
    set observed_path [string trim [get_property $property $device]]
    if {$observed_path eq {}} {
        error "$property readback is empty after file binding"
    }
    set normalized_expected [file normalize $expected_path]
    set normalized_observed [file normalize $observed_path]
    if {![string equal -nocase \
            $normalized_observed $normalized_expected]} {
        error "$property readback mismatch after file binding: \
$normalized_observed != $normalized_expected"
    }
    return $normalized_observed
}

proc ::stage1::reset_session_state {} {
    variable manager_open
    variable target_open
    set manager_open 0
    set target_open 0
}

proc ::stage1::close_bound_hardware {} {
    variable manager_open
    variable target_open
    if {$target_open} {
        catch {close_hw_target}
        set target_open 0
    }
    if {$manager_open} {
        catch {close_hw_manager}
        set manager_open 0
    }
}

proc ::stage1::open_bound_hardware {
    bit_path ltx_path profile hw_server_url
} {
    variable manager_open
    variable target_open

    profile_core_roles $profile
    foreach {label path} [list BIT $bit_path LTX $ltx_path] {
        if {[string trim $path] eq {}} {
            error "Accepted $label path is empty"
        }
        set normalized [file normalize $path]
        if {![file isfile $normalized]} {
            error "Accepted $label is missing: $normalized"
        }
        set normalized_path($label) $normalized
    }

    reset_session_state
    open_hw_manager
    set manager_open 1
    connect_hw_server -url $hw_server_url
    open_hw_target
    set target_open 1

    set device_record [select_fpga_device_record [runtime_device_records]]
    set device [dict get $device_record object]

    # These assignments bind metadata only. This procedure never programs,
    # resets the device, or arms an ILA.
    set_property PROGRAM.FILE $normalized_path(BIT) $device
    set_property PROBES.FILE $normalized_path(LTX) $device
    set_property FULL_PROBES.FILE $normalized_path(LTX) $device
    refresh_hw_device $device

    set bit_readback [require_file_readback \
        $device PROGRAM.FILE $normalized_path(BIT)]
    set probes_readback [require_file_readback \
        $device PROBES.FILE $normalized_path(LTX)]
    set full_probes_readback [require_file_readback \
        $device FULL_PROBES.FILE $normalized_path(LTX)]
    set ila_records [select_ila_records \
        [runtime_ila_records $device] $profile]

    puts "STAGE2I_FPGA_DEVICE_OBJECT=$device"
    puts "STAGE2I_IMPLEMENTATION_PROFILE=$profile"
    puts "STAGE2I_BIT_BINDING_PATH=$normalized_path(BIT)"
    puts "STAGE2I_BIT_PROGRAM_FILE_READBACK=$bit_readback"
    puts "STAGE2I_LTX_BINDING_PATH=$normalized_path(LTX)"
    puts "STAGE2I_LTX_PROBES_FILE_READBACK=$probes_readback"
    puts "STAGE2I_LTX_FULL_PROBES_FILE_READBACK=$full_probes_readback"
    foreach role [profile_core_roles $profile] {
        set record [dict get $ila_records $role]
        puts "STAGE2I_ILA_CORE_ROLE=$role"
        puts "STAGE2I_ILA_OBJECT=[dict get $record object]"
        puts "STAGE2I_ILA_CELL_NAME=[dict get $record cell_name]"
        puts "STAGE2I_ILA_LOGICAL_PROBE_COUNT=[dict size [dict get $record logical_probe_map]]"
    }
    puts "STAGE2I_BIT_LTX_BINDING_PASS"
    puts "STAGE2I_ILA_IDENTITY_PASS"

    return [dict create \
        profile $profile \
        bit_path $normalized_path(BIT) \
        ltx_path $normalized_path(LTX) \
        device_record $device_record \
        ila_records $ila_records]
}

proc ::stage1::static_compile {additional_procs} {
    set procedures [concat [lsort [info procs ::stage1::*]] $additional_procs]
    foreach procedure $procedures {
        if {![info complete [info body $procedure]]} {
            error "$procedure Tcl body is incomplete"
        }
        if {[catch {
            tcl::unsupported::disassemble proc $procedure
        } compile_error]} {
            error "$procedure Tcl compilation failed: $compile_error"
        }
    }
}
