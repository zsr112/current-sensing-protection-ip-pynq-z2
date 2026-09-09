namespace eval ::stage1d::environment_check {
    variable required_evidence_fields {
        schema_version
        observation_timestamp
        observation_source
        vivado_version
        sw_build
        ip_build
        part
        board_part
        board_definition_available
        board_definition_files
        ip_identities
    }
}

proc ::stage1d::environment_check::_error_record {
    error_code
    category
    message
    recoverability
} {
    return [dict create \
        error_code $error_code \
        category $category \
        phase_name environment_verification \
        message $message \
        underlying_error {} \
        evidence_references {} \
        recoverability $recoverability]
}

proc ::stage1d::environment_check::_result {status outputs errors {evidence_locations {}}} {
    return [dict create \
        status $status \
        evidence_locations $evidence_locations \
        logs {} \
        reports {} \
        errors $errors \
        outputs $outputs \
        artifact_references {}]
}

proc ::stage1d::environment_check::_stop {
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

proc ::stage1d::environment_check::_read_evidence_file {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} content read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $content
    }
    if {$close_status != 0} {
        error "Unable to close environment evidence: $close_error"
    }

    set content [string trim $content]
    if {$content eq {}} {
        error {Environment evidence file is empty.}
    }
    if {[catch {dict size $content} dictionary_error]} {
        error "Environment evidence is not a declarative Tcl dictionary: $dictionary_error"
    }
    return $content
}

proc ::stage1d::environment_check::_validate_evidence_shape {evidence expected_schema} {
    variable required_evidence_fields

    foreach field $required_evidence_fields {
        if {![dict exists $evidence $field]} {
            error "Environment evidence is missing required field: $field"
        }
    }
    if {[dict get $evidence schema_version] ne $expected_schema} {
        error "Environment evidence schema mismatch: configured=$expected_schema observed=[dict get $evidence schema_version]"
    }
    if {![regexp {^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$} \
        [dict get $evidence observation_timestamp]]} {
        error {Environment evidence observation_timestamp is not canonical UTC.}
    }
    if {[dict get $evidence observation_source] eq {}} {
        error {Environment evidence observation_source must not be empty.}
    }
    if {![string is boolean -strict [dict get $evidence board_definition_available]]} {
        error {Environment evidence board_definition_available must be boolean.}
    }
    foreach list_field {board_definition_files ip_identities} {
        if {[catch {llength [dict get $evidence $list_field]} list_error]} {
            error "Environment evidence field $list_field is not a list: $list_error"
        }
    }
    return 1
}

proc ::stage1d::environment_check::_compare_identity {
    evidence
    expected
    field
    outputs_variable
} {
    upvar 1 $outputs_variable outputs
    set expected_value [dict get $expected $field]
    set observed_value [dict get $evidence $field]
    dict set outputs $field $observed_value
    if {$observed_value ne $expected_value} {
        error "Environment identity mismatch for $field: observed=$observed_value expected=$expected_value"
    }
}

proc ::stage1d::environment_check::_resolve_ip_identities {
    required_patterns
    observed_identities
} {
    set unique_identities [dict create]
    foreach identity $observed_identities {
        if {![regexp {^[^:]+:[^:]+:[^:]+:[^:]+$} $identity]} {
            error "Invalid observed IP VLNV: $identity"
        }
        if {[dict exists $unique_identities $identity]} {
            error "Duplicate observed IP VLNV: $identity"
        }
        dict set unique_identities $identity 1
    }

    set resolved {}
    set missing {}
    set ambiguous {}
    foreach pattern $required_patterns {
        set matches {}
        foreach identity [dict keys $unique_identities] {
            if {[string match $pattern $identity]} {
                lappend matches $identity
            }
        }
        set matches [lsort -dictionary $matches]
        if {[llength $matches] == 0} {
            lappend missing $pattern
        } elseif {[llength $matches] > 1} {
            lappend ambiguous [dict create pattern $pattern matches $matches]
        } else {
            lappend resolved [dict create \
                required_pattern $pattern \
                resolved_vlnv [lindex $matches 0]]
        }
    }
    return [dict create \
        resolved $resolved \
        missing $missing \
        ambiguous $ambiguous]
}

proc ::stage1d::environment_check::_run {context} {
    set parsed [dict get $context parsed_arguments]
    set configuration [dict get $context configuration]
    set expected [dict get $configuration environment]
    set evidence_path [dict get $parsed environment_evidence_path]
    set outputs [dict create \
        expected_environment $expected \
        project_opened 0]

    if {$evidence_path eq {}} {
        return [_stop BLOCKED ENVIRONMENT_EVIDENCE_NOT_SUPPLIED ENVIRONMENT \
            {A declarative environment-evidence file is required for Phase 2 verification.} \
            PROVIDE_ENVIRONMENT_EVIDENCE $outputs]
    }
    set evidence_path [file normalize $evidence_path]
    if {![file exists $evidence_path] || ![file isfile $evidence_path]} {
        return [_stop BLOCKED ENVIRONMENT_EVIDENCE_NOT_FOUND ENVIRONMENT \
            {The supplied environment-evidence file does not exist.} \
            PROVIDE_ENVIRONMENT_EVIDENCE $outputs]
    }

    if {[catch {_read_evidence_file $evidence_path} evidence]} {
        return [_stop FAIL ENVIRONMENT_EVIDENCE_INVALID ENVIRONMENT \
            "Unable to read environment evidence: $evidence" NONE $outputs]
    }
    if {[catch {
        _validate_evidence_shape $evidence [dict get $expected evidence_schema_version]
    } shape_error]} {
        return [_stop FAIL ENVIRONMENT_EVIDENCE_SCHEMA_INVALID ENVIRONMENT \
            $shape_error NONE $outputs]
    }

    dict set outputs environment_evidence_path $evidence_path
    dict set outputs environment_evidence_hash \
        [::stage1d::source_check::sha256_file $evidence_path]
    dict set outputs observation_timestamp [dict get $evidence observation_timestamp]
    dict set outputs observation_source [dict get $evidence observation_source]

    foreach field {vivado_version sw_build ip_build part board_part} {
        if {[catch {
            _compare_identity $evidence $expected $field outputs
        } identity_error]} {
            return [_stop FAIL ENVIRONMENT_IDENTITY_MISMATCH ENVIRONMENT \
                $identity_error NONE $outputs]
        }
    }
    dict set outputs vivado_identity_verified 1
    dict set outputs target_identity_verified 1

    if {![dict get $evidence board_definition_available]} {
        return [_stop BLOCKED BOARD_DEFINITION_UNAVAILABLE ENVIRONMENT \
            {The required board definition is not available.} \
            INSTALL_BOARD_DEFINITION $outputs]
    }
    set board_definition_files [dict get $evidence board_definition_files]
    if {[llength $board_definition_files] == 0} {
        return [_stop BLOCKED BOARD_DEFINITION_EVIDENCE_MISSING ENVIRONMENT \
            {No board-definition files were recorded in environment evidence.} \
            PROVIDE_BOARD_EVIDENCE $outputs]
    }
    set normalized_board_files {}
    foreach board_file $board_definition_files {
        set normalized_board_file [file normalize $board_file]
        if {![file exists $normalized_board_file] || ![file isfile $normalized_board_file]} {
            dict set outputs board_definition_files $normalized_board_files
            return [_stop BLOCKED BOARD_DEFINITION_FILE_MISSING ENVIRONMENT \
                {A recorded board-definition file is unavailable.} \
                INSTALL_BOARD_DEFINITION $outputs]
        }
        lappend normalized_board_files $normalized_board_file
    }
    dict set outputs board_definition_available 1
    dict set outputs board_definition_files $normalized_board_files

    if {[catch {
        _resolve_ip_identities \
            [dict get $expected required_ip_patterns] \
            [dict get $evidence ip_identities]
    } ip_resolution]} {
        return [_stop FAIL IP_IDENTITY_EVIDENCE_INVALID ENVIRONMENT \
            $ip_resolution NONE $outputs]
    }
    dict set outputs observed_ip_identities [lsort -dictionary \
        [dict get $evidence ip_identities]]
    dict set outputs resolved_ip_identities [dict get $ip_resolution resolved]
    if {[llength [dict get $ip_resolution ambiguous]] > 0} {
        dict set outputs ambiguous_ip_identities [dict get $ip_resolution ambiguous]
        return [_stop FAIL AMBIGUOUS_IP_IDENTITY ENVIRONMENT \
            {A required IP pattern resolved to multiple VLNV identities.} NONE $outputs]
    }
    if {[llength [dict get $ip_resolution missing]] > 0} {
        dict set outputs missing_ip_identities [dict get $ip_resolution missing]
        return [_stop BLOCKED REQUIRED_IP_UNAVAILABLE ENVIRONMENT \
            {One or more required IP identities are unavailable.} \
            INSTALL_REQUIRED_IP $outputs]
    }
    dict set outputs required_ip_verified 1

    set custom_ip_identity [dict get $expected custom_protection_ip]
    if {[dict get $custom_ip_identity provenance_status] ne \
        {PENDING_PHASE3_RECONSTRUCTION}} {
        return [_stop FAIL CUSTOM_IP_PLACEHOLDER_INVALID PROVENANCE \
            {Custom protection IP provenance must remain pending until Phase 3 reconstruction.} \
            NONE $outputs]
    }
    dict set custom_ip_identity source_git_commit \
        [dict get $context source_verification git_commit]
    dict set custom_ip_identity packaged_ip_created 0
    dict set custom_ip_identity catalog_identity_verified 0
    dict set outputs custom_protection_ip_provenance $custom_ip_identity
    dict set outputs environment_verified 1

    set evidence_locations [linsert $normalized_board_files 0 $evidence_path]
    return [_result PASS $outputs {} $evidence_locations]
}

proc ::stage1d::environment_check::run {context} {
    set run_status [catch {_run $context} result run_options]
    if {$run_status == 0} {
        return $result
    }

    set underlying_error {}
    if {[dict exists $run_options -errorinfo]} {
        set underlying_error [dict get $run_options -errorinfo]
    }
    set error_record [_error_record \
        ENVIRONMENT_CHECK_INTERNAL_ERROR \
        CORE \
        "Unexpected environment verification error: $result" \
        NONE]
    dict set error_record underlying_error $underlying_error
    return [_result FAIL {} [list $error_record]]
}
