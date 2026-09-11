# Stage 1E Phase 2 reconstruction and synthesis controller composition.
#
# This module is definition-only when sourced. It composes the existing
# source, environment, workspace, lifecycle, reconstruction, and synthesis
# owners. It never implements Vivado design content itself and never grants
# implementation, artifact, publication, or board authority.

namespace eval ::stage1e::phase2_controller {
    variable context_schema_version stage1e-phase2-controller-context-v1
    variable result_schema_version stage1e-phase2-controller-result-v1
    variable configuration_schema_version stage1e-phase2-synthesis-config-v1
    variable profile_schema_version stage1e-reconstruction-profile-schema-v1
    variable workspace_identifier_schema_version \
        stage1e-phase2-workspace-identifier-v2
    variable workspace_identifier_prefix r
    variable controlled_workspace_root {}
    variable windows_max_path_bytes 260
    variable windows_path_safety_margin_bytes 16
    # These are the longest reviewed Vivado-generated descendants from the
    # Stage 1E design. The Retry #14 protection-IP XCI path is deliberately
    # included; validating concrete descendants avoids another undersized
    # constant reserve. MAX_PATH includes the terminating NUL, so usable paths
    # are limited to 259 bytes before the additional safety margin is applied.
    variable reviewed_vivado_descendant_paths {
        project/current_protection_ip_pynq_z2_stage1e.srcs/sources_1/bd/protection_system/ip/protection_system_processing_system7_0_0/protection_system_processing_system7_0_0.xci
        project/current_protection_ip_pynq_z2_stage1e.srcs/sources_1/bd/protection_system/ip/protection_system_protection_ip_axi_lite_0_0/protection_system_protection_ip_axi_lite_0_0.xci
        project/current_protection_ip_pynq_z2_stage1e.srcs/sources_1/bd/protection_system/ip/protection_system_system_ila_stage2b_0_0/protection_system_system_ila_stage2b_0_0.xci
        project/current_protection_ip_pynq_z2_stage1e.gen/sources_1/bd/protection_system/ip/protection_system_smartconnect_0_0/sc_xtlm_protection_system_smartconnect_0_0.mem
    }
    variable enabled_capabilities {
        IP_PACKAGING
        PROJECT_RECONSTRUCTION
        BD_GENERATION
        WRAPPER_GENERATION
        SYNTHESIS
    }
    variable disabled_capabilities {
        IMPLEMENTATION
        ARTIFACT_COLLECTION
        ARTIFACT_PUBLICATION
    }
    variable operation_order {
        input_ready
        source_verification
        environment_verification
        workspace_creation
        ip_packaging
        project_creation
        bd_creation
        base_design
        debug_design
        mutation_bridge
        bd_validation
        bd_save
        build_target
        synthesis
    }
    variable authorized_operation_map [dict create \
        ip_packaging [dict create \
            operation stage1e::ip_packaging::run \
            phase IP_PACKAGING capability IP_PACKAGING \
            capability_flag ip_packaging_enabled] \
        project_creation [dict create \
            operation vivado_project::create \
            phase PROJECT_RECONSTRUCTION capability PROJECT_RECONSTRUCTION \
            capability_flag project_reconstruction_enabled] \
        bd_creation [dict create \
            operation bd_flow::create \
            phase BD_GENERATION capability BD_GENERATION \
            capability_flag bd_generation_enabled] \
        base_design [dict create \
            operation stage1e::base_design::apply \
            phase BD_GENERATION capability BD_GENERATION \
            capability_flag bd_generation_enabled] \
        debug_design [dict create \
            operation stage1e::debug_design::apply \
            phase BD_GENERATION capability BD_GENERATION \
            capability_flag bd_generation_enabled] \
        mutation_bridge [dict create \
            operation stage1e::mutation_bridge::apply \
            phase MUTATION_EXECUTE capability BD_GENERATION \
            capability_flag bd_generation_enabled] \
        bd_validation [dict create \
            operation bd_flow_validate \
            phase BD_VALIDATION capability BD_GENERATION \
            capability_flag bd_generation_enabled] \
        bd_save [dict create \
            operation bd_flow_save \
            phase BD_SAVE capability BD_GENERATION \
            capability_flag bd_generation_enabled] \
        build_target [dict create \
            operation stage1e::build_target::prepare \
            phase WRAPPER_GENERATION capability WRAPPER_GENERATION \
            capability_flag wrapper_generation_enabled] \
        synthesis [dict create \
            operation stage1e::synthesis::run \
            phase SYNTHESIS capability SYNTHESIS \
            capability_flag synthesis_enabled]]
}

proc ::stage1e::phase2_controller::_require_dictionary {value label} {
    if {[catch {dict size $value} dictionary_error]} {
        error "$label is not a dictionary: $dictionary_error"
    }
    return $value
}

proc ::stage1e::phase2_controller::_require_keys {
    dictionary
    required_keys
    label
} {
    _require_dictionary $dictionary $label
    foreach key $required_keys {
        if {![dict exists $dictionary $key]} {
            error "$label is missing required key: $key"
        }
    }
    return 1
}

proc ::stage1e::phase2_controller::_assert_set_equal {
    actual
    expected
    label
} {
    set actual_sorted [lsort -dictionary $actual]
    set expected_sorted [lsort -dictionary $expected]
    if {$actual_sorted ne $expected_sorted ||
        [llength $actual] != [llength [lsort -unique $actual]]} {
        error "$label mismatch: expected=$expected_sorted actual=$actual_sorted"
    }
    return 1
}

proc ::stage1e::phase2_controller::_validate_hash {value label} {
    set value [string tolower $value]
    if {![regexp {^[0-9a-f]{64}$} $value]} {
        error "$label is not a SHA-256 digest."
    }
    return $value
}

proc ::stage1e::phase2_controller::_identity {dictionary} {
    dict set dictionary identity_sha256 \
        [::stage1d::source_check::sha256_text $dictionary]
    return $dictionary
}

proc ::stage1e::phase2_controller::_retry_number {execution_identity} {
    _require_keys $execution_identity {retry_number} \
        {Stage 1E execution identity}
    set retry_number [string trim [dict get $execution_identity retry_number]]
    if {![regexp {^[1-9][0-9]*$} $retry_number]} {
        error {Stage 1E retry number must be a positive canonical integer.}
    }
    return $retry_number
}

proc ::stage1e::phase2_controller::_workspace_identifier {retry_number} {
    variable workspace_identifier_prefix
    set retry_number [string trim $retry_number]
    if {![regexp {^[1-9][0-9]*$} $retry_number]} {
        error {Controlled workspace retry number must be a positive canonical integer.}
    }
    return "${workspace_identifier_prefix}${retry_number}"
}

proc ::stage1e::phase2_controller::_workspace_root {} {
    variable controlled_workspace_root
    if {$controlled_workspace_root eq ""} {
        if {![info exists ::env(CSIP_BUILD_ROOT)] || $::env(CSIP_BUILD_ROOT) eq ""} {
            error {Set CSIP_BUILD_ROOT to a short external workspace root.}
        }
        return [file normalize $::env(CSIP_BUILD_ROOT)]
    }
    return [file normalize $controlled_workspace_root]
}

proc ::stage1e::phase2_controller::_same_path {first second} {
    set first [string map {\\ /} [file normalize $first]]
    set second [string map {\\ /} [file normalize $second]]
    if {$::tcl_platform(platform) eq {windows}} {
        return [string equal -nocase $first $second]
    }
    return [string equal $first $second]
}

proc ::stage1e::phase2_controller::_path_byte_length {path} {
    set normalized [string map {\\ /} [file normalize $path]]
    return [string length [encoding convertto utf-8 $normalized]]
}

proc ::stage1e::phase2_controller::_workspace_path_budget {
    build_workspace_root
    workspace_identifier
} {
    variable windows_max_path_bytes
    variable windows_path_safety_margin_bytes
    variable reviewed_vivado_descendant_paths
    set build_workspace_root [file normalize $build_workspace_root]
    set execution_workspace [file normalize \
        [file join $build_workspace_root $workspace_identifier]]
    set workspace_root_bytes [_path_byte_length $build_workspace_root]
    set workspace_bytes [_path_byte_length $execution_workspace]
    set usable_bytes [expr {$windows_max_path_bytes - 1}]
    if {$workspace_root_bytes > $usable_bytes ||
        $workspace_bytes > $usable_bytes} {
        error [join [list \
            {Controlled Stage 1E workspace root exceeds the Windows} \
            {Vivado path budget.} \
            "workspace_root_bytes=$workspace_root_bytes" \
            "execution_workspace_bytes=$workspace_bytes" \
            "usable_bytes=$usable_bytes path=$execution_workspace"] { }]
    }
    set longest_relative_path {}
    set longest_path_bytes 0
    foreach relative_path $reviewed_vivado_descendant_paths {
        set candidate [file normalize \
            [file join $execution_workspace $relative_path]]
        set candidate_bytes [_path_byte_length $candidate]
        if {$candidate_bytes > $longest_path_bytes} {
            set longest_path_bytes $candidate_bytes
            set longest_relative_path $relative_path
        }
    }
    set projected_bytes \
        [expr {$longest_path_bytes + $windows_path_safety_margin_bytes}]
    if {$projected_bytes > $usable_bytes} {
        error [join [list \
            {Controlled Stage 1E execution workspace exceeds the Windows} \
            {Vivado path budget after the required safety margin.} \
            "workspace_root_bytes=$workspace_root_bytes" \
            "root: workspace_bytes=$workspace_bytes" \
            "longest_reviewed_path_bytes=$longest_path_bytes" \
            "safety_margin_bytes=$windows_path_safety_margin_bytes" \
            "usable_bytes=$usable_bytes path=$execution_workspace"] { }]
    }
    return [dict create \
        workspace_root $build_workspace_root \
        workspace_root_bytes $workspace_root_bytes \
        execution_workspace $execution_workspace \
        execution_workspace_bytes $workspace_bytes \
        reviewed_descendant_path_count \
            [llength $reviewed_vivado_descendant_paths] \
        longest_reviewed_relative_path $longest_relative_path \
        longest_reviewed_path_bytes $longest_path_bytes \
        windows_path_safety_margin_bytes $windows_path_safety_margin_bytes \
        projected_max_path_bytes $projected_bytes \
        windows_usable_path_bytes $usable_bytes \
        windows_max_path_bytes $windows_max_path_bytes]
}

proc ::stage1e::phase2_controller::_controlled_input_ready {context} {
    variable workspace_identifier_schema_version
    set execution_identity [dict get $context execution_identity]
    set execution_identifier [dict get \
        $execution_identity execution_identifier]
    set retry_number [_retry_number $execution_identity]
    set workspace_identifier [_workspace_identifier $retry_number]
    set workspace_root [_workspace_root]
    if {![_same_path [dict get $context parsed_arguments build_workspace] \
            $workspace_root]} {
        error [join [list \
            {Controlled Stage 1E build-workspace root must match the} \
            {retry-indexed short-root policy:} \
            "expected=$workspace_root" \
            "actual=[dict get $context parsed_arguments build_workspace]"] { }]
    }
    set path_budget \
        [_workspace_path_budget $workspace_root $workspace_identifier]

    # The historical readiness checker remains unchanged. It receives a local
    # compact identifier solely for collision checking and path projection;
    # the controller-owned execution identity remains the full identifier.
    set projected_context $context
    dict set projected_context execution_identity execution_identifier \
        $workspace_identifier
    set result [::stage1e::controller::phase_input_ready $projected_context]
    if {[dict get $result status] ne {PASS}} {
        return $result
    }
    dict set result outputs execution_identifier $execution_identifier
    dict set result outputs retry_number $retry_number
    dict set result outputs workspace_identifier $workspace_identifier
    dict set result outputs workspace_identifier_schema_version \
        $workspace_identifier_schema_version
    dict set result outputs workspace_path_budget $path_budget
    return $result
}

proc ::stage1e::phase2_controller::_controlled_workspace_creation {context} {
    variable workspace_identifier_schema_version
    set execution_identity [dict get $context execution_identity]
    set execution_identifier [dict get \
        $execution_identity execution_identifier]
    set retry_number [_retry_number $execution_identity]
    set workspace_identifier [_workspace_identifier $retry_number]
    if {![dict exists $context input_validation_outputs \
            workspace_identifier] ||
        [dict get $context input_validation_outputs workspace_identifier] ne \
            $workspace_identifier ||
        ![dict exists $context input_validation_outputs retry_number] ||
        [dict get $context input_validation_outputs retry_number] ne \
            $retry_number} {
        error {Controlled workspace identifier is not bound to input readiness.}
    }

    set projected_context $context
    dict set projected_context execution_identity workspace_identifier \
        $workspace_identifier
    dict set projected_context execution_identity \
        workspace_identifier_schema_version \
        $workspace_identifier_schema_version
    return [::stage1d::workspace_manager::run $projected_context]
}

proc ::stage1e::phase2_controller::validate_profile {profile} {
    variable profile_schema_version
    variable enabled_capabilities
    variable disabled_capabilities
    _require_keys $profile {
        schema_version profile_identity profile_state capability_model
        adapter_inventory identity_binding authorization_policy build_policy
        constraint_policy
    } {Stage 1E reconstruction profile}
    if {[dict get $profile schema_version] ne $profile_schema_version} {
        error {Unsupported Stage 1E reconstruction profile schema.}
    }
    if {[dict get $profile profile_identity profile_id] ne \
            {stage1e_reconstruction_profile_v1} ||
        [dict get $profile profile_identity active_phase] ne \
            {PHASE2_SYNTHESIS} ||
        [dict get $profile capability_model active_phase] ne \
            {PHASE2_SYNTHESIS}} {
        error {Stage 1E Phase 2 synthesis profile is not selected.}
    }
    set phase [dict get $profile capability_model phases PHASE2_SYNTHESIS]
    if {[dict get $phase activation_state] ne {ACTIVE}} {
        error {Stage 1E Phase 2 synthesis profile is not active.}
    }
    _assert_set_equal [dict get $phase enabled_capabilities] \
        $enabled_capabilities {Phase 2 enabled capabilities}
    _assert_set_equal [dict get $phase disabled_capabilities] \
        $disabled_capabilities {Phase 2 disabled capabilities}
    foreach capability $enabled_capabilities {
        if {![dict get $profile capability_model capabilities \
                $capability profile_enabled]} {
            error "Phase 2 capability is not profile-enabled: $capability"
        }
    }
    foreach capability $disabled_capabilities {
        if {[dict get $profile capability_model capabilities \
                $capability profile_enabled]} {
            error "Forbidden Phase 2 capability is enabled: $capability"
        }
    }
    set state [dict get $profile profile_state]
    if {![dict get $state synthesis_execution_enabled] ||
        [dict get $state implementation_execution_enabled] ||
        [dict get $state artifact_operations_enabled] ||
        [dict get $state board_access_enabled]} {
        error {Stage 1E Phase 2 profile execution boundaries are invalid.}
    }
    set synthesis [dict get $profile build_policy synthesis]
    if {[dict get $synthesis policy_status] ne {REVIEWED_READY} ||
        ![dict get $synthesis capability_enabled] ||
        [dict get $synthesis incremental_synthesis_policy enabled] ||
        [string trim [dict get $synthesis \
            incremental_synthesis_policy checkpoint]] ne {}} {
        error {Stage 1E synthesis policy is not clean-run ready.}
    }
    set constraints [dict get $profile constraint_policy]
    if {[dict get $constraints policy_status] ne {REVIEWED_ACCEPTED} ||
        [dict get $constraints unknown_constraint_state_action] ne {BLOCK} ||
        [dict get $constraints build_pass_with_unknown_constraint_state]} {
        error {Stage 1E constraint policy is not reviewed and fail-closed.}
    }
    return 1
}

proc ::stage1e::phase2_controller::validate_configuration {configuration} {
    variable configuration_schema_version
    variable enabled_capabilities
    variable disabled_capabilities
    variable operation_order
    _require_keys $configuration {
        schema_version profile_reference capability_policy phase_order
        source_verification environment workspace reconstruction_policy
    } {Stage 1E Phase 2 configuration}
    if {[dict get $configuration schema_version] ne \
        $configuration_schema_version} {
        error {Unsupported Stage 1E Phase 2 configuration schema.}
    }
    if {[dict get $configuration profile_reference profile_id] ne \
        {stage1e_reconstruction_profile_v1}} {
        error {Stage 1E Phase 2 configuration references the wrong profile.}
    }
    _assert_set_equal [dict get $configuration capability_policy enabled] \
        $enabled_capabilities {Configuration enabled capabilities}
    _assert_set_equal [dict get $configuration capability_policy disabled] \
        $disabled_capabilities {Configuration disabled capabilities}
    if {[dict get $configuration capability_policy authorization_default] ne \
            {DENY} ||
        [dict get $configuration capability_policy \
            explicit_per_capability_grant_required] != 1} {
        error {Stage 1E Phase 2 configuration does not fail closed.}
    }
    if {[lrange [dict get $configuration phase_order] 0 end] ne \
        [lrange $operation_order 0 end]} {
        error {Stage 1E Phase 2 controller phase order is inconsistent.}
    }
    foreach section {
        packaging project bd base_design debug_design mutation build_target
    } {
        if {![dict exists $configuration reconstruction_policy $section]} {
            error "Stage 1E reconstruction policy is missing: $section"
        }
    }
    return 1
}

proc ::stage1e::phase2_controller::validate_execution_authorization {
    authorization
    execution_id
} {
    variable enabled_capabilities
    variable disabled_capabilities
    variable authorized_operation_map
    _require_keys $authorization {
        schema_version status authority execution_id profile_id
        retry_number git_commit git_tree workspace_root
        enabled_capabilities disabled_capabilities permitted_operations
    } {Stage 1E execution authorization}
    if {[dict get $authorization schema_version] ne \
            {stage1e-phase2-execution-authorization-v1} ||
        [dict get $authorization status] ne {AUTHORIZED} ||
        [dict get $authorization authority] ne \
            {stage1e_execution_authority} ||
        [dict get $authorization execution_id] ne $execution_id ||
        [dict get $authorization profile_id] ne \
            {stage1e_reconstruction_profile_v1}} {
        error {Stage 1E Phase 2 execution authorization identity mismatch.}
    }
    _assert_set_equal [dict get $authorization enabled_capabilities] \
        $enabled_capabilities {Authorized enabled capabilities}
    _assert_set_equal [dict get $authorization disabled_capabilities] \
        $disabled_capabilities {Authorized disabled capabilities}
    set expected_operations {}
    dict for {key definition} $authorized_operation_map {
        lappend expected_operations [dict get $definition operation]
    }
    _assert_set_equal [dict get $authorization permitted_operations] \
        $expected_operations {Authorized operation set}
    return 1
}

proc ::stage1e::phase2_controller::_validate_execution_workspace_binding {
    root_context
} {
    set execution_identity [dict get $root_context execution_identity]
    _require_keys $execution_identity {
        execution_identifier retry_number candidate_git_commit
    } {Stage 1E execution identity}
    set authorization [dict get $root_context execution_authorization]
    set retry_number [_retry_number $execution_identity]
    if {[dict get $authorization retry_number] ne $retry_number} {
        error {Authorized retry number does not match the execution context.}
    }
    set candidate_commit \
        [string tolower [dict get $execution_identity candidate_git_commit]]
    set authorized_commit \
        [string tolower [dict get $authorization git_commit]]
    set authorized_tree [string tolower [dict get $authorization git_tree]]
    if {![regexp {^[0-9a-f]{40}$} $candidate_commit] ||
        ![regexp {^[0-9a-f]{40}$} $authorized_commit] ||
        ![regexp {^[0-9a-f]{40}$} $authorized_tree] ||
        $candidate_commit ne $authorized_commit} {
        error {Authorized Git commit/tree workspace binding is invalid.}
    }
    set workspace_root [_workspace_root]
    set workspace_identifier [_workspace_identifier $retry_number]
    set expected_workspace [file normalize \
        [file join $workspace_root $workspace_identifier]]
    if {![_same_path [dict get $root_context parsed_arguments \
            build_workspace] $workspace_root]} {
        error {Parsed build-workspace root violates the short-root policy.}
    }
    if {![_same_path [dict get $authorization workspace_root] \
            $expected_workspace]} {
        error {Authorized workspace path is not bound to the retry number.}
    }
    return 1
}

proc ::stage1e::phase2_controller::_authorization {
    root_context
    operation_key
} {
    variable authorized_operation_map
    set definition [dict get $authorized_operation_map $operation_key]
    set operation [dict get $definition operation]
    set external [dict get $root_context execution_authorization]
    if {$operation ni [dict get $external permitted_operations]} {
        error "Operation is absent from execution authorization: $operation"
    }
    return [dict create \
        status AUTHORIZED \
        authority controller_core \
        execution_id [dict get $root_context execution_id] \
        operation $operation \
        phase [dict get $definition phase] \
        capability [dict get $definition capability_flag] \
        capability_enabled 1]
}

proc ::stage1e::phase2_controller::default_operations {} {
    return [dict create \
        input_ready ::stage1e::phase2_controller::_controlled_input_ready \
        source_verification ::stage1d::source_check::run \
        environment_verification ::stage1d::environment_check::run \
        workspace_creation \
            ::stage1e::phase2_controller::_controlled_workspace_creation \
        ip_packaging ::stage1e::ip_packaging::run \
        project_creation ::stage1d::vivado_project::create \
        bd_creation ::stage1d::bd_flow::create \
        base_design ::stage1e::base_design::apply \
        debug_design ::stage1e::debug_design::apply \
        mutation_bridge ::stage1e::mutation_bridge::apply \
        bd_validation ::stage1d::bd_flow::validate \
        bd_save ::stage1d::bd_flow::save \
        build_target ::stage1e::build_target::prepare \
        synthesis ::stage1e::synthesis::run]
}

proc ::stage1e::phase2_controller::_resolve_operations {overrides} {
    set operations [default_operations]
    _require_dictionary $overrides {Stage 1E operation overrides}
    dict for {key command} $overrides {
        if {![dict exists $operations $key]} {
            error "Unknown Stage 1E Phase 2 operation override: $key"
        }
        if {[llength $command] == 0 ||
            [llength [info commands [lindex $command 0]]] != 1} {
            error "Unavailable Stage 1E operation override: $key"
        }
        dict set operations $key $command
    }
    return $operations
}

proc ::stage1e::phase2_controller::_invoke {operations key context} {
    set command [dict get $operations $key]
    set invoke_status [catch {
        uplevel #0 [linsert $command end $context]
    } result invoke_options]
    if {$invoke_status != 0} {
        return [dict create \
            status FAIL \
            errors [list [dict create \
                code PHASE_INVOCATION_FAILED \
                phase $key \
                message $result \
                error_info [expr {
                    [dict exists $invoke_options -errorinfo] ?
                    [dict get $invoke_options -errorinfo] : {}
                }]]]]
    }
    if {[catch {dict size $result}] ||
        ![dict exists $result status] ||
        [dict get $result status] ni {PASS FAIL BLOCKED}} {
        return [dict create \
            status FAIL \
            errors [list [dict create \
                code PHASE_RESULT_INVALID phase $key \
                message {Operation returned an invalid structured result.}]]]
    }
    return $result
}

proc ::stage1e::phase2_controller::_launcher_failure_result {
    key
    error_code
    message
    {error_info {}}
} {
    return [dict create \
        status FAIL \
        errors [list [dict create \
            code $error_code \
            error_code $error_code \
            phase $key \
            category LAUNCHER \
            message $message \
            error_info $error_info]]]
}

# Vivado creates .Xil and other transient state relative to the process cwd.
# Bind that cwd for every operation that owns Vivado state, then restore the
# runner cwd. This keeps a long external runner path out of the generated
# hierarchy without allowing the runner to replace the identity-bound path.
proc ::stage1e::phase2_controller::_invoke_in_workspace {
    operations
    key
    context
    workspace_identity
} {
    set enter_status [catch {
        ::stage1e::phase2_build::enter_launcher_workspace \
            $workspace_identity
    } launcher_state enter_options]
    if {$enter_status != 0} {
        return [_launcher_failure_result $key \
            LAUNCHER_CWD_BINDING_FAILED \
            "Unable to bind Vivado launcher cwd: $launcher_state" \
            [expr {
                [dict exists $enter_options -errorinfo] ?
                [dict get $enter_options -errorinfo] : {}
            }]]
    }

    set invoke_status [catch {
        _invoke $operations $key $context
    } operation_result invoke_options]
    set cwd_status [catch {
        ::stage1e::phase2_build::validate_launcher_cwd \
            $workspace_identity [pwd] 1
    } cwd_error cwd_options]
    set leave_status [catch {
        ::stage1e::phase2_build::leave_launcher_workspace $launcher_state
    } leave_error leave_options]

    if {$invoke_status != 0} {
        return [_launcher_failure_result $key \
            LAUNCHER_OPERATION_FAILED $operation_result \
            [expr {
                [dict exists $invoke_options -errorinfo] ?
                [dict get $invoke_options -errorinfo] : {}
            }]]
    }
    if {$cwd_status != 0} {
        return [_launcher_failure_result $key \
            LAUNCHER_CWD_ESCAPED_WORKSPACE $cwd_error \
            [expr {
                [dict exists $cwd_options -errorinfo] ?
                [dict get $cwd_options -errorinfo] : {}
            }]]
    }
    if {$leave_status != 0} {
        return [_launcher_failure_result $key \
            LAUNCHER_CWD_RESTORE_FAILED $leave_error \
            [expr {
                [dict exists $leave_options -errorinfo] ?
                [dict get $leave_options -errorinfo] : {}
            }]]
    }
    return $operation_result
}

proc ::stage1e::phase2_controller::_result_status {result} {
    return [dict get $result status]
}

proc ::stage1e::phase2_controller::_record_phase {
    phase_results_variable
    key
    context
    result
} {
    upvar 1 $phase_results_variable phase_results
    set record [dict create \
        phase $key \
        status [dict get $result status] \
        result $result]
    if {![catch {dict size $context}] &&
        [dict exists $context authorization]} {
        dict set record authorization [dict get $context authorization]
    }
    lappend phase_results $record
}

proc ::stage1e::phase2_controller::_select_inventory {
    source_identity
    paths
} {
    set by_path [dict create]
    foreach entry [dict get $source_identity source_inventory] {
        dict set by_path [string map {\\ /} [dict get $entry path]] $entry
    }
    set selected {}
    foreach path $paths {
        set path [string map {\\ /} $path]
        if {![dict exists $by_path $path]} {
            error "Accepted source inventory does not contain: $path"
        }
        lappend selected [dict get $by_path $path]
    }
    return $selected
}

proc ::stage1e::phase2_controller::_normalize_identities {
    root_context
    source_result
    environment_result
    workspace_result
} {
    set execution_id [dict get $root_context execution_id]
    set source_outputs [dict get $source_result outputs]
    set environment_outputs [dict get $environment_result outputs]
    set workspace_outputs [dict get $workspace_result outputs]
    set source_inventory [dict get $source_outputs source_inventory]
    set source_inventory_sha256 \
        [::stage1d::source_check::aggregate_inventory_hash $source_inventory]
    set source_identity [_identity [dict create \
        schema_version stage1e-source-identity-v1 \
        execution_id $execution_id \
        repository_root [dict get $source_outputs repository_root] \
        git_commit [dict get $source_outputs git_commit] \
        source_inventory $source_inventory \
        source_inventory_sha256 $source_inventory_sha256 \
        controller_source_hash [dict get \
            $source_outputs controller_source_hash]]]
    set configuration [dict get $root_context configuration]
    set profile_hash [_validate_hash \
        [dict get $root_context profile_sha256] {Profile SHA-256}]
    set configuration_hash [_validate_hash \
        [dict get $source_outputs configuration_hash] \
        {Configuration SHA-256}]
    set configuration_identity [_identity [dict create \
        schema_version stage1e-configuration-identity-v1 \
        execution_id $execution_id \
        profile_id [dict get $root_context profile \
            profile_identity profile_id] \
        profile_sha256 $profile_hash \
        configuration_sha256 $configuration_hash \
        sha256 [::stage1d::source_check::sha256_text \
            [list $profile_hash $configuration_hash]]]]
    set environment_identity [_identity [dict create \
        schema_version stage1e-environment-identity-v1 \
        execution_id $execution_id \
        vivado_version [dict get $environment_outputs vivado_version] \
        sw_build [dict get $environment_outputs sw_build] \
        ip_build [dict get $environment_outputs ip_build] \
        part [dict get $environment_outputs part] \
        board_part [dict get $environment_outputs board_part] \
        ip_identities [dict get \
            $environment_outputs observed_ip_identities] \
        environment_evidence_hash [dict get \
            $environment_outputs environment_evidence_hash]]]
    set workspace_root [file normalize \
        [dict get $workspace_outputs execution_workspace]]
    set project_policy [dict get $configuration \
        reconstruction_policy project]
    set project_name [dict get $project_policy project_name]
    set run_name [dict get $root_context profile \
        build_policy synthesis run_name]
    _require_keys $workspace_outputs {
        workspace_identifier retry_number ownership_evidence
        workspace_identity workspace_identity_hash
    } {Controlled workspace outputs}
    set expected_workspace_identity \
        [::stage1d::workspace_manager::phase2_workspace_identity \
            $execution_id \
            [_retry_number [dict get $root_context execution_identity]] \
            [dict get $source_outputs git_commit] \
            [dict get $root_context execution_authorization git_tree] \
            [dict get $workspace_outputs workspace_identifier] \
            $workspace_root \
            $project_name \
            $run_name \
            [dict get $workspace_outputs ownership_evidence]]
    set workspace_identity [dict get $workspace_outputs workspace_identity]
    if {$workspace_identity ne $expected_workspace_identity ||
        [dict get $workspace_outputs workspace_identity_hash] ne \
            [dict get $expected_workspace_identity identity_sha256]} {
        error {Workspace identity does not match the ownership binding.}
    }
    return [dict create \
        source_identity $source_identity \
        configuration_identity $configuration_identity \
        environment_identity $environment_identity \
        workspace_identity $workspace_identity]
}

proc ::stage1e::phase2_controller::_common_context {
    root_context
    state
    operation_key
} {
    set workspace [dict get $state workspace_identity]
    return [dict create \
        execution_id [dict get $root_context execution_id] \
        authorization [_authorization $root_context $operation_key] \
        source_identity [dict get $state source_identity] \
        environment_identity [dict get $state environment_identity] \
        configuration_identity [dict get $state configuration_identity] \
        workspace_root [dict get $workspace workspace_root] \
        evidence_dir [dict get $workspace evidence_dir] \
        launcher_working_directory [dict get $workspace workspace_root] \
        launcher_contract_version \
            [::stage1e::phase2_build::launcher_contract_version]]
}

proc ::stage1e::phase2_controller::_packaging_context {
    root_context
    state
} {
    set policy [dict get $root_context configuration \
        reconstruction_policy packaging]
    set common [_common_context $root_context $state ip_packaging]
    set workspace_root [dict get $common workspace_root]
    return [dict create \
        context_schema_version stage1e-ip-packaging-context-v1 \
        operation stage1e::ip_packaging::run \
        execution_id [dict get $root_context execution_id] \
        authorization [dict get $common authorization] \
        repository_root [dict get $state source_identity repository_root] \
        source_inventory [_select_inventory [dict get $state source_identity] \
            [dict get $policy source_paths]] \
        package_inventory [dict get $policy package_inventory] \
        workspace_root $workspace_root \
        packaging_workspace [file normalize [file join $workspace_root \
            [dict get $policy packaging_workspace_relative]]] \
        ip_repo_path [file normalize [file join $workspace_root \
            [dict get $policy ip_repo_relative]]] \
        vlnv_expectation [dict get $policy vlnv_expectation]]
}

proc ::stage1e::phase2_controller::_project_context {
    root_context
    state
} {
    set policy [dict get $root_context configuration \
        reconstruction_policy project]
    set common [_common_context $root_context $state project_creation]
    set workspace_root [dict get $common workspace_root]
    set project_name [dict get $policy project_name]
    return [dict merge $common [dict create \
        context_schema_version stage1e-vivado-project-create-context-v1 \
        operation vivado_project::create \
        phase PROJECT_RECONSTRUCTION \
        project_path [file normalize [file join $workspace_root project \
            "${project_name}.xpr"]] \
        project_name $project_name \
        part [dict get $common environment_identity part] \
        board_part [dict get $common environment_identity board_part] \
        target_language [dict get $policy target_language] \
        source_inventory [dict get $policy source_inventory] \
        constraint_policy [dict get $policy constraint_policy] \
        ip_repo_identity [dict get $state ip_repo_identity]]]
}

proc ::stage1e::phase2_controller::_bd_context {
    root_context
    state
} {
    set policy [dict get $root_context configuration \
        reconstruction_policy bd]
    set common [_common_context $root_context $state bd_creation]
    set project [dict get $state project_ownership]
    set project_identity [dict get $project project_identity]
    set bd_name [dict get $policy bd_name]
    set project_name [dict get $project_identity project_name]
    set expected_path [file join [dict get $project_identity project_directory] \
        "${project_name}.srcs" sources_1 bd $bd_name "${bd_name}.bd"]
    set topology [dict get $policy topology_policy]
    dict set topology execution_id [dict get $root_context execution_id]
    dict set topology sha256 \
        [::stage1d::source_check::sha256_text $topology]
    return [dict merge $common [dict create \
        context_schema_version stage1e-bd-create-context-v1 \
        operation bd_flow::create \
        phase BD_GENERATION \
        project_ownership $project \
        bd_identity [dict create \
            schema_version stage1e-bd-create-identity-v1 \
            bd_name $bd_name expected_bd_path [file normalize $expected_path]] \
        topology_policy $topology]]
}

proc ::stage1e::phase2_controller::_base_design_context {
    root_context
    state
} {
    set policy [dict get $root_context configuration \
        reconstruction_policy base_design]
    set topology [dict get $policy topology_policy]
    dict set topology execution_id [dict get $root_context execution_id]
    dict set topology sha256 \
        [::stage1d::source_check::sha256_text $topology]
    dict set policy topology_policy $topology
    return [dict merge [_common_context $root_context $state base_design] \
        $policy [dict create \
            context_schema_version stage1e-base-design-context-v1 \
            operation stage1e::base_design::apply \
            phase BD_GENERATION \
            project_ownership [dict get $state project_ownership] \
            bd_ownership [dict get $state bd_ownership]]]
}

proc ::stage1e::phase2_controller::_debug_design_context {
    root_context
    state
} {
    set policy [dict get $root_context configuration \
        reconstruction_policy debug_design]
    return [dict merge [_common_context $root_context $state debug_design] \
        $policy [dict create \
            context_schema_version stage1e-debug-design-context-v1 \
            operation stage1e::debug_design::apply \
            phase BD_GENERATION \
            project_ownership [dict get $state project_ownership] \
            bd_ownership [dict get $state bd_ownership] \
            base_design_identity [dict get $state base_design_identity]]]
}

proc ::stage1e::phase2_controller::_mutation_context {
    root_context
    state
} {
    set common [_common_context $root_context $state mutation_bridge]
    set policy [dict get $root_context configuration \
        reconstruction_policy mutation]
    set assertion [dict create \
        execution_id [dict get $root_context execution_id] \
        operation stage1d_controlled_stimulus \
        phase MUTATION_EXECUTE \
        bd_name [dict get $state bd_ownership bd_name] \
        decision ALLOW]
    return [dict merge $common [dict create \
        context_schema_version stage1e-mutation-bridge-context-v1 \
        operation stage1e::mutation_bridge::apply \
        phase MUTATION_EXECUTE \
        project_ownership [dict get $state project_ownership] \
        bd_ownership [dict get $state bd_ownership] \
        base_design_identity [dict get $state base_design_identity] \
        debug_design_identity [dict get $state debug_design_identity] \
        mutation_configuration [dict get $policy mutation_configuration] \
        mutation_authorization_assertion_source [dict create \
            owner controller_core authorization_assertion $assertion]]]
}

proc ::stage1e::phase2_controller::_bd_lifecycle_context {
    root_context
    state
    operation_key
} {
    set common [_common_context $root_context $state $operation_key]
    return [dict merge $common [dict create \
        project_path [dict get $state project_ownership project_path] \
        bd_name [dict get $state bd_ownership bd_name] \
        project_ownership [dict get $state project_ownership] \
        bd_ownership [dict get $state bd_ownership]]]
}

proc ::stage1e::phase2_controller::_build_target_context {
    root_context
    state
} {
    set common [_common_context $root_context $state build_target]
    set policy [dict get $root_context configuration \
        reconstruction_policy build_target]
    set project_identity [dict get $state project_ownership project_identity]
    set project_name [dict get $project_identity project_name]
    set bd_name [dict get $state bd_ownership bd_name]
    set wrapper_name [dict get $policy wrapper_name]
    set wrapper_path [file join [dict get $project_identity project_directory] \
        "${project_name}.gen" sources_1 bd $bd_name hdl \
        "${wrapper_name}.v"]
    return [dict merge $common [dict create \
        context_schema_version stage1e-build-target-context-v1 \
        operation stage1e::build_target::prepare \
        phase WRAPPER_GENERATION \
        project_ownership [dict get $state project_ownership] \
        bd_ownership [dict get $state bd_ownership] \
        package_identity [dict get $state package_identity] \
        base_design_identity [dict get $state base_design_identity] \
        debug_design_identity [dict get $state debug_design_identity] \
        controlled_mutation_identity \
            [dict get $state controlled_mutation_identity] \
        wrapper_name $wrapper_name \
        wrapper_path_policy [dict create \
            schema_version stage1e-wrapper-path-policy-v1 \
            path [file normalize $wrapper_path]] \
        top_module_policy [dict create \
            schema_version stage1e-top-module-policy-v1 \
            top_module $wrapper_name fileset sources_1] \
        output_product_policy [dict get $policy output_product_policy]]]
}

proc ::stage1e::phase2_controller::_synthesis_context {
    root_context
    state
} {
    set common [_common_context $root_context $state synthesis]
    set workspace [dict get $state workspace_identity]
    set profile_policy [dict get $root_context profile build_policy synthesis]
    set launcher_lifetime_policy \
        [::stage1e::phase2_build::validate_launcher_lifetime_policy \
            $profile_policy]
    set evidence_paths \
        [::stage1e::phase2_build::synthesis_evidence_paths \
            $workspace $profile_policy]
    set report_dir [dict get $evidence_paths directory]
    if {[file exists $report_dir] && ![file isdirectory $report_dir]} {
        error {Synthesis evidence destination exists and is not a directory.}
    }
    if {![file isdirectory $report_dir]} {
        file mkdir $report_dir
    }
    set output [dict get $workspace synthesis_output_dir]
    set policy [dict create \
        schema_version stage1e-synthesis-policy-v1 \
        run_name [dict get $profile_policy run_name] \
        strategy [dict get $profile_policy strategy] \
        directives [dict get $profile_policy directives] \
        seed_policy [dict get $profile_policy seed_policy] \
        job_policy [dict get $profile_policy job_policy] \
        incremental_synthesis_policy [dict create \
            enabled [dict get $profile_policy \
                incremental_synthesis_policy enabled] \
            checkpoint [dict get $profile_policy \
                incremental_synthesis_policy checkpoint]] \
        output_directory $output \
        fileset [dict get $profile_policy run_policy fileset] \
        top_module [dict get $profile_policy run_policy top_module] \
        allowed_initial_statuses [dict get $profile_policy \
            run_policy allowed_initial_statuses] \
        accepted_terminal_statuses [dict get $profile_policy \
            run_policy accepted_terminal_statuses] \
        report_paths [dict get $evidence_paths report_paths] \
        run_log_path [dict get $evidence_paths run_log_path] \
        warning_policy [dict get $profile_policy warning_policy]]
    return [dict merge $common [dict create \
        context_schema_version stage1e-synthesis-context-v1 \
        operation stage1e::synthesis::run \
        phase SYNTHESIS \
        workspace_identity $workspace \
        launcher_lifetime_policy $launcher_lifetime_policy \
        build_target_identity [dict get $state build_target_identity] \
        project_ownership [dict get $state project_ownership] \
        bd_ownership [dict get $state bd_ownership] \
        synthesis_policy $policy]]
}

proc ::stage1e::phase2_controller::_final_result {
    status
    decision
    root_context
    phase_results
    state
} {
    variable result_schema_version
    set result [dict create \
        schema_version $result_schema_version \
        execution_id [dict get $root_context execution_id] \
        status $status \
        decision $decision \
        phase_results $phase_results \
        identities $state \
        implementation_performed 0 \
        artifacts_generated 0 \
        artifact_collection_performed 0 \
        artifact_publication_performed 0 \
        board_access_performed 0]
    foreach key {
        build_target_identity synthesis_result_identity
        project_ownership bd_ownership
    } {
        if {[dict exists $state $key]} {
            dict set result $key [dict get $state $key]
        }
    }
    return $result
}

proc ::stage1e::phase2_controller::_stop_result {
    root_context
    phase_results
    state
    result
} {
    set status [dict get $result status]
    return [_final_result $status "PHASE2_[string toupper $status]" \
        $root_context $phase_results $state]
}

proc ::stage1e::phase2_controller::run {
    root_context
    {operation_overrides {}}
} {
    variable context_schema_version
    _require_keys $root_context {
        context_schema_version execution_id execution_identity
        parsed_arguments profile profile_sha256 configuration
        execution_authorization
    } {Stage 1E Phase 2 controller context}
    if {[dict get $root_context context_schema_version] ne \
        $context_schema_version} {
        error {Unsupported Stage 1E Phase 2 controller context schema.}
    }
    set execution_id [dict get $root_context execution_id]
    if {$execution_id ne [dict get $root_context execution_identity \
        execution_identifier]} {
        error {Stage 1E execution identity is inconsistent.}
    }
    validate_profile [dict get $root_context profile]
    validate_configuration [dict get $root_context configuration]
    validate_execution_authorization \
        [dict get $root_context execution_authorization] $execution_id
    _validate_execution_workspace_binding $root_context
    set operations [_resolve_operations $operation_overrides]
    set phase_results [list [dict create \
        phase profile status PASS \
        profile_id stage1e_reconstruction_profile_v1 \
        active_phase PHASE2_SYNTHESIS]]
    set state [dict create]

    set phase_execution_identity [dict get $root_context execution_identity]
    dict set phase_execution_identity git_tree \
        [dict get $root_context execution_authorization git_tree]
    dict set phase_execution_identity project_name \
        [dict get $root_context configuration reconstruction_policy \
            project project_name]
    dict set phase_execution_identity synthesis_run_name \
        [dict get $root_context profile build_policy synthesis run_name]
    set preflight [dict create \
        parsed_arguments [dict get $root_context parsed_arguments] \
        configuration [dict get $root_context configuration] \
        execution_identity $phase_execution_identity]
    set input_result [_invoke $operations input_ready $preflight]
    _record_phase phase_results input_ready $preflight $input_result
    if {[_result_status $input_result] ne {PASS}} {
        return [_stop_result $root_context $phase_results $state $input_result]
    }
    dict set preflight input_validation_outputs \
        [dict get $input_result outputs]

    set source_result [_invoke $operations source_verification $preflight]
    _record_phase phase_results source_verification $preflight $source_result
    if {[_result_status $source_result] ne {PASS}} {
        return [_stop_result $root_context $phase_results $state $source_result]
    }
    dict set preflight source_verification [dict get $source_result outputs]

    set environment_result \
        [_invoke $operations environment_verification $preflight]
    _record_phase phase_results environment_verification \
        $preflight $environment_result
    if {[_result_status $environment_result] ne {PASS}} {
        return [_stop_result $root_context $phase_results $state \
            $environment_result]
    }
    dict set preflight environment_verification \
        [dict get $environment_result outputs]

    set workspace_result [_invoke $operations workspace_creation $preflight]
    _record_phase phase_results workspace_creation $preflight $workspace_result
    if {[_result_status $workspace_result] ne {PASS}} {
        return [_stop_result $root_context $phase_results $state \
            $workspace_result]
    }
    set state [_normalize_identities $root_context $source_result \
        $environment_result $workspace_result]

    foreach operation_key {
        ip_packaging
        project_creation
        bd_creation
        base_design
        debug_design
        mutation_bridge
        bd_validation
        bd_save
        build_target
        synthesis
    } {
        switch -- $operation_key {
            ip_packaging {
                set operation_context [_packaging_context $root_context $state]
            }
            project_creation {
                set operation_context [_project_context $root_context $state]
            }
            bd_creation {
                set operation_context [_bd_context $root_context $state]
            }
            base_design {
                set operation_context \
                    [_base_design_context $root_context $state]
            }
            debug_design {
                set operation_context \
                    [_debug_design_context $root_context $state]
            }
            mutation_bridge {
                set operation_context [_mutation_context $root_context $state]
            }
            bd_validation - bd_save {
                set operation_context [_bd_lifecycle_context \
                    $root_context $state $operation_key]
            }
            build_target {
                set operation_context \
                    [_build_target_context $root_context $state]
            }
            synthesis {
                set operation_context [_synthesis_context $root_context $state]
            }
        }
        set operation_result \
            [_invoke_in_workspace $operations $operation_key \
                $operation_context [dict get $state workspace_identity]]
        _record_phase phase_results $operation_key \
            $operation_context $operation_result
        if {[_result_status $operation_result] ne {PASS}} {
            return [_stop_result $root_context $phase_results $state \
                $operation_result]
        }
        switch -- $operation_key {
            ip_packaging {
                dict set state package_identity [dict get $operation_result \
                    produced_identities package_identity]
                dict set state ip_repo_identity [dict get $operation_result \
                    produced_identities ip_repo_identity]
            }
            project_creation {
                dict set state project_ownership \
                    [dict get $operation_result ownership_records]
            }
            bd_creation {
                dict set state bd_ownership \
                    [dict get $operation_result ownership_records]
            }
            base_design {
                dict set state base_design_identity [dict get $operation_result \
                    produced_identities base_design_identity]
            }
            debug_design {
                dict set state debug_design_identity [dict get $operation_result \
                    produced_identities debug_design_identity]
            }
            mutation_bridge {
                dict set state controlled_mutation_identity \
                    [dict get $operation_result produced_identities \
                        controlled_mutation_identity]
            }
            bd_validation - bd_save {
                dict set state bd_ownership [dict get $operation_result \
                    outputs lifecycle_context bd_ownership]
            }
            build_target {
                set target [dict get $operation_result produced_identities \
                    build_target_identity]
                if {[dict get $target execution_id] ne $execution_id ||
                    [dict get $target producer_operation] ne \
                        {stage1e::build_target::prepare}} {
                    error {Controller rejected the build-target identity.}
                }
                dict set target acceptance_state ACCEPTED
                dict set target accepted_by controller_core
                dict set state build_target_identity $target
            }
            synthesis {
                dict set state synthesis_result_identity [dict get \
                    $operation_result produced_identities \
                    synthesis_result_identity]
            }
        }
    }
    return [_final_result PASS SYNTHESIS_CANDIDATE_READY \
        $root_context $phase_results $state]
}
