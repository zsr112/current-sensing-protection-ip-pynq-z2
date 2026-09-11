source [file join [file dirname [info script]] \
    stage1e_runtime_test_support.tcl]

set fixture [::stage1e::runtime_test::identity_fixture]
set runtime_identity [dict get $fixture runtime]
set policy_identity [dict get $fixture policy]
set configuration_identity [dict get $fixture configuration]

::stage1e::runtime_test::run_case canonical_serialization_is_field_ordered {
    set fields {alpha beta gamma}
    set first [dict create gamma three alpha one beta two]
    set second [dict create beta two gamma three alpha one]
    set first_payload [::stage1e::runtime_identity::canonical_payload \
        $fields $first]
    set second_payload [::stage1e::runtime_identity::canonical_payload \
        $fields $second]
    ::stage1e::runtime_test::assert_equal $first_payload $second_payload \
        {Canonical payload changed with dictionary insertion order}
    ::stage1e::runtime_test::assert_equal \
        [::stage1e::runtime_identity::compute $fields $first] \
        [::stage1e::runtime_identity::compute $fields $second] \
        {Canonical identity changed with dictionary insertion order}
}

::stage1e::runtime_test::run_case identity_schemas_accept_complete_records {
    ::stage1e::runtime_schema::validate_runtime_backend_identity \
        $runtime_identity
    ::stage1e::runtime_schema::validate_policy_identity_v2 $policy_identity
    ::stage1e::runtime_schema::validate_configuration_identity_v2 \
        $configuration_identity
}

::stage1e::runtime_test::run_case framework_and_controller_foundation_validate {
    set framework_path [file join \
        [::stage1e::runtime_test::repository_root] fpga vivado build config \
        stage1e_phase3_implementation_framework_v2.dict]
    set framework \
        [::stage1e::phase3_implementation_controller_v2::load_framework \
            $framework_path]
    set result \
        [::stage1e::phase3_implementation_controller_v2::prepare_foundation \
            $framework $runtime_identity $policy_identity \
            $configuration_identity]
    ::stage1e::runtime_test::assert_equal \
        FOUNDATION_READY_NOT_AUTHORIZED [dict get $result status] \
        {Controller foundation status mismatch}
    ::stage1e::runtime_test::assert_equal 0 \
        [dict get $result implementation_execution_authorized] \
        {Controller foundation granted implementation authority}
    ::stage1e::runtime_test::assert_equal NOT_CREATED \
        [dict get $result qualification_identity] \
        {Controller foundation created qualification identity}
}

::stage1e::runtime_test::run_case adapter_request_schema_is_mock_only {
    set callbacks {}
    foreach operation [::stage1e::runtime_schema::allowed_operations] {
        dict set callbacks $operation ::stage1e::runtime_test::unused_callback
    }
    set request [::stage1e::implementation_v2::prepare_mock_request \
        $runtime_identity $policy_identity $configuration_identity $callbacks]
    ::stage1e::runtime_runner::validate_request $request
    ::stage1e::runtime_test::assert_equal MOCK_ONLY [dict get $request mode] \
        {Adapter request is not mock-only}
    ::stage1e::runtime_test::assert_equal NOT_APPLICABLE_MOCK \
        [dict get $request authorization_state] \
        {Adapter mock request represents authorization}
}

::stage1e::runtime_test::run_case parser_records_remain_undispositioned {
    set evidence [::stage1e::runtime_test::synthetic_hash b]
    set message [::stage1e::runtime_parser::parse_message [dict create \
        phase route_design severity WARNING identifier MOCK:1 \
        text {synthetic warning} evidence_identity $evidence]]
    ::stage1e::runtime_test::assert_equal UNDISPOSITIONED \
        [dict get $message disposition] \
        {Parser assigned a warning disposition}
    set exception [::stage1e::runtime_parser::parse_timing_exception \
        [dict create exception_id MOCK_EXCEPTION \
            exception_type FALSE_PATH from_object MOCK_FROM to_object MOCK_TO \
            through_objects NONE constraint_source mock_constraints.xdc \
            evidence_identity $evidence review_state PENDING_REVIEW]]
    ::stage1e::runtime_test::assert_equal PENDING_REVIEW \
        [dict get $exception review_state] \
        {Parser accepted a timing exception}
}

::stage1e::runtime_test::run_case configuration_and_warning_contracts_parse {
    set root [::stage1e::runtime_test::repository_root]
    set configuration [::stage1e::runtime_schema::read_dictionary [file join \
        $root fpga vivado build config \
        stage1e_implementation_configuration_v2.dict]]
    ::stage1e::runtime_schema::require_exact_fields $configuration {
        schema_version
        configuration_state
        identity_contract
        tool_configuration
        operation_order
        effective_step_graph
        readback_contract
        report_contract
        boundary
    } {Implementation configuration contract v2}
    ::stage1e::runtime_schema::validate_effective_graph \
        [dict get $configuration effective_step_graph]
    set warning [::stage1e::runtime_schema::read_dictionary [file join \
        $root fpga vivado build config \
        stage1e_implementation_warning_policy_v2.dict]]
    ::stage1e::runtime_schema::require_exact_fields $warning {
        schema_version
        policy_state
        identity_contract
        disposition_interface
        severity_contract
        finding_interfaces
        boundary
    } {Implementation warning policy v2}
    ::stage1e::runtime_test::assert_equal {} \
        [dict get $warning disposition_interface accepted_dispositions] \
        {Warning policy contains a pre-accepted disposition}
    ::stage1e::runtime_test::assert_equal BLOCK \
        [dict get $warning disposition_interface unknown_identifier_action] \
        {Unknown warning identifiers are not blocking}
    ::stage1e::runtime_test::assert_equal 0 \
        [dict get $warning boundary implementation_authorized] \
        {Warning policy grants implementation authority}
}

::stage1e::runtime_test::finish
