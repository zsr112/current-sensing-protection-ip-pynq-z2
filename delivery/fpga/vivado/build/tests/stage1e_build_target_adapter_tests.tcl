# Source-only tests for the Stage 1E WP-B3.7 build-target adapter.
#
# The backend is an in-memory model. No Vivado executable, project lifecycle
# command, BD lifecycle command, synthesis, implementation, board access, or
# final artifact command is invoked by this suite.

namespace eval ::stage1e::build_target_adapter_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_root {}
    variable invocation_log {}
    variable forbidden_count 0
    variable current_project project::stage1e_design
    variable current_bd protection_system
    variable properties [dict create]
    variable fileset_object fileset::sources_1
    variable wrapper_registered 0
    variable wrapper_return {}
    variable wrapper_expected {}
    variable generated_products {}
    variable repository_paths {}
}

set stage1e_build_target_test_dir [file normalize [file dirname [info script]]]
set stage1e_build_target_adapter [file normalize [file join \
    $stage1e_build_target_test_dir .. adapters stage1e_build_target.tcl]]

# Sourcing must be definition-only. Replace the backend immediately afterward.
source $stage1e_build_target_adapter
rename ::stage1e::build_target::backend::invoke \
    ::stage1e::build_target::backend::_production_invoke
proc ::stage1e::build_target::backend::invoke {command arguments} {
    return [::stage1e::build_target_adapter_tests::mock_invoke \
        $command $arguments]
}

proc ::stage1e::build_target_adapter_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::build_target_adapter_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::build_target_adapter_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::build_target_adapter_tests::assert_status {
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

proc ::stage1e::build_target_adapter_tests::first_error_code {result} {
    if {![dict exists $result errors] ||
        [llength [dict get $result errors]] == 0} {
        fail {Expected a structured error record.}
    }
    return [dict get [lindex [dict get $result errors] 0] code]
}

proc ::stage1e::build_target_adapter_tests::run_case {name body} {
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

proc ::stage1e::build_target_adapter_tests::temporary_base {} {
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
    error {No external temporary directory is available for build-target tests.}
}

proc ::stage1e::build_target_adapter_tests::prepare_suite {} {
    variable test_root
    set test_root [file normalize [file join [temporary_base] \
        "stage1e_build_target_tests_[pid]_[clock clicks]"]]
    if {![string match {stage1e_build_target_tests_*} \
        [file tail $test_root]]} {
        error "Unsafe build-target test root: $test_root"
    }
    file mkdir $test_root
}

proc ::stage1e::build_target_adapter_tests::safe_cleanup {} {
    variable test_root
    if {$test_root eq {} || ![file exists $test_root]} {
        return
    }
    if {![string match {stage1e_build_target_tests_*} \
        [file tail $test_root]]} {
        error "Refusing unsafe build-target test cleanup: $test_root"
    }
    file delete -force -- $test_root
}

proc ::stage1e::build_target_adapter_tests::reset_mock {} {
    variable invocation_log
    variable forbidden_count
    variable current_project
    variable current_bd
    variable properties
    variable fileset_object
    variable wrapper_registered
    variable wrapper_return
    variable wrapper_expected
    variable generated_products
    variable repository_paths
    set invocation_log {}
    set forbidden_count 0
    set current_project project::stage1e_design
    set current_bd protection_system
    set properties [dict create]
    set fileset_object fileset::sources_1
    set wrapper_registered 0
    set wrapper_return {}
    set wrapper_expected {}
    set generated_products {}
    set repository_paths {}
}

proc ::stage1e::build_target_adapter_tests::mock_invoke {command arguments} {
    variable invocation_log
    variable forbidden_count
    variable current_project
    variable current_bd
    variable properties
    variable fileset_object
    variable wrapper_registered
    variable wrapper_return
    variable wrapper_expected
    variable generated_products
    variable repository_paths
    lappend invocation_log [linsert $arguments 0 $command]

    set forbidden {
        create_project open_project close_project
        create_bd_design open_bd_design close_bd_design
        validate_bd_design save_bd_design
        stage1d_controlled_stimulus::apply
        synth_design launch_runs wait_on_run
        opt_design place_design route_design
        write_bitstream write_debug_probes write_hw_platform export_hardware
        write_xsa exit
    }
    if {$command in $forbidden} {
        incr forbidden_count
        error "Forbidden command invoked: $command"
    }

    switch -- $command {
        current_project { return $current_project }
        current_bd_design { return $current_bd }
        get_files {
            set query [lindex $arguments end]
            if {$query eq $wrapper_expected && $wrapper_registered} {
                return [list file::$wrapper_expected]
            }
            if {[string match {*protection_system.bd} $query]} {
                return [list file::protection_system_bd]
            }
            return {}
        }
        get_filesets { return [list $fileset_object] }
        current_fileset { return $fileset_object }
        get_property {
            set property [string toupper [lindex $arguments 0]]
            set object [lindex $arguments 1]
            if {$property eq {IP_REPO_PATHS}} {
                return $repository_paths
            }
            if {[dict exists $properties $object $property]} {
                return [dict get $properties $object $property]
            }
            if {$property eq {NAME} && $object eq $fileset_object} {
                return sources_1
            }
            if {$property eq {NAME} && $object eq file::protection_system_bd} {
                return protection_system.bd
            }
            if {$property eq {NAME} && [string match {file::*} $object]} {
                return [string range $object 6 end]
            }
            return {}
        }
        generate_target {
            set generated_products [list \
                [file join [file dirname $wrapper_expected] .. \
                    protection_system.bd.bmm] \
                [file join [file dirname $wrapper_expected] \
                    protection_system_stub.v]]
            return $generated_products
        }
        make_wrapper {
            if {$wrapper_return eq {}} {
                return [list $wrapper_expected]
            }
            return $wrapper_return
        }
        add_files {
            set wrapper_registered 1
            return {}
        }
        set_property {
            if {[lindex $arguments 0] ne {top}} {
                error "Unexpected set_property invocation: $arguments"
            }
            set top [lindex $arguments 1]
            set object [lindex $arguments 2]
            dict set properties $object TOP $top
            return {}
        }
        default {
            error "Unexpected mock Vivado command: $command $arguments"
        }
    }
}

proc ::stage1e::build_target_adapter_tests::valid_context {name} {
    variable test_root
    variable current_project
    variable properties
    variable wrapper_expected
    variable repository_paths
    set execution_id "STAGE1E-BUILD-TARGET-$name"
    set workspace_root [file normalize [file join $test_root executions $name]]
    set evidence_dir [file join $workspace_root evidence]
    set project_directory [file join $workspace_root project]
    set project_path [file join $project_directory stage1e_design.xpr]
    set bd_path [file join $project_directory stage1e_design.srcs sources_1 bd \
        protection_system protection_system.bd]
    set wrapper_path [file join $project_directory project.gen sources_1 bd \
        protection_system hdl stage1e_design_wrapper.v]
    set repository_root [file normalize [file join $test_root repository]]
    set ip_repo_path [file join $workspace_root ip_repo]
    file mkdir $evidence_dir
    file mkdir [file dirname $bd_path]
    file mkdir [file dirname $wrapper_path]
    file mkdir $ip_repo_path
    set wrapper_expected [file normalize $wrapper_path]
    set repository_paths [list [file normalize $ip_repo_path]]

    set project_identity [dict create \
        project_name stage1e_design \
        project_directory [file normalize $project_directory] \
        project_path [file normalize $project_path] \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0]
    set project_ownership [dict create \
        owner vivado_project execution_id $execution_id \
        project_handle $current_project \
        project_path [file normalize $project_path] \
        identity_verified 1 project_identity $project_identity]
    set bd_ownership [dict create \
        owner bd_flow execution_id $execution_id \
        project_path [file normalize $project_path] \
        bd_name protection_system bd_path [file normalize $bd_path] \
        opened 1 identity_verified 1 validated 1 saved 1]

    dict set properties $current_project NAME stage1e_design
    dict set properties $current_project DIRECTORY \
        [file normalize $project_directory]
    dict set properties $current_project PART xc7z020clg400-1
    dict set properties $current_project BOARD_PART \
        tul.com.tw:pynq-z2:part0:1.0
    dict set properties fileset::sources_1 NAME sources_1

    set hash [string repeat a 64]
    set package_identity [dict create \
        schema_version stage1e-package-identity-v1 \
        execution_id $execution_id \
        vlnv zsr112.local:protection:protection_ip_axi_lite:0.3 \
        top_module protection_ip_top_axi_lite \
        package_sha256 $hash \
        source_inventory_sha256 [string repeat b 64] \
        package_inventory_sha256 [string repeat c 64] \
        component_metadata_sha256 [string repeat d 64] \
        ip_repo_path [file normalize $ip_repo_path]]
    set base_identity [dict create \
        schema_version stage1e-base-design-identity-v1 \
        producer_operation stage1e::base_design::apply \
        execution_id $execution_id project_path [file normalize $project_path] \
        bd_name protection_system bd_path [file normalize $bd_path] \
        identity_sha256 [string repeat e 64]]
    set debug_identity [dict create \
        schema_version stage1e-debug-design-identity-v1 \
        producer_operation stage1e::debug_design::apply \
        execution_id $execution_id project_path [file normalize $project_path] \
        bd_name protection_system bd_path [file normalize $bd_path] \
        identity_sha256 [string repeat f 64]]
    set mutation_identity [dict create \
        schema_version stage1e-controlled-mutation-identity-v1 \
        producer_operation stage1e::mutation_bridge::apply \
        execution_id $execution_id project_path [file normalize $project_path] \
        bd_name protection_system bd_path [file normalize $bd_path] \
        identity_sha256 [string repeat 1 64]]
    return [dict create \
        context_schema_version stage1e-build-target-context-v1 \
        operation stage1e::build_target::prepare \
        phase WRAPPER_GENERATION \
        execution_id $execution_id \
        authorization [dict create \
            status AUTHORIZED authority controller_core \
            execution_id $execution_id \
            operation stage1e::build_target::prepare \
            phase WRAPPER_GENERATION \
            capability wrapper_generation_enabled capability_enabled 1] \
        source_identity [dict create \
            schema_version stage1e-source-identity-v1 \
            execution_id $execution_id repository_root $repository_root \
            git_commit [string repeat 2 40]] \
        environment_identity [dict create \
            schema_version stage1e-environment-identity-v1 \
            execution_id $execution_id vivado_version 2024.1 \
            part xc7z020clg400-1 \
            board_part tul.com.tw:pynq-z2:part0:1.0] \
        configuration_identity [dict create \
            schema_version stage1e-configuration-identity-v1 \
            execution_id $execution_id sha256 [string repeat 3 64]] \
        workspace_root [file normalize $workspace_root] \
        evidence_dir [file normalize $evidence_dir] \
        project_ownership $project_ownership \
        bd_ownership $bd_ownership \
        package_identity $package_identity \
        base_design_identity $base_identity \
        debug_design_identity $debug_identity \
        controlled_mutation_identity $mutation_identity \
        wrapper_name stage1e_design_wrapper \
        wrapper_path_policy [dict create \
            schema_version stage1e-wrapper-path-policy-v1 \
            path [file normalize $wrapper_path]] \
        top_module_policy [dict create \
            schema_version stage1e-top-module-policy-v1 \
            top_module stage1e_design_wrapper fileset sources_1] \
        output_product_policy [dict create \
            schema_version stage1e-output-product-policy-v1 \
            target all products {protection_system.bd.bmm protection_system_stub.v}]]
}

proc ::stage1e::build_target_adapter_tests::assert_no_forbidden {} {
    variable forbidden_count
    assert_equal 0 $forbidden_count {Forbidden-command tripwire count}
}

proc ::stage1e::build_target_adapter_tests::command_index {command} {
    variable invocation_log
    for {set index 0} {$index < [llength $invocation_log]} {incr index} {
        if {[lindex [lindex $invocation_log $index] 0] eq $command} {
            return $index
        }
    }
    return -1
}

proc ::stage1e::build_target_adapter_tests::run_all {} {
    variable invocation_log
    variable wrapper_return
    variable wrapper_expected

    run_case BUILD_TARGET_CONTEXT_VALID {
        reset_mock
        set context [valid_context context_valid]
        set result [::stage1e::build_target::prepare $context]
        assert_status $result PASS {Valid build-target status}
        assert_true [dict exists $result produced_identities \
            build_target_identity] {Build-target identity missing}
        assert_equal [dict get $context project_ownership] \
            [dict get $result ownership_records project_ownership] \
            {Project ownership changed}
        assert_equal [dict get $context bd_ownership] \
            [dict get $result ownership_records bd_ownership] \
            {BD ownership changed}
        assert_true [expr {[command_index generate_target] >= 0}] \
            {BD output products were not generated}
        assert_true [expr {[command_index make_wrapper] > \
            [command_index generate_target]}] {Wrapper ordering invalid}
        assert_true [expr {[command_index add_files] > \
            [command_index make_wrapper]}] {Wrapper add ordering invalid}
        assert_true [expr {[command_index set_property] > \
            [command_index add_files]}] {Top selection ordering invalid}
        assert_no_forbidden
    }

    run_case BUILD_TARGET_AUTH_REJECT {
        reset_mock
        set context [valid_context auth_reject]
        dict set context authorization capability_enabled 0
        set result [::stage1e::build_target::prepare $context]
        assert_status $result BLOCKED {Authorization rejection status}
        assert_equal AUTHORIZATION_MISMATCH [first_error_code $result] \
            {Authorization rejection code}
        assert_equal {} $invocation_log {Authorization reached backend}
    }

    run_case BUILD_TARGET_PROJECT_OWNER_REJECT {
        reset_mock
        set context [valid_context project_owner_reject]
        dict set context project_ownership owner unexpected_owner
        set result [::stage1e::build_target::prepare $context]
        assert_status $result FAIL {Project-owner rejection status}
        assert_equal PROJECT_OWNER_INVALID [first_error_code $result] \
            {Project-owner rejection code}
        assert_equal {} $invocation_log {Project-owner rejection reached backend}
    }

    run_case BUILD_TARGET_BD_OWNER_REJECT {
        reset_mock
        set context [valid_context bd_owner_reject]
        dict set context bd_ownership owner unexpected_owner
        set result [::stage1e::build_target::prepare $context]
        assert_status $result FAIL {BD-owner rejection status}
        assert_equal BD_OWNER_INVALID [first_error_code $result] \
            {BD-owner rejection code}
        assert_equal {} $invocation_log {BD-owner rejection reached backend}
    }

    run_case BUILD_TARGET_UNSAVED_BD_REJECT {
        reset_mock
        set context [valid_context unsaved_bd]
        dict set context bd_ownership saved 0
        set result [::stage1e::build_target::prepare $context]
        assert_status $result FAIL {Unsaved-BD rejection status}
        assert_equal BD_OWNER_STATE_INVALID [first_error_code $result] \
            {Unsaved-BD rejection code}
        assert_equal {} $invocation_log {Unsaved-BD rejection reached backend}
    }

    run_case BUILD_TARGET_WRAPPER_IDENTITY_REJECT {
        reset_mock
        set context [valid_context wrapper_identity_reject]
        set wrapper_return [list [file join [dict get $context workspace_root] \
            project wrong_wrapper.v]]
        set result [::stage1e::build_target::prepare $context]
        assert_status $result FAIL {Wrapper identity rejection status}
        assert_equal WRAPPER_IDENTITY_MISMATCH [first_error_code $result] \
            {Wrapper identity rejection code}
        assert_true [expr {[command_index add_files] < 0}] \
            {Mismatched wrapper was added to the project}
    }

    run_case BUILD_TARGET_RESULT_SCHEMA {
        reset_mock
        set result [::stage1e::build_target::prepare \
            [valid_context result_schema]]
        assert_status $result PASS {Result-schema status}
        foreach key {
            schema_version operation phase execution_id status
            consumed_identities produced_identities ownership_records
            evidence_references warnings errors cleanup_result
        } {
            assert_true [dict exists $result $key] \
            "Result schema missing: $key"
        }
        assert_equal stage1e-build-target-result-v1 \
            [dict get $result schema_version] {Result schema version}
        set identity [dict get $result produced_identities build_target_identity]
        foreach field {
            package_identity_sha256 base_design_identity_sha256
            debug_design_identity_sha256 controlled_mutation_identity_sha256
            output_product_policy_sha256 readback_sha256 identity_sha256
        } {
            assert_true [regexp {^[0-9a-f]{64}$} [dict get $identity $field]] \
                "Build-target identity digest invalid: $field"
        }
    }

    run_case BUILD_TARGET_NO_SYNTHESIS {
        reset_mock
        set result [::stage1e::build_target::prepare [valid_context no_synthesis]]
        assert_status $result PASS {No-synthesis status}
        assert_equal 0 [dict get $result synthesis_performed] \
            {Synthesis was reported}
        assert_no_forbidden
    }

    run_case BUILD_TARGET_NO_IMPLEMENTATION {
        reset_mock
        set result [::stage1e::build_target::prepare \
            [valid_context no_implementation]]
        assert_status $result PASS {No-implementation status}
        assert_equal 0 [dict get $result implementation_performed] \
            {Implementation was reported}
        assert_no_forbidden
    }

    run_case BUILD_TARGET_NO_ARTIFACT {
        reset_mock
        set result [::stage1e::build_target::prepare [valid_context no_artifact]]
        assert_status $result PASS {No-artifact status}
        foreach field {
            artifacts_generated artifact_generation_performed
            artifact_publication_performed
        } {
            assert_equal 0 [dict get $result $field] \
                "Artifact boundary field $field"
        }
        assert_no_forbidden
    }
}

set test_status [catch {
    ::stage1e::build_target_adapter_tests::prepare_suite
    ::stage1e::build_target_adapter_tests::run_all
} test_error test_options]
set cleanup_status [catch {
    ::stage1e::build_target_adapter_tests::safe_cleanup
} cleanup_error cleanup_options]
rename ::stage1e::build_target::backend::invoke {}
rename ::stage1e::build_target::backend::_production_invoke \
    ::stage1e::build_target::backend::invoke

if {$test_status != 0} {
    incr ::stage1e::build_target_adapter_tests::fail_count
    puts stderr "TEST SUITE: FAIL: $test_error"
    if {[dict exists $test_options -errorinfo]} {
        puts stderr [dict get $test_options -errorinfo]
    }
}
if {$cleanup_status != 0} {
    incr ::stage1e::build_target_adapter_tests::fail_count
    puts stderr "TEST CLEANUP: FAIL: $cleanup_error"
    if {[dict exists $cleanup_options -errorinfo]} {
        puts stderr [dict get $cleanup_options -errorinfo]
    }
}

puts "SUMMARY PASS=$::stage1e::build_target_adapter_tests::pass_count FAIL=$::stage1e::build_target_adapter_tests::fail_count"
if {$::stage1e::build_target_adapter_tests::fail_count != 0} {
    exit 1
}
exit 0
