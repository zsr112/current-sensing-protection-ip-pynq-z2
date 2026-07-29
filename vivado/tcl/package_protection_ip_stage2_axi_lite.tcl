# Vivado 2024.1 / Stage 2 AXI4-Lite IP packaging script.
#
# Scope:
# - Package rtl/protection_ip_top_axi_lite.v as a Vivado custom IP.
# - Write the generated IP repository outside this Git repository.
# - Stop before block design, synthesis, implementation, bitstream, hardware
#   export, or debug-probe generation.
#
# Run later from Vivado 2024.1 after review, for example:
# vivado -mode batch -source <repo-root>/vivado/tcl/<script-name>.tcl
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
set top_module protection_ip_top_axi_lite

set ip_vendor zsr112.local
set ip_library protection
set ip_name protection_ip_axi_lite
set ip_version 0.1
set ip_vlnv ${ip_vendor}:${ip_library}:${ip_name}:${ip_version}

if {![info exists ::env(PROTECTION_IP_VIVADO_BUILD_ROOT)] || $::env(PROTECTION_IP_VIVADO_BUILD_ROOT) eq ""} {
    error "Set PROTECTION_IP_VIVADO_BUILD_ROOT to an external Vivado build directory."
}
set public_build_root [file normalize $::env(PROTECTION_IP_VIVADO_BUILD_ROOT)]
set packaging_root $public_build_root
set ip_repo_root [file join $packaging_root ip_repo]
set ip_output_dir [file join $ip_repo_root $ip_name]
set tmp_work_root [file join $packaging_root vivado_work]
set tmp_project_dir [file join $tmp_work_root ip_packaging_tmp]
set tmp_project_name protection_ip_axi_lite_packaging_tmp

set axi_interface_name S_AXI
set axi_clock_name ACLK
set axi_reset_name ARESETN
set axi_addr_width 8
set axi_data_width 32
set axi_clock_freq_hz 100000000
set data_width 12
set cnt_width 16
set health_cnt_width 8
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
    [file join $rtl_dir fault_defs.vh] \
    [file join $rtl_dir current_compare_dual.v] \
    [file join $rtl_dir fault_classifier.v] \
    [file join $rtl_dir protection_core_top.v] \
    [file join $rtl_dir protection_fsm.v] \
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
set_property file_type {Verilog Header} [get_files [file join $rtl_dir fault_defs.vh]]
set_property top $top_module [current_fileset]
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
set_property description {Current-sensing protection IP with AXI4-Lite register access for Stage 2 PYNQ-Z2 integration planning.} $core
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
] {
    set param [ipx::get_user_parameters $param_name -of_objects $core -quiet]
    if {[llength $param] != 0} {
        set_property value $param_value $param
        set_property value_format long $param
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

# IP-XACT register-object creation is intentionally left for a later reviewed
# pass if needed. The Tcl commands for register field objects vary across Vivado
# versions; the authoritative map is documented above and in:
# docs/implementation/register_map.md

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
puts "Next step: review and run this packaging Tcl, then write/review Stage 2 BD Tcl. Do not proceed directly to BD or synthesis."
