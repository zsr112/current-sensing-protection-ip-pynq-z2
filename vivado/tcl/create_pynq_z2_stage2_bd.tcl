# Vivado 2024.1 / PYNQ-Z2 Stage 2 block-design draft.
#
# Scope:
# - Open the existing Stage 1 external Vivado project.
# - Add the generated Stage 2 packaged IP repository.
# - Create a minimal Zynq PS -> SmartConnect -> AXI-Lite protection IP block
#   design.
# - Use safe internal constants for first-pass digital stimulus.
# - Stop before synthesis, implementation, bitstream, hardware export, or debug
#   probe generation.
#
# Run later from Vivado 2024.1 only after review, for example:
# vivado -mode batch -source <repo-root>/vivado/tcl/<script-name>.tcl
#
# This script intentionally does not call:
# - launch_runs
# - synth_design
# - opt_design
# - place_design
# - route_design
# - write_bitstream
# - write_hw_platform
# - write_debug_probes
# - export_hardware
# - generate_target
#
# Address planning:
# - 0x43C00000 is a planning address only. The final address must be confirmed
#   in Vivado Address Editor / assign_bd_address output.
# - The packaged IP has an IP-XACT/BD segment range of 0x1000.
# - The RTL true decode aperture is 0x100 because AXI_ADDR_WIDTH=8.
# - Accesses beyond the low 8 address bits can alias unless the RTL decode is
#   later widened.
#
# First controlled BD run note:
# - Vivado 2024.1 reported unsupported IP xilinx.com:ip:axi_interconnect:1.7.
# - This revision uses SmartConnect instead.

set expected_version_pattern {*Vivado v2024.1*}
if {![info exists ::env(PROTECTION_IP_VIVADO_BUILD_ROOT)] || $::env(PROTECTION_IP_VIVADO_BUILD_ROOT) eq ""} {
    error "Set PROTECTION_IP_VIVADO_BUILD_ROOT to an external Vivado build directory."
}
set public_build_root [file normalize $::env(PROTECTION_IP_VIVADO_BUILD_ROOT)]
set project_path [file join $public_build_root vivado_work pynq_z2_stage1_boardpart current_protection_ip_pynq_z2_stage1_boardpart.xpr]
set expected_part xc7z020clg400-1
set expected_board_part tul.com.tw:pynq-z2:part0:1.0

set ip_repo_path [file join $public_build_root ip_repo]
set protection_vlnv zsr112.local:protection:protection_ip_axi_lite:0.1
set bd_name protection_system
set planned_base_addr 0x43C00000
set planned_range 0x1000

set sample_valid_const 1
set i_ch1_const 1024
set i_ch2_const 1024

proc require_ipdef {pattern label} {
    set defs [get_ipdefs -all -quiet $pattern]
    if {[llength $defs] == 0} {
        error "Required IP definition not found for $label: $pattern"
    }
    return [lindex $defs 0]
}

proc require_bd_intf_pin {path} {
    set pins [get_bd_intf_pins -quiet $path]
    if {[llength $pins] == 0} {
        error "Required BD interface pin not found: $path"
    }
    return [lindex $pins 0]
}

proc require_bd_pin {path} {
    set pins [get_bd_pins -quiet $path]
    if {[llength $pins] == 0} {
        error "Required BD pin not found: $path"
    }
    return [lindex $pins 0]
}

proc require_bd_port_or_intf_port {path label} {
    set ports [get_bd_ports -quiet $path]
    set intf_ports [get_bd_intf_ports -quiet $path]
    if {([llength $ports] == 0) && ([llength $intf_ports] == 0)} {
        error "Required external BD port/interface not found for $label: $path"
    }
    if {[llength $intf_ports] != 0} {
        return [lindex $intf_ports 0]
    }
    return [lindex $ports 0]
}

set vivado_version [version]
if {![string match $expected_version_pattern $vivado_version]} {
    error "Expected Vivado 2024.1. Current version output is: $vivado_version"
}

if {![file exists $project_path]} {
    error "Stage 1 project not found: $project_path"
}

if {![file isdirectory $ip_repo_path]} {
    error "Packaged IP repository not found: $ip_repo_path"
}

# Keep Vivado-generated auxiliary files such as PS7 summaries out of the Git
# repository when this script is launched from the repo working directory.
cd [file dirname $project_path]

open_project $project_path

set current_part [get_property PART [current_project]]
if {$current_part ne $expected_part} {
    error "Unexpected project part: $current_part. Expected: $expected_part"
}

set current_board_part [get_property BOARD_PART [current_project]]
if {$current_board_part ne $expected_board_part} {
    error "Unexpected board_part: $current_board_part. Expected: $expected_board_part"
}

set repo_paths [get_property IP_REPO_PATHS [current_project]]
if {[lsearch -exact $repo_paths $ip_repo_path] < 0} {
    lappend repo_paths $ip_repo_path
    set_property IP_REPO_PATHS $repo_paths [current_project]
}
update_ip_catalog

set protection_defs [get_ipdefs -all -quiet $protection_vlnv]
if {[llength $protection_defs] == 0} {
    error "Packaged protection IP is not visible in the catalog: $protection_vlnv"
}

set existing_bd_files [get_files -quiet -all [format "*%s.bd" $bd_name]]
if {[llength $existing_bd_files] != 0} {
    error "Block design already exists for $bd_name: $existing_bd_files. Archive/remove it manually before rerunning; this script does not overwrite."
}

if {[llength [get_bd_designs -quiet $bd_name]] != 0} {
    error "Block design is already open in memory: $bd_name"
}

create_bd_design $bd_name

set ps7_vlnv [require_ipdef xilinx.com:ip:processing_system7:* processing_system7]
set proc_sys_reset_vlnv [require_ipdef xilinx.com:ip:proc_sys_reset:* proc_sys_reset]
set smartconnect_vlnv [require_ipdef xilinx.com:ip:smartconnect:* smartconnect]
set xlconstant_vlnv [require_ipdef xilinx.com:ip:xlconstant:* xlconstant]

set ps7 [create_bd_cell -type ip -vlnv $ps7_vlnv processing_system7_0]
set rst [create_bd_cell -type ip -vlnv $proc_sys_reset_vlnv proc_sys_reset_0]
set smartconnect [create_bd_cell -type ip -vlnv $smartconnect_vlnv smartconnect_0]
set prot [create_bd_cell -type ip -vlnv $protection_vlnv protection_ip_axi_lite_0]
set c_sample_valid [create_bd_cell -type ip -vlnv $xlconstant_vlnv sample_valid_const]
set c_i_ch1 [create_bd_cell -type ip -vlnv $xlconstant_vlnv i_ch1_const]
set c_i_ch2 [create_bd_cell -type ip -vlnv $xlconstant_vlnv i_ch2_const]
set c_dcm_locked [create_bd_cell -type ip -vlnv $xlconstant_vlnv dcm_locked_const]

# Reset polarity is verified after the PS reset is connected. In Vivado 2024.1,
# proc_sys_reset CONFIG.C_EXT_RESET_HIGH and ext_reset_in CONFIG.POLARITY are
# BD-propagated/read-only in this flow, so the script asserts the propagated
# active-low policy instead of silently relying on defaults.

# PYNQ-Z2 PS7 board automation is required. A PS block with only M_AXI_GP0 and
# FCLK0 is not enough for a usable PYNQ-Z2 design because DDR and FIXED_IO must
# be externalized by the board preset. If this syntax changes in Vivado 2024.1,
# stop here and inspect the generated command from the Vivado GUI.
set ps_automation_status [catch {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} \
        [get_bd_cells processing_system7_0]
} ps_automation_msg]

if {$ps_automation_status != 0} {
    error "PYNQ-Z2 PS7 board automation failed. Review apply_bd_automation syntax in Vivado 2024.1. Message: $ps_automation_msg"
}

# Keep these explicit settings after board automation so the minimal AXI-Lite
# path is enabled and FCLK0 remains the planned 100 MHz PL/AXI clock. Vivado
# propagates the dependent GP0 AXI clock frequency; do not force read-only
# propagated PCW_M_AXI_GP0_FREQMHZ in this BD flow.
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
] $ps7

require_bd_port_or_intf_port DDR "PYNQ-Z2 DDR external interface"
require_bd_port_or_intf_port FIXED_IO "PYNQ-Z2 FIXED_IO external interface"
require_bd_intf_pin processing_system7_0/M_AXI_GP0
require_bd_pin processing_system7_0/FCLK_CLK0
require_bd_pin processing_system7_0/FCLK_RESET0_N

require_bd_intf_pin smartconnect_0/S00_AXI
require_bd_intf_pin smartconnect_0/M00_AXI
require_bd_pin smartconnect_0/aclk
require_bd_pin smartconnect_0/aresetn

require_bd_pin proc_sys_reset_0/ext_reset_in
require_bd_pin proc_sys_reset_0/slowest_sync_clk
require_bd_pin proc_sys_reset_0/dcm_locked
require_bd_pin proc_sys_reset_0/peripheral_aresetn

require_bd_intf_pin protection_ip_axi_lite_0/S_AXI
require_bd_pin protection_ip_axi_lite_0/ACLK
require_bd_pin protection_ip_axi_lite_0/ARESETN
require_bd_pin protection_ip_axi_lite_0/sample_valid
require_bd_pin protection_ip_axi_lite_0/i_ch1
require_bd_pin protection_ip_axi_lite_0/i_ch2

set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] $smartconnect
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL $sample_valid_const] $c_sample_valid
set_property -dict [list CONFIG.CONST_WIDTH {12} CONFIG.CONST_VAL $i_ch1_const] $c_i_ch1
set_property -dict [list CONFIG.CONST_WIDTH {12} CONFIG.CONST_VAL $i_ch2_const] $c_i_ch2
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $c_dcm_locked

# Clocking: PS FCLK_CLK0 is the first-pass 100 MHz PL/AXI clock.
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins smartconnect_0/aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins protection_ip_axi_lite_0/ACLK]

# Reset: PS FCLK_RESET0_N is active-low. After connection, Vivado should
# propagate proc_sys_reset_0/ext_reset_in to active-low and
# CONFIG.C_EXT_RESET_HIGH=0. peripheral_aresetn is active-low to match
# smartconnect_0/aresetn and protection_ip_axi_lite_0/ARESETN.
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net [get_bd_pins dcm_locked_const/dout] [get_bd_pins proc_sys_reset_0/dcm_locked]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins smartconnect_0/aresetn]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins protection_ip_axi_lite_0/ARESETN]

# AXI-Lite path: PS GP0 master -> SmartConnect -> packaged protection IP.
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins protection_ip_axi_lite_0/S_AXI]

# First-pass safe digital stimulus. These constants do not represent real ADC
# or AFE input and are only for early BD/MMIO plumbing.
connect_bd_net [get_bd_pins sample_valid_const/dout] [get_bd_pins protection_ip_axi_lite_0/sample_valid]
connect_bd_net [get_bd_pins i_ch1_const/dout] [get_bd_pins protection_ip_axi_lite_0/i_ch1]
connect_bd_net [get_bd_pins i_ch2_const/dout] [get_bd_pins protection_ip_axi_lite_0/i_ch2]

# Outputs intentionally remain internal in this first-pass BD. Do not connect
# pwm_out to real pins, a gate driver, or a power stage at this stage. Add ILA
# probes in a later Stage 2B debug Tcl after the minimal BD is reviewed.

assign_bd_address \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    -offset $planned_base_addr \
    -range $planned_range \
    [get_bd_addr_segs protection_ip_axi_lite_0/S_AXI/reg0]

validate_bd_design

set ps_reset_polarity [get_property CONFIG.POLARITY [get_bd_pins processing_system7_0/FCLK_RESET0_N]]
if {$ps_reset_polarity ne "ACTIVE_LOW"} {
    error "processing_system7_0/FCLK_RESET0_N polarity is $ps_reset_polarity; expected ACTIVE_LOW."
}

set rst_ext_reset_polarity [get_property CONFIG.POLARITY [get_bd_pins proc_sys_reset_0/ext_reset_in]]
if {$rst_ext_reset_polarity ne "ACTIVE_LOW"} {
    error "proc_sys_reset_0/ext_reset_in polarity is $rst_ext_reset_polarity; expected ACTIVE_LOW after FCLK_RESET0_N connection."
}

set rst_ext_reset_high [get_property CONFIG.C_EXT_RESET_HIGH $rst]
if {$rst_ext_reset_high ne "0"} {
    error "proc_sys_reset_0 CONFIG.C_EXT_RESET_HIGH is $rst_ext_reset_high after validation; expected 0."
}

# save_bd_design only saves the .bd when this script is explicitly run in the
# future. It does not create output products, create an HDL wrapper, or change
# the project top to a wrapper. Those remain separate reviewed future steps.
save_bd_design

puts "Stage 2 minimal block design created."
puts "BD name: $bd_name"
puts "IP repo path: $ip_repo_path"
puts "Protection IP VLNV: $protection_vlnv"
puts "AXI fabric: smartconnect_0"
puts "Planned address: base=$planned_base_addr range=$planned_range"
puts "Stimulus constants: sample_valid=1 i_ch1=12'h400 i_ch2=12'h400"
puts "PS7 board automation: DDR and FIXED_IO are expected to be externalized by the PYNQ-Z2 board preset."
puts "Reset policy: FCLK_RESET0_N drives proc_sys_reset ext_reset_in with C_EXT_RESET_HIGH=0; peripheral_aresetn drives SmartConnect/protection active-low resets."
puts "First BD run finding: axi_interconnect:1.7 was unsupported in this Vivado 2024.1 flow; this script uses SmartConnect."
puts "BD wrapper/output-product generation remains a future step."
puts "Next step: review script output and Address Editor. Still do not run synthesis, implementation, bitstream, or hardware export."
