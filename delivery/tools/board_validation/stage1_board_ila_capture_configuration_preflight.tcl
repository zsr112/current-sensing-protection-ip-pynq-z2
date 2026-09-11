# Host-only Stage2I ILA capture-configuration preflight.
#
# The script binds the exact BIT/LTX metadata and validates property plans for
# every capture mode supported by the selected profile. It never programs,
# arms, waits for, uploads, or exports a capture.

set script_directory [file dirname [file normalize [info script]]]
source [file join $script_directory stage1_board_ila_common.tcl]
source [file join \
    $script_directory stage1_board_ila_capture_configuration.tcl]

proc execute_capture_configuration_preflight {} {
    global options bit_path ltx_path

    set preflight_status [catch {
        set binding [::stage1::open_bound_hardware \
            $bit_path $ltx_path $options(-profile) \
            $options(-hw_server_url)]
        set ila_records [dict get $binding ila_records]
        set target [current_hw_target]

        foreach mode [::stage1::capture_config::capture_modes_for_profile \
                $options(-profile)] {
            set role [::stage1::capture_config::capture_mode_core_role $mode]
            set ila_record [dict get $ila_records $role]
            set ila [dict get $ila_record object]
            set probe_map [dict get $ila_record logical_probe_map]
            set plan [::stage1::capture_config::build_runtime_plan \
                $options(-profile) $mode $target $ila $probe_map \
                $options(-target_frequency_hz)]
            ::stage1::capture_config::log_plan $mode $plan
            ::stage1::capture_config::validate_plan $plan
            puts "STAGE2I_ILA_CONFIGURATION_MODE_PLAN_PASS mode=$mode core_role=$role property_count=[llength $plan]"
        }

        puts "STAGE2I_ILA_CONFIGURATION_PREFLIGHT_CAPTURE_TRIGGER_WRITE_COUNT=0"
        puts "STAGE2I_ILA_CONFIGURATION_PREFLIGHT_NO_CAPTURE_TRIGGER_WRITE_PASS"
        puts "STAGE2I_ILA_CAPTURE_CONFIGURATION_PREFLIGHT_PASS"
        puts "PROFILE=$options(-profile)"
        puts "BIT_IDENTITY_INPUT=$bit_path"
        puts "LTX_IDENTITY_INPUT=$ltx_path"
    } preflight_error preflight_options]

    ::stage1::close_bound_hardware
    if {$preflight_status != 0} {
        puts stderr \
            "STAGE2I_ILA_CAPTURE_CONFIGURATION_PREFLIGHT_FAILED: $preflight_error"
        return -options $preflight_options $preflight_error
    }
}

if {[info exists ::stage1_configuration_preflight_library_only] &&
    $::stage1_configuration_preflight_library_only} {
    return
}

array set options {
    -bit {}
    -ltx {}
    -profile {}
    -hw_server_url {localhost:3121}
    -target_frequency_hz {1000000}
    -static_check {0}
}

if {[expr {[llength $argv] % 2}] != 0} {
    error "Arguments must be key/value pairs: $argv"
}
foreach {name value} $argv {
    if {![info exists options($name)]} {
        error "Unknown argument: $name"
    }
    set options($name) $value
}
foreach required {-bit -ltx -profile} {
    if {$options($required) eq {}} {
        error "Missing required argument: $required"
    }
}
if {$options(-static_check) ni {0 1}} {
    error "-static_check must be 0 or 1"
}
if {![string is integer -strict $options(-target_frequency_hz)] ||
    $options(-target_frequency_hz) <= 0} {
    error "-target_frequency_hz must be a positive integer"
}
::stage1::capture_config::capture_modes_for_profile $options(-profile)

set bit_path [file normalize $options(-bit)]
set ltx_path [file normalize $options(-ltx)]
foreach {label path} [list BIT $bit_path LTX $ltx_path] {
    if {![file isfile $path]} {
        error "Accepted $label is missing: $path"
    }
}

if {$options(-static_check)} {
    ::stage1::static_compile {execute_capture_configuration_preflight}
    puts "STAGE2I_ILA_CAPTURE_CONFIGURATION_PREFLIGHT_STATIC_CHECK_PASS"
    puts "PROFILE=$options(-profile)"
    puts "BIT=$bit_path"
    puts "LTX=$ltx_path"
    return
}

execute_capture_configuration_preflight
