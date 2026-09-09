# Offline fixture tests for Stage2I ILA capture planning and call graphs.

set test_directory [file dirname [file normalize [info script]]]
set repository_root [file dirname $test_directory]
set tool_directory [file join $repository_root tools board_validation]

source [file join $tool_directory stage1_board_ila_common.tcl]
source [file join \
    $tool_directory stage1_board_ila_capture_configuration.tcl]
set ::stage1_capture_library_only 1
source [file join $tool_directory stage1_board_ila_capture.tcl]
unset ::stage1_capture_library_only
set ::stage1_configuration_preflight_library_only 1
source [file join \
    $tool_directory stage1_board_ila_capture_configuration_preflight.tcl]
unset ::stage1_configuration_preflight_library_only

set ::stage2i_config_check_count 0

proc assert_true {condition message} {
    incr ::stage2i_config_check_count
    if {![uplevel 1 [list expr $condition]]} {
        error "ASSERTION FAILED: $message"
    }
}

proc assert_equal {actual expected message} {
    incr ::stage2i_config_check_count
    if {$actual ne $expected} {
        error "ASSERTION FAILED: $message: $actual != $expected"
    }
}

proc expect_error {script pattern message} {
    incr ::stage2i_config_check_count
    if {![catch {uplevel 1 $script} observed]} {
        error "ASSERTION FAILED: $message did not fail"
    }
    if {![string match $pattern $observed]} {
        error "ASSERTION FAILED: $message: $observed"
    }
}

proc capability {type read_only current_value} {
    return [dict create \
        present 1 type $type read_only $read_only \
        current_value $current_value]
}

proc fixture_catalogs {profile role} {
    set target_catalog [dict create \
        PARAM.FREQUENCY [capability long 0 1000000]]
    set ila_catalog [dict create \
        CONTROL.DATA_DEPTH [capability long 0 4096] \
        CONTROL.TRIGGER_POSITION [capability long 0 2048] \
        CONTROL.WINDOW_COUNT [capability long 0 1] \
        CONTROL.CAPTURE_MODE [capability string 0 ALWAYS] \
        CONTROL.TRIGGER_MODE [capability string 0 BASIC_ONLY] \
        CONTROL.TRIGGER_CONDITION [capability string 0 AND]]
    set probe_map [dict create]
    set probe_catalogs [dict create]
    set contract [::stage1::core_contract $profile $role]
    foreach {index width} [dict get $contract probe_widths] {
        dict set probe_map $index "${role}_probe_$index"
        dict set probe_catalogs $index [dict create \
            DISPLAY_RADIX [capability string 0 BINARY] \
            DISPLAY_AS_ENUM [capability bool 0 false] \
            TRIGGER_COMPARE_VALUE \
                [capability string 0 \
                    [::stage1::capture_config::wildcard_compare $width]]]
    }
    return [dict create \
        target_catalog $target_catalog \
        ila_catalog $ila_catalog \
        probe_map $probe_map \
        probe_catalogs $probe_catalogs]
}

proc build_fixture_plan {profile mode} {
    set role [::stage1::capture_config::capture_mode_core_role $mode]
    set fixture [fixture_catalogs $profile $role]
    return [::stage1::capture_config::build_plan_from_catalogs \
        $profile $mode hw_target_1 \
        [dict get $fixture target_catalog] hw_ila_1 \
        [dict get $fixture ila_catalog] [dict get $fixture probe_map] \
        [dict get $fixture probe_catalogs] 1000000]
}

proc find_plan_item {plan scope property} {
    set matches {}
    foreach item $plan {
        if {[dict get $item scope] eq $scope &&
            [dict get $item property] eq $property} {
            lappend matches $item
        }
    }
    if {[llength $matches] != 1} {
        error "Expected one plan item for $scope $property: $matches"
    }
    return [lindex $matches 0]
}

set safe_profile SAFE_INERT
set b2_profile READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
assert_equal \
    [::stage1::capture_config::capture_modes_for_profile $safe_profile] \
    {destination_trigger_now destination_fault_valid destination_fault_latched} \
    {SAFE_INERT exposes destination capture modes only}
assert_equal \
    [::stage1::capture_config::capture_modes_for_profile $b2_profile] \
    {destination_trigger_now destination_fault_valid destination_fault_latched source_trigger_now source_stall source_accept} \
    {B2 exposes explicit destination and source capture modes}

set destination_plan [build_fixture_plan \
    $b2_profile destination_fault_latched]
::stage1::capture_config::validate_plan $destination_plan
assert_equal [llength $destination_plan] 31 \
    {B2 destination plan covers seven core properties and eight probes}
set fault_latched [find_plan_item \
    $destination_plan probe4 TRIGGER_COMPARE_VALUE]
assert_equal [dict get $fault_latched desired] {eq1'b1} \
    {B2 destination fault-latched trigger uses probe4}
assert_equal [dict get $fault_latched core_role] destination \
    {destination plan records its explicit core role}
set fsm_wildcard [find_plan_item \
    $destination_plan probe7 TRIGGER_COMPARE_VALUE]
assert_equal [dict get $fsm_wildcard desired] {eq4'bxxxx} \
    {B2 destination fsm_state remains a wildcard for fault trigger}

set safe_destination_plan [build_fixture_plan \
    $safe_profile destination_fault_latched]
::stage1::capture_config::validate_plan $safe_destination_plan
assert_equal [llength $safe_destination_plan] 43 \
    {SAFE_INERT destination plan retains all 12 probes}
assert_equal [dict get [find_plan_item \
    $safe_destination_plan probe7 TRIGGER_COMPARE_VALUE] desired] {eq1'b1} \
    {SAFE_INERT destination fault-latched trigger remains probe7}

set stall_plan [build_fixture_plan $b2_profile source_stall]
::stage1::capture_config::validate_plan $stall_plan
assert_equal [llength $stall_plan] 31 \
    {source plan covers seven core properties and eight probes}
assert_equal [dict get [find_plan_item \
    $stall_plan probe0 TRIGGER_COMPARE_VALUE] desired] {eq1'b1} \
    {source stall requires valid high}
assert_equal [dict get [find_plan_item \
    $stall_plan probe1 TRIGGER_COMPARE_VALUE] desired] {eq1'b0} \
    {source stall requires ready low}
assert_equal [dict get [find_plan_item \
    $stall_plan probe5 TRIGGER_COMPARE_VALUE] desired] {eq7'bxxxxxxx} \
    {source remaining count is wildcarded during stall trigger}

set accept_plan [build_fixture_plan $b2_profile source_accept]
assert_equal [dict get [find_plan_item \
    $accept_plan probe6 TRIGGER_COMPARE_VALUE] desired] {eq1'b1} \
    {source acceptance trigger uses producer_accept}

set immediate_plan [build_fixture_plan $b2_profile source_trigger_now]
set immediate_compare [find_plan_item \
    $immediate_plan probe0 TRIGGER_COMPARE_VALUE]
assert_equal [dict get $immediate_compare required] 0 \
    {trigger-now comparator is optional}
assert_equal [dict get $immediate_compare action] KEEP_EXISTING \
    {trigger-now does not rewrite a comparator}

set parsed [::stage1::capture_config::parse_property_report \
    "Property Type Read-only Visible Value\nCONTROL.DATA_DEPTH long false true 4096\nDISPLAY_AS_ENUM bool true false false\n"]
assert_equal [dict get $parsed CONTROL.DATA_DEPTH current_value] 4096 \
    {five-column property reports parse their value}
assert_equal [dict get $parsed DISPLAY_AS_ENUM read_only] 1 \
    {property mutability parses exactly}

set missing_fixture [fixture_catalogs $b2_profile source]
dict unset missing_fixture ila_catalog CONTROL.DATA_DEPTH
set missing_plan [::stage1::capture_config::build_plan_from_catalogs \
    $b2_profile source_stall hw_target_1 \
    [dict get $missing_fixture target_catalog] hw_ila_1 \
    [dict get $missing_fixture ila_catalog] \
    [dict get $missing_fixture probe_map] \
    [dict get $missing_fixture probe_catalogs] 1000000]
expect_error {
    ::stage1::capture_config::validate_plan $missing_plan
} {*FAIL_MISSING_REQUIRED*} {missing data depth is a hard failure}

set read_only_fixture [fixture_catalogs $b2_profile source]
dict set read_only_fixture target_catalog PARAM.FREQUENCY \
    [capability long 1 6000000]
set read_only_plan [::stage1::capture_config::build_plan_from_catalogs \
    $b2_profile source_stall hw_target_1 \
    [dict get $read_only_fixture target_catalog] hw_ila_1 \
    [dict get $read_only_fixture ila_catalog] \
    [dict get $read_only_fixture probe_map] \
    [dict get $read_only_fixture probe_catalogs] 1000000]
expect_error {
    ::stage1::capture_config::validate_plan $read_only_plan
} {*FAIL_READ_ONLY_REQUIRED*} \
    {a mismatched read-only target frequency is rejected}

expect_error {
    ::stage1::core_contract $safe_profile source
} {*not valid for profile SAFE_INERT*} \
    {SAFE_INERT cannot select the source core}
expect_error {
    ::stage1::capture_config::capture_mode_core_role old_fault_mode
} {*Unsupported Stage2I capture mode*} {stale capture modes are rejected}

set preflight_graph [info body execute_capture_configuration_preflight]
foreach forbidden {
    program_hw_devices
    run_hw_ila
    wait_on_hw_ila
    upload_hw_ila_data
    write_hw_ila_data
} {
    assert_true {[string first $forbidden $preflight_graph] < 0} \
        "configuration preflight excludes $forbidden"
}
set capture_graph [info body execute_capture]
assert_true {[string first {dict get $binding ila_records} $capture_graph] >= 0} \
    {capture resolves the selected role from the bound ILA map}
assert_true {[string first {program_hw_devices} $capture_graph] < 0} \
    {capture never programs the FPGA}
assert_true {[string first {run_hw_ila -trigger_now} $capture_graph] >= 0} \
    {capture retains explicit immediate trigger behavior}

::stage1::static_compile \
    {apply_configuration_plan cleanup_capture_files execute_capture \
     execute_capture_configuration_preflight}
puts "STAGE2I_ILA_CAPTURE_CONFIGURATION_FIXTURE_TESTS_PASS checks=$::stage2i_config_check_count"
