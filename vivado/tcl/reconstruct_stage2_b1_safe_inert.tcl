# Compact Stage2 B1 public structural reconstruction adapter.
#
# DERIVATION_ID=STAGE2_B1_PUBLIC_RECONSTRUCTION_ADAPTER_V1
# DERIVED_FROM_CURRENT_ENGINEERING_PRODUCTION_AUTHORITY=YES
# NEW_PARALLEL_PRODUCTION_AUTHORITY=NO
# LIVE_ENGINEERING_AUTHORITY_PATH=fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl
# LIVE_ENGINEERING_AUTHORITY_SHA256=5da3f9ee6f3c6ef9069e9e8074f9f22213b797646d143bbc913021cbbd52c2ad
# ENGINEERING_COMMIT=9c5e6f6ac7dc311f12755c8b1713433d35e39bff
# PROFILE=SAFE_INERT
#
# This adapter packages the current IP, creates the accepted B1 SAFE_INERT
# block-design topology, validates the finite public contract, generates BD
# output products and the HDL wrapper, and sets the project top. It deliberately
# stops before synthesis, implementation, routing, bitstream, XSA, Hardware
# Manager, or board actions.
#
# Run with Vivado 2024.1 after setting PROTECTION_IP_VIVADO_BUILD_ROOT to a
# fresh external short path. The directory may be absent or empty.

namespace eval ::stage2_b1_public_adapter_v1 {
    variable expected_version_pattern {*Vivado v2024.1*}
    variable part xc7z020clg400-1
    variable board_part tul.com.tw:pynq-z2:part0:1.0
    variable protection_vlnv zsr112.local:protection:protection_ip_axi_lite:0.3
    variable bd_name protection_system
    variable project_top protection_system_wrapper
    variable required_cells {
        axi_gpio_stage1d_0
        dcm_locked_const
        proc_sys_reset_0
        processing_system7_0
        protection_ip_axi_lite_0
        sample_valid_const
        smartconnect_0
        system_ila_stage2b_0
        xlslice_stage1d_ch1
        xlslice_stage1d_ch2
    }
}

proc ::stage2_b1_public_adapter_v1::_raise {code message} {
    return -code error -errorcode [list STAGE2 B1 PUBLIC_ADAPTER_V1 $code] $message
}

proc ::stage2_b1_public_adapter_v1::_canonical_path {path} {
    return [string map {\\ /} [file normalize $path]]
}

proc ::stage2_b1_public_adapter_v1::_path_is_within {parent child} {
    set parent [string trimright [string tolower [_canonical_path $parent]] /]
    set child [string tolower [_canonical_path $child]]
    return [expr {$child eq $parent || [string first "${parent}/" $child] == 0}]
}

proc ::stage2_b1_public_adapter_v1::_require_file {path label} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise INPUT_MISSING "$label is missing: $path"
    }
    return $path
}

proc ::stage2_b1_public_adapter_v1::_require_unique {objects label} {
    if {[llength $objects] != 1} {
        _raise OBJECT_IDENTITY "$label must resolve to exactly one object; actual=[llength $objects]"
    }
    return [lindex $objects 0]
}

proc ::stage2_b1_public_adapter_v1::_require_bd_cell {name} {
    return [_require_unique [get_bd_cells -quiet $name] "BD cell $name"]
}

proc ::stage2_b1_public_adapter_v1::_require_bd_pin {path} {
    return [_require_unique [get_bd_pins -quiet $path] "BD pin $path"]
}

proc ::stage2_b1_public_adapter_v1::_require_bd_intf_pin {path} {
    return [_require_unique [get_bd_intf_pins -quiet $path] "BD interface pin $path"]
}

proc ::stage2_b1_public_adapter_v1::_require_ipdef {vlnv} {
    set definition [_require_unique [get_ipdefs -all -quiet $vlnv] "IP definition $vlnv"]
    if {[get_property VLNV $definition] ne $vlnv} {
        _raise IP_CATALOG "Resolved IP definition differs from $vlnv"
    }
    return $definition
}

proc ::stage2_b1_public_adapter_v1::_numeric_equal {actual expected} {
    if {![catch {expr {wide($actual)}} left] &&
        ![catch {expr {wide($expected)}} right]} {
        return [expr {$left == $right}]
    }
    return [expr {$actual eq $expected}]
}

proc ::stage2_b1_public_adapter_v1::_assert_property {object property expected label} {
    set actual [get_property $property $object]
    if {![_numeric_equal $actual $expected]} {
        _raise TOPOLOGY_PROPERTY "$label $property mismatch: actual=$actual expected=$expected"
    }
    return $actual
}

proc ::stage2_b1_public_adapter_v1::_object_path {object} {
    return [string trimleft [string map {\\ /} $object] /]
}

proc ::stage2_b1_public_adapter_v1::_scalar_net_for_pin {path} {
    set pin [_require_bd_pin $path]
    return [_require_unique [get_bd_nets -quiet -of_objects $pin] "Scalar net for $path"]
}

proc ::stage2_b1_public_adapter_v1::_interface_net_for_pin {path} {
    set pin [_require_bd_intf_pin $path]
    return [_require_unique [get_bd_intf_nets -quiet -of_objects $pin] "Interface net for $path"]
}

proc ::stage2_b1_public_adapter_v1::_connect_pin_preserving_net {source_path sink_path} {
    set source [_require_bd_pin $source_path]
    set sink [_require_bd_pin $sink_path]
    set nets [get_bd_nets -quiet -of_objects $source]
    if {[llength $nets] == 0} {
        connect_bd_net $source $sink
    } elseif {[llength $nets] == 1} {
        connect_bd_net -net [lindex $nets 0] $sink
    } else {
        _raise TOPOLOGY_CONNECTION "Source pin has multiple scalar nets: $source_path"
    }
}

proc ::stage2_b1_public_adapter_v1::_assert_same_scalar_net {paths label} {
    set expected [_scalar_net_for_pin [lindex $paths 0]]
    foreach path [lrange $paths 1 end] {
        if {[_scalar_net_for_pin $path] ne $expected} {
            _raise TOPOLOGY_CONNECTION "$label does not share one scalar net"
        }
    }
    return $expected
}

proc ::stage2_b1_public_adapter_v1::_assert_exact_scalar_net {paths label} {
    set expected [_assert_same_scalar_net $paths $label]
    set actual {}
    foreach pin [get_bd_pins -quiet -of_objects $expected] {
        lappend actual [_object_path $pin]
    }
    if {[lsort -dictionary $actual] ne [lsort -dictionary $paths]} {
        _raise TOPOLOGY_CONNECTION "$label scalar-net membership is not exact: actual=$actual expected=$paths"
    }
    return $expected
}

proc ::stage2_b1_public_adapter_v1::_assert_exact_interface_net {paths label} {
    set expected [_interface_net_for_pin [lindex $paths 0]]
    foreach path [lrange $paths 1 end] {
        if {[_interface_net_for_pin $path] ne $expected} {
            _raise TOPOLOGY_CONNECTION "$label does not share one interface net"
        }
    }
    set actual {}
    foreach pin [get_bd_intf_pins -quiet -of_objects $expected] {
        lappend actual [_object_path $pin]
    }
    if {[lsort -dictionary $actual] ne [lsort -dictionary $paths]} {
        _raise TOPOLOGY_CONNECTION "$label interface-net membership is not exact: actual=$actual expected=$paths"
    }
    return $expected
}

proc ::stage2_b1_public_adapter_v1::_ensure_bus_interface {core name bus abstraction mode} {
    set value [ipx::get_bus_interfaces $name -of_objects $core -quiet]
    if {[llength $value] == 0} {
        set value [ipx::add_bus_interface $name $core]
    }
    set_property bus_type_vlnv $bus $value
    set_property abstraction_type_vlnv $abstraction $value
    set_property interface_mode $mode $value
    return $value
}

proc ::stage2_b1_public_adapter_v1::_ensure_port_map {busif logical physical} {
    set value [ipx::get_port_maps $logical -of_objects $busif -quiet]
    if {[llength $value] == 0} {
        set value [ipx::add_port_map $logical $busif]
    }
    set_property physical_name $physical $value
}

proc ::stage2_b1_public_adapter_v1::_ensure_bus_parameter {busif name value} {
    set parameter [ipx::get_bus_parameters $name -of_objects $busif -quiet]
    if {[llength $parameter] == 0} {
        set parameter [ipx::add_bus_parameter $name $busif]
    }
    set_property value $value $parameter
}

proc ::stage2_b1_public_adapter_v1::_rtl_files {repo_root} {
    set rtl [file join $repo_root rtl]
    set files [list \
        [file join $rtl adc_sample_cdc_bridge.v] \
        [file join $rtl adc_sample_code_normalizer.sv] \
        [file join $rtl async_fifo_gray.v] \
        [file join $rtl source_observability_cdc.v] \
        [file join $rtl transaction_destination_observer.v] \
        [file join $rtl transaction_source_observer.v] \
        [file join $rtl fault_defs.vh] \
        [file join $rtl generated protection_register_map.vh] \
        [file join $rtl generated stage2f_adc_source_profile.svh] \
        [file join $rtl reset_release_sync.v] \
        [file join $rtl current_compare_dual.v] \
        [file join $rtl fault_classifier.v] \
        [file join $rtl protection_core_top.v] \
        [file join $rtl protection_fsm.v] \
        [file join $rtl protection_ip_top_async_adc_axi_lite.v] \
        [file join $rtl protection_ip_top_axi_lite.v] \
        [file join $rtl protection_ip_top_reg_controlled.v] \
        [file join $rtl protection_reg_bank.v] \
        [file join $rtl pwm_gate.v] \
        [file join $rtl pwm_gen.v] \
        [file join $rtl sensor_health_monitor.v]]
    foreach path $files {
        _require_file $path {Packaged IP RTL source}
    }
    return $files
}

proc ::stage2_b1_public_adapter_v1::_constraint_files {repo_root} {
    set files [list \
        [file join $repo_root vivado constraints stage2d_async_adc_atomic_cdc.xdc] \
        [file join $repo_root vivado constraints stage2e_transaction_observability_cdc.xdc]]
    foreach path $files {
        _require_file $path {Packaged IP implementation constraint}
    }
    return $files
}

proc ::stage2_b1_public_adapter_v1::_stage_packaged_generated_header {
    core ip_root source relative_path file_type
} {
    _require_file $source {Generated packaged header source}
    set destination [file join $ip_root {*}[split $relative_path /]]
    file mkdir [file dirname $destination]
    if {![string equal -nocase [_canonical_path $source] [_canonical_path $destination]]} {
        file copy -force -- $source $destination
    }

    set source_name [_canonical_path $source]
    set flat_name "src/[file tail $source]"
    foreach group_name {
        xilinx_anylanguagesynthesis
        xilinx_anylanguagebehavioralsimulation
    } {
        set group [_require_unique \
            [ipx::get_file_groups $group_name -of_objects $core -quiet] \
            "Packaged IP file group $group_name"]
        foreach packaged_file [ipx::get_files -of_objects $group] {
            set name [get_property NAME $packaged_file]
            if {$name eq $flat_name ||
                ([file pathtype $name] eq {absolute} &&
                 [string equal -nocase [_canonical_path $name] $source_name])} {
                ipx::remove_file $name $group
            }
        }
        set packaged [ipx::get_files $relative_path -of_objects $group -quiet]
        if {[llength $packaged] == 0} {
            set packaged [ipx::add_file $relative_path $group]
        } elseif {[llength $packaged] != 1} {
            _raise PACKAGED_HEADER "Generated header is not unique: $relative_path"
        }
        set_property type $file_type $packaged
        set_property is_include true $packaged
        set_property dependency {src} $group
        if {[get_property DEPENDENCY $group] ne {src} ||
            [file pathtype [get_property DEPENDENCY $group]] ne {relative}} {
            _raise PACKAGED_HEADER "Include dependency is not portable: $group_name"
        }
    }

    set flat_path [file join $ip_root src [file tail $source]]
    if {[file exists $flat_path] &&
        ![string equal -nocase [_canonical_path $flat_path] [_canonical_path $destination]]} {
        file delete -force -- $flat_path
    }
    _require_file $destination {Nested packaged generated header}
}

proc ::stage2_b1_public_adapter_v1::_stage_packaged_implementation_constraints {
    core constraint_files
} {
    set synthesis [_require_unique \
        [ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects $core -quiet] \
        {Packaged IP synthesis file group}]
    set groups [ipx::get_file_groups xilinx_implementation -of_objects $core -quiet]
    if {[llength $groups] == 0} {
        set implementation [ipx::add_file_group xilinx_implementation -type implementation $core]
    } else {
        set implementation [_require_unique $groups {Packaged IP implementation file group}]
    }

    foreach source $constraint_files {
        set relative_path "src/[file tail $source]"
        set synthesis_files [ipx::get_files $relative_path -of_objects $synthesis -quiet]
        if {[llength $synthesis_files] > 1} {
            _raise PACKAGED_CONSTRAINT "Constraint is duplicated in synthesis: $relative_path"
        }
        if {[llength $synthesis_files] == 1} {
            ipx::remove_file $relative_path $synthesis
        }
        set implementation_files [ipx::get_files $relative_path -of_objects $implementation -quiet]
        if {[llength $implementation_files] == 0} {
            set implementation_file [ipx::add_file $relative_path $implementation]
        } elseif {[llength $implementation_files] == 1} {
            set implementation_file [lindex $implementation_files 0]
        } else {
            _raise PACKAGED_CONSTRAINT "Constraint is duplicated in implementation: $relative_path"
        }
        set_property type xdc $implementation_file
        set_property processing_order late $implementation_file

        set occurrence_count 0
        set owning_groups {}
        foreach group [ipx::get_file_groups -of_objects $core] {
            set files [ipx::get_files $relative_path -of_objects $group -quiet]
            incr occurrence_count [llength $files]
            if {[llength $files] != 0} {
                lappend owning_groups [get_property NAME $group]
            }
        }
        if {$occurrence_count != 1 || $owning_groups ne {xilinx_implementation}} {
            _raise PACKAGED_CONSTRAINT \
                "Constraint must occur once and only in xilinx_implementation: $relative_path"
        }
    }
}

proc ::stage2_b1_public_adapter_v1::_files_named {root basename} {
    set matches {}
    foreach path [glob -nocomplain -directory $root *] {
        if {[file isdirectory $path]} {
            set matches [concat $matches [_files_named $path $basename]]
        } elseif {[file tail $path] eq $basename} {
            lappend matches $path
        }
    }
    return $matches
}

proc ::stage2_b1_public_adapter_v1::_stage_package_sources {
    repo_root ip_root rtl_files constraint_files
} {
    set source_root [file join $ip_root src]
    file mkdir [file join $source_root generated]
    set staged_rtl {}
    foreach source $rtl_files {
        if {[file tail [file dirname $source]] eq {generated}} {
            set destination [file join $source_root generated [file tail $source]]
        } else {
            set destination [file join $source_root [file tail $source]]
        }
        file copy -force -- $source $destination
        lappend staged_rtl $destination
    }
    set staged_constraints {}
    foreach source $constraint_files {
        set destination [file join $source_root [file tail $source]]
        file copy -force -- $source $destination
        lappend staged_constraints $destination
    }
    return [dict create \
        rtl $staged_rtl \
        constraints $staged_constraints \
        fault_header [file join $source_root fault_defs.vh] \
        register_header [file join $source_root generated protection_register_map.vh] \
        profile_header [file join $source_root generated stage2f_adc_source_profile.svh]]
}

proc ::stage2_b1_public_adapter_v1::_validate_packaged_portability {
    core ip_root repo_root constraint_files
} {
    set absolute_source_references 0
    set absolute_include_dependencies 0
    foreach group [ipx::get_file_groups -of_objects $core] {
        set dependency [get_property DEPENDENCY $group]
        if {$dependency ne {} && [file pathtype $dependency] eq {absolute}} {
            incr absolute_include_dependencies
        }
        foreach packaged_file [ipx::get_files -of_objects $group] {
            if {[file pathtype [get_property NAME $packaged_file]] eq {absolute}} {
                incr absolute_source_references
            }
        }
    }

    set register_headers [_files_named $ip_root protection_register_map.vh]
    set profile_headers [_files_named $ip_root stage2f_adc_source_profile.svh]
    if {[llength $register_headers] != 1 || [llength $profile_headers] != 1} {
        _raise PACKAGED_HEADER \
            "Generated header tree occurrence mismatch: register=[llength $register_headers] profile=[llength $profile_headers]"
    }

    set constraint_duplicate_count 0
    foreach source $constraint_files {
        set basename [file tail $source]
        set tree_occurrences [_files_named $ip_root $basename]
        if {[llength $tree_occurrences] != 1} {
            incr constraint_duplicate_count [expr {abs([llength $tree_occurrences] - 1)}]
        }
        set relative_path "src/$basename"
        set group_occurrences 0
        set owning_groups {}
        foreach group [ipx::get_file_groups -of_objects $core] {
            set files [ipx::get_files $relative_path -of_objects $group -quiet]
            incr group_occurrences [llength $files]
            if {[llength $files] != 0} {
                lappend owning_groups [get_property NAME $group]
            }
        }
        if {$group_occurrences != 1 || $owning_groups ne {xilinx_implementation}} {
            incr constraint_duplicate_count
        }
    }

    set component [_require_file [file join $ip_root component.xml] {Packaged component.xml}]
    set channel [open $component r]
    fconfigure $channel -encoding utf-8 -translation auto
    set component_text [read $channel]
    close $channel
    set repo_forward [_canonical_path $repo_root]
    set repo_native [file normalize $repo_root]
    set component_absolute_references 0
    if {[string first $repo_forward $component_text] >= 0} {
        incr component_absolute_references
    }
    if {$repo_native ne $repo_forward && [string first $repo_native $component_text] >= 0} {
        incr component_absolute_references
    }

    if {$absolute_source_references != 0 ||
        $absolute_include_dependencies != 0 ||
        $constraint_duplicate_count != 0 ||
        $component_absolute_references != 0} {
        _raise PACKAGED_PORTABILITY \
            "Package is not portable: absolute_sources=$absolute_source_references absolute_dependencies=$absolute_include_dependencies constraint_duplicates=$constraint_duplicate_count component_absolute_refs=$component_absolute_references"
    }

    return [dict create \
        absolute_source_references $absolute_source_references \
        absolute_include_dependencies $absolute_include_dependencies \
        register_header_duplicates 0 \
        profile_header_duplicates 0 \
        constraint_duplicates $constraint_duplicate_count \
        include_dependency_relative 1 \
        constraint_scope_pass 1]
}

proc ::stage2_b1_public_adapter_v1::_package_ip {repo_root build_root} {
    variable part
    variable board_part
    variable protection_vlnv

    set package_project [file join $build_root ip_packaging_project]
    set ip_repo [file join $build_root ip_repo]
    set ip_root [file join $ip_repo protection_ip_axi_lite]
    file mkdir $ip_repo
    set rtl_files [_rtl_files $repo_root]
    set constraint_files [_constraint_files $repo_root]
    set staged [_stage_package_sources \
        $repo_root $ip_root $rtl_files $constraint_files]
    create_project stage2_b1_public_ip_packaging $package_project -part $part
    set_property board_part $board_part [current_project]
    set_property target_language Verilog [current_project]

    add_files -norecurse -fileset sources_1 [dict get $staged rtl]
    add_files -norecurse -fileset constrs_1 [dict get $staged constraints]

    set fault_header [dict get $staged fault_header]
    set register_header [dict get $staged register_header]
    set profile_header [dict get $staged profile_header]
    set staged_constraints [dict get $staged constraints]
    set register_ipxact [file join $repo_root vivado tcl generated protection_register_map_ipxact.tcl]
    _require_file $register_ipxact {Generated register-map IP-XACT metadata}
    source $register_ipxact

    set_property file_type {Verilog Header} [get_files $fault_header]
    set_property file_type {Verilog Header} [get_files $register_header]
    set_property file_type {Verilog Header} [get_files $profile_header]
    foreach constraint $staged_constraints {
        set_property file_type XDC [get_files $constraint]
        set_property USED_IN_SYNTHESIS false [get_files $constraint]
        set_property USED_IN_IMPLEMENTATION true [get_files $constraint]
        set_property PROCESSING_ORDER LATE [get_files $constraint]
    }
    set_property top protection_ip_top_async_adc_axi_lite [current_fileset]
    update_compile_order -fileset sources_1

    ipx::package_project -root_dir $ip_root -vendor zsr112.local \
        -library protection -taxonomy {/UserIP} -import_files -set_current true
    set core [ipx::current_core]
    set_property name protection_ip_axi_lite $core
    set_property version 0.3 $core
    set_property display_name {Current Protection AXI-Lite IP} $core
    set_property supported_families {zynq Production} $core

    _stage_packaged_implementation_constraints $core $staged_constraints
    _stage_packaged_generated_header $core $ip_root $register_header \
        {src/generated/protection_register_map.vh} verilogSource
    _stage_packaged_generated_header $core $ip_root $profile_header \
        {src/generated/stage2f_adc_source_profile.svh} systemVerilogSource

    foreach {parameter minimum maximum} {
        DATA_WIDTH 1 1024
        ADC_FIFO_ADDR_WIDTH 2 16
        OBS_SEQUENCE_WIDTH 16 32
    } {
        set object [_require_unique \
            [ipx::get_user_parameters $parameter -of_objects $core -quiet] \
            "Packaged user parameter $parameter"]
        set_property value_validation_type range_long $object
        set_property value_validation_range_minimum $minimum $object
        set_property value_validation_range_maximum $maximum $object
    }

    set saxi [_ensure_bus_interface $core S_AXI \
        xilinx.com:interface:aximm:1.0 xilinx.com:interface:aximm_rtl:1.0 slave]
    _ensure_bus_parameter $saxi PROTOCOL AXI4LITE
    _ensure_bus_parameter $saxi DATA_WIDTH 32
    _ensure_bus_parameter $saxi ADDR_WIDTH 8
    foreach {logical physical} {
        AWADDR S_AXI_AWADDR AWVALID S_AXI_AWVALID AWREADY S_AXI_AWREADY
        WDATA S_AXI_WDATA WSTRB S_AXI_WSTRB WVALID S_AXI_WVALID
        WREADY S_AXI_WREADY BRESP S_AXI_BRESP BVALID S_AXI_BVALID
        BREADY S_AXI_BREADY ARADDR S_AXI_ARADDR ARVALID S_AXI_ARVALID
        ARREADY S_AXI_ARREADY RDATA S_AXI_RDATA RRESP S_AXI_RRESP
        RVALID S_AXI_RVALID RREADY S_AXI_RREADY
    } {
        _ensure_port_map $saxi $logical $physical
    }
    set aclk [_ensure_bus_interface $core ACLK \
        xilinx.com:signal:clock:1.0 xilinx.com:signal:clock_rtl:1.0 slave]
    _ensure_port_map $aclk CLK ACLK
    _ensure_bus_parameter $aclk ASSOCIATED_BUSIF S_AXI
    _ensure_bus_parameter $aclk ASSOCIATED_RESET ARESETN
    _ensure_bus_parameter $aclk FREQ_HZ 100000000
    set aresetn [_ensure_bus_interface $core ARESETN \
        xilinx.com:signal:reset:1.0 xilinx.com:signal:reset_rtl:1.0 slave]
    _ensure_port_map $aresetn RST ARESETN
    _ensure_bus_parameter $aresetn POLARITY ACTIVE_LOW
    set adc_clk [_ensure_bus_interface $core adc_src_clk \
        xilinx.com:signal:clock:1.0 xilinx.com:signal:clock_rtl:1.0 slave]
    _ensure_port_map $adc_clk CLK adc_src_clk
    _ensure_bus_parameter $adc_clk ASSOCIATED_RESET ARESETN

    set memory_map [ipx::get_memory_maps S_AXI -of_objects $core -quiet]
    if {[llength $memory_map] == 0} {
        set memory_map [ipx::add_memory_map S_AXI $core]
    }
    set_property slave_memory_map_ref S_AXI $saxi
    set block [ipx::get_address_blocks reg0 -of_objects $memory_map -quiet]
    if {[llength $block] == 0} {
        set block [ipx::add_address_block reg0 $memory_map]
    }
    set_property base_address 0 $block
    set_property range 0x1000 $block
    set_property width 32 $block
    set_property usage register $block
    set register_count [protection_register_map_apply_ipxact $block]
    if {$register_count != $::PROTECTION_REGISTER_MAP_REGISTER_COUNT} {
        _raise PACKAGED_REGISTER_MAP {Generated IP-XACT register count differs from its authority}
    }

    ipx::create_xgui_files $core
    ipx::update_checksums $core
    ipx::check_integrity $core
    ipx::save_core $core
    if {[get_property VLNV $core] ne $protection_vlnv} {
        _raise PACKAGED_IP_IDENTITY {Packaged protection IP VLNV differs}
    }
    set portability [_validate_packaged_portability \
        $core $ip_root $repo_root $staged_constraints]
    close_project
    return [dict create ip_repo $ip_repo ip_root $ip_root portability $portability]
}

proc ::stage2_b1_public_adapter_v1::_probe_specs {} {
    return {
        {protection_ip_axi_lite_0/ARESETN 1}
        {protection_ip_axi_lite_0/adc_sample_valid 1}
        {protection_ip_axi_lite_0/adc_sample_ch1 12}
        {protection_ip_axi_lite_0/adc_sample_ch2 12}
        {protection_ip_axi_lite_0/pwm_raw 1}
        {protection_ip_axi_lite_0/pwm_out 1}
        {protection_ip_axi_lite_0/fault_valid 1}
        {protection_ip_axi_lite_0/fault_latched 1}
        {protection_ip_axi_lite_0/fault_code 8}
        {protection_ip_axi_lite_0/fault_code_latched 8}
        {protection_ip_axi_lite_0/fsm_state 4}
        {protection_ip_axi_lite_0/adc_sample_ready 1}
    }
}

proc ::stage2_b1_public_adapter_v1::_create_project_and_bd {build_root package} {
    variable part
    variable board_part
    variable protection_vlnv
    variable bd_name

    set project_dir [file join $build_root project]
    create_project stage2_b1_public_reconstruction $project_dir -part $part
    set_property board_part $board_part [current_project]
    set_property target_language Verilog [current_project]
    set_property IP_REPO_PATHS [list [dict get $package ip_repo]] [current_project]
    update_ip_catalog

    foreach vlnv [list \
        xilinx.com:ip:processing_system7:5.5 \
        xilinx.com:ip:proc_sys_reset:5.0 \
        xilinx.com:ip:smartconnect:1.0 \
        xilinx.com:ip:xlconstant:1.1 \
        xilinx.com:ip:system_ila:1.1 \
        xilinx.com:ip:axi_gpio:2.0 \
        xilinx.com:ip:xlslice:1.0 \
        $protection_vlnv] {
        _require_ipdef $vlnv
    }
    if {[get_property PART [current_project]] ne $part ||
        [get_property BOARD_PART [current_project]] ne $board_part} {
        _raise PROJECT_IDENTITY {Project target identity differs from the B1 authority}
    }

    create_bd_design $bd_name
    set ps [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
    set reset [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]
    set smart [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0]
    set protection [create_bd_cell -type ip \
        -vlnv $protection_vlnv protection_ip_axi_lite_0]
    set sample [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:xlconstant:1.1 sample_valid_const]
    set locked [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:xlconstant:1.1 dcm_locked_const]
    set gpio [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_stage1d_0]
    set slice1 [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:xlslice:1.0 xlslice_stage1d_ch1]
    set slice2 [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:xlslice:1.0 xlslice_stage1d_ch2]
    set ila [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:system_ila:1.1 system_ila_stage2b_0]

    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} $ps
    set_property -dict [list \
        CONFIG.PCW_USE_M_AXI_GP0 {1} \
        CONFIG.PCW_EN_CLK0_PORT {1} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}] $ps
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $smart
    set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $sample
    set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $locked
    set_property -dict [list \
        CONFIG.C_IS_DUAL {0} \
        CONFIG.C_GPIO_WIDTH {24} \
        CONFIG.C_ALL_OUTPUTS {1} \
        CONFIG.C_INTERRUPT_PRESENT {0} \
        CONFIG.C_DOUT_DEFAULT {0x00400400}] $gpio
    set_property -dict [list \
        CONFIG.DIN_WIDTH {24} CONFIG.DIN_FROM {11} \
        CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {12}] $slice1
    set_property -dict [list \
        CONFIG.DIN_WIDTH {24} CONFIG.DIN_FROM {23} \
        CONFIG.DIN_TO {12} CONFIG.DOUT_WIDTH {12}] $slice2

    set probes [_probe_specs]
    set_property CONFIG.C_MON_TYPE MIX $ila
    set_property -dict [list \
        CONFIG.C_PROBE_WIDTH_PROPAGATION MANUAL \
        CONFIG.C_NUM_MONITOR_SLOTS {1} \
        CONFIG.C_SLOT_0_INTF_TYPE xilinx.com:interface:aximm_rtl:1.0 \
        CONFIG.C_SLOT_0_AXI_PROTOCOL AXI4LITE \
        CONFIG.C_NUM_OF_PROBES [llength $probes] \
        CONFIG.C_DATA_DEPTH {4096}] $ila
    set index 0
    foreach spec $probes {
        set_property CONFIG.C_PROBE${index}_WIDTH [lindex $spec 1] $ila
        incr index
    }

    connect_bd_net \
        [_require_bd_pin processing_system7_0/FCLK_CLK0] \
        [_require_bd_pin processing_system7_0/M_AXI_GP0_ACLK] \
        [_require_bd_pin smartconnect_0/aclk] \
        [_require_bd_pin proc_sys_reset_0/slowest_sync_clk] \
        [_require_bd_pin protection_ip_axi_lite_0/ACLK] \
        [_require_bd_pin protection_ip_axi_lite_0/adc_src_clk] \
        [_require_bd_pin axi_gpio_stage1d_0/s_axi_aclk] \
        [_require_bd_pin system_ila_stage2b_0/clk]
    connect_bd_net \
        [_require_bd_pin processing_system7_0/FCLK_RESET0_N] \
        [_require_bd_pin proc_sys_reset_0/ext_reset_in]
    connect_bd_net \
        [_require_bd_pin dcm_locked_const/dout] \
        [_require_bd_pin proc_sys_reset_0/dcm_locked]
    connect_bd_net \
        [_require_bd_pin proc_sys_reset_0/peripheral_aresetn] \
        [_require_bd_pin smartconnect_0/aresetn] \
        [_require_bd_pin protection_ip_axi_lite_0/ARESETN] \
        [_require_bd_pin axi_gpio_stage1d_0/s_axi_aresetn] \
        [_require_bd_pin system_ila_stage2b_0/resetn]

    connect_bd_intf_net \
        [_require_bd_intf_pin processing_system7_0/M_AXI_GP0] \
        [_require_bd_intf_pin smartconnect_0/S00_AXI]
    connect_bd_intf_net \
        [_require_bd_intf_pin smartconnect_0/M00_AXI] \
        [_require_bd_intf_pin protection_ip_axi_lite_0/S_AXI]
    connect_bd_intf_net \
        [_require_bd_intf_pin protection_ip_axi_lite_0/S_AXI] \
        [_require_bd_intf_pin system_ila_stage2b_0/SLOT_0_AXI]
    connect_bd_intf_net \
        [_require_bd_intf_pin smartconnect_0/M01_AXI] \
        [_require_bd_intf_pin axi_gpio_stage1d_0/S_AXI]

    connect_bd_net \
        [_require_bd_pin axi_gpio_stage1d_0/gpio_io_o] \
        [_require_bd_pin xlslice_stage1d_ch1/Din] \
        [_require_bd_pin xlslice_stage1d_ch2/Din]
    connect_bd_net \
        [_require_bd_pin xlslice_stage1d_ch1/Dout] \
        [_require_bd_pin protection_ip_axi_lite_0/adc_sample_ch1]
    connect_bd_net \
        [_require_bd_pin xlslice_stage1d_ch2/Dout] \
        [_require_bd_pin protection_ip_axi_lite_0/adc_sample_ch2]
    connect_bd_net \
        [_require_bd_pin sample_valid_const/dout] \
        [_require_bd_pin protection_ip_axi_lite_0/adc_sample_valid]

    set index 0
    foreach spec $probes {
        _connect_pin_preserving_net [lindex $spec 0] system_ila_stage2b_0/probe${index}
        incr index
    }

    assign_bd_address \
        -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
        -offset 0x43C00000 -range 0x00001000 \
        [get_bd_addr_segs protection_ip_axi_lite_0/S_AXI/reg0]
    assign_bd_address \
        -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
        -offset 0x41200000 -range 0x00010000 \
        [get_bd_addr_segs axi_gpio_stage1d_0/S_AXI/Reg]

    validate_bd_design
    save_bd_design
    set bd_file [_require_unique [get_files -quiet -all "*$bd_name.bd"] {Block design file}]
    generate_target all $bd_file
    set wrappers [make_wrapper -files $bd_file -top]
    set wrapper [_require_unique $wrappers {Generated BD wrapper}]
    _require_file $wrapper {Generated BD wrapper}
    add_files -norecurse $wrapper
    set_property top protection_system_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    return [dict create bd_file $bd_file wrapper $wrapper project_dir $project_dir]
}

proc ::stage2_b1_public_adapter_v1::_mapped_segment {cell_name} {
    set space [_require_unique \
        [get_bd_addr_spaces -quiet processing_system7_0/Data] \
        {PS data address space}]
    set selected {}
    foreach segment [get_bd_addr_segs -quiet -of_objects $space] {
        if {[string first [string tolower $cell_name] [string tolower $segment]] >= 0} {
            lappend selected $segment
        }
    }
    return [_require_unique $selected "Mapped segment for $cell_name"]
}

proc ::stage2_b1_public_adapter_v1::_assert_pin_width {path expected} {
    set pin [_require_bd_pin $path]
    set left [get_property LEFT $pin]
    set right [get_property RIGHT $pin]
    set width [expr {($left eq {} && $right eq {}) ? 1 : abs(int($left) - int($right)) + 1}]
    if {$width != $expected} {
        _raise TOPOLOGY_PROBE_WIDTH "$path width mismatch: actual=$width expected=$expected"
    }
}

proc ::stage2_b1_public_adapter_v1::_validate_final_topology {project} {
    variable part
    variable board_part
    variable protection_vlnv
    variable bd_name
    variable project_top
    variable required_cells

    if {[current_bd_design] ne $bd_name} {
        _raise TOPOLOGY_BD {Current block design is not protection_system}
    }
    if {[get_property PART [current_project]] ne $part ||
        [get_property BOARD_PART [current_project]] ne $board_part} {
        _raise TOPOLOGY_TARGET {Project target identity differs}
    }
    set cells {}
    foreach cell [get_bd_cells -quiet] {
        lappend cells [_object_path $cell]
    }
    if {[lsort -dictionary $cells] ne [lsort -dictionary $required_cells]} {
        _raise TOPOLOGY_CELL_INVENTORY \
            "Final B1 cell inventory differs: actual=$cells expected=$required_cells"
    }
    foreach {name vlnv} [list \
        axi_gpio_stage1d_0 xilinx.com:ip:axi_gpio:2.0 \
        dcm_locked_const xilinx.com:ip:xlconstant:1.1 \
        proc_sys_reset_0 xilinx.com:ip:proc_sys_reset:5.0 \
        processing_system7_0 xilinx.com:ip:processing_system7:5.5 \
        protection_ip_axi_lite_0 $protection_vlnv \
        sample_valid_const xilinx.com:ip:xlconstant:1.1 \
        smartconnect_0 xilinx.com:ip:smartconnect:1.0 \
        system_ila_stage2b_0 xilinx.com:ip:system_ila:1.1 \
        xlslice_stage1d_ch1 xilinx.com:ip:xlslice:1.0 \
        xlslice_stage1d_ch2 xilinx.com:ip:xlslice:1.0] {
        _assert_property [_require_bd_cell $name] VLNV $vlnv "BD cell $name"
    }

    set smart [_require_bd_cell smartconnect_0]
    _assert_property $smart CONFIG.NUM_SI 1 SmartConnect
    _assert_property $smart CONFIG.NUM_MI 2 SmartConnect
    set gpio [_require_bd_cell axi_gpio_stage1d_0]
    foreach {property value} {
        C_IS_DUAL 0 C_GPIO_WIDTH 24 C_ALL_OUTPUTS 1
        C_INTERRUPT_PRESENT 0 C_DOUT_DEFAULT 0x00400400
    } {
        _assert_property $gpio CONFIG.$property $value {AXI GPIO}
    }
    foreach {name properties} {
        xlslice_stage1d_ch1 {DIN_WIDTH 24 DIN_FROM 11 DIN_TO 0 DOUT_WIDTH 12}
        xlslice_stage1d_ch2 {DIN_WIDTH 24 DIN_FROM 23 DIN_TO 12 DOUT_WIDTH 12}
    } {
        set slice [_require_bd_cell $name]
        foreach {property value} $properties {
            _assert_property $slice CONFIG.$property $value "XL Slice $name"
        }
    }
    _assert_property [_require_bd_cell sample_valid_const] CONFIG.CONST_WIDTH 1 sample_valid_const
    _assert_property [_require_bd_cell sample_valid_const] CONFIG.CONST_VAL 0 sample_valid_const

    set protection_segment [_mapped_segment protection_ip_axi_lite_0]
    _assert_property $protection_segment OFFSET 0x43C00000 {Protection address}
    _assert_property $protection_segment RANGE 0x00001000 {Protection address}
    set gpio_segment [_mapped_segment axi_gpio_stage1d_0]
    _assert_property $gpio_segment OFFSET 0x41200000 {GPIO address}
    _assert_property $gpio_segment RANGE 0x00010000 {GPIO address}
    set address_space [_require_unique \
        [get_bd_addr_spaces -quiet processing_system7_0/Data] \
        {PS data address space}]
    if {[llength [get_bd_addr_segs -quiet -of_objects $address_space]] != 2} {
        _raise TOPOLOGY_ADDRESS_INVENTORY {PS data address space must contain exactly two segments}
    }

    _assert_exact_interface_net \
        {processing_system7_0/M_AXI_GP0 smartconnect_0/S00_AXI} \
        {PS to SmartConnect}
    _assert_exact_interface_net \
        {smartconnect_0/M00_AXI protection_ip_axi_lite_0/S_AXI system_ila_stage2b_0/SLOT_0_AXI} \
        {Protection AXI and ILA monitor}
    _assert_exact_interface_net \
        {smartconnect_0/M01_AXI axi_gpio_stage1d_0/S_AXI} \
        {GPIO AXI path}
    _assert_exact_scalar_net \
        {processing_system7_0/FCLK_CLK0 processing_system7_0/M_AXI_GP0_ACLK smartconnect_0/aclk proc_sys_reset_0/slowest_sync_clk protection_ip_axi_lite_0/ACLK protection_ip_axi_lite_0/adc_src_clk axi_gpio_stage1d_0/s_axi_aclk system_ila_stage2b_0/clk} \
        {100 MHz clock}
    _assert_exact_scalar_net \
        {processing_system7_0/FCLK_RESET0_N proc_sys_reset_0/ext_reset_in} \
        {PS reset input}
    _assert_exact_scalar_net \
        {dcm_locked_const/dout proc_sys_reset_0/dcm_locked} \
        {Reset lock constant}
    _assert_exact_scalar_net \
        {proc_sys_reset_0/peripheral_aresetn smartconnect_0/aresetn protection_ip_axi_lite_0/ARESETN axi_gpio_stage1d_0/s_axi_aresetn system_ila_stage2b_0/resetn system_ila_stage2b_0/probe0} \
        {Peripheral active-low reset}
    _assert_exact_scalar_net \
        {axi_gpio_stage1d_0/gpio_io_o xlslice_stage1d_ch1/Din xlslice_stage1d_ch2/Din} \
        {Packed GPIO stimulus}
    _assert_exact_scalar_net \
        {sample_valid_const/dout protection_ip_axi_lite_0/adc_sample_valid system_ila_stage2b_0/probe1} \
        {adc_sample_valid constant zero}
    _assert_exact_scalar_net \
        {xlslice_stage1d_ch1/Dout protection_ip_axi_lite_0/adc_sample_ch1 system_ila_stage2b_0/probe2} \
        {adc_sample_ch1 source}
    _assert_exact_scalar_net \
        {xlslice_stage1d_ch2/Dout protection_ip_axi_lite_0/adc_sample_ch2 system_ila_stage2b_0/probe3} \
        {adc_sample_ch2 source}
    _assert_exact_scalar_net \
        {protection_ip_axi_lite_0/adc_sample_ready system_ila_stage2b_0/probe11} \
        {adc_sample_ready destination observation}

    foreach {path property expected label} {
        processing_system7_0/FCLK_RESET0_N CONFIG.POLARITY ACTIVE_LOW {PS reset}
        proc_sys_reset_0/ext_reset_in CONFIG.POLARITY ACTIVE_LOW {Processor System Reset input}
        proc_sys_reset_0/peripheral_aresetn CONFIG.POLARITY ACTIVE_LOW {Peripheral reset output}
        protection_ip_axi_lite_0/ARESETN CONFIG.POLARITY ACTIVE_LOW {Protection reset input}
        axi_gpio_stage1d_0/s_axi_aresetn CONFIG.POLARITY ACTIVE_LOW {AXI GPIO reset input}
        system_ila_stage2b_0/resetn CONFIG.POLARITY ACTIVE_LOW {System ILA reset input}
    } {
        _assert_property [_require_bd_pin $path] $property $expected $label
    }
    _assert_property [_require_bd_cell proc_sys_reset_0] CONFIG.C_EXT_RESET_HIGH 0 \
        {Processor System Reset}

    set ila [_require_bd_cell system_ila_stage2b_0]
    foreach {property value} {
        C_MON_TYPE MIX C_PROBE_WIDTH_PROPAGATION MANUAL
        C_NUM_MONITOR_SLOTS 1 C_SLOT_0_INTF_TYPE xilinx.com:interface:aximm_rtl:1.0
        C_SLOT_0_AXI_PROTOCOL AXI4LITE C_NUM_OF_PROBES 12 C_DATA_DEPTH 4096
    } {
        _assert_property $ila CONFIG.$property $value {System ILA}
    }
    set index 0
    foreach spec [_probe_specs] {
        set source [lindex $spec 0]
        set width [lindex $spec 1]
        _assert_pin_width system_ila_stage2b_0/probe${index} $width
        _assert_property $ila CONFIG.C_PROBE${index}_WIDTH $width {System ILA probe}
        if {$index < 4} {
            _assert_same_scalar_net [list $source system_ila_stage2b_0/probe${index}] \
                "System ILA probe $index"
        } else {
            _assert_exact_scalar_net [list $source system_ila_stage2b_0/probe${index}] \
                "System ILA probe $index"
        }
        incr index
    }

    foreach forbidden {
        stage2i_b2_ready_aware_stimulus_0
        proc_sys_reset_stage2i_b2_src
        system_ila_stage2i_b2_source_0
        i_ch1_const
        i_ch2_const
    } {
        if {[llength [get_bd_cells -quiet $forbidden]] != 0} {
            _raise TOPOLOGY_PROFILE_LEAKAGE "B1 contains forbidden cell: $forbidden"
        }
    }
    if {[get_property top [current_fileset]] ne $project_top} {
        _raise TOPOLOGY_WRAPPER {Project top is not protection_system_wrapper}
    }
    _require_file [dict get $project wrapper] {Generated protection_system_wrapper}
    return 1
}

proc ::stage2_b1_public_adapter_v1::_write_summary {build_root package project} {
    set summary [file join $build_root public_reconstruction_summary.txt]
    set portability [dict get $package portability]
    set channel [open $summary w]
    fconfigure $channel -encoding utf-8 -translation lf
    foreach line [list \
        {VIVADO_VERSION=2024.1} \
        {DERIVATION_ID=STAGE2_B1_PUBLIC_RECONSTRUCTION_ADAPTER_V1} \
        {CURRENT_ENGINEERING_VIVADO_PRODUCTION_AUTHORITY=STAGE1E_PRODUCTION_VIVADO_RUNNER_V2} \
        {PROJECT_CREATION=PASS} \
        {IP_PACKAGING=PASS} \
        {IP_PACKAGE_PORTABILITY_CHECK=PASS} \
        {B1_SAFE_INERT_BD_CREATION=PASS} \
        {B1_SAFE_INERT_BD_VALIDATION=PASS} \
        {B1_SAFE_INERT_BD_SAVE=PASS} \
        {BD_OUTPUT_PRODUCTS_GENERATION=PASS} \
        {BD_WRAPPER_GENERATION=PASS} \
        {PROJECT_TOP_VALIDATION=PASS} \
        {PUBLIC_RECONSTRUCTION_B1_STRUCTURAL_FINGERPRINT=PASS} \
        {PUBLIC_RECONSTRUCTION_ADDRESS_MAP=PASS} \
        {PUBLIC_RECONSTRUCTION_PROFILE_CLASS=SAFE_INERT} \
        {PROTECTION_IP_ADDRESS=0x43C00000} \
        {AXI_GPIO_ADDRESS=0x41200000} \
        {ADC_SAMPLE_VALID_CONSTANT=0} \
        {B2_SYNTHETIC_PRODUCER_PRESENT=NO} \
        {B2_SOURCE_DOMAIN_ILA_PRESENT=NO} \
        {PROJECT_TOP=protection_system_wrapper} \
        "PACKAGED_IP_ABSOLUTE_SOURCE_REFERENCE_COUNT=[dict get $portability absolute_source_references]" \
        "PACKAGED_IP_ABSOLUTE_INCLUDE_DEPENDENCY_COUNT=[dict get $portability absolute_include_dependencies]" \
        "PACKAGED_GENERATED_REGISTER_HEADER_DUPLICATE_COUNT=[dict get $portability register_header_duplicates]" \
        "PACKAGED_GENERATED_PROFILE_HEADER_DUPLICATE_COUNT=[dict get $portability profile_header_duplicates]" \
        "PACKAGED_INCLUDE_DEPENDENCY_RELATIVE=[expr {[dict get $portability include_dependency_relative] ? {YES} : {NO}}]" \
        "PACKAGED_IMPLEMENTATION_CONSTRAINT_DUPLICATE_COUNT=[dict get $portability constraint_duplicates]" \
        "PACKAGED_IMPLEMENTATION_CONSTRAINT_SCOPE=[expr {[dict get $portability constraint_scope_pass] ? {PASS} : {FAIL}}]" \
        {SYNTHESIS_RUN=NO} \
        {IMPLEMENTATION_RUN=NO} \
        {ROUTE_DESIGN_RUN=NO} \
        {BITSTREAM_GENERATED=NO} \
        {XSA_GENERATED=NO} \
        {BOARD_ACTIONS=NONE} \
        "PROJECT_PATH=[file join [dict get $project project_dir] stage2_b1_public_reconstruction.xpr]" \
        "BD_FILE=[dict get $project bd_file]" \
        "WRAPPER_FILE=[dict get $project wrapper]" \
        "PACKAGED_IP_ROOT=[dict get $package ip_root]"] {
        puts $channel $line
        puts $line
    }
    close $channel
    return $summary
}

proc ::stage2_b1_public_adapter_v1::run {} {
    variable expected_version_pattern

    if {![info exists ::env(PROTECTION_IP_VIVADO_BUILD_ROOT)] ||
        [string trim $::env(PROTECTION_IP_VIVADO_BUILD_ROOT)] eq {}} {
        _raise BUILD_ROOT {Set PROTECTION_IP_VIVADO_BUILD_ROOT to a fresh external short path}
    }
    set script_path [file normalize [info script]]
    set repo_root [file normalize [file join [file dirname $script_path] ../..]]
    set build_root [file normalize $::env(PROTECTION_IP_VIVADO_BUILD_ROOT)]
    if {[_path_is_within $repo_root $build_root]} {
        _raise BUILD_ROOT {The Vivado build root must be outside the delivery repository}
    }
    if {[file exists $build_root] &&
        [llength [glob -nocomplain -directory $build_root *]] != 0} {
        _raise BUILD_ROOT "The Vivado build root is not empty: $build_root"
    }
    file mkdir $build_root
    cd $build_root

    set vivado_version [version]
    if {![string match $expected_version_pattern $vivado_version]} {
        _raise VIVADO_VERSION "Expected Vivado 2024.1; actual=$vivado_version"
    }
    set package [_package_ip $repo_root $build_root]
    set project [_create_project_and_bd $build_root $package]
    validate_bd_design
    _validate_final_topology $project
    set summary [_write_summary $build_root $package $project]
    puts "PUBLIC_RECONSTRUCTION_SUMMARY=$summary"
    puts {FINAL_STATUS=STAGE2_B1_PUBLIC_STRUCTURAL_RECONSTRUCTION_PASS}
}

::stage2_b1_public_adapter_v1::run
