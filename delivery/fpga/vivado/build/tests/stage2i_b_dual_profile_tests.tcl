set script_path [file normalize [info script]]
set build_root [file normalize [file join [file dirname $script_path] ..]]
set repository_root [file normalize [file join $build_root .. .. ..]]
set runner_path [file join $build_root runtime runner \
    stage1e_production_vivado_runner_v2.tcl]
set constraint_path [file join $repository_root fpga vivado constraints \
    stage2i_b2_ready_aware_stimulus_cdc.xdc]
set producer_path [file join $repository_root fpga vivado test_profile \
    stage2i_b2_ready_aware_stimulus.v]

source $runner_path

proc fail {message} {
    puts stderr "FAIL: $message"
    exit 1
}

proc assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} { fail $message }
}

proc read_text {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set value [read $channel]
    close $channel
    return $value
}

set b1 [::stage1e::production_vivado_runner_v2::topology_contract SAFE_INERT]
set b2 [::stage1e::production_vivado_runner_v2::topology_contract \
    READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS]

assert_true {[dict get $b1 implementation_profile] eq {SAFE_INERT}} \
    {B1 profile identity differs}
assert_true {[llength [dict get $b1 cell_inventory]] == 10} \
    {B1 cell inventory is not exact}
foreach forbidden {
    stage2i_b2_ready_aware_stimulus_0
    proc_sys_reset_stage2i_b2_src
    system_ila_stage2i_b2_source_0
} {
    assert_true {[lsearch -exact [dict get $b1 cell_inventory] $forbidden] < 0} \
        "B2 cell leaked into B1: $forbidden"
}
assert_true {[dict get $b1 controlled_stimulus valid_value] == 0} \
    {B1 sample valid is not explicitly zero}
assert_true {[dict get $b1 adc_source_clock driver] eq \
    {processing_system7_0/FCLK_CLK0}} {B1 adc source clock changed}
assert_true {[dict get $b1 system_ila properties C_NUM_OF_PROBES] == 12 &&
    [llength [dict get $b1 system_ila probes]] == 12} \
    {B1 destination ILA probe contract changed}
set b1_destination_contract {}
foreach probe [dict get $b1 system_ila probes] {
    lappend b1_destination_contract \
        [list [dict get $probe index] [dict get $probe source] \
            [dict get $probe width]]
}
set expected_b1_destination_contract {
    {0 protection_ip_axi_lite_0/ARESETN 1}
    {1 protection_ip_axi_lite_0/adc_sample_valid 1}
    {2 protection_ip_axi_lite_0/adc_sample_ch1 12}
    {3 protection_ip_axi_lite_0/adc_sample_ch2 12}
    {4 protection_ip_axi_lite_0/pwm_raw 1}
    {5 protection_ip_axi_lite_0/pwm_out 1}
    {6 protection_ip_axi_lite_0/fault_valid 1}
    {7 protection_ip_axi_lite_0/fault_latched 1}
    {8 protection_ip_axi_lite_0/fault_code 8}
    {9 protection_ip_axi_lite_0/fault_code_latched 8}
    {10 protection_ip_axi_lite_0/fsm_state 4}
    {11 protection_ip_axi_lite_0/adc_sample_ready 1}
}
assert_true {[lrange $b1_destination_contract 0 end] eq
    [lrange $expected_b1_destination_contract 0 end]} \
    {B1 destination ILA probe identities or widths changed}

assert_true {[dict get $b2 implementation_profile] eq \
    {READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS}} {B2 profile identity differs}
foreach required {
    stage2i_b2_ready_aware_stimulus_0
    proc_sys_reset_stage2i_b2_src
    system_ila_stage2i_b2_source_0
} {
    assert_true {[lsearch -exact [dict get $b2 cell_inventory] $required] >= 0} \
        "B2 cell is missing: $required"
}
assert_true {[dict get $b2 adc_source_clock driver] eq \
    {processing_system7_0/FCLK_CLK1}} {B2 source clock is not FCLK1}
assert_true {[dict get $b2 adc_source_clock frequency_mhz] == 125} \
    {B2 source frequency is not 125 MHz}
assert_true {[dict get $b2 controlled_stimulus ready_consumed] == 1 &&
    [dict get $b2 controlled_stimulus transaction_pulse_bounded] == 1 &&
    [dict get $b2 controlled_stimulus maximum_burst_count] == 127} \
    {B2 ready-aware bounded producer contract differs}
assert_true {[dict get $b2 source_system_ila present] == 1 &&
    [llength [dict get $b2 source_system_ila probes]] == 8} \
    {B2 source-domain ILA contract differs}
assert_true {[dict get $b2 system_ila properties C_NUM_OF_PROBES] == 8 &&
    [llength [dict get $b2 system_ila probes]] == 8} \
    {B2 destination ILA is not limited to destination-domain probes}
set b2_destination_sources {}
foreach probe [dict get $b2 system_ila probes] {
    lappend b2_destination_sources [dict get $probe source]
}
assert_true {$b2_destination_sources eq {protection_ip_axi_lite_0/ARESETN protection_ip_axi_lite_0/pwm_raw protection_ip_axi_lite_0/pwm_out protection_ip_axi_lite_0/fault_valid protection_ip_axi_lite_0/fault_latched protection_ip_axi_lite_0/fault_code protection_ip_axi_lite_0/fault_code_latched protection_ip_axi_lite_0/fsm_state}} \
    {B2 destination ILA probe map differs}
foreach source {
    protection_ip_axi_lite_0/adc_sample_valid
    protection_ip_axi_lite_0/adc_sample_ch1
    protection_ip_axi_lite_0/adc_sample_ch2
    protection_ip_axi_lite_0/adc_sample_ready
} {
    assert_true {[lsearch -exact $b2_destination_sources $source] < 0} \
        "B2 destination ILA still samples a source-domain signal: $source"
}
assert_true {![::stage1e::production_vivado_runner_v2::_is_ready_aware_profile \
    SAFE_INERT]} {B1 was classified as the ready-aware profile}
assert_true {[::stage1e::production_vivado_runner_v2::_is_ready_aware_profile \
    READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS]} \
    {B2 was not classified as the ready-aware profile}

foreach index {0 1 2 3} {
    assert_true {![::stage1e::production_vivado_runner_v2::_destination_probe_net_requires_exact_membership \
        SAFE_INERT $index]} \
        "B1 shared input probe $index unexpectedly requires exact net membership"
}
foreach index {4 5 6 7 8 9 10 11} {
    assert_true {[::stage1e::production_vivado_runner_v2::_destination_probe_net_requires_exact_membership \
        SAFE_INERT $index]} \
        "B1 output probe $index does not require exact net membership"
}
assert_true {![::stage1e::production_vivado_runner_v2::_destination_probe_net_requires_exact_membership \
    READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS 0]} \
    {B2 reset probe unexpectedly requires exact net membership}
foreach index {1 2 3 4 5 6 7} {
    assert_true {[::stage1e::production_vivado_runner_v2::_destination_probe_net_requires_exact_membership \
        READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS $index]} \
        "B2 destination probe $index does not require exact net membership"
}

foreach dispatch_proc {
    create_build_project
    add_controlled_stimulus
    validate_topology_fixture
} {
    set dispatch_body [info body \
        ::stage1e::production_vivado_runner_v2::$dispatch_proc]
    assert_true {[string first {_is_ready_aware_profile} $dispatch_body] >= 0} \
        "B2 dispatch does not use the exact profile predicate: $dispatch_proc"
}
set create_project_body [info body \
    ::stage1e::production_vivado_runner_v2::create_build_project]
assert_true {[string first \
    {stage2i_b2_ready_aware_stimulus.v} $create_project_body] >= 0 &&
    [string first \
        {set_property file_type Verilog} $create_project_body] >= 0 &&
    [string first \
        {set_property file_type SystemVerilog} $create_project_body] < 0} \
    {B2 module-reference source is not staged as a Verilog top}
set add_b2_body [info body \
    ::stage1e::production_vivado_runner_v2::_add_ready_aware_stimulus]
set validate_topology_body [info body \
    ::stage1e::production_vivado_runner_v2::validate_final_topology]
foreach body [list $add_b2_body $validate_topology_body] {
    assert_true {[string first \
        {system_ila_stage2i_b2_source_0/resetn} $body] < 0} \
        {Probe-only native B2 source System ILA assumes a nonexistent reset pin}
}
set add_debug_body [info body \
    ::stage1e::production_vivado_runner_v2::add_debug]
foreach body [list $add_debug_body $validate_topology_body] {
    assert_true {[string first {_probe_specs $profile} $body] >= 0} \
        {Destination ILA construction or validation is not profile-specific}
}
foreach forbidden {
    {protection_ip_axi_lite_0/adc_sample_valid system_ila_stage2b_0/probe1 system_ila_stage2i_b2_source_0/probe0}
    {protection_ip_axi_lite_0/adc_sample_ch1 system_ila_stage2b_0/probe2 system_ila_stage2i_b2_source_0/probe2}
    {protection_ip_axi_lite_0/adc_sample_ch2 system_ila_stage2b_0/probe3 system_ila_stage2i_b2_source_0/probe3}
    {protection_ip_axi_lite_0/adc_sample_ready stage2i_b2_ready_aware_stimulus_0/sample_ready system_ila_stage2b_0/probe11}
} {
    assert_true {[string first $forbidden $validate_topology_body] < 0} \
        "B2 source-domain net still includes the destination ILA: $forbidden"
}

rename ::stage1e::production_vivado_runner_v2::_add_ready_aware_stimulus \
    ::stage1e::production_vivado_runner_v2::_add_ready_aware_stimulus_real
proc ::stage1e::production_vivado_runner_v2::_add_ready_aware_stimulus {
    context project
} {
    return [dict create \
        profile [dict get $context implementation_profile] \
        project $project]
}
set b2_dispatch [::stage1e::production_vivado_runner_v2::add_controlled_stimulus \
    [dict create implementation_profile \
        READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS] \
    fixture_project]
rename ::stage1e::production_vivado_runner_v2::_add_ready_aware_stimulus {}
rename ::stage1e::production_vivado_runner_v2::_add_ready_aware_stimulus_real \
    ::stage1e::production_vivado_runner_v2::_add_ready_aware_stimulus
assert_true {[dict get $b2_dispatch profile] eq \
    {READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS} &&
    [dict get $b2_dispatch project] eq {fixture_project}} \
    {B2 controlled-stimulus dispatch fell through to SAFE_INERT}

set create_base_bd_body [info body \
    ::stage1e::production_vivado_runner_v2::create_base_bd]
assert_true {[string first {CONFIG.PCW_EN_RST1_PORT {1}} \
    $create_base_bd_body] >= 0} \
    {B2 PS configuration does not enable the parameter-gated FCLK1 reset port}
assert_true {[string first \
    {CONFIG.PCW_EN_RST1_PORT 1 {PS FCLK1 reset port}} \
    $validate_topology_body] >= 0} \
    {B2 topology validation does not read back the FCLK1 reset-port enable}

::stage1e::production_vivado_runner_v2::validate_topology_fixture $b1
::stage1e::production_vivado_runner_v2::validate_topology_fixture $b2
set duplicate_source_probe_b2 $b2
set duplicate_source_probes \
    [dict get $duplicate_source_probe_b2 source_system_ila probes]
set duplicate_probe [lindex $duplicate_source_probes 1]
dict set duplicate_probe index \
    [dict get [lindex $duplicate_source_probes 0] index]
lset duplicate_source_probes 1 $duplicate_probe
dict set duplicate_source_probe_b2 source_system_ila probes \
    $duplicate_source_probes
set duplicate_source_probe_code [catch {
    ::stage1e::production_vivado_runner_v2::validate_topology_fixture \
        $duplicate_source_probe_b2
} duplicate_source_probe_message]
assert_true {$duplicate_source_probe_code == 1 &&
    $duplicate_source_probe_message eq \
        {B2 source ILA probe inventory contains a duplicate.}} \
    {B2 source-ILA duplicate guard did not execute}
set leaked $b1
dict lappend leaked cell_inventory stage2i_b2_ready_aware_stimulus_0
assert_true {[catch {
    ::stage1e::production_vivado_runner_v2::validate_topology_fixture $leaked
}]} {B1 topology leakage mutation passed}
assert_true {[catch {
    ::stage1e::production_vivado_runner_v2::topology_contract THIRD_PROFILE
}]} {Unknown implementation profile passed}

set source_context [dict create repository_root $repository_root]
set production_rtl \
    [::stage1e::production_vivado_runner_v2::_rtl_files $source_context]
set production_xdc \
    [::stage1e::production_vivado_runner_v2::_constraint_files $source_context]
assert_true {[llength $production_rtl] == 21} \
    {Production RTL source count changed}
assert_true {[llength $production_xdc] == 2} \
    {Production XDC source count changed}
assert_true {[lsearch -exact $production_rtl $producer_path] < 0} \
    {B2 producer entered the production RTL authority}

set package_body [info body \
    ::stage1e::production_vivado_runner_v2::package_protection_ip]
assert_true {[string first \
    {set_property USED_IN_SYNTHESIS false} $package_body] >= 0} \
    {Production packaged constraints are not implementation-only}
assert_true {[string first \
    {set_property USED_IN_SYNTHESIS true} $package_body] < 0} \
    {Production packaged constraints still claim synthesis use}
set constraint_group_body [info body \
    ::stage1e::production_vivado_runner_v2::_stage_packaged_implementation_constraints]
foreach required {
    {xilinx_anylanguagesynthesis}
    {xilinx_implementation}
    {ipx::remove_file $relative_path $synthesis}
    {ipx::add_file}
    {set_property type xdc $implementation_file}
    {set_property processing_order late $implementation_file}
    {$occurrence_count != 1}
    {$owning_groups ne {xilinx_implementation}}
} {
    assert_true {[string first $required $constraint_group_body] >= 0} \
        "Packaged implementation-constraint helper lacks token: $required"
}

set constraint_source [read_text $constraint_path]
assert_true {![regexp {(?m)^[ \t]*(namespace|proc|foreach|for|while|if|lappend|dict|return|error)([ \t]|$)} $constraint_source]} \
    {B2 CDC authority is not restricted-XDC-compatible straight-line Tcl}
foreach required {
    {COMMAND_REQUEST}
    {COMMAND_BUNDLED_DATA}
    {COMMAND_ACKNOWLEDGMENT}
    {PRODUCER_ACTIVE_STATUS}
    {producer_active_reg_reg}
    {ACCEPTED_COUNT_STATUS}
    {REMAINING_COUNT_STATUS}
    {set_max_delay -datapath_only}
    {set_bus_skew}
    {u_adc_source_reset_release_sync/release_pipe_reg}
    {set_false_path -to}
} {
    assert_true {[string first $required $constraint_source] >= 0} \
        "B2 CDC constraint lacks token: $required"
}
foreach forbidden {
    {set_clock_groups}
    {fifo_write_data}
    {fifo_read_data}
} {
    assert_true {[string first $forbidden $constraint_source] < 0} \
        "B2 CDC constraint contains broad token: $forbidden"
}

proc mock_prelude {mode} {
    return [string map [list @MODE@ [list $mode]] {
        set ::mock_mode @MODE@
        set ::max_delay_calls {}
        set ::bus_skew_calls {}
        set ::false_path_calls {}

        proc get_cells {args} {
            set pattern [lindex $args end]
            set result {}
            foreach leaf {
                request_toggle_aclk_reg
                request_toggle_sync1_src_reg
                ack_toggle_src_reg
                ack_toggle_sync1_aclk_reg
                producer_active_reg_reg
                producer_active_sync1_aclk_reg
            } {
                if {$::mock_mode eq {missing_active} &&
                    $leaf eq {producer_active_reg_reg}} {
                    continue
                }
                set name \
                    "top/stage2i_b2_ready_aware_stimulus_0/inst/$leaf"
                if {[regexp $pattern $name]} { lappend result $name }
            }
            foreach {leaf width} {
                command_hold_aclk_reg 31
                command_capture_src_reg 31
                accepted_count_gray_src_reg 8
                accepted_count_gray_sync1_aclk_reg 8
                remaining_gray_src_reg 7
                remaining_gray_sync1_aclk_reg 7
            } {
                for {set index 0} {$index < $width} {incr index} {
                    if {$::mock_mode eq {missing_bit} &&
                        $leaf eq {command_capture_src_reg} && $index == 30} {
                        continue
                    }
                    set name "top/stage2i_b2_ready_aware_stimulus_0/inst/${leaf}\[$index\]"
                    if {[regexp $pattern $name]} { lappend result $name }
                }
            }
            foreach index {0 1} {
                if {$::mock_mode eq {reset_missing} && $index == 1} {
                    continue
                }
                set name "top/protection_system_i/protection_ip_axi_lite_0/inst/u_adc_source_reset_release_sync/release_pipe_reg\[$index\]"
                if {[regexp $pattern $name]} { lappend result $name }
            }
            return $result
        }

        proc get_property {property object} {
            if {$property eq {NAME}} { return $object }
            if {$property eq {PERIOD}} {
                if {[string first {_src} $object] >= 0 ||
                    [string first {producer_active_reg} $object] >= 0} {
                    return 8.000
                }
                return 10.000
            }
            error "unexpected property: $property"
        }

        proc get_pins {args} {
            set object_index [lsearch -exact $args -of_objects]
            set cells [lindex $args [expr {$object_index + 1}]]
            set filter_index [lsearch -exact $args -filter]
            set filter [lindex $args [expr {$filter_index + 1}]]
            regexp {REF_PIN_NAME == ([A-Z]+)} $filter _ pin
            set result {}
            foreach cell $cells { lappend result ${cell}/${pin} }
            return $result
        }

        proc get_clocks {args} {
            set object_index [lsearch -exact $args -of_objects]
            set pin [lindex $args [expr {$object_index + 1}]]
            return [list ${pin}/clock]
        }

        proc set_max_delay {args} { lappend ::max_delay_calls $args }
        proc set_bus_skew {args} { lappend ::bus_skew_calls $args }
        proc set_false_path {args} { lappend ::false_path_calls $args }
    }]
}

proc run_constraint_fixture {constraint_path mode} {
    set child [interp create]
    interp eval $child [mock_prelude $mode]
    set code [catch {
        interp eval $child [list source $constraint_path]
    } message options]
    set result [dict create code $code message $message]
    if {!$code} {
        dict set result max_delay_calls \
            [interp eval $child {set ::max_delay_calls}]
        dict set result bus_skew_calls \
            [interp eval $child {set ::bus_skew_calls}]
        dict set result false_path_calls \
            [interp eval $child {set ::false_path_calls}]
        dict set result authority_result [interp eval $child \
            {set ::stage2i_b2_ready_aware_stimulus_cdc_constraint_result}]
    } elseif {[dict exists $options -errorcode]} {
        dict set result errorcode [dict get $options -errorcode]
    }
    interp delete $child
    return $result
}

set positive [run_constraint_fixture $constraint_path positive]
assert_true {[dict get $positive code] == 0} \
    "B2 CDC positive fixture failed: [dict get $positive message]"
assert_true {[llength [dict get $positive max_delay_calls]] == 6} \
    {B2 CDC did not emit six max-delay constraints}
assert_true {[llength [dict get $positive bus_skew_calls]] == 3} \
    {B2 CDC did not emit three bus-skew constraints}
assert_true {[llength [dict get $positive false_path_calls]] == 1} \
    {B2 CDC did not emit exactly one reset false-path constraint}
assert_true {[llength [dict get $positive authority_result]] == 7} \
    {B2 CDC result did not record six crossings and one reset exception}
set reset_call [lindex [dict get $positive false_path_calls] 0]
assert_true {[llength $reset_call] == 2 &&
    [lindex $reset_call 0] eq {-to} &&
    [llength [lindex $reset_call 1]] == 2} \
    "B2 reset false path is not one exact two-pin -to exception: $reset_call"
foreach reset_pin [lindex $reset_call 1] {
    assert_true {[regexp {u_adc_source_reset_release_sync/release_pipe_reg\[[0-1]\]/CLR$} $reset_pin]} \
        "B2 reset false path expanded beyond release_pipe CLR pins: $reset_pin"
}
foreach call [concat [dict get $positive max_delay_calls] \
    [dict get $positive bus_skew_calls]] {
    assert_true {[lsearch -exact $call 8.0] >= 0 ||
        [lsearch -exact $call 8.000] >= 0} \
        "B2 CDC crossing did not use the smaller 8 ns period: $call"
    set from_position [lsearch -exact $call -from]
    set to_position [lsearch -exact $call -to]
    assert_true {$from_position >= 0 && $to_position >= 0} \
        "B2 CDC crossing lacks explicit endpoints: $call"
    set endpoint_cells [concat \
        [lindex $call [expr {$from_position + 1}]] \
        [lindex $call [expr {$to_position + 1}]]]
    foreach endpoint $endpoint_cells {
        assert_true {![regexp {/[QD]$} $endpoint]} \
            "B2 CDC crossing uses a segmented data-pin endpoint: $endpoint"
        assert_true {[regexp {_reg(\[[0-9]+\])?$} $endpoint]} \
            "B2 CDC endpoint is not an exact register cell: $endpoint"
    }
}

foreach mode {missing_bit missing_active reset_missing} {
    set negative [run_constraint_fixture $constraint_path $mode]
    assert_true {[dict get $negative code] == 1} \
        "$mode B2 CDC cardinality fixture did not fail closed"
}

set producer_source [read_text $producer_path]
foreach required {
    {ASYNC_REG = "TRUE"}
    {SHREG_EXTRACT = "NO"}
    {(* KEEP = "TRUE" *) reg producer_active_reg;}
    {sample_valid_reg && sample_ready}
    {command_capture_pending_src}
    {command_overwrite_error_aclk}
} {
    assert_true {[string first $required $producer_source] >= 0} \
        "B2 producer source lacks token: $required"
}

puts {PRODUCTION_PROFILE_DEFAULT=SAFE_INERT}
puts {BOARD_TEST_PROFILE_REQUIRES_EXPLICIT_SELECTION=YES}
puts {PRODUCTION_RTL_SOURCE_COUNT=21}
puts {PRODUCTION_XDC_SOURCE_COUNT=2}
puts {B1_TEST_PROFILE_TOPOLOGY_LEAKAGE=0}
puts {B2_RUNTIME_PROFILE_DISPATCH=PASS}
puts {B2_DISTINCT_ADC_SOURCE_CLOCK=PASS_STATIC}
puts {B2_SOURCE_DOMAIN_HANDSHAKE_OBSERVABILITY=PASS_STATIC}
puts {STAGE2I_B_DUAL_PROFILE_STATIC_TESTS=PASS}
