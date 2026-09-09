# Standalone Stage 1D immutable delivery-bundle instance support and tests.
# This script uses Tcl only and must not invoke Vivado or lifecycle code.

namespace eval ::stage1d::delivery_bundle_instance_tests {
    variable pass_count 0
    variable failure_count 0
    variable test_root {}
    variable expected_profile_sha256 \
        e60518e48949117d7150fc12bd68a43b98bb290bb27a33f4ebf2a3167ba32e3b
    variable expected_manifest_sha256 \
        08ddb8e59c38296002329b7d4434bad7a30f07ce69acb12a384363ffa0654b5a
}

set stage1d_instance_test_dir [file normalize [file dirname [info script]]]
set stage1d_instance_build_root [file normalize \
    [file join $stage1d_instance_test_dir ..]]
set stage1d_instance_repository_root [file normalize \
    [file join $stage1d_instance_build_root .. .. ..]]
set stage1d_instance_bundle_root {}

source [file join $stage1d_instance_build_root lib source_check.tcl]
source [file join $stage1d_instance_build_root controller \
    delivery_bundle_loader.tcl]
source [file join $stage1d_instance_build_root controller \
    delivery_bundle_generator.tcl]

proc ::stage1d::delivery_bundle_instance_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1d::delivery_bundle_instance_tests::assert_equal {
    actual
    expected
    label
} {
    if {$actual ne $expected} {
        fail "$label: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1d::delivery_bundle_instance_tests::assert_true {
    condition
    label
} {
    if {!$condition} {
        fail "$label: condition is false"
    }
}

proc ::stage1d::delivery_bundle_instance_tests::run_case {name body} {
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

proc ::stage1d::delivery_bundle_instance_tests::component_status {
    result
    check_name
} {
    foreach component [dict get $result component_results] {
        if {[dict get $component check] eq $check_name} {
            return [dict get $component status]
        }
    }
    fail "Loader result is missing component: $check_name"
}

proc ::stage1d::delivery_bundle_instance_tests::read_binary {path} {
    set channel [open $path r]
    fconfigure $channel -encoding binary -translation binary
    set content [read $channel]
    close $channel
    return $content
}

proc ::stage1d::delivery_bundle_instance_tests::bundle_snapshot {root} {
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

proc ::stage1d::delivery_bundle_instance_tests::assert_bundle_layout {
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

proc ::stage1d::delivery_bundle_instance_tests::expected_request {} {
    set source_revision f6c8e119869a39720dd20456fdd8f33d1cd545a7
    set source_inventory [list \
        [dict create \
            path rtl/fault_defs.vh \
            size 384 \
            sha256 \
                bd54c73dce491dcdf2ede48dd25503dca850d8aa29770d08414d5c82a171a075] \
        [dict create \
            path rtl/current_compare_dual.v \
            size 740 \
            sha256 \
                13a9a0afb99fd7ce16a942e77bb2980152d4fe1e96c6d4ef750d28fdd6928747] \
        [dict create \
            path rtl/fault_classifier.v \
            size 1322 \
            sha256 \
                ff02daa7635130c7b86e75f4eaeeba111509e922f97040afb7c6b8cc7388c678] \
        [dict create \
            path rtl/moving_avg_filter.v \
            size 1632 \
            sha256 \
                044b46d5d45575035b5cfce95ed04721ab744a4028c36fc1304e7d47d062f8f5] \
        [dict create \
            path rtl/protection_core_top.v \
            size 2855 \
            sha256 \
                f69d849e99750e096e679e2ffd7c7a8cf5f8431968733b98830f1695b59b0fd5] \
        [dict create \
            path rtl/protection_fsm.v \
            size 2616 \
            sha256 \
                a6494fa6d56a3d40e0423dab3f15d107f8303f5ae83d1f4f3657071a63af5ef7] \
        [dict create \
            path rtl/protection_ip_top_axi_lite.v \
            size 7296 \
            sha256 \
                2d496e5a5a337074e9f388dc558a14e0bf5d82e9e28b44f003047bd95df364c8] \
        [dict create \
            path rtl/protection_ip_top_reg_controlled.v \
            size 3355 \
            sha256 \
                6a15139dbe342441bdf0534cfd60f7f7f9ab0908a27735811f9a2ea129a70e3a] \
        [dict create \
            path rtl/protection_reg_bank.v \
            size 2837 \
            sha256 \
                ef77cfd34faadca5a72c65c429c6742da2402dee2725313f20cdfb8ff395d45c] \
        [dict create \
            path rtl/pwm_gate.v \
            size 210 \
            sha256 \
                565f969f5ac81300a9c5a4921bc4158b7a933489f54c54b6f28584bccdc80f68] \
        [dict create \
            path rtl/pwm_gen.v \
            size 880 \
            sha256 \
                bad0663d768342e75decb32b6f5b70b96f1c85234662b7a13dd8151586dd0ecc] \
        [dict create \
            path rtl/sensor_health_monitor.v \
            size 2295 \
            sha256 \
                39598410bd7a52c7cb50cca8c2ff1a9173e326823218092a68e22cb9f59a0ad1] \
        [dict create \
            path fpga/vivado/package_protection_ip_stage2_axi_lite.tcl \
            size 11016 \
            sha256 \
                34e0ff2fc772533570dcc386616e7cc03ad8ad8bd3f92aa90c6586d6bb5a673c] \
        [dict create \
            path fpga/vivado/create_pynq_z2_project_stage1_boardpart.tcl \
            size 3608 \
            sha256 \
                6b24c1027e758c7b9d0ac90227a50dbfe3b67fd74218b61dd4d9ac0f247e6061] \
        [dict create \
            path fpga/vivado/create_pynq_z2_stage2_bd.tcl \
            size 12840 \
            sha256 \
                43e2941a76adb7af8894745eea6a853620964e48dd92c8d3b52d458eb39d440d] \
        [dict create \
            path fpga/vivado/add_pynq_z2_stage2b_debug.tcl \
            size 9441 \
            sha256 \
                003c3e6df1f7223bd3ec2af11623b2051ef4732dfb7c617b04e970a9d4e22704] \
        [dict create \
            path fpga/vivado/add_pynq_z2_stage1d_controlled_stimulus.tcl \
            size 10400 \
            sha256 \
                b55e554fd8c166cef6ec39804d4957f3da08e5bd29b4aacbf2cc5f3d53512e4e] \
        [dict create \
            path fpga/vivado/build/mutation/stage1d_controlled_stimulus.tcl \
            size 28672 \
            sha256 \
                ddb2fb31727e40d835c61aac6a431d8763723fda62449275e58feeea9171612d] \
        [dict create \
            path fpga/vivado/build/stage1d_artifact_build.tcl \
            size 2958 \
            sha256 \
                676ed1313e44a2afca78daefc56659ec3242f0469e00982618337dad60527cbd] \
        [dict create \
            path fpga/vivado/build/controller/argument_parser.tcl \
            size 2499 \
            sha256 \
                4a4048825553bd0afbf0ea1d374abed6544c273305e8c20f4d61c0e5ced0d223] \
        [dict create \
            path fpga/vivado/build/controller/configuration_loader.tcl \
            size 4792 \
            sha256 \
                141c1fb39148b66ee7284aee930ec6a393cbcf674a7b10615c7f1461da918ede] \
        [dict create \
            path fpga/vivado/build/controller/controller_core.tcl \
            size 130968 \
            sha256 \
                b4f4323039982b0d5c24a79d9d61d4c50fba10e3a6bcec26acd64665a42552b8] \
        [dict create \
            path fpga/vivado/build/controller/decision_engine.tcl \
            size 4049 \
            sha256 \
                2afc039f00ac05e0954392797f0f16cb7b6ab0790e98aa4121ce45202c44d638] \
        [dict create \
            path fpga/vivado/build/controller/logger.tcl \
            size 2442 \
            sha256 \
                34e3178fc1a51c058f56d3adcb5f4e0130a15b6a8296911844b9893a479901b4] \
        [dict create \
            path fpga/vivado/build/controller/phase_runner.tcl \
            size 10724 \
            sha256 \
                c9c79ed0e9c5d8cf63cf1a45214b57b7b9c3a6cacba8dd39900139cba66c4191] \
        [dict create \
            path fpga/vivado/build/controller/state_manager.tcl \
            size 4963 \
            sha256 \
                b43b5adbfcc8f83e2ccdf8def021b62f79dd17e1407c2ef3c149a9708b594139] \
        [dict create \
            path fpga/vivado/build/lib/source_check.tcl \
            size 17205 \
            sha256 \
                40220677e65c584a226fbf0b3878bc476e1b86bf09817e887761f8c60e4383e3] \
        [dict create \
            path fpga/vivado/build/lib/environment_check.tcl \
            size 11286 \
            sha256 \
                ba1cd048a9a00c373cf1a324091dc0a29e4f232afe297a5da5e4d2119215b8bb] \
        [dict create \
            path fpga/vivado/build/lib/workspace_manager.tcl \
            size 11546 \
            sha256 \
                dfdc2f8dc6f081ec0cce9ad129002fafb975af7d2c16015ddb2262054516b792] \
        [dict create \
            path fpga/vivado/build/lib/vivado_project.tcl \
            size 21731 \
            sha256 \
                d45f32574dcdd38b6c3d45b215225021a68c73514d9082f272d8f3d067358d41] \
        [dict create \
            path fpga/vivado/build/lib/bd_flow.tcl \
            size 21068 \
            sha256 \
                055b23f8119f9bd4dd340556ca37fc806d335a44c768f7a297b2af1d283cbca2] \
        [dict create \
            path fpga/vivado/build/config/stage1d_build_config.dict \
            size 5418 \
            sha256 \
                0c3dcdb72c2f246d1aafb8fcc473cf989c5b80bdd9eef311b31245e61adb67f4]]

    set source_identity [dict create \
        git_commit $source_revision \
        controller_source_hash \
            9cefa08b783e905c785757262269bc85e45a9808d001f450042a1630afd67cdd \
        configuration_hash \
            0c3dcdb72c2f246d1aafb8fcc473cf989c5b80bdd9eef311b31245e61adb67f4 \
        source_inventory $source_inventory]
    set environment_identity [dict create \
        vivado_version {Vivado v2024.1} \
        fpga_part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        required_ip_identities [list \
            xilinx.com:ip:processing_system7:* \
            xilinx.com:ip:proc_sys_reset:* \
            xilinx.com:ip:smartconnect:* \
            xilinx.com:ip:xlconstant:* \
            xilinx.com:ip:system_ila:* \
            xilinx.com:ip:axi_gpio:2.0 \
            xilinx.com:ip:xlslice:1.0 \
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
            generation_timestamp 2026-07-14T19:06:17Z \
            review_provenance \
                stage1d-first-immutable-bundle-review-v1]]
}

proc ::stage1d::delivery_bundle_instance_tests::load_instance {root} {
    set request [expected_request]
    return [::stage1d::delivery_bundle_loader::load \
        $root \
        [dict get $request source_identity] \
        [dict get $request environment_identity]]
}

proc ::stage1d::delivery_bundle_instance_tests::run_all {} {
    variable failure_count
    variable pass_count
    variable test_root
    variable expected_profile_sha256
    variable expected_manifest_sha256
    global stage1d_instance_bundle_root
    global stage1d_instance_repository_root

    run_case INSTANCE_LAYOUT_AND_LOADER_VALIDATION {
        assert_bundle_layout $stage1d_instance_bundle_root
        set result [load_instance $stage1d_instance_bundle_root]
        assert_equal [dict get $result status] PASS \
            {immutable bundle loader status}
        foreach check_name {
            BUNDLE_MANIFEST_SCHEMA_VALID
            BUNDLE_MANIFEST_HASH_VALID
            BUNDLE_PATH_CONTAINMENT_VALID
            PROFILE_SCHEMA_VERSION_SUPPORTED
            PROFILE_REQUIRED_FIELDS_VALID
            PROFILE_HASH_VALID
            PROFILE_SCOPE_VALID
            PROFILE_ENVIRONMENT_BINDING_VALID
            PROFILE_PARSE_SIDE_EFFECT_FREE
            PROFILE_SOURCE_BINDING_VALID
        } {
            assert_equal [component_status $result $check_name] PASS \
                "$check_name status"
        }
        assert_equal [dict get $result bundle_identity bundle_id] \
            stage1d-dry-run-v1 {bundle identity}
        assert_equal [dict get $result bundle_identity manifest_sha256] \
            $expected_manifest_sha256 {manifest fingerprint}
        assert_equal [dict get $result profile_identity profile_sha256] \
            $expected_profile_sha256 {profile fingerprint}
    }

    run_case INSTANCE_EXPLICIT_INPUT_BINDINGS {
        set request [expected_request]
        set result [load_instance $stage1d_instance_bundle_root]
        set manifest [dict get $result outputs validated_manifest]
        set profile [dict get $result outputs validated_profile]
        assert_equal [dict get $manifest source_revision] \
            [dict get $request source_revision] \
            {manifest frozen source revision}
        assert_equal [dict get $profile source_revision] \
            [dict get $request source_revision] \
            {profile frozen source revision}
        assert_equal \
            [::stage1d::delivery_bundle_loader::_canonical_source_identity \
                [dict get $manifest source_identity]] \
            [::stage1d::delivery_bundle_loader::_canonical_source_identity \
                [dict get $request source_identity]] \
            {source identity}
        assert_equal [dict get $manifest environment_identity] \
            [dict get $request environment_identity] \
            {manifest environment identity}
        assert_equal [dict get $profile environment_identity] \
            [dict get $request environment_identity] \
            {profile environment identity}
        assert_equal [dict get $profile scope] \
            [dict get $request scope] {reviewed profile scope}
        assert_equal [dict get $profile evidence_policy] \
            [dict get $request evidence_policy] {evidence policy}
        assert_equal \
            [::stage1d::delivery_bundle_loader::_canonical_sorted_dict \
                [dict get $manifest provenance]] \
            [::stage1d::delivery_bundle_loader::_canonical_sorted_dict \
                [dict get $request provenance]] \
            {generation provenance}
        assert_equal [dict get $profile profile_id] \
            [dict get $request profile_id] {profile identity}
        assert_equal [dict get $profile profile_version] \
            [dict get $request profile_version] {profile version}
        assert_true [expr {![dict exists $manifest execution_id]}] \
            {manifest excludes execution_id}
        assert_true [expr {![dict exists $profile execution_id]}] \
            {profile excludes execution_id}
    }

    run_case INSTANCE_DETERMINISTIC_REPRODUCTION {
        set request [expected_request]
        set first_parent [file normalize [file join $test_root first]]
        set second_parent [file normalize [file join $test_root second]]
        file mkdir $first_parent
        file mkdir $second_parent

        set ::stage1d_instance_execution_id STAGE1D-INSTANCE-EXECUTION-A
        set first [::stage1d::delivery_bundle_generator::generate \
            $first_parent $request]
        set ::stage1d_instance_execution_id STAGE1D-INSTANCE-EXECUTION-B
        set second [::stage1d::delivery_bundle_generator::generate \
            $second_parent $request]
        unset ::stage1d_instance_execution_id

        assert_true [expr {[dict get $first bundle_root] ne \
            [dict get $second bundle_root]}] {distinct output locations}
        assert_equal [dict get $first bundle_identity] \
            [dict get $second bundle_identity] \
            {reproduced bundle identity}
        assert_equal [dict get $first bundle_identity manifest_sha256] \
            $expected_manifest_sha256 {reproduced manifest hash}
        assert_equal [dict get $first profile_identity profile_sha256] \
            $expected_profile_sha256 {reproduced profile hash}

        set instance_snapshot [bundle_snapshot $stage1d_instance_bundle_root]
        set first_snapshot [bundle_snapshot [dict get $first bundle_root]]
        set second_snapshot [bundle_snapshot [dict get $second bundle_root]]
        assert_equal $first_snapshot $second_snapshot \
            {two-generation canonical bundle content}
        assert_equal $first_snapshot $instance_snapshot \
            {instance canonical bundle content}
        foreach content [dict values $instance_snapshot] {
            assert_true [expr {[string first \
                STAGE1D-INSTANCE-EXECUTION-A $content] < 0}] \
                {first execution_id excluded from bundle content}
            assert_true [expr {[string first \
                STAGE1D-INSTANCE-EXECUTION-B $content] < 0}] \
                {second execution_id excluded from bundle content}
            assert_true [expr {[string first \
                $stage1d_instance_repository_root $content] < 0}] \
                {absolute output location excluded from bundle content}
        }
        foreach generated_result [list $first $second] {
            foreach side_effect_count [dict values \
                [dict get $generated_result outputs side_effects]] {
                assert_equal $side_effect_count 0 \
                    {generator side-effect boundary}
            }
            assert_equal [dict get $generated_result outputs \
                authorization_assertion_generated] 0 \
                {authorization assertion boundary}
        }
    }

    run_case INSTANCE_DECLARATIVE_AND_BOUNDED {
        set snapshot [bundle_snapshot $stage1d_instance_bundle_root]
        foreach content [dict values $snapshot] {
            foreach forbidden_token [list \
                {$} {[} {]} {;} [format %c 0]] {
                assert_true [expr {[string first $forbidden_token \
                    $content] < 0}] \
                    {bundle content contains declarative data only}
            }
        }
        assert_bundle_layout $stage1d_instance_bundle_root
    }

    if {$failure_count != 0} {
        error "Delivery-bundle instance tests failed: $failure_count"
    }
    puts {BUNDLE_MANIFEST_HASH_VALID: PASS}
    puts {PROFILE_HASH_VALID: PASS}
    puts {SOURCE_BINDING_VALID: PASS}
    puts {ENVIRONMENT_BINDING_VALID: PASS}
    puts {PATH_CONTAINMENT_VALID: PASS}
    puts {BUNDLE_IDENTITY_STABLE: PASS}
    puts {EXECUTION_ID_INDEPENDENT: PASS}
    puts {CANONICAL_BUNDLE_CONTENT_STABLE: PASS}
    puts {NO_VIVADO_EXECUTION: PASS}
    puts {NO_LIFECYCLE_INVOCATION: PASS}
    puts {NO_MUTATION_INVOCATION: PASS}
    puts {NO_IMPLEMENTATION_ARTIFACT_GENERATION: PASS}
    puts "SUMMARY PASS=$pass_count FAIL=$failure_count"
}

if {$argc != 0} {
    puts stderr {Usage: delivery_bundle_instance_tests.tcl}
    exit 1
}

set stage1d_instance_temp_channel \
    [file tempfile stage1d_instance_temp_anchor]
close $stage1d_instance_temp_channel
file delete -- $stage1d_instance_temp_anchor
set stage1d_instance_test_root [file normalize \
    "${stage1d_instance_temp_anchor}_stage1d_delivery_bundle_instance"]
set stage1d_instance_temp_parent [file dirname $stage1d_instance_test_root]
set ::stage1d::delivery_bundle_instance_tests::test_root [file normalize \
    $stage1d_instance_test_root]
file mkdir $::stage1d::delivery_bundle_instance_tests::test_root

set stage1d_instance_test_status [catch {
    set stage1d_instance_fixture_parent [file join \
        $::stage1d::delivery_bundle_instance_tests::test_root fixture]
    file mkdir $stage1d_instance_fixture_parent
    set stage1d_instance_fixture_result \
        [::stage1d::delivery_bundle_generator::generate \
            $stage1d_instance_fixture_parent \
            [::stage1d::delivery_bundle_instance_tests::expected_request]]
    set stage1d_instance_bundle_root [dict get \
        $stage1d_instance_fixture_result bundle_root]
    ::stage1d::delivery_bundle_instance_tests::run_all
} stage1d_instance_test_error stage1d_instance_test_options]

set stage1d_instance_cleanup_root \
    $::stage1d::delivery_bundle_instance_tests::test_root
set stage1d_instance_cleanup_parent \
    [file dirname $stage1d_instance_cleanup_root]
if {[file normalize $stage1d_instance_cleanup_parent] ne \
    [file normalize $stage1d_instance_temp_parent] ||
    [file normalize $stage1d_instance_cleanup_root] ne \
        [file normalize $stage1d_instance_test_root]} {
    puts stderr {Refusing test cleanup outside the verified temporary parent.}
    exit 1
}
file delete -force -- $stage1d_instance_cleanup_root

if {$stage1d_instance_test_status != 0} {
    puts stderr $stage1d_instance_test_error
    if {[dict exists $stage1d_instance_test_options -errorinfo]} {
        puts stderr [dict get $stage1d_instance_test_options -errorinfo]
    }
    exit 1
}
exit 0
