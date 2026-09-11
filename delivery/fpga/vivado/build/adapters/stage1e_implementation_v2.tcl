# Stage 1E implementation adapter foundation v2.
#
# The adapter creates and validates mock-only runner request/result shapes. It
# does not dispatch Vivado, consume authorization, decide acceptance, or grant
# artifact or board authority.

namespace eval ::stage1e::implementation_v2 {
    variable runner_result_fields {
        schema_version
        mode
        status
        operation_results
        authorization_consumption
        acceptance_decision
        artifact_authority
        board_authority
    }
}

proc ::stage1e::implementation_v2::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E IMPLEMENTATION_ADAPTER_V2 $code] $message
}

proc ::stage1e::implementation_v2::prepare_mock_request {
    runtime_identity
    policy_identity
    configuration_identity
    callbacks
} {
    ::stage1e::runtime_schema::validate_runtime_backend_identity \
        $runtime_identity
    ::stage1e::runtime_schema::validate_policy_identity_v2 $policy_identity
    ::stage1e::runtime_schema::validate_configuration_identity_v2 \
        $configuration_identity
    set runtime_hash [dict get $runtime_identity identity_sha256]
    set policy_hash [dict get $policy_identity identity_sha256]
    if {[dict get $policy_identity runtime_backend_identity] ne $runtime_hash ||
        [dict get $configuration_identity runtime_backend_identity] ne \
            $runtime_hash ||
        [dict get $configuration_identity policy_identity] ne $policy_hash} {
        _raise IDENTITY_MISMATCH \
            {Runtime, policy, and configuration identities are not bound.}
    }
    return [dict create \
        schema_version stage1e-runtime-runner-request-v1 \
        mode MOCK_ONLY \
        runtime_backend_identity $runtime_hash \
        policy_identity $policy_hash \
        configuration_identity \
            [dict get $configuration_identity identity_sha256] \
        authorization_state NOT_APPLICABLE_MOCK \
        operation_order [dict get $configuration_identity operation_order] \
        effective_step_graph \
            [dict get $configuration_identity effective_step_graph] \
        callbacks $callbacks \
        artifact_authority NONE \
        board_authority NONE]
}

proc ::stage1e::implementation_v2::validate_mock_result {result} {
    variable runner_result_fields
    ::stage1e::runtime_schema::require_exact_fields $result \
        $runner_result_fields {Implementation adapter v2 mock result}
    if {[dict get $result schema_version] ne \
            {stage1e-runtime-runner-result-v1} ||
        [dict get $result mode] ne {MOCK_ONLY}} {
        _raise RESULT_INVALID {Implementation adapter v2 result mismatch.}
    }
    if {[dict get $result status] ni {COMPLETED FAILED BLOCKED}} {
        _raise RESULT_INVALID {Implementation adapter v2 status is invalid.}
    }
    foreach field {authorization_consumption acceptance_decision} {
        if {[dict get $result $field] ne {NOT_OWNED}} {
            _raise AUTHORITY_INVALID \
                "Implementation adapter v2 $field must be NOT_OWNED."
        }
    }
    foreach field {artifact_authority board_authority} {
        if {[dict get $result $field] ne {NONE}} {
            _raise AUTHORITY_INVALID \
                "Implementation adapter v2 $field must be NONE."
        }
    }
    return 1
}
