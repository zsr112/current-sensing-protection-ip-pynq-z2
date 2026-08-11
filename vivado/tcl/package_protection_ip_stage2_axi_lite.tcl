# Historical package-only compatibility entrypoint. It is retained for frozen
# replay and is not a current production build or source-list authority. The
# live authority is stage1e_production_vivado_runner_v2::package_protection_ip.
#
# Vivado 2024.1 / Stage 2 AXI4-Lite IP packaging script.
#
# Scope:
# - Package the strict asynchronous-ADC AXI-Lite production wrapper.
# - Write the generated IP repository outside this Git repository.
# - Stop before block design, synthesis, implementation, bitstream, hardware
#   export, or debug-probe generation.
#
# Run later from a Vivado 2024.1 command shell after review, for example:
# vivado -mode batch -source vivado/tcl/package_protection_ip_stage2_axi_lite.tcl
# Set PROTECTION_IP_PACKAGING_ROOT to override the default sibling output tree.
#
# This script intentionally does not call:
# - create_bd_design
# - launch_runs
# - synth_design
# - opt_design
# - place_design
# - route_design
# - write_bitstream
# - write_hw_platform
# - write_debug_probes
# - export_hardware
#
# Register map carried by protection_reg_bank:
# - 0x00 CTRL        RW / W1P
# - 0x04 STATUS      RO
# - 0x08 FAULT_CODE  RO
# - 0x0C I_CH1       RO
# - 0x10 I_CH2       RO
# - 0x14 TH_OC1      RW
# - 0x18 TH_OC2      RW
# - 0x1C TH_DIFF     RW
# - 0x20 PWM_PERIOD  RW
# - 0x24 PWM_DUTY    RW
# - 0x28 OBS_CAPABILITY RO
# - 0x2C OBS_STATUS_W1C RO / W1C
# - 0x30 OBS_SOURCE_ACCEPT_COUNT RO
# - 0x34 OBS_DESTINATION_DELIVERY_COUNT RO
# - 0x38 OBS_BACKPRESSURE_CYCLE_COUNT RO
# - 0x3C OBS_SOURCE_PROTOCOL_VIOLATION_COUNT RO
# - 0x40 OBS_SOURCE_DROP_COUNT RO
# - 0x44 OBS_FIFO_OVERFLOW_ATTEMPT_COUNT RO
# - 0x48 OBS_FIFO_UNDERFLOW_ATTEMPT_COUNT RO
# - 0x4C OBS_DUPLICATE_DELIVERY_COUNT RO
# - 0x50 OBS_SEQUENCE_GAP_COUNT RO
# - 0x54 OBS_REORDER_OR_STALE_COUNT RO
# - 0x58 OBS_AGGREGATE_ERROR_COUNT RO
# - 0x5C OBS_LAST_SOURCE_SEQUENCE RO
# - 0x60 OBS_LAST_DESTINATION_SEQUENCE RO
# All diagnostic counters are 32-bit saturating and reset-only.
# OBS_STATUS_W1C bits 8:0 are W1C causes. Bit 9 ANY_ERROR is a read-only
# maintained OR of post-clear error causes 1:8.
#
# Address planning:
# - The RTL consumes AXI_ADDR_WIDTH=8, so the real decode aperture is 0x100.
# - Vivado IP-XACT address blocks commonly use a minimum 4 KiB range, so this
#   package records a 0x1000 IP metadata range while documenting the 0x100 RTL
#   aperture.
# - A BD/PYNQ outer segment may later use 0x1000 or 64 KiB for convenience.
# - Accesses beyond the low 8 address bits can alias unless the RTL/metadata is
#   extended.
# - 0x43C00000 is only a placeholder/planning base. The final hardware base
#   address must come from Vivado Address Editor.

set expected_version_pattern {*Vivado v2024.1*}
set board_part_name tul.com.tw:pynq-z2:part0:1.0
set part_name xc7z020clg400-1
set top_module protection_ip_top_async_adc_axi_lite

set ip_vendor zsr112.local
set ip_library protection
set ip_name protection_ip_axi_lite
set ip_version 0.3
set ip_vlnv ${ip_vendor}:${ip_library}:${ip_name}:${ip_version}
set ip_xact_address_block_metadata PASS
set ip_xact_register_objects GENERATED_FROM_LIVE_REGISTER_MAP
set external_register_map_authority SPEC_REGISTER_MAP_JSON

set axi_interface_name S_AXI
set axi_clock_name ACLK
set axi_reset_name ARESETN
set axi_addr_width 8
set axi_data_width 32
set axi_clock_freq_hz 100000000
set data_width 12
set cnt_width 16
set health_cnt_width 8
set adc_fifo_addr_width 3
set obs_sequence_width 32
set rtl_decode_aperture 0x100
set ip_address_block_range 0x1000

set raw_script_path [info script]
if {$raw_script_path eq ""} {
    error "This script must be sourced from its file path so the repository root can be resolved safely."
}

set script_path [file normalize $raw_script_path]
set script_dir [file dirname $script_path]
set repo_root [file normalize [file join $script_dir ../..]]
set rtl_dir [file join $repo_root rtl]
set register_map_ipxact [file join $script_dir generated protection_register_map_ipxact.tcl]
if {[info exists ::env(PROTECTION_IP_PACKAGING_ROOT)] &&
        [string trim $::env(PROTECTION_IP_PACKAGING_ROOT)] ne {}} {
    set packaging_root [file normalize $::env(PROTECTION_IP_PACKAGING_ROOT)]
} elseif {[info exists ::env(PROTECTION_IP_VIVADO_BUILD_ROOT)] &&
        [string trim $::env(PROTECTION_IP_VIVADO_BUILD_ROOT)] ne {}} {
    set packaging_root [file normalize $::env(PROTECTION_IP_VIVADO_BUILD_ROOT)]
} else {
    error "Set PROTECTION_IP_VIVADO_BUILD_ROOT to an external writable build root."
}
set ip_repo_root [file join $packaging_root ip_repo]
set ip_output_dir [file join $ip_repo_root $ip_name]
set tmp_work_root [file join $packaging_root vivado_work]
set tmp_project_dir [file join $tmp_work_root ip_packaging_tmp]
set tmp_project_name protection_ip_axi_lite_packaging_tmp
set cdc_constraint_files [list \
    [file join $repo_root vivado constraints stage2d_async_adc_atomic_cdc.xdc] \
    [file join $repo_root vivado constraints stage2e_transaction_observability_cdc.xdc] \
]

proc assert_outside_repo {repo_root path label} {
    set normalized_repo [string tolower [file normalize $repo_root]]
    set normalized_path [string tolower [file normalize $path]]
    if {[string first $normalized_repo $normalized_path] == 0} {
        error "Refusing to place $label inside the Git repository: $path"
    }
}

proc require_absent_dir {path label} {
    if {[file exists $path]} {
        error "$label already exists: $path. Archive or remove it manually before rerunning. This script does not use -force."
    }
}

proc require_file {path} {
    if {![file exists $path]} {
        error "Required source file not found: $path"
    }
}

proc ensure_bus_interface {core name bus_vlnv abstraction_vlnv mode} {
    set busif [ipx::get_bus_interfaces $name -of_objects $core -quiet]
    if {[llength $busif] == 0} {
        set busif [ipx::add_bus_interface $name $core]
    }
    set_property bus_type_vlnv $bus_vlnv $busif
    set_property abstraction_type_vlnv $abstraction_vlnv $busif
    set_property interface_mode $mode $busif
    return $busif
}

proc ensure_port_map {busif logical_name physical_name} {
    set port_map [ipx::get_port_maps $logical_name -of_objects $busif -quiet]
    if {[llength $port_map] == 0} {
        set port_map [ipx::add_port_map $logical_name $busif]
    }
    set_property physical_name $physical_name $port_map
}

proc set_bus_parameter {busif name value} {
    set parameter [ipx::get_bus_parameters $name -of_objects $busif -quiet]
    if {[llength $parameter] == 0} {
        set parameter [ipx::add_bus_parameter $name $busif]
    }
    set_property value $value $parameter
}

set vivado_version [version]
if {![string match $expected_version_pattern $vivado_version]} {
    error "Expected Vivado 2024.1. Current version output is: $vivado_version"
}

if {![file isdirectory $rtl_dir]} {
    error "RTL directory not found: $rtl_dir"
}

set rtl_files [list \
    [file join $rtl_dir adc_sample_cdc_bridge.v] \
    [file join $rtl_dir adc_sample_code_normalizer.sv] \
    [file join $rtl_dir async_fifo_gray.v] \
    [file join $rtl_dir source_observability_cdc.v] \
    [file join $rtl_dir transaction_destination_observer.v] \
    [file join $rtl_dir transaction_source_observer.v] \
    [file join $rtl_dir fault_defs.vh] \
    [file join $rtl_dir generated protection_register_map.vh] \
    [file join $rtl_dir generated stage2f_adc_source_profile.svh] \
    [file join $rtl_dir reset_release_sync.v] \
    [file join $rtl_dir current_compare_dual.v] \
    [file join $rtl_dir fault_classifier.v] \
    [file join $rtl_dir protection_core_top.v] \
    [file join $rtl_dir protection_fsm.v] \
    [file join $rtl_dir protection_ip_top_async_adc_axi_lite.v] \
    [file join $rtl_dir protection_ip_top_axi_lite.v] \
    [file join $rtl_dir protection_ip_top_reg_controlled.v] \
    [file join $rtl_dir protection_reg_bank.v] \
    [file join $rtl_dir pwm_gate.v] \
    [file join $rtl_dir pwm_gen.v] \
    [file join $rtl_dir sensor_health_monitor.v] \
]

# moving_avg_filter.v is intentionally excluded from the Stage 2 packaged IP
# because it is not instantiated by protection_ip_top_axi_lite. It remains a
# future enhancement source and can be packaged later if integrated into the top
# hierarchy.

foreach rtl_file $rtl_files {
    require_file $rtl_file
}
foreach cdc_constraint_file $cdc_constraint_files {
    require_file $cdc_constraint_file
}
require_file $register_map_ipxact
source $register_map_ipxact

assert_outside_repo $repo_root $ip_output_dir "generated IP output"
assert_outside_repo $repo_root $tmp_project_dir "temporary Vivado packaging project"
require_absent_dir $ip_output_dir "IP output directory"
require_absent_dir $tmp_project_dir "Temporary Vivado project directory"

file mkdir $ip_repo_root
file mkdir $tmp_work_root

create_project $tmp_project_name $tmp_project_dir -part $part_name
set_property board_part $board_part_name [current_project]
set_property target_language Verilog [current_project]

add_files -norecurse -fileset sources_1 $rtl_files
add_files -norecurse -fileset constrs_1 $cdc_constraint_files
set_property file_type {Verilog Header} [get_files [file join $rtl_dir fault_defs.vh]]
set_property file_type {Verilog Header} [get_files \
    [file join $rtl_dir generated protection_register_map.vh]]
set_property file_type {Verilog Header} [get_files \
    [file join $rtl_dir generated stage2f_adc_source_profile.svh]]
foreach cdc_constraint_file $cdc_constraint_files {
    set_property file_type XDC [get_files $cdc_constraint_file]
    set_property USED_IN_SYNTHESIS true [get_files $cdc_constraint_file]
    set_property USED_IN_IMPLEMENTATION true [get_files $cdc_constraint_file]
    set_property PROCESSING_ORDER LATE [get_files $cdc_constraint_file]
}
set_property top $top_module [current_fileset]
set_property include_dirs [list $rtl_dir] [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project \
    -root_dir $ip_output_dir \
    -vendor $ip_vendor \
    -library $ip_library \
    -taxonomy {/UserIP} \
    -import_files \
    -set_current true

set core [ipx::current_core]
set_property name $ip_name $core
set_property version $ip_version $core
set_property display_name {Current Protection AXI-Lite IP} $core
set_property description {Current-sensing protection IP with AXI4-Lite transaction-integrity observability for Stage 2 PYNQ-Z2 integration planning.} $core
set_property vendor_display_name {zsr112.local} $core
set_property company_url {https://zsr112.local} $core
set_property supported_families {zynq Production} $core

# Keep the current RTL parameters visible in the packaged IP. The values here
# match the Stage 2 planning defaults and the current RTL defaults.
foreach {param_name param_value} [list \
    DATA_WIDTH $data_width \
    CNT_WIDTH $cnt_width \
    AXI_ADDR_WIDTH $axi_addr_width \
    AXI_DATA_WIDTH $axi_data_width \
    HEALTH_CNT_WIDTH $health_cnt_width \
    ADC_FIFO_ADDR_WIDTH $adc_fifo_addr_width \
    OBS_SEQUENCE_WIDTH $obs_sequence_width \
] {
    set param [ipx::get_user_parameters $param_name -of_objects $core -quiet]
    if {[llength $param] != 1} {
        error "Expected exactly one packaged user parameter: $param_name"
    }
    set_property value $param_value $param
    set_property value_format long $param
    if {$param_name eq {DATA_WIDTH}} {
        set_property value_validation_type range_long $param
        set_property value_validation_range_minimum 1 $param
        set_property value_validation_range_maximum 1024 $param
    } elseif {$param_name eq {ADC_FIFO_ADDR_WIDTH}} {
        set_property value_validation_type range_long $param
        set_property value_validation_range_minimum 2 $param
        set_property value_validation_range_maximum 16 $param
    } elseif {$param_name eq {OBS_SEQUENCE_WIDTH}} {
        set_property value_validation_type range_long $param
        set_property value_validation_range_minimum 16 $param
        set_property value_validation_range_maximum 32 $param
    }
}

# Explicit AXI4-Lite slave interface metadata. The RTL intentionally omits
# AWPROT/ARPROT and uses ACLK/ARESETN rather than S_AXI_ACLK/S_AXI_ARESETN, so
# the clock/reset association is declared explicitly instead of relying only on
# add-module inference in a block design.
set saxi [ensure_bus_interface \
    $core \
    $axi_interface_name \
    xilinx.com:interface:aximm:1.0 \
    xilinx.com:interface:aximm_rtl:1.0 \
    slave]
set_property display_name {S_AXI} $saxi
set_bus_parameter $saxi PROTOCOL AXI4LITE
set_bus_parameter $saxi DATA_WIDTH $axi_data_width
set_bus_parameter $saxi ADDR_WIDTH $axi_addr_width

foreach {logical physical} [list \
    AWADDR  S_AXI_AWADDR \
    AWVALID S_AXI_AWVALID \
    AWREADY S_AXI_AWREADY \
    WDATA   S_AXI_WDATA \
    WSTRB   S_AXI_WSTRB \
    WVALID  S_AXI_WVALID \
    WREADY  S_AXI_WREADY \
    BRESP   S_AXI_BRESP \
    BVALID  S_AXI_BVALID \
    BREADY  S_AXI_BREADY \
    ARADDR  S_AXI_ARADDR \
    ARVALID S_AXI_ARVALID \
    ARREADY S_AXI_ARREADY \
    RDATA   S_AXI_RDATA \
    RRESP   S_AXI_RRESP \
    RVALID  S_AXI_RVALID \
    RREADY  S_AXI_RREADY \
] {
    ensure_port_map $saxi $logical $physical
}

set aclk_if [ensure_bus_interface \
    $core \
    $axi_clock_name \
    xilinx.com:signal:clock:1.0 \
    xilinx.com:signal:clock_rtl:1.0 \
    slave]
ensure_port_map $aclk_if CLK $axi_clock_name
set_bus_parameter $aclk_if ASSOCIATED_BUSIF $axi_interface_name
set_bus_parameter $aclk_if ASSOCIATED_RESET $axi_reset_name
set_bus_parameter $aclk_if FREQ_HZ $axi_clock_freq_hz

set aresetn_if [ensure_bus_interface \
    $core \
    $axi_reset_name \
    xilinx.com:signal:reset:1.0 \
    xilinx.com:signal:reset_rtl:1.0 \
    slave]
ensure_port_map $aresetn_if RST $axi_reset_name
set_bus_parameter $aresetn_if POLARITY ACTIVE_LOW

set adc_clock_if [ensure_bus_interface \
    $core \
    adc_src_clk \
    xilinx.com:signal:clock:1.0 \
    xilinx.com:signal:clock_rtl:1.0 \
    slave]
ensure_port_map $adc_clock_if CLK adc_src_clk
set_bus_parameter $adc_clock_if ASSOCIATED_RESET $axi_reset_name

set memory_map [ipx::get_memory_maps $axi_interface_name -of_objects $core -quiet]
if {[llength $memory_map] == 0} {
    set memory_map [ipx::add_memory_map $axi_interface_name $core]
}
set_property slave_memory_map_ref $axi_interface_name $saxi

set address_block [ipx::get_address_blocks reg0 -of_objects $memory_map -quiet]
if {[llength $address_block] == 0} {
    set address_block [ipx::add_address_block reg0 $memory_map]
}
set_property base_address 0 $address_block
set_property range $ip_address_block_range $address_block
set_property width $axi_data_width $address_block
set_property usage register $address_block

set generated_register_count [protection_register_map_apply_ipxact $address_block]
if {$generated_register_count != $PROTECTION_REGISTER_MAP_REGISTER_COUNT} {
    error "Generated IP-XACT register count mismatch: $generated_register_count"
}

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

puts "Stage 2 AXI4-Lite IP package generated."
puts "Generated IP repo path: $ip_repo_root"
puts "IP output directory: $ip_output_dir"
puts "VLNV: $ip_vlnv"
puts "Top module: $top_module"
puts "AXI interface: $axi_interface_name"
puts "Clock/reset: $axi_clock_name / $axi_reset_name"
puts "Address range planning: RTL aperture $rtl_decode_aperture; IP-XACT range $ip_address_block_range; larger BD/PYNQ segments require alias risk review."
puts "IP_XACT_ADDRESS_BLOCK_METADATA=$ip_xact_address_block_metadata"
puts "IP_XACT_REGISTER_OBJECTS=$ip_xact_register_objects"
puts "IP_XACT_REGISTER_COUNT=$generated_register_count"
puts "EXTERNAL_REGISTER_MAP_AUTHORITY=$external_register_map_authority"
puts "Next step: review and run this packaging Tcl, then write/review Stage 2 BD Tcl. Do not proceed directly to BD or synthesis."
