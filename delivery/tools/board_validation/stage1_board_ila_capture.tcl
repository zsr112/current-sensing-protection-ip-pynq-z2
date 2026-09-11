# Capture one explicitly selected Stage2I System ILA window.
#
# The caller supplies the exact profile, BIT, LTX, core role, and capture mode.
# This script never programs or resets the FPGA and never selects the first ILA.

set script_directory [file dirname [file normalize [info script]]]
source [file join $script_directory stage1_board_ila_common.tcl]
source [file join \
    $script_directory stage1_board_ila_capture_configuration.tcl]

proc apply_configuration_plan {plan} {
    ::stage1::capture_config::validate_plan $plan
    foreach item $plan {
        if {[dict get $item action] ne {SET}} {
            continue
        }
        set property [dict get $item property]
        set desired [dict get $item desired]
        set object [dict get $item object]
        set type [dict get $item type]
        set_property $property $desired $object
        set observed [get_property $property $object]
        if {![::stage1::capture_config::property_values_equal \
                $type $observed $desired]} {
            error "ILA property verification failed: \
$property observed=$observed desired=$desired"
        }
        puts "STAGE2I_ILA_PROPERTY_SET_VERIFIED=$property"
    }
}

proc cleanup_capture_files {} {
    global output_path metadata_path partial_output_path
    global output_created metadata_created partial_created

    if {$metadata_created && [file exists $metadata_path]} {
        file delete -force -- $metadata_path
    }
    if {$output_created && [file exists $output_path]} {
        file delete -force -- $output_path
    }
    if {$partial_created && [file exists $partial_output_path]} {
        file delete -force -- $partial_output_path
    }
}

proc execute_capture {} {
    global options bit_path ltx_path output_path metadata_path
    global partial_output_path output_created metadata_created partial_created
    global capture_stage

    set output_created 0
    set metadata_created 0
    set partial_created 0
    set capture_stage OPEN_AND_BIND

    set capture_status [catch {
        set binding [::stage1::open_bound_hardware \
            $bit_path $ltx_path $options(-profile) \
            $options(-hw_server_url)]
        set device_record [dict get $binding device_record]
        set ila_record [dict get \
            [dict get $binding ila_records] $options(-core_role)]
        set ila [dict get $ila_record object]
        set probe_map [dict get $ila_record logical_probe_map]
        set target [current_hw_target]

        set capture_stage REPORT_AND_PLAN_CONFIGURATION
        set configuration_plan \
            [::stage1::capture_config::build_runtime_plan \
                $options(-profile) $options(-mode) $target $ila $probe_map \
                $options(-target_frequency_hz)]
        ::stage1::capture_config::log_plan \
            $options(-mode) $configuration_plan
        ::stage1::capture_config::validate_plan $configuration_plan

        set capture_stage APPLY_AND_VERIFY_CONFIGURATION
        apply_configuration_plan $configuration_plan
        set observed_target_frequency \
            [get_property PARAM.FREQUENCY $target]
        if {![::stage1::capture_config::values_equal \
                $observed_target_frequency \
                $options(-target_frequency_hz)]} {
            error "JTAG target frequency mismatch: $observed_target_frequency"
        }

        set capture_stage ARM
        if {[::stage1::capture_config::mode_is_trigger_now \
                $options(-mode)]} {
            run_hw_ila -trigger_now $ila
        } else {
            run_hw_ila $ila
        }
        puts "STAGE2I_ILA_ARMED mode=$options(-mode) core_role=$options(-core_role)"

        set capture_stage WAIT
        wait_on_hw_ila $ila

        set capture_stage UPLOAD
        upload_hw_ila_data $ila

        set capture_stage REQUIRE_UNIQUE_ILA_DATA
        set data [::stage1::require_single \
            [get_hw_ila_data -of_objects $ila] {uploaded ILA data}]

        set capture_stage EXPORT_PARTIAL_CSV
        set output_dir [file dirname $output_path]
        if {![file isdirectory $output_dir]} {
            file mkdir $output_dir
        }
        set partial_created 1
        write_hw_ila_data -csv_file $partial_output_path $data

        set capture_stage VERIFY_PARTIAL_CSV
        if {![file isfile $partial_output_path] ||
            [file size $partial_output_path] <= 0} {
            error "Vivado did not create a nonempty capture CSV"
        }

        set capture_stage SEAL_CAPTURE_CSV
        file rename -- $partial_output_path $output_path
        set partial_created 0
        set output_created 1
        if {![file isfile $output_path] || [file size $output_path] <= 0} {
            error "Sealed capture CSV is missing or empty"
        }

        set capture_stage WRITE_METADATA
        set metadata [open $metadata_path {WRONLY CREAT EXCL}]
        set metadata_created 1
        try {
            puts $metadata "field\tvalue"
            puts $metadata "implementation_profile\t$options(-profile)"
            puts $metadata "core_role\t$options(-core_role)"
            puts $metadata "capture_mode\t$options(-mode)"
            puts $metadata "output_path\t$output_path"
            puts $metadata "bit_path\t$bit_path"
            puts $metadata "ltx_path\t$ltx_path"
            puts $metadata "device\t[dict get $device_record name]"
            puts $metadata "device_part\t[dict get $device_record part]"
            puts $metadata "ila_name\t[dict get $ila_record name]"
            puts $metadata \
                "ila_cell_name\t[dict get $ila_record cell_name]"
            puts $metadata \
                "ila_capture_mode\t[get_property CONTROL.CAPTURE_MODE $ila]"
            puts $metadata \
                "ila_data_depth\t[get_property CONTROL.DATA_DEPTH $ila]"
            puts $metadata \
                "ila_trigger_position\t[get_property CONTROL.TRIGGER_POSITION $ila]"
            puts $metadata \
                "ila_window_count\t[get_property CONTROL.WINDOW_COUNT $ila]"
            puts $metadata \
                "ila_logical_probe_count\t[dict size $probe_map]"
            puts $metadata "probe_csv_radix\tBINARY"
            puts $metadata \
                "target_frequency_hz\t$observed_target_frequency"
            puts $metadata \
                "configuration_property_count\t[llength $configuration_plan]"
            puts $metadata "fpga_programming_calls\t0"
            puts $metadata "device_reset_calls\t0"
            puts $metadata "automatic_retries\t0"
        } finally {
            close $metadata
        }

        set capture_stage FINAL_OUTPUT_VERIFY
        if {![file isfile $metadata_path] ||
            [file size $metadata_path] <= 0} {
            error "Capture metadata is missing or empty"
        }
        puts "STAGE2I_ILA_CAPTURE_PASS"
        puts "PROFILE=$options(-profile)"
        puts "CORE_ROLE=$options(-core_role)"
        puts "CAPTURE_MODE=$options(-mode)"
        puts "CAPTURE_CSV=$output_path"
        puts "CAPTURE_METADATA=$metadata_path"
    } capture_error capture_options]

    ::stage1::close_bound_hardware
    if {$capture_status != 0} {
        cleanup_capture_files
        puts stderr "STAGE2I_ILA_CAPTURE_FAILURE_STAGE=$capture_stage"
        puts stderr "STAGE2I_ILA_CAPTURE_FAILED: $capture_error"
        return -options $capture_options $capture_error
    }
}

if {[info exists ::stage1_capture_library_only] &&
    $::stage1_capture_library_only} {
    return
}

array set options {
    -bit {}
    -ltx {}
    -profile {}
    -core_role {}
    -output {}
    -mode {}
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
foreach required {-bit -ltx -profile -core_role -output -mode} {
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
set mode_role [::stage1::capture_config::capture_mode_core_role \
    $options(-mode)]
if {$mode_role ne $options(-core_role)} {
    error "Capture mode $options(-mode) requires core role $mode_role"
}
::stage1::core_contract $options(-profile) $options(-core_role)

set bit_path [file normalize $options(-bit)]
set ltx_path [file normalize $options(-ltx)]
set output_path [file normalize $options(-output)]
set metadata_path "[file rootname $output_path].metadata.tsv"
set partial_output_path "${output_path}.partial.[pid]"

foreach {label path} [list BIT $bit_path LTX $ltx_path] {
    if {![file isfile $path]} {
        error "Accepted $label is missing: $path"
    }
}
foreach candidate [list $output_path $metadata_path $partial_output_path] {
    if {[file exists $candidate]} {
        error "Refusing to overwrite capture output: $candidate"
    }
}

if {$options(-static_check)} {
    ::stage1::static_compile \
        {apply_configuration_plan cleanup_capture_files execute_capture}
    puts "STAGE2I_ILA_CAPTURE_STATIC_CHECK_PASS"
    puts "PROFILE=$options(-profile)"
    puts "CORE_ROLE=$options(-core_role)"
    puts "BIT=$bit_path"
    puts "LTX=$ltx_path"
    puts "MODE=$options(-mode)"
    return
}

execute_capture
