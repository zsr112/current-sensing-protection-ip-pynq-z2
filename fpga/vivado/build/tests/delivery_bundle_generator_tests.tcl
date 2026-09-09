# Standalone Stage 1D delivery-bundle generator tests.
# This script uses Tcl only and must not invoke Vivado or lifecycle code.

namespace eval ::stage1d::delivery_bundle_generator_tests {
    variable pass_count 0
    variable failure_count 0
    variable test_root {}
}

set stage1d_generator_test_dir [file normalize [file dirname [info script]]]
set stage1d_generator_build_root [file normalize \
    [file join $stage1d_generator_test_dir ..]]
set stage1d_generator_repository_root [file normalize \
    [file join $stage1d_generator_build_root .. .. ..]]

source [file join $stage1d_generator_build_root lib source_check.tcl]
source [file join $stage1d_generator_build_root controller \
    delivery_bundle_loader.tcl]
source [file join $stage1d_generator_build_root controller \
    delivery_bundle_generator.tcl]

proc ::stage1d::delivery_bundle_generator_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1d::delivery_bundle_generator_tests::assert_equal {
    actual
    expected
    label
} {
    if {$actual ne $expected} {
        fail "$label: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1d::delivery_bundle_generator_tests::assert_true {
    condition
    label
} {
    if {!$condition} {
        fail "$label: condition is false"
    }
}

proc ::stage1d::delivery_bundle_generator_tests::run_case {name body} {
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

proc ::stage1d::delivery_bundle_generator_tests::assert_generator_error {
    body
    expected_check
    expected_code
} {
    set call_status [catch {uplevel 1 $body} call_error call_options]
    assert_equal $call_status 1 "$expected_check rejection status"
    if {![dict exists $call_options -errorcode]} {
        fail "$expected_check rejection has no errorcode: $call_error"
    }
    set error_code [dict get $call_options -errorcode]
    assert_equal [llength $error_code] 5 \
        "$expected_check errorcode length"
    assert_equal [lrange $error_code 0 2] \
        {STAGE1D DELIVERY_BUNDLE_GENERATOR FAIL} \
        "$expected_check errorcode prefix"
    assert_equal [lindex $error_code 3] $expected_check \
        "$expected_check errorcode check"
    assert_equal [lindex $error_code 4] $expected_code \
        "$expected_check errorcode reason"
}

proc ::stage1d::delivery_bundle_generator_tests::read_text {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set content [read $channel]
    close $channel
    return $content
}

proc ::stage1d::delivery_bundle_generator_tests::read_binary {path} {
    set channel [open $path r]
    fconfigure $channel -encoding binary -translation binary
    set content [read $channel]
    close $channel
    return $content
}

proc ::stage1d::delivery_bundle_generator_tests::new_output_parent {name} {
    variable test_root
    set output_parent [file normalize [file join $test_root $name]]
    file mkdir $output_parent
    return $output_parent
}

proc ::stage1d::delivery_bundle_generator_tests::bundle_root {
    output_parent
} {
    return [file normalize [file join $output_parent stage1d-dry-run-v1]]
}

proc ::stage1d::delivery_bundle_generator_tests::bundle_snapshot {root} {
    set snapshot {}
    foreach relative_path {
        manifest.dict
        profile/stage1d_controlled_dry_run_v1.dict
        source_reference
    } {
        set path [file join $root {*}[split $relative_path /]]
        lappend snapshot $relative_path [read_binary $path]
    }
    return $snapshot
}

proc ::stage1d::delivery_bundle_generator_tests::assert_bundle_layout {
    root
} {
    assert_equal \
        [lsort [glob -nocomplain -tails -directory $root *]] \
        {manifest.dict profile source_reference} \
        {bundle root members}
    assert_equal [glob -nocomplain -tails \
        -directory [file join $root profile] *] \
        {stage1d_controlled_dry_run_v1.dict} \
        {bundle profile members}
    foreach relative_path {
        manifest.dict
        profile/stage1d_controlled_dry_run_v1.dict
        source_reference
    } {
        assert_true [file isfile \
            [file join $root {*}[split $relative_path /]]] \
            "bundle member exists: $relative_path"
    }
}

proc ::stage1d::delivery_bundle_generator_tests::valid_request {} {
    set source_revision [string repeat a 40]
    set source_identity [dict create \
        git_commit $source_revision \
        controller_source_hash [string repeat b 64] \
        configuration_hash [string repeat c 64] \
        source_inventory [list \
            [dict create \
                path rtl/protection_core_top.v \
                size 4096 \
                sha256 [string repeat d 64]] \
            [dict create \
                path fpga/vivado/build/controller/controller_core.tcl \
                size 8192 \
                sha256 [string repeat e 64]]]]
    set environment_identity [dict create \
        vivado_version {Vivado v2024.1} \
        fpga_part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        required_ip_identities [list \
            xilinx.com:ip:processing_system7:5.5 \
            xilinx.com:ip:smartconnect:1.0 \
            zsr112.local:protection:protection_ip_axi_lite:0.3]]
    return [dict create \
        schema_version v1 \
        bundle_id stage1d-dry-run-v1 \
        profile_id stage1d_controlled_dry_run_v1 \
        profile_version v1 \
        source_revision $source_revision \
        source_identity $source_identity \
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
            require_evidence_dir 1] \
        provenance [dict create \
            source_revision $source_revision \
            generator_identity \
                STAGE1D-DELIVERY-BUNDLE-GENERATOR-v1 \
            generation_timestamp 2026-07-15T00:00:00Z \
            review_provenance stage1d-generator-review-v1]]
}

proc ::stage1d::delivery_bundle_generator_tests::run_all {} {
    variable failure_count
    variable pass_count
    global stage1d_generator_build_root

    run_case TCL_MODULE_AND_CONFIGURATION_SYNTAX {
        set generator_path [file join $stage1d_generator_build_root \
            controller delivery_bundle_generator.tcl]
        set generator_text [read_text $generator_path]
        assert_true [info complete $generator_text] \
            {generator Tcl syntax completeness}
        source $generator_path
        assert_equal \
            [::stage1d::delivery_bundle_generator::version] \
            STAGE1D-DELIVERY-BUNDLE-GENERATOR-v1 \
            {generator version}

        set configuration_path [file join $stage1d_generator_build_root \
            config stage1d_build_config.dict]
        set configuration_text [string trim [read_text $configuration_path]]
        assert_true [expr {![catch {dict size $configuration_text}]}] \
            {configuration Tcl dictionary syntax}
    }

    run_case GENERATOR_VALID_OUTPUT_LOADS_WITH_ALL_BINDINGS {
        set output_parent [new_output_parent valid_output]
        set request [valid_request]
        set result [::stage1d::delivery_bundle_generator::generate \
            $output_parent $request]
        assert_equal [dict get $result status] PASS {generator status}
        set root [dict get $result bundle_root]
        assert_equal $root [bundle_root $output_parent] \
            {explicit bundle root}
        assert_bundle_layout $root

        set loader_result [::stage1d::delivery_bundle_loader::load \
            $root \
            [dict get $request source_identity] \
            [dict get $request environment_identity]]
        assert_equal [dict get $loader_result status] PASS \
            {generated bundle loader status}
        foreach component [dict get $loader_result component_results] {
            assert_equal [dict get $component status] PASS \
                "loader check [dict get $component check]"
        }
        assert_equal \
            [dict get $result bundle_identity manifest_sha256] \
            [dict get $loader_result bundle_identity manifest_sha256] \
            {manifest hash binding}
        assert_equal \
            [dict get $result profile_identity profile_sha256] \
            [dict get $loader_result profile_identity profile_sha256] \
            {profile hash binding}
        assert_equal [dict get $result source_identity git_commit] \
            [dict get $request source_revision] {source binding}
        assert_equal [dict get $result environment_identity] \
            [dict get $request environment_identity] \
            {environment binding}
    }

    run_case GENERATOR_DETERMINISTIC_OUTPUT_AND_REPRODUCIBILITY {
        set request [valid_request]
        set first_parent [new_output_parent deterministic_first]
        set second_parent [new_output_parent deterministic_second]
        set ::stage1d_generator_execution_id EXECUTION-A
        set first [::stage1d::delivery_bundle_generator::generate \
            $first_parent $request]
        set ::stage1d_generator_execution_id EXECUTION-B
        set second [::stage1d::delivery_bundle_generator::generate \
            $second_parent $request]
        unset ::stage1d_generator_execution_id

        assert_equal \
            [bundle_snapshot [dict get $first bundle_root]] \
            [bundle_snapshot [dict get $second bundle_root]] \
            {canonical bundle bytes}
        assert_equal [dict get $first bundle_identity] \
            [dict get $second bundle_identity] \
            {bundle identity independent of output and execution identifier}
        assert_equal \
            [dict get $first profile_identity profile_sha256] \
            [dict get $second profile_identity profile_sha256] \
            {deterministic profile hash}
        assert_equal \
            [dict get $first bundle_identity manifest_sha256] \
            [dict get $second bundle_identity manifest_sha256] \
            {deterministic manifest hash}
    }

    run_case GENERATOR_NO_AMBIENT_DEPENDENCY {
        set request [valid_request]
        set first_parent [new_output_parent ambient_first]
        set second_parent [new_output_parent ambient_second]
        set first_working [new_output_parent working_first]
        set second_working [new_output_parent working_second]
        set saved_directory [file normalize [pwd]]
        set environment_names {
            USERPROFILE USERNAME COMPUTERNAME VIVADO_PATH XILINX_VIVADO
        }
        set saved_environment [dict create]
        foreach name $environment_names {
            if {[info exists ::env($name)]} {
                dict set saved_environment $name \
                    [list 1 $::env($name)]
            } else {
                dict set saved_environment $name [list 0 {}]
            }
        }

        try {
            cd $first_working
            foreach name $environment_names {
                set ::env($name) AMBIENT-FIRST
            }
            set first [::stage1d::delivery_bundle_generator::generate \
                $first_parent $request]

            cd $second_working
            foreach name $environment_names {
                set ::env($name) AMBIENT-SECOND
            }
            set second [::stage1d::delivery_bundle_generator::generate \
                $second_parent $request]
        } finally {
            cd $saved_directory
            foreach name $environment_names {
                lassign [dict get $saved_environment $name] existed value
                if {$existed} {
                    set ::env($name) $value
                } else {
                    unset -nocomplain ::env($name)
                }
            }
        }

        assert_equal \
            [bundle_snapshot [dict get $first bundle_root]] \
            [bundle_snapshot [dict get $second bundle_root]] \
            {bundle independent of ambient state}

        set generator_text [read_text [file join \
            $stage1d_generator_build_root controller \
            delivery_bundle_generator.tcl]]
        foreach forbidden_call {
            {::env(}
            {[pwd]}
            {[info hostname]}
            {[clock }
            {[pid]}
            {open_project }
            {open_bd_design }
        } {
            assert_true [expr {[string first $forbidden_call \
                $generator_text] < 0}] \
                "ambient read or Vivado call absent: $forbidden_call"
        }
    }

    run_case GENERATOR_SIDE_EFFECT_FREE_AND_BOUNDED_MEMBERS {
        set ::stage1d_generator_forbidden_calls 0
        foreach command_name {
            open_project
            open_bd_design
            validate_bd_design
            save_bd_design
        } {
            proc ::$command_name args {
                incr ::stage1d_generator_forbidden_calls
                error {forbidden Vivado command invoked}
            }
        }
        namespace eval ::stage1d_controlled_stimulus {}
        proc ::stage1d_controlled_stimulus::apply args {
            incr ::stage1d_generator_forbidden_calls
            error {forbidden mutation invoked}
        }

        try {
            set output_parent [new_output_parent side_effect_free]
            set result [::stage1d::delivery_bundle_generator::generate \
                $output_parent [valid_request]]
            assert_equal $::stage1d_generator_forbidden_calls 0 \
                {Vivado lifecycle and mutation calls}
            assert_bundle_layout [dict get $result bundle_root]
            foreach count [dict values \
                [dict get $result outputs side_effects]] {
                assert_equal $count 0 {reported generator side effect}
            }
            assert_equal \
                [dict get $result outputs authorization_assertion_generated] \
                0 {authorization assertion generation}
        } finally {
            foreach command_name {
                open_project
                open_bd_design
                validate_bd_design
                save_bd_design
            } {
                rename ::$command_name {}
            }
            rename ::stage1d_controlled_stimulus::apply {}
            namespace delete ::stage1d_controlled_stimulus
            unset -nocomplain ::stage1d_generator_forbidden_calls
        }
    }

    run_case GENERATOR_SOURCE_MISMATCH_REJECTED {
        set output_parent [new_output_parent source_mismatch]
        set request [valid_request]
        dict set request source_revision [string repeat f 40]
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_SOURCE_BINDING_VALID SOURCE_REVISION_MISMATCH
        assert_true [expr {![file exists [bundle_root $output_parent]]}] \
            {source mismatch creates no bundle}
    }

    run_case GENERATOR_INVALID_SCHEMA_SCOPE_AND_POLICY_REJECTED {
        set output_parent [new_output_parent invalid_contract]

        set request [valid_request]
        dict set request unknown_field rejected
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_SCHEMA_VALID FIELD_SET_INVALID

        set request [valid_request]
        dict set request scope phase_limit SYNTHESIS
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_SCHEMA_VALID PROFILE_SCOPE_INVALID

        set request [valid_request]
        dict set request evidence_policy require_execution_id 0
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_SCHEMA_VALID EVIDENCE_POLICY_INVALID

        set request [valid_request]
        dict unset request environment_identity board_part
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_ENVIRONMENT_BINDING_VALID FIELD_SET_INVALID

        assert_true [expr {![file exists [bundle_root $output_parent]]}] \
            {invalid request creates no bundle}
    }

    run_case GENERATOR_UNSAFE_VALUES_AND_AUTHOR_PATHS_REJECTED {
        set output_parent [new_output_parent unsafe_values]

        set request [valid_request]
        dict set request profile_version {$ambient_profile_version}
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_SCHEMA_VALID EXECUTABLE_OR_AMBIENT_VALUE_REJECTED

        set request [valid_request]
        dict set request provenance review_provenance \
            {[set ::stage1d_generator_forbidden_calls 1]}
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_SCHEMA_VALID EXECUTABLE_OR_AMBIENT_VALUE_REJECTED

        set request [valid_request]
        set inventory [dict get $request source_identity source_inventory]
        set first_entry [lindex $inventory 0]
        dict set first_entry path /private_source.v
        set inventory [lreplace $inventory 0 0 $first_entry]
        dict set request source_identity source_inventory $inventory
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_NO_AMBIENT_DEPENDENCY \
            ABSOLUTE_AUTHOR_PATH_REJECTED

        assert_true [expr {![file exists [bundle_root $output_parent]]}] \
            {unsafe input creates no bundle}
    }

    run_case GENERATOR_AMBIENT_OUTPUT_AND_EXECUTION_FIELD_REJECTED {
        set request [valid_request]
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                relative-output $request
        } GENERATOR_NO_AMBIENT_DEPENDENCY \
            EXPLICIT_ABSOLUTE_OUTPUT_PARENT_REQUIRED

        set output_parent [new_output_parent execution_field]
        dict set request execution_id forbidden
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_SCHEMA_VALID FIELD_SET_INVALID
        assert_true [expr {![file exists [bundle_root $output_parent]]}] \
            {execution identifier creates no bundle}
    }

    run_case GENERATOR_IMMUTABLE_OUTPUT_NOT_OVERWRITTEN {
        set output_parent [new_output_parent immutable_output]
        set request [valid_request]
        set first [::stage1d::delivery_bundle_generator::generate \
            $output_parent $request]
        set before [bundle_snapshot [dict get $first bundle_root]]
        assert_generator_error {
            ::stage1d::delivery_bundle_generator::generate \
                $output_parent $request
        } GENERATOR_SIDE_EFFECT_FREE IMMUTABLE_BUNDLE_EXISTS
        set after [bundle_snapshot [dict get $first bundle_root]]
        assert_equal $after $before {immutable bundle content}
    }

    if {$failure_count != 0} {
        error "Delivery-bundle generator tests failed: $failure_count"
    }
    foreach check_name \
        [::stage1d::delivery_bundle_generator::required_checks] {
        puts "$check_name: PASS"
    }
    puts {TCL_SYNTAX: PASS}
    puts {CONFIGURATION_SYNTAX: PASS}
    puts {NO_VIVADO_EXECUTION: PASS}
    puts "SUMMARY PASS=$pass_count FAIL=$failure_count"
}

set stage1d_generator_temp_parent $stage1d_generator_repository_root
set ::stage1d::delivery_bundle_generator_tests::test_root [file normalize \
    [file join $stage1d_generator_temp_parent \
        "stage1d_delivery_bundle_generator_[pid]_[clock clicks]"]]
file mkdir $::stage1d::delivery_bundle_generator_tests::test_root

set stage1d_generator_test_status [catch {
    ::stage1d::delivery_bundle_generator_tests::run_all
} stage1d_generator_test_error stage1d_generator_test_options]

set stage1d_generator_cleanup_root \
    $::stage1d::delivery_bundle_generator_tests::test_root
set stage1d_generator_cleanup_parent \
    [file dirname $stage1d_generator_cleanup_root]
if {[file normalize $stage1d_generator_cleanup_parent] ne \
    [file normalize $stage1d_generator_temp_parent] ||
    ![string match {stage1d_delivery_bundle_generator_*} \
        [file tail $stage1d_generator_cleanup_root]]} {
    puts stderr {Refusing test cleanup outside the verified temporary parent.}
    exit 1
}
file delete -force -- $stage1d_generator_cleanup_root

if {$stage1d_generator_test_status != 0} {
    puts stderr $stage1d_generator_test_error
    if {[dict exists $stage1d_generator_test_options -errorinfo]} {
        puts stderr [dict get $stage1d_generator_test_options -errorinfo]
    }
    exit 1
}
exit 0
