# Stage 1D block-design lifecycle adapter.
#
# Ownership boundary:
# - consume explicit controller lifecycle context;
# - select, open, and verify the authorized block design;
# - validate and save only when the preceding lifecycle result authorizes it;
# - return structured results without making controller continuation decisions.
#
# This module is definition-only when sourced. Vivado commands are invoked only
# through an explicit open, validate, or save procedure call. Lifecycle state is
# passed in dictionaries; the adapter retains no hidden namespace/global state.

namespace eval ::stage1d::bd_flow {}

proc ::stage1d::bd_flow::_get_or_default {dictionary key default_value} {
    if {[dict exists $dictionary $key]} {
        return [dict get $dictionary $key]
    }
    return $default_value
}

proc ::stage1d::bd_flow::_error_record {
    error_code
    category
    operation
    message
    underlying_error
    recoverability
} {
    return [dict create \
        error_code $error_code \
        category $category \
        phase_name bd_flow \
        operation $operation \
        message $message \
        underlying_error $underlying_error \
        evidence_references {} \
        recoverability $recoverability]
}

# Result-schema boundary:
#
# BD lifecycle operations return structured results with the consistent
# semantic fields status, phase, execution_id, vivado_invoked,
# artifacts_generated, errors, warnings, and outputs. Result construction stays
# local to this Stage 1D adapter. A future Stage 1E evolution may extract shared
# result construction without changing this boundary.
proc ::stage1d::bd_flow::_result {
    status
    context
    errors
    outputs
    {warnings {}}
} {
    set execution_id {}
    if {![catch {dict size $context}] && [dict exists $context execution_id]} {
        set execution_id [dict get $context execution_id]
    }
    set vivado_invoked [_get_or_default $outputs vivado_invoked 0]

    return [dict create \
        status $status \
        phase bd_flow \
        execution_id $execution_id \
        vivado_invoked $vivado_invoked \
        artifacts_generated 0 \
        errors $errors \
        warnings $warnings \
        evidence_locations {} \
        logs {} \
        reports {} \
        outputs [dict merge [dict create \
            lifecycle_owner bd_flow \
            artifacts_generated 0] $outputs] \
        artifact_references {}]
}

proc ::stage1d::bd_flow::_stop {
    status
    context
    error_code
    category
    operation
    message
    underlying_error
    recoverability
    outputs
} {
    return [_result $status $context [list [_error_record \
        $error_code \
        $category \
        $operation \
        $message \
        $underlying_error \
        $recoverability]] $outputs]
}

proc ::stage1d::bd_flow::_canonical_components {path} {
    set components [file split [file normalize $path]]
    if {$::tcl_platform(platform) ne {windows}} {
        return $components
    }

    set normalized_components {}
    foreach component $components {
        lappend normalized_components [string tolower $component]
    }
    return $normalized_components
}

proc ::stage1d::bd_flow::_paths_equal {first_path second_path} {
    return [expr {
        [_canonical_components $first_path] eq
        [_canonical_components $second_path]
    }]
}

proc ::stage1d::bd_flow::_is_equal_or_descendant {
    candidate_path
    parent_path
} {
    set candidate_components [_canonical_components $candidate_path]
    set parent_components [_canonical_components $parent_path]
    if {[llength $candidate_components] < [llength $parent_components]} {
        return 0
    }
    for {set index 0} {$index < [llength $parent_components]} {incr index} {
        if {[lindex $candidate_components $index] ne \
            [lindex $parent_components $index]} {
            return 0
        }
    }
    return 1
}

proc ::stage1d::bd_flow::_validate_context {context operation} {
    if {[catch {dict size $context} context_error]} {
        error "BD flow context is not a dictionary: $context_error"
    }

    foreach required_key {
        execution_id
        authorization
        workspace_root
        project_path
        bd_name
        evidence_dir
        source_identity
        environment_identity
        project_ownership
    } {
        if {![dict exists $context $required_key]} {
            error "BD flow context is missing required key: $required_key"
        }
    }

    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        error {BD flow context requires a nonempty execution_id.}
    }

    set authorization [dict get $context authorization]
    if {[catch {dict size $authorization} authorization_error]} {
        error "BD flow authorization is not a dictionary: $authorization_error"
    }
    foreach authorization_key {status authority operation} {
        if {![dict exists $authorization $authorization_key]} {
            error "BD flow authorization is missing key: $authorization_key"
        }
    }
    if {[dict get $authorization status] ne {AUTHORIZED} ||
        [dict get $authorization authority] ne {controller_core} ||
        [dict get $authorization operation] ne $operation} {
        error "BD flow operation is not explicitly authorized: $operation"
    }

    set workspace_root [dict get $context workspace_root]
    set project_path [dict get $context project_path]
    set evidence_dir [dict get $context evidence_dir]
    foreach path_field {
        workspace_root
        project_path
        evidence_dir
    } path_value [list $workspace_root $project_path $evidence_dir] {
        if {[file pathtype $path_value] ne {absolute}} {
            error "BD flow $path_field must be an absolute path."
        }
    }
    set workspace_root [file normalize $workspace_root]
    set project_path [file normalize $project_path]
    set evidence_dir [file normalize $evidence_dir]
    if {![_is_equal_or_descendant $project_path $workspace_root]} {
        error {BD flow project_path must remain within workspace_root.}
    }
    if {![_is_equal_or_descendant $evidence_dir $workspace_root]} {
        error {BD flow evidence_dir must remain within workspace_root.}
    }
    if {![string equal -nocase [file extension $project_path] {.xpr}]} {
        error {BD flow project_path must identify a .xpr file.}
    }

    set bd_name [dict get $context bd_name]
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $bd_name]} {
        error "BD flow bd_name is invalid: $bd_name"
    }

    foreach identity_field {source_identity environment_identity} {
        if {[catch {
            dict size [dict get $context $identity_field]
        } identity_error]} {
            error "BD flow $identity_field is not a dictionary: $identity_error"
        }
    }
    set environment_identity [dict get $context environment_identity]
    foreach identity_key {part board_part} {
        if {![dict exists $environment_identity $identity_key] ||
            [string trim [dict get $environment_identity $identity_key]] eq {}} {
            error "BD flow environment_identity is missing: $identity_key"
        }
    }

    set project_ownership [dict get $context project_ownership]
    if {[catch {dict size $project_ownership} ownership_error]} {
        error "BD flow project_ownership is not a dictionary: $ownership_error"
    }
    foreach ownership_key {
        owner
        execution_id
        project_handle
        project_path
        identity_verified
        project_identity
    } {
        if {![dict exists $project_ownership $ownership_key]} {
            error "BD flow project_ownership is missing key: $ownership_key"
        }
    }
    if {[dict get $project_ownership owner] ne {vivado_project}} {
        error {BD flow requires vivado_project ownership.}
    }
    if {[dict get $project_ownership execution_id] ne $execution_id} {
        error {BD flow project ownership execution_id does not match context.}
    }
    if {[string trim [dict get $project_ownership project_handle]] eq {}} {
        error {BD flow project ownership handle must not be empty.}
    }
    if {![_paths_equal \
        [dict get $project_ownership project_path] $project_path]} {
        error {BD flow project ownership path does not match context.}
    }
    if {![string is boolean -strict \
        [dict get $project_ownership identity_verified]] ||
        ![dict get $project_ownership identity_verified]} {
        error {BD flow requires verified project identity.}
    }

    return [dict create \
        execution_id $execution_id \
        workspace_root $workspace_root \
        project_path $project_path \
        project_handle [dict get $project_ownership project_handle] \
        bd_name $bd_name \
        evidence_dir $evidence_dir]
}

proc ::stage1d::bd_flow::_validate_bd_ownership {
    context
    validated_context
    require_validated
} {
    if {![dict exists $context bd_ownership]} {
        error {BD flow lifecycle context has no bd_ownership record.}
    }
    set ownership [dict get $context bd_ownership]
    if {[catch {dict size $ownership} ownership_error]} {
        error "BD flow bd_ownership is not a dictionary: $ownership_error"
    }
    foreach ownership_key {
        owner
        execution_id
        project_path
        bd_name
        bd_path
        opened
        identity_verified
        validated
        saved
    } {
        if {![dict exists $ownership $ownership_key]} {
            error "BD flow bd_ownership is missing key: $ownership_key"
        }
    }

    if {[dict get $ownership owner] ne {bd_flow}} {
        error {BD lifecycle authority is not bd_flow.}
    }
    if {[dict get $ownership execution_id] ne \
        [dict get $validated_context execution_id]} {
        error {BD ownership execution_id does not match context.}
    }
    if {![string equal \
        [dict get $ownership bd_name] \
        [dict get $validated_context bd_name]]} {
        error {BD ownership name does not match context.}
    }
    if {![_paths_equal \
        [dict get $ownership project_path] \
        [dict get $validated_context project_path]]} {
        error {BD ownership project path does not match context.}
    }

    set bd_path [dict get $ownership bd_path]
    if {[file pathtype $bd_path] ne {absolute}} {
        error {BD ownership path must be absolute.}
    }
    set bd_path [file normalize $bd_path]
    if {![_is_equal_or_descendant \
        $bd_path [dict get $validated_context workspace_root]]} {
        error {BD ownership path must remain within workspace_root.}
    }
    if {![string equal -nocase [file extension $bd_path] {.bd}]} {
        error {BD ownership path must identify a .bd file.}
    }

    foreach boolean_field {opened identity_verified validated saved} {
        if {![string is boolean -strict [dict get $ownership $boolean_field]]} {
            error "BD ownership field must be boolean: $boolean_field"
        }
    }
    if {![dict get $ownership opened] ||
        ![dict get $ownership identity_verified]} {
        error {BD ownership requires an opened, identity-verified design.}
    }
    if {$require_validated && ![dict get $ownership validated]} {
        error {BD save requires successful BD validation.}
    }

    dict set validated_context bd_path $bd_path
    dict set validated_context bd_ownership $ownership
    return $validated_context
}

proc ::stage1d::bd_flow::_current_bd_name {} {
    return [current_bd_design]
}

proc ::stage1d::bd_flow::_bd_file_available {bd_path} {
    return [expr {[file exists $bd_path] && [file isfile $bd_path]}]
}

proc ::stage1d::bd_flow::_lifecycle_context {
    context
    validated_context
    bd_path
} {
    dict set context bd_ownership [dict create \
        owner bd_flow \
        execution_id [dict get $validated_context execution_id] \
        project_path [dict get $validated_context project_path] \
        bd_name [dict get $validated_context bd_name] \
        bd_path $bd_path \
        opened 1 \
        identity_verified 1 \
        validated 0 \
        saved 0]
    return $context
}

proc ::stage1d::bd_flow::_set_lifecycle_state {context field value} {
    dict set context bd_ownership $field $value
    return $context
}

proc ::stage1d::bd_flow::open {context} {
    set operation bd_flow_open
    if {[catch {
        _validate_context $context $operation
    } validated_context context_options]} {
        return [_stop FAIL $context \
            BD_FLOW_CONTEXT_INVALID CONTRACT $operation \
            "BD open context validation failed: $validated_context" \
            [_get_or_default $context_options -errorinfo {}] \
            FIX_CONTROLLER_CONTEXT \
            [dict create operation open bd_opened 0 vivado_invoked 0]]
    }

    set bd_name [dict get $validated_context bd_name]
    set bd_pattern [format {*%s.bd} $bd_name]
    if {[catch {
        get_files -quiet -all $bd_pattern
    } bd_files query_options]} {
        return [_stop FAIL $context \
            BD_SELECTION_FAILED VIVADO $operation \
            "Unable to select block design '$bd_name': $bd_files" \
            [_get_or_default $query_options -errorinfo {}] \
            CLEANUP_PROJECT \
            [dict create operation open bd_name $bd_name \
                bd_opened 0 vivado_invoked 1]]
    }
    if {[llength $bd_files] == 0} {
        return [_stop BLOCKED $context \
            BD_NOT_FOUND WORKSPACE $operation \
            "Authorized block design was not found: $bd_name" \
            {} PREPARE_BLOCK_DESIGN \
            [dict create operation open bd_name $bd_name \
                bd_opened 0 vivado_invoked 1]]
    }
    if {[llength $bd_files] != 1} {
        return [_stop FAIL $context \
            BD_SELECTION_AMBIGUOUS IDENTITY $operation \
            "Block-design selection is ambiguous for '$bd_name': $bd_files" \
            {} REMOVE_AMBIGUOUS_BLOCK_DESIGNS \
            [dict create operation open bd_name $bd_name \
                bd_opened 0 vivado_invoked 1]]
    }

    set bd_file [lindex $bd_files 0]
    if {[catch {
        file normalize [get_property NAME $bd_file]
    } bd_path identity_options]} {
        return [_stop FAIL $context \
            BD_PATH_QUERY_FAILED VIVADO $operation \
            "Unable to resolve block-design path: $bd_path" \
            [_get_or_default $identity_options -errorinfo {}] \
            CLEANUP_PROJECT \
            [dict create operation open bd_name $bd_name \
                bd_opened 0 vivado_invoked 1]]
    }
    if {![_is_equal_or_descendant \
        $bd_path [dict get $validated_context workspace_root]] ||
        ![string equal -nocase [file extension $bd_path] {.bd}]} {
        return [_stop FAIL $context \
            BD_PATH_INVALID IDENTITY $operation \
            "Resolved block-design path is outside the authorized workspace or is not a .bd file: $bd_path" \
            {} REJECT_BLOCK_DESIGN \
            [dict create operation open bd_name $bd_name bd_path $bd_path \
                bd_opened 0 vivado_invoked 1]]
    }
    if {![_bd_file_available $bd_path]} {
        return [_stop BLOCKED $context \
            BD_FILE_UNAVAILABLE WORKSPACE $operation \
            "Resolved block-design file is unavailable: $bd_path" \
            {} PREPARE_BLOCK_DESIGN \
            [dict create operation open bd_name $bd_name bd_path $bd_path \
                bd_opened 0 vivado_invoked 1]]
    }

    if {[catch {open_bd_design $bd_path} open_error open_options]} {
        return [_stop FAIL $context \
            BD_OPEN_FAILED VIVADO $operation \
            "Vivado open_bd_design failed: $open_error" \
            [_get_or_default $open_options -errorinfo {}] \
            CLEANUP_PROJECT \
            [dict create operation open bd_name $bd_name bd_path $bd_path \
                bd_opened 0 vivado_invoked 1]]
    }
    if {[catch {_current_bd_name} current_bd current_options]} {
        return [_stop FAIL $context \
            BD_CURRENT_QUERY_FAILED VIVADO $operation \
            "Unable to query current block design: $current_bd" \
            [_get_or_default $current_options -errorinfo {}] \
            CLEANUP_PROJECT \
            [dict create operation open bd_name $bd_name bd_path $bd_path \
                bd_opened 0 identity_verified 0 vivado_invoked 1]]
    }
    if {$current_bd ne $bd_name} {
        return [_stop FAIL $context \
            BD_IDENTITY_MISMATCH IDENTITY $operation \
            "Current block-design identity mismatch: actual=$current_bd expected=$bd_name" \
            {} CLEANUP_PROJECT \
            [dict create operation open bd_name $bd_name bd_path $bd_path \
                bd_opened 0 identity_verified 0 vivado_invoked 1]]
    }

    set lifecycle_context [_lifecycle_context \
        $context $validated_context $bd_path]
    return [_result PASS $context {} [dict create \
        operation open \
        bd_name $bd_name \
        bd_path $bd_path \
        bd_opened 1 \
        identity_verified 1 \
        lifecycle_context $lifecycle_context \
        vivado_invoked 1]]
}

proc ::stage1d::bd_flow::validate {context} {
    set operation bd_flow_validate
    if {[catch {
        set validated_context [_validate_context $context $operation]
        _validate_bd_ownership $context $validated_context 0
    } validated_context context_options]} {
        return [_stop FAIL $context \
            BD_FLOW_CONTEXT_INVALID CONTRACT $operation \
            "BD validation context is invalid: $validated_context" \
            [_get_or_default $context_options -errorinfo {}] \
            FIX_CONTROLLER_CONTEXT \
            [dict create operation validate bd_validated 0 vivado_invoked 0]]
    }

    set bd_name [dict get $validated_context bd_name]
    if {[catch {_current_bd_name} current_bd current_options] ||
        $current_bd ne $bd_name} {
        return [_stop FAIL $context \
            BD_CURRENT_IDENTITY_INVALID IDENTITY $operation \
            "Current block design is not the adapter-owned design: actual=$current_bd expected=$bd_name" \
            [_get_or_default $current_options -errorinfo {}] \
            CLEANUP_PROJECT \
            [dict create operation validate bd_name $bd_name \
                bd_validated 0 vivado_invoked 1]]
    }
    if {[catch {validate_bd_design} validation_error validation_options]} {
        return [_stop FAIL $context \
            BD_VALIDATION_FAILED VIVADO $operation \
            "Vivado validate_bd_design failed: $validation_error" \
            [_get_or_default $validation_options -errorinfo {}] \
            CLEANUP_PROJECT \
            [dict create operation validate bd_name $bd_name \
                bd_validated 0 vivado_invoked 1]]
    }

    set lifecycle_context [_set_lifecycle_state $context validated 1]
    return [_result PASS $context {} [dict create \
        operation validate \
        bd_name $bd_name \
        bd_path [dict get $validated_context bd_path] \
        bd_validated 1 \
        lifecycle_context $lifecycle_context \
        vivado_invoked 1]]
}

proc ::stage1d::bd_flow::save {context} {
    set operation bd_flow_save
    if {[catch {
        set validated_context [_validate_context $context $operation]
        _validate_bd_ownership $context $validated_context 1
    } validated_context context_options]} {
        return [_stop FAIL $context \
            BD_FLOW_CONTEXT_INVALID CONTRACT $operation \
            "BD save context is invalid: $validated_context" \
            [_get_or_default $context_options -errorinfo {}] \
            FIX_CONTROLLER_CONTEXT \
            [dict create operation save bd_saved 0 vivado_invoked 0]]
    }

    set bd_name [dict get $validated_context bd_name]
    if {[catch {_current_bd_name} current_bd current_options] ||
        $current_bd ne $bd_name} {
        return [_stop FAIL $context \
            BD_CURRENT_IDENTITY_INVALID IDENTITY $operation \
            "Current block design is not the validated adapter-owned design: actual=$current_bd expected=$bd_name" \
            [_get_or_default $current_options -errorinfo {}] \
            CLEANUP_PROJECT \
            [dict create operation save bd_name $bd_name \
                bd_saved 0 vivado_invoked 1]]
    }
    if {[catch {save_bd_design} save_error save_options]} {
        return [_stop FAIL $context \
            BD_SAVE_FAILED VIVADO $operation \
            "Vivado save_bd_design failed: $save_error" \
            [_get_or_default $save_options -errorinfo {}] \
            CLEANUP_PROJECT \
            [dict create operation save bd_name $bd_name \
                bd_saved 0 vivado_invoked 1]]
    }

    set lifecycle_context [_set_lifecycle_state $context saved 1]
    return [_result PASS $context {} [dict create \
        operation save \
        bd_name $bd_name \
        bd_path [dict get $validated_context bd_path] \
        bd_saved 1 \
        lifecycle_context $lifecycle_context \
        vivado_invoked 1]]
}

# Stage 1E additive block-design creation boundary.
#
# This extension preserves the Stage 1D open/validate/save procedures above.
# It creates one empty BD through the existing singular bd_flow owner, returns
# the existing bd_ownership record shape, and stops before topology, validation,
# save, output-product generation, build execution, or artifact generation.
namespace eval ::stage1d::bd_flow::create_backend {}

proc ::stage1d::bd_flow::create_backend::invoke {command arguments} {
    return [uplevel #0 [list $command {*}$arguments]]
}

proc ::stage1d::bd_flow::_create_invoke {command args} {
    return [::stage1d::bd_flow::create_backend::invoke $command $args]
}

proc ::stage1d::bd_flow::_create_raise {
    status
    error_code
    error_class
    message
} {
    return -code error -errorcode [list \
        STAGE1E BD_FLOW_CREATE $status $error_code $error_class] $message
}

# Vivado 2024.1 reports an empty BD session as BD 5-104 and may surface the
# caught Tcl error as Common 17-39. Only the pre-create session probe may
# interpret these exact messages as an empty handle. Post-create identity
# verification and the existing open/validate/save lifecycle remain strict.
proc ::stage1d::bd_flow::_create_is_no_open_bd_error {
    message
    options
} {
    set expected_lines [list \
        {ERROR: [BD 5-104] A block design must be open to run this command.} \
        {ERROR: [BD 5-104] A block design must be open to run this command. Please create/open a block design.} \
        {ERROR: [Common 17-39] 'current_bd_design' failed due to earlier errors.}]
    set candidates [list $message]
    if {[dict exists $options -errorinfo]} {
        lappend candidates [dict get $options -errorinfo]
    }
    foreach candidate $candidates {
        foreach line [split $candidate "\n"] {
            if {[lsearch -exact $expected_lines [string trim $line]] >= 0} {
                return 1
            }
        }
    }
    return 0
}

proc ::stage1d::bd_flow::_create_query_current_bd_allow_empty {} {
    set query_status [catch {
        _create_invoke current_bd_design
    } current_bd query_options]
    if {$query_status == 0} {
        return $current_bd
    }
    if {[_create_is_no_open_bd_error $current_bd $query_options]} {
        return {}
    }
    _create_raise FAIL BD_CURRENT_QUERY_FAILED VIVADO \
        "Unable to query the current block design: $current_bd"
}

proc ::stage1d::bd_flow::_create_decode_error {
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
        [lrange $tcl_error_code 0 1] eq {STAGE1E BD_FLOW_CREATE}} {
        set status [lindex $tcl_error_code 2]
        set error_code [lindex $tcl_error_code 3]
        set error_class [lindex $tcl_error_code 4]
    } elseif {[lrange $tcl_error_code 0 2] eq {TCL LOOKUP COMMAND}} {
        set status BLOCKED
        set error_code VIVADO_COMMAND_UNAVAILABLE
        set error_class ENVIRONMENT
    }
    return [dict create \
        status $status \
        error_code $error_code \
        error_class $error_class \
        message $message \
        underlying_error $underlying_error]
}

proc ::stage1d::bd_flow::_create_error_record {decoded} {
    set code [dict get $decoded error_code]
    set class [dict get $decoded error_class]
    return [dict create \
        code $code \
        error_code $code \
        class $class \
        category $class \
        operation bd_flow::create \
        phase BD_GENERATION \
        message [dict get $decoded message] \
        underlying_error [dict get $decoded underlying_error] \
        evidence_references {}]
}

proc ::stage1d::bd_flow::_create_cleanup_result {
    required
    attempted
    completed
    disposition
} {
    return [dict create \
        owner bd_flow \
        required $required \
        attempted $attempted \
        completed $completed \
        disposition $disposition \
        errors {}]
}

proc ::stage1d::bd_flow::_create_context_execution_id {context} {
    if {![catch {dict size $context}] &&
        [dict exists $context execution_id]} {
        return [dict get $context execution_id]
    }
    return {}
}

proc ::stage1d::bd_flow::_create_result {
    status
    context
    consumed_identities
    produced_identities
    ownership_records
    evidence
    warnings
    errors
    cleanup_result
    vivado_invoked
} {
    return [dict create \
        schema_version stage1e-bd-create-result-v1 \
        operation bd_flow::create \
        phase BD_GENERATION \
        execution_id [_create_context_execution_id $context] \
        status $status \
        consumed_identities $consumed_identities \
        produced_identities $produced_identities \
        ownership_records $ownership_records \
        bd_ownership $ownership_records \
        evidence $evidence \
        evidence_references $evidence \
        warnings $warnings \
        errors $errors \
        cleanup_result $cleanup_result \
        vivado_invoked $vivado_invoked \
        topology_created 0 \
        topology_mutation_performed 0 \
        bd_validated 0 \
        bd_saved 0 \
        output_products_generated 0 \
        synthesis_performed 0 \
        implementation_performed 0 \
        artifacts_generated 0 \
        artifact_generation_performed 0 \
        artifact_publication_performed 0]
}

proc ::stage1d::bd_flow::_create_require_dictionary {value label} {
    if {[catch {dict size $value} dictionary_error]} {
        _create_raise FAIL CONTEXT_FIELD_INVALID CONTRACT \
            "$label must be a dictionary: $dictionary_error"
    }
}

proc ::stage1d::bd_flow::_create_require_keys {
    dictionary
    required_keys
    label
} {
    _create_require_dictionary $dictionary $label
    foreach key $required_keys {
        if {![dict exists $dictionary $key]} {
            _create_raise FAIL CONTEXT_FIELD_MISSING CONTRACT \
                "$label is missing required key: $key"
        }
    }
}

proc ::stage1d::bd_flow::_create_is_strict_descendant {
    candidate_path
    parent_path
} {
    return [expr {
        ![_paths_equal $candidate_path $parent_path] &&
        [_is_equal_or_descendant $candidate_path $parent_path]
    }]
}

proc ::stage1d::bd_flow::_create_validate_authorization {
    authorization
    execution_id
} {
    if {[catch {dict size $authorization} authorization_error]} {
        _create_raise BLOCKED AUTHORIZATION_INVALID AUTHORIZATION \
            "authorization must be a dictionary: $authorization_error"
    }
    foreach key {
        status
        authority
        execution_id
        operation
        phase
        capability
        capability_enabled
    } {
        if {![dict exists $authorization $key]} {
            _create_raise BLOCKED AUTHORIZATION_INCOMPLETE AUTHORIZATION \
                "authorization is missing required key: $key"
        }
    }
    if {[dict get $authorization status] ne {AUTHORIZED} ||
        [dict get $authorization authority] ne {controller_core} ||
        [dict get $authorization execution_id] ne $execution_id ||
        [dict get $authorization operation] ne {bd_flow::create} ||
        [dict get $authorization phase] ne {BD_GENERATION} ||
        [dict get $authorization capability] ne {bd_generation_enabled} ||
        ![string is boolean -strict \
            [dict get $authorization capability_enabled]] ||
        ![dict get $authorization capability_enabled]} {
        _create_raise BLOCKED AUTHORIZATION_MISMATCH AUTHORIZATION \
            {Controller authorization does not permit BD creation.}
    }
}

proc ::stage1d::bd_flow::_create_validate_identity {
    identity
    label
    execution_id
} {
    _create_require_dictionary $identity $label
    if {[dict size $identity] == 0} {
        _create_raise FAIL IDENTITY_MISSING IDENTITY \
            "$label must not be empty."
    }
    if {[dict exists $identity execution_id] &&
        [dict get $identity execution_id] ne $execution_id} {
        _create_raise FAIL CONSUMED_IDENTITY_EXECUTION_MISMATCH IDENTITY \
            "$label belongs to another execution."
    }
    return $identity
}

proc ::stage1d::bd_flow::_create_validate_topology_policy {
    topology_policy
    execution_id
} {
    _create_require_keys $topology_policy {
        schema_version
        policy_id
        source_reference
        sha256
    } {topology_policy}
    if {[dict get $topology_policy schema_version] ne
        {stage1e-topology-policy-reference-v1}} {
        _create_raise FAIL TOPOLOGY_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {topology_policy has an unsupported schema version.}
    }
    foreach field {policy_id source_reference} {
        if {[string trim [dict get $topology_policy $field]] eq {}} {
            _create_raise FAIL TOPOLOGY_POLICY_INVALID CONTRACT \
                "topology_policy $field must not be empty."
        }
    }
    set digest [string tolower [dict get $topology_policy sha256]]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {
        _create_raise FAIL TOPOLOGY_POLICY_HASH_INVALID IDENTITY \
            {topology_policy sha256 is invalid.}
    }
    if {[dict exists $topology_policy execution_id] &&
        [dict get $topology_policy execution_id] ne $execution_id} {
        _create_raise FAIL TOPOLOGY_POLICY_EXECUTION_MISMATCH IDENTITY \
            {topology_policy belongs to another execution.}
    }
    dict set topology_policy sha256 $digest
    return $topology_policy
}

proc ::stage1d::bd_flow::_validate_create_context {context} {
    _create_require_keys $context {
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
        bd_identity
        topology_policy
    } {BD create context}

    if {[dict get $context context_schema_version] ne
        {stage1e-bd-create-context-v1}} {
        _create_raise FAIL CONTEXT_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported Stage 1E BD create context schema.}
    }
    if {[dict get $context operation] ne {bd_flow::create} ||
        [dict get $context phase] ne {BD_GENERATION}} {
        _create_raise FAIL OPERATION_MISMATCH CONTRACT \
            {BD create operation or phase does not match the interface.}
    }
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        _create_raise FAIL EXECUTION_ID_INVALID CONTRACT \
            {BD create execution_id must not be empty.}
    }
    _create_validate_authorization \
        [dict get $context authorization] $execution_id
    if {[dict exists $context bd_ownership]} {
        _create_raise FAIL AMBIGUOUS_BD_OWNERSHIP OWNERSHIP \
            {BD creation cannot replace existing bd_ownership.}
    }

    set source_identity [_create_validate_identity \
        [dict get $context source_identity] source_identity $execution_id]
    set environment_identity [_create_validate_identity \
        [dict get $context environment_identity] \
        environment_identity $execution_id]
    set configuration_identity [_create_validate_identity \
        [dict get $context configuration_identity] \
        configuration_identity $execution_id]
    set topology_policy [_create_validate_topology_policy \
        [dict get $context topology_policy] $execution_id]

    set bd_identity [dict get $context bd_identity]
    _create_require_keys $bd_identity {
        schema_version
        bd_name
        expected_bd_path
    } {bd_identity}
    if {[dict get $bd_identity schema_version] ne
        {stage1e-bd-create-identity-v1}} {
        _create_raise FAIL BD_IDENTITY_SCHEMA_UNSUPPORTED CONTRACT \
            {bd_identity has an unsupported schema version.}
    }
    set bd_name [dict get $bd_identity bd_name]
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $bd_name]} {
        _create_raise FAIL BD_NAME_INVALID IDENTITY \
            "bd_identity name is invalid: $bd_name"
    }

    # Reuse the existing Stage 1D context and project-ownership validation by
    # projecting only the fields it already owns. The create-specific checks
    # above retain the stronger Stage 1E authorization contract.
    set project_ownership [dict get $context project_ownership]
    _create_require_dictionary $project_ownership project_ownership
    if {![dict exists $project_ownership project_path]} {
        _create_raise FAIL PROJECT_OWNERSHIP_INCOMPLETE OWNERSHIP \
            {project_ownership is missing project_path.}
    }
    set projected_context $context
    dict set projected_context project_path \
        [dict get $project_ownership project_path]
    dict set projected_context bd_name $bd_name
    if {[catch {
        _validate_context $projected_context bd_flow::create
    } validated_context validation_options]} {
        _create_raise FAIL PROJECT_OWNERSHIP_INVALID OWNERSHIP \
            "BD create project ownership validation failed: $validated_context"
    }

    set workspace_root [dict get $validated_context workspace_root]
    set evidence_dir [file normalize [dict get $context evidence_dir]]
    set project_path [dict get $validated_context project_path]
    set project_directory [file dirname $project_path]
    if {![file isdirectory $evidence_dir]} {
        _create_raise FAIL EVIDENCE_DIRECTORY_INVALID WORKSPACE \
            {BD create evidence_dir must exist.}
    }
    if {![file isfile $project_path]} {
        _create_raise BLOCKED PROJECT_FILE_UNAVAILABLE DEPENDENCY \
            {The owned Vivado project file is unavailable.}
    }

    set expected_bd_path [dict get $bd_identity expected_bd_path]
    if {[file pathtype $expected_bd_path] ne {absolute}} {
        _create_raise FAIL BD_PATH_NOT_ABSOLUTE WORKSPACE \
            {bd_identity expected_bd_path must be absolute.}
    }
    set expected_bd_path [file normalize $expected_bd_path]
    if {![_create_is_strict_descendant $expected_bd_path $workspace_root] ||
        ![_create_is_strict_descendant $expected_bd_path \
            $project_directory]} {
        _create_raise FAIL BD_PATH_REJECTED WORKSPACE \
            {Expected BD path must be project-contained and execution-owned.}
    }
    if {![string equal -nocase \
        [file extension $expected_bd_path] {.bd}] ||
        [file rootname [file tail $expected_bd_path]] ne $bd_name} {
        _create_raise FAIL BD_PATH_IDENTITY_MISMATCH IDENTITY \
            {Expected BD path does not match the authorized BD name.}
    }
    if {[file exists $expected_bd_path]} {
        _create_raise FAIL BD_ALREADY_EXISTS WORKSPACE \
            {Expected BD path already exists; adoption is forbidden.}
    }
    dict set bd_identity expected_bd_path $expected_bd_path

    set project_identity [dict get $project_ownership project_identity]
    _create_require_keys $project_identity {
        project_name
        project_directory
        part
        board_part
    } {project_ownership project_identity}
    if {![_paths_equal \
        [dict get $project_identity project_directory] $project_directory]} {
        _create_raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
            {Project identity directory does not match project ownership.}
    }
    foreach identity_field {part board_part} {
        if {![dict exists $environment_identity $identity_field] ||
            [dict get $project_identity $identity_field] ne
                [dict get $environment_identity $identity_field]} {
            _create_raise FAIL PROJECT_ENVIRONMENT_MISMATCH IDENTITY \
                "Project identity does not match $identity_field."
        }
    }

    return [dict merge $validated_context [dict create \
        context $context \
        source_identity $source_identity \
        environment_identity $environment_identity \
        configuration_identity $configuration_identity \
        project_ownership $project_ownership \
        project_identity $project_identity \
        project_directory $project_directory \
        bd_identity $bd_identity \
        expected_bd_path $expected_bd_path \
        topology_policy $topology_policy]]
}

proc ::stage1d::bd_flow::_create_require_single_object {
    objects
    label
} {
    if {[llength $objects] != 1} {
        _create_raise FAIL VIVADO_OBJECT_CARDINALITY VIVADO \
            "$label must resolve to exactly one object; found [llength $objects]."
    }
    return [lindex $objects 0]
}

proc ::stage1d::bd_flow::_create_verify_current_project {validated} {
    set expected_handle [dict get $validated project_handle]
    set current_handle [_create_invoke current_project]
    if {$current_handle eq {} || $current_handle ne $expected_handle} {
        _create_raise FAIL PROJECT_HANDLE_MISMATCH OWNERSHIP \
            "Current project is not the owned project: actual=$current_handle expected=$expected_handle"
    }

    set project_identity [dict get $validated project_identity]
    set actual_name [_create_invoke get_property NAME $current_handle]
    set actual_directory [file normalize \
        [_create_invoke get_property DIRECTORY $current_handle]]
    set actual_part [_create_invoke get_property PART $current_handle]
    set actual_board_part [_create_invoke get_property BOARD_PART \
        $current_handle]
    if {$actual_name ne [dict get $project_identity project_name] ||
        ![_paths_equal $actual_directory \
            [dict get $validated project_directory]] ||
        $actual_part ne [dict get $project_identity part] ||
        $actual_board_part ne [dict get $project_identity board_part]} {
        _create_raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
            {Current Vivado project does not match project_ownership identity.}
    }
    return [dict create \
        project_name $actual_name \
        project_directory $actual_directory \
        part $actual_part \
        board_part $actual_board_part]
}

proc ::stage1d::bd_flow::_create_assert_no_existing_bd {validated} {
    set bd_name [dict get $validated bd_name]
    set bd_pattern [format {*%s.bd} $bd_name]
    set existing_files [_create_invoke get_files -quiet -all $bd_pattern]
    if {[llength $existing_files] != 0} {
        _create_raise FAIL BD_ALREADY_EXISTS OWNERSHIP \
            "A block-design file already exists for $bd_name: $existing_files"
    }
    set existing_designs [_create_invoke get_bd_designs -quiet $bd_name]
    if {[llength $existing_designs] != 0} {
        _create_raise FAIL BD_ALREADY_EXISTS OWNERSHIP \
            "A block design is already loaded for $bd_name: $existing_designs"
    }
    set current_bd [_create_query_current_bd_allow_empty]
    if {$current_bd ne {}} {
        _create_raise FAIL BD_SESSION_OCCUPIED OWNERSHIP \
            "Vivado already has a current block design: $current_bd"
    }
}

proc ::stage1d::bd_flow::_create_topology_readback {} {
    set readback [dict create]
    foreach command {
        get_bd_cells
        get_bd_ports
        get_bd_intf_ports
        get_bd_nets
        get_bd_intf_nets
    } {
        set objects [_create_invoke $command -quiet]
        if {[llength $objects] != 0} {
            _create_raise FAIL BD_NOT_EMPTY IDENTITY \
                "New block design contains topology objects from $command."
        }
        dict set readback $command 0
    }
    return $readback
}

proc ::stage1d::bd_flow::create {context} {
    set validation_status [catch {
        _validate_create_context $context
    } validated validation_options]
    if {$validation_status != 0} {
        set decoded [_create_decode_error $validated $validation_options \
            BD_CREATE_CONTEXT_INVALID CONTRACT]
        return [_create_result \
            [dict get $decoded status] $context {} {} {} {} {} \
            [list [_create_error_record $decoded]] \
            [_create_cleanup_result 0 0 1 NOT_REQUIRED] 0]
    }

    set consumed_identities [dict create \
        source_identity [dict get $validated source_identity] \
        environment_identity [dict get $validated environment_identity] \
        configuration_identity [dict get $validated configuration_identity] \
        project_ownership [dict get $validated project_ownership] \
        bd_identity_expectation [dict get $validated bd_identity] \
        topology_policy [dict get $validated topology_policy]]
    set vivado_invoked 1
    set bd_create_attempted 0
    set execution_status [catch {
        set project_readback [_create_verify_current_project $validated]
        _create_assert_no_existing_bd $validated

        set bd_create_attempted 1
        _create_invoke create_bd_design [dict get $validated bd_name]
        set current_bd [_create_invoke current_bd_design]
        if {$current_bd ne [dict get $validated bd_name]} {
            _create_raise FAIL BD_IDENTITY_MISMATCH IDENTITY \
                "Created BD identity mismatch: actual=$current_bd expected=[dict get $validated bd_name]"
        }

        set bd_pattern [format {*%s.bd} [dict get $validated bd_name]]
        set bd_file [_create_require_single_object \
            [_create_invoke get_files -quiet -all $bd_pattern] \
            {Created block-design file}]
        set bd_path [file normalize \
            [_create_invoke get_property NAME $bd_file]]
        if {![_paths_equal $bd_path \
            [dict get $validated expected_bd_path]] ||
            ![_create_is_strict_descendant $bd_path \
                [dict get $validated project_directory]] ||
            ![string equal -nocase [file extension $bd_path] {.bd}] ||
            [file rootname [file tail $bd_path]] ne
                [dict get $validated bd_name]} {
            _create_raise FAIL BD_PATH_IDENTITY_MISMATCH IDENTITY \
                "Created BD path mismatch: actual=$bd_path expected=[dict get $validated expected_bd_path]"
        }
        set topology_readback [_create_topology_readback]

        set lifecycle_context [_lifecycle_context \
            $context $validated $bd_path]
        set bd_ownership [dict get $lifecycle_context bd_ownership]
        set produced_bd_identity [dict create \
            schema_version stage1e-bd-identity-v1 \
            producer_operation bd_flow::create \
            execution_id [dict get $validated execution_id] \
            project_path [dict get $validated project_path] \
            bd_name [dict get $validated bd_name] \
            bd_path $bd_path \
            topology_policy [dict get $validated topology_policy] \
            empty_design_verified 1]
        set evidence [dict create \
            project_readback $project_readback \
            bd_readback [dict create \
                bd_name $current_bd \
                bd_path $bd_path] \
            topology_readback $topology_readback]
    } execution_error execution_options]

    if {$execution_status != 0} {
        set decoded [_create_decode_error $execution_error \
            $execution_options BD_CREATE_FAILED VIVADO]
        if {$bd_create_attempted} {
            set cleanup_result [_create_cleanup_result \
                1 0 0 PROJECT_CLEANUP_REQUIRED]
        } else {
            set cleanup_result [_create_cleanup_result \
                0 0 1 NOT_REQUIRED]
        }
        return [_create_result \
            [dict get $decoded status] $context $consumed_identities \
            {} {} {} {} [list [_create_error_record $decoded]] \
            $cleanup_result $vivado_invoked]
    }

    return [_create_result PASS $context $consumed_identities \
        [dict create bd_identity $produced_bd_identity] \
        $bd_ownership $evidence {} {} \
        [_create_cleanup_result 0 0 1 NOT_REQUIRED] $vivado_invoked]
}
