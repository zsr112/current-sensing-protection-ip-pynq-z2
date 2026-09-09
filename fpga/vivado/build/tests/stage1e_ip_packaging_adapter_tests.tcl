# Source-only tests for the Stage 1E IP packaging adapter.
#
# The suite replaces the adapter's single backend command boundary with an
# isolated Tcl mock. It creates only temporary text files and directories. It
# does not invoke Vivado or generate FPGA artifacts.

namespace eval ::stage1e::ip_packaging_adapter_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_root {}
    variable repository_root {}
    variable invocation_log {}
    variable properties [dict create]
    variable bus_interfaces [dict create]
    variable port_maps [dict create]
    variable bus_parameters [dict create]
    variable memory_maps [dict create]
    variable address_blocks [dict create]
    variable file_groups [dict create]
    variable file_group_files [dict create]
    variable current_project {}
    variable empty_session_behavior RETURN_EMPTY
    variable current_fileset sources_1
    variable filesets [dict create sources_1 fileset:sources_1]
    variable current_core core0
    variable current_cores {core0}
    variable package_root {}
    variable project_open 0
    variable close_count 0
    variable save_core_count 0
    variable saved_core {}
    variable saved_core_identity [dict create]
    variable forbidden_count 0
    variable forced_vendor_readback {}
    variable added_files {}
}

set stage1e_packaging_test_dir [file normalize [file dirname [info script]]]
set stage1e_packaging_build_root [file normalize \
    [file join $stage1e_packaging_test_dir ..]]
set stage1e_packaging_adapter [file join \
    $stage1e_packaging_build_root adapters stage1e_ip_packaging.tcl]

# Sourcing must define procedures only. In a plain Tcl interpreter, any
# source-time Vivado command would fail before the mock is installed.
source $stage1e_packaging_adapter

rename ::stage1e::ip_packaging::backend::invoke \
    ::stage1e::ip_packaging::backend::_production_invoke
proc ::stage1e::ip_packaging::backend::invoke {command arguments} {
    return [::stage1e::ip_packaging_adapter_tests::mock_invoke \
        $command $arguments]
}

# Exercise the production project-property helper bodies without Vivado. The
# helpers deliberately call these global Vivado command names directly so the
# current project object is evaluated in the set_property/get_property command.
proc ::current_project {} {
    return [::stage1e::ip_packaging_adapter_tests::mock_invoke \
        current_project {}]
}

proc ::set_property {property value objects} {
    return [::stage1e::ip_packaging_adapter_tests::mock_invoke \
        set_property [list $property $value $objects]]
}

proc ::get_property {property objects} {
    return [::stage1e::ip_packaging_adapter_tests::mock_invoke \
        get_property [list $property $objects]]
}

proc ::get_filesets {name} {
    return [::stage1e::ip_packaging_adapter_tests::mock_invoke \
        get_filesets [list $name]]
}

proc ::stage1e::ip_packaging_adapter_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::ip_packaging_adapter_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::ip_packaging_adapter_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::ip_packaging_adapter_tests::assert_sha256 {
    value
    message
} {
    if {![regexp {^[0-9a-f]{64}$} $value]} {
        fail "$message is not a lowercase SHA-256 digest: $value"
    }
}

proc ::stage1e::ip_packaging_adapter_tests::assert_result_status {
    result
    expected_status
    message
} {
    if {[catch {dict size $result} dictionary_error]} {
        fail "$message is not a dictionary: $dictionary_error"
    }
    if {[dict get $result status] ne $expected_status} {
        fail "$message: expected=<$expected_status> actual=<[dict get $result status]> errors=<[dict get $result errors]>"
    }
}

proc ::stage1e::ip_packaging_adapter_tests::first_error_code {result} {
    set errors [dict get $result errors]
    if {[llength $errors] == 0} {
        fail {Expected a structured error record.}
    }
    return [dict get [lindex $errors 0] code]
}

proc ::stage1e::ip_packaging_adapter_tests::property_invocations {property} {
    variable invocation_log
    set matches {}
    foreach invocation $invocation_log {
        if {[lindex $invocation 0] eq {set_property} &&
            [lindex $invocation 1] eq $property} {
            lappend matches $invocation
        }
    }
    return $matches
}

proc ::stage1e::ip_packaging_adapter_tests::run_case {name body} {
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

proc ::stage1e::ip_packaging_adapter_tests::temporary_base {} {
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
    error {No external temporary directory is available for packaging tests.}
}

proc ::stage1e::ip_packaging_adapter_tests::write_text {path text} {
    file mkdir [file dirname $path]
    set channel [open $path w]
    fconfigure $channel -encoding utf-8 -translation lf
    set write_status [catch {puts -nonewline $channel $text} \
        write_error write_options]
    set close_status [catch {close $channel} close_error]
    if {$write_status != 0} {
        return -options $write_options $write_error
    }
    if {$close_status != 0} {
        error "Unable to close test file: $close_error"
    }
}

proc ::stage1e::ip_packaging_adapter_tests::prepare_suite {} {
    variable test_root
    variable repository_root

    set test_root [file normalize [file join [temporary_base] \
        "stage1e_ip_packaging_tests_[pid]_[clock clicks]"]]
    if {![string match {stage1e_ip_packaging_tests_*} \
        [file tail $test_root]]} {
        error "Unsafe packaging test root: $test_root"
    }
    file mkdir $test_root
    set repository_root [file join $test_root source_repository]
    file mkdir [file join $repository_root rtl]
    file mkdir [file join $repository_root fpga vivado constraints]
    write_text [file join $repository_root rtl fault_defs.vh] \
        "`define TEST_FAULT 1\n"
    write_text [file join \
        $repository_root rtl protection_ip_top_axi_lite.v] \
        "module protection_ip_top_axi_lite; endmodule\n"
    write_text [file join $repository_root fpga vivado constraints \
        stage2d_async_adc_atomic_cdc.xdc] \
        "# mock Stage 2D CDC constraints\n"
    write_text [file join $repository_root fpga vivado constraints \
        stage2e_transaction_observability_cdc.xdc] \
        "# mock Stage 2E CDC constraints\n"
}

proc ::stage1e::ip_packaging_adapter_tests::safe_cleanup {} {
    variable test_root
    if {$test_root eq {} || ![file exists $test_root]} {
        return
    }
    set normalized [file normalize $test_root]
    if {![string match {stage1e_ip_packaging_tests_*} \
        [file tail $normalized]]} {
        error "Refusing unsafe packaging test cleanup: $normalized"
    }
    file delete -force -- $normalized
}

proc ::stage1e::ip_packaging_adapter_tests::reset_mock {} {
    variable invocation_log {}
    variable properties [dict create]
    variable bus_interfaces [dict create]
    variable port_maps [dict create]
    variable bus_parameters [dict create]
    variable memory_maps [dict create]
    variable address_blocks [dict create]
    variable file_groups [dict create]
    variable file_group_files [dict create]
    variable current_project {}
    variable empty_session_behavior RETURN_EMPTY
    variable current_fileset sources_1
    variable filesets [dict create sources_1 fileset:sources_1]
    variable current_core core0
    variable current_cores {core0}
    variable package_root {}
    variable project_open 0
    variable close_count 0
    variable save_core_count 0
    variable saved_core {}
    variable saved_core_identity [dict create]
    variable forbidden_count 0
    variable forced_vendor_readback {}
    variable added_files {}
}

proc ::stage1e::ip_packaging_adapter_tests::set_property_value {
    object
    property
    value
} {
    variable properties
    dict set properties [list $object $property] $value
}

proc ::stage1e::ip_packaging_adapter_tests::get_property_value {
    object
    property
} {
    variable properties
    variable current_core
    variable forced_vendor_readback
    if {$object eq $current_core && $property eq {vendor} &&
        $forced_vendor_readback ne {}} {
        return $forced_vendor_readback
    }
    set key [list $object $property]
    if {![dict exists $properties $key]} {
        error "Mock property is unavailable: object=$object property=$property"
    }
    return [dict get $properties $key]
}

proc ::stage1e::ip_packaging_adapter_tests::get_core_property_values {
    object
    property
} {
    variable current_cores

    if {[llength $current_cores] > 1 && $object eq $current_cores} {
        set values {}
        foreach core $current_cores {
            lappend values [get_core_property_values $core $property]
        }
        return $values
    }
    if {$property eq {VLNV}} {
        set parts {}
        foreach identity_property {vendor library name version} {
            lappend parts [get_property_value $object $identity_property]
        }
        return [join $parts :]
    }
    return [get_property_value $object $property]
}

proc ::stage1e::ip_packaging_adapter_tests::option_value {
    arguments
    option
} {
    set index [lsearch -exact $arguments $option]
    if {$index < 0 || $index + 1 >= [llength $arguments]} {
        error "Mock command is missing option: $option"
    }
    return [lindex $arguments [expr {$index + 1}]]
}

proc ::stage1e::ip_packaging_adapter_tests::mock_object_get {
    variable_name
    key
} {
    upvar 1 $variable_name objects
    if {[dict exists $objects $key]} {
        return [dict get $objects $key]
    }
    return {}
}

proc ::stage1e::ip_packaging_adapter_tests::mock_object_add {
    variable_name
    key
    prefix
} {
    upvar 1 $variable_name objects
    set object "$prefix:[dict size $objects]"
    dict set objects $key $object
    return $object
}

proc ::stage1e::ip_packaging_adapter_tests::mock_invoke {
    command
    arguments
} {
    variable invocation_log
    variable bus_interfaces
    variable port_maps
    variable bus_parameters
    variable memory_maps
    variable address_blocks
    variable file_groups
    variable file_group_files
    variable current_project
    variable empty_session_behavior
    variable current_fileset
    variable filesets
    variable current_core
    variable current_cores
    variable package_root
    variable project_open
    variable close_count
    variable save_core_count
    variable saved_core
    variable saved_core_identity
    variable forbidden_count
    variable added_files

    lappend invocation_log [list $command {*}$arguments]
    set forbidden_commands {
        create_bd_design
        open_bd_design
        validate_bd_design
        save_bd_design
        launch_runs
        synth_design
        opt_design
        place_design
        route_design
        write_bitstream
        write_hw_platform
        write_debug_probes
        export_hardware
    }
    if {$command in $forbidden_commands} {
        incr forbidden_count
        error "Forbidden mock command invoked: $command"
    }

    switch -- $command {
        create_project {
            set project_name [lindex $arguments 0]
            set project_path [lindex $arguments 1]
            file mkdir $project_path
            set current_project "project:$project_name"
            set project_open 1
            return $current_project
        }
        current_project {
            if {$project_open} {
                return $current_project
            }
            switch -- $empty_session_behavior {
                RETURN_EMPTY {
                    return {}
                }
                RAISE_CORETCL_NO_PROJECT {
                    error \
                        {ERROR: [Coretcl 2-88] No projects are currently open.}
                }
                RAISE_UNEXPECTED {
                    error \
                        {ERROR: [Common 17-69] Unexpected project query failure.}
                }
                default {
                    error "Unsupported empty-session mock behavior: $empty_session_behavior"
                }
            }
        }
        set_property {
            if {[llength $arguments] != 3} {
                error "Mock set_property argument order/arity is invalid: $arguments"
            }
            lassign $arguments property value object
            set_property_value $object $property $value
            return {}
        }
        get_property {
            lassign $arguments property object
            if {$property in {VLNV vendor library name version}} {
                return [get_core_property_values $object $property]
            }
            return [get_property_value $object $property]
        }
        add_files {
            foreach file [lindex $arguments end] {
                lappend added_files $file
            }
            return $added_files
        }
        get_files {
            return "file:[lindex $arguments end]"
        }
        current_fileset {
            return $current_fileset
        }
        get_filesets {
            set name [lindex $arguments end]
            if {[dict exists $filesets $name]} {
                return [dict get $filesets $name]
            }
            return {}
        }
        update_compile_order {
            return {}
        }
        ipx::package_project {
            set package_root [option_value $arguments -root_dir]
            file mkdir $package_root
            foreach core $current_cores {
                set_property_value $core vendor \
                    [option_value $arguments -vendor]
                set_property_value $core library \
                    [option_value $arguments -library]
                set_property_value $core name \
                    protection_ip_top_axi_lite
                set_property_value $core version 1.0
                set_property_value $core taxonomy \
                    [option_value $arguments -taxonomy]
            }
            write_text [file join $package_root component.xml] \
                "<component mock=\"initial\"/>\n"
            set synthesis_group file_group:xilinx_anylanguagesynthesis
            dict set file_groups xilinx_anylanguagesynthesis $synthesis_group
            set_property_value $synthesis_group NAME \
                xilinx_anylanguagesynthesis
            set_property_value $synthesis_group TYPE synthesis
            foreach source $added_files {
                if {[string tolower [file extension $source]] ne {.xdc}} {
                    continue
                }
                set relative_path "src/[file tail $source]"
                set file_object \
                    "ipx_file:xilinx_anylanguagesynthesis:$relative_path"
                dict lappend file_group_files $synthesis_group $file_object
                set_property_value $file_object NAME $relative_path
            }
            return $current_cores
        }
        ipx::current_core {
            if {[llength $current_cores] == 1} {
                foreach core $current_cores {
                    return $core
                }
            }
            return $current_cores
        }
        ipx::get_user_parameters {
            return "user_parameter:[lindex $arguments 0]"
        }
        ipx::get_file_groups {
            set object_index [lsearch -exact $arguments -of_objects]
            if {$object_index < 0} {
                error {Mock ipx::get_file_groups lacks -of_objects.}
            }
            if {[llength $arguments] > 0 &&
                ![string match {-*} [lindex $arguments 0]]} {
                set name [lindex $arguments 0]
                if {[dict exists $file_groups $name]} {
                    return [dict get $file_groups $name]
                }
                return {}
            }
            return [dict values $file_groups]
        }
        ipx::add_file_group {
            set name [lindex $arguments 0]
            if {[dict exists $file_groups $name]} {
                error "Mock file group already exists: $name"
            }
            set object "file_group:$name"
            dict set file_groups $name $object
            set_property_value $object NAME $name
            set type_index [lsearch -exact $arguments -type]
            if {$type_index >= 0} {
                set_property_value $object TYPE \
                    [lindex $arguments [expr {$type_index + 1}]]
            }
            return $object
        }
        ipx::get_files {
            set relative_path [lindex $arguments 0]
            set group [option_value $arguments -of_objects]
            set matches {}
            if {[dict exists $file_group_files $group]} {
                foreach file_object [dict get $file_group_files $group] {
                    if {[get_property_value $file_object NAME] eq \
                        $relative_path} {
                        lappend matches $file_object
                    }
                }
            }
            return $matches
        }
        ipx::remove_file {
            lassign $arguments relative_path group
            set retained {}
            if {[dict exists $file_group_files $group]} {
                foreach file_object [dict get $file_group_files $group] {
                    if {[get_property_value $file_object NAME] ne \
                        $relative_path} {
                        lappend retained $file_object
                    }
                }
            }
            dict set file_group_files $group $retained
            return {}
        }
        ipx::add_file {
            lassign $arguments relative_path group
            set file_object "ipx_file:[string map {: _} $group]:$relative_path"
            dict lappend file_group_files $group $file_object
            set_property_value $file_object NAME $relative_path
            return $file_object
        }
        ipx::get_bus_interfaces {
            set name [lindex $arguments 0]
            set core [option_value $arguments -of_objects]
            return [mock_object_get bus_interfaces [list $core $name]]
        }
        ipx::add_bus_interface {
            lassign $arguments name core
            return [mock_object_add bus_interfaces \
                [list $core $name] bus_interface]
        }
        ipx::get_port_maps {
            set name [lindex $arguments 0]
            set interface [option_value $arguments -of_objects]
            return [mock_object_get port_maps [list $interface $name]]
        }
        ipx::add_port_map {
            lassign $arguments name interface
            return [mock_object_add port_maps \
                [list $interface $name] port_map]
        }
        ipx::get_bus_parameters {
            set name [lindex $arguments 0]
            set interface [option_value $arguments -of_objects]
            return [mock_object_get bus_parameters [list $interface $name]]
        }
        ipx::add_bus_parameter {
            lassign $arguments name interface
            return [mock_object_add bus_parameters \
                [list $interface $name] bus_parameter]
        }
        ipx::get_memory_maps {
            set name [lindex $arguments 0]
            set core [option_value $arguments -of_objects]
            return [mock_object_get memory_maps [list $core $name]]
        }
        ipx::add_memory_map {
            lassign $arguments name core
            return [mock_object_add memory_maps \
                [list $core $name] memory_map]
        }
        ipx::get_address_blocks {
            set name [lindex $arguments 0]
            set memory_map [option_value $arguments -of_objects]
            return [mock_object_get address_blocks [list $memory_map $name]]
        }
        ipx::add_address_block {
            lassign $arguments name memory_map
            return [mock_object_add address_blocks \
                [list $memory_map $name] address_block]
        }
        ipx::create_xgui_files -
        ipx::update_checksums {
            return {}
        }
        ipx::check_integrity {
            return PASS
        }
        ipx::save_core {
            incr save_core_count
            set saved_core [lindex $arguments 0]
            set saved_core_identity [dict create]
            foreach property {vendor library name version} {
                dict set saved_core_identity $property \
                    [get_core_property_values $saved_core $property]
            }
            dict set saved_core_identity vlnv \
                [get_core_property_values $saved_core VLNV]
            write_text [file join $package_root component.xml] \
                "<component mock=\"saved\" vlnv=\"[dict get $saved_core_identity vlnv]\"/>\n"
            write_text [file join $package_root hdl packaged_sources.txt] \
                [join $added_files "\n"]
            write_text [file join $package_root metadata.txt] \
                {mock package metadata}
            return {}
        }
        close_project {
            if {!$project_open} {
                error {Mock close_project called without an open project.}
            }
            set project_open 0
            incr close_count
            return {}
        }
        default {
            error "Unexpected mock Vivado command: $command"
        }
    }
}

proc ::stage1e::ip_packaging_adapter_tests::source_inventory {} {
    variable repository_root
    set inventory {}
    foreach relative_path {
        rtl/fault_defs.vh
        rtl/protection_ip_top_axi_lite.v
        fpga/vivado/constraints/stage2d_async_adc_atomic_cdc.xdc
        fpga/vivado/constraints/stage2e_transaction_observability_cdc.xdc
    } {
        set absolute_path [file join \
            $repository_root {*}[split $relative_path /]]
        lappend inventory [dict create \
            path $relative_path \
            size [file size $absolute_path] \
            sha256 [::stage1d::source_check::sha256_file $absolute_path]]
    }
    return $inventory
}

proc ::stage1e::ip_packaging_adapter_tests::package_inventory {} {
    return [dict create \
        schema_version stage1e-ip-package-inventory-v1 \
        source_paths {
            rtl/fault_defs.vh
            rtl/protection_ip_top_axi_lite.v
        } \
        constraint_paths {
            fpga/vivado/constraints/stage2d_async_adc_atomic_cdc.xdc
            fpga/vivado/constraints/stage2e_transaction_observability_cdc.xdc
        } \
        header_paths {rtl/fault_defs.vh} \
        project_name protection_ip_axi_lite_packaging_tmp \
        top_module protection_ip_top_axi_lite \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        target_language Verilog \
        component_metadata [dict create \
            display_name {Current Protection AXI-Lite IP} \
            description {Current-sensing protection IP with AXI4-Lite access.} \
            vendor_display_name zsr112.local \
            company_url https://zsr112.local \
            supported_families {zynq Production} \
            taxonomy {/UserIP}] \
        user_parameters [dict create \
            DATA_WIDTH 12 \
            CNT_WIDTH 16 \
            AXI_ADDR_WIDTH 8 \
            AXI_DATA_WIDTH 32 \
            HEALTH_CNT_WIDTH 8 \
            ADC_FIFO_ADDR_WIDTH 3] \
        axi_interface [dict create \
            name S_AXI \
            clock_name ACLK \
            reset_name ARESETN \
            address_width 8 \
            data_width 32 \
            clock_frequency_hz 100000000 \
            port_map [dict create \
                AWADDR S_AXI_AWADDR \
                AWVALID S_AXI_AWVALID \
                AWREADY S_AXI_AWREADY \
                WDATA S_AXI_WDATA \
                WSTRB S_AXI_WSTRB \
                WVALID S_AXI_WVALID \
                WREADY S_AXI_WREADY \
                BRESP S_AXI_BRESP \
                BVALID S_AXI_BVALID \
                BREADY S_AXI_BREADY \
                ARADDR S_AXI_ARADDR \
                ARVALID S_AXI_ARVALID \
                ARREADY S_AXI_ARREADY \
                RDATA S_AXI_RDATA \
                RRESP S_AXI_RRESP \
                RVALID S_AXI_RVALID \
                RREADY S_AXI_RREADY]] \
        address_block [dict create \
            memory_map_name S_AXI \
            name reg0 \
            base_address 0 \
            range 4096 \
            width 32 \
            usage register]]
}

proc ::stage1e::ip_packaging_adapter_tests::valid_context {name} {
    variable test_root
    variable repository_root
    set execution_id "STAGE1E-IP-PACKAGING-$name"
    set workspace_root [file normalize \
        [file join $test_root executions $name]]
    file mkdir $workspace_root
    return [dict create \
        context_schema_version stage1e-ip-packaging-context-v1 \
        operation stage1e::ip_packaging::run \
        execution_id $execution_id \
        authorization [dict create \
            status AUTHORIZED \
            authority controller_core \
            execution_id $execution_id \
            operation stage1e::ip_packaging::run \
            phase IP_PACKAGING \
            capability ip_packaging_enabled \
            capability_enabled 1] \
        repository_root $repository_root \
        source_inventory [source_inventory] \
        package_inventory [package_inventory] \
        workspace_root $workspace_root \
        packaging_workspace [file join \
            $workspace_root ip_packaging project] \
        ip_repo_path [file join $workspace_root ip_repo] \
        vlnv_expectation [dict create \
            vendor zsr112.local \
            library protection \
            name protection_ip_axi_lite \
            version 0.3]]
}

proc ::stage1e::ip_packaging_adapter_tests::all_files {root} {
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

proc ::stage1e::ip_packaging_adapter_tests::run_all {} {
    variable invocation_log
    variable repository_root
    variable forced_vendor_readback
    variable current_project
    variable empty_session_behavior
    variable filesets
    variable current_core
    variable current_cores
    variable file_groups
    variable file_group_files
    variable project_open
    variable close_count
    variable save_core_count
    variable saved_core
    variable saved_core_identity
    variable added_files
    variable forbidden_count

    run_case STAGE1E_IP_PACKAGING_DEFINITION_ONLY {
    reset_mock
    assert_true [llength \
        [info commands ::stage1e::ip_packaging::run]] \
        {Adapter run procedure was not defined.}
    assert_equal {} $invocation_log \
        {Sourcing the adapter invoked a Vivado command}
}

    run_case STAGE1E_IP_PACKAGING_MISSING_CONTEXT_REJECTION {
    reset_mock
    set context [valid_context missing_context]
    dict unset context package_inventory
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {Missing context rejection status}
    assert_equal CONTEXT_FIELD_MISSING [first_error_code $result] \
        {Missing context rejection code}
    assert_equal 0 [dict get $result vivado_invoked] \
        {Missing context invoked Vivado}
    assert_equal {} $invocation_log \
        {Missing context reached the mock backend}
    }

    run_case STAGE1E_IP_PACKAGING_MISSING_CDC_CONSTRAINT_REJECTION {
    reset_mock
    set context [valid_context missing_cdc_constraint]
    dict set context package_inventory constraint_paths {}
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {Missing CDC constraint rejection status}
    assert_equal PACKAGE_CONSTRAINTS_EMPTY [first_error_code $result] \
        {Missing CDC constraint rejection code}
    assert_equal {} $invocation_log \
        {Missing CDC constraint reached the Vivado backend}
    }

    run_case STAGE1E_IP_PACKAGING_FIFO_PARAMETER_GUARD_REJECTION {
    reset_mock
    set context [valid_context invalid_fifo_parameter]
    dict set context package_inventory user_parameters ADC_FIFO_ADDR_WIDTH 1
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {FIFO parameter guard rejection status}
    assert_equal PACKAGE_PARAMETER_GUARD [first_error_code $result] \
        {FIFO parameter guard rejection code}
    assert_equal {} $invocation_log \
        {FIFO parameter guard reached the Vivado backend}
    }

    run_case STAGE1E_IP_PACKAGING_DATA_PARAMETER_GUARD_REJECTION {
    reset_mock
    set context [valid_context invalid_data_parameter]
    dict set context package_inventory user_parameters DATA_WIDTH 0
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {DATA_WIDTH guard rejection status}
    assert_equal PACKAGE_INVENTORY_INVALID [first_error_code $result] \
        {DATA_WIDTH guard rejection code}
    assert_equal {} $invocation_log \
        {DATA_WIDTH guard reached the Vivado backend}
    }

    run_case STAGE1E_IP_PACKAGING_TOP_DEPENDENCY_CLOSURE_REJECTION {
    reset_mock
    set top_path [file join \
        $repository_root rtl protection_ip_top_axi_lite.v]
    write_text $top_path [join {
        {module protection_ip_top_axi_lite;}
        {  reset_release_sync u_reset_release_sync ();}
        {endmodule}
        {}
    } "\n"]
    set context [valid_context top_dependency_missing]
    set result [::stage1e::ip_packaging::run $context]
    write_text $top_path \
        "module protection_ip_top_axi_lite; endmodule\n"
    assert_result_status $result BLOCKED \
        {Top dependency closure rejection status}
    assert_equal PACKAGE_SOURCE_DEPENDENCY_MISSING [first_error_code $result] \
        {Top dependency closure rejection code}
    assert_equal 0 [dict get $result vivado_invoked] \
        {Top dependency closure rejection invoked Vivado}
    assert_equal {} $invocation_log \
        {Top dependency closure rejection reached the mock backend}
    }

    run_case STAGE1E_IP_PACKAGING_PARAMETERIZED_DEPENDENCY_CLOSURE_REJECTION {
    reset_mock
    set top_path [file join \
        $repository_root rtl protection_ip_top_axi_lite.v]
    write_text $top_path [join {
        {module protection_ip_top_axi_lite;}
        {  omitted_parameterized_module #(}
        {    .WIDTH(1)}
        {  ) u_missing ();}
        {endmodule}
        {}
    } "\n"]
    set context [valid_context parameterized_dependency_missing]
    set result [::stage1e::ip_packaging::run $context]
    write_text $top_path \
        "module protection_ip_top_axi_lite; endmodule\n"
    assert_result_status $result BLOCKED \
        {Parameterized dependency closure rejection status}
    assert_equal PACKAGE_SOURCE_DEPENDENCY_MISSING [first_error_code $result] \
        {Parameterized dependency closure rejection code}
    assert_equal 0 [dict get $result vivado_invoked] \
        {Parameterized dependency closure rejection invoked Vivado}
    assert_equal {} $invocation_log \
        {Parameterized dependency closure rejection reached the mock backend}
    }

    run_case STAGE1E_IP_PACKAGING_AUTHORIZATION_MISMATCH_REJECTION {
    reset_mock
    set context [valid_context authorization_mismatch]
    dict set context authorization operation vivado_project::create
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result BLOCKED \
        {Authorization mismatch rejection status}
    assert_equal AUTHORIZATION_MISMATCH [first_error_code $result] \
        {Authorization mismatch rejection code}
    assert_equal 0 [dict get $result vivado_invoked] \
        {Authorization mismatch invoked Vivado}
    assert_equal {} $invocation_log \
        {Authorization mismatch reached the mock backend}
}

    run_case STAGE1E_IP_PACKAGING_PATH_CONTAINMENT_REJECTION {
    reset_mock
    set context [valid_context path_containment]
    dict set context packaging_workspace [file join \
        $repository_root generated packaging_project]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {Path containment rejection status}
    assert_equal PATH_CONTAINMENT_VIOLATION [first_error_code $result] \
        {Path containment rejection code}
    assert_equal {} $invocation_log \
        {Path containment rejection reached the mock backend}
}

    run_case STAGE1E_IP_PACKAGING_VLNV_MISMATCH_REJECTION {
    reset_mock
    set context [valid_context vlnv_mismatch]
    set forced_vendor_readback unexpected.vendor
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {VLNV mismatch rejection status}
    assert_equal VLNV_MISMATCH [first_error_code $result] \
        {VLNV mismatch rejection code}
    assert_equal 1 [dict get $result vivado_invoked] \
        {VLNV mismatch did not reach the isolated mock}
    assert_equal 1 $close_count \
        {VLNV mismatch did not close the packaging project}
    assert_true [dict get $result cleanup_result completed] \
        {VLNV mismatch cleanup did not complete}
    assert_true [expr {
        ![file exists [dict get $context packaging_workspace]]
    }] \
        {VLNV mismatch retained the failed packaging workspace}
    assert_true [expr {![file exists [file join \
        [dict get $context ip_repo_path] protection_ip_axi_lite]]}] \
        {VLNV mismatch retained partial packaged IP output}
}

    run_case STAGE1E_IP_PACKAGING_PACKAGE_CREATES_ONE_CORE {
    reset_mock
    set current_cores {core0}
    set context [valid_context exactly_one_core]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {Exactly-one-core status}
    assert_true [dict exists $result produced_identities package_identity] \
        {Exactly-one-core run did not produce package identity}
    assert_true [expr {
        [lsearch -exact -index 0 $invocation_log ipx::current_core] >= 0
    }] {Exactly-one-core run did not bind the current packaged core}
    assert_true [expr {
        [lsearch -exact -index 0 $invocation_log ipx::get_cores] < 0
    }] {Exactly-one-core run used the unsupported project-core query}
    set package_invocations {}
    foreach invocation $invocation_log {
        if {[lindex $invocation 0] eq {ipx::package_project}} {
            lappend package_invocations $invocation
        }
    }
    assert_equal 1 [llength $package_invocations] \
        {Package project was not invoked exactly once}
    assert_equal true [option_value \
        [lrange [lindex $package_invocations 0] 1 end] -set_current] \
        {Package project did not request current-core binding}
    set resolver_body [info body \
        ::stage1e::ip_packaging::_resolve_target_core]
    assert_true [expr {[string first {llength $core} $resolver_body] < 0}] \
        {Target-core resolver treats the opaque core handle as a list}
}

    run_case STAGE1E_IP_PACKAGING_IMPLEMENTATION_ONLY_CONSTRAINTS {
    reset_mock
    set context [valid_context implementation_only_constraints]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS \
        {Implementation-only constraint packaging status}
    set synthesis [dict get $file_groups xilinx_anylanguagesynthesis]
    set implementation [dict get $file_groups xilinx_implementation]
    assert_equal implementation \
        [get_property_value $implementation TYPE] \
        {Implementation file-group type}

    set constraint_files {}
    foreach relative_path [dict get $context package_inventory \
        constraint_paths] {
        lappend constraint_files [file join \
            [dict get $context repository_root] \
            {*}[split $relative_path /]]
    }
    ::stage1e::ip_packaging::_stage_implementation_constraints \
        $current_core $constraint_files

    foreach source $constraint_files {
        set relative_path "src/[file tail $source]"
        set synthesis_matches {}
        if {[dict exists $file_group_files $synthesis]} {
            foreach file_object [dict get $file_group_files $synthesis] {
                if {[get_property_value $file_object NAME] eq $relative_path} {
                    lappend synthesis_matches $file_object
                }
            }
        }
        set implementation_matches {}
        if {[dict exists $file_group_files $implementation]} {
            foreach file_object [dict get \
                $file_group_files $implementation] {
                if {[get_property_value $file_object NAME] eq $relative_path} {
                    lappend implementation_matches $file_object
                }
            }
        }
        set total_occurrences 0
        foreach group [dict values $file_groups] {
            if {![dict exists $file_group_files $group]} {
                continue
            }
            foreach file_object [dict get $file_group_files $group] {
                if {[get_property_value $file_object NAME] eq $relative_path} {
                    incr total_occurrences
                }
            }
        }
        assert_equal 0 [llength $synthesis_matches] \
            "Constraint remained in synthesis: $relative_path"
        assert_equal 1 [llength $implementation_matches] \
            "Constraint implementation membership: $relative_path"
        assert_equal 1 $total_occurrences \
            "Constraint total IP-XACT occurrences: $relative_path"
        set file_object [lindex $implementation_matches 0]
        assert_equal xdc [get_property_value $file_object type] \
            "Constraint IP-XACT type: $relative_path"
        assert_equal late [get_property_value \
            $file_object processing_order] \
            "Constraint IP-XACT processing order: $relative_path"
    }
    set synthesis_properties [property_invocations USED_IN_SYNTHESIS]
    assert_equal 2 [llength $synthesis_properties] \
        {Constraint synthesis-use property count}
    foreach invocation $synthesis_properties {
        assert_equal false [lindex $invocation 2] \
            {Constraint synthesis-use property value}
    }
}

    run_case STAGE1E_IP_PACKAGING_OPAQUE_CORE_HANDLE_PASS {
    reset_mock
    set opaque_core \
        {zsr112.local:protection:protection_ip_top_axi_lite:1.0 (protection_ip_top_axi_lite_v1_0)}
    assert_true [expr {[llength $opaque_core] > 1}] \
        {Opaque-core test handle does not model the Vivado string form}
    set current_cores [list $opaque_core]
    set context [valid_context opaque_core_handle]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {Opaque-core handle status}
    assert_equal $opaque_core $saved_core \
        {Opaque current-core object was not preserved through save}
    assert_equal zsr112.local:protection:protection_ip_axi_lite:0.3 \
        [dict get $result evidence_references metadata_readback \
            saved_core_identity vlnv] \
        {Opaque current-core saved identity}
}

    run_case STAGE1E_IP_PACKAGING_ZERO_CORE_REJECTION {
    reset_mock
    set current_cores {}
    set context [valid_context zero_core]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {Zero-core rejection status}
    assert_equal PACKAGED_CORE_NOT_FOUND [first_error_code $result] \
        {Zero-core rejection code}
    assert_equal 1 $close_count \
        {Zero-core rejection did not close the packaging project}
    assert_true [dict get $result cleanup_result completed] \
        {Zero-core rejection cleanup did not complete}
}

    run_case STAGE1E_IP_PACKAGING_MULTIPLE_CORE_REJECTION {
    reset_mock
    set current_cores {core0 core1}
    set context [valid_context multiple_core]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {Multiple-core rejection status}
    assert_equal PACKAGED_CORE_AMBIGUOUS [first_error_code $result] \
        {Multiple-core rejection code}
    assert_equal 1 $close_count \
        {Multiple-core rejection did not close the packaging project}
    assert_true [dict get $result cleanup_result completed] \
        {Multiple-core rejection cleanup did not complete}
}

    run_case STAGE1E_IP_PACKAGING_SAVED_CORE_IDENTITY {
    reset_mock
    set current_cores {core0}
    set context [valid_context saved_core_identity]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {Saved-core identity status}
    assert_equal 1 $save_core_count \
        {Packaged core was not saved exactly once}
    assert_equal core0 $saved_core \
        {Save did not target the bound packaged core}
    set expected_saved_identity [dict create \
        vendor zsr112.local \
        library protection \
        name protection_ip_axi_lite \
        version 0.3 \
        vlnv zsr112.local:protection:protection_ip_axi_lite:0.3]
    assert_equal $expected_saved_identity $saved_core_identity \
        {Saved core mock identity}
    set metadata [dict get \
        $result evidence_references metadata_readback]
    assert_equal 1 [dict get $metadata core_persisted] \
        {Result evidence does not prove core persistence}
    assert_equal $saved_core_identity \
        [dict get $metadata saved_core_identity] \
        {Saved core identity evidence mismatch}
    set component_xml [dict get $result evidence_references component_xml]
    set channel [open $component_xml r]
    set component_text [read $channel]
    close $channel
    assert_true [expr {[string first \
        {zsr112.local:protection:protection_ip_axi_lite:0.3} \
        $component_text] >= 0}] \
        {Persisted component.xml does not contain the saved VLNV}
    set package_index [lsearch -exact -index 0 \
        $invocation_log ipx::package_project]
    set bind_index [lsearch -exact -index 0 \
        $invocation_log ipx::current_core]
    set integrity_index [lsearch -exact -index 0 \
        $invocation_log ipx::check_integrity]
    set save_index [lsearch -exact -index 0 \
        $invocation_log ipx::save_core]
    set close_index [lsearch -exact -index 0 \
        $invocation_log close_project]
    assert_true [expr {
        $package_index >= 0 && $package_index < $bind_index &&
        $bind_index < $integrity_index && $integrity_index < $save_index &&
        $save_index < $close_index
    }] {Package, bind, save, and close lifecycle order is invalid}
}

    run_case STAGE1E_IP_PACKAGING_WRONG_CORE_VLNV_REJECTION {
    reset_mock
    set current_cores {core0}
    set forced_vendor_readback unexpected.vendor
    set context [valid_context wrong_core_vlnv]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {Wrong-core-VLNV rejection status}
    assert_equal VLNV_MISMATCH [first_error_code $result] \
        {Wrong-core-VLNV rejection code}
    assert_equal 1 $close_count \
        {Wrong-core-VLNV rejection did not close the packaging project}
    assert_true [dict get $result cleanup_result completed] \
        {Wrong-core-VLNV rejection cleanup did not complete}
}

    run_case STAGE1E_IP_PACKAGING_EMPTY_PROJECT_HANDLE_CONTINUES {
    reset_mock
    set empty_session_behavior RETURN_EMPTY
    set context [valid_context empty_project_handle]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS \
        {Empty project handle packaging status}
    assert_equal 1 $close_count \
        {Empty project handle did not continue through packaging and close}
    assert_true [dict exists $result produced_identities package_identity] \
        {Empty project handle did not produce package identity}
    assert_equal 1 [llength [property_invocations board_part]] \
        {Empty project handle did not reach board-part assignment}
    set top_invocations [property_invocations top]
    assert_equal 1 [llength $top_invocations] \
        {Empty project handle did not reach top assignment}
    assert_equal fileset:sources_1 [lindex [lindex $top_invocations 0] 3] \
        {Empty project handle used a plain fileset target}
}

    run_case STAGE1E_IP_PACKAGING_CORETCL_NO_PROJECT_CONTINUES {
    reset_mock
    set empty_session_behavior RAISE_CORETCL_NO_PROJECT
    set context [valid_context coretcl_no_project]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS \
        {Coretcl no-project packaging status}
    assert_equal 1 $close_count \
        {Coretcl no-project condition did not continue and close}
    assert_true [dict exists $result produced_identities package_identity] \
        {Coretcl no-project condition did not produce package identity}
    assert_equal 1 [llength [property_invocations board_part]] \
        {Coretcl no-project condition did not reach board-part assignment}
    set top_invocations [property_invocations top]
    assert_equal 1 [llength $top_invocations] \
        {Coretcl no-project condition did not reach top assignment}
    assert_equal fileset:sources_1 [lindex [lindex $top_invocations 0] 3] \
        {Coretcl no-project condition used a plain fileset target}
}

    run_case STAGE1E_IP_PACKAGING_FILESET_OBJECT_RESOLUTION {
    reset_mock
    set context [valid_context fileset_object_resolution]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {Fileset object resolution status}
    set resolutions {}
    foreach invocation $invocation_log {
        if {[lindex $invocation 0] eq {get_filesets}} {
            lappend resolutions $invocation
        }
    }
    assert_true [expr {[llength $resolutions] >= 3}] \
        {Fileset was not resolved for validation, assignment, and readback}
    foreach invocation $resolutions {
        assert_equal sources_1 [lindex $invocation end] \
            {Fileset resolution name}
    }
    set helper_body [info body \
        ::stage1e::ip_packaging::backend::set_fileset_property]
    assert_true [expr {
        [string first {[get_filesets $fileset_name]} $helper_body] >= 0
    }] {Production fileset-property helper does not resolve get_filesets}
}

    run_case STAGE1E_IP_PACKAGING_TOP_ASSIGNMENT {
    reset_mock
    set context [valid_context top_assignment]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {Top assignment status}
    set invocations [property_invocations top]
    assert_equal 1 [llength $invocations] \
        {Top module was not assigned exactly once}
    set invocation [lindex $invocations 0]
    assert_equal protection_ip_top_axi_lite [lindex $invocation 2] \
        {Top assignment value}
    assert_equal fileset:sources_1 [lindex $invocation 3] \
        {Top assignment fileset object}
    assert_true [expr {[lindex $invocation 3] ne {sources_1}}] \
        {Top assignment passed the plain fileset name as an object}
}

    run_case STAGE1E_IP_PACKAGING_INVALID_FILESET_REJECTION {
    reset_mock
    set filesets [dict create]
    set context [valid_context invalid_fileset]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL {Invalid fileset rejection status}
    assert_equal VIVADO_OBJECT_CARDINALITY [first_error_code $result] \
        {Invalid fileset rejection code}
    assert_equal 0 [llength [property_invocations top]] \
        {Invalid fileset reached top assignment}
    assert_equal 1 $close_count \
        {Invalid fileset did not close the packaging project}
    assert_true [dict get $result cleanup_result completed] \
        {Invalid fileset cleanup did not complete}
}

    run_case STAGE1E_IP_PACKAGING_BOARD_PART_ASSIGNMENT {
    reset_mock
    set context [valid_context board_part_assignment]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {Board-part assignment status}
    set invocations [property_invocations board_part]
    assert_equal 1 [llength $invocations] \
        {Board part was not assigned exactly once}
    set invocation [lindex $invocations 0]
    assert_equal tul.com.tw:pynq-z2:part0:1.0 [lindex $invocation 2] \
        {Board-part assignment value}
    assert_equal project:protection_ip_axi_lite_packaging_tmp \
        [lindex $invocation 3] {Board-part assignment project object}
}

    run_case STAGE1E_IP_PACKAGING_PROJECT_PROPERTY_TARGET {
    reset_mock
    set context [valid_context project_property_target]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {Project-property target status}
    set expected_project project:protection_ip_axi_lite_packaging_tmp
    foreach property {board_part target_language} {
        set invocations [property_invocations $property]
        assert_equal 1 [llength $invocations] \
            "Project property assignment count: $property"
        assert_equal $expected_project [lindex [lindex $invocations 0] 3] \
            "Project property object target: $property"
    }
    set helper_body [info body \
        ::stage1e::ip_packaging::backend::set_current_project_property]
    assert_true [expr {
        [string first \
            {set_property $property $value [current_project]} \
            $helper_body] >= 0
    }] {Production project-property helper does not use [current_project]}
}

    run_case STAGE1E_IP_PACKAGING_SET_PROPERTY_ARGUMENT_ORDER {
    reset_mock
    set context [valid_context set_property_argument_order]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {set_property argument-order status}
    set set_property_count 0
    foreach invocation $invocation_log {
        if {[lindex $invocation 0] ne {set_property}} {
            continue
        }
        incr set_property_count
        assert_equal 4 [llength $invocation] \
            {set_property command/property/value/object arity}
        assert_true [expr {[string trim [lindex $invocation 1]] ne {}}] \
            {set_property property is empty}
        assert_true [expr {[string trim [lindex $invocation 3]] ne {}}] \
            {set_property object target is empty}
    }
    assert_true [expr {$set_property_count > 0}] \
        {Packaging did not exercise any set_property command}
}

    run_case STAGE1E_IP_PACKAGING_EXISTING_PROJECT_REJECTS {
    reset_mock
    set current_project project:ambient
    set project_open 1
    set context [valid_context existing_project]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result BLOCKED \
        {Existing project rejection status}
    assert_equal PACKAGING_SESSION_OCCUPIED [first_error_code $result] \
        {Existing project rejection code}
    assert_equal 0 $close_count \
        {Adapter closed an existing project it did not own}
    assert_equal 1 $project_open \
        {Adapter changed the existing project ownership state}
    assert_true [expr {
        [lsearch -exact -index 0 $invocation_log create_project] < 0
    }] {Adapter attempted to create a project in an occupied session}
    assert_equal 0 [llength [property_invocations board_part]] \
        {Existing project rejection changed the ambient board part}
    assert_equal 0 [llength [property_invocations top]] \
        {Existing project rejection changed the ambient fileset top}
    assert_true [expr {
        [lsearch -exact -index 0 $invocation_log get_filesets] < 0
    }] {Existing project rejection attempted fileset resolution}
}

    run_case STAGE1E_IP_PACKAGING_UNEXPECTED_PROJECT_QUERY_FAILS {
    reset_mock
    set empty_session_behavior RAISE_UNEXPECTED
    set context [valid_context unexpected_project_query]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result FAIL \
        {Unexpected project query failure status}
    assert_equal PACKAGING_PROJECT_QUERY_FAILED [first_error_code $result] \
        {Unexpected project query failure code}
    assert_equal 0 $close_count \
        {Unexpected query failure closed an unowned project}
    assert_true [dict get $result cleanup_result completed] \
        {Unexpected query failure cleanup did not complete}
    assert_true [expr {
        [lsearch -exact -index 0 $invocation_log create_project] < 0
    }] {Unexpected query failure reached project creation}
}

    run_case STAGE1E_IP_PACKAGING_PACKAGE_IDENTITY_GENERATION {
    reset_mock
    set context [valid_context package_identity]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {Package identity generation status}
    set package_identity [dict get \
        $result produced_identities package_identity]
    set ip_repo_identity [dict get \
        $result produced_identities ip_repo_identity]
    foreach field {
        source_inventory_sha256
        package_inventory_sha256
        component_metadata_sha256
        generated_inventory_sha256
        component_xml_sha256
        package_sha256
    } {
        assert_sha256 [dict get $package_identity $field] \
            "Package identity field $field"
    }
    assert_sha256 [dict get $ip_repo_identity ip_repo_sha256] \
        {IP repository identity digest}
    assert_equal [dict get $context execution_id] \
        [dict get $package_identity execution_id] \
        {Package identity execution binding}
    assert_equal zsr112.local:protection:protection_ip_axi_lite:0.3 \
        [dict get $package_identity vlnv] {Package identity VLNV}
    assert_equal 1 $close_count \
        {Successful packaging did not close the temporary project}
    assert_true [file isfile [dict get \
        $result evidence_references component_xml]] \
        {Package identity evidence lacks component.xml}
    assert_equal 4 [llength $added_files] \
        {Adapter did not package exactly the approved source/constraint set}
    assert_equal 2 [llength [property_invocations value_validation_type]] \
        {Packaged parameter guard validation types were not both configured}
    assert_equal 2 [llength [property_invocations \
        value_validation_range_minimum]] \
        {Packaged parameter guard minimums were not both configured}
}

    run_case STAGE1E_IP_PACKAGING_STRUCTURED_RESULT_SCHEMA {
    reset_mock
    set context [valid_context structured_result]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {Structured result status}
    set required_result_keys [lsort -dictionary {
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
        vivado_invoked
        artifacts_generated
        artifact_generation_performed
        artifact_publication_performed
    }]
    assert_equal $required_result_keys \
        [lsort -dictionary [dict keys $result]] \
        {Structured result keys}
    assert_equal stage1e-ip-packaging-result-v1 \
        [dict get $result schema_version] {Structured result schema version}
    assert_equal stage1e::ip_packaging::run \
        [dict get $result operation] {Structured result operation}
    assert_equal IP_PACKAGING [dict get $result phase] \
        {Structured result phase}
    assert_equal {} [dict get $result errors] \
        {Successful structured result contains errors}
    assert_true [dict get $result cleanup_result project_closed] \
        {Structured result does not prove project close}
}

    run_case STAGE1E_IP_PACKAGING_NO_ARTIFACT_GENERATION {
    reset_mock
    set context [valid_context no_artifacts]
    set result [::stage1e::ip_packaging::run $context]
    assert_result_status $result PASS {No-artifact packaging status}
    foreach field {
        artifacts_generated
        artifact_generation_performed
        artifact_publication_performed
    } {
        assert_equal 0 [dict get $result $field] \
            "No-artifact result field $field"
    }
    assert_equal 0 $forbidden_count \
        {Packaging invoked a forbidden build/artifact command}
    foreach invocation $invocation_log {
        set command [lindex $invocation 0]
        assert_true [expr {$command ni {
            create_bd_design
            open_bd_design
            validate_bd_design
            save_bd_design
            launch_runs
            synth_design
            opt_design
            place_design
            route_design
            write_bitstream
            write_hw_platform
            write_debug_probes
            export_hardware
        }}] "Forbidden command present in invocation log: $command"
    }
    set forbidden_extensions {.bit .hwh .xsa .ltx .dcp}
    foreach path [all_files [dict get $context workspace_root]] {
        assert_true [expr {
            [string tolower [file extension $path]] ni $forbidden_extensions
        }] "Mock packaging generated a forbidden artifact: $path"
    }
    }
}

set test_status [catch {
    ::stage1e::ip_packaging_adapter_tests::prepare_suite
    ::stage1e::ip_packaging_adapter_tests::run_all
} test_error test_options]
set cleanup_status [catch {
    ::stage1e::ip_packaging_adapter_tests::safe_cleanup
} cleanup_error cleanup_options]
rename ::stage1e::ip_packaging::backend::invoke {}
rename ::stage1e::ip_packaging::backend::_production_invoke \
    ::stage1e::ip_packaging::backend::invoke
rename ::current_project {}
rename ::set_property {}
rename ::get_property {}
rename ::get_filesets {}

if {$test_status != 0} {
    incr ::stage1e::ip_packaging_adapter_tests::fail_count
    puts stderr "TEST SUITE: FAIL: $test_error"
    if {[dict exists $test_options -errorinfo]} {
        puts stderr [dict get $test_options -errorinfo]
    }
}

if {$cleanup_status != 0} {
    incr ::stage1e::ip_packaging_adapter_tests::fail_count
    puts stderr "TEST CLEANUP: FAIL: $cleanup_error"
    if {[dict exists $cleanup_options -errorinfo]} {
        puts stderr [dict get $cleanup_options -errorinfo]
    }
}

puts "SUMMARY PASS=$::stage1e::ip_packaging_adapter_tests::pass_count FAIL=$::stage1e::ip_packaging_adapter_tests::fail_count"
if {$::stage1e::ip_packaging_adapter_tests::fail_count != 0} {
    exit 1
}
exit 0
