# Source-only tests for Stage 1E Phase 3 Implementation Controller Framework v1.
#
# All runtime results are synthetic dictionaries. This suite has no Vivado
# backend, executes no implementation operation, creates no FPGA artifact,
# and has no artifact-publication or board authority.

namespace eval ::stage1e::phase3_implementation_framework_tests {
    variable pass_count 0
    variable fail_count 0
    variable repository_root [file normalize [file join \
        [file dirname [info script]] .. .. .. ..]]
    variable phase3_framework {}
    variable artifact_framework {}
    variable execution_id STAGE1E-20990101-000000-a1b2c3d
}

proc ::stage1e::phase3_implementation_framework_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::phase3_implementation_framework_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::phase3_implementation_framework_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::phase3_implementation_framework_tests::assert_fails {
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
        fail [join [list "$message: expected error code" \
            "$expected_error_code, got <$error_code>: $result"] { }]
    }
}

proc ::stage1e::phase3_implementation_framework_tests::run_case {
    name
    body
} {
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

proc ::stage1e::phase3_implementation_framework_tests::read_text {path} {
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

proc ::stage1e::phase3_implementation_framework_tests::hex {character} {
    return [string repeat $character 64]
}

proc ::stage1e::phase3_implementation_framework_tests::load_frameworks {} {
    variable repository_root
    variable phase3_framework
    variable artifact_framework
    set build_root [file join $repository_root fpga vivado build]
    source [file join $build_root lib source_check.tcl]
    source [file join $build_root lib stage1e_artifact_closure_schema.tcl]
    source [file join $build_root controller \
        stage1e_phase3_implementation_controller.tcl]
    source [file join $build_root adapters stage1e_implementation.tcl]
    set artifact_framework \
        [::stage1e::artifact_closure_schema::read_dictionary [file join \
            $build_root config stage1e_artifact_closure_framework_v1.dict]]
    set phase3_framework \
        [::stage1e::artifact_closure_schema::read_dictionary [file join \
            $build_root config \
            stage1e_phase3_implementation_framework_v1.dict]]
}

proc ::stage1e::phase3_implementation_framework_tests::artifact_identity {
    contract
    record
} {
    dict set record identity_sha256 \
        [::stage1e::artifact_closure_schema::compute_identity \
            $contract $record]
    return $record
}

proc ::stage1e::phase3_implementation_framework_tests::controller_identity {
    fields
    record
} {
    dict set record identity_sha256 \
        [::stage1e::phase3_implementation_controller::compute_identity \
            $fields $record]
    return $record
}

proc ::stage1e::phase3_implementation_framework_tests::adapter_identity {
    fields
    record
} {
    dict set record identity_sha256 \
        [::stage1e::implementation::compute_identity $fields $record]
    return $record
}

proc ::stage1e::phase3_implementation_framework_tests::qualification_fixture {} {
    variable artifact_framework
    variable execution_id
    set record [dict create \
        schema_version qualification_identity_v1 \
        execution_identity $execution_id \
        workspace_identity [hex 2] \
        environment_identity [hex 3] \
        source_identity [hex 1] \
        synthesis_result_identity [hex 4] \
        gate_results [dict create \
            Q0 PASS Q1 PASS Q2 PASS Q3 PASS Q4 PASS Q5 PASS] \
        evidence_identity [hex 5] \
        decision PASS]
    return [artifact_identity [dict get $artifact_framework \
        qualification_contract] $record]
}

proc ::stage1e::phase3_implementation_framework_tests::authorization_fixture {
    qualification
} {
    variable artifact_framework
    set record [dict create \
        schema_version stage1e-implementation-authorization-binding-v1 \
        authorization_identity [hex 6] \
        status AUTHORIZED \
        capability IMPLEMENTATION \
        consume_state UNCONSUMED \
        qualification_identity [dict get $qualification identity_sha256] \
        execution_identity [dict get $qualification execution_identity] \
        workspace_identity [dict get $qualification workspace_identity] \
        environment_identity [dict get $qualification environment_identity] \
        source_identity [dict get $qualification source_identity] \
        synthesis_result_identity [dict get $qualification \
            synthesis_result_identity]]
    return [artifact_identity [dict get $artifact_framework \
        implementation_authorization_contract] $record]
}

proc ::stage1e::phase3_implementation_framework_tests::predecessor_fixture {} {
    variable execution_id
    return [dict create \
        schema_version stage1e-synthesis-result-identity-v1 \
        identity_sha256 [hex 4] \
        execution_id $execution_id \
        acceptance_state CANDIDATE \
        source_identity_sha256 [hex 1] \
        run_name synth_1 \
        run_status {synth_design Complete!} \
        top_module protection_system_wrapper \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0]
}

proc ::stage1e::phase3_implementation_framework_tests::policy_fixture {} {
    variable phase3_framework
    set fields $::stage1e::phase3_implementation_controller::policy_identity_fields
    set policy_hash [dict get $phase3_framework provenance_guard sources \
        docs/design/stage1e_implementation_policy_v1.md sha256]
    set record [dict create \
        schema_version stage1e-implementation-policy-identity-v1 \
        policy_id stage1e_implementation_policy_v1 \
        policy_document docs/design/stage1e_implementation_policy_v1.md \
        vivado_version 2024.1 \
        target protection_system_wrapper \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        canonical_policy_sha256 $policy_hash \
        effective_configuration_sha256 [hex 7]]
    return [controller_identity $fields $record]
}

proc ::stage1e::phase3_implementation_framework_tests::evidence_fixture {} {
    variable execution_id
    set fields \
        $::stage1e::phase3_implementation_controller::evidence_lifecycle_identity_fields
    set record [dict create \
        schema_version stage1e-phase3-evidence-lifecycle-v1 \
        execution_id $execution_id \
        evidence_root_identity [hex 8] \
        initial_state EMPTY_ACCEPTED \
        current_execution_only 1 \
        prior_execution_evidence_present 0 \
        preserve_on_failure 1]
    return [controller_identity $fields $record]
}

proc ::stage1e::phase3_implementation_framework_tests::context_fixture {} {
    variable execution_id
    set qualification [qualification_fixture]
    return [dict create \
        schema_version stage1e-phase3-implementation-preparation-context-v1 \
        execution_id $execution_id \
        source_identity [hex 1] \
        workspace_identity [hex 2] \
        environment_identity [hex 3] \
        synthesis_predecessor [predecessor_fixture] \
        qualification_identity $qualification \
        implementation_authorization \
            [authorization_fixture $qualification] \
        implementation_policy_identity [policy_fixture] \
        evidence_lifecycle [evidence_fixture]]
}

proc ::stage1e::phase3_implementation_framework_tests::preparation_fixture {} {
    variable artifact_framework
    variable phase3_framework
    return [::stage1e::phase3_implementation_controller::prepare \
        $artifact_framework $phase3_framework [context_fixture]]
}

proc ::stage1e::phase3_implementation_framework_tests::consumption_fixture {
    preparation
    authorization
} {
    set fields $::stage1e::implementation::consumption_identity_fields
    set record [dict create \
        schema_version stage1e-implementation-capability-consumption-v1 \
        authorization_record_identity [dict get $preparation \
            implementation_authorization_identity] \
        authorization_identity [dict get $authorization \
            authorization_identity] \
        capability IMPLEMENTATION \
        execution_id [dict get $preparation execution_id] \
        prior_state UNCONSUMED \
        new_state CONSUMED_ONCE \
        consume_point IMMEDIATELY_BEFORE_FIRST_ADAPTER_OPERATION \
        evidence_identity [hex 9]]
    return [adapter_identity $fields $record]
}

proc ::stage1e::phase3_implementation_framework_tests::operation_results_fixture {} {
    set results [dict create]
    set characters {a b c d}
    set index 0
    foreach operation $::stage1e::implementation::operation_order {
        set character [lindex $characters $index]
        dict set results $operation [dict create \
            status COMPLETED \
            evidence_identity [hex $character] \
            log_identity [hex $character] \
            hash_identity [hex $character]]
        incr index
    }
    return $results
}

proc ::stage1e::phase3_implementation_framework_tests::adapter_result_fixture {
    preparation
    authorization
} {
    variable execution_id
    set evidence [dict create \
        operation_evidence [hex 3] \
        report_evidence [hex 4] \
        authorization_consumption_evidence [hex 9]]
    set logs [dict create \
        implementation_log [hex 6] \
        message_inventory [hex 7] \
        controller_trace [hex 8]]
    set hashes [dict create \
        implementation_run [hex a] \
        timing_report [hex b] \
        utilization_report [hex c] \
        drc_report [hex d] \
        methodology_report [hex e] \
        checkpoint [hex f] \
        evidence_inventory [::stage1d::source_check::sha256_text $evidence] \
        logs_inventory [::stage1d::source_check::sha256_text $logs]]
    set result [dict create \
        schema_version stage1e-implementation-adapter-result-v1 \
        status COMPLETED \
        execution_id $execution_id \
        synthesis_result_identity [dict get $preparation \
            synthesis_result_identity] \
        implementation_run_identity [dict get $hashes implementation_run] \
        authorization_consumption [consumption_fixture $preparation \
            $authorization] \
        operation_results [operation_results_fixture] \
        evidence $evidence \
        logs $logs \
        hashes $hashes \
        acceptance_decision NOT_OWNED \
        artifact_authority NONE \
        board_authority NONE]
    return [adapter_identity \
        $::stage1e::implementation::result_identity_fields $result]
}

proc ::stage1e::phase3_implementation_framework_tests::review_fixture {
    preparation
    adapter_result
} {
    set fields \
        $::stage1e::phase3_implementation_controller::review_bundle_identity_fields
    set hashes [dict get $adapter_result hashes]
    set record [dict create \
        schema_version stage1e-implementation-review-bundle-v1 \
        execution_id [dict get $preparation execution_id] \
        implementation_run_identity [dict get $hashes implementation_run] \
        implementation_policy_identity [dict get $preparation \
            implementation_policy_identity] \
        timing_report_identity [dict get $hashes timing_report] \
        utilization_report_identity [dict get $hashes utilization_report] \
        drc_identity [dict get $hashes drc_report] \
        methodology_identity [dict get $hashes methodology_report] \
        checkpoint_identity [dict get $hashes checkpoint] \
        warning_review_identity [hex 3] \
        decision PASS \
        review_authority STAGE1E_ENGINEERING_REVIEW]
    return [controller_identity $fields $record]
}

proc ::stage1e::phase3_implementation_framework_tests::full_fixture {} {
    variable artifact_framework
    variable phase3_framework
    set context [context_fixture]
    set preparation [::stage1e::phase3_implementation_controller::prepare \
        $artifact_framework $phase3_framework $context]
    set adapter_result [adapter_result_fixture $preparation \
        [dict get $context implementation_authorization]]
    set review [review_fixture $preparation $adapter_result]
    return [dict create \
        context $context \
        preparation $preparation \
        adapter_result $adapter_result \
        review $review]
}

::stage1e::phase3_implementation_framework_tests::load_frameworks

namespace eval ::stage1e::phase3_implementation_framework_tests {

run_case CAPABILITY_SCHEMA_VALID {
    variable phase3_framework
    assert_true \
        [::stage1e::phase3_implementation_controller::validate_framework \
            $phase3_framework] {Phase 3 capability schema did not validate}
}

run_case CAPABILITY_OPERATION_ORDER_FROZEN {
    variable phase3_framework
    assert_equal {opt_design place_design route_design implementation_reports} \
        [dict keys [dict get $phase3_framework capability_contract \
        allowed_operations]] {Allowed implementation operation order}
}

run_case CAPABILITY_FORBIDDEN_OPERATIONS_FROZEN {
    variable phase3_framework
    set forbidden [dict get $phase3_framework capability_contract \
        forbidden_operations]
    foreach operation {
        write_bitstream
        write_hw_platform
        artifact_collection
        artifact_publication
        open_hw_manager
        board_access
    } {
        assert_true [expr {$operation in $forbidden}] \
            "Forbidden capability operation is missing: $operation"
    }
}

run_case CAPABILITY_FAIL_CLOSED_SCHEMA_IS_COMPLETE {
    variable phase3_framework
    set bad_framework $phase3_framework
    dict unset bad_framework capability_contract fail_closed_rules \
        unknown_operation
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_framework \
            $bad_framework
    } IDENTITY_INCOMPLETE {Missing fail-closed capability rule}
}

run_case DECLARATION_DOES_NOT_GRANT_AUTHORITY {
    variable phase3_framework
    set boundary [dict get $phase3_framework authorization_boundary]
    foreach flag {
        declaration_is_permission
        implementation_execution_authorized
        runtime_backend_present
        artifact_candidate_authorized
        artifact_collection_authorized
        artifact_publication_authorized
        bitstream_generation_authorized
        xsa_generation_authorized
        board_access_authorized
    } {
        assert_equal 0 [dict get $boundary $flag] \
            "Unexpected Phase 3 authority: $flag"
    }
}

run_case QUALIFICATION_Q0_THROUGH_Q5_REQUIRED {
    variable artifact_framework
    variable phase3_framework
    set context [context_fixture]
    set qualification [dict get $context qualification_identity]
    dict set qualification gate_results Q3 FAIL
    set qualification [artifact_identity [dict get $artifact_framework \
        qualification_contract] $qualification]
    dict set context qualification_identity $qualification
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_preparation_context \
            $artifact_framework $phase3_framework $context
    } IDENTITY_MISMATCH {Non-PASS qualification gate}
}

run_case MISSING_QUALIFICATION_BLOCKS {
    variable artifact_framework
    variable phase3_framework
    set context [context_fixture]
    dict unset context qualification_identity
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_preparation_context \
            $artifact_framework $phase3_framework $context
    } IDENTITY_INCOMPLETE {Missing qualification identity}
}

run_case STALE_QUALIFICATION_BLOCKS {
    variable artifact_framework
    variable phase3_framework
    set context [context_fixture]
    set qualification [dict get $context qualification_identity]
    dict set qualification workspace_identity STALE
    set qualification [artifact_identity [dict get $artifact_framework \
        qualification_contract] $qualification]
    dict set context qualification_identity $qualification
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_preparation_context \
            $artifact_framework $phase3_framework $context
    } IDENTITY_INVALID {Stale qualification identity}
}

run_case VALID_BOUND_PREPARATION {
    variable artifact_framework
    variable phase3_framework
    set result [::stage1e::phase3_implementation_controller::prepare \
        $artifact_framework $phase3_framework [context_fixture]]
    assert_equal PREPARATION_VALIDATED_NOT_AUTHORIZED [dict get $result \
        status] {Preparation result status}
    assert_equal UNCONSUMED [dict get $result authorization_consume_state] \
        {Preparation must not consume authorization}
}

run_case CONSUMED_AUTHORIZATION_BLOCKS_PREPARATION {
    variable artifact_framework
    variable phase3_framework
    set context [context_fixture]
    set authorization [dict get $context implementation_authorization]
    dict set authorization consume_state CONSUMED_ONCE
    set authorization [artifact_identity [dict get $artifact_framework \
        implementation_authorization_contract] $authorization]
    dict set context implementation_authorization $authorization
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_preparation_context \
            $artifact_framework $phase3_framework $context
    } IDENTITY_MISMATCH {Consumed authorization reuse}
}

run_case AUTHORIZATION_BINDING_MISMATCH_BLOCKS {
    variable artifact_framework
    variable phase3_framework
    set context [context_fixture]
    set authorization [dict get $context implementation_authorization]
    dict set authorization workspace_identity [hex f]
    set authorization [artifact_identity [dict get $artifact_framework \
        implementation_authorization_contract] $authorization]
    dict set context implementation_authorization $authorization
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_preparation_context \
            $artifact_framework $phase3_framework $context
    } IDENTITY_MISMATCH {Authorization qualification mismatch}
}

run_case SAME_EXECUTION_PREDECESSOR_REQUIRED {
    variable artifact_framework
    variable phase3_framework
    set context [context_fixture]
    dict set context synthesis_predecessor execution_id \
        STAGE1E-20990101-000001-deadbee
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_preparation_context \
            $artifact_framework $phase3_framework $context
    } IDENTITY_MISMATCH {Cross-execution synthesis predecessor}
}

run_case SAME_SOURCE_PREDECESSOR_REQUIRED {
    variable artifact_framework
    variable phase3_framework
    set context [context_fixture]
    dict set context synthesis_predecessor source_identity_sha256 [hex f]
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_preparation_context \
            $artifact_framework $phase3_framework $context
    } IDENTITY_MISMATCH {Cross-source synthesis predecessor}
}

run_case HISTORICAL_REFERENCE_IS_NOT_RUNTIME_AUTHORITY {
    variable phase3_framework
    assert_equal 0 [dict get $phase3_framework identity_integration \
        reference_identity_is_runtime_predecessor] \
        {Reference synthesis identity runtime boundary}
}

run_case STALE_EVIDENCE_LIFECYCLE_BLOCKS {
    variable artifact_framework
    variable phase3_framework
    set context [context_fixture]
    set evidence [dict get $context evidence_lifecycle]
    dict set evidence prior_execution_evidence_present 1
    set evidence [controller_identity \
        $::stage1e::phase3_implementation_controller::evidence_lifecycle_identity_fields \
        $evidence]
    dict set context evidence_lifecycle $evidence
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_preparation_context \
            $artifact_framework $phase3_framework $context
    } IDENTITY_MISMATCH {Prior-execution evidence reuse}
}

run_case PREPARATION_RESULT_HAS_NO_RUNTIME_AUTHORITY {
    set result [preparation_fixture]
    assert_equal 0 [dict get $result implementation_execution_permitted] \
        {Preparation implementation authority}
    assert_equal 0 [dict get $result runtime_dispatch_available] \
        {Preparation runtime dispatch}
    assert_equal NONE [dict get $result artifact_authority] \
        {Preparation artifact authority}
    assert_equal NONE [dict get $result board_authority] \
        {Preparation board authority}
}

run_case ADAPTER_REQUEST_IS_INERT {
    variable phase3_framework
    set request [::stage1e::implementation::prepare_request \
        $phase3_framework [preparation_fixture]]
    assert_true [::stage1e::implementation::validate_request \
        $phase3_framework $request] {Adapter request did not validate}
    assert_equal ABSENT [dict get $request runtime_backend] \
        {Adapter runtime backend boundary}
    assert_equal 0 [dict get $request execution_permitted] \
        {Adapter execution authority}
}

run_case ADAPTER_COMPLETED_RESULT_CONTRACT_VALID {
    variable phase3_framework
    set fixture [full_fixture]
    assert_true [::stage1e::implementation::validate_result \
        $phase3_framework [dict get $fixture adapter_result]] \
        {Completed adapter result did not validate}
    set normalized [::stage1e::implementation::normalize_result \
        $phase3_framework [dict get $fixture adapter_result]]
    assert_equal {evidence hashes logs status} \
        [lsort -dictionary [dict keys $normalized]] \
        {Normalized adapter return fields}
}

run_case ADAPTER_CANNOT_DECIDE_ACCEPTANCE {
    variable phase3_framework
    set fixture [full_fixture]
    set result [dict get $fixture adapter_result]
    dict set result acceptance_decision PASS
    set result [adapter_identity \
        $::stage1e::implementation::result_identity_fields $result]
    assert_fails {
        ::stage1e::implementation::validate_result $phase3_framework $result
    } CONTRACT_MISMATCH {Adapter acceptance decision}
}

run_case ADAPTER_PHASE_ORDER_FAILS_CLOSED {
    variable phase3_framework
    set fixture [full_fixture]
    set result [dict get $fixture adapter_result]
    set original [dict get $result operation_results]
    set reordered [dict create]
    foreach operation {
        place_design opt_design route_design implementation_reports
    } {
        dict set reordered $operation [dict get $original $operation]
    }
    dict set result operation_results $reordered
    set result [adapter_identity \
        $::stage1e::implementation::result_identity_fields $result]
    assert_fails {
        ::stage1e::implementation::validate_result $phase3_framework $result
    } CONTRACT_MISMATCH {Out-of-order adapter phase result}
}

run_case ADAPTER_MISSING_HASH_FAILS_CLOSED {
    variable phase3_framework
    set fixture [full_fixture]
    set result [dict get $fixture adapter_result]
    dict unset result hashes checkpoint
    set result [adapter_identity \
        $::stage1e::implementation::result_identity_fields $result]
    assert_fails {
        ::stage1e::implementation::validate_result $phase3_framework $result
    } CONTRACT_INCOMPLETE {Missing adapter checkpoint hash}
}

run_case ADAPTER_RUN_HASH_MISMATCH_FAILS_CLOSED {
    variable phase3_framework
    set fixture [full_fixture]
    set result [dict get $fixture adapter_result]
    dict set result implementation_run_identity [hex f]
    set result [adapter_identity \
        $::stage1e::implementation::result_identity_fields $result]
    assert_fails {
        ::stage1e::implementation::validate_result $phase3_framework $result
    } CONTRACT_MISMATCH {Adapter implementation-run hash mismatch}
}

run_case CONSUMPTION_REUSE_BLOCKS_RESULT_IDENTITY {
    variable artifact_framework
    variable phase3_framework
    set fixture [full_fixture]
    set result [dict get $fixture adapter_result]
    set consumption [dict get $result authorization_consumption]
    dict set consumption prior_state CONSUMED_ONCE
    set consumption [adapter_identity \
        $::stage1e::implementation::consumption_identity_fields $consumption]
    dict set result authorization_consumption $consumption
    set result [adapter_identity \
        $::stage1e::implementation::result_identity_fields $result]
    assert_fails {
        ::stage1e::phase3_implementation_controller::produce_implementation_result_identity_candidate \
            $artifact_framework $phase3_framework \
            [dict get $fixture preparation] $result [dict get $fixture review]
    } IDENTITY_MISMATCH {Consumed capability reuse}
}

run_case IMPLEMENTATION_RESULT_IDENTITY_CANDIDATE_VALID {
    variable artifact_framework
    variable phase3_framework
    set fixture [full_fixture]
    set identity \
        [::stage1e::phase3_implementation_controller::produce_implementation_result_identity_candidate \
            $artifact_framework $phase3_framework \
            [dict get $fixture preparation] \
            [dict get $fixture adapter_result] [dict get $fixture review]]
    assert_true \
        [::stage1e::artifact_closure_schema::validate_implementation_result \
            $artifact_framework $identity] \
        {Implementation result identity candidate did not validate}
    assert_equal CANDIDATE [dict get $identity acceptance_state] \
        {Implementation result identity candidate state}
}

run_case ADAPTER_EXECUTION_MISMATCH_BLOCKS_IDENTITY {
    variable artifact_framework
    variable phase3_framework
    set fixture [full_fixture]
    set result [dict get $fixture adapter_result]
    dict set result execution_id STAGE1E-20990101-000001-deadbee
    set result [adapter_identity \
        $::stage1e::implementation::result_identity_fields $result]
    assert_fails {
        ::stage1e::phase3_implementation_controller::produce_implementation_result_identity_candidate \
            $artifact_framework $phase3_framework \
            [dict get $fixture preparation] $result [dict get $fixture review]
    } IDENTITY_MISMATCH {Adapter cross-execution result}
}

run_case NONPASS_REVIEW_BLOCKS_IDENTITY {
    variable artifact_framework
    variable phase3_framework
    set fixture [full_fixture]
    set review [dict get $fixture review]
    dict set review decision FAIL
    set review [controller_identity \
        $::stage1e::phase3_implementation_controller::review_bundle_identity_fields \
        $review]
    assert_fails {
        ::stage1e::phase3_implementation_controller::produce_implementation_result_identity_candidate \
            $artifact_framework $phase3_framework \
            [dict get $fixture preparation] \
            [dict get $fixture adapter_result] $review
    } IDENTITY_MISMATCH {Non-PASS implementation review}
}

run_case PROVENANCE_GUARD_VALID {
    variable repository_root
    variable phase3_framework
    assert_true \
        [::stage1e::phase3_implementation_controller::validate_provenance \
            $repository_root $phase3_framework] \
        {Phase 3 provenance guard did not validate}
}

run_case PROVENANCE_MISMATCH_BLOCKS {
    variable repository_root
    variable phase3_framework
    set bad_framework $phase3_framework
    set path docs/design/stage1f_runtime_qualification_plan.md
    dict set bad_framework provenance_guard sources $path sha256 [hex f]
    assert_fails {
        ::stage1e::phase3_implementation_controller::validate_provenance \
            $repository_root $bad_framework
    } IDENTITY_MISMATCH {Phase 3 provenance mismatch}
}

run_case NO_RUNTIME_INVOCATION_ENTRYPOINTS {
    variable repository_root
    set paths [list \
        [file join $repository_root fpga vivado build controller \
            stage1e_phase3_implementation_controller.tcl] \
        [file join $repository_root fpga vivado build adapters \
            stage1e_implementation.tcl]]
    set command_pattern \
        {^[ \t]*(launch_runs|opt_design|place_design|route_design|phys_opt_design|power_opt_design|write_bitstream|write_hw_platform|open_hw_manager)[ \t]+[^#\r\n]+}
    foreach path $paths {
        set source [read_text $path]
        assert_true [expr {![regexp -line $command_pattern $source]}] \
            "Runtime command invocation found in [file tail $path]"
        assert_true [expr {[string first \
            {proc ::stage1e::implementation::run} $source] < 0}] \
            "Runtime adapter entrypoint found in [file tail $path]"
    }
}

}

puts "SUMMARY PASS=$::stage1e::phase3_implementation_framework_tests::pass_count FAIL=$::stage1e::phase3_implementation_framework_tests::fail_count"
if {$::stage1e::phase3_implementation_framework_tests::fail_count != 0} {
    exit 1
}
