# Stage 1D Vivado project lifecycle adapter.
#
# Ownership boundary:
# - consume the explicit controller lifecycle context;
# - validate and open the authorized project path;
# - verify project handle, path, part, and board identity;
# - return explicit project-handle ownership for normal close or failure cleanup;
# - return structured results without making controller continuation decisions.
#
# This module is definition-only when sourced. Vivado commands are invoked only
# through an explicit open, close, or cleanup procedure call. Lifecycle state is
# passed in dictionaries; the adapter retains no hidden namespace/global state.

namespace eval ::stage1d::vivado_project {}

proc ::stage1d::vivado_project::_get_or_default {dictionary key default_value} {
    if {[dict exists $dictionary $key]} {
        return [dict get $dictionary $key]
    }
    return $default_value
}

proc ::stage1d::vivado_project::_error_record {
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
        phase_name vivado_project \
        operation $operation \
        message $message \
        underlying_error $underlying_error \
        evidence_references {} \
        recoverability $recoverability]
}

# Result-schema boundary:
#
# Project lifecycle operations return structured results with the consistent
# semantic fields status, phase, execution_id, vivado_invoked,
# artifacts_generated, errors, warnings, and outputs. Result construction stays
# local to this Stage 1D adapter. A future Stage 1E evolution may extract shared
# result construction into a dedicated module without changing this boundary.
proc ::stage1d::vivado_project::_result {
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
        phase vivado_project \
        execution_id $execution_id \
        vivado_invoked $vivado_invoked \
        artifacts_generated 0 \
        errors $errors \
        warnings $warnings \
        evidence_locations {} \
        logs {} \
        reports {} \
        outputs [dict merge [dict create \
            lifecycle_owner vivado_project \
            artifacts_generated 0] $outputs] \
        artifact_references {}]
}

proc ::stage1d::vivado_project::_stop {
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

proc ::stage1d::vivado_project::_canonical_components {path} {
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

proc ::stage1d::vivado_project::_paths_equal {first_path second_path} {
    return [expr {
        [_canonical_components $first_path] eq
        [_canonical_components $second_path]
    }]
}

proc ::stage1d::vivado_project::_is_equal_or_descendant {
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

proc ::stage1d::vivado_project::_validate_context {context} {
    if {[catch {dict size $context} context_error]} {
        error "Vivado project adapter context is not a dictionary: $context_error"
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
    } {
        if {![dict exists $context $required_key]} {
            error "Vivado project adapter context is missing required key: $required_key"
        }
    }

    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        error {Vivado project adapter requires a nonempty execution_id.}
    }

    set authorization [dict get $context authorization]
    if {[catch {dict size $authorization} authorization_error]} {
        error "Vivado project authorization is not a dictionary: $authorization_error"
    }
    foreach authorization_key {status authority operation} {
        if {![dict exists $authorization $authorization_key]} {
            error "Vivado project authorization is missing key: $authorization_key"
        }
    }
    if {[dict get $authorization status] ne {AUTHORIZED} ||
        [dict get $authorization authority] ne {controller_core} ||
        [dict get $authorization operation] ne {vivado_project_open}} {
        error {Vivado project operation is not explicitly authorized by controller_core.}
    }

    set workspace_root [dict get $context workspace_root]
    set project_path [dict get $context project_path]
    if {[file pathtype $workspace_root] ne {absolute}} {
        error {Vivado project workspace_root must be an absolute path.}
    }
    if {[file pathtype $project_path] ne {absolute}} {
        error {Vivado project project_path must be an absolute path.}
    }
    set workspace_root [file normalize $workspace_root]
    set project_path [file normalize $project_path]
    if {![_is_equal_or_descendant $project_path $workspace_root]} {
        error {Vivado project_path must remain within workspace_root.}
    }
    if {![string equal -nocase [file extension $project_path] {.xpr}]} {
        error {Vivado project_path must identify a .xpr file.}
    }

    set environment_identity [dict get $context environment_identity]
    if {[catch {dict size $environment_identity} environment_error]} {
        error "Vivado project environment_identity is not a dictionary: $environment_error"
    }
    foreach identity_key {part board_part} {
        if {![dict exists $environment_identity $identity_key] ||
            [string trim [dict get $environment_identity $identity_key]] eq {}} {
            error "Vivado project environment_identity is missing: $identity_key"
        }
    }

    return [dict create \
        execution_id $execution_id \
        workspace_root $workspace_root \
        project_path $project_path \
        expected_project_name [file rootname [file tail $project_path]] \
        expected_project_directory [file dirname $project_path] \
        expected_part [dict get $environment_identity part] \
        expected_board_part [dict get $environment_identity board_part]]
}

proc ::stage1d::vivado_project::_project_file_available {project_path} {
    return [expr {[file exists $project_path] && [file isfile $project_path]}]
}

proc ::stage1d::vivado_project::_current_project_handle {} {
    return [current_project]
}

proc ::stage1d::vivado_project::_verify_project_identity {
    project_handle
    validated_context
} {
    if {$project_handle eq {}} {
        error {Vivado did not establish a current project handle after open_project.}
    }

    set actual_name [get_property NAME $project_handle]
    set actual_directory [file normalize [get_property DIRECTORY $project_handle]]
    set actual_part [get_property PART $project_handle]
    set actual_board_part [get_property BOARD_PART $project_handle]

    if {$actual_name ne [dict get $validated_context expected_project_name]} {
        error "Vivado project name mismatch: actual=$actual_name expected=[dict get $validated_context expected_project_name]"
    }
    if {![_paths_equal \
        $actual_directory \
        [dict get $validated_context expected_project_directory]]} {
        error "Vivado project directory mismatch: actual=$actual_directory expected=[dict get $validated_context expected_project_directory]"
    }
    if {$actual_part ne [dict get $validated_context expected_part]} {
        error "Vivado project part mismatch: actual=$actual_part expected=[dict get $validated_context expected_part]"
    }
    if {$actual_board_part ne [dict get $validated_context expected_board_part]} {
        error "Vivado project board part mismatch: actual=$actual_board_part expected=[dict get $validated_context expected_board_part]"
    }

    return [dict create \
        project_name $actual_name \
        project_directory $actual_directory \
        part $actual_part \
        board_part $actual_board_part]
}

proc ::stage1d::vivado_project::_owned_context {
    context
    validated_context
    project_handle
    project_identity
} {
    dict set context project_ownership [dict create \
        owner vivado_project \
        execution_id [dict get $validated_context execution_id] \
        project_handle $project_handle \
        project_path [dict get $validated_context project_path] \
        identity_verified 1 \
        project_identity $project_identity]
    return $context
}

proc ::stage1d::vivado_project::_validate_owned_context {context} {
    set validated_context [_validate_context $context]
    if {![dict exists $context project_ownership]} {
        error {Vivado project lifecycle context has no project_ownership record.}
    }

    set ownership [dict get $context project_ownership]
    if {[catch {dict size $ownership} ownership_error]} {
        error "Vivado project_ownership is not a dictionary: $ownership_error"
    }
    foreach ownership_key {
        owner
        execution_id
        project_handle
        project_path
        identity_verified
        project_identity
    } {
        if {![dict exists $ownership $ownership_key]} {
            error "Vivado project_ownership is missing key: $ownership_key"
        }
    }
    if {[dict get $ownership owner] ne {vivado_project}} {
        error {Vivado project lifecycle authority is not vivado_project.}
    }
    if {[dict get $ownership execution_id] ne \
        [dict get $validated_context execution_id]} {
        error {Vivado project ownership execution_id does not match context.}
    }
    if {[string trim [dict get $ownership project_handle]] eq {}} {
        error {Vivado project ownership handle must not be empty.}
    }
    if {![_paths_equal \
        [dict get $ownership project_path] \
        [dict get $validated_context project_path]]} {
        error {Vivado project ownership path does not match context.}
    }
    if {![string is boolean -strict [dict get $ownership identity_verified]] ||
        ![dict get $ownership identity_verified]} {
        error {Vivado project ownership requires verified project identity.}
    }

    dict set validated_context project_handle \
        [dict get $ownership project_handle]
    return $validated_context
}

proc ::stage1d::vivado_project::_failed_open_cleanup {} {
    if {[catch {_current_project_handle} current_handle query_options]} {
        return [dict create \
            cleanup_attempted 1 \
            cleanup_completed 0 \
            cleanup_error [_get_or_default $query_options -errorinfo {}]]
    }
    if {$current_handle eq {}} {
        return [dict create \
            cleanup_attempted 1 \
            cleanup_completed 1 \
            cleanup_error {}]
    }
    if {[catch {close_project} close_error close_options]} {
        return [dict create \
            cleanup_attempted 1 \
            cleanup_completed 0 \
            cleanup_error [_get_or_default $close_options -errorinfo $close_error]]
    }
    return [dict create \
        cleanup_attempted 1 \
        cleanup_completed 1 \
        cleanup_error {}]
}

proc ::stage1d::vivado_project::open {context} {
    set operation open

    if {[catch {_validate_context $context} validated_context context_options]} {
        set underlying_error [_get_or_default $context_options -errorinfo {}]
        return [_stop FAIL $context \
            VIVADO_PROJECT_CONTEXT_INVALID CONTRACT $operation \
            "Vivado project context validation failed: $validated_context" \
            $underlying_error FIX_CONTROLLER_CONTEXT \
            [dict create operation $operation project_opened 0 vivado_invoked 0]]
    }

    set project_path [dict get $validated_context project_path]
    if {![_project_file_available $project_path]} {
        return [_stop BLOCKED $context \
            VIVADO_PROJECT_NOT_FOUND WORKSPACE $operation \
            "Authorized Vivado project file is unavailable: $project_path" \
            {} PREPARE_PROJECT_WORKSPACE \
            [dict create operation $operation project_path $project_path \
                project_opened 0 vivado_invoked 0]]
    }

    if {[catch {_current_project_handle} existing_handle query_options]} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_QUERY_FAILED VIVADO $operation \
            "Unable to query the current Vivado project before open: $existing_handle" \
            [_get_or_default $query_options -errorinfo {}] CLEANUP_REQUIRED \
            [dict create operation $operation project_path $project_path \
                project_opened 0 vivado_invoked 1]]
    }
    if {$existing_handle ne {}} {
        return [_stop BLOCKED $context \
            VIVADO_PROJECT_SESSION_OCCUPIED OWNERSHIP $operation \
            {Vivado already has a current project; the adapter will not assume its ownership.} \
            {} CLOSE_EXISTING_PROJECT \
            [dict create operation $operation project_path $project_path \
                project_opened 0 vivado_invoked 1]]
    }

    set open_status [catch {
        open_project $project_path
    } open_result open_options]
    if {$open_status != 0} {
        set cleanup_outputs [_failed_open_cleanup]
        return [_stop FAIL $context \
            VIVADO_PROJECT_OPEN_FAILED VIVADO $operation \
            "Vivado open_project failed: $open_result" \
            [_get_or_default $open_options -errorinfo {}] CLEANUP_REQUIRED \
            [dict merge [dict create operation $operation \
                project_path $project_path \
                project_opened 0 \
                vivado_invoked 1] $cleanup_outputs]]
    }

    set identity_status [catch {
        set project_handle [_current_project_handle]
        set project_identity [_verify_project_identity \
            $project_handle $validated_context]
    } identity_error identity_options]
    if {$identity_status != 0} {
        set cleanup_status [catch {close_project} cleanup_error]
        if {$cleanup_status == 0} {
            set cleanup_error {}
        }
        return [_stop FAIL $context \
            VIVADO_PROJECT_IDENTITY_MISMATCH IDENTITY $operation \
            "Opened Vivado project failed identity verification: $identity_error" \
            [_get_or_default $identity_options -errorinfo {}] REJECT_PROJECT \
            [dict create \
                operation $operation \
                project_path $project_path \
                project_opened 0 \
                identity_verified 0 \
                cleanup_attempted 1 \
                cleanup_completed [expr {$cleanup_status == 0}] \
                cleanup_error $cleanup_error \
                vivado_invoked 1]]
    }

    set lifecycle_context [_owned_context \
        $context $validated_context $project_handle $project_identity]

    return [_result PASS $context {} [dict merge [dict create \
        operation $operation \
        project_path $project_path \
        project_handle $project_handle \
        project_handle_owned 1 \
        project_opened 1 \
        identity_verified 1 \
        lifecycle_context $lifecycle_context \
        vivado_invoked 1] $project_identity]]
}

proc ::stage1d::vivado_project::close {context} {
    set operation close

    if {[catch {_validate_owned_context $context} validated_context context_options]} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_CONTEXT_INVALID CONTRACT $operation \
            "Vivado project close context validation failed: $validated_context" \
            [_get_or_default $context_options -errorinfo {}] FIX_CONTROLLER_CONTEXT \
            [dict create operation $operation project_closed 0 vivado_invoked 0]]
    }

    set expected_handle [dict get $validated_context project_handle]
    if {[catch {_current_project_handle} current_handle current_options] ||
        $current_handle ne $expected_handle} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_HANDLE_MISMATCH OWNERSHIP $operation \
            "Current Vivado project is not the adapter-owned handle: current=$current_handle expected=$expected_handle" \
            [_get_or_default $current_options -errorinfo {}] RESTORE_OWNED_PROJECT \
            [dict create operation $operation project_closed 0 vivado_invoked 1]]
    }

    if {[catch {close_project} close_error close_options]} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_CLOSE_FAILED VIVADO $operation \
            "Vivado close_project failed: $close_error" \
            [_get_or_default $close_options -errorinfo {}] CLEANUP_REQUIRED \
            [dict create operation $operation project_closed 0 vivado_invoked 1]]
    }

    set released_context [dict remove $context project_ownership]
    return [_result PASS $context {} [dict create \
        operation $operation \
        project_path [dict get $validated_context project_path] \
        project_handle_owned 0 \
        project_closed 1 \
        lifecycle_context $released_context \
        vivado_invoked 1]]
}

proc ::stage1d::vivado_project::cleanup {context reason} {
    set operation cleanup

    if {[string trim $reason] eq {}} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_CLEANUP_REASON_MISSING CONTRACT $operation \
            {Vivado project cleanup requires a nonempty reason.} \
            {} PROVIDE_CLEANUP_REASON \
            [dict create operation $operation cleanup_completed 0 vivado_invoked 0]]
    }
    if {[catch {_validate_context $context} validated_context context_options]} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_CONTEXT_INVALID CONTRACT $operation \
            "Vivado project cleanup context validation failed: $validated_context" \
            [_get_or_default $context_options -errorinfo {}] FIX_CONTROLLER_CONTEXT \
            [dict create operation $operation cleanup_completed 0 \
                cleanup_reason $reason vivado_invoked 0]]
    }

    if {![dict exists $context project_ownership]} {
        return [_result PASS $context {} [dict create \
            operation $operation \
            cleanup_reason $reason \
            cleanup_completed 1 \
            project_closed 0 \
            vivado_invoked 0]]
    }

    if {[catch {_validate_owned_context $context} validated_context context_options]} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_OWNERSHIP_INVALID OWNERSHIP $operation \
            "Vivado project cleanup ownership validation failed: $validated_context" \
            [_get_or_default $context_options -errorinfo {}] FIX_LIFECYCLE_CONTEXT \
            [dict create operation $operation cleanup_reason $reason \
                cleanup_completed 0 vivado_invoked 0]]
    }

    set expected_handle [dict get $validated_context project_handle]
    if {[catch {_current_project_handle} current_handle current_options]} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_CLEANUP_QUERY_FAILED VIVADO $operation \
            "Unable to query current Vivado project during cleanup: $current_handle" \
            [_get_or_default $current_options -errorinfo {}] MANUAL_SESSION_CLEANUP \
            [dict create operation $operation cleanup_reason $reason \
                cleanup_completed 0 vivado_invoked 1]]
    }
    if {$current_handle ne {} && $current_handle ne $expected_handle} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_HANDLE_MISMATCH OWNERSHIP $operation \
            "Cleanup refused to close a non-owned project: current=$current_handle expected=$expected_handle" \
            {} MANUAL_SESSION_CLEANUP \
            [dict create operation $operation cleanup_reason $reason \
                cleanup_completed 0 vivado_invoked 1]]
    }

    if {$current_handle ne {} &&
        [catch {close_project} close_error close_options]} {
        return [_stop FAIL $context \
            VIVADO_PROJECT_CLEANUP_CLOSE_FAILED VIVADO $operation \
            "Vivado close_project failed during cleanup: $close_error" \
            [_get_or_default $close_options -errorinfo {}] MANUAL_SESSION_CLEANUP \
            [dict create operation $operation cleanup_reason $reason \
                cleanup_completed 0 vivado_invoked 1]]
    }

    set released_context [dict remove $context project_ownership]
    return [_result PASS $context {} [dict create \
        operation $operation \
        cleanup_reason $reason \
        cleanup_completed 1 \
        project_closed [expr {$current_handle ne {}}] \
        project_handle_owned 0 \
        lifecycle_context $released_context \
        vivado_invoked 1]]
}

# Stage 1E additive project-creation boundary.
#
# This extension deliberately leaves the Stage 1D open/close/cleanup helpers
# above unchanged. It creates a project through the same singular
# vivado_project owner and returns the existing project_ownership record shape.
# It is definition-only when sourced and cannot create a BD or run a build.
namespace eval ::stage1d::vivado_project::create_backend {}

# Reuse the existing source-verification digest implementation so project-only
# sources and constraints are rechecked against the accepted inventory before
# any Vivado mutation. Loading it defines procedures only.
if {[llength [info commands ::stage1d::source_check::sha256_file]] == 0} {
    set ::stage1d::vivado_project::_create_source_check_path \
        [file normalize [file join [file dirname [info script]] \
            source_check.tcl]]
    source $::stage1d::vivado_project::_create_source_check_path
    unset ::stage1d::vivado_project::_create_source_check_path
}

proc ::stage1d::vivado_project::create_backend::invoke {
    command
    arguments
} {
    return [uplevel #0 [list $command {*}$arguments]]
}

# Vivado project handles carry an internal object representation that can be
# lost when current_project is stored and later passed back as a plain project
# name. Keep project property access at this production boundary so Vivado
# evaluates the explicit current-project object in the consuming command.
proc ::stage1d::vivado_project::create_backend::set_current_project_property {
    property
    value
} {
    return [set_property $property $value [current_project]]
}

proc ::stage1d::vivado_project::create_backend::get_current_project_property {
    property
} {
    return [get_property $property [current_project]]
}

proc ::stage1d::vivado_project::_create_invoke {command args} {
    return [::stage1d::vivado_project::create_backend::invoke \
        $command $args]
}

# Vivado 2024.1 raises Coretcl 2-88 when current_project is queried in an
# empty session. Only project-creation preflight and failed-create cleanup may
# interpret that exact condition as an empty handle. Post-create verification
# and the existing Stage 1D owned-project operations remain strict.
proc ::stage1d::vivado_project::_create_is_no_open_project_error {
    message
    options
} {
    set expected \
        {ERROR: [Coretcl 2-88] No projects are currently open.}
    if {[string trim $message] eq $expected} {
        return 1
    }
    if {[dict exists $options -errorinfo]} {
        foreach line [split [dict get $options -errorinfo] "\n"] {
            if {[string trim $line] eq $expected} {
                return 1
            }
        }
    }
    return 0
}

proc ::stage1d::vivado_project::_create_query_current_project_allow_empty {} {
    set query_status [catch {
        _create_invoke current_project
    } project query_options]
    if {$query_status == 0} {
        return $project
    }
    if {[_create_is_no_open_project_error $project $query_options]} {
        return {}
    }
    _create_raise FAIL VIVADO_PROJECT_QUERY_FAILED VIVADO \
        "Unable to query the current Vivado project: $project"
}

proc ::stage1d::vivado_project::_create_raise {
    status
    error_code
    error_class
    message
} {
    return -code error -errorcode [list \
        STAGE1E VIVADO_PROJECT_CREATE $status $error_code $error_class] \
        $message
}

proc ::stage1d::vivado_project::_create_decode_error {
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
        [lrange $tcl_error_code 0 1] eq
            {STAGE1E VIVADO_PROJECT_CREATE}} {
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

proc ::stage1d::vivado_project::_create_error_record {decoded} {
    set code [dict get $decoded error_code]
    set class [dict get $decoded error_class]
    return [dict create \
        code $code \
        error_code $code \
        class $class \
        category $class \
        operation vivado_project::create \
        phase PROJECT_RECONSTRUCTION \
        message [dict get $decoded message] \
        underlying_error [dict get $decoded underlying_error] \
        evidence_references {}]
}

proc ::stage1d::vivado_project::_create_default_cleanup_result {} {
    return [dict create \
        owner vivado_project \
        required 0 \
        attempted 0 \
        completed 1 \
        project_closed 0 \
        removed_paths {} \
        errors {}]
}

proc ::stage1d::vivado_project::_create_context_execution_id {context} {
    if {![catch {dict size $context}] &&
        [dict exists $context execution_id]} {
        return [dict get $context execution_id]
    }
    return {}
}

proc ::stage1d::vivado_project::_create_result {
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
        schema_version stage1e-vivado-project-create-result-v1 \
        operation vivado_project::create \
        phase PROJECT_RECONSTRUCTION \
        execution_id [_create_context_execution_id $context] \
        status $status \
        consumed_identities $consumed_identities \
        produced_identities $produced_identities \
        ownership_records $ownership_records \
        evidence $evidence \
        evidence_references $evidence \
        warnings $warnings \
        errors $errors \
        cleanup_result $cleanup_result \
        vivado_invoked $vivado_invoked \
        bd_created 0 \
        synthesis_performed 0 \
        implementation_performed 0 \
        artifacts_generated 0 \
        artifact_generation_performed 0 \
        artifact_publication_performed 0]
}

proc ::stage1d::vivado_project::_create_require_dictionary {
    value
    label
} {
    if {[catch {dict size $value} dictionary_error]} {
        _create_raise FAIL CONTEXT_FIELD_INVALID CONTRACT \
            "$label must be a dictionary: $dictionary_error"
    }
}

proc ::stage1d::vivado_project::_create_require_keys {
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

proc ::stage1d::vivado_project::_create_is_strict_descendant {
    candidate_path
    parent_path
} {
    return [expr {
        ![_paths_equal $candidate_path $parent_path] &&
        [_is_equal_or_descendant $candidate_path $parent_path]
    }]
}

proc ::stage1d::vivado_project::_create_paths_overlap {
    first_path
    second_path
} {
    return [expr {
        [_is_equal_or_descendant $first_path $second_path] ||
        [_is_equal_or_descendant $second_path $first_path]
    }]
}

proc ::stage1d::vivado_project::_create_normalize_relative_path {
    path
    label
} {
    set canonical [string map {\\ /} [string trim $path]]
    if {$canonical eq {} || [file pathtype $canonical] ne {relative}} {
        _create_raise FAIL SOURCE_PATH_INVALID SOURCE \
            "$label must be a nonempty repository-relative path."
    }
    set components [file split $canonical]
    foreach component $components {
        if {$component in {. .. {}}} {
            _create_raise FAIL SOURCE_PATH_INVALID SOURCE \
                "$label contains a disallowed path component."
        }
    }
    return [join $components /]
}

proc ::stage1d::vivado_project::_create_resolve_source_path {
    repository_root
    relative_path
} {
    set absolute_path [file normalize \
        [file join $repository_root {*}[split $relative_path /]]]
    if {![_create_is_strict_descendant $absolute_path $repository_root]} {
        _create_raise FAIL SOURCE_PATH_ESCAPE SOURCE \
            "Source path escapes repository_root: $relative_path"
    }
    return $absolute_path
}

proc ::stage1d::vivado_project::_create_inventory_entry_path {
    entry
    label
} {
    if {![catch {dict size $entry}] && [dict exists $entry path]} {
        return [_create_normalize_relative_path [dict get $entry path] $label]
    }
    return [_create_normalize_relative_path $entry $label]
}

proc ::stage1d::vivado_project::_create_validate_authorization {
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
        [dict get $authorization operation] ne {vivado_project::create} ||
        [dict get $authorization phase] ne {PROJECT_RECONSTRUCTION} ||
        [dict get $authorization capability] ne
            {project_reconstruction_enabled} ||
        ![string is boolean -strict \
            [dict get $authorization capability_enabled]] ||
        ![dict get $authorization capability_enabled]} {
        _create_raise BLOCKED AUTHORIZATION_MISMATCH AUTHORIZATION \
            {Controller authorization does not permit project creation.}
    }
}

proc ::stage1d::vivado_project::_create_validate_identity {
    identity
    label
} {
    _create_require_dictionary $identity $label
    if {[dict size $identity] == 0} {
        _create_raise FAIL IDENTITY_MISSING IDENTITY \
            "$label must not be empty."
    }
    return $identity
}

proc ::stage1d::vivado_project::_create_validate_ip_repo_identity {
    identity
    execution_id
    workspace_root
} {
    _create_require_keys $identity {
        schema_version
        execution_id
        path
        packaged_ip_path
        vlnv
        package_sha256
        ip_repo_sha256
    } {ip_repo_identity}
    if {[dict get $identity schema_version] ne
        {stage1e-ip-repo-identity-v1}} {
        _create_raise FAIL IP_REPO_SCHEMA_UNSUPPORTED IDENTITY \
            {ip_repo_identity has an unsupported schema version.}
    }
    if {[dict get $identity execution_id] ne $execution_id} {
        _create_raise FAIL IP_REPO_EXECUTION_MISMATCH IDENTITY \
            {ip_repo_identity belongs to another execution.}
    }
    foreach digest_field {package_sha256 ip_repo_sha256} {
        set digest [string tolower [dict get $identity $digest_field]]
        if {![regexp {^[0-9a-f]{64}$} $digest]} {
            _create_raise FAIL IP_REPO_HASH_INVALID IDENTITY \
                "ip_repo_identity $digest_field is not a SHA-256 digest."
        }
        dict set identity $digest_field $digest
    }
    if {![regexp {^[^:]+:[^:]+:[^:]+:[^:]+$} \
        [dict get $identity vlnv]]} {
        _create_raise FAIL IP_REPO_VLNV_INVALID IDENTITY \
            {ip_repo_identity vlnv is invalid.}
    }
    foreach path_field {path packaged_ip_path} {
        set path [dict get $identity $path_field]
        if {[file pathtype $path] ne {absolute}} {
            _create_raise FAIL IP_REPO_PATH_INVALID WORKSPACE \
                "ip_repo_identity $path_field must be absolute."
        }
        set path [file normalize $path]
        if {![_create_is_strict_descendant $path $workspace_root]} {
            _create_raise FAIL IP_REPO_PATH_INVALID WORKSPACE \
                "ip_repo_identity $path_field must be execution-contained."
        }
        if {![file isdirectory $path]} {
            _create_raise BLOCKED IP_REPO_UNAVAILABLE DEPENDENCY \
                "ip_repo_identity $path_field is unavailable."
        }
        dict set identity $path_field $path
    }
    if {![_create_is_strict_descendant \
        [dict get $identity packaged_ip_path] [dict get $identity path]]} {
        _create_raise FAIL IP_PACKAGE_PATH_INVALID IDENTITY \
            {Packaged IP path is not contained by its IP repository.}
    }
    return $identity
}

proc ::stage1d::vivado_project::_create_validate_source_inventory {
    repository_root
    accepted_inventory
    project_inventory
} {
    set accepted_by_path [dict create]
    foreach entry $accepted_inventory {
        _create_require_keys $entry {path sha256} \
            {accepted source inventory entry}
        set relative_path [_create_normalize_relative_path \
            [dict get $entry path] {accepted source inventory path}]
        if {[dict exists $accepted_by_path $relative_path]} {
            _create_raise FAIL SOURCE_INVENTORY_DUPLICATE SOURCE \
                "Duplicate accepted source path: $relative_path"
        }
        set digest [string tolower [dict get $entry sha256]]
        if {![regexp {^[0-9a-f]{64}$} $digest]} {
            _create_raise FAIL SOURCE_HASH_INVALID SOURCE \
                "Accepted source hash is invalid: $relative_path"
        }
        dict set entry path $relative_path
        dict set entry sha256 $digest
        dict set accepted_by_path $relative_path $entry
    }

    set normalized_inventory {}
    set absolute_files {}
    set seen [dict create]
    foreach entry $project_inventory {
        set relative_path [_create_inventory_entry_path \
            $entry {project source inventory path}]
        if {[dict exists $seen $relative_path]} {
            _create_raise FAIL SOURCE_INVENTORY_DUPLICATE SOURCE \
                "Duplicate project source path: $relative_path"
        }
        if {![dict exists $accepted_by_path $relative_path]} {
            _create_raise FAIL SOURCE_NOT_ACCEPTED SOURCE \
                "Project source is absent from source_identity: $relative_path"
        }
        if {[string equal -nocase [file extension $relative_path] {.xdc}]} {
            _create_raise FAIL SOURCE_ROLE_MISMATCH SOURCE \
                "Constraint file must be declared by constraint_policy: $relative_path"
        }
        set absolute_path [_create_resolve_source_path \
            $repository_root $relative_path]
        if {![file isfile $absolute_path]} {
            _create_raise BLOCKED SOURCE_FILE_UNAVAILABLE DEPENDENCY \
                "Accepted project source is unavailable: $relative_path"
        }
        set accepted_entry [dict get $accepted_by_path $relative_path]
        if {[::stage1d::source_check::sha256_file $absolute_path] ne \
            [dict get $accepted_entry sha256]} {
            _create_raise FAIL SOURCE_HASH_MISMATCH SOURCE \
                "Project source changed after acceptance: $relative_path"
        }
        if {[dict exists $accepted_entry size] &&
            [file size $absolute_path] != [dict get $accepted_entry size]} {
            _create_raise FAIL SOURCE_SIZE_MISMATCH SOURCE \
                "Project source size changed after acceptance: $relative_path"
        }
        dict set seen $relative_path 1
        lappend normalized_inventory $accepted_entry
        lappend absolute_files $absolute_path
    }
    return [dict create \
        inventory $normalized_inventory \
        files $absolute_files]
}

proc ::stage1d::vivado_project::_create_validate_constraint_policy {
    repository_root
    accepted_inventory
    policy
} {
    _create_require_keys $policy {mode files} {constraint_policy}
    set mode [dict get $policy mode]
    set files [dict get $policy files]
    if {$mode ni {NO_USER_XDC FILES}} {
        _create_raise FAIL CONSTRAINT_POLICY_INVALID CONTRACT \
            {constraint_policy mode must be NO_USER_XDC or FILES.}
    }
    if {$mode eq {NO_USER_XDC} && [llength $files] != 0} {
        _create_raise FAIL CONSTRAINT_POLICY_INVALID CONTRACT \
            {NO_USER_XDC policy cannot contain constraint files.}
    }

    set accepted_by_path [dict create]
    foreach entry $accepted_inventory {
        _create_require_keys $entry {path sha256} \
            {accepted source inventory entry}
        set relative_path [_create_normalize_relative_path \
            [dict get $entry path] {accepted source inventory path}]
        set digest [string tolower [dict get $entry sha256]]
        if {![regexp {^[0-9a-f]{64}$} $digest]} {
            _create_raise FAIL SOURCE_HASH_INVALID SOURCE \
                "Accepted source hash is invalid: $relative_path"
        }
        dict set entry path $relative_path
        dict set entry sha256 $digest
        dict set accepted_by_path $relative_path $entry
    }
    set normalized_files {}
    set absolute_files {}
    set seen [dict create]
    foreach entry $files {
        set relative_path [_create_inventory_entry_path \
            $entry {constraint inventory path}]
        if {[dict exists $seen $relative_path]} {
            _create_raise FAIL CONSTRAINT_INVENTORY_DUPLICATE SOURCE \
                "Duplicate constraint path: $relative_path"
        }
        if {![string equal -nocase [file extension $relative_path] {.xdc}]} {
            _create_raise FAIL CONSTRAINT_EXTENSION_INVALID SOURCE \
                "Constraint is not an .xdc file: $relative_path"
        }
        if {![dict exists $accepted_by_path $relative_path]} {
            _create_raise FAIL CONSTRAINT_NOT_ACCEPTED SOURCE \
                "Constraint is absent from source_identity: $relative_path"
        }
        set absolute_path [_create_resolve_source_path \
            $repository_root $relative_path]
        if {![file isfile $absolute_path]} {
            _create_raise BLOCKED CONSTRAINT_FILE_UNAVAILABLE DEPENDENCY \
                "Accepted constraint is unavailable: $relative_path"
        }
        set accepted_entry [dict get $accepted_by_path $relative_path]
        if {[::stage1d::source_check::sha256_file $absolute_path] ne \
            [dict get $accepted_entry sha256]} {
            _create_raise FAIL CONSTRAINT_HASH_MISMATCH SOURCE \
                "Constraint changed after acceptance: $relative_path"
        }
        if {[dict exists $accepted_entry size] &&
            [file size $absolute_path] != [dict get $accepted_entry size]} {
            _create_raise FAIL CONSTRAINT_SIZE_MISMATCH SOURCE \
                "Constraint size changed after acceptance: $relative_path"
        }
        dict set seen $relative_path 1
        lappend normalized_files $accepted_entry
        lappend absolute_files $absolute_path
    }
    dict set policy files $normalized_files
    return [dict create \
        policy $policy \
        files $absolute_files]
}

proc ::stage1d::vivado_project::_validate_create_context {context} {
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
        project_path
        project_name
        part
        board_part
        target_language
        source_inventory
        constraint_policy
        ip_repo_identity
    } {Vivado project create context}

    if {[dict get $context context_schema_version] ne
        {stage1e-vivado-project-create-context-v1}} {
        _create_raise FAIL CONTEXT_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported Vivado project create context schema.}
    }
    if {[dict get $context operation] ne {vivado_project::create} ||
        [dict get $context phase] ne {PROJECT_RECONSTRUCTION}} {
        _create_raise FAIL OPERATION_MISMATCH CONTRACT \
            {Vivado project create operation or phase does not match.}
    }
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        _create_raise FAIL EXECUTION_ID_INVALID CONTRACT \
            {Vivado project create execution_id must not be empty.}
    }
    _create_validate_authorization \
        [dict get $context authorization] $execution_id
    if {[dict exists $context project_ownership]} {
        _create_raise FAIL AMBIGUOUS_PROJECT_OWNERSHIP OWNERSHIP \
            {Project creation cannot consume or replace existing ownership.}
    }

    set source_identity [_create_validate_identity \
        [dict get $context source_identity] source_identity]
    set environment_identity [_create_validate_identity \
        [dict get $context environment_identity] environment_identity]
    set configuration_identity [_create_validate_identity \
        [dict get $context configuration_identity] configuration_identity]
    foreach identity [list \
        $source_identity $environment_identity $configuration_identity] \
        label {source_identity environment_identity configuration_identity} {
        if {[dict exists $identity execution_id] &&
            [dict get $identity execution_id] ne $execution_id} {
            _create_raise FAIL CONSUMED_IDENTITY_EXECUTION_MISMATCH IDENTITY \
                "$label belongs to another execution."
        }
    }
    _create_require_keys $source_identity {
        repository_root
        source_inventory
    } {source_identity}
    foreach identity_field {part board_part} {
        if {![dict exists $environment_identity $identity_field]} {
            _create_raise FAIL ENVIRONMENT_IDENTITY_INCOMPLETE IDENTITY \
                "environment_identity is missing: $identity_field"
        }
    }

    foreach value_field {project_name part board_part target_language} {
        if {[string trim [dict get $context $value_field]] eq {}} {
            _create_raise FAIL CONTEXT_FIELD_INVALID CONTRACT \
                "Vivado project create $value_field must not be empty."
        }
    }
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} \
        [dict get $context project_name]]} {
        _create_raise FAIL PROJECT_NAME_INVALID CONTRACT \
            {Vivado project_name is not a valid project identifier.}
    }
    if {[dict get $context target_language] ni {Verilog VHDL}} {
        _create_raise FAIL TARGET_LANGUAGE_INVALID CONTRACT \
            {Vivado target_language must be Verilog or VHDL.}
    }
    if {[dict get $environment_identity part] ne [dict get $context part] ||
        [dict get $environment_identity board_part] ne
            [dict get $context board_part]} {
        _create_raise FAIL ENVIRONMENT_IDENTITY_MISMATCH IDENTITY \
            {Project part or board part does not match environment_identity.}
    }

    foreach path_field {workspace_root evidence_dir project_path} {
        set path [dict get $context $path_field]
        if {[file pathtype $path] ne {absolute}} {
            _create_raise FAIL PATH_NOT_ABSOLUTE WORKSPACE \
                "Vivado project create $path_field must be absolute."
        }
        dict set context $path_field [file normalize $path]
    }
    set repository_root [dict get $source_identity repository_root]
    if {[file pathtype $repository_root] ne {absolute}} {
        _create_raise FAIL REPOSITORY_PATH_INVALID SOURCE \
            {source_identity repository_root must be absolute.}
    }
    set repository_root [file normalize $repository_root]
    dict set source_identity repository_root $repository_root
    set workspace_root [dict get $context workspace_root]
    set evidence_dir [dict get $context evidence_dir]
    set project_path [dict get $context project_path]
    set project_directory [file dirname $project_path]

    if {![file isdirectory $repository_root]} {
        _create_raise BLOCKED REPOSITORY_UNAVAILABLE DEPENDENCY \
            {source_identity repository_root is unavailable.}
    }
    if {![file isdirectory $workspace_root]} {
        _create_raise BLOCKED WORKSPACE_UNAVAILABLE DEPENDENCY \
            {Vivado project workspace_root is unavailable.}
    }
    if {[_create_paths_overlap $repository_root $workspace_root]} {
        _create_raise FAIL REPOSITORY_WORKSPACE_OVERLAP WORKSPACE \
            {Vivado project workspace must be external to the repository.}
    }
    if {![_create_is_strict_descendant $evidence_dir $workspace_root] ||
        ![file isdirectory $evidence_dir]} {
        _create_raise FAIL EVIDENCE_DIRECTORY_INVALID WORKSPACE \
            {Vivado project evidence_dir must be an existing execution directory.}
    }
    if {![_create_is_strict_descendant $project_path $workspace_root] ||
        [_is_equal_or_descendant $project_path $repository_root]} {
        _create_raise FAIL PROJECT_PATH_REJECTED WORKSPACE \
            {Vivado project output must be execution-contained and external.}
    }
    if {![string equal -nocase [file extension $project_path] {.xpr}]} {
        _create_raise FAIL PROJECT_PATH_REJECTED WORKSPACE \
            {Vivado project_path must identify a .xpr file.}
    }
    if {[file rootname [file tail $project_path]] ne
        [dict get $context project_name]} {
        _create_raise FAIL PROJECT_IDENTITY_AMBIGUOUS IDENTITY \
            {project_name must match the project_path filename.}
    }
    if {[file exists $project_path]} {
        _create_raise FAIL PROJECT_ALREADY_EXISTS WORKSPACE \
            {Vivado project_path already exists; adoption is forbidden.}
    }
    if {[file exists $project_directory]} {
        _create_raise FAIL PROJECT_WORKSPACE_STALE WORKSPACE \
            {Vivado project directory must not exist before creation.}
    }

    set ip_repo_identity [_create_validate_ip_repo_identity \
        [dict get $context ip_repo_identity] $execution_id $workspace_root]
    set accepted_inventory [dict get $source_identity source_inventory]
    set source_validation [_create_validate_source_inventory \
        $repository_root $accepted_inventory \
        [dict get $context source_inventory]]
    set constraint_validation [_create_validate_constraint_policy \
        $repository_root $accepted_inventory \
        [dict get $context constraint_policy]]

    return [dict create \
        context $context \
        execution_id $execution_id \
        source_identity $source_identity \
        environment_identity $environment_identity \
        configuration_identity $configuration_identity \
        workspace_root $workspace_root \
        evidence_dir $evidence_dir \
        project_path $project_path \
        project_directory $project_directory \
        project_name [dict get $context project_name] \
        part [dict get $context part] \
        board_part [dict get $context board_part] \
        target_language [dict get $context target_language] \
        source_validation $source_validation \
        constraint_validation $constraint_validation \
        ip_repo_identity $ip_repo_identity]
}

proc ::stage1d::vivado_project::_create_require_single_object {
    objects
    label
} {
    if {[llength $objects] != 1} {
        _create_raise FAIL VIVADO_OBJECT_CARDINALITY VIVADO \
            "$label must resolve to exactly one object; found [llength $objects]."
    }
    return [lindex $objects 0]
}

proc ::stage1d::vivado_project::_create_assert_current_project_property {
    property
    expected
    label
} {
    set actual \
        [::stage1d::vivado_project::create_backend::get_current_project_property \
            $property]
    if {$actual ne $expected} {
        _create_raise FAIL PROJECT_PROPERTY_MISMATCH IDENTITY \
            "$label $property mismatch: actual=$actual expected=$expected"
    }
    return $actual
}

proc ::stage1d::vivado_project::_create_verify_current_project_identity {
    validated_context
} {
    set actual_name \
        [::stage1d::vivado_project::create_backend::get_current_project_property \
            NAME]
    set actual_directory [file normalize \
        [::stage1d::vivado_project::create_backend::get_current_project_property \
            DIRECTORY]]
    set actual_part \
        [::stage1d::vivado_project::create_backend::get_current_project_property \
            PART]
    set actual_board_part \
        [::stage1d::vivado_project::create_backend::get_current_project_property \
            BOARD_PART]

    if {$actual_name ne [dict get $validated_context expected_project_name]} {
        _create_raise FAIL PROJECT_PROPERTY_MISMATCH IDENTITY \
            "Vivado project name mismatch: actual=$actual_name expected=[dict get $validated_context expected_project_name]"
    }
    if {![_paths_equal $actual_directory \
            [dict get $validated_context expected_project_directory]]} {
        _create_raise FAIL PROJECT_PROPERTY_MISMATCH IDENTITY \
            "Vivado project directory mismatch: actual=$actual_directory expected=[dict get $validated_context expected_project_directory]"
    }
    if {$actual_part ne [dict get $validated_context expected_part]} {
        _create_raise FAIL PROJECT_PROPERTY_MISMATCH IDENTITY \
            "Vivado project part mismatch: actual=$actual_part expected=[dict get $validated_context expected_part]"
    }
    if {$actual_board_part ne \
            [dict get $validated_context expected_board_part]} {
        _create_raise FAIL PROJECT_PROPERTY_MISMATCH IDENTITY \
            "Vivado project board part mismatch: actual=$actual_board_part expected=[dict get $validated_context expected_board_part]"
    }

    return [dict create \
        project_name $actual_name \
        project_directory $actual_directory \
        part $actual_part \
        board_part $actual_board_part]
}

proc ::stage1d::vivado_project::_create_verify_ip_repository {
    ip_repo_identity
} {
    set expected_path [dict get $ip_repo_identity path]
    set readback_paths \
        [::stage1d::vivado_project::create_backend::get_current_project_property \
            IP_REPO_PATHS]
    if {[llength $readback_paths] != 1 ||
        ![_paths_equal [lindex $readback_paths 0] $expected_path]} {
        _create_raise FAIL IP_REPO_READBACK_MISMATCH IDENTITY \
            {Project IP_REPO_PATHS does not match the accepted repository.}
    }

    set expected_vlnv [dict get $ip_repo_identity vlnv]
    set ipdef [_create_require_single_object \
        [_create_invoke get_ipdefs -all $expected_vlnv] \
        {Packaged protection IP definition}]
    set actual_vlnv [_create_invoke get_property VLNV $ipdef]
    if {$actual_vlnv ne $expected_vlnv} {
        _create_raise FAIL IP_REPO_VLNV_MISMATCH IDENTITY \
            "IP catalog VLNV mismatch: actual=$actual_vlnv expected=$expected_vlnv"
    }
    return [dict create \
        path $expected_path \
        vlnv $actual_vlnv \
        package_sha256 [dict get $ip_repo_identity package_sha256] \
        ip_repo_sha256 [dict get $ip_repo_identity ip_repo_sha256]]
}

proc ::stage1d::vivado_project::_create_failure_cleanup {
    validated
    may_own_project
} {
    set cleanup_errors {}
    set project_closed 0
    set removed_paths {}
    set project_directory [dict get $validated project_directory]

    if {$may_own_project} {
        if {[catch {_create_query_current_project_allow_empty} current_handle \
            current_options]} {
            lappend cleanup_errors [dict create \
                operation current_project \
                message $current_handle \
                underlying_error \
                    [_get_or_default $current_options -errorinfo $current_handle]]
        } elseif {$current_handle ne {}} {
            if {[catch {_create_invoke close_project} close_error \
                close_options]} {
                lappend cleanup_errors [dict create \
                    operation close_project \
                    message $close_error \
                    underlying_error \
                        [_get_or_default $close_options -errorinfo $close_error]]
            } else {
                set project_closed 1
            }
        }
    }

    if {[file exists $project_directory]} {
        if {[catch {file delete -force $project_directory} remove_error \
            remove_options]} {
            lappend cleanup_errors [dict create \
                operation remove_project_directory \
                message $remove_error \
                underlying_error \
                    [_get_or_default $remove_options -errorinfo $remove_error]]
        } else {
            lappend removed_paths $project_directory
        }
    }
    return [dict create \
        owner vivado_project \
        required 1 \
        attempted 1 \
        completed [expr {[llength $cleanup_errors] == 0}] \
        project_closed $project_closed \
        removed_paths $removed_paths \
        errors $cleanup_errors]
}

proc ::stage1d::vivado_project::create {context} {
    set validation_status [catch {
        _validate_create_context $context
    } validated validation_options]
    if {$validation_status != 0} {
        set decoded [_create_decode_error $validated $validation_options \
            VIVADO_PROJECT_CREATE_CONTEXT_INVALID CONTRACT]
        return [_create_result \
            [dict get $decoded status] $context {} {} {} {} {} \
            [list [_create_error_record $decoded]] \
            [_create_default_cleanup_result] 0]
    }

    set consumed_identities [dict create \
        source_identity [dict get $validated source_identity] \
        environment_identity [dict get $validated environment_identity] \
        configuration_identity [dict get $validated configuration_identity] \
        workspace_identity [dict create \
            workspace_root [dict get $validated workspace_root] \
            evidence_dir [dict get $validated evidence_dir]] \
        ip_repo_identity [dict get $validated ip_repo_identity]]
    set vivado_invoked 1
    if {[catch {_create_query_current_project_allow_empty} existing_handle \
        query_options]} {
        set decoded [_create_decode_error $existing_handle $query_options \
            VIVADO_PROJECT_QUERY_FAILED VIVADO]
        return [_create_result \
            [dict get $decoded status] $context $consumed_identities \
            {} {} {} {} [list [_create_error_record $decoded]] \
            [_create_default_cleanup_result] $vivado_invoked]
    }
    if {$existing_handle ne {}} {
        set decoded [dict create \
            status BLOCKED \
            error_code VIVADO_PROJECT_SESSION_OCCUPIED \
            error_class OWNERSHIP \
            message {Vivado already has a current project; creation will not adopt it.} \
            underlying_error {}]
        return [_create_result BLOCKED $context $consumed_identities \
            {} {} {} {} [list [_create_error_record $decoded]] \
            [_create_default_cleanup_result] $vivado_invoked]
    }

    set may_own_project 1
    set execution_status [catch {
        _create_invoke create_project \
            [dict get $validated project_name] \
            [dict get $validated project_directory] \
            -part [dict get $validated part]
        set project_handle [_create_require_single_object \
            [_create_invoke current_project] {Created Vivado project}]

        ::stage1d::vivado_project::create_backend::set_current_project_property \
            board_part [dict get $validated board_part]
        ::stage1d::vivado_project::create_backend::set_current_project_property \
            target_language [dict get $validated target_language]
        ::stage1d::vivado_project::create_backend::set_current_project_property \
            IP_REPO_PATHS \
            [list [dict get $validated ip_repo_identity path]]
        _create_invoke update_ip_catalog

        set source_files [dict get $validated source_validation files]
        if {[llength $source_files] != 0} {
            _create_invoke add_files -norecurse -fileset sources_1 \
                $source_files
        }
        set constraint_files [dict get \
            $validated constraint_validation files]
        if {[llength $constraint_files] != 0} {
            _create_invoke add_files -norecurse -fileset constrs_1 \
                $constraint_files
        }

        set expected_identity [dict create \
            execution_id [dict get $validated execution_id] \
            project_path [dict get $validated project_path] \
            expected_project_name [dict get $validated project_name] \
            expected_project_directory \
                [dict get $validated project_directory] \
            expected_part [dict get $validated part] \
            expected_board_part [dict get $validated board_part]]
        set base_identity [_create_verify_current_project_identity \
            $expected_identity]
        set target_language [_create_assert_current_project_property \
            TARGET_LANGUAGE \
            [dict get $validated target_language] {Vivado project}]
        set repository_readback [_create_verify_ip_repository \
            [dict get $validated ip_repo_identity]]
        if {![file isfile [dict get $validated project_path]]} {
            _create_raise FAIL PROJECT_FILE_MISSING OUTPUT \
                {Vivado did not create the expected .xpr file.}
        }

        set project_identity [dict merge $base_identity [dict create \
            schema_version stage1e-project-identity-v1 \
            producer_operation vivado_project::create \
            execution_id [dict get $validated execution_id] \
            project_path [dict get $validated project_path] \
            target_language $target_language \
            ip_repo_identity [dict get $validated ip_repo_identity] \
            source_inventory [dict get \
                $validated source_validation inventory] \
            constraint_policy [dict get \
                $validated constraint_validation policy]]]
        set project_ownership [dict create \
            owner vivado_project \
            execution_id [dict get $validated execution_id] \
            project_handle $project_handle \
            project_path [dict get $validated project_path] \
            identity_verified 1 \
            project_identity $project_identity]
        set evidence [dict create \
            project_readback $project_identity \
            ip_repository_readback $repository_readback \
            project_sources $source_files \
            constraints $constraint_files]
    } execution_error execution_options]

    if {$execution_status != 0} {
        set cleanup_result [_create_failure_cleanup \
            $validated $may_own_project]
        set decoded [_create_decode_error $execution_error \
            $execution_options VIVADO_PROJECT_CREATE_FAILED VIVADO]
        if {![dict get $cleanup_result completed]} {
            dict set decoded status FAIL
        }
        return [_create_result \
            [dict get $decoded status] $context $consumed_identities \
            {} {} {} {} [list [_create_error_record $decoded]] \
            $cleanup_result $vivado_invoked]
    }

    return [_create_result PASS $context $consumed_identities \
        [dict create project_identity $project_identity] \
        $project_ownership $evidence {} {} \
        [_create_default_cleanup_result] $vivado_invoked]
}
