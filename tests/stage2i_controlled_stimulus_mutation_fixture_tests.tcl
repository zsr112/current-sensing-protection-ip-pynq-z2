# Definition-only tests for the Stage2I controlled-stimulus mutation bridge.

set test_directory [file dirname [file normalize [info script]]]
set repository_root [file dirname $test_directory]
set module_path [file join $repository_root fpga vivado build mutation \
    stage1d_controlled_stimulus.tcl]

set ::stage2i_mutation_calls {}
source $module_path

proc mutation_equal {actual expected message} {
    if {$actual ne $expected} {
        error "ASSERTION FAILED: $message: $actual != $expected"
    }
}

proc mutation_expect_error {script pattern message} {
    if {![catch {uplevel 1 $script} observed]} {
        error "ASSERTION FAILED: $message did not fail"
    }
    if {![string match $pattern $observed]} {
        error "ASSERTION FAILED: $message: $observed"
    }
}

proc current_bd_design {} {
    return protection_system
}

namespace eval ::stage1e::production_vivado_runner_v2 {}
proc ::stage1e::production_vivado_runner_v2::add_controlled_stimulus {
    context project
} {
    lappend ::stage2i_mutation_calls [dict get $context implementation_profile]
    dict set project applied_profile [dict get $context implementation_profile]
    return $project
}

mutation_equal [llength $::stage2i_mutation_calls] 0 \
    {sourcing the mutation module performs no mutation}

set safe_contract [::stage1d_controlled_stimulus::current_profile_contract \
    SAFE_INERT]
mutation_equal [dict get $safe_contract source_ila_present] 0 \
    {SAFE_INERT has no source-domain ILA}
set b2_contract [::stage1d_controlled_stimulus::current_profile_contract \
    READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS]
mutation_equal [dict get $b2_contract command_cdc] \
    BUNDLED_DATA_REQUEST_ACK {B2 uses the reviewed atomic CDC mechanism}
mutation_equal [dict get $b2_contract maximum_burst_count] 127 \
    {B2 burst bound matches the producer contract}

foreach profile {
    SAFE_INERT
    READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
} {
    set result [::stage1d_controlled_stimulus::apply_current_profile \
        [dict create \
            authorization_state STAGE2I_PROFILE_MUTATION_EXPLICIT \
            implementation_profile $profile \
            current_bd protection_system \
            project [dict create bd_name protection_system]]]
    mutation_equal [dict get $result status] PASS \
        "$profile mutation delegates successfully"
    mutation_equal [dict get $result implementation_profile] $profile \
        "$profile identity is preserved"
    mutation_equal [dict get $result mutation_authority] \
        ::stage1e::production_vivado_runner_v2::add_controlled_stimulus \
        {the shared production runner remains the mutation authority}
}
mutation_equal $::stage2i_mutation_calls \
    {SAFE_INERT READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS} \
    {both current profiles are passed explicitly to the runner}

mutation_expect_error {
    ::stage1d_controlled_stimulus::apply_current_profile [dict create \
        authorization_state DENIED \
        implementation_profile SAFE_INERT \
        current_bd protection_system \
        project [dict create]]
} {*authorization is not explicit*} {implicit mutation authorization is rejected}
mutation_expect_error {
    ::stage1d_controlled_stimulus::apply_current_profile [dict create \
        authorization_state STAGE2I_PROFILE_MUTATION_EXPLICIT \
        implementation_profile FUTURE_PROFILE \
        current_bd protection_system \
        project [dict create]]
} {*Unsupported Stage2I controlled-stimulus profile*} \
    {hypothetical profiles are rejected}
mutation_expect_error {
    ::stage1d_controlled_stimulus::apply_current_profile [dict create \
        authorization_state STAGE2I_PROFILE_MUTATION_EXPLICIT \
        implementation_profile SAFE_INERT \
        current_bd wrong_bd \
        project [dict create]]
} {*requires protection_system*} {the wrong BD identity is rejected}

puts "STAGE2I_CONTROLLED_STIMULUS_MUTATION_FIXTURE_TESTS_PASS"
