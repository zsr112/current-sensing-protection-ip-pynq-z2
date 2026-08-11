# Vivado 2024.1 / PYNQ-Z2 Stage 1 project skeleton.
#
# Scope:
# - Create a board-part project outside this Git repository.
# - Add the current RTL sources.
# - Set the strict asynchronous-ADC AXI-Lite wrapper as the top module.
# - Stop before block design, synthesis, implementation, bitstream, or export.
#
# Run from Vivado 2024.1, for example:
# Run in Vivado 2024.1 batch mode from this repository root.

set expected_version_pattern {*Vivado v2024.1*}
set board_part_name tul.com.tw:pynq-z2:part0:1.0
set part_name xc7z020clg400-1
set project_name current_protection_ip_pynq_z2_stage1_boardpart
if {![info exists ::env(PROTECTION_IP_VIVADO_BUILD_ROOT)] || $::env(PROTECTION_IP_VIVADO_BUILD_ROOT) eq ""} {
    error "Set PROTECTION_IP_VIVADO_BUILD_ROOT to an external writable build root."
}
set public_build_root [file normalize $::env(PROTECTION_IP_VIVADO_BUILD_ROOT)]
set work_root [file join $public_build_root vivado_work]
set project_dir [file normalize [file join $work_root pynq_z2_stage1_boardpart]]
set top_module protection_ip_top_async_adc_axi_lite

set raw_script_path [info script]
if {$raw_script_path eq ""} {
    error "This script must be sourced from its file path so the repository root can be resolved safely."
}

set script_path [file normalize $raw_script_path]
set script_dir [file dirname $script_path]
set repo_root [file normalize [file join $script_dir ../..]]
set rtl_dir [file join $repo_root rtl]
set cdc_constraints [list \
    [file join $repo_root vivado constraints stage2d_async_adc_atomic_cdc.xdc] \
    [file join $repo_root vivado constraints stage2e_transaction_observability_cdc.xdc] \
]

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
    [file join $rtl_dir generated stage2f_adc_source_profile.svh] \
    [file join $rtl_dir reset_release_sync.v] \
    [file join $rtl_dir current_compare_dual.v] \
    [file join $rtl_dir fault_classifier.v] \
    [file join $rtl_dir moving_avg_filter.v] \
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

foreach rtl_file $rtl_files {
    if {![file exists $rtl_file]} {
        error "Required RTL file not found: $rtl_file"
    }
}
foreach cdc_constraint $cdc_constraints {
    if {![file isfile $cdc_constraint]} {
        error "Required CDC constraint not found: $cdc_constraint"
    }
}

set normalized_repo_root [string tolower [file normalize $repo_root]]
set normalized_project_dir [string tolower [file normalize $project_dir]]
if {[string first $normalized_repo_root $normalized_project_dir] == 0} {
    error "Refusing to create the Vivado project inside the Git repository: $project_dir"
}

if {[file exists $project_dir]} {
    error "Project output directory already exists: $project_dir. Remove or archive that work directory manually before rerunning."
}

file mkdir $work_root
create_project $project_name $project_dir -part $part_name
set_property board_part $board_part_name [current_project]
set_property target_language Verilog [current_project]

add_files -norecurse -fileset sources_1 $rtl_files
add_files -norecurse -fileset constrs_1 $cdc_constraints
set_property file_type {Verilog Header} [get_files [file join $rtl_dir fault_defs.vh]]
set_property file_type {Verilog Header} [get_files \
    [file join $rtl_dir generated stage2f_adc_source_profile.svh]]
foreach cdc_constraint $cdc_constraints {
    set_property file_type XDC [get_files $cdc_constraint]
    set_property USED_IN_SYNTHESIS true [get_files $cdc_constraint]
    set_property USED_IN_IMPLEMENTATION true [get_files $cdc_constraint]
    set_property PROCESSING_ORDER LATE [get_files $cdc_constraint]
}
set_property include_dirs [list $rtl_dir] [current_fileset]
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

# The placeholder board-pin XDC at fpga/constraints/pynq_z2_preboard_draft.xdc is not added here.
# The internal Stage 2D CDC authority above is production-required and independent of board pins.
# Stage 1 intentionally does not create a Zynq block design or any generated hardware outputs.

puts "Stage 1 PYNQ-Z2 board-part project skeleton created."
puts "Project directory: $project_dir"
puts "Board part: $board_part_name"
puts "Part: $part_name"
puts "Top: $top_module"
puts "Next: inspect the .xpr and RTL hierarchy before adding block design Tcl."
