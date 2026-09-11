namespace eval ::stage1d::decision_engine {
    variable decision_schema_version v1
    variable evidence_completeness_fields {
        phase_evidence_complete
        phase_evidence_schema_valid
        required_logs_retained
        required_reports_retained
    }
    variable publication_gate_fields {
        required_artifacts_present
        artifact_hashes_recorded
        manifest_complete
        manifest_schema_valid
        publication_authorized
        artifact_publication_complete
    }
}

proc ::stage1d::decision_engine::schema_version {} {
    variable decision_schema_version
    return $decision_schema_version
}

proc ::stage1d::decision_engine::_assess_gate {gate_inputs required_fields} {
    set missing_fields {}
    set invalid_fields {}
    set unsatisfied_fields {}

    if {[catch {dict size $gate_inputs}]} {
        return [dict create \
            satisfied 0 \
            missing_fields $required_fields \
            invalid_fields {gate_inputs} \
            unsatisfied_fields {}]
    }

    foreach field $required_fields {
        if {![dict exists $gate_inputs $field]} {
            lappend missing_fields $field
            continue
        }

        set value [dict get $gate_inputs $field]
        if {![string is boolean -strict $value]} {
            lappend invalid_fields $field
        } elseif {![expr {$value}]} {
            lappend unsatisfied_fields $field
        }
    }

    set satisfied [expr {
        [llength $missing_fields] == 0 &&
        [llength $invalid_fields] == 0 &&
        [llength $unsatisfied_fields] == 0
    }]
    return [dict create \
        satisfied $satisfied \
        missing_fields $missing_fields \
        invalid_fields $invalid_fields \
        unsatisfied_fields $unsatisfied_fields]
}

proc ::stage1d::decision_engine::evaluate {
    state
    phase_evidence
    evidence_completeness
    publication_gate
} {
    variable decision_schema_version
    variable evidence_completeness_fields
    variable publication_gate_fields

    set current_state [::stage1d::state_manager::current $state]
    set evidence_assessment [_assess_gate \
        $evidence_completeness \
        $evidence_completeness_fields]
    set publication_assessment [_assess_gate \
        $publication_gate \
        $publication_gate_fields]

    switch -- $current_state {
        PASS {
            if {![dict get $evidence_assessment satisfied]} {
                set decision FAIL
                set reason_code EVIDENCE_COMPLETENESS_GATE_UNSATISFIED
            } elseif {![dict get $publication_assessment satisfied]} {
                set decision FAIL
                set reason_code PUBLICATION_GATE_UNSATISFIED
            } else {
                set decision PASS
                set reason_code LIFECYCLE_COMPLETE
            }
        }
        FAIL {
            set decision FAIL
            set reason_code LIFECYCLE_FAILED
        }
        BLOCKED {
            set decision BLOCKED
            set reason_code LIFECYCLE_BLOCKED
        }
        default {
            set decision BLOCKED
            set reason_code LIFECYCLE_INCOMPLETE
        }
    }

    return [dict create \
        decision_schema_version $decision_schema_version \
        decision $decision \
        reason_code $reason_code \
        current_state $current_state \
        execution_id_schema_version [dict get $state execution_id_schema_version] \
        execution_identifier [dict get $state execution_identifier] \
        controller_api_version [dict get $state controller_api_version] \
        phase_evidence_count [llength $phase_evidence] \
        evidence_completeness $evidence_completeness \
        evidence_completeness_assessment $evidence_assessment \
        publication_gate $publication_gate \
        publication_gate_assessment $publication_assessment]
}

proc ::stage1d::decision_engine::exit_code {decision} {
    switch -- $decision {
        PASS { return 0 }
        FAIL { return 1 }
        BLOCKED { return 2 }
        default { return 3 }
    }
}
