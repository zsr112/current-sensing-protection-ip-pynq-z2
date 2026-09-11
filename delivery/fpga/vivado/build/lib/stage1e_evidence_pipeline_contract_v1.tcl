# Stage 1E PRT02-D evidence-pipeline structural contract v1.
#
# This module owns exact structural validation and delegates canonical JSON
# encoding and no-overwrite publication to the admitted PRT02-A providers.
# It does not issue report commands, create identities, disposition findings,
# decide implementation acceptance, or create a result candidate.

set ::stage1e_evidence_contract_lib_dir [file dirname [info script]]
if {![llength [info commands ::stage1e::canonical_json_v1::canonical_bytes]]} {
    source [file join $::stage1e_evidence_contract_lib_dir \
        stage1e_runtime_canonical_json_v1.tcl]
}
if {![llength [info commands ::stage1e::atomic_publication_v1::publish]]} {
    source [file join $::stage1e_evidence_contract_lib_dir \
        stage1e_runtime_atomic_publication_v1.tcl]
}
if {![llength [info commands ::stage1e::vivado_runtime_contract_v1::validate_handoff]]} {
    source [file join $::stage1e_evidence_contract_lib_dir \
        stage1e_vivado_runtime_contract_v1.tcl]
}

namespace eval ::stage1e::evidence_pipeline_contract_v1 {
    variable interface_version stage1e-evidence-pipeline-common-interface-v1
    variable library_directory $::stage1e_evidence_contract_lib_dir
    variable build_root [file dirname $::stage1e_evidence_contract_lib_dir]
    variable report_contract {}
    variable message_contract {}
    variable format_profiles_contract {}
    variable record_contract {}
}
unset ::stage1e_evidence_contract_lib_dir

proc ::stage1e::evidence_pipeline_contract_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::evidence_pipeline_contract_v1::_raise {code message} {
    return -code error -errorcode [list STAGE1E EVIDENCE $code] $message
}

proc ::stage1e::evidence_pipeline_contract_v1::require_dictionary {
    value label
} {
    if {[catch {dict size $value}]} {
        _raise RECORD_INVALID "$label must be a Tcl dictionary."
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::require_unique_key_list {
    value label
} {
    if {[catch {set length [llength $value]}] || $length % 2 != 0} {
        _raise RECORD_INVALID "$label must be an alternating key/value list."
    }
    set seen {}
    foreach {key ignored} $value {
        if {[dict exists $seen $key]} {
            _raise DUPLICATE_CONTRACT_KEY \
                "$label contains duplicate key '$key'."
        }
        dict set seen $key 1
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::_raw_key_value {
    value key label
} {
    require_unique_key_list $value $label
    foreach {observed nested} $value {
        if {$observed eq $key} { return $nested }
    }
    _raise CONTRACT_KEY_MISSING "$label is missing key '$key'."
}

proc ::stage1e::evidence_pipeline_contract_v1::validate_raw_contract_keys {
    contract_kind value
} {
    require_unique_key_list $value "$contract_kind contract"
    switch -- $contract_kind {
        REPORT {
            set roles [_raw_key_value $value roles {REPORT contract}]
            require_unique_key_list $roles {REPORT roles dictionary}
            foreach {role definition} $roles {
                require_unique_key_list $definition "REPORT role $role"
            }
            set conditional [_raw_key_value $value conditional_roles \
                {REPORT contract}]
            require_unique_key_list $conditional \
                {REPORT conditional-role dictionary}
            foreach {role definition} $conditional {
                require_unique_key_list $definition \
                    "REPORT conditional role $role"
            }
            require_unique_key_list \
                [_raw_key_value $value continuation_policy {REPORT contract}] \
                {REPORT continuation policy}
            require_unique_key_list \
                [_raw_key_value $value authority_boundary {REPORT contract}] \
                {REPORT authority boundary}
        }
        MESSAGE {
            require_unique_key_list \
                [_raw_key_value $value known_fixture_identifiers \
                    {MESSAGE contract}] \
                {MESSAGE known fixture identifiers}
            require_unique_key_list \
                [_raw_key_value $value authority_boundary {MESSAGE contract}] \
                {MESSAGE authority boundary}
        }
        PROFILES {
            set profiles [_raw_key_value $value profiles \
                {Parser profiles contract}]
            require_unique_key_list $profiles {Parser profile dictionary}
            foreach {name definition} $profiles {
                require_unique_key_list $definition "Parser profile $name"
            }
            require_unique_key_list \
                [_raw_key_value $value profile_match \
                    {Parser profiles contract}] \
                {Parser profile-match contract}
        }
        RECORDS {
            require_unique_key_list \
                [_raw_key_value $value interface_versions \
                    {Evidence record contract}] \
                {Evidence interface-version dictionary}
            set records [_raw_key_value $value records \
                {Evidence record contract}]
            require_unique_key_list $records {Evidence record dictionary}
            foreach {name definition} $records {
                require_unique_key_list $definition \
                    "Evidence record definition $name"
                require_unique_key_list \
                    [_raw_key_value $definition types \
                        "Evidence record definition $name"] \
                    "Evidence record type map $name"
            }
            require_unique_key_list \
                [_raw_key_value $value enums {Evidence record contract}] \
                {Evidence enum dictionary}
            require_unique_key_list \
                [_raw_key_value $value policy_stop {Evidence record contract}] \
                {Evidence policy-stop dictionary}
        }
        default {
            _raise CONTRACT_KIND_INVALID \
                "Unknown raw contract kind '$contract_kind'."
        }
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::require_exact_fields {
    value fields label
} {
    require_dictionary $value $label
    set actual [lsort [dict keys $value]]
    set expected [lsort $fields]
    if {$actual ne $expected} {
        _raise FIELD_SET_MISMATCH \
            "$label fields differ: expected {$expected}, observed {$actual}."
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::require_equal {
    expected actual label
} {
    if {$expected ne $actual} {
        _raise VALUE_MISMATCH \
            "$label differs: expected '$expected', observed '$actual'."
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::require_one_of {
    value allowed label
} {
    if {[lsearch -exact $allowed $value] < 0} {
        _raise ENUM_INVALID \
            "$label '$value' is outside the closed set {$allowed}."
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::require_nonempty {
    value label
} {
    if {$value eq {}} { _raise VALUE_EMPTY "$label must not be empty." }
    if {[string first "\u0000" $value] >= 0} {
        _raise VALUE_INVALID "$label contains an embedded NUL."
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::require_sha256 {value label} {
    if {![::stage1e::canonical_json_v1::is_sha256 $value]} {
        _raise SHA256_INVALID "$label is not a lowercase SHA-256 observation."
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::read_dictionary {path} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise CONTRACT_MISSING "Contract file is missing: $path"
    }
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation lf
    try {
        set value [string trim [read $channel]]
    } finally {
        close $channel
    }
    set tail [file tail $path]
    switch -- $tail {
        stage1e_report_contract_v1.dict { set kind REPORT }
        stage1e_message_contract_v1.dict { set kind MESSAGE }
        stage1e_parser_format_profiles_v1.dict { set kind PROFILES }
        stage1e_evidence_record_contract_v1.dict { set kind RECORDS }
        default {
            _raise CONTRACT_KIND_INVALID \
                "Unrecognized evidence contract filename '$tail'."
        }
    }
    validate_raw_contract_keys $kind $value
    require_dictionary $value "Contract $tail"
    return $value
}

proc ::stage1e::evidence_pipeline_contract_v1::authority_none {} {
    return [dict create \
        qualification_decision NONE \
        authorization_issue NONE \
        authorization_consumption NOT_OWNED \
        engineering_acceptance NONE \
        implementation_result_candidate NONE \
        artifact NONE \
        publication NONE \
        hardware_manager NONE \
        board_access NONE]
}

proc ::stage1e::evidence_pipeline_contract_v1::integrity_observation {
    subject_role binding integrity_state {bytes {}}
} {
    if {[dict exists $binding producer_session_reference]} {
        set session [dict get $binding producer_session_reference]
    } elseif {[dict exists $binding producer_session \
            producer_session_reference]} {
        set session [dict get $binding producer_session \
            producer_session_reference]
    } else {
        _raise INTEGRITY_BINDING_INVALID \
            {Integrity binding lacks a producer-session reference.}
    }
    if {$integrity_state eq {VERIFIED_SHA256}} {
        set byte_count [string length $bytes]
        set digest [::stage1e::canonical_json_v1::digest_bytes $bytes]
    } elseif {$integrity_state in \
            {UNAVAILABLE_WITH_REASON NOT_APPLICABLE}} {
        set byte_count -1
        set digest $integrity_state
    } else {
        _raise INTEGRITY_STATE_INVALID \
            "Unknown integrity state '$integrity_state'."
    }
    set observation [dict create \
        schema_version stage1e-content-integrity-observation-v1 \
        subject_role $subject_role \
        request_identity [dict get $binding request_identity] \
        execution_id [dict get $binding execution_id] \
        attempt_id [dict get $binding attempt_id] \
        workspace_identity [dict get $binding workspace_identity] \
        producer_session_reference $session \
        integrity_state $integrity_state byte_count $byte_count \
        content_sha256 $digest]
    validate_record content_integrity_observation $observation
    return $observation
}

proc ::stage1e::evidence_pipeline_contract_v1::validate_authority {
    authority
} {
    validate_record evidence_authority_boundary $authority
    foreach {field expected} {
        qualification_decision NONE
        authorization_issue NONE
        authorization_consumption NOT_OWNED
        engineering_acceptance NONE
        implementation_result_candidate NONE
        artifact NONE
        publication NONE
        hardware_manager NONE
        board_access NONE
    } {
        require_equal $expected [dict get $authority $field] \
            "Evidence authority $field"
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::_validate_report_contract {
    contract
} {
    require_exact_fields $contract {
        schema_version contract_state vivado_version qualification_state
        role_order role_fields roles conditional_roles attempt_states
        continuation_policy authority_boundary
    } {REPORT contract}
    foreach {field expected} {
        schema_version stage1e-production-report-contract-v1
        contract_state PRODUCTION_CANDIDATE_REVIEW_REQUIRED
        vivado_version 2024.1
        qualification_state ACTUAL_VIVADO_REPORT_COMMANDS_NOT_QUALIFIED
    } {
        require_equal $expected [dict get $contract $field] \
            "REPORT contract $field"
    }
    set expected_fields [dict get $contract role_fields]
    set roles [dict get $contract roles]
    set order [dict get $contract role_order]
    if {[llength $order] != 20 || [llength [lsort -unique $order]] != 20} {
        _raise REPORT_CONTRACT_INVALID \
            {REPORT role order must contain exactly twenty unique roles.}
    }
    set ordinal 0
    foreach role $order {
        incr ordinal
        if {![dict exists $roles $role]} {
            _raise REPORT_CONTRACT_INVALID "REPORT role is missing: $role"
        }
        set definition [dict get $roles $role]
        require_exact_fields $definition $expected_fields \
            "REPORT role $role"
        require_equal $ordinal [dict get $definition ordinal] \
            "REPORT role $role ordinal"
        require_equal NONE [dict get $definition authority_boundary] \
            "REPORT role $role authority"
        require_one_of [dict get $definition requirement_state] \
            {REQUIRED CONDITIONAL ADOPTED_REQUIRED FAILURE_SAFE_ONLY} \
            "REPORT role $role requirement state"
        if {[dict get $definition acquisition_owner] eq {COLLECTOR}} {
            require_nonempty [dict get $definition command_facade_role] \
                "REPORT role $role command facade"
            require_nonempty [dict get $definition command_name] \
                "REPORT role $role command name"
        } else {
            require_equal NONE [dict get $definition command_facade_role] \
                "Adopted REPORT role $role command facade"
            require_equal NONE [dict get $definition command_name] \
                "Adopted REPORT role $role command name"
        }
    }
    require_exact_fields $roles $order {REPORT role dictionary}
    set conditional [dict get $contract conditional_roles]
    require_exact_fields $conditional {CONDITIONAL_BUS_SKEW} \
        {REPORT conditional roles}
    set bus [dict get $conditional CONDITIONAL_BUS_SKEW]
    require_exact_fields $bus {
        owner states unknown_action collector_inference parser_inference
    } {Conditional bus-skew contract}
    foreach {field expected} {
        owner CONTROLLER_CONFIGURATION_INPUT
        unknown_action BLOCK
        collector_inference PROHIBITED
        parser_inference PROHIBITED
    } {
        require_equal $expected [dict get $bus $field] \
            "Conditional bus-skew $field"
    }
    require_equal {REQUIRED NOT_REQUIRED CONDITION_UNKNOWN} \
        [dict get $bus states] {Conditional bus-skew state order}
    set observed_states [list {*}[dict get $contract attempt_states]]
    set expected_states [list NOT_ATTEMPTED STARTED COLLECTED FAILED MISSING \
        BLOCKED UNAVAILABLE_FOR_STATE INTERRUPTED]
    if {$observed_states ne $expected_states} {
        _raise REPORT_CONTRACT_INVALID \
            {REPORT attempt-state order differs from the frozen contract.}
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::_validate_message_contract {
    contract
} {
    require_exact_fields $contract {
        schema_version contract_state qualification_state severity_order
        grouping_key unknown_identifier_action unknown_value_rule conflict_rule
        known_fixture_identifiers message_fields drc_fields
        methodology_fields timing_fields clock_cdc_fields
        timing_exception_fields utilization_fields authority_boundary
    } {MESSAGE contract}
    foreach {field expected} {
        schema_version stage1e-production-message-contract-v1
        contract_state PRODUCTION_CANDIDATE_REVIEW_REQUIRED
        qualification_state ACTUAL_VIVADO_REPORT_FORMATS_NOT_QUALIFIED
        unknown_identifier_action UNKNOWN_IDENTIFIER
        unknown_value_rule UNKNOWN_NEVER_ZERO
        conflict_rule PRESERVE_ALL_AND_BLOCK
    } {
        require_equal $expected [dict get $contract $field] \
            "MESSAGE contract $field"
    }
    require_equal {INFO WARNING CRITICAL_WARNING ERROR UNKNOWN} \
        [dict get $contract severity_order] {MESSAGE severity order}
    require_dictionary [dict get $contract known_fixture_identifiers] \
        {Known fixture identifiers}
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::_validate_profiles_contract {
    contract
} {
    require_exact_fields $contract {
        schema_version contract_state qualification_state parser_interface
        common_header common_end_marker encoding line_endings locale
        numeric_contract profiles terminal_states profile_match
    } {Parser profiles contract}
    foreach {field expected} {
        schema_version stage1e-parser-format-profiles-contract-v1
        contract_state FIXTURE_PROFILE_ONLY
        qualification_state VIVADO_2024_1_FORMAT_QUALIFICATION_REQUIRED
        parser_interface stage1e-production-evidence-parser-interface-v1
        common_header STAGE1E_EVIDENCE_FIXTURE_V1
        common_end_marker END_STAGE1E_EVIDENCE_FIXTURE_V1
        encoding UTF-8
        line_endings LF
        locale INVARIANT
    } {
        require_equal $expected [dict get $contract $field] \
            "Parser profiles $field"
    }
    set profiles [dict get $contract profiles]
    set observed {}
    foreach {name definition} $profiles {
        require_exact_fields $definition {
            ordinal role record_kinds signature qualification_state
            vivado_qualification
        } "Parser profile $name"
        lappend observed [list [dict get $definition ordinal] $name]
        require_equal FIXTURE_PROFILE_ONLY \
            [dict get $definition qualification_state] \
            "Parser profile $name fixture state"
        require_equal VIVADO_2024_1_FORMAT_QUALIFICATION_REQUIRED \
            [dict get $definition vivado_qualification] \
            "Parser profile $name Vivado state"
    }
    set ordinal 0
    foreach pair [lsort -integer -index 0 $observed] {
        incr ordinal
        require_equal $ordinal [lindex $pair 0] \
            {Parser profile ordinal sequence}
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::_validate_record_contract {
    contract
} {
    require_exact_fields $contract {
        schema_version contract_state canonical_json_interface
        atomic_publication_interface interface_versions records enums
        policy_stop
    } {Evidence record contract}
    foreach {field expected} {
        schema_version stage1e-evidence-record-contract-v1
        contract_state PRODUCTION_CANDIDATE_REVIEW_REQUIRED
        canonical_json_interface stage1e-runtime-canonical-json-interface-v1
        atomic_publication_interface stage1e-runtime-atomic-publication-interface-v1
    } {
        require_equal $expected [dict get $contract $field] \
            "Evidence record contract $field"
    }
    require_exact_fields [dict get $contract interface_versions] {
        common collector parser serializer controller adapter
    } {Evidence interface versions}
    set records [dict get $contract records]
    foreach {name definition} $records {
        require_exact_fields $definition {owner fields types} \
            "Evidence record definition $name"
        set fields [dict get $definition fields]
        set types [dict get $definition types]
        require_exact_fields $types $fields \
            "Evidence record type map $name"
        if {[llength $fields] != [llength [lsort -unique $fields]]} {
            _raise RECORD_CONTRACT_INVALID \
                "Evidence record $name contains duplicate fields."
        }
        foreach field $fields {
            set type [dict get $types $field]
            if {$type in {string integer dictionary string_list}} {
                continue
            }
            if {[string match {record:*} $type]} {
                set target [string range $type 7 end]
            } elseif {[string match {record_list:*} $type]} {
                set target [string range $type 12 end]
            } else {
                _raise RECORD_CONTRACT_INVALID \
                    "Evidence record $name has unsupported type '$type'."
            }
            if {![dict exists $records $target]} {
                _raise RECORD_CONTRACT_INVALID \
                    "Evidence record $name references missing type '$target'."
            }
        }
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::_initialize {} {
    variable build_root
    variable report_contract
    variable message_contract
    variable format_profiles_contract
    variable record_contract
    set config [file join $build_root config]
    set report_contract [read_dictionary \
        [file join $config stage1e_report_contract_v1.dict]]
    set message_contract [read_dictionary \
        [file join $config stage1e_message_contract_v1.dict]]
    set format_profiles_contract [read_dictionary \
        [file join $config stage1e_parser_format_profiles_v1.dict]]
    set record_contract [read_dictionary \
        [file join $config stage1e_evidence_record_contract_v1.dict]]
    _validate_report_contract $report_contract
    _validate_message_contract $message_contract
    _validate_profiles_contract $format_profiles_contract
    _validate_record_contract $record_contract
}

proc ::stage1e::evidence_pipeline_contract_v1::report_contract {} {
    variable report_contract
    return $report_contract
}

proc ::stage1e::evidence_pipeline_contract_v1::message_contract {} {
    variable message_contract
    return $message_contract
}

proc ::stage1e::evidence_pipeline_contract_v1::format_profiles_contract {} {
    variable format_profiles_contract
    return $format_profiles_contract
}

proc ::stage1e::evidence_pipeline_contract_v1::record_contract {} {
    variable record_contract
    return $record_contract
}

proc ::stage1e::evidence_pipeline_contract_v1::role_order {} {
    variable report_contract
    return [dict get $report_contract role_order]
}

proc ::stage1e::evidence_pipeline_contract_v1::role_definition {role} {
    variable report_contract
    if {![dict exists $report_contract roles $role]} {
        _raise REPORT_ROLE_UNKNOWN "Unknown REPORT role '$role'."
    }
    return [dict get $report_contract roles $role]
}

proc ::stage1e::evidence_pipeline_contract_v1::adopted_roles {} {
    set result {}
    foreach role [role_order] {
        if {[dict get [role_definition $role] acquisition_owner] ne {COLLECTOR}} {
            lappend result $role
        }
    }
    return $result
}

proc ::stage1e::evidence_pipeline_contract_v1::collector_roles {} {
    set result {}
    foreach role [role_order] {
        if {[dict get [role_definition $role] acquisition_owner] eq {COLLECTOR}} {
            lappend result $role
        }
    }
    return $result
}

proc ::stage1e::evidence_pipeline_contract_v1::profile_definition {name} {
    variable format_profiles_contract
    if {![dict exists $format_profiles_contract profiles $name]} {
        _raise PROFILE_UNSUPPORTED "Unknown parser format profile '$name'."
    }
    return [dict get $format_profiles_contract profiles $name]
}

proc ::stage1e::evidence_pipeline_contract_v1::record_definition {name} {
    variable record_contract
    if {![dict exists $record_contract records $name]} {
        _raise RECORD_TYPE_UNKNOWN "Unknown evidence record type '$name'."
    }
    return [dict get $record_contract records $name]
}

proc ::stage1e::evidence_pipeline_contract_v1::_validate_type {
    type value label
} {
    if {$type eq {string}} {
        require_nonempty $value $label
        return 1
    }
    if {$type eq {integer}} {
        if {![string is integer -strict $value]} {
            _raise TYPE_INVALID "$label must be a canonical integer."
        }
        return 1
    }
    if {$type eq {dictionary}} {
        return [require_dictionary $value $label]
    }
    if {$type eq {string_list}} {
        if {[catch {llength $value}]} {
            _raise TYPE_INVALID "$label must be a Tcl list of strings."
        }
        foreach item $value { require_nonempty $item "$label item" }
        return 1
    }
    if {[string match {record:*} $type]} {
        return [validate_record [string range $type 7 end] $value]
    }
    if {[string match {record_list:*} $type]} {
        set record_type [string range $type 12 end]
        if {[catch {llength $value}]} {
            _raise TYPE_INVALID "$label must be a list of records."
        }
        foreach item $value { validate_record $record_type $item }
        return 1
    }
    _raise TYPE_INVALID "$label uses unsupported type '$type'."
}

proc ::stage1e::evidence_pipeline_contract_v1::_expected_schema {name} {
    set schemas [dict create \
        content_integrity_observation \
            stage1e-content-integrity-observation-v1 \
        sealed_evidence_reference stage1e-sealed-evidence-reference-v1 \
        collector_producer_session stage1e-collector-producer-session-v1 \
        report_output_reservation stage1e-report-output-reservation-v1 \
        fixture_operation_ledger stage1e-fixture-operation-ledger-v1 \
        fixture_structural_evidence \
            stage1e-fixture-structural-evidence-v1 \
        raw_evidence_item stage1e-raw-evidence-item-v1 \
        raw_evidence_inventory stage1e-raw-evidence-inventory-v1 \
        collector_request stage1e-production-collector-request-v1 \
        report_attempt_open_event stage1e-report-attempt-open-event-v1 \
        report_attempt_terminal_event stage1e-report-attempt-terminal-event-v1 \
        report_interruption_event stage1e-report-interruption-event-v1 \
        report_attempt_logical_record stage1e-report-attempt-logical-record-v1 \
        report_ledger stage1e-report-attempt-ledger-v1 \
        collector_result stage1e-production-collector-result-v1 \
        parser_request stage1e-production-parser-request-v1 \
        parser_attempt stage1e-parser-attempt-v1 \
        parser_result stage1e-production-parser-result-v1 \
        message_inventory stage1e-message-inventory-v1 \
        drc_inventory stage1e-drc-inventory-v1 \
        methodology_inventory stage1e-methodology-inventory-v1 \
        timing_inventory stage1e-timing-inventory-v1 \
        clock_cdc_inventory stage1e-clock-cdc-inventory-v1 \
        timing_exception_inventory stage1e-timing-exception-inventory-v1 \
        utilization_inventory stage1e-utilization-inventory-v1 \
        ledger_projection_comparison stage1e-ledger-projection-comparison-v1 \
        evidence_set_inventory stage1e-evidence-set-inventory-v1 \
        evidence_completeness_result stage1e-evidence-completeness-result-v1 \
        evidence_structural_review_result \
            stage1e-evidence-structural-review-result-v1]
    if {[dict exists $schemas $name]} { return [dict get $schemas $name] }
    return {}
}

proc ::stage1e::evidence_pipeline_contract_v1::validate_record {
    name record
} {
    set definition [record_definition $name]
    set fields [dict get $definition fields]
    require_exact_fields $record $fields "Evidence record $name"
    set types [dict get $definition types]
    foreach field $fields {
        _validate_type [dict get $types $field] [dict get $record $field] \
            "$name.$field"
    }
    set expected_schema [_expected_schema $name]
    if {$expected_schema ne {} && [dict exists $record schema_version]} {
        require_equal $expected_schema [dict get $record schema_version] \
            "$name schema version"
    }
    _validate_semantics $name $record
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::_validate_binding_group {
    record reference
} {
    foreach field {
        request_identity execution_id attempt_id workspace_identity
    } {
        if {[dict exists $reference $field]} {
            require_equal [dict get $reference $field] [dict get $record $field] \
                "Current-attempt binding $field"
        }
    }
}

proc ::stage1e::evidence_pipeline_contract_v1::_validate_inventory {
    name record
} {
    require_equal [llength [dict get $record records]] \
        [dict get $record record_count] "$name record count"
    require_one_of [dict get $record parse_state] {
        COMPLETE PARTIAL UNSUPPORTED_FORMAT CONFLICT TRUNCATED_INPUT
        UNKNOWN_IDENTIFIER UNKNOWN_NUMERIC
    } "$name parse state"
    require_one_of [dict get $record identity_state] {
        PENDING_IDENTITY_PROVIDER UNAVAILABLE_WITH_REASON
    } "$name identity state"
    validate_authority [dict get $record authority_boundary]
}

proc ::stage1e::evidence_pipeline_contract_v1::_require_related_binding {
    open related label
} {
    foreach field {
        role_ordinal report_role role_attempt request_identity execution_id
        attempt_id workspace_identity producer_session_reference
    } {
        require_equal [dict get $open $field] [dict get $related $field] \
            "$label $field"
    }
    require_equal [dict get $open event_reference] \
        [dict get $related open_event_reference] "$label open reference"
    require_equal [dict get $open reservation_reference] \
        [dict get $related reservation_reference] "$label reservation"
}

proc ::stage1e::evidence_pipeline_contract_v1::_validate_report_event_graph {
    ledger
} {
    set reservations [dict get $ledger reservations]
    require_equal [llength $reservations] \
        [dict get $ledger reservation_count] {Report reservation count}
    set reservation_by_reference {}
    foreach reservation $reservations {
        set reference [dict get $reservation reservation_reference]
        if {[dict exists $reservation_by_reference $reference]} {
            _raise RESERVATION_GRAPH_INVALID \
                "Duplicate report reservation '$reference'."
        }
        _validate_binding_group $ledger $reservation
        require_equal [dict get $ledger producer_session_reference] \
            [dict get $reservation producer_session_reference] \
            {Report reservation producer session}
        dict set reservation_by_reference $reference $reservation
    }

    set opens [dict get $ledger open_events]
    set terminals [dict get $ledger terminal_events]
    set interruptions [dict get $ledger interruption_events]
    set logicals [dict get $ledger logical_attempts]
    set event_count [expr {[llength $opens] + [llength $terminals] +
        [llength $interruptions]}]
    require_equal $event_count [dict get $ledger event_count] \
        {Report ledger event count}

    set ordinal_map {}
    set all_events [concat $opens $terminals $interruptions]
    foreach events [list $opens $terminals $interruptions] {
        set prior 0
        foreach event $events {
            set ordinal [dict get $event event_ordinal]
            if {$ordinal <= $prior} {
                _raise EVENT_ORDER_INVALID \
                    {An event list is not in strictly increasing order.}
            }
            set prior $ordinal
        }
    }
    foreach event $all_events {
        set ordinal [dict get $event event_ordinal]
        if {[dict exists $ordinal_map $ordinal]} {
            _raise EVENT_ORDER_INVALID \
                "Duplicate report event ordinal '$ordinal'."
        }
        dict set ordinal_map $ordinal $event
    }
    for {set ordinal 1} {$ordinal <= $event_count} {incr ordinal} {
        if {![dict exists $ordinal_map $ordinal]} {
            _raise EVENT_ORDER_INVALID \
                "Missing report event ordinal '$ordinal'."
        }
    }

    set open_by_reference {}
    set attempt_keys {}
    set used_reservations {}
    foreach open $opens {
        _validate_binding_group $ledger $open
        require_equal [dict get $ledger producer_session_reference] \
            [dict get $open producer_session_reference] \
            {Report open producer session}
        set reference [dict get $open event_reference]
        if {[dict exists $open_by_reference $reference]} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                "Duplicate report open reference '$reference'."
        }
        dict set open_by_reference $reference $open
        set attempt_key "[dict get $open report_role]#[dict get $open role_attempt]"
        if {[dict exists $attempt_keys $attempt_key]} {
            _raise REPORT_RETRY_INVALID \
                "Report attempt '$attempt_key' was opened more than once."
        }
        dict set attempt_keys $attempt_key 1
        set reservation_reference [dict get $open reservation_reference]
        if {![dict exists $reservation_by_reference $reservation_reference]} {
            _raise RESERVATION_GRAPH_INVALID \
                "Open event lacks reservation '$reservation_reference'."
        }
        if {[dict exists $used_reservations $reservation_reference]} {
            _raise RESERVATION_GRAPH_INVALID \
                "Reservation reused by more than one open event."
        }
        set reservation [dict get $reservation_by_reference \
            $reservation_reference]
        foreach field {role_ordinal report_role role_attempt request_identity
                execution_id attempt_id workspace_identity
                producer_session_reference requested_path} {
            require_equal [dict get $open $field] \
                [dict get $reservation $field] \
                "Open/reservation binding $field"
        }
        dict set used_reservations $reservation_reference 1
    }
    require_equal [llength $reservations] [dict size $used_reservations] \
        {Report reservation/open cardinality}

    set completions {}
    foreach terminal $terminals {
        set open_reference [dict get $terminal open_event_reference]
        if {![dict exists $open_by_reference $open_reference]} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                "Orphan terminal event for '$open_reference'."
        }
        if {[dict exists $completions $open_reference]} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                "Multiple completions for '$open_reference'."
        }
        set open [dict get $open_by_reference $open_reference]
        _require_related_binding $open $terminal {Terminal/open binding}
        if {[dict get $terminal event_ordinal] <=
                [dict get $open event_ordinal]} {
            _raise EVENT_ORDER_INVALID \
                {Terminal event does not follow its open event.}
        }
        dict set completions $open_reference [list TERMINAL $terminal]
    }
    foreach interruption $interruptions {
        set open_reference [dict get $interruption open_event_reference]
        if {![dict exists $open_by_reference $open_reference]} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                "Orphan interruption event for '$open_reference'."
        }
        if {[dict exists $completions $open_reference]} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                "Terminal and interruption both complete '$open_reference'."
        }
        set open [dict get $open_by_reference $open_reference]
        _require_related_binding $open $interruption \
            {Interruption/open binding}
        if {[dict get $interruption event_ordinal] <=
                [dict get $open event_ordinal]} {
            _raise EVENT_ORDER_INVALID \
                {Interruption event does not follow its open event.}
        }
        dict set completions $open_reference [list INTERRUPTION $interruption]
    }
    foreach reference [dict keys $open_by_reference] {
        if {![dict exists $completions $reference]} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                "Open event '$reference' has no terminal or interruption."
        }
    }

    require_equal [llength $opens] [llength $logicals] \
        {Report open/logical cardinality}
    set logical_by_open {}
    foreach logical $logicals {
        set open_reference [dict get $logical open_event_reference]
        if {![dict exists $open_by_reference $open_reference]} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                "Logical record has no real open event '$open_reference'."
        }
        if {[dict exists $logical_by_open $open_reference]} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                "Duplicate logical record for '$open_reference'."
        }
        set open [dict get $open_by_reference $open_reference]
        _require_related_binding $open $logical {Logical/open binding}
        require_equal [dict get $open requested_path] \
            [dict get $logical requested_path] {Logical requested path}
        lassign [dict get $completions $open_reference] kind completion
        if {$kind eq {TERMINAL}} {
            require_equal [dict get $completion event_reference] \
                [dict get $logical terminal_event_reference] \
                {Logical terminal reference}
            require_equal NONE [dict get $logical interruption_event_reference] \
                {Logical interruption absence}
            require_equal [dict get $completion attempt_status] \
                [dict get $logical attempt_status] {Logical terminal status}
            require_equal [dict get $completion observed_path] \
                [dict get $logical observed_path] {Logical observed path}
        } else {
            require_equal NONE [dict get $logical terminal_event_reference] \
                {Logical terminal absence}
            require_equal [dict get $completion event_reference] \
                [dict get $logical interruption_event_reference] \
                {Logical interruption reference}
            require_equal INTERRUPTED [dict get $logical attempt_status] \
                {Logical interruption status}
            require_equal NONE [dict get $logical observed_path] \
                {Logical interrupted observed path}
        }
        require_equal [dict get $completion failure_reference] \
            [dict get $logical failure_reference] {Logical failure reference}
        dict set logical_by_open $open_reference 1
    }

    require_one_of [dict get $ledger preflight_state] {CLEAR BLOCKED} \
        {Report ledger preflight state}
    set derived COMPLETED
    if {[dict get $ledger preflight_state] eq {BLOCKED}} {
        if {[llength $opens] != 0} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                {A preflight-blocked ledger contains open attempts.}
        }
        if {[dict get $ledger preflight_failure_reference] eq {NONE}} {
            _raise REPORT_EVENT_GRAPH_INVALID \
                {A preflight-blocked ledger lacks its failure reference.}
        }
        set derived BLOCKED
    } else {
        require_equal NONE [dict get $ledger preflight_failure_reference] \
            {Clear report-ledger preflight failure}
        foreach terminal $terminals {
            set status [dict get $terminal attempt_status]
            if {$status in {BLOCKED UNAVAILABLE_FOR_STATE}} {
                set derived BLOCKED
            } elseif {$status in {FAILED MISSING} && $derived ne {BLOCKED}} {
                set derived FAILED
            }
        }
        if {[llength $interruptions] > 0 && $derived ne {BLOCKED}} {
            set derived FAILED
        }
    }
    require_equal $derived [dict get $ledger terminal_state] \
        {Report ledger terminal state derived from event graph}
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::_validate_semantics {
    name record
} {
    variable record_contract
    if {$name eq {evidence_authority_boundary}} { return 1 }
    if {[dict exists $record authority_boundary]} {
        validate_authority [dict get $record authority_boundary]
    }
    switch -- $name {
        content_integrity_observation {
            set state [dict get $record integrity_state]
            require_one_of $state \
                [dict get $record_contract enums integrity_states] \
                {Content integrity state}
            if {$state eq {VERIFIED_SHA256}} {
                if {[dict get $record byte_count] < 0} {
                    _raise INTEGRITY_OBSERVATION_INVALID \
                        {Verified content has a negative byte count.}
                }
                require_sha256 [dict get $record content_sha256] \
                    {Content integrity observation}
            } else {
                require_equal -1 [dict get $record byte_count] \
                    {Unavailable content-integrity byte count}
                require_equal $state [dict get $record content_sha256] \
                    {Unavailable content-integrity observation}
            }
        }
        sealed_evidence_reference {
            set state [dict get $record integrity_state]
            require_one_of $state \
                [dict get $record_contract enums integrity_states] \
                {Sealed reference integrity state}
            require_one_of [dict get $record location_state] \
                [dict get $record_contract enums reference_location_states] \
                {Sealed reference location state}
            require_one_of [dict get $record availability_state] \
                [dict get $record_contract enums \
                    reference_availability_states] \
                {Sealed reference availability state}
            set observation [dict get $record content_sha256_observation]
            require_equal [dict get $record reference_role] \
                [dict get $observation subject_role] \
                {Sealed reference integrity role}
            require_equal $state [dict get $observation integrity_state] \
                {Sealed reference integrity observation state}
            _validate_binding_group $record $observation
            require_equal [dict get $record producer_session_reference] \
                [dict get $observation producer_session_reference] \
                {Sealed reference integrity producer session}
            if {[dict get $record location_state] eq {FILE}} {
                require_equal PRESENT [dict get $record availability_state] \
                    {File reference availability}
                require_equal VERIFIED_SHA256 $state \
                    {File reference integrity}
            } else {
                require_equal NONE [dict get $record literal_path] \
                    {Non-file reference literal path}
                require_equal NOT_APPLICABLE $state \
                    {Non-file reference integrity}
                require_equal UNAVAILABLE_WITH_REASON \
                    [dict get $record publication_receipt_reference] \
                    {Non-file publication receipt}
            }
        }
        collector_producer_session {
            require_equal IMMUTABLE [dict get $record immutable_state] \
                {Collector producer-session immutable state}
            require_equal 1 [dict get $record first_collector_ordinal] \
                {Collector first ordinal}
            require_equal stage1e-production-vivado-collector-interface-v1 \
                [dict get $record collector_interface] \
                {Collector producer-session interface}
            require_equal stage1e-production-report-contract-v1 \
                [dict get $record report_contract_version] \
                {Collector producer-session REPORT contract}
        }
        report_output_reservation {
            require_equal EXCLUSIVE_NO_OVERWRITE \
                [dict get $record reservation_state] \
                {Report output reservation state}
            set definition [role_definition [dict get $record report_role]]
            require_equal [dict get $definition ordinal] \
                [dict get $record role_ordinal] {Reservation role ordinal}
            require_equal 1 [dict get $record role_attempt] \
                {Reservation role attempt}
        }
        fixture_operation_ledger {
            require_equal FIXTURE_ONLY [dict get $record fixture_state] \
                {Fixture operation-ledger state}
            require_equal SEALED_CURRENT_ATTEMPT \
                [dict get $record ledger_state] \
                {Fixture operation-ledger sealed state}
            require_equal [llength [dict get $record entries]] \
                [dict get $record entry_count] \
                {Fixture operation-ledger entry count}
        }
        fixture_structural_evidence {
            require_equal FIXTURE_ONLY [dict get $record fixture_state] \
                {Fixture structural-evidence state}
            require_one_of [dict get $record reference_role] {
                VIVADO_COMPONENT_RESULT FORBIDDEN_BOUNDARY_EVIDENCE
            } {Fixture structural-evidence reference role}
            require_equal MATCH [dict get $record request_provenance_state] \
                {Fixture request provenance}
            require_equal CLEAR [dict get $record phys_opt_prohibition_state] \
                {Fixture physical-optimization prohibition}
            require_equal CLEAR [dict get $record forbidden_operation_state] \
                {Fixture forbidden-operation scan}
            require_equal CLEAR [dict get $record downstream_output_state] \
                {Fixture downstream-output scan}
            require_equal COMPLETE [dict get $record structural_state] \
                {Fixture structural evidence state}
        }
        raw_evidence_item {
            set role [dict get $record role]
            set definition [role_definition $role]
            require_equal [dict get $definition ordinal] \
                [dict get $record ordinal] "Raw evidence role $role ordinal"
            require_equal [dict get $definition acquisition_owner] \
                [dict get $record acquisition_owner] \
                "Raw evidence role $role owner"
            require_one_of [dict get $record evidence_state] \
                [dict get $record_contract enums evidence_states] \
                "Raw evidence role $role state"
            require_one_of [dict get $record identity_state] \
                [dict get $record_contract enums identity_states] \
                "Raw evidence role $role identity state"
            require_one_of [dict get $record foreign_state] \
                [dict get $record_contract enums foreign_states] \
                "Raw evidence role $role foreign state"
            require_one_of [dict get $record byte_state] \
                [dict get $record_contract enums byte_states] \
                "Raw evidence role $role byte state"
            if {[dict get $record byte_state] in {PRESENT ZERO_BYTE}} {
                if {[dict get $record byte_count] < 0} {
                    _raise BYTE_STATE_INVALID \
                        "Raw evidence role $role has a negative present byte count."
                }
            } else {
                require_equal -1 [dict get $record byte_count] \
                    "Raw evidence role $role unavailable byte count"
            }
            if {[dict get $record byte_state] eq {ZERO_BYTE}} {
                require_equal 0 [dict get $record byte_count] \
                    "Raw evidence role $role zero byte count"
            }
            set integrity_state [dict get $record integrity_state]
            require_one_of $integrity_state \
                [dict get $record_contract enums integrity_states] \
                "Raw evidence role $role integrity state"
            set observation [dict get $record content_sha256_observation]
            require_equal $role [dict get $observation subject_role] \
                "Raw evidence role $role integrity role"
            require_equal $integrity_state \
                [dict get $observation integrity_state] \
                "Raw evidence role $role integrity observation state"
            require_equal [dict get $record byte_count] \
                [dict get $observation byte_count] \
                "Raw evidence role $role integrity byte count"
            _validate_binding_group $record $observation
            require_equal [dict get $record producer_session_reference] \
                [dict get $observation producer_session_reference] \
                "Raw evidence role $role integrity producer session"
            if {[dict get $record byte_state] eq {PRESENT}} {
                require_equal VERIFIED_SHA256 $integrity_state \
                    "Raw evidence role $role present integrity"
            } elseif {[dict get $record byte_state] eq {ZERO_BYTE}} {
                require_equal VERIFIED_SHA256 $integrity_state \
                    "Raw evidence role $role zero-byte integrity"
            } elseif {[dict get $record evidence_state] eq {NOT_REQUIRED} ||
                    [string match {STRUCTURAL_*} \
                        [dict get $record format_profile]]} {
                require_equal NOT_APPLICABLE $integrity_state \
                    "Raw evidence role $role non-file integrity"
            } else {
                require_equal UNAVAILABLE_WITH_REASON $integrity_state \
                    "Raw evidence role $role unavailable integrity"
            }
        }
        raw_evidence_inventory {
            require_equal [llength [dict get $record items]] \
                [dict get $record item_count] {Raw evidence item count}
            require_equal stage1e-production-report-contract-v1 \
                [dict get $record report_contract_version] \
                {Raw evidence REPORT contract}
            require_equal PENDING_IDENTITY_PROVIDER \
                [dict get $record identity_state] \
                {Raw evidence inventory identity state}
            foreach item [dict get $record items] {
                _validate_binding_group $record $item
            }
        }
        collector_request {
            require_equal stage1e-production-vivado-collector-interface-v1 \
                [dict get $record collector_interface] \
                {Collector request interface}
            foreach {field expected} {
                report_contract_version stage1e-production-report-contract-v1
                message_contract_version stage1e-production-message-contract-v1
                parser_profiles_contract_version stage1e-parser-format-profiles-contract-v1
                evidence_record_contract_version stage1e-evidence-record-contract-v1
            } {
                require_equal $expected [dict get $record $field] \
                    "Collector request $field"
            }
            require_one_of [dict get $record execution_model_state] {
                FIXTURE_MODEL_VALIDATED PRODUCTION_UNQUALIFIED
            } {Collector execution model state}
            ::stage1e::vivado_runtime_contract_v1::validate_handoff \
                [dict get $record c_handoff]
            set handoff [dict get $record c_handoff]
            _validate_binding_group $record $handoff
            require_equal [dict get $record session_id] \
                [dict get $handoff session_id] {Collector C session binding}
            require_equal PRODUCTION_COLLECTOR_NOT_IMPLEMENTED \
                [dict get $handoff report_contract_reference] \
                {Immutable C handoff Collector boundary marker}
            require_equal [dict get $handoff current_design_state] \
                [dict get $record current_design_state] \
                {Collector current design state}
            foreach item [dict get $record adopted_evidence] {
                require_equal [dict get $record producer_session \
                    producer_session_reference] \
                    [dict get $item producer_session_reference] \
                    {Collector adopted-evidence producer binding}
            }
        }
        report_attempt_open_event {
            require_equal OPEN [dict get $record event_type] \
                {Report open event type}
            require_equal PENDING_IDENTITY_PROVIDER \
                [dict get $record identity_state] \
                {Report open identity relationship state}
            set definition [role_definition [dict get $record report_role]]
            require_equal [dict get $definition ordinal] \
                [dict get $record role_ordinal] {Report open role ordinal}
            require_equal [dict get $definition command_facade_role] \
                [dict get $record exact_command_role] \
                {Report open command role}
            require_equal [dict get $definition command_name] \
                [dict get $record exact_command_name] \
                {Report open command name}
            require_equal [dict get $definition ordered_options] \
                [dict get $record exact_command_options] \
                {Report open command options}
            require_nonempty [dict get $record reservation_reference] \
                {Report open reservation reference}
        }
        report_attempt_terminal_event {
            require_equal TERMINAL [dict get $record event_type] \
                {Report terminal event type}
            require_one_of [dict get $record attempt_status] {
                COLLECTED FAILED MISSING BLOCKED UNAVAILABLE_FOR_STATE
            } {Report terminal attempt status}
            if {[dict get $record attempt_status] eq {COLLECTED}} {
                require_equal PRESENT [dict get $record byte_state] \
                    {Collected report byte state}
                if {[dict get $record byte_count] <= 0} {
                    _raise ZERO_BYTE_PROHIBITED \
                        {A collected report must contain nonzero bytes.}
                }
            }
            if {[dict get $record byte_state] in {PRESENT ZERO_BYTE}} {
                require_equal VERIFIED_SHA256 \
                    [dict get $record integrity_state] \
                    {File-backed report integrity state}
            } else {
                require_equal UNAVAILABLE_WITH_REASON \
                    [dict get $record integrity_state] \
                    {Unavailable report integrity state}
            }
            set observation [dict get $record content_sha256_observation]
            require_equal [dict get $record report_role] \
                [dict get $observation subject_role] \
                {Terminal report integrity role}
            require_equal [dict get $record integrity_state] \
                [dict get $observation integrity_state] \
                {Terminal report integrity observation state}
            require_equal [dict get $record byte_count] \
                [dict get $observation byte_count] \
                {Terminal report integrity byte count}
            _validate_binding_group $record $observation
            require_equal [dict get $record producer_session_reference] \
                [dict get $observation producer_session_reference] \
                {Terminal report integrity producer session}
        }
        report_interruption_event {
            require_equal INTERRUPTION [dict get $record event_type] \
                {Report interruption event type}
            require_equal INTERRUPTED [dict get $record interruption_state] \
                {Report interruption state}
        }
        report_attempt_logical_record {
            require_one_of [dict get $record attempt_status] \
                [dict get $record_contract enums report_attempt_states] \
                {Logical report attempt state}
        }
        report_ledger {
            require_equal IMMUTABLE_APPEND_ONLY [dict get $record immutable_state] \
                {Report ledger immutable state}
            require_equal 0 [dict get $record retry_count] \
                {Report ledger retry count}
            _validate_report_event_graph $record
        }
        collector_result {
            require_one_of [dict get $record terminal_status] \
                {COMPLETED FAILED BLOCKED} {Collector terminal status}
            require_equal NOT_CREATED [dict get $record candidate_effect] \
                {Collector candidate effect}
            require_equal PENDING_IDENTITY_PROVIDER \
                [dict get $record identity_state] \
                {Collector result identity state}
            _validate_binding_group $record \
                [dict get $record raw_evidence_inventory]
            if {[dict get $record terminal_status] eq {COMPLETED}} {
                foreach field {failure_category failure_code failure_phase} {
                    require_equal NONE [dict get $record $field] \
                        "Completed Collector $field"
                }
            } elseif {[dict get $record failure_code] eq \
                    {ACTUAL_VIVADO_REPORT_COMMANDS_NOT_QUALIFIED}} {
                require_equal BLOCKED [dict get $record terminal_status] \
                    {Unqualified production Collector status}
                require_equal TOOL_CAPABILITY \
                    [dict get $record failure_category] \
                    {Unqualified production Collector category}
                require_equal REPORT_COLLECTION \
                    [dict get $record failure_phase] \
                    {Unqualified production Collector phase}
            }
        }
        parser_request {
            require_equal stage1e-production-evidence-parser-interface-v1 \
                [dict get $record parser_interface] {Parser request interface}
            foreach {field expected} {
                report_contract_version stage1e-production-report-contract-v1
                message_contract_version stage1e-production-message-contract-v1
                format_profiles_contract_version stage1e-parser-format-profiles-contract-v1
                input_seal_state SEALED_EXACT_INVENTORY
                historical_source_state CURRENT_SYNTHETIC_ONLY
            } {
                require_equal $expected [dict get $record $field] \
                    "Parser request $field"
            }
            _validate_binding_group $record \
                [dict get $record raw_evidence_inventory]
        }
        parser_attempt {
            require_equal IMMUTABLE_APPEND_ONLY [dict get $record immutable_state] \
                {Parser attempt immutable state}
            require_one_of [dict get $record attempt_state] {
                STARTED COMPLETE PARTIAL UNSUPPORTED_FORMAT CONFLICT
                TRUNCATED_INPUT UNKNOWN_IDENTIFIER UNKNOWN_NUMERIC
            } {Parser attempt state}
        }
        parser_result {
            require_one_of [dict get $record terminal_state] {
                COMPLETE PARTIAL UNSUPPORTED_FORMAT CONFLICT TRUNCATED_INPUT
                UNKNOWN_IDENTIFIER UNKNOWN_NUMERIC
            } {Parser result terminal state}
            require_equal NOT_CREATED [dict get $record candidate_effect] \
                {Parser result candidate effect}
            require_equal PENDING_IDENTITY_PROVIDER \
                [dict get $record identity_state] \
                {Parser result identity state}
            _validate_binding_group $record [dict get $record parser_attempt]
        }
        message_inventory - drc_inventory - methodology_inventory -
        clock_cdc_inventory - timing_exception_inventory -
        utilization_inventory {
            _validate_inventory $name $record
        }
        timing_record {
            set state [dict get $record normalized_value_state]
            require_one_of $state \
                [dict get $record_contract enums numeric_value_states] \
                {Timing normalized-value state}
            if {$state eq {PRESENT}} {
                if {![string is integer -strict \
                        [dict get $record normalized_value]]} {
                    _raise NUMERIC_VALUE_INVALID \
                        {Present timing value is not a canonical integer.}
                }
            } else {
                require_equal UNKNOWN [dict get $record normalized_value] \
                    {Unknown timing normalized value}
                if {[dict get $record completeness] eq {COMPLETE}} {
                    _raise NUMERIC_VALUE_INVALID \
                        {Unknown timing value cannot be structurally complete.}
                }
            }
        }
        clock_cdc_record {
            set state [dict get $record period_state]
            require_one_of $state \
                [dict get $record_contract enums numeric_value_states] \
                {Clock period state}
            if {$state eq {PRESENT}} {
                if {![string is integer -strict [dict get $record period_ps]]} {
                    _raise NUMERIC_VALUE_INVALID \
                        {Present clock period is not a canonical integer.}
                }
            } else {
                require_equal UNKNOWN [dict get $record period_ps] \
                    {Unknown clock period}
                if {[dict get $record completeness] eq {COMPLETE}} {
                    _raise NUMERIC_VALUE_INVALID \
                        {Unknown clock period cannot be structurally complete.}
                }
            }
        }
        timing_inventory {
            _validate_inventory $name $record
            require_one_of [dict get $record summary_detail_state] \
                {MATCH NOT_APPLICABLE CONFLICT} \
                {Timing summary/detail state}
        }
        ledger_projection_comparison {
            require_one_of [dict get $record comparison_state] \
                {MATCH MISMATCH} {Ledger projection comparison state}
            if {[dict get $record comparison_state] eq {MATCH} &&
                    [llength [dict get $record mismatch_details]] != 0} {
                _raise PROJECTION_INVALID \
                    {A matching ledger projection carries mismatch details.}
            }
            set expected_reference_role [dict create \
                OPERATION_LEDGER FULL_OPERATION_LEDGER \
                REPORT_ATTEMPT_LEDGER FULL_REPORT_ATTEMPT_LEDGER]
            if {![dict exists $expected_reference_role \
                    [dict get $record ledger_role]]} {
                _raise PROJECTION_INVALID \
                    {Projection ledger role is outside the closed pair.}
            }
            require_equal [dict get $expected_reference_role \
                    [dict get $record ledger_role]] \
                [dict get $record full_ledger_reference reference_role] \
                {Projection/reference ledger role}
        }
        evidence_set_inventory {
            require_equal [llength [dict get $record items]] \
                [dict get $record item_count] {Evidence-set item count}
            require_equal NOT_CREATED [dict get $record candidate_effect] \
                {Evidence-set candidate effect}
            require_equal PENDING_IDENTITY_PROVIDER \
                [dict get $record identity_state] \
                {Evidence-set identity state}
            set ordinal 0
            foreach item [dict get $record items] {
                incr ordinal
                require_equal $ordinal [dict get $item ordinal] \
                    {Evidence-set role ordinal}
                require_equal [lindex [role_order] [expr {$ordinal - 1}]] \
                    [dict get $item role] {Evidence-set role order}
                _validate_binding_group $record $item
            }
            require_equal 14 \
                [llength [dict get $record full_ledger_references]] \
                {Evidence-set sealed-reference count}
            foreach reference [dict get $record full_ledger_references] {
                _validate_binding_group $record $reference
                require_equal [dict get $record producer_session_reference] \
                    [dict get $reference producer_session_reference] \
                    {Evidence-set sealed-reference producer session}
            }
            set comparisons [dict get $record projection_comparisons]
            require_equal 2 [llength $comparisons] \
                {Evidence-set projection comparison count}
            set expected_roles {OPERATION_LEDGER REPORT_ATTEMPT_LEDGER}
            set comparison_index 0
            foreach comparison $comparisons {
                require_equal [lindex $expected_roles $comparison_index] \
                    [dict get $comparison ledger_role] \
                    {Evidence-set projection comparison order}
                incr comparison_index
            }
        }
        evidence_completeness_result {
            require_one_of [dict get $record completeness_state] \
                {COMPLETE PARTIAL UNAVAILABLE} \
                {Evidence completeness state}
            require_equal STRUCTURAL_ONLY [dict get $record structural_only] \
                {Evidence completeness authority}
            require_equal NOT_CREATED [dict get $record candidate_effect] \
                {Evidence completeness candidate effect}
            _validate_binding_group $record \
                [dict get $record evidence_set_reference]
        }
        evidence_structural_review_result {
            require_equal NOT_CREATED [dict get $record candidate_effect] \
                {Structural review candidate effect}
            require_equal PENDING_IDENTITY_PROVIDER \
                [dict get $record identity_state] \
                {Structural review identity state}
            require_equal NONE [dict get $record authority_state] \
                {Structural review authority state}
            if {[dict get $record review_state] eq \
                    {EVIDENCE_STRUCTURAL_REVIEW_COMPLETE}} {
                foreach {field expected} {
                    terminal_status BLOCKED
                    failure_category POLICY_REVIEW
                    failure_code PRODUCTION_POLICY_REVIEW_NOT_IMPLEMENTED
                    failure_phase REVIEW
                    policy_review_state NOT_IMPLEMENTED
                } {
                    require_equal $expected [dict get $record $field] \
                        "Policy-review stop $field"
                }
            }
        }
    }
    return 1
}

proc ::stage1e::evidence_pipeline_contract_v1::_string_schema {} {
    return [::stage1e::canonical_json_v1::new_object [list \
        type [::stage1e::canonical_json_v1::new_string string]]]
}

proc ::stage1e::evidence_pipeline_contract_v1::_integer_schema {} {
    return [::stage1e::canonical_json_v1::new_object [list \
        type [::stage1e::canonical_json_v1::new_string integer]]]
}

proc ::stage1e::evidence_pipeline_contract_v1::_schema_for_type {type} {
    if {$type eq {string}} { return [_string_schema] }
    if {$type eq {integer}} { return [_integer_schema] }
    if {$type eq {string_list}} {
        return [::stage1e::canonical_json_v1::new_object [list \
            type [::stage1e::canonical_json_v1::new_string array] \
            items [_string_schema]]]
    }
    if {[string match {record:*} $type]} {
        return [record_schema_node [string range $type 7 end]]
    }
    if {[string match {record_list:*} $type]} {
        return [::stage1e::canonical_json_v1::new_object [list \
            type [::stage1e::canonical_json_v1::new_string array] \
            items [record_schema_node [string range $type 12 end]]]]
    }
    _raise SERIALIZATION_UNSUPPORTED \
        "Type '$type' cannot be serialized as a structural record."
}

proc ::stage1e::evidence_pipeline_contract_v1::record_schema_node {name} {
    set definition [record_definition $name]
    set fields [dict get $definition fields]
    set types [dict get $definition types]
    set required_nodes {}
    set property_pairs {}
    foreach field $fields {
        lappend required_nodes [::stage1e::canonical_json_v1::new_string $field]
        lappend property_pairs $field [_schema_for_type [dict get $types $field]]
    }
    return [::stage1e::canonical_json_v1::new_object [list \
        type [::stage1e::canonical_json_v1::new_string object] \
        additionalProperties [::stage1e::canonical_json_v1::new_boolean 0] \
        required [::stage1e::canonical_json_v1::new_array $required_nodes] \
        x-stage1e-canonical-order \
            [::stage1e::canonical_json_v1::new_array $required_nodes] \
        properties [::stage1e::canonical_json_v1::new_object $property_pairs]]]
}

proc ::stage1e::evidence_pipeline_contract_v1::_node_for_type {type value} {
    if {$type eq {string}} {
        return [::stage1e::canonical_json_v1::new_string $value]
    }
    if {$type eq {integer}} {
        return [::stage1e::canonical_json_v1::new_integer $value]
    }
    if {$type eq {string_list}} {
        set nodes {}
        foreach item $value {
            lappend nodes [::stage1e::canonical_json_v1::new_string $item]
        }
        return [::stage1e::canonical_json_v1::new_array $nodes]
    }
    if {[string match {record:*} $type]} {
        return [record_node [string range $type 7 end] $value]
    }
    if {[string match {record_list:*} $type]} {
        set nodes {}
        set target [string range $type 12 end]
        foreach item $value { lappend nodes [record_node $target $item] }
        return [::stage1e::canonical_json_v1::new_array $nodes]
    }
    _raise SERIALIZATION_UNSUPPORTED \
        "Type '$type' cannot be serialized as a structural record."
}

proc ::stage1e::evidence_pipeline_contract_v1::record_node {name record} {
    validate_record $name $record
    set definition [record_definition $name]
    set fields [dict get $definition fields]
    set types [dict get $definition types]
    set pairs {}
    foreach field $fields {
        lappend pairs $field [_node_for_type [dict get $types $field] \
            [dict get $record $field]]
    }
    return [::stage1e::canonical_json_v1::new_object $pairs]
}

proc ::stage1e::evidence_pipeline_contract_v1::canonical_record_bytes {
    name record
} {
    set node [record_node $name $record]
    set schema [record_schema_node $name]
    return [::stage1e::canonical_json_v1::canonical_bytes $node $schema {}]
}

proc ::stage1e::evidence_pipeline_contract_v1::_value_from_node {
    type node
} {
    if {$type in {string integer}} {
        return [::stage1e::canonical_json_v1::node_value $node]
    }
    if {$type eq {string_list}} {
        set result {}
        foreach item [::stage1e::canonical_json_v1::array_values $node] {
            lappend result [::stage1e::canonical_json_v1::node_value $item]
        }
        return $result
    }
    if {[string match {record:*} $type]} {
        return [record_from_node [string range $type 7 end] $node]
    }
    if {[string match {record_list:*} $type]} {
        set result {}
        set target [string range $type 12 end]
        foreach item [::stage1e::canonical_json_v1::array_values $node] {
            lappend result [record_from_node $target $item]
        }
        return $result
    }
    _raise SERIALIZATION_UNSUPPORTED \
        "Type '$type' cannot be parsed from a structural record."
}

proc ::stage1e::evidence_pipeline_contract_v1::record_from_node {name node} {
    set definition [record_definition $name]
    set types [dict get $definition types]
    set result {}
    foreach field [dict get $definition fields] {
        dict set result $field [_value_from_node [dict get $types $field] \
            [::stage1e::canonical_json_v1::object_get $node $field]]
    }
    validate_record $name $result
    return $result
}

proc ::stage1e::evidence_pipeline_contract_v1::parse_record_bytes {
    name bytes
} {
    set schema [record_schema_node $name]
    set node [::stage1e::canonical_json_v1::parse_canonical $bytes $schema {}]
    return [record_from_node $name $node]
}

::stage1e::evidence_pipeline_contract_v1::_initialize
