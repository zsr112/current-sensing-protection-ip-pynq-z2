# Vivado 2024.1 / PYNQ-Z2 Stage 1D controlled-stimulus BD patch draft.
#
# Construction order:
#   1. create_pynq_z2_stage2_bd.tcl
#   2. add_pynq_z2_stage2b_debug.tcl
#   3. this Stage 1D patch
#
# Scope:
# - Delegate reviewed external-project lifecycle to the vivado_project adapter.
# - Delegate protection_system BD open, identity, validation, and save lifecycle
#   to the bd_flow adapter.
# - Require the base protection integration and Stage 2B System ILA.
# - Add one test-only 24-bit AXI GPIO current-code provider.
# - Preserve the protection RTL, packaged IP, register map, recovery contract,
#   existing protection-input nets, and existing ILA sinks.
# - Stop after BD validation and save.
#
# This file is fail-closed by default. It requires an operation-specific,
# controller-owned authorization assertion before mutation can begin.
# Downstream build, export, software, PYNQ, MMIO, and board operations are not
# part of this script.
#
# Reproducibility policy:
# - Repository Tcl files are the source of truth for design construction.
# - Vivado-generated projects are external build workspaces, not repository
#   design sources.
# - Every generated artifact package requires a manifest containing source,
#   Tcl, IP, and artifact identities with cryptographic hashes.
#
# Explicit compatibility input:
# - Before sourcing this patch, set stage1d_project_context to the complete
#   controller-compatible lifecycle context for the reviewed external project.
# - The context supplies workspace_root, project_path, environment identity,
#   and controller authorization explicitly; this script does not rediscover
#   project identity from environment variables.
# - The context must also carry the controller-generated authorization_assertion
#   for this execution. The wrapper passes that assertion unchanged and does not
#   create or broaden mutation authorization.
# - The compatibility wrapper translates explicit lifecycle context and
#   delegates project and BD operations to their authoritative adapters.

set expected_version_pattern {*Vivado v2024.1*}
set stage1d_source_baseline 2efeb7efaf5b97ca7850f61f1001224c00efd111
set expected_bd_name protection_system

set ps_name processing_system7_0
set reset_name proc_sys_reset_0
set smartconnect_name smartconnect_0
set protection_name protection_ip_axi_lite_0
set protection_vlnv zsr112.local:protection:protection_ip_axi_lite:0.1
# Catalog identities verified with Vivado 2024.1, Vivado build 5076996,
# and IP build 5075265.
set axi_gpio_vlnv xilinx.com:ip:axi_gpio:2.0
set xlslice_vlnv xilinx.com:ip:xlslice:1.0
set ila_name system_ila_stage2b_0

set sample_valid_const_name sample_valid_const
set i_ch1_const_name i_ch1_const
set i_ch2_const_name i_ch2_const

set gpio_name axi_gpio_stage1d_0
set slice_ch1_name xlslice_stage1d_ch1
set slice_ch2_name xlslice_stage1d_ch2

set expected_protection_base 0x43C00000
set expected_protection_range 0x00001000
set planned_gpio_base 0x41200000
set planned_gpio_range 0x00010000

# Reset/default stimulus codes only. Execution must read the active protection
# thresholds and independently freeze reviewed safe and fault values.
set gpio_width 24
set safe_current_code 1024
set safe_gpio_default [format {0x%08X} [expr {(($safe_current_code & 0xFFF) << 12) | ($safe_current_code & 0xFFF)}]]

# Load the lifecycle owners and definition-only mutation module.
set stage1d_build_root [file normalize [file join \
    [file dirname [file normalize [info script]]] build]]
set stage1d_project_adapter [file join \
    $stage1d_build_root lib vivado_project.tcl]
set stage1d_bd_adapter [file join \
    $stage1d_build_root lib bd_flow.tcl]
set stage1d_mutation_module [file normalize [file join \
    $stage1d_build_root mutation stage1d_controlled_stimulus.tcl]]
if {![file exists $stage1d_project_adapter] ||
    ![file isfile $stage1d_project_adapter]} {
    error "Stage 1D project adapter not found: $stage1d_project_adapter"
}
if {![file exists $stage1d_bd_adapter] ||
    ![file isfile $stage1d_bd_adapter]} {
    error "Stage 1D BD adapter not found: $stage1d_bd_adapter"
}
if {![file exists $stage1d_mutation_module] ||
    ![file isfile $stage1d_mutation_module]} {
    error "Stage 1D mutation module not found: $stage1d_mutation_module"
}
source $stage1d_project_adapter
source $stage1d_bd_adapter
source $stage1d_mutation_module

set vivado_version [version]
if {![string match $expected_version_pattern $vivado_version]} {
    error "Expected Vivado 2024.1. Current version output is: $vivado_version"
}

if {![info exists stage1d_project_context]} {
    error {Stage 1D compatibility entrypoint requires explicit stage1d_project_context before sourcing.}
}
if {[catch {dict size $stage1d_project_context} context_error]} {
    error "Stage 1D compatibility project context is not a dictionary: $context_error"
}
if {![dict exists $stage1d_project_context authorization_assertion]} {
    error {Stage 1D compatibility entrypoint requires a controller-owned authorization_assertion.}
}
set stage1d_authorization_assertion [dict get \
    $stage1d_project_context authorization_assertion]
set stage1d_project_adapter_context [dict remove \
    $stage1d_project_context authorization_assertion]

set project_open_result [::stage1d::vivado_project::open \
    $stage1d_project_adapter_context]
if {[dict get $project_open_result status] ne {PASS}} {
    error "Stage 1D project adapter did not open the project: status=[dict get $project_open_result status] errors=[dict get $project_open_result errors]"
}
set project_path [dict get $project_open_result outputs project_path]
set project_lifecycle_context [dict get \
    $project_open_result outputs lifecycle_context]
set bd_lifecycle_context $project_lifecycle_context
dict set bd_lifecycle_context authorization operation bd_flow_open

set stage1d_compatibility_status [catch {
    set bd_open_result [::stage1d::bd_flow::open $bd_lifecycle_context]
    if {[dict get $bd_open_result status] ne {PASS}} {
        error "Stage 1D BD adapter did not open the block design: status=[dict get $bd_open_result status] errors=[dict get $bd_open_result errors]"
    }
    set bd_lifecycle_context [dict get \
        $bd_open_result outputs lifecycle_context]
    set current_bd [dict get $bd_open_result outputs bd_name]

    set mutation_context [dict create \
        execution_id [dict get $project_lifecycle_context execution_id] \
        authorization_assertion $stage1d_authorization_assertion \
        bd_name $current_bd \
        evidence_dir [dict get $project_lifecycle_context evidence_dir] \
        environment_identity [dict get \
            $project_lifecycle_context environment_identity] \
        axi_gpio_vlnv $axi_gpio_vlnv \
        current_bd $current_bd \
        expected_bd_name $expected_bd_name \
        expected_protection_base $expected_protection_base \
        expected_protection_range $expected_protection_range \
        gpio_name $gpio_name \
        gpio_width $gpio_width \
        i_ch1_const_name $i_ch1_const_name \
        i_ch2_const_name $i_ch2_const_name \
        ila_name $ila_name \
        planned_gpio_base $planned_gpio_base \
        planned_gpio_range $planned_gpio_range \
        project_path $project_path \
        protection_name $protection_name \
        protection_vlnv $protection_vlnv \
        ps_name $ps_name \
        reset_name $reset_name \
        safe_gpio_default $safe_gpio_default \
        sample_valid_const_name $sample_valid_const_name \
        slice_ch1_name $slice_ch1_name \
        slice_ch2_name $slice_ch2_name \
        smartconnect_name $smartconnect_name \
        stage1d_source_baseline $stage1d_source_baseline \
        vivado_version $vivado_version \
        xlslice_vlnv $xlslice_vlnv \
    ]

    set mutation_result \
        [stage1d_controlled_stimulus::apply $mutation_context]
    if {[catch {dict size $mutation_result} mutation_result_error]} {
        error "Stage 1D mutation returned an invalid result: $mutation_result_error"
    }
    if {[dict size $mutation_result] > 0} {
        if {![dict exists $mutation_result status]} {
            error {Stage 1D mutation result is missing status.}
        }
        set mutation_status [dict get $mutation_result status]
        if {$mutation_status ne {PASS}} {
            set mutation_errors {}
            if {[dict exists $mutation_result errors]} {
                set mutation_errors [dict get $mutation_result errors]
            }
            error "Stage 1D mutation did not pass: status=$mutation_status errors=$mutation_errors"
        }
    }

    dict set bd_lifecycle_context authorization operation bd_flow_validate
    set bd_validate_result [::stage1d::bd_flow::validate \
        $bd_lifecycle_context]
    if {[dict get $bd_validate_result status] ne {PASS}} {
        error "Stage 1D BD adapter did not validate the block design: status=[dict get $bd_validate_result status] errors=[dict get $bd_validate_result errors]"
    }
    set bd_lifecycle_context [dict get \
        $bd_validate_result outputs lifecycle_context]

    dict set bd_lifecycle_context authorization operation bd_flow_save
    set bd_save_result [::stage1d::bd_flow::save $bd_lifecycle_context]
    if {[dict get $bd_save_result status] ne {PASS}} {
        error "Stage 1D BD adapter did not save the block design: status=[dict get $bd_save_result status] errors=[dict get $bd_save_result errors]"
    }
} stage1d_compatibility_error stage1d_compatibility_options]

if {$stage1d_compatibility_status != 0} {
    set cleanup_result [::stage1d::vivado_project::cleanup \
        $project_lifecycle_context \
        {legacy Stage 1D BD or mutation failure}]
    if {[dict get $cleanup_result status] ne {PASS}} {
        puts stderr "Stage 1D project cleanup failed: [dict get $cleanup_result errors]"
    }
    return -options $stage1d_compatibility_options $stage1d_compatibility_error
}

set project_close_result [::stage1d::vivado_project::close \
    $project_lifecycle_context]
if {[dict get $project_close_result status] ne {PASS}} {
    error "Stage 1D project adapter did not close the project: status=[dict get $project_close_result status] errors=[dict get $project_close_result errors]"
}

puts "Final GPIO address must be confirmed in Address Editor/readback, HWH, and Overlay metadata."
puts "No downstream build or hardware action was requested by this patch."
