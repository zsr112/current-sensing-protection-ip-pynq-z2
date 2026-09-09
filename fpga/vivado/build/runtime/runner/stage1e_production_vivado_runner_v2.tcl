# Stage 1E continuous Vivado build driver v2.
#
# The public Tcl surface remains one named execution context. The bounded
# helpers below reconstruct the reviewed Stage 1E AXI-GPIO/System-ILA design,
# perform exact final-BD readback before synthesis, execute Project Mode, and
# publish evidence. They do not own independent lifecycles.

set ::stage1e_vivado_runner_v2_dir [file dirname [info script]]
set ::stage1e_vivado_runner_v2_build [file dirname [file dirname $::stage1e_vivado_runner_v2_dir]]
if {![llength [info commands ::stage1e::production_vivado_observer_v2::observe_fixture]]} {
    source [file join $::stage1e_vivado_runner_v2_build runtime observer vivado stage1e_production_vivado_observer_v2.tcl]
}
if {![llength [info commands ::stage1e::production_vivado_collector_v2::collect_live]]} {
    source [file join $::stage1e_vivado_runner_v2_build runtime collector stage1e_production_vivado_collector_v2.tcl]
}
if {![llength [info commands ::stage1e::canonical_json_v1::canonical_bytes]]} {
    source [file join $::stage1e_vivado_runner_v2_build lib stage1e_runtime_canonical_json_v1.tcl]
}

namespace eval ::stage1e::production_vivado_runner_v2 {
    variable interface_version stage1e-production-vivado-runner-interface-v2
    variable implementation_phases {opt_design place_design route_design}
    variable build_root [file dirname [file dirname [file dirname [info script]]]]
    variable journal_ordinal 0
    variable context_fields {
        context_schema_version execution_id request_identity run_kind
        repository_root vivado_version vivado_build workspace_path project_path
        output_path report_root artifact_root result_path part board_part
        build_target implementation_profile source_commit source_tree
        execution_contract_identity
        finding_decision_identity project_retention process_identity
        project_identity design_identity phase_journal_path
    }
}
unset ::stage1e_vivado_runner_v2_dir
unset ::stage1e_vivado_runner_v2_build

proc ::stage1e::production_vivado_runner_v2::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_vivado_runner_v2::_is_ready_aware_profile {profile} {
    return [expr {$profile eq {READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS}}]
}

proc ::stage1e::production_vivado_runner_v2::_raise {code message} {
    return -code error -errorcode [list STAGE1E EXECUTION RUNNER_V2 $code] $message
}

proc ::stage1e::production_vivado_runner_v2::_canonical_path {path} {
    return [string map {\\ /} [file normalize $path]]
}

proc ::stage1e::production_vivado_runner_v2::_require_file {path label} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise INPUT_MISSING "$label is missing: $path"
    }
    return $path
}

proc ::stage1e::production_vivado_runner_v2::_require_command {name} {
    if {[string match {::*} $name]} {
        set global_name $name
    } else {
        set global_name "::$name"
    }

    if {![llength [info commands $global_name]]} {
        _raise VIVADO_COMMAND_UNAVAILABLE \
            "Vivado command is unavailable: $global_name"
    }

    return $global_name
}

proc ::stage1e::production_vivado_runner_v2::_require_unique_object {objects label} {
    if {[llength $objects] != 1} {
        _raise OBJECT_IDENTITY "$label must resolve to exactly one object."
    }
    return [lindex $objects 0]
}

proc ::stage1e::production_vivado_runner_v2::_require_bd_cell {name} {
    return [_require_unique_object [get_bd_cells -quiet $name] "BD cell $name"]
}

proc ::stage1e::production_vivado_runner_v2::_require_bd_pin {path} {
    return [_require_unique_object [get_bd_pins -quiet $path] "BD pin $path"]
}

proc ::stage1e::production_vivado_runner_v2::_require_bd_intf_pin {path} {
    return [_require_unique_object [get_bd_intf_pins -quiet $path] "BD interface pin $path"]
}

proc ::stage1e::production_vivado_runner_v2::_require_ipdef_exact {vlnv} {
    set definition [_require_unique_object [get_ipdefs -all -quiet $vlnv] "IP definition $vlnv"]
    if {[get_property VLNV $definition] ne $vlnv} {
        _raise IP_CATALOG "Resolved IP definition differs from exact VLNV $vlnv."
    }
    return $definition
}

proc ::stage1e::production_vivado_runner_v2::_numeric_equal {actual expected} {
    if {![catch {expr {wide($actual)}} left] &&
        ![catch {expr {wide($expected)}} right]} {
        return [expr {$left == $right}]
    }
    return [expr {$actual eq $expected}]
}

proc ::stage1e::production_vivado_runner_v2::_assert_property {object property expected label} {
    set actual [get_property $property $object]
    if {![_numeric_equal $actual $expected]} {
        _raise TOPOLOGY_PROPERTY "$label $property mismatch: actual=$actual expected=$expected"
    }
    return $actual
}

proc ::stage1e::production_vivado_runner_v2::_object_path {object} {
    return [string trimleft [string map {\\ /} $object] /]
}

proc ::stage1e::production_vivado_runner_v2::_scalar_net_for_pin {path} {
    set pin [_require_bd_pin $path]
    return [_require_unique_object [get_bd_nets -quiet -of_objects $pin] "Scalar net for $path"]
}

proc ::stage1e::production_vivado_runner_v2::_interface_net_for_pin {path} {
    set pin [_require_bd_intf_pin $path]
    return [_require_unique_object [get_bd_intf_nets -quiet -of_objects $pin] "Interface net for $path"]
}

proc ::stage1e::production_vivado_runner_v2::_assert_exact_scalar_net {paths label} {
    set expected_net [_scalar_net_for_pin [lindex $paths 0]]
    foreach path [lrange $paths 1 end] {
        if {[_scalar_net_for_pin $path] ne $expected_net} {
            _raise TOPOLOGY_CONNECTION "$label does not share one scalar net."
        }
    }
    set actual {}
    foreach pin [get_bd_pins -quiet -of_objects $expected_net] {
        lappend actual [_object_path $pin]
    }
    if {[lsort -dictionary $actual] ne [lsort -dictionary $paths]} {
        _raise TOPOLOGY_CONNECTION "$label scalar-net membership is not exact."
    }
    return $expected_net
}

proc ::stage1e::production_vivado_runner_v2::_assert_same_scalar_net {paths label} {
    set expected_net [_scalar_net_for_pin [lindex $paths 0]]
    foreach path [lrange $paths 1 end] {
        if {[_scalar_net_for_pin $path] ne $expected_net} {
            _raise TOPOLOGY_CONNECTION "$label does not share one scalar net."
        }
    }
    return $expected_net
}

proc ::stage1e::production_vivado_runner_v2::_assert_exact_interface_net {paths label} {
    set expected_net [_interface_net_for_pin [lindex $paths 0]]
    foreach path [lrange $paths 1 end] {
        if {[_interface_net_for_pin $path] ne $expected_net} {
            _raise TOPOLOGY_CONNECTION "$label does not share one interface net."
        }
    }
    set actual {}
    foreach pin [get_bd_intf_pins -quiet -of_objects $expected_net] {
        lappend actual [_object_path $pin]
    }
    if {[lsort -dictionary $actual] ne [lsort -dictionary $paths]} {
        _raise TOPOLOGY_CONNECTION "$label interface-net membership is not exact."
    }
    return $expected_net
}

proc ::stage1e::production_vivado_runner_v2::_connect_pin_preserving_net {source_path sink_path} {
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

proc ::stage1e::production_vivado_runner_v2::_file_identity {path} {
    _require_file $path {Identity source}
    return [::stage1e::canonical_json_v1::digest_file $path]
}

proc ::stage1e::production_vivado_runner_v2::_file_size {path} {
    _require_file $path {Sized file}
    return [file size $path]
}

proc ::stage1e::production_vivado_runner_v2::topology_contract {
    {profile SAFE_INERT}
} {
    if {$profile ni {SAFE_INERT READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS}} {
        _raise IMPLEMENTATION_PROFILE "Unsupported topology profile: $profile"
    }
    set probes {}
    set index 0
    foreach spec [_probe_specs $profile] {
        set source [lindex $spec 0]
        set width [lindex $spec 1]
        lappend probes [dict create index $index source $source width $width]
        incr index
    }
    set platform_ports [dict create \
        DDR_addr 15 \
        DDR_ba 3 \
        DDR_cas_n 1 \
        DDR_ck_n 1 \
        DDR_ck_p 1 \
        DDR_cke 1 \
        DDR_cs_n 1 \
        DDR_dm 4 \
        DDR_dq 32 \
        DDR_dqs_n 4 \
        DDR_dqs_p 4 \
        DDR_odt 1 \
        DDR_ras_n 1 \
        DDR_reset_n 1 \
        DDR_we_n 1 \
        FIXED_IO_ddr_vrn 1 \
        FIXED_IO_ddr_vrp 1 \
        FIXED_IO_mio 54 \
        FIXED_IO_ps_clk 1 \
        FIXED_IO_ps_porb 1 \
        FIXED_IO_ps_srstb 1]
    set common [dict create \
        implementation_profile $profile \
        target [dict create board PYNQ-Z2 part xc7z020clg400-1 board_part tul.com.tw:pynq-z2:part0:1.0] \
        bd_name protection_system \
        project_top protection_system_wrapper \
        wrapper_exists 1 \
        smartconnect [dict create NUM_SI 1 NUM_MI 2] \
        addresses [dict create \
            protection [dict create offset 0x43C00000 range 0x00001000] \
            axi_gpio [dict create offset 0x41200000 range 0x00010000]] \
        system_ila [dict create \
            present 1 \
            monitor_source protection_ip_axi_lite_0/S_AXI \
            properties [dict create C_MON_TYPE MIX C_PROBE_WIDTH_PROPAGATION MANUAL C_NUM_MONITOR_SLOTS 1 C_SLOT_0_INTF_TYPE xilinx.com:interface:aximm_rtl:1.0 C_SLOT_0_AXI_PROTOCOL AXI4LITE C_NUM_OF_PROBES [llength $probes] C_DATA_DEPTH 4096] \
            probes $probes] \
        external_interfaces {DDR FIXED_IO} \
        platform_external_scalar_ports $platform_ports \
        custom_external_pl_ports {} \
        pwm_out_visibility SYSTEM_ILA_INTERNAL_ONLY]

    if {$profile eq {SAFE_INERT}} {
        return [dict merge $common [dict create \
        cell_inventory {
            axi_gpio_stage1d_0 dcm_locked_const proc_sys_reset_0
            processing_system7_0 protection_ip_axi_lite_0 sample_valid_const
            smartconnect_0 system_ila_stage2b_0 xlslice_stage1d_ch1
            xlslice_stage1d_ch2
        } \
        cell_vlnvs [dict create \
            axi_gpio_stage1d_0 xilinx.com:ip:axi_gpio:2.0 \
            dcm_locked_const xilinx.com:ip:xlconstant:1.1 \
            proc_sys_reset_0 xilinx.com:ip:proc_sys_reset:5.0 \
            processing_system7_0 xilinx.com:ip:processing_system7:5.5 \
            protection_ip_axi_lite_0 zsr112.local:protection:protection_ip_axi_lite:0.3 \
            sample_valid_const xilinx.com:ip:xlconstant:1.1 \
            smartconnect_0 xilinx.com:ip:smartconnect:1.0 \
            system_ila_stage2b_0 xilinx.com:ip:system_ila:1.1 \
            xlslice_stage1d_ch1 xilinx.com:ip:xlslice:1.0 \
            xlslice_stage1d_ch2 xilinx.com:ip:xlslice:1.0] \
        axi_gpio [dict create C_IS_DUAL 0 C_GPIO_WIDTH 24 C_ALL_OUTPUTS 1 C_INTERRUPT_PRESENT 0 C_DOUT_DEFAULT 0x00400400] \
        slices [dict create \
            xlslice_stage1d_ch1 [dict create DIN_WIDTH 24 DIN_FROM 11 DIN_TO 0 DOUT_WIDTH 12] \
            xlslice_stage1d_ch2 [dict create DIN_WIDTH 24 DIN_FROM 23 DIN_TO 12 DOUT_WIDTH 12]] \
        adc_source_clock [dict create driver processing_system7_0/FCLK_CLK0 sink protection_ip_axi_lite_0/adc_src_clk current_clock_alias ACLK future_distinct_clock_supported 1] \
        adc_sample_sources [dict create adc_sample_ch1 xlslice_stage1d_ch1/Dout adc_sample_ch2 xlslice_stage1d_ch2/Dout] \
        controlled_stimulus [dict create profile SAFE_INERT_EXPLICIT profile_class SAFE_INERT production_authority 1 demo_test_only 0 valid_value 0 functional_adc_stimulus 0 valid_source_exists 1 ready_consumed 0 no_overwrite_when_ready_low 0 transaction_pulse_bounded 0 valid_driver sample_valid_const/dout valid_sink protection_ip_axi_lite_0/adc_sample_valid ready_source protection_ip_axi_lite_0/adc_sample_ready ready_probe system_ila_stage2b_0/probe11 source_acceptance_claimed 0 fault_stimulus_claimed 0] \
        debug_ready_observation [dict create ready_observation_clock_domain ACLK adc_src_clock_domain FCLK_CLK0 destination_clock_domain FCLK_CLK0 clocks_identical_in_current_profile 1 acceptance_evidence_scope CURRENT_IDENTICAL_CLOCKS_ONLY distinct_clock_debug_policy SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION direct_async_ready_observation_as_cdc_proof 0] \
        source_system_ila [dict create present 0]]]
    }

    set source_probes {}
    foreach {index source width} {
        0 stage2i_b2_ready_aware_stimulus_0/sample_valid 1
        1 protection_ip_axi_lite_0/adc_sample_ready 1
        2 stage2i_b2_ready_aware_stimulus_0/sample_ch1 12
        3 stage2i_b2_ready_aware_stimulus_0/sample_ch2 12
        4 stage2i_b2_ready_aware_stimulus_0/producer_active 1
        5 stage2i_b2_ready_aware_stimulus_0/producer_remaining 7
        6 stage2i_b2_ready_aware_stimulus_0/producer_accept 1
        7 stage2i_b2_ready_aware_stimulus_0/command_pending_src 1
    } {
        lappend source_probes \
            [dict create index $index source $source width $width]
    }
    return [dict merge $common [dict create \
        cell_inventory {
            axi_gpio_stage1d_0 dcm_locked_const proc_sys_reset_0
            proc_sys_reset_stage2i_b2_src processing_system7_0
            protection_ip_axi_lite_0 smartconnect_0
            stage2i_b2_ready_aware_stimulus_0 system_ila_stage2b_0
            system_ila_stage2i_b2_source_0
        } \
        cell_vlnvs [dict create \
            axi_gpio_stage1d_0 xilinx.com:ip:axi_gpio:2.0 \
            dcm_locked_const xilinx.com:ip:xlconstant:1.1 \
            proc_sys_reset_0 xilinx.com:ip:proc_sys_reset:5.0 \
            proc_sys_reset_stage2i_b2_src xilinx.com:ip:proc_sys_reset:5.0 \
            processing_system7_0 xilinx.com:ip:processing_system7:5.5 \
            protection_ip_axi_lite_0 zsr112.local:protection:protection_ip_axi_lite:0.3 \
            smartconnect_0 xilinx.com:ip:smartconnect:1.0 \
            system_ila_stage2b_0 xilinx.com:ip:system_ila:1.1 \
            system_ila_stage2i_b2_source_0 xilinx.com:ip:system_ila:1.1] \
        axi_gpio [dict create C_IS_DUAL 1 C_GPIO_WIDTH 32 C_GPIO2_WIDTH 32 C_ALL_OUTPUTS 1 C_ALL_INPUTS_2 1 C_INTERRUPT_PRESENT 0 C_DOUT_DEFAULT 0x00000000] \
        slices [dict create] \
        adc_source_clock [dict create driver processing_system7_0/FCLK_CLK1 sink protection_ip_axi_lite_0/adc_src_clk current_clock_alias DISTINCT_FCLK1 frequency_mhz 125] \
        adc_sample_sources [dict create adc_sample_ch1 stage2i_b2_ready_aware_stimulus_0/sample_ch1 adc_sample_ch2 stage2i_b2_ready_aware_stimulus_0/sample_ch2] \
        controlled_stimulus [dict create profile READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS profile_class BOARD_TEST production_authority 0 demo_test_only 1 valid_value DYNAMIC functional_adc_stimulus 1 valid_source_exists 1 ready_consumed 1 no_overwrite_when_ready_low 1 transaction_pulse_bounded 1 maximum_burst_count 127 command_cdc BUNDLED_DATA_REQUEST_ACK valid_driver stage2i_b2_ready_aware_stimulus_0/sample_valid valid_sink protection_ip_axi_lite_0/adc_sample_valid ready_source protection_ip_axi_lite_0/adc_sample_ready ready_probe system_ila_stage2i_b2_source_0/probe1 source_acceptance_claimed 1 fault_stimulus_claimed 1] \
        debug_ready_observation [dict create ready_observation_clock_domain FCLK_CLK1 adc_src_clock_domain FCLK_CLK1 destination_clock_domain FCLK_CLK0 clocks_identical_in_current_profile 0 acceptance_evidence_scope SOURCE_DOMAIN_CYCLE_ACCURATE distinct_clock_debug_policy SOURCE_DOMAIN_ILA direct_async_ready_observation_as_cdc_proof 0] \
        source_system_ila [dict create present 1 cell system_ila_stage2i_b2_source_0 properties [dict create C_MON_TYPE NATIVE C_PROBE_WIDTH_PROPAGATION MANUAL C_NUM_MONITOR_SLOTS 0 C_NUM_OF_PROBES 8 C_DATA_DEPTH 4096] probes $source_probes]]]
}

proc ::stage1e::production_vivado_runner_v2::validate_topology_fixture {observed} {
    set expected [topology_contract [dict get $observed implementation_profile]]
    ::stage1e::vivado_runtime_contract_v2::require_exact_fields $observed [dict keys $expected] {Stage 1E topology fixture}
    set inventory [dict get $observed cell_inventory]
    if {[llength $inventory] != [llength [lsort -unique $inventory]]} {
        _raise TOPOLOGY_FIXTURE {Topology fixture cell inventory contains a duplicate.}
    }
    set probes [dict get $observed system_ila probes]
    set indices {}
    foreach probe $probes { lappend indices [dict get $probe index] }
    if {[llength $indices] != [llength [lsort -unique $indices]]} {
        _raise TOPOLOGY_FIXTURE {Topology fixture probe inventory contains a duplicate.}
    }
    if {[_is_ready_aware_profile \
        [dict get $observed implementation_profile]]} {
        set source_indices {}
        foreach probe [dict get $observed source_system_ila probes] {
            lappend source_indices [dict get $probe index]
        }
        if {[llength $source_indices] !=
            [llength [lsort -unique $source_indices]]} {
            _raise TOPOLOGY_FIXTURE \
                {B2 source ILA probe inventory contains a duplicate.}
        }
    }
    if {$observed ne $expected} {
        _raise TOPOLOGY_FIXTURE {Stage 1E topology differs from the exact controlled integration contract.}
    }
    return 1
}

proc ::stage1e::production_vivado_runner_v2::_validate_context {context} {
    variable context_fields
    ::stage1e::vivado_runtime_contract_v2::require_exact_fields $context $context_fields {Named Vivado execution context}
    ::stage1e::vivado_runtime_contract_v2::require_equal stage1e-vivado-execution-context-v1 [dict get $context context_schema_version] {Execution context schema}
    foreach field {execution_id request_identity source_commit source_tree execution_contract_identity process_identity project_identity design_identity vivado_version vivado_build} {
        if {[dict get $context $field] eq {}} {
            _raise CONTEXT_FIELD_EMPTY "Execution context field is empty: $field"
        }
    }
    foreach field {request_identity execution_contract_identity} {
        if {![regexp {^[0-9a-f]{64}$} [dict get $context $field]]} {
            _raise CONTEXT_IDENTITY "Execution context SHA-256 identity is invalid: $field"
        }
    }
    foreach field {source_commit source_tree} {
        if {![regexp {^[0-9a-f]{40}$} [dict get $context $field]]} {
            _raise CONTEXT_IDENTITY "Execution context Git identity is invalid: $field"
        }
    }
    if {[dict get $context run_kind] eq {FORMAL}} {
        _raise FORMAL_CURRENT_RUN_FINDING_COMPARATOR_NOT_IMPLEMENTED FORMAL_CURRENT_RUN_FINDING_COMPARATOR_NOT_IMPLEMENTED
    }
    if {[dict get $context run_kind] ne {ENGINEERING}} {
        _raise RUN_KIND {Unsupported run kind.}
    }
    if {[dict get $context build_target] ni {IMPLEMENTATION ARTIFACTS}} {
        _raise BUILD_TARGET {Unsupported build target.}
    }
    if {[dict get $context implementation_profile] ni {
        SAFE_INERT READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
    }} {
        _raise IMPLEMENTATION_PROFILE {Unsupported implementation profile.}
    }
    if {[dict get $context project_retention] ni {RETAIN REMOVE}} {
        _raise PROJECT_RETENTION {Unsupported project retention setting.}
    }
    foreach field {repository_root workspace_path project_path output_path report_root artifact_root result_path phase_journal_path} {
        if {[file pathtype [dict get $context $field]] ne {absolute}} {
            _raise CONTEXT_PATH "Execution context path is not absolute: $field"
        }
    }
    return $context
}

proc ::stage1e::production_vivado_runner_v2::_assert_execution_contract_identity {context} {
    set path [file join [dict get $context repository_root] fpga vivado build config stage1e_execution_contract_v1.json]
    set bytes [::stage1e::canonical_json_v1::read_file_bytes $path]
    if {[::stage1e::canonical_json_v1::digest_bytes $bytes] ne [dict get $context execution_contract_identity]} {
        _raise EXECUTION_CONTRACT_IDENTITY {Execution contract differs from the sealed machine runtime owner.}
    }
    ::stage1e::canonical_json_v1::parse_bytes $bytes
    return $path
}

proc ::stage1e::production_vivado_runner_v2::_tsv_field {value} {
    return [string map [list \\ \\\\ \t \\t \r \\r \n \\n] $value]
}

proc ::stage1e::production_vivado_runner_v2::initialize_phase_journal {context} {
    variable journal_ordinal
    set path [dict get $context phase_journal_path]
    if {![file exists [file dirname $path]] || [file exists $path]} {
        _raise PHASE_JOURNAL_PATH {Runner phase journal path is not fresh and writable.}
    }
    set channel [open $path {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel "ordinal\tutc_timestamp\tevent\tphase\texecution_id\trun_identity\tSTATUS\tPROGRESS\tCURRENT_STEP\toutput_identity\tdetail"
    close $channel
    set journal_ordinal 0
    return $path
}

proc ::stage1e::production_vivado_runner_v2::append_phase_journal {
    context event phase run_identity status progress current_step output_identity detail
} {
    variable journal_ordinal
    if {$event ni {ATTEMPT COMPLETED FAILED}} {
        _raise PHASE_JOURNAL_EVENT "Unsupported phase-journal event: $event"
    }
    incr journal_ordinal
    set timestamp [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]
    set values [list $journal_ordinal $timestamp $event $phase [dict get $context execution_id] $run_identity $status $progress $current_step $output_identity $detail]
    set escaped {}
    foreach value $values { lappend escaped [_tsv_field $value] }
    set channel [open [dict get $context phase_journal_path] a]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel [join $escaped \t]
    close $channel
    return $journal_ordinal
}

proc ::stage1e::production_vivado_runner_v2::_phase_journal_record {context} {
    set path [dict get $context phase_journal_path]
    return [dict create path [_canonical_path $path] bytes [_file_size $path] sha256 [_file_identity $path]]
}

proc ::stage1e::production_vivado_runner_v2::phase_order {} {
    variable implementation_phases
    return $implementation_phases
}

proc ::stage1e::production_vivado_runner_v2::new_phase_state {} {
    return [dict create schema_version stage1e-project-mode-phase-state-v2 completed_phases {} phase_attempts {} terminal_state OPEN first_failure NONE]
}

proc ::stage1e::production_vivado_runner_v2::_next_implementation_phase {state} {
    set ordinal [llength [dict get $state completed_phases]]
    if {$ordinal >= [llength [phase_order]]} { return NONE }
    return [lindex [phase_order] $ordinal]
}

proc ::stage1e::production_vivado_runner_v2::_start_implementation_phase {state phase} {
    ::stage1e::vivado_runtime_contract_v2::require_exact_fields $state {schema_version completed_phases phase_attempts terminal_state first_failure} {Project Mode phase state}
    if {[dict get $state terminal_state] ne {OPEN} || [_next_implementation_phase $state] ne $phase ||
        [lsearch -exact [dict get $state phase_attempts] $phase] >= 0} {
        _raise PHASE_ORDER {Project Mode phase order or exact-once state differs.}
    }
    dict lappend state phase_attempts $phase
    return $state
}

proc ::stage1e::production_vivado_runner_v2::_finish_implementation_phase {state observation} {
    if {[dict get $observation action] ne {PROCEED}} {
        dict set state terminal_state BLOCKED
        dict set state first_failure [dict get $observation reason]
        return $state
    }
    dict lappend state completed_phases [dict get $observation phase]
    if {[llength [dict get $state completed_phases]] == [llength [phase_order]]} {
        dict set state terminal_state ROUTED
    }
    return $state
}

proc ::stage1e::production_vivado_runner_v2::run_fixture {state properties snapshot} {
    set phase [dict get $snapshot phase]
    set state [_start_implementation_phase $state $phase]
    set observation [::stage1e::production_vivado_observer_v2::observe_fixture $properties $snapshot]
    set state [_finish_implementation_phase $state $observation]
    return [dict create phase_state $state observation $observation]
}

proc ::stage1e::production_vivado_runner_v2::_assert_tool_identity {context} {
    _require_command version
    set version_text [version]
    if {[string first [dict get $context vivado_version] $version_text] < 0 ||
        [string first [dict get $context vivado_build] $version_text] < 0} {
        _raise VIVADO_VERSION "Unexpected Vivado identity: $version_text"
    }
    return $version_text
}

proc ::stage1e::production_vivado_runner_v2::_rtl_files {context} {
    set rtl [file join [dict get $context repository_root] rtl]
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
    foreach file $files { _require_file $file {Packaged IP RTL source} }
    return $files
}

proc ::stage1e::production_vivado_runner_v2::_constraint_files {context} {
    set files [list \
        [file join [dict get $context repository_root] fpga vivado \
            constraints stage2d_async_adc_atomic_cdc.xdc] \
        [file join [dict get $context repository_root] fpga vivado \
            constraints stage2e_transaction_observability_cdc.xdc] \
    ]
    foreach file $files { _require_file $file {Packaged IP constraint source} }
    return $files
}

proc ::stage1e::production_vivado_runner_v2::_ensure_bus_interface {core name bus abstraction mode} {
    set value [ipx::get_bus_interfaces $name -of_objects $core -quiet]
    if {[llength $value] == 0} { set value [ipx::add_bus_interface $name $core] }
    set_property bus_type_vlnv $bus $value
    set_property abstraction_type_vlnv $abstraction $value
    set_property interface_mode $mode $value
    return $value
}

proc ::stage1e::production_vivado_runner_v2::_ensure_port_map {busif logical physical} {
    set value [ipx::get_port_maps $logical -of_objects $busif -quiet]
    if {[llength $value] == 0} { set value [ipx::add_port_map $logical $busif] }
    set_property physical_name $physical $value
}

proc ::stage1e::production_vivado_runner_v2::_ensure_bus_parameter {busif name value} {
    set parameter [ipx::get_bus_parameters $name -of_objects $busif -quiet]
    if {[llength $parameter] == 0} { set parameter [ipx::add_bus_parameter $name $busif] }
    set_property value $value $parameter
}

proc ::stage1e::production_vivado_runner_v2::_stage_packaged_generated_header {
    core ip_root source relative_path file_type
} {
    _require_file $source {Generated packaged header source}
    set destination [file join $ip_root {*}[split $relative_path /]]
    file mkdir [file dirname $destination]
    file copy -force -- $source $destination

    set source_name [_canonical_path $source]
    set flat_name "src/[file tail $source]"
    foreach group_name {
        xilinx_anylanguagesynthesis
        xilinx_anylanguagebehavioralsimulation
    } {
        set group [_require_unique_object \
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
        set file [ipx::get_files $relative_path -of_objects $group -quiet]
        if {[llength $file] == 0} {
            set file [ipx::add_file $relative_path $group]
        } elseif {[llength $file] != 1} {
            _raise PACKAGED_HEADER \
                "Packaged generated header is not unique: $relative_path"
        }
        set_property type $file_type $file
        set_property is_include true $file
        set_property dependency {src} $group
        if {[get_property DEPENDENCY $group] ne {src} ||
            [file pathtype [get_property DEPENDENCY $group]] ne {relative}} {
            _raise PACKAGED_HEADER \
                "Packaged include dependency is not portable: $group_name"
        }
    }

    set flat_path [file join $ip_root src [file tail $source]]
    if {[file exists $flat_path] &&
        ![string equal -nocase [_canonical_path $flat_path] \
            [_canonical_path $destination]]} {
        file delete -force -- $flat_path
    }
    _require_file $destination {Nested packaged generated header}
    return $destination
}

proc ::stage1e::production_vivado_runner_v2::_stage_packaged_implementation_constraints {
    core constraint_files
} {
    set synthesis [_require_unique_object \
        [ipx::get_file_groups xilinx_anylanguagesynthesis \
            -of_objects $core -quiet] \
        {Packaged IP synthesis file group}]
    set implementation_groups [ipx::get_file_groups xilinx_implementation \
        -of_objects $core -quiet]
    if {[llength $implementation_groups] == 0} {
        set implementation [ipx::add_file_group xilinx_implementation \
            -type implementation $core]
    } else {
        set implementation [_require_unique_object $implementation_groups \
            {Packaged IP implementation file group}]
    }

    foreach source $constraint_files {
        set relative_path "src/[file tail $source]"
        set synthesis_files [ipx::get_files $relative_path \
            -of_objects $synthesis -quiet]
        if {[llength $synthesis_files] > 1} {
            _raise PACKAGED_CONSTRAINT \
                "Packaged constraint is duplicated in synthesis: $relative_path"
        }
        if {[llength $synthesis_files] == 1} {
            ipx::remove_file $relative_path $synthesis
        }

        set implementation_files [ipx::get_files $relative_path \
            -of_objects $implementation -quiet]
        if {[llength $implementation_files] == 0} {
            set implementation_file [ipx::add_file \
                $relative_path $implementation]
        } elseif {[llength $implementation_files] == 1} {
            set implementation_file [lindex $implementation_files 0]
        } else {
            _raise PACKAGED_CONSTRAINT \
                "Packaged constraint is duplicated in implementation: $relative_path"
        }
        set_property type xdc $implementation_file
        set_property processing_order late $implementation_file

        set occurrence_count 0
        set owning_groups {}
        foreach group [ipx::get_file_groups -of_objects $core] {
            set files [ipx::get_files $relative_path \
                -of_objects $group -quiet]
            incr occurrence_count [llength $files]
            if {[llength $files] != 0} {
                lappend owning_groups [get_property NAME $group]
            }
        }
        if {$occurrence_count != 1 ||
            $owning_groups ne {xilinx_implementation}} {
            _raise PACKAGED_CONSTRAINT \
                "Packaged constraint must occur exactly once and only in xilinx_implementation: $relative_path"
        }
    }
}

proc ::stage1e::production_vivado_runner_v2::package_protection_ip {context} {
    foreach command {create_project add_files current_project current_fileset update_compile_order close_project} { _require_command $command }
    set workspace [dict get $context workspace_path]
    set package_project [file join $workspace ip_packaging_project]
    set ip_repo [file join $workspace ip_repo]
    set ip_root [file join $ip_repo protection_ip_axi_lite]
    if {[file exists $package_project] || [file exists $ip_root]} {
        _raise FRESH_PACKAGE_PATH {Fresh packaging paths already exist.}
    }
    file mkdir $ip_repo
    ::create_project stage1e_ip_packaging $package_project \
        -part [dict get $context part]
    set_property board_part [dict get $context board_part] [current_project]
    set_property target_language Verilog [current_project]
    set rtl_files [_rtl_files $context]
    set constraint_files [_constraint_files $context]
    add_files -norecurse -fileset sources_1 $rtl_files
    add_files -norecurse -fileset constrs_1 $constraint_files
    set header [file join [dict get $context repository_root] rtl fault_defs.vh]
    set register_map_header [file join [dict get $context repository_root] rtl generated protection_register_map.vh]
    set profile_header [file join [dict get $context repository_root] rtl generated stage2f_adc_source_profile.svh]
    set register_map_ipxact [file join [dict get $context repository_root] fpga vivado generated protection_register_map_ipxact.tcl]
    _require_file $register_map_ipxact {Generated protection register-map IP-XACT metadata}
    source $register_map_ipxact
    set_property file_type {Verilog Header} [get_files [list $header]]
    set_property file_type {Verilog Header} [get_files [list $register_map_header]]
    set_property file_type {Verilog Header} [get_files [list $profile_header]]
    foreach constraint_file $constraint_files {
        set_property file_type XDC [get_files [list $constraint_file]]
        set_property USED_IN_SYNTHESIS false [get_files [list $constraint_file]]
        set_property USED_IN_IMPLEMENTATION true [get_files [list $constraint_file]]
        set_property PROCESSING_ORDER LATE [get_files [list $constraint_file]]
    }
    set_property include_dirs [list [file dirname $header]] [current_fileset]
    set_property top protection_ip_top_async_adc_axi_lite [current_fileset]
    update_compile_order -fileset sources_1
    ipx::package_project -root_dir $ip_root -vendor zsr112.local -library protection -taxonomy {/UserIP} -import_files -set_current true
    set core [ipx::current_core]
    set_property name protection_ip_axi_lite $core
    set_property version 0.3 $core
    set_property display_name {Current Protection AXI-Lite IP} $core
    set_property supported_families {zynq Production} $core
    _stage_packaged_implementation_constraints $core $constraint_files
    _stage_packaged_generated_header $core $ip_root $register_map_header \
        {src/generated/protection_register_map.vh} verilogSource
    _stage_packaged_generated_header $core $ip_root $profile_header \
        {src/generated/stage2f_adc_source_profile.svh} systemVerilogSource
    foreach {parameter_name minimum maximum} {
        DATA_WIDTH 1 1024
        ADC_FIFO_ADDR_WIDTH 2 16
        OBS_SEQUENCE_WIDTH 16 32
    } {
        set parameter [ipx::get_user_parameters $parameter_name -of_objects $core -quiet]
        if {[llength $parameter] != 1} {
            _raise PACKAGED_PARAMETER "Expected exactly one packaged user parameter: $parameter_name"
        }
        set_property value_validation_type range_long $parameter
        set_property value_validation_range_minimum $minimum $parameter
        set_property value_validation_range_maximum $maximum $parameter
    }
    set saxi [_ensure_bus_interface $core S_AXI xilinx.com:interface:aximm:1.0 xilinx.com:interface:aximm_rtl:1.0 slave]
    _ensure_bus_parameter $saxi PROTOCOL AXI4LITE
    _ensure_bus_parameter $saxi DATA_WIDTH 32
    _ensure_bus_parameter $saxi ADDR_WIDTH 8
    foreach {logical physical} {AWADDR S_AXI_AWADDR AWVALID S_AXI_AWVALID AWREADY S_AXI_AWREADY WDATA S_AXI_WDATA WSTRB S_AXI_WSTRB WVALID S_AXI_WVALID WREADY S_AXI_WREADY BRESP S_AXI_BRESP BVALID S_AXI_BVALID BREADY S_AXI_BREADY ARADDR S_AXI_ARADDR ARVALID S_AXI_ARVALID ARREADY S_AXI_ARREADY RDATA S_AXI_RDATA RRESP S_AXI_RRESP RVALID S_AXI_RVALID RREADY S_AXI_RREADY} {
        _ensure_port_map $saxi $logical $physical
    }
    set aclk [_ensure_bus_interface $core ACLK xilinx.com:signal:clock:1.0 xilinx.com:signal:clock_rtl:1.0 slave]
    _ensure_port_map $aclk CLK ACLK
    _ensure_bus_parameter $aclk ASSOCIATED_BUSIF S_AXI
    _ensure_bus_parameter $aclk ASSOCIATED_RESET ARESETN
    _ensure_bus_parameter $aclk FREQ_HZ 100000000
    set aresetn [_ensure_bus_interface $core ARESETN xilinx.com:signal:reset:1.0 xilinx.com:signal:reset_rtl:1.0 slave]
    _ensure_port_map $aresetn RST ARESETN
    _ensure_bus_parameter $aresetn POLARITY ACTIVE_LOW
    set adc_clk [_ensure_bus_interface $core adc_src_clk xilinx.com:signal:clock:1.0 xilinx.com:signal:clock_rtl:1.0 slave]
    _ensure_port_map $adc_clk CLK adc_src_clk
    _ensure_bus_parameter $adc_clk ASSOCIATED_RESET ARESETN
    set memory_map [ipx::get_memory_maps S_AXI -of_objects $core -quiet]
    if {[llength $memory_map] == 0} { set memory_map [ipx::add_memory_map S_AXI $core] }
    set_property slave_memory_map_ref S_AXI $saxi
    set block [ipx::get_address_blocks reg0 -of_objects $memory_map -quiet]
    if {[llength $block] == 0} { set block [ipx::add_address_block reg0 $memory_map] }
    set_property base_address 0 $block
    set_property range 0x1000 $block
    set_property width 32 $block
    set_property usage register $block
    set generated_register_count [protection_register_map_apply_ipxact $block]
    if {$generated_register_count != $::PROTECTION_REGISTER_MAP_REGISTER_COUNT} {
        _raise PACKAGED_REGISTER_MAP {Generated IP-XACT register count differs from its authority.}
    }
    ipx::create_xgui_files $core
    ipx::update_checksums $core
    ipx::check_integrity $core
    ipx::save_core $core
    if {[get_property VLNV $core] ne {zsr112.local:protection:protection_ip_axi_lite:0.3}} {
        _raise PACKAGED_IP_IDENTITY {Packaged protection IP VLNV differs.}
    }
    set component [file join $ip_root component.xml]
    _require_file $component {Packaged protection component}
    set component_identity [_file_identity $component]
    ::close_project
    return [dict create ip_repo $ip_repo component_path $component component_identity $component_identity]
}

# The native ::create_project {name directory args} command remains tool-owned.
proc ::stage1e::production_vivado_runner_v2::create_build_project {context package} {
    set project_path [dict get $context project_path]
    set project_dir [file dirname $project_path]
    set project_name [file rootname [file tail $project_path]]
    if {[file exists $project_dir] && [llength [glob -nocomplain -directory $project_dir *]] != 0} {
        _raise FRESH_PROJECT_PATH {Fresh project directory is not empty.}
    }
    ::create_project $project_name $project_dir \
        -part [dict get $context part]
    set_property board_part [dict get $context board_part] [current_project]
    set_property target_language Verilog [current_project]
    set_property IP_REPO_PATHS [list [dict get $package ip_repo]] [current_project]
    update_ip_catalog
    foreach vlnv {
        xilinx.com:ip:processing_system7:5.5
        xilinx.com:ip:proc_sys_reset:5.0
        xilinx.com:ip:smartconnect:1.0
        xilinx.com:ip:xlconstant:1.1
        xilinx.com:ip:system_ila:1.1
        xilinx.com:ip:axi_gpio:2.0
        xilinx.com:ip:xlslice:1.0
        zsr112.local:protection:protection_ip_axi_lite:0.3
    } { _require_ipdef_exact $vlnv }
    if {[_is_ready_aware_profile \
        [dict get $context implementation_profile]]} {
        set b2_source [file join [dict get $context repository_root] fpga \
            vivado test_profile stage2i_b2_ready_aware_stimulus.v]
        set b2_constraint [file join [dict get $context repository_root] fpga \
            vivado constraints stage2i_b2_ready_aware_stimulus_cdc.xdc]
        _require_file $b2_source {B2 ready-aware stimulus source}
        _require_file $b2_constraint {B2 ready-aware stimulus CDC constraint}
        add_files -norecurse -fileset sources_1 [list $b2_source]
        add_files -norecurse -fileset constrs_1 [list $b2_constraint]
        set_property file_type Verilog [get_files [list $b2_source]]
        set_property file_type XDC [get_files [list $b2_constraint]]
        set_property USED_IN_SYNTHESIS false [get_files [list $b2_constraint]]
        set_property USED_IN_IMPLEMENTATION true [get_files [list $b2_constraint]]
        set_property PROCESSING_ORDER LATE [get_files [list $b2_constraint]]
        update_compile_order -fileset sources_1
    }
    if {[_canonical_path [get_property DIRECTORY [current_project]]] ne [_canonical_path $project_dir] ||
        [get_property PART [current_project]] ne [dict get $context part] ||
        [get_property BOARD_PART [current_project]] ne [dict get $context board_part]} {
        _raise PROJECT_IDENTITY {Created project identity differs from the execution context.}
    }
    return [dict create project_path $project_path project_dir $project_dir project_name $project_name bd_name protection_system]
}

proc ::stage1e::production_vivado_runner_v2::create_base_bd {context project} {
    set bd_name [dict get $project bd_name]
    set profile [dict get $context implementation_profile]
    if {[llength [get_bd_designs -quiet $bd_name]] != 0} {
        _raise BD_EXISTS {Block design already exists.}
    }
    create_bd_design $bd_name
    set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
    set reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]
    set smart [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0]
    set protection [create_bd_cell -type ip -vlnv zsr112.local:protection:protection_ip_axi_lite:0.3 protection_ip_axi_lite_0]
    set sample [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 sample_valid_const]
    set ch1 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 i_ch1_const]
    set ch2 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 i_ch2_const]
    set locked [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 dcm_locked_const]
    if {$profile eq {READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS}} {
        set source_reset [create_bd_cell -type ip \
            -vlnv xilinx.com:ip:proc_sys_reset:5.0 \
            proc_sys_reset_stage2i_b2_src]
    }
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} [get_bd_cells processing_system7_0]
    set ps_properties [list CONFIG.PCW_USE_M_AXI_GP0 {1} \
        CONFIG.PCW_EN_CLK0_PORT {1} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}]
    if {$profile eq {READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS}} {
        lappend ps_properties CONFIG.PCW_EN_CLK1_PORT {1} \
            CONFIG.PCW_EN_RST1_PORT {1} \
            CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {125}
    }
    set_property -dict $ps_properties $ps
    set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] $smart
    set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $sample
    set_property -dict [list CONFIG.CONST_WIDTH {12} CONFIG.CONST_VAL {1024}] $ch1
    set_property -dict [list CONFIG.CONST_WIDTH {12} CONFIG.CONST_VAL {1024}] $ch2
    set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $locked
    connect_bd_net [_require_bd_pin processing_system7_0/FCLK_CLK0] [_require_bd_pin processing_system7_0/M_AXI_GP0_ACLK] [_require_bd_pin smartconnect_0/aclk] [_require_bd_pin proc_sys_reset_0/slowest_sync_clk] [_require_bd_pin protection_ip_axi_lite_0/ACLK]
    if {$profile eq {SAFE_INERT}} {
        _connect_pin_preserving_net processing_system7_0/FCLK_CLK0 \
            protection_ip_axi_lite_0/adc_src_clk
    } else {
        connect_bd_net [_require_bd_pin processing_system7_0/FCLK_CLK1] \
            [_require_bd_pin protection_ip_axi_lite_0/adc_src_clk] \
            [_require_bd_pin proc_sys_reset_stage2i_b2_src/slowest_sync_clk]
        connect_bd_net [_require_bd_pin processing_system7_0/FCLK_RESET1_N] \
            [_require_bd_pin proc_sys_reset_stage2i_b2_src/ext_reset_in]
        _connect_pin_preserving_net dcm_locked_const/dout \
            proc_sys_reset_stage2i_b2_src/dcm_locked
    }
    connect_bd_net [_require_bd_pin processing_system7_0/FCLK_RESET0_N] [_require_bd_pin proc_sys_reset_0/ext_reset_in]
    connect_bd_net [_require_bd_pin dcm_locked_const/dout] [_require_bd_pin proc_sys_reset_0/dcm_locked]
    connect_bd_net [_require_bd_pin proc_sys_reset_0/peripheral_aresetn] [_require_bd_pin smartconnect_0/aresetn] [_require_bd_pin protection_ip_axi_lite_0/ARESETN]
    connect_bd_intf_net [_require_bd_intf_pin processing_system7_0/M_AXI_GP0] [_require_bd_intf_pin smartconnect_0/S00_AXI]
    connect_bd_intf_net [_require_bd_intf_pin smartconnect_0/M00_AXI] [_require_bd_intf_pin protection_ip_axi_lite_0/S_AXI]
    connect_bd_net [_require_bd_pin sample_valid_const/dout] [_require_bd_pin protection_ip_axi_lite_0/adc_sample_valid]
    connect_bd_net [_require_bd_pin i_ch1_const/dout] [_require_bd_pin protection_ip_axi_lite_0/adc_sample_ch1]
    connect_bd_net [_require_bd_pin i_ch2_const/dout] [_require_bd_pin protection_ip_axi_lite_0/adc_sample_ch2]
    assign_bd_address -target_address_space [get_bd_addr_spaces processing_system7_0/Data] -offset 0x43C00000 -range 0x00001000 [get_bd_addr_segs protection_ip_axi_lite_0/S_AXI/reg0]
    validate_bd_design
    save_bd_design
    set bd_file [_require_unique_object [get_files -quiet -all "*$bd_name.bd"] {Block design file}]
    dict set project bd_file $bd_file
    return $project
}

proc ::stage1e::production_vivado_runner_v2::_probe_specs {profile} {
    if {[_is_ready_aware_profile $profile]} {
        return {
            {protection_ip_axi_lite_0/ARESETN 1}
            {protection_ip_axi_lite_0/pwm_raw 1}
            {protection_ip_axi_lite_0/pwm_out 1}
            {protection_ip_axi_lite_0/fault_valid 1}
            {protection_ip_axi_lite_0/fault_latched 1}
            {protection_ip_axi_lite_0/fault_code 8}
            {protection_ip_axi_lite_0/fault_code_latched 8}
            {protection_ip_axi_lite_0/fsm_state 4}
        }
    }
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

proc ::stage1e::production_vivado_runner_v2::_source_probe_specs {} {
    return {
        {stage2i_b2_ready_aware_stimulus_0/sample_valid 1}
        {protection_ip_axi_lite_0/adc_sample_ready 1}
        {stage2i_b2_ready_aware_stimulus_0/sample_ch1 12}
        {stage2i_b2_ready_aware_stimulus_0/sample_ch2 12}
        {stage2i_b2_ready_aware_stimulus_0/producer_active 1}
        {stage2i_b2_ready_aware_stimulus_0/producer_remaining 7}
        {stage2i_b2_ready_aware_stimulus_0/producer_accept 1}
        {stage2i_b2_ready_aware_stimulus_0/command_pending_src 1}
    }
}

proc ::stage1e::production_vivado_runner_v2::_destination_probe_net_requires_exact_membership {
    profile index
} {
    if {$index == 0} {
        return 0
    }
    if {$profile eq {SAFE_INERT} && $index < 4} {
        return 0
    }
    return 1
}

proc ::stage1e::production_vivado_runner_v2::add_debug {context project} {
    set name system_ila_stage2b_0
    set profile [dict get $context implementation_profile]
    set probes [_probe_specs $profile]
    if {[llength [get_bd_cells -quiet $name]] != 0} {
        _raise DEBUG_EXISTS {System ILA already exists.}
    }
    set ila [create_bd_cell -type ip -vlnv xilinx.com:ip:system_ila:1.1 $name]
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
    _connect_pin_preserving_net processing_system7_0/FCLK_CLK0 ${name}/clk
    _connect_pin_preserving_net proc_sys_reset_0/peripheral_aresetn ${name}/resetn
    connect_bd_intf_net [_require_bd_intf_pin protection_ip_axi_lite_0/S_AXI] [_require_bd_intf_pin ${name}/SLOT_0_AXI]
    set index 0
    foreach spec $probes {
        _connect_pin_preserving_net [lindex $spec 0] ${name}/probe${index}
        incr index
    }
    validate_bd_design
    save_bd_design
    return $project
}

proc ::stage1e::production_vivado_runner_v2::_mapped_segment_for_cell {cell_name} {
    set space [_require_unique_object [get_bd_addr_spaces -quiet processing_system7_0/Data] {PS data address space}]
    set selected {}
    foreach segment [get_bd_addr_segs -quiet -of_objects $space] {
        if {[string first [string tolower $cell_name] [string tolower $segment]] >= 0} {
            lappend selected $segment
        }
    }
    return [_require_unique_object $selected "Mapped address segment for $cell_name"]
}

proc ::stage1e::production_vivado_runner_v2::_add_ready_aware_stimulus {
    context project
} {
    set valid_net [_scalar_net_for_pin protection_ip_axi_lite_0/adc_sample_valid]
    set ch1_net [_scalar_net_for_pin protection_ip_axi_lite_0/adc_sample_ch1]
    set ch2_net [_scalar_net_for_pin protection_ip_axi_lite_0/adc_sample_ch2]
    set gpio [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_stage1d_0]
    set producer [create_bd_cell -type module \
        -reference stage2i_b2_ready_aware_stimulus \
        stage2i_b2_ready_aware_stimulus_0]
    set source_ila [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:system_ila:1.1 \
        system_ila_stage2i_b2_source_0]

    set_property -dict [list \
        CONFIG.C_IS_DUAL {1} \
        CONFIG.C_GPIO_WIDTH {32} \
        CONFIG.C_GPIO2_WIDTH {32} \
        CONFIG.C_ALL_OUTPUTS {1} \
        CONFIG.C_ALL_INPUTS_2 {1} \
        CONFIG.C_INTERRUPT_PRESENT {0} \
        CONFIG.C_DOUT_DEFAULT {0x00000000}] $gpio
    set_property -dict [list \
        CONFIG.C_MON_TYPE {NATIVE} \
        CONFIG.C_PROBE_WIDTH_PROPAGATION {MANUAL} \
        CONFIG.C_NUM_MONITOR_SLOTS {0} \
        CONFIG.C_NUM_OF_PROBES {8} \
        CONFIG.C_DATA_DEPTH {4096}] $source_ila
    set index 0
    foreach spec [_source_probe_specs] {
        set_property CONFIG.C_PROBE${index}_WIDTH [lindex $spec 1] $source_ila
        incr index
    }

    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] \
        [_require_bd_cell smartconnect_0]
    connect_bd_intf_net [_require_bd_intf_pin smartconnect_0/M01_AXI] \
        [_require_bd_intf_pin axi_gpio_stage1d_0/S_AXI]
    _connect_pin_preserving_net processing_system7_0/FCLK_CLK0 \
        axi_gpio_stage1d_0/s_axi_aclk
    _connect_pin_preserving_net processing_system7_0/FCLK_CLK0 \
        stage2i_b2_ready_aware_stimulus_0/aclk
    _connect_pin_preserving_net proc_sys_reset_0/peripheral_aresetn \
        axi_gpio_stage1d_0/s_axi_aresetn
    _connect_pin_preserving_net proc_sys_reset_0/peripheral_aresetn \
        stage2i_b2_ready_aware_stimulus_0/aclk_aresetn
    _connect_pin_preserving_net processing_system7_0/FCLK_CLK1 \
        stage2i_b2_ready_aware_stimulus_0/adc_src_clk
    _connect_pin_preserving_net processing_system7_0/FCLK_CLK1 \
        system_ila_stage2i_b2_source_0/clk
    _connect_pin_preserving_net \
        proc_sys_reset_stage2i_b2_src/peripheral_aresetn \
        stage2i_b2_ready_aware_stimulus_0/adc_src_aresetn

    connect_bd_net [_require_bd_pin axi_gpio_stage1d_0/gpio_io_o] \
        [_require_bd_pin stage2i_b2_ready_aware_stimulus_0/control_word_aclk]
    connect_bd_net \
        [_require_bd_pin stage2i_b2_ready_aware_stimulus_0/status_word_aclk] \
        [_require_bd_pin axi_gpio_stage1d_0/gpio2_io_i]

    disconnect_bd_net $valid_net [_require_bd_pin sample_valid_const/dout]
    disconnect_bd_net $ch1_net [_require_bd_pin i_ch1_const/dout]
    disconnect_bd_net $ch2_net [_require_bd_pin i_ch2_const/dout]
    connect_bd_net -net $valid_net \
        [_require_bd_pin stage2i_b2_ready_aware_stimulus_0/sample_valid]
    connect_bd_net -net $ch1_net \
        [_require_bd_pin stage2i_b2_ready_aware_stimulus_0/sample_ch1]
    connect_bd_net -net $ch2_net \
        [_require_bd_pin stage2i_b2_ready_aware_stimulus_0/sample_ch2]
    _connect_pin_preserving_net protection_ip_axi_lite_0/adc_sample_ready \
        stage2i_b2_ready_aware_stimulus_0/sample_ready
    delete_bd_objs [_require_bd_cell sample_valid_const] \
        [_require_bd_cell i_ch1_const] [_require_bd_cell i_ch2_const]

    set index 0
    foreach spec [_source_probe_specs] {
        _connect_pin_preserving_net [lindex $spec 0] \
            system_ila_stage2i_b2_source_0/probe${index}
        incr index
    }
    assign_bd_address \
        -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
        -offset 0x41200000 -range 0x00010000 \
        [get_bd_addr_segs axi_gpio_stage1d_0/S_AXI/Reg]
    validate_bd_design
    save_bd_design
    return $project
}

proc ::stage1e::production_vivado_runner_v2::add_controlled_stimulus {context project} {
    if {[_is_ready_aware_profile \
        [dict get $context implementation_profile]]} {
        return [_add_ready_aware_stimulus $context $project]
    }
    set i_ch1_net [_scalar_net_for_pin protection_ip_axi_lite_0/adc_sample_ch1]
    set i_ch2_net [_scalar_net_for_pin protection_ip_axi_lite_0/adc_sample_ch2]
    set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_stage1d_0]
    set slice1 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_stage1d_ch1]
    set slice2 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_stage1d_ch2]
    set_property -dict [list CONFIG.C_IS_DUAL {0} CONFIG.C_GPIO_WIDTH {24} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_INTERRUPT_PRESENT {0} CONFIG.C_DOUT_DEFAULT {0x00400400}] $gpio
    set_property -dict [list CONFIG.DIN_WIDTH {24} CONFIG.DIN_FROM {11} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {12}] $slice1
    set_property -dict [list CONFIG.DIN_WIDTH {24} CONFIG.DIN_FROM {23} CONFIG.DIN_TO {12} CONFIG.DOUT_WIDTH {12}] $slice2
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] [_require_bd_cell smartconnect_0]
    connect_bd_intf_net [_require_bd_intf_pin smartconnect_0/M01_AXI] [_require_bd_intf_pin axi_gpio_stage1d_0/S_AXI]
    _connect_pin_preserving_net processing_system7_0/FCLK_CLK0 axi_gpio_stage1d_0/s_axi_aclk
    _connect_pin_preserving_net proc_sys_reset_0/peripheral_aresetn axi_gpio_stage1d_0/s_axi_aresetn
    connect_bd_net [_require_bd_pin axi_gpio_stage1d_0/gpio_io_o] [_require_bd_pin xlslice_stage1d_ch1/Din] [_require_bd_pin xlslice_stage1d_ch2/Din]
    disconnect_bd_net $i_ch1_net [_require_bd_pin i_ch1_const/dout]
    disconnect_bd_net $i_ch2_net [_require_bd_pin i_ch2_const/dout]
    connect_bd_net -net $i_ch1_net [_require_bd_pin xlslice_stage1d_ch1/Dout]
    connect_bd_net -net $i_ch2_net [_require_bd_pin xlslice_stage1d_ch2/Dout]
    delete_bd_objs [_require_bd_cell i_ch1_const] [_require_bd_cell i_ch2_const]
    set_property CONFIG.CONST_VAL {0} [_require_bd_cell sample_valid_const]
    assign_bd_address -target_address_space [get_bd_addr_spaces processing_system7_0/Data] -offset 0x41200000 -range 0x00010000 [get_bd_addr_segs axi_gpio_stage1d_0/S_AXI/Reg]
    validate_bd_design
    save_bd_design
    return $project
}

proc ::stage1e::production_vivado_runner_v2::generate_wrapper {context project} {
    set bd_file [dict get $project bd_file]
    generate_target all $bd_file
    set wrappers [make_wrapper -files $bd_file -top]
    set wrapper [_require_unique_object $wrappers {Generated wrapper}]
    _require_file $wrapper {Generated wrapper}
    add_files -norecurse [list $wrapper]
    set_property top protection_system_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    dict set project wrapper_path $wrapper
    return $project
}

proc ::stage1e::production_vivado_runner_v2::_assert_pin_width {path expected} {
    set pin [_require_bd_pin $path]
    set left [get_property LEFT $pin]
    set right [get_property RIGHT $pin]
    set width [expr {($left eq {} && $right eq {}) ? 1 : abs(int($left) - int($right)) + 1}]
    if {$width != $expected} {
        _raise TOPOLOGY_PROBE_WIDTH "Pin width mismatch for $path: actual=$width expected=$expected"
    }
}

proc ::stage1e::production_vivado_runner_v2::_bd_external_port_width {name} {
    set ports [get_bd_ports -quiet $name]
    if {[llength $ports] != 1} {
        _raise TOPOLOGY_PLATFORM_PORT_INVENTORY \
            "External platform port must resolve exactly once: $name"
    }
    set port [lindex $ports 0]
    if {[_object_path $port] ne $name} {
        _raise TOPOLOGY_PLATFORM_PORT_INVENTORY \
            "External platform port resolved to a different object: $name"
    }
    set left [get_property LEFT $port]
    set right [get_property RIGHT $port]
    if {$left eq {} && $right eq {}} {
        return 1
    }
    if {$left eq {} || $right eq {} ||
        ![string is integer -strict $left] ||
        ![string is integer -strict $right]} {
        _raise TOPOLOGY_PLATFORM_PORT_WIDTH \
            "External platform port has malformed bounds: $name LEFT='$left' RIGHT='$right'"
    }
    return [expr {abs(wide($left) - wide($right)) + 1}]
}

proc ::stage1e::production_vivado_runner_v2::_validate_platform_interface_inventory {observed expected} {
    set observed_sorted [lsort -dictionary -unique $observed]
    set expected_sorted [lsort -dictionary -unique $expected]
    if {[llength $observed] != [llength $observed_sorted] ||
        [llength $expected] != [llength $expected_sorted] ||
        $observed_sorted ne $expected_sorted} {
        _raise TOPOLOGY_PLATFORM_INTERFACE_INVENTORY \
            "External platform interface inventory mismatch: actual=$observed expected=$expected"
    }
    return 1
}

proc ::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory {observed expected expected_custom} {
    if {[llength $observed] % 2 != 0} {
        _raise TOPOLOGY_PLATFORM_PORT_INVENTORY \
            {External platform port inventory is malformed.}
    }
    set observed_names {}
    foreach {name width} $observed {
        lappend observed_names $name
    }
    if {[llength $observed_names] != [llength [lsort -dictionary -unique $observed_names]]} {
        _raise TOPOLOGY_PLATFORM_PORT_INVENTORY \
            {External platform port inventory contains a duplicate.}
    }

    set missing {}
    foreach name [dict keys $expected] {
        if {[lsearch -exact $observed_names $name] < 0} {
            lappend missing $name
        }
    }
    if {[llength $missing] != 0} {
        _raise TOPOLOGY_PLATFORM_PORT_INVENTORY \
            "External platform port inventory is missing required ports: $missing"
    }

    set custom {}
    foreach name $observed_names {
        if {![dict exists $expected $name]} {
            lappend custom $name
        }
    }
    if {[lsort -dictionary $custom] ne [lsort -dictionary $expected_custom]} {
        _raise TOPOLOGY_CUSTOM_EXTERNAL_PORT \
            "Custom external PL port inventory mismatch: actual=$custom expected=$expected_custom"
    }

    foreach {name expected_width} $expected {
        set position [lsearch -exact $observed_names $name]
        set actual_width [lindex $observed [expr {$position * 2 + 1}]]
        if {![string is integer -strict $actual_width] ||
            wide($actual_width) != wide($expected_width)} {
            _raise TOPOLOGY_PLATFORM_PORT_WIDTH \
                "External platform port width mismatch: $name actual=$actual_width expected=$expected_width"
        }
    }
    return 1
}

proc ::stage1e::production_vivado_runner_v2::_wrapper_module_header_inventory {path} {
    _require_file $path {Generated wrapper}
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set source [read $channel]
    close $channel

    if {![regexp -indices {(?m)^[ \t]*module[ \t\r\n]+([A-Za-z_][A-Za-z0-9_$]*)[ \t\r\n]*\(} \
        $source declaration_indices module_indices]} {
        _raise TOPOLOGY_WRAPPER {Generated wrapper module header does not exist.}
    }
    set module_name [string range $source [lindex $module_indices 0] [lindex $module_indices 1]]
    set header_start [expr {[lindex $declaration_indices 1] + 1}]
    set depth 1
    set header_end -1
    for {set index $header_start} {$index < [string length $source]} {incr index} {
        set character [string index $source $index]
        if {$character eq {(}} {
            incr depth
        } elseif {$character eq {)}} {
            incr depth -1
            if {$depth == 0} {
                set header_end [expr {$index - 1}]
                set terminator_index [expr {$index + 1}]
                break
            }
        }
    }
    if {$header_end < $header_start} {
        _raise TOPOLOGY_WRAPPER {Generated wrapper module header is malformed.}
    }
    while {$terminator_index < [string length $source] &&
        [string is space [string index $source $terminator_index]]} {
        incr terminator_index
    }
    if {$terminator_index >= [string length $source] ||
        [string index $source $terminator_index] ne {;}} {
        _raise TOPOLOGY_WRAPPER {Generated wrapper module header lacks its semicolon terminator.}
    }

    set ports {}
    set header [string range $source $header_start $header_end]
    foreach declaration [split $header ,] {
        set declaration [string trim $declaration]
        if {$declaration eq {} ||
            ![regexp {([A-Za-z_][A-Za-z0-9_$]*)[ \t\r\n]*$} $declaration _ name]} {
            _raise TOPOLOGY_WRAPPER \
                "Generated wrapper contains a malformed module-header port declaration: '$declaration'"
        }
        lappend ports $name
    }
    return [dict create module_name $module_name ports $ports]
}

proc ::stage1e::production_vivado_runner_v2::_validate_wrapper_port_inventory {observed expected_module expected_ports} {
    if {![dict exists $observed module_name] || ![dict exists $observed ports] ||
        [dict get $observed module_name] ne $expected_module} {
        _raise TOPOLOGY_WRAPPER \
            "Generated wrapper module is not $expected_module."
    }
    set ports [dict get $observed ports]
    set unique_ports [lsort -dictionary -unique $ports]
    set expected_names [lsort -dictionary [dict keys $expected_ports]]
    if {[llength $ports] != [llength $unique_ports] ||
        $unique_ports ne $expected_names} {
        _raise TOPOLOGY_WRAPPER_PORT_INVENTORY \
            "Generated wrapper top-level port inventory mismatch: actual=$ports expected=[dict keys $expected_ports]"
    }
    return 1
}

proc ::stage1e::production_vivado_runner_v2::_assert_mapped_address {cell offset range} {
    set segment [_mapped_segment_for_cell $cell]
    _assert_property $segment OFFSET $offset "$cell address"
    _assert_property $segment RANGE $range "$cell address"
    return $segment
}

proc ::stage1e::production_vivado_runner_v2::validate_final_topology {context project} {
    set profile [dict get $context implementation_profile]
    set expected [topology_contract $profile]
    if {[current_bd_design] ne {protection_system}} {
        _raise TOPOLOGY_BD {Current block design identity differs.}
    }
    if {[get_property PART [current_project]] ne [dict get $context part] ||
        [get_property BOARD_PART [current_project]] ne [dict get $context board_part]} {
        _raise TOPOLOGY_TARGET {Project target identity differs.}
    }
    set cells {}
    foreach cell [get_bd_cells -quiet] { lappend cells [_object_path $cell] }
    if {[lsort -dictionary $cells] ne [lsort -dictionary [dict get $expected cell_inventory]]} {
        _raise TOPOLOGY_CELL_INVENTORY {Final BD cell inventory is missing, duplicated, or additional.}
    }
    dict for {name vlnv} [dict get $expected cell_vlnvs] {
        _assert_property [_require_bd_cell $name] VLNV $vlnv "BD cell $name"
    }
    set smart [_require_bd_cell smartconnect_0]
    _assert_property $smart CONFIG.NUM_MI 2 SmartConnect
    _assert_property $smart CONFIG.NUM_SI 1 SmartConnect
    set gpio [_require_bd_cell axi_gpio_stage1d_0]
    dict for {property value} [dict get $expected axi_gpio] {
        _assert_property $gpio CONFIG.$property $value {AXI GPIO}
    }
    dict for {name properties} [dict get $expected slices] {
        set slice [_require_bd_cell $name]
        dict for {property value} $properties {
            _assert_property $slice CONFIG.$property $value "XL Slice $name"
        }
    }
    if {$profile eq {SAFE_INERT}} {
        set sample [_require_bd_cell sample_valid_const]
        _assert_property $sample CONFIG.CONST_WIDTH 1 sample_valid_const
        _assert_property $sample CONFIG.CONST_VAL 0 sample_valid_const
        if {[llength [get_bd_cells -quiet i_ch1_const]] != 0 ||
            [llength [get_bd_cells -quiet i_ch2_const]] != 0} {
            _raise TOPOLOGY_CURRENT_DRIVER \
                {Protection current inputs remain connected to constants.}
        }
    } else {
        foreach forbidden {
            sample_valid_const i_ch1_const i_ch2_const
            xlslice_stage1d_ch1 xlslice_stage1d_ch2
        } {
            if {[llength [get_bd_cells -quiet $forbidden]] != 0} {
                _raise TOPOLOGY_PROFILE_LEAKAGE \
                    "B2 retained a SAFE_INERT-only cell: $forbidden"
            }
        }
        _require_bd_cell stage2i_b2_ready_aware_stimulus_0
        _require_bd_cell proc_sys_reset_stage2i_b2_src
        _require_bd_cell system_ila_stage2i_b2_source_0
    }
    _assert_mapped_address protection_ip_axi_lite_0 0x43C00000 0x00001000
    _assert_mapped_address axi_gpio_stage1d_0 0x41200000 0x00010000
    set address_space [_require_unique_object [get_bd_addr_spaces -quiet processing_system7_0/Data] {PS data address space}]
    if {[llength [get_bd_addr_segs -quiet -of_objects $address_space]] != 2} {
        _raise TOPOLOGY_ADDRESS_INVENTORY {PS data address space must contain exactly two mapped segments.}
    }
    _assert_exact_interface_net {processing_system7_0/M_AXI_GP0 smartconnect_0/S00_AXI} {PS to SmartConnect}
    _assert_exact_interface_net {smartconnect_0/M00_AXI protection_ip_axi_lite_0/S_AXI system_ila_stage2b_0/SLOT_0_AXI} {Protection AXI and ILA monitor}
    _assert_exact_interface_net {smartconnect_0/M01_AXI axi_gpio_stage1d_0/S_AXI} {AXI GPIO master path}
    if {$profile eq {SAFE_INERT}} {
        _assert_exact_scalar_net {processing_system7_0/FCLK_CLK0 processing_system7_0/M_AXI_GP0_ACLK smartconnect_0/aclk proc_sys_reset_0/slowest_sync_clk protection_ip_axi_lite_0/ACLK protection_ip_axi_lite_0/adc_src_clk axi_gpio_stage1d_0/s_axi_aclk system_ila_stage2b_0/clk} {100 MHz clock}
        _assert_exact_scalar_net {processing_system7_0/FCLK_RESET0_N proc_sys_reset_0/ext_reset_in} {PS reset input}
        _assert_exact_scalar_net {dcm_locked_const/dout proc_sys_reset_0/dcm_locked} {Reset lock constant}
        _assert_exact_scalar_net {proc_sys_reset_0/peripheral_aresetn smartconnect_0/aresetn protection_ip_axi_lite_0/ARESETN axi_gpio_stage1d_0/s_axi_aresetn system_ila_stage2b_0/resetn system_ila_stage2b_0/probe0} {Peripheral active-low reset}
    } else {
        _assert_exact_scalar_net {processing_system7_0/FCLK_CLK0 processing_system7_0/M_AXI_GP0_ACLK smartconnect_0/aclk proc_sys_reset_0/slowest_sync_clk protection_ip_axi_lite_0/ACLK axi_gpio_stage1d_0/s_axi_aclk system_ila_stage2b_0/clk stage2i_b2_ready_aware_stimulus_0/aclk} {100 MHz clock}
        _assert_exact_scalar_net {processing_system7_0/FCLK_CLK1 protection_ip_axi_lite_0/adc_src_clk proc_sys_reset_stage2i_b2_src/slowest_sync_clk stage2i_b2_ready_aware_stimulus_0/adc_src_clk system_ila_stage2i_b2_source_0/clk} {125 MHz source clock}
        _assert_exact_scalar_net {processing_system7_0/FCLK_RESET0_N proc_sys_reset_0/ext_reset_in} {PS FCLK0 reset input}
        _assert_exact_scalar_net {processing_system7_0/FCLK_RESET1_N proc_sys_reset_stage2i_b2_src/ext_reset_in} {PS FCLK1 reset input}
        _assert_exact_scalar_net {dcm_locked_const/dout proc_sys_reset_0/dcm_locked proc_sys_reset_stage2i_b2_src/dcm_locked} {Reset lock constant}
        _assert_exact_scalar_net {proc_sys_reset_0/peripheral_aresetn smartconnect_0/aresetn protection_ip_axi_lite_0/ARESETN axi_gpio_stage1d_0/s_axi_aresetn system_ila_stage2b_0/resetn system_ila_stage2b_0/probe0 stage2i_b2_ready_aware_stimulus_0/aclk_aresetn} {ACLK active-low reset}
        _assert_exact_scalar_net {proc_sys_reset_stage2i_b2_src/peripheral_aresetn stage2i_b2_ready_aware_stimulus_0/adc_src_aresetn} {Source active-low reset}
        _assert_property [_require_bd_cell processing_system7_0] \
            CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100 {PS FCLK0}
        _assert_property [_require_bd_cell processing_system7_0] \
            CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ 125 {PS FCLK1}
        _assert_property [_require_bd_cell processing_system7_0] \
            CONFIG.PCW_EN_RST1_PORT 1 {PS FCLK1 reset port}
    }
    _assert_property [_require_bd_pin processing_system7_0/FCLK_RESET0_N] CONFIG.POLARITY ACTIVE_LOW {PS FCLK reset}
    _assert_property [_require_bd_pin proc_sys_reset_0/ext_reset_in] CONFIG.POLARITY ACTIVE_LOW {Processor System Reset input}
    _assert_property [_require_bd_cell proc_sys_reset_0] CONFIG.C_EXT_RESET_HIGH 0 {Processor System Reset}
    _assert_property [_require_bd_pin proc_sys_reset_0/peripheral_aresetn] CONFIG.POLARITY ACTIVE_LOW {Peripheral reset output}
    _assert_property [_require_bd_pin protection_ip_axi_lite_0/ARESETN] CONFIG.POLARITY ACTIVE_LOW {Protection reset input}
    _assert_property [_require_bd_pin axi_gpio_stage1d_0/s_axi_aresetn] CONFIG.POLARITY ACTIVE_LOW {AXI GPIO reset input}
    _assert_property [_require_bd_pin system_ila_stage2b_0/resetn] CONFIG.POLARITY ACTIVE_LOW {System ILA reset input}
    if {$profile eq {SAFE_INERT}} {
        _assert_exact_scalar_net {axi_gpio_stage1d_0/gpio_io_o xlslice_stage1d_ch1/Din xlslice_stage1d_ch2/Din} {Packed GPIO stimulus}
        _assert_exact_scalar_net {sample_valid_const/dout protection_ip_axi_lite_0/adc_sample_valid system_ila_stage2b_0/probe1} {adc_sample_valid constant zero}
        _assert_exact_scalar_net {xlslice_stage1d_ch1/Dout protection_ip_axi_lite_0/adc_sample_ch1 system_ila_stage2b_0/probe2} {adc_sample_ch1 slice source}
        _assert_exact_scalar_net {xlslice_stage1d_ch2/Dout protection_ip_axi_lite_0/adc_sample_ch2 system_ila_stage2b_0/probe3} {adc_sample_ch2 slice source}
        _assert_exact_scalar_net {protection_ip_axi_lite_0/adc_sample_ready system_ila_stage2b_0/probe11} {adc_sample_ready evidence path}
    } else {
        _assert_exact_scalar_net {axi_gpio_stage1d_0/gpio_io_o stage2i_b2_ready_aware_stimulus_0/control_word_aclk} {B2 command word}
        _assert_exact_scalar_net {stage2i_b2_ready_aware_stimulus_0/status_word_aclk axi_gpio_stage1d_0/gpio2_io_i} {B2 status word}
        _assert_exact_scalar_net {stage2i_b2_ready_aware_stimulus_0/sample_valid protection_ip_axi_lite_0/adc_sample_valid system_ila_stage2i_b2_source_0/probe0} {B2 adc_sample_valid path}
        _assert_exact_scalar_net {stage2i_b2_ready_aware_stimulus_0/sample_ch1 protection_ip_axi_lite_0/adc_sample_ch1 system_ila_stage2i_b2_source_0/probe2} {B2 adc_sample_ch1 path}
        _assert_exact_scalar_net {stage2i_b2_ready_aware_stimulus_0/sample_ch2 protection_ip_axi_lite_0/adc_sample_ch2 system_ila_stage2i_b2_source_0/probe3} {B2 adc_sample_ch2 path}
        _assert_exact_scalar_net {protection_ip_axi_lite_0/adc_sample_ready stage2i_b2_ready_aware_stimulus_0/sample_ready system_ila_stage2i_b2_source_0/probe1} {B2 adc_sample_ready path}
    }
    set ila [_require_bd_cell system_ila_stage2b_0]
    dict for {property value} [dict get $expected system_ila properties] {
        _assert_property $ila CONFIG.$property $value {System ILA}
    }
    set index 0
    foreach spec [_probe_specs $profile] {
        set source [lindex $spec 0]
        set width [lindex $spec 1]
        _assert_pin_width system_ila_stage2b_0/probe${index} $width
        _assert_property $ila CONFIG.C_PROBE${index}_WIDTH $width {System ILA probe}
        if {[_destination_probe_net_requires_exact_membership \
                $profile $index]} {
            _assert_exact_scalar_net [list $source system_ila_stage2b_0/probe${index}] "System ILA probe $index"
        } else {
            _assert_same_scalar_net [list $source system_ila_stage2b_0/probe${index}] "System ILA probe $index"
        }
        incr index
    }
    if {$profile eq {READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS}} {
        set source_reset [_require_bd_cell proc_sys_reset_stage2i_b2_src]
        _assert_property $source_reset CONFIG.C_EXT_RESET_HIGH 0 \
            {B2 source Processor System Reset}
        _assert_property \
            [_require_bd_pin proc_sys_reset_stage2i_b2_src/ext_reset_in] \
            CONFIG.POLARITY ACTIVE_LOW {B2 source reset input}
        _assert_property \
            [_require_bd_pin proc_sys_reset_stage2i_b2_src/peripheral_aresetn] \
            CONFIG.POLARITY ACTIVE_LOW {B2 source reset output}
        set source_ila [_require_bd_cell system_ila_stage2i_b2_source_0]
        dict for {property value} \
            [dict get $expected source_system_ila properties] {
            _assert_property $source_ila CONFIG.$property $value \
                {B2 source System ILA}
        }
        set index 0
        foreach spec [_source_probe_specs] {
            set source [lindex $spec 0]
            set width [lindex $spec 1]
            _assert_pin_width system_ila_stage2i_b2_source_0/probe${index} \
                $width
            _assert_property $source_ila CONFIG.C_PROBE${index}_WIDTH $width \
                {B2 source System ILA probe}
            if {$index < 4} {
                _assert_same_scalar_net \
                    [list $source \
                        system_ila_stage2i_b2_source_0/probe${index}] \
                    "B2 source System ILA probe $index"
            } else {
                _assert_exact_scalar_net \
                    [list $source \
                        system_ila_stage2i_b2_source_0/probe${index}] \
                    "B2 source System ILA probe $index"
            }
            incr index
        }
    }
    set external_interfaces {}
    foreach port [get_bd_intf_ports -quiet] { lappend external_interfaces [_object_path $port] }
    _validate_platform_interface_inventory \
        $external_interfaces [dict get $expected external_interfaces]
    set external_ports {}
    foreach port [get_bd_ports -quiet] {
        set name [_object_path $port]
        lappend external_ports $name [_bd_external_port_width $name]
    }
    _validate_platform_port_inventory \
        $external_ports \
        [dict get $expected platform_external_scalar_ports] \
        [dict get $expected custom_external_pl_ports]
    if {![dict exists $project wrapper_path] || ![file exists [dict get $project wrapper_path]] ||
        [file tail [dict get $project wrapper_path]] ne {protection_system_wrapper.v}} {
        _raise TOPOLOGY_WRAPPER {Exact protection_system wrapper does not exist.}
    }
    if {[get_property top [current_fileset]] ne {protection_system_wrapper}} {
        _raise TOPOLOGY_TOP {Synthesis top is not protection_system_wrapper.}
    }
    _validate_wrapper_port_inventory \
        [_wrapper_module_header_inventory [dict get $project wrapper_path]] \
        [dict get $expected project_top] \
        [dict get $expected platform_external_scalar_ports]
    validate_bd_design
    save_bd_design
    validate_topology_fixture $expected
    return [dict create contract $expected topology_identity [::stage1e::canonical_json_v1::digest_bytes [encoding convertto utf-8 $expected]]]
}

proc ::stage1e::production_vivado_runner_v2::_run_synthesis {project} {
    launch_runs synth_1
    wait_on_run synth_1
    set run [_require_unique_object [get_runs -quiet synth_1] {Synthesis run}]
    set status [get_property STATUS $run]
    set progress [get_property PROGRESS $run]
    if {$status ne {synth_design Complete!} || $progress ne {100%}} {
        _raise SYNTHESIS_STATE {Synthesis did not reach its exact completed state.}
    }
    set checkpoint [file join [get_property DIRECTORY $run] protection_system_wrapper.dcp]
    return [dict create run_identity synth_1 STATUS $status PROGRESS $progress CURRENT_STEP [get_property CURRENT_STEP $run] checkpoint $checkpoint output_identity [_file_identity $checkpoint]]
}

proc ::stage1e::production_vivado_runner_v2::_forbidden_operations {impl_run} {
    set observed {}
    foreach {property operation expected} {
        STEPS.PHYS_OPT_DESIGN.IS_ENABLED phys_opt_design 0
        STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED post_route_phys_opt_design 0
        STEPS.POWER_OPT_DESIGN.IS_ENABLED power_opt_design 0
        STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED post_place_power_opt_design 0
        AUTO_INCREMENTAL_CHECKPOINT incremental_implementation 0
    } {
        if {[get_property $property $impl_run] ne $expected} { lappend observed $operation }
    }
    if {[get_property INCREMENTAL_CHECKPOINT $impl_run] ne {}} { lappend observed checkpoint_import }
    return $observed
}

proc ::stage1e::production_vivado_runner_v2::_configure_implementation {} {
    set impl [_require_unique_object [get_runs -quiet impl_1] {Implementation run}]
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED 0 $impl
    set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED 0 $impl
    set_property STEPS.POWER_OPT_DESIGN.IS_ENABLED 0 $impl
    set_property STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED 0 $impl
    set_property AUTO_INCREMENTAL_CHECKPOINT 0 $impl
    set_property INCREMENTAL_CHECKPOINT {} $impl
    set requested [dict get [::stage1e::vivado_runtime_contract_v2::property_map] requested_implementation_graph]
    ::stage1e::vivado_runtime_contract_v2::validate_requested_graph [dict create \
        enabled_operations {opt_design place_design route_design} \
        launch_targets {opt_design place_design route_design} \
        prohibited_operations [dict get $requested prohibited_operations] \
        incremental_implementation AUTO_INCREMENTAL_CHECKPOINT_ZERO_AND_INCREMENTAL_CHECKPOINT_EMPTY]
    if {[llength [_forbidden_operations $impl]] != 0} {
        _raise FORBIDDEN_CONFIGURATION {Forbidden implementation configuration is enabled.}
    }
    return $impl
}

proc ::stage1e::production_vivado_runner_v2::_execute_phase {state phase run_directory impl_run} {
    set state [_start_implementation_phase $state $phase]
    launch_runs impl_1 -to_step $phase
    wait_on_run impl_1
    set observation [::stage1e::production_vivado_observer_v2::observe_live $phase $run_directory [_forbidden_operations $impl_run]]
    set state [_finish_implementation_phase $state $observation]
    return [dict create phase_state $state observation $observation]
}

proc ::stage1e::production_vivado_runner_v2::_complete_artifacts_bitstream {impl_run} {
    launch_runs impl_1 -to_step write_bitstream
    wait_on_run impl_1
    set evidence {}
    foreach property {NAME STATUS PROGRESS CURRENT_STEP DIRECTORY} {
        dict set evidence $property [get_property $property $impl_run]
    }
    if {[dict get $evidence NAME] ne {impl_1}} {
        _raise BITSTREAM_RUN_IDENTITY {Project Mode bitstream run is not impl_1.}
    }
    if {[dict get $evidence STATUS] ne {write_bitstream Complete!}} {
        _raise BITSTREAM_RUN_STATE {Project Mode bitstream did not reach its exact completed state.}
    }
    if {[dict get $evidence PROGRESS] ne {100%}} {
        _raise BITSTREAM_RUN_PROGRESS {Project Mode bitstream did not reach 100% progress.}
    }
    set forbidden [_forbidden_operations $impl_run]
    if {[llength $forbidden] != 0} {
        _raise FORBIDDEN_OPERATION "Forbidden implementation operation observed: $forbidden"
    }
    set bitstream [file join [dict get $evidence DIRECTORY] protection_system_wrapper.bit]
    _require_file $bitstream {Run-owned implementation BIT}
    if {[file size $bitstream] <= 0} {
        _raise BITSTREAM_EMPTY {Run-owned implementation BIT is empty.}
    }
    dict set evidence bitstream_path $bitstream
    return $evidence
}

proc ::stage1e::production_vivado_runner_v2::_artifact_binding {context} {
    return [dict create \
        implementation_profile [dict get $context implementation_profile] \
        execution_id [dict get $context execution_id] \
        source_commit [dict get $context source_commit] \
        source_tree [dict get $context source_tree] \
        project_identity [dict get $context project_identity] \
        design_identity [dict get $context design_identity]]
}

proc ::stage1e::production_vivado_runner_v2::_artifact_record {context role path} {
    return [::stage1e::production_vivado_collector_v2::_artifact_record [_artifact_binding $context] $role $path]
}

proc ::stage1e::production_vivado_runner_v2::_copy_artifact_new {source destination role} {
    _require_file $source "Generated $role artifact"
    if {[file exists $destination]} {
        _raise ARTIFACT_COLLISION "Artifact output already exists: $destination"
    }
    file copy -- $source $destination
    return $destination
}

proc ::stage1e::production_vivado_runner_v2::_expected_hwh_source {project} {
    set expected [file join [dict get $project project_dir] "[dict get $project project_name].gen" sources_1 bd [dict get $project bd_name] hw_handoff "[dict get $project bd_name].hwh"]
    _require_file $expected {Exact protection_system HWH source}
    return $expected
}

proc ::stage1e::production_vivado_runner_v2::_validate_artifact_roles {artifacts expected_roles} {
    set roles {}
    foreach artifact $artifacts { lappend roles [dict get $artifact role] }
    if {$roles ne $expected_roles || [llength $roles] != [llength [lsort -unique $roles]]} {
        _raise ARTIFACT_ROLE_INVENTORY "Artifact roles are not exact and unique: $roles"
    }
    return 1
}

proc ::stage1e::production_vivado_runner_v2::_generate_artifacts {context project run_bitstream} {
    if {[dict get $context build_target] ne {ARTIFACTS}} { return {} }
    set root [dict get $context artifact_root]
    set bitstream [_copy_artifact_new $run_bitstream [file join $root protection_system.bit] BITSTREAM]
    set xsa [file join $root protection_system.xsa]
    write_hw_platform -fixed -include_bit -file $xsa
    set hwh_source [_expected_hwh_source $project]
    set hwh [_copy_artifact_new $hwh_source [file join $root protection_system.hwh] HWH]
    if {[llength [get_debug_cores -quiet]] == 0} {
        _raise LTX_DEBUG_CORE {System ILA topology did not produce a debug core.}
    }
    set ltx [file join $root protection_system.ltx]
    write_debug_probes $ltx
    set artifacts [list \
        [_artifact_record $context BITSTREAM $bitstream] \
        [_artifact_record $context XSA $xsa] \
        [_artifact_record $context HWH $hwh] \
        [_artifact_record $context LTX $ltx]]
    _validate_artifact_roles $artifacts {BITSTREAM XSA HWH LTX}
    return $artifacts
}

proc ::stage1e::production_vivado_runner_v2::_report_paths {context} {
    set paths {}
    foreach role [::stage1e::production_vivado_collector_v2::report_roles] {
        dict set paths $role [file join [dict get $context report_root] "[string tolower $role].rpt"]
    }
    return $paths
}

proc ::stage1e::production_vivado_runner_v2::_result_schema {} {
    variable build_root
    set path [file join $build_root config stage1e_vivado_result_schema_v1.json]
    return [::stage1e::canonical_json_v1::parse_bytes [::stage1e::canonical_json_v1::read_file_bytes $path]]
}

proc ::stage1e::production_vivado_runner_v2::_string_array_node {values} {
    set nodes {}
    foreach value $values { lappend nodes [::stage1e::canonical_json_v1::new_string $value] }
    return [::stage1e::canonical_json_v1::new_array $nodes]
}

proc ::stage1e::production_vivado_runner_v2::_artifact_array_node {artifacts} {
    set nodes {}
    foreach artifact $artifacts {
        lappend nodes [::stage1e::canonical_json_v1::new_object [list \
            role [::stage1e::canonical_json_v1::new_string [dict get $artifact role]] \
            path [::stage1e::canonical_json_v1::new_string [dict get $artifact path]] \
            bytes [::stage1e::canonical_json_v1::new_integer [dict get $artifact bytes]] \
            sha256 [::stage1e::canonical_json_v1::new_string [dict get $artifact sha256]] \
            implementation_profile [::stage1e::canonical_json_v1::new_string [dict get $artifact implementation_profile]] \
            execution_id [::stage1e::canonical_json_v1::new_string [dict get $artifact execution_id]] \
            source_commit [::stage1e::canonical_json_v1::new_string [dict get $artifact source_commit]] \
            source_tree [::stage1e::canonical_json_v1::new_string [dict get $artifact source_tree]] \
            project_identity [::stage1e::canonical_json_v1::new_string [dict get $artifact project_identity]] \
            design_identity [::stage1e::canonical_json_v1::new_string [dict get $artifact design_identity]]]]
    }
    return [::stage1e::canonical_json_v1::new_array $nodes]
}

proc ::stage1e::production_vivado_runner_v2::_journal_node {journal} {
    return [::stage1e::canonical_json_v1::new_object [list \
        path [::stage1e::canonical_json_v1::new_string [dict get $journal path]] \
        bytes [::stage1e::canonical_json_v1::new_integer [dict get $journal bytes]] \
        sha256 [::stage1e::canonical_json_v1::new_string [dict get $journal sha256]]]]
}

proc ::stage1e::production_vivado_runner_v2::_write_result {context result} {
    set schema [_result_schema]
    set registry [dict create stage1e-vivado-result-v1 $schema]
    set node [::stage1e::canonical_json_v1::new_object [list \
        schema_version [::stage1e::canonical_json_v1::new_string stage1e-vivado-result-v1] \
        execution_id [::stage1e::canonical_json_v1::new_string [dict get $context execution_id]] \
        request_identity [::stage1e::canonical_json_v1::new_string [dict get $context request_identity]] \
        execution_contract_identity [::stage1e::canonical_json_v1::new_string [dict get $context execution_contract_identity]] \
        implementation_profile [::stage1e::canonical_json_v1::new_string [dict get $context implementation_profile]] \
        source_commit [::stage1e::canonical_json_v1::new_string [dict get $context source_commit]] \
        source_tree [::stage1e::canonical_json_v1::new_string [dict get $context source_tree]] \
        project_identity [::stage1e::canonical_json_v1::new_string [dict get $context project_identity]] \
        design_identity [::stage1e::canonical_json_v1::new_string [dict get $context design_identity]] \
        run_kind [::stage1e::canonical_json_v1::new_string [dict get $context run_kind]] \
        result_state [::stage1e::canonical_json_v1::new_string [dict get $result result_state]] \
        failure_code [::stage1e::canonical_json_v1::new_string [dict get $result failure_code]] \
        reason [::stage1e::canonical_json_v1::new_string [dict get $result reason]] \
        route_completed [::stage1e::canonical_json_v1::new_boolean [dict get $result route_completed]] \
        SYNTH_RUN_AVAILABLE [::stage1e::canonical_json_v1::new_boolean [dict get $result SYNTH_RUN_AVAILABLE]] \
        IMPL_RUN_AVAILABLE [::stage1e::canonical_json_v1::new_boolean [dict get $result IMPL_RUN_AVAILABLE]] \
        GUI_PROJECT_PATH [::stage1e::canonical_json_v1::new_string [dict get $result GUI_PROJECT_PATH]] \
        PROJECT_SAFE_TO_OPEN [::stage1e::canonical_json_v1::new_boolean [dict get $result PROJECT_SAFE_TO_OPEN]] \
        forbidden_operation_count [::stage1e::canonical_json_v1::new_integer [llength [dict get $result forbidden_operations]]] \
        forbidden_operations [_string_array_node [dict get $result forbidden_operations]] \
        runner_phase_journal [_journal_node [dict get $result runner_phase_journal]] \
        collector_state [::stage1e::canonical_json_v1::new_string [dict get $result collector_state]] \
        artifact_inventory [_artifact_array_node [dict get $result artifact_inventory]] \
        finding_decision_identity [::stage1e::canonical_json_v1::new_string [dict get $context finding_decision_identity]]]]
    set bytes [::stage1e::canonical_json_v1::canonical_bytes $node $schema $registry]
    set channel [open [dict get $context result_path] {WRONLY CREAT EXCL}]
    fconfigure $channel -translation binary -encoding binary
    puts -nonewline $channel $bytes
    close $channel
}

proc ::stage1e::production_vivado_runner_v2::_blocked_result {context reason} {
    return [dict create result_state BLOCKED failure_code EXECUTION_FAILED reason $reason \
        route_completed 0 SYNTH_RUN_AVAILABLE 0 IMPL_RUN_AVAILABLE 0 \
        GUI_PROJECT_PATH UNAVAILABLE PROJECT_SAFE_TO_OPEN 0 forbidden_operations {} \
        runner_phase_journal [_phase_journal_record $context] collector_state BLOCKED artifact_inventory {}]
}

proc ::stage1e::production_vivado_runner_v2::_safe_impl_evidence {} {
    if {[catch {set run [_require_unique_object [get_runs -quiet impl_1] {Implementation run}]}]} {
        return [dict create run_identity NOT_AVAILABLE STATUS NOT_AVAILABLE PROGRESS NOT_AVAILABLE CURRENT_STEP NOT_AVAILABLE]
    }
    set evidence [dict create run_identity impl_1]
    foreach property {STATUS PROGRESS CURRENT_STEP} {
        if {[catch {get_property $property $run} value]} { set value NOT_AVAILABLE }
        dict set evidence $property $value
    }
    return $evidence
}

proc ::stage1e::production_vivado_runner_v2::run {context} {
    _validate_context $context
    initialize_phase_journal $context
    set result [_blocked_result $context {Execution did not start.}]
    set current_phase {}
    if {[catch {
        set current_phase SOURCE_PRECHECK
        append_phase_journal $context ATTEMPT $current_phase PRECHECK NOT_STARTED 0 NONE NONE {Validate sealed contract and Vivado identity.}
        _assert_execution_contract_identity $context
        set tool_identity [_assert_tool_identity $context]
        append_phase_journal $context COMPLETED $current_phase PRECHECK VALIDATED 0 NONE [dict get $context execution_contract_identity] $tool_identity
        set current_phase {}

        set current_phase PACKAGE_IP
        append_phase_journal $context ATTEMPT $current_phase stage1e_ip_packaging NOT_STARTED 0 NONE NONE {Package exact protection IP.}
        set package [package_protection_ip $context]
        append_phase_journal $context COMPLETED $current_phase stage1e_ip_packaging COMPLETE 100 NONE [dict get $package component_identity] [dict get $package component_path]
        set current_phase {}

        set current_phase CREATE_PROJECT
        append_phase_journal $context ATTEMPT $current_phase [dict get $context project_identity] NOT_STARTED 0 NONE NONE {Create fresh PYNQ-Z2 project.}
        set project [create_build_project $context $package]
        append_phase_journal $context COMPLETED $current_phase [dict get $context project_identity] CREATED 100 NONE [dict get $context project_identity] [dict get $project project_path]
        set current_phase {}

        set current_phase CREATE_BASE_BD
        append_phase_journal $context ATTEMPT $current_phase protection_system NOT_STARTED 0 NONE NONE {Create reviewed PS/reset/SmartConnect/protection base.}
        set project [create_base_bd $context $project]
        append_phase_journal $context COMPLETED $current_phase protection_system VALIDATED 100 NONE protection_system [dict get $project bd_file]
        set current_phase {}

        set current_phase ADD_DEBUG
        append_phase_journal $context ATTEMPT $current_phase protection_system NOT_STARTED 0 NONE NONE {Add exact mixed System ILA.}
        set project [add_debug $context $project]
        if {[dict get $context implementation_profile] eq {SAFE_INERT}} {
            set debug_detail {Twelve destination probes and one AXI monitor connected for the identical-clock production profile.}
        } else {
            set debug_detail {Destination System ILA connected; source-domain System ILA is added with the B2 stimulus.}
        }
        append_phase_journal $context COMPLETED $current_phase protection_system VALIDATED 100 NONE system_ila_stage2b_0 $debug_detail
        set current_phase {}

        set current_phase ADD_CONTROLLED_STIMULUS
        append_phase_journal $context ATTEMPT $current_phase protection_system NOT_STARTED 0 NONE NONE {Add exact profile-specific AXI GPIO stimulus source.}
        set project [add_controlled_stimulus $context $project]
        if {[dict get $context implementation_profile] eq {SAFE_INERT}} {
            set stimulus_detail {GPIO[11:0] to channel 1; GPIO[23:12] to channel 2; sample_valid is explicitly zero.}
        } else {
            set stimulus_detail {Dual-channel GPIO controls the bounded ready-aware producer; FCLK1 is 125 MHz and source-domain ILA observes valid, ready, payload, state, remaining, and acceptance.}
        }
        append_phase_journal $context COMPLETED $current_phase protection_system VALIDATED 100 NONE axi_gpio_stage1d_0 $stimulus_detail
        set current_phase {}

        set current_phase GENERATE_WRAPPER
        append_phase_journal $context ATTEMPT $current_phase protection_system_wrapper NOT_STARTED 0 NONE NONE {Generate exact BD output products and wrapper.}
        set project [generate_wrapper $context $project]
        set wrapper_identity [_file_identity [dict get $project wrapper_path]]
        append_phase_journal $context COMPLETED $current_phase protection_system_wrapper GENERATED 100 NONE $wrapper_identity [dict get $project wrapper_path]
        set current_phase {}

        set current_phase VALIDATE_FINAL_TOPOLOGY
        append_phase_journal $context ATTEMPT $current_phase protection_system READBACK 0 NONE NONE {Read back the complete final BD before synthesis.}
        set topology [validate_final_topology $context $project]
        append_phase_journal $context COMPLETED $current_phase protection_system VALIDATED 100 NONE [dict get $topology topology_identity] "Exact [dict get $context implementation_profile] topology read back."
        set current_phase {}

        set current_phase SYNTHESIS
        append_phase_journal $context ATTEMPT $current_phase synth_1 {Not started} 0 NONE NONE {Launch and wait for synthesis.}
        set synthesis [_run_synthesis $project]
        dict set result SYNTH_RUN_AVAILABLE 1
        append_phase_journal $context COMPLETED $current_phase [dict get $synthesis run_identity] [dict get $synthesis STATUS] [dict get $synthesis PROGRESS] [dict get $synthesis CURRENT_STEP] [dict get $synthesis output_identity] [dict get $synthesis checkpoint]
        set current_phase {}

        set impl [_configure_implementation]
        dict set result IMPL_RUN_AVAILABLE 1
        set run_directory [get_property DIRECTORY $impl]
        set state [new_phase_state]
        foreach phase [phase_order] {
            set current_phase [string toupper $phase]
            set before [_safe_impl_evidence]
            append_phase_journal $context ATTEMPT $current_phase impl_1 [dict get $before STATUS] [dict get $before PROGRESS] [dict get $before CURRENT_STEP] NONE "Launch impl_1 through $phase."
            set phase_result [_execute_phase $state $phase $run_directory $impl]
            set state [dict get $phase_result phase_state]
            set observation [dict get $phase_result observation]
            if {[dict get $observation action] ne {PROCEED}} {
                _raise PHASE_COMPLETION [dict get $observation reason]
            }
            set snapshot [dict get $observation snapshot]
            append_phase_journal $context COMPLETED $current_phase impl_1 [dict get $snapshot run_status] [dict get $snapshot progress] [dict get $snapshot current_step] [dict get $snapshot checkpoint_identity] [dict get $snapshot checkpoint]
            set current_phase {}
        }
        if {[dict get $state terminal_state] ne {ROUTED}} {
            _raise PHASE_COMPLETION {Implementation phase state is not routed.}
        }

        set current_phase ARTIFACT_GENERATION
        set artifact_before [_safe_impl_evidence]
        append_phase_journal $context ATTEMPT $current_phase impl_1 [dict get $artifact_before STATUS] [dict get $artifact_before PROGRESS] [dict get $artifact_before CURRENT_STEP] NONE {Generate requested deterministic artifact roles.}
        set run_bitstream {}
        if {[dict get $context build_target] eq {ARTIFACTS}} {
            set bitstream_evidence [_complete_artifacts_bitstream $impl]
            set run_bitstream [dict get $bitstream_evidence bitstream_path]
        }
        open_run impl_1
        set final_forbidden [_forbidden_operations $impl]
        if {[llength $final_forbidden] != 0} {
            _raise FORBIDDEN_OPERATION "Forbidden implementation operation observed: $final_forbidden"
        }
        set artifacts [_generate_artifacts $context $project $run_bitstream]
        set generated_roles {}
        foreach artifact $artifacts { lappend generated_roles [dict get $artifact role] }
        set artifact_after [_safe_impl_evidence]
        append_phase_journal $context COMPLETED $current_phase impl_1 [dict get $artifact_after STATUS] [dict get $artifact_after PROGRESS] [dict get $artifact_after CURRENT_STEP] [join $generated_roles ,] {Requested artifacts generated.}
        set current_phase {}

        set current_phase REPORT_COLLECTION
        set report_before [_safe_impl_evidence]
        append_phase_journal $context ATTEMPT $current_phase impl_1 [dict get $report_before STATUS] [dict get $report_before PROGRESS] [dict get $report_before CURRENT_STEP] NONE {Collect closed report inventory and manifest.}
        set collector_request [dict create \
            report_root [dict get $context report_root] \
            implementation_profile [dict get $context implementation_profile] \
            execution_id [dict get $context execution_id] \
            source_commit [dict get $context source_commit] \
            source_tree [dict get $context source_tree] \
            project_identity [dict get $context project_identity] \
            design_identity [dict get $context design_identity] \
            run_identity impl_1 \
            process_identity [dict get $context process_identity] \
            role_output_paths [_report_paths $context]]
        set collected [::stage1e::production_vivado_collector_v2::collect_live $collector_request]
        if {[dict get $collected action] ne {PROCEED}} {
            _raise COLLECTOR [dict get $collected reason]
        }
        set artifacts [::stage1e::production_vivado_collector_v2::write_artifact_manifest [dict get $context artifact_root] $artifacts [dict get $collected attempts] [_artifact_binding $context]]
        if {[dict get $context build_target] eq {ARTIFACTS}} {
            _validate_artifact_roles $artifacts {BITSTREAM XSA HWH LTX ARTIFACT_MANIFEST}
        }
        set report_after [_safe_impl_evidence]
        append_phase_journal $context COMPLETED $current_phase impl_1 [dict get $report_after STATUS] [dict get $report_after PROGRESS] [dict get $report_after CURRENT_STEP] ARTIFACT_MANIFEST {Reports and exact artifact manifest collected.}
        set current_phase {}

        dict set result result_state COMPLETED
        dict set result failure_code NONE
        dict set result reason {Routed engineering implementation, reports, and requested artifacts completed.}
        dict set result route_completed 1
        dict set result GUI_PROJECT_PATH [_canonical_path [dict get $project project_path]]
        dict set result PROJECT_SAFE_TO_OPEN 1
        dict set result forbidden_operations $final_forbidden
        dict set result runner_phase_journal [_phase_journal_record $context]
        dict set result collector_state COLLECTED
        dict set result artifact_inventory $artifacts
        if {[dict get $context project_retention] eq {REMOVE}} {
            ::close_project
            file delete -force [dict get $project project_dir]
            dict set result GUI_PROJECT_PATH NOT_RETAINED
            dict set result PROJECT_SAFE_TO_OPEN 0
        }
    } reason options]} {
        if {$current_phase ne {}} {
            set evidence [_safe_impl_evidence]
            catch {append_phase_journal $context FAILED $current_phase [dict get $evidence run_identity] [dict get $evidence STATUS] [dict get $evidence PROGRESS] [dict get $evidence CURRENT_STEP] NONE $reason}
        }
        set result [_blocked_result $context $reason]
    }
    _write_result $context $result
    return $result
}
