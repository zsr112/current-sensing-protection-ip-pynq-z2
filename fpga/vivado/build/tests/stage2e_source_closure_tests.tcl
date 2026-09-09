namespace eval ::stage2e::source_closure {
    variable repo_root [file normalize \
        [file join [file dirname [info script]] .. .. .. ..]]
    variable negative_passes 0
}

proc ::stage2e::source_closure::read_text {relative_path} {
    variable repo_root
    set path [file join $repo_root {*}[split $relative_path /]]
    if {![file isfile $path]} { error "Required file is missing: $relative_path" }
    set channel [open $path r]
    try { return [read $channel] } finally { close $channel }
}

proc ::stage2e::source_closure::read_dict_file {relative_path} {
    set value [read_text $relative_path]
    if {[catch {dict size $value} message]} {
        error "Invalid Tcl dictionary $relative_path: $message"
    }
    return $value
}

proc ::stage2e::source_closure::assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}

proc ::stage2e::source_closure::assert_path_once {values path label} {
    set count [llength [lsearch -all -exact $values $path]]
    if {$count != 1} {
        error "$label must contain $path exactly once; actual=$count"
    }
}

proc ::stage2e::source_closure::validate_observability_sources {values label} {
    foreach path {
        rtl/adc_sample_cdc_bridge.v
        rtl/adc_sample_code_normalizer.sv
        rtl/async_fifo_gray.v
        rtl/generated/stage2f_adc_source_profile.svh
        rtl/source_observability_cdc.v
        rtl/transaction_destination_observer.v
        rtl/transaction_source_observer.v
        rtl/generated/protection_register_map.vh
        rtl/protection_ip_top_async_adc_axi_lite.v
        rtl/protection_ip_top_axi_lite.v
        rtl/protection_ip_top_reg_controlled.v
        rtl/protection_reg_bank.v
    } {
        assert_path_once $values $path $label
    }
}

proc ::stage2e::source_closure::validate_constraints {values label} {
    foreach path {
        fpga/vivado/constraints/stage2d_async_adc_atomic_cdc.xdc
        fpga/vivado/constraints/stage2e_transaction_observability_cdc.xdc
    } {
        assert_path_once $values $path $label
    }
}

proc ::stage2e::source_closure::remove_exact {values path} {
    set index [lsearch -exact $values $path]
    if {$index < 0} { error "Cannot remove absent negative-fixture path: $path" }
    return [lreplace $values $index $index]
}

proc ::stage2e::source_closure::expect_rejected {script label} {
    variable negative_passes
    if {![catch {uplevel 1 $script}]} {
        error "Negative Stage 2E source fixture unexpectedly passed: $label"
    }
    incr negative_passes
    puts "$label=PASS"
}

proc ::stage2e::source_closure::require_tokens {text tokens label} {
    foreach token $tokens {
        if {[string first $token $text] < 0} {
            error "$label omits required token: $token"
        }
    }
}

proc ::stage2e::source_closure::validate_register_maps {
    rtl documentation header python package contract
} {
    set entries {
        {OBS_CAPABILITY 28}
        {OBS_STATUS_W1C 2C}
        {OBS_SOURCE_ACCEPT_COUNT 30}
        {OBS_DESTINATION_DELIVERY_COUNT 34}
        {OBS_BACKPRESSURE_CYCLE_COUNT 38}
        {OBS_SOURCE_PROTOCOL_VIOLATION_COUNT 3C}
        {OBS_SOURCE_DROP_COUNT 40}
        {OBS_FIFO_OVERFLOW_ATTEMPT_COUNT 44}
        {OBS_FIFO_UNDERFLOW_ATTEMPT_COUNT 48}
        {OBS_DUPLICATE_DELIVERY_COUNT 4C}
        {OBS_SEQUENCE_GAP_COUNT 50}
        {OBS_REORDER_OR_STALE_COUNT 54}
        {OBS_AGGREGATE_ERROR_COUNT 58}
        {OBS_LAST_SOURCE_SEQUENCE 5C}
        {OBS_LAST_DESTINATION_SEQUENCE 60}
    }
    foreach entry $entries {
        lassign $entry name offset
        require_tokens $rtl [list \
            "`define PROTECTION_REG_${name} 8'h${offset}"] {RTL register map}
        require_tokens $documentation [list $name "0x$offset"] \
            {Register-map documentation}
        require_tokens $header [list "PROTECTION_REG_${name} 0x${offset}u"] \
            {C software map}
        require_tokens $python [list "${name} = 0x$offset" "REG_${name}"] \
            {Python software map}
        require_tokens $package [list "0x$offset" $name] {Package map}
    }
    require_tokens $contract {
        {"capability_offset": "0x28"}
        {"status_w1c_offset": "0x2C"}
        {"status_w1c_mask": "0x000001FF"}
        {"any_error_access": "READ_ONLY_MAINTAINED_POST_CLEAR_AGGREGATE"}
        {"counter_range": ["0x30", "0x58"]}
        {"last_sequence_range": ["0x5C", "0x60"]}
    } {Execution register contract}
}

proc ::stage2e::source_closure::run {} {
    variable negative_passes
    set negative_passes 0
    set phase2 [read_dict_file \
        fpga/vivado/build/config/stage1e_phase2_synthesis_config_v1.dict]
    set stage1d [read_dict_file \
        fpga/vivado/build/config/stage1d_build_config.dict]

    foreach key_path {
        {source_verification required_paths}
        {environment custom_protection_ip source_paths}
        {reconstruction_policy packaging source_paths}
        {reconstruction_policy packaging package_inventory source_paths}
    } {
        validate_observability_sources [dict get $phase2 {*}$key_path] \
            "Phase 2 $key_path"
    }
    foreach key_path {
        {source_verification required_paths}
        {environment custom_protection_ip source_paths}
    } {
        validate_observability_sources [dict get $stage1d {*}$key_path] \
            "Stage 1D $key_path"
    }
    validate_constraints [dict get $phase2 source_verification required_paths] \
        {Phase 2 required paths}
    validate_constraints [dict get $phase2 reconstruction_policy packaging \
        package_inventory constraint_paths] {Package constraint inventory}
    validate_constraints [dict get $stage1d source_verification required_paths] \
        {Stage 1D required paths}
    validate_constraints [dict get $stage1d environment custom_protection_ip \
        source_paths] {Stage 1D custom IP paths}

    foreach config [list $phase2 $stage1d] label {Phase2 Stage1D} {
        foreach key {required_paths tcl_paths} {
            foreach test_path {
                fpga/vivado/build/tests/stage2e_source_closure_tests.tcl
                fpga/vivado/build/tests/stage2e_observability_cdc_constraint_tests.tcl
            } {
                assert_path_once [dict get $config source_verification $key] \
                    $test_path "$label $key"
            }
        }
    }

    assert_true {
        [dict get $phase2 reconstruction_policy packaging vlnv_expectation \
            version] eq {0.3}
    } {Package VLNV expectation is not 0.3}
    assert_true {
        [dict get $phase2 environment custom_protection_ip vlnv] eq
            {zsr112.local:protection:protection_ip_axi_lite:0.3}
    } {Phase 2 custom-IP VLNV is not 0.3}
    assert_true {
        [dict get $stage1d environment custom_protection_ip vlnv] eq
            {zsr112.local:protection:protection_ip_axi_lite:0.3}
    } {Stage 1D custom-IP VLNV is not 0.3}
    assert_true {
        [dict get $phase2 reconstruction_policy packaging package_inventory \
            user_parameters OBS_SEQUENCE_WIDTH] == 32
    } {Package inventory omits the 32-bit sequence parameter}

    foreach direct_authority {
        fpga/vivado/package_protection_ip_stage2_axi_lite.tcl
        fpga/vivado/create_pynq_z2_project_stage1_boardpart.tcl
        fpga/vivado/create_pynq_z2_project_preboard.tcl
        fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl
    } {
        set text [read_text $direct_authority]
        assert_true {[info complete $text]} \
            "$direct_authority is not complete Tcl"
        require_tokens $text {
            adc_sample_code_normalizer.sv
            stage2f_adc_source_profile.svh
            source_observability_cdc.v
            transaction_destination_observer.v
            transaction_source_observer.v
            stage2e_transaction_observability_cdc.xdc
        } $direct_authority
    }
    foreach vlnv_authority {
        fpga/vivado/create_pynq_z2_stage2_bd.tcl
        fpga/vivado/add_pynq_z2_stage1d_controlled_stimulus.tcl
        fpga/vivado/build/controller/controller_core.tcl
        fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl
        fpga/vivado/build/config/stage1e_execution_contract_v1.json
    } {
        require_tokens [read_text $vlnv_authority] \
            {zsr112.local:protection:protection_ip_axi_lite:0.3} \
            $vlnv_authority
    }
    require_tokens [read_text \
        fpga/vivado/package_protection_ip_stage2_axi_lite.tcl] \
        {{set ip_version 0.3}} {Package IP version authority}
    require_tokens [read_text \
        fpga/vivado/package_protection_ip_stage2_axi_lite.tcl] {
        {set ip_xact_address_block_metadata PASS}
        {set ip_xact_register_objects GENERATED_FROM_LIVE_REGISTER_MAP}
        {set external_register_map_authority SPEC_REGISTER_MAP_JSON}
        protection_register_map_apply_ipxact
    } {Package IP-XACT scope authority}

    set bridge [read_text rtl/adc_sample_cdc_bridge.v]
    require_tokens $bridge {
        transaction_source_observer
        {source_sequence, src_sample_ch1, src_sample_ch2}
        {fifo_write_enable = src_rst_n &&}
        {src_sample_valid && src_sample_ready}
        dst_sample_sequence
    } {ADC bridge}
    set source_monitor [read_text rtl/transaction_source_observer.v]
    require_tokens $source_monitor {
        stall_pending
        stall_payload_snapshot
        stall_violation_recorded
        source_protocol_violation_event
        backpressure_cycle
        counter_binary_to_gray
    } {Source monitor}
    set destination_monitor [read_text rtl/transaction_destination_observer.v]
    require_tokens $destination_monitor {
        expected_sequence
        last_destination_sequence
        duplicate_delivery_event
        sequence_gap_event
        reorder_or_stale_event
        post_clear_specific_status
        post_clear_any_error
        {event_status[STATUS_ANY_ERROR] = 1'b0;}
    } {Destination monitor}
    assert_true {[string first {payload_equal} $destination_monitor] < 0} \
        {Destination identity monitor depends on payload equality}
    set source_cdc [read_text rtl/source_observability_cdc.v]
    require_tokens $source_cdc {
        {ASYNC_REG = "TRUE"}
        source_accept_count_gray_sync1
        source_accept_count_gray_sync2
        counter_gray_to_binary
    } {Source observability CDC}

    set reg_rtl [read_text rtl/generated/protection_register_map.vh]
    set implementation_rtl [read_text rtl/protection_reg_bank.v]
    set reg_doc [read_text docs/implementation/register_map.md]
    set c_header [read_text sw/ps_register_demo/protection_ip_regs.h]
    set python_map [read_text sw/generated/protection_register_map.py]
    set package [read_text \
        fpga/vivado/generated/protection_register_map_ipxact.tcl]
    set contract [read_text \
        fpga/vivado/build/config/stage1e_execution_contract_v1.json]
    validate_register_maps $reg_rtl $reg_doc $c_header $python_map \
        $package $contract
    require_tokens $implementation_rtl {
        {obs_status_w1c_clear[8] <= wr_data[8]}
    } {AXI status W1C cause-bit mask}
    assert_true {[string first {obs_status_w1c_clear[9:8] <=} $implementation_rtl] < 0} \
        {AXI status W1C still exposes read-only ANY_ERROR as writable}
    require_tokens $contract {
        REGISTERED_GRAY_MONOTONIC_COUNTERS
        {"eventually_consistent": true}
        {"atomic_multi_register_snapshot": false}
        {"external_irq": false}
    } {Execution observability contract}

    set canonical [dict get $phase2 environment custom_protection_ip source_paths]
    foreach negative {
        {rtl/transaction_source_observer.v NEGATIVE_SOURCE_MONITOR_OMISSION}
        {rtl/source_observability_cdc.v NEGATIVE_GRAY_CDC_OMISSION}
        {rtl/transaction_destination_observer.v NEGATIVE_DESTINATION_MONITOR_OMISSION}
    } {
        lassign $negative path label
        set reduced [remove_exact $canonical $path]
        expect_rejected {
            validate_observability_sources $reduced $label
        } $label
    }
    set constraints [dict get $phase2 reconstruction_policy packaging \
        package_inventory constraint_paths]
    set reduced_constraints [remove_exact $constraints \
        fpga/vivado/constraints/stage2e_transaction_observability_cdc.xdc]
    expect_rejected {
        validate_constraints $reduced_constraints NEGATIVE_OBS_XDC_OMISSION
    } NEGATIVE_OBSERVABILITY_CONSTRAINT_OMISSION

    set bad_python [string map {{OBS_SEQUENCE_GAP_COUNT = 0x50} \
        {OBS_SEQUENCE_GAP_COUNT = 0x54}} $python_map]
    expect_rejected {
        validate_register_maps $reg_rtl $reg_doc $c_header $bad_python \
            $package $contract
    } NEGATIVE_SOFTWARE_REGISTER_MAP_MISMATCH

    set bad_contract [string map {{"capability_offset": "0x28"} \
        {"capability_offset": "0x24"}} $contract]
    expect_rejected {
        validate_register_maps $reg_rtl $reg_doc $c_header $python_map \
            $package $bad_contract
    } NEGATIVE_EXECUTION_CONTRACT_REGISTER_MAP_MISMATCH

    assert_true {$negative_passes == 6} \
        {Stage 2E source-closure negative fixture count is not six}
    puts {STAGE2E_RTL_SOURCE_AUTHORITIES=PASS}
    puts {STAGE2E_CDC_SOURCE_AUTHORITY=PASS}
    puts {STAGE2E_REGISTER_MAP_CONVERGENCE=PASS}
    puts {STAGE2E_SOFTWARE_MAP_CONVERGENCE=PASS}
    puts {STAGE2E_IP_VLNV=0.3}
    puts {STAGE2E_SOURCE_CLOSURE_NEGATIVE_FIXTURES=PASS_6_OF_6}
    puts {STAGE2E_SOURCE_CLOSURE_TESTS=PASS}
}

if {[file normalize [info script]] eq [file normalize $::argv0]} {
    if {[catch {::stage2e::source_closure::run} message options]} {
        puts stderr "STAGE2E SOURCE CLOSURE FAILED: $message"
        exit 1
    }
}
