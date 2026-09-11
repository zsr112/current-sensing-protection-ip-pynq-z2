# Stage 1E Phase 3 runtime qualification framework v1.
#
# This module validates declarative observations and identity records only.
# It has no Vivado backend, performs no workspace mutation, consumes no
# authorization, and cannot execute implementation or downstream operations.

namespace eval ::stage1e::phase3_runtime_qualification {
    variable framework_schema_version \
        stage1e-phase3-runtime-qualification-framework-v1
    variable capability_schema_version \
        stage1e-vivado-implementation-capability-observation-v1
    variable workspace_schema_version \
        stage1e-phase3-workspace-launcher-observation-v1
    variable evidence_schema_version implementation_evidence_identity_v1
    variable evidence_plan_schema_version \
        stage1e-implementation-evidence-plan-identity-v1
    variable message_inventory_schema_version \
        stage1e-implementation-message-inventory-v1
    variable retry_guard_schema_version stage1e-phase3-runtime-retry-guard-v1
    variable context_schema_version \
        stage1e-phase3-runtime-qualification-context-v1
    variable result_schema_version \
        stage1e-phase3-runtime-qualification-result-v1
    variable qualification_evidence_schema_version \
        stage1e-phase3-runtime-qualification-evidence-identity-v1
    variable authorization_result_schema_version \
        stage1e-phase3-runtime-authorization-qualification-result-v1
    variable result_identity_fields {
        schema_version
        status
        execution_id
        capability_identity
        workspace_qualification_identity
        workspace_identity
        synthesis_result_identity
        evidence_plan_identity
        qualification_evidence_identity
        qualification_identity
        implementation_execution_authorized
        authorization_consumption_authorized
        artifact_authority
        board_authority
    }
    variable message_inventory_identity_fields {
        schema_version
        execution_id
        error_count
        critical_warning_count
        warning_count
        info_count
        unknown_identifier_count
        review_state
    }
}

proc ::stage1e::phase3_runtime_qualification::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E PHASE3_RUNTIME_QUALIFICATION $code] $message
}

proc ::stage1e::phase3_runtime_qualification::_require_dictionary {
    value
    label
} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise SCHEMA_INVALID "$label is not a dictionary: $dictionary_error"
    }
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_require_fields {
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
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_require_exact_fields {
    record
    fields
    label
} {
    _require_fields $record $fields $label
    set expected [lsort -dictionary $fields]
    set actual [lsort -dictionary [dict keys $record]]
    if {$expected ne $actual} {
        _raise SCHEMA_INVALID \
            "$label fields differ: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_require_equal {
    expected
    actual
    label
} {
    if {$expected ne $actual} {
        _raise IDENTITY_MISMATCH \
            "$label mismatch: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_require_exact_list {
    expected
    actual
    label
} {
    set expected [list {*}$expected]
    set actual [list {*}$actual]
    if {$expected ne $actual} {
        _raise SCHEMA_INVALID \
            "$label differs: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_require_sha256 {
    value
    label
} {
    set value [string tolower $value]
    if {![regexp {^[0-9a-f]{64}$} $value] ||
        $value eq [string repeat 0 64]} {
        _raise IDENTITY_INVALID \
            "$label is not a non-placeholder SHA-256 identity."
    }
    return $value
}

proc ::stage1e::phase3_runtime_qualification::_require_identity_value {
    value
    label
} {
    if {[string toupper $value] in {
        UNKNOWN MISSING STALE NOT_FROZEN NOT_PRODUCED NOT_APPLICABLE
    }} {
        _raise IDENTITY_INVALID "$label is a blocking identity value."
    }
    return [_require_sha256 $value $label]
}

proc ::stage1e::phase3_runtime_qualification::_require_positive_integer {
    value
    label
} {
    if {![regexp {^[1-9][0-9]*$} $value]} {
        _raise SCHEMA_INVALID "$label is not a positive canonical integer."
    }
    return $value
}

proc ::stage1e::phase3_runtime_qualification::_require_nonnegative_integer {
    value
    label
} {
    if {![regexp {^(0|[1-9][0-9]*)$} $value]} {
        _raise SCHEMA_INVALID \
            "$label is not a non-negative canonical integer."
    }
    return $value
}

proc ::stage1e::phase3_runtime_qualification::_require_dependencies {} {
    foreach command {
        ::stage1d::source_check::sha256_text
        ::stage1e::artifact_closure_schema::validate_framework
        ::stage1e::artifact_closure_schema::validate_qualification_identity
        ::stage1e::artifact_closure_schema::validate_authorization_binding
        ::stage1e::artifact_closure_schema::compute_identity
        ::stage1e::artifact_closure_schema::validate_provenance
        ::stage1e::phase3_implementation_controller::validate_framework
        ::stage1e::phase3_implementation_controller::_validate_predecessor
    } {
        if {![llength [info commands $command]]} {
            _raise DEPENDENCY_MISSING \
                "Required qualification dependency is unavailable: $command"
        }
    }
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_identity_payload {
    fields
    record
} {
    set payload {}
    foreach field $fields {
        if {![dict exists $record $field]} {
            _raise IDENTITY_INCOMPLETE \
                "Identity payload is missing field: $field"
        }
        append payload [list $field] {=} [list [dict get $record $field]] "\n"
    }
    return $payload
}

proc ::stage1e::phase3_runtime_qualification::compute_identity {
    fields
    record
} {
    if {![llength [info commands ::stage1d::source_check::sha256_text]]} {
        _raise DEPENDENCY_MISSING \
            {Stage 1D source-check SHA-256 provider is unavailable.}
    }
    return [::stage1d::source_check::sha256_text \
        [_identity_payload $fields $record]]
}

proc ::stage1e::phase3_runtime_qualification::_validate_identity_hash {
    fields
    record
    label
} {
    _require_fields $record {identity_sha256} $label
    set actual [_require_sha256 [dict get $record identity_sha256] \
        "$label identity_sha256"]
    set expected [compute_identity $fields $record]
    _require_equal $expected $actual "$label canonical identity"
    return $expected
}

proc ::stage1e::phase3_runtime_qualification::validate_framework {
    framework
} {
    variable framework_schema_version
    variable capability_schema_version
    variable workspace_schema_version
    variable evidence_schema_version
    _require_exact_fields $framework {
        schema_version
        framework_identity
        authorization_boundary
        qualification_contract
        capability_probe_contract
        workspace_launcher_contract
        implementation_evidence_contract
        authorization_runtime_contract
        identity_chain
        provenance_guard
        validation_contract
    } {Runtime qualification framework}
    _require_equal $framework_schema_version [dict get $framework \
        schema_version] {Runtime qualification framework schema}

    set identity [dict get $framework framework_identity]
    _require_exact_fields $identity {
        framework_id
        framework_status
        baseline_git_commit
        reference_synthesis_execution_id
        reference_synthesis_result_identity
        target
        part
        board_part
        vivado_version
        software_build
        ip_build
        implementation_run_name
        hash_algorithm
    } {Runtime qualification framework identity}
    _require_equal stage1e_phase3_runtime_qualification_v1 [dict get \
        $identity framework_id] {Runtime qualification framework identifier}
    _require_equal PREPARATION_ONLY [dict get $identity framework_status] \
        {Runtime qualification framework status}
    if {![regexp -nocase {^[0-9a-f]{40}$} [dict get $identity \
            baseline_git_commit]]} {
        _raise IDENTITY_INVALID \
            {Runtime qualification baseline is not a full Git commit.}
    }
    _require_sha256 [dict get $identity \
        reference_synthesis_result_identity] \
        {Reference synthesis result identity}
    _require_equal SHA256 [dict get $identity hash_algorithm] \
        {Runtime qualification hash algorithm}

    set boundary [dict get $framework authorization_boundary]
    _require_exact_fields $boundary {
        schema_version
        preparation_only
        observation_contract_only
        vivado_invocation_authorized
        capability_probe_execution_authorized
        workspace_creation_authorized
        launcher_execution_authorized
        implementation_execution_authorized
        authorization_consumption_authorized
        artifact_generation_authorized
        artifact_publication_authorized
        board_access_authorized
        declaration_is_permission
    } {Runtime qualification authorization boundary}
    foreach flag {preparation_only observation_contract_only} {
        _require_equal 1 [dict get $boundary $flag] \
            "Runtime qualification boundary $flag"
    }
    foreach flag {
        vivado_invocation_authorized
        capability_probe_execution_authorized
        workspace_creation_authorized
        launcher_execution_authorized
        implementation_execution_authorized
        authorization_consumption_authorized
        artifact_generation_authorized
        artifact_publication_authorized
        board_access_authorized
        declaration_is_permission
    } {
        _require_equal 0 [dict get $boundary $flag] \
            "Runtime qualification boundary $flag"
    }

    set qualification [dict get $framework qualification_contract]
    _require_exact_fields $qualification {
        schema_version
        context_schema
        result_schema
        qualification_identity_schema
        qualification_evidence_schema
        gate_order
        gates
        required_gate_status
        required_decision
        evidence_required_fields
        evidence_identity_fields
        missing_action
        stale_action
        mismatch_action
        unknown_action
    } {Runtime qualification contract}
    _require_exact_list {Q0 Q1 Q2 Q3 Q4 Q5} [dict get $qualification \
        gate_order] {Runtime qualification gate order}
    _require_exact_fields [dict get $qualification gates] \
        {Q0 Q1 Q2 Q3 Q4 Q5} {Runtime qualification gate definitions}
    foreach action {missing_action stale_action mismatch_action unknown_action} {
        _require_equal BLOCK [dict get $qualification $action] \
            "Runtime qualification $action"
    }

    set capability [dict get $framework capability_probe_contract]
    _require_exact_fields $capability {
        schema_version
        probe_mode
        probe_order
        probes
        required_fields
        identity_fields
        vivado_identity_contract
        license_contract
        run_contract
        missing_probe_action
        unavailable_command_action
        license_failure_action
        target_mismatch_action
        unknown_action
    } {Vivado capability probe contract}
    _require_equal $capability_schema_version [dict get $capability \
        schema_version] {Vivado capability observation schema}
    set probe_order {
        opt_design
        place_design
        route_design
        implementation_reports
        timing_reports
        drc_reports
        methodology_reports
    }
    _require_exact_list $probe_order [dict get $capability probe_order] \
        {Vivado capability probe order}
    _require_exact_fields [dict get $capability probes] $probe_order \
        {Vivado capability probes}
    foreach probe $probe_order {
        set definition [dict get $capability probes $probe]
        _require_exact_fields $definition {
            discovery_commands required_status mutation_allowed
        } "Vivado capability probe $probe"
        _require_equal PASS [dict get $definition required_status] \
            "Vivado capability probe status $probe"
        _require_equal 0 [dict get $definition mutation_allowed] \
            "Vivado capability probe mutation boundary $probe"
    }
    foreach action {
        missing_probe_action
        unavailable_command_action
        license_failure_action
        target_mismatch_action
        unknown_action
    } {
        _require_equal BLOCK [dict get $capability $action] \
            "Vivado capability $action"
    }

    set workspace [dict get $framework workspace_launcher_contract]
    _require_exact_fields $workspace {
        schema_version
        required_fields
        identity_fields
        check_order
        required_workspace_state
        workspace_existed_before
        prior_execution_state_present
        current_execution_owner
        path_budget_contract
        launcher_lifetime_contract
        observation_contract
        missing_action
        stale_action
        containment_failure_action
        reuse_action
        unknown_action
    } {Workspace and launcher contract}
    _require_equal $workspace_schema_version [dict get $workspace \
        schema_version] {Workspace observation schema}
    _require_exact_list {
        fresh_workspace ownership identity containment cwd xil_location
        path_budget launcher_lifetime child_process_observation
        dispatch_monitoring
    } [dict get $workspace check_order] \
        {Workspace qualification check order}
    foreach action {
        missing_action stale_action containment_failure_action reuse_action
        unknown_action
    } {
        _require_equal BLOCK [dict get $workspace $action] \
            "Workspace qualification $action"
    }

    set evidence [dict get $framework implementation_evidence_contract]
    _require_exact_fields $evidence {
        schema_version
        required_fields
        identity_fields
        role_fields
        required_log_roles
        required_report_roles
        message_inventory_schema
        message_inventory_fields
        required_hash_roles
        required_evidence_state
        required_decision
        entry_plan_contract
        runtime_identity_produced_at_entry
        missing_role_action
        missing_hash_action
        execution_mismatch_action
        unknown_action
    } {Implementation evidence contract}
    _require_equal $evidence_schema_version [dict get $evidence \
        schema_version] {Implementation evidence schema}
    _require_equal 0 [dict get $evidence runtime_identity_produced_at_entry] \
        {Implementation evidence entry-production boundary}
    foreach action {
        missing_role_action missing_hash_action execution_mismatch_action
        unknown_action
    } {
        _require_equal BLOCK [dict get $evidence $action] \
            "Implementation evidence $action"
    }

    set authorization [dict get $framework authorization_runtime_contract]
    _require_exact_fields $authorization {
        schema_version
        qualification_schema
        authorization_schema
        synthesis_schema
        required_status
        required_capability
        required_consume_state
        retry_guard_schema
        retry_guard_required_fields
        retry_guard_identity_fields
        missing_identity_action
        stale_identity_action
        wrong_execution_action
        consumed_authorization_action
        retry_reuse_action
        unknown_action
    } {Authorization runtime contract}
    _require_equal AUTHORIZED [dict get $authorization required_status] \
        {Runtime authorization status}
    _require_equal IMPLEMENTATION [dict get $authorization \
        required_capability] {Runtime authorization capability}
    _require_equal UNCONSUMED [dict get $authorization \
        required_consume_state] {Runtime authorization consume state}
    foreach action {
        missing_identity_action stale_identity_action wrong_execution_action
        consumed_authorization_action retry_reuse_action unknown_action
    } {
        _require_equal BLOCK [dict get $authorization $action] \
            "Runtime authorization $action"
    }

    set chain [dict get $framework identity_chain]
    _require_exact_fields $chain {
        schema_version
        order
        same_execution_required
        exact_workspace_required
        exact_synthesis_result_required
        authorization_must_be_unconsumed
        historical_synthesis_is_runtime_authority
        qualification_is_implementation_authority
        mismatch_action
    } {Runtime qualification identity chain}
    foreach flag {
        same_execution_required exact_workspace_required
        exact_synthesis_result_required authorization_must_be_unconsumed
    } {
        _require_equal 1 [dict get $chain $flag] \
            "Runtime qualification chain $flag"
    }
    foreach flag {
        historical_synthesis_is_runtime_authority
        qualification_is_implementation_authority
    } {
        _require_equal 0 [dict get $chain $flag] \
            "Runtime qualification chain $flag"
    }
    _require_equal BLOCK [dict get $chain mismatch_action] \
        {Runtime qualification identity mismatch action}

    set provenance [dict get $framework provenance_guard]
    _require_exact_fields $provenance {
        schema_version algorithm canonicalization sources missing_action
        mismatch_action
    } {Runtime qualification provenance guard}
    _require_equal SHA256 [dict get $provenance algorithm] \
        {Runtime qualification provenance algorithm}
    if {[dict size [dict get $provenance sources]] == 0} {
        _raise PROVENANCE_INCOMPLETE \
            {Runtime qualification provenance inventory is empty.}
    }
    dict for {path entry} [dict get $provenance sources] {
        _require_exact_fields $entry {role sha256} \
            "Runtime qualification provenance source $path"
        _require_sha256 [dict get $entry sha256] \
            "Runtime qualification provenance identity $path"
    }
    foreach action {missing_action mismatch_action} {
        _require_equal BLOCK [dict get $provenance $action] \
            "Runtime qualification provenance $action"
    }

    set validation [dict get $framework validation_contract]
    _require_exact_fields $validation {
        schema_version
        required_suites
        vivado_invocation_allowed
        implementation_execution_allowed
        artifact_generation_allowed
        board_access_allowed
        unknown_or_missing_identity_action
    } {Runtime qualification validation contract}
    foreach flag {
        vivado_invocation_allowed implementation_execution_allowed
        artifact_generation_allowed board_access_allowed
    } {
        _require_equal 0 [dict get $validation $flag] \
            "Runtime qualification validation $flag"
    }
    _require_equal BLOCK [dict get $validation \
        unknown_or_missing_identity_action] \
        {Runtime qualification unknown identity action}
    return 1
}

proc ::stage1e::phase3_runtime_qualification::validate_capability_observation {
    framework
    observation
} {
    variable capability_schema_version
    set contract [dict get $framework capability_probe_contract]
    _require_exact_fields $observation [dict get $contract required_fields] \
        {Vivado implementation capability observation}
    _require_equal $capability_schema_version [dict get $observation \
        schema_version] {Vivado capability observation schema}
    _require_equal OBSERVATION_ONLY [dict get $observation probe_mode] \
        {Vivado capability probe mode}
    if {[string trim [dict get $observation execution_id]] eq {} ||
        [string toupper [dict get $observation execution_id]] in {
            UNKNOWN MISSING STALE
        }} {
        _raise IDENTITY_INVALID \
            {Vivado capability execution_id is missing or blocking.}
    }
    set identity [dict get $framework framework_identity]
    _require_equal [dict get $identity part] [dict get $observation part] \
        {Vivado capability part}
    _require_equal [dict get $identity board_part] [dict get $observation \
        board_part] {Vivado capability board part}

    set vivado [dict get $observation vivado_identity]
    set vivado_contract [dict get $contract vivado_identity_contract]
    _require_exact_fields $vivado [dict get $vivado_contract required_fields] \
        {Vivado identity}
    _require_equal [dict get $vivado_contract schema_version] [dict get \
        $vivado schema_version] {Vivado identity schema}
    foreach field {vivado_version software_build ip_build} {
        _require_equal [dict get $identity $field] [dict get $vivado $field] \
            "Vivado identity $field"
    }
    foreach field {executable_identity evidence_identity} {
        _require_identity_value [dict get $vivado $field] \
            "Vivado identity $field"
    }

    set license [dict get $observation license_capability]
    set license_contract [dict get $contract license_contract]
    _require_exact_fields $license [dict get $license_contract \
        required_fields] {Implementation license capability}
    _require_equal [dict get $license_contract schema_version] [dict get \
        $license schema_version] {Implementation license schema}
    _require_equal PASS [dict get $license status] \
        {Implementation license status}
    _require_equal 1 [dict get $license implementation_feature_available] \
        {Implementation license feature availability}
    _require_identity_value [dict get $license evidence_identity] \
        {Implementation license evidence identity}

    set run [dict get $observation run_capability]
    set run_contract [dict get $contract run_contract]
    _require_exact_fields $run [dict get $run_contract required_fields] \
        {Implementation run capability}
    _require_equal [dict get $run_contract schema_version] [dict get $run \
        schema_version] {Implementation run capability schema}
    _require_equal PASS [dict get $run status] \
        {Implementation run capability status}
    _require_equal [dict get $identity implementation_run_name] [dict get \
        $run run_name] {Implementation run name}
    _require_exact_fields [dict get $run command_availability] [dict get \
        $run_contract required_commands] {Implementation run commands}
    dict for {command available} [dict get $run command_availability] {
        _require_equal 1 $available \
            "Implementation run command availability $command"
    }
    _require_equal 0 [dict get $run mutation_performed] \
        {Implementation run capability mutation boundary}
    _require_identity_value [dict get $run evidence_identity] \
        {Implementation run capability evidence identity}

    set probe_results [dict get $observation probe_results]
    _require_exact_fields $probe_results [dict get $contract probe_order] \
        {Vivado capability probe results}
    foreach probe [dict get $contract probe_order] {
        set result [dict get $probe_results $probe]
        _require_exact_fields $result {
            status command_availability mutation_performed evidence_identity
        } "Vivado capability probe result $probe"
        _require_equal PASS [dict get $result status] \
            "Vivado capability probe result $probe"
        set commands [dict get $contract probes $probe discovery_commands]
        _require_exact_fields [dict get $result command_availability] \
            $commands "Vivado capability commands $probe"
        dict for {command available} [dict get $result command_availability] {
            _require_equal 1 $available \
                "Vivado capability command $probe/$command"
        }
        _require_equal 0 [dict get $result mutation_performed] \
            "Vivado capability mutation boundary $probe"
        _require_identity_value [dict get $result evidence_identity] \
            "Vivado capability evidence $probe"
    }
    _require_identity_value [dict get $observation evidence_identity] \
        {Vivado capability evidence inventory identity}
    _require_equal PASS [dict get $observation decision] \
        {Vivado capability decision}
    _validate_identity_hash [dict get $contract identity_fields] \
        $observation {Vivado implementation capability observation}
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_canonical_components {path} {
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

proc ::stage1e::phase3_runtime_qualification::_path_is_descendant {
    candidate
    parent
} {
    set candidate [_canonical_components $candidate]
    set parent [_canonical_components $parent]
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

proc ::stage1e::phase3_runtime_qualification::_paths_equal {first second} {
    return [expr {[_canonical_components $first] eq \
        [_canonical_components $second]}]
}

proc ::stage1e::phase3_runtime_qualification::_paths_overlap {first second} {
    return [expr {[_path_is_descendant $first $second] ||
        [_path_is_descendant $second $first]}]
}

proc ::stage1e::phase3_runtime_qualification::_path_byte_length {path} {
    set normalized [string map {\\ /} [file normalize $path]]
    return [string length [encoding convertto utf-8 $normalized]]
}

proc ::stage1e::phase3_runtime_qualification::_validate_observation_check {
    contract
    observation
    label
} {
    _require_exact_fields $observation [dict get $contract required_fields] \
        $label
    _require_equal PASS [dict get $observation status] "$label status"
    _require_equal 1 [dict get $observation available] "$label availability"
    _require_identity_value [dict get $observation evidence_identity] \
        "$label evidence identity"
    return 1
}

proc ::stage1e::phase3_runtime_qualification::validate_workspace_observation {
    framework
    observation
} {
    variable workspace_schema_version
    set contract [dict get $framework workspace_launcher_contract]
    _require_exact_fields $observation [dict get $contract required_fields] \
        {Workspace and launcher observation}
    _require_equal $workspace_schema_version [dict get $observation \
        schema_version] {Workspace and launcher observation schema}
    set execution_id [dict get $observation execution_id]
    if {[string trim $execution_id] eq {} ||
        [string toupper $execution_id] in {UNKNOWN MISSING STALE}} {
        _raise IDENTITY_INVALID \
            {Workspace observation execution_id is missing or blocking.}
    }
    _require_positive_integer [dict get $observation retry_number] \
        {Workspace retry number}
    foreach field {workspace_identity ownership_identity evidence_identity} {
        _require_identity_value [dict get $observation $field] \
            "Workspace observation $field"
    }
    foreach field {
        workspace_path repository_root artifact_storage_root launcher_cwd
        xil_root
    } {
        set path [dict get $observation $field]
        if {[file pathtype $path] ne {absolute}} {
            _raise CONTAINMENT_INVALID \
                "Workspace observation $field is not absolute: $path"
        }
    }
    set workspace_path [dict get $observation workspace_path]
    set repository_root [dict get $observation repository_root]
    set artifact_root [dict get $observation artifact_storage_root]
    if {[_paths_overlap $workspace_path $repository_root] ||
        [_paths_overlap $workspace_path $artifact_root]} {
        _raise CONTAINMENT_INVALID \
            {Execution workspace overlaps the repository or artifact root.}
    }
    _require_equal 1 [_paths_equal $workspace_path [dict get $observation \
        launcher_cwd]] {Launcher working directory}
    set expected_xil [file normalize [file join $workspace_path .Xil]]
    _require_equal 1 [_paths_equal $expected_xil [dict get $observation \
        xil_root]] {Launcher .Xil location}
    _require_equal [dict get $contract required_workspace_state] [dict get \
        $observation workspace_state] {Workspace state}
    foreach field {
        workspace_existed_before prior_execution_state_present
    } {
        _require_equal 0 [dict get $observation $field] \
            "Workspace freshness $field"
    }
    _require_equal 1 [dict get $observation current_execution_owner] \
        {Workspace current-execution ownership}

    set budget [dict get $observation path_budget]
    set budget_contract [dict get $contract path_budget_contract]
    _require_exact_fields $budget [dict get $budget_contract required_fields] \
        {Workspace path budget}
    _require_equal PASS [dict get $budget status] {Workspace path budget status}
    foreach field {
        workspace_path_bytes longest_reviewed_path_bytes safety_margin_bytes
        max_usable_bytes
    } {
        _require_positive_integer [dict get $budget $field] \
            "Workspace path budget $field"
    }
    _require_equal [_path_byte_length $workspace_path] [dict get $budget \
        workspace_path_bytes] {Workspace path byte count}
    if {[dict get $budget safety_margin_bytes] < [dict get $budget_contract \
            minimum_safety_margin_bytes] ||
        [dict get $budget max_usable_bytes] > [dict get $budget_contract \
            maximum_usable_bytes] ||
        [dict get $budget longest_reviewed_path_bytes] +
            [dict get $budget safety_margin_bytes] >
            [dict get $budget max_usable_bytes]} {
        _raise PATH_BUDGET_INVALID \
            {Workspace path budget does not preserve the required margin.}
    }

    set lifetime [dict get $observation launcher_lifetime]
    set lifetime_contract [dict get $contract launcher_lifetime_contract]
    _require_exact_fields $lifetime [dict get $lifetime_contract \
        required_fields] {Launcher lifetime}
    _require_equal PASS [dict get $lifetime status] {Launcher lifetime status}
    foreach field {controller_budget_minutes launcher_lifetime_minutes} {
        _require_positive_integer [dict get $lifetime $field] \
            "Launcher lifetime $field"
    }
    if {[dict get $lifetime launcher_lifetime_minutes] <=
        [dict get $lifetime controller_budget_minutes]} {
        _raise LAUNCHER_LIFETIME_INVALID \
            {Launcher lifetime does not exceed the controller budget.}
    }
    set observation_contract [dict get $contract observation_contract]
    foreach field {child_process_observation dispatch_monitoring} {
        _validate_observation_check $observation_contract [dict get \
            $observation $field] "Workspace $field"
    }
    set results [dict get $observation check_results]
    _require_exact_fields $results [dict get $contract check_order] \
        {Workspace qualification check results}
    dict for {check status} $results {
        _require_equal PASS $status "Workspace qualification check $check"
    }
    _require_equal PASS [dict get $observation decision] \
        {Workspace qualification decision}
    _validate_identity_hash [dict get $contract identity_fields] \
        $observation {Workspace and launcher observation}
    return 1
}

proc ::stage1e::phase3_runtime_qualification::validate_evidence_plan {
    framework
    plan
} {
    variable evidence_plan_schema_version
    set evidence [dict get $framework implementation_evidence_contract]
    set contract [dict get $evidence entry_plan_contract]
    _require_exact_fields $plan [dict get $contract required_fields] \
        {Implementation evidence plan}
    _require_equal $evidence_plan_schema_version [dict get $plan \
        schema_version] {Implementation evidence plan schema}
    foreach field {workspace_identity evidence_root_identity} {
        _require_identity_value [dict get $plan $field] \
            "Implementation evidence plan $field"
    }
    _require_exact_list [dict get $evidence required_log_roles] [dict get \
        $plan log_roles] {Implementation evidence-plan log roles}
    _require_exact_list [dict get $evidence required_report_roles] [dict get \
        $plan report_roles] {Implementation evidence-plan report roles}
    _require_equal MESSAGE_INVENTORY [dict get $plan \
        message_inventory_role] {Implementation evidence message role}
    _require_exact_list [dict get $evidence required_hash_roles] [dict get \
        $plan hash_roles] {Implementation evidence-plan hash roles}
    _require_equal 1 [dict get $plan current_execution_only] \
        {Implementation evidence-plan execution scope}
    _require_equal 0 [dict get $plan prior_outputs_present] \
        {Implementation evidence-plan prior outputs}
    _require_equal 1 [dict get $plan paths_contained] \
        {Implementation evidence-plan containment}
    _require_equal PASS [dict get $plan decision] \
        {Implementation evidence-plan decision}
    _validate_identity_hash [dict get $contract identity_fields] $plan \
        {Implementation evidence plan}
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_validate_evidence_roles {
    roles
    expected_roles
    role_fields
    execution_id
    label
} {
    _require_exact_fields $roles $expected_roles $label
    foreach role $expected_roles {
        set entry [dict get $roles $role]
        _require_exact_fields $entry $role_fields "$label role $role"
        _require_equal $execution_id [dict get $entry execution_id] \
            "$label execution binding $role"
        _require_equal PHASE3_IMPLEMENTATION [dict get $entry \
            producer_phase] "$label producer phase $role"
        _require_identity_value [dict get $entry path_identity] \
            "$label path identity $role"
        _require_positive_integer [dict get $entry size] "$label size $role"
        _require_identity_value [dict get $entry sha256] "$label hash $role"
    }
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_validate_message_inventory {
    framework
    inventory
    execution_id
} {
    variable message_inventory_schema_version
    variable message_inventory_identity_fields
    set contract [dict get $framework implementation_evidence_contract]
    _require_exact_fields $inventory [dict get $contract \
        message_inventory_fields] {Implementation message inventory}
    _require_equal $message_inventory_schema_version [dict get $inventory \
        schema_version] {Implementation message inventory schema}
    _require_equal $execution_id [dict get $inventory execution_id] \
        {Implementation message inventory execution binding}
    foreach field {
        error_count critical_warning_count warning_count info_count
        unknown_identifier_count
    } {
        _require_nonnegative_integer [dict get $inventory $field] \
            "Implementation message inventory $field"
    }
    foreach field {error_count critical_warning_count unknown_identifier_count} {
        _require_equal 0 [dict get $inventory $field] \
            "Implementation message acceptance $field"
    }
    _require_equal REVIEWED [dict get $inventory review_state] \
        {Implementation message review state}
    _validate_identity_hash $message_inventory_identity_fields $inventory \
        {Implementation message inventory}
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_evidence_set_digest {record} {
    set hashes [dict get $record hashes]
    set payload [list \
        [dict get $record execution_id] \
        [dict get $record workspace_identity] \
        [dict get $record synthesis_result_identity] \
        [dict get $record implementation_run_identity] \
        [dict get $record authorization_consumption_identity] \
        [dict get $hashes logs_identity] \
        [dict get $hashes reports_identity] \
        [dict get $hashes message_inventory_identity]]
    return [::stage1d::source_check::sha256_text $payload]
}

proc ::stage1e::phase3_runtime_qualification::validate_implementation_evidence_identity {
    framework
    record
} {
    variable evidence_schema_version
    set contract [dict get $framework implementation_evidence_contract]
    _require_exact_fields $record [dict get $contract required_fields] \
        {Implementation evidence identity}
    _require_equal $evidence_schema_version [dict get $record \
        schema_version] {Implementation evidence identity schema}
    set execution_id [dict get $record execution_id]
    if {[string trim $execution_id] eq {}} {
        _raise IDENTITY_INVALID \
            {Implementation evidence execution_id is empty.}
    }
    foreach field {
        workspace_identity synthesis_result_identity implementation_run_identity
        authorization_consumption_identity
    } {
        _require_identity_value [dict get $record $field] \
            "Implementation evidence $field"
    }
    _validate_evidence_roles [dict get $record logs] [dict get $contract \
        required_log_roles] [dict get $contract role_fields] $execution_id \
        {Implementation logs}
    _validate_evidence_roles [dict get $record reports] [dict get $contract \
        required_report_roles] [dict get $contract role_fields] $execution_id \
        {Implementation reports}
    _validate_message_inventory $framework [dict get $record \
        message_inventory] $execution_id
    set hashes [dict get $record hashes]
    _require_exact_fields $hashes [dict get $contract required_hash_roles] \
        {Implementation evidence hashes}
    dict for {role value} $hashes {
        _require_identity_value $value "Implementation evidence hash $role"
    }
    _require_equal [::stage1d::source_check::sha256_text [dict get $record \
        logs]] [dict get $hashes logs_identity] \
        {Implementation logs identity}
    _require_equal [::stage1d::source_check::sha256_text [dict get $record \
        reports]] [dict get $hashes reports_identity] \
        {Implementation reports identity}
    _require_equal [dict get $record message_inventory identity_sha256] \
        [dict get $hashes message_inventory_identity] \
        {Implementation message inventory identity}
    _require_equal [_evidence_set_digest $record] [dict get $hashes \
        evidence_set_digest] {Implementation evidence-set digest}
    _require_equal [dict get $contract required_evidence_state] [dict get \
        $record evidence_state] {Implementation evidence state}
    _require_equal [dict get $contract required_decision] [dict get $record \
        decision] {Implementation evidence decision}
    _validate_identity_hash [dict get $contract identity_fields] $record \
        {Implementation evidence identity}
    return 1
}

proc ::stage1e::phase3_runtime_qualification::validate_retry_guard {
    framework
    guard
} {
    variable retry_guard_schema_version
    set contract [dict get $framework authorization_runtime_contract]
    _require_exact_fields $guard [dict get $contract \
        retry_guard_required_fields] {Runtime retry guard}
    _require_equal $retry_guard_schema_version [dict get $guard \
        schema_version] {Runtime retry guard schema}
    set execution_id [dict get $guard execution_id]
    if {[string trim $execution_id] eq {} ||
        [string toupper $execution_id] in {UNKNOWN MISSING STALE}} {
        _raise IDENTITY_INVALID {Retry-guard execution_id is blocking.}
    }
    _require_positive_integer [dict get $guard retry_number] \
        {Retry-guard retry number}
    set prior_execution [dict get $guard prior_execution_id]
    if {$prior_execution ne {NONE} && $prior_execution eq $execution_id} {
        _raise RETRY_REUSE \
            {Retry guard reuses the current execution identifier.}
    }
    set prior_authorization [dict get $guard prior_authorization_identity]
    if {$prior_authorization ne {NONE}} {
        _require_identity_value $prior_authorization \
            {Retry-guard prior authorization identity}
    }
    foreach field {
        authorization_reuse_requested workspace_reuse_requested
        checkpoint_reuse_requested generated_output_reuse_requested
    } {
        _require_equal 0 [dict get $guard $field] "Retry guard $field"
    }
    _require_equal PASS [dict get $guard decision] {Retry-guard decision}
    _validate_identity_hash [dict get $contract retry_guard_identity_fields] \
        $guard {Runtime retry guard}
    return 1
}

proc ::stage1e::phase3_runtime_qualification::_validate_gate_evidence {
    framework
    gate_evidence
    bindings
} {
    set contract [dict get $framework qualification_contract]
    set gate_order [dict get $contract gate_order]
    _require_exact_fields $gate_evidence $gate_order \
        {Runtime qualification gate evidence}
    foreach gate $gate_order {
        set entry [dict get $gate_evidence $gate]
        _require_exact_fields $entry {status evidence_identity} \
            "Runtime qualification gate evidence $gate"
        _require_equal PASS [dict get $entry status] \
            "Runtime qualification gate status $gate"
        _require_identity_value [dict get $entry evidence_identity] \
            "Runtime qualification gate identity $gate"
        _require_equal [dict get $bindings $gate] [dict get $entry \
            evidence_identity] "Runtime qualification gate binding $gate"
    }
    return 1
}

proc ::stage1e::phase3_runtime_qualification::compose_qualification_candidate {
    artifact_framework
    implementation_framework
    runtime_framework
    context
} {
    variable context_schema_version
    variable result_schema_version
    variable result_identity_fields
    variable qualification_evidence_schema_version
    _require_dependencies
    validate_framework $runtime_framework
    ::stage1e::artifact_closure_schema::validate_framework $artifact_framework
    ::stage1e::phase3_implementation_controller::validate_framework \
        $implementation_framework
    _require_exact_fields $context {
        schema_version
        execution_id
        source_identity
        plan_contract_identity
        capability_observation
        workspace_observation
        synthesis_predecessor
        evidence_plan
        authorization_preparation_identity
        gate_evidence
        retry_guard
    } {Runtime qualification context}
    _require_equal $context_schema_version [dict get $context schema_version] \
        {Runtime qualification context schema}
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {} ||
        [string toupper $execution_id] in {UNKNOWN MISSING STALE}} {
        _raise IDENTITY_INVALID \
            {Runtime qualification execution_id is missing or blocking.}
    }
    foreach field {
        source_identity plan_contract_identity authorization_preparation_identity
    } {
        dict set context $field [_require_identity_value [dict get $context \
            $field] "Runtime qualification $field"]
    }
    set plan_path docs/design/stage1f_runtime_qualification_plan.md
    _require_equal [dict get $runtime_framework provenance_guard sources \
        $plan_path sha256] [dict get $context plan_contract_identity] \
        {Runtime qualification plan identity}

    set capability [dict get $context capability_observation]
    set workspace [dict get $context workspace_observation]
    set plan [dict get $context evidence_plan]
    set retry [dict get $context retry_guard]
    validate_capability_observation $runtime_framework $capability
    validate_workspace_observation $runtime_framework $workspace
    validate_evidence_plan $runtime_framework $plan
    validate_retry_guard $runtime_framework $retry
    foreach record [list $capability $workspace $plan $retry] {
        _require_equal $execution_id [dict get $record execution_id] \
            {Runtime qualification same-execution binding}
    }
    _require_equal [dict get $workspace workspace_identity] [dict get $plan \
        workspace_identity] {Evidence-plan workspace binding}

    set predecessor [dict get $context synthesis_predecessor]
    set synthesis_identity [string tolower [dict get $predecessor \
        identity_sha256]]
    set reference_identity [string tolower [dict get $runtime_framework \
        framework_identity reference_synthesis_result_identity]]
    if {$synthesis_identity eq $reference_identity} {
        _raise HISTORICAL_PREDECESSOR \
            {Reference synthesis identity cannot be runtime predecessor state.}
    }
    ::stage1e::phase3_implementation_controller::_validate_predecessor \
        $implementation_framework $predecessor $execution_id \
        [dict get $context source_identity] $synthesis_identity

    set bindings [dict create \
        Q0 [dict get $context plan_contract_identity] \
        Q1 [dict get $context source_identity] \
        Q2 [dict get $capability identity_sha256] \
        Q3 [dict get $workspace identity_sha256] \
        Q4 $synthesis_identity \
        Q5 [dict get $context authorization_preparation_identity]]
    _validate_gate_evidence $runtime_framework [dict get $context \
        gate_evidence] $bindings

    set evidence_contract [dict get $runtime_framework \
        qualification_contract]
    set evidence [dict create \
        schema_version $qualification_evidence_schema_version \
        execution_id $execution_id \
        source_identity [dict get $context source_identity] \
        plan_contract_identity [dict get $context plan_contract_identity] \
        capability_identity [dict get $capability identity_sha256] \
        workspace_qualification_identity [dict get $workspace \
            identity_sha256] \
        workspace_identity [dict get $workspace workspace_identity] \
        synthesis_result_identity $synthesis_identity \
        evidence_plan_identity [dict get $plan identity_sha256] \
        authorization_preparation_identity [dict get $context \
            authorization_preparation_identity] \
        gate_evidence [dict get $context gate_evidence] \
        retry_guard_identity [dict get $retry identity_sha256] \
        decision PASS]
    dict set evidence identity_sha256 [compute_identity [dict get \
        $evidence_contract evidence_identity_fields] $evidence]
    _require_exact_fields $evidence [dict get $evidence_contract \
        evidence_required_fields] {Runtime qualification evidence identity}

    set gate_results [dict create]
    foreach gate [dict get $evidence_contract gate_order] {
        dict set gate_results $gate [dict get $context gate_evidence $gate \
            status]
    }
    set qualification_contract [dict get $artifact_framework \
        qualification_contract]
    set qualification [dict create \
        schema_version qualification_identity_v1 \
        execution_identity $execution_id \
        workspace_identity [dict get $workspace workspace_identity] \
        environment_identity [dict get $capability identity_sha256] \
        source_identity [dict get $context source_identity] \
        synthesis_result_identity $synthesis_identity \
        gate_results $gate_results \
        evidence_identity [dict get $evidence identity_sha256] \
        decision PASS]
    dict set qualification identity_sha256 \
        [::stage1e::artifact_closure_schema::compute_identity \
            $qualification_contract $qualification]
    ::stage1e::artifact_closure_schema::validate_qualification_identity \
        $artifact_framework $qualification

    set result [dict create \
        schema_version $result_schema_version \
        status QUALIFIED_NOT_AUTHORIZED \
        execution_id $execution_id \
        capability_identity [dict get $capability identity_sha256] \
        workspace_qualification_identity [dict get $workspace \
            identity_sha256] \
        workspace_identity [dict get $workspace workspace_identity] \
        synthesis_result_identity $synthesis_identity \
        evidence_plan_identity [dict get $plan identity_sha256] \
        qualification_evidence_identity [dict get $evidence \
            identity_sha256] \
        qualification_identity $qualification \
        implementation_execution_authorized 0 \
        authorization_consumption_authorized 0 \
        artifact_authority NONE \
        board_authority NONE]
    dict set result identity_sha256 \
        [compute_identity $result_identity_fields $result]
    return $result
}

proc ::stage1e::phase3_runtime_qualification::validate_qualification_result {
    artifact_framework
    result
} {
    variable result_schema_version
    variable result_identity_fields
    _require_exact_fields $result [linsert $result_identity_fields 1 \
        identity_sha256] {Runtime qualification result}
    _require_equal $result_schema_version [dict get $result schema_version] \
        {Runtime qualification result schema}
    _require_equal QUALIFIED_NOT_AUTHORIZED [dict get $result status] \
        {Runtime qualification result status}
    foreach field {
        identity_sha256 capability_identity workspace_qualification_identity
        workspace_identity synthesis_result_identity evidence_plan_identity
        qualification_evidence_identity
    } {
        _require_identity_value [dict get $result $field] \
            "Runtime qualification result $field"
    }
    ::stage1e::artifact_closure_schema::validate_qualification_identity \
        $artifact_framework [dict get $result qualification_identity]
    _require_equal [dict get $result execution_id] [dict get $result \
        qualification_identity execution_identity] \
        {Runtime qualification result execution binding}
    foreach flag {
        implementation_execution_authorized authorization_consumption_authorized
    } {
        _require_equal 0 [dict get $result $flag] \
            "Runtime qualification result $flag"
    }
    foreach field {artifact_authority board_authority} {
        _require_equal NONE [dict get $result $field] \
            "Runtime qualification result $field"
    }
    _validate_identity_hash $result_identity_fields $result \
        {Runtime qualification result}
    return 1
}

proc ::stage1e::phase3_runtime_qualification::validate_authorization_runtime {
    artifact_framework
    implementation_framework
    runtime_framework
    qualification_result
    authorization
    synthesis_predecessor
    workspace_observation
    retry_guard
} {
    variable authorization_result_schema_version
    _require_dependencies
    validate_framework $runtime_framework
    validate_qualification_result $artifact_framework $qualification_result
    validate_workspace_observation $runtime_framework $workspace_observation
    validate_retry_guard $runtime_framework $retry_guard
    set qualification [dict get $qualification_result qualification_identity]
    ::stage1e::artifact_closure_schema::validate_authorization_binding \
        $artifact_framework $qualification $authorization
    set execution_id [dict get $qualification execution_identity]
    _require_equal $execution_id [dict get $workspace_observation \
        execution_id] {Authorization workspace execution binding}
    _require_equal $execution_id [dict get $retry_guard execution_id] \
        {Authorization retry-guard execution binding}
    _require_equal [dict get $qualification_result \
        workspace_qualification_identity] [dict get $workspace_observation \
        identity_sha256] {Authorization workspace qualification binding}
    _require_equal [dict get $qualification workspace_identity] [dict get \
        $workspace_observation workspace_identity] \
        {Authorization workspace identity binding}
    ::stage1e::phase3_implementation_controller::_validate_predecessor \
        $implementation_framework $synthesis_predecessor $execution_id \
        [dict get $qualification source_identity] [dict get $qualification \
        synthesis_result_identity]
    return [dict create \
        schema_version $authorization_result_schema_version \
        status RUNTIME_INPUTS_QUALIFIED_NOT_CONSUMED \
        execution_id $execution_id \
        qualification_identity [dict get $qualification identity_sha256] \
        implementation_authorization_identity [dict get $authorization \
            identity_sha256] \
        synthesis_result_identity [dict get $qualification \
            synthesis_result_identity] \
        workspace_identity [dict get $qualification workspace_identity] \
        authorization_consume_state UNCONSUMED \
        implementation_execution_permitted 0 \
        artifact_authority NONE \
        board_authority NONE]
}

proc ::stage1e::phase3_runtime_qualification::validate_provenance {
    repository_root
    framework
} {
    _require_dependencies
    validate_framework $framework
    return [::stage1e::artifact_closure_schema::validate_provenance \
        $repository_root $framework]
}

