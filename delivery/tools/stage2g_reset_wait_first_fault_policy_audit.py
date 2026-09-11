#!/usr/bin/env python3
"""Static and mutation-connected audit for the Stage 2G policy contract.

This tool deliberately validates architecture artifacts only. It never edits
RTL, registers, software, or generated hardware sources.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


BASE_COMMIT = "94b400ad3a713f4fdaf7b0e347c40baeab28a924"
PREVIOUS_AUDIT_COMMIT = "af0c604d9de9fa4a6b659940be2d41f9fbc170bd"
BRANCH = "codex/stage2g-reset-wait-first-fault-policy-audit"
CONTRACT_PATH = Path("spec/stage2g_reset_wait_first_fault_policy.json")
SCHEMA_PATH = Path("spec/stage2g_reset_wait_first_fault_policy.schema.json")
SOURCE_MAP_PATH = Path("spec/stage2g_reset_wait_first_fault_policy_source_map.json")
BEHAVIOR_PATH = Path("spec/stage2g_reset_wait_first_fault_current_behavior.json")
STATUS_PATH = Path("spec/stage2g_reset_wait_first_fault_policy_status.json")
FIXTURE_DIR = Path("spec/stage2g_fixtures")
AUDIT_DOC = Path("docs/architecture/stage2g_reset_wait_first_fault_policy_audit.md")
SOURCE_DOC = Path("docs/architecture/stage2g_reset_wait_first_fault_policy_source_map.md")
TRADEOFF_DOC = Path("docs/architecture/stage2g_reset_wait_first_fault_policy_tradeoff.md")
VERIFY_DOC = Path("docs/verification/stage2g_reset_wait_first_fault_verification_plan.md")
REVIEW_DOC = Path("docs/architecture/stage2g_reset_wait_first_fault_policy_review_contract.md")
RECOVERY_DOC = Path("docs/architecture/stage2g_public_recovery_contract_addendum.md")
LEGACY_FAULT_DEFS_PATH = Path("rtl/fault_defs.vh")
GENERATED_FAULT_DEFS_PATH = Path("rtl/generated/protection_register_map.vh")

FROZEN_FAULT_DEFINITIONS = {
    "FAULT_NONE": "00",
    "FAULT_OVERCURRENT": "01",
    "FAULT_SENSOR_MISMATCH": "02",
    "FAULT_SENSOR_OPEN": "03",
    "FAULT_SENSOR_SATURATION": "04",
    "FAULT_SENSOR_STUCK": "05",
    "FAULT_OC_WITH_ANY_SENSOR": "06",
}

ALLOWED_CHANGE_PREFIXES = (
    "docs/architecture/",
    "docs/verification/",
    "spec/",
    "tools/",
)
ALLOWED_CHANGE_FILES = {
    "tools/tests/test_stage2g_reset_wait_first_fault_policy_audit.py",
}

DECISION_KEYS = {
    "RESET_WAIT_ENTRY",
    "RESET_WAIT_EXIT",
    "FIRST_ELIGIBLE_TRANSACTION",
    "HEALTHY_QUALIFICATION_COUNT",
    "FAULT_DURING_RESET_WAIT",
    "FAULT_ON_EXIT_TRANSACTION",
    "NO_SAMPLE_POLICY",
    "FAULT_EPISODE_START_END",
    "FIRST_CAUSE_CAPTURE",
    "SIMULTANEOUS_PRIORITY",
    "FIRST_LIVE_SEEN_BITMAPS",
    "PERSISTENT_FAULT_POLICY",
    "CLEAR_ACCEPTANCE",
    "FAULT_VS_CLEAR_PRIORITY",
    "RESET_VS_FAULT_PRIORITY",
    "RESET_VS_CLEAR_PRIORITY",
    "POST_CLEAR_DESTINATION_STATE",
    "POST_RECOVERY_RETRIGGER",
    "STAGE2E_ERROR_CLASSIFICATION",
    "SAFE_OUTPUT_RELEASE",
    "REGISTER_VISIBILITY_DEFERRAL",
    "FAULT_EVALUATION_TRANSACTION",
    "FAULT_EVALUATION_VALID_AUTHORITY",
    "FAULT_EVALUATION_SEQUENCE_ALIGNMENT",
    "FAULT_EVALUATION_LATENCY_CLASS",
    "CLEAR_REQUEST_BOUNDARY",
    "CLEAR_RESOLUTION_TRANSACTION",
    "CLEAR_PENDING_NO_SAMPLE",
    "REPEATED_CLEAR_PENDING",
    "CLEAR_RESOLUTION_VS_RESET_WAIT_EXIT",
    "POLICY_DECISION_CYCLE",
    "TRANSACTION_INTEGRITY_SOURCE",
    "SOURCE_DIAGNOSTIC_CDC_CLASSIFICATION",
    "STICKY_STATUS_POLICY_ROLE",
}

CAUSE_NAMES = {
    "CH1_OVERCURRENT",
    "CH2_OVERCURRENT",
    "SENSOR_MISMATCH",
    "SENSOR_OPEN",
    "SENSOR_SATURATION",
    "SENSOR_STUCK",
}

ERROR_NAMES = {
    "SOURCE_PROTOCOL_VIOLATION_ATTACHED_TO_ACCEPTED_TRANSACTION",
    "DESTINATION_SEQUENCE_ERROR_ATTACHED_TO_DELIVERED_TRANSACTION",
    "SOURCE_DROP_WITHOUT_ACCEPTANCE",
    "DELAYED_SYNCHRONIZED_SOURCE_COUNTERS",
    "FIFO_OVERFLOW_ATTEMPT_WITHOUT_ACCEPTANCE",
    "FIFO_UNDERFLOW_ATTEMPT_WITHOUT_DELIVERY",
    "HISTORICAL_STICKY_W1C_STATUS",
    "COUNTER_SATURATION",
    "SOURCE_OR_PROFILE_MISMATCH",
    "NO_SAMPLE_AFTER_RESET_OR_CLEAR",
}

TEMPORAL_CLASSIFICATIONS = {
    "TRANSACTION_CORRELATED_BLOCKER",
    "STATUS_ONLY",
}

EXPECTED_TEMPORAL_CLASSIFICATIONS = {
    "SOURCE_PROTOCOL_VIOLATION_ATTACHED_TO_ACCEPTED_TRANSACTION": "TRANSACTION_CORRELATED_BLOCKER",
    "DESTINATION_SEQUENCE_ERROR_ATTACHED_TO_DELIVERED_TRANSACTION": "TRANSACTION_CORRELATED_BLOCKER",
    "SOURCE_DROP_WITHOUT_ACCEPTANCE": "STATUS_ONLY",
    "DELAYED_SYNCHRONIZED_SOURCE_COUNTERS": "STATUS_ONLY",
    "FIFO_OVERFLOW_ATTEMPT_WITHOUT_ACCEPTANCE": "STATUS_ONLY",
    "FIFO_UNDERFLOW_ATTEMPT_WITHOUT_DELIVERY": "STATUS_ONLY",
    "HISTORICAL_STICKY_W1C_STATUS": "STATUS_ONLY",
    "COUNTER_SATURATION": "STATUS_ONLY",
    "SOURCE_OR_PROFILE_MISMATCH": "STATUS_ONLY",
    "NO_SAMPLE_AFTER_RESET_OR_CLEAR": "STATUS_ONLY",
}


class DuplicateJsonKey(ValueError):
    """Raised when an authority file contains duplicate object keys."""


class AuditError(RuntimeError):
    """Raised for a failed static or semantic audit."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJsonKey(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object)
    except (OSError, UnicodeError, json.JSONDecodeError, DuplicateJsonKey) as exc:
        raise AuditError(f"invalid JSON {path.as_posix()}: {exc}") from exc


def _is_type(value: Any, type_name: str) -> bool:
    if type_name == "object":
        return isinstance(value, dict)
    if type_name == "array":
        return isinstance(value, list)
    if type_name == "string":
        return isinstance(value, str)
    if type_name == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if type_name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if type_name == "boolean":
        return isinstance(value, bool)
    if type_name == "null":
        return value is None
    return False


def _resolve_ref(root_schema: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise AuditError(f"unsupported schema reference: {reference}")
    value: Any = root_schema
    for component in reference[2:].split("/"):
        value = value[component.replace("~1", "/").replace("~0", "~")]
    if not isinstance(value, dict):
        raise AuditError(f"schema reference is not an object: {reference}")
    return value


def _validate_schema_value(
    schema: dict[str, Any], value: Any, location: str, errors: list[str], root_schema: dict[str, Any]
) -> None:
    if "$ref" in schema:
        _validate_schema_value(_resolve_ref(root_schema, str(schema["$ref"])), value, location, errors, root_schema)
        return
    type_value = schema.get("type")
    if isinstance(type_value, str) and not _is_type(value, type_value):
        errors.append(f"{location} must be {type_value}")
        return
    if isinstance(type_value, list) and not any(
        isinstance(candidate, str) and _is_type(value, candidate) for candidate in type_value
    ):
        errors.append(f"{location} has an invalid type")
        return
    if "const" in schema and value != schema["const"]:
        errors.append(f"{location} must equal {schema['const']!r}")
    enum = schema.get("enum")
    if isinstance(enum, list) and value not in enum:
        errors.append(f"{location} is outside enum")
    if isinstance(value, str):
        if isinstance(schema.get("minLength"), int) and len(value) < schema["minLength"]:
            errors.append(f"{location} is shorter than minLength")
        if isinstance(schema.get("maxLength"), int) and len(value) > schema["maxLength"]:
            errors.append(f"{location} is longer than maxLength")
        if isinstance(schema.get("pattern"), str) and re.fullmatch(schema["pattern"], value) is None:
            errors.append(f"{location} fails pattern")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(schema.get("minimum"), (int, float)) and value < schema["minimum"]:
            errors.append(f"{location} is below minimum")
        if isinstance(schema.get("maximum"), (int, float)) and value > schema["maximum"]:
            errors.append(f"{location} is above maximum")
    if isinstance(value, list):
        if isinstance(schema.get("minItems"), int) and len(value) < schema["minItems"]:
            errors.append(f"{location} has too few items")
        if isinstance(schema.get("maxItems"), int) and len(value) > schema["maxItems"]:
            errors.append(f"{location} has too many items")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(value):
                _validate_schema_value(item_schema, item, f"{location}[{index}]", errors, root_schema)
    if isinstance(value, dict):
        required = schema.get("required", [])
        if isinstance(required, list):
            for key in required:
                if isinstance(key, str) and key not in value:
                    errors.append(f"{location}.{key} is required")
        properties = schema.get("properties", {})
        if isinstance(properties, dict):
            if schema.get("additionalProperties") is False:
                extras = set(value) - set(properties)
                if extras:
                    errors.append(f"{location} has unexpected fields: {sorted(extras)}")
            for key, child_schema in properties.items():
                if key in value and isinstance(child_schema, dict):
                    _validate_schema_value(child_schema, value[key], f"{location}.{key}", errors, root_schema)
        if isinstance(schema.get("minProperties"), int) and len(value) < schema["minProperties"]:
            errors.append(f"{location} has too few properties")
    for clause in schema.get("allOf", []) if isinstance(schema.get("allOf"), list) else []:
        if isinstance(clause, dict):
            _validate_schema_value(clause, value, location, errors, root_schema)


def schema_errors(contract: dict[str, Any], schema: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        errors.append("schema does not declare draft 2020-12")
    _validate_schema_value(schema, contract, "$", errors, schema)
    return errors


def _get_path(value: Any, dotted_path: str) -> Any:
    current = value
    for part in dotted_path.split("."):
        current = current[int(part)] if isinstance(current, list) else current[part]
    return current


def set_path(value: Any, dotted_path: str, replacement: Any) -> None:
    parts = dotted_path.split(".")
    current = value
    for part in parts[:-1]:
        current = current[int(part)] if isinstance(current, list) else current[part]
    final = parts[-1]
    if isinstance(current, list):
        current[int(final)] = replacement
    else:
        current[final] = replacement


def validate_contract(contract: dict[str, Any], schema: dict[str, Any]) -> list[str]:
    """Return all schema and target-policy invariant violations."""

    errors = [f"schema: {item}" for item in schema_errors(contract, schema)]
    if schema.get("$id") != "https://current-sensing-protection-ip.local/schema/stage2g-reset-wait-first-fault-policy-v2":
        errors.append("schema id is not the closed Stage 2G v2 contract")
    if schema.get("additionalProperties") is not False:
        errors.append("top-level schema must reject additional properties")
    if contract.get("schema_version") != "stage2g-reset-wait-first-fault-policy-v2":
        errors.append("schema_version is not the frozen Stage 2G contract")
    scope = contract.get("scope", {})
    if scope != {
        "stage": "2G",
        "audit_only": True,
        "implementation_started": False,
        "policy_gap_closed": False,
        "remaining_contract_gaps": 2,
        "functional_rtl_changes_allowed": False,
        "public_interface_changes_allowed": False,
        "previous_audit_commit": PREVIOUS_AUDIT_COMMIT,
    }:
        errors.append("scope must retain audit-only status and two remaining gaps")
    authorities = contract.get("authorities", {})
    expected_authorities = {
        "sample_event_authority": "ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT",
        "fault_input_authority": "RAW_PROTECTION_EVALUATION",
        "normalized_telemetry_gates_fault_policy": False,
        "normalized_range_flags_gate_fault_policy": False,
        "normalized_configuration_valid_gates_fault_policy": False,
        "raw_protection_threshold_domain": "UNSIGNED_RAW_CODE_COMPATIBILITY",
        "existing_register_offsets": "0x00..0x60_UNCHANGED",
        "new_axi_offsets_added": False,
        "external_interface_change_required": False,
    }
    if authorities != expected_authorities:
        errors.append("authorities do not preserve the frozen raw/CDC/register boundary")

    expected_sequence_addendum = {
        "addendum_id": "STAGE2G_SEQUENCE_WIDTH_CONTRACT_IMPLEMENTATION_ADDENDUM_V1",
        "fault_eval_sequence_width": "OBS_SEQUENCE_WIDTH",
        "supported_sequence_widths": "16_TO_32",
        "minimum_sequence_width": 16,
        "maximum_sequence_width": 32,
        "sequence_arithmetic": "MODULO_2_POW_SEQUENCE_WIDTH",
        "binding": "SEQUENCE_WIDTH_EQUALS_OBS_SEQUENCE_WIDTH",
        "classification_authority": "SHARED_STAGE2E_TRANSACTION_SEQUENCE_CLASSIFIER",
        "first_nonzero_delivery": "STALE_RETAIN_EXPECTED",
        "forward_gap": "DIRTY_RESYNC_DELIVERED_PLUS_ONE",
        "duplicate": "DIRTY_RETAIN_EXPECTED",
        "reorder_stale": "DIRTY_RETAIN_EXPECTED",
        "next_matching_transaction_restores_eligibility": True,
    }
    if contract.get("sequence_width_contract_addendum") != expected_sequence_addendum:
        errors.append("sequence-width implementation addendum is incomplete")

    expected_recovery_addendum = {
        "addendum_id": "STAGE2G_PUBLIC_RECOVERY_OBSERVABILITY_IMPLEMENTATION_ADDENDUM_V1",
        "internal_episode_end": "LEGAL_CLEAR_ACCEPTANCE",
        "public_recovery_complete": "LATER_CLEAN_HEALTHY_EVALUATION_ENTERING_ARMED",
        "clear_acceptance_equals_public_recovery_complete": False,
        "public_status_owner": "EXISTING_STATUS_AND_FAULT_CODE_REGISTERS",
        "public_fault_latched_signal": "public_fault_latched_compat",
        "public_fault_code_signal": "public_fault_code_compat",
        "post_clear_pending_signal": "post_clear_recovery_pending",
        "clear_acceptance_public_behavior": "RETAIN_LATCH_AND_PRIOR_FIRST_CAUSE_SET_PENDING",
        "no_sample_post_clear_behavior": "RETAIN_PUBLIC_STATUS_AND_PENDING",
        "nonclean_post_clear_behavior": "RETAIN_PUBLIC_STATUS_AND_PENDING",
        "later_clean_healthy_behavior": "ENTER_ARMED_CLEAR_PUBLIC_STATUS_AND_PENDING",
        "clean_fault_before_rearm_behavior": "START_NEW_EPISODE_REPLACE_PUBLIC_FIRST_CAUSE",
        "reset_behavior": "CLEAR_INTERNAL_AND_PUBLIC_RECOVERY_STATE",
        "new_recovery_status_bit_added": False,
        "software_recovery_api_changed": False,
        "software_recovery_predicate": "recovery_is_verified(snapshot)",
    }
    if contract.get("public_recovery_contract_addendum") != expected_recovery_addendum:
        errors.append("public recovery observability implementation addendum is incomplete")

    evaluation = contract.get("fault_evaluation_transaction", {})
    expected_evaluation_values = {
        "valid_signal": "fault_eval_valid",
        "sequence_signal": "fault_eval_sequence[SEQUENCE_WIDTH-1:0]",
        "bitmap_signal": "fault_eval_bitmap[5:0]",
        "code_signal": "fault_eval_code[7:0]",
        "integrity_signal": "fault_eval_integrity_clean",
        "valid_authority": "ONE_PER_ATOMIC_RAW_CDC_DESTINATION_DELIVERY",
        "sequence_width": "OBS_SEQUENCE_WIDTH",
        "fault_present_definition": "fault_eval_valid && fault_eval_bitmap != 0",
        "healthy_evaluation_definition": "fault_eval_valid && fault_eval_bitmap == 0",
        "policy_eligible_definition": "fault_eval_valid && fault_eval_integrity_clean",
        "zero_bitmap_is_valid_healthy_evaluation": True,
        "current_fault_valid_semantics": "REGISTERED_NONZERO_FAULT_PRESENCE_FOR_ONE_EVALUATED_TRANSACTION",
        "current_fault_valid_is_evaluation_valid": False,
        "missing_current_signal": "HEALTHY_OR_FAULTY_EVALUATION_COMPLETION_VALID",
        "fields_aligned": True,
        "no_channel_or_cause_tearing": True,
        "reset_flush_rule": "RESET_INVALIDATES_ALL_PIPELINE_VALID_BITS_AND_PENDING_EVALUATIONS_NO_PRE_RESET_RETIREMENT",
        "sequence_wrap_rule": "MODULO_2_POW_SEQUENCE_WIDTH_IDENTITY_WRAP_DOES_NOT_CHANGE_RETIREMENT_ORDER",
    }
    for key, expected in expected_evaluation_values.items():
        if evaluation.get(key) != expected:
            errors.append(f"fault-evaluation transaction mismatch for {key}")
    pipeline = evaluation.get("pipeline", {})
    expected_pipeline = {
        "clock": "ACLK",
        "delivery_edge_offset": 0,
        "decision_health_edge_offset": 1,
        "fault_eval_register_edge_offset": 2,
        "policy_decision_edge_offset": 3,
        "latency_class": "FIXED_3_ACLK_EDGES_DELIVERY_TO_POLICY_DECISION_II1",
        "fixed_delivery_to_policy_cycles": 3,
        "initiation_interval": 1,
        "exactly_one_evaluation_per_delivery": True,
        "no_evaluation_without_delivery": True,
        "no_drop": True,
        "no_duplicate": True,
        "no_reorder": True,
    }
    if pipeline != expected_pipeline:
        errors.append("fault-evaluation pipeline must retain fixed 0/1/2/3 offsets and II=1 invariants")
    expected_nonclean = {
        "arms_reset_wait": False,
        "accepts_clear": False,
        "becomes_physical_fault_cause": False,
        "updates_first_cause": False,
        "updates_live_or_seen_bitmap": False,
        "next_clean_transaction_restores_eligibility": True,
    }
    if evaluation.get("nonclean_policy") != expected_nonclean:
        errors.append("non-clean evaluation policy must fail safe and recover on the next clean transaction")

    decision_cycle = contract.get("policy_decision", {})
    if decision_cycle.get("clock") != "ACLK" or decision_cycle.get("cycle") != "FAULT_EVALUATION_RETIREMENT":
        errors.append("policy decision must occur at ACLK fault-evaluation retirement")
    if decision_cycle.get("priority_order") != ["RESET", "FAULT", "CLEAR", "HEALTHY_PROGRESS"]:
        errors.append("policy decision priority is not frozen")
    if decision_cycle.get("delivered_not_retired_rule") != "ORDERED_BY_CLEAR_REQUEST_FENCE_NOT_BY_SAME_CYCLE_WORDING":
        errors.append("in-flight destination deliveries must be ordered by the clear request fence at evaluation retirement")

    reset_wait = contract.get("reset_wait", {})
    if reset_wait.get("arming_policy") != "FIRST_ELIGIBLE_TRANSACTION_ARMS_IMMEDIATELY":
        errors.append("RESET_WAIT arming policy must be immediate first eligible transaction")
    if reset_wait.get("healthy_qualification_count") != 1:
        errors.append("healthy qualification count must be exactly one")
    reset_wait_text = json.dumps(reset_wait).upper()
    if "HYBRID_TIMEOUT" in reset_wait_text or "CONFIGURABLE_QUALIFICATION" in reset_wait_text:
        errors.append("RESET_WAIT must not add an unowned timeout or configurable field")
    lifecycle = contract.get("episode_lifecycle", {})
    if lifecycle.get("conceptual_states") != ["RESET", "RESET_WAIT", "ARMED", "FAULT_LATCHED"]:
        errors.append("conceptual episode states are incomplete or reordered")
    fault = contract.get("fault_model", {})
    causes = fault.get("causes", [])
    if {item.get("name") for item in causes if isinstance(item, dict)} != CAUSE_NAMES:
        errors.append("fault cause inventory must contain exactly six primitive causes")
    if sorted(item.get("bitmap_bit") for item in causes if isinstance(item, dict)) != list(range(6)):
        errors.append("fault bitmap bits must be unique and cover 0..5")
    if fault.get("simultaneous_priority") != [
        "OC_WITH_ANY_SENSOR",
        "OVERCURRENT",
        "SENSOR_SATURATION",
        "SENSOR_OPEN",
        "SENSOR_STUCK",
        "SENSOR_MISMATCH",
    ]:
        errors.append("simultaneous-fault priority must be explicit and deterministic")
    if fault.get("persistent_fault_retrigger") is not False:
        errors.append("persistent faults must not retrigger first-cause events")
    if fault.get("later_fault_overwrites_first_cause") is not False:
        errors.append("later faults must not overwrite first cause")
    if fault.get("non_sample_async_sources") != "NONE_IDENTIFIED_PROTECTION_INPUTS_ARE_RAW_SAMPLE_EVALUATIONS":
        errors.append("non-sample asynchronous protection source inventory is not explicit")
    bitmaps = contract.get("bitmaps", {})
    if bitmaps.get("width") != 6 or bitmaps.get("public_visibility") != "DEFERRED_TO_STAGE2H":
        errors.append("first/live/seen bitmap model must be six-bit and deferred publicly")
    clear = contract.get("clear_recovery", {})
    expected_clear_values = {
        "protocol": "REQUEST_EVALUATION_FENCED",
        "resolution_transaction": "FIRST_FAULT_EVAL_VALID_ON_AN_ACLK_EDGE_STRICTLY_AFTER_REQUEST_CAPTURE",
        "resolution_order_domain": "FAULT_EVALUATION_RETIREMENT_ORDER",
        "same_edge_evaluation_order": "EVALUATION_RETIRING_ON_REQUEST_EDGE_IS_EARLIER_AND_DOES_NOT_RESOLVE_NEW_REQUEST",
        "delivery_before_request_retire_after_request": "RESOLVES_REQUEST_BECAUSE_RETIREMENT_IS_STRICTLY_AFTER_CAPTURE",
        "rejection_condition": "CLEAR_PENDING_AND_FAULT_EVAL_VALID_AND_(NONZERO_BITMAP_OR_NONCLEAN_INTEGRITY)",
        "pending_after_accept": "CLEAR_PENDING_CLEARS",
        "pending_after_reject": "CLEAR_PENDING_CLEARS_NEW_REQUEST_REQUIRED",
        "clear_pending_no_sample": "REMAIN_FAULT_LATCHED_SAFE_INDEFINITELY",
        "repeated_clear_while_pending": "IDEMPOTENT_COALESCED_NO_DUPLICATE_EPISODE_END",
        "continuous_ii1_progress": "REQUEST_RESOLVES_ON_NEXT_RETIREMENT_EDGE_AFTER_CAPTURE",
        "sequence_wrap": "NO_SEQUENCE_COMPARISON_IN_FENCE_MODULO_WRAP_PRESERVES_RETIREMENT_ORDER",
        "reset_while_pending": "RESET_CLEARS_PENDING_AND_ALL_EPISODE_PIPELINE_STATE",
        "resolution_transaction_reset_wait_role": "DOES_NOT_ARM_OR_RELEASE_SAFE_OUTPUT",
    }
    for key, expected in expected_clear_values.items():
        if clear.get(key) != expected:
            errors.append(f"request/evaluation-fenced clear mismatch for {key}")
    if clear.get("acceptance_condition") != [
        "CLEAR_PENDING_IS_TRUE",
        "FAULT_EVAL_VALID_IS_TRUE",
        "FAULT_EVAL_BITMAP_IS_ZERO",
        "FAULT_EVAL_INTEGRITY_CLEAN_IS_TRUE",
        "RESET_IS_FALSE",
    ]:
        errors.append("clear acceptance must use the fresh clean post-request resolution transaction")
    clear_text = json.dumps(clear).upper()
    if "PIPELINE_EMPTY" in clear_text or "NO_PENDING_RAW_EVALUATION" in clear_text:
        errors.append("clear must not depend on global pipeline empty or an unqualified pending predicate")
    if clear.get("clear_while_any_live_fault") != "REJECT":
        errors.append("clear while live fault must reject")
    if clear.get("source_removal_without_clear") != "REMAIN_LATCHED":
        errors.append("source removal without clear must remain latched")
    if clear.get("fault_and_clear_same_cycle") != "FAULT_PRIORITY":
        errors.append("fault must win same-cycle clear")
    if clear.get("clear_and_reset_same_cycle") != "RESET_PRIORITY":
        errors.append("reset must win same-cycle clear")
    if clear.get("post_clear_destination_state") != "RESET_WAIT":
        errors.append("successful clear must target RESET_WAIT")
    if clear.get("successful_clear_starts_new_episode") is not True:
        errors.append("successful clear must start a new episode")
    if clear.get("post_recovery_fault_can_latch_again") is not True:
        errors.append("post-recovery faults must be able to latch again")
    if clear.get("recovery_qualify_state") != "NOT_USED":
        errors.append("unowned distinct recovery state must not be introduced")
    reset = contract.get("reset_policy", {})
    if reset.get("priority_order") != ["RESET", "FAULT", "CLEAR", "HEALTHY_PROGRESS"]:
        errors.append("reset/fault/clear priority order is not frozen")
    if reset.get("effect_on_clear_pending") != "CLEAR_TO_ZERO":
        errors.append("reset must clear a pending clear request")
    if reset.get("effect_on_pending_sample_pipeline") != "FLUSH_ALL_VALID_BITS_AND_DISCARD_PENDING_FAULT_EVALUATIONS":
        errors.append("reset must flush all pending evaluation valid stages")
    if reset.get("stale_sample_rule") != "NO_PRE_RESET_EVALUATION_MAY_RETIRE_POST_RESET":
        errors.append("stale pre-reset evaluation rule is missing")

    integrity = contract.get("transaction_integrity", {})
    expected_integrity_values = {
        "source_component": "SOURCE_STALL_OFFER_STABILITY_RESULT_CARRIED_IN_ATOMIC_FIFO_PAYLOAD",
        "source_offer_rule": "ACCEPTED_STALLED_OFFER_IS_DIRTY_IF_PAYLOAD_CHANGED_WHILE_VALID_REMAINED_ASSERTED",
        "withdrawn_offer_rule": "NO_ACCEPTED_TRANSACTION_NO_CARRIED_DIRTY_BIT_DIAGNOSTIC_COUNTER_ONLY",
        "destination_component": "DELIVERED_SEQUENCE_EQUALS_CURRENT_EXPECTED_SEQUENCE",
        "destination_recovery": "GAP_RESYNCS_TO_DELIVERED_PLUS_ONE_DUPLICATE_OR_STALE_RETAINS_EXPECTED_NEXT_MATCHING_CLEAN_TRANSACTION_RESTORES_ELIGIBILITY",
        "alignment_identity": "FAULT_EVAL_SEQUENCE",
        "global_diagnostic_inhibit": False,
        "software_clear_dependency": False,
    }
    for key, expected in expected_integrity_values.items():
        if integrity.get(key) != expected:
            errors.append(f"transaction-integrity authority mismatch for {key}")
    if "COUNTER" in str(integrity.get("source_component", "")):
        errors.append("eventually consistent source counters cannot qualify a delivered transaction")

    error_rows = contract.get("error_classification", [])
    if len(error_rows) != len(ERROR_NAMES) or {row.get("condition") for row in error_rows if isinstance(row, dict)} != ERROR_NAMES:
        errors.append("Stage 2E error classification inventory is incomplete")
    for row in error_rows:
        if not isinstance(row, dict):
            continue
        condition = row.get("condition")
        classification = row.get("temporal_classification")
        if classification not in TEMPORAL_CLASSIFICATIONS:
            errors.append(f"invalid temporal error classification for {condition}")
        if condition in EXPECTED_TEMPORAL_CLASSIFICATIONS and classification != EXPECTED_TEMPORAL_CLASSIFICATIONS[condition]:
            errors.append(f"error classification policy changed for {condition}")
        if row.get("protection_trip") is not False:
            errors.append(f"diagnostic/blocker condition {condition} cannot be a protection trip")
        for field in ("authority", "policy_role", "arming_effect", "clear_effect", "software_visibility", "safety_rationale", "current_behavior", "target_behavior"):
            if not isinstance(row.get(field), str) or not row[field].strip():
                errors.append(f"error classification {condition} has an empty {field}")
        if classification == "TRANSACTION_CORRELATED_BLOCKER" and row.get("policy_role") != "MARK_MATCHING_FAULT_EVAL_NONCLEAN":
            errors.append(f"transaction-correlated condition {condition} must mark only its matching evaluation")
        if classification == "STATUS_ONLY" and row.get("policy_role") not in {"NO_DIRECT_POLICY_GATE", "NO_EVALUATION_NO_PROGRESS"}:
            errors.append(f"status-only condition {condition} cannot gate safety policy")

    safe_output = contract.get("safe_output", {})
    if safe_output.get("clear_resolution_transaction_releases_safe_output") is not False:
        errors.append("clear resolution transaction cannot release safe output")
    if safe_output.get("safe_state_release_condition") != "ONLY_AFTER_LEGAL_CLEAR_TO_RESET_WAIT_THEN_LATER_CLEAN_HEALTHY_FAULT_EVAL":
        errors.append("safe release must require a later clean healthy evaluation")

    decisions = contract.get("required_decisions", {})
    if set(decisions) != DECISION_KEYS:
        errors.append("required decision disposition set is incomplete or has hidden decisions")
    for key, decision in decisions.items():
        if not isinstance(decision, dict):
            errors.append(f"decision {key} is not an object")
        elif not decision.get("status") or not decision.get("decision") or not decision.get("owner"):
            errors.append(f"decision {key} lacks status, decision, or owner")
        elif decision.get("status") not in {"APPROVED", "DEFERRED_TO_STAGE2H", "OWNER_DECISION_REQUIRED", "NOT_APPLICABLE"}:
            errors.append(f"decision {key} uses an unapproved disposition vocabulary")
        elif key != "REGISTER_VISIBILITY_DEFERRAL" and decision.get("status") != "APPROVED":
            errors.append(f"decision {key} must be APPROVED for the selected contract")
    if decisions.get("REGISTER_VISIBILITY_DEFERRAL", {}).get("status") != "DEFERRED_TO_STAGE2H":
        errors.append("register visibility must be deferred to Stage 2H")
    if contract.get("open_owner_decisions") != []:
        errors.append("open owner decisions must be explicit and empty for this selected policy")
    return errors


def validate_source_map(root: Path, source_map: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if source_map.get("schema_version") != "stage2g-reset-wait-first-fault-source-map-v3":
        errors.append("source map is not the sequence-integrity v3 map")
    expected_current_pipeline = {
        "clock": "ACLK",
        "delivery_capture_edge_offset": 0,
        "comparator_health_decision_edge_offset": 1,
        "registered_classifier_result_edge_offset": 2,
        "fsm_policy_consumption_edge_offset": 3,
        "fixed_delivery_to_policy_edges": 3,
        "initiation_interval": 1,
        "internal_fifo_prefetch_event": "IMPLEMENTATION_DETAIL_NOT_POLICY_AUTHORITY",
        "atomic_raw_cdc_destination_delivery_event": "DST_SAMPLE_VALID_ACCEPTED_EDGE",
        "fault_valid_semantics": "REGISTERED_NONZERO_FAULT_PRESENCE_FOR_ONE_EVALUATED_TRANSACTION",
        "evaluation_completion_valid": "FAULT_EVAL_VALID_ONE_PER_ATOMIC_RAW_CDC_DESTINATION_DELIVERY",
        "sequence_width_binding": "SEQUENCE_WIDTH_EQUALS_OBS_SEQUENCE_WIDTH",
    }
    if source_map.get("current_pipeline") != expected_current_pipeline:
        errors.append("source map must freeze current 0/1/2/3 offsets, II=1, and corrected fault_valid semantics")
    future_path = source_map.get("future_transaction_path", {})
    if future_path.get("path_status") != "IMPLEMENTED":
        errors.append("source map transaction path is not marked implemented")
    if future_path.get("fifo_payload") != [
        "source_sequence[OBS_SEQUENCE_WIDTH-1:0]", "raw_ch1", "raw_ch2", "source_offer_integrity_clean"
    ]:
        errors.append("source map future FIFO payload lacks atomic source integrity")
    if future_path.get("destination_attachment") != "EXPECTED_SEQUENCE_RESULT_FOR_THE_DELIVERED_TRANSACTION":
        errors.append("source map future transaction lacks delivered sequence-integrity attachment")
    if future_path.get("pipeline_fields") != [
        "fault_eval_valid",
        "fault_eval_sequence[SEQUENCE_WIDTH-1:0]",
        "fault_eval_bitmap[5:0]",
        "fault_eval_code[7:0]",
        "fault_eval_integrity_clean",
    ]:
        errors.append("source map future transaction fields are incomplete or unaligned")
    if future_path.get("alignment_identity") != "fault_eval_sequence":
        errors.append("source map future transaction lacks sequence identity")
    expected_width_fields = {
        "fault_eval_sequence_width": "OBS_SEQUENCE_WIDTH",
        "supported_sequence_widths": "16_TO_32",
        "sequence_arithmetic": "MODULO_2_POW_SEQUENCE_WIDTH",
        "classification_authority": "SHARED_STAGE2E_TRANSACTION_SEQUENCE_CLASSIFIER",
    }
    for key, value in expected_width_fields.items():
        if future_path.get(key) != value:
            errors.append(f"source map sequence-width mismatch for {key}")
    if "NO_PRE_RESET_EVALUATION" not in str(future_path.get("reset_rule", "")):
        errors.append("source map future transaction lacks reset flush rule")
    baseline_entries = source_map.get("baseline_entries")
    if not isinstance(baseline_entries, list) or len(baseline_entries) != 17:
        return ["source map must preserve exactly 17 baseline entries"]
    required_files = {
        "rtl/protection_fsm.v",
        "rtl/fault_classifier.v",
        "rtl/fault_defs.vh",
        "rtl/protection_core_top.v",
        "rtl/current_compare_dual.v",
        "rtl/sensor_health_monitor.v",
        "rtl/protection_reg_bank.v",
        "rtl/protection_ip_top_axi_lite.v",
        "rtl/protection_ip_top_async_adc_axi_lite.v",
        "rtl/adc_sample_cdc_bridge.v",
        "rtl/async_fifo_gray.v",
        "rtl/reset_release_sync.v",
        "rtl/adc_sample_code_normalizer.sv",
        "rtl/transaction_source_observer.v",
        "rtl/transaction_destination_observer.v",
        "rtl/pwm_gen.v",
        "rtl/pwm_gate.v",
    }
    actual_files = {
        entry.get("module_file")
        for entry in baseline_entries
        if isinstance(entry, dict)
    }
    missing = required_files - actual_files
    if missing:
        errors.append(f"source map missing required files: {sorted(missing)}")
    for index, entry in enumerate(baseline_entries):
        if not isinstance(entry, dict):
            errors.append(f"source map entry {index} is not an object")
            continue
        relative = entry.get("module_file")
        if not isinstance(relative, str) or not (root / relative).is_file():
            errors.append(f"source map entry {index} points to missing source {relative}")
        for field in ("signals", "clock_reset_domain", "producer", "consumer", "logic_kind", "current_semantics", "current_tests", "known_ambiguity"):
            if field not in entry or entry[field] in (None, "", []):
                errors.append(f"source map entry {relative} missing {field}")
        current_tests = entry.get("current_tests", [])
        if isinstance(current_tests, list):
            for test in current_tests:
                if not isinstance(test, str) or not (root / test).is_file():
                    errors.append(f"source map entry {relative} cites missing test {test}")
    classifier_rows = [
        entry
        for entry in baseline_entries
        if isinstance(entry, dict)
        and entry.get("module_file") == "rtl/fault_classifier.v"
    ]
    classifier_text = classifier_rows[0].get("current_semantics", "") if len(classifier_rows) == 1 else ""
    if "registered nonzero fault-presence result" not in classifier_text or "not a general evaluation-valid pulse" not in classifier_text:
        errors.append("source map does not correct current fault_valid semantics")

    implementation_entries = source_map.get("implementation_entries")
    if not isinstance(implementation_entries, list) or len(implementation_entries) < 9:
        errors.append("source map must contain at least nine implementation entries")
        return errors
    required_fields = (
        "implementation_id",
        "module_file",
        "module",
        "signals",
        "clock_reset_domain",
        "producer",
        "consumer",
        "logic_kind",
        "pipeline_offset",
        "reset_behavior",
        "visibility",
        "tests",
    )
    implementation_ids: list[str] = []
    for index, entry in enumerate(implementation_entries):
        if not isinstance(entry, dict):
            errors.append(f"implementation source-map entry {index} is not an object")
            continue
        implementation_id = entry.get("implementation_id")
        if isinstance(implementation_id, str):
            implementation_ids.append(implementation_id)
        for field in required_fields:
            if field not in entry or entry[field] in (None, "", []):
                errors.append(
                    f"implementation source-map entry {implementation_id} missing {field}"
                )
        relative = entry.get("module_file")
        if not isinstance(relative, str) or not (root / relative).is_file():
            errors.append(
                f"implementation source-map entry {implementation_id} points to missing source {relative}"
            )
        tests = entry.get("tests", [])
        if isinstance(tests, list):
            for test in tests:
                if not isinstance(test, str) or not (root / test).is_file():
                    errors.append(
                        f"implementation source-map entry {implementation_id} cites missing test {test}"
                    )
    if len(implementation_ids) != len(set(implementation_ids)):
        errors.append("implementation source-map IDs must be unique")
    required_ids = {
        "IMPL_SEQUENCE_CLASSIFIER",
        "IMPL_SOURCE_INTEGRITY_TRACKER",
        "IMPL_FIFO_SIDEBAND",
        "IMPL_FAULT_EVAL_PIPELINE",
        "IMPL_EPISODE_CONTROLLER",
        "IMPL_PROTECTION_CORE",
        "IMPL_REG_CONTROLLED_WRAPPER",
        "IMPL_AXI_WRAPPER",
        "IMPL_PUBLIC_COMPAT_BOUNDARY",
        "IMPL_PRODUCTION_SAFE_GATE",
    }
    if not required_ids.issubset(set(implementation_ids)):
        errors.append(
            "source map implementation coverage missing IDs: "
            f"{sorted(required_ids-set(implementation_ids))}"
        )
    trace = source_map.get("implemented_path_trace", {})
    traced_ids: set[str] = set()
    for path_name in ("source_to_public_status", "source_to_safe_output"):
        path_ids = trace.get(path_name)
        if not isinstance(path_ids, list) or not path_ids:
            errors.append(f"source map implemented trace missing {path_name}")
            continue
        traced_ids.update(str(value) for value in path_ids)
    if trace.get("public_recovery_boundary") != "IMPL_PUBLIC_COMPAT_BOUNDARY":
        errors.append("source map public recovery boundary is missing")
    if trace.get("path_status") != "IMPLEMENTED_AND_VALIDATED":
        errors.append("source map implemented path is not validated")
    if not required_ids.issubset(traced_ids):
        errors.append(
            "source map implemented trace does not cover all required implementation entries"
        )
    return errors


def validate_evidence_citation(root: Path, citation: str) -> str | None:
    match = re.fullmatch(r"(.+):(\d+)(?:-(\d+))?", citation)
    if match is None:
        return f"malformed evidence citation {citation}"
    path_text, start_text, end_text = match.groups()
    source = root / path_text
    if not source.is_file():
        return f"cites missing evidence {path_text}"
    start = int(start_text)
    end = int(end_text or start_text)
    if (
        Path(path_text) != LEGACY_FAULT_DEFS_PATH
        or start != 5
        or end != 11
    ):
        line_count = len(source.read_text(encoding="utf-8").splitlines())
        if start >= 1 and end >= start and end <= line_count:
            return None
        return f"cites invalid line range {citation}"

    shim = source.read_text(encoding="utf-8")
    include = '`include "generated/protection_register_map.vh"'
    if shim.count(include) != 1:
        return "legacy fault citation does not resolve through the generated authority"
    independent = re.findall(
        r"(?m)^\s*`define\s+FAULT_(?!DEFS_VH\b)[A-Z0-9_]+\b", shim
    )
    if independent:
        return "legacy fault citation resolves through a shim with numeric ownership"

    generated = root / GENERATED_FAULT_DEFS_PATH
    if not generated.is_file():
        return f"cites missing generated fault authority {GENERATED_FAULT_DEFS_PATH}"
    generated_text = generated.read_text(encoding="utf-8")
    for name, value in FROZEN_FAULT_DEFINITIONS.items():
        definition = rf"(?m)^\s*`define\s+{name}\s+8'h{value}\s*$"
        if re.search(definition, generated_text) is None:
            return f"generated fault authority changed frozen definition {name}"
    alias = (
        r"(?m)^\s*`define\s+FAULT_OC_WITH_SENSOR\s+"
        r"`FAULT_OC_WITH_ANY_SENSOR\s*$"
    )
    if re.search(alias, generated_text) is None:
        return "generated fault authority changed frozen alias FAULT_OC_WITH_SENSOR"
    return None


def validate_behavior_matrix(root: Path, matrix: dict[str, Any]) -> list[str]:
    expected = {
        "POWER_ON_RESET",
        "RESET_WAIT_ENTRY",
        "RESET_WAIT_EXIT",
        "FIRST_RAW_TRANSACTION",
        "FAULT_ON_FIRST_RAW_TRANSACTION",
        "NO_TRANSACTION_AFTER_RESET",
        "PERSISTENT_FAULT",
        "FAULT_SOURCE_REMOVAL",
        "CLEAR_WITH_LIVE_FAULT",
        "CLEAR_AFTER_SOURCE_REMOVAL",
        "FAULT_AND_CLEAR_SAME_CYCLE",
        "SECOND_FAULT_AFTER_FIRST",
        "SIMULTANEOUS_FAULTS",
        "RESET_DURING_ACTIVE_FAULT",
        "RESET_DURING_RECOVERY",
        "POST_CLEAR_FIRST_TRANSACTION",
        "FAULT_VALID_NOT_EVALUATION_VALID",
        "PIPELINE_LATENCY_OFFSETS",
        "CLEAR_ON_EVALUATION_RETIREMENT_EDGE",
        "CLEAR_BETWEEN_DELIVERY_AND_RETIREMENT",
        "CONTINUOUS_II1_CLEAR_REQUEST",
        "RESET_FLUSH_PENDING_EVALUATION",
    }
    errors: list[str] = []
    rows = matrix.get("scenarios")
    actual = {row.get("id") for row in rows if isinstance(row, dict)} if isinstance(rows, list) else set()
    if actual != expected:
        errors.append(f"current behavior matrix ids mismatch: missing={sorted(expected-actual)}, extra={sorted(actual-expected)}")
    vocabulary = set(matrix.get("classification_vocabulary", []))
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            errors.append("behavior matrix contains a non-object row")
            continue
        if not set(row.get("classification", [])) <= vocabulary:
            errors.append(f"behavior row {row.get('id')} uses an unknown classification")
        for field in ("observed_behavior", "evidence", "target_gap"):
            if not row.get(field):
                errors.append(f"behavior row {row.get('id')} missing {field}")
        for citation in row.get("evidence", []):
            if not isinstance(citation, str):
                errors.append(f"behavior row {row.get('id')} has a non-string evidence citation")
                continue
            citation_error = validate_evidence_citation(root, citation)
            if citation_error is not None:
                errors.append(f"behavior row {row.get('id')} {citation_error}")
    return errors


def documentation_path_errors(root: Path) -> list[str]:
    errors: list[str] = []
    path_pattern = re.compile(r"`((?:docs|spec|rtl|sw|fpga|tools|tb|sim)/[^`| ]+\.(?:md|json|py|tcl|v|sv|vh|h|c|ps1|sh))(?:\:\d+(?:-\d+)?)?`")
    for relative in (
        AUDIT_DOC,
        SOURCE_DOC,
        TRADEOFF_DOC,
        VERIFY_DOC,
        REVIEW_DOC,
        RECOVERY_DOC,
    ):
        path = root / relative
        if not path.is_file():
            errors.append(f"missing required document {relative.as_posix()}")
            continue
        text = path.read_text(encoding="utf-8")
        for match in path_pattern.finditer(text):
            if not (root / match.group(1)).is_file():
                errors.append(f"{relative.as_posix()} references missing {match.group(1)}")
    return errors


def cross_artifact_errors(root: Path, contract: dict[str, Any], document_texts: dict[str, str] | None = None) -> list[str]:
    """Check that the prose artifacts and target contract cannot disagree."""

    errors = validate_contract(contract, load_json(root / SCHEMA_PATH))
    if document_texts is None:
        document_texts = {
            "audit": (root / AUDIT_DOC).read_text(encoding="utf-8"),
            "source": (root / SOURCE_DOC).read_text(encoding="utf-8"),
            "tradeoff": (root / TRADEOFF_DOC).read_text(encoding="utf-8"),
            "verification": (root / VERIFY_DOC).read_text(encoding="utf-8"),
            "review": (root / REVIEW_DOC).read_text(encoding="utf-8"),
        }
    combined = "\n".join(document_texts.values())
    required_tokens = [
        "STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT",
        "STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION",
        "NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO",
        "FIRST_FAULT_LATCH_PER_EPISODE=YES",
        "FIRST_FAULT_IMMUTABLE_DURING_EPISODE=YES",
        "PERSISTENT_FAULT_RETRIGGER=NO",
        "LATER_FAULT_OVERWRITES_FIRST_CAUSE=NO",
        "SIMULTANEOUS_FAULT_PRIORITY=DETERMINISTIC",
        "SIMULTANEOUS_FAULT_INFORMATION_PRESERVED=YES",
        "CLEAR_WHILE_ANY_LIVE_FAULT=REJECT",
        "FAULT_AND_CLEAR_SAME_CYCLE=FAULT_PRIORITY",
        "SOURCE_REMOVAL_WITHOUT_CLEAR=REMAIN_LATCHED",
        "SUCCESSFUL_CLEAR_STARTS_NEW_EPISODE=YES",
        "POST_RECOVERY_FAULT_CAN_LATCH_AGAIN=YES",
        "FAULT_EVALUATION_TRANSACTION=EXPLICIT",
        "FAULT_EVALUATION_VALID_AUTHORITY=ONE_PER_ATOMIC_RAW_CDC_DESTINATION_DELIVERY",
        "FAULT_EVALUATION_SEQUENCE_ALIGNED=YES",
        "FAULT_EVALUATION_BITMAP_ALIGNED=YES",
        "FAULT_EVALUATION_INTEGRITY_ALIGNED=YES",
        "ZERO_BITMAP_IS_VALID_HEALTHY_EVALUATION=YES",
        "CURRENT_FAULT_VALID_IS_EVALUATION_VALID=NO",
        "CLEAR_PROTOCOL=REQUEST_EVALUATION_FENCED",
        "CLEAR_PENDING_NO_SAMPLE=REMAIN_LATCHED_SAFE",
        "CONTINUOUS_II1_CLEAR_PROGRESS=PASS",
        "PRE_REQUEST_EVALUATION_RESOLVES_CLEAR=NO",
        "CLEAR_RESOLUTION_TRANSACTION_RELEASES_SAFE_OUTPUT=NO",
        "POST_CLEAR_DESTINATION_STATE=RESET_WAIT",
        "POLICY_DECISION_CLOCK=ACLK",
        "POLICY_DECISION_CYCLE=FAULT_EVALUATION_RETIREMENT",
        "TRANSACTION_CORRELATED_INTEGRITY=EXPLICIT",
        "EVENTUALLY_CONSISTENT_SOURCE_COUNTER_GATES_POLICY=NO",
        "SOFTWARE_W1C_STICKY_GATES_POLICY=NO",
        "STAGE2E_ERROR_CLASSIFICATION=PASS",
        "REMAINING_CONTRACT_GAPS=2",
        "STAGE2G_IMPLEMENTATION_STARTED=NO",
        "RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO",
        "STAGE2_COMPLETE=NO",
    ]
    for token in required_tokens:
        if token not in combined:
            errors.append(f"cross-artifact token missing: {token}")
    if "FIRST_ELIGIBLE_TRANSACTION_ARMS_IMMEDIATELY" not in combined:
        errors.append("cross-artifact RESET_WAIT selection is missing")
    if "HEALTHY_QUALIFICATION_COUNT=1" not in combined:
        errors.append("cross-artifact healthy qualification count is missing")
    if "0x00..0x60" not in combined and "0x00 through 0x60" not in combined:
        errors.append("cross-artifact existing register range is missing")
    forbidden_claims = (
        "NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=YES",
        "NEW_AXI_OFFSETS_ADDED=YES",
        "REMAINING_CONTRACT_GAPS=1",
        "STAGE2G_IMPLEMENTATION_STARTED=YES",
        "RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=YES",
        "STAGE2_COMPLETE=YES",
        "CURRENT_FAULT_VALID_IS_EVALUATION_VALID=YES",
        "EVENTUALLY_CONSISTENT_SOURCE_COUNTER_GATES_POLICY=YES",
        "SOFTWARE_W1C_STICKY_GATES_POLICY=YES",
        "CLEAR_RESOLUTION_TRANSACTION_RELEASES_SAFE_OUTPUT=YES",
    )
    for token in forbidden_claims:
        if token in combined:
            errors.append(f"forbidden cross-artifact claim present: {token}")
    return errors


def _apply_fixture_mutation(contract: dict[str, Any], mutation: dict[str, Any]) -> None:
    if mutation.get("operation") != "set":
        raise AuditError(f"unsupported fixture operation: {mutation.get('operation')}")
    set_path(contract, str(mutation["path"]), copy.deepcopy(mutation.get("value")))


def validate_fixtures(root: Path, contract: dict[str, Any], schema: dict[str, Any]) -> tuple[int, int, list[str]]:
    errors: list[str] = []
    positive = load_json(root / FIXTURE_DIR / "positive_fixture.json")
    if positive.get("expected") != "PASS" or positive.get("mutations") != []:
        errors.append("positive fixture metadata is invalid")
    positive_path = root / positive.get("contract_path", "")
    if not positive_path.is_file() or validate_contract(load_json(positive_path), schema):
        errors.append("positive contract fixture did not validate")
    elif positive_path.read_bytes() != (root / CONTRACT_PATH).read_bytes():
        errors.append("positive contract fixture is not byte-identical to the authority")
    negative = load_json(root / FIXTURE_DIR / "negative_mutations.json")
    mutations = negative.get("mutations", [])
    passed_negative = 0
    for mutation in mutations:
        candidate = copy.deepcopy(contract)
        try:
            _apply_fixture_mutation(candidate, mutation)
            candidate_errors = validate_contract(candidate, schema)
        except (KeyError, IndexError, TypeError, AuditError) as exc:
            candidate_errors = [str(exc)]
        if candidate_errors and mutation.get("expected"):
            passed_negative += 1
        else:
            errors.append(f"negative fixture did not fail closed: {mutation.get('id')}")
    expected_count = int(negative.get("expected_count", -1))
    if expected_count != len(mutations):
        errors.append("negative fixture expected_count mismatch")
    return 1, passed_negative, errors


def validate_cross_fixtures(root: Path, contract: dict[str, Any]) -> tuple[int, list[str]]:
    manifest = load_json(root / FIXTURE_DIR / "cross_artifact_negative_mutations.json")
    mutations = manifest.get("mutations", [])
    errors: list[str] = []
    passed = 0
    docs = {
        "audit": (root / AUDIT_DOC).read_text(encoding="utf-8"),
        "source": (root / SOURCE_DOC).read_text(encoding="utf-8"),
        "tradeoff": (root / TRADEOFF_DOC).read_text(encoding="utf-8"),
        "verification": (root / VERIFY_DOC).read_text(encoding="utf-8"),
        "review": (root / REVIEW_DOC).read_text(encoding="utf-8"),
    }
    schema = load_json(root / SCHEMA_PATH)
    for mutation in mutations:
        candidate = copy.deepcopy(contract)
        try:
            _apply_fixture_mutation(candidate, mutation)
            candidate_errors = cross_artifact_errors(root, candidate, docs)
        except (KeyError, IndexError, TypeError, AuditError) as exc:
            candidate_errors = [str(exc)]
        if candidate_errors:
            passed += 1
        else:
            errors.append(f"cross-artifact fixture did not fail: {mutation.get('id')}")
    if int(manifest.get("expected_count", -1)) != len(mutations):
        errors.append("cross-artifact fixture expected_count mismatch")
    # Keep the schema variable intentionally loaded here: a missing schema must
    # fail the fixture gate rather than being hidden by a cached contract.
    if not isinstance(schema, dict):
        errors.append("cross-artifact fixture schema is not an object")
    return passed, errors


def validate_raw_authority_sources(root: Path) -> list[str]:
    errors: list[str] = []
    async_top = (root / "rtl/protection_ip_top_async_adc_axi_lite.v").read_text(encoding="utf-8")
    core = (root / "rtl/protection_core_top.v").read_text(encoding="utf-8")
    if ".sample_valid(dst_sample_valid)" not in async_top:
        errors.append("raw async top is no longer driven by dst_sample_valid")
    if "normalized_sample_valid" not in async_top:
        errors.append("Stage 2F-D normalizer fork is absent from async top")
    if "normalized_sample_valid" in core or "normalized_profile_valid" in core:
        errors.append("normalized telemetry appears in raw protection core")
    if "normalized_sample_valid" in (root / "rtl/protection_ip_top_reg_controlled.v").read_text(encoding="utf-8"):
        errors.append("normalized telemetry appears in controlled raw core wrapper")
    if "0x64" in (root / "docs/implementation/register_map.md").read_text(encoding="utf-8"):
        errors.append("existing register map contains a Stage 2G offset above 0x60")
    return errors


def validate_status_artifact(root: Path, status: dict[str, Any], contract: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    expected = {
        "branch": "codex/stage2g-reset-wait-first-fault-policy-implementation",
        "base_commit": "ef6a990b154edd03b0b144d7d7cd0e41303dc095",
        "previous_implementation_commit": "7f332bac77b0433e241a769faf161855894a8b77",
        "previous_audit_commit": PREVIOUS_AUDIT_COMMIT,
        "fault_evaluation_transaction": "EXPLICIT",
        "fault_evaluation_valid_authority": "ONE_PER_ATOMIC_RAW_CDC_DESTINATION_DELIVERY",
        "fault_evaluation_sequence_aligned": True,
        "fault_eval_sequence_width": "OBS_SEQUENCE_WIDTH",
        "supported_sequence_widths": "16_TO_32",
        "sequence_arithmetic": "MODULO_2_POW_SEQUENCE_WIDTH",
        "policy_integrity_equals_stage2e_transaction_classification": "PASS",
        "fault_evaluation_bitmap_aligned": True,
        "fault_evaluation_integrity_aligned": True,
        "zero_bitmap_is_valid_healthy_evaluation": True,
        "current_fault_valid_is_evaluation_valid": False,
        "fault_evaluation_latency_class": "FIXED_3_ACLK_EDGES_DELIVERY_TO_POLICY_DECISION_II1",
        "clear_protocol": "REQUEST_EVALUATION_FENCED",
        "clear_pending_no_sample": "REMAIN_FAULT_LATCHED_SAFE_INDEFINITELY",
        "continuous_ii1_clear_progress": "PASS",
        "pre_request_evaluation_resolves_clear": False,
        "clear_resolution_transaction_releases_safe_output": False,
        "policy_decision_clock": "ACLK",
        "policy_decision_cycle": "FAULT_EVALUATION_RETIREMENT",
        "transaction_correlated_integrity": "EXPLICIT",
        "eventually_consistent_source_counter_gates_policy": False,
        "software_w1c_sticky_gates_policy": False,
        "sequence_width_16": "PASS",
        "sequence_width_24": "PASS",
        "sequence_width_32": "PASS",
        "sequence_wrap_16": "PASS",
        "sequence_wrap_24": "PASS",
        "sequence_wrap_32": "PASS",
        "public_recovery_contract_addendum": "STAGE2G_PUBLIC_RECOVERY_OBSERVABILITY_IMPLEMENTATION_ADDENDUM_V1",
        "internal_episode_end": "LEGAL_CLEAR_ACCEPTANCE",
        "public_recovery_complete": "LATER_CLEAN_HEALTHY_EVALUATION_ENTERING_ARMED",
        "clear_acceptance_equals_public_recovery_complete": False,
        "public_status_owner": "EXISTING_STATUS_AND_FAULT_CODE_REGISTERS",
        "status_fault_latched_during_post_clear_reset_wait": 1,
        "fault_code_during_post_clear_reset_wait": "RETAIN_PRIOR_FIRST_CAUSE",
        "no_sample_post_clear_recovery_verified": False,
        "nonclean_post_clear_recovery_verified": False,
        "later_healthy_clears_compatibility_status": "PASS",
        "post_clear_fault_replaces_with_new_first_cause": "PASS",
        "reset_clears_compatibility_status": "PASS",
        "new_recovery_status_bit_added": False,
        "software_recovery_api_changed": False,
        "software_recovery_api_semantics_preserved": "PASS",
        "source_map_baseline_entries": 17,
        "source_map_implementation_entries": 10,
        "source_map_implemented_path_trace": "PASS",
        "stage2g_sample_event_authority": "ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT",
        "stage2g_fault_input_authority": "RAW_PROTECTION_EVALUATION",
        "normalized_telemetry_gates_fault_policy": False,
        "fault_episode_model": "EXPLICIT",
        "first_fault_latch_per_episode": True,
        "first_fault_immutable_during_episode": True,
        "persistent_fault_retrigger": False,
        "later_fault_overwrites_first_cause": False,
        "simultaneous_fault_priority": "DETERMINISTIC",
        "simultaneous_fault_information_preserved": True,
        "clear_while_any_live_fault": "REJECT",
        "fault_and_clear_same_cycle": "FAULT_PRIORITY",
        "source_removal_without_clear": "REMAIN_LATCHED",
        "successful_clear_starts_new_episode": True,
        "post_recovery_fault_can_latch_again": True,
        "healthy_qualification_count": 1,
        "post_clear_destination_state": "RESET_WAIT",
        "register_visibility_owner": "STAGE2H",
        "new_axi_offsets_added": False,
        "external_interface_change_required": False,
        "stage2g_implementation_started": True,
        "reset_wait_first_fault_policy_gap_closed": False,
        "remaining_contract_gaps": 2,
        "stage2_complete": False,
    }
    for key, value in expected.items():
        if status.get(key) != value:
            errors.append(f"status artifact mismatch for {key}: {status.get(key)!r} != {value!r}")
    if status.get("reset_wait_policy") != contract.get("reset_wait", {}).get("arming_policy"):
        errors.append("status RESET_WAIT policy disagrees with contract")
    if status.get("status_schema_version") != "stage2g-reset-wait-first-fault-policy-status-v4":
        errors.append("status artifact is not v4")
    if status.get("final_status_before_commit") != "STAGE2G_FUNCTIONAL_RTL_RECOVERY_OBSERVABILITY_HARDENING_IN_PROGRESS":
        errors.append("status artifact has an unexpected final status")
    return errors


def changed_paths(root: Path) -> list[str]:
    commands = [
        ["git", "diff", "--name-only", BASE_COMMIT],
        ["git", "diff", "--name-only", "--cached", BASE_COMMIT],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ]
    values: set[str] = set()
    for command in commands:
        completed = subprocess.run(command, cwd=root, text=True, encoding="utf-8", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if completed.returncode != 0:
            continue
        values.update(line.strip().replace("\\", "/") for line in completed.stdout.splitlines() if line.strip())
    return sorted(values)


def validate_scope(root: Path) -> list[str]:
    errors: list[str] = []
    disallowed = []
    for path in changed_paths(root):
        if path.startswith(ALLOWED_CHANGE_PREFIXES) or path in ALLOWED_CHANGE_FILES:
            continue
        # The audit is allowed to add a Stage 2G test under tb/, but no RTL or
        # production software changes are allowed. Keep this explicit.
        if path.startswith("tb/stage2g/"):
            continue
        disallowed.append(path)
    if disallowed:
        errors.append(f"scope contains forbidden changed paths: {disallowed}")
    for path in changed_paths(root):
        if path.startswith("rtl/") or path.startswith("sw/") or path.startswith("fpga/"):
            errors.append(f"functional/interface change is forbidden in audit: {path}")
    return errors


def audit_repository(root: Path, *, check_git: bool = False) -> dict[str, Any]:
    contract = load_json(root / CONTRACT_PATH)
    schema = load_json(root / SCHEMA_PATH)
    source_map = load_json(root / SOURCE_MAP_PATH)
    behavior = load_json(root / BEHAVIOR_PATH)
    status = load_json(root / STATUS_PATH)
    errors: list[str] = []
    errors.extend(validate_contract(contract, schema))
    errors.extend(validate_source_map(root, source_map))
    errors.extend(validate_behavior_matrix(root, behavior))
    errors.extend(validate_status_artifact(root, status, contract))
    errors.extend(documentation_path_errors(root))
    errors.extend(cross_artifact_errors(root, contract))
    errors.extend(validate_raw_authority_sources(root))
    positive_count, negative_count, fixture_errors = validate_fixtures(root, contract, schema)
    errors.extend(fixture_errors)
    cross_count, cross_errors = validate_cross_fixtures(root, contract)
    errors.extend(cross_errors)
    if check_git:
        branch = subprocess.run(["git", "branch", "--show-current"], cwd=root, text=True, encoding="utf-8", stdout=subprocess.PIPE, check=True).stdout.strip()
        if branch != BRANCH:
            errors.append(f"branch mismatch: {branch} != {BRANCH}")
        main = subprocess.run(["git", "rev-parse", "main"], cwd=root, text=True, encoding="utf-8", stdout=subprocess.PIPE, check=True).stdout.strip()
        if main != BASE_COMMIT:
            errors.append(f"main mismatch: {main} != {BASE_COMMIT}")
        remote = subprocess.run(["git", "rev-parse", "origin/main"], cwd=root, text=True, encoding="utf-8", stdout=subprocess.PIPE, check=True).stdout.strip()
        if remote != BASE_COMMIT:
            errors.append(f"origin/main mismatch: {remote} != {BASE_COMMIT}")
        errors.extend(validate_scope(root))
    return {
        "errors": errors,
        "positive_count": positive_count,
        "negative_count": negative_count,
        "negative_expected": int(load_json(root / FIXTURE_DIR / "negative_mutations.json").get("expected_count", 0)),
        "cross_count": cross_count,
        "cross_expected": int(load_json(root / FIXTURE_DIR / "cross_artifact_negative_mutations.json").get("expected_count", 0)),
        "source_entries": len(source_map.get("baseline_entries", []))
        + len(source_map.get("implementation_entries", [])),
        "source_baseline_entries": len(source_map.get("baseline_entries", [])),
        "source_implementation_entries": len(
            source_map.get("implementation_entries", [])
        ),
        "behavior_scenarios": len(behavior.get("scenarios", [])),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--no-git-check", action="store_true", help="skip branch/base and changed-path checks")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        result = audit_repository(root, check_git=not args.no_git_check)
    except (AuditError, OSError, subprocess.CalledProcessError) as exc:
        print(f"STAGE2G_STATIC_CONTRACT_AUDIT=FAIL\nERROR={exc}", file=sys.stderr)
        return 1
    if result["errors"]:
        print("STAGE2G_STATIC_CONTRACT_AUDIT=FAIL", file=sys.stderr)
        for error in result["errors"]:
            print(f"ERROR={error}", file=sys.stderr)
        return 1
    print("STAGE2G_STATIC_CONTRACT_AUDIT=PASS")
    print("STAGE2G_JSON_SCHEMA_VALIDATION=PASS")
    print(f"STAGE2G_POSITIVE_FIXTURES=PASS_{result['positive_count']}_OF_{result['positive_count']}")
    print(f"STAGE2G_NEGATIVE_FIXTURES=PASS_{result['negative_count']}_OF_{result['negative_expected']}")
    print(f"STAGE2G_CROSS_ARTIFACT_NEGATIVE_FIXTURES=PASS_{result['cross_count']}_OF_{result['cross_expected']}")
    print(f"STAGE2G_SOURCE_MAP=PASS_{result['source_entries']}_ENTRIES")
    print(
        "SOURCE_MAP_BASELINE_ENTRIES="
        f"PASS_{result['source_baseline_entries']}"
    )
    print(
        "SOURCE_MAP_IMPLEMENTATION_ENTRIES="
        f"PASS_{result['source_implementation_entries']}"
    )
    print("SOURCE_MAP_IMPLEMENTED_PATH_TRACE=PASS")
    print(f"STAGE2G_CURRENT_BEHAVIOR_MATRIX=PASS_{result['behavior_scenarios']}_SCENARIOS")
    print("STAGE2G_RAW_AUTHORITY_INVARIANCE=PASS")
    print("FAULT_EVALUATION_TRANSACTION=EXPLICIT")
    print("FAULT_EVALUATION_VALID_AUTHORITY=ONE_PER_ATOMIC_RAW_CDC_DESTINATION_DELIVERY")
    print("FAULT_EVALUATION_SEQUENCE_ALIGNED=YES")
    print("FAULT_EVAL_SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH")
    print("SUPPORTED_SEQUENCE_WIDTHS=16_TO_32")
    print("SEQUENCE_ARITHMETIC=MODULO_2_POW_SEQUENCE_WIDTH")
    print("FAULT_EVALUATION_BITMAP_ALIGNED=YES")
    print("FAULT_EVALUATION_INTEGRITY_ALIGNED=YES")
    print("ZERO_BITMAP_IS_VALID_HEALTHY_EVALUATION=YES")
    print("CURRENT_FAULT_VALID_IS_EVALUATION_VALID=NO")
    print("FAULT_EVALUATION_LATENCY_CLASS=FIXED_3_ACLK_EDGES_DELIVERY_TO_POLICY_DECISION_II1")
    print("CLEAR_PROTOCOL=REQUEST_EVALUATION_FENCED")
    print("CLEAR_PENDING_NO_SAMPLE=REMAIN_LATCHED_SAFE")
    print("CONTINUOUS_II1_CLEAR_PROGRESS=PASS")
    print("PRE_REQUEST_EVALUATION_RESOLVES_CLEAR=NO")
    print("CLEAR_RESOLUTION_TRANSACTION_RELEASES_SAFE_OUTPUT=NO")
    print("POST_CLEAR_DESTINATION_STATE=RESET_WAIT")
    print("POLICY_DECISION_CLOCK=ACLK")
    print("POLICY_DECISION_CYCLE=FAULT_EVALUATION_RETIREMENT")
    print("TRANSACTION_CORRELATED_INTEGRITY=EXPLICIT")
    print("EVENTUALLY_CONSISTENT_SOURCE_COUNTER_GATES_POLICY=NO")
    print("SOFTWARE_W1C_STICKY_GATES_POLICY=NO")
    print("STAGE2E_ERROR_CLASSIFICATION=PASS")
    print("POLICY_INTEGRITY_EQUALS_STAGE2E_TRANSACTION_CLASSIFICATION=PASS")
    print("NEW_AXI_OFFSETS_ADDED=NO")
    print("STAGE2G_IMPLEMENTATION_STARTED=YES")
    print("RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO")
    print("REMAINING_CONTRACT_GAPS=2")
    print("STAGE2_COMPLETE=NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
