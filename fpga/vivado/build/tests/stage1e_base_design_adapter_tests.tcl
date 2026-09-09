# Source-only tests for the Stage 1E base-design topology adapter.
#
# The adapter backend is replaced with an isolated in-memory Vivado model. The
# suite invokes no Vivado executable, owns no lifecycle object, validates or
# saves no BD, runs no build, and generates no FPGA artifact.

namespace eval ::stage1e::base_design_adapter_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_root {}
    variable invocation_log {}
    variable forbidden_count 0
    variable current_project project::stage1e_design
    variable current_bd protection_system
    variable properties [dict create]
    variable ipdefs [dict create]
    variable forced_vlnv_readback [dict create]
    variable cells [dict create]
    variable pins [dict create]
    variable intf_pins [dict create]
    variable ports [dict create]
    variable intf_ports [dict create]
    variable scalar_net_by_object [dict create]
    variable intf_net_by_object [dict create]
    variable address_spaces [dict create]
    variable address_segments [dict create]
    variable mapped_address_segments [dict create]
    variable assigned_address_offset {}
    variable assigned_address_range {}
    variable address_readback_delay 0
    variable address_offset_mode VALID
    variable net_sequence 0
}

set stage1e_base_test_dir [file normalize [file dirname [info script]]]
set stage1e_base_build_root [file normalize \
    [file join $stage1e_base_test_dir ..]]
set stage1e_base_adapter [file join \
    $stage1e_base_build_root adapters stage1e_base_design.tcl]

# Source-time execution would fail in this plain Tcl interpreter before the
# backend is replaced, so this also proves the definition-only boundary.
source $stage1e_base_adapter

rename ::stage1e::base_design::backend::invoke \
    ::stage1e::base_design::backend::_production_invoke
proc ::stage1e::base_design::backend::invoke {command arguments} {
    return [::stage1e::base_design_adapter_tests::mock_invoke \
        $command $arguments]
}

proc ::stage1e::base_design_adapter_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::base_design_adapter_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::base_design_adapter_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::base_design_adapter_tests::assert_status {
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

proc ::stage1e::base_design_adapter_tests::first_error_code {result} {
    set errors [dict get $result errors]
    if {[llength $errors] == 0} {
        fail {Expected a structured error record.}
    }
    return [dict get [lindex $errors 0] code]
}

proc ::stage1e::base_design_adapter_tests::run_case {name body} {
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

proc ::stage1e::base_design_adapter_tests::temporary_base {} {
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
    error {No external temporary directory is available for base-design tests.}
}

proc ::stage1e::base_design_adapter_tests::prepare_suite {} {
    variable test_root
    set test_root [file normalize [file join [temporary_base] \
        "stage1e_base_design_tests_[pid]_[clock clicks]"]]
    if {![string match {stage1e_base_design_tests_*} \
        [file tail $test_root]]} {
        error "Unsafe base-design test root: $test_root"
    }
    file mkdir $test_root
}

proc ::stage1e::base_design_adapter_tests::safe_cleanup {} {
    variable test_root
    if {$test_root eq {} || ![file exists $test_root]} {
        return
    }
    if {![string match {stage1e_base_design_tests_*} \
        [file tail $test_root]]} {
        error "Refusing unsafe base-design test cleanup: $test_root"
    }
    file delete -force $test_root
}

proc ::stage1e::base_design_adapter_tests::vlnv_map {} {
    return [dict create \
        processing_system7 xilinx.com:ip:processing_system7:5.5 \
        smartconnect xilinx.com:ip:smartconnect:1.0 \
        protection zsr112.local:protection:protection_ip_axi_lite:0.3 \
        reset xilinx.com:ip:proc_sys_reset:5.0 \
        constant xilinx.com:ip:xlconstant:1.1]
}

proc ::stage1e::base_design_adapter_tests::reset_mock {} {
    variable invocation_log
    variable forbidden_count
    variable current_project
    variable current_bd
    variable properties
    variable ipdefs
    variable forced_vlnv_readback
    variable cells
    variable pins
    variable intf_pins
    variable ports
    variable intf_ports
    variable scalar_net_by_object
    variable intf_net_by_object
    variable address_spaces
    variable address_segments
    variable mapped_address_segments
    variable assigned_address_offset
    variable assigned_address_range
    variable address_readback_delay
    variable address_offset_mode
    variable net_sequence
    set invocation_log {}
    set forbidden_count 0
    set current_project project::stage1e_design
    set current_bd protection_system
    set properties [dict create]
    set ipdefs [dict create]
    foreach {role vlnv} [vlnv_map] {
        set object "ipdef::$role"
        dict set ipdefs $vlnv [list $object]
        dict set properties $object VLNV $vlnv
    }
    set forced_vlnv_readback [dict create]
    set cells [dict create]
    set pins [dict create]
    set intf_pins [dict create]
    set ports [dict create]
    set intf_ports [dict create]
    set scalar_net_by_object [dict create]
    set intf_net_by_object [dict create]
    set address_spaces [dict create]
    set address_segments [dict create]
    set mapped_address_segments [dict create]
    set assigned_address_offset {}
    set assigned_address_range {}
    set address_readback_delay 0
    set address_offset_mode VALID
    set net_sequence 0
}

proc ::stage1e::base_design_adapter_tests::materialize_address_readback {
    segment
} {
    variable properties
    variable assigned_address_offset
    variable assigned_address_range
    variable address_offset_mode
    switch -- $address_offset_mode {
        VALID {
            dict set properties $segment OFFSET $assigned_address_offset
        }
        MISSING {
            dict unset properties $segment OFFSET
        }
        WRONG {
            dict set properties $segment OFFSET 0x43D00000
        }
        default {
            error "Unexpected address offset mode: $address_offset_mode"
        }
    }
    if {$assigned_address_range eq {4096}} {
        dict set properties $segment RANGE 4K
    } else {
        dict set properties $segment RANGE $assigned_address_range
    }
}

proc ::stage1e::base_design_adapter_tests::add_pin {
    path
    {property_values {}}
} {
    variable pins
    variable properties
    set object "pin::$path"
    dict set pins $path $object
    foreach {property value} $property_values {
        dict set properties $object $property $value
    }
    return $object
}

proc ::stage1e::base_design_adapter_tests::add_intf_pin {path} {
    variable intf_pins
    set object "intfpin::$path"
    dict set intf_pins $path $object
    return $object
}

proc ::stage1e::base_design_adapter_tests::materialize_cell_pins {name} {
    variable address_spaces
    variable address_segments
    switch -- $name {
        processing_system7_0 {
            add_pin $name/FCLK_CLK0 [dict create CONFIG.FREQ_HZ 100000000]
            add_pin $name/M_AXI_GP0_ACLK
            add_pin $name/FCLK_RESET0_N \
                [dict create CONFIG.POLARITY ACTIVE_LOW]
            add_intf_pin $name/M_AXI_GP0
            dict set address_spaces $name/Data addrspace::$name/Data
        }
        proc_sys_reset_0 {
            add_pin $name/ext_reset_in \
                [dict create CONFIG.POLARITY ACTIVE_LOW]
            add_pin $name/slowest_sync_clk
            add_pin $name/dcm_locked
            add_pin $name/peripheral_aresetn \
                [dict create CONFIG.POLARITY ACTIVE_LOW]
        }
        smartconnect_0 {
            add_pin $name/aclk
            add_pin $name/aresetn
            add_intf_pin $name/S00_AXI
            add_intf_pin $name/M00_AXI
        }
        protection_ip_axi_lite_0 {
            add_pin $name/ACLK
            add_pin $name/ARESETN
            add_pin $name/adc_src_clk
            add_pin $name/adc_sample_valid
            add_pin $name/adc_sample_ready
            add_pin $name/adc_sample_ch1
            add_pin $name/adc_sample_ch2
            add_intf_pin $name/S_AXI
            dict set address_segments $name/S_AXI/reg0 \
                addrseg::$name/S_AXI/reg0
        }
        sample_valid_const -
        i_ch1_const -
        i_ch2_const -
        dcm_locked_const {
            add_pin $name/dout
        }
        default {
            error "Unexpected mock cell name: $name"
        }
    }
}

proc ::stage1e::base_design_adapter_tests::connect_objects {
    mapping_variable
    prefix
    first
    second
} {
    variable net_sequence
    upvar 1 $mapping_variable mapping
    set net {}
    if {[dict exists $mapping $first]} {
        set net [dict get $mapping $first]
    } elseif {[dict exists $mapping $second]} {
        set net [dict get $mapping $second]
    } else {
        incr net_sequence
        set net "${prefix}::$net_sequence"
    }
    dict set mapping $first $net
    dict set mapping $second $net
    return $net
}

proc ::stage1e::base_design_adapter_tests::lookup_named {
    dictionary
    arguments
} {
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

proc ::stage1e::base_design_adapter_tests::mock_invoke {
    command
    arguments
} {
    variable invocation_log
    variable forbidden_count
    variable current_project
    variable current_bd
    variable properties
    variable ipdefs
    variable forced_vlnv_readback
    variable cells
    variable pins
    variable intf_pins
    variable ports
    variable intf_ports
    variable scalar_net_by_object
    variable intf_net_by_object
    variable address_spaces
    variable address_segments
    variable mapped_address_segments
    variable assigned_address_offset
    variable assigned_address_range
    variable address_readback_delay
    lappend invocation_log [linsert $arguments 0 $command]

    if {$command in {
        open_project
        create_project
        close_project
        create_bd_design
        open_bd_design
        close_bd_design
        validate_bd_design
        save_bd_design
        generate_target
        make_wrapper
        launch_runs
        synth_design
        opt_design
        place_design
        route_design
        write_bitstream
        write_hw_platform
        write_debug_probes
        export_hardware
    }} {
        incr forbidden_count
        error "Forbidden mock command invoked: $command"
    }

    switch -- $command {
        current_project {
            return $current_project
        }
        current_bd_design {
            return $current_bd
        }
        get_ipdefs {
            set vlnv [lindex $arguments end]
            if {[dict exists $ipdefs $vlnv]} {
                return [dict get $ipdefs $vlnv]
            }
            return {}
        }
        get_property {
            lassign $arguments property object
            set property [string toupper $property]
            if {$property eq {VLNV} &&
                [dict exists $forced_vlnv_readback $object]} {
                return [dict get $forced_vlnv_readback $object]
            }
            if {$property eq {NAME} &&
                ([string match {net::*} $object] ||
                    [string match {intfnet::*} $object])} {
                return $object
            }
            if {![dict exists $properties $object $property]} {
                return {}
            }
            return [dict get $properties $object $property]
        }
        get_bd_cells {
            return [lookup_named $cells $arguments]
        }
        get_bd_pins {
            return [lookup_named $pins $arguments]
        }
        get_bd_intf_pins {
            return [lookup_named $intf_pins $arguments]
        }
        get_bd_ports {
            return [lookup_named $ports $arguments]
        }
        get_bd_intf_ports {
            return [lookup_named $intf_ports $arguments]
        }
        get_bd_nets {
            if {[lsearch -exact $arguments -of_objects] >= 0} {
                set object [lindex $arguments end]
                if {[dict exists $scalar_net_by_object $object]} {
                    return [list [dict get $scalar_net_by_object $object]]
                }
                return {}
            }
            return [lsort -unique [dict values $scalar_net_by_object]]
        }
        get_bd_intf_nets {
            if {[lsearch -exact $arguments -of_objects] >= 0} {
                set object [lindex $arguments end]
                if {[dict exists $intf_net_by_object $object]} {
                    return [list [dict get $intf_net_by_object $object]]
                }
                return {}
            }
            return [lsort -unique [dict values $intf_net_by_object]]
        }
        get_bd_addr_spaces {
            return [lookup_named $address_spaces $arguments]
        }
        get_bd_addr_segs {
            set of_objects_index [lsearch -exact $arguments -of_objects]
            if {$of_objects_index >= 0} {
                set address_space [lindex $arguments \
                    [expr {$of_objects_index + 1}]]
                if {![dict exists $mapped_address_segments $address_space]} {
                    return {}
                }
                set segments [dict get $mapped_address_segments $address_space]
                if {$address_readback_delay > 0} {
                    incr address_readback_delay -1
                } else {
                    foreach segment $segments {
                        materialize_address_readback $segment
                    }
                }
                return $segments
            }
            return [lookup_named $address_segments $arguments]
        }
        create_bd_cell {
            set vlnv [lindex $arguments 3]
            set name [lindex $arguments 4]
            set object "cell::$name"
            dict set cells $name $object
            dict set properties $object VLNV $vlnv
            materialize_cell_pins $name
            return $object
        }
        apply_bd_automation {
            dict set intf_ports DDR intfport::DDR
            dict set intf_ports FIXED_IO intfport::FIXED_IO
            return {}
        }
        set_property {
            lassign $arguments option property_values object
            if {$option ne {-dict}} {
                error {Mock set_property supports only -dict.}
            }
            foreach {property value} $property_values {
                dict set properties $object [string toupper $property] $value
            }
            return {}
        }
        connect_bd_net {
            lassign $arguments first second
            return [connect_objects scalar_net_by_object net $first $second]
        }
        connect_bd_intf_net {
            lassign $arguments first second
            return [connect_objects intf_net_by_object intfnet $first $second]
        }
        assign_bd_address {
            set address_space_index [lsearch -exact \
                $arguments -target_address_space]
            set offset_index [lsearch -exact $arguments -offset]
            set range_index [lsearch -exact $arguments -range]
            set address_space [lindex $arguments \
                [expr {$address_space_index + 1}]]
            set assigned_address_offset \
                [lindex $arguments [expr {$offset_index + 1}]]
            set assigned_address_range \
                [lindex $arguments [expr {$range_index + 1}]]
            set mapped_segment \
                addrseg::processing_system7_0/Data/SEG_protection_ip_axi_lite_0_reg0
            dict set mapped_address_segments $address_space \
                [list $mapped_segment]
            dict set properties $mapped_segment NAME \
                SEG_protection_ip_axi_lite_0_reg0
            if {$address_readback_delay == 0} {
                materialize_address_readback $mapped_segment
            }
            return {}
        }
        default {
            error "Unexpected mock Vivado command: $command"
        }
    }
}

proc ::stage1e::base_design_adapter_tests::cell_policy {} {
    return [dict create \
        schema_version stage1e-base-cell-policy-v1 \
        creation_order {
            processing_system7
            reset
            smartconnect
            protection
            sample_valid_const
            i_ch1_const
            i_ch2_const
            dcm_locked_const
        } \
        instances [dict create \
            processing_system7 [dict create \
                name processing_system7_0 \
                vlnv_role processing_system7 \
                properties [dict create \
                    CONFIG.PCW_USE_M_AXI_GP0 1 \
                    CONFIG.PCW_EN_CLK0_PORT 1 \
                    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100]] \
            reset [dict create \
                name proc_sys_reset_0 \
                vlnv_role reset \
                properties {}] \
            smartconnect [dict create \
                name smartconnect_0 \
                vlnv_role smartconnect \
                properties [dict create CONFIG.NUM_MI 1 CONFIG.NUM_SI 1]] \
            protection [dict create \
                name protection_ip_axi_lite_0 \
                vlnv_role protection \
                properties {}] \
            sample_valid_const [dict create \
                name sample_valid_const \
                vlnv_role constant \
                properties [dict create \
                    CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0]] \
            i_ch1_const [dict create \
                name i_ch1_const \
                vlnv_role constant \
                properties [dict create \
                    CONFIG.CONST_WIDTH 12 CONFIG.CONST_VAL 1024]] \
            i_ch2_const [dict create \
                name i_ch2_const \
                vlnv_role constant \
                properties [dict create \
                    CONFIG.CONST_WIDTH 12 CONFIG.CONST_VAL 1024]] \
            dcm_locked_const [dict create \
                name dcm_locked_const \
                vlnv_role constant \
                properties [dict create \
                    CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1]]] \
        board_automation [dict create \
            cell_role processing_system7 \
            rule xilinx.com:bd_rule:processing_system7 \
            config {make_external "FIXED_IO, DDR" apply_board_preset "1"} \
            expected_external_interfaces {DDR FIXED_IO}]]
}

proc ::stage1e::base_design_adapter_tests::interface_policy {} {
    return [dict create \
        schema_version stage1e-base-interface-policy-v1 \
        required_external_interfaces {DDR FIXED_IO} \
        interface_connections [list \
            [dict create \
                source processing_system7_0/M_AXI_GP0 \
                sink smartconnect_0/S00_AXI] \
            [dict create \
                source smartconnect_0/M00_AXI \
                sink protection_ip_axi_lite_0/S_AXI]] \
        stimulus_connections [list \
            [dict create \
                source sample_valid_const/dout \
                sink protection_ip_axi_lite_0/adc_sample_valid] \
            [dict create \
                source i_ch1_const/dout \
                sink protection_ip_axi_lite_0/adc_sample_ch1] \
            [dict create \
                source i_ch2_const/dout \
                sink protection_ip_axi_lite_0/adc_sample_ch2]]]
}

proc ::stage1e::base_design_adapter_tests::clock_policy {} {
    return [dict create \
        schema_version stage1e-base-clock-policy-v1 \
        frequency_hz 100000000 \
        frequency_property CONFIG.FREQ_HZ \
        source processing_system7_0/FCLK_CLK0 \
        sinks {
            processing_system7_0/M_AXI_GP0_ACLK
            smartconnect_0/aclk
            proc_sys_reset_0/slowest_sync_clk
            protection_ip_axi_lite_0/ACLK
            protection_ip_axi_lite_0/adc_src_clk
        }]
}

proc ::stage1e::base_design_adapter_tests::reset_policy {} {
    return [dict create \
        schema_version stage1e-base-reset-policy-v1 \
        connections [list \
            [dict create \
                source processing_system7_0/FCLK_RESET0_N \
                sink proc_sys_reset_0/ext_reset_in] \
            [dict create \
                source dcm_locked_const/dout \
                sink proc_sys_reset_0/dcm_locked] \
            [dict create \
                source proc_sys_reset_0/peripheral_aresetn \
                sink smartconnect_0/aresetn] \
            [dict create \
                source proc_sys_reset_0/peripheral_aresetn \
                sink protection_ip_axi_lite_0/ARESETN]] \
        polarity_checks [list \
            [dict create \
                path processing_system7_0/FCLK_RESET0_N \
                property CONFIG.POLARITY \
                expected ACTIVE_LOW] \
            [dict create \
                path proc_sys_reset_0/ext_reset_in \
                property CONFIG.POLARITY \
                expected ACTIVE_LOW] \
            [dict create \
                path proc_sys_reset_0/peripheral_aresetn \
                property CONFIG.POLARITY \
                expected ACTIVE_LOW]]]
}

proc ::stage1e::base_design_adapter_tests::valid_context {name} {
    variable test_root
    variable current_project
    variable properties
    set execution_id "STAGE1E-BASE-DESIGN-$name"
    set workspace_root [file normalize [file join $test_root executions $name]]
    set evidence_dir [file join $workspace_root evidence]
    set project_directory [file join $workspace_root project]
    set project_path [file join $project_directory stage1e_design.xpr]
    set bd_path [file join $project_directory stage1e_design.srcs \
        sources_1 bd protection_system protection_system.bd]
    file mkdir $evidence_dir
    file mkdir [file dirname $bd_path]

    dict set properties $current_project NAME stage1e_design
    dict set properties $current_project DIRECTORY \
        [file normalize $project_directory]
    dict set properties $current_project PART xc7z020clg400-1
    dict set properties $current_project BOARD_PART \
        tul.com.tw:pynq-z2:part0:1.0

    set project_identity [dict create \
        schema_version stage1e-project-identity-v1 \
        execution_id $execution_id \
        project_name stage1e_design \
        project_directory [file normalize $project_directory] \
        project_path [file normalize $project_path] \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0]
    set project_ownership [dict create \
        owner vivado_project \
        execution_id $execution_id \
        project_handle $current_project \
        project_path [file normalize $project_path] \
        identity_verified 1 \
        project_identity $project_identity]
    set bd_ownership [dict create \
        owner bd_flow \
        execution_id $execution_id \
        project_path [file normalize $project_path] \
        bd_name protection_system \
        bd_path [file normalize $bd_path] \
        opened 1 \
        identity_verified 1 \
        validated 0 \
        saved 0]

    return [dict create \
        context_schema_version stage1e-base-design-context-v1 \
        operation stage1e::base_design::apply \
        phase BD_GENERATION \
        execution_id $execution_id \
        authorization [dict create \
            status AUTHORIZED \
            authority controller_core \
            execution_id $execution_id \
            operation stage1e::base_design::apply \
            phase BD_GENERATION \
            capability bd_generation_enabled \
            capability_enabled 1] \
        source_identity [dict create \
            schema_version stage1e-source-identity-v1 \
            execution_id $execution_id \
            git_commit [string repeat 1 40]] \
        environment_identity [dict create \
            schema_version stage1e-environment-identity-v1 \
            execution_id $execution_id \
            vivado_version 2024.1 \
            part xc7z020clg400-1 \
            board_part tul.com.tw:pynq-z2:part0:1.0] \
        configuration_identity [dict create \
            schema_version stage1e-configuration-identity-v1 \
            execution_id $execution_id \
            sha256 [string repeat c 64]] \
        workspace_root $workspace_root \
        evidence_dir $evidence_dir \
        project_ownership $project_ownership \
        bd_ownership $bd_ownership \
        profile_policy [dict create \
            schema_version stage2d-stimulus-profile-policy-v1 \
            profile SAFE_INERT \
            profile_class SAFE_INERT \
            production_authority 1 \
            demo_test_only 0 \
            valid_value 0 \
            functional_adc_stimulus 0 \
            valid_source_exists 1 \
            ready_consumed 0 \
            no_overwrite_when_ready_low 0 \
            transaction_pulse_bounded 0] \
        topology_policy [dict create \
            schema_version stage1e-topology-policy-reference-v1 \
            execution_id $execution_id \
            policy_id pynq_z2_stage1e_base_design_v1 \
            source_reference fpga/vivado/create_pynq_z2_stage2_bd.tcl \
            sha256 [string repeat d 64]] \
        expected_vlnv_map [vlnv_map] \
        cell_policy [cell_policy] \
        interface_policy [interface_policy] \
        clock_policy [clock_policy] \
        reset_policy [reset_policy] \
        address_policy [dict create \
            schema_version stage1e-base-address-policy-v1 \
            address_space processing_system7_0/Data \
            target_segment protection_ip_axi_lite_0/S_AXI/reg0 \
            offset 0x43C00000 \
            range 0x00001000]]
}

proc ::stage1e::base_design_adapter_tests::assert_no_commands {
    forbidden_commands
    label
} {
    variable invocation_log
    variable forbidden_count
    assert_equal 0 $forbidden_count "$label tripwire count"
    foreach invocation $invocation_log {
        set command [lindex $invocation 0]
        assert_true [expr {$command ni $forbidden_commands}] \
            "$label command was invoked: $command"
    }
}

proc ::stage1e::base_design_adapter_tests::all_files {root} {
    set files {}
    foreach entry [glob -nocomplain -directory $root -- * .*] {
        if {[file tail $entry] in {. ..}} {
            continue
        }
        if {[file isdirectory $entry]} {
            foreach nested [all_files $entry] {
                lappend files $nested
            }
        } elseif {[file isfile $entry]} {
            lappend files $entry
        }
    }
    return $files
}

proc ::stage1e::base_design_adapter_tests::run_all {} {
    variable invocation_log
    variable forced_vlnv_readback
    variable address_readback_delay
    variable address_offset_mode

    run_case BASE_DESIGN_CONTEXT_VALID {
        reset_mock
        set context [valid_context context_valid]
        set result [::stage1e::base_design::apply $context]
        assert_status $result PASS {Valid base-design context status}
        assert_true [dict exists $result produced_identities \
            base_design_identity] {Base-design identity is missing}
        assert_equal [dict get $context project_ownership] \
            [dict get $result ownership_records project_ownership] \
            {Project ownership changed}
        assert_equal [dict get $context bd_ownership] \
            [dict get $result ownership_records bd_ownership] \
            {BD ownership changed}
    }

    run_case BASE_DESIGN_AUTH_REJECT {
        reset_mock
        set context [valid_context auth_reject]
        dict set context authorization capability_enabled 0
        set result [::stage1e::base_design::apply $context]
        assert_status $result BLOCKED {Authorization rejection status}
        assert_equal AUTHORIZATION_MISMATCH [first_error_code $result] \
            {Authorization rejection code}
        assert_equal 0 [dict get $result vivado_invoked] \
            {Authorization rejection invoked Vivado}
        assert_equal {} $invocation_log \
            {Authorization rejection reached the backend}
    }

    run_case BASE_DESIGN_PROJECT_OWNER_REJECT {
        reset_mock
        set context [valid_context project_owner_reject]
        dict set context project_ownership owner unexpected_owner
        set result [::stage1e::base_design::apply $context]
        assert_status $result FAIL {Project owner rejection status}
        assert_equal PROJECT_OWNER_INVALID [first_error_code $result] \
            {Project owner rejection code}
        assert_equal {} $invocation_log \
            {Project owner rejection reached the backend}
    }

    run_case BASE_DESIGN_BD_OWNER_REJECT {
        reset_mock
        set context [valid_context bd_owner_reject]
        dict set context bd_ownership saved 1
        set result [::stage1e::base_design::apply $context]
        assert_status $result FAIL {BD owner rejection status}
        assert_equal BD_OWNER_STATE_INVALID [first_error_code $result] \
            {BD owner rejection code}
        assert_equal {} $invocation_log \
            {BD owner rejection reached the backend}
    }

    run_case BASE_DESIGN_VLNV_MISMATCH_REJECT {
        reset_mock
        set context [valid_context vlnv_mismatch]
        dict set forced_vlnv_readback ipdef::protection \
            unexpected.vendor:unexpected:protection:9.9
        set result [::stage1e::base_design::apply $context]
        assert_status $result FAIL {VLNV mismatch rejection status}
        assert_equal VLNV_MISMATCH [first_error_code $result] \
            {VLNV mismatch rejection code}
        assert_true [expr {[lsearch -glob $invocation_log \
            {create_bd_cell *}] < 0}] \
            {VLNV mismatch reached topology mutation}
        assert_true [expr {![dict get $result cleanup_result required]}] \
            {Pre-mutation VLNV mismatch required cleanup}
    }

    run_case BASE_DESIGN_RESULT_SCHEMA {
        reset_mock
        set context [valid_context result_schema]
        set result [::stage1e::base_design::apply $context]
        assert_status $result PASS {Structured result status}
        set required_keys [lsort -dictionary {
            schema_version
            operation
            phase
            execution_id
            status
            consumed_identities
            produced_identities
            ownership_records
            evidence_references
            warnings
            errors
            cleanup_result
        }]
        foreach key $required_keys {
            assert_true [dict exists $result $key] \
                "Structured result is missing: $key"
        }
        assert_equal stage1e-base-design-result-v1 \
            [dict get $result schema_version] {Result schema version}
        assert_equal stage1e::base_design::apply \
            [dict get $result operation] {Result operation}
        assert_equal BD_GENERATION [dict get $result phase] {Result phase}
        set identity [dict get $result produced_identities \
            base_design_identity]
        foreach digest {
            topology_policy_sha256
            policy_bundle_sha256
            readback_sha256
            identity_sha256
        } {
            assert_true [regexp {^[0-9a-f]{64}$} \
                [dict get $identity $digest]] \
                "Base-design identity digest is invalid: $digest"
        }
    }

    run_case BASE_DESIGN_ADDRESS_ASSIGNED_SEGMENT_VALID {
        reset_mock
        set context [valid_context address_assigned_segment]
        set result [::stage1e::base_design::apply $context]
        assert_status $result PASS {Assigned address-segment status}
        set readback [dict get $result evidence_references \
            topology_readback address]
        assert_equal \
            addrseg::processing_system7_0/Data/SEG_protection_ip_axi_lite_0_reg0 \
            [dict get $readback assigned_segment] \
            {Assigned address-segment object}
        assert_equal 1136656384 [dict get $readback offset] \
            {Assigned address-segment offset}
        assert_equal 4K [dict get $readback range] \
            {Assigned address-segment range}
        assert_true [expr {[lsearch -exact $invocation_log [list \
            get_property OFFSET \
            addrseg::processing_system7_0/Data/SEG_protection_ip_axi_lite_0_reg0]] \
            >= 0}] {OFFSET was not read from the assigned segment object}
    }

    run_case BASE_DESIGN_ADDRESS_MISSING_OFFSET_REJECT {
        reset_mock
        set address_offset_mode MISSING
        set context [valid_context address_missing_offset]
        set result [::stage1e::base_design::apply $context]
        assert_status $result FAIL {Missing address offset rejection status}
        assert_equal PROPERTY_READBACK_MISMATCH [first_error_code $result] \
            {Missing address offset rejection code}
        assert_true [string match {*OFFSET is empty*} \
            [dict get [lindex [dict get $result errors] 0] message]] \
            {Missing address offset rejection message}
    }

    run_case BASE_DESIGN_ADDRESS_WRONG_OFFSET_REJECT {
        reset_mock
        set address_offset_mode WRONG
        set context [valid_context address_wrong_offset]
        set result [::stage1e::base_design::apply $context]
        assert_status $result FAIL {Wrong address offset rejection status}
        assert_equal PROPERTY_READBACK_MISMATCH [first_error_code $result] \
            {Wrong address offset rejection code}
        assert_true [string match {*OFFSET mismatch*} \
            [dict get [lindex [dict get $result errors] 0] message]] \
            {Wrong address offset rejection message}
    }

    run_case BASE_DESIGN_ADDRESS_DELAYED_READBACK {
        reset_mock
        set address_readback_delay 1
        set context [valid_context address_delayed_readback]
        set result [::stage1e::base_design::apply $context]
        assert_status $result PASS {Delayed address readback status}
        set query_count 0
        foreach invocation $invocation_log {
            if {[lrange $invocation 0 2] eq \
                {get_bd_addr_segs -quiet -of_objects}} {
                incr query_count
            }
        }
        assert_equal 2 $query_count \
            {Delayed address readback query count}
    }

    run_case BASE_DESIGN_NO_SAVE {
        reset_mock
        set context [valid_context no_save]
        set result [::stage1e::base_design::apply $context]
        assert_status $result PASS {No-save status}
        assert_equal 0 [dict get $result bd_validated] \
            {Base design reported validation}
        assert_equal 0 [dict get $result bd_saved] \
            {Base design reported save}
        assert_no_commands {
            open_project
            create_project
            close_project
            create_bd_design
            open_bd_design
            close_bd_design
            validate_bd_design
            save_bd_design
        } {Lifecycle/save boundary}
    }

    run_case BASE_DESIGN_NO_SYNTHESIS {
        reset_mock
        set context [valid_context no_synthesis]
        set result [::stage1e::base_design::apply $context]
        assert_status $result PASS {No-synthesis status}
        assert_equal 0 [dict get $result synthesis_performed] \
            {Base design reported synthesis}
        assert_equal 0 [dict get $result implementation_performed] \
            {Base design reported implementation}
        assert_no_commands {
            launch_runs synth_design opt_design place_design route_design
        } {Build boundary}
    }

    run_case BASE_DESIGN_NO_ARTIFACT {
        reset_mock
        set context [valid_context no_artifact]
        set result [::stage1e::base_design::apply $context]
        assert_status $result PASS {No-artifact status}
        foreach field {
            artifacts_generated
            artifact_generation_performed
            artifact_publication_performed
        } {
            assert_equal 0 [dict get $result $field] \
                "No-artifact result field $field"
        }
        assert_no_commands {
            generate_target
            make_wrapper
            write_bitstream
            write_hw_platform
            write_debug_probes
            export_hardware
        } {Artifact boundary}
        foreach path [all_files [dict get $context workspace_root]] {
            assert_true [expr {
                [string tolower [file extension $path]] ni
                    {.bit .hwh .xsa .ltx .dcp}
            }] "Mock base design generated an FPGA artifact: $path"
        }
    }
}

set test_status [catch {
    ::stage1e::base_design_adapter_tests::prepare_suite
    ::stage1e::base_design_adapter_tests::run_all
} test_error test_options]
set cleanup_status [catch {
    ::stage1e::base_design_adapter_tests::safe_cleanup
} cleanup_error cleanup_options]
rename ::stage1e::base_design::backend::invoke {}
rename ::stage1e::base_design::backend::_production_invoke \
    ::stage1e::base_design::backend::invoke

if {$test_status != 0} {
    incr ::stage1e::base_design_adapter_tests::fail_count
    puts stderr "TEST SUITE: FAIL: $test_error"
    if {[dict exists $test_options -errorinfo]} {
        puts stderr [dict get $test_options -errorinfo]
    }
}
if {$cleanup_status != 0} {
    incr ::stage1e::base_design_adapter_tests::fail_count
    puts stderr "TEST CLEANUP: FAIL: $cleanup_error"
    if {[dict exists $cleanup_options -errorinfo]} {
        puts stderr [dict get $cleanup_options -errorinfo]
    }
}

puts "SUMMARY PASS=$::stage1e::base_design_adapter_tests::pass_count FAIL=$::stage1e::base_design_adapter_tests::fail_count"
if {$::stage1e::base_design_adapter_tests::fail_count != 0} {
    exit 1
}
exit 0
