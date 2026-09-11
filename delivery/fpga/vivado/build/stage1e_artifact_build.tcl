# Stage 1E WP-A Artifact Closure controller skeleton.
#
# Scope: STAGE1E_WP_A_CONTROLLER_SKELETON. This entrypoint implements source,
# environment, and external-workspace readiness only and stops at
# BUILD_CONTROLLER_READY. Every future build capability remains deny-by-default.

namespace eval ::stage1e {}
namespace eval ::stage1e::controller {
    variable controller_version STAGE1E-BUILD-CTRL-v1.1
    variable controller_api_version STAGE1E-CONTROLLER-API-v1
    variable configuration_schema_version stage1e-build-config-v2
    variable execution_id_schema_version v1
    variable phase_evidence_schema_version v1
    variable build_profile_definition [dict create \
        schema_version stage1e-build-profile-identity-v1 \
        profile_id stage1e_controller_skeleton \
        stage STAGE1E \
        work_package WP-A \
        scope_id STAGE1E_WP_A_CONTROLLER_SKELETON]
    variable skeleton_scope_definition [dict create \
        schema_version stage1e-skeleton-scope-v1 \
        scope_id STAGE1E_WP_A_CONTROLLER_SKELETON \
        stage STAGE1E \
        work_package WP-A \
        execution_mode READINESS_ONLY \
        terminal_state BUILD_CONTROLLER_READY \
        build_execution_permitted 0]
    variable context_boundary_definition [dict create \
        schema_version stage1e-controller-context-v1 \
        context_owner STAGE1E_WP_A_CONTROLLER \
        stage1d_adapter_policy MINIMUM_REQUIRED_FIELDS \
        stage1d_controller_core_ownership UNCHANGED \
        stage1d_lifecycle_authority NOT_IMPORTED \
        stage1d_mutation_authority NOT_IMPORTED \
        build_authority NOT_GRANTED]
    variable disabled_capability_names {
        ip_packaging_enabled
        project_reconstruction_enabled
        bd_generation_enabled
        wrapper_generation_enabled
        synthesis_enabled
        implementation_enabled
        artifact_generation_enabled
        artifact_collection_enabled
        publication_enabled
        vivado_invocation_enabled
        board_access_enabled
    }
    variable future_phase_capability_map [dict create \
        IP_PACKAGING ip_packaging_enabled \
        PROJECT_RECONSTRUCTION project_reconstruction_enabled \
        BD_GENERATION bd_generation_enabled \
        WRAPPER_GENERATION wrapper_generation_enabled \
        SYNTHESIS synthesis_enabled \
        IMPLEMENTATION implementation_enabled \
        ARTIFACT_COLLECTION artifact_collection_enabled \
        PUBLICATION publication_enabled]
    variable initial_phase_order {
        INPUT_READY
        SOURCE_VALIDATED
        ENVIRONMENT_VALIDATED
        WORKSPACE_READY
        BUILD_CONTROLLER_READY
    }
    variable forbidden_states [concat \
        [dict keys $future_phase_capability_map] {ARTIFACT_READY}]
    variable terminal_states {FAIL BLOCKED}
    variable forward_transitions [dict create \
        INIT INPUT_READY \
        INPUT_READY SOURCE_VALIDATED \
        SOURCE_VALIDATED ENVIRONMENT_VALIDATED \
        ENVIRONMENT_VALIDATED WORKSPACE_READY \
        WORKSPACE_READY BUILD_CONTROLLER_READY]
}

set stage1e_build_root [file normalize [file dirname [info script]]]
set stage1e_controller_root [file join $stage1e_build_root controller]
set stage1e_library_root [file join $stage1e_build_root lib]
# Load the existing Stage 1D modules as definition-only dependencies. Stage 1E
# reuses their identity, source/environment verification, workspace isolation,
# evidence, logging, lifecycle, authorization, and fail-closed semantics. No
# lifecycle or Vivado procedure is invoked while this file is sourced.
set stage1e_reused_modules [list \
    [file join $stage1e_controller_root logger.tcl] \
    [file join $stage1e_controller_root phase_runner.tcl] \
    [file join $stage1e_library_root source_check.tcl] \
    [file join $stage1e_library_root environment_check.tcl] \
    [file join $stage1e_library_root workspace_manager.tcl] \
    [file join $stage1e_controller_root controller_core.tcl]]

foreach stage1e_module_path $stage1e_reused_modules {
    if {![file exists $stage1e_module_path] ||
        ![file isfile $stage1e_module_path]} {
        error "Required reused controller module not found: $stage1e_module_path"
    }
    source $stage1e_module_path
}

proc ::stage1e::controller::version {} {
    variable controller_version
    return $controller_version
}

proc ::stage1e::controller::api_version {} {
    variable controller_api_version
    return $controller_api_version
}

proc ::stage1e::controller::execution_id_schema_version {} {
    variable execution_id_schema_version
    return $execution_id_schema_version
}

proc ::stage1e::controller::phase_order {} {
    variable initial_phase_order
    return $initial_phase_order
}

proc ::stage1e::controller::build_profile_identity {} {
    variable build_profile_definition
    return $build_profile_definition
}

proc ::stage1e::controller::skeleton_scope {} {
    variable skeleton_scope_definition
    return $skeleton_scope_definition
}

proc ::stage1e::controller::context_boundary {} {
    variable context_boundary_definition
    return $context_boundary_definition
}

proc ::stage1e::controller::disabled_capabilities {} {
    variable disabled_capability_names
    set capabilities [dict create]
    foreach capability $disabled_capability_names {
        dict set capabilities $capability 0
    }
    return $capabilities
}

proc ::stage1e::controller::future_phase_boundaries {} {
    variable future_phase_capability_map
    return $future_phase_capability_map
}

proc ::stage1e::controller::usage {} {
    set scope [skeleton_scope]
    return [join [list \
        {Usage: stage1e_artifact_build.tcl -tclargs <options>} \
        "Scope: [dict get $scope scope_id]" \
        {} \
        {Required options:} \
        {  --repository-root <path>} \
        {  --build-workspace <external-path>} \
        {  --artifact-storage <external-path>} \
        {  --configuration <stage1e-config-path>} \
        {  --environment-evidence <declarative-dict-path>} \
        {  --git-commit <full-or-candidate-commit>} \
        {} \
        {Other options:} \
        {  --help} \
        {} \
        {This skeleton stops at BUILD_CONTROLLER_READY.}] "\n"]
}

proc ::stage1e::controller::parse_arguments {arguments} {
    set option_map [dict create \
        --repository-root repository_root \
        --build-workspace build_workspace \
        --artifact-storage artifact_storage \
        --configuration configuration_path \
        --environment-evidence environment_evidence_path \
        --git-commit candidate_git_commit]
    set parsed [dict create help 0]
    set seen [dict create]

    for {set index 0} {$index < [llength $arguments]} {incr index} {
        set option [lindex $arguments $index]
        if {$option eq {--help}} {
            if {[dict exists $seen $option]} {
                error "Duplicate option: $option"
            }
            dict set seen $option 1
            dict set parsed help 1
            continue
        }
        if {![dict exists $option_map $option]} {
            error "Unknown option: $option"
        }
        if {[dict exists $seen $option]} {
            error "Duplicate option: $option"
        }
        incr index
        if {$index >= [llength $arguments]} {
            error "Missing value for option: $option"
        }
        set value [lindex $arguments $index]
        if {[string trim $value] eq {}} {
            error "Empty value for option: $option"
        }
        dict set seen $option 1
        dict set parsed [dict get $option_map $option] $value
    }

    if {[dict get $parsed help]} {
        return $parsed
    }
    foreach required_key {
        repository_root
        build_workspace
        artifact_storage
        configuration_path
        environment_evidence_path
        candidate_git_commit
    } {
        if {![dict exists $parsed $required_key]} {
            error "Missing required Stage 1E controller input: $required_key"
        }
    }
    return $parsed
}

proc ::stage1e::controller::_read_declarative_dict {path label} {
    set normalized_path [file normalize $path]
    if {![file exists $normalized_path] ||
        ![file isfile $normalized_path]} {
        error "$label file not found: $normalized_path"
    }
    set channel [open $normalized_path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} text read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $text
    }
    if {$close_status != 0} {
        error "Unable to close $label file: $close_error"
    }
    set text [string trim $text]
    if {$text eq {}} {
        error "$label file is empty: $normalized_path"
    }
    if {[catch {dict size $text} parse_error]} {
        error "$label is not a declarative Tcl dictionary: $parse_error"
    }
    return $text
}

proc ::stage1e::controller::_resolve_repository_file {
    repository_root
    relative_path
    label
} {
    if {[file pathtype $relative_path] ne {relative}} {
        error "$label path must be repository-relative: $relative_path"
    }
    foreach component [file split [string map {\\ /} $relative_path]] {
        if {$component in {. ..}} {
            error "$label path contains a disallowed component: $relative_path"
        }
    }
    set resolved [file normalize [file join $repository_root $relative_path]]
    if {![::stage1d::controller_core::_is_equal_or_descendant \
        $resolved $repository_root]} {
        error "$label path escapes the repository: $relative_path"
    }
    if {![file exists $resolved] || ![file isfile $resolved]} {
        error "$label file is unavailable: $resolved"
    }
    return $resolved
}

proc ::stage1e::controller::_append_unique {base additions label} {
    set combined $base
    set seen [dict create]
    foreach item $base {
        if {[dict exists $seen $item]} {
            error "Duplicate $label entry in referenced inventory: $item"
        }
        dict set seen $item 1
    }
    foreach item $additions {
        if {[dict exists $seen $item]} {
            error "Duplicate $label extension entry: $item"
        }
        dict set seen $item 1
        lappend combined $item
    }
    return $combined
}

proc ::stage1e::controller::_inventory_contains_file {
    repository_root
    relative_paths
    candidate_path
} {
    set candidate_components \
        [::stage1d::controller_core::_canonical_components $candidate_path]
    foreach relative_path $relative_paths {
        lassign [::stage1d::source_check::_resolve_repository_path \
            $repository_root $relative_path] _ inventory_path
        if {[::stage1d::controller_core::_canonical_components \
            $inventory_path] eq $candidate_components} {
            return 1
        }
    }
    return 0
}

proc ::stage1e::controller::_assert_dictionary_keys {
    label
    dictionary
    expected_keys
} {
    if {[catch {dict size $dictionary} dictionary_error]} {
        error "$label is not a dictionary: $dictionary_error"
    }
    set actual [lsort -dictionary [dict keys $dictionary]]
    set expected [lsort -dictionary $expected_keys]
    if {$actual ne $expected} {
        error "$label keys mismatch: expected=$expected actual=$actual"
    }
    return 1
}

proc ::stage1e::controller::_assert_exact_dictionary {
    label
    actual
    expected
} {
    _assert_dictionary_keys $label $actual [dict keys $expected]
    foreach key [dict keys $expected] {
        if {[dict get $actual $key] ne [dict get $expected $key]} {
            error "$label value mismatch: $key"
        }
    }
    return 1
}

proc ::stage1e::controller::_validate_disabled_capability_flags {
    flags
    label
} {
    set expected [disabled_capabilities]
    _assert_dictionary_keys $label $flags [dict keys $expected]
    foreach capability [dict keys $expected] {
        set value [dict get $flags $capability]
        if {![string is boolean -strict $value] || $value} {
            error "$label requires $capability=0."
        }
    }
    return 1
}

proc ::stage1e::controller::configuration_disabled_capabilities {
    configuration
} {
    return [dict get $configuration disabled_capabilities flags]
}

proc ::stage1e::controller::validate_configuration {configuration} {
    variable configuration_schema_version
    variable controller_version
    variable controller_api_version
    variable execution_id_schema_version
    variable phase_evidence_schema_version
    variable initial_phase_order

    foreach required_key {
        schema_version
        build_profile
        build_profile_identity
        skeleton_scope
        controller_version
        controller_api_version
        execution_id_schema_version
        phase_evidence_schema_version
        manifest_schema_version
        source_inventory_reference
        source_inventory_extensions
        build_phases
        disabled_capabilities
        future_phase_boundaries
        artifact_roles
        workspace_policy
        acceptance_policy_reference
    } {
        if {![dict exists $configuration $required_key]} {
            error "Stage 1E configuration is missing key: $required_key"
        }
    }

    foreach {field expected} [list \
        schema_version $configuration_schema_version \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        execution_id_schema_version $execution_id_schema_version \
        phase_evidence_schema_version $phase_evidence_schema_version] {
        if {[dict get $configuration $field] ne $expected} {
            error "Unsupported Stage 1E $field: [dict get $configuration $field]"
        }
    }
    if {[dict get $configuration build_profile] ne \
        {stage1e_controller_skeleton}} {
        error {Unsupported Stage 1E build profile.}
    }
    _assert_exact_dictionary {Stage 1E build profile identity} \
        [dict get $configuration build_profile_identity] \
        [build_profile_identity]
    _assert_exact_dictionary {Stage 1E skeleton scope} \
        [dict get $configuration skeleton_scope] [skeleton_scope]

    set reference [dict get $configuration source_inventory_reference]
    foreach field {schema_version path source_section environment_section} {
        if {![dict exists $reference $field] ||
            [string trim [dict get $reference $field]] eq {}} {
            error "Stage 1E source inventory reference is missing: $field"
        }
    }
    if {[dict get $reference schema_version] ne {v1}} {
        error {Unsupported source inventory reference schema.}
    }

    set extensions [dict get $configuration source_inventory_extensions]
    _assert_dictionary_keys {Stage 1E source inventory extensions} \
        $extensions {
            schema_version
            extension_mechanism
            required_paths
            tcl_paths
            controller_source_paths
            expected_controller_source_sha256
        }
    foreach field {
        required_paths
        tcl_paths
        controller_source_paths
        expected_controller_source_sha256
    } {
        if {![dict exists $extensions $field]} {
            error "Stage 1E source inventory extensions are missing: $field"
        }
    }
    if {[dict get $extensions schema_version] ne \
        {stage1e-source-inventory-extension-v1} ||
        [dict get $extensions extension_mechanism] ne {APPEND_ONLY}} {
        error {Unsupported Stage 1E source inventory extension mechanism.}
    }
    if {![regexp {^[0-9A-Fa-f]{64}$} [dict get \
        $extensions expected_controller_source_sha256]]} {
        error {Stage 1E expected controller source SHA-256 is invalid.}
    }

    set phases [dict get $configuration build_phases]
    _assert_dictionary_keys {Stage 1E build phases} $phases {
        schema_version
        phase_order
    }
    if {[dict get $phases schema_version] ne \
        {stage1e-readiness-phase-model-v1}} {
        error {Unsupported Stage 1E readiness phase model.}
    }
    if {[list {*}[dict get $phases phase_order]] ne \
        [list {*}$initial_phase_order]} {
        error {Stage 1E initial phase order does not match the controller contract.}
    }

    set capability_configuration \
        [dict get $configuration disabled_capabilities]
    _assert_dictionary_keys {Stage 1E disabled capabilities} \
        $capability_configuration {schema_version flags}
    if {[dict get $capability_configuration schema_version] ne \
        {stage1e-disabled-capabilities-v1}} {
        error {Unsupported Stage 1E disabled capability schema.}
    }
    set capability_flags [dict get $capability_configuration flags]
    _validate_disabled_capability_flags \
        $capability_flags {Stage 1E disabled capabilities}

    set future_boundaries [dict get \
        $configuration future_phase_boundaries]
    _assert_dictionary_keys {Stage 1E future phase boundaries} \
        $future_boundaries {
            schema_version
            default_transition_policy
            phase_capability_map
        }
    if {[dict get $future_boundaries schema_version] ne \
        {stage1e-future-phase-boundaries-v1} ||
        [dict get $future_boundaries default_transition_policy] ne {DENY}} {
        error {Unsupported Stage 1E future phase boundary policy.}
    }
    set configured_future_map [dict get \
        $future_boundaries phase_capability_map]
    _assert_exact_dictionary {Stage 1E future phase capability map} \
        $configured_future_map [future_phase_boundaries]
    foreach capability [dict values $configured_future_map] {
        if {![dict exists $capability_flags $capability] ||
            [dict get $capability_flags $capability]} {
            error "Future Stage 1E capability is not disabled: $capability"
        }
    }

    set artifact_configuration [dict get $configuration artifact_roles]
    _assert_dictionary_keys {Stage 1E artifact role configuration} \
        $artifact_configuration {schema_version placeholders}
    if {[dict get $artifact_configuration schema_version] ne \
        {stage1e-artifact-role-placeholders-v1}} {
        error {Unsupported Stage 1E artifact role placeholder schema.}
    }
    set roles [dict get $artifact_configuration placeholders]
    if {[lsort -dictionary [dict keys $roles]] ne {bit hwh ltx xsa}} {
        error {Stage 1E artifact roles must be exactly bit, hwh, ltx, and xsa.}
    }
    set expected_extensions [dict create \
        bit .bit hwh .hwh xsa .xsa ltx .ltx]
    set expected_acceptance [dict create \
        bit REQUIRED hwh REQUIRED xsa REQUIRED \
        ltx CONDITIONAL_DEBUG]
    foreach role [dict keys $roles] {
        set role_definition [dict get $roles $role]
        set role_fields {
            extension
            future_acceptance
            placeholder
            generation_enabled
            collection_enabled
            publication_enabled
        }
        _assert_dictionary_keys "Stage 1E artifact role $role" \
            $role_definition $role_fields
        if {[dict get $role_definition extension] ne \
            [dict get $expected_extensions $role] ||
            [dict get $role_definition future_acceptance] ne \
            [dict get $expected_acceptance $role]} {
            error "Stage 1E artifact role identity mismatch: $role"
        }
        if {![string is boolean -strict \
            [dict get $role_definition placeholder]] ||
            ![dict get $role_definition placeholder]} {
            error "Stage 1E artifact role $role must remain a placeholder."
        }
        foreach disabled_field {
            generation_enabled
            collection_enabled
            publication_enabled
        } {
            set value [dict get $role_definition $disabled_field]
            if {![string is boolean -strict $value] || $value} {
                error "Stage 1E artifact role $role requires $disabled_field=0."
            }
        }
    }

    set workspace_policy [dict get $configuration workspace_policy]
    foreach field {
        ownership_schema_version
        require_external_workspace
        require_separate_artifact_storage
        require_fresh_execution_workspace
        phase_evidence_relative_path
        stale_vivado_markers
    } {
        if {![dict exists $workspace_policy $field]} {
            error "Stage 1E workspace policy is missing: $field"
        }
    }
    foreach true_field {
        require_external_workspace
        require_separate_artifact_storage
        require_fresh_execution_workspace
    } {
        set value [dict get $workspace_policy $true_field]
        if {![string is boolean -strict $value] || !$value} {
            error "Stage 1E workspace policy requires $true_field=1."
        }
    }

    set acceptance [dict get $configuration acceptance_policy_reference]
    foreach field {schema_version path} {
        if {![dict exists $acceptance $field] ||
            [string trim [dict get $acceptance $field]] eq {}} {
            error "Stage 1E acceptance policy reference is missing: $field"
        }
    }
    return 1
}

proc ::stage1e::controller::load_configuration {
    configuration_path
    repository_root
} {
    set repository_root [file normalize $repository_root]
    if {![file isdirectory $repository_root]} {
        error "Repository root is not an existing directory: $repository_root"
    }
    set configuration_path [file normalize $configuration_path]
    if {![::stage1d::controller_core::_is_equal_or_descendant \
        $configuration_path $repository_root]} {
        error {Stage 1E configuration must be located in the repository.}
    }
    set configuration [_read_declarative_dict \
        $configuration_path {Stage 1E configuration}]
    validate_configuration $configuration

    set reference [dict get $configuration source_inventory_reference]
    set reference_path [_resolve_repository_file \
        $repository_root [dict get $reference path] \
        {Source inventory reference}]
    set referenced_configuration [_read_declarative_dict \
        $reference_path {Referenced Stage 1D configuration}]

    set source_section [dict get $reference source_section]
    set environment_section [dict get $reference environment_section]
    if {![dict exists $referenced_configuration $source_section]} {
        error "Referenced source section is unavailable: $source_section"
    }
    if {![dict exists $referenced_configuration $environment_section]} {
        error "Referenced environment section is unavailable: $environment_section"
    }

    set source_verification [dict get \
        $referenced_configuration $source_section]
    set extensions [dict get $configuration source_inventory_extensions]
    foreach list_field {required_paths tcl_paths controller_source_paths} {
        dict set source_verification $list_field [_append_unique \
            [dict get $source_verification $list_field] \
            [dict get $extensions $list_field] $list_field]
    }
    dict set source_verification expected_controller_source_sha256 \
        [string tolower [dict get \
            $extensions expected_controller_source_sha256]]

    set acceptance_path [_resolve_repository_file \
        $repository_root [dict get \
            $configuration acceptance_policy_reference path] \
        {Acceptance policy reference}]

    set reviewed_paths [dict get $source_verification required_paths]
    foreach {input_path input_label} [list \
        $configuration_path {Stage 1E configuration} \
        $reference_path {Referenced source inventory} \
        $acceptance_path {Acceptance policy}] {
        if {![_inventory_contains_file \
            $repository_root $reviewed_paths $input_path]} {
            error "$input_label is not included in the reviewed source inventory."
        }
    }

    dict set configuration source_verification $source_verification
    dict set configuration environment [dict get \
        $referenced_configuration $environment_section]
    dict set configuration workspace [dict create \
        ownership_schema_version [dict get \
            $configuration workspace_policy ownership_schema_version] \
        stale_vivado_markers [dict get \
            $configuration workspace_policy stale_vivado_markers]]
    dict set configuration configuration_path $configuration_path
    dict set configuration referenced_configuration_path $reference_path
    dict set configuration acceptance_policy_path $acceptance_path
    return $configuration
}

proc ::stage1e::controller::generate_execution_identity {
    candidate_git_commit
    {epoch_seconds {}}
} {
    variable controller_version
    variable controller_api_version
    variable execution_id_schema_version

    set normalized_commit \
        [::stage1d::controller_core::_validate_candidate_git_commit \
            $candidate_git_commit]
    if {$epoch_seconds eq {}} {
        set epoch_seconds [clock seconds]
    }
    if {![string is integer -strict $epoch_seconds]} {
        error {Stage 1E execution identifier epoch must be an integer.}
    }
    set timestamp [clock format $epoch_seconds -gmt 1 \
        -format {%Y%m%d-%H%M%S}]
    set generated_at [::stage1d::logger::utc_timestamp $epoch_seconds]
    set git_short [string range $normalized_commit 0 6]
    set execution_identifier "STAGE1E-$timestamp-$git_short"

    return [dict create \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        skeleton_scope_id [dict get [skeleton_scope] scope_id] \
        execution_id_schema_version $execution_id_schema_version \
        execution_identifier $execution_identifier \
        generated_at $generated_at \
        candidate_git_commit $normalized_commit \
        git_short $git_short]
}

proc ::stage1e::controller::new_stage1e_context {
    parsed_arguments
    configuration
    execution_identity
} {
    return [dict create \
        context_boundary [context_boundary] \
        build_profile_identity [build_profile_identity] \
        skeleton_scope [skeleton_scope] \
        disabled_capabilities \
            [configuration_disabled_capabilities $configuration] \
        parsed_arguments $parsed_arguments \
        configuration $configuration \
        execution_identity $execution_identity]
}

proc ::stage1e::controller::validate_stage1e_context {context} {
    set required_fields {
        context_boundary
        build_profile_identity
        skeleton_scope
        disabled_capabilities
        parsed_arguments
        configuration
        execution_identity
    }
    set allowed_fields [concat $required_fields {
        input_validation_outputs
        source_result
        source_verification
        environment_result
        environment_verification
        workspace_result
        workspace_verification
    }]
    foreach field $required_fields {
        if {![dict exists $context $field]} {
            error "Stage 1E context is missing boundary field: $field"
        }
    }
    foreach field [dict keys $context] {
        if {$field ni $allowed_fields} {
            error "Stage 1E context contains an unowned field: $field"
        }
    }
    _assert_exact_dictionary {Stage 1E context boundary} \
        [dict get $context context_boundary] [context_boundary]
    _assert_exact_dictionary {Stage 1E context build profile} \
        [dict get $context build_profile_identity] \
        [build_profile_identity]
    _assert_exact_dictionary {Stage 1E context skeleton scope} \
        [dict get $context skeleton_scope] [skeleton_scope]
    _validate_disabled_capability_flags \
        [dict get $context disabled_capabilities] \
        {Stage 1E context disabled capabilities}

    set configuration [dict get $context configuration]
    _assert_exact_dictionary {Stage 1E context/configuration profile binding} \
        [dict get $context build_profile_identity] \
        [dict get $configuration build_profile_identity]
    _assert_exact_dictionary {Stage 1E context/configuration scope binding} \
        [dict get $context skeleton_scope] \
        [dict get $configuration skeleton_scope]
    _assert_exact_dictionary \
        {Stage 1E context/configuration capability binding} \
        [dict get $context disabled_capabilities] \
        [configuration_disabled_capabilities $configuration]
    if {[dict get $context execution_identity skeleton_scope_id] ne \
        [dict get $context skeleton_scope scope_id]} {
        error {Stage 1E execution identity is outside the skeleton scope.}
    }

    foreach {result_field output_field} {
        source_result source_verification
        environment_result environment_verification
        workspace_result workspace_verification
    } {
        if {[dict exists $context $result_field] != \
            [dict exists $context $output_field]} {
            error "Stage 1E context has an incomplete result boundary: $result_field"
        }
        if {[dict exists $context $result_field] &&
            [dict get $context $result_field outputs] ne \
            [dict get $context $output_field]} {
            error "Stage 1E context result binding mismatch: $result_field"
        }
    }
    if {[dict exists $context environment_result] &&
        ![dict exists $context source_result]} {
        error {Stage 1E environment context exists without source context.}
    }
    if {[dict exists $context workspace_result] &&
        ![dict exists $context environment_result]} {
        error {Stage 1E workspace context exists without environment context.}
    }
    return 1
}

proc ::stage1e::controller::_operation_context {
    operation_key
    context
} {
    validate_stage1e_context $context
    switch -- $operation_key {
        source_validate {
            set fields {
                parsed_arguments
                configuration
                execution_identity
                input_validation_outputs
            }
        }
        environment_validate {
            set fields {
                parsed_arguments
                configuration
                source_verification
            }
        }
        workspace_create {
            set fields {
                parsed_arguments
                configuration
                execution_identity
                input_validation_outputs
                source_verification
                environment_verification
            }
        }
        default {
            return $context
        }
    }
    set adapted [dict create]
    foreach field $fields {
        if {![dict exists $context $field]} {
            error "Stage 1D operation context is missing: $field"
        }
        dict set adapted $field [dict get $context $field]
    }
    return $adapted
}

proc ::stage1e::controller::new_state {execution_identity} {
    return [dict create \
        execution_identifier [dict get \
            $execution_identity execution_identifier] \
        current_state INIT \
        history {}]
}

proc ::stage1e::controller::current_state {state} {
    return [dict get $state current_state]
}

proc ::stage1e::controller::_force_terminal_state {state_variable state_name} {
    upvar 1 $state_variable state
    if {$state_name ni {FAIL BLOCKED}} {
        error "Invalid Stage 1E terminal state: $state_name"
    }
    dict set state current_state $state_name
}

proc ::stage1e::controller::transition {
    state_variable
    next_state
    evidence
} {
    variable forward_transitions
    variable forbidden_states
    variable terminal_states
    upvar 1 $state_variable state

    set future_boundaries [future_phase_boundaries]
    if {[dict exists $future_boundaries $next_state]} {
        error "Stage 1E skeleton scope blocks future phase $next_state ([dict get $future_boundaries $next_state])."
    }
    if {$next_state in $forbidden_states} {
        error "Stage 1E controller skeleton forbids transition to $next_state."
    }
    set current [dict get $state current_state]
    if {$current in $terminal_states} {
        error "Stage 1E terminal state cannot transition: $current"
    }
    if {$next_state in $terminal_states} {
        set allowed 1
    } else {
        set allowed [expr {
            [dict exists $forward_transitions $current] &&
            [dict get $forward_transitions $current] eq $next_state
        }]
    }
    if {!$allowed} {
        error "Illegal Stage 1E transition: $current -> $next_state"
    }
    ::stage1d::phase_runner::validate_evidence $evidence
    if {[dict get $evidence execution_identifier] ne \
        [dict get $state execution_identifier]} {
        error {Stage 1E phase evidence execution identity mismatch.}
    }
    set status [dict get $evidence status]
    if {$next_state eq {FAIL} && $status ne {FAIL}} {
        error {Stage 1E FAIL transition requires FAIL evidence.}
    }
    if {$next_state eq {BLOCKED} &&
        $status ni {BLOCKED SKIPPED_DEPENDENCY}} {
        error {Stage 1E BLOCKED transition requires blocked evidence.}
    }
    if {$next_state ni $terminal_states && $status ne {PASS}} {
        error "Stage 1E forward transition to $next_state requires PASS."
    }
    dict lappend state history [dict create \
        prior_state $current \
        next_state $next_state \
        phase_name [dict get $evidence phase_name] \
        phase_status $status \
        transition_time [dict get $evidence end_time]]
    dict set state current_state $next_state
}

proc ::stage1e::controller::_error_record {
    error_code
    category
    phase_name
    message
    {underlying_error {}}
} {
    return [dict create \
        error_code $error_code \
        category $category \
        phase_name $phase_name \
        message $message \
        underlying_error $underlying_error \
        evidence_references {} \
        recoverability NONE]
}

proc ::stage1e::controller::_phase_result {
    status
    outputs
    {errors {}}
    {evidence_locations {}}
} {
    return [dict create \
        status $status \
        evidence_locations $evidence_locations \
        logs {} \
        reports {} \
        errors $errors \
        outputs $outputs \
        artifact_references {}]
}

proc ::stage1e::controller::disabled_execution_status {} {
    return [dict create \
        build_execution_authorized 0 \
        ip_packaging_invoked 0 \
        project_reconstruction_invoked 0 \
        project_opened 0 \
        project_created 0 \
        bd_generation_invoked 0 \
        bd_created 0 \
        wrapper_generation_invoked 0 \
        wrapper_generated 0 \
        synthesis_invoked 0 \
        implementation_invoked 0 \
        artifact_generation_invoked 0 \
        artifact_collection_invoked 0 \
        publication_invoked 0 \
        vivado_invoked 0 \
        board_accessed 0 \
        bitstream_generated 0 \
        hwh_generated 0 \
        xsa_exported 0 \
        ltx_generated 0 \
        artifacts_generated 0 \
        manifest_published 0]
}

proc ::stage1e::controller::phase_input_ready {context} {
    set parsed [dict get $context parsed_arguments]
    set execution_identity [dict get $context execution_identity]
    set repository_root [file normalize [dict get $parsed repository_root]]
    set build_workspace_root [file normalize \
        [dict get $parsed build_workspace]]
    set artifact_storage_root [file normalize \
        [dict get $parsed artifact_storage]]

    if {![file isdirectory $repository_root]} {
        error "Repository root is unavailable: $repository_root"
    }
    if {[::stage1d::controller_core::_paths_overlap \
        $repository_root $build_workspace_root]} {
        error {Build workspace must be external to the repository.}
    }
    if {[::stage1d::controller_core::_paths_overlap \
        $repository_root $artifact_storage_root]} {
        error {Artifact storage must be external to the repository.}
    }
    if {[::stage1d::controller_core::_paths_overlap \
        $build_workspace_root $artifact_storage_root]} {
        error {Build workspace and artifact storage must be separate.}
    }
    set locations \
        [::stage1d::controller_core::_assert_execution_identifier_available \
            [dict get $execution_identity execution_identifier] \
            $build_workspace_root $artifact_storage_root]

    return [_phase_result PASS [dict merge [dict create \
        repository_root $repository_root \
        build_workspace_root $build_workspace_root \
        artifact_storage_root $artifact_storage_root \
        collision_check_result PASS \
        workspace_created 0] [disabled_execution_status] $locations]]
}

proc ::stage1e::controller::_require_true {outputs field label} {
    if {![dict exists $outputs $field] ||
        ![string is boolean -strict [dict get $outputs $field]] ||
        ![dict get $outputs $field]} {
        error "$label requires true field: $field"
    }
}

proc ::stage1e::controller::_require_false {outputs field label} {
    if {![dict exists $outputs $field] ||
        ![string is boolean -strict [dict get $outputs $field]] ||
        [dict get $outputs $field]} {
        error "$label requires false field: $field"
    }
}

proc ::stage1e::controller::validate_source_context {result} {
    if {[dict get $result status] ne {PASS}} {
        error {Stage 1E source context must have PASS status.}
    }
    set outputs [dict get $result outputs]
    if {![dict exists $outputs git_commit] ||
        ![regexp {^[0-9A-Fa-f]{40}$} [dict get $outputs git_commit]]} {
        error {Stage 1E source context has an invalid Git commit identity.}
    }
    foreach field {controller_source_hash configuration_hash} {
        if {![dict exists $outputs $field] ||
            ![regexp {^[0-9A-Fa-f]{64}$} [dict get $outputs $field]]} {
            error "Stage 1E source context has invalid SHA-256 identity: $field"
        }
    }
    _require_true $outputs worktree_clean {Stage 1E source context}
    _require_true $outputs source_state_frozen {Stage 1E source context}
    return 1
}

proc ::stage1e::controller::validate_environment_context {result} {
    if {[dict get $result status] ne {PASS}} {
        error {Stage 1E environment context must have PASS status.}
    }
    set outputs [dict get $result outputs]
    foreach field {
        environment_verified
        vivado_identity_verified
        target_identity_verified
        required_ip_verified
    } {
        _require_true $outputs $field {Stage 1E environment context}
    }
    if {![dict exists $outputs custom_protection_ip_provenance]} {
        error {Stage 1E environment context lacks custom IP provenance.}
    }
    if {![dict exists $outputs environment_evidence_hash] ||
        ![regexp {^[0-9A-Fa-f]{64}$} \
            [dict get $outputs environment_evidence_hash]]} {
        error {Stage 1E environment evidence SHA-256 is invalid.}
    }
    set custom_ip [dict get $outputs custom_protection_ip_provenance]
    _require_false $custom_ip packaged_ip_created \
        {Stage 1E environment custom IP context}
    _require_false $custom_ip catalog_identity_verified \
        {Stage 1E environment custom IP context}
    if {![dict exists $custom_ip source_git_commit] ||
        ![regexp {^[0-9A-Fa-f]{40}$} \
            [dict get $custom_ip source_git_commit]]} {
        error {Stage 1E environment custom IP source identity is invalid.}
    }
    return 1
}

proc ::stage1e::controller::validate_workspace_context {result} {
    if {[dict get $result status] ne {PASS}} {
        error {Stage 1E workspace context must have PASS status.}
    }
    set outputs [dict get $result outputs]
    _require_true $outputs workspace_created {Stage 1E workspace context}
    _require_true $outputs ownership_bound {Stage 1E workspace context}
    _require_false $outputs project_created {Stage 1E workspace context}
    _require_false $outputs artifacts_generated {Stage 1E workspace context}
    foreach field {
        execution_workspace
        artifact_group
        ownership_evidence
        ownership_binding
    } {
        if {![dict exists $outputs $field] ||
            [string trim [dict get $outputs $field]] eq {}} {
            error "Stage 1E workspace context is missing: $field"
        }
    }
    return 1
}

proc ::stage1e::controller::_assert_no_build_side_effects {result label} {
    if {[dict exists $result artifact_references] &&
        [llength [dict get $result artifact_references]] != 0} {
        error "$label returned artifact references in the controller skeleton."
    }
    set outputs [dict get $result outputs]
    foreach field {
        ip_packaging_invoked
        project_reconstruction_invoked
        project_opened
        project_created
        bd_generation_invoked
        bd_created
        wrapper_generation_invoked
        wrapper_generated
        synthesis_invoked
        implementation_invoked
        artifact_generation_invoked
        artifact_collection_invoked
        publication_invoked
        vivado_invoked
        board_accessed
        bitstream_generated
        hwh_generated
        xsa_exported
        ltx_generated
        artifacts_generated
        manifest_published
        artifact_publication_complete
    } {
        if {[dict exists $outputs $field] &&
            (![string is boolean -strict [dict get $outputs $field]] ||
            [dict get $outputs $field])} {
            error "$label reported forbidden build side effect: $field"
        }
    }
    return 1
}

proc ::stage1e::controller::phase_build_controller_ready {context} {
    validate_stage1e_context $context
    set configuration [dict get $context configuration]
    _validate_disabled_capability_flags \
        [configuration_disabled_capabilities $configuration] \
        {Build controller readiness capabilities}
    validate_source_context [dict get $context source_result]
    validate_environment_context [dict get $context environment_result]
    validate_workspace_context [dict get $context workspace_result]
    set source_commit [string tolower [dict get \
        $context source_verification git_commit]]
    set environment_commit [string tolower [dict get $context \
        environment_verification custom_protection_ip_provenance \
        source_git_commit]]
    if {$source_commit ne $environment_commit} {
        error {Source and environment execution identities do not match.}
    }
    set ownership [dict get \
        $context workspace_verification ownership_binding]
    foreach {ownership_field context_field} {
        git_commit git_commit
        controller_source_hash controller_source_hash
        configuration_hash configuration_hash
    } {
        if {[dict get $ownership $ownership_field] ne \
            [dict get $context source_verification $context_field]} {
            error "Workspace ownership identity mismatch: $ownership_field"
        }
    }
    if {[dict get $ownership environment_evidence_hash] ne \
        [dict get $context environment_verification \
            environment_evidence_hash]} {
        error {Workspace ownership environment identity mismatch.}
    }
    return [_phase_result PASS [dict merge \
        [disabled_execution_status] \
        [dict create \
            skeleton_scope_id [dict get [skeleton_scope] scope_id] \
            build_controller_ready 1]]]
}

proc ::stage1e::controller::default_operations {} {
    return [dict create \
        input_ready ::stage1e::controller::phase_input_ready \
        source_validate ::stage1d::source_check::run \
        environment_validate ::stage1d::environment_check::run \
        workspace_create ::stage1d::workspace_manager::run \
        controller_ready ::stage1e::controller::phase_build_controller_ready \
        persist_evidence ::stage1e::controller::persist_phase_evidence]
}

proc ::stage1e::controller::_resolve_operations {overrides} {
    set operations [default_operations]
    if {[catch {dict size $overrides} override_error]} {
        error "Stage 1E operation overrides are not a dictionary: $override_error"
    }
    foreach key [dict keys $overrides] {
        if {![dict exists $operations $key]} {
            error "Unknown Stage 1E operation override: $key"
        }
        set command [dict get $overrides $key]
        if {[llength $command] == 0 ||
            [llength [info commands [lindex $command 0]]] != 1} {
            error "Stage 1E operation override is unavailable: $key"
        }
        dict set operations $key $command
    }
    return $operations
}

proc ::stage1e::controller::_execute_operation {
    operation_key
    operations
    context
} {
    set command [dict get $operations $operation_key]
    set operation_context [_operation_context $operation_key $context]
    set result [uplevel #0 [linsert $command end $operation_context]]
    if {[catch {dict size $result} dictionary_error]} {
        error "Stage 1E $operation_key result is not a dictionary: $dictionary_error"
    }
    if {![dict exists $result status] ||
        [dict get $result status] ni {PASS FAIL BLOCKED SKIPPED_DEPENDENCY}} {
        error "Stage 1E $operation_key result has invalid status."
    }
    foreach field {
        evidence_locations logs reports errors outputs artifact_references
    } {
        if {![dict exists $result $field]} {
            error "Stage 1E $operation_key result is missing: $field"
        }
    }
    _assert_no_build_side_effects $result $operation_key
    if {[dict get $result status] eq {PASS}} {
        switch -- $operation_key {
            source_validate { validate_source_context $result }
            environment_validate { validate_environment_context $result }
            workspace_create { validate_workspace_context $result }
        }
    }
    return $result
}

proc ::stage1e::controller::_status_severity {status} {
    switch -- $status {
        PASS { return INFO }
        BLOCKED -
        SKIPPED_DEPENDENCY { return WARNING }
        default { return ERROR }
    }
}

proc ::stage1e::controller::_emit_log {log_record} {
    puts [list STAGE1E_LOG $log_record]
}

proc ::stage1e::controller::run_phase {
    state_variable
    logger_variable
    operation_key
    phase_name
    success_state
    operations
    context
} {
    upvar 1 $state_variable state
    upvar 1 $logger_variable logger
    variable controller_version
    variable controller_api_version
    variable execution_id_schema_version
    variable phase_evidence_schema_version

    set execution_identifier [dict get $state execution_identifier]
    set start_time [::stage1d::logger::utc_timestamp]
    set start_log [::stage1d::logger::record \
        logger $phase_name INFO PHASE_START \
        "Stage 1E phase started: $phase_name" $start_time]
    _emit_log $start_log

    set callback_status [catch {
        _execute_operation $operation_key $operations $context
    } callback_result callback_options]
    if {$callback_status != 0} {
        set status FAIL
        set error_info {}
        if {[dict exists $callback_options -errorinfo]} {
            set error_info [dict get $callback_options -errorinfo]
        }
        set callback_result [_phase_result FAIL {} [list [_error_record \
            STAGE1E_PHASE_CALLBACK_ERROR CORE $phase_name \
            "Stage 1E phase failed closed: $callback_result" \
            $error_info]]]
    } else {
        set status [dict get $callback_result status]
    }

    set end_time [::stage1d::logger::utc_timestamp]
    set evidence [dict create \
        phase_evidence_schema_version $phase_evidence_schema_version \
        skeleton_scope_id [dict get \
            $context skeleton_scope scope_id] \
        context_schema_version [dict get \
            $context context_boundary schema_version] \
        phase_name $phase_name \
        status $status \
        start_time $start_time \
        end_time $end_time \
        execution_id_schema_version $execution_id_schema_version \
        execution_identifier $execution_identifier \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        evidence_locations [dict get $callback_result evidence_locations] \
        logs [dict get $callback_result logs] \
        reports [dict get $callback_result reports] \
        errors [dict get $callback_result errors] \
        outputs [dict get $callback_result outputs] \
        artifact_references [dict get $callback_result artifact_references]]

    set validation_status [catch {
        ::stage1d::phase_runner::validate_evidence \
            $evidence $phase_name $execution_identifier
    } validation_error validation_options]
    if {$validation_status != 0} {
        set status FAIL
        dict set evidence status FAIL
        dict set evidence evidence_locations {}
        dict set evidence reports {}
        dict set evidence outputs {}
        dict set evidence artifact_references {}
        dict set evidence errors [list [_error_record \
            STAGE1E_PHASE_EVIDENCE_INVALID EVIDENCE $phase_name \
            "Stage 1E phase evidence is invalid: $validation_error"]]
    }

    if {$status eq {PASS}} {
        set target_state $success_state
    } elseif {$status in {BLOCKED SKIPPED_DEPENDENCY}} {
        set target_state BLOCKED
    } else {
        set target_state FAIL
    }
    if {[catch {transition state $target_state $evidence} transition_error]} {
        set status FAIL
        dict set evidence status FAIL
        dict lappend evidence errors [_error_record \
            STAGE1E_STATE_TRANSITION_INVALID STATE $phase_name \
            "Stage 1E transition failed: $transition_error"]
        _force_terminal_state state FAIL
    }

    set end_log [::stage1d::logger::record \
        logger $phase_name [_status_severity $status] PHASE_END \
        "Stage 1E phase completed with $status: $phase_name" $end_time]
    _emit_log $end_log
    set evidence_logs [list $start_log]
    foreach callback_log [dict get $evidence logs] {
        lappend evidence_logs $callback_log
    }
    lappend evidence_logs $end_log
    dict set evidence logs $evidence_logs
    ::stage1d::phase_runner::validate_evidence \
        $evidence $phase_name $execution_identifier
    return [dict create evidence $evidence callback_result $callback_result]
}

proc ::stage1e::controller::_write_exclusive {path content} {
    set channel [open $path {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    set write_status [catch {
        puts $channel $content
    } write_error write_options]
    set close_status [catch {close $channel} close_error]
    if {$write_status != 0} {
        return -options $write_options $write_error
    }
    if {$close_status != 0} {
        error "Unable to close Stage 1E evidence file: $close_error"
    }
}

proc ::stage1e::controller::persist_phase_evidence {
    context
    phase_evidence
    state
} {
    validate_stage1e_context $context
    set configuration [dict get $context configuration]
    set workspace_outputs [dict get $context workspace_verification]
    set execution_workspace [file normalize \
        [dict get $workspace_outputs execution_workspace]]
    set relative_path [dict get \
        $configuration workspace_policy phase_evidence_relative_path]
    if {[file pathtype $relative_path] ne {relative}} {
        error {Stage 1E phase evidence path must be workspace-relative.}
    }
    set evidence_path [file normalize \
        [file join $execution_workspace $relative_path]]
    if {![::stage1d::controller_core::_is_equal_or_descendant \
        $evidence_path $execution_workspace]} {
        error {Stage 1E phase evidence path escapes the execution workspace.}
    }
    if {![file isdirectory [file dirname $evidence_path]]} {
        error {Stage 1E phase evidence parent directory is unavailable.}
    }

    set payload [dict create \
        schema_version [dict get $configuration phase_evidence_schema_version] \
        controller_version [version] \
        controller_api_version [api_version] \
        build_profile_identity [dict get \
            $context build_profile_identity] \
        skeleton_scope [dict get $context skeleton_scope] \
        context_boundary [dict get $context context_boundary] \
        disabled_capabilities [dict get \
            $context disabled_capabilities] \
        future_phase_boundaries [future_phase_boundaries] \
        execution_identity [dict get $context execution_identity] \
        current_state [current_state $state] \
        source_identity [dict get $context source_verification] \
        environment_identity [dict get $context environment_verification] \
        workspace_identity $workspace_outputs \
        configured_phase_order [dict get \
            $configuration build_phases phase_order] \
        phase_evidence $phase_evidence \
        disabled_execution_status [disabled_execution_status]]
    _write_exclusive $evidence_path $payload
    return [dict create \
        status PASS \
        evidence_path $evidence_path \
        evidence_relative_path $relative_path \
        evidence_sha256 \
            [::stage1d::source_check::sha256_file $evidence_path]]
}

proc ::stage1e::controller::_invoke_persistence {
    operations
    context
    phase_evidence
    state
} {
    set command [dict get $operations persist_evidence]
    set result [uplevel #0 [linsert $command end \
        $context $phase_evidence $state]]
    if {[catch {dict size $result} persistence_error] ||
        ![dict exists $result status] ||
        [dict get $result status] ne {PASS}} {
        error "Stage 1E evidence persistence failed: $result"
    }
    return $result
}

proc ::stage1e::controller::main {
    arguments
    {operation_overrides {}}
} {
    variable controller_version
    variable controller_api_version
    variable execution_id_schema_version

    set parsed [parse_arguments $arguments]
    if {[dict get $parsed help]} {
        puts [usage]
        return [dict create \
            controller_version $controller_version \
            controller_api_version $controller_api_version \
            skeleton_scope [skeleton_scope] \
            decision HELP \
            exit_code 0]
    }

    set repository_root [file normalize [dict get $parsed repository_root]]
    set configuration [load_configuration \
        [dict get $parsed configuration_path] $repository_root]
    set execution_identity [generate_execution_identity \
        [dict get $parsed candidate_git_commit]]
    set state [new_state $execution_identity]
    set logger [::stage1d::logger::new \
        [dict get $execution_identity execution_identifier] \
        $execution_id_schema_version \
        $controller_version $controller_api_version]
    set operations [_resolve_operations $operation_overrides]
    set context [new_stage1e_context \
        $parsed $configuration $execution_identity]
    validate_stage1e_context $context
    set phase_evidence {}

    set phase_specs {
        {input_ready INPUT_READY INPUT_READY}
        {source_validate SOURCE_VALIDATED SOURCE_VALIDATED}
        {environment_validate ENVIRONMENT_VALIDATED ENVIRONMENT_VALIDATED}
        {workspace_create WORKSPACE_READY WORKSPACE_READY}
        {controller_ready BUILD_CONTROLLER_READY BUILD_CONTROLLER_READY}
    }
    foreach phase_spec $phase_specs {
        if {[current_state $state] in {FAIL BLOCKED}} {
            break
        }
        lassign $phase_spec operation_key phase_name success_state
        set phase_run [run_phase \
            state logger $operation_key $phase_name $success_state \
            $operations $context]
        set evidence [dict get $phase_run evidence]
        set callback_result [dict get $phase_run callback_result]
        lappend phase_evidence $evidence
        if {[dict get $evidence status] ne {PASS}} {
            continue
        }
        switch -- $success_state {
            INPUT_READY {
                dict set context input_validation_outputs \
                    [dict get $callback_result outputs]
            }
            SOURCE_VALIDATED {
                dict set context source_result $callback_result
                dict set context source_verification \
                    [dict get $callback_result outputs]
            }
            ENVIRONMENT_VALIDATED {
                dict set context environment_result $callback_result
                dict set context environment_verification \
                    [dict get $callback_result outputs]
            }
            WORKSPACE_READY {
                dict set context workspace_result $callback_result
                dict set context workspace_verification \
                    [dict get $callback_result outputs]
            }
        }
        validate_stage1e_context $context
    }

    set persistence_result [dict create \
        status NOT_ATTEMPTED evidence_path {} evidence_sha256 {}]
    if {[dict exists $context workspace_verification]} {
        set persistence_status [catch {
            _invoke_persistence \
                $operations $context $phase_evidence $state
        } persistence_result persistence_options]
        if {$persistence_status != 0} {
            set persistence_result [dict create \
                status FAIL \
                evidence_path {} \
                evidence_sha256 {} \
                error_message $persistence_result]
            _force_terminal_state state FAIL
        }
    }

    set final_state [current_state $state]
    switch -- $final_state {
        BUILD_CONTROLLER_READY {
            if {[dict get $persistence_result status] ne {PASS}} {
                set decision FAIL
                set reason_code PHASE_EVIDENCE_NOT_PERSISTED
                set exit_code 1
            } else {
                set decision READY
                set reason_code BUILD_CONTROLLER_SKELETON_READY
                set exit_code 0
            }
        }
        BLOCKED {
            set decision BLOCKED
            set reason_code CONTROLLER_PREREQUISITE_BLOCKED
            set exit_code 2
        }
        default {
            set decision FAIL
            set reason_code CONTROLLER_SKELETON_FAILED
            set exit_code 1
        }
    }

    set workspace_created 0
    if {[dict exists $context workspace_verification workspace_created]} {
        set workspace_created [dict get \
            $context workspace_verification workspace_created]
    }

    set result [dict create \
        controller_version $controller_version \
        controller_api_version $controller_api_version \
        build_profile_identity [dict get \
            $context build_profile_identity] \
        skeleton_scope [dict get $context skeleton_scope] \
        context_boundary [dict get $context context_boundary] \
        disabled_capabilities [dict get \
            $context disabled_capabilities] \
        future_phase_boundaries [future_phase_boundaries] \
        artifact_role_placeholders [dict get \
            $configuration artifact_roles placeholders] \
        execution_id_schema_version $execution_id_schema_version \
        execution_identity $execution_identity \
        execution_identifier [dict get \
            $execution_identity execution_identifier] \
        decision $decision \
        reason_code $reason_code \
        current_state $final_state \
        state_history [dict get $state history] \
        configured_phase_order [dict get \
            $configuration build_phases phase_order] \
        phase_evidence $phase_evidence \
        phase_evidence_persistence $persistence_result \
        logs [::stage1d::logger::records $logger] \
        workspace_created $workspace_created \
        build_controller_ready [expr {
            $decision eq {READY} &&
            $final_state eq {BUILD_CONTROLLER_READY}
        }] \
        exit_code $exit_code]
    return [dict merge [disabled_execution_status] $result]
}

proc ::stage1e::controller::_bootstrap_failure {
    message
    options
} {
    set error_info {}
    if {[dict exists $options -errorinfo]} {
        set error_info [dict get $options -errorinfo]
    }
    set result [dict create \
        controller_version [version] \
        controller_api_version [api_version] \
        build_profile_identity [build_profile_identity] \
        skeleton_scope [skeleton_scope] \
        context_boundary [context_boundary] \
        disabled_capabilities [disabled_capabilities] \
        future_phase_boundaries [future_phase_boundaries] \
        execution_id_schema_version [execution_id_schema_version] \
        decision FAIL \
        reason_code CONTROLLER_BOOTSTRAP_ERROR \
        current_state FAIL \
        error_message $message \
        error_info $error_info \
        phase_evidence {} \
        workspace_created 0 \
        build_controller_ready 0 \
        exit_code 1]
    return [dict merge [disabled_execution_status] $result]
}

proc ::stage1e::controller::invoke {
    arguments
    {operation_overrides {}}
} {
    set run_status [catch {
        main $arguments $operation_overrides
    } result run_options]
    if {$run_status == 0} {
        return $result
    }
    return [_bootstrap_failure $result $run_options]
}

if {![info exists ::env(STAGE1E_CONTROLLER_NO_MAIN)] ||
    $::env(STAGE1E_CONTROLLER_NO_MAIN) ne {1}} {
    set stage1e_main_result [::stage1e::controller::invoke $argv]
    set ::stage1e::last_result $stage1e_main_result
    puts [list STAGE1E_RESULT $stage1e_main_result]
    if {![info exists ::env(STAGE1E_CONTROLLER_NO_EXIT)] ||
        $::env(STAGE1E_CONTROLLER_NO_EXIT) ne {1}} {
        exit [dict get $stage1e_main_result exit_code]
    }
}
