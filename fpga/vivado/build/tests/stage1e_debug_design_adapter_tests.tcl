# Source-only tests for the Stage 1E debug-topology adapter.
#
# The backend below is an in-memory Vivado model.  The suite verifies context
# rejection and topology/readback behavior without invoking Vivado, acquiring
# lifecycle ownership, validating/saving a BD, running Stage 1D mutation, or
# generating an FPGA artifact.

namespace eval ::stage1e::debug_design_adapter_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_root {}
    variable invocation_log {}
    variable forbidden_count 0
    variable current_project project::stage1e_design
    variable current_bd protection_system
    variable properties [dict create]
    variable ipdefs [dict create]
    variable cells [dict create]
    variable pins [dict create]
    variable intf_pins [dict create]
    variable scalar_net_by_object [dict create]
    variable intf_net_by_object [dict create]
    variable net_objects [dict create]
    variable forced_vlnv {}
    variable forced_widths [dict create]
    variable force_probe_width_parameters_disabled 0
    variable missing_created_pins {}
    variable net_sequence 0
}

set stage1e_debug_test_dir [file normalize [file dirname [info script]]]
set stage1e_debug_adapter [file normalize [file join \
    $stage1e_debug_test_dir .. adapters stage1e_debug_design.tcl]]

# Sourcing the adapter must define procedures only.  The backend is replaced
# immediately afterward with the isolated mock.
source $stage1e_debug_adapter
rename ::stage1e::debug_design::backend::invoke \
    ::stage1e::debug_design::backend::_production_invoke
proc ::stage1e::debug_design::backend::invoke {command arguments} {
    return [::stage1e::debug_design_adapter_tests::mock_invoke \
        $command $arguments]
}

proc ::stage1e::debug_design_adapter_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::debug_design_adapter_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::debug_design_adapter_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::debug_design_adapter_tests::assert_status {
    result
    expected
    message
} {
    if {[catch {dict size $result} dictionary_error]} {
        fail "$message is not a dictionary: $dictionary_error"
    }
    if {[dict get $result status] ne $expected} {
        fail "$message: expected=<$expected> actual=<[dict get $result status]> errors=<[dict get $result errors]>"
    }
}

proc ::stage1e::debug_design_adapter_tests::first_error_code {result} {
    set errors [dict get $result errors]
    if {[llength $errors] == 0} {
        fail {Expected a structured error record.}
    }
    return [dict get [lindex $errors 0] code]
}

proc ::stage1e::debug_design_adapter_tests::run_case {name body} {
    variable pass_count
    variable fail_count
    set case_status [catch {uplevel 1 $body} case_error case_options]
    if {$case_status == 0} {
        incr pass_count
        puts "$name: PASS"
        return
    }
    incr fail_count
    puts stderr "$name: FAIL: $case_error"
    if {[dict exists $case_options -errorinfo]} {
        puts stderr [dict get $case_options -errorinfo]
    }
}

proc ::stage1e::debug_design_adapter_tests::temporary_base {} {
    foreach variable_name {STAGE1E_TEST_TEMP_ROOT TEMP TMP TMPDIR} {
        if {[info exists ::env($variable_name)] &&
            [string trim $::env($variable_name)] ne {}} {
            set canonical [string map {\\ /} $::env($variable_name)]
            if {$::tcl_platform(platform) eq {windows} &&
                [regexp {^[A-Za-z]:/} $canonical]} {
                set canonical "//?/$canonical"
            }
            return [file normalize $canonical]
        }
    }
    error {No external temporary directory is available for debug tests.}
}

proc ::stage1e::debug_design_adapter_tests::prepare_suite {} {
    variable test_root
    set test_root [file normalize [file join [temporary_base] \
        "stage1e_debug_design_tests_[pid]_[clock clicks]"]]
    if {![string match {stage1e_debug_design_tests_*} \
        [file tail $test_root]]} {
        error "Unsafe debug test root: $test_root"
    }
    file mkdir $test_root
}

proc ::stage1e::debug_design_adapter_tests::safe_cleanup {} {
    variable test_root
    if {$test_root eq {} || ![file exists $test_root]} {
        return
    }
    if {![string match {stage1e_debug_design_tests_*} \
        [file tail $test_root]]} {
        error "Refusing unsafe debug test cleanup: $test_root"
    }
    file delete -force -- $test_root
}

proc ::stage1e::debug_design_adapter_tests::probe_widths {} {
    return {1 1 12 12 1 1 1 1 8 8 4 1}
}

proc ::stage1e::debug_design_adapter_tests::reset_mock {} {
    variable invocation_log
    variable forbidden_count
    variable current_project
    variable current_bd
    variable properties
    variable ipdefs
    variable cells
    variable pins
    variable intf_pins
    variable scalar_net_by_object
    variable intf_net_by_object
    variable net_objects
    variable forced_vlnv
    variable forced_widths
    variable force_probe_width_parameters_disabled
    variable missing_created_pins
    variable net_sequence
    set invocation_log {}
    set forbidden_count 0
    set current_project project::stage1e_design
    set current_bd protection_system
    set properties [dict create]
    set ipdefs [dict create]
    set cells [dict create]
    set pins [dict create]
    set intf_pins [dict create]
    set scalar_net_by_object [dict create]
    set intf_net_by_object [dict create]
    set net_objects [dict create]
    set forced_vlnv {}
    set forced_widths [dict create]
    set force_probe_width_parameters_disabled 0
    set missing_created_pins {}
    set net_sequence 0

    dict set properties $current_project NAME stage1e_design
    dict set properties $current_project DIRECTORY \
        [file normalize [file join [temporary_base] stage1e_mock_project]]
    dict set properties $current_project PART xc7z020clg400-1
    dict set properties $current_project BOARD_PART \
        tul.com.tw:pynq-z2:part0:1.0

    set ila_vlnv xilinx.com:ip:system_ila:1.1
    dict set ipdefs $ila_vlnv ipdef::system_ila
    dict set properties ipdef::system_ila VLNV $ila_vlnv

    # Existing base-design cells and pins.
    foreach path {
        processing_system7_0/FCLK_CLK0
        proc_sys_reset_0/peripheral_aresetn
        protection_ip_axi_lite_0/ARESETN
        protection_ip_axi_lite_0/adc_sample_valid
        protection_ip_axi_lite_0/adc_sample_ch1
        protection_ip_axi_lite_0/adc_sample_ch2
        protection_ip_axi_lite_0/pwm_raw
        protection_ip_axi_lite_0/pwm_out
        protection_ip_axi_lite_0/fault_valid
        protection_ip_axi_lite_0/fault_latched
        protection_ip_axi_lite_0/fault_code
        protection_ip_axi_lite_0/fault_code_latched
        protection_ip_axi_lite_0/fsm_state
        protection_ip_axi_lite_0/adc_sample_ready
    } {
        add_pin $path
    }
    dict set properties pin::proc_sys_reset_0/peripheral_aresetn \
        CONFIG.POLARITY ACTIVE_LOW
    set width_map [dict create \
        protection_ip_axi_lite_0/adc_sample_ch1 12 \
        protection_ip_axi_lite_0/adc_sample_ch2 12 \
        protection_ip_axi_lite_0/fault_code 8 \
        protection_ip_axi_lite_0/fault_code_latched 8 \
        protection_ip_axi_lite_0/fsm_state 4]
    dict for {path width} $width_map {
        dict set properties pin::$path LEFT [expr {$width - 1}]
        dict set properties pin::$path RIGHT 0
    }
    foreach path {
        protection_ip_axi_lite_0/S_AXI
        smartconnect_0/M00_AXI
    } {
        add_intf_pin $path
    }
    # The base design's existing clock/reset and AXI nets.
    set clock_net [new_net dbg_existing_clock]
    connect_scalar_objects $clock_net \
        pin::processing_system7_0/FCLK_CLK0
    set reset_net [new_net dbg_existing_reset]
    connect_scalar_objects $reset_net \
        pin::proc_sys_reset_0/peripheral_aresetn pin::protection_ip_axi_lite_0/ARESETN
    foreach path {
        protection_ip_axi_lite_0/adc_sample_valid
        protection_ip_axi_lite_0/adc_sample_ch1
        protection_ip_axi_lite_0/adc_sample_ch2
    } {
        set net [new_net "existing_$path"]
        connect_scalar_objects $net pin::$path
    }
    set axi_net [new_intf_net axi_monitor_existing]
    connect_intf_objects $axi_net \
        intfpin::protection_ip_axi_lite_0/S_AXI \
        intfpin::smartconnect_0/M00_AXI
}

proc ::stage1e::debug_design_adapter_tests::add_pin {path} {
    variable pins
    variable properties
    set object pin::$path
    dict set pins $path $object
    if {![dict exists $properties $object LEFT]} {
        dict set properties $object LEFT {}
        dict set properties $object RIGHT {}
    }
    return $object
}

proc ::stage1e::debug_design_adapter_tests::add_intf_pin {path} {
    variable intf_pins
    set object intfpin::$path
    dict set intf_pins $path $object
    return $object
}

proc ::stage1e::debug_design_adapter_tests::new_net {name} {
    variable net_objects
    set object net::$name
    dict set net_objects $object $name
    return $object
}

proc ::stage1e::debug_design_adapter_tests::new_intf_net {name} {
    variable net_objects
    set object intfnet::$name
    dict set net_objects $object $name
    return $object
}

proc ::stage1e::debug_design_adapter_tests::connect_scalar_objects {net args} {
    variable scalar_net_by_object
    foreach object $args {
        dict set scalar_net_by_object $object $net
    }
}

proc ::stage1e::debug_design_adapter_tests::connect_intf_objects {net args} {
    variable intf_net_by_object
    foreach object $args {
        dict set intf_net_by_object $object $net
    }
}

proc ::stage1e::debug_design_adapter_tests::lookup_named {dictionary arguments} {
    set names {}
    foreach argument $arguments {
        if {![string match {-*} $argument]} {
            lappend names $argument
        }
    }
    if {[llength $names] == 0} {
        return [dict values $dictionary]
    }
    set name [lindex $names end]
    if {[dict exists $dictionary $name]} {
        return [list [dict get $dictionary $name]]
    }
    return {}
}

proc ::stage1e::debug_design_adapter_tests::mock_invoke {command arguments} {
    variable invocation_log
    variable forbidden_count
    variable current_project
    variable current_bd
    variable properties
    variable ipdefs
    variable cells
    variable pins
    variable intf_pins
    variable scalar_net_by_object
    variable intf_net_by_object
    variable net_objects
    variable forced_vlnv
    variable forced_widths
    variable force_probe_width_parameters_disabled
    variable missing_created_pins
    variable net_sequence
    lappend invocation_log [linsert $arguments 0 $command]

    if {$command in {
        open_project create_project close_project create_bd_design
        open_bd_design close_bd_design validate_bd_design save_bd_design
        stage1d_controlled_stimulus::apply launch_runs synth_design
        opt_design place_design route_design write_bitstream
        write_hw_platform write_debug_probes export_hardware exit
    }} {
        incr forbidden_count
        error "Forbidden command invoked: $command"
    }

    switch -- $command {
        current_project { return $current_project }
        current_bd_design { return $current_bd }
        get_ipdefs {
            set requested [lindex $arguments end]
            if {[dict exists $ipdefs $requested]} {
                return [list [dict get $ipdefs $requested]]
            }
            return {}
        }
        get_property {
            set property [string toupper [lindex $arguments 0]]
            set object [lindex $arguments 1]
            if {$property eq {VLNV} && $forced_vlnv ne {} &&
                $object eq {ipdef::system_ila}} {
                return $forced_vlnv
            }
            if {$property eq {NAME} && [dict exists $net_objects $object]} {
                return [dict get $net_objects $object]
            }
            if {$property in {LEFT RIGHT} &&
                [dict exists $forced_widths $object]} {
                set width [dict get $forced_widths $object]
                if {$width == 1} {
                    return {}
                }
                if {$property eq {LEFT}} { return [expr {$width - 1}] }
                return 0
            }
            if {[dict exists $properties $object $property]} {
                return [dict get $properties $object $property]
            }
            return {}
        }
        get_bd_cells { return [lookup_named $cells $arguments] }
        get_bd_pins { return [lookup_named $pins $arguments] }
        get_bd_intf_pins { return [lookup_named $intf_pins $arguments] }
        get_bd_nets {
            if {[lsearch -exact $arguments -of_objects] >= 0} {
                set object [lindex $arguments end]
                if {[dict exists $scalar_net_by_object $object]} {
                    return [list [dict get $scalar_net_by_object $object]]
                }
                return {}
            }
            set names [lookup_named $net_objects $arguments]
            set result {}
            foreach object $names {
                if {[string match {net::*} $object]} { lappend result $object }
            }
            return $result
        }
        get_bd_intf_nets {
            if {[lsearch -exact $arguments -of_objects] >= 0} {
                set object [lindex $arguments end]
                if {[dict exists $intf_net_by_object $object]} {
                    return [list [dict get $intf_net_by_object $object]]
                }
                return {}
            }
            set names [lookup_named $net_objects $arguments]
            set result {}
            foreach object $names {
                if {[string match {intfnet::*} $object]} { lappend result $object }
            }
            return $result
        }
        create_bd_cell {
            set vlnv [lindex $arguments 3]
            set name [lindex $arguments 4]
            set object cell::$name
            dict set cells $name $object
            dict set properties $object VLNV $vlnv
            dict set properties $object CONFIG.C_MON_TYPE INTERFACE
            dict set properties $object CONFIG.C_PROBE_WIDTH_PROPAGATION AUTO
            dict set properties $object CONFIG.C_NUM_OF_PROBES 1
            dict set properties $object CONFIG.C_PROBE0_WIDTH 1
            add_pin $name/clk
            add_pin $name/resetn
            add_intf_pin $name/SLOT_0_AXI
            set default_probe $name/probe0
            if {$default_probe ni $missing_created_pins} {
                add_pin $default_probe
            }
            return $object
        }
        set_property {
            if {[lindex $arguments 0] ne {-dict}} {
                error "Unexpected set_property form: $arguments"
            }
            set property_dict [lindex $arguments 1]
            set object [lindex $arguments 2]
            dict for {property value} $property_dict {
                set property [string toupper $property]
                if {[regexp {^CONFIG\.C_PROBE([0-9]+)_WIDTH$} \
                    $property -> index]} {
                    set propagation AUTO
                    if {[dict exists $properties $object \
                        CONFIG.C_PROBE_WIDTH_PROPAGATION]} {
                        set propagation [dict get $properties $object \
                            CONFIG.C_PROBE_WIDTH_PROPAGATION]
                    }
                    if {$force_probe_width_parameters_disabled ||
                        $propagation ne {MANUAL}} {
                        continue
                    }
                    dict set properties $object $property $value
                    set cell_name [string range $object \
                        [string length {cell::}] end]
                    set pin pin::$cell_name/probe$index
                    if {$value == 1} {
                        dict set properties $pin LEFT {}
                        dict set properties $pin RIGHT {}
                    } else {
                        dict set properties $pin LEFT [expr {$value - 1}]
                        dict set properties $pin RIGHT 0
                    }
                    continue
                }
                dict set properties $object $property $value
                if {$property eq {CONFIG.C_NUM_OF_PROBES}} {
                    set cell_name [string range $object \
                        [string length {cell::}] end]
                    for {set index 0} {$index < $value} {incr index} {
                        set path $cell_name/probe$index
                        set width_property "CONFIG.C_PROBE${index}_WIDTH"
                        if {![dict exists $properties $object $width_property]} {
                            dict set properties $object $width_property 1
                        }
                        if {$path ni $missing_created_pins} {
                            add_pin $path
                        }
                    }
                }
            }
            return {}
        }
        create_bd_net {
            set name [lindex $arguments end]
            return [new_net $name]
        }
        connect_bd_net {
            set net_index [lsearch -exact $arguments -net]
            if {$net_index < 0} { error "Expected -net scalar connection" }
            set net [lindex $arguments [incr net_index]]
            foreach object [lrange $arguments [expr {$net_index + 1}] end] {
                connect_scalar_objects $net $object
            }
            return {}
        }
        connect_bd_intf_net {
            set objects {}
            foreach object $arguments {
                if {[string match {intfpin::*} $object]} { lappend objects $object }
            }
            if {[llength $objects] >= 2} {
                set existing {}
                foreach object $objects {
                    if {[dict exists $intf_net_by_object $object]} {
                        set existing [dict get $intf_net_by_object $object]
                        break
                    }
                }
                if {$existing eq {}} {
                    incr net_sequence
                    set existing [new_intf_net "debug_interface_$net_sequence"]
                }
                connect_intf_objects $existing {*}$objects
            }
            return {}
        }
        default { error "Unexpected mock Vivado command: $command $arguments" }
    }
}

proc ::stage1e::debug_design_adapter_tests::valid_context {name} {
    variable test_root
    variable current_project
    variable properties
    set execution_id STAGE1E-DEBUG-$name
    set workspace_root [file normalize [file join $test_root executions $name]]
    set evidence_dir [file join $workspace_root evidence]
    set project_directory [file join $workspace_root project]
    set project_path [file join $project_directory stage1e_design.xpr]
    set bd_path [file join $project_directory stage1e_design.srcs sources_1 bd protection_system protection_system.bd]
    file mkdir $evidence_dir
    file mkdir [file dirname $bd_path]
    set project_handle project::stage1e_design
    set project_identity [dict create \
        project_name stage1e_design \
        project_directory [file normalize $project_directory] \
        project_path [file normalize $project_path] \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0]
    set project_ownership [dict create \
        owner vivado_project execution_id $execution_id \
        project_handle $project_handle project_path [file normalize $project_path] \
        identity_verified 1 project_identity $project_identity]
    set bd_ownership [dict create \
        owner bd_flow execution_id $execution_id \
        project_path [file normalize $project_path] \
        bd_name protection_system bd_path [file normalize $bd_path] \
        opened 1 identity_verified 1 validated 0 saved 0]
    dict set properties $current_project DIRECTORY \
        [file normalize $project_directory]
    set probes {}
    set sources {
        protection_ip_axi_lite_0/ARESETN
        protection_ip_axi_lite_0/adc_sample_valid
        protection_ip_axi_lite_0/adc_sample_ch1
        protection_ip_axi_lite_0/adc_sample_ch2
        protection_ip_axi_lite_0/pwm_raw
        protection_ip_axi_lite_0/pwm_out
        protection_ip_axi_lite_0/fault_valid
        protection_ip_axi_lite_0/fault_latched
        protection_ip_axi_lite_0/fault_code
        protection_ip_axi_lite_0/fault_code_latched
        protection_ip_axi_lite_0/fsm_state
        protection_ip_axi_lite_0/adc_sample_ready
    }
    set widths [probe_widths]
    for {set index 0} {$index < 12} {incr index} {
        lappend probes [dict create index $index \
            source [lindex $sources $index] \
            probe system_ila_stage2b_0/probe$index \
            width [lindex $widths $index]]
    }
    return [dict create \
        context_schema_version stage1e-debug-design-context-v1 \
        operation stage1e::debug_design::apply phase BD_GENERATION \
        execution_id $execution_id \
        authorization [dict create \
            status AUTHORIZED authority controller_core \
            execution_id $execution_id \
            operation stage1e::debug_design::apply phase BD_GENERATION \
            capability bd_generation_enabled capability_enabled 1] \
        source_identity [dict create schema_version stage1e-source-identity-v1 \
            execution_id $execution_id git_commit [string repeat 1 40]] \
        environment_identity [dict create \
            schema_version stage1e-environment-identity-v1 \
            execution_id $execution_id vivado_version 2024.1 \
            part xc7z020clg400-1 board_part tul.com.tw:pynq-z2:part0:1.0] \
        configuration_identity [dict create \
            schema_version stage1e-configuration-identity-v1 \
            execution_id $execution_id sha256 [string repeat c 64]] \
        workspace_root $workspace_root evidence_dir $evidence_dir \
        project_ownership $project_ownership bd_ownership $bd_ownership \
        base_design_identity [dict create \
            schema_version stage1e-base-design-identity-v1 \
            producer_operation stage1e::base_design::apply \
            execution_id $execution_id project_path [file normalize $project_path] \
            bd_name protection_system bd_path [file normalize $bd_path] \
            topology_policy_sha256 [string repeat d 64] \
            policy_bundle_sha256 [string repeat e 64] \
            readback_sha256 [string repeat f 64] \
            identity_sha256 [string repeat a 64]] \
        debug_policy [dict create \
            schema_version stage1e-debug-policy-reference-v1 \
            policy_id stage1e_stage2b_debug_v1 \
            source_reference fpga/vivado/add_pynq_z2_stage2b_debug.tcl \
            sha256 [string repeat b 64] enabled 1 \
            clock_source processing_system7_0/FCLK_CLK0 \
            reset_source proc_sys_reset_0/peripheral_aresetn \
            reset_polarity ACTIVE_LOW \
            ready_observation_clock_domain ACLK \
            adc_src_clock_domain FCLK_CLK0 \
            destination_clock_domain FCLK_CLK0 \
            clocks_identical_in_current_profile 1 \
            acceptance_evidence_scope CURRENT_IDENTICAL_CLOCKS_ONLY \
            distinct_clock_debug_policy SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION \
            direct_async_ready_observation_as_cdc_proof 0] \
        system_ila_identity [dict create \
            schema_version stage1e-system-ila-identity-v1 \
            cell_name system_ila_stage2b_0 \
            vlnv xilinx.com:ip:system_ila:1.1 \
            properties [dict create \
                CONFIG.C_MON_TYPE MIX \
                CONFIG.C_PROBE_WIDTH_PROPAGATION MANUAL \
                CONFIG.C_NUM_MONITOR_SLOTS 1 \
                CONFIG.C_SLOT_0_INTF_TYPE xilinx.com:interface:aximm_rtl:1.0 \
                CONFIG.C_SLOT_0_AXI_PROTOCOL AXI4LITE \
                CONFIG.C_NUM_OF_PROBES 12 CONFIG.C_DATA_DEPTH 4096]] \
        monitor_interface_policy [dict create \
            schema_version stage1e-debug-monitor-interface-policy-v1 \
            target protection_ip_axi_lite_0/S_AXI \
            monitor system_ila_stage2b_0/SLOT_0_AXI \
            expected_net_members {\
                protection_ip_axi_lite_0/S_AXI smartconnect_0/M00_AXI}] \
        probe_schema [dict create \
            schema_version stage1e-debug-probe-schema-v1 probes $probes] \
        width_expectations [dict create \
            schema_version stage1e-debug-width-expectations-v1 widths $widths]]
}

proc ::stage1e::debug_design_adapter_tests::assert_no_forbidden {} {
    variable forbidden_count
    assert_equal 0 $forbidden_count {Forbidden command tripwire count}
}

proc ::stage1e::debug_design_adapter_tests::all_files {root} {
    set files {}
    foreach entry [glob -nocomplain -directory $root -- * .*] {
        if {[file tail $entry] in {. ..}} { continue }
        if {[file isdirectory $entry]} {
            foreach nested [all_files $entry] { lappend files $nested }
        } elseif {[file isfile $entry]} {
            lappend files $entry
        }
    }
    return $files
}

proc ::stage1e::debug_design_adapter_tests::run_all {} {
    variable invocation_log
    variable forced_widths
    variable force_probe_width_parameters_disabled
    variable missing_created_pins
    variable properties
    variable scalar_net_by_object

    run_case DEBUG_CONTEXT_VALID {
        reset_mock
        set context [valid_context context_valid]
        set result [::stage1e::debug_design::apply $context]
        assert_status $result PASS {Valid debug context status}
        assert_true [dict exists $result produced_identities \
            debug_design_identity] {Debug identity missing}
        assert_equal [dict get $context project_ownership] \
            [dict get $result ownership_records project_ownership] \
            {Project ownership changed}
        assert_equal [dict get $context bd_ownership] \
            [dict get $result ownership_records bd_ownership] \
            {BD ownership changed}
    }

    run_case DEBUG_SYSTEM_ILA_PRELOCK_CONFIGURATION {
        reset_mock
        set result [::stage1e::debug_design::apply \
            [valid_context prelock_configuration]]
        assert_status $result PASS {Pre-lock System ILA configuration status}
        set cell cell::system_ila_stage2b_0
        assert_equal MANUAL [dict get $properties $cell \
            CONFIG.C_PROBE_WIDTH_PROPAGATION] \
            {Native probe width propagation mode}
        assert_equal 12 [dict get $properties $cell CONFIG.C_NUM_OF_PROBES] \
            {System ILA probe count}
        foreach {index width} {2 12 3 12 8 8 9 8 10 4 11 1} {
            assert_equal $width [dict get $properties $cell \
                "CONFIG.C_PROBE${index}_WIDTH"] \
                "System ILA probe$index configured width"
        }

        set mode_index -1
        set enablement_index -1
        set widths_index -1
        set first_connection_index -1
        for {set index 0} {$index < [llength $invocation_log]} {incr index} {
            set invocation [lindex $invocation_log $index]
            set command [lindex $invocation 0]
            if {$command eq {set_property}} {
                set property_dict [lindex $invocation 2]
                if {[dict exists $property_dict CONFIG.C_MON_TYPE]} {
                    set mode_index $index
                }
                if {[dict exists $property_dict \
                    CONFIG.C_PROBE_WIDTH_PROPAGATION]} {
                    set enablement_index $index
                }
                if {[dict exists $property_dict CONFIG.C_PROBE2_WIDTH]} {
                    set widths_index $index
                }
            } elseif {$first_connection_index < 0 &&
                $command in {connect_bd_net connect_bd_intf_net}} {
                set first_connection_index $index
            }
        }
        assert_true [expr {$mode_index >= 0 && $enablement_index >= 0 &&
            $widths_index >= 0 &&
            $first_connection_index >= 0 &&
            $mode_index < $enablement_index &&
            $enablement_index < $widths_index &&
            $widths_index < $first_connection_index}] \
            {Probe mode/count/width configuration did not precede wiring}
    }

    run_case DEBUG_SYSTEM_ILA_AUTO_WIDTH_MODE_REJECT {
        reset_mock
        set context [valid_context auto_width_mode]
        dict set context system_ila_identity properties \
            CONFIG.C_PROBE_WIDTH_PROPAGATION AUTO
        set result [::stage1e::debug_design::apply $context]
        assert_status $result FAIL {AUTO width mode rejection status}
        assert_equal SYSTEM_ILA_CONFIGURATION_INVALID \
            [first_error_code $result] {AUTO width mode rejection code}
        assert_equal {} $invocation_log \
            {AUTO width mode rejection reached Vivado backend}
    }

    run_case DEBUG_SYSTEM_ILA_DISABLED_WIDTH_REJECT {
        reset_mock
        set force_probe_width_parameters_disabled 1
        set result [::stage1e::debug_design::apply \
            [valid_context disabled_width_parameter]]
        assert_status $result FAIL {Disabled width parameter rejection status}
        assert_equal PROPERTY_READBACK_MISMATCH [first_error_code $result] \
            {Disabled width parameter rejection code}
        foreach invocation $invocation_log {
            assert_true [expr {[lindex $invocation 0] ni \
                {connect_bd_net connect_bd_intf_net}}] \
                {Disabled width parameter reached debug wiring}
        }
    }

    run_case DEBUG_AUTH_REJECT {
        reset_mock
        set context [valid_context auth_reject]
        dict set context authorization capability_enabled 0
        set result [::stage1e::debug_design::apply $context]
        assert_status $result BLOCKED {Authorization rejection status}
        assert_equal AUTHORIZATION_MISMATCH [first_error_code $result] \
            {Authorization rejection code}
        assert_equal {} $invocation_log {Authorization reached backend}
    }

    run_case DEBUG_PROJECT_OWNER_REJECT {
        reset_mock
        set context [valid_context project_owner_reject]
        dict set context project_ownership owner unexpected_owner
        set result [::stage1e::debug_design::apply $context]
        assert_status $result FAIL {Project owner rejection status}
        assert_equal PROJECT_OWNER_INVALID [first_error_code $result] \
            {Project owner rejection code}
        assert_equal {} $invocation_log {Project owner reached backend}
    }

    run_case DEBUG_BD_OWNER_REJECT {
        reset_mock
        set context [valid_context bd_owner_reject]
        dict set context bd_ownership saved 1
        set result [::stage1e::debug_design::apply $context]
        assert_status $result FAIL {BD owner rejection status}
        assert_equal BD_OWNER_STATE_INVALID [first_error_code $result] \
            {BD owner rejection code}
        assert_equal {} $invocation_log {BD owner reached backend}
    }

    run_case DEBUG_BASE_IDENTITY_REJECT {
        reset_mock
        set context [valid_context base_identity_reject]
        dict set context base_design_identity execution_id OTHER-EXECUTION
        set result [::stage1e::debug_design::apply $context]
        assert_status $result FAIL {Base identity rejection status}
        assert_equal BASE_DESIGN_IDENTITY_MISMATCH [first_error_code $result] \
            {Base identity rejection code}
        assert_equal {} $invocation_log {Base identity reached backend}
    }

    run_case DEBUG_PROBE2_12BIT_CONNECTED {
        reset_mock
        set context [valid_context probe2_12bit]
        set result [::stage1e::debug_design::apply $context]
        assert_status $result PASS {12-bit probe status}
        assert_equal 12 [dict get $properties \
            cell::system_ila_stage2b_0 CONFIG.C_PROBE2_WIDTH] \
            {System ILA probe2 configured width}
        set probe2 [lindex [dict get $result evidence_references \
            topology_readback probes] 2]
        assert_equal protection_ip_axi_lite_0/adc_sample_ch1 \
            [dict get $probe2 source] {Probe2 source mapping}
        assert_equal system_ila_stage2b_0/probe2 \
            [dict get $probe2 sink] {Probe2 sink mapping}
        assert_equal 12 [dict get $probe2 source_width] \
            {Probe2 source width}
        assert_equal 12 [dict get $probe2 sink_width] \
            {Probe2 sink width}
        assert_equal [dict get $scalar_net_by_object \
            pin::protection_ip_axi_lite_0/adc_sample_ch1] \
            [dict get $scalar_net_by_object \
                pin::system_ila_stage2b_0/probe2] \
            {Probe2 did not connect to the i_ch1 net}
    }

    run_case DEBUG_PROBE2_SOURCE_MAPPING_REJECT {
        reset_mock
        set context [valid_context probe2_source_mapping]
        set probes [dict get $context probe_schema probes]
        set probe2 [lindex $probes 2]
        dict set probe2 source protection_ip_axi_lite_0/adc_sample_ch2
        lset probes 2 $probe2
        dict set context probe_schema probes $probes
        set result [::stage1e::debug_design::apply $context]
        assert_status $result FAIL {Probe2 source mapping rejection status}
        assert_equal PROBE2_MAPPING_INVALID [first_error_code $result] \
            {Probe2 source mapping rejection code}
        assert_equal {} $invocation_log \
            {Probe2 source mapping rejection reached Vivado backend}
    }

    run_case DEBUG_PROBE11_READY_MAPPING_REJECT {
        reset_mock
        set context [valid_context probe11_ready_mapping]
        set probes [dict get $context probe_schema probes]
        set probe11 [lindex $probes 11]
        dict set probe11 source protection_ip_axi_lite_0/fsm_state
        lset probes 11 $probe11
        dict set context probe_schema probes $probes
        set result [::stage1e::debug_design::apply $context]
        assert_status $result FAIL {Probe11 ready mapping rejection status}
        assert_equal PROBE11_MAPPING_INVALID [first_error_code $result] \
            {Probe11 ready mapping rejection code}
        assert_equal {} $invocation_log \
            {Probe11 ready mapping rejection reached Vivado backend}
    }

    run_case DEBUG_PROBE_SCALAR_SOURCE_REJECT {
        reset_mock
        set context [valid_context probe_scalar_source]
        dict set forced_widths pin::protection_ip_axi_lite_0/adc_sample_ch1 1
        set result [::stage1e::debug_design::apply $context]
        assert_status $result FAIL {Scalar probe source rejection status}
        assert_equal PROBE_SOURCE_WIDTH_MISMATCH [first_error_code $result] \
            {Scalar probe source rejection code}
        assert_true [dict get $result cleanup_result required] \
            {Scalar probe source rejection did not require cleanup}
        assert_true [expr {![dict exists $scalar_net_by_object \
            pin::system_ila_stage2b_0/probe2]}] \
            {Scalar source mismatch connected probe2 implicitly}
    }

    run_case DEBUG_PROBE_MISSING_REJECT {
        reset_mock
        set missing_created_pins {system_ila_stage2b_0/probe2}
        set context [valid_context probe_missing]
        set result [::stage1e::debug_design::apply $context]
        assert_status $result FAIL {Missing probe rejection status}
        assert_equal VIVADO_OBJECT_CARDINALITY [first_error_code $result] \
            {Missing probe rejection code}
        assert_true [dict get $result cleanup_result required] \
            {Missing probe rejection did not require cleanup}
    }

    run_case DEBUG_PROBE_WIDTH_MISMATCH_REJECT {
        reset_mock
        set context [valid_context probe_width_reject]
        dict set forced_widths pin::system_ila_stage2b_0/probe2 1
        set result [::stage1e::debug_design::apply $context]
        assert_status $result FAIL {Probe width rejection status}
        assert_equal PROBE_WIDTH_MISMATCH [first_error_code $result] \
            {Probe width rejection code}
        assert_true [dict get $result cleanup_result required] \
            {Probe width rejection did not require controller cleanup}
        assert_true [expr {![dict exists $scalar_net_by_object \
            pin::system_ila_stage2b_0/probe2]}] \
            {Sink width mismatch connected probe2 implicitly}
    }

    run_case DEBUG_RESULT_SCHEMA {
        reset_mock
        set result [::stage1e::debug_design::apply \
            [valid_context result_schema]]
        assert_status $result PASS {Result schema status}
        foreach key {
            schema_version operation phase execution_id status
            consumed_identities produced_identities ownership_records
            evidence_references warnings errors cleanup_result
        } {
            assert_true [dict exists $result $key] \
                "Result schema missing: $key"
        }
        assert_equal stage1e-debug-design-result-v1 \
            [dict get $result schema_version] {Result schema version}
        set identity [dict get $result produced_identities \
            debug_design_identity]
        foreach field {
            base_design_identity_sha256 debug_policy_sha256
            policy_bundle_sha256 readback_sha256 identity_sha256
        } {
            assert_true [regexp {^[0-9a-f]{64}$} \
                [dict get $identity $field]] \
                "Identity digest invalid: $field"
        }
    }

    run_case DEBUG_NO_SAVE {
        reset_mock
        set result [::stage1e::debug_design::apply [valid_context no_save]]
        assert_status $result PASS {No-save status}
        assert_equal 0 [dict get $result bd_validated] \
            {Debug reported BD validation}
        assert_equal 0 [dict get $result bd_saved] {Debug reported BD save}
        assert_no_forbidden
        foreach command {open_project create_project close_project \
            create_bd_design open_bd_design close_bd_design \
            validate_bd_design save_bd_design} {
            assert_true [expr {[lsearch -glob $invocation_log \
                "$command *"] < 0}] "Forbidden lifecycle command: $command"
        }
    }

    run_case DEBUG_NO_MUTATION {
        reset_mock
        set result [::stage1e::debug_design::apply [valid_context no_mutation]]
        assert_status $result PASS {No-mutation status}
        assert_equal 0 [dict get $result controlled_mutation_invoked] \
            {Stage 1D mutation was reported}
        assert_equal 0 [dict get $result mutation_invoked] \
            {Mutation was reported}
        assert_true [expr {[lsearch -glob $invocation_log \
            {stage1d_controlled_stimulus::*}] < 0}] \
            {Stage 1D mutation command was invoked}
    }

    run_case DEBUG_NO_ARTIFACT {
        reset_mock
        set context [valid_context no_artifact]
        set result [::stage1e::debug_design::apply $context]
        assert_status $result PASS {No-artifact status}
        foreach field {
            artifacts_generated artifact_generation_performed
            artifact_publication_performed synthesis_performed
            implementation_performed
        } {
            assert_equal 0 [dict get $result $field] \
                "Artifact boundary field $field"
        }
        foreach path [all_files [dict get $context workspace_root]] {
            assert_true [expr {[string tolower [file extension $path]] ni \
                {.bit .hwh .xsa .ltx .dcp}}] \
                "Debug adapter generated artifact: $path"
        }
    }
}

set test_status [catch {
    ::stage1e::debug_design_adapter_tests::prepare_suite
    ::stage1e::debug_design_adapter_tests::run_all
} test_error test_options]
set cleanup_status [catch {
    ::stage1e::debug_design_adapter_tests::safe_cleanup
} cleanup_error cleanup_options]
rename ::stage1e::debug_design::backend::invoke {}
rename ::stage1e::debug_design::backend::_production_invoke \
    ::stage1e::debug_design::backend::invoke

if {$test_status != 0} {
    incr ::stage1e::debug_design_adapter_tests::fail_count
    puts stderr "TEST SUITE: FAIL: $test_error"
    if {[dict exists $test_options -errorinfo]} {
        puts stderr [dict get $test_options -errorinfo]
    }
}
if {$cleanup_status != 0} {
    incr ::stage1e::debug_design_adapter_tests::fail_count
    puts stderr "TEST CLEANUP: FAIL: $cleanup_error"
    if {[dict exists $cleanup_options -errorinfo]} {
        puts stderr [dict get $cleanup_options -errorinfo]
    }
}

puts "SUMMARY PASS=$::stage1e::debug_design_adapter_tests::pass_count FAIL=$::stage1e::debug_design_adapter_tests::fail_count"
if {$::stage1e::debug_design_adapter_tests::fail_count != 0} {
    exit 1
}
exit 0
