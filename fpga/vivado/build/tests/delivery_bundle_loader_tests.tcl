# Standalone Stage 1D delivery-bundle loader tests.
# This script uses Tcl only and must not invoke Vivado or controller lifecycle code.

namespace eval ::stage1d::delivery_bundle_loader_tests {
    variable pass_count 0
    variable failure_count 0
    variable side_effect_count 0
    variable test_root {}
}

set stage1d_loader_test_dir [file normalize [file dirname [info script]]]
set stage1d_loader_build_root [file normalize \
    [file join $stage1d_loader_test_dir ..]]
set stage1d_loader_repository_root [file normalize \
    [file join $stage1d_loader_build_root .. .. ..]]

source [file join $stage1d_loader_build_root lib source_check.tcl]
source [file join $stage1d_loader_build_root controller \
    delivery_bundle_loader.tcl]

proc ::stage1d::delivery_bundle_loader_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1d::delivery_bundle_loader_tests::assert_equal {
    actual
    expected
    label
} {
    if {$actual ne $expected} {
        fail "$label: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1d::delivery_bundle_loader_tests::assert_true {
    condition
    label
} {
    if {!$condition} {
        fail "$label: condition is false"
    }
}

proc ::stage1d::delivery_bundle_loader_tests::component_status {
    result
    check_name
} {
    foreach component [dict get $result component_results] {
        if {[dict get $component check] eq $check_name} {
            return [dict get $component status]
        }
    }
    fail "component result is missing: $check_name"
}

proc ::stage1d::delivery_bundle_loader_tests::assert_result_check {
    result
    expected_result_status
    check_name
    expected_check_status
} {
    assert_equal [dict get $result status] $expected_result_status \
        "$check_name overall status"
    assert_equal [component_status $result $check_name] \
        $expected_check_status "$check_name component status"
}

proc ::stage1d::delivery_bundle_loader_tests::run_case {name body} {
    variable pass_count
    variable failure_count
    set case_status [catch {uplevel 1 $body} case_error case_options]
    if {$case_status != 0} {
        incr failure_count
        puts stderr "FAIL $name: $case_error"
        if {[dict exists $case_options -errorinfo]} {
            puts stderr [dict get $case_options -errorinfo]
        }
        return
    }
    incr pass_count
    puts "PASS $name"
}

proc ::stage1d::delivery_bundle_loader_tests::write_text {path content} {
    file mkdir [file dirname $path]
    set channel [open $path w]
    fconfigure $channel -encoding utf-8 -translation lf
    puts -nonewline $channel $content
    close $channel
}

proc ::stage1d::delivery_bundle_loader_tests::finalize_profile {profile} {
    dict set profile profile_sha256 [string repeat 0 64]
    dict set profile profile_sha256 \
        [::stage1d::delivery_bundle_loader::profile_fingerprint $profile]
    return $profile
}

proc ::stage1d::delivery_bundle_loader_tests::finalize_manifest {manifest} {
    dict set manifest manifest_sha256 [string repeat 0 64]
    dict set manifest manifest_sha256 \
        [::stage1d::delivery_bundle_loader::manifest_fingerprint $manifest]
    return $manifest
}

proc ::stage1d::delivery_bundle_loader_tests::write_profile {
    root
    profile
    {relative_path profile/stage1d_controlled_dry_run_v1.dict}
} {
    write_text [file join $root {*}[split $relative_path /]] \
        [::stage1d::delivery_bundle_loader::serialize_profile $profile]
}

proc ::stage1d::delivery_bundle_loader_tests::write_manifest {
    root
    manifest
} {
    write_text [file join $root manifest.dict] \
        [::stage1d::delivery_bundle_loader::serialize_manifest $manifest]
}

proc ::stage1d::delivery_bundle_loader_tests::write_source_reference {
    root
    source_reference
} {
    write_text [file join $root source_reference] \
        [::stage1d::delivery_bundle_loader::serialize_source_reference \
            $source_reference]
}

proc ::stage1d::delivery_bundle_loader_tests::create_valid_bundle {root} {
    file mkdir [file join $root profile]

    set source_revision [string repeat a 40]
    set source_identity [dict create \
        git_commit $source_revision \
        controller_source_hash [string repeat b 64] \
        configuration_hash [string repeat c 64] \
        source_inventory [list [dict create \
            path rtl/protection_core_top.v \
            size 4096 \
            sha256 [string repeat d 64]]]]
    set environment_identity [dict create \
        vivado_version {Vivado v2024.1} \
        fpga_part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        required_ip_identities [list \
            xilinx.com:ip:processing_system7:5.5 \
            xilinx.com:ip:smartconnect:1.0 \
            zsr112.local:protection:protection_ip_axi_lite:0.3]]
    set profile [dict create \
        schema_version v1 \
        profile_id stage1d_controlled_dry_run_v1 \
        profile_version v1 \
        profile_sha256 [string repeat 0 64] \
        source_revision $source_revision \
        environment_identity $environment_identity \
        scope [dict create \
            phase_limit MUTATION_EXECUTE \
            project_operations 1 \
            design_operations 1 \
            mutation_operations 1] \
        evidence_policy [dict create \
            require_execution_id 1 \
            require_source_identity 1 \
            require_environment_identity 1 \
            require_evidence_dir 1]]
    set profile [finalize_profile $profile]

    set profile_path profile/stage1d_controlled_dry_run_v1.dict
    set manifest [dict create \
        schema_version v1 \
        bundle_id stage1d-dry-run-v1 \
        manifest_sha256 [string repeat 0 64] \
        source_revision $source_revision \
        source_identity $source_identity \
        profile_path $profile_path \
        profile_sha256 [dict get $profile profile_sha256] \
        environment_identity $environment_identity \
        provenance [dict create \
            created_at 2026-07-15T00:00:00Z \
            created_by delivery_bundle_loader_tests \
            derivation TEST_FIXTURE \
            review_status REVIEWED \
            reviewed_by delivery_bundle_loader_tests]]
    set manifest [finalize_manifest $manifest]
    set source_reference [dict create \
        source_revision $source_revision \
        source_identity $source_identity]

    write_profile $root $profile $profile_path
    write_manifest $root $manifest
    write_source_reference $root $source_reference
    return [dict create \
        root $root \
        profile $profile \
        manifest $manifest \
        source_reference $source_reference \
        source_identity $source_identity \
        environment_identity $environment_identity]
}

proc ::stage1d::delivery_bundle_loader_tests::new_fixture {name} {
    variable test_root
    set root [file join $test_root $name]
    return [create_valid_bundle $root]
}

proc ::stage1d::delivery_bundle_loader_tests::load_fixture {
    fixture
    {source_identity {}}
    {environment_identity {}}
} {
    if {$source_identity eq {}} {
        set source_identity [dict get $fixture source_identity]
    }
    if {$environment_identity eq {}} {
        set environment_identity [dict get $fixture environment_identity]
    }
    return [::stage1d::delivery_bundle_loader::load \
        [dict get $fixture root] $source_identity $environment_identity]
}

proc ::stage1d::delivery_bundle_loader_tests::rewrite_valid_profile {
    fixture_variable
    profile
} {
    upvar 1 $fixture_variable fixture
    set profile [finalize_profile $profile]
    dict set fixture profile $profile
    set manifest [dict get $fixture manifest]
    dict set manifest profile_sha256 [dict get $profile profile_sha256]
    set manifest [finalize_manifest $manifest]
    dict set fixture manifest $manifest
    write_profile [dict get $fixture root] $profile \
        [dict get $manifest profile_path]
    write_manifest [dict get $fixture root] $manifest
}

proc ::stage1d::delivery_bundle_loader_tests::rewrite_valid_manifest {
    fixture_variable
    manifest
} {
    upvar 1 $fixture_variable fixture
    set manifest [finalize_manifest $manifest]
    dict set fixture manifest $manifest
    write_manifest [dict get $fixture root] $manifest
}

proc ::stage1d::delivery_bundle_loader_tests::run_all {} {
    variable side_effect_count
    variable test_root
    variable failure_count
    variable pass_count
    global stage1d_loader_repository_root
    global stage1d_loader_build_root

    run_case SHA256_KNOWN_VECTOR {
        assert_equal \
            [::stage1d::source_check::sha256_text abc] \
            ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad \
            {SHA-256 known vector}
    }

    run_case TCL_MODULE_SOURCE_TIME_SYNTAX_AND_SIDE_EFFECT_FREE {
        set module_paths [list \
            controller/argument_parser.tcl \
            controller/configuration_loader.tcl \
            controller/logger.tcl \
            controller/state_manager.tcl \
            controller/phase_runner.tcl \
            controller/decision_engine.tcl \
            lib/source_check.tcl \
            controller/delivery_bundle_loader.tcl \
            lib/environment_check.tcl \
            lib/workspace_manager.tcl \
            lib/vivado_project.tcl \
            lib/bd_flow.tcl \
            mutation/stage1d_controlled_stimulus.tcl \
            controller/controller_core.tcl]
        foreach relative_path $module_paths {
            source [file join $stage1d_loader_build_root \
                {*}[split $relative_path /]]
        }
        set wrapper_path [file join $stage1d_loader_build_root \
            stage1d_artifact_build.tcl]
        set wrapper_text \
            [::stage1d::delivery_bundle_loader::_read_text_file \
                $wrapper_path {Stage 1D wrapper} \
                BUNDLE_MANIFEST_SCHEMA_VALID FAIL]
        assert_true [info complete $wrapper_text] \
            {Stage 1D wrapper Tcl syntax completeness}
        assert_true \
            [expr {[string first delivery_bundle_loader.tcl \
                $wrapper_text] >= 0}] \
            {Stage 1D wrapper sources the delivery bundle loader}
        assert_equal $side_effect_count 0 {module source-time side effects}
    }

    run_case VALID_BUNDLE_ALL_REQUIRED_CHECKS {
        set fixture [new_fixture valid]
        set result [load_fixture $fixture]
        assert_equal [dict get $result status] PASS {valid bundle status}
        foreach check_name \
            [::stage1d::delivery_bundle_loader::required_checks] {
            assert_equal [component_status $result $check_name] PASS \
                "$check_name valid result"
            assert_true [dict get $result outputs $check_name] \
                "$check_name output marker"
        }
        foreach side_effect [dict values \
            [dict get $result outputs side_effects]] {
            assert_equal $side_effect 0 {loader side effect counter}
        }
        assert_true [dict get $result outputs STATIC_SIDE_EFFECT_FREE] \
            STATIC_SIDE_EFFECT_FREE
        assert_true \
            [expr {![dict exists $result authorization_assertion]}] \
            {loader result excludes authorization_assertion}
        assert_equal [dict get $result outputs authorization_assertion_generated] \
            0 {authorization assertion generation}
    }

    run_case BUNDLE_MANIFEST_SCHEMA_REJECTS_UNKNOWN_FIELD {
        set fixture [new_fixture manifest_schema_unknown]
        set manifest [dict get $fixture manifest]
        dict set manifest unknown_field rejected
        write_text [file join [dict get $fixture root] manifest.dict] \
            "$manifest\n"
        set result [load_fixture $fixture]
        assert_result_check $result FAIL \
            BUNDLE_MANIFEST_SCHEMA_VALID FAIL
    }

    run_case BUNDLE_MANIFEST_HASH_MISMATCH_REJECTED {
        set fixture [new_fixture manifest_hash_mismatch]
        set manifest [dict get $fixture manifest]
        dict set manifest bundle_id stage1d-dry-run-tampered
        dict set fixture manifest $manifest
        write_manifest [dict get $fixture root] $manifest
        set result [load_fixture $fixture]
        assert_result_check $result FAIL \
            BUNDLE_MANIFEST_HASH_VALID FAIL
    }

    run_case BUNDLE_ABSOLUTE_PROFILE_PATH_REJECTED {
        set fixture [new_fixture absolute_path]
        set manifest [dict get $fixture manifest]
        dict set manifest profile_path /ambient/profile.dict
        rewrite_valid_manifest fixture $manifest
        set result [load_fixture $fixture]
        assert_result_check $result FAIL \
            BUNDLE_PATH_CONTAINMENT_VALID FAIL
    }

    run_case BUNDLE_TRAVERSAL_PROFILE_PATH_REJECTED {
        set fixture [new_fixture traversal_path]
        set manifest [dict get $fixture manifest]
        dict set manifest profile_path profile/../outside.dict
        rewrite_valid_manifest fixture $manifest
        set result [load_fixture $fixture]
        assert_result_check $result FAIL \
            BUNDLE_PATH_CONTAINMENT_VALID FAIL
    }

    run_case BUNDLE_DOES_NOT_DISCOVER_AMBIENT_PROFILE {
        set fixture [new_fixture no_ambient_discovery]
        set manifest [dict get $fixture manifest]
        dict set manifest profile_path profile/not_selected.dict
        rewrite_valid_manifest fixture $manifest
        set result [load_fixture $fixture]
        assert_result_check $result BLOCKED \
            BUNDLE_PATH_CONTAINMENT_VALID BLOCKED
    }

    run_case PROFILE_SCHEMA_VERSION_UNSUPPORTED_REJECTED {
        set fixture [new_fixture unsupported_profile_schema]
        set profile [dict get $fixture profile]
        dict set profile schema_version v999
        rewrite_valid_profile fixture $profile
        set result [load_fixture $fixture]
        assert_result_check $result FAIL \
            PROFILE_SCHEMA_VERSION_SUPPORTED FAIL
    }

    run_case PROFILE_REQUIRED_FIELD_MISSING_REJECTED {
        set fixture [new_fixture missing_profile_field]
        set profile [dict get $fixture profile]
        dict unset profile profile_version
        write_text [file join [dict get $fixture root] profile \
            stage1d_controlled_dry_run_v1.dict] "$profile\n"
        set result [load_fixture $fixture]
        assert_result_check $result FAIL \
            PROFILE_REQUIRED_FIELDS_VALID FAIL
    }

    run_case PROFILE_HASH_MISMATCH_REJECTED {
        set fixture [new_fixture profile_hash_mismatch]
        set profile [dict get $fixture profile]
        dict set profile profile_sha256 [string repeat 0 64]
        dict set fixture profile $profile
        set manifest [dict get $fixture manifest]
        dict set manifest profile_sha256 [string repeat 0 64]
        rewrite_valid_manifest fixture $manifest
        write_profile [dict get $fixture root] $profile
        set result [load_fixture $fixture]
        assert_result_check $result FAIL PROFILE_HASH_VALID FAIL
    }

    run_case PROFILE_SCOPE_OUTSIDE_STAGE1D_REJECTED {
        set fixture [new_fixture profile_scope_invalid]
        set profile [dict get $fixture profile]
        dict set profile scope phase_limit SYNTHESIS
        rewrite_valid_profile fixture $profile
        set result [load_fixture $fixture]
        assert_result_check $result BLOCKED PROFILE_SCOPE_VALID BLOCKED
    }

    run_case PROFILE_ENVIRONMENT_MISMATCH_REJECTED {
        set fixture [new_fixture environment_mismatch]
        set accepted_environment [dict get $fixture environment_identity]
        dict set accepted_environment board_part \
            example.invalid:board:part0:1.0
        set result [load_fixture $fixture {} $accepted_environment]
        assert_result_check $result BLOCKED \
            PROFILE_ENVIRONMENT_BINDING_VALID BLOCKED
    }

    run_case PROFILE_COMMAND_SUBSTITUTION_REJECTED_WITHOUT_EXECUTION {
        set fixture [new_fixture command_substitution]
        set ::stage1d_loader_side_effect 0
        set malicious_profile \
            {schema_version v1 profile_id [set ::stage1d_loader_side_effect 1]}
        write_text [file join [dict get $fixture root] profile \
            stage1d_controlled_dry_run_v1.dict] "$malicious_profile\n"
        set result [load_fixture $fixture]
        assert_result_check $result FAIL PROFILE_PARSE_SIDE_EFFECT_FREE FAIL
        assert_equal $::stage1d_loader_side_effect 0 \
            {command substitution was not executed}
    }

    run_case PROFILE_VARIABLE_SUBSTITUTION_REJECTED_WITHOUT_EXECUTION {
        set fixture [new_fixture variable_substitution]
        set ::stage1d_loader_side_effect 0
        set malicious_profile \
            {schema_version v1 profile_id $::stage1d_loader_side_effect}
        write_text [file join [dict get $fixture root] profile \
            stage1d_controlled_dry_run_v1.dict] "$malicious_profile\n"
        set result [load_fixture $fixture]
        assert_result_check $result FAIL PROFILE_PARSE_SIDE_EFFECT_FREE FAIL
        assert_equal $::stage1d_loader_side_effect 0 \
            {variable substitution was not executed}
    }

    run_case PROFILE_SOURCE_STATEMENT_REJECTED_WITHOUT_EXECUTION {
        set fixture [new_fixture source_statement]
        set ::stage1d_loader_side_effect 0
        set malicious_script [file join [dict get $fixture root] malicious.tcl]
        write_text $malicious_script \
            {set ::stage1d_loader_side_effect 1}
        set malicious_profile "source [list $malicious_script]\n"
        write_text [file join [dict get $fixture root] profile \
            stage1d_controlled_dry_run_v1.dict] $malicious_profile
        set result [load_fixture $fixture]
        assert_result_check $result FAIL PROFILE_PARSE_SIDE_EFFECT_FREE FAIL
        assert_equal $::stage1d_loader_side_effect 0 \
            {source statement was not executed}
    }

    run_case PROFILE_SOURCE_REVISION_MISMATCH_REJECTED {
        set fixture [new_fixture source_revision_mismatch]
        set accepted_source [dict get $fixture source_identity]
        dict set accepted_source git_commit [string repeat e 40]
        set result [load_fixture $fixture $accepted_source]
        assert_result_check $result BLOCKED \
            PROFILE_SOURCE_BINDING_VALID BLOCKED
    }

    run_case SOURCE_REFERENCE_MISMATCH_REJECTED {
        set fixture [new_fixture source_reference_mismatch]
        set source_reference [dict get $fixture source_reference]
        dict set source_reference source_revision [string repeat e 40]
        write_source_reference [dict get $fixture root] $source_reference
        set result [load_fixture $fixture]
        assert_result_check $result BLOCKED \
            PROFILE_SOURCE_BINDING_VALID BLOCKED
    }

    run_case CONFIGURATION_SYNTAX_AND_CONTROLLER_HASH_ALIGNMENT {
        set configuration_path [file join $stage1d_loader_build_root \
            config stage1d_build_config.dict]
        set configuration_text [string trim \
            [::stage1d::delivery_bundle_loader::_read_text_file \
                $configuration_path configuration \
                BUNDLE_MANIFEST_SCHEMA_VALID FAIL]]
        assert_true [expr {![catch {dict size $configuration_text}]}] \
            {configuration Tcl dictionary syntax}
        set configuration $configuration_text
        set supported_versions [dict create]
        foreach version_field {
            schema_version
            controller_version
            controller_api_version
            execution_id_schema_version
            phase_evidence_schema_version
            decision_schema_version
            manifest_schema_version
        } {
            dict set supported_versions $version_field \
                [dict get $configuration $version_field]
        }
        set loaded_configuration \
            [::stage1d::configuration_loader::load \
                $configuration_path $supported_versions]
        assert_equal [dict get $loaded_configuration schema_version] v1 \
            {configuration loader schema validation}
        set controller_paths [dict get $configuration \
            source_verification controller_source_paths]
        set inventory [::stage1d::source_check::hash_inventory \
            $stage1d_loader_repository_root $controller_paths]
        set actual_hash [::stage1d::source_check::aggregate_inventory_hash \
            $inventory]
        assert_equal $actual_hash [dict get $configuration \
            source_verification expected_controller_source_sha256] \
            {controller source hash alignment}
    }

    foreach check_name \
        [::stage1d::delivery_bundle_loader::required_checks] {
        puts "$check_name: PASS"
    }
    puts {STATIC_SIDE_EFFECT_FREE: PASS}

    if {$failure_count != 0} {
        error "Delivery-bundle loader tests failed: $failure_count"
    }
    puts "SUMMARY PASS=$pass_count FAIL=$failure_count"
}

set stage1d_loader_temp_parent $stage1d_loader_repository_root
set ::stage1d::delivery_bundle_loader_tests::test_root [file normalize \
    [file join $stage1d_loader_temp_parent \
        "stage1d_delivery_bundle_loader_[pid]_[clock clicks]"]]
file mkdir $::stage1d::delivery_bundle_loader_tests::test_root

set stage1d_loader_test_status [catch {
    ::stage1d::delivery_bundle_loader_tests::run_all
} stage1d_loader_test_error stage1d_loader_test_options]

set stage1d_loader_cleanup_root \
    $::stage1d::delivery_bundle_loader_tests::test_root
set stage1d_loader_cleanup_parent [file dirname $stage1d_loader_cleanup_root]
if {[file normalize $stage1d_loader_cleanup_parent] ne \
    [file normalize $stage1d_loader_temp_parent] ||
    ![string match {stage1d_delivery_bundle_loader_*} \
        [file tail $stage1d_loader_cleanup_root]]} {
    puts stderr {Refusing test cleanup outside the verified temporary parent.}
    exit 1
}
file delete -force -- $stage1d_loader_cleanup_root

if {$stage1d_loader_test_status != 0} {
    puts stderr $stage1d_loader_test_error
    if {[dict exists $stage1d_loader_test_options -errorinfo]} {
        puts stderr [dict get $stage1d_loader_test_options -errorinfo]
    }
    exit 1
}
exit 0
