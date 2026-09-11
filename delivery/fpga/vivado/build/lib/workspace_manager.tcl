namespace eval ::stage1d::workspace_manager {
    variable phase2_workspace_identity_schema_version \
        stage1e-workspace-identity-v2
}

proc ::stage1d::workspace_manager::phase2_workspace_identity {
    execution_identifier
    retry_number
    git_commit
    git_tree
    workspace_identifier
    execution_workspace
    project_name
    synthesis_run_name
    ownership_evidence
} {
    variable phase2_workspace_identity_schema_version
    if {![regexp {^[1-9][0-9]*$} $retry_number]} {
        error {Phase 2 workspace retry number must be a positive canonical integer.}
    }
    if {$workspace_identifier ne "r$retry_number"} {
        error {Phase 2 workspace identifier is not bound to the retry number.}
    }
    foreach {value label pattern} [list \
        $git_commit {Git commit} {^[0-9a-fA-F]{40}$} \
        $git_tree {Git tree} {^[0-9a-fA-F]{40}$} \
        $project_name {Project name} {^[A-Za-z0-9._-]+$} \
        $synthesis_run_name {Synthesis run name} {^[A-Za-z0-9._-]+$}] {
        if {![regexp $pattern $value]} {
            error "$label is invalid for the Phase 2 workspace identity."
        }
    }
    set execution_workspace [file normalize $execution_workspace]
    set evidence_dir [file normalize \
        [file join $execution_workspace execution_state]]
    set synthesis_output_dir [file normalize [file join \
        $execution_workspace project "${project_name}.runs" \
        $synthesis_run_name]]
    set identity [dict create \
        schema_version $phase2_workspace_identity_schema_version \
        execution_id $execution_identifier \
        retry_number $retry_number \
        git_commit [string tolower $git_commit] \
        git_tree [string tolower $git_tree] \
        workspace_identifier $workspace_identifier \
        workspace_path $execution_workspace \
        workspace_root $execution_workspace \
        evidence_dir $evidence_dir \
        synthesis_output_dir $synthesis_output_dir \
        ownership_evidence $ownership_evidence]
    dict set identity identity_sha256 \
        [::stage1d::source_check::sha256_text $identity]
    return $identity
}

proc ::stage1d::workspace_manager::_canonical_components {path} {
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

proc ::stage1d::workspace_manager::_is_equal_or_descendant {candidate parent} {
    set candidate_components [_canonical_components $candidate]
    set parent_components [_canonical_components $parent]
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

proc ::stage1d::workspace_manager::_paths_overlap {first_path second_path} {
    return [expr {
        [_is_equal_or_descendant $first_path $second_path] ||
        [_is_equal_or_descendant $second_path $first_path]
    }]
}

proc ::stage1d::workspace_manager::_error_record {
    error_code
    category
    message
    recoverability
} {
    return [dict create \
        error_code $error_code \
        category $category \
        phase_name workspace_preparation \
        message $message \
        underlying_error {} \
        evidence_references {} \
        recoverability $recoverability]
}

proc ::stage1d::workspace_manager::_result {status outputs errors {evidence_locations {}}} {
    return [dict create \
        status $status \
        evidence_locations $evidence_locations \
        logs {} \
        reports {} \
        errors $errors \
        outputs $outputs \
        artifact_references {}]
}

proc ::stage1d::workspace_manager::_stop {
    status
    error_code
    category
    message
    recoverability
    outputs
} {
    return [_result $status $outputs [list [_error_record \
        $error_code $category $message $recoverability]]]
}

proc ::stage1d::workspace_manager::_relative_to_root {root path} {
    set root_components [_canonical_components $root]
    set path_components [file split [file normalize $path]]
    set relative_components [lrange $path_components [llength $root_components] end]
    return [string map {\\ /} [file join {*}$relative_components]]
}

proc ::stage1d::workspace_manager::_find_stale_vivado_state {root patterns} {
    if {![file isdirectory $root]} {
        return {}
    }

    set stale_entries {}
    set queue [list [list $root 0]]
    set inspected 0
    while {[llength $queue] > 0} {
        lassign [lindex $queue 0] current depth
        set queue [lrange $queue 1 end]

        set children [glob -nocomplain -directory $current *]
        foreach hidden [glob -nocomplain -directory $current .*] {
            if {[file tail $hidden] ni {. ..}} {
                lappend children $hidden
            }
        }
        foreach child [lsort -dictionary -unique $children] {
            incr inspected
            if {$inspected > 4096} {
                lappend stale_entries SCAN_LIMIT_REACHED
                return $stale_entries
            }

            set child_name [file tail $child]
            foreach pattern $patterns {
                if {[string match $pattern $child_name]} {
                    lappend stale_entries [_relative_to_root $root $child]
                    break
                }
            }

            if {$depth < 8 && [file isdirectory $child] && [file type $child] ne {link}} {
                lappend queue [list $child [expr {$depth + 1}]]
            }
        }
    }
    return [lsort -dictionary -unique $stale_entries]
}

proc ::stage1d::workspace_manager::_write_ownership_binding {path ownership} {
    set channel [open $path {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    set write_status [catch {puts $channel $ownership} write_error write_options]
    set close_status [catch {close $channel} close_error]
    if {$write_status != 0} {
        return -options $write_options $write_error
    }
    if {$close_status != 0} {
        error "Unable to close workspace ownership binding: $close_error"
    }
}

proc ::stage1d::workspace_manager::_run {context} {
    set parsed [dict get $context parsed_arguments]
    set configuration [dict get $context configuration]
    set execution_identity [dict get $context execution_identity]
    set input_outputs [dict get $context input_validation_outputs]
    set source_outputs [dict get $context source_verification]
    set environment_outputs [dict get $context environment_verification]

    set repository_root [file normalize [dict get $parsed repository_root]]
    set build_workspace_root [file normalize [dict get $parsed build_workspace]]
    set artifact_storage_root [file normalize [dict get $parsed artifact_storage]]
    set execution_identifier [dict get $execution_identity execution_identifier]
    set workspace_identifier $execution_identifier
    set compact_workspace_identifier 0
    if {[dict exists $execution_identity workspace_identifier]} {
        set workspace_identifier \
            [dict get $execution_identity workspace_identifier]
        set compact_workspace_identifier 1
        if {[string trim $workspace_identifier] eq {} ||
            ![regexp {^[A-Za-z0-9._-]+$} $workspace_identifier] ||
            [file tail $workspace_identifier] ne $workspace_identifier} {
            error {Controlled workspace identifier is not a safe path component.}
        }
    }
    set execution_workspace [file normalize \
        [file join $build_workspace_root $workspace_identifier]]
    set artifact_group [file normalize \
        [file join $artifact_storage_root $workspace_identifier]]
    set ownership_relative_path execution_state/ownership.dict
    set outputs [dict create \
        repository_root $repository_root \
        build_workspace_root $build_workspace_root \
        artifact_storage_root $artifact_storage_root \
        execution_workspace $execution_workspace \
        artifact_group $artifact_group \
        workspace_created 0 \
        ownership_bound 0 \
        artifacts_generated 0]
    if {$compact_workspace_identifier} {
        foreach key {
            retry_number git_tree project_name synthesis_run_name
        } {
            if {![dict exists $execution_identity $key]} {
                error "Controlled execution identity is missing key: $key"
            }
        }
        set phase2_workspace_identity [phase2_workspace_identity \
            $execution_identifier \
            [dict get $execution_identity retry_number] \
            [dict get $source_outputs git_commit] \
            [dict get $execution_identity git_tree] \
            $workspace_identifier \
            $execution_workspace \
            [dict get $execution_identity project_name] \
            [dict get $execution_identity synthesis_run_name] \
            $ownership_relative_path]
        dict set outputs execution_identifier $execution_identifier
        dict set outputs workspace_identifier $workspace_identifier
        dict set outputs retry_number \
            [dict get $execution_identity retry_number]
        dict set outputs workspace_identity $phase2_workspace_identity
        dict set outputs workspace_identity_hash \
            [dict get $phase2_workspace_identity identity_sha256]
        if {[dict exists $execution_identity \
                workspace_identifier_schema_version]} {
            dict set outputs workspace_identifier_schema_version \
                [dict get $execution_identity \
                    workspace_identifier_schema_version]
        }
    }

    if {[_paths_overlap $repository_root $build_workspace_root]} {
        return [_stop FAIL WORKSPACE_REPOSITORY_OVERLAP WORKSPACE \
            {Build workspace must be external to the Git repository.} \
            SELECT_EXTERNAL_WORKSPACE $outputs]
    }
    if {[_paths_overlap $repository_root $artifact_storage_root]} {
        return [_stop FAIL ARTIFACT_STORAGE_REPOSITORY_OVERLAP WORKSPACE \
            {Artifact storage must be external to the Git repository.} \
            SELECT_EXTERNAL_ARTIFACT_STORAGE $outputs]
    }
    if {[_paths_overlap $build_workspace_root $artifact_storage_root]} {
        return [_stop FAIL WORKSPACE_ARTIFACT_STORAGE_OVERLAP WORKSPACE \
            {Build workspace and artifact storage must not overlap.} \
            SEPARATE_STORAGE_ROOTS $outputs]
    }
    dict set outputs repository_separation_verified 1
    dict set outputs artifact_storage_separation_verified 1

    if {[file exists $build_workspace_root] && ![file isdirectory $build_workspace_root]} {
        return [_stop BLOCKED WORKSPACE_ROOT_NOT_DIRECTORY WORKSPACE \
            {Build workspace root exists but is not a directory.} \
            SELECT_EXTERNAL_WORKSPACE $outputs]
    }
    if {[file exists $artifact_storage_root] && ![file isdirectory $artifact_storage_root]} {
        return [_stop BLOCKED ARTIFACT_STORAGE_NOT_DIRECTORY WORKSPACE \
            {Artifact storage root exists but is not a directory.} \
            SELECT_EXTERNAL_ARTIFACT_STORAGE $outputs]
    }

    set expected_workspace [file normalize [dict get $input_outputs execution_workspace]]
    if {[_canonical_components $execution_workspace] ne \
        [_canonical_components $expected_workspace]} {
        return [_stop FAIL EXECUTION_WORKSPACE_IDENTITY_MISMATCH PROVENANCE \
            {Workspace path does not match the collision-checked execution identity.} \
            NONE $outputs]
    }
    if {[file exists $artifact_group]} {
        return [_stop FAIL ARTIFACT_GROUP_COLLISION PROVENANCE \
            {The execution-specific artifact group already exists.} \
            GENERATE_NEW_EXECUTION_IDENTIFIER $outputs]
    }

    set stale_patterns [dict get $configuration workspace stale_vivado_markers]
    if {[file exists $execution_workspace]} {
        set stale_entries [_find_stale_vivado_state $execution_workspace $stale_patterns]
        dict set outputs stale_vivado_state $stale_entries
        if {[llength $stale_entries] > 0} {
            return [_stop FAIL STALE_VIVADO_STATE WORKSPACE \
                {Execution workspace contains stale Vivado generated state.} \
                GENERATE_NEW_EXECUTION_IDENTIFIER $outputs]
        }
        return [_stop FAIL WORKSPACE_NOT_FRESH WORKSPACE \
            {Execution workspace already exists and cannot be reused.} \
            GENERATE_NEW_EXECUTION_IDENTIFIER $outputs]
    }
    dict set outputs workspace_fresh 1
    dict set outputs stale_vivado_state_detected 0

    set execution_state_directory [file join $execution_workspace execution_state]
    set logs_directory [file join $execution_workspace logs]
    set reports_directory [file join $execution_workspace reports]
    if {[catch {
        file mkdir $execution_state_directory
        file mkdir $logs_directory
        file mkdir $reports_directory
    } create_error]} {
        return [_stop BLOCKED WORKSPACE_CREATION_FAILED WORKSPACE \
            "Unable to create the controlled execution workspace: $create_error" \
            PROVIDE_WRITABLE_WORKSPACE $outputs]
    }
    dict set outputs workspace_created 1

    set ownership_path [file join $execution_workspace execution_state ownership.dict]
    set ownership [dict create \
        ownership_schema_version [dict get $configuration workspace ownership_schema_version] \
        execution_identifier $execution_identifier \
        execution_id_schema_version [dict get $execution_identity execution_id_schema_version] \
        execution_generation_timestamp [dict get $execution_identity generated_at] \
        controller_version [::stage1d::controller_core::version] \
        controller_api_version [::stage1d::controller_core::api_version] \
        git_commit [dict get $source_outputs git_commit] \
        controller_source_hash [dict get $source_outputs controller_source_hash] \
        configuration_hash [dict get $source_outputs configuration_hash] \
        environment_evidence_hash [dict get $environment_outputs environment_evidence_hash] \
        workspace_role ACTIVE_BUILD_WORKSPACE]
    if {$compact_workspace_identifier} {
        dict set ownership execution_id $execution_identifier
        dict set ownership retry_number \
            [dict get $execution_identity retry_number]
        dict set ownership git_tree \
            [string tolower [dict get $execution_identity git_tree]]
        dict set ownership workspace_path $execution_workspace
        dict set ownership workspace_identifier $workspace_identifier
        dict set ownership workspace_identity_schema_version \
            [dict get $phase2_workspace_identity schema_version]
        dict set ownership workspace_identity_hash \
            [dict get $phase2_workspace_identity identity_sha256]
        if {[dict exists $execution_identity \
                workspace_identifier_schema_version]} {
            dict set ownership workspace_identifier_schema_version \
                [dict get $execution_identity \
                    workspace_identifier_schema_version]
        }
    }
    if {[catch {
        _write_ownership_binding $ownership_path $ownership
    } ownership_error]} {
        dict set outputs workspace_contaminated 1
        return [_stop FAIL WORKSPACE_OWNERSHIP_BINDING_FAILED PROVENANCE \
            "Unable to bind workspace ownership: $ownership_error" \
            GENERATE_NEW_EXECUTION_IDENTIFIER $outputs]
    }

    dict set outputs ownership_bound 1
    dict set outputs ownership_binding $ownership
    dict set outputs ownership_evidence $ownership_relative_path
    dict set outputs workspace_areas {
        execution_state
        logs
        reports
    }
    dict set outputs project_created 0
    return [_result PASS $outputs {} [list $ownership_relative_path]]
}

proc ::stage1d::workspace_manager::run {context} {
    set run_status [catch {_run $context} result run_options]
    if {$run_status == 0} {
        return $result
    }

    set underlying_error {}
    if {[dict exists $run_options -errorinfo]} {
        set underlying_error [dict get $run_options -errorinfo]
    }
    set error_record [_error_record \
        WORKSPACE_MANAGER_INTERNAL_ERROR \
        CORE \
        "Unexpected workspace verification error: $result" \
        NONE]
    dict set error_record underlying_error $underlying_error
    return [_result FAIL {} [list $error_record]]
}
