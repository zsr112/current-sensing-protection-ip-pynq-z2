# Source-only tests for the Stage 1E controlled-mutation bridge.
#
# The authoritative Stage 1D procedure is replaced by a narrow in-memory mock
# after the bridge is sourced.  The suite therefore exercises context
# validation, projection, and result normalization without invoking Vivado,
# saving a BD, or generating an FPGA artifact.

namespace eval ::stage1e::mutation_bridge_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_root {}
    variable invocation_count 0
    variable invocation_contexts {}
    variable last_projected_context {}
    variable mock_result {}
    variable mock_error {}
}

set stage1e_mutation_test_dir [file normalize [file dirname [info script]]]
set stage1e_mutation_adapter [file normalize [file join \
    $stage1e_mutation_test_dir .. adapters stage1e_mutation_bridge.tcl]]
set stage1e_mutation_adapter_channel [open $stage1e_mutation_adapter r]
fconfigure $stage1e_mutation_adapter_channel -encoding utf-8 -translation lf
set stage1e_mutation_adapter_source [read $stage1e_mutation_adapter_channel]
close $stage1e_mutation_adapter_channel

# Sourcing the bridge must be definition-only.  It may load the unchanged
# Stage 1D module, but it must not call that module until apply is invoked.
source $stage1e_mutation_adapter
rename ::stage1d_controlled_stimulus::apply \
    ::stage1d_controlled_stimulus::_stage1e_test_production_apply

proc ::stage1d_controlled_stimulus::apply {context} {
    incr ::stage1e::mutation_bridge_tests::invocation_count
    set ::stage1e::mutation_bridge_tests::last_projected_context $context
    lappend ::stage1e::mutation_bridge_tests::invocation_contexts $context
    if {$::stage1e::mutation_bridge_tests::mock_error ne {}} {
        error $::stage1e::mutation_bridge_tests::mock_error
    }
    return $::stage1e::mutation_bridge_tests::mock_result
}

proc ::stage1e::mutation_bridge_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::mutation_bridge_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::mutation_bridge_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::mutation_bridge_tests::assert_status {
    result
    expected
    message
} {
    if {[catch {dict size $result} dictionary_error]} {
        fail "$message is not a dictionary: $dictionary_error"
    }
    if {![dict exists $result status] ||
        [dict get $result status] ne $expected} {
        fail "$message: expected=<$expected> actual=<[dict get $result status]> errors=<[dict get $result errors]>"
    }
}

proc ::stage1e::mutation_bridge_tests::first_error_code {result} {
    if {![dict exists $result errors] ||
        [llength [dict get $result errors]] == 0} {
        fail {Expected a structured bridge error record.}
    }
    set first_error [lindex [dict get $result errors] 0]
    if {![dict exists $first_error code]} {
        fail {Bridge error record has no code.}
    }
    return [dict get $first_error code]
}

proc ::stage1e::mutation_bridge_tests::run_case {name body} {
    variable pass_count
    variable fail_count
    set case_status [catch {uplevel 1 $body} case_error case_options]
    if {$case_status == 0} {
        incr pass_count
        puts "$name: PASS"
        return
    }
    incr fail_count
    puts stderr "$name: FAIL: $case_error"
    if {[dict exists $case_options -errorinfo]} {
        puts stderr [dict get $case_options -errorinfo]
    }
}

proc ::stage1e::mutation_bridge_tests::temporary_base {} {
    foreach variable_name {STAGE1E_TEST_TEMP_ROOT TEMP TMP TMPDIR} {
        if {[info exists ::env($variable_name)] &&
            [string trim $::env($variable_name)] ne {}} {
            set canonical [string map {\\ /} $::env($variable_name)]
            if {$::tcl_platform(platform) eq {windows} &&
                [regexp {^[A-Za-z]:/} $canonical]} {
                set canonical "//?/$canonical"
            }
            return [file normalize $canonical]
        }
    }
    error {No external temporary directory is available for mutation-bridge tests.}
}

proc ::stage1e::mutation_bridge_tests::prepare_suite {} {
    variable test_root
    set test_root [file normalize [file join [temporary_base] \
        "stage1e_mutation_bridge_tests_[pid]_[clock clicks]"]]
    if {![string match {stage1e_mutation_bridge_tests_*} \
        [file tail $test_root]]} {
        error "Unsafe mutation-bridge test root: $test_root"
    }
    file mkdir [file join $test_root workspace execution_state stage1e_design]
    file mkdir [file join $test_root workspace stage1e_design.srcs sources_1 bd protection_system]
}

proc ::stage1e::mutation_bridge_tests::safe_cleanup {} {
    variable test_root
    if {$test_root eq {} || ![file exists $test_root]} {
        return
    }
    if {![string match {stage1e_mutation_bridge_tests_*} \
        [file tail $test_root]]} {
        error "Refusing unsafe mutation-bridge test cleanup: $test_root"
    }
    file delete -force -- $test_root
}

proc ::stage1e::mutation_bridge_tests::reset_mock {} {
    variable invocation_count
    variable invocation_contexts
    variable last_projected_context
    variable mock_result
    variable mock_error
    set invocation_count 0
    set invocation_contexts {}
    set last_projected_context {}
    set mock_result {}
    set mock_error {}
}

proc ::stage1e::mutation_bridge_tests::valid_context {} {
    variable test_root
    set execution_id stage1e-test-execution
    set workspace_root [file normalize [file join $test_root workspace]]
    set evidence_dir [file normalize [file join $workspace_root execution_state]]
    set project_directory [file normalize [file join $workspace_root stage1e_design]]
    set project_path [file join $project_directory stage1e_design.xpr]
    set bd_path [file normalize [file join $workspace_root \
        stage1e_design.srcs sources_1 bd protection_system protection_system.bd]]

    set project_identity [dict create \
        project_name stage1e_design \
        project_directory $project_directory \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0]
    set project_ownership [dict create \
        owner vivado_project \
        execution_id $execution_id \
        project_handle project::stage1e_design \
        project_path $project_path \
        identity_verified 1 \
        project_identity $project_identity]
    set bd_ownership [dict create \
        owner bd_flow \
        execution_id $execution_id \
        project_path $project_path \
        bd_name protection_system \
        bd_path $bd_path \
        opened 1 \
        identity_verified 1 \
        validated 0 \
        saved 0]

    set mutation_configuration [dict create \
        axi_gpio_vlnv xilinx.com:ip:axi_gpio:2.0 \
        expected_protection_base 0x43C00000 \
        expected_protection_range 0x00001000 \
        gpio_name axi_gpio_stage1d_0 \
        gpio_width 24 \
        i_ch1_const_name i_ch1_const \
        i_ch2_const_name i_ch2_const \
        ila_name system_ila_stage2b_0 \
        planned_gpio_base 0x41200000 \
        planned_gpio_range 0x00010000 \
        protection_name protection_ip_axi_lite_0 \
        protection_vlnv zsr112.local:protection:protection_ip_axi_lite:0.3 \
        ps_name processing_system7_0 \
        reset_name proc_sys_reset_0 \
        safe_gpio_default 0x00400400 \
        sample_valid_const_name sample_valid_const \
        stimulus_profile SAFE_INERT_EXPLICIT \
        stimulus_profile_class SAFE_INERT \
        source_acceptance_claimed 0 \
        fault_stimulus_claimed 0 \
        slice_ch1_name xlslice_stage1d_ch1 \
        slice_ch2_name xlslice_stage1d_ch2 \
        smartconnect_name smartconnect_0 \
        stage1d_source_baseline 2efeb7efaf5b97ca7850f61f1001224c00efd111 \
        xlslice_vlnv xilinx.com:ip:xlslice:1.0]
    set assertion [dict create \
        execution_id $execution_id \
        operation stage1d_controlled_stimulus \
        phase MUTATION_EXECUTE \
        bd_name protection_system \
        decision ALLOW]

    return [dict create \
        context_schema_version stage1e-mutation-bridge-context-v1 \
        operation stage1e::mutation_bridge::apply \
        phase MUTATION_EXECUTE \
        execution_id $execution_id \
        authorization [dict create \
            status AUTHORIZED \
            authority controller_core \
            execution_id $execution_id \
            operation stage1e::mutation_bridge::apply \
            phase MUTATION_EXECUTE \
            capability bd_generation_enabled \
            capability_enabled 1] \
        source_identity [dict create \
            schema_version stage1e-source-identity-v1 \
            execution_id $execution_id \
            git_commit [string repeat 1 40]] \
        environment_identity [dict create \
            schema_version stage1e-environment-identity-v1 \
            execution_id $execution_id \
            vivado_version 2024.1 \
            part xc7z020clg400-1 \
            board_part tul.com.tw:pynq-z2:part0:1.0] \
        configuration_identity [dict create \
            schema_version stage1e-configuration-identity-v1 \
            execution_id $execution_id \
            sha256 [string repeat c 64]] \
        workspace_root $workspace_root \
        evidence_dir $evidence_dir \
        project_ownership $project_ownership \
        bd_ownership $bd_ownership \
        base_design_identity [dict create \
            schema_version stage1e-base-design-identity-v1 \
            producer_operation stage1e::base_design::apply \
            execution_id $execution_id \
            project_path $project_path \
            bd_name protection_system \
            bd_path $bd_path \
            identity_sha256 [string repeat a 64]] \
        debug_design_identity [dict create \
            schema_version stage1e-debug-design-identity-v1 \
            producer_operation stage1e::debug_design::apply \
            execution_id $execution_id \
            project_path $project_path \
            bd_name protection_system \
            bd_path $bd_path \
            base_design_identity_sha256 [string repeat a 64] \
            identity_sha256 [string repeat b 64]] \
        mutation_configuration $mutation_configuration \
        mutation_authorization_assertion_source [dict create \
            owner controller_core \
            authorization_assertion $assertion]]
}

proc ::stage1e::mutation_bridge_tests::expected_stage1d_fields {} {
    return {
        execution_id
        authorization_assertion
        bd_name
        evidence_dir
        environment_identity
        axi_gpio_vlnv
        current_bd
        expected_bd_name
        expected_protection_base
        expected_protection_range
        gpio_name
        gpio_width
        i_ch1_const_name
        i_ch2_const_name
        ila_name
        planned_gpio_base
        planned_gpio_range
        project_path
        protection_name
        protection_vlnv
        ps_name
        reset_name
        safe_gpio_default
        sample_valid_const_name
        stimulus_profile
        stimulus_profile_class
        source_acceptance_claimed
        fault_stimulus_claimed
        slice_ch1_name
        slice_ch2_name
        smartconnect_name
        stage1d_source_baseline
        vivado_version
        xlslice_vlnv
    }
}

proc ::stage1e::mutation_bridge_tests::assert_result_schema {result} {
    foreach key {
        schema_version operation phase execution_id status
        consumed_identities produced_identities ownership_records
        evidence_references warnings errors cleanup_result
        stage1d_result stage1d_outputs mutation_summary
        vivado_invoked mutation_invoked mutation_started
        lifecycle_ownership_created project_opened project_created
        bd_created bd_validated bd_saved synthesis_performed
        implementation_performed artifacts_generated
        artifact_generation_performed artifact_publication_performed
    } {
        assert_true [dict exists $result $key] \
            "Result is missing required key: $key"
    }
}

proc ::stage1e::mutation_bridge_tests::assert_no_build_flags {result} {
    foreach key {
        project_opened project_created bd_created bd_validated bd_saved
        synthesis_performed implementation_performed artifacts_generated
        artifact_generation_performed artifact_publication_performed
    } {
        assert_equal 0 [dict get $result $key] \
            "Stage 1E bridge must leave $key disabled"
    }
}

proc ::stage1e::mutation_bridge_tests::run_all {} {
    run_case MUTATION_BRIDGE_CONTEXT_VALID {
        reset_mock
        set context [valid_context]
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result PASS {Valid context status}
        assert_equal 1 $::stage1e::mutation_bridge_tests::invocation_count \
            {Valid context invokes mutation once}
        assert_equal [lsort [expected_stage1d_fields]] \
            [lsort [dict keys $::stage1e::mutation_bridge_tests::last_projected_context]] \
            {Projected context field set}
        assert_equal [dict get $context mutation_authorization_assertion_source authorization_assertion] \
            [dict get $::stage1e::mutation_bridge_tests::last_projected_context authorization_assertion] \
            {Projected assertion is unchanged}
        foreach forbidden_key {
            context_schema_version authorization source_identity
            configuration_identity project_ownership bd_ownership
            base_design_identity debug_design_identity
            mutation_configuration workspace_root
        } {
            assert_true [expr {![dict exists \
                $::stage1e::mutation_bridge_tests::last_projected_context $forbidden_key]}] \
                "Stage 1E-only field leaked into Stage 1D context: $forbidden_key"
        }
        assert_true [dict exists [dict get $result produced_identities] \
            controlled_mutation_identity] \
            {Valid mutation did not produce controlled_mutation_identity.}
    }

    run_case MUTATION_BRIDGE_AUTH_REJECT {
        reset_mock
        set context [valid_context]
        dict set context authorization capability_enabled 0
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result BLOCKED {Authorization rejection status}
        assert_equal AUTHORIZATION_MISMATCH [first_error_code $result] \
            {Authorization rejection code}
        assert_equal 0 $::stage1e::mutation_bridge_tests::invocation_count \
            {Authorization rejection invoked Stage 1D}
    }

    run_case MUTATION_BRIDGE_STIMULUS_PROFILE_REJECT {
        reset_mock
        set context [valid_context]
        dict set context mutation_configuration stimulus_profile FUNCTIONAL_READY_AWARE
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result FAIL {Stimulus profile rejection status}
        assert_equal STIMULUS_PROFILE_INVALID [first_error_code $result] \
            {Stimulus profile rejection code}
        assert_equal 0 $::stage1e::mutation_bridge_tests::invocation_count \
            {Stimulus profile rejection invoked Stage 1D}
    }

    run_case MUTATION_BRIDGE_STIMULUS_CLAIM_REJECT {
        reset_mock
        set context [valid_context]
        dict set context mutation_configuration source_acceptance_claimed 1
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result FAIL {Stimulus claim rejection status}
        assert_equal STIMULUS_CLAIM_INVALID [first_error_code $result] \
            {Stimulus claim rejection code}
        assert_equal 0 $::stage1e::mutation_bridge_tests::invocation_count \
            {Stimulus claim rejection invoked Stage 1D}
    }

    run_case MUTATION_BRIDGE_PROJECT_OWNER_REJECT {
        reset_mock
        set context [valid_context]
        dict set context project_ownership owner stage1e_test
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result FAIL {Project ownership rejection status}
        assert_equal PROJECT_OWNER_INVALID [first_error_code $result] \
            {Project ownership rejection code}
        assert_equal 0 $::stage1e::mutation_bridge_tests::invocation_count \
            {Project ownership rejection invoked Stage 1D}
    }

    run_case MUTATION_BRIDGE_BD_OWNER_REJECT {
        reset_mock
        set context [valid_context]
        dict set context bd_ownership owner stage1e_test
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result FAIL {BD ownership rejection status}
        assert_equal BD_OWNER_INVALID [first_error_code $result] \
            {BD ownership rejection code}
        assert_equal 0 $::stage1e::mutation_bridge_tests::invocation_count \
            {BD ownership rejection invoked Stage 1D}
    }

    run_case MUTATION_BRIDGE_BASE_IDENTITY_REJECT {
        reset_mock
        set context [valid_context]
        dict set context base_design_identity execution_id other-execution
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result FAIL {Base identity rejection status}
        assert_equal BASE_DESIGN_IDENTITY_MISMATCH [first_error_code $result] \
            {Base identity rejection code}
        assert_equal 0 $::stage1e::mutation_bridge_tests::invocation_count \
            {Base identity rejection invoked Stage 1D}
    }

    run_case MUTATION_BRIDGE_DEBUG_IDENTITY_REJECT {
        reset_mock
        set context [valid_context]
        dict set context debug_design_identity base_design_identity_sha256 \
            [string repeat f 64]
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result FAIL {Debug identity rejection status}
        assert_equal DEBUG_DESIGN_IDENTITY_MISMATCH [first_error_code $result] \
            {Debug identity rejection code}
        assert_equal 0 $::stage1e::mutation_bridge_tests::invocation_count \
            {Debug identity rejection invoked Stage 1D}
    }

    run_case MUTATION_BRIDGE_RESULT_SCHEMA {
        reset_mock
        set context [valid_context]
        set ::stage1e::mutation_bridge_tests::mock_result [dict create \
            status PASS \
            execution_id stage1e-test-execution \
            vivado_invoked 0 \
            artifacts_generated 0 \
            errors {} \
            warnings [list [dict create code REVIEWED_WARNING]] \
            outputs [dict create mutation_started 1 evidence_token retained] \
            evidence_references [dict create mutation_log retained] \
            mutation_summary [dict create changed_properties {} marker retained]]
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result PASS {Structured result status}
        assert_result_schema $result
        assert_equal [dict get $::stage1e::mutation_bridge_tests::mock_result warnings] \
            [dict get $result warnings] \
            {Stage 1D warnings were preserved}
        assert_equal [dict get $::stage1e::mutation_bridge_tests::mock_result mutation_summary] \
            [dict get $result mutation_summary] \
            {Stage 1D mutation summary was preserved}
        assert_equal [dict get $::stage1e::mutation_bridge_tests::mock_result evidence_references] \
            [dict get $result evidence_references] \
            {Stage 1D evidence references were preserved}
        assert_true [dict exists [dict get $result produced_identities] \
            controlled_mutation_identity] \
            {Structured PASS did not produce controlled mutation identity.}
        set mutation_identity [dict get $result produced_identities \
            controlled_mutation_identity]
        foreach hash_field {
            source_identity_sha256 environment_identity_sha256
            configuration_identity_sha256 workspace_identity_sha256
            mutation_configuration_sha256 authorization_assertion_sha256
            projected_context_sha256 stage1d_result_sha256 identity_sha256
        } {
            assert_true [regexp {^[0-9a-f]{64}$} \
                [dict get $mutation_identity $hash_field]] \
                "Controlled mutation identity hash is invalid: $hash_field"
        }
        assert_no_build_flags $result
    }

    run_case MUTATION_BRIDGE_NO_DUPLICATED_MUTATION {
        reset_mock
        set context [valid_context]
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result PASS {No-duplication execution status}
        assert_equal 1 $::stage1e::mutation_bridge_tests::invocation_count \
            {Bridge invoked the authoritative mutation exactly once}
        foreach forbidden_command {
            create_bd_cell connect_bd_net connect_bd_intf_net
            disconnect_bd_net delete_bd_objs assign_bd_address
            set_property save_bd_design validate_bd_design
        } {
            assert_equal -1 [string first $forbidden_command \
                $::stage1e_mutation_adapter_source] \
                "Bridge duplicates Stage 1D command: $forbidden_command"
        }
    }

    run_case MUTATION_BRIDGE_NO_SAVE {
        reset_mock
        set context [valid_context]
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result PASS {No-save execution status}
        assert_equal 0 [dict get $result bd_validated] \
            {Bridge must not validate the BD}
        assert_equal 0 [dict get $result bd_saved] \
            {Bridge must not save the BD}
        foreach forbidden_command {validate_bd_design save_bd_design close_project} {
            assert_equal -1 [string first $forbidden_command \
                $::stage1e_mutation_adapter_source] \
                "Bridge owns forbidden lifecycle command: $forbidden_command"
        }
    }

    run_case MUTATION_BRIDGE_NO_ARTIFACT {
        reset_mock
        set context [valid_context]
        set result [::stage1e::mutation_bridge::apply $context]
        assert_status $result PASS {No-artifact execution status}
        assert_no_build_flags $result
        foreach forbidden_command {
            launch_runs synth_design opt_design place_design route_design
            write_bitstream write_hw_platform write_debug_probes
            export_ip_user_files
        } {
            assert_equal -1 [string first $forbidden_command \
                $::stage1e_mutation_adapter_source] \
                "Bridge owns forbidden build command: $forbidden_command"
        }
    }
}

set suite_status [catch {
    ::stage1e::mutation_bridge_tests::prepare_suite
    ::stage1e::mutation_bridge_tests::run_all
} suite_error suite_options]

set cleanup_status [catch {
    ::stage1e::mutation_bridge_tests::safe_cleanup
} cleanup_error]
rename ::stage1d_controlled_stimulus::apply {}
rename ::stage1d_controlled_stimulus::_stage1e_test_production_apply \
    ::stage1d_controlled_stimulus::apply
if {$suite_status != 0} {
    puts stderr "Mutation-bridge test suite failed unexpectedly: $suite_error"
    if {[dict exists $suite_options -errorinfo]} {
        puts stderr [dict get $suite_options -errorinfo]
    }
}
if {$cleanup_status != 0} {
    puts stderr "Mutation-bridge test cleanup failed: $cleanup_error"
}

puts "SUMMARY PASS=$::stage1e::mutation_bridge_tests::pass_count FAIL=$::stage1e::mutation_bridge_tests::fail_count"
if {$suite_status != 0 || $cleanup_status != 0 ||
    $::stage1e::mutation_bridge_tests::fail_count != 0} {
    exit 1
}
