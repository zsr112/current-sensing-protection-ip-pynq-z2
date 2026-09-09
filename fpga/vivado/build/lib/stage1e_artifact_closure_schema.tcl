# Source-only schema and fail-closed validators for the Stage 1E Artifact
# Closure Framework v1. This module performs no Vivado, implementation,
# artifact-generation, publication, or board operation.

namespace eval ::stage1e::artifact_closure_schema {
    variable framework_schema_version stage1e-artifact-closure-framework-v1
    variable qualification_schema_version qualification_identity_v1
    variable authorization_schema_version \
        stage1e-implementation-authorization-binding-v1
    variable implementation_result_schema_version \
        stage1e-implementation-result-identity-v1
    variable artifact_candidate_schema_version \
        stage1e-artifact-candidate-identity-v1
    variable acceptance_schema_version stage1e-artifact-acceptance-result-v1
}

proc ::stage1e::artifact_closure_schema::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E ARTIFACT_CLOSURE_FRAMEWORK $code] $message
}

proc ::stage1e::artifact_closure_schema::read_dictionary {path} {
    if {![file isfile $path]} {
        _raise FILE_MISSING "Dictionary file is unavailable: $path"
    }
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} contents read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $contents
    }
    if {$close_status != 0} {
        _raise FILE_READ_FAILED "Unable to close dictionary file: $close_error"
    }
    if {[catch {dict size $contents} dictionary_error]} {
        _raise SCHEMA_INVALID \
            "File is not a declarative Tcl dictionary: $dictionary_error"
    }
    return $contents
}

proc ::stage1e::artifact_closure_schema::_require_dictionary {
    value
    label
} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise SCHEMA_INVALID "$label is not a dictionary: $dictionary_error"
    }
}

proc ::stage1e::artifact_closure_schema::_require_fields {
    record
    fields
    label
} {
    _require_dictionary $record $label
    foreach field $fields {
        if {![dict exists $record $field]} {
            _raise IDENTITY_INCOMPLETE "$label is missing field: $field"
        }
        if {[dict get $record $field] eq {}} {
            _raise IDENTITY_INCOMPLETE "$label has an empty field: $field"
        }
    }
}

proc ::stage1e::artifact_closure_schema::_require_exact_fields {
    record
    fields
    label
} {
    _require_fields $record $fields $label
    set actual [lsort -dictionary [dict keys $record]]
    set expected [lsort -dictionary $fields]
    if {$actual ne $expected} {
        _raise SCHEMA_INVALID \
            "$label fields differ: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::artifact_closure_schema::_require_equal {
    expected
    actual
    label
} {
    if {$expected ne $actual} {
        _raise IDENTITY_MISMATCH \
            "$label mismatch: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::artifact_closure_schema::_require_sha256 {value label} {
    if {![regexp -nocase {^[0-9a-f]{64}$} $value]} {
        _raise IDENTITY_INVALID "$label is not a SHA-256 identity."
    }
    set upper [string toupper $value]
    if {$upper in {UNKNOWN NOT_FROZEN NOT_PRODUCED NOT_APPLICABLE}} {
        _raise IDENTITY_INVALID "$label is a blocking placeholder."
    }
}

proc ::stage1e::artifact_closure_schema::_require_git_commit {value label} {
    if {![regexp -nocase {^[0-9a-f]{40}$} $value]} {
        _raise IDENTITY_INVALID "$label is not a full Git commit identity."
    }
}

proc ::stage1e::artifact_closure_schema::_require_identity_value {
    value
    label
} {
    if {[string toupper $value] in {
        UNKNOWN
        MISSING
        STALE
        NOT_FROZEN
        NOT_PRODUCED
        NOT_APPLICABLE
    }} {
        _raise IDENTITY_INVALID "$label is a blocking identity value."
    }
    _require_sha256 $value $label
}

proc ::stage1e::artifact_closure_schema::_require_schema {
    record
    expected
    label
} {
    _require_fields $record {schema_version} $label
    _require_equal $expected [dict get $record schema_version] \
        "$label schema_version"
}

proc ::stage1e::artifact_closure_schema::_contract {
    framework
    contract_name
} {
    if {![dict exists $framework $contract_name]} {
        _raise SCHEMA_INVALID "Framework lacks contract: $contract_name"
    }
    set contract [dict get $framework $contract_name]
    _require_dictionary $contract "Framework contract $contract_name"
    return $contract
}

proc ::stage1e::artifact_closure_schema::_identity_payload {
    contract
    record
} {
    _require_fields $contract {identity_fields} {Identity contract}
    set payload {}
    foreach field [dict get $contract identity_fields] {
        if {![dict exists $record $field]} {
            _raise IDENTITY_INCOMPLETE \
                "Identity payload is missing field: $field"
        }
        append payload [list $field] {=} [list [dict get $record $field]] "\n"
    }
    return $payload
}

proc ::stage1e::artifact_closure_schema::compute_identity {
    contract
    record
} {
    if {![llength [info commands ::stage1d::source_check::sha256_text]]} {
        _raise HASH_PROVIDER_MISSING \
            {Stage 1D source_check SHA-256 provider is unavailable.}
    }
    return [::stage1d::source_check::sha256_text \
        [_identity_payload $contract $record]]
}

proc ::stage1e::artifact_closure_schema::_validate_identity_hash {
    contract
    record
    label
} {
    _require_fields $record {identity_sha256} $label
    _require_sha256 [dict get $record identity_sha256] \
        "$label identity_sha256"
    set computed [compute_identity $contract $record]
    _require_equal $computed [string tolower \
        [dict get $record identity_sha256]] "$label canonical identity"
    return $computed
}

proc ::stage1e::artifact_closure_schema::_require_exact_list {
    expected
    actual
    label
} {
    if {$expected ne $actual} {
        _raise SCHEMA_INVALID \
            "$label differs: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::artifact_closure_schema::validate_framework {framework} {
    variable framework_schema_version
    variable qualification_schema_version
    variable authorization_schema_version
    variable implementation_result_schema_version
    variable artifact_candidate_schema_version
    variable acceptance_schema_version

    set required_sections {
        schema_version
        framework_identity
        authorization_boundary
        qualification_contract
        implementation_authorization_contract
        implementation_result_contract
        artifact_candidate_contract
        artifact_acceptance_contract
        identity_chain
        provenance_guard
        validation_contract
    }
    _require_exact_fields $framework $required_sections {Framework}
    _require_equal $framework_schema_version \
        [dict get $framework schema_version] {Framework schema_version}

    set identity [dict get $framework framework_identity]
    _require_exact_fields $identity {
        framework_id
        framework_status
        baseline_git_commit
        reference_synthesis_result_identity
        target
        part
        board_part
        vivado_version
        software_build
        ip_build
        hash_algorithm
    } {Framework identity}
    _require_equal stage1e_artifact_closure_framework_v1 \
        [dict get $identity framework_id] {Framework identifier}
    _require_equal PREPARATION_ONLY [dict get $identity framework_status] \
        {Framework status}
    _require_git_commit [dict get $identity baseline_git_commit] \
        {Framework baseline Git commit}
    _require_sha256 [dict get $identity reference_synthesis_result_identity] \
        {Reference synthesis result identity}
    _require_equal SHA256 [dict get $identity hash_algorithm] \
        {Framework hash algorithm}

    set boundary [dict get $framework authorization_boundary]
    _require_exact_fields $boundary {
        schema_version
        preparation_only
        declaration_is_permission
        implementation_execution_authorized
        artifact_collection_authorized
        artifact_publication_authorized
        board_access_authorized
        missing_or_unknown_identity_action
    } {Authorization boundary}
    foreach flag {
        declaration_is_permission
        implementation_execution_authorized
        artifact_collection_authorized
        artifact_publication_authorized
        board_access_authorized
    } {
        _require_equal 0 [dict get $boundary $flag] \
            "Authorization boundary $flag"
    }
    _require_equal 1 [dict get $boundary preparation_only] \
        {Authorization boundary preparation_only}
    _require_equal BLOCK [dict get $boundary \
        missing_or_unknown_identity_action] \
        {Unknown identity authorization action}

    set qualification [_contract $framework qualification_contract]
    _require_equal $qualification_schema_version \
        [dict get $qualification schema_version] \
        {Qualification contract schema}
    set gate_order {Q0 Q1 Q2 Q3 Q4 Q5}
    _require_exact_list $gate_order [dict get $qualification gate_order] \
        {Qualification gate order}
    set gates [dict get $qualification gates]
    _require_exact_fields $gates $gate_order {Qualification gates}
    foreach gate $gate_order {
        _require_exact_fields [dict get $gates $gate] \
            {name required_status blocking_on_nonpass} \
            "Qualification gate $gate"
        _require_equal PASS [dict get $gates $gate required_status] \
            "Qualification gate $gate required status"
        _require_equal 1 [dict get $gates $gate blocking_on_nonpass] \
            "Qualification gate $gate blocking policy"
    }
    foreach action {
        missing_identity_action
        stale_identity_action
        mismatch_action
        unknown_identity_action
    } {
        _require_equal BLOCK [dict get $qualification $action] \
            "Qualification $action"
    }

    set authorization [_contract $framework \
        implementation_authorization_contract]
    _require_equal $authorization_schema_version \
        [dict get $authorization schema_version] \
        {Implementation authorization schema}
    _require_equal IMPLEMENTATION [dict get $authorization \
        required_capability] {Implementation authorization capability}
    _require_equal AUTHORIZED [dict get $authorization required_status] \
        {Implementation authorization status}
    _require_equal UNCONSUMED [dict get $authorization \
        required_consume_state] {Implementation authorization consume state}

    set implementation [_contract $framework implementation_result_contract]
    _require_equal $implementation_result_schema_version \
        [dict get $implementation schema_version] \
        {Implementation result contract schema}
    _require_equal CANDIDATE [dict get $implementation \
        required_acceptance_state] {Implementation acceptance state}

    set candidate [_contract $framework artifact_candidate_contract]
    _require_equal $artifact_candidate_schema_version \
        [dict get $candidate schema_version] \
        {Artifact candidate contract schema}
    _require_equal PHASE4_ARTIFACT_CLOSURE [dict get $candidate \
        required_producer_phase] {Artifact candidate producer phase}
    _require_equal NON_ACCEPTED_CANDIDATE [dict get $candidate \
        identity_state] {Artifact candidate state}

    set acceptance [_contract $framework artifact_acceptance_contract]
    _require_equal $acceptance_schema_version \
        [dict get $acceptance schema_version] \
        {Artifact acceptance contract schema}
    foreach field {
        manifest_verification
        hash_verification
        atomic_publication
        stage1e_artifact_closure_decision
    } {
        _require_equal PASS [dict get $acceptance required_results $field] \
            "Artifact acceptance $field"
    }

    set chain [dict get $framework identity_chain]
    _require_exact_list {
        implementation_result_identity
        artifact_candidate_identity
        artifact_set_digest
    } [dict get $chain order] {Artifact identity chain}
    _require_equal 0 [dict get $chain \
        candidate_identity_means_acceptance] \
        {Artifact candidate acceptance boundary}

    set provenance [dict get $framework provenance_guard]
    _require_fields $provenance {
        schema_version
        algorithm
        sources
        missing_action
        mismatch_action
    } {Provenance guard}
    _require_equal SHA256 [dict get $provenance algorithm] \
        {Provenance hash algorithm}
    if {[dict size [dict get $provenance sources]] == 0} {
        _raise PROVENANCE_INCOMPLETE \
            {Provenance source inventory is empty.}
    }
    _require_equal BLOCK [dict get $provenance missing_action] \
        {Provenance missing action}
    _require_equal BLOCK [dict get $provenance mismatch_action] \
        {Provenance mismatch action}

    set validation [dict get $framework validation_contract]
    _require_fields $validation {
        schema_version
        required_suites
        unknown_or_missing_identity_action
        vivado_invocation_allowed
        implementation_allowed
        artifact_generation_allowed
    } {Validation contract}
    foreach flag {
        vivado_invocation_allowed
        implementation_allowed
        artifact_generation_allowed
    } {
        _require_equal 0 [dict get $validation $flag] \
            "Validation contract $flag"
    }
    _require_equal BLOCK [dict get $validation \
        unknown_or_missing_identity_action] \
        {Validation unknown identity action}
    return 1
}

proc ::stage1e::artifact_closure_schema::validate_qualification_identity {
    framework
    identity
} {
    variable qualification_schema_version
    set contract [_contract $framework qualification_contract]
    set fields [dict get $contract required_fields]
    _require_exact_fields $identity $fields {Qualification identity}
    _require_schema $identity $qualification_schema_version \
        {Qualification identity}

    foreach field {
        workspace_identity
        environment_identity
        source_identity
        synthesis_result_identity
        evidence_identity
    } {
        _require_identity_value [dict get $identity $field] \
            "Qualification $field"
    }
    set execution_id [dict get $identity execution_identity]
    if {[string trim $execution_id] eq {} ||
        [string toupper $execution_id] in {UNKNOWN MISSING STALE}} {
        _raise IDENTITY_INVALID \
            {Qualification execution_identity is missing or blocking.}
    }

    set expected_gates [dict get $contract gate_order]
    set results [dict get $identity gate_results]
    _require_exact_fields $results $expected_gates \
        {Qualification gate results}
    foreach gate $expected_gates {
        _require_equal PASS [dict get $results $gate] \
            "Qualification result $gate"
    }
    _require_equal PASS [dict get $identity decision] \
        {Qualification decision}
    _validate_identity_hash $contract $identity {Qualification identity}
    return 1
}

proc ::stage1e::artifact_closure_schema::validate_authorization_binding {
    framework
    qualification
    authorization
} {
    variable authorization_schema_version
    validate_qualification_identity $framework $qualification
    set contract [_contract $framework \
        implementation_authorization_contract]
    set fields [dict get $contract required_fields]
    _require_exact_fields $authorization $fields \
        {Implementation authorization}
    _require_schema $authorization $authorization_schema_version \
        {Implementation authorization}
    _require_equal [dict get $contract required_status] \
        [dict get $authorization status] {Authorization status}
    _require_equal [dict get $contract required_capability] \
        [dict get $authorization capability] {Authorization capability}
    _require_equal [dict get $contract required_consume_state] \
        [dict get $authorization consume_state] \
        {Authorization consume state}

    set binding_map {
        qualification_identity identity_sha256
        execution_identity execution_identity
        workspace_identity workspace_identity
        environment_identity environment_identity
        source_identity source_identity
        synthesis_result_identity synthesis_result_identity
    }
    foreach {authorization_field qualification_field} $binding_map {
        _require_equal [dict get $qualification $qualification_field] \
            [dict get $authorization $authorization_field] \
            "Authorization binding $authorization_field"
    }
    foreach field {
        authorization_identity
        qualification_identity
        workspace_identity
        environment_identity
        source_identity
        synthesis_result_identity
    } {
        _require_identity_value [dict get $authorization $field] \
            "Authorization $field"
    }
    _validate_identity_hash $contract $authorization \
        {Implementation authorization}
    return 1
}

proc ::stage1e::artifact_closure_schema::validate_implementation_result {
    framework
    result
} {
    variable implementation_result_schema_version
    set contract [_contract $framework implementation_result_contract]
    set fields [dict get $contract required_fields]
    _require_exact_fields $result $fields {Implementation result identity}
    _require_schema $result $implementation_result_schema_version \
        {Implementation result identity}
    if {[string trim [dict get $result execution_id]] eq {}} {
        _raise IDENTITY_INVALID {Implementation execution_id is empty.}
    }
    foreach field {
        source_identity
        synthesis_result_identity
        implementation_run_identity
        implementation_policy_identity
        timing_report_identity
        utilization_report_identity
        drc_identity
        methodology_identity
        checkpoint_identity
    } {
        _require_identity_value [dict get $result $field] \
            "Implementation result $field"
    }
    _require_equal [dict get $contract required_acceptance_state] \
        [dict get $result acceptance_state] \
        {Implementation result acceptance_state}
    _validate_identity_hash $contract $result \
        {Implementation result identity}
    return 1
}

proc ::stage1e::artifact_closure_schema::_validate_artifact_roles {
    contract
    candidate
} {
    set roles [dict get $candidate artifact_roles]
    set required_roles [dict get $contract required_artifact_roles]
    _require_exact_fields $roles $required_roles {Artifact roles}
    set required_fields [dict get $contract required_role_fields]
    set allowed_phases [dict get $contract allowed_role_producer_phases]
    foreach role_name $required_roles {
        set role [dict get $roles $role_name]
        _require_exact_fields $role $required_fields \
            "Artifact role $role_name"
        _require_equal $role_name [dict get $role logical_role] \
            "Artifact role $role_name logical_role"
        if {[dict get $role producer_phase] ni $allowed_phases} {
            _raise PROVENANCE_MISMATCH \
                "Artifact role $role_name has an invalid producer phase."
        }
        _require_equal [dict get $candidate execution_id] \
            [dict get $role execution_id] \
            "Artifact role $role_name execution_id"
        _require_equal CANDIDATE [dict get $role collection_state] \
            "Artifact role $role_name collection_state"
        set size [dict get $role size]
        if {![string is integer -strict $size] || $size < 0} {
            _raise SCHEMA_INVALID \
                "Artifact role $role_name has an invalid size."
        }
        _require_sha256 [dict get $role sha256] \
            "Artifact role $role_name sha256"
    }
}

proc ::stage1e::artifact_closure_schema::validate_artifact_candidate {
    framework
    implementation_result
    candidate
} {
    variable artifact_candidate_schema_version
    validate_implementation_result $framework $implementation_result
    set contract [_contract $framework artifact_candidate_contract]
    set fields [dict get $contract required_fields]
    _require_exact_fields $candidate $fields {Artifact candidate identity}
    _require_schema $candidate $artifact_candidate_schema_version \
        {Artifact candidate identity}
    _require_equal [dict get $implementation_result execution_id] \
        [dict get $candidate execution_id] \
        {Artifact candidate execution_id}
    _require_equal [dict get $implementation_result identity_sha256] \
        [dict get $candidate implementation_result_identity] \
        {Artifact candidate implementation_result_identity}
    _require_equal [dict get $implementation_result \
        implementation_run_identity] \
        [dict get $candidate implementation_run_identity] \
        {Artifact candidate implementation_run_identity}
    _require_equal [dict get $implementation_result source_identity] \
        [dict get $candidate source_identity] \
        {Artifact candidate source_identity}
    _require_equal [dict get $contract required_producer_phase] \
        [dict get $candidate producer_phase] \
        {Artifact candidate producer_phase}
    _require_equal [dict get $contract identity_state] \
        [dict get $candidate identity_state] \
        {Artifact candidate identity_state}

    foreach field {
        implementation_result_identity
        implementation_run_identity
        source_identity
        environment_identity
        workspace_identity
        manifest_identity
    } {
        _require_identity_value [dict get $candidate $field] \
            "Artifact candidate $field"
    }

    set provenance [dict get $candidate provenance_bindings]
    set provenance_fields [dict get $contract required_provenance_fields]
    _require_exact_fields $provenance $provenance_fields \
        {Artifact candidate provenance bindings}
    foreach field {
        execution_id
        source_identity
        environment_identity
        workspace_identity
        implementation_result_identity
        implementation_run_identity
    } {
        _require_equal [dict get $candidate $field] \
            [dict get $provenance $field] \
            "Artifact candidate provenance $field"
    }
    _require_equal [dict get $implementation_result synthesis_result_identity] \
        [dict get $provenance synthesis_result_identity] \
        {Artifact candidate provenance synthesis_result_identity}
    _validate_artifact_roles $contract $candidate
    _validate_identity_hash $contract $candidate \
        {Artifact candidate identity}
    return 1
}

proc ::stage1e::artifact_closure_schema::validate_identity_chain {
    framework
    qualification
    implementation_result
    candidate
} {
    validate_qualification_identity $framework $qualification
    validate_artifact_candidate $framework $implementation_result $candidate
    _require_equal [dict get $qualification execution_identity] \
        [dict get $implementation_result execution_id] \
        {Qualification-to-implementation execution identity}
    _require_equal [dict get $qualification source_identity] \
        [dict get $implementation_result source_identity] \
        {Qualification-to-implementation source identity}
    _require_equal [dict get $qualification synthesis_result_identity] \
        [dict get $implementation_result synthesis_result_identity] \
        {Qualification-to-implementation synthesis identity}
    _require_equal [dict get $qualification workspace_identity] \
        [dict get $candidate workspace_identity] \
        {Qualification-to-candidate workspace identity}
    _require_equal [dict get $qualification environment_identity] \
        [dict get $candidate environment_identity] \
        {Qualification-to-candidate environment identity}
    return 1
}

proc ::stage1e::artifact_closure_schema::validate_artifact_acceptance {
    framework
    candidate
    acceptance
} {
    variable acceptance_schema_version
    set contract [_contract $framework artifact_acceptance_contract]
    set fields [dict get $contract required_fields]
    _require_exact_fields $acceptance $fields {Artifact acceptance result}
    _require_schema $acceptance $acceptance_schema_version \
        {Artifact acceptance result}
    _require_equal [dict get $candidate identity_sha256] \
        [dict get $acceptance artifact_candidate_identity] \
        {Artifact acceptance candidate identity}
    foreach {field required} [dict get $contract required_results] {
        _require_equal $required [dict get $acceptance $field] \
            "Artifact acceptance $field"
    }
    _require_sha256 [dict get $acceptance artifact_candidate_identity] \
        {Artifact acceptance candidate identity}
    _require_sha256 [dict get $acceptance artifact_set_digest] \
        {Artifact set digest}
    return 1
}

proc ::stage1e::artifact_closure_schema::_path_is_descendant {
    candidate
    parent
} {
    set candidate_parts [file split [file normalize $candidate]]
    set parent_parts [file split [file normalize $parent]]
    if {[llength $candidate_parts] < [llength $parent_parts]} {
        return 0
    }
    for {set index 0} {$index < [llength $parent_parts]} {incr index} {
        set left [lindex $candidate_parts $index]
        set right [lindex $parent_parts $index]
        if {$::tcl_platform(platform) eq {windows}} {
            set left [string tolower $left]
            set right [string tolower $right]
        }
        if {$left ne $right} {
            return 0
        }
    }
    return 1
}

proc ::stage1e::artifact_closure_schema::validate_provenance {
    repository_root
    framework
} {
    if {![llength [info commands ::stage1d::source_check::sha256_file]]} {
        _raise HASH_PROVIDER_MISSING \
            {Stage 1D source_check file SHA-256 provider is unavailable.}
    }
    set guard [dict get $framework provenance_guard]
    set sources [dict get $guard sources]
    dict for {relative_path entry} $sources {
        _require_exact_fields $entry {role sha256} \
            "Provenance source $relative_path"
        if {[file pathtype $relative_path] ne {relative}} {
            _raise PROVENANCE_MISMATCH \
                "Provenance path is not repository-relative: $relative_path"
        }
        set absolute_path [file normalize \
            [file join $repository_root $relative_path]]
        if {![_path_is_descendant $absolute_path $repository_root]} {
            _raise PROVENANCE_MISMATCH \
                "Provenance path escapes the repository: $relative_path"
        }
        if {![file isfile $absolute_path]} {
            _raise PROVENANCE_MISSING \
                "Provenance source is unavailable: $relative_path"
        }
        set expected [string tolower [dict get $entry sha256]]
        _require_sha256 $expected "Provenance SHA-256 $relative_path"
        set actual [::stage1d::source_check::sha256_file $absolute_path]
        _require_equal $expected $actual \
            "Provenance source SHA-256 $relative_path"
    }
    return 1
}
