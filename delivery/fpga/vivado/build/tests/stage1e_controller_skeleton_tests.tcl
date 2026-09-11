# Source-only verification for the Stage 1E Artifact Closure controller
# skeleton. The suite creates only a temporary external workspace and
# structured controller evidence. Vivado commands and FPGA artifact creation
# are guarded by tripwires.

namespace eval ::stage1e::controller_skeleton_tests {
    variable pass_count 0
    variable fail_count 0
    variable configuration {}
    variable controller_result {}
    variable test_root {}
    variable build_workspace_root {}
    variable artifact_storage_root {}
    variable vivado_invocation_count 0
    variable observed_stage1d_contexts [dict create]
    variable stage1d_version_before {}
    variable stage1d_api_before {}
    variable installed_tripwires {}
    variable native_exec_name \
        ::stage1e::controller_skeleton_tests::_native_exec
}

set stage1e_tests_root [file normalize [file dirname [info script]]]
set stage1e_build_root [file normalize [file join $stage1e_tests_root ..]]
set stage1e_repository_root [file normalize \
    [file join $stage1e_build_root .. .. ..]]
set stage1e_entrypoint [file join \
    $stage1e_build_root stage1e_artifact_build.tcl]

set stage1e_had_no_main [info exists ::env(STAGE1E_CONTROLLER_NO_MAIN)]
if {$stage1e_had_no_main} {
    set stage1e_prior_no_main $::env(STAGE1E_CONTROLLER_NO_MAIN)
}
set ::env(STAGE1E_CONTROLLER_NO_MAIN) 1
set stage1e_load_status [catch {
    source $stage1e_entrypoint
} stage1e_load_result stage1e_load_options]
if {$stage1e_had_no_main} {
    set ::env(STAGE1E_CONTROLLER_NO_MAIN) $stage1e_prior_no_main
} else {
    unset ::env(STAGE1E_CONTROLLER_NO_MAIN)
}
if {$stage1e_load_status != 0} {
    puts stderr "Unable to source Stage 1E controller: $stage1e_load_result"
    exit 1
}

set ::stage1e::controller_skeleton_tests::repository_root \
    $stage1e_repository_root
set ::stage1e::controller_skeleton_tests::build_root \
    $stage1e_build_root
set ::stage1e::controller_skeleton_tests::entrypoint \
    $stage1e_entrypoint
set ::stage1e::controller_skeleton_tests::configuration_path \
    [file join $stage1e_build_root config stage1e_build_config.dict]
set ::stage1e::controller_skeleton_tests::stage1d_version_before \
    [::stage1d::controller_core::version]
set ::stage1e::controller_skeleton_tests::stage1d_api_before \
    [::stage1d::controller_core::api_version]

proc ::stage1e::controller_skeleton_tests::fail {message} {
    error $message
}

proc ::stage1e::controller_skeleton_tests::assert_true {value message} {
    if {!$value} {
        fail $message
    }
}

proc ::stage1e::controller_skeleton_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::controller_skeleton_tests::assert_dictionary_equal {
    expected
    actual
    message
} {
    if {[catch {dict size $expected}] || [catch {dict size $actual}]} {
        fail "$message: value is not a dictionary"
    }
    set expected_keys [lsort -dictionary [dict keys $expected]]
    set actual_keys [lsort -dictionary [dict keys $actual]]
    assert_equal $expected_keys $actual_keys "$message keys"
    foreach key $expected_keys {
        assert_equal [dict get $expected $key] [dict get $actual $key] \
            "$message field=$key"
    }
}

proc ::stage1e::controller_skeleton_tests::run_case {name body} {
    variable pass_count
    variable fail_count

    set case_status [catch {uplevel 1 $body} case_result case_options]
    if {$case_status == 0} {
        incr pass_count
        puts "$name: PASS"
        return
    }
    incr fail_count
    puts stderr "$name: FAIL: $case_result"
    if {[dict exists $case_options -errorinfo]} {
        puts stderr [dict get $case_options -errorinfo]
    }
}

proc ::stage1e::controller_skeleton_tests::read_text {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} text read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $text
    }
    if {$close_status != 0} {
        error "Unable to close test input: $close_error"
    }
    return $text
}

proc ::stage1e::controller_skeleton_tests::temporary_base {} {
    if {[info exists ::env(STAGE1E_TEST_TEMP_ROOT)] &&
        [string trim $::env(STAGE1E_TEST_TEMP_ROOT)] ne {}} {
        set base $::env(STAGE1E_TEST_TEMP_ROOT)
    } else {
        set base {}
        foreach environment_variable {TEMP TMP TMPDIR} {
            if {[info exists ::env($environment_variable)] &&
                [string trim $::env($environment_variable)] ne {}} {
                set base $::env($environment_variable)
                break
            }
        }
    }
    if {$base eq {}} {
        error {No external temporary directory is available for source-only tests.}
    }
    set canonical [string map {\\ /} $base]
    if {$::tcl_platform(platform) eq {windows} &&
        [regexp {^[A-Za-z]:/} $canonical]} {
        # Preserve Windows paths through Tcl distributions that collapse
        # hidden or junction components during ordinary normalization.
        set canonical "//?/$canonical"
    }
    return [file normalize $canonical]
}

proc ::stage1e::controller_skeleton_tests::prepare_test_root {} {
    variable repository_root
    variable test_root
    variable build_workspace_root
    variable artifact_storage_root

    set base [temporary_base]
    set test_root [file normalize [file join $base \
        "stage1e_controller_tests_[pid]_[clock clicks]"]]
    if {[::stage1d::controller_core::_paths_overlap \
        $repository_root $test_root]} {
        error {Stage 1E tests require a temporary root external to the repository.}
    }
    if {![string match {stage1e_controller_tests_*} [file tail $test_root]]} {
        error {Refusing an unexpected Stage 1E test root.}
    }
    file mkdir $test_root
    set build_workspace_root [file join $test_root build_workspaces]
    set artifact_storage_root [file join $test_root artifact_storage]
}

proc ::stage1e::controller_skeleton_tests::safe_cleanup {} {
    variable repository_root
    variable test_root

    if {$test_root eq {} || ![file exists $test_root]} {
        return
    }
    set normalized [file normalize $test_root]
    if {![string match {stage1e_controller_tests_*} [file tail $normalized]] ||
        [::stage1d::controller_core::_paths_overlap \
            $repository_root $normalized]} {
        error "Refusing to clean an unsafe Stage 1E test root: $normalized"
    }
    file delete -force -- $normalized
}

proc ::stage1e::controller_skeleton_tests::load_configuration {} {
    variable configuration
    variable configuration_path
    variable repository_root

    if {$configuration eq {}} {
        set configuration [::stage1e::controller::load_configuration \
            $configuration_path $repository_root]
    }
    return $configuration
}

proc ::stage1e::controller_skeleton_tests::fake_source_context {context} {
    variable observed_stage1d_contexts
    if {[dict exists $context context_boundary]} {
        error {Stage 1E context leaked into the Stage 1D source adapter.}
    }
    dict set observed_stage1d_contexts source_validate \
        [lsort -dictionary [dict keys $context]]
    set configuration [dict get $context configuration]
    set commit [string tolower [dict get \
        $context execution_identity candidate_git_commit]]
    set outputs [dict create \
        git_commit $commit \
        worktree_clean 1 \
        source_state_frozen 1 \
        controller_source_hash [dict get \
            $configuration source_verification \
            expected_controller_source_sha256] \
        configuration_hash [::stage1d::source_check::sha256_file \
            [dict get $configuration configuration_path]] \
        project_created 0 \
        bd_created 0 \
        synthesis_invoked 0 \
        implementation_invoked 0 \
        vivado_invoked 0 \
        artifacts_generated 0 \
        manifest_published 0]
    return [::stage1e::controller::_phase_result PASS $outputs]
}

proc ::stage1e::controller_skeleton_tests::fake_environment_context {context} {
    variable observed_stage1d_contexts
    if {[dict exists $context context_boundary]} {
        error {Stage 1E context leaked into the Stage 1D environment adapter.}
    }
    dict set observed_stage1d_contexts environment_validate \
        [lsort -dictionary [dict keys $context]]
    set source_commit [dict get $context source_verification git_commit]
    set outputs [dict create \
        environment_verified 1 \
        vivado_identity_verified 1 \
        target_identity_verified 1 \
        required_ip_verified 1 \
        environment_evidence_hash \
            dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
        custom_protection_ip_provenance [dict create \
            vlnv zsr112.local:protection:protection_ip_axi_lite:0.3 \
            source_git_commit $source_commit \
            packaged_ip_created 0 \
            catalog_identity_verified 0] \
        project_created 0 \
        bd_created 0 \
        synthesis_invoked 0 \
        implementation_invoked 0 \
        vivado_invoked 0 \
        artifacts_generated 0 \
        manifest_published 0]
    return [::stage1e::controller::_phase_result PASS $outputs]
}

proc ::stage1e::controller_skeleton_tests::observed_workspace_context {
    context
} {
    variable observed_stage1d_contexts
    if {[dict exists $context context_boundary]} {
        error {Stage 1E context leaked into the Stage 1D workspace adapter.}
    }
    dict set observed_stage1d_contexts workspace_create \
        [lsort -dictionary [dict keys $context]]
    return [::stage1d::workspace_manager::run $context]
}

proc ::stage1e::controller_skeleton_tests::vivado_tripwire {
    command_name
    args
} {
    variable vivado_invocation_count
    incr vivado_invocation_count
    error "Forbidden Vivado command invoked: $command_name"
}

proc ::stage1e::controller_skeleton_tests::guarded_exec {args} {
    variable vivado_invocation_count
    variable native_exec_name

    if {[llength $args] > 0} {
        set executable [string tolower [file tail [lindex $args 0]]]
        if {$executable in {vivado vivado.bat vivado.exe}} {
            incr vivado_invocation_count
            error "Forbidden Vivado executable invocation: [lindex $args 0]"
        }
    }
    return [uplevel 1 [linsert $args 0 $native_exec_name]]
}

proc ::stage1e::controller_skeleton_tests::install_tripwires {} {
    variable installed_tripwires
    variable native_exec_name

    set installed_tripwires {}
    foreach command_name {
        create_project
        open_project
        create_bd_design
        generate_target
        make_wrapper
        synth_design
        opt_design
        place_design
        route_design
        launch_runs
        wait_on_run
        write_bitstream
        write_debug_probes
        write_hw_platform
    } {
        set command_path ::$command_name
        if {[llength [info commands $command_path]] == 0} {
            interp alias {} $command_path {} \
                ::stage1e::controller_skeleton_tests::vivado_tripwire \
                $command_name
            lappend installed_tripwires $command_path
        }
    }
    if {[llength [info commands $native_exec_name]] != 0} {
        error {Stage 1E test exec tripwire is already installed.}
    }
    rename ::exec $native_exec_name
    proc ::exec {args} {
        return [::stage1e::controller_skeleton_tests::guarded_exec {*}$args]
    }
}

proc ::stage1e::controller_skeleton_tests::remove_tripwires {} {
    variable installed_tripwires
    variable native_exec_name

    foreach command_path $installed_tripwires {
        if {[llength [info commands $command_path]] != 0} {
            rename $command_path {}
        }
    }
    set installed_tripwires {}
    if {[llength [info commands $native_exec_name]] != 0} {
        if {[llength [info commands ::exec]] != 0} {
            rename ::exec {}
        }
        rename $native_exec_name ::exec
    }
}

proc ::stage1e::controller_skeleton_tests::ensure_controller_result {} {
    variable repository_root
    variable build_workspace_root
    variable artifact_storage_root
    variable configuration_path
    variable controller_result

    if {$controller_result ne {}} {
        return $controller_result
    }
    load_configuration
    set arguments [list \
        --repository-root $repository_root \
        --build-workspace $build_workspace_root \
        --artifact-storage $artifact_storage_root \
        --configuration $configuration_path \
        --environment-evidence $configuration_path \
        --git-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa]
    set overrides [dict create \
        source_validate \
            ::stage1e::controller_skeleton_tests::fake_source_context \
        environment_validate \
            ::stage1e::controller_skeleton_tests::fake_environment_context \
        workspace_create \
            ::stage1e::controller_skeleton_tests::observed_workspace_context]

    install_tripwires
    set run_status [catch {
        ::stage1e::controller::invoke $arguments $overrides
    } run_result run_options]
    remove_tripwires
    if {$run_status != 0} {
        return -options $run_options $run_result
    }
    set controller_result $run_result
    return $controller_result
}

proc ::stage1e::controller_skeleton_tests::phase_outputs {
    result
    phase_name
} {
    foreach evidence [dict get $result phase_evidence] {
        if {[dict get $evidence phase_name] eq $phase_name} {
            return [dict get $evidence outputs]
        }
    }
    error "Stage 1E phase evidence not found: $phase_name"
}

proc ::stage1e::controller_skeleton_tests::collect_files {root} {
    if {![file isdirectory $root]} {
        return {}
    }
    set files {}
    foreach path [glob -nocomplain -directory $root * .*] {
        if {[file tail $path] in {. ..}} {
            continue
        }
        if {[file isdirectory $path] && [file type $path] ne {link}} {
            foreach nested [collect_files $path] {
                lappend files $nested
            }
        } elseif {[file isfile $path]} {
            lappend files $path
        }
    }
    return $files
}

proc ::stage1e::controller_skeleton_tests::run_all {} {
    variable repository_root
    variable build_root
    variable entrypoint
    variable configuration_path
    variable build_workspace_root
    variable artifact_storage_root
    variable vivado_invocation_count
    variable observed_stage1d_contexts
    variable stage1d_version_before
    variable stage1d_api_before

    run_case STAGE1E_CONFIG_VALID {
        set configuration [load_configuration]
        assert_equal stage1e-build-config-v2 \
            [dict get $configuration schema_version] \
            {Stage 1E configuration schema mismatch}
        assert_dictionary_equal \
            [::stage1e::controller::build_profile_identity] \
            [dict get $configuration build_profile_identity] \
            {Stage 1E build profile identity mismatch}
        assert_dictionary_equal [::stage1e::controller::skeleton_scope] \
            [dict get $configuration skeleton_scope] \
            {Stage 1E skeleton scope mismatch}
        assert_equal [list {*}[::stage1e::controller::phase_order]] \
            [list {*}[dict get $configuration build_phases phase_order]] \
            {Stage 1E phase configuration mismatch}
        assert_equal APPEND_ONLY [dict get $configuration \
            source_inventory_extensions extension_mechanism] \
            {Stage 1E source inventory extension is not append-only}
        foreach disabled_field [dict keys \
            [::stage1e::controller::disabled_capabilities]] {
            assert_equal 0 \
                [dict get $configuration disabled_capabilities \
                    flags $disabled_field] \
                "Stage 1E configuration unexpectedly enables $disabled_field"
        }
        assert_dictionary_equal \
            [::stage1e::controller::future_phase_boundaries] \
            [dict get $configuration future_phase_boundaries \
                phase_capability_map] \
            {Stage 1E future phase boundary mapping mismatch}
        foreach role [dict values \
            [dict get $configuration artifact_roles placeholders]] {
            assert_equal 1 [dict get $role placeholder] \
                {Stage 1E artifact role is not a placeholder}
            foreach disabled_field {
                generation_enabled
                collection_enabled
                publication_enabled
            } {
                assert_equal 0 [dict get $role $disabled_field] \
                    "Stage 1E artifact role enables $disabled_field"
            }
        }
        set required_paths [dict get \
            $configuration source_verification required_paths]
        assert_equal [llength $required_paths] \
            [llength [lsort -unique $required_paths]] \
            {Stage 1E required source inventory contains duplicates}
        ::stage1d::source_check::hash_inventory \
            $repository_root $required_paths
        set controller_inventory [::stage1d::source_check::hash_inventory \
            $repository_root [dict get $configuration \
                source_verification controller_source_paths]]
        assert_equal [dict get $configuration source_verification \
            expected_controller_source_sha256] \
            [::stage1d::source_check::aggregate_inventory_hash \
                $controller_inventory] \
            {Stage 1E controller source aggregate hash mismatch}
        assert_true [info complete [read_text $entrypoint]] \
            {Stage 1E entrypoint is not a complete Tcl script}
        set raw_configuration [string trim [read_text $configuration_path]]
        assert_true [expr {![catch {dict size $raw_configuration}]}] \
            {Stage 1E configuration is not a declarative Tcl dictionary}
        set invalid_configuration $configuration
        dict set invalid_configuration disabled_capabilities \
            flags synthesis_enabled 1
        assert_equal 1 [catch {
            ::stage1e::controller::validate_configuration \
                $invalid_configuration
        }] {Stage 1E configuration did not fail closed on synthesis enablement}
    }

    run_case STAGE1E_SOURCE_CONTEXT_VALID {
        set configuration [load_configuration]
        set context [dict create \
            configuration $configuration \
            execution_identity [::stage1e::controller::generate_execution_identity \
                aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0]]
        set result [fake_source_context $context]
        assert_equal 1 \
            [::stage1e::controller::validate_source_context $result] \
            {Stage 1E source context validation failed}
        set invalid_result $result
        dict set invalid_result outputs worktree_clean 0
        assert_equal 1 [catch {
            ::stage1e::controller::validate_source_context $invalid_result
        }] {Stage 1E source context did not fail closed}
    }

    run_case STAGE1E_ENVIRONMENT_CONTEXT_VALID {
        set configuration [load_configuration]
        set source_result [fake_source_context [dict create \
            configuration $configuration \
            execution_identity [::stage1e::controller::generate_execution_identity \
                aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0]]]
        set result [fake_environment_context [dict create \
            source_verification [dict get $source_result outputs]]]
        assert_equal 1 \
            [::stage1e::controller::validate_environment_context $result] \
            {Stage 1E environment context validation failed}
        set invalid_result $result
        dict set invalid_result outputs custom_protection_ip_provenance \
            packaged_ip_created 1
        assert_equal 1 [catch {
            ::stage1e::controller::validate_environment_context \
                $invalid_result
        }] {Stage 1E environment context did not fail closed}
    }

    run_case STAGE1E_WORKSPACE_VALID {
        set result [ensure_controller_result]
        assert_equal READY [dict get $result decision] \
            {Stage 1E skeleton did not become ready}
        set outputs [phase_outputs $result WORKSPACE_READY]
        assert_equal 1 [dict get $outputs workspace_created] \
            {Stage 1E external workspace was not created}
        assert_equal 1 [dict get $outputs ownership_bound] \
            {Stage 1E workspace ownership was not bound}
        assert_true [file isfile [file join \
            [dict get $outputs execution_workspace] \
            [dict get $outputs ownership_evidence]]] \
            {Stage 1E workspace ownership evidence is absent}
        set persistence [dict get $result phase_evidence_persistence]
        assert_equal PASS [dict get $persistence status] \
            {Stage 1E structured phase evidence was not persisted}
        assert_true [file isfile [dict get $persistence evidence_path]] \
            {Stage 1E structured phase evidence file is absent}
        assert_true [expr {![file exists [dict get $outputs artifact_group]]}] \
            {Stage 1E workspace helper created an artifact group}
        set persisted [string trim [read_text \
            [dict get $persistence evidence_path]]]
        assert_equal BUILD_CONTROLLER_READY [dict get $persisted current_state] \
            {Persisted Stage 1E state is incorrect}
        assert_dictionary_equal [::stage1e::controller::skeleton_scope] \
            [dict get $persisted skeleton_scope] \
            {Persisted Stage 1E scope identity mismatch}
        assert_dictionary_equal [::stage1e::controller::context_boundary] \
            [dict get $persisted context_boundary] \
            {Persisted Stage 1E context boundary mismatch}
    }

    run_case STAGE1E_PHASE_ORDER_VALID {
        set result [ensure_controller_result]
        set observed_order {}
        foreach evidence [dict get $result phase_evidence] {
            lappend observed_order [dict get $evidence phase_name]
            assert_equal PASS [dict get $evidence status] \
                {Stage 1E readiness phase did not pass}
        }
        assert_equal [list {*}[::stage1e::controller::phase_order]] \
            [list {*}$observed_order] \
            {Stage 1E phase execution order mismatch}
        assert_equal BUILD_CONTROLLER_READY [dict get $result current_state] \
            {Stage 1E final skeleton state mismatch}
        set forbidden_status [catch {
            set state [::stage1e::controller::new_state \
                [::stage1e::controller::generate_execution_identity \
                    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0]]
            ::stage1e::controller::transition state SYNTHESIS {}
        }]
        assert_equal 1 $forbidden_status \
            {Stage 1E skeleton allowed a SYNTHESIS transition}
    }

    run_case STAGE1E_DEFAULT_NO_BUILD_EXECUTION {
        set result [ensure_controller_result]
        set operations [::stage1e::controller::default_operations]
        assert_equal [list \
            input_ready \
            source_validate \
            environment_validate \
            workspace_create \
            controller_ready \
            persist_evidence] [dict keys $operations] \
            {Stage 1E default operation boundary mismatch}
        foreach field [dict keys \
            [::stage1e::controller::disabled_execution_status]] {
            assert_equal 0 [dict get $result $field] \
                "Stage 1E skeleton unexpectedly enabled $field"
        }
        assert_equal 1 [dict get $result build_controller_ready] \
            {Stage 1E controller readiness was not established}
    }

    run_case STAGE1D_ISOLATION_VALID {
        set result [ensure_controller_result]
        assert_equal $stage1d_version_before \
            [::stage1d::controller_core::version] \
            {Stage 1D controller version changed during Stage 1E execution}
        assert_equal $stage1d_api_before \
            [::stage1d::controller_core::api_version] \
            {Stage 1D controller API changed during Stage 1E execution}
        set boundary [dict get $result context_boundary]
        assert_equal MINIMUM_REQUIRED_FIELDS [dict get $boundary \
            stage1d_adapter_policy] \
            {Stage 1E did not enforce the minimum Stage 1D adapter context}
        assert_equal UNCHANGED [dict get $boundary \
            stage1d_controller_core_ownership] \
            {Stage 1E expanded Stage 1D controller_core ownership}
        assert_equal NOT_IMPORTED [dict get $boundary \
            stage1d_lifecycle_authority] \
            {Stage 1E imported Stage 1D lifecycle authority}
        assert_equal NOT_IMPORTED [dict get $boundary \
            stage1d_mutation_authority] \
            {Stage 1E imported Stage 1D mutation authority}
        assert_equal NOT_GRANTED [dict get $boundary build_authority] \
            {Stage 1E context granted build authority}
        foreach {operation expected_fields} [list \
            source_validate {
                configuration
                execution_identity
                input_validation_outputs
                parsed_arguments
            } \
            environment_validate {
                configuration
                parsed_arguments
                source_verification
            } \
            workspace_create {
                configuration
                environment_verification
                execution_identity
                input_validation_outputs
                parsed_arguments
                source_verification
            }] {
            assert_equal [lsort -dictionary $expected_fields] \
                [dict get $observed_stage1d_contexts $operation] \
                "Stage 1D adapter field boundary mismatch: $operation"
        }
        set operations [::stage1e::controller::default_operations]
        assert_equal ::stage1d::source_check::run \
            [dict get $operations source_validate] \
            {Stage 1E no longer reuses Stage 1D source verification}
        assert_equal ::stage1d::environment_check::run \
            [dict get $operations environment_validate] \
            {Stage 1E no longer reuses Stage 1D environment verification}
        assert_equal ::stage1d::workspace_manager::run \
            [dict get $operations workspace_create] \
            {Stage 1E no longer reuses Stage 1D workspace isolation}
    }

    run_case STAGE1E_BUILD_DISABLED_ENFORCEMENT {
        set configuration [load_configuration]
        set result [ensure_controller_result]
        set expected [::stage1e::controller::disabled_capabilities]
        assert_dictionary_equal $expected \
            [dict get $result disabled_capabilities] \
            {Stage 1E result capability boundary mismatch}
        foreach capability [dict keys $expected] {
            assert_equal 0 [dict get $configuration \
                disabled_capabilities flags $capability] \
                "Stage 1E capability is enabled: $capability"
            set invalid_configuration $configuration
            dict set invalid_configuration disabled_capabilities \
                flags $capability 1
            assert_equal 1 [catch {
                ::stage1e::controller::validate_configuration \
                    $invalid_configuration
            }] "Stage 1E accepted enabled capability: $capability"
        }
        foreach field [dict keys \
            [::stage1e::controller::disabled_execution_status]] {
            assert_equal 0 [dict get $result $field] \
                "Stage 1E execution status is not disabled: $field"
        }
        foreach role [dict values \
            [dict get $result artifact_role_placeholders]] {
            assert_equal 1 [dict get $role placeholder] \
                {Accepted output role is not a disabled placeholder}
            assert_equal 0 [dict get $role generation_enabled] \
                {Artifact generation placeholder is enabled}
            assert_equal 0 [dict get $role collection_enabled] \
                {Artifact collection placeholder is enabled}
            assert_equal 0 [dict get $role publication_enabled] \
                {Artifact publication placeholder is enabled}
        }
    }

    run_case STAGE1E_FUTURE_PHASE_BLOCKING {
        set configuration [load_configuration]
        set result [ensure_controller_result]
        set boundaries [::stage1e::controller::future_phase_boundaries]
        assert_equal DENY [dict get $configuration \
            future_phase_boundaries default_transition_policy] \
            {Stage 1E future transition policy is not deny-by-default}
        assert_dictionary_equal $boundaries \
            [dict get $result future_phase_boundaries] \
            {Stage 1E result future boundary mismatch}
        foreach future_phase [dict keys $boundaries] {
            set state [::stage1e::controller::new_state \
                [::stage1e::controller::generate_execution_identity \
                    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0]]
            assert_equal 1 [catch {
                ::stage1e::controller::transition \
                    state $future_phase {}
            }] "Stage 1E allowed future phase: $future_phase"
        }
        set state [::stage1e::controller::new_state \
            [::stage1e::controller::generate_execution_identity \
                aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0]]
        assert_equal 1 [catch {
            ::stage1e::controller::transition state ARTIFACT_READY {}
        }] {Stage 1E allowed legacy ARTIFACT_READY transition}
        foreach evidence [dict get $result phase_evidence] {
            assert_true [expr {
                ![dict exists $boundaries [dict get $evidence phase_name]]
            }] {Future phase appeared in Stage 1E skeleton evidence}
        }
    }

    run_case STAGE1E_CAPABILITY_CONFIG_ALIGNMENT {
        set configuration [load_configuration]
        set configured_flags [dict get $configuration \
            disabled_capabilities flags]
        set configured_phase_map [dict get $configuration \
            future_phase_boundaries phase_capability_map]
        set controller_phase_map \
            [::stage1e::controller::future_phase_boundaries]
        set expected_matrix [dict create \
            ip_packaging [dict create \
                flag ip_packaging_enabled phase IP_PACKAGING] \
            project_reconstruction [dict create \
                flag project_reconstruction_enabled \
                phase PROJECT_RECONSTRUCTION] \
            bd_generation [dict create \
                flag bd_generation_enabled phase BD_GENERATION] \
            wrapper_generation [dict create \
                flag wrapper_generation_enabled \
                phase WRAPPER_GENERATION] \
            synthesis [dict create \
                flag synthesis_enabled phase SYNTHESIS] \
            implementation [dict create \
                flag implementation_enabled phase IMPLEMENTATION] \
            artifact_collection [dict create \
                flag artifact_collection_enabled \
                phase ARTIFACT_COLLECTION] \
            artifact_publication [dict create \
                flag publication_enabled phase PUBLICATION]]

        assert_equal 8 [dict size $expected_matrix] \
            {Stage 1E capability alignment matrix size mismatch}
        assert_dictionary_equal $configured_phase_map \
            $controller_phase_map \
            {Configuration/controller future phase map mismatch}

        set expected_flags {}
        set expected_phases {}
        foreach logical_capability [dict keys $expected_matrix] {
            set binding [dict get $expected_matrix $logical_capability]
            set flag [dict get $binding flag]
            set phase [dict get $binding phase]
            lappend expected_flags $flag
            lappend expected_phases $phase

            assert_true [dict exists $configured_flags $flag] \
                "Configuration omits capability: $logical_capability"
            assert_equal 0 [dict get $configured_flags $flag] \
                "Configuration enables capability: $logical_capability"
            assert_true [dict exists $configured_phase_map $phase] \
                "Configuration omits future phase: $phase"
            assert_true [dict exists $controller_phase_map $phase] \
                "Controller omits future phase: $phase"
            assert_equal $flag [dict get $configured_phase_map $phase] \
                "Configuration phase binding mismatch: $phase"
            assert_equal $flag [dict get $controller_phase_map $phase] \
                "Controller phase binding mismatch: $phase"

            set state [::stage1e::controller::new_state \
                [::stage1e::controller::generate_execution_identity \
                    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0]]
            assert_equal 1 [catch {
                ::stage1e::controller::transition state $phase {}
            }] "Disabled capability transitioned to execution: $phase"
        }

        assert_equal [lsort -dictionary -unique $expected_flags] \
            [lsort -dictionary -unique \
                [dict values $controller_phase_map]] \
            {Controller capability exists without matrix declaration}
        assert_equal [lsort -dictionary -unique $expected_phases] \
            [lsort -dictionary -unique \
                [dict keys $controller_phase_map]] \
            {Controller phase exists without configuration declaration}

        set enabled_capabilities {}
        foreach flag [dict keys $configured_flags] {
            if {[dict get $configured_flags $flag]} {
                lappend enabled_capabilities $flag
                assert_true [expr {
                    $flag in [dict values $controller_phase_map]
                }] "Enabled capability lacks controller support: $flag"
            }
        }
        assert_equal {} $enabled_capabilities \
            {Stage 1E configuration contains an enabled capability}
        foreach phase [dict keys $controller_phase_map] {
            set flag [dict get $controller_phase_map $phase]
            assert_true [dict exists $configured_flags $flag] \
                "Controller phase lacks configuration declaration: $phase"
        }
    }

    run_case NO_VIVADO_INVOCATION {
        set result [ensure_controller_result]
        assert_equal 0 $vivado_invocation_count \
            {A Vivado command or executable was invoked}
        assert_equal 0 [dict get $result vivado_invoked] \
            {Stage 1E result reported Vivado invocation}
        foreach operation [dict values \
            [::stage1e::controller::default_operations]] {
            assert_true [expr {![string match {*vivado_project*} $operation]}] \
                {Stage 1E default operation reaches a Vivado project helper}
            assert_true [expr {![string match {*bd_flow*} $operation]}] \
                {Stage 1E default operation reaches a BD helper}
        }
    }

    run_case NO_ARTIFACT_GENERATION {
        set result [ensure_controller_result]
        assert_equal 0 [dict get $result artifacts_generated] \
            {Stage 1E result reported artifact generation}
        assert_true [expr {![file exists $artifact_storage_root]}] \
            {Stage 1E skeleton created artifact storage content}
        set forbidden_extensions {.bit .hwh .xsa .ltx .dcp .xpr}
        foreach path [collect_files $build_workspace_root] {
            assert_true [expr {
                [string tolower [file extension $path]] ni $forbidden_extensions
            }] "Stage 1E skeleton generated a forbidden file: $path"
        }
    }
}

set stage1e_test_status [catch {
    ::stage1e::controller_skeleton_tests::prepare_test_root
    ::stage1e::controller_skeleton_tests::run_all
} stage1e_test_result stage1e_test_options]
set stage1e_cleanup_status [catch {
    ::stage1e::controller_skeleton_tests::remove_tripwires
    ::stage1e::controller_skeleton_tests::safe_cleanup
} stage1e_cleanup_result]

if {$stage1e_test_status != 0} {
    puts stderr "Stage 1E test suite failed unexpectedly: $stage1e_test_result"
    if {[dict exists $stage1e_test_options -errorinfo]} {
        puts stderr [dict get $stage1e_test_options -errorinfo]
    }
    exit 1
}
if {$stage1e_cleanup_status != 0} {
    puts stderr "Stage 1E test cleanup failed: $stage1e_cleanup_result"
    exit 1
}

set stage1e_pass_count \
    $::stage1e::controller_skeleton_tests::pass_count
set stage1e_fail_count \
    $::stage1e::controller_skeleton_tests::fail_count
puts "STAGE1E_TEST_SUMMARY: PASS=$stage1e_pass_count FAIL=$stage1e_fail_count"
if {$stage1e_fail_count != 0} {
    exit 1
}
exit 0
