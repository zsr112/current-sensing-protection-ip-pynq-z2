# Source-only validation for Stage 1E Artifact Closure Framework v1.
#
# The suite validates declarative schemas, identity completeness, provenance
# binding, policy text, and fail-closed behavior. It does not invoke Vivado,
# run implementation, generate an FPGA artifact, or grant a capability.

namespace eval ::stage1e::artifact_closure_framework_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_directory [file normalize [file dirname [info script]]]
    variable repository_root [file normalize [file join \
        [file dirname [info script]] .. .. .. ..]]
    variable framework {}
}

proc ::stage1e::artifact_closure_framework_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::artifact_closure_framework_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::artifact_closure_framework_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::artifact_closure_framework_tests::assert_fails {
    body
    expected_error_code
    message
} {
    set status [catch {uplevel 1 $body} result options]
    if {$status == 0} {
        fail "$message: validation unexpectedly passed"
    }
    if {![dict exists $options -errorcode]} {
        fail "$message: failure has no error code: $result"
    }
    set error_code [dict get $options -errorcode]
    if {[lsearch -exact $error_code $expected_error_code] < 0} {
        fail "$message: expected error code $expected_error_code, got <$error_code>: $result"
    }
}

proc ::stage1e::artifact_closure_framework_tests::read_text {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} contents read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $contents
    }
    if {$close_status != 0} {
        error "Unable to close $path: $close_error"
    }
    return $contents
}

proc ::stage1e::artifact_closure_framework_tests::run_case {name body} {
    variable pass_count
    variable fail_count
    set status [catch {uplevel 1 $body} result options]
    if {$status == 0} {
        incr pass_count
        puts "$name: PASS"
        return
    }
    incr fail_count
    puts stderr "$name: FAIL: $result"
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
}

proc ::stage1e::artifact_closure_framework_tests::hex {character} {
    return [string repeat $character 64]
}

proc ::stage1e::artifact_closure_framework_tests::load_framework {} {
    variable repository_root
    variable framework
    set source_check_path [file join $repository_root fpga vivado build lib \
        source_check.tcl]
    set schema_path [file join $repository_root fpga vivado build lib \
        stage1e_artifact_closure_schema.tcl]
    set framework_path [file join $repository_root fpga vivado build config \
        stage1e_artifact_closure_framework_v1.dict]
    source $source_check_path
    source $schema_path
    set framework \
        [::stage1e::artifact_closure_schema::read_dictionary $framework_path]
}

proc ::stage1e::artifact_closure_framework_tests::with_identity_hash {
    contract
    record
} {
    dict set record identity_sha256 \
        [::stage1e::artifact_closure_schema::compute_identity \
            $contract $record]
    return $record
}

proc ::stage1e::artifact_closure_framework_tests::qualification_fixture {} {
    variable framework
    set contract [dict get $framework qualification_contract]
    set identity [dict create \
        schema_version qualification_identity_v1 \
        identity_sha256 [hex 0] \
        execution_identity STAGE1E-FRAMEWORK-TEST-001 \
        workspace_identity [hex a] \
        environment_identity [hex b] \
        source_identity [hex c] \
        synthesis_result_identity [dict get $framework framework_identity \
            reference_synthesis_result_identity] \
        gate_results [dict create \
            Q0 PASS Q1 PASS Q2 PASS Q3 PASS Q4 PASS Q5 PASS] \
        evidence_identity [hex d] \
        decision PASS]
    return [with_identity_hash $contract $identity]
}

proc ::stage1e::artifact_closure_framework_tests::authorization_fixture {
    qualification
} {
    variable framework
    set contract [dict get $framework implementation_authorization_contract]
    set authorization [dict create \
        schema_version stage1e-implementation-authorization-binding-v1 \
        identity_sha256 [hex 0] \
        authorization_identity [hex e] \
        status AUTHORIZED \
        capability IMPLEMENTATION \
        consume_state UNCONSUMED \
        qualification_identity [dict get $qualification identity_sha256] \
        execution_identity [dict get $qualification execution_identity] \
        workspace_identity [dict get $qualification workspace_identity] \
        environment_identity [dict get $qualification environment_identity] \
        source_identity [dict get $qualification source_identity] \
        synthesis_result_identity \
            [dict get $qualification synthesis_result_identity]]
    return [with_identity_hash $contract $authorization]
}

proc ::stage1e::artifact_closure_framework_tests::implementation_fixture {
    qualification
} {
    variable framework
    set contract [dict get $framework implementation_result_contract]
    set result [dict create \
        schema_version stage1e-implementation-result-identity-v1 \
        identity_sha256 [hex 0] \
        execution_id [dict get $qualification execution_identity] \
        source_identity [dict get $qualification source_identity] \
        synthesis_result_identity \
            [dict get $qualification synthesis_result_identity] \
        implementation_run_identity [hex 1] \
        implementation_policy_identity [hex 2] \
        timing_report_identity [hex 3] \
        utilization_report_identity [hex 4] \
        drc_identity [hex 5] \
        methodology_identity [hex 6] \
        checkpoint_identity [hex 7] \
        acceptance_state CANDIDATE]
    return [with_identity_hash $contract $result]
}

proc ::stage1e::artifact_closure_framework_tests::artifact_roles_fixture {
    execution_id
} {
    variable framework
    set contract [dict get $framework artifact_candidate_contract]
    set roles {}
    foreach role_name [dict get $contract required_artifact_roles] {
        if {$role_name eq {SYNTHESIS_REPORT}} {
            set producer_phase PHASE2_SYNTHESIS
        } elseif {$role_name in {
            IMPLEMENTATION_REPORT
            TIMING_REPORT
            UTILIZATION_REPORT
            DRC_REPORT
            METHODOLOGY_REPORT
        }} {
            set producer_phase PHASE3_IMPLEMENTATION
        } else {
            set producer_phase PHASE4_ARTIFACT_CLOSURE
        }
        set filename [string tolower $role_name]
        dict set roles $role_name [dict create \
            logical_role $role_name \
            producer_phase $producer_phase \
            origin_path "candidate/$filename.dat" \
            relative_destination "$filename.dat" \
            size 1 \
            sha256 [hex a] \
            execution_id $execution_id \
            collection_state CANDIDATE]
    }
    return $roles
}

proc ::stage1e::artifact_closure_framework_tests::candidate_fixture {
    qualification
    implementation_result
} {
    variable framework
    set contract [dict get $framework artifact_candidate_contract]
    set execution_id [dict get $implementation_result execution_id]
    set candidate [dict create \
        schema_version stage1e-artifact-candidate-identity-v1 \
        identity_sha256 [hex 0] \
        execution_id $execution_id \
        implementation_result_identity \
            [dict get $implementation_result identity_sha256] \
        implementation_run_identity \
            [dict get $implementation_result implementation_run_identity] \
        artifact_roles [artifact_roles_fixture $execution_id] \
        producer_phase PHASE4_ARTIFACT_CLOSURE \
        source_identity [dict get $implementation_result source_identity] \
        environment_identity [dict get $qualification environment_identity] \
        workspace_identity [dict get $qualification workspace_identity] \
        manifest_identity [hex b] \
        provenance_bindings [dict create \
            execution_id $execution_id \
            source_identity [dict get $implementation_result source_identity] \
            environment_identity [dict get $qualification \
                environment_identity] \
            workspace_identity [dict get $qualification workspace_identity] \
            synthesis_result_identity [dict get $implementation_result \
                synthesis_result_identity] \
            implementation_result_identity [dict get $implementation_result \
                identity_sha256] \
            implementation_run_identity [dict get $implementation_result \
                implementation_run_identity]] \
        identity_state NON_ACCEPTED_CANDIDATE]
    return [with_identity_hash $contract $candidate]
}

proc ::stage1e::artifact_closure_framework_tests::acceptance_fixture {
    candidate
} {
    return [dict create \
        schema_version stage1e-artifact-acceptance-result-v1 \
        artifact_candidate_identity [dict get $candidate identity_sha256] \
        manifest_verification PASS \
        hash_verification PASS \
        atomic_publication PASS \
        artifact_set_digest [hex c] \
        stage1e_artifact_closure_decision PASS]
}

namespace eval ::stage1e::artifact_closure_framework_tests {

load_framework

run_case FRAMEWORK_SCHEMA_CORRECTNESS {
    variable framework
    assert_true \
        [::stage1e::artifact_closure_schema::validate_framework $framework] \
        {Framework schema did not validate}
}

run_case QUALIFICATION_SCHEMA_AND_GATES_VALID {
    variable framework
    set qualification [qualification_fixture]
    assert_true [::stage1e::artifact_closure_schema::validate_qualification_identity \
        $framework $qualification] \
        {Qualification identity did not validate}
}

run_case QUALIFICATION_MISSING_IDENTITY_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    dict unset qualification source_identity
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_qualification_identity \
            $framework $qualification
    } IDENTITY_INCOMPLETE {Missing qualification identity}
}

run_case QUALIFICATION_UNKNOWN_IDENTITY_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    dict set qualification environment_identity UNKNOWN
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_qualification_identity \
            $framework $qualification
    } IDENTITY_INVALID {Unknown qualification identity}
}

run_case QUALIFICATION_NONPASS_GATE_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    dict set qualification gate_results Q4 BLOCKED
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_qualification_identity \
            $framework $qualification
    } IDENTITY_MISMATCH {Non-PASS qualification gate}
}

run_case IMPLEMENTATION_AUTHORIZATION_BINDING_VALID {
    variable framework
    set qualification [qualification_fixture]
    set authorization [authorization_fixture $qualification]
    assert_true [::stage1e::artifact_closure_schema::validate_authorization_binding \
        $framework $qualification \
            $authorization] {Authorization binding did not validate}
}

run_case AUTHORIZATION_MISSING_QUALIFICATION_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    set authorization [authorization_fixture $qualification]
    dict unset authorization qualification_identity
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_authorization_binding \
            $framework $qualification $authorization
    } IDENTITY_INCOMPLETE {Authorization missing qualification identity}
}

run_case AUTHORIZATION_STALE_QUALIFICATION_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    set authorization [authorization_fixture $qualification]
    dict set authorization qualification_identity [hex f]
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_authorization_binding \
            $framework $qualification $authorization
    } IDENTITY_MISMATCH {Authorization stale qualification identity}
}

run_case IMPLEMENTATION_RESULT_SCHEMA_VALID {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    assert_true [::stage1e::artifact_closure_schema::validate_implementation_result \
        $framework $result] \
        {Implementation result did not validate}
}

run_case IMPLEMENTATION_RESULT_MISSING_IDENTITY_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    dict unset result drc_identity
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_implementation_result \
            $framework $result
    } IDENTITY_INCOMPLETE {Implementation result missing DRC identity}
}

run_case IMPLEMENTATION_RESULT_UNKNOWN_IDENTITY_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    dict set result methodology_identity UNKNOWN
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_implementation_result \
            $framework $result
    } IDENTITY_INVALID {Implementation result unknown methodology identity}
}

run_case IMPLEMENTATION_RESULT_HASH_MISMATCH_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    dict set result identity_sha256 [hex f]
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_implementation_result \
            $framework $result
    } IDENTITY_MISMATCH {Implementation result hash mismatch}
}

run_case ARTIFACT_CANDIDATE_SCHEMA_VALID {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    set candidate [candidate_fixture $qualification $result]
    assert_true [::stage1e::artifact_closure_schema::validate_artifact_candidate \
        $framework $result $candidate] \
        {Artifact candidate did not validate}
}

run_case IDENTITY_CHAIN_COMPLETE_AND_BOUND {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    set candidate [candidate_fixture $qualification $result]
    assert_true [::stage1e::artifact_closure_schema::validate_identity_chain \
        $framework $qualification $result $candidate] \
        {Identity chain did not validate}
}

run_case ARTIFACT_CANDIDATE_MISSING_ROLE_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    set candidate [candidate_fixture $qualification $result]
    dict unset candidate artifact_roles FPGA_CONFIGURATION
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_artifact_candidate \
            $framework $result $candidate
    } IDENTITY_INCOMPLETE {Artifact candidate missing required role}
}

run_case PREVIOUS_RETRY_ARTIFACT_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    set candidate [candidate_fixture $qualification $result]
    dict set candidate artifact_roles FPGA_CONFIGURATION execution_id \
        STAGE1E-PREVIOUS-RETRY
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_artifact_candidate \
            $framework $result $candidate
    } IDENTITY_MISMATCH {Previous retry artifact role}
}

run_case ARTIFACT_PROVENANCE_MISMATCH_BLOCKS {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    set candidate [candidate_fixture $qualification $result]
    dict set candidate provenance_bindings workspace_identity [hex f]
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_artifact_candidate \
            $framework $result $candidate
    } IDENTITY_MISMATCH {Artifact candidate provenance mismatch}
}

run_case ARTIFACT_CANDIDATE_IS_NOT_ACCEPTANCE {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    set candidate [candidate_fixture $qualification $result]
    set acceptance [acceptance_fixture $candidate]
    dict unset acceptance artifact_set_digest
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_artifact_acceptance \
            $framework $candidate $acceptance
    } IDENTITY_INCOMPLETE {Candidate without artifact-set digest}
}

run_case ARTIFACT_ACCEPTANCE_CHAIN_VALID {
    variable framework
    set qualification [qualification_fixture]
    set result [implementation_fixture $qualification]
    set candidate [candidate_fixture $qualification $result]
    set acceptance [acceptance_fixture $candidate]
    assert_true [::stage1e::artifact_closure_schema::validate_artifact_acceptance \
        $framework $candidate $acceptance] \
        {Artifact acceptance chain did not validate}
}

run_case POLICY_CONTRACT_MARKERS_VALID {
    variable repository_root
    set qualification_text [read_text [file join $repository_root docs design \
        stage1f_runtime_qualification_plan.md]]
    set implementation_text [read_text [file join $repository_root docs design \
        stage1e_implementation_policy_v1.md]]
    set acceptance_text [read_text [file join $repository_root docs design \
        stage1e_artifact_closure_acceptance.md]]
    foreach marker {
        qualification_identity_v1
        {Q0 through Q5}
        {IMPLEMENTATION authorization}
    } {
        assert_true [expr {[string first $marker $qualification_text] >= 0 ||
            [string first $marker $implementation_text] >= 0}] \
            "Qualification policy marker missing: $marker"
    }
    foreach marker {
        stage1e-implementation-result-identity-v1
        stage1e-artifact-candidate-identity-v1
        artifact_set_digest
    } {
        assert_true [expr {[string first $marker $implementation_text] >= 0}] \
            "Implementation policy marker missing: $marker"
    }
    foreach marker {
        {manifest is complete}
        {artifact-set digest}
        {implementation, timing, utilization, DRC, methodology}
    } {
        assert_true [expr {[string first $marker $acceptance_text] >= 0}] \
            "Artifact acceptance marker missing: $marker"
    }
}

run_case PROVENANCE_GUARD_VALID {
    variable repository_root
    variable framework
    assert_true [::stage1e::artifact_closure_schema::validate_provenance \
        $repository_root $framework] {Framework provenance did not validate}
}

run_case PROVENANCE_MISMATCH_BLOCKS {
    variable repository_root
    variable framework
    set bad_framework $framework
    set first_path [lindex [dict keys \
        [dict get $bad_framework provenance_guard sources]] 0]
    dict set bad_framework provenance_guard sources $first_path sha256 [hex f]
    assert_fails {
        ::stage1e::artifact_closure_schema::validate_provenance \
            $repository_root $bad_framework
    } IDENTITY_MISMATCH {Provenance hash mismatch}
}

run_case PREPARATION_ONLY_NO_RUNTIME_AUTHORITY {
    variable framework
    set boundary [dict get $framework authorization_boundary]
    foreach flag {
        declaration_is_permission
        implementation_execution_authorized
        artifact_collection_authorized
        artifact_publication_authorized
        board_access_authorized
    } {
        assert_equal 0 [dict get $boundary $flag] \
            "Unexpected runtime authority: $flag"
    }
}

run_case SCHEMA_MODULE_HAS_NO_VIVADO_COMMANDS {
    variable repository_root
    set schema_text [read_text [file join $repository_root fpga vivado build \
        lib stage1e_artifact_closure_schema.tcl]]
    foreach forbidden_command {
        launch_runs
        open_run
        write_bitstream
        write_hw_platform
        open_hw_manager
    } {
        assert_true [expr {[string first $forbidden_command $schema_text] < 0}] \
            "Schema module contains forbidden command: $forbidden_command"
    }
}

}

puts "SUMMARY PASS=$::stage1e::artifact_closure_framework_tests::pass_count FAIL=$::stage1e::artifact_closure_framework_tests::fail_count"
if {$::stage1e::artifact_closure_framework_tests::fail_count != 0} {
    exit 1
}
