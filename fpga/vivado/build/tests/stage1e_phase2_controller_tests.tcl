# Source-only tests for the Stage 1E Phase 2 controller composition.
# All phase operations are replaced with in-memory mocks. No Vivado command,
# synthesis run, implementation operation, artifact operation, or board access
# is available to this test suite.

set ::env(STAGE1E_CONTROLLER_NO_MAIN) 1
set ::env(STAGE1E_CONTROLLER_NO_EXIT) 1
set test_directory [file normalize [file dirname [info script]]]
set build_root [file normalize [file join $test_directory ..]]
set repository_root [file normalize [file join $build_root .. .. ..]]
source [file join $build_root stage1e_phase2_synthesis_build.tcl]
# Virtual short paths test MAX_PATH calculations; they are never created here.
set ::stage1e::phase2_controller::controlled_workspace_root [file normalize /s1e]

namespace eval ::stage1e::phase2_controller_tests {
    variable pass_count 0
    variable fail_count 0
    variable invocation_order {}
    variable contexts [dict create]
    variable observed_cwds [dict create]
    variable test_root [file normalize [file join [pwd] \
        .stage1e_phase2_controller_test_tmp]]
    variable repository_root $::repository_root
    variable profile {}
    variable configuration {}
    variable execution_id STAGE1E-20990101-000000-1234567
    variable retry_number 99
    variable path_test_guard {}
    variable path_test_root {}
}

set ::stage1e::phase2_controller_tests::path_test_root [file normalize \
    [file join $::repository_root .s1ept]]
set ::stage1e::phase2_controller_tests::path_test_guard \
    $::stage1e::phase2_controller_tests::path_test_root

proc ::stage1e::phase2_controller_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::phase2_controller_tests::assert_true {
    condition
    message
} {
    if {!$condition} { fail $message }
}

proc ::stage1e::phase2_controller_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::phase2_controller_tests::assert_set_equal {
    expected
    actual
    message
} {
    if {[lsort -dictionary $expected] ne [lsort -dictionary $actual] ||
        [llength $actual] != [llength [lsort -unique $actual]]} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::phase2_controller_tests::read_dict {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set contents [read $channel]
    close $channel
    if {[catch {dict size $contents} dictionary_error]} {
        fail "Invalid dictionary file $path: $dictionary_error"
    }
    return $contents
}

proc ::stage1e::phase2_controller_tests::write_dict {path value} {
    set channel [open $path {WRONLY CREAT TRUNC}]
    fconfigure $channel -encoding utf-8 -translation lf
    set write_status [catch {puts $channel $value} write_error write_options]
    set close_status [catch {close $channel} close_error]
    if {$write_status != 0} {
        return -options $write_options $write_error
    }
    if {$close_status != 0} {
        error "Unable to close test dictionary: $close_error"
    }
}

proc ::stage1e::phase2_controller_tests::safe_cleanup {} {
    variable test_root
    set normalized [file normalize $test_root]
    if {[file tail $normalized] ne {.stage1e_phase2_controller_test_tmp}} {
        error "Refusing unsafe Phase 2 test cleanup: $normalized"
    }
    if {[file exists $normalized]} {
        file delete -force -- $normalized
    }
}

proc ::stage1e::phase2_controller_tests::safe_path_cleanup {} {
    variable path_test_guard
    variable path_test_root
    set normalized [file normalize $path_test_root]
    if {[string tolower $normalized] ne [string tolower $path_test_guard] ||
        [file tail $normalized] ne {.s1ept} ||
        [string tolower [file dirname $normalized]] ne \
            [string tolower [file normalize $::repository_root]]} {
        error "Refusing unsafe execution-path test cleanup: $normalized"
    }
    if {[file exists $normalized]} {
        file delete -force -- $normalized
    }
}

proc ::stage1e::phase2_controller_tests::path_preflight_context {
    execution_identifier
    retry_number
    build_workspace
    artifact_storage
} {
    variable repository_root
    variable profile
    variable configuration
    return [dict create \
        parsed_arguments [dict create \
            repository_root $repository_root \
            build_workspace [file normalize $build_workspace] \
            artifact_storage [file normalize $artifact_storage]] \
        configuration $configuration \
        execution_identity [dict create \
            execution_identifier $execution_identifier \
            retry_number $retry_number \
            execution_id_schema_version v1 \
            generated_at 2099-01-01T00:00:00Z \
            candidate_git_commit [string repeat 1 40] \
            git_tree [string repeat 2 40] \
            project_name [dict get $configuration reconstruction_policy \
                project project_name] \
            synthesis_run_name [dict get $profile build_policy synthesis \
                run_name]]]
}

proc ::stage1e::phase2_controller_tests::load_inputs {} {
    variable repository_root
    variable profile
    variable configuration
    set profile [read_dict [file join $repository_root fpga vivado build \
        config stage1e_reconstruction_profile_v1.dict]]
    set configuration [read_dict [file join $repository_root fpga vivado \
        build config stage1e_phase2_synthesis_config_v1.dict]]
}

proc ::stage1e::phase2_controller_tests::reset_mock {} {
    variable invocation_order
    variable contexts
    variable observed_cwds
    safe_cleanup
    set invocation_order {}
    set contexts [dict create]
    set observed_cwds [dict create]
}

proc ::stage1e::phase2_controller_tests::source_inventory {} {
    variable configuration
    set inventory {}
    foreach path [dict get $configuration reconstruction_policy packaging \
        source_paths] {
        lappend inventory [dict create \
            path $path size 1 sha256 [string repeat a 64]]
    }
    return $inventory
}

proc ::stage1e::phase2_controller_tests::record {key context} {
    variable invocation_order
    variable contexts
    variable observed_cwds
    lappend invocation_order $key
    dict set contexts $key $context
    dict set observed_cwds $key [file normalize [pwd]]
}

proc ::stage1e::phase2_controller_tests::mock_input_ready {context} {
    record input_ready $context
    return [dict create status PASS outputs [dict create \
        collision_check_result PASS]]
}

proc ::stage1e::phase2_controller_tests::mock_source {context} {
    variable repository_root
    record source_verification $context
    return [dict create status PASS outputs [dict create \
        repository_root $repository_root \
        git_commit [string repeat 1 40] \
        worktree_clean 1 \
        source_state_frozen 1 \
        source_inventory [source_inventory] \
        controller_source_hash [string repeat b 64] \
        configuration_hash [string repeat c 64]]]
}

proc ::stage1e::phase2_controller_tests::mock_environment {context} {
    record environment_verification $context
    return [dict create status PASS outputs [dict create \
        vivado_version {Vivado v2024.1} \
        sw_build 5076996 ip_build 5075265 \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        observed_ip_identities {
            xilinx.com:ip:processing_system7:5.5
            xilinx.com:ip:proc_sys_reset:5.0
            xilinx.com:ip:smartconnect:1.0
            xilinx.com:ip:xlconstant:1.1
            xilinx.com:ip:system_ila:1.1
            xilinx.com:ip:axi_gpio:2.0
            xilinx.com:ip:xlslice:1.0
        } \
        environment_evidence_hash [string repeat d 64]]]
}

proc ::stage1e::phase2_controller_tests::mock_workspace {context} {
    variable test_root
    record workspace_creation $context
    set execution_identity [dict get $context execution_identity]
    set retry_number [dict get $execution_identity retry_number]
    set workspace_identifier \
        [::stage1e::phase2_controller::_workspace_identifier \
            $retry_number]
    set workspace [file normalize \
        [file join $test_root $workspace_identifier]]
    file mkdir [file join $workspace execution_state]
    set ownership_evidence execution_state/ownership.dict
    set workspace_identity \
        [::stage1d::workspace_manager::phase2_workspace_identity \
            [dict get $execution_identity execution_identifier] \
            $retry_number \
            [string repeat 1 40] \
            [dict get $execution_identity git_tree] \
            $workspace_identifier \
            $workspace \
            [dict get $execution_identity project_name] \
            [dict get $execution_identity synthesis_run_name] \
            $ownership_evidence]
    write_dict [file join $workspace $ownership_evidence] [dict create \
        execution_id [dict get $execution_identity execution_identifier] \
        retry_number $retry_number \
        workspace_path $workspace \
        workspace_identifier $workspace_identifier \
        workspace_identity_schema_version \
            [dict get $workspace_identity schema_version] \
        workspace_identity_hash \
            [dict get $workspace_identity identity_sha256]]
    return [dict create status PASS outputs [dict create \
        execution_workspace $workspace \
        workspace_identifier $workspace_identifier \
        retry_number $retry_number \
        workspace_identity $workspace_identity \
        workspace_identity_hash [dict get $workspace_identity \
            identity_sha256] \
        ownership_evidence $ownership_evidence]]
}

proc ::stage1e::phase2_controller_tests::mock_packaging {context} {
    record ip_packaging $context
    set execution_id [dict get $context execution_id]
    return [dict create status PASS produced_identities [dict create \
        package_identity [dict create \
            schema_version stage1e-package-identity-v1 \
            execution_id $execution_id \
            vlnv zsr112.local:protection:protection_ip_axi_lite:0.3 \
            identity_sha256 [string repeat e 64]] \
        ip_repo_identity [dict create \
            schema_version stage1e-ip-repo-identity-v1 \
            execution_id $execution_id \
            path [dict get $context ip_repo_path] \
            packaged_ip_path [file join [dict get $context ip_repo_path] \
                protection_ip_axi_lite] \
            vlnv zsr112.local:protection:protection_ip_axi_lite:0.3 \
            package_sha256 [string repeat e 64] \
            ip_repo_sha256 [string repeat f 64]]]]
}

proc ::stage1e::phase2_controller_tests::mock_project {context} {
    record project_creation $context
    set project_path [dict get $context project_path]
    set project_identity [dict create \
        schema_version stage1e-project-identity-v1 \
        execution_id [dict get $context execution_id] \
        project_name [dict get $context project_name] \
        project_directory [file dirname $project_path] \
        project_path $project_path \
        part [dict get $context part] \
        board_part [dict get $context board_part] \
        target_language [dict get $context target_language]]
    return [dict create status PASS ownership_records [dict create \
        owner vivado_project \
        execution_id [dict get $context execution_id] \
        project_handle project::stage1e \
        project_path $project_path identity_verified 1 \
        project_identity $project_identity]]
}

proc ::stage1e::phase2_controller_tests::mock_bd {context} {
    record bd_creation $context
    return [dict create status PASS ownership_records [dict create \
        owner bd_flow \
        execution_id [dict get $context execution_id] \
        project_path [dict get $context project_ownership project_path] \
        bd_name [dict get $context bd_identity bd_name] \
        bd_path [dict get $context bd_identity expected_bd_path] \
        opened 1 identity_verified 1 validated 0 saved 0]]
}

proc ::stage1e::phase2_controller_tests::mock_base {context} {
    record base_design $context
    return [dict create status PASS produced_identities [dict create \
        base_design_identity [dict create \
            schema_version stage1e-base-design-identity-v1 \
            producer_operation stage1e::base_design::apply \
            execution_id [dict get $context execution_id] \
            project_path [dict get $context project_ownership project_path] \
            bd_name [dict get $context bd_ownership bd_name] \
            bd_path [dict get $context bd_ownership bd_path] \
            topology_policy_sha256 [string repeat 1 64] \
            policy_bundle_sha256 [string repeat 2 64] \
            readback_sha256 [string repeat 3 64] \
            identity_sha256 [string repeat 4 64]]]]
}

proc ::stage1e::phase2_controller_tests::mock_debug {context} {
    record debug_design $context
    return [dict create status PASS produced_identities [dict create \
        debug_design_identity [dict create \
            schema_version stage1e-debug-design-identity-v1 \
            producer_operation stage1e::debug_design::apply \
            execution_id [dict get $context execution_id] \
            project_path [dict get $context project_ownership project_path] \
            bd_name [dict get $context bd_ownership bd_name] \
            bd_path [dict get $context bd_ownership bd_path] \
            base_design_identity_sha256 [string repeat 4 64] \
            identity_sha256 [string repeat 5 64]]]]
}

proc ::stage1e::phase2_controller_tests::mock_mutation {context} {
    record mutation_bridge $context
    return [dict create status PASS produced_identities [dict create \
        controlled_mutation_identity [dict create \
            schema_version stage1e-controlled-mutation-identity-v1 \
            producer_operation stage1e::mutation_bridge::apply \
            execution_id [dict get $context execution_id] \
            project_path [dict get $context project_ownership project_path] \
            bd_name [dict get $context bd_ownership bd_name] \
            bd_path [dict get $context bd_ownership bd_path] \
            identity_sha256 [string repeat 6 64]]]]
}

proc ::stage1e::phase2_controller_tests::mock_bd_validation {context} {
    record bd_validation $context
    set lifecycle $context
    dict set lifecycle bd_ownership validated 1
    return [dict create status PASS outputs [dict create \
        lifecycle_context $lifecycle]]
}

proc ::stage1e::phase2_controller_tests::mock_bd_save {context} {
    record bd_save $context
    set lifecycle $context
    dict set lifecycle bd_ownership saved 1
    return [dict create status PASS outputs [dict create \
        lifecycle_context $lifecycle]]
}

proc ::stage1e::phase2_controller_tests::mock_build_target {context} {
    record build_target $context
    return [dict create status PASS produced_identities [dict create \
        build_target_identity [dict create \
            schema_version stage1e-build-target-identity-v1 \
            producer_operation stage1e::build_target::prepare \
            execution_id [dict get $context execution_id] \
            project_path [dict get $context project_ownership project_path] \
            bd_name [dict get $context bd_ownership bd_name] \
            bd_path [dict get $context bd_ownership bd_path] \
            wrapper_path [dict get $context wrapper_path_policy path] \
            top_module [dict get $context top_module_policy top_module] \
            fileset [dict get $context top_module_policy fileset] \
            source_identity_sha256 [dict get $context source_identity \
                identity_sha256] \
            configuration_identity_sha256 [dict get $context \
                configuration_identity identity_sha256] \
            environment_identity_sha256 [dict get $context \
                environment_identity identity_sha256] \
            identity_sha256 [string repeat 7 64]]]]
}

proc ::stage1e::phase2_controller_tests::mock_synthesis {context} {
    record synthesis $context
    return [dict create status PASS produced_identities [dict create \
        synthesis_result_identity [dict create \
            schema_version stage1e-synthesis-result-identity-v1 \
            producer_operation stage1e::synthesis::run \
            execution_id [dict get $context execution_id] \
            acceptance_state CANDIDATE \
            identity_sha256 [string repeat 8 64]]]]
}

proc ::stage1e::phase2_controller_tests::operation_overrides {} {
    return [dict create \
        input_ready ::stage1e::phase2_controller_tests::mock_input_ready \
        source_verification ::stage1e::phase2_controller_tests::mock_source \
        environment_verification ::stage1e::phase2_controller_tests::mock_environment \
        workspace_creation ::stage1e::phase2_controller_tests::mock_workspace \
        ip_packaging ::stage1e::phase2_controller_tests::mock_packaging \
        project_creation ::stage1e::phase2_controller_tests::mock_project \
        bd_creation ::stage1e::phase2_controller_tests::mock_bd \
        base_design ::stage1e::phase2_controller_tests::mock_base \
        debug_design ::stage1e::phase2_controller_tests::mock_debug \
        mutation_bridge ::stage1e::phase2_controller_tests::mock_mutation \
        bd_validation ::stage1e::phase2_controller_tests::mock_bd_validation \
        bd_save ::stage1e::phase2_controller_tests::mock_bd_save \
        build_target ::stage1e::phase2_controller_tests::mock_build_target \
        synthesis ::stage1e::phase2_controller_tests::mock_synthesis]
}

proc ::stage1e::phase2_controller_tests::root_context {} {
    variable repository_root
    variable profile
    variable configuration
    variable execution_id
    variable retry_number
    set permitted {}
    dict for {key definition} \
        $::stage1e::phase2_controller::authorized_operation_map {
        lappend permitted [dict get $definition operation]
    }
    return [dict create \
        context_schema_version stage1e-phase2-controller-context-v1 \
        execution_id $execution_id \
        execution_identity [dict create \
            execution_identifier $execution_id \
            retry_number $retry_number \
            execution_id_schema_version v1 \
            generated_at 2099-01-01T00:00:00Z \
            candidate_git_commit [string repeat 1 40]] \
        parsed_arguments [dict create \
            repository_root $repository_root \
            build_workspace [::stage1e::phase2_controller::_workspace_root] \
            artifact_storage [file normalize [file join [temporary_base] artifacts]] \
            environment_evidence_path [file join [temporary_base] environment.dict]] \
        profile $profile \
        profile_sha256 [string repeat 9 64] \
        configuration $configuration \
        execution_authorization [dict create \
            schema_version stage1e-phase2-execution-authorization-v1 \
            status AUTHORIZED authority stage1e_execution_authority \
            execution_id $execution_id \
            retry_number $retry_number \
            git_commit [string repeat 1 40] \
            git_tree [string repeat 2 40] \
            workspace_root [file normalize [file join \
                [::stage1e::phase2_controller::_workspace_root] \
                [::stage1e::phase2_controller::_workspace_identifier \
                    $retry_number]]] \
            profile_id stage1e_reconstruction_profile_v1 \
            enabled_capabilities {
                IP_PACKAGING PROJECT_RECONSTRUCTION BD_GENERATION
                WRAPPER_GENERATION SYNTHESIS
            } \
            disabled_capabilities {
                IMPLEMENTATION ARTIFACT_COLLECTION ARTIFACT_PUBLICATION
            } \
            permitted_operations $permitted]]
}

proc ::stage1e::phase2_controller_tests::temporary_base {} {
    variable test_root
    return [file normalize $test_root]
}

proc ::stage1e::phase2_controller_tests::run_controller {} {
    return [::stage1e::phase2_build::run \
        [root_context] [operation_overrides]]
}

proc ::stage1e::phase2_controller_tests::run_case {name body} {
    variable pass_count
    variable fail_count
    set status [catch {uplevel 1 $body} message options]
    if {$status == 0} {
        incr pass_count
        puts "$name: PASS"
        return
    }
    incr fail_count
    puts stderr "$name: FAIL: $message"
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
}

proc ::stage1e::phase2_controller_tests::run_all {} {
    variable repository_root
    variable profile
    variable configuration
    variable invocation_order
    variable contexts
    variable observed_cwds

    run_case PHASE2_CAPABILITY_ENABLED {
        ::stage1e::phase2_controller::validate_profile $profile
        ::stage1e::phase2_controller::validate_configuration $configuration
        assert_set_equal {
            IP_PACKAGING PROJECT_RECONSTRUCTION BD_GENERATION
            WRAPPER_GENERATION SYNTHESIS
        } [dict get $configuration capability_policy enabled] \
            {Phase 2 enabled capability set}
        assert_set_equal {
            IMPLEMENTATION ARTIFACT_COLLECTION ARTIFACT_PUBLICATION
        } [dict get $configuration capability_policy disabled] \
            {Phase 2 disabled capability set}
    }

    run_case PHASE2_WINDOWS_WORKSPACE_PATH_BUDGET {
        set defaults [::stage1e::phase2_controller::default_operations]
        assert_equal \
            ::stage1e::phase2_controller::_controlled_input_ready \
            [dict get $defaults input_ready] \
            {Controlled input-readiness path is not composed}
        assert_equal \
            ::stage1e::phase2_controller::_controlled_workspace_creation \
            [dict get $defaults workspace_creation] \
            {Controlled workspace-creation path is not composed}
        set workspace_root \
            [::stage1e::phase2_controller::_workspace_root]
        assert_equal [file normalize /s1e] $workspace_root \
            {Controlled workspace short root}
        set workspace_identifier \
            [::stage1e::phase2_controller::_workspace_identifier 14]
        assert_equal r14 $workspace_identifier \
            {Retry-indexed workspace identifier}
        set budget [::stage1e::phase2_controller::_workspace_path_budget \
            $workspace_root $workspace_identifier]
        set workspace [dict get $budget execution_workspace]
        assert_equal [file normalize /s1e/r14] $workspace \
            {Retry #14 workspace path}
        assert_equal 4 [dict get $budget reviewed_descendant_path_count] \
            {Reviewed Vivado descendant inventory}
        assert_equal 16 [dict get $budget \
            windows_path_safety_margin_bytes] \
            {Windows path safety margin}
        assert_true [string match \
            {*protection_system_protection_ip_axi_lite_0_0.xci} \
            [dict get $budget longest_reviewed_relative_path]] \
            {Retry #14 longest failing XCI is not budgeted}
        assert_equal [expr {
            [dict get $budget longest_reviewed_path_bytes] +
            [dict get $budget windows_path_safety_margin_bytes]
        }] [dict get $budget projected_max_path_bytes] \
            {Projected path does not include the safety margin}
        assert_true [expr {
            [dict get $budget projected_max_path_bytes] <=
            [dict get $budget windows_usable_path_bytes]
        }] {Controlled workspace path budget exceeds Windows MAX_PATH}
        assert_true [expr {
            [dict get $budget workspace_root_bytes] <
            [dict get $budget execution_workspace_bytes]
        }] {Workspace root length was not explicitly validated}

        set long_context [path_preflight_context \
            STAGE1E-20990101-010203-1234567 14 \
            /fixture/stage1e_first_controlled_synthesis_retry14_20260717_201646/builds \
            /stage1e_path_test_artifacts]
        set root_status [catch {
            ::stage1e::phase2_controller::_controlled_input_ready \
                $long_context
        } root_error]
        assert_equal 1 $root_status \
            {Legacy long workspace root was not rejected}
        assert_true [string match \
            {*retry-indexed short-root policy*} $root_error] \
            {Long-root rejection does not identify the workspace policy}

        set over_budget_root [file normalize \
            [file join /fixture [string repeat x 100]]]
        set budget_status [catch {
            ::stage1e::phase2_controller::_workspace_path_budget \
                $over_budget_root $workspace_identifier
        } budget_error]
        assert_equal 1 $budget_status \
            {Over-budget workspace root was not rejected before execution}
        assert_true [string match \
            {*exceeds the Windows Vivado path budget*} $budget_error] \
            {Over-budget rejection does not identify the path contract}
    }

    run_case PHASE2_LAUNCHER_CWD_VALID {
        reset_mock
        set caller_cwd [file normalize [pwd]]
        set result [run_controller]
        assert_equal PASS [dict get $result status] \
            {Launcher cwd controller result}
        set workspace_identity \
            [dict get $contexts synthesis workspace_identity]
        set workspace [dict get $workspace_identity workspace_root]
        foreach operation {
            ip_packaging project_creation bd_creation base_design debug_design
            mutation_bridge bd_validation bd_save build_target synthesis
        } {
            assert_equal [file normalize $workspace] \
                [dict get $observed_cwds $operation] \
                "Vivado operation launcher cwd: $operation"
        }
        assert_equal $caller_cwd [file normalize [pwd]] \
            {External runner cwd was not restored}
        set validation [::stage1e::phase2_build::validate_launcher_cwd \
            $workspace_identity $workspace]
        assert_equal stage1e-vivado-launcher-cwd-v1 \
            [dict get $validation contract_version] \
            {Launcher cwd contract version}
        assert_equal [file normalize $workspace] \
            [dict get $validation expected_cwd] \
            {Launcher expected cwd binding}
        assert_equal [file normalize $workspace] \
            [dict get $contexts synthesis launcher_working_directory] \
            {Launcher cwd was not propagated to operation context}
    }

    run_case PHASE2_LAUNCHER_LIFETIME_VALID {
        set synthesis_policy [dict get $profile build_policy synthesis]
        set lifetime \
            [::stage1e::phase2_build::validate_launcher_lifetime_policy \
                $synthesis_policy]
        assert_equal stage1e-vivado-launcher-lifetime-v1 \
            [dict get $lifetime contract_version] \
            {Launcher lifetime contract version}
        assert_equal 120 [dict get $lifetime launcher_timeout_minutes] \
            {External launcher timeout}
        assert_equal 120 \
            [dict get $lifetime required_launcher_timeout_minutes] \
            {Required external launcher timeout}
        assert_equal 1 \
            [dict get $lifetime do_not_terminate_while_wait_active] \
            {Launcher wait ownership boundary}

        reset_mock
        set result [run_controller]
        assert_equal PASS [dict get $result status] \
            {Launcher lifetime controller result}
        assert_equal $lifetime \
            [dict get $contexts synthesis launcher_lifetime_policy] \
            {Launcher lifetime was not propagated to synthesis context}
        assert_equal 60 [dict get $contexts synthesis synthesis_policy \
            job_policy wait_timeout_minutes] \
            {Bounded wait policy was not propagated}
    }

    run_case PHASE2_LAUNCHER_LIFETIME_REJECT {
        set synthesis_policy [dict get $profile build_policy synthesis]
        dict set synthesis_policy job_policy launcher_timeout_minutes 119
        set rejected [catch {
            ::stage1e::phase2_build::validate_launcher_lifetime_policy \
                $synthesis_policy
        } rejection]
        assert_equal 1 $rejected \
            {Undersized external launcher lifetime was accepted}
        assert_true [expr {[string first \
            {shorter than the controlled execution budget} $rejection] >= 0}] \
            {Launcher lifetime rejection reason}
    }

    run_case PHASE2_LAUNCHER_XIL_ROOT_CONTAINED {
        reset_mock
        set result [run_controller]
        assert_equal PASS [dict get $result status] \
            {Launcher .Xil precondition}
        set identity [dict get $contexts synthesis workspace_identity]
        set budget [::stage1e::phase2_build::launcher_path_budget $identity]
        set workspace [dict get $budget workspace_root]
        set xil_root [dict get $budget xil_root]
        assert_equal .Xil [file tail $xil_root] \
            {Vivado state root name}
        assert_true [::stage1e::phase2_build::_path_is_equal_or_descendant \
            $xil_root $workspace] \
            {Vivado .Xil root escaped workspace}
        assert_true [expr {
            ![::stage1e::phase2_build::_launcher_same_path \
                $xil_root $workspace]
        }] {Vivado .Xil root is not a strict workspace descendant}
    }

    run_case PHASE2_LAUNCHER_SHORT_PATH_GUARANTEE {
        set workspace [file normalize /s1e/r20]
        set identity [::stage1d::workspace_manager::phase2_workspace_identity \
            STAGE1E-20990101-010220-1234567 20 \
            [string repeat 1 40] [string repeat 2 40] r20 $workspace \
            [dict get $configuration reconstruction_policy project \
                project_name] \
            [dict get $profile build_policy synthesis run_name] \
            execution_state/ownership.dict]
        set budget [::stage1e::phase2_build::launcher_path_budget $identity]
        assert_equal $workspace [dict get $budget workspace_root] \
            {Retry #20 launcher workspace}
        assert_true [expr {
            [dict get $budget projected_xil_path_bytes] <=
            [dict get $budget windows_usable_path_bytes]
        }] {Launcher .Xil path exceeds Windows path budget}
        assert_equal 1 [dict get $budget \
            reviewed_xil_descendant_path_count] \
            {Reviewed launcher .Xil descendant inventory}
        assert_true [string match \
            {*.Xil/*/coregen/protection_system_smartconnect_0_0/*} \
            [string map {\\ /} [dict get $budget \
                longest_reviewed_xil_relative_path]]] \
            {Observed SmartConnect .Xil path is not budgeted}
        assert_equal [expr {
            [dict get $budget longest_reviewed_xil_path_bytes] +
            [dict get $budget windows_path_safety_margin_bytes]
        }] [dict get $budget projected_xil_path_bytes] \
            {Projected .Xil path omits the safety margin}
        assert_equal 16 [dict get $budget \
            windows_path_safety_margin_bytes] \
            {Launcher Windows path safety margin}
    }

    run_case PHASE2_LAUNCHER_RUNNER_PATH_INDEPENDENT {
        reset_mock
        set caller_cwd [file normalize [pwd]]
        set long_runner [file normalize [file join \
            $::stage1e::phase2_controller_tests::test_root \
            "external_runner_[string repeat x 96]"]]
        file mkdir $long_runner
        try {
            cd $long_runner
            set observed_runner [file normalize [pwd]]
            set result [run_controller]
            assert_equal PASS [dict get $result status] \
                {Long external runner controller result}
            set identity [dict get $contexts synthesis workspace_identity]
            set workspace [dict get $identity workspace_root]
            assert_true [expr {
                ![::stage1e::phase2_build::_launcher_same_path \
                    $workspace $observed_runner]
            }] {Launcher adopted the external runner directory}
            set rejection_status [catch {
                ::stage1e::phase2_build::validate_launcher_cwd \
                    $identity $observed_runner
            } rejection]
            assert_equal 1 $rejection_status \
                {External runner cwd passed launcher validation}
            assert_true [string match \
                {*cwd is not the controlled workspace*} $rejection] \
                {External runner cwd rejection reason}
            foreach operation {
                ip_packaging project_creation bd_creation base_design
                debug_design mutation_bridge bd_validation bd_save
                build_target synthesis
            } {
                assert_equal [file normalize $workspace] \
                    [dict get $observed_cwds $operation] \
                    "Runner-path-independent cwd: $operation"
            }
            set xil_root [dict get \
                [::stage1e::phase2_build::launcher_path_budget $identity] \
                xil_root]
            assert_true [expr {
                ![::stage1e::phase2_build::_path_is_equal_or_descendant \
                    $xil_root $observed_runner]
            }] {Vivado .Xil root remained below the external runner}
            assert_equal $observed_runner [file normalize [pwd]] \
                {Runner cwd was not restored after controlled execution}
        } finally {
            cd $caller_cwd
        }
    }

    run_case PHASE2_EXECUTION_DIRECTORIES_UNIQUE {
        set first_identifier \
            [::stage1e::phase2_controller::_workspace_identifier 14]
        set second_identifier \
            [::stage1e::phase2_controller::_workspace_identifier 15]
        assert_equal r14 $first_identifier \
            {Retry #14 human-readable workspace identifier}
        assert_equal r15 $second_identifier \
            {Retry #15 human-readable workspace identifier}
        assert_true [expr {$first_identifier ne $second_identifier}] \
            {Distinct retries share a workspace identifier}
        assert_equal $first_identifier \
            [::stage1e::phase2_controller::_workspace_identifier 14] \
            {Workspace identifier is not deterministic}
        set root [::stage1e::phase2_controller::_workspace_root]
        assert_true [expr {
            [file normalize [file join $root $first_identifier]] ne
            [file normalize [file join $root $second_identifier]]
        }] {Distinct executions resolve to the same workspace directory}
        foreach invalid_retry {{} 0 014 -1 abc} {
            assert_equal 1 [catch {
                ::stage1e::phase2_controller::_workspace_identifier \
                    $invalid_retry
            }] "Invalid retry number was accepted: $invalid_retry"
        }
    }

    run_case PHASE2_WORKSPACE_OWNERSHIP_EVIDENCE_VALID {
        variable path_test_root
        set original_workspace_root \
            $::stage1e::phase2_controller::controlled_workspace_root
        safe_path_cleanup
        try {
            set execution_identifier STAGE1E-20990101-010205-1234567
            set retry_number 14
            set simulated_repository [file join $path_test_root repository]
            set controlled_root [file join $path_test_root builds]
            set ::stage1e::phase2_controller::controlled_workspace_root \
                $controlled_root
            file mkdir $simulated_repository
            set context [path_preflight_context $execution_identifier \
                $retry_number $controlled_root \
                [file join $path_test_root artifacts]]
            dict set context parsed_arguments repository_root \
                [file normalize $simulated_repository]
            set input_result \
                [::stage1e::phase2_controller::_controlled_input_ready $context]
            assert_equal PASS [dict get $input_result status] \
                {Ownership-test input readiness}
            dict set context input_validation_outputs \
                [dict get $input_result outputs]
            dict set context source_verification [dict create \
                git_commit [string repeat 1 40] \
                controller_source_hash [string repeat 2 64] \
                configuration_hash [string repeat 3 64]]
            dict set context environment_verification [dict create \
                environment_evidence_hash [string repeat 4 64]]
            set result \
                [::stage1e::phase2_controller::_controlled_workspace_creation \
                    $context]
            assert_equal PASS [dict get $result status] \
                "Controlled workspace creation: [dict get $result errors]"
            set outputs [dict get $result outputs]
            set workspace [dict get $outputs execution_workspace]
            set workspace_identifier [dict get $outputs workspace_identifier]
            set ownership_path [file join $workspace \
                [dict get $outputs ownership_evidence]]
            assert_true [file isfile $ownership_path] \
                {Workspace ownership evidence is absent}
            set ownership [read_dict $ownership_path]
            assert_equal $execution_identifier \
                [dict get $ownership execution_identifier] \
                {Ownership lost the full execution identity}
            assert_equal $execution_identifier \
                [dict get $ownership execution_id] \
                {Ownership full execution_id binding}
            assert_equal $retry_number [dict get $ownership retry_number] \
                {Ownership retry-number binding}
            assert_equal [string repeat 1 40] \
                [dict get $ownership git_commit] \
                {Ownership Git commit binding}
            assert_equal [string repeat 2 40] \
                [dict get $ownership git_tree] \
                {Ownership Git tree binding}
            assert_equal [file normalize $workspace] \
                [dict get $ownership workspace_path] \
                {Ownership workspace-path binding}
            assert_equal $workspace_identifier \
                [dict get $ownership workspace_identifier] \
                {Ownership workspace identifier binding}
            assert_equal stage1e-phase2-workspace-identifier-v2 \
                [dict get $ownership workspace_identifier_schema_version] \
                {Ownership workspace identifier schema}
            assert_equal stage1e-workspace-identity-v2 \
                [dict get $ownership workspace_identity_schema_version] \
                {Ownership workspace identity schema}
            assert_equal [dict get $outputs workspace_identity_hash] \
                [dict get $ownership workspace_identity_hash] \
                {Ownership workspace identity hash}
            assert_equal [dict get $outputs workspace_identity_hash] \
                [dict get $outputs workspace_identity identity_sha256] \
                {Workspace identity hash is not deterministic}
            assert_equal ACTIVE_BUILD_WORKSPACE \
                [dict get $ownership workspace_role] \
                {Ownership workspace role}
            assert_equal 1 [dict get $outputs ownership_bound] \
                {Workspace ownership binding result}
            assert_equal r14 [file tail $workspace] \
                {Owned workspace directory leaf}

            set collision_result \
                [::stage1e::phase2_controller::_controlled_workspace_creation \
                    $context]
            assert_equal FAIL [dict get $collision_result status] \
                {Retry workspace collision was not rejected}
            assert_equal WORKSPACE_NOT_FRESH \
                [dict get [lindex [dict get $collision_result errors] 0] \
                    error_code] \
                {Retry workspace collision error code}
        } finally {
            set ::stage1e::phase2_controller::controlled_workspace_root \
                $original_workspace_root
            safe_path_cleanup
        }
    }

    run_case PHASE2_SYNTHESIS_AUTHORIZATION_PATH {
        reset_mock
        set result [run_controller]
        assert_equal PASS [dict get $result status] {Controller status}
        set authorization [dict get $contexts synthesis authorization]
        assert_equal AUTHORIZED [dict get $authorization status] \
            {Synthesis grant status}
        assert_equal controller_core [dict get $authorization authority] \
            {Synthesis grant owner}
        assert_equal stage1e::synthesis::run \
            [dict get $authorization operation] {Synthesis grant operation}
        assert_equal synthesis_enabled [dict get $authorization capability] \
            {Synthesis grant capability}
        assert_equal [dict get $result build_target_identity identity_sha256] \
            [dict get $contexts synthesis build_target_identity identity_sha256] \
            {Authorized build-target identity}
        assert_equal ACCEPTED [dict get $contexts synthesis \
            build_target_identity acceptance_state] \
            {Build target was not controller-accepted}
    }

    run_case PHASE2_SYNTHESIS_EVIDENCE_PATH_CONTRACT {
        reset_mock
        set result [run_controller]
        assert_equal PASS [dict get $result status] \
            {Synthesis evidence composition status}
        set synthesis_context [dict get $contexts synthesis]
        set workspace [dict get $synthesis_context workspace_identity]
        set expected_directory [file normalize [file join \
            [dict get $workspace evidence_dir] synthesis]]
        assert_true [file isdirectory $expected_directory] \
            {Synthesis evidence directory was not created}
        set synthesis_policy [dict get $synthesis_context synthesis_policy]
        foreach role {synthesis_report utilization_report message_report} {
            set path [dict get $synthesis_policy report_paths $role]
            assert_equal $expected_directory [file dirname $path] \
                "Synthesis report path contract: $role"
        }
        assert_equal $expected_directory [file dirname \
            [dict get $synthesis_policy run_log_path]] \
            {Synthesis log path contract}
        assert_true [expr {![file exists [file join \
            [dict get $workspace workspace_root] reports synthesis]]}] \
            {Sibling synthesis report directory was created}

        set composed [::stage1e::phase2_build::synthesis_evidence_paths \
            $workspace [dict get $profile build_policy synthesis]]
        assert_equal stage1e-synthesis-evidence-path-v1 \
            [dict get $composed schema_version] \
            {Synthesis evidence path schema}
        assert_equal $expected_directory [dict get $composed directory] \
            {Synthesis evidence path composition}
    }

    run_case PHASE2_SYNTHESIS_EVIDENCE_TRAVERSAL_REJECT {
        reset_mock
        set result [run_controller]
        assert_equal PASS [dict get $result status] \
            {Traversal precondition status}
        set workspace [dict get $contexts synthesis workspace_identity]
        set policy [dict get $profile build_policy synthesis]
        dict set policy output_policy report_directory_role ../synthesis
        set rejected [catch {
            ::stage1e::phase2_build::synthesis_evidence_paths \
                $workspace $policy
        } rejection]
        assert_true $rejected {Traversal evidence role was accepted}
        assert_true [expr {[string first {reviewed synthesis role} \
            $rejection] >= 0}] {Traversal rejection reason}

        set policy [dict get $profile build_policy synthesis]
        dict set policy report_policy synthesis_report ../synthesis.rpt
        set rejected [catch {
            ::stage1e::phase2_build::synthesis_evidence_paths \
                $workspace $policy
        } rejection]
        assert_true $rejected {Traversal report filename was accepted}
        assert_true [expr {[string first {plain relative filename} \
            $rejection] >= 0}] {Traversal filename rejection reason}
    }

    run_case PHASE2_CONTROLLER_COMPOSITION {
        reset_mock
        set result [run_controller]
        assert_equal PASS [dict get $result status] {Composition status}
        assert_equal SYNTHESIS_CANDIDATE_READY [dict get $result decision] \
            {Composition decision}
        assert_equal [lrange [dict get $configuration phase_order] 0 end] \
            [lrange $invocation_order 0 end] {Controller operation order}
        assert_equal [dict get $contexts project_creation execution_id] \
            [dict get $contexts synthesis execution_id] \
            {Execution identity propagation}
        assert_equal 1 [dict get $contexts build_target \
            bd_ownership validated] {Validated BD propagation}
        assert_equal 1 [dict get $contexts build_target \
            bd_ownership saved] {Saved BD propagation}
    }

    run_case PHASE2_CONTROLLER_SOURCE_HASH_BOUND {
        set source_policy [dict get $configuration source_verification]
        set inventory [::stage1d::source_check::hash_inventory \
            $repository_root [dict get $source_policy \
                controller_source_paths]]
        assert_equal [dict get $source_policy \
            expected_controller_source_sha256] \
            [::stage1d::source_check::aggregate_inventory_hash $inventory] \
            {Phase 2 controller inventory hash}
        assert_equal fpga/vivado/build/stage1e_phase2_synthesis_build.tcl \
            [dict get $profile identity_binding controller \
                controller_source_path] {Phase 2 controller entrypoint binding}
        assert_equal STAGE1E-PHASE2-SYNTHESIS-BUILD-v1 \
            [::stage1e::phase2_build::version] \
            {Phase 2 entrypoint version binding}
    }

    run_case PHASE2_NO_IMPLEMENTATION {
        reset_mock
        set result [run_controller]
        assert_equal 0 [dict get $result implementation_performed] \
            {Implementation boundary}
        assert_true [expr {{implementation} ni $invocation_order}] \
            {Implementation operation was composed}
        assert_true [expr {{IMPLEMENTATION} in [dict get $configuration \
            capability_policy disabled]}] \
            {Implementation is not disabled}
    }

    run_case PHASE2_NO_ARTIFACT {
        reset_mock
        set result [run_controller]
        foreach field {
            artifacts_generated artifact_collection_performed
            artifact_publication_performed board_access_performed
        } {
            assert_equal 0 [dict get $result $field] \
                "Forbidden result flag: $field"
        }
        foreach operation {
            artifact_collection artifact_publication implementation board_access
        } {
            assert_true [expr {$operation ni $invocation_order}] \
                "Forbidden operation was composed: $operation"
        }
    }
}

set suite_status [catch {
    ::stage1e::phase2_controller_tests::load_inputs
    ::stage1e::phase2_controller_tests::run_all
} suite_error suite_options]

if {$suite_status != 0} {
    incr ::stage1e::phase2_controller_tests::fail_count
    puts stderr "TEST SUITE: FAIL: $suite_error"
    if {[dict exists $suite_options -errorinfo]} {
        puts stderr [dict get $suite_options -errorinfo]
    }
}

catch {::stage1e::phase2_controller_tests::safe_cleanup}
catch {::stage1e::phase2_controller_tests::safe_path_cleanup}
puts "SUMMARY PASS=$::stage1e::phase2_controller_tests::pass_count FAIL=$::stage1e::phase2_controller_tests::fail_count"
if {$::stage1e::phase2_controller_tests::fail_count != 0} {
    exit 1
}
