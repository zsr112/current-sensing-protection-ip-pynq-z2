source [file join [file dirname [info script]] \
    stage1e_runtime_test_support.tcl]

namespace eval ::stage1e::runtime_mock_test {}

proc ::stage1e::runtime_mock_test::operation_callback {operation request} {
    return [dict create \
        status COMPLETED \
        evidence [dict create operation $operation mode MOCK_ONLY] \
        logs [list "mock:$operation"] \
        hashes [dict create mock_identity \
            [::stage1e::runtime_test::synthetic_hash c]]]
}

proc ::stage1e::runtime_mock_test::report_callback {role request} {
    return [dict create \
        status COLLECTED \
        path "mock/$role.rpt" \
        sha256 [::stage1e::runtime_test::synthetic_hash d] \
        bytes 17 \
        message MOCK_COLLECTED]
}

proc ::stage1e::runtime_mock_test::failed_report_callback {role request} {
    if {$role eq {DRC}} {
        return [dict create status FAILED path NONE sha256 NONE bytes 0 \
            message MOCK_FAILURE]
    }
    return [::stage1e::runtime_mock_test::report_callback $role $request]
}

proc ::stage1e::runtime_mock_test::environment_callback {request} {
    set root [::stage1e::runtime_test::repository_root]
    return [dict create \
        schema_version stage1e-runtime-environment-observation-v1 \
        status CURRENT \
        environment_identity [::stage1e::runtime_test::synthetic_hash e] \
        host_name MOCK_HOST \
        os_description MOCK_WINDOWS \
        cwd $root \
        xil_path [file join $root .Xil] \
        launcher_lifetime MOCK_OBSERVED \
        child_process_observation MOCK_OBSERVED \
        dispatch_monitoring MOCK_OBSERVED \
        tool_observation VIVADO_NOT_INVOKED]
}

set fixture [::stage1e::runtime_test::identity_fixture]
set runtime_identity [dict get $fixture runtime]
set policy_identity [dict get $fixture policy]
set configuration_identity [dict get $fixture configuration]

::stage1e::runtime_test::run_case runner_mock_enforces_fixed_graph {
    set callbacks {}
    foreach operation [::stage1e::runtime_schema::allowed_operations] {
        dict set callbacks $operation \
            ::stage1e::runtime_mock_test::operation_callback
    }
    set request [::stage1e::implementation_v2::prepare_mock_request \
        $runtime_identity $policy_identity $configuration_identity $callbacks]
    set result [::stage1e::runtime_runner::run_mock $request]
    ::stage1e::implementation_v2::validate_mock_result $result
    ::stage1e::runtime_test::assert_equal COMPLETED [dict get $result status] \
        {Runner mock did not complete}
    ::stage1e::runtime_test::assert_equal 4 \
        [dict size [dict get $result operation_results]] \
        {Runner mock did not execute the exact graph}
    ::stage1e::runtime_test::assert_equal NOT_OWNED \
        [dict get $result acceptance_decision] \
        {Runner mock decided acceptance}
}

::stage1e::runtime_test::run_case collector_mock_records_complete_ledger {
    set callbacks {}
    foreach role [::stage1e::runtime_collector::report_roles] {
        dict set callbacks $role ::stage1e::runtime_mock_test::report_callback
    }
    set request [dict create \
        schema_version stage1e-runtime-collector-request-v1 \
        mode MOCK_ONLY \
        runtime_backend_identity [dict get $runtime_identity identity_sha256] \
        execution_binding [::stage1e::runtime_test::synthetic_hash f] \
        report_roles [::stage1e::runtime_collector::report_roles] \
        callbacks $callbacks artifact_authority NONE board_authority NONE]
    set result [::stage1e::runtime_collector::collect_mock $request]
    ::stage1e::runtime_test::assert_equal COMPLETED [dict get $result status] \
        {Collector mock did not complete}
    ::stage1e::runtime_test::assert_equal \
        [llength [::stage1e::runtime_collector::report_roles]] \
        [llength [dict get $result report_ledger]] \
        {Collector ledger is incomplete}
    ::stage1e::runtime_test::assert_equal NOT_OWNED \
        [dict get $result waiver_decision] \
        {Collector mock granted a waiver}
}

::stage1e::runtime_test::run_case collector_mock_preserves_failed_attempt {
    set callbacks {}
    foreach role [::stage1e::runtime_collector::report_roles] {
        dict set callbacks $role \
            ::stage1e::runtime_mock_test::failed_report_callback
    }
    set request [dict create \
        schema_version stage1e-runtime-collector-request-v1 \
        mode MOCK_ONLY \
        runtime_backend_identity [dict get $runtime_identity identity_sha256] \
        execution_binding [::stage1e::runtime_test::synthetic_hash 1] \
        report_roles [::stage1e::runtime_collector::report_roles] \
        callbacks $callbacks artifact_authority NONE board_authority NONE]
    set result [::stage1e::runtime_collector::collect_mock $request]
    ::stage1e::runtime_test::assert_equal FAILED [dict get $result status] \
        {Collector did not fail closed}
    ::stage1e::runtime_test::assert_equal FAILED \
        [dict get $result reports DRC status] \
        {Collector did not preserve the failed DRC attempt}
}

::stage1e::runtime_test::run_case observer_mock_is_current_and_contained {
    set result [::stage1e::runtime_observer::observe_mock \
        ::stage1e::runtime_mock_test::environment_callback \
        [dict create mode MOCK_ONLY]]
    ::stage1e::runtime_test::assert_equal CURRENT [dict get $result status] \
        {Observer mock status mismatch}
}

::stage1e::runtime_test::finish
