# Pre-board draft. Not validated on PYNQ-Z2 hardware yet.
#
# Draft Vivado Tcl for planning the PYNQ-Z2 project.
# This script has not been run in Windows Vivado and does not prove synthesis,
# implementation, bitstream generation, or board validation.

set proj_name current_protection_ip_pynq_z2_preboard
set proj_dir ./vivado_project_pynq_z2_preboard
set part_name xc7z020clg400-1

create_project $proj_name $proj_dir -part $part_name -force

set repo_root [file normalize [file join [pwd] ../..]]
set rtl_dir [file join $repo_root rtl]
set cdc_constraints [list \
    [file join $repo_root vivado constraints stage2d_async_adc_atomic_cdc.xdc] \
    [file join $repo_root vivado constraints stage2e_transaction_observability_cdc.xdc] \
]

add_files -norecurse [list \
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
set_property file_type {Verilog Header} [get_files [file join $rtl_dir fault_defs.vh]]
set_property file_type {Verilog Header} [get_files \
    [file join $rtl_dir generated stage2f_adc_source_profile.svh]]
set_property include_dirs [list $rtl_dir] [current_fileset]
foreach cdc_constraint $cdc_constraints {
    if {![file isfile $cdc_constraint]} {
        error "Required CDC constraint not found: $cdc_constraint"
    }
}
add_files -norecurse -fileset constrs_1 $cdc_constraints
foreach cdc_constraint $cdc_constraints {
    set_property file_type XDC [get_files $cdc_constraint]
    set_property USED_IN_SYNTHESIS true [get_files $cdc_constraint]
    set_property USED_IN_IMPLEMENTATION true [get_files $cdc_constraint]
    set_property PROCESSING_ORDER LATE [get_files $cdc_constraint]
}

# Draft only: AXI-Lite integration should package the asynchronous ADC wrapper
# into a Zynq PS block design. Do not treat this top property as a completed BD.
set_property top protection_ip_top_async_adc_axi_lite [current_fileset]
update_compile_order -fileset sources_1

puts "Pre-board draft created with Stage 2D FIFO and Stage 2E observability CDC XDC authorities. Add Zynq PS, AXI interconnect, clock/reset, ILA, address map, and reviewed board-pin XDC in Vivado."
puts "Confirm base address in Vivado Address Editor; 0x43C00000 is only a placeholder."
