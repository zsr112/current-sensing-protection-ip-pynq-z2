# Source-only contract tests for stage1e_reconstruction_profile_v1.
#
# This suite parses the profile as a Tcl dictionary and reads adapter sources
# as text. It does not source an adapter, invoke Vivado, authorize a build, or
# create generated state.

namespace eval ::stage1e::reconstruction_profile_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_directory [file normalize [file dirname [info script]]]
    variable repository_root [file normalize [file join \
        [file dirname [info script]] .. .. .. ..]]
    variable profile_path {}
    variable skeleton_config_path {}
    variable profile_text {}
    variable profile {}
    variable skeleton_config {}
}

proc ::stage1e::reconstruction_profile_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::reconstruction_profile_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::reconstruction_profile_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::reconstruction_profile_tests::assert_set_equal {
    expected
    actual
    message
} {
    set expected_sorted [lsort -dictionary $expected]
    set actual_sorted [lsort -dictionary $actual]
    if {$expected_sorted ne $actual_sorted ||
        [llength $actual] != [llength [lsort -unique $actual]]} {
        fail "$message: expected=<$expected_sorted> actual=<$actual_sorted>"
    }
}

proc ::stage1e::reconstruction_profile_tests::assert_dict_keys {
    dictionary
    required_keys
    label
} {
    if {[catch {dict size $dictionary} dictionary_error]} {
        fail "$label is not a dictionary: $dictionary_error"
    }
    foreach key $required_keys {
        if {![dict exists $dictionary $key]} {
            fail "$label is missing key: $key"
        }
    }
}

proc ::stage1e::reconstruction_profile_tests::read_text {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} contents read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $contents
    }
    if {$close_status != 0} {
        error "Unable to close $path: $close_error"
    }
    return $contents
}

proc ::stage1e::reconstruction_profile_tests::read_dict {path label} {
    set contents [read_text $path]
    if {[catch {dict size $contents} dictionary_error]} {
        fail "$label is not valid Tcl dictionary syntax: $dictionary_error"
    }
    return $contents
}

proc ::stage1e::reconstruction_profile_tests::run_case {name body} {
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

proc ::stage1e::reconstruction_profile_tests::load_inputs {} {
    variable repository_root
    variable profile_path
    variable skeleton_config_path
    variable profile_text
    variable profile
    variable skeleton_config
    set profile_path [file normalize [file join $repository_root fpga vivado \
        build config stage1e_reconstruction_profile_v1.dict]]
    set skeleton_config_path [file normalize [file join $repository_root fpga \
        vivado build config stage1e_build_config.dict]]
    if {![file isfile $profile_path]} {
        error "Reconstruction profile is unavailable: $profile_path"
    }
    if {![file isfile $skeleton_config_path]} {
        error "Historical skeleton config is unavailable: $skeleton_config_path"
    }
    set profile_text [read_text $profile_path]
    set profile [read_dict $profile_path {Reconstruction profile}]
    set skeleton_config [read_dict $skeleton_config_path \
        {Historical skeleton configuration}]
}

proc ::stage1e::reconstruction_profile_tests::expected_capabilities {} {
    return {
        IP_PACKAGING
        PROJECT_RECONSTRUCTION
        BD_GENERATION
        WRAPPER_GENERATION
        SYNTHESIS
        IMPLEMENTATION
        ARTIFACT_COLLECTION
        ARTIFACT_PUBLICATION
    }
}

proc ::stage1e::reconstruction_profile_tests::expected_phase1_enabled {} {
    return {
        IP_PACKAGING
        PROJECT_RECONSTRUCTION
        BD_GENERATION
        WRAPPER_GENERATION
    }
}

proc ::stage1e::reconstruction_profile_tests::expected_phase1_disabled {} {
    return {
        SYNTHESIS
        IMPLEMENTATION
        ARTIFACT_COLLECTION
        ARTIFACT_PUBLICATION
    }
}

proc ::stage1e::reconstruction_profile_tests::expected_phase2_enabled {} {
    return {
        IP_PACKAGING
        PROJECT_RECONSTRUCTION
        BD_GENERATION
        WRAPPER_GENERATION
        SYNTHESIS
    }
}

proc ::stage1e::reconstruction_profile_tests::expected_phase2_disabled {} {
    return {
        IMPLEMENTATION
        ARTIFACT_COLLECTION
        ARTIFACT_PUBLICATION
    }
}

proc ::stage1e::reconstruction_profile_tests::adapter_expectations {} {
    return [dict create \
        stage1e_ip_packaging [dict create \
            work_package WP-B capability IP_PACKAGING \
            interface stage1e::ip_packaging::run] \
        vivado_project::create [dict create \
            work_package WP-B capability PROJECT_RECONSTRUCTION \
            interface vivado_project::create] \
        bd_flow::create [dict create \
            work_package WP-B capability BD_GENERATION \
            interface bd_flow::create] \
        stage1e_base_design [dict create \
            work_package WP-B capability BD_GENERATION \
            interface stage1e::base_design::apply] \
        stage1e_debug_design [dict create \
            work_package WP-B capability BD_GENERATION \
            interface stage1e::debug_design::apply] \
        stage1e_mutation_bridge [dict create \
            work_package WP-B capability BD_GENERATION \
            interface stage1e::mutation_bridge::apply] \
        stage1e_build_target [dict create \
            work_package WP-B capability WRAPPER_GENERATION \
            interface stage1e::build_target::prepare] \
        stage1e_synthesis [dict create \
            work_package WP-C capability SYNTHESIS \
            interface stage1e::synthesis::run]]
}

proc ::stage1e::reconstruction_profile_tests::run_all {} {
    variable repository_root
    variable profile_path
    variable profile_text
    variable profile
    variable skeleton_config

    run_case PROFILE_SCHEMA_VALID {
        assert_equal stage1e-reconstruction-profile-schema-v1 \
            [dict get $profile schema_version] {Profile schema version}
        assert_dict_keys $profile {
            schema_version
            profile_identity
            profile_state
            capability_model
            adapter_inventory
            identity_binding
            authorization_policy
            build_policy
            constraint_policy
        } profile
        foreach section {
            profile_identity profile_state capability_model adapter_inventory
            identity_binding authorization_policy build_policy constraint_policy
        } {
            assert_true [expr {![catch {dict size [dict get $profile $section]}]}] \
                "Profile section is not a dictionary: $section"
        }
    }

    run_case PROFILE_IDENTITY_VALID {
        set identity [dict get $profile profile_identity]
        assert_equal stage1e_reconstruction_profile_v1 \
            [dict get $identity profile_id] {Profile identifier}
        assert_equal v1 [dict get $identity profile_version] {Profile version}
        assert_equal STAGE1E [dict get $identity stage] {Profile stage}
        assert_equal STAGE1E_RECONSTRUCTION_AND_BUILD \
            [dict get $identity scope_id] {Profile scope}
        assert_equal SYNTHESIS_READY_EXECUTION_CONFIGURATION \
            [dict get $identity configuration_role] \
            {Profile configuration role}
        assert_equal PHASE2_SYNTHESIS [dict get $identity active_phase] \
            {Active profile phase}
        assert_equal stage1e_controller_skeleton \
            [dict get $identity supersedes_intended_role] \
            {Historical profile reference}
        assert_equal 1 [dict get $identity historical_profile_semantics_unchanged] \
            {Historical profile isolation declaration}

        # The old file remains the readiness-only profile and is not selected
        # or reinterpreted by this standalone profile implementation.
        assert_equal stage1e_controller_skeleton \
            [dict get $skeleton_config build_profile] \
            {Historical skeleton build profile}
        assert_equal READINESS_ONLY \
            [dict get $skeleton_config skeleton_scope execution_mode] \
            {Historical skeleton execution mode}
        assert_equal BUILD_CONTROLLER_READY \
            [dict get $skeleton_config skeleton_scope terminal_state] \
            {Historical skeleton terminal state}
        assert_equal 0 \
            [dict get $skeleton_config skeleton_scope build_execution_permitted] \
            {Historical skeleton execution permission}
    }

    run_case CONTROLLED_BUILD_SOURCE_CLOSURE {
        set phase2_configuration [read_dict [file normalize [file join \
            $repository_root fpga vivado build config \
            stage1e_phase2_synthesis_config_v1.dict]] \
            {Phase 2 synthesis configuration}]
        set stage1d_configuration [read_dict [file normalize [file join \
            $repository_root fpga vivado build config \
            stage1d_build_config.dict]] \
            {Stage 1D build configuration}]
        set reset_source rtl/reset_release_sync.v
        set stage2d_sources {
            rtl/adc_sample_cdc_bridge.v
            rtl/async_fifo_gray.v
            rtl/protection_ip_top_async_adc_axi_lite.v
        }
        set stage2f_sources {
            rtl/adc_sample_code_normalizer.sv
            rtl/generated/stage2f_adc_source_profile.svh
        }
        foreach key_path {
            {source_verification required_paths}
            {environment custom_protection_ip source_paths}
            {reconstruction_policy packaging source_paths}
            {reconstruction_policy packaging package_inventory source_paths}
        } {
            set configured_paths [dict get $phase2_configuration {*}$key_path]
            assert_equal 1 [llength [lsearch -all -exact \
                $configured_paths $reset_source]] \
                "Phase 2 source authority must contain reset synchronizer once: $key_path"
            foreach source $stage2d_sources {
                assert_equal 1 [llength [lsearch -all -exact \
                    $configured_paths $source]] \
                    "Phase 2 source authority must contain $source once: $key_path"
            }
            foreach source $stage2f_sources {
                assert_equal 1 [llength [lsearch -all -exact \
                    $configured_paths $source]] \
                    "Phase 2 source authority must contain $source once: $key_path"
            }
        }
        foreach key_path {
            {source_verification required_paths}
            {environment custom_protection_ip source_paths}
        } {
            set configured_paths [dict get $stage1d_configuration {*}$key_path]
            assert_equal 1 [llength [lsearch -all -exact \
                $configured_paths $reset_source]] \
                "Stage 1D source authority must contain reset synchronizer once: $key_path"
            foreach source $stage2d_sources {
                assert_equal 1 [llength [lsearch -all -exact \
                    $configured_paths $source]] \
                    "Stage 1D source authority must contain $source once: $key_path"
            }
            foreach source $stage2f_sources {
                assert_equal 1 [llength [lsearch -all -exact \
                    $configured_paths $source]] \
                    "Stage 1D source authority must contain $source once: $key_path"
            }
        }
        set top_text [read_text [file normalize [file join \
            $repository_root rtl protection_ip_top_async_adc_axi_lite.v]]]
        assert_true [regexp \
            {\mreset_release_sync\M[ \t\r\n]+u_adc_source_reset_release_sync\M} \
            $top_text] \
            {Configured top no longer instantiates reset_release_sync}
        assert_true [regexp \
            {\madc_sample_code_normalizer\M[ \t\r\n]*#\([ \t\r\n]*\.RAW_WIDTH\(DATA_WIDTH\),[ \t\r\n]*\.SEQUENCE_WIDTH\(OBS_SEQUENCE_WIDTH\),[ \t\r\n]*\.NORMALIZED_WIDTH\(13\)[ \t\r\n]*\)[ \t\r\n]+u_adc_sample_code_normalizer\M} \
            $top_text] \
            {Configured top no longer explicitly binds adc_sample_code_normalizer widths}
        assert_true [expr {[string first {.raw_delivery_valid(dst_sample_valid)} \
            $top_text] >= 0}] \
            {Normalizer is no longer fed by the atomic raw delivery event}
        puts {CONTROLLED_BUILD_SOURCE_CLOSURE=PASS}
    }

    run_case PROFILE_CAPABILITY_MODEL_VALID {
        set model [dict get $profile capability_model]
        assert_equal stage1e-progressive-capability-model-v1 \
            [dict get $model schema_version] {Capability model schema}
        assert_equal DENY [dict get $model authorization_default] \
            {Capability default}
        assert_equal 0 [dict get $model declaration_is_permission] \
            {Capability declaration permission}
        assert_equal 1 [dict get $model grants_are_per_capability] \
            {Per-capability grants}
        assert_equal 1 [dict get $model progressive_enablement_supported] \
            {Progressive enablement support}
        assert_equal 1 [dict get $model cumulative_phase_model] \
            {Cumulative phase model}
        assert_equal PHASE2_SYNTHESIS [dict get $model active_phase] \
            {Capability-model active phase}
        assert_set_equal [expected_capabilities] \
            [dict get $model supported_capabilities] \
            {Supported capability inventory}
        assert_equal [lrange {
            PHASE1_RECONSTRUCTION
            PHASE2_SYNTHESIS
            PHASE3_IMPLEMENTATION
            PHASE4_ARTIFACT_CLOSURE
        } 0 end] \
            [lrange [dict get $model phase_order] 0 end] \
            {Capability phase order}
        assert_equal ACTIVE \
            [dict get $model phases PHASE2_SYNTHESIS activation_state] \
            {Active synthesis phase state}
        assert_equal DISABLED_PENDING_SEPARATE_AUTHORIZATION \
            [dict get $model phases PHASE3_IMPLEMENTATION activation_state] \
            {Future implementation phase state}
        assert_equal DISABLED_PENDING_SEPARATE_AUTHORIZATION \
            [dict get $model phases PHASE4_ARTIFACT_CLOSURE activation_state] \
            {Future artifact phase state}
    }

    run_case PROFILE_PHASE2_ENABLED {
        set model [dict get $profile capability_model]
        assert_equal ACTIVE_PREREQUISITE \
            [dict get $model phases PHASE1_RECONSTRUCTION activation_state] \
            {Phase 1 activation state}
        assert_set_equal [expected_phase1_enabled] \
            [dict get $model phases PHASE1_RECONSTRUCTION \
                enabled_capabilities] {Phase 1 enabled capabilities}
        foreach capability [expected_phase1_enabled] {
            assert_equal 1 \
                [dict get $model capabilities $capability profile_enabled] \
                "Phase 1 profile flag: $capability"
            assert_equal 1 [dict get $model capabilities $capability \
                explicit_execution_grant_required] \
                "Phase 1 authorization gate: $capability"
        }
        assert_set_equal [expected_phase2_enabled] \
            [dict get $model phases PHASE2_SYNTHESIS \
                enabled_capabilities] {Phase 2 enabled capabilities}
        assert_set_equal [expected_phase2_disabled] \
            [dict get $model phases PHASE2_SYNTHESIS \
                disabled_capabilities] {Phase 2 disabled capabilities}
    }

    run_case PROFILE_SYNTHESIS_ENABLED {
        set model [dict get $profile capability_model]
        assert_true [expr {{SYNTHESIS} in [dict get $model phases \
            PHASE2_SYNTHESIS enabled_capabilities]}] \
            {SYNTHESIS missing from Phase 2 enabled set}
        assert_equal 1 [dict get $model capabilities SYNTHESIS profile_enabled] \
            {SYNTHESIS profile flag}
        assert_equal 1 [dict get $profile profile_state \
            synthesis_execution_enabled] {Synthesis execution state}
        assert_equal 1 [dict get $profile build_policy synthesis \
            capability_enabled] {Synthesis build-policy capability}
        assert_equal REVIEWED_READY [dict get $profile build_policy \
            synthesis policy_status] {Synthesis readiness status}
        assert_equal {Vivado Synthesis Defaults} [dict get $profile \
            build_policy synthesis strategy] {Synthesis strategy}
        assert_equal Default [dict get $profile build_policy synthesis \
            directives STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE] \
            {Synthesis directive}
        assert_equal NOT_APPLICABLE [dict get $profile build_policy synthesis \
            seed_policy mode] {Synthesis seed policy}
        assert_equal LOCAL [dict get $profile build_policy synthesis \
            job_policy mode] {Synthesis job mode}
        assert_true [expr {[dict get $profile build_policy synthesis \
            job_policy jobs] > 0}] {Synthesis job count}
        set job_policy [dict get $profile build_policy synthesis job_policy]
        assert_equal 300 [dict get $job_policy dispatch_timeout_seconds] \
            {Synthesis dispatch timeout}
        assert_equal 1000 [dict get $job_policy \
            dispatch_poll_interval_milliseconds] \
            {Synthesis dispatch poll interval}
        assert_equal 60 [dict get $job_policy wait_timeout_minutes] \
            {Synthesis bounded wait timeout}
        assert_equal 45 [dict get $job_policy \
            pre_synthesis_budget_minutes] \
            {Synthesis pre-run launcher budget}
        assert_equal 10 [dict get $job_policy shutdown_grace_minutes] \
            {Synthesis launcher shutdown grace}
        set required_launcher_minutes [expr {
            [dict get $job_policy pre_synthesis_budget_minutes] +
            ([dict get $job_policy dispatch_timeout_seconds] + 59) / 60 +
            [dict get $job_policy wait_timeout_minutes] +
            [dict get $job_policy shutdown_grace_minutes]
        }]
        assert_true [expr {
            [dict get $job_policy launcher_timeout_minutes] >=
            $required_launcher_minutes
        }] {External launcher lifetime is shorter than controlled execution}
        assert_equal 0 [dict get $profile build_policy synthesis \
            incremental_synthesis_policy enabled] \
            {Incremental synthesis initial policy}
        assert_equal {} [dict get $profile build_policy synthesis \
            incremental_synthesis_policy checkpoint] \
            {Incremental synthesis checkpoint}
    }

    run_case PROFILE_SYNTHESIS_WARNING_POLICY_VALID {
        set policy [dict get $profile build_policy synthesis warning_policy]
        assert_equal stage1e-synthesis-warning-policy-v1 \
            [dict get $policy schema_version] {Warning policy schema}
        assert_equal stage1e_vivado_2024_1_retry19_warning_dispositions_v1 \
            [dict get $policy policy_id] {Warning policy identifier}
        assert_equal REVIEWED_ACCEPTED [dict get $policy policy_status] \
            {Warning policy review state}
        assert_equal REJECTED [dict get $policy unknown_disposition] \
            {Unknown warning disposition}
        assert_equal docs/status/stage1e_first_controlled_synthesis_execution_retry19.md \
            [dict get $policy review_evidence] {Warning review evidence}
        set review_evidence [dict get $policy review_evidence]
        assert_true [file isfile [file normalize [file join \
            $repository_root $review_evidence]]] \
            {Warning review evidence is unavailable}
        set phase2_configuration [read_dict [file normalize [file join \
            $repository_root fpga vivado build config \
            stage1e_phase2_synthesis_config_v1.dict]] \
            {Phase 2 synthesis configuration}]
        assert_true [expr {$review_evidence in [dict get \
            $phase2_configuration source_verification required_paths]}] \
            {Warning review evidence is absent from the source inventory}

        set expected_counts [dict create \
            {Synth 8-7071} 8 \
            {Synth 8-7023} 3 \
            {Synth 8-4446} 1 \
            {Synth 8-7129} 48 \
            {Synth 8-7080} 1]
        set dispositions [dict get $policy dispositions]
        assert_set_equal [dict keys $expected_counts] \
            [dict keys $dispositions] {Reviewed warning identifiers}
        dict for {identifier maximum_count} $expected_counts {
            set disposition [dict get $dispositions $identifier]
            assert_dict_keys $disposition {
                identifier classification acceptance_state severity
                observed_count min_count max_count rationale review_authority
                vivado_identity configuration_identity evidence_reference
            } "warning disposition $identifier"
            assert_equal $identifier [dict get $disposition identifier] \
                "Warning identifier binding: $identifier"
            assert_equal ACCEPTED [dict get $disposition classification] \
                "Warning classification: $identifier"
            assert_equal ACCEPTED [dict get $disposition acceptance_state] \
                "Warning acceptance state: $identifier"
            assert_equal WARNING [dict get $disposition severity] \
                "Warning severity: $identifier"
            assert_equal $maximum_count [dict get $disposition observed_count] \
                "Observed warning count: $identifier"
            assert_equal 1 [dict get $disposition min_count] \
                "Minimum warning count: $identifier"
            assert_equal $maximum_count [dict get $disposition max_count] \
                "Maximum accepted warning count: $identifier"
            assert_equal STAGE1E_SYNTHESIS_WARNING_REVIEW \
                [dict get $disposition review_authority] \
                "Warning review authority: $identifier"
            assert_true [expr {[string trim \
                [dict get $disposition rationale]] ne {}}] \
                "Warning rationale is empty: $identifier"
            assert_equal docs/status/stage1e_first_controlled_synthesis_execution_retry19.md \
                [dict get $disposition evidence_reference] \
                "Warning evidence reference: $identifier"
            assert_equal 2024.1 [dict get $disposition vivado_identity version] \
                "Warning Vivado version: $identifier"
            assert_equal 5076996 \
                [dict get $disposition vivado_identity sw_build] \
                "Warning Vivado software build: $identifier"
            assert_equal 5075265 \
                [dict get $disposition vivado_identity ip_build] \
                "Warning Vivado IP build: $identifier"
            assert_equal stage1e_reconstruction_profile_v1 \
                [dict get $disposition configuration_identity profile_id] \
                "Warning profile binding: $identifier"
            assert_equal PHASE2_SYNTHESIS \
                [dict get $disposition configuration_identity phase] \
                "Warning phase binding: $identifier"
            assert_equal stage1e-phase2-synthesis-config-v1 \
                [dict get $disposition configuration_identity \
                    configuration_schema] \
                "Warning configuration schema: $identifier"
        }
    }

    run_case PROFILE_IMPLEMENTATION_DISABLED {
        set model [dict get $profile capability_model]
        assert_true [expr {{IMPLEMENTATION} in [dict get $model phases \
            PHASE2_SYNTHESIS disabled_capabilities]}] \
            {IMPLEMENTATION missing from Phase 2 disabled set}
        assert_equal 0 [dict get $model capabilities IMPLEMENTATION \
            profile_enabled] {IMPLEMENTATION profile flag}
        assert_equal 0 [dict get $profile profile_state \
            implementation_execution_enabled] {Implementation execution state}
    }

    run_case PROFILE_ARTIFACT_DISABLED {
        set model [dict get $profile capability_model]
        foreach capability {ARTIFACT_COLLECTION ARTIFACT_PUBLICATION} {
            assert_true [expr {$capability in [dict get $model phases \
                PHASE2_SYNTHESIS disabled_capabilities]}] \
                "Artifact capability missing from disabled set: $capability"
            assert_equal 0 [dict get $model capabilities $capability \
                profile_enabled] "Artifact profile flag: $capability"
        }
        assert_equal 0 [dict get $profile profile_state \
            artifact_operations_enabled] {Artifact operations state}
        assert_equal 0 [dict get $profile profile_state board_access_enabled] \
            {Board access state}
    }

    run_case PROFILE_ADAPTER_INVENTORY_VALID {
        set inventory [dict get $profile adapter_inventory]
        set expectations [adapter_expectations]
        assert_equal stage1e-adapter-inventory-v1 \
            [dict get $inventory schema_version] {Adapter inventory schema}
        assert_equal SHA256 [dict get $inventory source_binding_policy \
            hash_algorithm] {Adapter hash algorithm}
        assert_equal 1 [dict get $inventory source_binding_policy \
            source_sha256_required] {Adapter source hash requirement}
        assert_equal EXECUTION_AUTHORIZATION \
            [dict get $inventory source_binding_policy binding_time] \
            {Adapter source binding time}
        assert_equal [dict keys $expectations] \
            [lrange [dict get $inventory operation_order] 0 end] \
            {Adapter operation order}
        assert_set_equal [dict keys $expectations] \
            [dict keys [dict get $inventory adapters]] \
            {Adapter inventory identities}

        dict for {adapter_id expected} $expectations {
            set adapter [dict get $inventory adapters $adapter_id]
            assert_dict_keys $adapter {
                work_package capability phase source_path interface
                implementation_command adapter_version context_schema_version
                result_schema_version produced_identity_schema_versions
            } "adapter $adapter_id"
            foreach field {work_package capability interface} {
                assert_equal [dict get $expected $field] \
                    [dict get $adapter $field] \
                    "Adapter $adapter_id field $field"
            }
            assert_equal v1 [dict get $adapter adapter_version] \
                "Adapter version: $adapter_id"
            foreach schema_field {context_schema_version result_schema_version} {
                assert_true [regexp -- {-v[0-9]+$} \
                    [dict get $adapter $schema_field]] \
                    "Adapter schema is not version-bound: $adapter_id/$schema_field"
            }
            assert_true [expr {[llength [dict get $adapter \
                produced_identity_schema_versions]] > 0}] \
                "Adapter identity schemas missing: $adapter_id"
            foreach identity_schema \
                [dict get $adapter produced_identity_schema_versions] {
                assert_true [regexp -- {-v[0-9]+$} $identity_schema] \
                    "Adapter identity is not version-bound: $adapter_id/$identity_schema"
            }

            set source_path [file normalize [file join $repository_root \
                [dict get $adapter source_path]]]
            assert_true [file isfile $source_path] \
                "Adapter source is unavailable: $adapter_id"
            set source_text [read_text $source_path]
            foreach binding [list \
                [dict get $adapter implementation_command] \
                [dict get $adapter context_schema_version] \
                [dict get $adapter result_schema_version] \
                {*}[dict get $adapter produced_identity_schema_versions]] {
                assert_true [expr {[string first $binding $source_text] >= 0}] \
                    "Adapter source does not contain bound identity: $adapter_id/$binding"
            }
        }
    }

    run_case PROFILE_AUTHORIZATION_REQUIRED {
        set policy [dict get $profile authorization_policy]
        assert_equal stage1e-capability-authorization-policy-v1 \
            [dict get $policy schema_version] {Authorization schema}
        assert_equal DENY [dict get $policy authorization_default] \
            {Authorization default}
        assert_equal 0 [dict get $policy profile_declaration_is_permission] \
            {Profile declaration permission}
        assert_equal controller_core [dict get $policy authorization_issuer] \
            {Authorization issuer}
        assert_equal EXPLICIT_PER_CAPABILITY \
            [dict get $policy capability_grant_mode] \
            {Capability authorization mode}
        assert_equal REQUIRED_EXACT \
            [dict get $policy execution_identity_match] \
            {Authorization execution binding}
        assert_equal 0 [dict get $policy wildcard_grants_allowed] \
            {Wildcard authorization policy}
        assert_equal 0 [dict get $policy adapter_self_authorization_allowed] \
            {Adapter self-authorization policy}
        assert_set_equal {
            status authority execution_id operation phase capability
            capability_enabled
        } [dict get $policy required_grant_fields] \
            {Authorization required fields}
        dict for {capability definition} \
            [dict get $profile capability_model capabilities] {
            assert_equal 1 [dict get $definition \
                explicit_execution_grant_required] \
                "Capability lacks explicit authorization: $capability"
        }
    }

    run_case PROFILE_NO_VIVADO_EXECUTION {
        assert_equal 0 [dict get $profile profile_state \
            vivado_execution_enabled_by_declaration] \
            {Profile declaration enabled Vivado}
        assert_equal 1 [dict get $profile profile_state \
            synthesis_execution_enabled] {Profile enabled synthesis}
        assert_equal 0 [dict get $profile profile_state \
            implementation_execution_enabled] {Profile enabled implementation}
        assert_equal 0 [dict get $profile profile_state \
            artifact_operations_enabled] {Profile enabled artifacts}
        assert_equal REVIEWED_ACCEPTED [dict get $profile constraint_policy \
            policy_status] {Constraint policy fail-closed state}
        assert_equal ACCEPTED_EMPTY_USER_XDC_INVENTORY [dict get $profile \
            constraint_policy xdc_inventory_reference \
            accepted_inventory_status] {Accepted XDC inventory state}
        assert_equal BLOCK [dict get $profile constraint_policy \
            unknown_constraint_state_action] {Unknown constraint action}
        assert_equal 0 [dict get $profile constraint_policy \
            build_pass_with_unknown_constraint_state] \
            {Unknown constraint PASS policy}
        foreach forbidden {
            launch_runs wait_on_run synth_design
            opt_design place_design route_design
            write_bitstream write_hw_platform write_xsa export_hardware
        } {
            set command_pattern [format {^[ \t]*%s([ \t]|$)} $forbidden]
            assert_true [expr {![regexp -line -- \
                $command_pattern $profile_text]}] \
                "Profile contains executable Vivado command: $forbidden"
        }
    }
}

set suite_status [catch {
    ::stage1e::reconstruction_profile_tests::load_inputs
    ::stage1e::reconstruction_profile_tests::run_all
} suite_error suite_options]

if {$suite_status != 0} {
    incr ::stage1e::reconstruction_profile_tests::fail_count
    puts stderr "TEST SUITE: FAIL: $suite_error"
    if {[dict exists $suite_options -errorinfo]} {
        puts stderr [dict get $suite_options -errorinfo]
    }
}

puts "SUMMARY PASS=$::stage1e::reconstruction_profile_tests::pass_count FAIL=$::stage1e::reconstruction_profile_tests::fail_count"
if {$::stage1e::reconstruction_profile_tests::fail_count != 0} {
    exit 1
}
