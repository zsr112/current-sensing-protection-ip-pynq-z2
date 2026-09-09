# One bounded, coordinated source/destination capture. Preserve partial evidence.
set directory [file dirname [file normalize [info script]]]
set ::stage1_capture_library_only 1
source [file join $directory stage1_board_ila_capture.tcl]
unset ::stage1_capture_library_only

proc write_new {path content} {
    set stream [open $path {WRONLY CREAT EXCL}]
    try { puts $stream $content } finally { close $stream }
}

proc configure_role {record role mode output} {
    set profile READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
    set ila [dict get $record object]
    set probes [dict get $record logical_probe_map]
    set base_mode $mode
    if {$mode in {destination_reset_wait destination_armed}} {
        set base_mode destination_fault_latched
    }
    set plan [::stage1::capture_config::build_runtime_plan \
        $profile $base_mode [current_hw_target] $ila $probes 1000000]
    ::stage1::capture_config::validate_plan $plan
    apply_configuration_plan $plan
    if {$mode in {destination_reset_wait destination_armed}} {
        foreach {index width} [dict get [::stage1::core_contract $profile $role] probe_widths] {
            set value [::stage1::capture_config::wildcard_compare $width]
            if {$index == 7} {
                set value [expr {$mode eq {destination_reset_wait} ? {eq4'b0010} : {eq4'b0000}}]
            }
            set probe [dict get $probes $index]
            set_property TRIGGER_COMPARE_VALUE $value $probe
            if {![::stage1::capture_config::values_equal [get_property TRIGGER_COMPARE_VALUE $probe] $value]} {
                error "Custom trigger verification failed for $role probe$index"
            }
        }
    }
    set probe_text "index\tobject\twidth\tradix"
    set trigger_text "scope\tproperty\tvalue"
    foreach property {CONTROL.DATA_DEPTH CONTROL.TRIGGER_POSITION CONTROL.WINDOW_COUNT CONTROL.CAPTURE_MODE CONTROL.TRIGGER_MODE CONTROL.TRIGGER_CONDITION} {
        append trigger_text "\nila\t$property\t[get_property $property $ila]"
    }
    append trigger_text "\nrequest\tmode\t$mode"
    append trigger_text "\ntarget\tfrequency_hz\t[get_property PARAM.FREQUENCY [current_hw_target]]"
    foreach index [lsort -integer [dict keys $probes]] {
        set probe [dict get $probes $index]
        append probe_text "\n$index\t$probe\t[get_property WIDTH $probe]\t[get_property DISPLAY_RADIX $probe]"
        append trigger_text "\nprobe$index\tTRIGGER_COMPARE_VALUE\t[get_property TRIGGER_COMPARE_VALUE $probe]"
    }
    write_new [file join $output ${role}.probes.tsv] $probe_text
    write_new [file join $output ${role}.trigger.tsv] $trigger_text
    write_new [file join $output ${role}.properties.txt] [report_property -all -return_string $ila]
    if {[string match *_trigger_now $mode]} {
        run_hw_ila -trigger_now $ila
    } else {
        run_hw_ila $ila
    }
    return $ila
}

if {[info exists ::stage2_pair_library_only] && $::stage2_pair_library_only} { return }
if {[llength $argv] != 6} {
    error "Expected BIT LTX output source-mode destination-mode execution-ID"
}
lassign $argv bit ltx output source_mode destination_mode execution_id
set profile READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
set outcome [catch {
    set binding [::stage1::open_bound_hardware $bit $ltx $profile localhost:3121]
    set ilas {}
    foreach role {source destination} mode [list $source_mode $destination_mode] {
        set record [dict get $binding ila_records $role]
        dict set ilas $role [configure_role $record $role $mode $output]
    }
    write_new [file join $output armed.txt] $execution_id
    puts "PAIR_ARMED=$execution_id"
    set deadline [expr {[clock milliseconds] + 180000}]
    while {![file exists [file join $output collect.txt]]} {
        if {[clock milliseconds] >= $deadline} { error "Host action deadline exceeded" }
        after 100
    }
    foreach role {source destination} mode [list $source_mode $destination_mode] {
        set ila [dict get $ilas $role]
        # Vivado 2024.1 expresses this timeout in minutes, not seconds.
        wait_on_hw_ila -timeout 0.5 $ila
        upload_hw_ila_data $ila
        set data [::stage1::require_single [get_hw_ila_data -of_objects $ila] {ILA data}]
        set csv [file join $output ${role}.csv]
        if {[file exists $csv]} { error "Capture already exists: $csv" }
        write_hw_ila_data -csv_file $csv $data
        if {![file exists $csv] || [file size $csv] == 0} { error "Empty CSV: $role" }
        set metadata "field\tvalue"
        foreach {key value} [list \
            implementation_profile $profile core_role $role capture_mode $mode \
            execution_id $execution_id bit_path artifacts/protection_system.bit \
            ltx_path artifacts/protection_system.ltx \
            device_part [dict get $binding device_record part] \
            ila_cell_name [dict get $binding ila_records $role cell_name] \
            ila_logical_probe_count 8 probe_csv_radix BINARY \
            fpga_programming_calls 0 device_reset_calls 0 automatic_retries 0 \
            ila_data_depth [get_property CONTROL.DATA_DEPTH $ila] \
            ila_trigger_position [get_property CONTROL.TRIGGER_POSITION $ila]] {
            append metadata "\n$key\t$value"
        }
        write_new [file join $output ${role}.metadata.tsv] $metadata
    }
    write_new [file join $output capture_status.txt] PASS
    puts "PAIR_CAPTURE=PASS"
} message options]
::stage1::close_bound_hardware
if {$outcome} {
    write_new [file join $output failure.txt] "FAIL: $message\n[dict get $options -errorinfo]"
    puts stderr "PAIR_CAPTURE=FAIL: $message"
    exit 1
}
exit 0
