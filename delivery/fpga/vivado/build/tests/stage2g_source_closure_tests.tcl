namespace eval ::stage2g::source_closure {
    variable repo_root [file normalize \
        [file join [file dirname [info script]] .. .. .. ..]]
    variable negative_passes 0
}

proc ::stage2g::source_closure::read_text {relative_path} {
    variable repo_root
    set path [file join $repo_root {*}[split $relative_path /]]
    if {![file isfile $path]} { error "Required file is missing: $relative_path" }
    set channel [open $path r]
    try { return [read $channel] } finally { close $channel }
}

proc ::stage2g::source_closure::assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}

proc ::stage2g::source_closure::assert_path_once {values path label} {
    set count [llength [lsearch -all -exact $values $path]]
    if {$count != 1} {
        error "$label must contain $path exactly once; actual=$count"
    }
}

proc ::stage2g::source_closure::remove_exact {values path} {
    set index [lsearch -exact $values $path]
    if {$index < 0} { error "Cannot remove absent fixture path: $path" }
    return [lreplace $values $index $index]
}

proc ::stage2g::source_closure::expect_rejected {script label} {
    variable negative_passes
    if {![catch {uplevel 1 $script}]} {
        error "Negative current source/package fixture unexpectedly passed: $label"
    }
    incr negative_passes
    puts "$label=PASS"
}

proc ::stage2g::source_closure::repo_relative_paths {values} {
    variable repo_root
    set root [string map {\\ /} [file normalize $repo_root]]
    set prefix "$root/"
    set result {}
    foreach value $values {
        set normalized [string map {\\ /} [file normalize $value]]
        if {[string first $prefix $normalized] != 0} {
            error "Live production authority returned a path outside the repository: $value"
        }
        lappend result [string range $normalized [string length $prefix] end]
    }
    return $result
}

proc ::stage2g::source_closure::token_count {text token} {
    set count 0
    set start 0
    while {1} {
        set index [string first $token $text $start]
        if {$index < 0} { return $count }
        incr count
        set start [expr {$index + [string length $token]}]
    }
}

proc ::stage2g::source_closure::validate_rtl_authority {values label} {
    assert_true {[llength $values] == 21} \
        "$label RTL source count differs from the live authority"
    assert_true {[llength [lsort -unique $values]] == [llength $values]} \
        "$label contains duplicate RTL paths"
    foreach path {
        rtl/adc_sample_cdc_bridge.v
        rtl/adc_sample_code_normalizer.sv
        rtl/async_fifo_gray.v
        rtl/generated/protection_register_map.vh
        rtl/generated/stage2f_adc_source_profile.svh
        rtl/source_observability_cdc.v
        rtl/transaction_destination_observer.v
        rtl/transaction_source_observer.v
        rtl/protection_ip_top_async_adc_axi_lite.v
        rtl/protection_ip_top_axi_lite.v
        rtl/protection_ip_top_reg_controlled.v
        rtl/protection_reg_bank.v
        rtl/fault_classifier.v
        rtl/protection_fsm.v
        rtl/protection_core_top.v
    } {
        assert_path_once $values $path $label
    }
}

proc ::stage2g::source_closure::validate_constraint_authority {values label} {
    assert_true {[llength $values] == 2} \
        "$label constraint count differs from the live authority"
    foreach path {
        fpga/vivado/constraints/stage2d_async_adc_atomic_cdc.xdc
        fpga/vivado/constraints/stage2e_transaction_observability_cdc.xdc
    } {
        assert_path_once $values $path $label
    }
}

proc ::stage2g::source_closure::validate_live_package_binding {body label} {
    foreach token {
        {generated protection_register_map_ipxact.tcl}
        {_require_file $register_map_ipxact}
        {source $register_map_ipxact}
        {protection_register_map_apply_ipxact $block}
    } {
        assert_true {[token_count $body $token] == 1} \
            "$label must contain '$token' exactly once"
    }
    foreach token {
        {ipx::get_memory_maps S_AXI}
        {ipx::get_address_blocks reg0}
        {$::PROTECTION_REGISTER_MAP_REGISTER_COUNT}
    } {
        assert_true {[string first $token $body] >= 0} \
            "$label omits live S_AXI/reg0 generated-metadata token: $token"
    }
    assert_true {
        [string first {ipx::get_address_blocks reg0} $body] <
        [string first {protection_register_map_apply_ipxact $block} $body]
    } "$label applies generated metadata before selecting live reg0"
    foreach token {
        {src/generated/protection_register_map.vh}
        {src/generated/stage2f_adc_source_profile.svh}
    } {
        assert_true {[token_count $body $token] == 1} \
            "$label must stage the generated header exactly once: $token"
    }
    assert_true {
        [token_count $body {_stage_packaged_generated_header $core $ip_root}] == 2
    } "$label must stage exactly two nested generated headers"
}

proc ::stage2g::source_closure::validate_packaged_header_helper {body label} {
    foreach token {
        {xilinx_anylanguagesynthesis}
        {xilinx_anylanguagebehavioralsimulation}
        {file copy -force -- $source $destination}
        {ipx::get_files -of_objects $group}
        {ipx::remove_file $name $group}
        {ipx::add_file $relative_path $group}
        {set_property type $file_type $file}
        {set_property is_include true $file}
        {set_property dependency {src} $group}
        {[file pathtype [get_property DEPENDENCY $group]] ne {relative}}
        {file delete -force -- $flat_path}
    } {
        assert_true {[string first $token $body] >= 0} \
            "$label omits packaged-header layout token: $token"
    }
}

proc ::stage2g::source_closure::validate_packaged_constraint_helper {
    body label
} {
    foreach token {
        {xilinx_anylanguagesynthesis}
        {xilinx_implementation}
        {ipx::remove_file $relative_path $synthesis}
        {ipx::add_file}
        {set_property type xdc $implementation_file}
        {set_property processing_order late $implementation_file}
        {$occurrence_count != 1}
        {$owning_groups ne {xilinx_implementation}}
    } {
        assert_true {[string first $token $body] >= 0} \
            "$label omits implementation-only constraint token: $token"
    }
}

proc ::stage2g::source_closure::validate_text_contract {} {
    set wrapper [read_text rtl/protection_ip_top_async_adc_axi_lite.v]
    foreach token {
        stage2g_adc_sample_cdc_bridge
        stage2g_protection_ip_axi_lite
        {.SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH)}
        dst_sample_sequence
        dst_sample_integrity_clean
        adc_sample_code_normalizer
    } {
        assert_true {[string first $token $wrapper] >= 0} \
            "Production wrapper omits current Stage 2G token: $token"
    }

    set bridge [read_text rtl/adc_sample_cdc_bridge.v]
    foreach token {
        {module stage2g_adc_sample_cdc_bridge}
        {fifo_write_data}
        {source_integrity_clean}
        {dst_sample_integrity_clean}
    } {
        assert_true {[string first $token $bridge] >= 0} \
            "ADC bridge omits current source-integrity token: $token"
    }

    set core [read_text rtl/protection_core_top.v]
    set destination [read_text rtl/transaction_destination_observer.v]
    set reg_controlled [read_text rtl/protection_ip_top_reg_controlled.v]
    set axi [read_text rtl/protection_ip_top_axi_lite.v]
    foreach pair [list \
        [list $core {module stage2g_protection_core}] \
        [list $core {input  wire sample_destination_integrity_clean}] \
        [list $core {sample_source_integrity_clean &&}] \
        [list $core {sample_destination_integrity_clean;}] \
        [list $destination {module destination_sequence_integrity_tracker}] \
        [list $destination {stage2e_transaction_sequence_classifier #(}] \
        [list $destination {sequence_delta[SEQUENCE_WIDTH-1]}] \
        [list $reg_controlled {.sample_destination_integrity_clean(}] \
        [list $axi {.sample_destination_integrity_clean(}]] {
        lassign $pair text token
        assert_true {[string first $token $text] >= 0} \
            "Current B2 source topology omits token: $token"
    }
    assert_true {[string first {stage2e_transaction_sequence_classifier} $core] < 0} \
        {Current core incorrectly owns destination sequence classification}
    assert_true {[string first {normalized_sample_valid} $core] < 0} \
        {Normalized telemetry leaked into the raw protection core}
}

proc ::stage2g::source_closure::validate_generated_metadata {} {
    variable repo_root
    source [file join $repo_root fpga vivado build tests \
        stage2e_ipxact_metadata_scope_tests.tcl]
    set generated [read_text fpga/vivado/generated/protection_register_map_ipxact.tcl]
    ::stage2e::ipxact_scope::validate_mock $generated CURRENT_LIVE_PACKAGE_IPXACT

    set properties $::stage2e::ipxact_scope::properties
    foreach {object property expected} {
        register:REGISTER_MAP_VERSION access read-only
        register:REGISTER_MAP_VERSION address_offset 0x80
        parameter:register:REGISTER_MAP_VERSION:RESET_VALUE value 0x524D0101
        register:POLICY_STATUS access read-only
        register:POLICY_STATUS address_offset 0xA0
        parameter:register:POLICY_STATUS:RESET_VALUE value 0x00000004
        field:register:POLICY_STATUS:RESET_WAIT_STATE bit_offset 2
        field:register:POLICY_STATUS:RESET_WAIT_STATE access read-only
        register:POLICY_EVALUATION_SEQUENCE address_offset 0xB0
        field:register:POLICY_EVALUATION_SEQUENCE:SEQUENCE bit_width 32
    } {
        assert_true {
            [dict exists $properties $object $property] &&
            [dict get $properties $object $property] eq $expected
        } "Generated IP-XACT representative metadata differs: $object $property"
    }
}

proc ::stage2g::source_closure::run {} {
    variable repo_root
    variable negative_passes
    set negative_passes 0

    source [file join $repo_root fpga vivado build runtime runner \
        stage1e_production_vivado_runner_v2.tcl]
    set context [dict create repository_root $repo_root]
    set rtl_files [repo_relative_paths \
        [::stage1e::production_vivado_runner_v2::_rtl_files $context]]
    set constraint_files [repo_relative_paths \
        [::stage1e::production_vivado_runner_v2::_constraint_files $context]]
    validate_rtl_authority $rtl_files LIVE_PRODUCTION_RTL_AUTHORITY
    validate_constraint_authority $constraint_files \
        LIVE_PRODUCTION_CONSTRAINT_AUTHORITY
    validate_text_contract

    set package_body [info body \
        ::stage1e::production_vivado_runner_v2::package_protection_ip]
    validate_live_package_binding $package_body LIVE_PRODUCTION_PACKAGE
    set packaged_header_body [info body \
        ::stage1e::production_vivado_runner_v2::_stage_packaged_generated_header]
    validate_packaged_header_helper $packaged_header_body \
        LIVE_PACKAGED_GENERATED_HEADER_LAYOUT
    set packaged_constraint_body [info body \
        ::stage1e::production_vivado_runner_v2::_stage_packaged_implementation_constraints]
    validate_packaged_constraint_helper $packaged_constraint_body \
        LIVE_PACKAGED_IMPLEMENTATION_CONSTRAINT_LAYOUT
    assert_true {[string first \
        {set_property USED_IN_SYNTHESIS false} $package_body] >= 0} \
        {Live package does not mark scoped XDC implementation-only}
    assert_true {[string first \
        {set_property USED_IN_SYNTHESIS true} $package_body] < 0} \
        {Live package still marks scoped XDC for synthesis}
    validate_generated_metadata

    set missing_destination [remove_exact $rtl_files \
        rtl/transaction_destination_observer.v]
    expect_rejected {
        validate_rtl_authority $missing_destination \
            NEGATIVE_B2_DESTINATION_TRACKER_OMISSION
    } CURRENT_SOURCE_CLOSURE_REJECTS_MISSING_B2_DEPENDENCY

    set missing_xdc [remove_exact $constraint_files \
        fpga/vivado/constraints/stage2e_transaction_observability_cdc.xdc]
    expect_rejected {
        validate_constraint_authority $missing_xdc NEGATIVE_XDC_OMISSION
    } LIVE_PACKAGE_REJECTS_MISSING_XDC

    set missing_ipxact [string map \
        [list {source $register_map_ipxact} {}] $package_body]
    expect_rejected {
        validate_live_package_binding $missing_ipxact NEGATIVE_IPXACT_OMISSION
    } LIVE_PACKAGE_OMITS_GENERATED_IPXACT

    set apply_token {protection_register_map_apply_ipxact $block}
    set duplicated_apply [string map \
        [list $apply_token "$apply_token\n    $apply_token"] $package_body]
    expect_rejected {
        validate_live_package_binding $duplicated_apply NEGATIVE_IPXACT_DUPLICATE
    } LIVE_PACKAGE_APPLIES_IPXACT_TWICE

    assert_true {$negative_passes == 4} \
        {Current source/package negative fixture count differs}
    puts {PRODUCTION_RTL_SOURCE_COUNT=21}
    puts {PRODUCTION_XDC_SOURCE_COUNT=2}
    puts {PRODUCTION_SOURCE_LIST_CURRENT_AUTHORITY_COUNT=1}
    puts {LIVE_PRODUCTION_PACKAGE_USES_GENERATED_IPXACT=YES}
    puts {LIVE_PACKAGED_GENERATED_HEADER_LAYOUT=PASS}
    puts {LIVE_PACKAGED_IMPLEMENTATION_CONSTRAINT_LAYOUT=PASS}
    puts {LIVE_PRODUCTION_REGISTER_COUNT=33}
    puts {LIVE_PRODUCTION_FIELD_COUNT=97}
    puts {REGISTER_MAP_VERSION_METADATA_PRESENT=YES}
    puts {POLICY_STATUS_METADATA_PRESENT=YES}
    puts {POLICY_EVALUATION_SEQUENCE_METADATA_PRESENT=YES}
    puts {LIVE_PACKAGE_IPXACT_BINDING=PASS}
    puts {STAGE2G_CORE_LOCAL_SEQUENCE_STATE_REQUIRED=NO}
    puts {CURRENT_SOURCE_CLOSURE_TARGETS_B2_TOPOLOGY=YES}
    puts {CURRENT_SOURCE_CLOSURE_NEGATIVE_FIXTURES=PASS_4_OF_4}
    puts {CONTROLLED_BUILD_SOURCE_CLOSURE=PASS}
}

if {[catch {::stage2g::source_closure::run} message options]} {
    puts stderr "STAGE2G SOURCE CLOSURE FAILED: $message"
    exit 1
}
exit 0
