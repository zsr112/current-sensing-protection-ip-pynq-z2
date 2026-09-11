# Vivado 2024.1 / PYNQ-Z2 Stage 2B debug insertion draft.
#
# Purpose:
# - Add observation-oriented debug IP for later PYNQ MMIO and fault behavior work.
# - Use one mixed System ILA to observe the AXI-Lite interface delivered to the
#   protection IP and scalar protection signals in the same debug core.
# - This improves visibility only. It does not prove PYNQ MMIO behavior,
#   protection functionality, timing closure, or board-level safety.
#
# Safety:
# - This draft is guarded by default and will not open the external project/BD or
#   mutate the BD unless enable_bd_mutation_after_cloned_dry_run_review is manually set to 1.
# - Set the guard to 1 only after reviewing the Stage 2B-0/0.1/0.2 dry-run
#   evidence and explicitly choosing to mutate the external Stage 2A BD.
# - This script does not run downstream build, hardware export, or programming
#   artifact generation commands.
#
# CURRENT_ADC_SRC_CLK_EQUALS_ACLK=YES
# ACLK_ILA_READY_OBSERVATION_VALID_ONLY_WHILE_CLOCKS_IDENTICAL=YES
# DISTINCT_ADC_CLOCK_REQUIRES_SOURCE_CLOCK_ILA_OR_SYNCHRONIZED_OBSERVATION=YES
# DIRECT_ASYNC_READY_OBSERVATION_AS_CDC_PROOF=FORBIDDEN

set expected_version_pattern {*Vivado v2024.1*}
set configured_project [lindex $argv 0]
set configured_bd [lindex $argv 1]
if {$configured_project eq "" && [info exists ::env(CSIP_PROJECT_PATH)]} { set configured_project $::env(CSIP_PROJECT_PATH) }
if {$configured_bd eq "" && [info exists ::env(CSIP_BD_PATH)]} { set configured_bd $::env(CSIP_BD_PATH) }
if {$configured_project eq "" || $configured_bd eq ""} { error "Supply project and BD paths through -tclargs or CSIP_PROJECT_PATH/CSIP_BD_PATH" }
set project_path [file normalize $configured_project]
set bd_path [file normalize $configured_bd]
set expected_part xc7z020clg400-1
set expected_board_part tul.com.tw:pynq-z2:part0:1.0
set bd_name protection_system

set enable_bd_mutation_after_cloned_dry_run_review 0
set system_ila_name system_ila_stage2b_0

proc require_ipdef {pattern label} {
    set defs [get_ipdefs -all -quiet $pattern]
    if {[llength $defs] == 0} {
        error "Required IP definition not found for $label: $pattern"
    }
    return [lindex $defs 0]
}

proc require_bd_cell_absent {name} {
    set cells [get_bd_cells -quiet $name]
    if {[llength $cells] != 0} {
        error "Debug cell already exists: $name. Archive/remove the prior debug BD before rerunning; this script does not overwrite or use -force."
    }
}

proc require_bd_pin {path} {
    set pins [get_bd_pins -quiet $path]
    if {[llength $pins] == 0} {
        error "Required BD pin not found: $path"
    }
    return [lindex $pins 0]
}

proc require_bd_intf_pin {path} {
    set pins [get_bd_intf_pins -quiet $path]
    if {[llength $pins] == 0} {
        error "Required BD interface pin not found: $path"
    }
    return [lindex $pins 0]
}

proc debug_net_name {path} {
    set name $path
    regsub -all {[^A-Za-z0-9_]} $name "_" name
    return "dbg_$name"
}

proc connect_pin_to_existing_or_new_net {signal_pin_path sink_pin_path} {
    set signal_pin [require_bd_pin $signal_pin_path]
    set sink_pin [require_bd_pin $sink_pin_path]

    set nets [get_bd_nets -quiet -of_objects $signal_pin]
    if {[llength $nets] == 0} {
        set net_name [debug_net_name $signal_pin_path]
        if {[llength [get_bd_nets -quiet $net_name]] != 0} {
            error "Debug net name already exists before connection: $net_name"
        }
        set net [create_bd_net $net_name]
        connect_bd_net -net $net $signal_pin
        connect_bd_net -net $net $sink_pin
    } else {
        set net [lindex $nets 0]
        connect_bd_net -net $net $sink_pin
    }
}

proc connect_monitor_to_existing_intf_net {target_intf_pin_path monitor_intf_pin_path} {
    set target_pin [require_bd_intf_pin $target_intf_pin_path]
    set monitor_pin [require_bd_intf_pin $monitor_intf_pin_path]

    set nets [get_bd_intf_nets -quiet -of_objects $target_pin]
    if {[llength $nets] == 0} {
        error "AXI interface pin is not connected to an interface net: $target_intf_pin_path"
    }

    # The net lookup is a sanity check only; the actual connection intentionally uses pin-to-pin form.
    # Vivado 2024.1 dry-run proved that pin-to-pin form safely attaches the
    # monitor to the existing interface net. Passing the net name can be parsed
    # as a pin/port name in this flow.
    connect_bd_intf_net $target_pin $monitor_pin
}

proc assert_bd_pin_width {pin_path expected_width} {
    set pin [require_bd_pin $pin_path]
    set left [get_property LEFT $pin]
    set right [get_property RIGHT $pin]

    if {$left eq "" && $right eq ""} {
        set actual_width 1
    } elseif {$left eq "" || $right eq ""} {
        error "Cannot determine width for $pin_path: LEFT='$left' RIGHT='$right'"
    } else {
        set actual_width [expr {abs(int($left) - int($right)) + 1}]
    }

    if {$actual_width != $expected_width} {
        error "Unexpected width for $pin_path: actual=$actual_width expected=$expected_width"
    }

    puts "assert_bd_pin_width_ok pin=$pin_path width=$actual_width"
}

set vivado_version [version]
if {![string match $expected_version_pattern $vivado_version]} {
    error "Expected Vivado 2024.1. Current version output is: $vivado_version"
}

if {![file exists $project_path]} {
    error "Stage 2A project not found: $project_path"
}

if {![file exists $bd_path]} {
    error "Stage 2A block design not found: $bd_path"
}

if {!$enable_bd_mutation_after_cloned_dry_run_review} {
    error "Stage 2B BD mutation guard is disabled. Review the cloned-BD dry-run evidence, then manually set enable_bd_mutation_after_cloned_dry_run_review to 1 before mutating the external Stage 2A BD."
}

open_project $project_path

set current_part [get_property PART [current_project]]
if {$current_part ne $expected_part} {
    error "Unexpected project part: $current_part. Expected: $expected_part"
}

set current_board_part [get_property BOARD_PART [current_project]]
if {$current_board_part ne $expected_board_part} {
    error "Unexpected board_part: $current_board_part. Expected: $expected_board_part"
}

open_bd_design $bd_path

set current_bd [current_bd_design]
if {$current_bd ne $bd_name} {
    error "Unexpected current_bd_design: $current_bd. Expected: $bd_name"
}

require_bd_cell_absent $system_ila_name

require_bd_intf_pin protection_ip_axi_lite_0/S_AXI
require_bd_intf_pin smartconnect_0/M00_AXI
require_bd_pin processing_system7_0/FCLK_CLK0
require_bd_pin proc_sys_reset_0/peripheral_aresetn
require_bd_pin protection_ip_axi_lite_0/ARESETN

set resetn_pin [require_bd_pin proc_sys_reset_0/peripheral_aresetn]
set resetn_polarity [get_property CONFIG.POLARITY $resetn_pin]
if {$resetn_polarity ne "ACTIVE_LOW"} {
    error "Expected proc_sys_reset_0/peripheral_aresetn to be ACTIVE_LOW, got '$resetn_polarity'"
}

set scalar_probe_specs [list \
    [list protection_ip_axi_lite_0/ARESETN 1] \
    [list protection_ip_axi_lite_0/adc_sample_valid 1] \
    [list protection_ip_axi_lite_0/adc_sample_ch1 12] \
    [list protection_ip_axi_lite_0/adc_sample_ch2 12] \
    [list protection_ip_axi_lite_0/pwm_raw 1] \
    [list protection_ip_axi_lite_0/pwm_out 1] \
    [list protection_ip_axi_lite_0/fault_valid 1] \
    [list protection_ip_axi_lite_0/fault_latched 1] \
    [list protection_ip_axi_lite_0/fault_code 8] \
    [list protection_ip_axi_lite_0/fault_code_latched 8] \
    [list protection_ip_axi_lite_0/fsm_state 4] \
    [list protection_ip_axi_lite_0/adc_sample_ready 1] \
]

foreach spec $scalar_probe_specs {
    require_bd_pin [lindex $spec 0]
}

set system_ila_vlnv [require_ipdef xilinx.com:ip:system_ila:* system_ila]

set system_ila [create_bd_cell -type ip -vlnv $system_ila_vlnv $system_ila_name]
set_property -dict [list \
    CONFIG.C_MON_TYPE {MIX} \
    CONFIG.C_NUM_MONITOR_SLOTS {1} \
    CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:aximm_rtl:1.0} \
    CONFIG.C_SLOT_0_AXI_PROTOCOL {AXI4LITE} \
    CONFIG.C_NUM_OF_PROBES [llength $scalar_probe_specs] \
    CONFIG.C_DATA_DEPTH {4096} \
] $system_ila

require_bd_pin ${system_ila_name}/clk
require_bd_pin ${system_ila_name}/resetn
require_bd_intf_pin ${system_ila_name}/SLOT_0_AXI

set probe_index 0
foreach spec $scalar_probe_specs {
    require_bd_pin ${system_ila_name}/probe${probe_index}
    incr probe_index
}

# FCLK_CLK0 is the debug sampling clock. resetn is active low and follows the
# peripheral reset net already used by the protection IP.
connect_pin_to_existing_or_new_net processing_system7_0/FCLK_CLK0 ${system_ila_name}/clk
connect_pin_to_existing_or_new_net proc_sys_reset_0/peripheral_aresetn ${system_ila_name}/resetn

# Monitor the AXI-Lite traffic delivered to the protection IP receive side.
connect_monitor_to_existing_intf_net protection_ip_axi_lite_0/S_AXI ${system_ila_name}/SLOT_0_AXI

# Internal observation only: these output pins get debug nets when they were
# otherwise unconnected. This does not route PWM or fault outputs to board pins,
# gate drivers, or a power stage.
set probe_index 0
foreach spec $scalar_probe_specs {
    set signal_pin [lindex $spec 0]
    puts "connect_scalar_probe probe${probe_index} <= $signal_pin width=[lindex $spec 1]"
    connect_pin_to_existing_or_new_net $signal_pin ${system_ila_name}/probe${probe_index}
    incr probe_index
}

validate_bd_design

set probe_index 0
foreach spec $scalar_probe_specs {
    assert_bd_pin_width ${system_ila_name}/probe${probe_index} [lindex $spec 1]
    incr probe_index
}

save_bd_design

puts "Stage 2B debug draft applied."
puts "Debug core: $system_ila_name is a mixed System ILA for protection AXI-Lite and scalar probes."
puts "AXI monitor: SLOT_0_AXI attached to protection_ip_axi_lite_0/S_AXI."
puts "Scalar probes: protection reset, ADC valid/data/ready, PWM/fault outputs, fault codes, and fsm_state."
puts "Observation only: later AXI GPIO/stimulus IP or real sampling hardware is still needed for broader validation."

close_project
exit
