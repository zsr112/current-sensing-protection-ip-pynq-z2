namespace eval ::stage1d::controller_core {
    variable controller_version STAGE1D-BUILD-CTRL-v1.1
    variable controller_api_version STAGE1D-CONTROLLER-API-v1
    variable configuration_schema_version v1
    variable execution_id_schema_version v1
    variable phase_evidence_schema_version v1
    variable manifest_schema_version v1
    variable mutation_phase_sequence {BD_READY MUTATION_AUTHORIZED MUTATION_EXECUTE MUTATION_RESULT}
    variable preflight_result_fields {
        status
        phase
        execution_id
        source_identity
        environment_identity
        profile_identity
        workspace_identity
        errors
        warnings
        outputs
    }
    variable preflight_aggregate_fields {
        overall_status
        execution_id
        profile_identity
        source_identity
        environment_identity
        workspace_identity
        component_results
        errors
        warnings
    }
    variable preflight_statuses {PASS FAIL BLOCKED}
    variable dry_run_scope_fields {
        phase_limit
        project_operations
        design_operations
        mutation_operations
    }
    variable preflight_required_phases {
        PROFILE_SELECTION
        EFFECTIVE_SCOPE_VALIDATION
        SOURCE_VERIFICATION
        ENVIRONMENT_VERIFICATION
        WORKSPACE_VERIFICATION
        EXECUTION_CONTEXT_VERIFICATION
    }
    variable execution_context_fields {
        execution_id
        authorization
        workspace_root
        project_path
        bd_name
        evidence_dir
        bundle_identity
        source_identity
        environment_identity
    }
    variable execution_bundle_identity_fields {
        bundle_id
        manifest_sha256
        profile_sha256
        profile_id
        profile_version
    }
    variable authorization_assertion_fields {
        execution_id
        operation
        phase
        bd_name
        decision
    }
    variable authorization_evidence_context_fields {
        execution_id
        source_identity
        environment_identity
        bundle_identity
        profile_identity
        authorization_assertion
    }
    variable authorization_evidence_checks {
        AUTHORIZATION_EVIDENCE_CONTEXT_BOUND
        AUTHORIZATION_BUNDLE_IDENTITY_MATCH
        AUTHORIZATION_PROFILE_IDENTITY_MATCH
        AUTHORIZATION_SOURCE_IDENTITY_MATCH
        AUTHORIZATION_ENVIRONMENT_IDENTITY_MATCH
    }
    variable bundle_aware_preflight_phase BUNDLE_AWARE_PREFLIGHT
    variable bundle_aware_preflight_checks {
        EXECUTION_PROVENANCE_COMPLETE
        BUNDLE_PREFLIGHT_CONTEXT_VALID
        AUTHORIZATION_PREFLIGHT_CONTEXT_VALID
    }
    variable execution_provenance_fields {
        execution_id
        source_identity
        environment_identity
        workspace_identity
        bundle_identity
        profile_identity
        authorization_evidence_context
    }
    variable bundle_aware_preflight_result_fields {
        status
        phase
        execution_id
        provenance_context
        errors
        warnings
        outputs
    }
    variable mutation_context_fields {
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
        slice_ch1_name
        slice_ch2_name
        smartconnect_name
        stage1d_source_baseline
        vivado_version
        xlslice_vlnv
    }
    variable mutation_operational_context_fields {
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
        slice_ch1_name
        slice_ch2_name
        smartconnect_name
        stage1d_source_baseline
        vivado_version
        xlslice_vlnv
    }
    variable mutation_configuration_fields {
        axi_gpio_vlnv
        expected_protection_base
        expected_protection_range
        gpio_name
        gpio_width
        i_ch1_const_name
        i_ch2_const_name
        ila_name
        planned_gpio_base
        planned_gpio_range
        protection_name
        protection_vlnv
        ps_name
        reset_name
        safe_gpio_default
        sample_valid_const_name
        slice_ch1_name
        slice_ch2_name
        smartconnect_name
        stage1d_source_baseline
        xlslice_vlnv
    }
    variable approved_mutation_configuration {
        axi_gpio_vlnv xilinx.com:ip:axi_gpio:2.0
        expected_protection_base 0x43C00000
        expected_protection_range 0x00001000
        gpio_name axi_gpio_stage1d_0
        gpio_width 24
        i_ch1_const_name i_ch1_const
        i_ch2_const_name i_ch2_const
        ila_name system_ila_stage2b_0
        planned_gpio_base 0x41200000
        planned_gpio_range 0x00010000
        protection_name protection_ip_axi_lite_0
        protection_vlnv zsr112.local:protection:protection_ip_axi_lite:0.3
        ps_name processing_system7_0
        reset_name proc_sys_reset_0
        safe_gpio_default 0x00400400
        sample_valid_const_name sample_valid_const
        stimulus_profile SAFE_INERT_EXPLICIT
        source_acceptance_claimed 0
        fault_stimulus_claimed 0
        slice_ch1_name xlslice_stage1d_ch1
        slice_ch2_name xlslice_stage1d_ch2
        smartconnect_name smartconnect_0
        stage1d_source_baseline 2efeb7efaf5b97ca7850f61f1001224c00efd111
        xlslice_vlnv xilinx.com:ip:xlslice:1.0
    }
    variable mutation_result_fields {
        status
        phase
        execution_id
        vivado_invoked
        artifacts_generated
        errors
        warnings
        outputs
        mutation_summary
    }
    variable lifecycle_result_fields {
        status
        phase
        execution_id
        vivado_invoked
        artifacts_generated
        errors
        warnings
        evidence_locations
        logs
        reports
        outputs
        artifact_references
    }
    variable static_readiness_phase STATIC_READINESS
    variable static_readiness_statuses {PASS FAIL BLOCKED}
    variable static_readiness_result_fields {
        status
        phase
        execution_id
        component_results
        errors
        warnings
        outputs
    }
    variable static_readiness_component_fields {
        status
        result
        errors
        warnings
        outputs
    }
    variable static_readiness_required_results {
        PROFILE_STATIC_READY
        CONTROLLER_STATIC_READY
        LIFECYCLE_ADAPTER_STATIC_READY
        AUTHORIZATION_STATIC_READY
        MUTATION_BOUNDARY_STATIC_READY
        STATIC_SIDE_EFFECT_FREE
    }
    variable static_readiness_ordered_components {
        PROFILE_STATIC_READY
        CONTROLLER_STATIC_READY
        LIFECYCLE_ADAPTER_STATIC_READY
        AUTHORIZATION_STATIC_READY
        MUTATION_BOUNDARY_STATIC_READY
    }
    variable static_side_effect_fields {
        project_open_count
        bd_open_count
        mutation_invocation_count
        bd_validation_count
        bd_save_count
        artifact_generation_count
        vivado_invocation_count
    }
}

proc ::stage1d::controller_core::version {} {
    variable controller_version
    return $controller_version
}

proc ::stage1d::controller_core::api_version {} {
    variable controller_api_version
    return $controller_api_version
}

proc ::stage1d::controller_core::execution_id_schema_version {} {
    variable execution_id_schema_version
    return $execution_id_schema_version
}

proc ::stage1d::controller_core::phase_evidence_schema_version {} {
    variable phase_evidence_schema_version
    return $phase_evidence_schema_version
}

proc ::stage1d::controller_core::execution_context_contract {} {
    variable execution_context_fields
    variable execution_bundle_identity_fields
    return [dict create \
        schema_version v1 \
        fields $execution_context_fields \
        authorization_fields {status authority operation boundary} \
        bundle_identity_fields $execution_bundle_identity_fields]
}

proc ::stage1d::controller_core::authorization_assertion_schema {} {
    variable authorization_assertion_fields
    return [dict create \
        schema_version v1 \
        fields $authorization_assertion_fields \
        owner controller_core \
        validation_boundary \
            ::stage1d_controlled_stimulus::_validate_authorization_assertion]
}

proc ::stage1d::controller_core::authorization_evidence_context_contract {} {
    variable authorization_assertion_fields
    variable authorization_evidence_context_fields
    variable authorization_evidence_checks

    return [dict create \
        schema_version v1 \
        fields $authorization_evidence_context_fields \
        checks $authorization_evidence_checks \
        owner controller_core \
        authorization_assertion_fields $authorization_assertion_fields]
}

proc ::stage1d::controller_core::bundle_aware_preflight_contract {} {
    variable bundle_aware_preflight_checks
    variable bundle_aware_preflight_result_fields
    variable execution_provenance_fields

    return [dict create \
        schema_version v1 \
        result_fields $bundle_aware_preflight_result_fields \
        provenance_fields $execution_provenance_fields \
        checks $bundle_aware_preflight_checks \
        owner controller_core \
        authorization_assertion_generated 0]
}

proc ::stage1d::controller_core::mutation_interface_contract {} {
    variable mutation_context_fields
    variable mutation_result_fields
    return [dict create \
        procedure ::stage1d_controlled_stimulus::apply \
        arguments {context} \
        context_fields $mutation_context_fields \
        result_fields $mutation_result_fields]
}

proc ::stage1d::controller_core::supported_configuration_versions {} {
    variable controller_version
    variable controller_api_version
    variable configuration_schema_version
    variable execution_id_schema_version
    variable phase_evidence_schema_version
    variable manifest_schema_version

    return [dict create \
        schema_version $configuration_schema_version \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        execution_id_schema_version $execution_id_schema_version \
        phase_evidence_schema_version $phase_evidence_schema_version \
        decision_schema_version [::stage1d::decision_engine::schema_version] \
        manifest_schema_version $manifest_schema_version]
}

proc ::stage1d::controller_core::_validate_candidate_git_commit {candidate_git_commit} {
    if {![regexp {^[0-9A-Fa-f]{7,64}$} $candidate_git_commit]} {
        error {Candidate Git commit must contain 7 to 64 hexadecimal characters.}
    }
    return [string tolower $candidate_git_commit]
}

proc ::stage1d::controller_core::generate_execution_identity {candidate_git_commit {epoch_seconds {}}} {
    variable controller_version
    variable controller_api_version
    variable execution_id_schema_version

    set normalized_commit [_validate_candidate_git_commit $candidate_git_commit]
    if {$epoch_seconds eq {}} {
        set epoch_seconds [clock seconds]
    }
    if {![string is integer -strict $epoch_seconds]} {
        error {Execution identifier epoch must be an integer.}
    }

    set timestamp [clock format $epoch_seconds -gmt 1 -format {%Y%m%d-%H%M%S}]
    set generated_at [::stage1d::logger::utc_timestamp $epoch_seconds]
    set git_short [string range $normalized_commit 0 6]
    set execution_identifier "STAGE1D-$timestamp-$git_short"

    return [dict create \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        execution_id_schema_version $execution_id_schema_version \
        execution_identifier $execution_identifier \
        generated_at $generated_at \
        candidate_git_commit $normalized_commit \
        git_short $git_short]
}

proc ::stage1d::controller_core::_canonical_components {path} {
    set normalized_path [file normalize $path]
    set components [file split $normalized_path]
    if {$::tcl_platform(platform) eq {windows}} {
        set normalized_components {}
        foreach component $components {
            lappend normalized_components [string tolower $component]
        }
        return $normalized_components
    }
    return $components
}

proc ::stage1d::controller_core::_is_equal_or_descendant {candidate_path parent_path} {
    set candidate_components [_canonical_components $candidate_path]
    set parent_components [_canonical_components $parent_path]

    if {[llength $candidate_components] < [llength $parent_components]} {
        return 0
    }
    for {set index 0} {$index < [llength $parent_components]} {incr index} {
        if {[lindex $candidate_components $index] ne [lindex $parent_components $index]} {
            return 0
        }
    }
    return 1
}

proc ::stage1d::controller_core::_paths_overlap {first_path second_path} {
    if {[_is_equal_or_descendant $first_path $second_path]} {
        return 1
    }
    return [_is_equal_or_descendant $second_path $first_path]
}

proc ::stage1d::controller_core::_assert_execution_identifier_available {
    execution_identifier
    build_workspace_root
    artifact_storage_root
} {
    set execution_workspace [file normalize [file join $build_workspace_root $execution_identifier]]
    set artifact_group [file normalize [file join $artifact_storage_root $execution_identifier]]

    if {[file exists $execution_workspace]} {
        error "Execution identifier collision in build workspace: $execution_identifier"
    }
    if {[file exists $artifact_group]} {
        error "Execution identifier collision in artifact storage: $execution_identifier"
    }

    return [dict create \
        execution_workspace $execution_workspace \
        candidate_artifact_directory [file join $execution_workspace candidate_artifacts] \
        artifact_group $artifact_group]
}

proc ::stage1d::controller_core::_validate_configuration_identity {configuration} {
    ::stage1d::configuration_loader::validate_supported_versions \
        $configuration \
        [supported_configuration_versions]
    _validate_lifecycle_target_configuration $configuration
    _validated_mutation_configuration $configuration
}

proc ::stage1d::controller_core::_validated_mutation_configuration {
    configuration
} {
    variable approved_mutation_configuration
    variable mutation_configuration_fields

    if {[catch {dict size $configuration} configuration_error]} {
        error "Mutation configuration input is not a dictionary: $configuration_error"
    }
    if {![dict exists $configuration mutation_context]} {
        error {Configuration is missing the declarative mutation_context section.}
    }
    set mutation_configuration [dict get $configuration mutation_context]
    if {[catch {dict size $mutation_configuration} mutation_error]} {
        error "Configuration mutation_context is not a dictionary: $mutation_error"
    }
    if {[lsort [dict keys $mutation_configuration]] ne \
        [lsort $mutation_configuration_fields]} {
        error {Configuration mutation_context does not contain the exact approved fields.}
    }

    foreach field $mutation_configuration_fields {
        set value [dict get $mutation_configuration $field]
        if {[string trim $value] eq {}} {
            error "Configuration mutation_context field must not be empty: $field"
        }
        set approved_value [dict get $approved_mutation_configuration $field]
        if {$value ne $approved_value} {
            error "Configuration mutation_context field differs from the approved Stage 1D value: $field"
        }
    }
    if {![regexp {^[0-9a-f]{40}$} [dict get \
        $mutation_configuration stage1d_source_baseline]]} {
        error {Configured Stage 1D source baseline must be a full lowercase Git revision.}
    }
    return $mutation_configuration
}

proc ::stage1d::controller_core::_validate_lifecycle_target_configuration {configuration} {
    foreach required_key {project_relative_path bd_name} {
        if {![dict exists $configuration lifecycle $required_key]} {
            error "Configuration lifecycle section is missing key: $required_key"
        }
    }

    set project_relative_path [dict get \
        $configuration lifecycle project_relative_path]
    if {[string trim $project_relative_path] eq {}} {
        error {Configured lifecycle project_relative_path must not be empty.}
    }
    if {[file pathtype $project_relative_path] ne {relative}} {
        error {Configured lifecycle project_relative_path must be relative to workspace_root.}
    }
    if {![string equal -nocase [file extension $project_relative_path] {.xpr}]} {
        error {Configured lifecycle project_relative_path must identify a .xpr file.}
    }

    set bd_name [dict get $configuration lifecycle bd_name]
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $bd_name]} {
        error "Configured lifecycle bd_name is invalid: $bd_name"
    }
    return 1
}

proc ::stage1d::controller_core::_lifecycle_phase_index {phase_name} {
    set ordered_phases {
        INIT
        INPUT_VALIDATION
        SOURCE_VERIFIED
        ENVIRONMENT_VERIFIED
        WORKSPACE_READY
        PROJECT_READY
        BD_READY
        DESIGN_VALIDATED
        WRAPPER_READY
        SYNTH_DONE
        IMPL_DONE
        ARTIFACT_READY
        MANIFEST_READY
        PASS
    }
    set phase_index [lsearch -exact $ordered_phases $phase_name]
    if {$phase_index < 0} {
        error "Unsupported lifecycle phase limit or required state: $phase_name"
    }
    return $phase_index
}

proc ::stage1d::controller_core::_lifecycle_operation_scope {operation} {
    switch -- $operation {
        vivado_project_open {
            return [dict create \
                scope_key project_operations \
                required_state PROJECT_READY]
        }
        bd_flow_open {
            return [dict create \
                scope_key design_operations \
                required_state BD_READY]
        }
        bd_flow_validate -
        bd_flow_save {
            return [dict create \
                scope_key design_operations \
                required_state DESIGN_VALIDATED]
        }
        default {
            error "Unsupported lifecycle operation: $operation"
        }
    }
}

proc ::stage1d::controller_core::_lifecycle_scope_decision {configuration operation} {
    set operation_scope [_lifecycle_operation_scope $operation]
    set scope_key [dict get $operation_scope scope_key]
    set required_state [dict get $operation_scope required_state]

    if {![dict exists $configuration phase_limit]} {
        error {Configuration is missing lifecycle phase_limit.}
    }
    if {![dict exists $configuration phase_scope $scope_key]} {
        error "Configuration phase_scope is missing lifecycle key: $scope_key"
    }

    set phase_limit [dict get $configuration phase_limit]
    set scope_enabled [dict get $configuration phase_scope $scope_key]
    if {![string is boolean -strict $scope_enabled]} {
        error "Configuration lifecycle scope must be boolean: $scope_key=$scope_enabled"
    }
    set scope_enabled [expr {$scope_enabled ? 1 : 0}]
    set phase_limit_allows [expr {
        [_lifecycle_phase_index $phase_limit] >=
        [_lifecycle_phase_index $required_state]
    }]

    return [dict create \
        allowed [expr {$scope_enabled && $phase_limit_allows}] \
        operation $operation \
        scope_key $scope_key \
        scope_enabled $scope_enabled \
        phase_limit $phase_limit \
        required_state $required_state \
        phase_limit_allows $phase_limit_allows]
}

proc ::stage1d::controller_core::_lifecycle_scope_blocked_result {scope_decision} {
    set operation [dict get $scope_decision operation]
    set blocked_reasons {}
    if {![dict get $scope_decision scope_enabled]} {
        lappend blocked_reasons \
            "[dict get $scope_decision scope_key] is disabled"
    }
    if {![dict get $scope_decision phase_limit_allows]} {
        lappend blocked_reasons \
            "phase_limit [dict get $scope_decision phase_limit] does not authorize [dict get $scope_decision required_state]"
    }

    set boundary_error [dict create \
        error_code LIFECYCLE_SCOPE_BLOCKED \
        category SCOPE \
        phase_name $operation \
        message "Lifecycle operation is not authorized: [join $blocked_reasons {; }]" \
        underlying_error {} \
        evidence_references {} \
        recoverability UPDATE_LIFECYCLE_SCOPE]

    return [dict create \
        status BLOCKED \
        evidence_locations {} \
        logs {} \
        reports {} \
        errors [list $boundary_error] \
        outputs [dict create \
            lifecycle_authorized 0 \
            scope_decision $scope_decision \
            vivado_invoked 0 \
            artifacts_generated 0] \
        artifact_references {}]
}

proc ::stage1d::controller_core::create_lifecycle_context {context operation} {
    set execution_identity [dict get $context execution_identity]
    set configuration [dict get $context configuration]
    set source_outputs [dict get $context source_verification]
    set environment_outputs [dict get $context environment_verification]
    set workspace_outputs [dict get $context workspace_preparation]
    set scope_decision [_lifecycle_scope_decision $configuration $operation]
    if {![dict get $scope_decision allowed]} {
        error "Cannot create authorized context for blocked lifecycle operation: $operation"
    }

    set execution_id [dict get $execution_identity execution_identifier]
    set execution_workspace [file normalize \
        [dict get $workspace_outputs execution_workspace]]
    set project_path [file normalize [file join $execution_workspace \
        [dict get $configuration lifecycle project_relative_path]]]
    if {![_is_equal_or_descendant $project_path $execution_workspace]} {
        error {Configured lifecycle project_path escapes workspace_root.}
    }
    set evidence_directory [file normalize \
        [file join $execution_workspace execution_state]]

    set lifecycle_context [dict create \
        execution_id $execution_id \
        authorization [dict create \
            status AUTHORIZED \
            authority controller_core \
            operation $operation \
            phase_limit [dict get $scope_decision phase_limit] \
            scope_key [dict get $scope_decision scope_key] \
            mutation_authorized 0] \
        workspace_root $execution_workspace \
        project_path $project_path \
        bd_name [dict get $configuration lifecycle bd_name] \
        evidence_dir $evidence_directory \
        source_identity $source_outputs \
        environment_identity $environment_outputs]

    if {$operation eq {bd_flow_open}} {
        if {![dict exists \
            $context project_lifecycle_context project_ownership]} {
            error {BD open requires explicit vivado_project ownership context.}
        }
        dict set lifecycle_context project_ownership [dict get \
            $context project_lifecycle_context project_ownership]
    } elseif {$operation in {bd_flow_validate bd_flow_save}} {
        foreach ownership_key {project_ownership bd_ownership} {
            if {![dict exists \
                $context bd_lifecycle_context $ownership_key]} {
                error "BD lifecycle operation requires explicit ownership context: $ownership_key"
            }
            dict set lifecycle_context $ownership_key [dict get \
                $context bd_lifecycle_context $ownership_key]
        }
    }

    return $lifecycle_context
}

proc ::stage1d::controller_core::phase_vivado_project_open {context} {
    set operation vivado_project_open
    set scope_decision [_lifecycle_scope_decision \
        [dict get $context configuration] $operation]
    if {![dict get $scope_decision allowed]} {
        return [_lifecycle_scope_blocked_result $scope_decision]
    }
    set lifecycle_context [create_lifecycle_context $context $operation]
    return [::stage1d::vivado_project::open $lifecycle_context]
}

proc ::stage1d::controller_core::phase_bd_flow_open {context} {
    set operation bd_flow_open
    set scope_decision [_lifecycle_scope_decision \
        [dict get $context configuration] $operation]
    if {![dict get $scope_decision allowed]} {
        return [_lifecycle_scope_blocked_result $scope_decision]
    }
    set lifecycle_context [create_lifecycle_context $context $operation]
    return [::stage1d::bd_flow::open $lifecycle_context]
}

proc ::stage1d::controller_core::_lifecycle_prerequisite_blocked_result {
    operation
    message
} {
    set boundary_error [dict create \
        error_code LIFECYCLE_PREREQUISITE_BLOCKED \
        category LIFECYCLE \
        phase_name $operation \
        message $message \
        underlying_error {} \
        evidence_references {} \
        recoverability COMPLETE_PRECEDING_PHASE]
    return [dict create \
        status BLOCKED \
        evidence_locations {} \
        logs {} \
        reports {} \
        errors [list $boundary_error] \
        outputs [dict create \
            lifecycle_authorized 0 \
            operation $operation \
            vivado_invoked 0 \
            artifacts_generated 0] \
        artifact_references {}]
}

proc ::stage1d::controller_core::phase_bd_flow_validate {context} {
    set operation bd_flow_validate
    set scope_decision [_lifecycle_scope_decision \
        [dict get $context configuration] $operation]
    if {![dict get $scope_decision allowed]} {
        return [_lifecycle_scope_blocked_result $scope_decision]
    }
    if {![dict exists $context controller_state] ||
        [dict get $context controller_state] ne {BD_READY}} {
        return [_lifecycle_prerequisite_blocked_result $operation \
            {BD validation requires controller state BD_READY.}]
    }
    if {![dict exists $context mutation_result status] ||
        [dict get $context mutation_result status] ne {PASS}} {
        return [_lifecycle_prerequisite_blocked_result $operation \
            {BD validation requires an accepted mutation PASS result.}]
    }
    set lifecycle_context [create_lifecycle_context $context $operation]
    return [::stage1d::bd_flow::validate $lifecycle_context]
}

proc ::stage1d::controller_core::phase_bd_flow_save {context} {
    set operation bd_flow_save
    set scope_decision [_lifecycle_scope_decision \
        [dict get $context configuration] $operation]
    if {![dict get $scope_decision allowed]} {
        return [_lifecycle_scope_blocked_result $scope_decision]
    }
    if {![dict exists $context controller_state] ||
        [dict get $context controller_state] ne {DESIGN_VALIDATED}} {
        return [_lifecycle_prerequisite_blocked_result $operation \
            {BD save requires controller state DESIGN_VALIDATED.}]
    }
    if {![dict exists $context bd_validation_result status] ||
        [dict get $context bd_validation_result status] ne {PASS}} {
        return [_lifecycle_prerequisite_blocked_result $operation \
            {BD save requires an accepted BD validation PASS result.}]
    }
    set lifecycle_context [create_lifecycle_context $context $operation]
    return [::stage1d::bd_flow::save $lifecycle_context]
}

proc ::stage1d::controller_core::_mutation_phase_sequence {} {
    variable mutation_phase_sequence
    return $mutation_phase_sequence
}

proc ::stage1d::controller_core::_mutation_error_record {
    error_code
    category
    message
    underlying_error
    recoverability
} {
    return [dict create \
        error_code $error_code \
        category $category \
        phase_name stage1d_mutation \
        message $message \
        underlying_error $underlying_error \
        evidence_references {} \
        recoverability $recoverability]
}

proc ::stage1d::controller_core::_mutation_assertion_allows {
    authorization_assertion
} {
    variable authorization_assertion_fields

    if {[catch {dict size $authorization_assertion}]} {
        return 0
    }
    set required_keys [lsort $authorization_assertion_fields]
    if {[lsort [dict keys $authorization_assertion]] ne $required_keys} {
        return 0
    }
    return [expr {
        [string trim [dict get $authorization_assertion execution_id]] ne {} &&
        [dict get $authorization_assertion operation] eq
            {stage1d_controlled_stimulus} &&
        [dict get $authorization_assertion phase] eq {MUTATION_EXECUTE} &&
        [string trim [dict get $authorization_assertion bd_name]] ne {} &&
        [dict get $authorization_assertion decision] eq {ALLOW}
    }]
}

proc ::stage1d::controller_core::_authorization_evidence_check_state {} {
    variable authorization_evidence_checks

    set checks [dict create]
    foreach check_name $authorization_evidence_checks {
        dict set checks $check_name 0
    }
    return $checks
}

proc ::stage1d::controller_core::_authorization_evidence_binding_error {
    check_name
    message
} {
    return [_mutation_error_record \
        $check_name \
        AUTHORIZATION \
        $message \
        {} \
        REPEAT_PREFLIGHT]
}

proc ::stage1d::controller_core::_evaluate_authorization_evidence_binding {
    context
} {
    variable execution_context_fields

    set checks [_authorization_evidence_check_state]
    set errors {}
    set accepted_execution_context {}
    set selected_profile_identity {}
    set profile_result {}
    set current_execution_id {}

    if {[catch {dict size $context} context_error]} {
        lappend errors [_authorization_evidence_binding_error \
            AUTHORIZATION_EVIDENCE_CONTEXT_BOUND \
            "Authorization input context is invalid: $context_error"]
        return [dict create \
            status BLOCKED \
            execution_id {} \
            accepted_execution_context {} \
            selected_profile_identity {} \
            profile_result {} \
            checks $checks \
            errors $errors]
    }
    if {[dict exists $context execution_identity execution_identifier]} {
        set current_execution_id [dict get \
            $context execution_identity execution_identifier]
    }

    set baseline_status [catch {
        if {[string trim $current_execution_id] eq {}} {
            error {Current controller execution_id is missing.}
        }
        if {![dict exists $context preflight_result]} {
            error {Accepted preflight result is missing from controller context.}
        }
        set preflight_result [dict get $context preflight_result]
        validate_preflight_aggregate $preflight_result $current_execution_id
        if {[dict get $preflight_result overall_status] ne {PASS}} {
            error {Authorization requires an accepted PASS preflight result.}
        }

        set profile_result [_static_preflight_component \
            $preflight_result PROFILE_SELECTION]
        set execution_context_result [_static_preflight_component \
            $preflight_result EXECUTION_CONTEXT_VERIFICATION]
        if {[dict get $profile_result status] ne {PASS} ||
            [dict get $execution_context_result status] ne {PASS} ||
            ![dict exists $execution_context_result outputs \
                EXECUTION_CONTEXT_VALID] ||
            ![dict get $execution_context_result outputs \
                EXECUTION_CONTEXT_VALID] ||
            ![dict exists $execution_context_result outputs \
                execution_context]} {
            error {Accepted preflight execution context is unavailable.}
        }
        foreach binding_check {
            BUNDLE_IDENTITY_CONTEXT_BOUND
            BUNDLE_EVIDENCE_EXECUTION_MATCH
            BUNDLE_PROFILE_SCOPE_CONTEXT_MATCH
        } {
            if {![dict exists $execution_context_result outputs \
                $binding_check] ||
                ![dict get $execution_context_result outputs \
                    $binding_check]} {
                error "Preflight execution context binding is not accepted: $binding_check"
            }
        }

        set accepted_execution_context [dict get \
            $execution_context_result outputs execution_context]
        if {[catch {dict size $accepted_execution_context}]} {
            error {Accepted execution context is not a dictionary.}
        }
        if {[lsort [dict keys $accepted_execution_context]] ne
            [lsort $execution_context_fields]} {
            error {Accepted execution context does not match its contract.}
        }
        if {[dict get $accepted_execution_context execution_id] ne
            $current_execution_id} {
            error {Accepted execution context belongs to another execution.}
        }
        if {![dict exists $context configuration lifecycle bd_name] ||
            [dict get $context configuration lifecycle bd_name] ne
                [dict get $accepted_execution_context bd_name]} {
            error {Current BD identity does not match the accepted execution context.}
        }

        set selected_profile_identity [dict get \
            $preflight_result profile_identity]
        if {[dict size $selected_profile_identity] == 0} {
            error {Accepted selected profile identity is missing.}
        }
    } baseline_error baseline_options]
    if {$baseline_status != 0} {
        lappend errors [_authorization_evidence_binding_error \
            AUTHORIZATION_EVIDENCE_CONTEXT_BOUND \
            "Authorization evidence context is not available: $baseline_error"]
        return [dict create \
            status BLOCKED \
            execution_id $current_execution_id \
            accepted_execution_context {} \
            selected_profile_identity {} \
            profile_result {} \
            checks $checks \
            errors $errors]
    }

    set bundle_matches 1
    set accepted_bundle_identity [dict get \
        $accepted_execution_context bundle_identity]
    set bundle_selection_explicit [expr {
        [dict exists $profile_result outputs BUNDLE_SELECTION_EXPLICIT] &&
        [dict get $profile_result outputs BUNDLE_SELECTION_EXPLICIT]
    }]
    if {[dict size $accepted_bundle_identity] == 0} {
        if {$bundle_selection_explicit ||
            ([dict exists $context delivery_bundle_loading] &&
                [dict size [dict get \
                    $context delivery_bundle_loading]] > 0)} {
            set bundle_matches 0
        }
    } elseif {!$bundle_selection_explicit ||
        ![dict exists $profile_result outputs bundle_loader_result]} {
        set bundle_matches 0
    } else {
        set loader_result [dict get \
            $profile_result outputs bundle_loader_result]
        if {[catch {
            set projected_bundle_identity \
                [_execution_bundle_identity_from_loader_result \
                    $loader_result]
        }] || $projected_bundle_identity ne $accepted_bundle_identity ||
            ![dict exists $context delivery_bundle_loading] ||
            [dict get $context delivery_bundle_loading] ne $loader_result} {
            set bundle_matches 0
        }
    }
    dict set checks AUTHORIZATION_BUNDLE_IDENTITY_MATCH $bundle_matches

    set profile_matches [expr {
        [dict get $profile_result profile_identity] eq
            $selected_profile_identity
    }]
    dict set checks AUTHORIZATION_PROFILE_IDENTITY_MATCH $profile_matches

    set accepted_source_identity [dict get \
        $accepted_execution_context source_identity]
    set source_matches [expr {
        $accepted_source_identity eq
            [dict get $preflight_result source_identity] &&
        [dict exists $context source_verification] &&
        [dict get $context source_verification] eq
            $accepted_source_identity
    }]
    dict set checks AUTHORIZATION_SOURCE_IDENTITY_MATCH $source_matches

    set accepted_environment_identity [dict get \
        $accepted_execution_context environment_identity]
    set environment_matches [expr {
        $accepted_environment_identity eq
            [dict get $preflight_result environment_identity] &&
        [dict exists $context environment_verification] &&
        [dict get $context environment_verification] eq
            $accepted_environment_identity
    }]
    dict set checks AUTHORIZATION_ENVIRONMENT_IDENTITY_MATCH \
        $environment_matches

    set all_identities_match [expr {
        $bundle_matches &&
        $profile_matches &&
        $source_matches &&
        $environment_matches
    }]
    dict set checks AUTHORIZATION_EVIDENCE_CONTEXT_BOUND \
        $all_identities_match

    foreach specification {
        {AUTHORIZATION_EVIDENCE_CONTEXT_BOUND
            {Authorization evidence is not bound to the current validated execution context.}}
        {AUTHORIZATION_BUNDLE_IDENTITY_MATCH
            {Authorization bundle identity does not match the validated loader result.}}
        {AUTHORIZATION_PROFILE_IDENTITY_MATCH
            {Authorization profile identity does not match the selected profile.}}
        {AUTHORIZATION_SOURCE_IDENTITY_MATCH
            {Authorization source identity does not match accepted source evidence.}}
        {AUTHORIZATION_ENVIRONMENT_IDENTITY_MATCH
            {Authorization environment identity does not match accepted environment evidence.}}
    } {
        lassign $specification check_name message
        if {![dict get $checks $check_name]} {
            lappend errors [_authorization_evidence_binding_error \
                $check_name $message]
        }
    }

    return [dict create \
        status [expr {$all_identities_match ? {PASS} : {BLOCKED}}] \
        execution_id $current_execution_id \
        accepted_execution_context $accepted_execution_context \
        selected_profile_identity $selected_profile_identity \
        profile_result $profile_result \
        checks $checks \
        errors $errors]
}

proc ::stage1d::controller_core::_bundle_aware_preflight_check_state {} {
    variable bundle_aware_preflight_checks

    set checks [dict create]
    foreach check_name $bundle_aware_preflight_checks {
        dict set checks $check_name 0
    }
    return $checks
}

proc ::stage1d::controller_core::_bundle_aware_preflight_error {
    check_name
    message
} {
    variable bundle_aware_preflight_phase

    return [dict create \
        error_code $check_name \
        category PROVENANCE \
        phase_name $bundle_aware_preflight_phase \
        message $message \
        underlying_error {} \
        evidence_references {} \
        recoverability REPEAT_PREFLIGHT]
}

proc ::stage1d::controller_core::_bundle_aware_preflight_result {
    status
    execution_id
    provenance_context
    checks
    errors
} {
    variable bundle_aware_preflight_checks
    variable bundle_aware_preflight_phase
    variable bundle_aware_preflight_result_fields

    if {$status ni {PASS BLOCKED}} {
        error "Unsupported bundle-aware preflight status: $status"
    }
    if {[catch {dict size $provenance_context} provenance_error]} {
        error "Execution provenance context is invalid: $provenance_error"
    }
    if {[catch {dict size $checks} checks_error] ||
        [lrange [dict keys $checks] 0 end] ne
            [lrange $bundle_aware_preflight_checks 0 end]} {
        error "Bundle-aware preflight checks are invalid: $checks_error"
    }
    foreach check_name $bundle_aware_preflight_checks {
        if {![string is boolean -strict [dict get $checks $check_name]]} {
            error "Bundle-aware preflight check is not boolean: $check_name"
        }
    }
    if {[catch {llength $errors} errors_error]} {
        error "Bundle-aware preflight errors are invalid: $errors_error"
    }

    set continuation_allowed [expr {$status eq {PASS}}]
    set result [dict create \
        status $status \
        phase $bundle_aware_preflight_phase \
        execution_id $execution_id \
        provenance_context $provenance_context \
        errors $errors \
        warnings {} \
        outputs [dict merge $checks [dict create \
            continuation_allowed $continuation_allowed]]]
    if {[lrange [dict keys $result] 0 end] ne
        [lrange $bundle_aware_preflight_result_fields 0 end]} {
        error {Bundle-aware preflight result does not match its contract.}
    }
    return $result
}

# This is the final controller-owned provenance gate before controlled
# execution continuation. It validates an assertion that already exists; it
# neither creates an assertion nor invokes any lifecycle or mutation procedure.
proc ::stage1d::controller_core::verify_bundle_aware_preflight {
    context
    authorization_evidence_context
} {
    variable authorization_evidence_context_fields
    variable bundle_aware_preflight_checks
    variable execution_context_fields
    variable execution_provenance_fields

    set checks [_bundle_aware_preflight_check_state]
    set provenance_context {}
    set current_execution_id {}
    set verification_detail {}

    set verification_status [catch {
        if {[catch {dict size $context} context_error]} {
            error "Controller execution context is invalid: $context_error"
        }
        if {![dict exists $context execution_identity execution_identifier]} {
            error {Current controller execution_id is missing.}
        }
        set current_execution_id [dict get \
            $context execution_identity execution_identifier]
        if {[string trim $current_execution_id] eq {}} {
            error {Current controller execution_id is empty.}
        }

        set binding_evaluation \
            [_evaluate_authorization_evidence_binding $context]
        if {[dict get $binding_evaluation status] ne {PASS}} {
            error {The validated execution context is not accepted.}
        }
        set accepted_execution_context [dict get \
            $binding_evaluation accepted_execution_context]
        if {[lsort [dict keys $accepted_execution_context]] ne
            [lsort $execution_context_fields]} {
            error {The accepted execution context does not match its contract.}
        }

        set preflight_result [dict get $context preflight_result]
        validate_preflight_aggregate $preflight_result $current_execution_id
        if {[dict get $preflight_result overall_status] ne {PASS}} {
            error {Bundle-aware verification requires PASS preflight evidence.}
        }
        set profile_result [dict get $binding_evaluation profile_result]
        set selected_profile_identity [dict get \
            $preflight_result profile_identity]
        set source_identity [dict get $preflight_result source_identity]
        set environment_identity [dict get \
            $preflight_result environment_identity]
        set workspace_identity [dict get \
            $preflight_result workspace_identity]
        set bundle_identity [dict get \
            $accepted_execution_context bundle_identity]

        set provenance_context [dict create \
            execution_id $current_execution_id \
            source_identity $source_identity \
            environment_identity $environment_identity \
            workspace_identity $workspace_identity \
            bundle_identity $bundle_identity \
            profile_identity $selected_profile_identity \
            authorization_evidence_context \
                $authorization_evidence_context]

        set evidence_schema_valid [expr {
            ![catch {dict size $authorization_evidence_context}] &&
            [lsort [dict keys $authorization_evidence_context]] eq
                [lsort $authorization_evidence_context_fields]
        }]
        set assertion_schema_valid 0
        set authorization_assertion {}
        if {$evidence_schema_valid} {
            set authorization_assertion [dict get \
                $authorization_evidence_context authorization_assertion]
            set assertion_schema_valid \
                [_mutation_assertion_allows $authorization_assertion]
        }

        set source_execution_match [expr {
            [dict exists $source_identity \
                execution_identity_evidence execution_identifier] &&
            [dict get $source_identity \
                execution_identity_evidence execution_identifier] eq
                $current_execution_id
        }]
        set workspace_execution_match [expr {
            [dict exists $workspace_identity execution_identifier] &&
            [dict get $workspace_identity execution_identifier] eq
                $current_execution_id
        }]
        set profile_execution_match [expr {
            [dict exists $selected_profile_identity \
                provenance execution_id] &&
            [dict get $selected_profile_identity \
                provenance execution_id] eq $current_execution_id
        }]
        set workspace_source_match [expr {
            [dict exists $source_identity git_commit] &&
            [dict exists $workspace_identity git_commit] &&
            [dict get $source_identity git_commit] eq
                [dict get $workspace_identity git_commit]
        }]
        set workspace_environment_match [expr {
            [dict exists $environment_identity \
                environment_evidence_hash] &&
            [dict exists $workspace_identity \
                environment_evidence_hash] &&
            [dict get $environment_identity environment_evidence_hash] eq
                [dict get $workspace_identity environment_evidence_hash]
        }]
        set current_identity_match [expr {
            [dict get $accepted_execution_context execution_id] eq
                $current_execution_id &&
            [dict get $accepted_execution_context source_identity] eq
                $source_identity &&
            [dict get $accepted_execution_context environment_identity] eq
                $environment_identity &&
            [dict exists $context source_verification] &&
            [dict get $context source_verification] eq $source_identity &&
            [dict exists $context environment_verification] &&
            [dict get $context environment_verification] eq
                $environment_identity &&
            [dict get $profile_result profile_identity] eq
                $selected_profile_identity
        }]

        # The authorization binding evaluator consumes the accepted execution
        # context and the retained loader result. The execution-context markers
        # it requires also prove the selected profile and scope projections.
        set bundle_context_valid [expr {
            [dict get $binding_evaluation checks \
                AUTHORIZATION_BUNDLE_IDENTITY_MATCH] &&
            [dict get $binding_evaluation checks \
                AUTHORIZATION_PROFILE_IDENTITY_MATCH]
        }]
        dict set checks BUNDLE_PREFLIGHT_CONTEXT_VALID \
            $bundle_context_valid

        set authorization_context_valid 0
        if {$evidence_schema_valid} {
            set authorization_context_valid [expr {
                [dict get $authorization_evidence_context execution_id] eq
                    $current_execution_id &&
                [dict get $authorization_evidence_context \
                    source_identity] eq $source_identity &&
                [dict get $authorization_evidence_context \
                    environment_identity] eq $environment_identity &&
                [dict get $authorization_evidence_context \
                    bundle_identity] eq $bundle_identity &&
                [dict get $authorization_evidence_context \
                    profile_identity] eq $selected_profile_identity &&
                $assertion_schema_valid &&
                [dict get $authorization_assertion execution_id] eq
                    $current_execution_id &&
                [dict get $authorization_assertion bd_name] eq
                    [dict get $accepted_execution_context bd_name]
            }]
        }
        dict set checks AUTHORIZATION_PREFLIGHT_CONTEXT_VALID \
            $authorization_context_valid

        set provenance_fields_complete [expr {
            [lrange [dict keys $provenance_context] 0 end] eq
                [lrange $execution_provenance_fields 0 end] &&
            [dict size $source_identity] > 0 &&
            [dict size $environment_identity] > 0 &&
            [dict size $workspace_identity] > 0 &&
            [dict size $selected_profile_identity] > 0 &&
            $evidence_schema_valid
        }]
        set execution_provenance_complete [expr {
            $provenance_fields_complete &&
            $source_execution_match &&
            $workspace_execution_match &&
            $profile_execution_match &&
            $workspace_source_match &&
            $workspace_environment_match &&
            $current_identity_match &&
            $bundle_context_valid &&
            $authorization_context_valid
        }]
        dict set checks EXECUTION_PROVENANCE_COMPLETE \
            $execution_provenance_complete
    } verification_detail]

    set errors {}
    foreach specification {
        {EXECUTION_PROVENANCE_COMPLETE
            {Execution provenance is incomplete or belongs to different executions.}}
        {BUNDLE_PREFLIGHT_CONTEXT_VALID
            {Preflight bundle or profile identity does not match validated selection evidence.}}
        {AUTHORIZATION_PREFLIGHT_CONTEXT_VALID
            {Authorization evidence does not match the current validated execution context.}}
    } {
        lassign $specification check_name message
        if {![dict get $checks $check_name]} {
            if {$verification_status != 0 &&
                $check_name eq {EXECUTION_PROVENANCE_COMPLETE}} {
                append message " Detail: $verification_detail"
            }
            lappend errors [_bundle_aware_preflight_error \
                $check_name $message]
        }
    }

    set all_checks_pass 1
    foreach check_name $bundle_aware_preflight_checks {
        if {![dict get $checks $check_name]} {
            set all_checks_pass 0
        }
    }
    set status [expr {$all_checks_pass ? {PASS} : {BLOCKED}}]
    return [_bundle_aware_preflight_result \
        $status $current_execution_id $provenance_context $checks $errors]
}

# The controller is the single mutation-authorization policy owner. The
# assertion is deliberately operation-, phase-, execution-, and BD-specific;
# it grants no project, BD lifecycle, workspace, artifact, or process authority.
proc ::stage1d::controller_core::create_mutation_authorization_assertion {
    context
} {
    if {[catch {dict size $context} context_error]} {
        error "Controller authorization input is not a dictionary: $context_error"
    }

    set binding_evaluation \
        [_evaluate_authorization_evidence_binding $context]
    set accepted_execution_context [dict get \
        $binding_evaluation accepted_execution_context]

    set execution_id [dict get $binding_evaluation execution_id]
    set bd_name {}
    if {[dict size $accepted_execution_context] > 0} {
        set execution_id [dict get \
            $accepted_execution_context execution_id]
        set bd_name [dict get $accepted_execution_context bd_name]
    } elseif {[dict exists $context configuration lifecycle bd_name]} {
        set bd_name [dict get $context configuration lifecycle bd_name]
    }

    set decision DENY
    if {[string trim $execution_id] ne {} &&
        [string trim $bd_name] ne {} &&
        [dict get $binding_evaluation status] eq {PASS} &&
        [dict exists $context controller_state] &&
        [dict get $context controller_state] eq {BD_READY}} {
        set decision ALLOW
    }

    return [dict create \
        execution_id $execution_id \
        operation stage1d_controlled_stimulus \
        phase MUTATION_EXECUTE \
        bd_name $bd_name \
        decision $decision]
}

proc ::stage1d::controller_core::validate_authorization_evidence_context {
    context
    authorization_evidence_context
} {
    variable authorization_evidence_context_fields
    variable authorization_evidence_checks

    set evaluation [_evaluate_authorization_evidence_binding $context]
    set checks [_authorization_evidence_check_state]
    set current_execution_id [dict get $evaluation execution_id]
    set accepted_execution_context [dict get \
        $evaluation accepted_execution_context]
    set selected_profile_identity [dict get \
        $evaluation selected_profile_identity]
    set expected_assertion \
        [create_mutation_authorization_assertion $context]

    set evidence_schema_valid [expr {
        ![catch {dict size $authorization_evidence_context}] &&
        [lsort [dict keys $authorization_evidence_context]] eq
            [lsort $authorization_evidence_context_fields]
    }]
    if {$evidence_schema_valid &&
        [dict size $accepted_execution_context] > 0} {
        set bundle_matches [expr {
            [dict get $evaluation checks \
                AUTHORIZATION_BUNDLE_IDENTITY_MATCH] &&
            [dict get $authorization_evidence_context bundle_identity] eq
                [dict get $accepted_execution_context bundle_identity]
        }]
        dict set checks AUTHORIZATION_BUNDLE_IDENTITY_MATCH \
            $bundle_matches

        set profile_matches [expr {
            [dict get $evaluation checks \
                AUTHORIZATION_PROFILE_IDENTITY_MATCH] &&
            [dict get $authorization_evidence_context profile_identity] eq
                $selected_profile_identity
        }]
        dict set checks AUTHORIZATION_PROFILE_IDENTITY_MATCH \
            $profile_matches

        set source_matches [expr {
            [dict get $evaluation checks \
                AUTHORIZATION_SOURCE_IDENTITY_MATCH] &&
            [dict get $authorization_evidence_context source_identity] eq
                [dict get $accepted_execution_context source_identity]
        }]
        dict set checks AUTHORIZATION_SOURCE_IDENTITY_MATCH \
            $source_matches

        set environment_matches [expr {
            [dict get $evaluation checks \
                AUTHORIZATION_ENVIRONMENT_IDENTITY_MATCH] &&
            [dict get $authorization_evidence_context environment_identity] eq
                [dict get $accepted_execution_context environment_identity]
        }]
        dict set checks AUTHORIZATION_ENVIRONMENT_IDENTITY_MATCH \
            $environment_matches

        set evidence_context_bound [expr {
            [dict get $evaluation checks \
                AUTHORIZATION_EVIDENCE_CONTEXT_BOUND] &&
            [dict get $authorization_evidence_context execution_id] eq
                $current_execution_id &&
            [dict get $authorization_evidence_context \
                authorization_assertion] eq $expected_assertion &&
            $bundle_matches &&
            $profile_matches &&
            $source_matches &&
            $environment_matches
        }]
        dict set checks AUTHORIZATION_EVIDENCE_CONTEXT_BOUND \
            $evidence_context_bound
    }

    set errors {}
    foreach specification {
        {AUTHORIZATION_EVIDENCE_CONTEXT_BOUND
            {Authorization evidence context does not match the current execution.}}
        {AUTHORIZATION_BUNDLE_IDENTITY_MATCH
            {Authorization evidence bundle identity mismatch.}}
        {AUTHORIZATION_PROFILE_IDENTITY_MATCH
            {Authorization evidence profile identity mismatch.}}
        {AUTHORIZATION_SOURCE_IDENTITY_MATCH
            {Authorization evidence source identity mismatch.}}
        {AUTHORIZATION_ENVIRONMENT_IDENTITY_MATCH
            {Authorization evidence environment identity mismatch.}}
    } {
        lassign $specification check_name message
        if {![dict get $checks $check_name]} {
            lappend errors [_authorization_evidence_binding_error \
                $check_name $message]
        }
    }
    set status [expr {
        [dict get $checks AUTHORIZATION_EVIDENCE_CONTEXT_BOUND] ?
            {PASS} : {BLOCKED}
    }]

    return [dict create \
        status $status \
        phase AUTHORIZATION_EVIDENCE_BINDING \
        execution_id $current_execution_id \
        authorization_evidence_context $authorization_evidence_context \
        errors $errors \
        warnings {} \
        outputs [dict merge $checks [dict create \
            evidence_context_schema_valid $evidence_schema_valid]]]
}

proc ::stage1d::controller_core::create_mutation_authorization_evidence {
    context
} {
    set evaluation [_evaluate_authorization_evidence_binding $context]
    set accepted_execution_context [dict get \
        $evaluation accepted_execution_context]
    set authorization_assertion \
        [create_mutation_authorization_assertion $context]
    set authorization_evidence_context {}
    if {[dict size $accepted_execution_context] > 0} {
        set authorization_evidence_context [dict create \
            execution_id [dict get \
                $accepted_execution_context execution_id] \
            source_identity [dict get \
                $accepted_execution_context source_identity] \
            environment_identity [dict get \
                $accepted_execution_context environment_identity] \
            bundle_identity [dict get \
                $accepted_execution_context bundle_identity] \
            profile_identity [dict get \
                $evaluation selected_profile_identity] \
            authorization_assertion $authorization_assertion]
    }

    set validation_result [validate_authorization_evidence_context \
        $context $authorization_evidence_context]
    set mutation_authorized [expr {
        [dict get $validation_result status] eq {PASS} &&
        [_mutation_assertion_allows $authorization_assertion]
    }]
    set status [expr {$mutation_authorized ? {PASS} : {BLOCKED}}]
    set errors [dict get $validation_result errors]
    if {[dict get $validation_result status] eq {PASS} &&
        !$mutation_authorized} {
        lappend errors [_mutation_error_record \
            MUTATION_AUTHORIZATION_DENIED \
            AUTHORIZATION \
            {Controller authorization prerequisites did not permit mutation.} \
            {} \
            COMPLETE_BD_OPEN]
    }

    return [dict create \
        status $status \
        phase MUTATION_AUTHORIZATION \
        execution_id [dict get $validation_result execution_id] \
        authorization_evidence_context $authorization_evidence_context \
        authorization_assertion $authorization_assertion \
        errors $errors \
        warnings {} \
        outputs [dict merge [dict get $validation_result outputs] \
            [dict create \
                authorization_evidence_context \
                    $authorization_evidence_context \
                authorization_assertion $authorization_assertion \
                mutation_authorized $mutation_authorized]]]
}

proc ::stage1d::controller_core::_attach_authorization_evidence {
    mutation_result
    authorization_result
} {
    variable authorization_evidence_checks

    dict set mutation_result outputs authorization_evidence_context \
        [dict get $authorization_result authorization_evidence_context]
    dict set mutation_result outputs authorization_evidence_status \
        [dict get $authorization_result status]
    foreach check_name $authorization_evidence_checks {
        dict set mutation_result outputs $check_name [dict get \
            $authorization_result outputs $check_name]
    }
    return $mutation_result
}

proc ::stage1d::controller_core::_attach_bundle_aware_preflight {
    mutation_result
    bundle_aware_preflight_result
} {
    variable bundle_aware_preflight_checks

    dict set mutation_result outputs execution_provenance_context \
        [dict get $bundle_aware_preflight_result provenance_context]
    dict set mutation_result outputs bundle_aware_preflight_status \
        [dict get $bundle_aware_preflight_result status]
    dict set mutation_result outputs continuation_allowed [dict get \
        $bundle_aware_preflight_result outputs continuation_allowed]
    foreach check_name $bundle_aware_preflight_checks {
        dict set mutation_result outputs $check_name [dict get \
            $bundle_aware_preflight_result outputs $check_name]
    }
    return $mutation_result
}

proc ::stage1d::controller_core::_mutation_callback_result {
    status
    execution_id
    authorization_assertion
    mutation_invoked
    vivado_invoked
    artifacts_generated
    errors
    module_result
} {
    set evidence_locations {}
    set logs {}
    set reports {}
    set artifact_references {}
    set module_outputs {}
    set mutation_summary {}
    set warnings {}
    set module_phase {}

    if {![catch {dict size $module_result}]} {
        foreach field {
            evidence_locations
            logs
            reports
            artifact_references
        } {
            if {[dict exists $module_result $field]} {
                set $field [dict get $module_result $field]
            }
        }
        if {[dict exists $module_result outputs]} {
            set module_outputs [dict get $module_result outputs]
        }
        if {[dict exists $module_result mutation_summary]} {
            set mutation_summary [dict get $module_result mutation_summary]
        }
        if {[dict exists $module_result warnings]} {
            set warnings [dict get $module_result warnings]
        }
        if {[dict exists $module_result phase]} {
            set module_phase [dict get $module_result phase]
        }
    }

    set next_required_phase {}
    if {$status eq {PASS}} {
        set next_required_phase BD_VALIDATE
    }

    return [dict create \
        status $status \
        evidence_locations $evidence_locations \
        logs $logs \
        reports $reports \
        errors $errors \
        outputs [dict create \
            phase_sequence [_mutation_phase_sequence] \
            result_phase MUTATION_RESULT \
            execution_id $execution_id \
            authorization_assertion $authorization_assertion \
            mutation_authorized [_mutation_assertion_allows \
                $authorization_assertion] \
            mutation_invoked $mutation_invoked \
            mutation_invocation_count $mutation_invoked \
            mutation_status $status \
            vivado_invoked $vivado_invoked \
            artifacts_generated $artifacts_generated \
            next_required_phase $next_required_phase \
            module_phase $module_phase \
            module_outputs $module_outputs \
            mutation_summary $mutation_summary \
            warnings $warnings] \
        artifact_references $artifact_references]
}

proc ::stage1d::controller_core::create_mutation_context {
    context
    {authorization_assertion {}}
} {
    variable mutation_context_fields
    variable mutation_operational_context_fields

    if {[catch {dict size $context} context_error]} {
        error "Controller mutation input context is not a dictionary: $context_error"
    }
    if {![dict exists $context controller_state] ||
        [dict get $context controller_state] ne {BD_READY}} {
        error {Mutation authorization requires controller state BD_READY.}
    }

    set execution_id [dict get \
        $context execution_identity execution_identifier]
    if {[string trim $execution_id] eq {}} {
        error {Mutation context requires a nonempty execution_id.}
    }

    set execution_workspace [file normalize \
        [dict get $context workspace_preparation execution_workspace]]
    set evidence_dir [file normalize \
        [file join $execution_workspace execution_state]]
    set bd_name [dict get $context configuration lifecycle bd_name]

    set authorization_result \
        [create_mutation_authorization_evidence $context]
    if {[dict get $authorization_result status] ne {PASS}} {
        error {Controller authorization evidence is not bound to the current execution.}
    }
    set expected_authorization_assertion [dict get \
        $authorization_result authorization_assertion]
    if {$authorization_assertion eq {}} {
        set authorization_assertion $expected_authorization_assertion
    }
    if {$authorization_assertion ne $expected_authorization_assertion ||
        ![_mutation_assertion_allows $authorization_assertion] ||
        [dict get $authorization_assertion execution_id] ne $execution_id ||
        [dict get $authorization_assertion bd_name] ne $bd_name} {
        error {Controller mutation authorization assertion is invalid or denied.}
    }

    set binding_evaluation [_evaluate_authorization_evidence_binding $context]
    if {[dict get $binding_evaluation status] ne {PASS}} {
        error {Mutation context requires an accepted execution context.}
    }
    set accepted_execution_context [dict get \
        $binding_evaluation accepted_execution_context]

    foreach ownership_key {project_ownership bd_ownership} {
        if {![dict exists $context bd_lifecycle_context $ownership_key]} {
            error "Mutation context requires validated lifecycle ownership: $ownership_key"
        }
    }
    set project_ownership [dict get \
        $context bd_lifecycle_context project_ownership]
    set bd_ownership [dict get $context bd_lifecycle_context bd_ownership]
    if {[dict get $project_ownership owner] ne {vivado_project} ||
        [dict get $bd_ownership owner] ne {bd_flow} ||
        [dict get $project_ownership execution_id] ne $execution_id ||
        [dict get $bd_ownership execution_id] ne $execution_id ||
        ![dict get $project_ownership identity_verified] ||
        ![dict get $bd_ownership opened] ||
        ![dict get $bd_ownership identity_verified] ||
        [dict get $bd_ownership validated] ||
        [dict get $bd_ownership saved]} {
        error {Mutation context lifecycle ownership is not at the accepted BD_READY boundary.}
    }

    set current_bd [dict get $bd_ownership bd_name]
    if {$current_bd ne $bd_name ||
        [dict get $accepted_execution_context bd_name] ne $bd_name} {
        error {Mutation context BD identity does not match accepted execution evidence.}
    }
    set project_path [file normalize [dict get $bd_ownership project_path]]
    if {$project_path ne [file normalize \
        [dict get $project_ownership project_path]] ||
        $project_path ne [file normalize \
            [dict get $accepted_execution_context project_path]] ||
        ![_is_equal_or_descendant $project_path $execution_workspace]} {
        error {Mutation context project path does not match accepted lifecycle evidence.}
    }

    set accepted_environment [dict get $context environment_verification]
    if {![dict exists $accepted_environment environment_verified] ||
        ![dict get $accepted_environment environment_verified] ||
        ![dict exists $accepted_environment vivado_version]} {
        error {Mutation context requires accepted environment identity evidence.}
    }
    set mutation_configuration [_validated_mutation_configuration \
        [dict get $context configuration]]
    foreach catalog_field {axi_gpio_vlnv xlslice_vlnv} {
        set required_vlnv [dict get $mutation_configuration $catalog_field]
        if {![dict exists $accepted_environment observed_ip_identities] ||
            [lsearch -exact [dict get \
                $accepted_environment observed_ip_identities] \
                $required_vlnv] < 0} {
            error "Mutation context IP identity is absent from accepted environment evidence: $required_vlnv"
        }
    }
    if {![dict exists $accepted_environment expected_environment \
            custom_protection_ip vlnv] ||
        [dict get $accepted_environment expected_environment \
            custom_protection_ip vlnv] ne
            [dict get $mutation_configuration protection_vlnv]} {
        error {Mutation context protection IP identity does not match accepted environment evidence.}
    }

    set operational_context [dict merge $mutation_configuration [dict create \
        current_bd $current_bd \
        expected_bd_name $bd_name \
        project_path $project_path \
        vivado_version [dict get $accepted_environment vivado_version]]]
    if {[lsort [dict keys $operational_context]] ne \
        [lsort $mutation_operational_context_fields]} {
        error {Controller produced an invalid operational mutation context.}
    }

    set mutation_context [dict merge [dict create \
        execution_id $execution_id \
        authorization_assertion $authorization_assertion \
        bd_name $bd_name \
        evidence_dir $evidence_dir \
        environment_identity [dict get $context environment_verification]] \
        $operational_context]

    set required_keys [lsort $mutation_context_fields]
    if {[lsort [dict keys $mutation_context]] ne $required_keys} {
        error {Controller produced an invalid restricted mutation context.}
    }
    return $mutation_context
}

proc ::stage1d::controller_core::_normalize_mutation_invocation {
    mutation_context
    invocation_status
    module_result
    module_options
} {
    set execution_id [dict get $mutation_context execution_id]
    set authorization_assertion [dict get \
        $mutation_context authorization_assertion]

    if {$invocation_status != 0} {
        set underlying_error {}
        if {[dict exists $module_options -errorinfo]} {
            set underlying_error [dict get $module_options -errorinfo]
        }
        set error_record [_mutation_error_record \
            MUTATION_INVOCATION_ERROR \
            MUTATION \
            "Stage 1D mutation procedure failed: $module_result" \
            $underlying_error \
            CLEANUP_REQUIRED]
        return [_mutation_callback_result \
            FAIL $execution_id $authorization_assertion \
            1 1 0 [list $error_record] {}]
    }

    if {[catch {dict size $module_result} result_error]} {
        set error_record [_mutation_error_record \
            INVALID_MUTATION_RESULT \
            CONTRACT \
            {Mutation procedure returned neither its legacy empty result nor a structured result.} \
            $result_error \
            FIX_MUTATION_RESULT]
        return [_mutation_callback_result \
            FAIL $execution_id $authorization_assertion \
            1 1 0 [list $error_record] {}]
    }

    # The extracted Phase 3-B2A procedure returns an empty Tcl result after a
    # successful legacy invocation. Phase 3-B2B normalizes that boundary only;
    # it does not alter mutation behavior or claim later BD lifecycle phases.
    if {[dict size $module_result] == 0} {
        return [_mutation_callback_result \
            PASS $execution_id $authorization_assertion \
            1 1 0 {} {}]
    }

    if {![dict exists $module_result status]} {
        set error_record [_mutation_error_record \
            MISSING_MUTATION_STATUS \
            CONTRACT \
            {Structured mutation result is missing status.} \
            {} \
            FIX_MUTATION_RESULT]
        return [_mutation_callback_result \
            FAIL $execution_id $authorization_assertion \
            1 1 0 [list $error_record] $module_result]
    }

    set status [dict get $module_result status]
    if {$status ni {PASS FAIL BLOCKED}} {
        set error_record [_mutation_error_record \
            INVALID_MUTATION_STATUS \
            CONTRACT \
            "Unsupported mutation result status: $status" \
            {} \
            FIX_MUTATION_RESULT]
        return [_mutation_callback_result \
            FAIL $execution_id $authorization_assertion \
            1 1 0 [list $error_record] $module_result]
    }

    if {[dict exists $module_result execution_id] &&
        [dict get $module_result execution_id] ne $execution_id} {
        set error_record [_mutation_error_record \
            MUTATION_EXECUTION_ID_MISMATCH \
            CONTRACT \
            "Mutation result execution_id does not match controller execution: expected=$execution_id actual=[dict get $module_result execution_id]" \
            {} \
            REJECT_RESULT]
        return [_mutation_callback_result \
            FAIL $execution_id $authorization_assertion \
            1 1 0 [list $error_record] $module_result]
    }

    set vivado_invoked 1
    if {[dict exists $module_result vivado_invoked]} {
        set vivado_invoked [dict get $module_result vivado_invoked]
        if {![string is boolean -strict $vivado_invoked]} {
            set error_record [_mutation_error_record \
                INVALID_MUTATION_VIVADO_FLAG \
                CONTRACT \
                {Mutation result vivado_invoked must be boolean.} \
                {} \
                FIX_MUTATION_RESULT]
            return [_mutation_callback_result \
                FAIL $execution_id $authorization_assertion \
                1 1 0 [list $error_record] $module_result]
        }
        set vivado_invoked [expr {$vivado_invoked ? 1 : 0}]
    }

    set artifacts_generated 0
    if {[dict exists $module_result artifacts_generated]} {
        set artifacts_generated [dict get $module_result artifacts_generated]
        if {![string is boolean -strict $artifacts_generated]} {
            set error_record [_mutation_error_record \
                INVALID_MUTATION_ARTIFACT_FLAG \
                CONTRACT \
                {Mutation result artifacts_generated must be boolean.} \
                {} \
                FIX_MUTATION_RESULT]
            return [_mutation_callback_result \
                FAIL $execution_id $authorization_assertion \
                1 $vivado_invoked 0 [list $error_record] $module_result]
        }
        set artifacts_generated [expr {$artifacts_generated ? 1 : 0}]
    }
    if {$artifacts_generated} {
        set error_record [_mutation_error_record \
            MUTATION_ARTIFACT_BOUNDARY_VIOLATION \
            OWNERSHIP \
            {Mutation procedure reported artifact generation outside its ownership boundary.} \
            {} \
            REJECT_RESULT]
        return [_mutation_callback_result \
            FAIL $execution_id $authorization_assertion \
            1 $vivado_invoked 1 [list $error_record] $module_result]
    }

    set errors {}
    if {[dict exists $module_result errors]} {
        set errors [dict get $module_result errors]
        if {[catch {llength $errors} errors_error]} {
            set error_record [_mutation_error_record \
                INVALID_MUTATION_ERRORS \
                CONTRACT \
                {Mutation result errors must be a list.} \
                $errors_error \
                FIX_MUTATION_RESULT]
            return [_mutation_callback_result \
                FAIL $execution_id $authorization_assertion \
                1 $vivado_invoked 0 [list $error_record] $module_result]
        }
    }
    if {$status ne {PASS} && [llength $errors] == 0} {
        lappend errors [_mutation_error_record \
            "MUTATION_$status" \
            MUTATION \
            "Mutation procedure returned $status." \
            {} \
            NONE]
    }

    return [_mutation_callback_result \
        $status $execution_id $authorization_assertion \
        1 $vivado_invoked 0 $errors $module_result]
}

proc ::stage1d::controller_core::phase_stage1d_mutation {context} {
    set execution_id [dict get \
        $context execution_identity execution_identifier]
    set authorization_result \
        [create_mutation_authorization_evidence $context]
    set authorization_assertion [dict get \
        $authorization_result authorization_assertion]
    set bundle_aware_preflight_result [verify_bundle_aware_preflight \
        $context [dict get $authorization_result \
            authorization_evidence_context]]

    if {[dict get $authorization_result status] ne {PASS} ||
        ![_mutation_assertion_allows $authorization_assertion] ||
        [dict get $bundle_aware_preflight_result status] ne {PASS}} {
        set errors [concat \
            [dict get $authorization_result errors] \
            [dict get $bundle_aware_preflight_result errors]]
        if {[llength $errors] == 0} {
            lappend errors [_mutation_error_record \
                MUTATION_AUTHORIZATION_DENIED \
                AUTHORIZATION \
                {Controller denied Stage 1D controlled execution continuation.} \
                {} \
                COMPLETE_BD_OPEN]
        }
        set blocked_result [_mutation_callback_result \
            BLOCKED $execution_id $authorization_assertion \
            0 0 0 $errors {}]
        set blocked_result [_attach_authorization_evidence \
            $blocked_result $authorization_result]
        return [_attach_bundle_aware_preflight \
            $blocked_result $bundle_aware_preflight_result]
    }

    if {![namespace exists ::stage1d_controlled_stimulus] ||
        [llength [info procs ::stage1d_controlled_stimulus::apply]] != 1} {
        set error_record [_mutation_error_record \
            MUTATION_INTERFACE_UNAVAILABLE \
            SOURCE \
            {Required Stage 1D mutation namespace or apply procedure is unavailable.} \
            {} \
            LOAD_MUTATION_MODULE]
        set blocked_result [_mutation_callback_result \
            BLOCKED $execution_id $authorization_assertion \
            0 0 0 [list $error_record] {}]
        set blocked_result [_attach_authorization_evidence \
            $blocked_result $authorization_result]
        return [_attach_bundle_aware_preflight \
            $blocked_result $bundle_aware_preflight_result]
    }

    if {[catch {
        create_mutation_context $context $authorization_assertion
    } mutation_context context_options]} {
        set underlying_error {}
        if {[dict exists $context_options -errorinfo]} {
            set underlying_error [dict get $context_options -errorinfo]
        }
        set error_record [_mutation_error_record \
            MUTATION_CONTEXT_INVALID \
            CONTRACT \
            "Unable to create restricted mutation context: $mutation_context" \
            $underlying_error \
            FIX_CONTROLLER_CONTEXT]
        set failed_result [_mutation_callback_result \
            FAIL $execution_id $authorization_assertion \
            0 0 0 [list $error_record] {}]
        set failed_result [_attach_authorization_evidence \
            $failed_result $authorization_result]
        return [_attach_bundle_aware_preflight \
            $failed_result $bundle_aware_preflight_result]
    }

    set invocation_status [catch {
        ::stage1d_controlled_stimulus::apply $mutation_context
    } module_result module_options]

    set mutation_result [_normalize_mutation_invocation \
        $mutation_context $invocation_status $module_result $module_options]
    set mutation_result [_attach_authorization_evidence \
        $mutation_result $authorization_result]
    return [_attach_bundle_aware_preflight \
        $mutation_result $bundle_aware_preflight_result]
}

proc ::stage1d::controller_core::_run_mutation_phase_boundary {
    state_variable
    logger_variable
    context
} {
    upvar 1 $state_variable state
    upvar 1 $logger_variable logger

    set phase_name stage1d_mutation
    set execution_identifier [dict get $state execution_identifier]
    set start_time [::stage1d::logger::utc_timestamp]
    set start_log [::stage1d::logger::record \
        logger \
        $phase_name \
        INFO \
        MUTATION_AUTHORIZATION_EVALUATION \
        {Controller entered the Stage 1D mutation authorization evidence boundary.} \
        $start_time]
    ::stage1d::logger::emit $start_log

    dict set context controller_state \
        [::stage1d::state_manager::current $state]
    set callback_status [catch {
        phase_stage1d_mutation $context
    } callback_result callback_options]
    if {$callback_status != 0} {
        set underlying_error {}
        if {[dict exists $callback_options -errorinfo]} {
            set underlying_error [dict get $callback_options -errorinfo]
        }
        set error_record [_mutation_error_record \
            MUTATION_CONTROLLER_BOUNDARY_ERROR \
            CORE \
            "Unhandled controller mutation boundary error: $callback_result" \
            $underlying_error \
            NONE]
        set callback_result [_mutation_callback_result \
            FAIL $execution_identifier {} 0 0 0 [list $error_record] {}]
    }

    set status [dict get $callback_result status]
    set end_time [::stage1d::logger::utc_timestamp]
    switch -- $status {
        PASS { set severity INFO }
        BLOCKED { set severity WARNING }
        default { set severity ERROR }
    }
    set end_log [::stage1d::logger::record \
        logger \
        $phase_name \
        $severity \
        MUTATION_RESULT \
        "Controller recorded Stage 1D mutation result: $status" \
        $end_time]
    ::stage1d::logger::emit $end_log

    set evidence_logs [list $start_log]
    foreach callback_log [dict get $callback_result logs] {
        lappend evidence_logs $callback_log
    }
    lappend evidence_logs $end_log

    dict set callback_result outputs lifecycle_state_advanced \
        [expr {$status in {FAIL BLOCKED}}]
    set evidence [dict create \
        phase_evidence_schema_version [dict get \
            $context phase_evidence_schema_version] \
        phase_name $phase_name \
        status $status \
        start_time $start_time \
        end_time $end_time \
        execution_id_schema_version [dict get \
            $state execution_id_schema_version] \
        execution_identifier $execution_identifier \
        controller_version [dict get $state controller_version] \
        controller_api_version [dict get $state controller_api_version] \
        evidence_locations [dict get $callback_result evidence_locations] \
        logs $evidence_logs \
        reports [dict get $callback_result reports] \
        errors [dict get $callback_result errors] \
        outputs [dict get $callback_result outputs] \
        artifact_references [dict get $callback_result artifact_references]]

    ::stage1d::phase_runner::validate_evidence \
        $evidence $phase_name $execution_identifier

    # A successful mutation result does not imply BD validation or save. Keep
    # the lifecycle state at BD_READY until those owners are connected later.
    if {$status in {FAIL BLOCKED}} {
        set transition [::stage1d::state_manager::transition \
            state $status $evidence $end_time]
        dict set evidence state_transition $transition
    } else {
        dict set evidence state_transition {}
    }

    ::stage1d::phase_runner::validate_evidence \
        $evidence $phase_name $execution_identifier
    return $evidence
}

# Run a controller-owned lifecycle decision boundary whose PASS result does not
# claim a new state. BD save uses this because the current Stage 1D state model
# has DESIGN_VALIDATED but no separate BD_SAVED state. FAIL and BLOCKED remain
# terminal and are propagated through the state manager.
proc ::stage1d::controller_core::_run_nonadvancing_lifecycle_phase {
    state_variable
    logger_variable
    phase_name
    callback
    context
} {
    upvar 1 $state_variable state
    upvar 1 $logger_variable logger

    set execution_identifier [dict get $state execution_identifier]
    set start_time [::stage1d::logger::utc_timestamp]
    set start_log [::stage1d::logger::record \
        logger $phase_name INFO LIFECYCLE_PHASE_START \
        "Controller entered lifecycle phase: $phase_name" $start_time]
    ::stage1d::logger::emit $start_log

    set callback_command [linsert $callback end $context]
    set callback_status [catch {
        uplevel #0 $callback_command
    } callback_result callback_options]
    if {$callback_status != 0} {
        set underlying_error {}
        if {[dict exists $callback_options -errorinfo]} {
            set underlying_error [dict get $callback_options -errorinfo]
        }
        set callback_result [dict create \
            status FAIL \
            evidence_locations {} \
            logs {} \
            reports {} \
            errors [list [dict create \
                error_code LIFECYCLE_CALLBACK_ERROR \
                category CORE \
                phase_name $phase_name \
                message "Unhandled lifecycle callback error: $callback_result" \
                underlying_error $underlying_error \
                evidence_references {} \
                recoverability NONE]] \
            outputs {} \
            artifact_references {}]
    } elseif {[catch {dict size $callback_result} result_error]} {
        set callback_result [dict create \
            status FAIL \
            evidence_locations {} \
            logs {} \
            reports {} \
            errors [list [dict create \
                error_code INVALID_LIFECYCLE_RESULT \
                category CONTRACT \
                phase_name $phase_name \
                message {Lifecycle callback result is not a dictionary.} \
                underlying_error $result_error \
                evidence_references {} \
                recoverability FIX_ADAPTER_RESULT]] \
            outputs {} \
            artifact_references {}]
    } elseif {![dict exists $callback_result status] ||
        [dict get $callback_result status] ni {PASS FAIL BLOCKED}} {
        set callback_result [dict create \
            status FAIL \
            evidence_locations {} \
            logs {} \
            reports {} \
            errors [list [dict create \
                error_code INVALID_LIFECYCLE_STATUS \
                category CONTRACT \
                phase_name $phase_name \
                message {Lifecycle callback returned a missing or invalid status.} \
                underlying_error {} \
                evidence_references {} \
                recoverability FIX_ADAPTER_RESULT]] \
            outputs {} \
            artifact_references {}]
    }

    set status [dict get $callback_result status]
    set end_time [::stage1d::logger::utc_timestamp]
    switch -- $status {
        PASS { set severity INFO }
        BLOCKED { set severity WARNING }
        default { set severity ERROR }
    }
    set end_log [::stage1d::logger::record \
        logger $phase_name $severity LIFECYCLE_PHASE_RESULT \
        "Controller recorded lifecycle result: $status" $end_time]
    ::stage1d::logger::emit $end_log

    foreach list_field {
        evidence_locations
        logs
        reports
        errors
        artifact_references
    } {
        if {![dict exists $callback_result $list_field]} {
            dict set callback_result $list_field {}
        }
    }
    if {![dict exists $callback_result outputs]} {
        dict set callback_result outputs {}
    }
    set evidence_logs [list $start_log]
    foreach callback_log [dict get $callback_result logs] {
        lappend evidence_logs $callback_log
    }
    lappend evidence_logs $end_log
    dict set callback_result outputs lifecycle_state_advanced \
        [expr {$status in {FAIL BLOCKED}}]

    set evidence [dict create \
        phase_evidence_schema_version [dict get \
            $context phase_evidence_schema_version] \
        phase_name $phase_name \
        status $status \
        start_time $start_time \
        end_time $end_time \
        execution_id_schema_version [dict get \
            $state execution_id_schema_version] \
        execution_identifier $execution_identifier \
        controller_version [dict get $state controller_version] \
        controller_api_version [dict get $state controller_api_version] \
        evidence_locations [dict get $callback_result evidence_locations] \
        logs $evidence_logs \
        reports [dict get $callback_result reports] \
        errors [dict get $callback_result errors] \
        outputs [dict get $callback_result outputs] \
        artifact_references [dict get $callback_result artifact_references]]

    ::stage1d::phase_runner::validate_evidence \
        $evidence $phase_name $execution_identifier
    if {$status in {FAIL BLOCKED}} {
        set transition [::stage1d::state_manager::transition \
            state $status $evidence $end_time]
        dict set evidence state_transition $transition
    } else {
        dict set evidence state_transition {}
    }
    ::stage1d::phase_runner::validate_evidence \
        $evidence $phase_name $execution_identifier
    return $evidence
}

proc ::stage1d::controller_core::_verification_evidence_completeness {phase_evidence} {
    set phase_evidence_schema_valid 1
    foreach evidence $phase_evidence {
        if {[catch {::stage1d::phase_runner::validate_evidence $evidence}]} {
            set phase_evidence_schema_valid 0
            break
        }
    }

    return [dict create \
        phase_evidence_complete 0 \
        phase_evidence_schema_valid $phase_evidence_schema_valid \
        required_logs_retained 1 \
        required_reports_retained 1]
}

proc ::stage1d::controller_core::_unpublished_publication_gate {} {
    return [dict create \
        required_artifacts_present 0 \
        artifact_hashes_recorded 0 \
        manifest_complete 0 \
        manifest_schema_valid 0 \
        publication_authorized 0 \
        artifact_publication_complete 0]
}

proc ::stage1d::controller_core::_delivery_manifest_argument {
    parsed_arguments
} {
    if {![dict exists $parsed_arguments delivery_manifest_path]} {
        return {}
    }
    return [dict get $parsed_arguments delivery_manifest_path]
}

proc ::stage1d::controller_core::_path_contains_symbolic_link {path} {
    set components [file split $path]
    if {[llength $components] == 0} {
        return 0
    }

    set cursor [lindex $components 0]
    foreach component [lrange $components 1 end] {
        set cursor [file join $cursor $component]
        if {[file exists $cursor] && [file type $cursor] eq {link}} {
            return 1
        }
    }
    return 0
}

proc ::stage1d::controller_core::_validate_delivery_manifest_selection {
    parsed_arguments
} {
    set selected_path [_delivery_manifest_argument $parsed_arguments]
    if {$selected_path eq {}} {
        return [dict create \
            delivery_manifest_selected 0 \
            delivery_manifest_path {} \
            delivery_bundle_root {} \
            BUNDLE_SELECTION_EXPLICIT 0 \
            BUNDLE_SELECTION_PATH_BOUND 0]
    }
    if {[string trim $selected_path] eq {}} {
        error {Selected delivery manifest path must not be empty.}
    }
    if {[file pathtype $selected_path] ne {absolute}} {
        error {Selected delivery manifest path must be absolute.}
    }
    foreach component [file split $selected_path] {
        if {$component in {. ..}} {
            error {Selected delivery manifest path contains traversal.}
        }
    }
    if {![file exists $selected_path] || ![file isfile $selected_path] ||
        [file type $selected_path] ne {file}} {
        error {Selected delivery manifest is not an existing regular file.}
    }
    if {[file tail $selected_path] ne {manifest.dict}} {
        error {Selected delivery manifest must be named manifest.dict.}
    }
    if {[_path_contains_symbolic_link $selected_path]} {
        error {Selected delivery manifest path must not traverse symbolic links.}
    }

    set manifest_path [file normalize $selected_path]
    set bundle_root [file normalize [file dirname $manifest_path]]
    set expected_manifest [file normalize [file join $bundle_root manifest.dict]]
    if {![_is_equal_or_descendant $manifest_path $bundle_root] ||
        [_canonical_components $manifest_path] ne
            [_canonical_components $expected_manifest]} {
        error {Selected delivery manifest is not contained by its package root.}
    }

    return [dict create \
        delivery_manifest_selected 1 \
        delivery_manifest_path $manifest_path \
        delivery_bundle_root $bundle_root \
        BUNDLE_SELECTION_EXPLICIT 1 \
        BUNDLE_SELECTION_PATH_BOUND 1]
}

proc ::stage1d::controller_core::phase_input_validation {context} {
    set parsed [dict get $context parsed_arguments]
    set configuration [dict get $context configuration]
    set execution_identity [dict get $context execution_identity]

    _validate_configuration_identity $configuration

    set repository_root [file normalize [dict get $parsed repository_root]]
    set build_workspace_root [file normalize [dict get $parsed build_workspace]]
    set artifact_storage_root [file normalize [dict get $parsed artifact_storage]]
    set delivery_manifest_selection \
        [_validate_delivery_manifest_selection $parsed]

    if {![file exists $repository_root] || ![file isdirectory $repository_root]} {
        error "Repository root is not an existing directory: $repository_root"
    }
    if {[_paths_overlap $repository_root $build_workspace_root]} {
        error {Build workspace must be external to and separate from the repository.}
    }
    if {[_paths_overlap $repository_root $artifact_storage_root]} {
        error {Artifact storage must be external to and separate from the repository.}
    }
    if {[_paths_overlap $build_workspace_root $artifact_storage_root]} {
        error {Build workspace and artifact storage must be separate.}
    }

    set execution_locations [_assert_execution_identifier_available \
        [dict get $execution_identity execution_identifier] \
        $build_workspace_root \
        $artifact_storage_root]

    set outputs [dict merge [dict create \
        repository_root $repository_root \
        build_workspace_root $build_workspace_root \
        artifact_storage_root $artifact_storage_root \
        execution_workspace [dict get $execution_locations execution_workspace] \
        candidate_artifact_directory [dict get $execution_locations candidate_artifact_directory] \
        artifact_group [dict get $execution_locations artifact_group] \
        collision_check_result PASS \
        workspace_created 0 \
        candidate_artifacts_created 0] $delivery_manifest_selection]

    return [dict create \
        status PASS \
        evidence_locations {} \
        logs {} \
        reports {} \
        errors {} \
        outputs $outputs \
        artifact_references {}]
}

proc ::stage1d::controller_core::_preflight_error_record {
    error_code
    category
    phase
    message
    recoverability
    {underlying_error {}}
} {
    return [dict create \
        error_code $error_code \
        category $category \
        phase_name $phase \
        message $message \
        underlying_error $underlying_error \
        evidence_references {} \
        recoverability $recoverability]
}

proc ::stage1d::controller_core::_preflight_result {
    status
    phase
    execution_id
    source_identity
    environment_identity
    profile_identity
    workspace_identity
    errors
    warnings
    outputs
} {
    set result [dict create \
        status $status \
        phase $phase \
        execution_id $execution_id \
        source_identity $source_identity \
        environment_identity $environment_identity \
        profile_identity $profile_identity \
        workspace_identity $workspace_identity \
        errors $errors \
        warnings $warnings \
        outputs $outputs]
    validate_preflight_result $result $execution_id
    return $result
}

proc ::stage1d::controller_core::_preflight_identity_complete {identity} {
    if {[catch {dict size $identity} identity_error]} {
        error "Preflight identity is not a dictionary: $identity_error"
    }
    return [expr {[dict size $identity] > 0}]
}

proc ::stage1d::controller_core::validate_preflight_result {
    result
    {expected_execution_id {}}
    {require_complete_identity 0}
} {
    variable preflight_result_fields
    variable preflight_statuses

    if {[catch {dict size $result} result_error]} {
        error "Preflight result is not a dictionary: $result_error"
    }
    if {[lsort [dict keys $result]] ne [lsort $preflight_result_fields]} {
        error {Preflight result does not match the common result schema.}
    }
    if {[dict get $result status] ni $preflight_statuses} {
        error "Unsupported preflight status: [dict get $result status]"
    }
    if {[string trim [dict get $result phase]] eq {}} {
        error {Preflight result phase must not be empty.}
    }
    set execution_id [dict get $result execution_id]
    if {[string trim $execution_id] eq {}} {
        error {Preflight result execution_id must not be empty.}
    }
    if {$expected_execution_id ne {} && $execution_id ne $expected_execution_id} {
        error "Preflight execution_id mismatch: expected=$expected_execution_id actual=$execution_id"
    }

    foreach identity_field {
        source_identity
        environment_identity
        profile_identity
        workspace_identity
    } {
        set identity [dict get $result $identity_field]
        if {[catch {dict size $identity} identity_error]} {
            error "Preflight field $identity_field is not a dictionary: $identity_error"
        }
        if {$require_complete_identity && [dict size $identity] == 0} {
            error "Preflight result has incomplete identity: $identity_field"
        }
    }
    foreach list_field {errors warnings} {
        if {[catch {llength [dict get $result $list_field]} list_error]} {
            error "Preflight field $list_field is not a list: $list_error"
        }
    }
    if {[catch {dict size [dict get $result outputs]} outputs_error]} {
        error "Preflight outputs is not a dictionary: $outputs_error"
    }
    return 1
}

proc ::stage1d::controller_core::_profile_configuration_path {configuration} {
    if {[dict exists $configuration configuration_path]} {
        return [dict get $configuration configuration_path]
    }
    return IN_MEMORY_CONFIGURATION
}

# A profile is selected explicitly by choosing a configuration that contains a
# dry_run_profile section. The repository default has no such section and
# therefore remains closed. The profile is evidence and preflight scope only;
# it is not merged into lifecycle configuration in Stage 1D-D1.
proc ::stage1d::controller_core::resolve_preflight_profile {context} {
    set phase PROFILE_SELECTION
    set configuration [dict get $context configuration]
    set execution_id [dict get \
        $context execution_identity execution_identifier]
    set configuration_path [_profile_configuration_path $configuration]

    if {![dict exists $configuration dry_run_profile]} {
        set provenance [dict create \
            selection DEFAULT_CLOSED \
            configuration_path $configuration_path \
            execution_id $execution_id]
        set profile_identity [dict create \
            identity DEFAULT_CLOSED \
            provenance $provenance \
            source $configuration_path]
        set blocked_error [_preflight_error_record \
            DRY_RUN_PROFILE_NOT_SELECTED \
            AUTHORIZATION \
            $phase \
            {No explicit dry-run profile was selected; the default closed configuration remains active.} \
            SELECT_DRY_RUN_PROFILE]
        return [_preflight_result \
            BLOCKED $phase $execution_id {} {} $profile_identity {} \
            [list $blocked_error] {} [dict create \
                profile_selected 0 \
                selected_scope {} \
                profile_provenance $provenance \
                profile_source $configuration_path \
                PROFILE_SELECTION_VALID 0 \
                DEFAULT_CLOSED_WITHOUT_PROFILE 1]]
    }

    set profile [dict get $configuration dry_run_profile]
    if {[catch {dict size $profile} profile_error]} {
        set invalid_identity [dict create \
            identity INVALID \
            provenance [dict create configuration_path $configuration_path] \
            source $configuration_path]
        set error_record [_preflight_error_record \
            INVALID_DRY_RUN_PROFILE \
            CONFIGURATION \
            $phase \
            "Selected dry-run profile is not a dictionary: $profile_error" \
            FIX_PROFILE]
        return [_preflight_result \
            FAIL $phase $execution_id {} {} $invalid_identity {} \
            [list $error_record] {} [dict create \
                profile_selected 1 \
                selected_scope {} \
                PROFILE_SELECTION_VALID 0 \
                DEFAULT_CLOSED_WITHOUT_PROFILE 0]]
    }

    set validation_errors {}
    foreach required_field {identity provenance scope} {
        if {![dict exists $profile $required_field]} {
            lappend validation_errors "missing field: $required_field"
        }
    }
    if {[dict exists $profile identity] &&
        [string trim [dict get $profile identity]] eq {}} {
        lappend validation_errors {identity is empty}
    }
    if {[dict exists $profile provenance]} {
        set provenance [dict get $profile provenance]
        if {[catch {dict size $provenance} provenance_error]} {
            lappend validation_errors \
                "provenance is not a dictionary: $provenance_error"
        } elseif {[dict size $provenance] == 0} {
            lappend validation_errors {provenance is empty}
        }
    }
    if {[dict exists $profile scope] &&
        [catch {dict size [dict get $profile scope]} scope_error]} {
        lappend validation_errors "scope is not a dictionary: $scope_error"
    }

    if {[llength $validation_errors] > 0} {
        set invalid_identity [dict create \
            identity INVALID \
            provenance [dict create configuration_path $configuration_path] \
            source $configuration_path]
        set error_record [_preflight_error_record \
            INVALID_DRY_RUN_PROFILE \
            CONFIGURATION \
            $phase \
            "Selected dry-run profile is invalid: [join $validation_errors {; }]" \
            FIX_PROFILE]
        return [_preflight_result \
            FAIL $phase $execution_id {} {} $invalid_identity {} \
            [list $error_record] {} [dict create \
                profile_selected 1 \
                selected_scope {} \
                PROFILE_SELECTION_VALID 0 \
                DEFAULT_CLOSED_WITHOUT_PROFILE 0]]
    }

    set declared_provenance [dict get $profile provenance]
    set bound_provenance [dict create \
        declared $declared_provenance \
        configuration_path $configuration_path \
        execution_id $execution_id]
    set profile_identity [dict create \
        identity [dict get $profile identity] \
        provenance $bound_provenance \
        source $configuration_path]
    return [_preflight_result \
        PASS $phase $execution_id {} {} $profile_identity {} {} {} \
        [dict create \
            profile_selected 1 \
            selected_scope [dict get $profile scope] \
            profile_provenance $bound_provenance \
            profile_source $configuration_path \
            PROFILE_SELECTION_VALID 1 \
             DEFAULT_CLOSED_WITHOUT_PROFILE 0]]
}

proc ::stage1d::controller_core::_project_loader_environment_identity {
    accepted_environment_evidence
} {
    if {[catch {
        set environment_size [dict size $accepted_environment_evidence]
    } environment_error]} {
        error "Accepted environment evidence is invalid: $environment_error"
    }
    if {$environment_size == 0} {
        error {Accepted environment evidence is unavailable.}
    }

    foreach field {vivado_version board_part} {
        if {![dict exists $accepted_environment_evidence $field] ||
            [string trim [dict get $accepted_environment_evidence $field]] eq {}} {
            error "Accepted environment evidence is missing field: $field"
        }
    }
    if {[dict exists $accepted_environment_evidence fpga_part]} {
        set fpga_part [dict get $accepted_environment_evidence fpga_part]
    } elseif {[dict exists $accepted_environment_evidence part]} {
        set fpga_part [dict get $accepted_environment_evidence part]
    } else {
        error {Accepted environment evidence is missing FPGA part identity.}
    }
    if {[string trim $fpga_part] eq {}} {
        error {Accepted environment FPGA part identity is empty.}
    }

    set required_ip_identities {}
    if {[dict exists $accepted_environment_evidence required_ip_identities]} {
        set required_ip_identities \
            [dict get $accepted_environment_evidence required_ip_identities]
    } elseif {[dict exists $accepted_environment_evidence \
        expected_environment required_ip_patterns]} {
        set required_ip_identities [dict get \
            $accepted_environment_evidence \
            expected_environment required_ip_patterns]
        if {[dict exists $accepted_environment_evidence \
            expected_environment custom_protection_ip vlnv]} {
            lappend required_ip_identities [dict get \
                $accepted_environment_evidence \
                expected_environment custom_protection_ip vlnv]
        } elseif {[dict exists $accepted_environment_evidence \
            custom_protection_ip_provenance vlnv]} {
            lappend required_ip_identities [dict get \
                $accepted_environment_evidence \
                custom_protection_ip_provenance vlnv]
        }
    } elseif {[dict exists \
        $accepted_environment_evidence resolved_ip_identities]} {
        foreach resolution [dict get \
            $accepted_environment_evidence resolved_ip_identities] {
            if {[catch {dict size $resolution}] ||
                ![dict exists $resolution resolved_vlnv]} {
                error {Accepted environment contains an invalid resolved IP identity.}
            }
            lappend required_ip_identities \
                [dict get $resolution resolved_vlnv]
        }
        if {[dict exists $accepted_environment_evidence \
            custom_protection_ip_provenance vlnv]} {
            lappend required_ip_identities [dict get \
                $accepted_environment_evidence \
                custom_protection_ip_provenance vlnv]
        }
    }
    if {[llength $required_ip_identities] == 0} {
        error {Accepted environment has no required IP identities.}
    }

    set seen [dict create]
    set normalized_ip_identities {}
    foreach identity $required_ip_identities {
        if {[string trim $identity] eq {}} {
            error {Accepted environment contains an empty required IP identity.}
        }
        if {[dict exists $seen $identity]} {
            error "Accepted environment contains a duplicate IP identity: $identity"
        }
        dict set seen $identity 1
        lappend normalized_ip_identities $identity
    }

    return [dict create \
        vivado_version [dict get \
            $accepted_environment_evidence vivado_version] \
        fpga_part $fpga_part \
        board_part [dict get $accepted_environment_evidence board_part] \
        required_ip_identities $normalized_ip_identities]
}

proc ::stage1d::controller_core::_validate_delivery_bundle_loader_result {
    loader_result
} {
    if {[catch {dict size $loader_result} loader_result_error]} {
        error "Delivery bundle loader result is not a dictionary: $loader_result_error"
    }
    foreach required_field {
        status
        bundle_identity
        profile_identity
        validated_scope
        errors
        warnings
    } {
        if {![dict exists $loader_result $required_field]} {
            error "Delivery bundle loader result is missing field: $required_field"
        }
    }
    if {[dict get $loader_result status] ni {PASS FAIL BLOCKED}} {
        error "Delivery bundle loader returned unsupported status: [dict get $loader_result status]"
    }
    foreach identity_field {bundle_identity profile_identity validated_scope} {
        if {[catch {
            dict size [dict get $loader_result $identity_field]
        } identity_error]} {
            error "Delivery bundle loader field $identity_field is invalid: $identity_error"
        }
    }
    foreach list_field {errors warnings} {
        if {[catch {llength [dict get $loader_result $list_field]} list_error]} {
            error "Delivery bundle loader field $list_field is invalid: $list_error"
        }
    }
    if {[dict get $loader_result status] eq {PASS}} {
        foreach required_identity {
            bundle_identity
            profile_identity
            validated_scope
        } {
            if {[dict size [dict get $loader_result $required_identity]] == 0} {
                error "PASS delivery bundle result has empty field: $required_identity"
            }
        }
    }
    return 1
}

proc ::stage1d::controller_core::_execution_bundle_identity_from_loader_result {
    loader_result
} {
    variable execution_bundle_identity_fields

    _validate_delivery_bundle_loader_result $loader_result
    if {[dict get $loader_result status] ne {PASS}} {
        error {Execution bundle identity requires a PASS loader result.}
    }

    set loader_bundle_identity [dict get $loader_result bundle_identity]
    set loader_profile_identity [dict get $loader_result profile_identity]
    foreach required_field {bundle_id manifest_sha256 profile_sha256} {
        if {![dict exists $loader_bundle_identity $required_field] ||
            [string trim [dict get \
                $loader_bundle_identity $required_field]] eq {}} {
            error "Validated loader bundle identity is missing field: $required_field"
        }
    }
    foreach required_field {profile_id profile_version profile_sha256} {
        if {![dict exists $loader_profile_identity $required_field] ||
            [string trim [dict get \
                $loader_profile_identity $required_field]] eq {}} {
            error "Validated loader profile identity is missing field: $required_field"
        }
    }
    if {[dict get $loader_bundle_identity profile_sha256] ne
        [dict get $loader_profile_identity profile_sha256]} {
        error {Validated loader bundle and profile fingerprints do not match.}
    }

    set bundle_identity [dict create \
        bundle_id [dict get $loader_bundle_identity bundle_id] \
        manifest_sha256 [dict get \
            $loader_bundle_identity manifest_sha256] \
        profile_sha256 [dict get \
            $loader_bundle_identity profile_sha256] \
        profile_id [dict get $loader_profile_identity profile_id] \
        profile_version [dict get \
            $loader_profile_identity profile_version]]
    if {[lsort [dict keys $bundle_identity]] ne
        [lsort $execution_bundle_identity_fields]} {
        error {Execution bundle identity does not match its contract.}
    }
    return $bundle_identity
}

proc ::stage1d::controller_core::_bundle_profile_selection_result {
    context
    status
    selection
    loader_invoked
    loader_result
    errors
    warnings
} {
    set execution_id [dict get \
        $context execution_identity execution_identifier]
    set bundle_identity {}
    set loader_profile_identity {}
    set validated_scope {}
    if {[dict size $loader_result] > 0} {
        if {[dict exists $loader_result bundle_identity]} {
            set bundle_identity [dict get $loader_result bundle_identity]
        }
        if {[dict exists $loader_result profile_identity]} {
            set loader_profile_identity \
                [dict get $loader_result profile_identity]
        }
        if {[dict exists $loader_result validated_scope]} {
            set validated_scope [dict get $loader_result validated_scope]
        }
    }

    set identity INVALID_DELIVERY_BUNDLE
    if {[dict size $loader_profile_identity] > 0 &&
        [dict exists $loader_profile_identity profile_id]} {
        set identity [dict get $loader_profile_identity profile_id]
    }
    set profile_source [dict create \
        selection DELIVERY_MANIFEST \
        manifest_name manifest.dict]
    if {[dict size $bundle_identity] > 0} {
        set profile_source $bundle_identity
    }
    set provenance [dict create \
        selection DELIVERY_MANIFEST \
        execution_id $execution_id \
        bundle_identity $bundle_identity \
        profile_identity $loader_profile_identity]
    set adapted_profile_identity [dict create \
        identity $identity \
        provenance $provenance \
        source $profile_source]

    set projected_environment_identity {}
    if {[dict exists $selection projected_environment_identity]} {
        set projected_environment_identity \
            [dict get $selection projected_environment_identity]
    }
    set selection_valid [expr {$status eq {PASS}}]
    return [_preflight_result \
        $status PROFILE_SELECTION $execution_id {} {} \
        $adapted_profile_identity {} $errors $warnings [dict create \
            profile_selected 1 \
            selected_scope $validated_scope \
            profile_provenance $provenance \
            profile_source $profile_source \
            PROFILE_SELECTION_VALID $selection_valid \
            DEFAULT_CLOSED_WITHOUT_PROFILE 0 \
            BUNDLE_SELECTION_EXPLICIT 1 \
            BUNDLE_SELECTION_PATH_BOUND [dict get \
                $selection BUNDLE_SELECTION_PATH_BOUND] \
            bundle_loader_invoked $loader_invoked \
            selected_manifest_path [dict get \
                $selection delivery_manifest_path] \
            delivery_bundle_root [dict get \
                $selection delivery_bundle_root] \
            bundle_identity $bundle_identity \
            profile_identity $loader_profile_identity \
            validated_scope $validated_scope \
            projected_environment_identity \
                $projected_environment_identity \
            bundle_loader_result $loader_result]]
}

proc ::stage1d::controller_core::resolve_delivery_bundle_profile {
    context
    source_evidence
    environment_evidence
} {
    set parsed_arguments [dict get $context parsed_arguments]
    if {[_delivery_manifest_argument $parsed_arguments] eq {}} {
        return [resolve_preflight_profile $context]
    }

    set fallback_selection [dict create \
        delivery_manifest_selected 1 \
        delivery_manifest_path \
            [_delivery_manifest_argument $parsed_arguments] \
        delivery_bundle_root {} \
        BUNDLE_SELECTION_EXPLICIT 1 \
        BUNDLE_SELECTION_PATH_BOUND 0]
    if {![dict exists $context input_validation_outputs] ||
        ![dict exists $context input_validation_outputs \
            delivery_manifest_selected] ||
        ![dict get $context input_validation_outputs \
            delivery_manifest_selected]} {
        set error_record [_preflight_error_record \
            BUNDLE_SELECTION_PATH_NOT_ACCEPTED \
            INPUT_VALIDATION \
            PROFILE_SELECTION \
            {Delivery bundle loading requires an accepted explicit manifest path.} \
            FIX_DELIVERY_MANIFEST_PATH]
        return [_bundle_profile_selection_result \
            $context BLOCKED $fallback_selection 0 {} \
            [list $error_record] {}]
    }

    set selection [dict create]
    foreach field {
        delivery_manifest_selected
        delivery_manifest_path
        delivery_bundle_root
        BUNDLE_SELECTION_EXPLICIT
        BUNDLE_SELECTION_PATH_BOUND
    } {
        dict set selection $field \
            [dict get $context input_validation_outputs $field]
    }

    if {[dict exists $context configuration dry_run_profile]} {
        set error_record [_preflight_error_record \
            DUAL_PROFILE_SELECTION_REJECTED \
            CONFIGURATION \
            PROFILE_SELECTION \
            {Delivery manifest and legacy dry_run_profile selections are mutually exclusive.} \
            REMOVE_ONE_PROFILE_SELECTION]
        return [_bundle_profile_selection_result \
            $context FAIL $selection 0 {} [list $error_record] {}]
    }

    set accepted_source_identity \
        [_accepted_source_identity $source_evidence]
    set accepted_environment_evidence \
        [_accepted_environment_identity $environment_evidence]
    if {[dict size $accepted_source_identity] == 0 ||
        [dict size $accepted_environment_evidence] == 0 ||
        ![dict exists $context workspace_preparation]} {
        set error_record [_preflight_error_record \
            BUNDLE_LOADING_PREREQUISITE_NOT_READY \
            DEPENDENCY \
            PROFILE_SELECTION \
            {Delivery bundle loading requires accepted source, environment, and workspace preparation results.} \
            COMPLETE_PREFLIGHT_PREREQUISITES]
        return [_bundle_profile_selection_result \
            $context BLOCKED $selection 0 {} [list $error_record] {}]
    }

    if {[catch {
        _project_loader_environment_identity \
            $accepted_environment_evidence
    } projected_environment_identity projection_options]} {
        set underlying_error {}
        if {[dict exists $projection_options -errorinfo]} {
            set underlying_error [dict get $projection_options -errorinfo]
        }
        set error_record [_preflight_error_record \
            ENVIRONMENT_PROJECTION_INVALID \
            CONTRACT \
            PROFILE_SELECTION \
            "Unable to project accepted environment identity: $projected_environment_identity" \
            REPEAT_ENVIRONMENT_VERIFICATION \
            $underlying_error]
        return [_bundle_profile_selection_result \
            $context FAIL $selection 0 {} [list $error_record] {}]
    }
    dict set selection projected_environment_identity \
        $projected_environment_identity

    if {[llength [info procs \
        ::stage1d::delivery_bundle_loader::load]] != 1} {
        set error_record [_preflight_error_record \
            DELIVERY_BUNDLE_LOADER_UNAVAILABLE \
            SOURCE \
            PROFILE_SELECTION \
            {Delivery bundle loader procedure is unavailable.} \
            LOAD_DELIVERY_BUNDLE_LOADER]
        return [_bundle_profile_selection_result \
            $context FAIL $selection 0 {} [list $error_record] {}]
    }

    set invocation_status [catch {
        ::stage1d::delivery_bundle_loader::load \
            [dict get $selection delivery_bundle_root] \
            $accepted_source_identity \
            $projected_environment_identity
    } loader_result loader_options]
    if {$invocation_status != 0} {
        set underlying_error {}
        if {[dict exists $loader_options -errorinfo]} {
            set underlying_error [dict get $loader_options -errorinfo]
        }
        set error_record [_preflight_error_record \
            DELIVERY_BUNDLE_LOADER_INVOCATION_FAILED \
            CORE \
            PROFILE_SELECTION \
            "Delivery bundle loader invocation failed: $loader_result" \
            FIX_DELIVERY_BUNDLE_LOADER \
            $underlying_error]
        return [_bundle_profile_selection_result \
            $context FAIL $selection 1 {} [list $error_record] {}]
    }
    if {[catch {
        _validate_delivery_bundle_loader_result $loader_result
    } result_error result_options]} {
        set underlying_error {}
        if {[dict exists $result_options -errorinfo]} {
            set underlying_error [dict get $result_options -errorinfo]
        }
        set error_record [_preflight_error_record \
            DELIVERY_BUNDLE_LOADER_RESULT_INVALID \
            CONTRACT \
            PROFILE_SELECTION \
            $result_error \
            FIX_DELIVERY_BUNDLE_LOADER \
            $underlying_error]
        return [_bundle_profile_selection_result \
            $context FAIL $selection 1 {} [list $error_record] {}]
    }

    return [_bundle_profile_selection_result \
        $context [dict get $loader_result status] $selection 1 \
        $loader_result [dict get $loader_result errors] \
        [dict get $loader_result warnings]]
}

proc ::stage1d::controller_core::_configured_closed_scope {configuration} {
    set mutation_operations 0
    if {[dict exists $configuration phase_scope mutation_operations]} {
        set mutation_operations [dict get \
            $configuration phase_scope mutation_operations]
    }
    return [dict create \
        phase_limit [dict get $configuration phase_limit] \
        project_operations [dict get \
            $configuration phase_scope project_operations] \
        design_operations [dict get \
            $configuration phase_scope design_operations] \
        mutation_operations $mutation_operations]
}

proc ::stage1d::controller_core::_normalize_scope {scope} {
    variable dry_run_scope_fields

    if {[catch {dict size $scope} scope_error]} {
        error "Dry-run scope is not a dictionary: $scope_error"
    }
    if {[lsort [dict keys $scope]] ne [lsort $dry_run_scope_fields]} {
        error {Dry-run scope does not contain the exact required fields.}
    }
    set normalized [dict create phase_limit [dict get $scope phase_limit]]
    foreach permission {
        project_operations
        design_operations
        mutation_operations
    } {
        set value [dict get $scope $permission]
        if {[string is boolean -strict $value]} {
            set normalized_value [expr {$value ? 1 : 0}]
        } elseif {[string equal -nocase $value ENABLED]} {
            set normalized_value 1
        } elseif {[string equal -nocase $value DISABLED]} {
            set normalized_value 0
        } else {
            error "Dry-run permission must be boolean or enabled/disabled: $permission=$value"
        }
        dict set normalized $permission $normalized_value
    }
    return $normalized
}

proc ::stage1d::controller_core::validate_preflight_scope {
    context
    profile_result
} {
    set phase EFFECTIVE_SCOPE_VALIDATION
    set configuration [dict get $context configuration]
    set execution_id [dict get \
        $context execution_identity execution_identifier]
    set profile_identity [dict get $profile_result profile_identity]
    set profile_status [dict get $profile_result status]

    if {$profile_status ne {PASS} &&
        [dict exists $profile_result outputs profile_selected] &&
        [dict get $profile_result outputs profile_selected]} {
        set error_record [_preflight_error_record \
            PROFILE_SCOPE_UNAVAILABLE \
            DEPENDENCY \
            $phase \
            {Effective scope cannot be validated because explicit profile selection did not pass.} \
            FIX_PROFILE_SELECTION]
        return [_preflight_result \
            $profile_status $phase $execution_id {} {} \
            $profile_identity {} \
            [list $error_record] {} [dict create \
                effective_scope {} \
                selected_scope {} \
                PROFILE_SCOPE_EFFECTIVE 0 \
                DEFAULT_CLOSED_WITHOUT_PROFILE 0]]
    }

    if {![dict get $profile_result outputs profile_selected]} {
        set closed_scope [_configured_closed_scope $configuration]
        set closed_valid 1
        if {[catch {
            set closed_scope [_normalize_scope $closed_scope]
        } closed_error]} {
            set closed_valid 0
        } elseif {[dict get $closed_scope phase_limit] ne {WORKSPACE_READY} ||
            [dict get $closed_scope project_operations] ||
            [dict get $closed_scope design_operations] ||
            [dict get $closed_scope mutation_operations]} {
            set closed_valid 0
            set closed_error \
                {Default configuration grants dry-run operations or exceeds WORKSPACE_READY.}
        }

        if {!$closed_valid} {
            set error_record [_preflight_error_record \
                DEFAULT_CONFIGURATION_NOT_CLOSED \
                AUTHORIZATION \
                $phase \
                "Default-closed validation failed: $closed_error" \
                RESTORE_DEFAULT_CLOSED_SCOPE]
            return [_preflight_result \
                FAIL $phase $execution_id {} {} $profile_identity {} \
                [list $error_record] {} [dict create \
                    effective_scope $closed_scope \
                    selected_scope {} \
                    PROFILE_SCOPE_EFFECTIVE 0 \
                    DEFAULT_CLOSED_WITHOUT_PROFILE 0]]
        }

        set blocked_error [_preflight_error_record \
            DRY_RUN_SCOPE_NOT_AUTHORIZED \
            AUTHORIZATION \
            $phase \
            {Default scope is closed; an explicit dry-run profile is required.} \
            SELECT_DRY_RUN_PROFILE]
        return [_preflight_result \
            BLOCKED $phase $execution_id {} {} $profile_identity {} \
            [list $blocked_error] {} [dict create \
                effective_scope $closed_scope \
                selected_scope {} \
                PROFILE_SCOPE_EFFECTIVE 0 \
                DEFAULT_CLOSED_WITHOUT_PROFILE 1]]
    }

    set selected_scope [dict get $profile_result outputs selected_scope]
    if {[catch {
        set effective_scope [_normalize_scope $selected_scope]
    } scope_error]} {
        set error_record [_preflight_error_record \
            INVALID_DRY_RUN_SCOPE \
            CONFIGURATION \
            $phase \
            "Selected dry-run scope is invalid: $scope_error" \
            FIX_PROFILE_SCOPE]
        return [_preflight_result \
            FAIL $phase $execution_id {} {} $profile_identity {} \
            [list $error_record] {} [dict create \
                effective_scope {} \
                selected_scope $selected_scope \
                PROFILE_SCOPE_EFFECTIVE 0 \
                DEFAULT_CLOSED_WITHOUT_PROFILE 0]]
    }

    set scope_errors {}
    if {[dict get $effective_scope phase_limit] ne {MUTATION_EXECUTE}} {
        lappend scope_errors \
            {phase_limit must equal MUTATION_EXECUTE for the controlled dry run}
    }
    foreach permission {
        project_operations
        design_operations
        mutation_operations
    } {
        if {![dict get $effective_scope $permission]} {
            lappend scope_errors "$permission must be enabled"
        }
    }
    if {[llength $scope_errors] > 0} {
        set error_record [_preflight_error_record \
            DRY_RUN_SCOPE_NOT_EFFECTIVE \
            AUTHORIZATION \
            $phase \
            "Selected dry-run scope is not effective: [join $scope_errors {; }]" \
            FIX_PROFILE_SCOPE]
        return [_preflight_result \
            FAIL $phase $execution_id {} {} $profile_identity {} \
            [list $error_record] {} [dict create \
                effective_scope $effective_scope \
                selected_scope $selected_scope \
                PROFILE_SCOPE_EFFECTIVE 0 \
                DEFAULT_CLOSED_WITHOUT_PROFILE 0]]
    }

    return [_preflight_result \
        PASS $phase $execution_id {} {} $profile_identity {} {} {} \
        [dict create \
            effective_scope $effective_scope \
            selected_scope $selected_scope \
            PROFILE_SCOPE_EFFECTIVE 1 \
            DEFAULT_CLOSED_WITHOUT_PROFILE 0]]
}

proc ::stage1d::controller_core::_accepted_source_identity {phase_evidence} {
    if {[catch {dict size $phase_evidence}] ||
        ![dict exists $phase_evidence status] ||
        [dict get $phase_evidence status] ne {PASS} ||
        ![dict exists $phase_evidence outputs source_state_frozen] ||
        ![dict get $phase_evidence outputs source_state_frozen]} {
        return {}
    }
    return [dict get $phase_evidence outputs]
}

proc ::stage1d::controller_core::_accepted_environment_identity {
    phase_evidence
} {
    if {[catch {dict size $phase_evidence}] ||
        ![dict exists $phase_evidence status] ||
        [dict get $phase_evidence status] ne {PASS} ||
        ![dict exists $phase_evidence outputs environment_verified] ||
        ![dict get $phase_evidence outputs environment_verified]} {
        return {}
    }
    return [dict get $phase_evidence outputs]
}

proc ::stage1d::controller_core::_accepted_workspace_identity {
    phase_evidence
} {
    if {[catch {dict size $phase_evidence}] ||
        ![dict exists $phase_evidence status] ||
        [dict get $phase_evidence status] ne {PASS} ||
        ![dict exists $phase_evidence outputs ownership_bound] ||
        ![dict get $phase_evidence outputs ownership_bound] ||
        ![dict exists $phase_evidence outputs ownership_binding]} {
        return {}
    }
    return [dict get $phase_evidence outputs ownership_binding]
}

proc ::stage1d::controller_core::_bind_preflight_identities {
    result
    source_identity
    environment_identity
    workspace_identity
} {
    dict set result source_identity $source_identity
    dict set result environment_identity $environment_identity
    dict set result workspace_identity $workspace_identity
    validate_preflight_result $result [dict get $result execution_id]
    return $result
}

proc ::stage1d::controller_core::_phase_marker_valid {
    check_name
    phase_outputs
    source_identity
    environment_identity
    workspace_identity
} {
    switch -- $check_name {
        SOURCE_IDENTITY_VALID {
            return [expr {
                [_preflight_identity_complete $source_identity] &&
                [dict exists $phase_outputs git_commit] &&
                [dict exists $phase_outputs controller_source_hash] &&
                [dict exists $phase_outputs source_state_frozen] &&
                [dict get $phase_outputs source_state_frozen]
            }]
        }
        ENVIRONMENT_IDENTITY_VALID {
            return [expr {
                [_preflight_identity_complete $environment_identity] &&
                [dict exists $phase_outputs environment_evidence_hash] &&
                [dict exists $phase_outputs vivado_identity_verified] &&
                [dict get $phase_outputs vivado_identity_verified] &&
                [dict exists $phase_outputs target_identity_verified] &&
                [dict get $phase_outputs target_identity_verified] &&
                [dict exists $phase_outputs environment_verified] &&
                [dict get $phase_outputs environment_verified]
            }]
        }
        WORKSPACE_ISOLATION_VALID {
            return [expr {
                [_preflight_identity_complete $workspace_identity] &&
                [dict exists $phase_outputs workspace_created] &&
                [dict get $phase_outputs workspace_created] &&
                [dict exists $phase_outputs ownership_bound] &&
                [dict get $phase_outputs ownership_bound] &&
                [dict exists $phase_outputs repository_separation_verified] &&
                [dict get $phase_outputs repository_separation_verified] &&
                [dict exists $phase_outputs artifact_storage_separation_verified] &&
                [dict get $phase_outputs artifact_storage_separation_verified] &&
                [dict exists $phase_outputs artifacts_generated] &&
                ![dict get $phase_outputs artifacts_generated] &&
                [dict exists $phase_outputs project_created] &&
                ![dict get $phase_outputs project_created]
            }]
        }
        default {
            error "Unsupported preflight component check: $check_name"
        }
    }
}

proc ::stage1d::controller_core::preflight_phase_component_result {
    phase
    check_name
    phase_evidence
    execution_id
    profile_identity
    source_identity
    environment_identity
    workspace_identity
} {
    set phase_evidence_invalid [catch {
        set phase_evidence_size [dict size $phase_evidence]
    }]
    if {!$phase_evidence_invalid &&
        ($phase_evidence_size == 0 ||
            ![dict exists $phase_evidence status])} {
        set phase_evidence_invalid 1
    }
    if {$phase_evidence_invalid} {
        set blocked_error [_preflight_error_record \
            PREFLIGHT_COMPONENT_NOT_EXECUTED \
            DEPENDENCY \
            $phase \
            "Required preflight component did not execute: $phase" \
            COMPLETE_PREREQUISITE]
        return [_preflight_result \
            BLOCKED $phase $execution_id $source_identity \
            $environment_identity $profile_identity $workspace_identity \
            [list $blocked_error] {} [dict create \
                check_name $check_name \
                $check_name 0 \
                phase_outputs {}]]
    }

    set status [dict get $phase_evidence status]
    if {$status eq {SKIPPED_DEPENDENCY}} {
        set status BLOCKED
    }
    if {$status ni {PASS FAIL BLOCKED}} {
        set status FAIL
    }
    set errors {}
    if {[dict exists $phase_evidence errors]} {
        set errors [dict get $phase_evidence errors]
    }
    set warnings {}
    if {[dict exists $phase_evidence outputs warnings]} {
        set warnings [dict get $phase_evidence outputs warnings]
    }
    set phase_outputs {}
    if {[dict exists $phase_evidence outputs]} {
        set phase_outputs [dict get $phase_evidence outputs]
    }

    set marker_valid 0
    if {$status eq {PASS}} {
        if {![dict exists $phase_evidence execution_identifier] ||
            [dict get $phase_evidence execution_identifier] ne $execution_id} {
            set status FAIL
            lappend errors [_preflight_error_record \
                PREFLIGHT_COMPONENT_EXECUTION_ID_MISMATCH \
                PROVENANCE \
                $phase \
                {Component evidence execution identifier does not match the current execution.} \
                NONE]
        } elseif {![_phase_marker_valid \
            $check_name $phase_outputs $source_identity \
            $environment_identity $workspace_identity]} {
            set status FAIL
            lappend errors [_preflight_error_record \
                PREFLIGHT_COMPONENT_IDENTITY_INVALID \
                PROVENANCE \
                $phase \
                "Required component identity or readiness marker is invalid: $check_name" \
                REPEAT_VERIFICATION]
        } else {
            set marker_valid 1
        }
    }

    return [_preflight_result \
        $status $phase $execution_id $source_identity $environment_identity \
        $profile_identity $workspace_identity $errors $warnings [dict create \
            check_name $check_name \
            $check_name $marker_valid \
            phase_outputs $phase_outputs]]
}

proc ::stage1d::controller_core::verify_preflight_execution_context {
    context
    profile_result
    scope_result
    source_result
    environment_result
    workspace_result
} {
    set phase EXECUTION_CONTEXT_VERIFICATION
    set execution_id [dict get \
        $context execution_identity execution_identifier]
    set source_identity [dict get $source_result source_identity]
    set environment_identity [dict get \
        $environment_result environment_identity]
    set profile_identity [dict get $profile_result profile_identity]
    set workspace_identity [dict get $workspace_result workspace_identity]
    set bundle_selection_explicit [expr {
        [dict exists $profile_result outputs BUNDLE_SELECTION_EXPLICIT] &&
        [dict get $profile_result outputs BUNDLE_SELECTION_EXPLICIT]
    }]
    set execution_bundle_identity {}
    set bundle_evidence {}
    set bundle_identity_context_bound [expr {!$bundle_selection_explicit}]
    set bundle_evidence_execution_match [expr {!$bundle_selection_explicit}]
    set bundle_profile_scope_context_match [expr {!$bundle_selection_explicit}]

    foreach result [list $profile_result $scope_result $source_result \
        $environment_result $workspace_result] {
        if {[dict get $result status] eq {FAIL}} {
            set error_record [_preflight_error_record \
                EXECUTION_CONTEXT_PREREQUISITE_FAILED \
                DEPENDENCY \
                $phase \
                {Execution context cannot be accepted because a prerequisite failed.} \
                REPEAT_PREFLIGHT]
            return [_preflight_result \
                FAIL $phase $execution_id $source_identity \
                $environment_identity $profile_identity $workspace_identity \
                [list $error_record] {} [dict create \
                    EXECUTION_CONTEXT_VALID 0 \
                    execution_context {} \
                    BUNDLE_IDENTITY_CONTEXT_BOUND \
                        $bundle_identity_context_bound \
                    BUNDLE_EVIDENCE_EXECUTION_MATCH \
                        $bundle_evidence_execution_match \
                    BUNDLE_PROFILE_SCOPE_CONTEXT_MATCH \
                        $bundle_profile_scope_context_match \
                    bundle_evidence $bundle_evidence]]
        }
    }
    foreach result [list $source_result $environment_result $workspace_result] {
        if {[dict get $result status] ne {PASS}} {
            set error_record [_preflight_error_record \
                EXECUTION_CONTEXT_PREREQUISITE_BLOCKED \
                DEPENDENCY \
                $phase \
                {Execution context cannot be evaluated until identity prerequisites pass.} \
                COMPLETE_PREREQUISITE]
            return [_preflight_result \
                BLOCKED $phase $execution_id $source_identity \
                $environment_identity $profile_identity $workspace_identity \
                [list $error_record] {} [dict create \
                    EXECUTION_CONTEXT_VALID 0 \
                    execution_context {} \
                    BUNDLE_IDENTITY_CONTEXT_BOUND \
                        $bundle_identity_context_bound \
                    BUNDLE_EVIDENCE_EXECUTION_MATCH \
                        $bundle_evidence_execution_match \
                    BUNDLE_PROFILE_SCOPE_CONTEXT_MATCH \
                        $bundle_profile_scope_context_match \
                    bundle_evidence $bundle_evidence]]
        }
    }

    set validation_errors {}
    if {![dict exists $source_identity execution_identity_evidence execution_identifier] ||
        [dict get $source_identity \
            execution_identity_evidence execution_identifier] ne $execution_id} {
        lappend validation_errors {source execution identity does not match}
    }
    if {![dict exists $workspace_identity execution_identifier] ||
        [dict get $workspace_identity execution_identifier] ne $execution_id} {
        lappend validation_errors {workspace execution identity does not match}
    }
    if {![_preflight_identity_complete $profile_identity]} {
        lappend validation_errors {profile identity is incomplete}
    }
    if {![dict exists $profile_identity provenance execution_id] ||
        [dict get $profile_identity provenance execution_id] ne $execution_id} {
        lappend validation_errors {profile execution identity does not match}
    }

    set loader_result_valid 0
    set loader_result {}
    if {$bundle_selection_explicit} {
        if {![dict exists $context delivery_bundle_loading]} {
            lappend validation_errors \
                {controller context does not retain the accepted bundle result}
        } else {
            set loader_result [dict get $context delivery_bundle_loading]
            if {[catch {
                _validate_delivery_bundle_loader_result $loader_result
            } loader_result_error]} {
                lappend validation_errors \
                    "retained delivery bundle result is invalid: $loader_result_error"
            } elseif {[dict get $loader_result status] ne {PASS}} {
                lappend validation_errors \
                    {retained delivery bundle result is not accepted}
            } else {
                set loader_result_valid 1
            }
        }

        if {$loader_result_valid} {
            set identity_inputs_match 1
            if {[catch {
                set execution_bundle_identity \
                    [_execution_bundle_identity_from_loader_result \
                        $loader_result]
            } identity_error]} {
                set identity_inputs_match 0
                lappend validation_errors \
                    "validated execution bundle identity is invalid: $identity_error"
            }

            set loader_bundle_identity [dict get \
                $loader_result bundle_identity]
            set loader_profile_identity [dict get \
                $loader_result profile_identity]
            if {![dict exists $profile_result outputs bundle_loader_result] ||
                [dict get $profile_result outputs bundle_loader_result] ne
                    $loader_result} {
                set identity_inputs_match 0
                lappend validation_errors \
                    {profile selection does not retain the validated loader result}
            }
            if {![dict exists $profile_result outputs bundle_identity] ||
                [dict get $profile_result outputs bundle_identity] ne
                    $loader_bundle_identity} {
                set identity_inputs_match 0
                lappend validation_errors \
                    {profile selection bundle identity does not match the loader result}
            }
            if {![dict exists $profile_result outputs profile_identity] ||
                [dict get $profile_result outputs profile_identity] ne
                    $loader_profile_identity} {
                set identity_inputs_match 0
                lappend validation_errors \
                    {profile selection identity does not match the loader result}
            }
            if {![dict exists $profile_identity source] ||
                [dict get $profile_identity source] ne
                    $loader_bundle_identity} {
                set identity_inputs_match 0
                lappend validation_errors \
                    {profile source does not match validated bundle identity}
            }
            if {![dict exists $profile_identity provenance bundle_identity] ||
                [dict get $profile_identity provenance bundle_identity] ne
                    $loader_bundle_identity} {
                set identity_inputs_match 0
                lappend validation_errors \
                    {profile provenance does not bind validated bundle identity}
            }
            if {![dict exists $profile_identity provenance profile_identity] ||
                [dict get $profile_identity provenance profile_identity] ne
                    $loader_profile_identity} {
                set identity_inputs_match 0
                lappend validation_errors \
                    {profile provenance does not bind validated profile identity}
            }
            if {![dict exists $profile_identity identity] ||
                ![dict exists $loader_profile_identity profile_id] ||
                [dict get $profile_identity identity] ne
                    [dict get $loader_profile_identity profile_id]} {
                set identity_inputs_match 0
                lappend validation_errors \
                    {selected profile identity does not match the loader result}
            }
            if {$identity_inputs_match} {
                set bundle_identity_context_bound 1
            }

            set selected_manifest_path {}
            set evidence_inputs_match 1
            if {![dict exists $context input_validation_outputs \
                delivery_manifest_path] ||
                [string trim [dict get $context input_validation_outputs \
                    delivery_manifest_path]] eq {}} {
                set evidence_inputs_match 0
                lappend validation_errors \
                    {accepted selected manifest path is missing}
            } else {
                set selected_manifest_path [dict get \
                    $context input_validation_outputs delivery_manifest_path]
            }
            if {![dict exists $profile_result outputs \
                selected_manifest_path] ||
                [dict get $profile_result outputs selected_manifest_path] ne
                    $selected_manifest_path} {
                set evidence_inputs_match 0
                lappend validation_errors \
                    {profile selection manifest path does not match accepted input}
            }
            if {![dict exists $profile_identity provenance execution_id] ||
                [dict get $profile_identity provenance execution_id] ne
                    $execution_id} {
                set evidence_inputs_match 0
            }
            if {!$bundle_identity_context_bound} {
                set evidence_inputs_match 0
            }
            if {$evidence_inputs_match} {
                set bundle_evidence [dict create \
                    selected_manifest_path $selected_manifest_path \
                    bundle_identity $execution_bundle_identity \
                    execution_id $execution_id]
                set bundle_evidence_execution_match 1
            }
        }
    } elseif {![dict exists $profile_identity source] ||
        [dict get $profile_identity source] ne
            [_profile_configuration_path [dict get $context configuration]]} {
        lappend validation_errors {profile source does not match selected configuration}
    }
    if {![dict exists $scope_result outputs effective_scope]} {
        lappend validation_errors {effective permissions are missing}
        set effective_scope {}
    } else {
        set effective_scope [dict get $scope_result outputs effective_scope]
    }
    if {$bundle_selection_explicit && $loader_result_valid} {
        set scope_inputs_match 1
        set loader_scope_valid 1
        set loader_validated_scope {}
        if {[catch {
            set loader_validated_scope [_normalize_scope \
                [dict get $loader_result validated_scope]]
            set normalized_effective_scope \
                [_normalize_scope $effective_scope]
        } scope_binding_error]} {
            set scope_inputs_match 0
            set loader_scope_valid 0
            lappend validation_errors \
                "bundle scope binding is invalid: $scope_binding_error"
        }
        if {$scope_inputs_match &&
            $loader_validated_scope ne $normalized_effective_scope} {
            set scope_inputs_match 0
            lappend validation_errors \
                {effective scope does not match loader validated scope}
        }
        foreach profile_scope_field {validated_scope selected_scope} {
            if {![dict exists $profile_result outputs $profile_scope_field]} {
                set scope_inputs_match 0
                lappend validation_errors \
                    "profile selection is missing $profile_scope_field"
                continue
            }
            if {[catch {
                set normalized_profile_scope [_normalize_scope \
                    [dict get $profile_result outputs $profile_scope_field]]
            } profile_scope_error]} {
                set scope_inputs_match 0
                lappend validation_errors \
                    "profile selection $profile_scope_field is invalid: $profile_scope_error"
            } elseif {$loader_scope_valid &&
                $normalized_profile_scope ne $loader_validated_scope} {
                set scope_inputs_match 0
                lappend validation_errors \
                    "profile selection $profile_scope_field does not match loader validated scope"
            }
        }
        if {$scope_inputs_match} {
            set bundle_profile_scope_context_match 1
        }
    }

    set workspace_outputs [dict get $workspace_result outputs phase_outputs]
    if {![dict exists $workspace_outputs execution_workspace]} {
        lappend validation_errors {workspace root is missing}
        set workspace_root {}
    } else {
        set workspace_root [file normalize \
            [dict get $workspace_outputs execution_workspace]]
    }
    set project_path {}
    set evidence_dir {}
    if {$workspace_root ne {}} {
        set project_path [file normalize [file join $workspace_root \
            [dict get $context configuration lifecycle project_relative_path]]]
        set evidence_dir [file normalize \
            [file join $workspace_root execution_state]]
        if {![_is_equal_or_descendant $project_path $workspace_root]} {
            lappend validation_errors {project path escapes workspace root}
        }
        if {![_is_equal_or_descendant $evidence_dir $workspace_root]} {
            lappend validation_errors {evidence path escapes workspace root}
        }
    }

    if {[dict exists $workspace_identity git_commit] &&
        [dict exists $source_identity git_commit] &&
        [dict get $workspace_identity git_commit] ne
            [dict get $source_identity git_commit]} {
        lappend validation_errors {workspace source identity does not match}
    }
    if {[dict exists $workspace_identity environment_evidence_hash] &&
        [dict exists $environment_identity environment_evidence_hash] &&
        [dict get $workspace_identity environment_evidence_hash] ne
            [dict get $environment_identity environment_evidence_hash]} {
        lappend validation_errors {workspace environment identity does not match}
    }

    if {[llength $validation_errors] > 0} {
        set error_record [_preflight_error_record \
            EXECUTION_CONTEXT_INVALID \
            PROVENANCE \
            $phase \
            "Execution context validation failed: [join $validation_errors {; }]" \
            REPEAT_PREFLIGHT]
        return [_preflight_result \
            FAIL $phase $execution_id $source_identity \
            $environment_identity $profile_identity $workspace_identity \
            [list $error_record] {} [dict create \
                EXECUTION_CONTEXT_VALID 0 \
                execution_context {} \
                BUNDLE_IDENTITY_CONTEXT_BOUND \
                    $bundle_identity_context_bound \
                BUNDLE_EVIDENCE_EXECUTION_MATCH \
                    $bundle_evidence_execution_match \
                BUNDLE_PROFILE_SCOPE_CONTEXT_MATCH \
                    $bundle_profile_scope_context_match \
                bundle_evidence $bundle_evidence]]
    }

    set execution_context [dict create \
        execution_id $execution_id \
        authorization [dict create \
            status NOT_AUTHORIZED \
            authority controller_core \
            operation dry_run_preflight \
            boundary READINESS_ONLY] \
        workspace_root $workspace_root \
        project_path $project_path \
        bd_name [dict get $context configuration lifecycle bd_name] \
        evidence_dir $evidence_dir \
        bundle_identity $execution_bundle_identity \
        source_identity $source_identity \
        environment_identity $environment_identity]
    return [_preflight_result \
        PASS $phase $execution_id $source_identity $environment_identity \
        $profile_identity $workspace_identity {} {} [dict create \
            EXECUTION_CONTEXT_VALID 1 \
            execution_context $execution_context \
            effective_permissions $effective_scope \
            BUNDLE_IDENTITY_CONTEXT_BOUND \
                $bundle_identity_context_bound \
            BUNDLE_EVIDENCE_EXECUTION_MATCH \
                $bundle_evidence_execution_match \
            BUNDLE_PROFILE_SCOPE_CONTEXT_MATCH \
                $bundle_profile_scope_context_match \
            bundle_evidence $bundle_evidence]]
}

proc ::stage1d::controller_core::validate_preflight_aggregate {
    aggregate
    {expected_execution_id {}}
} {
    variable preflight_aggregate_fields
    variable preflight_required_phases
    variable preflight_statuses

    if {[catch {dict size $aggregate} aggregate_error]} {
        error "Preflight aggregate is not a dictionary: $aggregate_error"
    }
    if {[lsort [dict keys $aggregate]] ne
        [lsort $preflight_aggregate_fields]} {
        error {Preflight aggregate does not match the aggregate result schema.}
    }
    if {[dict get $aggregate overall_status] ni $preflight_statuses} {
        error "Unsupported aggregate status: [dict get $aggregate overall_status]"
    }
    set execution_id [dict get $aggregate execution_id]
    if {[string trim $execution_id] eq {}} {
        error {Preflight aggregate execution_id must not be empty.}
    }
    if {$expected_execution_id ne {} && $execution_id ne $expected_execution_id} {
        error "Aggregate execution_id mismatch: expected=$expected_execution_id actual=$execution_id"
    }
    foreach identity_field {
        profile_identity
        source_identity
        environment_identity
        workspace_identity
    } {
        if {[catch {
            dict size [dict get $aggregate $identity_field]
        } identity_error]} {
            error "Aggregate field $identity_field is not a dictionary: $identity_error"
        }
    }
    foreach list_field {component_results errors warnings} {
        if {[catch {llength [dict get $aggregate $list_field]} list_error]} {
            error "Aggregate field $list_field is not a list: $list_error"
        }
    }
    if {[llength [dict get $aggregate component_results]] == 0} {
        error {Preflight aggregate must contain component results.}
    }
    set component_phases {}
    foreach component [dict get $aggregate component_results] {
        validate_preflight_result $component $execution_id \
            [expr {[dict get $aggregate overall_status] eq {PASS}}]
        lappend component_phases [dict get $component phase]
    }
    if {[lrange $component_phases 0 end] ne
        [lrange $preflight_required_phases 0 end]} {
        error {Preflight aggregate does not contain the complete ordered component set.}
    }
    if {[dict get $aggregate overall_status] eq {PASS}} {
        foreach identity_field {
            profile_identity
            source_identity
            environment_identity
            workspace_identity
        } {
            if {[dict size [dict get $aggregate $identity_field]] == 0} {
                error "PASS aggregate has incomplete identity: $identity_field"
            }
        }
    }
    return 1
}

proc ::stage1d::controller_core::aggregate_preflight_results {
    component_results
} {
    variable preflight_required_phases

    if {[llength $component_results] == 0} {
        error {Cannot aggregate an empty preflight result set.}
    }

    set component_phases {}
    foreach component $component_results {
        if {[catch {dict get $component phase} component_phase]} {
            error {Preflight component is missing its phase identity.}
        }
        lappend component_phases $component_phase
    }
    if {[lrange $component_phases 0 end] ne
        [lrange $preflight_required_phases 0 end]} {
        error {Cannot aggregate a partial or unordered preflight result set.}
    }

    set first_result [lindex $component_results 0]
    validate_preflight_result $first_result
    set execution_id [dict get $first_result execution_id]
    set blocked_seen 0
    set fail_seen 0
    set errors {}
    set warnings {}
    set identities [dict create \
        profile_identity {} \
        source_identity {} \
        environment_identity {} \
        workspace_identity {}]

    foreach component $component_results {
        validate_preflight_result $component $execution_id
        switch -- [dict get $component status] {
            BLOCKED { set blocked_seen 1 }
            FAIL { set fail_seen 1 }
        }
        foreach error_record [dict get $component errors] {
            lappend errors $error_record
        }
        foreach warning_record [dict get $component warnings] {
            lappend warnings $warning_record
        }
        foreach identity_field {
            profile_identity
            source_identity
            environment_identity
            workspace_identity
        } {
            set candidate [dict get $component $identity_field]
            if {[dict size $candidate] == 0} {
                continue
            }
            set accepted [dict get $identities $identity_field]
            if {[dict size $accepted] == 0} {
                dict set identities $identity_field $candidate
            } elseif {$candidate ne $accepted} {
                set fail_seen 1
                lappend errors [_preflight_error_record \
                    PREFLIGHT_IDENTITY_MISMATCH \
                    PROVENANCE \
                    PREFLIGHT_AGGREGATION \
                    "Component results disagree on $identity_field." \
                    REPEAT_PREFLIGHT]
            }
        }
    }

    if {!$blocked_seen && !$fail_seen} {
        foreach identity_field {
            profile_identity
            source_identity
            environment_identity
            workspace_identity
        } {
            if {[dict size [dict get $identities $identity_field]] == 0} {
                set fail_seen 1
                lappend errors [_preflight_error_record \
                    PREFLIGHT_IDENTITY_INCOMPLETE \
                    PROVENANCE \
                    PREFLIGHT_AGGREGATION \
                    "All-PASS preflight is missing $identity_field." \
                    REPEAT_PREFLIGHT]
            }
        }
    }

    if {$blocked_seen} {
        set overall_status BLOCKED
    } elseif {$fail_seen} {
        set overall_status FAIL
    } else {
        set overall_status PASS
    }

    set aggregate [dict create \
        overall_status $overall_status \
        execution_id $execution_id \
        profile_identity [dict get $identities profile_identity] \
        source_identity [dict get $identities source_identity] \
        environment_identity [dict get $identities environment_identity] \
        workspace_identity [dict get $identities workspace_identity] \
        component_results $component_results \
        errors $errors \
        warnings $warnings]
    validate_preflight_aggregate $aggregate $execution_id
    return $aggregate
}

proc ::stage1d::controller_core::build_preflight_readiness {
    context
    profile_result
    scope_result
    source_evidence
    environment_evidence
    workspace_evidence
} {
    set execution_id [dict get \
        $context execution_identity execution_identifier]
    set source_identity [_accepted_source_identity $source_evidence]
    set environment_identity \
        [_accepted_environment_identity $environment_evidence]
    set workspace_identity \
        [_accepted_workspace_identity $workspace_evidence]

    set profile_result [_bind_preflight_identities \
        $profile_result $source_identity $environment_identity \
        $workspace_identity]
    set scope_result [_bind_preflight_identities \
        $scope_result $source_identity $environment_identity \
        $workspace_identity]
    set profile_identity [dict get $profile_result profile_identity]

    set source_result [preflight_phase_component_result \
        SOURCE_VERIFICATION SOURCE_IDENTITY_VALID $source_evidence \
        $execution_id $profile_identity $source_identity \
        $environment_identity $workspace_identity]
    set environment_result [preflight_phase_component_result \
        ENVIRONMENT_VERIFICATION ENVIRONMENT_IDENTITY_VALID \
        $environment_evidence $execution_id $profile_identity \
        $source_identity $environment_identity $workspace_identity]
    set workspace_result [preflight_phase_component_result \
        WORKSPACE_VERIFICATION WORKSPACE_ISOLATION_VALID \
        $workspace_evidence $execution_id $profile_identity \
        $source_identity $environment_identity $workspace_identity]
    set execution_context_result [verify_preflight_execution_context \
        $context $profile_result $scope_result $source_result \
        $environment_result $workspace_result]

    return [aggregate_preflight_results [list \
        $profile_result \
        $scope_result \
        $source_result \
        $environment_result \
        $workspace_result \
        $execution_context_result]]
}

proc ::stage1d::controller_core::_static_readiness_error_record {
    error_code
    category
    message
    underlying_error
    recoverability
} {
    variable static_readiness_phase
    return [dict create \
        error_code $error_code \
        category $category \
        phase_name $static_readiness_phase \
        message $message \
        underlying_error $underlying_error \
        evidence_references {} \
        recoverability $recoverability]
}

proc ::stage1d::controller_core::_static_readiness_component_result {
    result_name
    status
    errors
    warnings
    outputs
} {
    variable static_readiness_statuses
    if {$status ni $static_readiness_statuses} {
        error "Unsupported static readiness component status: $status"
    }
    if {[catch {llength $errors} errors_error]} {
        error "Static readiness component errors are not a list: $errors_error"
    }
    if {[catch {llength $warnings} warnings_error]} {
        error "Static readiness component warnings are not a list: $warnings_error"
    }
    if {[catch {dict size $outputs} outputs_error]} {
        error "Static readiness component outputs are not a dictionary: $outputs_error"
    }

    set outputs [dict merge $outputs [dict create \
        $result_name [expr {$status eq {PASS}}]]]
    return [dict create \
        status $status \
        result $result_name \
        errors $errors \
        warnings $warnings \
        outputs $outputs]
}

# Static readiness uses Tcl introspection only. This helper validates procedure
# availability, argument order, and optional defaults without invoking the
# inspected procedure.
proc ::stage1d::controller_core::_static_procedure_contract {
    procedure
    expected_arguments
    {expected_defaults {}}
} {
    set procedure_namespace [namespace qualifiers $procedure]
    if {$procedure_namespace eq {} || ![namespace exists $procedure_namespace]} {
        error "Required namespace is unavailable: $procedure_namespace"
    }
    if {[llength [info procs $procedure]] != 1} {
        error "Required procedure is unavailable: $procedure"
    }

    set actual_arguments [info args $procedure]
    if {$actual_arguments ne $expected_arguments} {
        error "Procedure interface mismatch for $procedure: expected={$expected_arguments} actual={$actual_arguments}"
    }
    if {[catch {dict size $expected_defaults} defaults_error]} {
        error "Expected procedure defaults are not a dictionary: $defaults_error"
    }

    set actual_defaults [dict create]
    foreach argument $actual_arguments {
        set has_default [info default $procedure $argument actual_default]
        set expects_default [dict exists $expected_defaults $argument]
        if {$has_default != $expects_default} {
            error "Procedure default contract mismatch for $procedure argument $argument"
        }
        if {$has_default} {
            set expected_default [dict get $expected_defaults $argument]
            if {$actual_default ne $expected_default} {
                error "Procedure default value mismatch for $procedure argument $argument"
            }
            dict set actual_defaults $argument $actual_default
        }
    }

    return [dict create \
        procedure $procedure \
        arguments $actual_arguments \
        defaults $actual_defaults]
}

proc ::stage1d::controller_core::_static_procedure_declares_fields {
    procedure
    required_fields
} {
    if {[llength [info procs $procedure]] != 1} {
        error "Required result boundary is unavailable: $procedure"
    }
    set procedure_body [info body $procedure]
    set missing_fields {}
    foreach field $required_fields {
        set field_pattern [format \
            {(^|[^[:alnum:]_])%s([^[:alnum:]_]|$)} $field]
        if {![regexp -- $field_pattern $procedure_body]} {
            lappend missing_fields $field
        }
    }
    if {[llength $missing_fields] > 0} {
        error "Result boundary $procedure does not declare required fields: [join $missing_fields {, }]"
    }
    return 1
}

proc ::stage1d::controller_core::_static_preflight_component {
    preflight_result
    phase
} {
    foreach component [dict get $preflight_result component_results] {
        if {[dict get $component phase] eq $phase} {
            return $component
        }
    }
    error "Preflight result is missing required component: $phase"
}

proc ::stage1d::controller_core::_verify_profile_static_readiness {
    preflight_result
} {
    set result_name PROFILE_STATIC_READY
    validate_preflight_aggregate $preflight_result

    set profile_result [_static_preflight_component \
        $preflight_result PROFILE_SELECTION]
    set scope_result [_static_preflight_component \
        $preflight_result EFFECTIVE_SCOPE_VALIDATION]

    set prerequisite_status PASS
    foreach component [list $profile_result $scope_result] {
        if {[dict get $component status] eq {FAIL}} {
            set prerequisite_status FAIL
        } elseif {[dict get $component status] eq {BLOCKED} &&
            $prerequisite_status eq {PASS}} {
            set prerequisite_status BLOCKED
        }
    }
    if {$prerequisite_status ne {PASS}} {
        set error_record [_static_readiness_error_record \
            PROFILE_STATIC_PREREQUISITE_NOT_READY \
            PROFILE \
            {Profile identity, provenance, and effective scope are not all accepted by preflight.} \
            {} \
            SELECT_VALID_PROFILE]
        return [_static_readiness_component_result \
            $result_name $prerequisite_status [list $error_record] {} \
            [dict create \
                profile_status [dict get $profile_result status] \
                scope_status [dict get $scope_result status]]]
    }

    set validation_errors {}
    set profile_identity [dict get $profile_result profile_identity]
    foreach required_field {identity provenance source} {
        if {![dict exists $profile_identity $required_field] ||
            [string trim [dict get $profile_identity $required_field]] eq {}} {
            lappend validation_errors \
                "profile identity is missing $required_field"
        }
    }
    if {![dict exists $profile_result outputs profile_selected] ||
        ![dict get $profile_result outputs profile_selected]} {
        lappend validation_errors {profile selection is not explicit}
    }
    if {![dict exists $profile_result outputs PROFILE_SELECTION_VALID] ||
        ![dict get $profile_result outputs PROFILE_SELECTION_VALID]} {
        lappend validation_errors {profile selection marker is not valid}
    }
    if {![dict exists $scope_result outputs PROFILE_SCOPE_EFFECTIVE] ||
        ![dict get $scope_result outputs PROFILE_SCOPE_EFFECTIVE]} {
        lappend validation_errors {effective scope marker is not valid}
    }
    if {[dict get $preflight_result profile_identity] ne $profile_identity} {
        lappend validation_errors \
            {aggregate profile identity does not match profile selection}
    }

    set profile_provenance [dict get $profile_identity provenance]
    set provenance_status [catch {
        set profile_provenance_size [dict size $profile_provenance]
    } provenance_error]
    if {$provenance_status != 0} {
        lappend validation_errors \
            "profile provenance is invalid: $provenance_error"
    } elseif {$profile_provenance_size == 0} {
        lappend validation_errors {profile provenance is empty}
    }
    if {![dict exists $profile_result outputs profile_provenance] ||
        [dict get $profile_result outputs profile_provenance] ne
            $profile_provenance} {
        lappend validation_errors \
            {profile provenance does not match the selected profile}
    }

    set effective_scope [dict get $scope_result outputs effective_scope]
    set selected_scope [dict get $profile_result outputs selected_scope]
    if {[catch {
        set normalized_selected_scope [_normalize_scope $selected_scope]
        set normalized_effective_scope [_normalize_scope $effective_scope]
    } scope_error]} {
        lappend validation_errors "profile scope is invalid: $scope_error"
    } elseif {$normalized_selected_scope ne $normalized_effective_scope} {
        lappend validation_errors \
            {effective scope does not match the selected profile scope}
    }

    if {[llength $validation_errors] > 0} {
        set error_record [_static_readiness_error_record \
            PROFILE_STATIC_CONTRACT_MISMATCH \
            CONTRACT \
            "Profile static readiness failed: [join $validation_errors {; }]" \
            {} \
            FIX_PROFILE_CONTRACT]
        return [_static_readiness_component_result \
            $result_name FAIL [list $error_record] {} [dict create \
                profile_identity $profile_identity \
                profile_provenance $profile_provenance \
                effective_scope $effective_scope]]
    }

    return [_static_readiness_component_result \
        $result_name PASS {} {} [dict create \
            profile_identity $profile_identity \
            profile_provenance $profile_provenance \
            effective_scope $normalized_effective_scope]]
}

proc ::stage1d::controller_core::_verify_controller_static_readiness {
    preflight_result
} {
    variable bundle_aware_preflight_checks
    variable bundle_aware_preflight_result_fields
    variable execution_context_fields
    variable execution_bundle_identity_fields
    variable execution_provenance_fields
    set result_name CONTROLLER_STATIC_READY
    validate_preflight_aggregate $preflight_result

    set procedure_contracts {}
    foreach specification [list \
        [list ::stage1d::controller_core::main {arguments} {}] \
        [list ::stage1d::controller_core::execution_context_contract {} {}] \
        [list ::stage1d::controller_core::bundle_aware_preflight_contract \
            {} {}] \
        [list ::stage1d::controller_core::verify_bundle_aware_preflight \
            {context authorization_evidence_context} {}] \
        [list ::stage1d::controller_core::verify_preflight_execution_context \
            {context profile_result scope_result source_result environment_result workspace_result} {}] \
        [list ::stage1d::controller_core::aggregate_preflight_results \
            {component_results} {}] \
        [list ::stage1d::controller_core::validate_preflight_aggregate \
            {aggregate expected_execution_id} \
            [dict create expected_execution_id {}]]] {
        lassign $specification procedure arguments defaults
        lappend procedure_contracts [_static_procedure_contract \
            $procedure $arguments $defaults]
    }

    set context_result [_static_preflight_component \
        $preflight_result EXECUTION_CONTEXT_VERIFICATION]
    if {[dict get $context_result status] ne {PASS}} {
        set status [dict get $context_result status]
        set error_record [_static_readiness_error_record \
            EXECUTION_CONTEXT_STATIC_PREREQUISITE_NOT_READY \
            CONTROLLER \
            {The accepted preflight execution context is unavailable.} \
            {} \
            COMPLETE_PREFLIGHT]
        return [_static_readiness_component_result \
            $result_name $status [list $error_record] {} [dict create \
                procedure_contracts $procedure_contracts \
                execution_context_available 0]]
    }

    set validation_errors {}
    if {![dict exists $context_result outputs EXECUTION_CONTEXT_VALID] ||
        ![dict get $context_result outputs EXECUTION_CONTEXT_VALID] ||
        ![dict exists $context_result outputs execution_context]} {
        lappend validation_errors \
            {preflight execution context contract is not accepted}
        set execution_context {}
    } else {
        set execution_context [dict get \
            $context_result outputs execution_context]
    }
    set bundle_binding_checks {
        BUNDLE_IDENTITY_CONTEXT_BOUND
        BUNDLE_EVIDENCE_EXECUTION_MATCH
        BUNDLE_PROFILE_SCOPE_CONTEXT_MATCH
    }
    foreach binding_check $bundle_binding_checks {
        if {![dict exists $context_result outputs $binding_check] ||
            ![dict get $context_result outputs $binding_check]} {
            lappend validation_errors \
                "execution context bundle binding check failed: $binding_check"
        }
    }
    set execution_context_status [catch {
        set execution_context_size [dict size $execution_context]
    } execution_context_error]
    if {$execution_context_status != 0} {
        lappend validation_errors \
            "execution context is not a dictionary: $execution_context_error"
    } elseif {[lsort [dict keys $execution_context]] ne
        [lsort $execution_context_fields]} {
        lappend validation_errors \
            {execution context does not contain the exact required fields}
    } elseif {$execution_context_size > 0} {
        if {[dict get $execution_context execution_id] ne
            [dict get $preflight_result execution_id]} {
            lappend validation_errors \
                {execution context is bound to a different execution}
        }
        set authorization [dict get $execution_context authorization]
        set expected_authorization [dict create \
            status NOT_AUTHORIZED \
            authority controller_core \
            operation dry_run_preflight \
            boundary READINESS_ONLY]
        if {$authorization ne $expected_authorization} {
            lappend validation_errors \
                {preflight execution context contains unexpected authorization}
        }
        set bundle_identity [dict get $execution_context bundle_identity]
        if {[catch {
            set bundle_identity_size [dict size $bundle_identity]
        } bundle_identity_error]} {
            lappend validation_errors \
                "execution bundle identity is not a dictionary: $bundle_identity_error"
        } elseif {$bundle_identity_size > 0} {
            if {[lsort [dict keys $bundle_identity]] ne
                [lsort $execution_bundle_identity_fields]} {
                lappend validation_errors \
                    {execution bundle identity does not contain the exact required fields}
            }
            foreach identity_field $execution_bundle_identity_fields {
                if {![dict exists $bundle_identity $identity_field] ||
                    [string trim [dict get \
                        $bundle_identity $identity_field]] eq {}} {
                    lappend validation_errors \
                        "execution bundle identity field is empty: $identity_field"
                }
            }
            if {![dict exists $context_result outputs bundle_evidence] ||
                ![dict exists $context_result outputs bundle_evidence \
                    bundle_identity] ||
                [dict get $context_result outputs bundle_evidence \
                    bundle_identity] ne $bundle_identity ||
                ![dict exists $context_result outputs bundle_evidence \
                    execution_id] ||
                [dict get $context_result outputs bundle_evidence \
                    execution_id] ne [dict get \
                        $execution_context execution_id] ||
                ![dict exists $context_result outputs bundle_evidence \
                    selected_manifest_path] ||
                [string trim [dict get $context_result outputs \
                    bundle_evidence selected_manifest_path]] eq {}} {
                lappend validation_errors \
                    {execution bundle evidence does not match its context}
            }
        } elseif {[dict exists $context_result outputs bundle_evidence] &&
            [dict size [dict get \
                $context_result outputs bundle_evidence]] > 0} {
            lappend validation_errors \
                {legacy execution context contains unexpected bundle evidence}
        }
    }

    set context_contract [execution_context_contract]
    if {[lsort [dict get $context_contract fields]] ne
        [lsort $execution_context_fields]} {
        lappend validation_errors \
            {declared execution context contract does not match controller fields}
    }

    set bundle_preflight_contract [bundle_aware_preflight_contract]
    set expected_bundle_preflight_contract_fields {
        schema_version
        result_fields
        provenance_fields
        checks
        owner
        authorization_assertion_generated
    }
    if {[lrange [dict keys $bundle_preflight_contract] 0 end] ne
            [lrange $expected_bundle_preflight_contract_fields 0 end] ||
        [dict get $bundle_preflight_contract schema_version] ne {v1} ||
        [dict get $bundle_preflight_contract result_fields] ne
            $bundle_aware_preflight_result_fields ||
        [dict get $bundle_preflight_contract provenance_fields] ne
            $execution_provenance_fields ||
        [dict get $bundle_preflight_contract checks] ne
            $bundle_aware_preflight_checks ||
        [dict get $bundle_preflight_contract owner] ne {controller_core} ||
        [dict get $bundle_preflight_contract \
            authorization_assertion_generated]} {
        lappend validation_errors \
            {bundle-aware preflight contract does not match controller fields}
    }
    set bundle_preflight_body [info body \
        ::stage1d::controller_core::verify_bundle_aware_preflight]
    foreach forbidden_procedure {
        create_mutation_authorization_assertion
        create_mutation_authorization_evidence
    } {
        if {[string first $forbidden_procedure \
            $bundle_preflight_body] >= 0} {
            lappend validation_errors \
                "bundle-aware preflight generates authorization through: $forbidden_procedure"
        }
    }

    if {[llength $validation_errors] > 0} {
        set error_record [_static_readiness_error_record \
            CONTROLLER_STATIC_CONTRACT_MISMATCH \
            CONTRACT \
            "Controller static readiness failed: [join $validation_errors {; }]" \
            {} \
            FIX_CONTROLLER_CONTRACT]
        return [_static_readiness_component_result \
            $result_name FAIL [list $error_record] {} [dict create \
                controller_entrypoint ::stage1d::controller_core::main \
                procedure_contracts $procedure_contracts \
                execution_context_contract $context_contract \
                bundle_binding_checks $bundle_binding_checks \
                bundle_aware_preflight_contract \
                    $bundle_preflight_contract \
                preflight_aggregation_boundary \
                    ::stage1d::controller_core::aggregate_preflight_results]]
    }

    return [_static_readiness_component_result \
        $result_name PASS {} {} [dict create \
            controller_entrypoint ::stage1d::controller_core::main \
            procedure_contracts $procedure_contracts \
            execution_context_contract $context_contract \
            bundle_binding_checks $bundle_binding_checks \
            bundle_aware_preflight_contract $bundle_preflight_contract \
            preflight_aggregation_boundary \
                ::stage1d::controller_core::aggregate_preflight_results \
            execution_context_authorized 0]]
}

proc ::stage1d::controller_core::_verify_lifecycle_adapter_static_readiness {} {
    variable lifecycle_result_fields
    set result_name LIFECYCLE_ADAPTER_STATIC_READY

    foreach required_namespace {
        ::stage1d::vivado_project
        ::stage1d::bd_flow
    } {
        if {![namespace exists $required_namespace]} {
            error "Required lifecycle namespace is unavailable: $required_namespace"
        }
    }

    set vivado_project_procedures {}
    foreach specification {
        {::stage1d::vivado_project::open {context}}
        {::stage1d::vivado_project::close {context}}
        {::stage1d::vivado_project::cleanup {context reason}}
    } {
        lassign $specification procedure arguments
        lappend vivado_project_procedures \
            [_static_procedure_contract $procedure $arguments]
    }
    set vivado_project_result [_static_procedure_contract \
        ::stage1d::vivado_project::_result \
        {status context errors outputs warnings} \
        [dict create warnings {}]]
    _static_procedure_declares_fields \
        ::stage1d::vivado_project::_result $lifecycle_result_fields

    set bd_flow_procedures {}
    foreach specification {
        {::stage1d::bd_flow::open {context}}
        {::stage1d::bd_flow::validate {context}}
        {::stage1d::bd_flow::save {context}}
    } {
        lassign $specification procedure arguments
        lappend bd_flow_procedures \
            [_static_procedure_contract $procedure $arguments]
    }
    set bd_flow_result [_static_procedure_contract \
        ::stage1d::bd_flow::_result \
        {status context errors outputs warnings} \
        [dict create warnings {}]]
    _static_procedure_declares_fields \
        ::stage1d::bd_flow::_result $lifecycle_result_fields

    return [_static_readiness_component_result \
        $result_name PASS {} {} [dict create \
            vivado_project [dict create \
                namespace ::stage1d::vivado_project \
                lifecycle_procedures $vivado_project_procedures \
                result_boundary $vivado_project_result \
                result_fields $lifecycle_result_fields] \
            bd_flow [dict create \
                namespace ::stage1d::bd_flow \
                lifecycle_procedures $bd_flow_procedures \
                result_boundary $bd_flow_result \
                result_fields $lifecycle_result_fields] \
            lifecycle_procedures_invoked 0]]
}

proc ::stage1d::controller_core::_verify_authorization_static_readiness {} {
    variable authorization_assertion_fields
    variable authorization_evidence_context_fields
    variable authorization_evidence_checks
    set result_name AUTHORIZATION_STATIC_READY

    set procedure_contracts [list \
        [_static_procedure_contract \
            ::stage1d::controller_core::authorization_assertion_schema {}] \
        [_static_procedure_contract \
            ::stage1d::controller_core::create_mutation_authorization_assertion \
            {context}] \
        [_static_procedure_contract \
            ::stage1d::controller_core::authorization_evidence_context_contract \
            {}] \
        [_static_procedure_contract \
            ::stage1d::controller_core::create_mutation_authorization_evidence \
            {context}] \
        [_static_procedure_contract \
            ::stage1d::controller_core::validate_authorization_evidence_context \
            {context authorization_evidence_context}] \
        [_static_procedure_contract \
            ::stage1d::controller_core::_mutation_assertion_allows \
            {authorization_assertion}] \
        [_static_procedure_contract \
            ::stage1d_controlled_stimulus::_validate_authorization_assertion \
            {context}]]

    set assertion_schema [authorization_assertion_schema]
    set expected_schema_keys {
        schema_version
        fields
        owner
        validation_boundary
    }
    if {[lsort [dict keys $assertion_schema]] ne
        [lsort $expected_schema_keys] ||
        [dict get $assertion_schema schema_version] ne {v1} ||
        [lsort [dict get $assertion_schema fields]] ne
            [lsort $authorization_assertion_fields] ||
        [dict get $assertion_schema owner] ne {controller_core} ||
        [dict get $assertion_schema validation_boundary] ne
            {::stage1d_controlled_stimulus::_validate_authorization_assertion}} {
        error {Authorization assertion schema does not match the approved contract.}
    }
    _static_procedure_declares_fields \
        ::stage1d::controller_core::create_mutation_authorization_assertion \
        $authorization_assertion_fields
    _static_procedure_declares_fields \
        ::stage1d_controlled_stimulus::_validate_authorization_assertion \
        $authorization_assertion_fields

    set evidence_context_contract \
        [authorization_evidence_context_contract]
    set expected_evidence_contract_keys {
        schema_version
        fields
        checks
        owner
        authorization_assertion_fields
    }
    if {[lsort [dict keys $evidence_context_contract]] ne
            [lsort $expected_evidence_contract_keys] ||
        [dict get $evidence_context_contract schema_version] ne {v1} ||
        [lsort [dict get $evidence_context_contract fields]] ne
            [lsort $authorization_evidence_context_fields] ||
        [dict get $evidence_context_contract checks] ne
            $authorization_evidence_checks ||
        [dict get $evidence_context_contract owner] ne {controller_core} ||
        [lsort [dict get $evidence_context_contract \
            authorization_assertion_fields]] ne
            [lsort $authorization_assertion_fields]} {
        error {Authorization evidence context does not match the approved contract.}
    }
    _static_procedure_declares_fields \
        ::stage1d::controller_core::create_mutation_authorization_evidence \
        $authorization_evidence_context_fields

    return [_static_readiness_component_result \
        $result_name PASS {} {} [dict create \
            authorization_assertion_schema $assertion_schema \
            authorization_evidence_context_contract \
                $evidence_context_contract \
            procedure_contracts $procedure_contracts \
            authorization_evidence_context_generated 0 \
            authorization_assertion_generated 0 \
            allow_decision_generated 0]]
}

proc ::stage1d::controller_core::_verify_mutation_boundary_static_readiness {} {
    variable mutation_context_fields
    variable mutation_result_fields
    set result_name MUTATION_BOUNDARY_STATIC_READY

    if {![namespace exists ::stage1d_controlled_stimulus]} {
        error {Required mutation namespace is unavailable: ::stage1d_controlled_stimulus}
    }
    set apply_contract [_static_procedure_contract \
        ::stage1d_controlled_stimulus::apply {context}]
    set controller_projection_contract [_static_procedure_contract \
        ::stage1d::controller_core::create_mutation_context \
        {context authorization_assertion} \
        [dict create authorization_assertion {}]]

    set interface_contract [mutation_interface_contract]
    if {[dict get $interface_contract procedure] ne
            {::stage1d_controlled_stimulus::apply} ||
        [dict get $interface_contract arguments] ne {context} ||
        [lsort [dict get $interface_contract context_fields]] ne
            [lsort $mutation_context_fields] ||
        [lsort [dict get $interface_contract result_fields]] ne
            [lsort $mutation_result_fields]} {
        error {Mutation boundary does not match the approved interface contract.}
    }

    return [_static_readiness_component_result \
        $result_name PASS {} {} [dict create \
            mutation_namespace ::stage1d_controlled_stimulus \
            apply_contract $apply_contract \
            controller_projection_contract $controller_projection_contract \
            interface_contract $interface_contract \
            mutation_invoked 0]]
}

proc ::stage1d::controller_core::_verify_static_side_effect_free {
    side_effect_state
} {
    variable static_side_effect_fields
    set result_name STATIC_SIDE_EFFECT_FREE

    if {[catch {dict size $side_effect_state} state_error]} {
        error "Static side-effect state is not a dictionary: $state_error"
    }
    if {[lsort [dict keys $side_effect_state]] ne
        [lsort $static_side_effect_fields]} {
        error {Static side-effect state does not contain the exact required counters.}
    }

    set invalid_counters {}
    set forbidden_operations_detected {}
    foreach field $static_side_effect_fields {
        set value [dict get $side_effect_state $field]
        if {![string is integer -strict $value] || $value < 0} {
            lappend invalid_counters $field
        } elseif {$value != 0} {
            lappend forbidden_operations_detected $field
        }
    }
    if {[llength $invalid_counters] > 0 ||
        [llength $forbidden_operations_detected] > 0} {
        set error_record [_static_readiness_error_record \
            STATIC_SIDE_EFFECT_DETECTED \
            SIDE_EFFECT \
            "Static readiness detected invalid counters {[join $invalid_counters {, }]} or forbidden operations {[join $forbidden_operations_detected {, }]}" \
            {} \
            RESET_WITHOUT_EXECUTION]
        return [_static_readiness_component_result \
            $result_name FAIL [list $error_record] {} [dict create \
                side_effect_state $side_effect_state \
                invalid_counters $invalid_counters \
                forbidden_operations_detected $forbidden_operations_detected]]
    }

    return [_static_readiness_component_result \
        $result_name PASS {} {} [dict create \
            side_effect_state $side_effect_state \
            forbidden_operations_detected {} \
            project_opened 0 \
            bd_opened 0 \
            mutation_invoked 0 \
            bd_validation_invoked 0 \
            bd_save_invoked 0 \
            artifacts_generated 0 \
            vivado_invoked 0]]
}

proc ::stage1d::controller_core::_static_readiness_overall_status {
    component_results
} {
    set overall_status PASS
    foreach component $component_results {
        set component_status [dict get $component status]
        if {$component_status eq {FAIL}} {
            return FAIL
        }
        if {$component_status eq {BLOCKED}} {
            set overall_status BLOCKED
        }
    }
    return $overall_status
}

proc ::stage1d::controller_core::_static_result_order_stable {
    component_results
} {
    variable static_readiness_ordered_components

    set ordered_component_count \
        [llength $static_readiness_ordered_components]
    if {[llength $component_results] < $ordered_component_count} {
        return 0
    }

    set observed_order {}
    foreach component [lrange \
        $component_results 0 [expr {$ordered_component_count - 1}]] {
        if {[catch {dict get $component result} result_name]} {
            return 0
        }
        lappend observed_order $result_name
    }
    return [expr {
        [lrange $observed_order 0 end] eq
        [lrange $static_readiness_ordered_components 0 end]
    }]
}

proc ::stage1d::controller_core::_run_static_readiness_component {
    result_name
    command
} {
    set command_status [catch {{*}$command} component_result command_options]
    if {$command_status != 0} {
        set underlying_error {}
        if {[dict exists $command_options -errorinfo]} {
            set underlying_error [dict get $command_options -errorinfo]
        }
        set error_record [_static_readiness_error_record \
            "${result_name}_CHECK_FAILED" \
            CONTRACT \
            "Static readiness check $result_name failed: $component_result" \
            $underlying_error \
            FIX_STATIC_CONTRACT]
        return [_static_readiness_component_result \
            $result_name FAIL [list $error_record] {} {}]
    }
    if {[dict get $component_result result] ne $result_name} {
        error "Static readiness callback returned the wrong result marker: expected=$result_name actual=[dict get $component_result result]"
    }
    return $component_result
}

proc ::stage1d::controller_core::validate_static_readiness_result {
    result
    {expected_execution_id {}}
} {
    variable static_readiness_phase
    variable static_readiness_statuses
    variable static_readiness_result_fields
    variable static_readiness_component_fields
    variable static_readiness_required_results
    variable static_readiness_ordered_components

    if {[catch {dict size $result} result_error]} {
        error "Static readiness result is not a dictionary: $result_error"
    }
    if {[lsort [dict keys $result]] ne
        [lsort $static_readiness_result_fields]} {
        error {Static readiness result does not match the controller evidence schema.}
    }
    if {[dict get $result status] ni $static_readiness_statuses} {
        error "Unsupported static readiness status: [dict get $result status]"
    }
    if {[dict get $result phase] ne $static_readiness_phase} {
        error "Static readiness phase mismatch: [dict get $result phase]"
    }
    set execution_id [dict get $result execution_id]
    if {[string trim $execution_id] eq {}} {
        error {Static readiness execution_id must not be empty.}
    }
    if {$expected_execution_id ne {} && $execution_id ne $expected_execution_id} {
        error "Static readiness execution_id mismatch: expected=$expected_execution_id actual=$execution_id"
    }
    foreach list_field {component_results errors warnings} {
        if {[catch {llength [dict get $result $list_field]} list_error]} {
            error "Static readiness field $list_field is not a list: $list_error"
        }
    }
    if {[catch {dict size [dict get $result outputs]} outputs_error]} {
        error "Static readiness outputs are not a dictionary: $outputs_error"
    }

    set observed_results {}
    foreach component [dict get $result component_results] {
        if {[catch {dict size $component} component_error]} {
            error "Static readiness component is not a dictionary: $component_error"
        }
        if {[lsort [dict keys $component]] ne
            [lsort $static_readiness_component_fields]} {
            error {Static readiness component does not match its result schema.}
        }
        set component_status [dict get $component status]
        set result_name [dict get $component result]
        if {$component_status ni $static_readiness_statuses} {
            error "Unsupported static readiness component status: $component_status"
        }
        foreach list_field {errors warnings} {
            if {[catch {llength [dict get $component $list_field]} list_error]} {
                error "Static readiness component field $list_field is not a list: $list_error"
            }
        }
        set component_outputs [dict get $component outputs]
        if {[catch {dict size $component_outputs} component_outputs_error]} {
            error "Static readiness component outputs are not a dictionary: $component_outputs_error"
        }
        if {![dict exists $component_outputs $result_name] ||
            ![string is boolean -strict \
                [dict get $component_outputs $result_name]] ||
            [expr {[dict get $component_outputs $result_name] ? 1 : 0}] !=
                [expr {$component_status eq {PASS}}]} {
            error "Static readiness marker does not match component status: $result_name"
        }
        lappend observed_results $result_name
    }
    set result_order_stable [_static_result_order_stable \
        [dict get $result component_results]]
    if {![dict exists $result outputs STATIC_RESULT_ORDER_STABLE] ||
        ![string is boolean -strict \
            [dict get $result outputs STATIC_RESULT_ORDER_STABLE]] ||
        [expr {[dict get $result outputs STATIC_RESULT_ORDER_STABLE] ? 1 : 0}] !=
            $result_order_stable} {
        error {STATIC_RESULT_ORDER_STABLE does not match the component result order.}
    }
    if {!$result_order_stable} {
        error "Static readiness component order is not stable: expected={[lrange $static_readiness_ordered_components 0 end]} observed={[lrange $observed_results 0 [expr {[llength $static_readiness_ordered_components] - 1}]]}"
    }
    if {[lrange $observed_results 0 end] ne
        [lrange $static_readiness_required_results 0 end]} {
        error {Static readiness result does not contain the complete ordered component set.}
    }

    set expected_status [_static_readiness_overall_status \
        [dict get $result component_results]]
    if {[dict get $result status] ne $expected_status} {
        error "Static readiness aggregate status mismatch: expected=$expected_status actual=[dict get $result status]"
    }
    set component_index 0
    foreach result_name $static_readiness_required_results {
        if {![dict exists $result outputs $result_name]} {
            error "Static readiness aggregate is missing marker: $result_name"
        }
        set aggregate_marker [dict get $result outputs $result_name]
        set component_marker [dict get \
            [lindex [dict get $result component_results] $component_index] \
            outputs $result_name]
        if {![string is boolean -strict $aggregate_marker] ||
            [expr {$aggregate_marker ? 1 : 0}] !=
                [expr {$component_marker ? 1 : 0}]} {
            error "Static readiness aggregate marker mismatch: $result_name"
        }
        incr component_index
    }
    if {![dict exists $result outputs static_readiness_ready] ||
        ![string is boolean -strict \
            [dict get $result outputs static_readiness_ready]] ||
        [expr {[dict get $result outputs static_readiness_ready] ? 1 : 0}] !=
            [expr {[dict get $result status] eq {PASS}}]} {
        error {Static readiness ready marker does not match aggregate status.}
    }
    return 1
}

proc ::stage1d::controller_core::run_static_readiness {
    context
    preflight_result
    side_effect_state
} {
    variable static_readiness_phase
    variable static_readiness_required_results
    variable static_readiness_ordered_components

    if {[catch {dict size $context} context_error]} {
        error "Static readiness context is not a dictionary: $context_error"
    }
    set execution_id [dict get \
        $context execution_identity execution_identifier]
    if {[string trim $execution_id] eq {}} {
        error {Static readiness requires a nonempty execution_id.}
    }

    set component_commands [dict create \
        PROFILE_STATIC_READY [list \
            ::stage1d::controller_core::_verify_profile_static_readiness \
            $preflight_result] \
        CONTROLLER_STATIC_READY [list \
            ::stage1d::controller_core::_verify_controller_static_readiness \
            $preflight_result] \
        LIFECYCLE_ADAPTER_STATIC_READY [list \
            ::stage1d::controller_core::_verify_lifecycle_adapter_static_readiness] \
        AUTHORIZATION_STATIC_READY [list \
            ::stage1d::controller_core::_verify_authorization_static_readiness] \
        MUTATION_BOUNDARY_STATIC_READY [list \
            ::stage1d::controller_core::_verify_mutation_boundary_static_readiness] \
        STATIC_SIDE_EFFECT_FREE [list \
            ::stage1d::controller_core::_verify_static_side_effect_free \
            $side_effect_state]]

    set component_results {}
    set errors {}
    set warnings {}
    set available_component_boundaries [dict create]
    set outputs [dict create \
        static_readiness_ready 0 \
        execution_authorized 0 \
        authorization_assertion_generated 0 \
        allow_decision_generated 0 \
        lifecycle_procedures_invoked 0 \
        mutation_invoked 0 \
        vivado_invoked 0 \
        artifacts_generated 0 \
        STATIC_RESULT_ORDER_STABLE 0 \
        static_result_order \
            [lrange $static_readiness_ordered_components 0 end]]

    foreach result_name $static_readiness_required_results {
        set component_result [_run_static_readiness_component \
            $result_name [dict get $component_commands $result_name]]
        lappend component_results $component_result
        set errors [concat $errors [dict get $component_result errors]]
        set warnings [concat $warnings [dict get $component_result warnings]]
        set component_outputs [dict get $component_result outputs]
        dict set outputs $result_name \
            [dict get $component_outputs $result_name]
        dict set available_component_boundaries \
            $result_name $component_outputs
    }

    dict set outputs STATIC_RESULT_ORDER_STABLE \
        [_static_result_order_stable $component_results]
    set status [_static_readiness_overall_status $component_results]
    dict set outputs static_readiness_ready [expr {$status eq {PASS}}]
    dict set outputs available_component_boundaries \
        $available_component_boundaries

    set result [dict create \
        status $status \
        phase $static_readiness_phase \
        execution_id $execution_id \
        component_results $component_results \
        errors $errors \
        warnings $warnings \
        outputs $outputs]
    validate_static_readiness_result $result $execution_id
    return $result
}

proc ::stage1d::controller_core::phase2_scope_boundary {context} {
    set phase_name phase2_scope_boundary
    set boundary_error [dict create \
        error_code PHASE2_SCOPE_BOUNDARY \
        category SCOPE \
        phase_name $phase_name \
        message {Phase 2 verification is complete; project creation and all later lifecycle phases are not implemented.} \
        underlying_error {} \
        evidence_references {} \
        recoverability IMPLEMENT_LATER_PHASE]

    return [dict create \
        status BLOCKED \
        evidence_locations {} \
        logs {} \
        reports {} \
        errors [list $boundary_error] \
        outputs [dict create \
            phase2_verification_ready 1 \
            next_required_state PROJECT_READY \
            workspace_created [dict get $context workspace_preparation workspace_created] \
            vivado_invoked 0 \
            artifacts_generated 0 \
            manifest_published 0] \
        artifact_references {}]
}

proc ::stage1d::controller_core::main {arguments} {
    variable controller_version
    variable controller_api_version
    variable execution_id_schema_version
    variable phase_evidence_schema_version

    set parsed_arguments [::stage1d::argument_parser::parse $arguments]
    if {[dict get $parsed_arguments help]} {
        puts [::stage1d::argument_parser::usage]
        return [dict create \
            controller_version $controller_version \
            controller_api_version $controller_api_version \
            decision HELP \
            exit_code 0]
    }

    set configuration [::stage1d::configuration_loader::load \
        [dict get $parsed_arguments configuration_path] \
        [supported_configuration_versions]]
    _validate_configuration_identity $configuration

    set execution_identity [generate_execution_identity \
        [dict get $parsed_arguments candidate_git_commit]]
    set execution_identifier [dict get $execution_identity execution_identifier]

    set state [::stage1d::state_manager::new \
        $execution_identifier \
        $execution_id_schema_version \
        $controller_version \
        $controller_api_version]
    set logger [::stage1d::logger::new \
        $execution_identifier \
        $execution_id_schema_version \
        $controller_version \
        $controller_api_version]

    set initialized_log [::stage1d::logger::record \
        logger \
        controller_core \
        INFO \
        CONTROLLER_INITIALIZED \
        "Controller initialized with execution identifier $execution_identifier"]
    ::stage1d::logger::emit $initialized_log

    set context [dict create \
        parsed_arguments $parsed_arguments \
        configuration $configuration \
        execution_identity $execution_identity \
        phase_evidence_schema_version $phase_evidence_schema_version]
    set profile_result [resolve_preflight_profile $context]
    set scope_result [validate_preflight_scope $context $profile_result]
    set phase_evidence {}
    set source_evidence {}
    set environment_evidence {}
    set workspace_evidence {}
    set workspace_created 0
    set vivado_invoked 0
    set artifacts_generated 0
    set mutation_invoked 0
    set mutation_phase_status NOT_REACHED
    set bd_validation_status NOT_REACHED
    set bd_save_status NOT_REACHED
    set static_readiness_result {}
    set static_readiness_status NOT_REACHED

    set input_evidence [::stage1d::phase_runner::run \
        state \
        logger \
        input_validation \
        INPUT_VALIDATION \
        [list ::stage1d::controller_core::phase_input_validation] \
        $context]
    lappend phase_evidence $input_evidence

    if {[::stage1d::state_manager::current $state] eq {INPUT_VALIDATION}} {
        dict set context input_validation_outputs [dict get $input_evidence outputs]
        set source_evidence [::stage1d::phase_runner::run \
            state \
            logger \
            source_verification \
            SOURCE_VERIFIED \
            [list ::stage1d::source_check::run] \
            $context]
        lappend phase_evidence $source_evidence
    }

    if {[::stage1d::state_manager::current $state] eq {SOURCE_VERIFIED}} {
        dict set context source_verification [dict get $source_evidence outputs]
        set environment_evidence [::stage1d::phase_runner::run \
            state \
            logger \
            environment_verification \
            ENVIRONMENT_VERIFIED \
            [list ::stage1d::environment_check::run] \
            $context]
        lappend phase_evidence $environment_evidence
    }

    if {[::stage1d::state_manager::current $state] eq {ENVIRONMENT_VERIFIED}} {
        dict set context environment_verification [dict get $environment_evidence outputs]
        set workspace_evidence [::stage1d::phase_runner::run \
            state \
            logger \
            workspace_preparation \
            WORKSPACE_READY \
            [list ::stage1d::workspace_manager::run] \
            $context]
        lappend phase_evidence $workspace_evidence
        if {[dict exists $workspace_evidence outputs workspace_created]} {
            set workspace_created [dict get $workspace_evidence outputs workspace_created]
        }
    }

    if {[::stage1d::state_manager::current $state] eq {WORKSPACE_READY}} {
        dict set context workspace_preparation [dict get $workspace_evidence outputs]
    }

    if {[_delivery_manifest_argument $parsed_arguments] ne {}} {
        set profile_result [resolve_delivery_bundle_profile \
            $context $source_evidence $environment_evidence]
        set scope_result [validate_preflight_scope $context $profile_result]
        if {[dict exists $profile_result outputs bundle_loader_result] &&
            [dict size [dict get \
                $profile_result outputs bundle_loader_result]] > 0} {
            dict set context delivery_bundle_loading [dict get \
                $profile_result outputs bundle_loader_result]
        }
    }

    set preflight_result [build_preflight_readiness \
        $context $profile_result $scope_result $source_evidence \
        $environment_evidence $workspace_evidence]
    dict set context preflight_result $preflight_result
    set preflight_status [dict get $preflight_result overall_status]
    switch -- $preflight_status {
        PASS { set preflight_severity INFO }
        BLOCKED { set preflight_severity WARNING }
        default { set preflight_severity ERROR }
    }
    set preflight_log [::stage1d::logger::record \
        logger \
        preflight \
        $preflight_severity \
        PREFLIGHT_READINESS_RESULT \
        "Preflight readiness result: $preflight_status"]
    ::stage1d::logger::emit $preflight_log

    set static_side_effect_state [dict create \
        project_open_count 0 \
        bd_open_count 0 \
        mutation_invocation_count $mutation_invoked \
        bd_validation_count 0 \
        bd_save_count 0 \
        artifact_generation_count $artifacts_generated \
        vivado_invocation_count $vivado_invoked]
    set static_readiness_result [run_static_readiness \
        $context $preflight_result $static_side_effect_state]
    set static_readiness_status [dict get $static_readiness_result status]
    switch -- $static_readiness_status {
        PASS { set static_readiness_severity INFO }
        BLOCKED { set static_readiness_severity WARNING }
        default { set static_readiness_severity ERROR }
    }
    set static_readiness_log [::stage1d::logger::record \
        logger \
        static_readiness \
        $static_readiness_severity \
        STATIC_READINESS_RESULT \
        "Static readiness result: $static_readiness_status"]
    ::stage1d::logger::emit $static_readiness_log

    set evidence_completeness [_verification_evidence_completeness $phase_evidence]
    set publication_gate [_unpublished_publication_gate]
    set decision [::stage1d::decision_engine::evaluate \
        $state \
        $phase_evidence \
        $evidence_completeness \
        $publication_gate]
    set final_decision [dict get $decision decision]
    switch -- $final_decision {
        FAIL { set decision_severity ERROR }
        BLOCKED { set decision_severity WARNING }
        default { set decision_severity INFO }
    }
    set decision_log [::stage1d::logger::record \
        logger \
        decision_engine \
        $decision_severity \
        FINAL_DECISION \
        "Controller decision: $final_decision"]
    ::stage1d::logger::emit $decision_log

    return [dict create \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        execution_id_schema_version $execution_id_schema_version \
        execution_identifier $execution_identifier \
        execution_identity $execution_identity \
        decision $final_decision \
        decision_evidence $decision \
        evidence_completeness $evidence_completeness \
        publication_gate $publication_gate \
        current_state [::stage1d::state_manager::current $state] \
        state_history [::stage1d::state_manager::history $state] \
        phase_evidence $phase_evidence \
        preflight_result $preflight_result \
        preflight_status $preflight_status \
        preflight_ready [expr {$preflight_status eq {PASS}}] \
        static_readiness_result $static_readiness_result \
        static_readiness_status $static_readiness_status \
        static_readiness_ready \
            [expr {$static_readiness_status eq {PASS}}] \
        logs [::stage1d::logger::records $logger] \
        workspace_created $workspace_created \
        mutation_invoked $mutation_invoked \
        mutation_phase_status $mutation_phase_status \
        bd_validation_status $bd_validation_status \
        bd_save_status $bd_save_status \
        vivado_invoked $vivado_invoked \
        artifacts_generated $artifacts_generated \
        manifest_published 0 \
        exit_code [::stage1d::decision_engine::exit_code $final_decision]]
}
