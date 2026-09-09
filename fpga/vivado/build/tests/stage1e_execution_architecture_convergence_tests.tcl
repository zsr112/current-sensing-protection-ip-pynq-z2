set test_dir [file dirname [file normalize [info script]]]
set build_root [file dirname $test_dir]
source [file join $build_root lib stage1e_vivado_runtime_contract_v2.tcl]
source [file join $test_dir fixtures stage1e_vivado_command_model_v2.tcl]
source [file join $build_root runtime runner stage1e_production_vivado_runner_v2.tcl]
source [file join $build_root runtime collector stage1e_production_vivado_collector_v2.tcl]

set assertions 0
proc assert_true {value label} {
    global assertions
    incr assertions
    if {!$value} { error "$label failed" }
}
proc assert_equal {expected actual label} {
    global assertions
    incr assertions
    if {$expected ne $actual} { error "$label: expected '$expected', observed '$actual'" }
}
proc assert_error {script label} {
    global assertions
    incr assertions
    if {![catch {uplevel 1 $script}]} { error "$label did not fail closed" }
}

proc isolated_file_digest {canonical_path input_path system_root_mode system_root_value exec_mode exec_output} {
    set system_root_exists [info exists ::env(SystemRoot)]
    if {$system_root_exists} { set system_root_saved $::env(SystemRoot) }
    set child [interp create]
    set status [catch {
        interp eval $child [list source $canonical_path]
        if {$system_root_mode eq {unset}} {
            interp eval $child {unset -nocomplain ::env(SystemRoot)}
        } else {
            interp eval $child [list set ::env(SystemRoot) $system_root_value]
        }
        if {$exec_mode ne {native}} {
            interp eval $child {rename ::exec ::stage1e_test_native_exec}
            if {$exec_mode eq {failure}} {
                interp eval $child [list proc ::exec args \
                    [list return -code error -errorcode {STAGE1E TEST EXEC} $exec_output]]
            } else {
                interp eval $child [list proc ::exec args [list return $exec_output]]
            }
        }
        interp eval $child [list ::stage1e::canonical_json_v1::digest_file $input_path]
    } result options]
    catch {interp delete $child}
    if {$system_root_exists} {
        set ::env(SystemRoot) $system_root_saved
    } else {
        unset -nocomplain ::env(SystemRoot)
    }
    return [dict create status $status result $result options $options]
}

proc require_invariant {value label} {
    if {!$value} { error "$label failed" }
}

proc require_error_code {expected_code script label} {
    set status [catch {uplevel 1 $script} reason options]
    if {!$status} { error "$label did not fail closed" }
    set expected [list STAGE1E EXECUTION RUNNER_V2 $expected_code]
    if {![dict exists $options -errorcode] || [dict get $options -errorcode] ne $expected} {
        error "$label: expected error code '$expected', observed '[dict get $options -errorcode]' ($reason)"
    }
}

proc json_node_to_native {node} {
    set type [::stage1e::canonical_json_v1::node_type $node]
    set value [::stage1e::canonical_json_v1::node_value $node]
    switch -- $type {
        object {
            set result {}
            foreach {key child} $value {
                dict set result $key [json_node_to_native $child]
            }
            return $result
        }
        array {
            set result {}
            foreach child $value { lappend result [json_node_to_native $child] }
            return $result
        }
        default { return $value }
    }
}

set runner_path [file join $build_root runtime runner stage1e_production_vivado_runner_v2.tcl]
set channel [open $runner_path r]
fconfigure $channel -encoding utf-8 -translation lf
set runner_source [read $channel]
close $channel

foreach procedure {
    ::stage1e::production_vivado_runner_v2::_file_identity
    ::stage1e::production_vivado_observer_v2::_file_identity
    ::stage1e::production_vivado_collector_v2::_artifact_record
    ::stage1e::production_vivado_collector_v2::_append_attempt
} {
    set body [info body $procedure]
    assert_true \
        [expr {[string first {::stage1e::canonical_json_v1::digest_file} $body] >= 0}] \
        "$procedure delegates file hashing to digest_file"
    assert_true [expr {[string first {[read } $body] < 0}] \
        "$procedure does not read complete hashed-file contents"
}
foreach procedure {
    ::stage1e::production_vivado_collector_v2::_artifact_record
    ::stage1e::production_vivado_collector_v2::_append_attempt
} {
    assert_true [expr {[string first {[file size } [info body $procedure]] >= 0}] \
        "$procedure obtains byte counts from file size"
}
assert_true \
    [expr {[string first {[file size } \
        [info body ::stage1e::production_vivado_runner_v2::_file_size]] >= 0}] \
    {Runner _file_size remains based on file size}

require_invariant \
    [expr {![llength [info procs ::stage1e::production_vivado_runner_v2::create_project]]}] \
    {Runner namespace excludes create_project helper}
require_invariant \
    [expr {[llength [info procs ::stage1e::production_vivado_runner_v2::create_build_project]] == 1}] \
    {Runner namespace exposes create_build_project helper}

set global_create_calls {}
set unqualified_create_calls {}
set global_close_calls {}
set unqualified_close_calls {}
set source_lines [split $runner_source \n]
set continuation_character [format %c 92]
for {set index 0} {$index < [llength $source_lines]} {incr index} {
    set line [string trim [lindex $source_lines $index]]
    if {$line eq {} || [string match {#*} $line]} { continue }
    if {[string match {::create_project *} $line]} {
        if {[string index $line end] eq $continuation_character} {
            set line "[string trim [string range $line 0 end-1]] [string trim [lindex $source_lines [incr index]]]"
        }
        lappend global_create_calls $line
    }
    if {[regexp {(^|\[|;)[ \t]*create_project([ \t]|\])} $line]} {
        lappend unqualified_create_calls $line
    }
    if {[string match {::close_project*} $line]} {
        lappend global_close_calls $line
    }
    if {[regexp {(^|\[|;)[ \t]*close_project([ \t]|\]|$)} $line]} {
        lappend unqualified_close_calls $line
    }
}
set expected_global_create_calls [list \
    {::create_project stage1e_ip_packaging $package_project -part [dict get $context part]} \
    {::create_project $project_name $project_dir -part [dict get $context part]}]
require_invariant \
    [expr {$global_create_calls eq $expected_global_create_calls}] \
    {Exact global create_project call inventory}
require_invariant \
    [expr {![llength $unqualified_create_calls]}] \
    {No executable unqualified create_project call}
require_invariant \
    [expr {[llength $global_close_calls] == 2 && ![llength $unqualified_close_calls]}] \
    {All project closure calls are global}
require_invariant \
    [expr {![regexp {(?m)^[ \t]*external_pl_ports[ \t]} $runner_source] &&
        [string first {TOPOLOGY_EXTERNAL_PORT} $runner_source] < 0 &&
        [string first {set scalar_ports [get_bd_ports -quiet]} $runner_source] < 0}] \
    {Original zero-external-port assumption is absent}

set selected_vivado_commands {
    create_project close_project open_project create_bd_design
    validate_bd_design save_bd_design generate_target make_wrapper
    launch_runs wait_on_run open_run write_bitstream write_hw_platform
}
set colliding_helpers {}
foreach helper [info procs ::stage1e::production_vivado_runner_v2::*] {
    set tail [namespace tail $helper]
    if {[lsearch -exact $selected_vivado_commands $tail] >= 0} {
        lappend colliding_helpers $tail
    }
}
require_invariant \
    [expr {![llength $colliding_helpers]}] \
    {Runner helper names do not collide with selected Vivado commands}

set command_probe "stage1e_command_probe_[pid]_[clock clicks]"
set local_probe "::stage1e::production_vivado_runner_v2::$command_probe"
set global_probe "::$command_probe"
proc $local_probe {} { return LOCAL_ONLY }
set probe_failure [catch {
    set local_status [catch {
        ::stage1e::production_vivado_runner_v2::_require_command $command_probe
    } local_reason local_options]
    require_invariant $local_status \
        {Namespace-local-only command is rejected}
    require_invariant \
        [expr {[dict get $local_options -errorcode] eq \
            {STAGE1E EXECUTION RUNNER_V2 VIVADO_COMMAND_UNAVAILABLE}}] \
        {Namespace-local-only command preserves error domain}
    require_invariant \
        [expr {[string first $global_probe $local_reason] >= 0}] \
        {Unavailable command reports global identity}

    proc $global_probe {} { return GLOBAL }
    require_invariant \
        [expr {[::stage1e::production_vivado_runner_v2::_require_command \
            $command_probe] eq $global_probe}] \
        {Unqualified capability check resolves global command}
    require_invariant \
        [expr {[::stage1e::production_vivado_runner_v2::_require_command \
            $global_probe] eq $global_probe}] \
        {Fully qualified capability check remains global}
} probe_reason probe_options]
catch {rename $local_probe {}}
catch {rename $global_probe {}}
if {$probe_failure} { return -options $probe_options $probe_reason }

set temporary [file normalize [file join $test_dir ".stage1e-mainline-[pid]-[clock clicks]"]]
set failure [catch {
    set real_properties [::stage1e::vivado_runtime_contract_v2::real_property_projection]
    set fixture_properties [::stage1e::vivado_command_model_v2::property_set]
    assert_equal [lsort -dictionary $real_properties] [lsort -dictionary $fixture_properties] {Fixture-to-real Vivado property parity}
    ::stage1e::vivado_runtime_contract_v2::validate_property_inventory $fixture_properties 1
    assert_error {::stage1e::vivado_runtime_contract_v2::validate_property_inventory [lrange $fixture_properties 1 end] 1} {Missing captured property}
    assert_error {::stage1e::vivado_runtime_contract_v2::validate_property_inventory [::stage1e::vivado_command_model_v2::with_synthetic_property $fixture_properties] 1} {Synthetic property}

    set model [::stage1e::vivado_command_model_v2::new]
    set state [::stage1e::production_vivado_runner_v2::new_phase_state]
    set route_snapshot {}
    foreach phase {opt_design place_design route_design} {
        set transition [::stage1e::vivado_command_model_v2::launch_to $model $phase]
        set model [dict get $transition model]
        set snapshot [dict get $transition snapshot]
        set phase_result [::stage1e::production_vivado_runner_v2::run_fixture $state $fixture_properties $snapshot]
        set state [dict get $phase_result phase_state]
        assert_equal PROCEED [dict get $phase_result observation action] "$phase completion"
        set route_snapshot $snapshot
    }
    assert_equal ROUTED [dict get $state terminal_state] {Routed phase state}
    set bad_status $route_snapshot
    dict set bad_status run_status {Not started route_design}
    assert_equal BLOCK [dict get [::stage1e::vivado_runtime_contract_v2::evaluate_phase_completion $bad_status] action] {Wrong run status blocks}
    assert_equal ROUTE_DESIGN_FAILED_TIMING \
        [::stage1e::vivado_runtime_contract_v2::normalize_status \
            {route_design Complete, Failed Timing!}] \
        {Failed-timing status normalization}
    set failed_timing [::stage1e::vivado_command_model_v2::with_failed_timing \
        $route_snapshot]
    set failed_timing_result \
        [::stage1e::vivado_runtime_contract_v2::evaluate_phase_completion \
            $failed_timing]
    assert_equal BLOCK [dict get $failed_timing_result action] \
        {Failed timing blocks route completion}
    assert_equal ROUTE_DESIGN_FAILED_TIMING \
        [lindex [dict get $failed_timing_result errorcode] end] \
        {Failed timing preserves an explicit blocking code}
    assert_true [expr {[string first {ROUTE_DESIGN_FAILED_TIMING} \
        [dict get $failed_timing_result reason]] >= 0}] \
        {Failed timing preserves an explicit blocking reason}
    set bad_checkpoint $route_snapshot
    dict set bad_checkpoint checkpoint_identity SELF_ASSERTED
    assert_equal BLOCK [dict get [::stage1e::vivado_runtime_contract_v2::evaluate_phase_completion $bad_checkpoint] action] {Non-hash checkpoint identity blocks}
    set forbidden $route_snapshot
    dict set forbidden forbidden_operations {phys_opt_design}
    assert_equal BLOCK [dict get [::stage1e::vivado_runtime_contract_v2::evaluate_phase_completion $forbidden] action] {Forbidden operation blocks}

    set topology [::stage1e::production_vivado_runner_v2::topology_contract]
    assert_true [::stage1e::production_vivado_runner_v2::validate_topology_fixture $topology] {Exact Stage 1E topology fixture}
    set execution_contract_path \
        [file join $build_root config stage1e_execution_contract_v1.json]
    set execution_contract_bytes \
        [::stage1e::canonical_json_v1::read_file_bytes $execution_contract_path]
    set execution_contract [json_node_to_native \
        [::stage1e::canonical_json_v1::parse_bytes $execution_contract_bytes]]
    set machine_topology [dict get $execution_contract topology]
    require_invariant [expr {
        [lsort -dictionary [dict get $machine_topology cell_inventory]] eq
            [lsort -dictionary [dict get $topology cell_inventory]] &&
        [dict get $machine_topology cell_vlnvs] eq
            [dict get $topology cell_vlnvs] &&
        [dict get $machine_topology system_ila probes] eq
            [dict get $topology system_ila probes]}] \
        {Machine contract cell, VLNV, and exact ILA topology converge with runtime}
    require_invariant [expr {
        [dict get $machine_topology adc_source_clock sink] eq
            [dict get $topology adc_source_clock sink] &&
        [dict get $machine_topology controlled_stimulus profile] eq
            [dict get $topology controlled_stimulus profile] &&
        [dict get $machine_topology controlled_stimulus ready_source] eq
            [dict get $topology controlled_stimulus ready_source] &&
        [dict get $machine_topology controlled_stimulus ready_probe] eq
            [dict get $topology controlled_stimulus ready_probe] &&
        [dict get $machine_topology controlled_stimulus source_acceptance_claimed] ==
            [dict get $topology controlled_stimulus source_acceptance_claimed] &&
        [dict get $machine_topology controlled_stimulus fault_stimulus_claimed] ==
            [dict get $topology controlled_stimulus fault_stimulus_claimed]}] \
        {Machine contract async ADC pins and controlled-stimulus semantics converge}
    foreach field {
        profile profile_class production_authority demo_test_only valid_value
        functional_adc_stimulus valid_source_exists ready_consumed
        no_overwrite_when_ready_low transaction_pulse_bounded
    } {
        require_invariant [expr {
            [dict get $machine_topology controlled_stimulus $field] eq
                [dict get $topology controlled_stimulus $field]}] \
            "Machine contract controlled-stimulus field $field converges with runtime"
    }
    foreach field {
        ready_observation_clock_domain adc_src_clock_domain
        destination_clock_domain clocks_identical_in_current_profile
        acceptance_evidence_scope distinct_clock_debug_policy
        direct_async_ready_observation_as_cdc_proof
    } {
        require_invariant [expr {
            [dict get $machine_topology debug_ready_observation $field] eq
                [dict get $topology debug_ready_observation $field]}] \
            "Machine contract ready-observation field $field converges with runtime"
    }
    set execution_contract_text \
        [encoding convertfrom utf-8 $execution_contract_bytes]
    foreach old_pin {
        protection_ip_axi_lite_0/sample_valid
        protection_ip_axi_lite_0/i_ch1
        protection_ip_axi_lite_0/i_ch2
    } {
        require_invariant [expr {[string first $old_pin $execution_contract_text] < 0}] \
            "Machine contract excludes old synchronous pin $old_pin"
    }
    require_invariant [expr {
        [dict get $topology controlled_stimulus profile] eq {SAFE_INERT_EXPLICIT} &&
        [dict get $topology controlled_stimulus profile_class] eq {SAFE_INERT} &&
        ![dict get $topology controlled_stimulus functional_adc_stimulus] &&
        ![dict get $topology controlled_stimulus valid_value] &&
        ![dict get $topology controlled_stimulus source_acceptance_claimed] &&
        ![dict get $topology controlled_stimulus fault_stimulus_claimed] &&
        [dict get $topology controlled_stimulus ready_source] eq
            {protection_ip_axi_lite_0/adc_sample_ready} &&
        [dict get $topology controlled_stimulus ready_probe] eq
            {system_ila_stage2b_0/probe11}}] \
        {Runtime topology publishes safe inert profile and ready evidence path}
    require_invariant [expr {
        [dict get $topology debug_ready_observation ready_observation_clock_domain] eq
            {ACLK} &&
        [dict get $topology debug_ready_observation adc_src_clock_domain] eq
            {FCLK_CLK0} &&
        [dict get $topology debug_ready_observation destination_clock_domain] eq
            {FCLK_CLK0} &&
        [dict get $topology debug_ready_observation clocks_identical_in_current_profile] &&
        [dict get $topology debug_ready_observation acceptance_evidence_scope] eq
            {CURRENT_IDENTICAL_CLOCKS_ONLY} &&
        [dict get $topology debug_ready_observation distinct_clock_debug_policy] eq
            {SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION} &&
        ![dict get $topology debug_ready_observation \
            direct_async_ready_observation_as_cdc_proof]}] \
        {Runtime topology bounds ACLK ILA readiness to current identical clocks}
    set bad_profile_topology $topology
    dict set bad_profile_topology controlled_stimulus profile_class \
        FUNCTIONAL_READY_AWARE
    assert_error {
        ::stage1e::production_vivado_runner_v2::validate_topology_fixture \
            $bad_profile_topology
    } {Runtime topology rejects a divergent production profile class}
    set bad_debug_topology $topology
    dict set bad_debug_topology debug_ready_observation \
        distinct_clock_debug_policy DIRECT_ASYNC_READY_PROBE
    assert_error {
        ::stage1e::production_vivado_runner_v2::validate_topology_fixture \
            $bad_debug_topology
    } {Runtime topology rejects direct asynchronous ready observation policy}
    require_invariant [expr {
        [dict get $topology cell_vlnvs protection_ip_axi_lite_0] eq
            {zsr112.local:protection:protection_ip_axi_lite:0.3} &&
        [dict get $topology system_ila properties C_NUM_OF_PROBES] == 12}] \
        {Runtime topology publishes IP v0.3 and exact 12-probe ILA}

    set required_platform_ports [dict create \
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
    set topology_fields [dict keys $topology]
    require_invariant \
        [expr {[lsearch -exact $topology_fields external_interfaces] >= 0 &&
            [lsearch -exact $topology_fields platform_external_scalar_ports] >= 0 &&
            [lsearch -exact $topology_fields custom_external_pl_ports] >= 0 &&
            [lsearch -exact $topology_fields external_pl_ports] < 0}] \
        {Topology fixture exposes distinct platform and custom port fields}
    require_invariant \
        [expr {[dict get $topology external_interfaces] eq {DDR FIXED_IO} &&
            [dict get $topology platform_external_scalar_ports] eq $required_platform_ports &&
            [dict get $topology custom_external_pl_ports] eq {}}] \
        {Topology fixture binds the exact platform boundary}

    set platform_interfaces [dict get $topology external_interfaces]
    set platform_ports [dict get $topology platform_external_scalar_ports]
    set custom_ports [dict get $topology custom_external_pl_ports]
    require_invariant \
        [::stage1e::production_vivado_runner_v2::_validate_platform_interface_inventory \
            $platform_interfaces {DDR FIXED_IO}] \
        {Exact two logical platform interfaces pass}
    require_invariant \
        [::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory \
            $platform_ports $required_platform_ports $custom_ports] \
        {Exact 21 physical platform ports pass}

    require_error_code TOPOLOGY_PLATFORM_PORT_INVENTORY \
        {::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory \
            {} $required_platform_ports $custom_ports} \
        {Empty physical platform port inventory}
    set bad_platform_ports [dict remove $platform_ports DDR_addr]
    require_error_code TOPOLOGY_PLATFORM_PORT_INVENTORY \
        {::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory \
            $bad_platform_ports $required_platform_ports $custom_ports} \
        {Missing DDR_addr}
    set bad_platform_ports [dict remove $platform_ports FIXED_IO_mio]
    require_error_code TOPOLOGY_PLATFORM_PORT_INVENTORY \
        {::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory \
            $bad_platform_ports $required_platform_ports $custom_ports} \
        {Missing FIXED_IO_mio}
    set bad_platform_ports $platform_ports
    dict set bad_platform_ports pwm_out 1
    require_error_code TOPOLOGY_CUSTOM_EXTERNAL_PORT \
        {::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory \
            $bad_platform_ports $required_platform_ports $custom_ports} \
        {Extra pwm_out}
    set bad_platform_ports $platform_ports
    dict set bad_platform_ports i_ch1 12
    require_error_code TOPOLOGY_CUSTOM_EXTERNAL_PORT \
        {::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory \
            $bad_platform_ports $required_platform_ports $custom_ports} \
        {Extra i_ch1}
    set bad_platform_ports [dict remove $platform_ports DDR_addr]
    dict set bad_platform_ports DDR_address 15
    require_error_code TOPOLOGY_PLATFORM_PORT_INVENTORY \
        {::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory \
            $bad_platform_ports $required_platform_ports $custom_ports} \
        {Renamed platform port}
    set duplicate_platform_ports [concat $platform_ports {DDR_addr 15}]
    require_error_code TOPOLOGY_PLATFORM_PORT_INVENTORY \
        {::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory \
            $duplicate_platform_ports $required_platform_ports $custom_ports} \
        {Duplicate platform port}
    foreach {name wrong_width} {DDR_addr 14 DDR_dq 31 FIXED_IO_mio 53} {
        set bad_platform_ports $platform_ports
        dict set bad_platform_ports $name $wrong_width
        require_error_code TOPOLOGY_PLATFORM_PORT_WIDTH \
            {::stage1e::production_vivado_runner_v2::_validate_platform_port_inventory \
                $bad_platform_ports $required_platform_ports $custom_ports} \
            "Wrong $name width"
    }

    require_error_code TOPOLOGY_PLATFORM_INTERFACE_INVENTORY \
        {::stage1e::production_vivado_runner_v2::_validate_platform_interface_inventory \
            {DDR FIXED_IO EXTRA} {DDR FIXED_IO}} \
        {Extra logical interface}
    require_error_code TOPOLOGY_PLATFORM_INTERFACE_INVENTORY \
        {::stage1e::production_vivado_runner_v2::_validate_platform_interface_inventory \
            {FIXED_IO} {DDR FIXED_IO}} \
        {Missing DDR logical interface}
    require_error_code TOPOLOGY_PLATFORM_INTERFACE_INVENTORY \
        {::stage1e::production_vivado_runner_v2::_validate_platform_interface_inventory \
            {DDR} {DDR FIXED_IO}} \
        {Missing FIXED_IO logical interface}

    set ::stage1e_width_probe_ports [dict create \
        scalar {/scalar} vector {/vector} malformed {/malformed} duplicate {/duplicate /duplicate_copy}]
    set ::stage1e_width_probe_bounds [dict create \
        /scalar [dict create LEFT {} RIGHT {}] \
        /vector [dict create LEFT 0 RIGHT 14] \
        /malformed [dict create LEFT bad RIGHT 0]]
    proc ::stage1e::production_vivado_runner_v2::get_bd_ports {args} {
        set name [lindex $args end]
        if {![dict exists $::stage1e_width_probe_ports $name]} { return {} }
        return [dict get $::stage1e_width_probe_ports $name]
    }
    proc ::stage1e::production_vivado_runner_v2::get_property {property object} {
        return [dict get $::stage1e_width_probe_bounds $object $property]
    }
    set width_probe_failure [catch {
        require_invariant \
            [expr {[::stage1e::production_vivado_runner_v2::_bd_external_port_width scalar] == 1}] \
            {Empty LEFT and RIGHT produce scalar width one}
        require_invariant \
            [expr {[::stage1e::production_vivado_runner_v2::_bd_external_port_width vector] == 15}] \
            {Absolute vector bounds produce exact width}
        require_error_code TOPOLOGY_PLATFORM_PORT_WIDTH \
            {::stage1e::production_vivado_runner_v2::_bd_external_port_width malformed} \
            {Malformed vector bounds}
        require_error_code TOPOLOGY_PLATFORM_PORT_INVENTORY \
            {::stage1e::production_vivado_runner_v2::_bd_external_port_width missing} \
            {Missing physical platform port}
        require_error_code TOPOLOGY_PLATFORM_PORT_INVENTORY \
            {::stage1e::production_vivado_runner_v2::_bd_external_port_width duplicate} \
            {Nonunique physical platform port}
    } width_probe_reason width_probe_options]
    rename ::stage1e::production_vivado_runner_v2::get_bd_ports {}
    rename ::stage1e::production_vivado_runner_v2::get_property {}
    unset ::stage1e_width_probe_ports ::stage1e_width_probe_bounds
    if {$width_probe_failure} {
        return -options $width_probe_options $width_probe_reason
    }

    file mkdir $temporary
    set canonical_path [file join $build_root lib stage1e_runtime_canonical_json_v1.tcl]
    set hash_root [file join $temporary {hash fixtures with spaces}]
    file mkdir $hash_root
    set known_sha256 ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    set empty_sha256 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    set known_bytes [encoding convertto utf-8 abc]
    assert_equal $known_sha256 \
        [::stage1e::canonical_json_v1::digest_bytes $known_bytes] \
        {Existing digest_bytes abc vector remains unchanged}
    assert_equal $empty_sha256 \
        [::stage1e::canonical_json_v1::digest_bytes {}] \
        {Existing digest_bytes empty vector remains unchanged}

    set known_path [file join $hash_root {known vector.bin}]
    set channel [open $known_path {WRONLY CREAT EXCL}]
    fconfigure $channel -translation binary -encoding binary
    puts -nonewline $channel $known_bytes
    close $channel
    assert_true [expr {[string first { } $known_path] >= 0}] \
        {Native file-hash fixture path contains spaces}
    set known_file_digest [::stage1e::canonical_json_v1::digest_file $known_path]
    assert_equal $known_sha256 $known_file_digest {Known regular-file SHA-256 vector}
    assert_true [regexp {^[0-9a-f]{64}$} $known_file_digest] \
        {Native file digest is lowercase canonical SHA-256}
    assert_equal $known_sha256 \
        [::stage1e::production_vivado_runner_v2::_file_identity $known_path] \
        {Runner delegates path-with-spaces identity to digest_file}
    assert_equal $known_sha256 \
        [::stage1e::production_vivado_observer_v2::_file_identity $known_path] \
        {Observer delegates existing checkpoint identity to digest_file}
    assert_equal MISSING \
        [::stage1e::production_vivado_observer_v2::_file_identity \
            [file join $hash_root {missing checkpoint.dcp}]] \
        {Observer preserves MISSING identity behavior}
    assert_error \
        [list ::stage1e::canonical_json_v1::digest_file \
            [file join $hash_root {missing vector.bin}]] \
        {Missing native file-hash input}
    assert_error \
        [list ::stage1e::canonical_json_v1::digest_file {}] \
        {Empty native file-hash input path}

    set empty_path [file join $hash_root {empty vector.bin}]
    set channel [open $empty_path {WRONLY CREAT EXCL}]
    close $channel
    set empty_digest_result \
        [isolated_file_digest $canonical_path $empty_path set $::env(SystemRoot) \
            success "$empty_sha256\n"]
    assert_equal 0 [dict get $empty_digest_result status] \
        {Empty-file digest accepts one strict native-provider result line}
    assert_equal $empty_sha256 [dict get $empty_digest_result result] \
        {Empty-file SHA-256 vector}

    set binary_bytes [binary format H* {00ff1080007f}]
    set binary_path [file join $hash_root {binary vector.bin}]
    set channel [open $binary_path {WRONLY CREAT EXCL}]
    fconfigure $channel -translation binary -encoding binary
    puts -nonewline $channel $binary_bytes
    close $channel
    assert_equal [string length $binary_bytes] [file size $binary_path] \
        {Binary file containing zero and non-UTF-8 bytes has exact size}
    set binary_digest [::stage1e::canonical_json_v1::digest_file $binary_path]
    assert_equal [::stage1e::canonical_json_v1::digest_bytes $binary_bytes] \
        $binary_digest {Binary native digest equals unchanged digest_bytes vector}

    set saved_system_root $::env(SystemRoot)
    set fake_system_root [file join $hash_root {provider absent}]
    file mkdir $fake_system_root
    set missing_system_root_result \
        [isolated_file_digest $canonical_path $known_path unset {} native {}]
    set absent_provider_result \
        [isolated_file_digest $canonical_path $known_path set $fake_system_root native {}]
    set command_failure_result \
        [isolated_file_digest $canonical_path $known_path set $saved_system_root \
            failure $known_sha256]
    set no_digest_result \
        [isolated_file_digest $canonical_path $known_path set $saved_system_root \
            success {CertUtil output contains no digest line}]
    set duplicate_digest_result \
        [isolated_file_digest $canonical_path $known_path set $saved_system_root \
            success "$known_sha256\n$known_sha256\n"]
    set shortened_digest_result \
        [isolated_file_digest $canonical_path $known_path set $saved_system_root \
            success "[string repeat a 63]\n"]
    set nonhex_digest [string replace $known_sha256 31 31 g]
    set nonhex_digest_result \
        [isolated_file_digest $canonical_path $known_path set $saved_system_root \
            success "$nonhex_digest\n"]
    set spaced_digest [join [regexp -all -inline {..} $known_sha256] { }]
    set spaced_digest_result \
        [isolated_file_digest $canonical_path $known_path set $saved_system_root \
            success "$spaced_digest\n"]
    set tabbed_digest [join [regexp -all -inline {..} $known_sha256] "\t"]
    set tabbed_digest_result \
        [isolated_file_digest $canonical_path $known_path set $saved_system_root \
            success "$tabbed_digest\n"]
    foreach {label result} [list \
        {Missing SystemRoot fails closed} $missing_system_root_result \
        {Fixed certutil provider path absent fails closed} $absent_provider_result \
        {Certutil command failure is a controlled digest error} $command_failure_result \
        {Certutil output with no digest line fails closed} $no_digest_result \
        {Certutil output with two digest lines fails closed} $duplicate_digest_result \
        {Shortened digest line fails closed} $shortened_digest_result \
        {Non-hexadecimal digest line fails closed} $nonhex_digest_result \
        {Internally spaced digest line fails closed} $spaced_digest_result \
        {Internally tabbed digest line fails closed} $tabbed_digest_result] {
        assert_true \
            [expr {[dict get $result status] &&
                [dict exists [dict get $result options] -errorcode] &&
                [dict get [dict get $result options] -errorcode] eq
                    {STAGE1E JSON FILE_DIGEST}}] $label
    }
    set uppercase_digest_result \
        [isolated_file_digest $canonical_path $known_path set $saved_system_root \
            success "CertUtil header\n[string toupper $known_sha256]\nCertUtil footer\n"]
    assert_equal 0 [dict get $uppercase_digest_result status] \
        {Uppercase valid certutil digest line is accepted}
    assert_equal $known_sha256 [dict get $uppercase_digest_result result] \
        {Uppercase valid certutil digest is normalized to lowercase}
    assert_true \
        [expr {[llength [info commands ::exec]] == 1 && ![llength [info procs ::exec]]}] \
        {Synthetic provider tests never rename parent interpreter exec}
    assert_equal $saved_system_root $::env(SystemRoot) \
        {Synthetic provider tests restore SystemRoot after every child interpreter}

    set powershell_path [file normalize [file join $::env(SystemRoot) System32 \
        WindowsPowerShell v1.0 powershell.exe]]
    set hash_path_environment STAGE1E_NATIVE_FILE_HASH_TEST_PATH
    set hash_path_environment_exists [info exists ::env($hash_path_environment)]
    if {$hash_path_environment_exists} {
        set hash_path_environment_saved $::env($hash_path_environment)
    }
    set ::env($hash_path_environment) [file nativename $binary_path]
    set powershell_command [list $powershell_path -NoLogo -NoProfile -NonInteractive \
        -Command {(Get-FileHash -LiteralPath $env:STAGE1E_NATIVE_FILE_HASH_TEST_PATH -Algorithm SHA256).Hash}]
    set powershell_status [catch {exec {*}$powershell_command 2>@1} powershell_output]
    if {$hash_path_environment_exists} {
        set ::env($hash_path_environment) $hash_path_environment_saved
    } else {
        unset ::env($hash_path_environment)
    }
    assert_equal 0 $powershell_status {Independent PowerShell Get-FileHash exits successfully}
    assert_equal $binary_digest [string tolower [string trim $powershell_output]] \
        {Native file digest equals independent PowerShell Get-FileHash}

    set certutil_path [file normalize \
        [file join $::env(SystemRoot) System32 certutil.exe]]
    set certutil_command [list $certutil_path -hashfile $binary_path SHA256]
    set certutil_status [catch {exec {*}$certutil_command 2>@1} certutil_output]
    assert_equal 0 $certutil_status {Direct fixed-path certutil exits successfully}
    set certutil_candidates {}
    foreach line [split $certutil_output "\n"] {
        set line [string trim $line]
        if {[regexp {^[0-9A-Fa-f]{64}$} $line]} {
            lappend certutil_candidates [string tolower $line]
        }
    }
    assert_equal 1 [llength $certutil_candidates] \
        {Direct fixed-path certutil emits exactly one strict digest line}
    assert_equal $binary_digest [lindex $certutil_candidates 0] \
        {Native file digest equals direct fixed-path certutil}

    set wrapper_declarations {}
    foreach {name width} $required_platform_ports {
        if {$width == 1} {
            lappend wrapper_declarations "    inout wire $name"
        } else {
            lappend wrapper_declarations [format {    inout wire [%d:0] %s} [expr {$width - 1}] $name]
        }
    }
    set wrapper_path [file join $temporary protection_system_wrapper.v]
    set channel [open $wrapper_path {WRONLY CREAT EXCL}]
    puts $channel "module protection_system_wrapper (\n[join $wrapper_declarations ,\n]\n);\nendmodule"
    close $channel
    set wrapper_inventory \
        [::stage1e::production_vivado_runner_v2::_wrapper_module_header_inventory $wrapper_path]
    require_invariant \
        [expr {[dict get $wrapper_inventory ports] eq [dict keys $required_platform_ports]}] \
        {Legal vector declarations yield only wrapper port names}
    require_invariant \
        [::stage1e::production_vivado_runner_v2::_validate_wrapper_port_inventory \
            $wrapper_inventory protection_system_wrapper $required_platform_ports] \
        {Exact wrapper platform-port inventory passes}
    set bad_wrapper_inventory $wrapper_inventory
    dict lappend bad_wrapper_inventory ports pwm_out
    require_error_code TOPOLOGY_WRAPPER_PORT_INVENTORY \
        {::stage1e::production_vivado_runner_v2::_validate_wrapper_port_inventory \
            $bad_wrapper_inventory protection_system_wrapper $required_platform_ports} \
        {Wrapper custom PL port}

    set bad $topology
    dict set bad smartconnect NUM_MI 1
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {NUM_MI one rejected}

    set bad $topology
    set inventory [dict get $bad cell_inventory]
    set position [lsearch -exact $inventory axi_gpio_stage1d_0]
    set inventory [lreplace $inventory $position $position]
    dict set bad cell_inventory $inventory
    dict unset bad cell_vlnvs axi_gpio_stage1d_0
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Missing AXI GPIO rejected}

    set bad $topology
    dict set bad addresses axi_gpio offset 0x41210000
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Wrong AXI GPIO address rejected}

    set bad $topology
    set inventory [dict get $bad cell_inventory]
    set position [lsearch -exact $inventory xlslice_stage1d_ch2]
    dict set bad cell_inventory [lreplace $inventory $position $position]
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Missing slice rejected}

    set bad $topology
    dict set bad controlled_stimulus valid_value 1
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {sample_valid one rejected}

    set bad $topology
    dict set bad system_ila present 0
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Missing System ILA rejected}

    set bad $topology
    set probes [dict get $bad system_ila probes]
    set probe [lindex $probes 2]
    dict set probe width 11
    lset probes 2 $probe
    dict set bad system_ila probes $probes
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Wrong probe width and order rejected}

    set bad $topology
    dict set bad adc_sample_sources adc_sample_ch1 i_ch1_const/dout
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Direct constant current driver rejected}

    set bad $topology
    set probes [dict get $bad system_ila probes]
    set old_pin_probe [lindex $probes 1]
    dict set old_pin_probe source protection_ip_axi_lite_0/sample_valid
    lset probes 1 $old_pin_probe
    dict set bad system_ila probes $probes
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Old synchronous pin fixture rejected}

    set bad $topology
    dict set bad controlled_stimulus source_acceptance_claimed 1
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Safe inert acceptance claim rejected}

    set bad $topology
    dict set bad controlled_stimulus ready_probe system_ila_stage2b_0/probe10
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Wrong ready evidence probe rejected}

    set bad $topology
    dict set bad wrapper_exists 0
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Missing wrapper rejected}

    set bad $topology
    dict set bad project_top wrong_top
    assert_error {::stage1e::production_vivado_runner_v2::validate_topology_fixture $bad} {Wrong synthesis top rejected}

    file mkdir [file join $temporary output reports]
    file mkdir [file join $temporary output artifacts]
    file mkdir [file join $temporary output journal]
    file mkdir [file join $temporary workspace project]
    set context [dict create \
        context_schema_version stage1e-vivado-execution-context-v1 \
        execution_id S1E-TCL-FIXTURE \
        request_identity [string repeat a 64] \
        run_kind ENGINEERING \
        repository_root $temporary \
        vivado_version 2024.1 \
        vivado_build 5076996 \
        workspace_path [file join $temporary workspace] \
        project_path [file join $temporary workspace project fixture.xpr] \
        output_path [file join $temporary output] \
        report_root [file join $temporary output reports] \
        artifact_root [file join $temporary output artifacts] \
        result_path [file join $temporary output vivado_result.json] \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        build_target ARTIFACTS \
        implementation_profile SAFE_INERT \
        source_commit [string repeat a 40] \
        source_tree [string repeat b 40] \
        execution_contract_identity [string repeat c 64] \
        finding_decision_identity NONE \
        project_retention RETAIN \
        process_identity S1E-TCL-FIXTURE \
        project_identity stage1e_S1E-TCL-FIXTURE \
        design_identity protection_system \
        phase_journal_path [file join $temporary output journal runner-phase.tsv]]
    ::stage1e::production_vivado_runner_v2::_validate_context $context
    set unknown_context $context
    dict set unknown_context unknown_field x
    assert_error {::stage1e::production_vivado_runner_v2::_validate_context $unknown_context} {Unknown named context field}
    set missing_context $context
    dict unset missing_context phase_journal_path
    assert_error {::stage1e::production_vivado_runner_v2::_validate_context $missing_context} {Missing named context field}
    set formal_context $context
    dict set formal_context run_kind FORMAL
    assert_error {::stage1e::production_vivado_runner_v2::_validate_context $formal_context} {FORMAL runner defense in depth}

    ::stage1e::production_vivado_runner_v2::initialize_phase_journal $context
    ::stage1e::production_vivado_runner_v2::append_phase_journal $context ATTEMPT OPT_DESIGN impl_1 {Not started} 0 NONE NONE "detail with\ttab and\nline"
    ::stage1e::production_vivado_runner_v2::append_phase_journal $context COMPLETED OPT_DESIGN impl_1 {Not started place_design} 50 place_design [string repeat d 64] {checkpoint complete}
    set channel [open [dict get $context phase_journal_path] r]
    fconfigure $channel -encoding utf-8 -translation lf
    set journal_text [read $channel]
    close $channel
    set journal_lines [split [string trimright $journal_text \n] \n]
    assert_equal 3 [llength $journal_lines] {Phase journal physical line count}
    foreach line $journal_lines { assert_equal 11 [llength [split $line \t]] {Phase journal exact columns} }
    assert_equal ATTEMPT [lindex [split [lindex $journal_lines 1] \t] 2] {Phase journal ATTEMPT chronology}
    assert_equal COMPLETED [lindex [split [lindex $journal_lines 2] \t] 2] {Phase journal COMPLETED chronology}
    assert_true [expr {[string first "detail with\\ttab and\\nline" $journal_text] >= 0}] {Phase journal detail escaping}
    set journal_record [::stage1e::production_vivado_runner_v2::_phase_journal_record $context]
    assert_equal {bytes path sha256} [lsort -dictionary [dict keys $journal_record]] \
        {Runner journal result field names remain unchanged}
    assert_equal [file size [dict get $context phase_journal_path]] \
        [dict get $journal_record bytes] {Runner journal byte count uses exact file size}
    assert_equal [::stage1e::canonical_json_v1::digest_file \
        [dict get $context phase_journal_path]] [dict get $journal_record sha256] \
        {Runner journal SHA-256 field remains exact}

    set expected_report_roles {
        TIMING_SUMMARY TIMING_PATH_GROUPS CLOCK_INTERACTION CLOCKS_GENERATED_CLOCKS
        CONSTRAINT_COVERAGE CHECK_TIMING TIMING_EXCEPTION_SOURCE CONDITIONAL_BUS_SKEW
        UTILIZATION DRC METHODOLOGY CDC MESSAGE_SOURCE
    }
    assert_equal $expected_report_roles \
        [::stage1e::production_vivado_collector_v2::report_roles] \
        {All thirteen report roles remain present in exact order}

    namespace eval ::stage1e_report_command_test { variable calls {} }
    proc ::report_exceptions args {
        lappend ::stage1e_report_command_test::calls \
            [linsert $args 0 report_exceptions]
    }
    set timing_exception_path [file join $temporary timing-exception-source.rpt]
    set constraint_coverage_path [file join $temporary constraint-coverage.rpt]
    ::stage1e::production_vivado_collector_v2::_invoke_fixed_report \
        TIMING_EXCEPTION_SOURCE $timing_exception_path
    ::stage1e::production_vivado_collector_v2::_invoke_fixed_report \
        CONSTRAINT_COVERAGE $constraint_coverage_path
    set report_exception_calls $::stage1e_report_command_test::calls
    rename ::report_exceptions {}
    assert_equal [list report_exceptions -file $timing_exception_path] \
        [lindex $report_exception_calls 0] \
        {Timing-exception source invokes the supported exact report command}
    assert_true [expr {[lsearch -exact \
        [lindex $report_exception_calls 0] -all] < 0}] \
        {Timing-exception source excludes unsupported -all}
    assert_equal [list report_exceptions -coverage -file \
        $constraint_coverage_path] [lindex $report_exception_calls 1] \
        {Constraint coverage retains the exact coverage report command}
    assert_true [expr {[lindex $report_exception_calls 0] ne \
        [lindex $report_exception_calls 1]}] \
        {Timing-exception source and constraint coverage remain distinct}
    set fixed_report_body \
        [info body ::stage1e::production_vivado_collector_v2::_invoke_fixed_report]
    assert_true [expr {
        [string first {help } $fixed_report_body] < 0 &&
        [string first {info commands} $fixed_report_body] < 0 &&
        [string first {catch } $fixed_report_body] < 0 &&
        [string first {fallback} [string tolower $fixed_report_body]] < 0}] \
        {Fixed reports retain no fallback or option-discovery logic}

    set paths {}
    set reports {}
    foreach role [::stage1e::production_vivado_collector_v2::report_roles] {
        dict set paths $role [file join [dict get $context report_root] "[string tolower $role].rpt"]
        dict set reports $role "fixture report $role\n"
    }
    set binding [dict create \
        implementation_profile [dict get $context implementation_profile] \
        execution_id [dict get $context execution_id] \
        source_commit [dict get $context source_commit] \
        source_tree [dict get $context source_tree] \
        project_identity [dict get $context project_identity] \
        design_identity [dict get $context design_identity]]
    set collector_request [dict create \
        report_root [dict get $context report_root] \
        implementation_profile [dict get $context implementation_profile] \
        execution_id [dict get $context execution_id] \
        source_commit [dict get $context source_commit] \
        source_tree [dict get $context source_tree] \
        project_identity [dict get $context project_identity] \
        design_identity [dict get $context design_identity] \
        run_identity impl_1 process_identity [dict get $context process_identity] \
        role_output_paths $paths]
    set failed_report_root [file join $temporary failed-report-collection]
    file mkdir $failed_report_root
    set failed_report_paths {}
    foreach role $expected_report_roles {
        dict set failed_report_paths $role \
            [file join $failed_report_root "[string tolower $role].rpt"]
    }
    set failed_collector_request [dict replace $collector_request \
        report_root $failed_report_root role_output_paths $failed_report_paths]
    proc ::report_timing_summary args { error {synthetic report failure} }
    set failed_collection \
        [::stage1e::production_vivado_collector_v2::collect_live \
            $failed_collector_request]
    rename ::report_timing_summary {}
    assert_true [expr {
        [dict get $failed_collection action] eq {BLOCK} &&
        [llength [dict get $failed_collection attempts]] == 1 &&
        [dict get [lindex [dict get $failed_collection attempts] 0] state] eq
            {FAILED}}] {Collector report-command failure remains fail-closed}

    set collected [::stage1e::production_vivado_collector_v2::collect_fixture $collector_request $reports]
    assert_equal PROCEED [dict get $collected action] {Collector fixture result}
    assert_equal 13 [llength [dict get $collected attempts]] {Exact report-role inventory}
    set first_attempt [lindex [dict get $collected attempts] 0]
    assert_equal {bytes ordinal path reason role sha256 state} \
        [lsort -dictionary [dict keys $first_attempt]] \
        {Collector report-attempt result field names remain unchanged}
    assert_equal [file size [dict get $first_attempt path]] \
        [dict get $first_attempt bytes] {Collector report-attempt byte count uses exact file size}
    assert_equal [::stage1e::canonical_json_v1::digest_file [dict get $first_attempt path]] \
        [dict get $first_attempt sha256] {Collector report-attempt SHA-256 remains exact}
    set ledger_path \
        [::stage1e::production_vivado_collector_v2::_attempt_ledger_path $collector_request]
    set channel [open $ledger_path r]
    fconfigure $channel -encoding utf-8 -translation lf
    set ledger_header [gets $channel]
    close $channel
    assert_equal "ordinal\treport_role\tstate\tpath\tbytes\tsha256\treason" \
        $ledger_header {Report-attempt ledger columns remain unchanged}
    set missing_attempt [::stage1e::production_vivado_collector_v2::_append_attempt \
        $collector_request 14 REPORT_MISSING MISSING \
        [file join [dict get $context report_root] {missing report.rpt}] NONE]
    assert_equal -1 [dict get $missing_attempt bytes] \
        {Absent report-attempt byte sentinel remains unchanged}
    assert_equal NONE [dict get $missing_attempt sha256] \
        {Absent report-attempt SHA-256 sentinel remains unchanged}
    assert_error {::stage1e::production_vivado_collector_v2::collect_fixture $collector_request $reports} {Collector create-new behavior}

    set binary_record [::stage1e::production_vivado_collector_v2::_artifact_record \
        $binding BINARY_HASH_FIXTURE $binary_path]
    assert_equal \
        {bytes design_identity execution_id implementation_profile path project_identity role sha256 source_commit source_tree} \
        [lsort -dictionary [dict keys $binary_record]] \
        {Artifact result fields include the sealed implementation profile}
    assert_equal [file size $binary_path] [dict get $binary_record bytes] \
        {Binary artifact byte count uses exact file size}
    assert_equal $binary_digest [dict get $binary_record sha256] \
        {Binary artifact SHA-256 remains exact}

    set artifacts {}
    foreach {role leaf} {BITSTREAM fixture.bit XSA fixture.xsa HWH protection_system.hwh LTX protection_system.ltx} {
        set path [file join [dict get $context artifact_root] $leaf]
        set channel [open $path {WRONLY CREAT EXCL}]
        puts -nonewline $channel "fixture $role"
        close $channel
        lappend artifacts [::stage1e::production_vivado_collector_v2::_artifact_record $binding $role $path]
    }
    set artifacts [::stage1e::production_vivado_collector_v2::write_artifact_manifest [dict get $context artifact_root] $artifacts [dict get $collected attempts] $binding]
    assert_true [::stage1e::production_vivado_runner_v2::_validate_artifact_roles $artifacts {BITSTREAM XSA HWH LTX ARTIFACT_MANIFEST}] {Exact artifact-role inventory}
    set manifested_artifact_roles {}
    foreach artifact $artifacts {
        lappend manifested_artifact_roles [dict get $artifact role]
    }
    assert_equal {BITSTREAM XSA HWH LTX ARTIFACT_MANIFEST} \
        $manifested_artifact_roles \
        {Artifact roles and appended manifest requirement remain unchanged}
    set duplicate $artifacts
    lappend duplicate [lindex $artifacts 0]
    assert_error {::stage1e::production_vivado_runner_v2::_validate_artifact_roles $duplicate {BITSTREAM XSA HWH LTX ARTIFACT_MANIFEST}} {Duplicate artifact role rejected}

    set hwh_project [dict create project_dir [file join $temporary exact-hwh] project_name fixture bd_name protection_system]
    set exact_hwh [file join [dict get $hwh_project project_dir] fixture.gen sources_1 bd protection_system hw_handoff protection_system.hwh]
    file mkdir [file dirname $exact_hwh]
    set channel [open $exact_hwh {WRONLY CREAT EXCL}]
    puts -nonewline $channel {exact HWH}
    close $channel
    set distractor [file join [dict get $hwh_project project_dir] aaa first.hwh]
    file mkdir [file dirname $distractor]
    set channel [open $distractor {WRONLY CREAT EXCL}]
    puts -nonewline $channel {wrong HWH}
    close $channel
    assert_equal $exact_hwh [::stage1e::production_vivado_runner_v2::_expected_hwh_source $hwh_project] {Deterministic exact-design HWH selection}

    namespace eval ::stage1e_project_mode_test {
        variable calls {}
        variable properties {}
    }
    proc ::launch_runs args {
        lappend ::stage1e_project_mode_test::calls [linsert $args 0 launch_runs]
    }
    proc ::wait_on_run args {
        lappend ::stage1e_project_mode_test::calls [linsert $args 0 wait_on_run]
    }
    proc ::get_property {property object} {
        return [dict get $::stage1e_project_mode_test::properties $property]
    }
    proc ::write_hw_platform args {
        lappend ::stage1e_project_mode_test::calls [linsert $args 0 write_hw_platform]
        set file_index [lsearch -exact $args -file]
        set channel [open [lindex $args [expr {$file_index + 1}]] {WRONLY CREAT EXCL}]
        puts -nonewline $channel {fixture XSA with associated BIT}
        close $channel
    }
    proc ::get_debug_cores args { return debug_core_0 }
    proc ::write_debug_probes {path} {
        set channel [open $path {WRONLY CREAT EXCL}]
        puts -nonewline $channel {fixture LTX}
        close $channel
    }

    set project_mode_run_directory [file join $temporary project-mode-run]
    file mkdir $project_mode_run_directory
    set project_mode_bit [file join $project_mode_run_directory protection_system_wrapper.bit]
    set channel [open $project_mode_bit {WRONLY CREAT EXCL}]
    puts -nonewline $channel {run-owned bitstream}
    close $channel
    set ::stage1e_project_mode_test::properties [dict create \
        NAME impl_1 \
        STATUS {write_bitstream Complete!} \
        PROGRESS 100% \
        CURRENT_STEP write_bitstream \
        DIRECTORY $project_mode_run_directory \
        STEPS.PHYS_OPT_DESIGN.IS_ENABLED 0 \
        STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED 0 \
        STEPS.POWER_OPT_DESIGN.IS_ENABLED 0 \
        STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED 0 \
        AUTO_INCREMENTAL_CHECKPOINT 0 \
        INCREMENTAL_CHECKPOINT {}]
    set project_mode_evidence \
        [::stage1e::production_vivado_runner_v2::_complete_artifacts_bitstream impl_1]
    assert_equal {launch_runs impl_1 -to_step write_bitstream} \
        [lindex $::stage1e_project_mode_test::calls 0] \
        {ARTIFACTS launches exact Project Mode write_bitstream step}
    assert_equal {wait_on_run impl_1} \
        [lindex $::stage1e_project_mode_test::calls 1] \
        {ARTIFACTS waits on exact impl_1 run}
    assert_equal [list impl_1 {write_bitstream Complete!} 100% write_bitstream \
        $project_mode_run_directory $project_mode_bit] [list \
        [dict get $project_mode_evidence NAME] \
        [dict get $project_mode_evidence STATUS] \
        [dict get $project_mode_evidence PROGRESS] \
        [dict get $project_mode_evidence CURRENT_STEP] \
        [dict get $project_mode_evidence DIRECTORY] \
        [dict get $project_mode_evidence bitstream_path]] \
        {Completed Project Mode run properties and exact BIT path are captured}

    dict set ::stage1e_project_mode_test::properties NAME wrong_impl
    assert_error {::stage1e::production_vivado_runner_v2::_complete_artifacts_bitstream impl_1} \
        {Wrong Project Mode run name rejected}
    dict set ::stage1e_project_mode_test::properties NAME impl_1
    dict set ::stage1e_project_mode_test::properties STATUS {route_design Complete!}
    assert_error {::stage1e::production_vivado_runner_v2::_complete_artifacts_bitstream impl_1} \
        {Exact write_bitstream completed status required}
    dict set ::stage1e_project_mode_test::properties STATUS {write_bitstream Complete!}
    dict set ::stage1e_project_mode_test::properties PROGRESS 99%
    assert_error {::stage1e::production_vivado_runner_v2::_complete_artifacts_bitstream impl_1} \
        {Project Mode write_bitstream requires 100% progress}
    dict set ::stage1e_project_mode_test::properties PROGRESS 100%

    file delete $project_mode_bit
    assert_error {::stage1e::production_vivado_runner_v2::_complete_artifacts_bitstream impl_1} \
        {Missing run-owned BIT rejected}
    set channel [open $project_mode_bit {WRONLY CREAT EXCL}]
    close $channel
    assert_error {::stage1e::production_vivado_runner_v2::_complete_artifacts_bitstream impl_1} \
        {Zero-byte run-owned BIT rejected}
    file delete $project_mode_bit
    set distractor_bit [file join $project_mode_run_directory arbitrary.bit]
    set channel [open $distractor_bit {WRONLY CREAT EXCL}]
    puts -nonewline $channel {wrong leaf}
    close $channel
    assert_error {::stage1e::production_vivado_runner_v2::_complete_artifacts_bitstream impl_1} \
        {Wrong BIT leaf is not accepted through fallback discovery}
    set channel [open $project_mode_bit {WRONLY CREAT EXCL}]
    puts -nonewline $channel {run-owned bitstream}
    close $channel
    dict set ::stage1e_project_mode_test::properties STEPS.PHYS_OPT_DESIGN.IS_ENABLED 1
    assert_error {::stage1e::production_vivado_runner_v2::_complete_artifacts_bitstream impl_1} \
        {Run-managed bitstream requires zero forbidden operations}
    dict set ::stage1e_project_mode_test::properties STEPS.PHYS_OPT_DESIGN.IS_ENABLED 0

    set generate_body \
        [info body ::stage1e::production_vivado_runner_v2::_generate_artifacts]
    assert_true [expr {[string first {write_bitstream -file} $generate_body] < 0}] \
        {Standalone artifact-root write_bitstream command is absent}
    set artifact_flow_root [file join $temporary project-mode-artifacts]
    file mkdir $artifact_flow_root
    set artifact_context $context
    dict set artifact_context artifact_root $artifact_flow_root
    set artifact_project [dict create \
        project_dir [file join $temporary project-mode-project] \
        project_name fixture \
        bd_name protection_system]
    set artifact_hwh [file join [dict get $artifact_project project_dir] \
        fixture.gen sources_1 bd protection_system hw_handoff protection_system.hwh]
    file mkdir [file dirname $artifact_hwh]
    set channel [open $artifact_hwh {WRONLY CREAT EXCL}]
    puts -nonewline $channel {fixture HWH}
    close $channel
    set ::stage1e_project_mode_test::calls {}
    set project_mode_artifacts [::stage1e::production_vivado_runner_v2::_generate_artifacts \
        $artifact_context $artifact_project $project_mode_bit]
    set copied_bit [file join $artifact_flow_root protection_system.bit]
    set collision_status [catch {
        ::stage1e::production_vivado_runner_v2::_generate_artifacts \
            $artifact_context $artifact_project $project_mode_bit
    }]
    assert_true [expr {$collision_status &&
        [::stage1e::canonical_json_v1::digest_file $project_mode_bit] eq \
        [::stage1e::canonical_json_v1::digest_file $copied_bit]}] \
        {Run-owned BIT is copied exactly with no-overwrite behavior}
    assert_equal [list write_hw_platform -fixed -include_bit -file \
        [file join $artifact_flow_root protection_system.xsa]] \
        [lindex $::stage1e_project_mode_test::calls 0] \
        {Hardware platform retains fixed include-bit flow}
    set generated_project_mode_roles {}
    foreach artifact $project_mode_artifacts {
        lappend generated_project_mode_roles [dict get $artifact role]
    }
    assert_equal {BITSTREAM XSA HWH LTX} $generated_project_mode_roles \
        {Generated Project Mode artifact roles remain exact}

    set run_body [info body ::stage1e::production_vivado_runner_v2::run]
    set bitstream_index [string first {_complete_artifacts_bitstream $impl} $run_body]
    set open_index [string first {open_run impl_1} $run_body]
    set generate_index [string first {_generate_artifacts $context $project $run_bitstream} $run_body]
    assert_true [expr {$bitstream_index >= 0 && $open_index > $bitstream_index &&
        $generate_index > $open_index}] \
        {ARTIFACTS opens impl_1 only after run-managed bitstream completion}
    set target_guard {if {[dict get $context build_target] eq {ARTIFACTS}} {
            set bitstream_evidence [_complete_artifacts_bitstream $impl]
            set run_bitstream [dict get $bitstream_evidence bitstream_path]
        }}
    assert_true [expr {[string first $target_guard $run_body] >= 0}] \
        {IMPLEMENTATION target does not launch Project Mode write_bitstream}
    assert_equal 1 [regexp -all {open_run impl_1} $run_body] \
        {IMPLEMENTATION target retains one unconditional routed-run open}
    assert_true [expr {[string first \
        {_validate_artifact_roles $artifacts {BITSTREAM XSA HWH LTX ARTIFACT_MANIFEST}} \
        $run_body] >= 0}] \
        {Final artifact roles remain BITSTREAM XSA HWH LTX ARTIFACT_MANIFEST}

    set frozen_contract_schema_identities {}
    set observed_contract_schema_identities {}
    foreach {leaf expected} {
        stage1e_execution_contract_v1.json a68b26f6ad8cd6ceb4eace1285876015b3e4f2f5e7303b5bd297df68d3b24d44
        stage1e_execution_request_schema_v1.json 9b9e94037d5d32590bfe5513ecaf9aa5be1012787285ecd9e158779df635ee74
        stage1e_terminal_result_schema_v1.json b6a1ffc42253bc11cf7c68ad7d63ed90ecd0c4426448f39cd1281a6a60ac9718
        stage1e_vivado_result_schema_v1.json 7a04a0edee593eca6e2102a33634ad9c54941942caf3343d8fd0f6cf92974440
    } {
        set observed [::stage1e::canonical_json_v1::digest_file \
            [file join $build_root config $leaf]]
        lappend observed_contract_schema_identities $observed
        lappend frozen_contract_schema_identities [expr {$observed eq $expected}]
    }
    assert_equal {1 1 1 1} $frozen_contract_schema_identities \
        {Published execution contract and request-result schema identities are exact}
    assert_equal [list \
        a68b26f6ad8cd6ceb4eace1285876015b3e4f2f5e7303b5bd297df68d3b24d44 \
        9b9e94037d5d32590bfe5513ecaf9aa5be1012787285ecd9e158779df635ee74 \
        b6a1ffc42253bc11cf7c68ad7d63ed90ecd0c4426448f39cd1281a6a60ac9718 \
        7a04a0edee593eca6e2102a33634ad9c54941942caf3343d8fd0f6cf92974440] \
        $observed_contract_schema_identities \
        {Execution contract and schemas match their published identities}
    assert_true [expr {
        [string first {[dict get $artifact_after STATUS]} $run_body] >= 0 &&
        [string first {[dict get $artifact_after PROGRESS]} $run_body] >= 0 &&
        [string first {[dict get $artifact_after CURRENT_STEP]} $run_body] >= 0 &&
        [string first {[dict get $report_before STATUS]} $run_body] >= 0 &&
        [string first {[dict get $report_after STATUS]} $run_body] >= 0 &&
        [string first {[dict get $report_after CURRENT_STEP]} $run_body] >= 0}] \
        {Artifact and report journals use actual current run properties}

    foreach command {
        launch_runs wait_on_run get_property write_hw_platform
        get_debug_cores write_debug_probes
    } {
        rename ::$command {}
    }
} reason options]
catch {file delete -force $temporary}
if {$failure} { return -options $options $reason }
puts "PASS stage1e_execution_architecture_convergence_tests assertions=$assertions"
