# Stage 1E mutation bridge.
#
# This module owns only the context projection and result normalization around
# the existing Stage 1D mutation procedure.  The Stage 1D procedure remains
# the sole implementation and mutation owner.  Sourcing this file defines
# procedures and loads the reviewed mutation module when necessary; it does
# not invoke Vivado or the mutation procedure.

namespace eval ::stage1e::mutation_bridge {
    variable context_schema_version stage1e-mutation-bridge-context-v1
    variable result_schema_version stage1e-mutation-bridge-result-v1
    variable operation_name stage1e::mutation_bridge::apply
    variable phase_name MUTATION_EXECUTE
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
        stimulus_profile
        stimulus_profile_class
        source_acceptance_claimed
        fault_stimulus_claimed
        slice_ch1_name
        slice_ch2_name
        smartconnect_name
        stage1d_source_baseline
        xlslice_vlnv
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
        stimulus_profile
        stimulus_profile_class
        source_acceptance_claimed
        fault_stimulus_claimed
        slice_ch1_name
        slice_ch2_name
        smartconnect_name
        stage1d_source_baseline
        vivado_version
        xlslice_vlnv
    }
}

# Load the unchanged authoritative implementation only when a caller has not
# already loaded it.  The source file is definition-only at this boundary.
if {[llength [info procs ::stage1d_controlled_stimulus::apply]] == 0} {
    set ::stage1e::mutation_bridge::_mutation_module_path [file normalize \
        [file join [file dirname [info script]] .. mutation \
            stage1d_controlled_stimulus.tcl]]
    if {[file exists $::stage1e::mutation_bridge::_mutation_module_path]} {
        source $::stage1e::mutation_bridge::_mutation_module_path
    }
    unset ::stage1e::mutation_bridge::_mutation_module_path
}

# Reuse the source-verification digest implementation.  This dependency has
# no Vivado side effects when sourced.
if {[llength [info commands ::stage1d::source_check::sha256_text]] == 0} {
    set ::stage1e::mutation_bridge::_source_check_path [file normalize \
        [file join [file dirname [info script]] .. lib source_check.tcl]]
    source $::stage1e::mutation_bridge::_source_check_path
    unset ::stage1e::mutation_bridge::_source_check_path
}

proc ::stage1e::mutation_bridge::_get_or_default {
    dictionary
    key
    default_value
} {
    if {![catch {dict size $dictionary}] && [dict exists $dictionary $key]} {
        return [dict get $dictionary $key]
    }
    return $default_value
}

proc ::stage1e::mutation_bridge::_nested_or_default {
    dictionary
    parent_key
    child_key
    default_value
} {
    if {![catch {dict size $dictionary}] &&
        [dict exists $dictionary $parent_key]} {
        set nested [dict get $dictionary $parent_key]
        if {![catch {dict size $nested}] &&
            [dict exists $nested $child_key]} {
            return [dict get $nested $child_key]
        }
    }
    return $default_value
}

proc ::stage1e::mutation_bridge::_raise {
    status
    error_code
    error_class
    message
} {
    return -code error -errorcode [list \
        STAGE1E MUTATION_BRIDGE $status $error_code $error_class] $message
}

proc ::stage1e::mutation_bridge::_decode_error {
    message
    options
    default_code
    default_class
} {
    set status FAIL
    set error_code $default_code
    set error_class $default_class
    set underlying_error [_get_or_default $options -errorinfo $message]
    set tcl_error_code [_get_or_default $options -errorcode {}]
    if {[llength $tcl_error_code] >= 5 &&
        [lrange $tcl_error_code 0 1] eq {STAGE1E MUTATION_BRIDGE}} {
        set status [lindex $tcl_error_code 2]
        set error_code [lindex $tcl_error_code 3]
        set error_class [lindex $tcl_error_code 4]
    } elseif {[lrange $tcl_error_code 0 2] eq {TCL LOOKUP COMMAND}} {
        set status BLOCKED
        set error_code MUTATION_INTERFACE_UNAVAILABLE
        set error_class SOURCE
    }
    return [dict create \
        status $status \
        error_code $error_code \
        error_class $error_class \
        message $message \
        underlying_error $underlying_error]
}

proc ::stage1e::mutation_bridge::_error_record {decoded} {
    variable operation_name
    variable phase_name
    set code [dict get $decoded error_code]
    set class [dict get $decoded error_class]
    return [dict create \
        code $code \
        error_code $code \
        class $class \
        category $class \
        operation $operation_name \
        phase $phase_name \
        message [dict get $decoded message] \
        underlying_error [dict get $decoded underlying_error] \
        evidence_references {}]
}

proc ::stage1e::mutation_bridge::_cleanup_result {
    required
    completed
    disposition
} {
    return [dict create \
        owner stage1d_controlled_stimulus \
        required $required \
        attempted 0 \
        completed $completed \
        disposition $disposition \
        errors {}]
}

proc ::stage1e::mutation_bridge::_context_execution_id {context} {
    if {![catch {dict size $context}] && [dict exists $context execution_id]} {
        return [dict get $context execution_id]
    }
    return {}
}

proc ::stage1e::mutation_bridge::_result {
    status
    context
    consumed_identities
    produced_identities
    ownership_records
    evidence_references
    warnings
    errors
    cleanup_result
    vivado_invoked
    mutation_invoked
    mutation_started
    stage1d_result
    stage1d_outputs
    mutation_summary
} {
    variable result_schema_version
    variable operation_name
    variable phase_name
    return [dict create \
        schema_version $result_schema_version \
        operation $operation_name \
        phase $phase_name \
        execution_id [_context_execution_id $context] \
        status $status \
        consumed_identities $consumed_identities \
        produced_identities $produced_identities \
        ownership_records $ownership_records \
        evidence_references $evidence_references \
        warnings $warnings \
        errors $errors \
        cleanup_result $cleanup_result \
        stage1d_result $stage1d_result \
        stage1d_outputs $stage1d_outputs \
        mutation_summary $mutation_summary \
        vivado_invoked $vivado_invoked \
        mutation_invoked $mutation_invoked \
        mutation_started $mutation_started \
        lifecycle_ownership_created 0 \
        project_opened 0 \
        project_created 0 \
        bd_created 0 \
        bd_validated 0 \
        bd_saved 0 \
        synthesis_performed 0 \
        implementation_performed 0 \
        artifacts_generated 0 \
        artifact_generation_performed 0 \
        artifact_publication_performed 0]
}

proc ::stage1e::mutation_bridge::_require_dictionary {value label} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise FAIL CONTEXT_FIELD_INVALID CONTRACT \
            "$label must be a dictionary: $dictionary_error"
    }
}

proc ::stage1e::mutation_bridge::_require_keys {
    dictionary
    required_keys
    label
} {
    _require_dictionary $dictionary $label
    foreach key $required_keys {
        if {![dict exists $dictionary $key]} {
            _raise FAIL CONTEXT_FIELD_MISSING CONTRACT \
                "$label is missing required key: $key"
        }
    }
}

proc ::stage1e::mutation_bridge::_canonical_components {path} {
    set components [file split [file normalize $path]]
    if {$::tcl_platform(platform) ne {windows}} {
        return $components
    }
    set canonical {}
    foreach component $components {
        lappend canonical [string tolower $component]
    }
    return $canonical
}

proc ::stage1e::mutation_bridge::_paths_equal {first_path second_path} {
    return [expr {
        [_canonical_components $first_path] eq
            [_canonical_components $second_path]
    }]
}

proc ::stage1e::mutation_bridge::_is_equal_or_descendant {
    candidate_path
    parent_path
} {
    set candidate [_canonical_components $candidate_path]
    set parent [_canonical_components $parent_path]
    if {[llength $candidate] < [llength $parent]} {
        return 0
    }
    for {set index 0} {$index < [llength $parent]} {incr index} {
        if {[lindex $candidate $index] ne [lindex $parent $index]} {
            return 0
        }
    }
    return 1
}

proc ::stage1e::mutation_bridge::_is_identifier {value} {
    return [regexp {^[A-Za-z_][A-Za-z0-9_]*$} $value]
}

proc ::stage1e::mutation_bridge::_validate_hash {value label} {
    set digest [string tolower [string trim $value]]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {
        _raise FAIL IDENTITY_HASH_INVALID IDENTITY \
            "$label must be a SHA-256 hexadecimal digest."
    }
    return $digest
}

proc ::stage1e::mutation_bridge::_validate_authorization {
    authorization
    execution_id
} {
    variable operation_name
    variable phase_name
    _require_keys $authorization {
        status
        authority
        execution_id
        operation
        phase
        capability
        capability_enabled
    } authorization
    if {[dict get $authorization status] ne {AUTHORIZED} ||
        [dict get $authorization authority] ne {controller_core} ||
        [dict get $authorization execution_id] ne $execution_id ||
        [dict get $authorization operation] ne $operation_name ||
        [dict get $authorization phase] ne $phase_name ||
        [dict get $authorization capability] ne {bd_generation_enabled} ||
        ![string is boolean -strict \
            [dict get $authorization capability_enabled]] ||
        ![dict get $authorization capability_enabled]} {
        _raise BLOCKED AUTHORIZATION_MISMATCH AUTHORIZATION \
            {Controller authorization does not permit the mutation bridge.}
    }
}

proc ::stage1e::mutation_bridge::_validate_identity {
    identity
    label
    execution_id
} {
    _require_dictionary $identity $label
    if {[dict size $identity] == 0} {
        _raise FAIL IDENTITY_MISSING IDENTITY "$label must not be empty."
    }
    if {[dict exists $identity execution_id] &&
        [dict get $identity execution_id] ne $execution_id} {
        _raise FAIL CONSUMED_IDENTITY_EXECUTION_MISMATCH IDENTITY \
            "$label belongs to another execution."
    }
    return $identity
}

proc ::stage1e::mutation_bridge::_validate_ownership {
    context
    execution_id
    workspace_root
} {
    set project [dict get $context project_ownership]
    _require_keys $project {
        owner
        execution_id
        project_handle
        project_path
        identity_verified
        project_identity
    } project_ownership
    if {[dict get $project owner] ne {vivado_project} ||
        [dict get $project execution_id] ne $execution_id ||
        [string trim [dict get $project project_handle]] eq {} ||
        ![string is boolean -strict [dict get $project identity_verified]] ||
        ![dict get $project identity_verified]} {
        _raise FAIL PROJECT_OWNER_INVALID OWNERSHIP \
            {Mutation bridge requires same-execution verified project ownership.}
    }
    set project_path [dict get $project project_path]
    if {[file pathtype $project_path] ne {absolute}} {
        _raise FAIL PROJECT_PATH_INVALID WORKSPACE \
            {project_ownership project_path must be absolute.}
    }
    set project_path [file normalize $project_path]
    if {![_is_equal_or_descendant $project_path $workspace_root] ||
        ![string equal -nocase [file extension $project_path] {.xpr}]} {
        _raise FAIL PROJECT_PATH_INVALID WORKSPACE \
            {Owned project path must be an execution-contained .xpr path.}
    }
    set project_identity [dict get $project project_identity]
    _require_keys $project_identity {
        project_name
        project_directory
        part
        board_part
    } {project_ownership project_identity}
    if {![_paths_equal [dict get $project_identity project_directory] \
        [file dirname $project_path]]} {
        _raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
            {Project identity directory does not match project ownership.}
    }
    dict set project project_path $project_path

    set bd [dict get $context bd_ownership]
    _require_keys $bd {
        owner
        execution_id
        project_path
        bd_name
        bd_path
        opened
        identity_verified
        validated
        saved
    } bd_ownership
    if {[dict get $bd owner] ne {bd_flow} ||
        [dict get $bd execution_id] ne $execution_id ||
        ![_paths_equal [dict get $bd project_path] $project_path]} {
        _raise FAIL BD_OWNER_INVALID OWNERSHIP \
            {Mutation bridge requires same-execution BD ownership.}
    }
    foreach field {opened identity_verified validated saved} {
        if {![string is boolean -strict [dict get $bd $field]]} {
            _raise FAIL BD_OWNER_INVALID OWNERSHIP \
                "bd_ownership state is not boolean: $field"
        }
    }
    if {![dict get $bd opened] || ![dict get $bd identity_verified] ||
        [dict get $bd validated] || [dict get $bd saved]} {
        _raise FAIL BD_OWNER_STATE_INVALID OWNERSHIP \
            {Mutation bridge requires an open, verified, unvalidated, unsaved BD.}
    }
    if {![_is_identifier [dict get $bd bd_name]]} {
        _raise FAIL BD_IDENTITY_INVALID IDENTITY \
            {bd_ownership bd_name is invalid.}
    }
    set bd_path [dict get $bd bd_path]
    if {[file pathtype $bd_path] ne {absolute}} {
        _raise FAIL BD_PATH_INVALID WORKSPACE \
            {bd_ownership bd_path must be absolute.}
    }
    set bd_path [file normalize $bd_path]
    if {![_is_equal_or_descendant $bd_path $workspace_root] ||
        ![string equal -nocase [file extension $bd_path] {.bd}] ||
        [file rootname [file tail $bd_path]] ne [dict get $bd bd_name]} {
        _raise FAIL BD_PATH_INVALID WORKSPACE \
            {Owned BD path must be an execution-contained matching .bd path.}
    }
    dict set bd project_path $project_path
    dict set bd bd_path $bd_path
    return [dict create project_ownership $project bd_ownership $bd]
}

proc ::stage1e::mutation_bridge::_unwrap_identity {identity key} {
    _require_dictionary $identity $key
    if {[dict exists $identity $key]} {
        return [dict get $identity $key]
    }
    return $identity
}

proc ::stage1e::mutation_bridge::_validate_base_identity {
    identity
    execution_id
    project
    bd
} {
    set identity [_unwrap_identity $identity base_design_identity]
    _require_keys $identity {
        schema_version
        producer_operation
        execution_id
        project_path
        bd_name
        bd_path
        identity_sha256
    } base_design_identity
    if {[dict get $identity schema_version] ne
        {stage1e-base-design-identity-v1} ||
        [dict get $identity producer_operation] ne
            {stage1e::base_design::apply} ||
        [dict get $identity execution_id] ne $execution_id ||
        ![_paths_equal [dict get $identity project_path] \
            [dict get $project project_path]] ||
        [dict get $identity bd_name] ne [dict get $bd bd_name] ||
        ![_paths_equal [dict get $identity bd_path] [dict get $bd bd_path]]} {
        _raise FAIL BASE_DESIGN_IDENTITY_MISMATCH IDENTITY \
            {base_design_identity is not bound to the owned same-execution BD.}
    }
    dict set identity identity_sha256 [_validate_hash \
        [dict get $identity identity_sha256] \
        {base_design_identity identity_sha256}]
    foreach field {topology_policy_sha256 policy_bundle_sha256 readback_sha256} {
        if {[dict exists $identity $field]} {
            dict set identity $field [_validate_hash \
                [dict get $identity $field] "base_design_identity $field"]
        }
    }
    return $identity
}

proc ::stage1e::mutation_bridge::_validate_debug_identity {
    identity
    execution_id
    project
    bd
    base_identity
} {
    set identity [_unwrap_identity $identity debug_design_identity]
    _require_keys $identity {
        schema_version
        producer_operation
        execution_id
        project_path
        bd_name
        bd_path
        base_design_identity_sha256
        identity_sha256
    } debug_design_identity
    if {[dict get $identity schema_version] ne
        {stage1e-debug-design-identity-v1} ||
        [dict get $identity producer_operation] ne
            {stage1e::debug_design::apply} ||
        [dict get $identity execution_id] ne $execution_id ||
        ![_paths_equal [dict get $identity project_path] \
            [dict get $project project_path]] ||
        [dict get $identity bd_name] ne [dict get $bd bd_name] ||
        ![_paths_equal [dict get $identity bd_path] [dict get $bd bd_path]] ||
        [string tolower [dict get $identity base_design_identity_sha256]] ne
            [dict get $base_identity identity_sha256]} {
        _raise FAIL DEBUG_DESIGN_IDENTITY_MISMATCH IDENTITY \
            {debug_design_identity is not bound to the accepted base design and owned same-execution BD.}
    }
    dict set identity identity_sha256 [_validate_hash \
        [dict get $identity identity_sha256] \
        {debug_design_identity identity_sha256}]
    foreach field {
        base_design_identity_sha256
        debug_policy_sha256
        policy_bundle_sha256
        readback_sha256
    } {
        if {[dict exists $identity $field]} {
            dict set identity $field [_validate_hash \
                [dict get $identity $field] "debug_design_identity $field"]
        }
    }
    return $identity
}

proc ::stage1e::mutation_bridge::_find_context_value {
    context keys label
} {
    foreach key $keys {
        if {[dict exists $context $key]} {
            return [dict get $context $key]
        }
    }
    _raise FAIL CONTEXT_FIELD_MISSING CONTRACT \
        "$label is missing; accepted names: [join $keys {, }]"
}

proc ::stage1e::mutation_bridge::_validate_assertion_source {
    context
    execution_id
    bd_name
} {
    set source [_find_context_value $context \
        {mutation_authorization_assertion_source authorization_assertion_source \
         mutation_authorization_assertion authorization_assertion} \
        {mutation authorization assertion source}]
    _require_dictionary $source {mutation authorization assertion source}
    set assertion $source
    if {[dict exists $source authorization_assertion]} {
        set assertion [dict get $source authorization_assertion]
    } elseif {[dict exists $source assertion]} {
        set assertion [dict get $source assertion]
    }
    _require_dictionary $assertion authorization_assertion
    set required_keys {execution_id operation phase bd_name decision}
    if {[lsort [dict keys $assertion]] ne [lsort $required_keys]} {
        _raise BLOCKED AUTHORIZATION_ASSERTION_SCOPE_INVALID AUTHORIZATION \
            {Stage 1D authorization_assertion must contain exactly its approved five fields.}
    }
    if {[dict get $assertion execution_id] ne $execution_id} {
        _raise BLOCKED AUTHORIZATION_EXECUTION_ID_MISMATCH AUTHORIZATION \
            {Mutation authorization assertion execution_id does not match the bridge execution.}
    }
    if {[dict get $assertion operation] ne {stage1d_controlled_stimulus} ||
        [dict get $assertion phase] ne {MUTATION_EXECUTE} ||
        [dict get $assertion bd_name] ne $bd_name} {
        _raise BLOCKED AUTHORIZATION_ASSERTION_MISMATCH AUTHORIZATION \
            {Mutation authorization assertion scope does not match Stage 1D.}
    }
    if {[dict get $assertion decision] ne {ALLOW}} {
        _raise BLOCKED AUTHORIZATION_DECISION_DENIED AUTHORIZATION \
            {Mutation authorization assertion does not explicitly allow mutation.}
    }
    if {[dict exists $source owner] && [dict get $source owner] ne {controller_core}} {
        _raise BLOCKED AUTHORIZATION_SOURCE_OWNER_INVALID AUTHORIZATION \
            {Mutation authorization assertion source is not controller-owned.}
    }
    return [dict create \
        assertion $assertion \
        source $source \
        sha256 [::stage1d::source_check::sha256_text $assertion]]
}

proc ::stage1e::mutation_bridge::_validate_mutation_configuration {context} {
    variable mutation_configuration_fields
    set configuration [_find_context_value $context \
        {mutation_configuration mutation_config \
         stage1d_mutation_configuration} \
        {existing Stage 1D mutation configuration}]
    _require_dictionary $configuration {mutation configuration}
    if {[dict exists $configuration mutation_context]} {
        set configuration [dict get $configuration mutation_context]
    }
    if {[lsort [dict keys $configuration]] ne
        [lsort $mutation_configuration_fields]} {
        _raise FAIL MUTATION_CONFIGURATION_SCOPE_INVALID CONTRACT \
            {Stage 1D mutation configuration must contain exactly its approved fields.}
    }
    foreach field $mutation_configuration_fields {
        if {[string trim [dict get $configuration $field]] eq {}} {
            _raise FAIL MUTATION_CONFIGURATION_INVALID CONTRACT \
                "Stage 1D mutation configuration field is empty: $field"
        }
    }
    if {![string is integer -strict [dict get $configuration gpio_width]] ||
        [dict get $configuration gpio_width] <= 0} {
        _raise FAIL MUTATION_CONFIGURATION_INVALID CONTRACT \
            {Stage 1D gpio_width must be a positive integer.}
    }
    if {![regexp {^[0-9a-f]{40}$} \
        [dict get $configuration stage1d_source_baseline]]} {
        _raise FAIL MUTATION_SOURCE_BASELINE_INVALID IDENTITY \
            {Stage 1D source baseline must be a lowercase 40-character Git revision.}
    }
    if {[dict get $configuration stimulus_profile] ne {SAFE_INERT_EXPLICIT}} {
        _raise FAIL STIMULUS_PROFILE_INVALID CONTRACT \
            {Stage 2D controlled stimulus profile must be SAFE_INERT_EXPLICIT.}
    }
    if {[dict get $configuration stimulus_profile_class] ne {SAFE_INERT}} {
        _raise FAIL STIMULUS_PROFILE_CLASS_INVALID CONTRACT \
            {Stage 2D controlled stimulus profile class must be SAFE_INERT.}
    }
    foreach claim {source_acceptance_claimed fault_stimulus_claimed} {
        set value [dict get $configuration $claim]
        if {![string is boolean -strict $value] || $value} {
            _raise FAIL STIMULUS_CLAIM_INVALID CONTRACT \
                "$claim must be the explicit false value for SAFE_INERT_EXPLICIT."
        }
    }
    return $configuration
}

proc ::stage1e::mutation_bridge::_validate_context {context} {
    variable context_schema_version
    variable operation_name
    variable phase_name
    _require_keys $context {
        context_schema_version
        operation
        phase
        execution_id
        authorization
        source_identity
        environment_identity
        configuration_identity
        workspace_root
        evidence_dir
        project_ownership
        bd_ownership
        base_design_identity
        debug_design_identity
    } {mutation-bridge context}
    if {[dict get $context context_schema_version] ne $context_schema_version} {
        _raise FAIL CONTEXT_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported mutation-bridge context schema.}
    }
    if {[dict get $context operation] ne $operation_name ||
        [dict get $context phase] ne $phase_name} {
        _raise FAIL OPERATION_MISMATCH CONTRACT \
            {Mutation-bridge operation or phase does not match the interface.}
    }
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        _raise FAIL EXECUTION_ID_INVALID CONTRACT \
            {Mutation-bridge execution_id must not be empty.}
    }
    _validate_authorization [dict get $context authorization] $execution_id
    set source_identity [_validate_identity \
        [dict get $context source_identity] source_identity $execution_id]
    set environment_identity [_validate_identity \
        [dict get $context environment_identity] environment_identity $execution_id]
    if {![dict exists $environment_identity vivado_version] ||
        [string trim [dict get $environment_identity vivado_version]] eq {}} {
        _raise FAIL ENVIRONMENT_IDENTITY_INCOMPLETE IDENTITY \
            {environment_identity must contain vivado_version for Stage 1D.}
    }
    set configuration_identity [_validate_identity \
        [dict get $context configuration_identity] \
        configuration_identity $execution_id]

    foreach path_field {workspace_root evidence_dir} {
        set path [dict get $context $path_field]
        if {[file pathtype $path] ne {absolute}} {
            _raise FAIL PATH_NOT_ABSOLUTE WORKSPACE \
                "Mutation-bridge $path_field must be absolute."
        }
        dict set context $path_field [file normalize $path]
    }
    set workspace_root [dict get $context workspace_root]
    set evidence_dir [dict get $context evidence_dir]
    if {![file isdirectory $workspace_root] ||
        ![file isdirectory $evidence_dir] ||
        ![_is_equal_or_descendant $evidence_dir $workspace_root]} {
        _raise FAIL WORKSPACE_CONTEXT_INVALID WORKSPACE \
            {Mutation-bridge workspace and evidence directories are unavailable or inconsistent.}
    }

    set ownership [_validate_ownership $context $execution_id $workspace_root]
    set project [dict get $ownership project_ownership]
    set bd [dict get $ownership bd_ownership]
    set base_identity [_validate_base_identity \
        [dict get $context base_design_identity] $execution_id $project $bd]
    set debug_identity [_validate_debug_identity \
        [dict get $context debug_design_identity] $execution_id $project $bd \
        $base_identity]
    set assertion [_validate_assertion_source $context $execution_id \
        [dict get $bd bd_name]]
    set mutation_configuration [_validate_mutation_configuration $context]

    return [dict create \
        context $context \
        execution_id $execution_id \
        source_identity $source_identity \
        environment_identity $environment_identity \
        configuration_identity $configuration_identity \
        workspace_root $workspace_root \
        evidence_dir $evidence_dir \
        project_ownership $project \
        bd_ownership $bd \
        base_design_identity $base_identity \
        debug_design_identity $debug_identity \
        authorization_assertion $assertion \
        mutation_configuration $mutation_configuration]
}

proc ::stage1e::mutation_bridge::_project_context {validated} {
    variable mutation_context_fields
    set mutation [dict get $validated mutation_configuration]
    set bd_name [dict get $validated bd_ownership bd_name]
    set project_path [dict get $validated project_ownership project_path]
    set environment [dict get $validated environment_identity]
    set projected [dict create \
        execution_id [dict get $validated execution_id] \
        authorization_assertion [dict get \
            $validated authorization_assertion assertion] \
        bd_name $bd_name \
        evidence_dir [dict get $validated evidence_dir] \
        environment_identity $environment]
    foreach field $mutation_context_fields {
        if {[dict exists $projected $field]} { continue }
        if {[dict exists $mutation $field]} {
            dict set projected $field [dict get $mutation $field]
        } else {
            switch -- $field {
                current_bd { dict set projected $field $bd_name }
                expected_bd_name { dict set projected $field $bd_name }
                project_path { dict set projected $field $project_path }
                vivado_version { dict set projected $field \
                    [dict get $environment vivado_version] }
                default {
                    _raise FAIL PROJECTION_FIELD_MISSING CONTRACT \
                        "Unable to project required Stage 1D field: $field"
                }
            }
        }
    }
    if {[lsort [dict keys $projected]] ne [lsort $mutation_context_fields]} {
        _raise FAIL PROJECTION_SCOPE_INVALID CONTRACT \
            {Projected mutation context does not match the exact Stage 1D contract.}
    }
    return $projected
}

proc ::stage1e::mutation_bridge::_empty_mutation_summary {} {
    return [dict create \
        created_cells {} \
        modified_nets {} \
        changed_properties {} \
        deleted_objects {} \
        address_changes {} \
        topology_checks {}]
}

proc ::stage1e::mutation_bridge::_normalize_result {
    raw_result
    invocation_status
    invocation_options
    projected_context
} {
    set execution_id [dict get $projected_context execution_id]
    set assertion [dict get $projected_context authorization_assertion]
    set assertion_hash [::stage1d::source_check::sha256_text $assertion]
    if {$invocation_status != 0} {
        set underlying_error [_get_or_default $invocation_options \
            -errorinfo $raw_result]
        return [dict create \
            status FAIL \
            errors [list [dict create \
                code MUTATION_INVOCATION_ERROR \
                error_code MUTATION_INVOCATION_ERROR \
                class MUTATION \
                category MUTATION \
                operation stage1d_controlled_stimulus::apply \
                phase MUTATION_EXECUTE \
                message "Stage 1D mutation procedure failed: $raw_result" \
                underlying_error $underlying_error \
                evidence_references {}]] \
            warnings {} \
            outputs {} \
            mutation_summary {} \
            evidence_references {} \
            stage1d_result {} \
            stage1d_result_hash [::stage1d::source_check::sha256_text \
                $raw_result] \
            assertion_hash $assertion_hash \
            vivado_invoked 1 \
            mutation_started 1]
    }
    if {[catch {dict size $raw_result} result_error]} {
        return [dict create \
            status FAIL \
            errors [list [dict create \
                code INVALID_MUTATION_RESULT \
                error_code INVALID_MUTATION_RESULT \
                class CONTRACT \
                category CONTRACT \
                operation stage1d_controlled_stimulus::apply \
                phase MUTATION_EXECUTE \
                message {Stage 1D mutation procedure did not return a dictionary.} \
                underlying_error $result_error \
                evidence_references {}]] \
            warnings {} outputs {} mutation_summary {} \
            evidence_references {} \
            stage1d_result $raw_result \
            stage1d_result_hash [::stage1d::source_check::sha256_text \
                $raw_result] \
            assertion_hash $assertion_hash vivado_invoked 1 \
            mutation_started 1]
    }
    set result_hash [::stage1d::source_check::sha256_text $raw_result]
    if {[dict size $raw_result] == 0} {
        return [dict create \
            status PASS errors {} warnings {} outputs {} \
            mutation_summary {} evidence_references {} stage1d_result {} \
            stage1d_result_hash $result_hash assertion_hash $assertion_hash \
            vivado_invoked 1 mutation_started 1]
    }
    set evidence_references [_get_or_default \
        $raw_result evidence_references {}]
    if {![dict exists $raw_result status] ||
        [dict get $raw_result status] ni {PASS FAIL BLOCKED}} {
        return [dict create \
            status FAIL \
            errors [list [dict create \
                code INVALID_MUTATION_STATUS \
                error_code INVALID_MUTATION_STATUS \
                class CONTRACT category CONTRACT \
                operation stage1d_controlled_stimulus::apply \
                phase MUTATION_EXECUTE \
                message {Stage 1D mutation result has an invalid status.} \
                underlying_error {} evidence_references {}]] \
            warnings {} outputs $raw_result mutation_summary {} \
            evidence_references $evidence_references \
            stage1d_result $raw_result stage1d_result_hash $result_hash \
            assertion_hash $assertion_hash vivado_invoked 1 \
            mutation_started 1]
    }
    set status [dict get $raw_result status]
    if {[dict exists $raw_result execution_id] &&
        [dict get $raw_result execution_id] ne $execution_id} {
        return [dict create \
            status FAIL \
            errors [list [dict create \
                code MUTATION_EXECUTION_ID_MISMATCH \
                error_code MUTATION_EXECUTION_ID_MISMATCH \
                class IDENTITY category IDENTITY \
                operation stage1d_controlled_stimulus::apply \
                phase MUTATION_EXECUTE \
                message {Stage 1D mutation result execution_id does not match the bridge execution.} \
                underlying_error {} evidence_references {}]] \
            warnings {} outputs $raw_result mutation_summary {} \
            evidence_references $evidence_references \
            stage1d_result $raw_result stage1d_result_hash $result_hash \
            assertion_hash $assertion_hash vivado_invoked 1 \
            mutation_started 1]
    }
    set artifacts 0
    if {[dict exists $raw_result artifacts_generated]} {
        set artifacts [dict get $raw_result artifacts_generated]
    } elseif {[dict exists $raw_result outputs artifacts_generated]} {
        set artifacts [dict get $raw_result outputs artifacts_generated]
    }
    if {[string is boolean -strict $artifacts] && $artifacts} {
        return [dict create \
            status FAIL \
            errors [list [dict create \
                code MUTATION_ARTIFACT_BOUNDARY_VIOLATION \
                error_code MUTATION_ARTIFACT_BOUNDARY_VIOLATION \
                class OWNERSHIP category OWNERSHIP \
                operation stage1d_controlled_stimulus::apply \
                phase MUTATION_EXECUTE \
                message {Stage 1D mutation result reported artifact generation.} \
                underlying_error {} evidence_references {}]] \
            warnings [_get_or_default $raw_result warnings {}] \
            outputs [_get_or_default $raw_result outputs {}] \
            mutation_summary [_get_or_default $raw_result mutation_summary {}] \
            evidence_references $evidence_references \
            stage1d_result $raw_result stage1d_result_hash $result_hash \
            assertion_hash $assertion_hash vivado_invoked 1 \
            mutation_started 1]
    }
    return [dict create \
        status $status \
        errors [_get_or_default $raw_result errors {}] \
        warnings [_get_or_default $raw_result warnings {}] \
        outputs [_get_or_default $raw_result outputs {}] \
        mutation_summary [_get_or_default $raw_result mutation_summary {}] \
        evidence_references $evidence_references \
        stage1d_result $raw_result stage1d_result_hash $result_hash \
        assertion_hash $assertion_hash \
        vivado_invoked [_get_or_default $raw_result vivado_invoked 1] \
        mutation_started [_nested_or_default $raw_result outputs \
            mutation_started [_get_or_default $raw_result mutation_started 1]]]
}

proc ::stage1e::mutation_bridge::_identity {
    validated
    projected_context
    normalized
} {
    set raw_hash [dict get $normalized stage1d_result_hash]
    set projection_hash [::stage1d::source_check::sha256_text \
        $projected_context]
    set mutation_hash [::stage1d::source_check::sha256_text \
        [dict get $validated mutation_configuration]]
    set source_hash [::stage1d::source_check::sha256_text \
        [dict get $validated source_identity]]
    set environment_hash [::stage1d::source_check::sha256_text \
        [dict get $validated environment_identity]]
    set configuration_hash [::stage1d::source_check::sha256_text \
        [dict get $validated configuration_identity]]
    set workspace_hash [::stage1d::source_check::sha256_text \
        [dict get $validated workspace_root]]
    set assertion_hash [dict get $normalized assertion_hash]
    set identity_hash [::stage1d::source_check::sha256_text [list \
        [dict get $validated execution_id] \
        [dict get $validated bd_ownership bd_path] \
        [dict get $validated base_design_identity identity_sha256] \
        [dict get $validated debug_design_identity identity_sha256] \
        $source_hash $environment_hash $configuration_hash $workspace_hash \
        $mutation_hash $assertion_hash $projection_hash $raw_hash]]
    return [dict create \
        schema_version stage1e-controlled-mutation-identity-v1 \
        producer_operation stage1e::mutation_bridge::apply \
        mutation_owner stage1d_controlled_stimulus \
        execution_id [dict get $validated execution_id] \
        project_path [dict get $validated project_ownership project_path] \
        bd_name [dict get $validated bd_ownership bd_name] \
        bd_path [dict get $validated bd_ownership bd_path] \
        base_design_identity_sha256 [dict get \
            $validated base_design_identity identity_sha256] \
        debug_design_identity_sha256 [dict get \
            $validated debug_design_identity identity_sha256] \
        source_identity_sha256 $source_hash \
        environment_identity_sha256 $environment_hash \
        configuration_identity_sha256 $configuration_hash \
        workspace_identity_sha256 $workspace_hash \
        mutation_configuration_sha256 $mutation_hash \
        authorization_assertion_sha256 $assertion_hash \
        projected_context_sha256 $projection_hash \
        stage1d_result_sha256 $raw_hash \
        identity_sha256 $identity_hash]
}

proc ::stage1e::mutation_bridge::apply {context} {
    set validation_status [catch {
        _validate_context $context
    } validated validation_options]
    if {$validation_status != 0} {
        set decoded [_decode_error $validated $validation_options \
            MUTATION_BRIDGE_CONTEXT_INVALID CONTRACT]
        return [_result [dict get $decoded status] $context {} {} {} {} {} \
            [list [_error_record $decoded]] \
            [_cleanup_result 0 1 NOT_REQUIRED] 0 0 0 {} {} {}]
    }

    set ownership_records [dict create \
        project_ownership [dict get $validated project_ownership] \
        bd_ownership [dict get $validated bd_ownership]]
    set consumed_identities [dict create \
        source_identity [dict get $validated source_identity] \
        environment_identity [dict get $validated environment_identity] \
        configuration_identity [dict get $validated configuration_identity] \
        project_ownership [dict get $validated project_ownership] \
        bd_ownership [dict get $validated bd_ownership] \
        base_design_identity [dict get $validated base_design_identity] \
        debug_design_identity [dict get $validated debug_design_identity] \
        mutation_configuration [dict get $validated mutation_configuration] \
        authorization_assertion [dict get \
            $validated authorization_assertion assertion]]

    if {[llength [info procs ::stage1d_controlled_stimulus::apply]] != 1} {
        set decoded [dict create \
            status BLOCKED \
            error_code MUTATION_INTERFACE_UNAVAILABLE \
            error_class SOURCE \
            message {The Stage 1D mutation procedure is unavailable.} \
            underlying_error {}]
        return [_result BLOCKED $context $consumed_identities {} \
            $ownership_records {} {} [list [_error_record $decoded]] \
            [_cleanup_result 0 1 NOT_REQUIRED] 0 0 0 {} {} {}]
    }

    set projection_status [catch {
        _project_context $validated
    } projected_context projection_options]
    if {$projection_status != 0} {
        set decoded [_decode_error $projected_context $projection_options \
            MUTATION_CONTEXT_PROJECTION_FAILED CONTRACT]
        return [_result [dict get $decoded status] $context \
            $consumed_identities {} $ownership_records {} {} \
            [list [_error_record $decoded]] \
            [_cleanup_result 0 1 NOT_REQUIRED] 0 0 0 {} {} {}]
    }
    set invocation_status [catch {
        ::stage1d_controlled_stimulus::apply $projected_context
    } raw_result invocation_options]
    set normalized [_normalize_result $raw_result $invocation_status \
        $invocation_options $projected_context]
    set status [dict get $normalized status]
    set stage1d_result [dict get $normalized stage1d_result]
    set evidence [dict get $normalized evidence_references]
    set produced {}
    if {$status eq {PASS}} {
        dict set produced controlled_mutation_identity \
            [_identity $validated $projected_context $normalized]
    }
    set mutation_started [dict get $normalized mutation_started]
    if {![string is boolean -strict $mutation_started]} {
        set mutation_started 1
    }
    if {$status eq {FAIL} && $mutation_started} {
        set cleanup [_cleanup_result 1 0 CONTROLLER_CLEANUP_REQUIRED]
    } else {
        set cleanup [_cleanup_result 0 1 NOT_REQUIRED]
    }
    return [_result $status $context $consumed_identities $produced \
        $ownership_records $evidence [dict get $normalized warnings] \
        [dict get $normalized errors] $cleanup \
        [dict get $normalized vivado_invoked] 1 $mutation_started \
        $stage1d_result [dict get $normalized outputs] \
        [dict get $normalized mutation_summary]]
}
