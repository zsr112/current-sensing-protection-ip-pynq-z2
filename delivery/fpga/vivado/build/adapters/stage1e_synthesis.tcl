# Stage 1E WP-C2 controlled synthesis adapter.
#
# This module is definition-only when sourced. It consumes an accepted build
# target and existing project/BD ownership, then owns only the bounded
# synthesis invocation and synthesis evidence collection. It does not own
# lifecycle creation, implementation, FPGA artifacts, publication, or
# controller continuation decisions.

namespace eval ::stage1e::synthesis {
    variable context_schema_version stage1e-synthesis-context-v1
    variable result_schema_version stage1e-synthesis-result-v1
    variable identity_schema_version stage1e-synthesis-result-identity-v1
    variable operation_name stage1e::synthesis::run
    variable phase_name SYNTHESIS
}

namespace eval ::stage1e::synthesis::backend {}

# Reuse the reviewed source-verification SHA-256 implementation. Loading this
# dependency defines Tcl procedures only and performs no Vivado operation.
if {[llength [info commands ::stage1d::source_check::sha256_file]] == 0} {
    set ::stage1e::synthesis::_source_check_path [file normalize \
        [file join [file dirname [info script]] .. lib source_check.tcl]]
    source $::stage1e::synthesis::_source_check_path
    unset ::stage1e::synthesis::_source_check_path
}

# Tests replace this single backend procedure with an in-memory model. The
# controller context cannot choose or modify the backend.
proc ::stage1e::synthesis::backend::invoke {command arguments} {
    return [uplevel #0 [list $command {*}$arguments]]
}

proc ::stage1e::synthesis::_invoke {command args} {
    return [::stage1e::synthesis::backend::invoke $command $args]
}

proc ::stage1e::synthesis::_get_or_default {
    dictionary
    key
    default_value
} {
    if {![catch {dict size $dictionary}] && [dict exists $dictionary $key]} {
        return [dict get $dictionary $key]
    }
    return $default_value
}

proc ::stage1e::synthesis::_raise {
    status
    error_code
    error_class
    message
} {
    return -code error -errorcode [list \
        STAGE1E SYNTHESIS $status $error_code $error_class] $message
}

proc ::stage1e::synthesis::_decode_error {
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
        [lrange $tcl_error_code 0 1] eq {STAGE1E SYNTHESIS}} {
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

proc ::stage1e::synthesis::_error_record {decoded} {
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

proc ::stage1e::synthesis::_cleanup_result {
    required
    completed
    disposition
} {
    return [dict create \
        owner stage1e::synthesis \
        required $required \
        attempted 0 \
        completed $completed \
        disposition $disposition \
        project_closed 0 \
        bd_closed 0 \
        run_reset 0 \
        evidence_preserved 1 \
        errors {}]
}

proc ::stage1e::synthesis::_context_execution_id {context} {
    if {![catch {dict size $context}] &&
        [dict exists $context execution_id]} {
        return [dict get $context execution_id]
    }
    return {}
}

proc ::stage1e::synthesis::_result {
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
    synthesis_performed
} {
    variable result_schema_version
    variable operation_name
    variable phase_name
    set continuation DENIED
    if {$status eq {PASS}} {
        set continuation ELIGIBLE
    }
    set result [dict create \
        schema_version $result_schema_version \
        operation $operation_name \
        phase $phase_name \
        execution_id [_context_execution_id $context] \
        status $status \
        consumed_identities $consumed_identities \
        produced_identities $produced_identities \
        ownership_records $ownership_records \
        evidence_references $evidence_references \
        evidence $evidence_references \
        warnings $warnings \
        errors $errors \
        cleanup_result $cleanup_result \
        continuation_recommendation $continuation \
        vivado_invoked $vivado_invoked \
        synthesis_performed $synthesis_performed \
        implementation_performed 0 \
        bitstream_generated 0 \
        xsa_exported 0 \
        artifacts_collected 0 \
        artifacts_generated 0 \
        artifact_generation_performed 0 \
        artifact_publication_performed 0 \
        board_access_performed 0]
    if {[dict exists $produced_identities synthesis_result_identity]} {
        dict set result synthesis_result_identity \
            [dict get $produced_identities synthesis_result_identity]
    }
    return $result
}

proc ::stage1e::synthesis::_require_dictionary {value label} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise FAIL CONTEXT_FIELD_INVALID CONTRACT \
            "$label must be a dictionary: $dictionary_error"
    }
}

proc ::stage1e::synthesis::_require_keys {
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

proc ::stage1e::synthesis::_canonical_components {path} {
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

proc ::stage1e::synthesis::_paths_equal {first_path second_path} {
    return [expr {
        [_canonical_components $first_path] eq
            [_canonical_components $second_path]
    }]
}

proc ::stage1e::synthesis::_is_equal_or_descendant {
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

proc ::stage1e::synthesis::_paths_overlap {first_path second_path} {
    return [expr {
        [_is_equal_or_descendant $first_path $second_path] ||
        [_is_equal_or_descendant $second_path $first_path]
    }]
}

proc ::stage1e::synthesis::_validate_hash {value label} {
    set digest [string tolower [string trim $value]]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {
        _raise FAIL IDENTITY_HASH_INVALID IDENTITY \
            "$label must be a 64-character SHA-256 digest."
    }
    return $digest
}

proc ::stage1e::synthesis::_validate_boolean {value label} {
    if {![string is boolean -strict $value]} {
        _raise FAIL BOOLEAN_INVALID CONTRACT "$label must be boolean."
    }
    return [expr {$value ? 1 : 0}]
}

proc ::stage1e::synthesis::_validate_identity {
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

proc ::stage1e::synthesis::_identity_hash {identity label} {
    foreach key {
        identity_sha256 sha256 environment_evidence_hash
        source_inventory_sha256 configuration_sha256
    } {
        if {[dict exists $identity $key] &&
            [string trim [dict get $identity $key]] ne {}} {
            return [_validate_hash [dict get $identity $key] "$label $key"]
        }
    }
    return [::stage1d::source_check::sha256_text $identity]
}

proc ::stage1e::synthesis::_validate_authorization {
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
    set capability [string toupper [dict get $authorization capability]]
    if {[dict get $authorization status] ne {AUTHORIZED} ||
        [dict get $authorization authority] ne {controller_core} ||
        [dict get $authorization execution_id] ne $execution_id ||
        [dict get $authorization operation] ne $operation_name ||
        [dict get $authorization phase] ne $phase_name ||
        $capability ni {SYNTHESIS SYNTHESIS_ENABLED} ||
        ![_validate_boolean [dict get $authorization capability_enabled] \
            authorization.capability_enabled]} {
        _raise BLOCKED AUTHORIZATION_MISMATCH AUTHORIZATION \
            {Controller authorization does not grant the SYNTHESIS capability.}
    }
}

proc ::stage1e::synthesis::_normalize_absolute_path {
    path
    label
} {
    if {[file pathtype $path] ne {absolute}} {
        _raise FAIL PATH_NOT_ABSOLUTE WORKSPACE \
            "$label must be an absolute path."
    }
    return [file normalize $path]
}

proc ::stage1e::synthesis::_read_ownership_evidence {path} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise FAIL WORKSPACE_OWNERSHIP_EVIDENCE_UNAVAILABLE OWNERSHIP \
            {Workspace ownership evidence is missing or is not a file.}
    }
    if {[catch {file type $path} path_type] || $path_type ne {file}} {
        _raise FAIL WORKSPACE_OWNERSHIP_EVIDENCE_UNAVAILABLE OWNERSHIP \
            {Workspace ownership evidence must be a regular file.}
    }
    if {[catch {open $path r} channel]} {
        _raise FAIL WORKSPACE_OWNERSHIP_EVIDENCE_UNAVAILABLE OWNERSHIP \
            {Workspace ownership evidence cannot be opened.}
    }
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} ownership]
    set close_status [catch {close $channel}]
    if {$read_status != 0 || $close_status != 0} {
        _raise FAIL WORKSPACE_OWNERSHIP_EVIDENCE_UNAVAILABLE OWNERSHIP \
            {Workspace ownership evidence cannot be read completely.}
    }
    _require_dictionary $ownership {workspace ownership evidence}
    return $ownership
}

proc ::stage1e::synthesis::_validate_workspace {
    workspace_identity
    source_identity
    execution_id
} {
    _require_dictionary $workspace_identity workspace_identity
    if {[dict size $workspace_identity] == 0} {
        _raise FAIL WORKSPACE_IDENTITY_MISSING IDENTITY \
            {workspace_identity must not be empty.}
    }
    _require_keys $workspace_identity {
        schema_version
        execution_id
        retry_number
        git_commit
        git_tree
        workspace_identifier
        workspace_path
        workspace_root
        evidence_dir
        synthesis_output_dir
        ownership_evidence
        identity_sha256
    } workspace_identity
    if {[dict get $workspace_identity schema_version] ne \
        {stage1e-workspace-identity-v2}} {
        _raise FAIL WORKSPACE_IDENTITY_SCHEMA_UNSUPPORTED IDENTITY \
            {Unsupported workspace identity schema.}
    }
    if {[dict get $workspace_identity execution_id] ne $execution_id} {
        _raise FAIL WORKSPACE_IDENTITY_EXECUTION_MISMATCH IDENTITY \
            {workspace_identity belongs to another execution.}
    }
    set retry_number [dict get $workspace_identity retry_number]
    if {![regexp {^[1-9][0-9]*$} $retry_number] ||
        [dict get $workspace_identity workspace_identifier] ne \
            "r$retry_number"} {
        _raise FAIL WORKSPACE_RETRY_IDENTITY_INVALID IDENTITY \
            {Workspace retry number and identifier are not consistently bound.}
    }
    foreach field {git_commit git_tree} {
        if {![regexp {^[0-9a-f]{40}$} \
                [dict get $workspace_identity $field]]} {
            _raise FAIL WORKSPACE_PROVENANCE_INVALID IDENTITY \
                "workspace_identity $field must be a lowercase Git object ID."
        }
    }
    if {[dict exists $source_identity git_commit] &&
        [dict get $workspace_identity git_commit] ne \
            [string tolower [dict get $source_identity git_commit]]} {
        _raise FAIL WORKSPACE_SOURCE_IDENTITY_MISMATCH IDENTITY \
            {Workspace Git commit does not match source identity.}
    }

    set supplied_hash [_validate_hash \
        [dict get $workspace_identity identity_sha256] \
        {workspace_identity identity_sha256}]
    set identity_payload $workspace_identity
    dict unset identity_payload identity_sha256
    set calculated_hash [::stage1d::source_check::sha256_text \
        $identity_payload]
    if {$supplied_hash ne $calculated_hash} {
        _raise FAIL WORKSPACE_IDENTITY_HASH_MISMATCH IDENTITY \
            {workspace_identity SHA-256 does not match its payload.}
    }
    dict set workspace_identity identity_sha256 $supplied_hash
    foreach field {
        workspace_path workspace_root evidence_dir synthesis_output_dir
    } {
        dict set workspace_identity $field [_normalize_absolute_path \
            [dict get $workspace_identity $field] "workspace_identity $field"]
    }
    set root [dict get $workspace_identity workspace_root]
    if {![_paths_equal [dict get $workspace_identity workspace_path] $root]} {
        _raise FAIL WORKSPACE_PATH_IDENTITY_MISMATCH IDENTITY \
            {workspace_path and workspace_root must identify the same workspace.}
    }
    set evidence [dict get $workspace_identity evidence_dir]
    set output [dict get $workspace_identity synthesis_output_dir]
    if {![file isdirectory $root] || ![file isdirectory $evidence]} {
        _raise BLOCKED WORKSPACE_UNAVAILABLE WORKSPACE \
            {Synthesis workspace_root and evidence_dir must exist.}
    }
    foreach path [list $evidence $output] label \
        {evidence_dir synthesis_output_dir} {
        if {![_is_equal_or_descendant $path $root] ||
            [_paths_equal $path $root]} {
            _raise FAIL WORKSPACE_CONTAINMENT_VIOLATION WORKSPACE \
                "$label must be a strict descendant of workspace_root."
        }
    }
    if {[_paths_overlap $evidence $output]} {
        _raise FAIL WORKSPACE_EVIDENCE_OUTPUT_OVERLAP WORKSPACE \
            {Synthesis evidence_dir and synthesis_output_dir must be disjoint.}
    }

    set ownership_reference \
        [string trim [dict get $workspace_identity ownership_evidence]]
    if {$ownership_reference eq {} ||
        [file pathtype $ownership_reference] ne {relative}} {
        _raise FAIL WORKSPACE_OWNERSHIP_REFERENCE_INVALID OWNERSHIP \
            {ownership_evidence must be a non-empty relative path.}
    }
    set ownership_path [file normalize \
        [file join $root $ownership_reference]]
    if {![_is_equal_or_descendant $ownership_path $evidence] ||
        [_paths_equal $ownership_path $evidence]} {
        _raise FAIL WORKSPACE_OWNERSHIP_REFERENCE_INVALID OWNERSHIP \
            {Workspace ownership evidence must be contained by evidence_dir.}
    }
    set ownership [_read_ownership_evidence $ownership_path]
    _require_keys $ownership {
        ownership_schema_version
        execution_identifier
        execution_id
        retry_number
        git_commit
        git_tree
        workspace_role
        workspace_path
        workspace_identifier
        workspace_identity_schema_version
        workspace_identity_hash
    } {workspace ownership evidence}
    set ownership_workspace_path [_normalize_absolute_path \
        [dict get $ownership workspace_path] \
        {workspace ownership evidence workspace_path}]
    set ownership_identity_hash [_validate_hash \
        [dict get $ownership workspace_identity_hash] \
        {workspace ownership evidence workspace_identity_hash}]
    if {[dict get $ownership ownership_schema_version] ne {v1} ||
        [dict get $ownership execution_identifier] ne $execution_id ||
        [dict get $ownership execution_id] ne $execution_id ||
        [dict get $ownership retry_number] ne $retry_number ||
        [dict get $ownership git_commit] ne \
            [dict get $workspace_identity git_commit] ||
        [dict get $ownership git_tree] ne \
            [dict get $workspace_identity git_tree] ||
        [dict get $ownership workspace_role] ne \
            {ACTIVE_BUILD_WORKSPACE} ||
        ![_paths_equal $ownership_workspace_path $root] ||
        [dict get $ownership workspace_identifier] ne \
            [dict get $workspace_identity workspace_identifier] ||
        [dict get $ownership workspace_identity_schema_version] ne \
            [dict get $workspace_identity schema_version] ||
        $ownership_identity_hash ne $supplied_hash} {
        _raise FAIL WORKSPACE_OWNERSHIP_MISMATCH OWNERSHIP \
            {Workspace identity does not match its ownership evidence.}
    }
    if {[dict exists $source_identity repository_root] &&
        [string trim [dict get $source_identity repository_root]] ne {}} {
        set repository_root [_normalize_absolute_path \
            [dict get $source_identity repository_root] \
            {source_identity repository_root}]
        if {[_paths_overlap $root $repository_root]} {
            _raise FAIL WORKSPACE_REPOSITORY_OVERLAP WORKSPACE \
                {Synthesis workspace must be external to the source repository.}
        }
    }
    return $workspace_identity
}

proc ::stage1e::synthesis::_validate_ownership {
    context
    execution_id
    workspace_root
    environment_identity
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
        ![_validate_boolean [dict get $project identity_verified] \
            project_ownership.identity_verified]} {
        _raise FAIL PROJECT_OWNER_INVALID OWNERSHIP \
            {Synthesis requires same-execution verified project ownership.}
    }
    set project_path [_normalize_absolute_path \
        [dict get $project project_path] {project_ownership project_path}]
    if {![_is_equal_or_descendant $project_path $workspace_root] ||
        ![string equal -nocase [file extension $project_path] {.xpr}]} {
        _raise FAIL PROJECT_PATH_INVALID WORKSPACE \
            {Owned project must be an execution-contained .xpr path.}
    }
    set project_identity [dict get $project project_identity]
    _require_keys $project_identity {
        project_name
        project_directory
        project_path
        part
        board_part
    } {project_ownership project_identity}
    if {![_paths_equal [dict get $project_identity project_path] $project_path] ||
        ![_paths_equal [dict get $project_identity project_directory] \
            [file dirname $project_path]]} {
        _raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
            {Project ownership identity does not match its path.}
    }
    foreach field {part board_part} {
        if {![dict exists $environment_identity $field] ||
            [dict get $project_identity $field] ne \
                [dict get $environment_identity $field]} {
            _raise FAIL PROJECT_ENVIRONMENT_MISMATCH IDENTITY \
                "Project ownership does not match environment $field."
        }
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
            {Synthesis requires same-execution BD ownership.}
    }
    foreach field {opened identity_verified validated saved} {
        if {![_validate_boolean [dict get $bd $field] \
                "bd_ownership.$field"] || ![dict get $bd $field]} {
            _raise FAIL BD_OWNER_STATE_INVALID OWNERSHIP \
                {Synthesis requires an opened, verified, validated, saved BD.}
        }
    }
    set bd_path [_normalize_absolute_path \
        [dict get $bd bd_path] {bd_ownership bd_path}]
    if {![_is_equal_or_descendant $bd_path $workspace_root] ||
        ![string equal -nocase [file extension $bd_path] {.bd}]} {
        _raise FAIL BD_PATH_INVALID WORKSPACE \
            {Owned BD must be an execution-contained .bd path.}
    }
    dict set bd project_path $project_path
    dict set bd bd_path $bd_path
    return [dict create project_ownership $project bd_ownership $bd]
}

proc ::stage1e::synthesis::_validate_build_target {
    identity
    execution_id
    source_identity
    configuration_identity
    environment_identity
    project
    bd
    workspace_root
} {
    set identity [_validate_identity $identity build_target_identity \
        $execution_id]
    _require_keys $identity {
        schema_version
        producer_operation
        execution_id
        project_path
        bd_name
        bd_path
        wrapper_path
        top_module
        fileset
        source_identity_sha256
        configuration_identity_sha256
        environment_identity_sha256
        identity_sha256
    } build_target_identity
    if {[dict get $identity schema_version] ne \
            {stage1e-build-target-identity-v1} ||
        [dict get $identity producer_operation] ne \
            {stage1e::build_target::prepare}} {
        _raise BLOCKED BUILD_TARGET_SCHEMA_UNSUPPORTED DEPENDENCY \
            {build_target_identity is not a Stage 1E build-target result.}
    }
    set accepted 0
    if {[dict exists $identity acceptance_state] &&
        [dict get $identity acceptance_state] in {ACCEPTED PASS}} {
        set accepted 1
    } elseif {[dict exists $identity status] &&
        [dict get $identity status] in {ACCEPTED PASS}} {
        set accepted 1
    } elseif {[dict exists $identity accepted] &&
        [_validate_boolean [dict get $identity accepted] \
            {build_target_identity accepted}]} {
        set accepted 1
    }
    if {!$accepted} {
        _raise BLOCKED BUILD_TARGET_NOT_ACCEPTED DEPENDENCY \
            {Synthesis requires an accepted build_target_identity.}
    }
    if {![_paths_equal [dict get $identity project_path] \
            [dict get $project project_path]] ||
        [dict get $identity bd_name] ne [dict get $bd bd_name] ||
        ![_paths_equal [dict get $identity bd_path] [dict get $bd bd_path]]} {
        _raise FAIL BUILD_TARGET_OWNERSHIP_MISMATCH OWNERSHIP \
            {build_target_identity does not match project/BD ownership.}
    }
    set wrapper_path [_normalize_absolute_path \
        [dict get $identity wrapper_path] {build_target_identity wrapper_path}]
    if {![_is_equal_or_descendant $wrapper_path $workspace_root]} {
        _raise FAIL BUILD_TARGET_WRAPPER_OUTSIDE_WORKSPACE WORKSPACE \
            {Build-target wrapper is outside the execution workspace.}
    }
    foreach {context_name target_hash_name} {
        source_identity source_identity_sha256
        configuration_identity configuration_identity_sha256
        environment_identity environment_identity_sha256
    } {
        set observed [_identity_hash [set $context_name] $context_name]
        set expected [_validate_hash [dict get $identity $target_hash_name] \
            "build_target_identity $target_hash_name"]
        if {$observed ne $expected} {
            _raise FAIL BUILD_TARGET_IDENTITY_MISMATCH IDENTITY \
                "Build target does not bind the current $context_name."
        }
    }
    dict set identity wrapper_path $wrapper_path
    dict set identity identity_sha256 [_validate_hash \
        [dict get $identity identity_sha256] \
        {build_target_identity identity_sha256}]
    return $identity
}

proc ::stage1e::synthesis::_validate_seed_policy {policy} {
    _require_keys $policy {mode} {synthesis_policy seed_policy}
    set mode [string toupper [dict get $policy mode]]
    if {$mode eq {NOT_APPLICABLE}} {
        dict set policy mode $mode
        return $policy
    }
    if {$mode ne {FIXED}} {
        _raise FAIL SYNTHESIS_SEED_POLICY_INVALID CONFIGURATION \
            {Synthesis seed mode must be NOT_APPLICABLE or FIXED.}
    }
    _require_keys $policy {property value} {synthesis_policy seed_policy}
    if {[string trim [dict get $policy property]] eq {} ||
        ![string is integer -strict [dict get $policy value]]} {
        _raise FAIL SYNTHESIS_SEED_POLICY_INVALID CONFIGURATION \
            {Fixed synthesis seed requires an explicit property and integer value.}
    }
    dict set policy mode $mode
    return $policy
}

proc ::stage1e::synthesis::_validate_warning_policy {policy} {
    _require_keys $policy {
        schema_version
        unknown_disposition
        dispositions
    } {synthesis_policy warning_policy}
    if {[dict get $policy schema_version] ne \
            {stage1e-synthesis-warning-policy-v1} ||
        [dict get $policy unknown_disposition] ne {REJECTED}} {
        _raise FAIL SYNTHESIS_WARNING_POLICY_INVALID CONFIGURATION \
            {Warning policy must reject unknown synthesis warnings.}
    }
    set dispositions [dict get $policy dispositions]
    _require_dictionary $dispositions \
        {synthesis_policy warning_policy dispositions}
    dict for {identifier disposition} $dispositions {
        if {[string trim $identifier] eq {}} {
            _raise FAIL SYNTHESIS_WARNING_POLICY_INVALID CONFIGURATION \
                {Warning disposition identifier must not be empty.}
        }
        _require_keys $disposition {
            classification severity min_count max_count rationale
        } "warning disposition $identifier"
        set classification [string toupper \
            [dict get $disposition classification]]
        if {$classification ni {ACCEPTED REJECTED REVIEW_REQUIRED}} {
            _raise FAIL SYNTHESIS_WARNING_POLICY_INVALID CONFIGURATION \
                "Warning disposition classification is invalid: $identifier"
        }
        foreach field {min_count max_count} {
            if {![string is integer -strict [dict get $disposition $field]] ||
                [dict get $disposition $field] < 0} {
                _raise FAIL SYNTHESIS_WARNING_POLICY_INVALID CONFIGURATION \
                    "Warning disposition $field is invalid: $identifier"
            }
        }
        if {[dict get $disposition min_count] >
            [dict get $disposition max_count]} {
            _raise FAIL SYNTHESIS_WARNING_POLICY_INVALID CONFIGURATION \
                "Warning disposition count range is invalid: $identifier"
        }
        if {[string trim [dict get $disposition severity]] eq {} ||
            [string trim [dict get $disposition rationale]] eq {}} {
            _raise FAIL SYNTHESIS_WARNING_POLICY_INVALID CONFIGURATION \
                "Warning disposition is incomplete: $identifier"
        }
        dict set disposition classification $classification
        dict set dispositions $identifier $disposition
    }
    dict set policy dispositions $dispositions
    return $policy
}

proc ::stage1e::synthesis::_validate_synthesis_policy {
    policy
    workspace_identity
    build_target_identity
} {
    _require_keys $policy {
        schema_version
        run_name
        strategy
        directives
        seed_policy
        job_policy
        incremental_synthesis_policy
        output_directory
        fileset
        top_module
        allowed_initial_statuses
        accepted_terminal_statuses
        report_paths
        run_log_path
        warning_policy
    } synthesis_policy
    if {[dict get $policy schema_version] ne \
        {stage1e-synthesis-policy-v1}} {
        _raise FAIL SYNTHESIS_POLICY_SCHEMA_UNSUPPORTED CONFIGURATION \
            {Unsupported synthesis policy schema.}
    }
    foreach field {run_name strategy fileset top_module} {
        if {[string trim [dict get $policy $field]] eq {}} {
            _raise FAIL SYNTHESIS_POLICY_INCOMPLETE CONFIGURATION \
                "Synthesis policy field must not be empty: $field"
        }
    }
    if {[dict get $policy fileset] ne \
            [dict get $build_target_identity fileset] ||
        [dict get $policy top_module] ne \
            [dict get $build_target_identity top_module]} {
        _raise FAIL SYNTHESIS_POLICY_TARGET_MISMATCH CONFIGURATION \
            {Synthesis policy does not match the accepted fileset/top.}
    }
    _require_dictionary [dict get $policy directives] \
        {synthesis_policy directives}
    if {[dict size [dict get $policy directives]] == 0} {
        _raise FAIL SYNTHESIS_POLICY_INCOMPLETE CONFIGURATION \
            {Synthesis directives must be explicit and non-empty.}
    }
    set seed_policy [_validate_seed_policy [dict get $policy seed_policy]]

    set job_policy [dict get $policy job_policy]
    _require_keys $job_policy {
        mode jobs dispatch_timeout_seconds
        dispatch_poll_interval_milliseconds wait_timeout_minutes
        pre_synthesis_budget_minutes shutdown_grace_minutes
        launcher_timeout_minutes
    } {synthesis_policy job_policy}
    if {[dict get $job_policy mode] ne {LOCAL} ||
        ![string is integer -strict [dict get $job_policy jobs]] ||
        [dict get $job_policy jobs] < 1} {
        _raise FAIL SYNTHESIS_JOB_POLICY_INVALID CONFIGURATION \
            {Synthesis job policy must specify LOCAL and a positive job count.}
    }
    foreach field {
        dispatch_timeout_seconds dispatch_poll_interval_milliseconds
        wait_timeout_minutes pre_synthesis_budget_minutes
        shutdown_grace_minutes launcher_timeout_minutes
    } {
        if {![string is integer -strict [dict get $job_policy $field]] ||
            [dict get $job_policy $field] < 1} {
            _raise FAIL SYNTHESIS_JOB_POLICY_INVALID CONFIGURATION \
                "Synthesis job policy field must be positive: $field"
        }
    }
    set dispatch_timeout_seconds \
        [dict get $job_policy dispatch_timeout_seconds]
    set dispatch_poll_milliseconds \
        [dict get $job_policy dispatch_poll_interval_milliseconds]
    if {$dispatch_poll_milliseconds > $dispatch_timeout_seconds * 1000} {
        _raise FAIL SYNTHESIS_JOB_POLICY_INVALID CONFIGURATION \
            {Synthesis dispatch poll interval exceeds its timeout.}
    }
    set dispatch_budget_minutes \
        [expr {($dispatch_timeout_seconds + 59) / 60}]
    set required_launcher_minutes [expr {
        [dict get $job_policy pre_synthesis_budget_minutes] +
        $dispatch_budget_minutes +
        [dict get $job_policy wait_timeout_minutes] +
        [dict get $job_policy shutdown_grace_minutes]
    }]
    if {[dict get $job_policy launcher_timeout_minutes] <
        $required_launcher_minutes} {
        _raise FAIL SYNTHESIS_LAUNCHER_LIFETIME_INVALID CONFIGURATION \
            {External Vivado launcher lifetime does not cover controlled synthesis.}
    }
    dict set job_policy dispatch_budget_minutes $dispatch_budget_minutes
    dict set job_policy required_launcher_timeout_minutes \
        $required_launcher_minutes
    dict set job_policy do_not_terminate_while_wait_active 1
    dict set policy job_policy $job_policy

    set incremental [dict get $policy incremental_synthesis_policy]
    _require_keys $incremental {enabled checkpoint} \
        {synthesis_policy incremental_synthesis_policy}
    if {[_validate_boolean [dict get $incremental enabled] \
            {incremental_synthesis_policy enabled}] ||
        [string trim [dict get $incremental checkpoint]] ne {}} {
        _raise FAIL INCREMENTAL_SYNTHESIS_PROHIBITED CONFIGURATION \
            {Initial Stage 1E synthesis must not use incremental synthesis or a checkpoint.}
    }

    foreach status_field {allowed_initial_statuses accepted_terminal_statuses} {
        if {[llength [dict get $policy $status_field]] == 0} {
            _raise FAIL SYNTHESIS_POLICY_INCOMPLETE CONFIGURATION \
                "Synthesis policy status list must not be empty: $status_field"
        }
    }

    set workspace_root [dict get $workspace_identity workspace_root]
    set evidence_dir [dict get $workspace_identity evidence_dir]
    set expected_output [dict get $workspace_identity synthesis_output_dir]
    set output [_normalize_absolute_path [dict get $policy output_directory] \
        {synthesis_policy output_directory}]
    if {![_paths_equal $output $expected_output] ||
        ![_is_equal_or_descendant $output $workspace_root]} {
        _raise FAIL SYNTHESIS_OUTPUT_POLICY_INVALID WORKSPACE \
            {Synthesis output directory does not match workspace identity.}
    }
    dict set policy output_directory $output

    set synthesis_evidence_dir [file normalize \
        [file join $evidence_dir synthesis]]
    if {![_is_equal_or_descendant $synthesis_evidence_dir $evidence_dir] ||
        [_paths_equal $synthesis_evidence_dir $evidence_dir] ||
        ![file isdirectory $synthesis_evidence_dir]} {
        _raise FAIL SYNTHESIS_EVIDENCE_DIRECTORY_INVALID WORKSPACE \
            {Synthesis evidence directory must exist at evidence_dir/synthesis.}
    }
    dict set policy synthesis_evidence_directory $synthesis_evidence_dir

    set report_paths [dict get $policy report_paths]
    _require_keys $report_paths {
        synthesis_report utilization_report message_report
    } {synthesis_policy report_paths}
    set normalized_reports [dict create]
    set observed_paths {}
    dict for {role path} $report_paths {
        if {$role ni {synthesis_report utilization_report message_report}} {
            _raise FAIL SYNTHESIS_REPORT_ROLE_INVALID CONFIGURATION \
                "Unexpected synthesis report role: $role"
        }
        set path [_normalize_absolute_path $path \
            "synthesis_policy report_paths $role"]
        if {![_paths_equal [file dirname $path] $synthesis_evidence_dir] ||
            ![file isdirectory [file dirname $path]]} {
            _raise FAIL SYNTHESIS_REPORT_PATH_INVALID WORKSPACE \
                [join [list \
                    {Synthesis report path is unavailable or outside} \
                    "evidence_dir/synthesis: $role"] { }]
        }
        if {[file exists $path]} {
            _raise FAIL SYNTHESIS_REPORT_STALE WORKSPACE \
                "Synthesis report path already exists: $role"
        }
        if {$path in $observed_paths} {
            _raise FAIL SYNTHESIS_REPORT_PATH_DUPLICATE CONFIGURATION \
                {Synthesis report roles must use distinct paths.}
        }
        lappend observed_paths $path
        dict set normalized_reports $role $path
    }
    dict set policy report_paths $normalized_reports

    set run_log [_normalize_absolute_path [dict get $policy run_log_path] \
        {synthesis_policy run_log_path}]
    if {![_paths_equal [file dirname $run_log] $synthesis_evidence_dir] ||
        ![file isdirectory [file dirname $run_log]] ||
        [file exists $run_log] || $run_log in $observed_paths} {
        _raise FAIL SYNTHESIS_LOG_PATH_INVALID WORKSPACE \
            [join [list \
                {Synthesis run log evidence path is stale, duplicate, or outside} \
                {evidence_dir/synthesis.}] { }]
    }
    set run_log_source [file normalize \
        [file join $output [file tail $run_log]]]
    if {![_paths_equal [file dirname $run_log_source] $output] ||
        [file exists $run_log_source]} {
        _raise FAIL SYNTHESIS_LOG_SOURCE_PATH_INVALID WORKSPACE \
            {Native synthesis run log path is stale or outside the run directory.}
    }
    set message_database [file normalize [file join $output vivado.pb]]
    if {![_paths_equal [file dirname $message_database] $output] ||
        [_paths_equal $message_database $run_log_source] ||
        [file exists $message_database]} {
        _raise FAIL SYNTHESIS_MESSAGE_DATABASE_PATH_INVALID WORKSPACE \
            {Synthesis message database path is stale or outside the run directory.}
    }
    dict set policy run_log_path $run_log
    dict set policy run_log_source_path $run_log_source
    dict set policy message_database_path $message_database
    dict set policy seed_policy $seed_policy
    dict set policy warning_policy [_validate_warning_policy \
        [dict get $policy warning_policy]]
    dict set policy identity_sha256 \
        [::stage1d::source_check::sha256_text $policy]
    return $policy
}

proc ::stage1e::synthesis::_validate_launcher_lifetime_binding {
    binding
    job_policy
} {
    _require_keys $binding {
        contract_version mode jobs dispatch_timeout_seconds
        dispatch_poll_interval_milliseconds dispatch_budget_minutes
        wait_timeout_minutes pre_synthesis_budget_minutes
        shutdown_grace_minutes required_launcher_timeout_minutes
        launcher_timeout_minutes do_not_terminate_while_wait_active
    } {launcher_lifetime_policy}
    if {[dict get $binding contract_version] ne \
            {stage1e-vivado-launcher-lifetime-v1} ||
        [dict get $binding do_not_terminate_while_wait_active] ne {1}} {
        _raise FAIL SYNTHESIS_LAUNCHER_LIFETIME_INVALID CONTRACT \
            {Vivado launcher lifetime contract is unsupported or unsafe.}
    }
    foreach field {
        mode jobs dispatch_timeout_seconds
        dispatch_poll_interval_milliseconds dispatch_budget_minutes
        wait_timeout_minutes pre_synthesis_budget_minutes
        shutdown_grace_minutes required_launcher_timeout_minutes
        launcher_timeout_minutes do_not_terminate_while_wait_active
    } {
        if {![dict exists $job_policy $field] ||
            [dict get $binding $field] ne [dict get $job_policy $field]} {
            _raise FAIL SYNTHESIS_LAUNCHER_LIFETIME_MISMATCH IDENTITY \
                "Vivado launcher lifetime binding mismatch: $field"
        }
    }
    return $binding
}

proc ::stage1e::synthesis::_validate_context {context} {
    variable context_schema_version
    variable operation_name
    variable phase_name
    _require_keys $context {
        context_schema_version
        operation
        phase
        execution_id
        authorization
        workspace_identity
        build_target_identity
        source_identity
        configuration_identity
        environment_identity
        project_ownership
        bd_ownership
        synthesis_policy
        launcher_lifetime_policy
    } {synthesis context}
    if {[dict get $context context_schema_version] ne $context_schema_version} {
        _raise FAIL CONTEXT_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported Stage 1E synthesis context schema.}
    }
    if {[dict get $context operation] ne $operation_name ||
        [dict get $context phase] ne $phase_name} {
        _raise FAIL OPERATION_MISMATCH CONTRACT \
            {Synthesis operation or phase does not match the interface.}
    }
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        _raise FAIL EXECUTION_ID_INVALID CONTRACT \
            {Synthesis execution_id must not be empty.}
    }
    _validate_authorization [dict get $context authorization] $execution_id
    set source_identity [_validate_identity \
        [dict get $context source_identity] source_identity $execution_id]
    set configuration_identity [_validate_identity \
        [dict get $context configuration_identity] configuration_identity \
        $execution_id]
    set environment_identity [_validate_identity \
        [dict get $context environment_identity] environment_identity \
        $execution_id]
    _require_keys $environment_identity {vivado_version part board_part} \
        environment_identity
    foreach field {vivado_version part board_part} {
        if {[string trim [dict get $environment_identity $field]] eq {}} {
            _raise BLOCKED ENVIRONMENT_IDENTITY_INCOMPLETE ENVIRONMENT \
                "Environment identity is missing: $field"
        }
    }
    set workspace_identity [_validate_workspace \
        [dict get $context workspace_identity] $source_identity $execution_id]
    set ownership [_validate_ownership $context $execution_id \
        [dict get $workspace_identity workspace_root] $environment_identity]
    set project [dict get $ownership project_ownership]
    set bd [dict get $ownership bd_ownership]
    set build_target [_validate_build_target \
        [dict get $context build_target_identity] $execution_id \
        $source_identity $configuration_identity $environment_identity \
        $project $bd [dict get $workspace_identity workspace_root]]
    set synthesis_policy [_validate_synthesis_policy \
        [dict get $context synthesis_policy] $workspace_identity $build_target]
    set launcher_lifetime_policy [_validate_launcher_lifetime_binding \
        [dict get $context launcher_lifetime_policy] \
        [dict get $synthesis_policy job_policy]]
    return [dict create \
        context $context \
        execution_id $execution_id \
        source_identity $source_identity \
        configuration_identity $configuration_identity \
        environment_identity $environment_identity \
        workspace_identity $workspace_identity \
        project_ownership $project \
        bd_ownership $bd \
        build_target_identity $build_target \
        synthesis_policy $synthesis_policy \
        launcher_lifetime_policy $launcher_lifetime_policy]
}

proc ::stage1e::synthesis::_read_property {property object label} {
    if {[catch {_invoke get_property $property $object} value options]} {
        _raise FAIL PROPERTY_READBACK_FAILED VIVADO \
            "$label property $property could not be read: $value"
    }
    return $value
}

proc ::stage1e::synthesis::_verify_live_ownership {validated} {
    set project [dict get $validated project_ownership]
    set project_handle [_invoke current_project]
    if {$project_handle ne [dict get $project project_handle]} {
        _raise FAIL PROJECT_OWNER_MISMATCH OWNERSHIP \
            {Current project does not match project ownership.}
    }
    set expected [dict get $project project_identity]
    set project_readback [dict create \
        project_handle $project_handle \
        project_name [_read_property NAME $project_handle project] \
        project_directory [file normalize \
            [_read_property DIRECTORY $project_handle project]] \
        part [_read_property PART $project_handle project] \
        board_part [_read_property BOARD_PART $project_handle project]]
    foreach field {project_name part board_part} {
        if {[dict get $project_readback $field] ne \
            [dict get $expected $field]} {
            _raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
                "Project readback mismatch: $field"
        }
    }
    if {![_paths_equal [dict get $project_readback project_directory] \
        [dict get $expected project_directory]]} {
        _raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
            {Project directory readback mismatch.}
    }
    set bd [dict get $validated bd_ownership]
    set current_bd [_invoke current_bd_design]
    if {$current_bd ne [dict get $bd bd_name]} {
        _raise FAIL BD_OWNER_MISMATCH OWNERSHIP \
            {Current BD does not match BD ownership.}
    }
    set bd_readback [dict create \
        bd_name $current_bd \
        bd_path [dict get $bd bd_path] \
        validated [dict get $bd validated] \
        saved [dict get $bd saved]]
    return [dict create project $project_readback bd $bd_readback]
}

proc ::stage1e::synthesis::_require_single_object {objects label} {
    if {[llength $objects] != 1} {
        _raise FAIL VIVADO_OBJECT_CARDINALITY VIVADO \
            "$label must resolve to exactly one object; found [llength $objects]."
    }
    return [lindex $objects 0]
}

proc ::stage1e::synthesis::_verify_fileset {validated} {
    set policy [dict get $validated synthesis_policy]
    set fileset [_require_single_object \
        [_invoke get_filesets -quiet [dict get $policy fileset]] \
        {Synthesis fileset}]
    set actual_name [_read_property NAME $fileset fileset]
    set actual_top [_read_property TOP $fileset fileset]
    if {$actual_name ne [dict get $policy fileset] ||
        $actual_top ne [dict get $policy top_module]} {
        _raise FAIL SYNTHESIS_TARGET_READBACK_MISMATCH IDENTITY \
            {Synthesis fileset/top does not match policy.}
    }
    return [dict create name $actual_name top $actual_top handle $fileset]
}

proc ::stage1e::synthesis::_verify_run_before_launch {validated} {
    set policy [dict get $validated synthesis_policy]
    set run [_require_single_object \
        [_invoke get_runs -quiet [dict get $policy run_name]] \
        {Synthesis run}]
    set readback [dict create \
        handle $run \
        name [_read_property NAME $run {synthesis run}] \
        directory [file normalize \
            [_read_property DIRECTORY $run {synthesis run}]] \
        status [_read_property STATUS $run {synthesis run}] \
        progress [_read_property PROGRESS $run {synthesis run}] \
        job_id [_read_property JOB_ID $run {synthesis run}]]
    if {[dict get $readback name] ne [dict get $policy run_name] ||
        ![_paths_equal [dict get $readback directory] \
            [dict get $policy output_directory]]} {
        _raise FAIL SYNTHESIS_RUN_IDENTITY_MISMATCH IDENTITY \
            {Synthesis run name or directory does not match policy.}
    }
    if {[dict get $readback status] ni \
        [dict get $policy allowed_initial_statuses]} {
        _raise FAIL SYNTHESIS_RUN_STALE WORKSPACE \
            "Synthesis run is not fresh: [dict get $readback status]"
    }
    set begin_marker [file normalize [file join \
        [dict get $readback directory] .Vivado_Synthesis.begin.rst]]
    set run_log [file normalize [file join \
        [dict get $readback directory] runme.log]]
    if {[dict get $readback progress] ne {0%} ||
        [string trim [dict get $readback job_id]] ne {} ||
        [file exists $begin_marker] || [file exists $run_log]} {
        _raise FAIL SYNTHESIS_RUN_STALE WORKSPACE \
            {Synthesis run contains stale dispatch or progress evidence.}
    }
    dict set readback begin_marker_path $begin_marker
    dict set readback run_log_path $run_log
    return $readback
}

proc ::stage1e::synthesis::_configure_run {validated run} {
    set policy [dict get $validated synthesis_policy]
    _invoke set_property STRATEGY [dict get $policy strategy] $run
    dict for {property value} [dict get $policy directives] {
        _invoke set_property $property $value $run
    }
    set seed_policy [dict get $policy seed_policy]
    if {[dict get $seed_policy mode] eq {FIXED}} {
        _invoke set_property [dict get $seed_policy property] \
            [dict get $seed_policy value] $run
    }
    set readback [dict create \
        strategy [_read_property STRATEGY $run {synthesis run}]]
    if {[dict get $readback strategy] ne [dict get $policy strategy]} {
        _raise FAIL SYNTHESIS_POLICY_READBACK_MISMATCH IDENTITY \
            {Synthesis strategy readback mismatch.}
    }
    set directive_readback [dict create]
    dict for {property expected} [dict get $policy directives] {
        set actual [_read_property $property $run {synthesis run}]
        if {$actual ne $expected} {
            _raise FAIL SYNTHESIS_POLICY_READBACK_MISMATCH IDENTITY \
                "Synthesis directive readback mismatch: $property"
        }
        dict set directive_readback $property $actual
    }
    dict set readback directives $directive_readback
    if {[dict get $seed_policy mode] eq {FIXED}} {
        set property [dict get $seed_policy property]
        set actual [_read_property $property $run {synthesis run}]
        if {$actual ne [dict get $seed_policy value]} {
            _raise FAIL SYNTHESIS_POLICY_READBACK_MISMATCH IDENTITY \
                {Synthesis seed readback mismatch.}
        }
        dict set readback seed [dict create property $property value $actual]
    } else {
        dict set readback seed [dict create mode NOT_APPLICABLE]
    }
    return $readback
}

proc ::stage1e::synthesis::_progress_observed {progress} {
    set progress [string trim $progress]
    return [expr {$progress ni {{} 0 0%}}]
}

proc ::stage1e::synthesis::_status_is_queued {status} {
    return [string match -nocase {Queued*} [string trim $status]]
}

proc ::stage1e::synthesis::_synthesis_run_objects {top_run} {
    set synthesis_runs {}
    foreach run [_invoke get_runs -quiet] {
        set is_synthesis [string tolower [string trim \
            [_read_property IS_SYNTHESIS $run {Vivado run}]]]
        if {$is_synthesis in {1 true}} {
            lappend synthesis_runs $run
        }
    }
    if {$top_run ni $synthesis_runs} {
        lappend synthesis_runs $top_run
    }
    return [lsort -unique $synthesis_runs]
}

proc ::stage1e::synthesis::_dispatch_snapshot {validated top_run} {
    set policy [dict get $validated synthesis_policy]
    set run_root [file normalize \
        [file dirname [dict get $policy output_directory]]]
    set records {}
    set begin_marker_observed 0
    set run_log_observed 0
    set job_assignment_observed 0
    set progress_observed 0
    set terminal_run_observed 0
    set queued_count 0
    set top_status {}
    set top_progress {}
    set top_job_id {}
    foreach run [_synthesis_run_objects $top_run] {
        set name [_read_property NAME $run {synthesis run}]
        set directory [file normalize \
            [_read_property DIRECTORY $run {synthesis run}]]
        if {![_is_equal_or_descendant $directory $run_root] ||
            [_paths_equal $directory $run_root]} {
            _raise FAIL SYNTHESIS_RUN_DIRECTORY_INVALID WORKSPACE \
                {Synthesis dispatch run directory escaped the project run root.}
        }
        set status [_read_property STATUS $run {synthesis run}]
        set progress [_read_property PROGRESS $run {synthesis run}]
        set job_id [_read_property JOB_ID $run {synthesis run}]
        set begin_marker [file normalize \
            [file join $directory .Vivado_Synthesis.begin.rst]]
        set run_log [file normalize [file join $directory runme.log]]
        set has_begin_marker [file isfile $begin_marker]
        set has_run_log [file isfile $run_log]
        set has_progress [_progress_observed $progress]
        set has_job_assignment [expr {[string trim $job_id] ne {}}]
        set terminal [expr {
            $status in [dict get $policy accepted_terminal_statuses] &&
            $progress eq {100%}
        }]
        if {[_status_is_queued $status]} {
            incr queued_count
        }
        if {$has_begin_marker} {
            set begin_marker_observed 1
        }
        if {$has_run_log} {
            set run_log_observed 1
        }
        if {$has_job_assignment} {
            set job_assignment_observed 1
        }
        if {$has_progress} {
            set progress_observed 1
        }
        if {$terminal} {
            set terminal_run_observed 1
        }
        if {$run eq $top_run} {
            set top_status $status
            set top_progress $progress
            set top_job_id $job_id
        }
        lappend records [dict create \
            name $name handle $run directory $directory status $status \
            progress $progress job_id $job_id \
            begin_marker_path $begin_marker \
            begin_marker_present $has_begin_marker \
            run_log_path $run_log run_log_present $has_run_log]
    }
    set child_process_observed [expr {
        $job_assignment_observed || $begin_marker_observed ||
        $terminal_run_observed
    }]
    set begin_marker_validated [expr {
        $begin_marker_observed || $terminal_run_observed
    }]
    set dispatch_started [expr {
        $child_process_observed && $begin_marker_validated &&
        $run_log_observed && $progress_observed
    }]
    return [dict create \
        top_run $top_run top_status $top_status \
        top_progress $top_progress top_job_id $top_job_id \
        synthesis_run_count [llength $records] queued_count $queued_count \
        child_process_observed $child_process_observed \
        job_assignment_observed $job_assignment_observed \
        begin_marker_observed $begin_marker_observed \
        begin_marker_validated $begin_marker_validated \
        run_log_observed $run_log_observed \
        progress_observed $progress_observed \
        terminal_run_observed $terminal_run_observed \
        dispatch_started $dispatch_started runs $records]
}

proc ::stage1e::synthesis::_wait_for_dispatch {validated top_run} {
    set job_policy [dict get $validated synthesis_policy job_policy]
    set timeout_milliseconds [expr {
        [dict get $job_policy dispatch_timeout_seconds] * 1000
    }]
    set poll_milliseconds \
        [dict get $job_policy dispatch_poll_interval_milliseconds]
    set elapsed_milliseconds 0
    set poll_count 0
    set observed [dict create \
        child_process_observed 0 job_assignment_observed 0 \
        begin_marker_observed 0 begin_marker_validated 0 \
        run_log_observed 0 progress_observed 0 \
        terminal_run_observed 0]
    while {1} {
        set snapshot [_dispatch_snapshot $validated $top_run]
        incr poll_count
        foreach field [dict keys $observed] {
            if {[dict get $snapshot $field]} {
                dict set observed $field 1
            }
        }
        if {[dict get $observed terminal_run_observed]} {
            dict set observed child_process_observed 1
            dict set observed begin_marker_validated 1
        }
        set dispatch_started [expr {
            [dict get $observed child_process_observed] &&
            [dict get $observed begin_marker_validated] &&
            [dict get $observed run_log_observed] &&
            [dict get $observed progress_observed]
        }]
        if {$dispatch_started} {
            return [dict merge $snapshot $observed [dict create \
                state STARTED dispatch_started 1 \
                elapsed_milliseconds $elapsed_milliseconds \
                poll_count $poll_count]]
        }
        if {$elapsed_milliseconds >= $timeout_milliseconds} {
            break
        }
        set delay [expr {min($poll_milliseconds,
            $timeout_milliseconds - $elapsed_milliseconds)}]
        _invoke after $delay
        incr elapsed_milliseconds $delay
    }
    set state INCOMPLETE
    if {[_status_is_queued [dict get $snapshot top_status]] &&
        ![dict get $observed child_process_observed] &&
        ![dict get $observed run_log_observed] &&
        ![dict get $observed progress_observed]} {
        set state STALLED
    }
    return [dict merge $snapshot $observed [dict create \
        state $state dispatch_started 0 \
        elapsed_milliseconds $elapsed_milliseconds \
        poll_count $poll_count]]
}

proc ::stage1e::synthesis::_require_message_collection_api {} {
    set probe_status [catch {
        _invoke info commands write_messages
    } commands probe_options]
    if {$probe_status != 0} {
        _raise FAIL SYNTHESIS_MESSAGE_API_PROBE_FAILED ENVIRONMENT \
            "Vivado message API capability probe failed: $commands"
    }
    if {[llength $commands] != 1 ||
        [lindex $commands 0] ne {write_messages}} {
        _raise BLOCKED SYNTHESIS_MESSAGE_API_UNAVAILABLE ENVIRONMENT \
            {Vivado 2024.1-compatible write_messages API is unavailable.}
    }
    return write_messages
}

proc ::stage1e::synthesis::_read_message_report {path} {
    if {![file isfile $path] || [file size $path] <= 0} {
        _raise FAIL SYNTHESIS_MESSAGE_EVIDENCE_MISSING EVIDENCE \
            {Synthesis message report is missing or empty.}
    }
    if {[catch {open $path r} channel]} {
        _raise FAIL SYNTHESIS_MESSAGE_EVIDENCE_UNREADABLE EVIDENCE \
            {Synthesis message report cannot be opened.}
    }
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} contents read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0 || $close_status != 0} {
        _raise FAIL SYNTHESIS_MESSAGE_EVIDENCE_UNREADABLE EVIDENCE \
            {Synthesis message report cannot be read completely.}
    }
    return $contents
}

proc ::stage1e::synthesis::_parse_message_report {
    contents
    expected_vivado_version
} {
    if {[string first "\u0000" $contents] >= 0} {
        _raise FAIL SYNTHESIS_MESSAGE_EVIDENCE_MALFORMED EVIDENCE \
            {Synthesis message report contains a NUL byte.}
    }
    set generated_header 0
    set command_header 0
    set report_version {}
    set records {}
    set output_lines {}
    foreach raw_line [split $contents "\n"] {
        set line [string trimright $raw_line "\r"]
        if {[regexp {^# Generated by Vivado ([0-9]+\.[0-9]+)} \
                $line _ version]} {
            set generated_header 1
            set report_version $version
            continue
        }
        if {[regexp {^# Command Used:[ \t]+write_messages([ \t]|$)} \
                $line] &&
            [string first {-message_db} $line] >= 0 &&
            [string first {-file} $line] >= 0} {
            set command_header 1
            continue
        }
        if {[regexp {^(INFO|STATUS|WARNING|CRITICAL WARNING|ERROR|CRITICAL ERROR):[ \t]+\[([^]]+)\][ \t]*(.*)$} \
                $line _ severity identifier message]} {
            set identifier [string trim $identifier]
            set message [string trim $message]
            if {$identifier eq {} || $message eq {} ||
                ![regexp {^[^\[\]\r\n]+$} $identifier]} {
                _raise FAIL SYNTHESIS_MESSAGE_EVIDENCE_MALFORMED EVIDENCE \
                    {Synthesis message record contains an invalid identifier or message.}
            }
            lappend records [dict create \
                identifier $identifier \
                severity [string toupper $severity] \
                message $message]
            continue
        }
        if {[regexp {^(INFO|STATUS|WARNING|CRITICAL WARNING|ERROR|CRITICAL ERROR):} \
                $line]} {
            _raise FAIL SYNTHESIS_MESSAGE_EVIDENCE_MALFORMED EVIDENCE \
                {Synthesis message report contains a malformed message record.}
        }
        if {[string trim $line] eq {} || [string match {#*} $line]} {
            continue
        }
        lappend output_lines $line
    }
    set expected_version {}
    regexp {([0-9]+\.[0-9]+)} $expected_vivado_version _ expected_version
    if {!$generated_header || !$command_header ||
        $expected_version eq {} || $report_version ne $expected_version ||
        [llength $records] == 0} {
        _raise FAIL SYNTHESIS_MESSAGE_EVIDENCE_MALFORMED EVIDENCE \
            {Synthesis message report header, version, command, or records are invalid.}
    }
    set severity_counts [dict create]
    foreach record $records {
        dict incr severity_counts [dict get $record severity] 1
    }
    return [dict create \
        schema_version stage1e-vivado-message-inventory-v1 \
        vivado_version $report_version \
        record_count [llength $records] \
        output_line_count [llength $output_lines] \
        severity_counts $severity_counts \
        records $records \
        output_lines $output_lines \
        records_sha256 [::stage1d::source_check::sha256_text $records] \
        output_sha256 [::stage1d::source_check::sha256_text $output_lines]]
}

proc ::stage1e::synthesis::_collect_message_evidence {validated} {
    set policy [dict get $validated synthesis_policy]
    set run_name [dict get $policy run_name]
    set database_path [dict get $policy message_database_path]
    if {![file isfile $database_path] || [file size $database_path] <= 0} {
        _raise FAIL SYNTHESIS_MESSAGE_DATABASE_UNAVAILABLE EVIDENCE \
            {Synthesis run message database is missing or empty.}
    }
    set report_path [dict get $policy report_paths message_report]
    set export_status [catch {
        _invoke write_messages \
            -message_db $database_path \
            -severity ALL \
            -suppression ALL \
            -modified_severity ALL \
            -verbose \
            -file $report_path
    } exported_path export_options]
    if {$export_status != 0} {
        _raise FAIL SYNTHESIS_MESSAGE_COLLECTION_FAILED EVIDENCE \
            "Vivado write_messages failed: $exported_path"
    }
    if {[string trim $exported_path] eq {} ||
        [file pathtype $exported_path] ne {absolute} ||
        ![_paths_equal $exported_path $report_path]} {
        _raise FAIL SYNTHESIS_MESSAGE_API_RESULT_INVALID EVIDENCE \
            {Vivado write_messages returned an unexpected evidence path.}
    }
    set contents [_read_message_report $report_path]
    set inventory [_parse_message_report $contents \
        [dict get $validated environment_identity vivado_version]]
    set database_evidence [_file_evidence synthesis_message_database \
        $database_path $run_name]
    set report_evidence [_file_evidence message_report \
        $report_path $run_name]
    dict set inventory message_database $database_evidence
    dict set inventory report $report_evidence
    set identity_payload $inventory
    dict set inventory identity_sha256 \
        [::stage1d::source_check::sha256_text $identity_payload]
    return [dict create \
        records [dict get $inventory records] \
        inventory $inventory \
        database_evidence $database_evidence \
        report_evidence $report_evidence]
}

proc ::stage1e::synthesis::_message_counts {records} {
    set counts [dict create]
    set examples [dict create]
    foreach record $records {
        set key [list [dict get $record identifier] \
            [dict get $record severity]]
        dict incr counts $key 1
        if {![dict exists $examples $key]} {
            dict set examples $key [dict get $record message]
        }
    }
    return [dict create counts $counts examples $examples]
}

proc ::stage1e::synthesis::_evaluate_messages {
    before_records
    after_records
    warning_policy
} {
    set before [_message_counts $before_records]
    set after [_message_counts $after_records]
    set warnings {}
    set errors {}
    set blocking_warnings 0
    dict for {key after_count} [dict get $after counts] {
        set before_count 0
        if {[dict exists $before counts $key]} {
            set before_count [dict get $before counts $key]
        }
        set count [expr {$after_count - $before_count}]
        if {$count <= 0} {
            continue
        }
        lassign $key identifier severity
        set message [dict get $after examples $key]
        if {$severity in {ERROR {CRITICAL ERROR}}} {
            lappend errors [dict create \
                code VIVADO_MESSAGE_ERROR \
                error_code VIVADO_MESSAGE_ERROR \
                class VIVADO \
                category VIVADO \
                identifier $identifier \
                severity $severity \
                count $count \
                message $message \
                evidence_references {message_report}]
            continue
        }
        if {$severity ni {WARNING {CRITICAL WARNING}}} {
            continue
        }
        set classification UNKNOWN
        set rationale {No matching warning disposition.}
        set disposition_match 0
        if {[dict exists $warning_policy dispositions $identifier]} {
            set disposition [dict get $warning_policy dispositions $identifier]
            set expected_severity [string toupper \
                [dict get $disposition severity]]
            if {$severity eq $expected_severity &&
                $count >= [dict get $disposition min_count] &&
                $count <= [dict get $disposition max_count]} {
                set disposition_match 1
                set classification [dict get $disposition classification]
                set rationale [dict get $disposition rationale]
            }
        }
        if {!$disposition_match || $classification ne {ACCEPTED}} {
            set blocking_warnings 1
        }
        lappend warnings [dict create \
            identifier $identifier \
            severity $severity \
            count $count \
            classification $classification \
            disposition_match $disposition_match \
            rationale $rationale \
            message $message \
            evidence_reference message_report]
    }
    return [dict create \
        warnings $warnings \
        errors $errors \
        blocking_warnings $blocking_warnings]
}

proc ::stage1e::synthesis::_file_evidence {role path run_name} {
    if {![file isfile $path] || [file size $path] <= 0} {
        _raise FAIL SYNTHESIS_EVIDENCE_FILE_INVALID EVIDENCE \
            "Synthesis evidence file is missing or empty: $role"
    }
    return [dict create \
        role $role \
        path [file normalize $path] \
        size [file size $path] \
        sha256 [::stage1d::source_check::sha256_file $path] \
        producing_run $run_name]
}

proc ::stage1e::synthesis::_collect_reports {validated run} {
    set policy [dict get $validated synthesis_policy]
    set paths [dict get $policy report_paths]
    # Vivado 2024.1 report_design_analysis does not accept -force. Report
    # destinations are already required to be fresh during policy validation,
    # so omitting it preserves the fail-closed stale-evidence boundary.
    _invoke report_design_analysis -file \
        [dict get $paths synthesis_report]
    _invoke report_utilization -file \
        [dict get $paths utilization_report] -force
    set evidence [dict create]
    foreach role {synthesis_report utilization_report} {
        set path [dict get $paths $role]
        dict set evidence $role [_file_evidence $role $path \
            [dict get $policy run_name]]
    }
    return $evidence
}

proc ::stage1e::synthesis::_preserve_run_log_evidence {validated} {
    set policy [dict get $validated synthesis_policy]
    set source [dict get $policy run_log_source_path]
    set destination [dict get $policy run_log_path]
    if {![file isfile $source] || [file size $source] <= 0} {
        _raise FAIL SYNTHESIS_LOG_SOURCE_UNAVAILABLE EVIDENCE \
            {Native synthesis run log is missing or empty.}
    }
    if {[file exists $destination]} {
        _raise FAIL SYNTHESIS_LOG_EVIDENCE_STALE EVIDENCE \
            {Synthesis log evidence destination already exists.}
    }
    if {[catch {file copy -- $source $destination} copy_error]} {
        _raise FAIL SYNTHESIS_LOG_EVIDENCE_WRITE_FAILED EVIDENCE \
            "Synthesis run log could not be preserved: $copy_error"
    }
    return [_file_evidence synthesis_log $destination \
        [dict get $policy run_name]]
}

proc ::stage1e::synthesis::_execute {context validated} {
    set ownership_records [dict create \
        project_ownership [dict get $validated project_ownership] \
        bd_ownership [dict get $validated bd_ownership]]
    set consumed_identities [dict create \
        source_identity [dict get $validated source_identity] \
        configuration_identity [dict get $validated configuration_identity] \
        environment_identity [dict get $validated environment_identity] \
        workspace_identity [dict get $validated workspace_identity] \
        build_target_identity [dict get $validated build_target_identity] \
        launcher_lifetime_policy \
            [dict get $validated launcher_lifetime_policy] \
        synthesis_policy [dict get $validated synthesis_policy]]
    set vivado_invoked 1
    set state_changed 0
    set synthesis_performed 0
    set evidence_references [dict create]
    set warnings {}
    set message_errors {}
    set execution_status [catch {
        set ownership_readback [_verify_live_ownership $validated]
        set fileset_readback [_verify_fileset $validated]
        set run_before [_verify_run_before_launch $validated]
        set run [dict get $run_before handle]
        set message_api [_require_message_collection_api]
        dict set evidence_references message_collection_api [dict create \
            command $message_api \
            source RUN_MESSAGE_DATABASE \
            database [dict get $validated synthesis_policy \
                message_database_path]]

        # The first state change occurs only after all context, ownership,
        # identity, path, run-freshness, and policy checks pass.
        set state_changed 1
        set policy_readback [_configure_run $validated $run]
        _invoke launch_runs $run -jobs \
            [dict get $validated synthesis_policy job_policy jobs]
        set dispatch_observation [_wait_for_dispatch $validated $run]
        dict set evidence_references dispatch $dispatch_observation
        if {[dict get $dispatch_observation state] eq {STALLED}} {
            _raise FAIL SYNTHESIS_DISPATCH_STALLED VIVADO \
                [join [list \
                    {Vivado synthesis dispatch timed out with the run queued,} \
                    {no child process, no begin marker, no run log, and no progress.}] { }]
        }
        if {![dict get $dispatch_observation dispatch_started]} {
            _raise FAIL SYNTHESIS_DISPATCH_EVIDENCE_INVALID EVIDENCE \
                {Vivado synthesis dispatch did not produce complete start evidence.}
        }
        set synthesis_performed 1
        set wait_timeout_minutes [dict get $validated synthesis_policy \
            job_policy wait_timeout_minutes]
        _invoke wait_on_run -timeout $wait_timeout_minutes $run
        set terminal_status [_read_property STATUS $run {synthesis run}]
        set terminal_progress [_read_property PROGRESS $run {synthesis run}]
        set completion_observation [_dispatch_snapshot $validated $run]
        dict set completion_observation wait_timeout_minutes \
            $wait_timeout_minutes
        dict set evidence_references completion_wait $completion_observation
        if {$terminal_status ni \
            [dict get $validated synthesis_policy accepted_terminal_statuses]} {
            if {[_status_is_queued $terminal_status] ||
                [string match -nocase {*Running*} $terminal_status]} {
                _raise FAIL SYNTHESIS_RUN_TIMEOUT VIVADO \
                    "Synthesis did not finish within the controlled wait: $terminal_status"
            }
            _raise FAIL SYNTHESIS_RUN_FAILED VIVADO \
                "Synthesis terminal status is not accepted: $terminal_status"
        }
        if {$terminal_progress ne {100%}} {
            _raise FAIL SYNTHESIS_RUN_PROGRESS_INVALID VIVADO \
                "Synthesis terminal progress is not complete: $terminal_progress"
        }
        set native_run_log [dict get $validated synthesis_policy \
            run_log_source_path]
        if {![file isfile $native_run_log] || [file size $native_run_log] <= 0} {
            _raise FAIL SYNTHESIS_RUN_LOG_MISSING EVIDENCE \
                {Completed synthesis has no non-empty native run log.}
        }
        set run_log [_preserve_run_log_evidence $validated]
        dict set evidence_references synthesis_log $run_log
        set message_collection [_collect_message_evidence $validated]
        dict set evidence_references message_database \
            [dict get $message_collection database_evidence]
        dict set evidence_references message_inventory \
            [dict get $message_collection inventory]
        set message_evaluation [_evaluate_messages {} \
            [dict get $message_collection records] \
            [dict get $validated synthesis_policy warning_policy]]
        set warnings [dict get $message_evaluation warnings]
        set message_errors [dict get $message_evaluation errors]
        _invoke open_run $run
        set report_evidence [_collect_reports $validated $run]
        dict set report_evidence message_report \
            [dict get $message_collection report_evidence]
        set run_readback [dict create \
            name [_read_property NAME $run {synthesis run}] \
            directory [file normalize \
                [_read_property DIRECTORY $run {synthesis run}]] \
            status $terminal_status \
            progress $terminal_progress \
            strategy [_read_property STRATEGY $run {synthesis run}] \
            jobs [dict get $validated synthesis_policy job_policy jobs] \
            wait_timeout_minutes $wait_timeout_minutes \
            incremental_synthesis_enabled 0]
        set evidence_references [dict create \
            ownership_readback $ownership_readback \
            fileset_readback $fileset_readback \
            run_before $run_before \
            policy_readback $policy_readback \
            dispatch $dispatch_observation \
            completion_wait $completion_observation \
            run_readback $run_readback \
            reports $report_evidence \
            synthesis_log $run_log \
            message_collection_api [dict get $evidence_references \
                message_collection_api] \
            message_database [dict get $message_collection database_evidence] \
            message_inventory [dict get $message_collection inventory] \
            warning_inventory $warnings \
            error_inventory $message_errors]
        if {[llength $message_errors] != 0} {
            _raise FAIL SYNTHESIS_ERRORS_OBSERVED VIVADO \
                {Vivado reported synthesis errors.}
        }
        if {[dict get $message_evaluation blocking_warnings]} {
            _raise FAIL SYNTHESIS_WARNING_UNRESOLVED POLICY \
                {Synthesis contains rejected, unknown, or unresolved warnings.}
        }

        set evidence_sha256 [::stage1d::source_check::sha256_text \
            $evidence_references]
        set run_identity_sha256 [::stage1d::source_check::sha256_text \
            $run_readback]
        set warnings_sha256 [::stage1d::source_check::sha256_text $warnings]
        set identity_payload [list \
            [dict get $validated execution_id] \
            [_identity_hash [dict get $validated source_identity] \
                source_identity] \
            [_identity_hash [dict get $validated configuration_identity] \
                configuration_identity] \
            [_identity_hash [dict get $validated environment_identity] \
                environment_identity] \
            [dict get $validated workspace_identity identity_sha256] \
            [dict get $validated build_target_identity identity_sha256] \
            [dict get $validated synthesis_policy identity_sha256] \
            $run_identity_sha256 $evidence_sha256 $warnings_sha256]
        set synthesis_result_identity [dict create \
            schema_version stage1e-synthesis-result-identity-v1 \
            producer_operation stage1e::synthesis::run \
            execution_id [dict get $validated execution_id] \
            acceptance_state CANDIDATE \
            source_identity_sha256 [_identity_hash \
                [dict get $validated source_identity] source_identity] \
            configuration_identity_sha256 [_identity_hash \
                [dict get $validated configuration_identity] \
                configuration_identity] \
            environment_identity_sha256 [_identity_hash \
                [dict get $validated environment_identity] \
                environment_identity] \
            workspace_identity_sha256 \
                [dict get $validated workspace_identity identity_sha256] \
            build_target_identity_sha256 \
                [dict get $validated build_target_identity identity_sha256] \
            synthesis_policy_sha256 \
                [dict get $validated synthesis_policy identity_sha256] \
            run_name [dict get $run_readback name] \
            run_directory [dict get $run_readback directory] \
            run_status [dict get $run_readback status] \
            top_module [dict get $fileset_readback top] \
            fileset [dict get $fileset_readback name] \
            part [dict get $validated environment_identity part] \
            board_part [dict get $validated environment_identity board_part] \
            vivado_version \
                [dict get $validated environment_identity vivado_version] \
            run_identity_sha256 $run_identity_sha256 \
            evidence_sha256 $evidence_sha256 \
            warnings_sha256 $warnings_sha256 \
            identity_sha256 [::stage1d::source_check::sha256_text \
                $identity_payload]]
    } execution_error execution_options]

    if {$execution_status != 0} {
        set decoded [_decode_error $execution_error $execution_options \
            SYNTHESIS_EXECUTION_FAILED VIVADO]
        set cleanup [_cleanup_result $state_changed \
            [expr {!$state_changed}] \
            [expr {$state_changed ? \
                {CONTROLLER_LIFECYCLE_DECISION_REQUIRED} : {NOT_REQUIRED}}]]
        set result_errors $message_errors
        lappend result_errors [_error_record $decoded]
        return [_result [dict get $decoded status] $context \
            $consumed_identities {} $ownership_records \
            $evidence_references $warnings $result_errors $cleanup \
            $vivado_invoked $synthesis_performed]
    }

    return [_result PASS $context $consumed_identities \
        [dict create synthesis_result_identity $synthesis_result_identity] \
        $ownership_records $evidence_references $warnings {} \
        [_cleanup_result 0 1 LIFECYCLE_OWNERSHIP_PRESERVED] \
        $vivado_invoked $synthesis_performed]
}

proc ::stage1e::synthesis::run {context} {
    set validation_status [catch {
        _validate_context $context
    } validated validation_options]
    if {$validation_status != 0} {
        set decoded [_decode_error $validated $validation_options \
            SYNTHESIS_CONTEXT_INVALID CONTRACT]
        return [_result [dict get $decoded status] $context {} {} {} {} {} \
            [list [_error_record $decoded]] \
            [_cleanup_result 0 1 NOT_REQUIRED] 0 0]
    }
    return [_execute $context $validated]
}
