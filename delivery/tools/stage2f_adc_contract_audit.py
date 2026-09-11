#!/usr/bin/env python3
"""Fail-closed static audit for the hardened Stage 2F ADC contract artifacts."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


BASE_COMMIT = "301bb72cafa3957392e9a64a5e6b2e97c4466886"
EXPECTED_BRANCH = "codex/stage2f-adc-encoding-scaling-audit"

FACT_PATH = Path("spec/stage2f_adc_fact_inventory.json")
TRACE_PATH = Path("spec/stage2f_adc_data_path_inventory.json")
AUTHORITY_PATH = Path("spec/stage2f_scaling_parameter_authority.json")
CLOSURE_PATH = Path("spec/stage2f_closure_boundary.json")
SOURCE_SCHEMA_PATH = Path("spec/stage2f_adc_source_profile.schema.json")
SOURCE_PROFILE_PATH = Path("spec/stage2f_adc_source_profile_unconfigured.json")
REFERENCE_PROFILE_PATH = Path("spec/stage3_reference_analog_profile.json")

AUDIT_DOC = Path("docs/architecture/stage2f_adc_encoding_scaling_audit.md")
TARGET_DOC = Path("docs/architecture/stage2f_adc_encoding_scaling_target_contract.md")
TRADEOFF_DOC = Path("docs/architecture/stage2f_adc_encoding_scaling_tradeoff.md")
VERIFY_DOC = Path("docs/verification/stage2f_adc_encoding_scaling_verification_plan.md")
REFERENCE_DOC = Path("docs/architecture/stage3_reference_analog_acquisition_profile.md")
PROJECT_COMPARISON_DOC = Path(
    "docs/architecture/stage3_public_reference_project_comparison.md"
)

SPEC_PATHS = (
    FACT_PATH,
    TRACE_PATH,
    AUTHORITY_PATH,
    CLOSURE_PATH,
    SOURCE_SCHEMA_PATH,
    SOURCE_PROFILE_PATH,
    REFERENCE_PROFILE_PATH,
)
DOCUMENT_PATHS = (
    AUDIT_DOC,
    TARGET_DOC,
    TRADEOFF_DOC,
    VERIFY_DOC,
    REFERENCE_DOC,
    PROJECT_COMPARISON_DOC,
)
REQUIRED_PATHS = SPEC_PATHS + DOCUMENT_PATHS

ALLOWED_CHANGE_PATHS = {path.as_posix() for path in REQUIRED_PATHS} | {
    "tools/stage2f_adc_contract_audit.py",
    "tools/build_stage2f_audit_review.py",
    "tools/tests/test_stage2f_adc_contract_audit.py",
}

CLASSIFICATIONS = {
    "REPOSITORY_FACT",
    "DERIVED_INFERENCE",
    "DESIGN_DECISION",
    "EXTERNAL_HARDWARE_UNKNOWN",
    "BOARD_CALIBRATION_REQUIRED",
    "OUT_OF_SCOPE",
}
FINDING_CLASSES = {
    "EXPLICIT_CONTRACT",
    "IMPLEMENTATION_ASSUMPTION",
    "TEST_ONLY_ASSUMPTION",
    "DOCUMENTATION_ONLY_CLAIM",
    "CONFLICT",
    "UNKNOWN",
}
AUTHORITY_TYPES = {
    "SYNTHESIS_TIME",
    "SOURCE_PROFILE",
    "IMPLEMENTATION_DERIVED",
    "RUNTIME_SOFTWARE",
    "NOT_SUPPORTED",
    "DEFERRED",
}
ENCODING_TAXONOMY = {"UNSIGNED_WITH_ZERO_CODE", "TWOS_COMPLEMENT"}
CONCEPTUAL_REGISTERS = {
    "SCALE_CAPABILITY",
    "SCALE_PROFILE_STATUS",
    "LATEST_NORMALIZED_CH1",
    "LATEST_NORMALIZED_CH2",
    "LATEST_NORMALIZED_SEQUENCE",
    "LATEST_NORMALIZED_FLAGS",
}

REQUIRED_FACT_IDS = {
    "F-WIDTH-001",
    "F-SIGNED-001",
    "F-ENCODING-001",
    "F-THRESHOLD-001",
    "F-THRESHOLD-002",
    "F-READBACK-001",
    "F-TEST-001",
    "F-HARDWARE-001",
    "F-HARDWARE-002",
    "F-HARDWARE-003",
    "F-HARDWARE-004",
    "F-HARDWARE-005",
    "F-HARDWARE-006",
    "F-HARDWARE-007",
    "F-CAL-001",
    "F-PINS-001",
    "F-SAMPLING-001",
    "F-RANGE-001",
    "F-TRUNCATION-001",
    "F-GAP-001",
    "F-PROFILE-001",
}
REQUIRED_NODE_IDS = {
    f"N{index:02d}_{suffix}"
    for index, suffix in (
        (1, "SAFE_INERT_SOURCE"),
        (2, "ADC_TOP_PORTS"),
        (3, "SOURCE_OBSERVER"),
        (4, "ATOMIC_FIFO_PACK"),
        (5, "ASYNC_FIFO"),
        (6, "ATOMIC_FIFO_UNPACK"),
        (7, "DESTINATION_OBSERVER"),
        (8, "ACCEPTED_SAMPLE_REGISTER"),
        (9, "OVERCURRENT_COMPARE"),
        (10, "MISMATCH_COMPARE"),
        (11, "SENSOR_HEALTH"),
        (12, "FAULT_POLICY"),
        (13, "RAW_MONITOR_READBACK"),
        (14, "ILA_RAW_PROBES"),
        (15, "THRESHOLD_WRITE_TRUNCATION"),
        (16, "AXI_REGISTER_BANK"),
        (17, "PYTHON_INTERFACE"),
        (18, "C_INTERFACE"),
        (19, "PYNQ_OVERLAY"),
        (20, "CANONICAL_TEST_STIMULUS"),
        (21, "STANDALONE_STAGE2_BD_PROFILE"),
        (22, "IP_PACKAGING_METADATA"),
        (23, "DOCUMENTATION_AND_DELIVERY_EXAMPLES"),
    )
}
REQUIRED_PARAMETERS = {
    "raw_width",
    "source_profile_state",
    "encoding",
    "zero_code",
    "channel_polarity",
    "normalized_width",
    "normalized_unit",
    "pipeline_latency",
    "pipeline_initiation_interval",
    "configuration_identity",
    "physical_unit_scale",
    "board_calibration_arithmetic",
    "generic_rational_divider",
    "overcurrent_thresholds",
    "difference_threshold",
    "normalized_protection_thresholds",
    "runtime_scaling_writes",
    "configuration_valid",
    "production_normalized_telemetry",
}
REQUIRED_CLOSURE_IDS = {
    "DF-CAPABILITY-001",
    "DF-COMPATIBILITY-001",
    "DF-THROUGHPUT-001",
    "PS-SELECTION-001",
    "PC-SCALE-001",
    "PC-CALIBRATION-001",
}
SOURCE_PROFILE_FIELDS = {
    "schema_version",
    "profile_state",
    "raw_width",
    "encoding",
    "zero_code",
    "channel_polarity",
    "profile_identity",
    "physical_unit_status",
    "production_selection",
}
REFERENCE_PROJECTS = {
    "DIGILENT_VIVADO_LIBRARY_PMODAD1": "OFFICIAL_IMPLEMENTATION_REFERENCE",
    "ADI_AD7476A_PMOD_FPGA_REFERENCE_PAGE": "OFFICIAL_IMPLEMENTATION_REFERENCE",
    "ADI_AD7476A_PMOD_XPS_OR_IPCORE_ARTIFACT": "OFFICIAL_IMPLEMENTATION_REFERENCE",
    "ADI_AD7476A_PMOD_LINUX_DEVICE_TREE": "OFFICIAL_SOFTWARE_INTEGRATION_REFERENCE",
    "AMILASHANAKA_PYNQ_PMOD_AD1": "COMMUNITY_INTEGRATION_REFERENCE",
    "RICCARDONICOLAIDIS_SAMPLER_PMOD_AD1": "COMMUNITY_EXPERIMENT_ONLY",
    "AMILASHANAKA_PMOD_AD1_DMA": "COMMUNITY_INTEGRATION_REFERENCE",
}
PUBLIC_CLASSIFICATIONS = {
    "OFFICIAL_INTERFACE_AUTHORITY",
    "OFFICIAL_IMPLEMENTATION_REFERENCE",
    "OFFICIAL_SOFTWARE_INTEGRATION_REFERENCE",
    "COMMUNITY_INTEGRATION_REFERENCE",
    "COMMUNITY_EXPERIMENT_ONLY",
}

UNKNOWN_HARDWARE_SUBJECTS = {
    "physical raw ADC encoding",
    "real ADC device",
    "reference voltage and analog input range",
    "AFE gain and sensor sensitivity",
    "real zero-current code and polarity",
    "real full-scale current range",
    "ADC connector and pin mapping",
    "real ADC sample rate and anti-alias filter",
}

REQUIRED_DOC_TOKENS = {
    AUDIT_DOC: (
        "CURRENT_RAW_SAMPLE_WIDTH=12",
        "CURRENT_RTL_INTERPRETATION=UNSIGNED",
        "CURRENT_RAW_ENCODING=UNKNOWN",
        "TH_DIFF_DOMAIN=UNSIGNED_RAW_CODE_DIFFERENCE",
        "DIGITAL_FOUNDATION_CLOSES_FROZEN_STAGE2F_GAP=NO",
        "STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT",
        "CURRENT_PRODUCTION_NORMALIZED_TELEMETRY=UNAVAILABLE_UNCONFIGURED",
        "STAGE2_DIGITAL_FOUNDATION_REQUIRES_PRODUCTION_ADC_SELECTION=NO",
        "STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE=YES",
        "STAGE2_VALIDATION_PROFILES_MAY_SELECT_EXPLICIT_ENCODINGS=YES",
        "STAGE2_VALIDATION_PROFILE_IS_PRODUCTION_SELECTION=NO",
        "PRODUCTION_SOURCE_SELECTION_OWNER=STAGE3",
        "PRODUCTION_NORMALIZED_TELEMETRY_WHILE_UNCONFIGURED=UNAVAILABLE",
        "SUPPORTED_ENCODING_CAPABILITY_IMPLEMENTED=FUTURE_STAGE2F_D",
        "CONTROLLED_DIGITAL_BOARD_VALIDATION_PROFILE=ALLOWED_NON_PRODUCTION",
        "RAW_PROTECTION_PATH_ACTIVE_AND_UNCHANGED=YES",
        "NORMALIZED_VALID_WHEN_UNCONFIGURED=NO",
        "REFERENCE_ANALOG_PROFILE=PYNQ_Z2_PMOD_AD1_DUAL_INA240_REFERENCE_V1",
        "REFERENCE_ANALOG_PROFILE_STATUS=REFERENCE_ONLY_NON_AUTHORITATIVE",
        "REMAINING_CONTRACT_GAPS=2",
    ),
    TARGET_DOC: (
        "RAW_CODE_PROTECTION_WITH_PARALLEL_SIGNED_NORMALIZED_TELEMETRY",
        "INITIAL_DIGITAL_TRANSFORM=ENCODING_THEN_NOMINAL_ZERO_REMOVAL_THEN_POLARITY",
        "UNSIGNED_WITH_ZERO_CODE",
        "TWOS_COMPLEMENT",
        "PIPELINE_LATENCY=IMPLEMENTATION_DERIVED_FIXED_CONSTANT",
        "PIPELINE_INITIATION_INTERVAL=1",
        "NO_BACKPRESSURE_TO_ATOMIC_CDC=YES",
        "GENERIC_RATIONAL_DIVIDER=NO",
        "CALIBRATION_ARITHMETIC=DEFERRED",
        "CONCEPTUAL_REGISTER_ACCESS=READ_ONLY",
        "NEW_REGISTER_OFFSETS_FINALIZED=NO",
        "STICKY_NORMALIZATION_STATUS=NO",
        "NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO",
        "STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE=YES",
        "NON_PRODUCTION_SIMULATION_PROFILES=SUPPORTED",
        "CONTROLLED_DIGITAL_BOARD_VALIDATION_PROFILE=ALLOWED_NON_PRODUCTION",
        "RAW_PROTECTION_PATH_ACTIVE_AND_UNCHANGED=YES",
        "NORMALIZED_VALID_WHEN_UNCONFIGURED=NO",
    ),
    TRADEOFF_DOC: (
        "A. Decode-only signed code counts",
        "B. Decode + polarity",
        "C. Decode + nominal zero + polarity",
        "D. Decode + per-channel offset",
        "E. Decode + arbitrary rational gain",
        "F. Software-only physical conversion",
        "G. Source-specific generated constant transform",
        "SELECTED_INITIAL_ARCHITECTURE=C_DECODE_NOMINAL_ZERO_AND_POLARITY",
        "BOARD_CALIBRATION_ACCURACY=EXTERNAL_EVIDENCE_REQUIRED",
    ),
    VERIFY_DOC: (
        "physical gap claimed closed while physical unit remains unsupported",
        "numeric latency conflicting with implementation-derived authority",
        "missing initiation interval",
        "unbounded runtime offset paired with a fixed intermediate-width claim",
        "DMA made mandatory for the protection path",
        "both Icarus and XSim",
        "configured profile identity equals UNCONFIGURED",
        "production-selected profile uses reserved identity",
    ),
    REFERENCE_DOC: (
        "PROFILE_ID=PYNQ_Z2_PMOD_AD1_DUAL_INA240_REFERENCE_V1",
        "ADC_DEVICE=dual AD7476A",
        "NOMINAL_CURRENT_PER_LSB_EXAMPLE=APPROX_3.22_MA",
        "ILLUSTRATIVE_ONLY=YES",
        "CALIBRATED=NO",
        "LOW_VOLTAGE_CURRENT_LIMITED_LAB_REFERENCE_ONLY=YES",
        "SEPARATE_ELECTRICAL_SAFETY_REVIEW_REQUIRED=YES",
        "PURCHASE_AUTHORIZATION=NO",
        "REFERENCE_BIDIRECTIONAL_NEGATIVE_OVERCURRENT_SUPPORTED_BY_CURRENT_RAW_PATH=NO",
        "REFERENCE_PROFILE_IS_END_TO_END_PROTECTION_COMPATIBLE=NO",
        "REFERENCE_PROFILE_REQUIRES_FUTURE_PROTECTION_DOMAIN_DECISION=YES",
        "FUTURE_STAGE4_END_TO_END_VALIDATION_REQUIREMENTS",
    ),
    PROJECT_COMPARISON_DOC: (
        "Digilent `vivado-library` PmodAD1",
        "Analog Devices AD7476A Pmod",
        "amilashanaka/PYNQ_PMOD_AD1",
        "riccardonicolaidis/Sampler_Pmod_AD1",
        "amilashanaka/PMOD_AD1_DMA",
        "ADI_AD7476A_PMOD_FPGA_REFERENCE_PAGE",
        "ADI_AD7476A_PMOD_XPS_OR_IPCORE_ARTIFACT",
        "ADI_AD7476A_PMOD_LINUX_DEVICE_TREE",
        "OFFICIAL_SOFTWARE_INTEGRATION_REFERENCE",
        "LINUX_DEVICE_TREE_IS_NOT_COMPLETE_FPGA_IMPLEMENTATION",
        "COMMUNITY_REPOSITORY_IS_HARDWARE_AUTHORITY=NO",
        "PUBLIC_REFERENCE_PROJECT_COMPARISON=PASS",
    ),
}


class DuplicateJsonKey(ValueError):
    """Raised when a machine-readable authority contains duplicate keys."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJsonKey(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _load_json(root: Path, relative: Path, errors: list[str]) -> dict[str, Any]:
    path = root / relative
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object)
    except (OSError, UnicodeError, json.JSONDecodeError, DuplicateJsonKey) as exc:
        errors.append(f"{relative.as_posix()}: invalid JSON: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{relative.as_posix()}: top level must be an object")
        return {}
    return value


def _duplicates(values: list[str]) -> set[str]:
    seen: set[str] = set()
    repeated: set[str] = set()
    for value in values:
        if value in seen:
            repeated.add(value)
        seen.add(value)
    return repeated


def _reference_path(reference: str) -> Path:
    match = re.fullmatch(r"(.+?):\d+(?:-\d+)?", reference)
    return Path(match.group(1) if match else reference)


def _is_json_type(value: Any, type_name: str) -> bool:
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


def _validate_schema_value(
    schema: dict[str, Any], value: Any, location: str, errors: list[str]
) -> None:
    """Validate the JSON Schema subset used by the deliberately small profile."""

    type_value = schema.get("type")
    if isinstance(type_value, str) and not _is_json_type(value, type_value):
        errors.append(f"source profile schema validation: {location} must be {type_value}")
        return
    if isinstance(type_value, list) and not any(
        isinstance(item, str) and _is_json_type(value, item) for item in type_value
    ):
        errors.append(f"source profile schema validation: {location} has invalid type")
        return
    if "const" in schema and value != schema["const"]:
        errors.append(
            f"source profile schema validation: {location} must equal {schema['const']!r}"
        )
    enum = schema.get("enum")
    if isinstance(enum, list) and value not in enum:
        errors.append(f"source profile schema validation: {location} not in enum")

    negative = schema.get("not")
    if isinstance(negative, dict):
        negative_errors: list[str] = []
        _validate_schema_value(negative, value, location, negative_errors)
        if not negative_errors:
            errors.append(f"source profile schema validation: {location} matches forbidden schema")

    one_of = schema.get("oneOf")
    if isinstance(one_of, list):
        passes = 0
        for candidate in one_of:
            candidate_errors: list[str] = []
            if isinstance(candidate, dict):
                _validate_schema_value(candidate, value, location, candidate_errors)
            else:
                candidate_errors.append("invalid schema")
            if not candidate_errors:
                passes += 1
        if passes != 1:
            errors.append(
                f"source profile schema validation: {location} must match exactly one schema"
            )

    if isinstance(value, str):
        if isinstance(schema.get("minLength"), int) and len(value) < schema["minLength"]:
            errors.append(f"source profile schema validation: {location} is too short")
        if isinstance(schema.get("maxLength"), int) and len(value) > schema["maxLength"]:
            errors.append(f"source profile schema validation: {location} is too long")
        pattern = schema.get("pattern")
        if isinstance(pattern, str) and re.fullmatch(pattern, value) is None:
            errors.append(f"source profile schema validation: {location} fails pattern")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(schema.get("minimum"), (int, float)) and value < schema["minimum"]:
            errors.append(f"source profile schema validation: {location} is below minimum")
        if isinstance(schema.get("maximum"), (int, float)) and value > schema["maximum"]:
            errors.append(f"source profile schema validation: {location} is above maximum")

    if isinstance(value, dict):
        required = schema.get("required", [])
        if isinstance(required, list):
            for key in required:
                if isinstance(key, str) and key not in value:
                    errors.append(
                        f"source profile schema validation: {location}.{key} is required"
                    )
        properties = schema.get("properties", {})
        if isinstance(properties, dict):
            if schema.get("additionalProperties") is False:
                extras = set(value) - set(properties)
                if extras:
                    errors.append(
                        "source profile schema validation: unexpected fields at "
                        f"{location}: {', '.join(sorted(extras))}"
                    )
            for key, child_schema in properties.items():
                if key in value and isinstance(child_schema, dict):
                    _validate_schema_value(
                        child_schema, value[key], f"{location}.{key}", errors
                    )

    all_of = schema.get("allOf")
    if isinstance(all_of, list):
        for clause in all_of:
            if not isinstance(clause, dict):
                errors.append("source profile schema validation: invalid allOf clause")
                continue
            condition = clause.get("if")
            consequence = clause.get("then")
            if isinstance(condition, dict) and isinstance(consequence, dict):
                condition_errors: list[str] = []
                _validate_schema_value(condition, value, location, condition_errors)
                if not condition_errors:
                    _validate_schema_value(consequence, value, location, errors)
            else:
                _validate_schema_value(clause, value, location, errors)


def validate_source_profile_contract(
    schema: dict[str, Any], instance: dict[str, Any]
) -> list[str]:
    errors: list[str] = []
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        errors.append("source profile schema must declare JSON Schema draft 2020-12")
    if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
        errors.append("source profile schema must be a closed object")
    if set(schema.get("required", [])) != SOURCE_PROFILE_FIELDS:
        errors.append("source profile schema required field set is incomplete or over-general")
    properties = schema.get("properties")
    if not isinstance(properties, dict) or set(properties) != SOURCE_PROFILE_FIELDS:
        errors.append("source profile schema property set is incomplete or over-general")
    else:
        encoding_values = properties.get("encoding", {}).get("enum", [])
        if set(encoding_values) != ENCODING_TAXONOMY | {"UNKNOWN"}:
            errors.append("source profile encoding taxonomy is incomplete or redundant")
        if properties.get("raw_width", {}).get("const") != 12:
            errors.append("source profile raw width must be 12")
    _validate_schema_value(schema, instance, "$", errors)
    return errors


def configured_simulation_profile() -> dict[str, Any]:
    """Return a valid non-production profile used to exercise schema semantics."""

    return {
        "schema_version": "stage2f-adc-source-profile-v1",
        "profile_state": "CONFIGURED_DIGITAL",
        "raw_width": 12,
        "encoding": "UNSIGNED_WITH_ZERO_CODE",
        "zero_code": 2048,
        "channel_polarity": {
            "channel_1": "INCREASING_CODE_IS_POSITIVE",
            "channel_2": "INCREASING_CODE_IS_NEGATIVE",
        },
        "profile_identity": "SIM_UNSIGNED_MIDSCALE",
        "physical_unit_status": "NOT_CONFIGURED",
        "production_selection": False,
    }


def _check_source_profile_examples(schema: dict[str, Any], errors: list[str]) -> None:
    valid = configured_simulation_profile()
    if validate_source_profile_contract(schema, valid):
        errors.append("valid configured simulation profile must pass")
    reserved = dict(valid)
    reserved["profile_identity"] = "UNCONFIGURED"
    if not validate_source_profile_contract(schema, reserved):
        errors.append("configured profile with reserved identity must fail")
    production_reserved = dict(reserved)
    production_reserved["production_selection"] = True
    if not validate_source_profile_contract(schema, production_reserved):
        errors.append("production-selected profile with reserved identity must fail")


def _check_fact_inventory(
    root: Path,
    data: dict[str, Any],
    errors: list[str],
    validate_references: bool,
) -> None:
    if data.get("schema_version") != "stage2f-adc-fact-inventory-v1":
        errors.append("fact inventory schema_version is invalid")
    if data.get("audit_base_commit") != BASE_COMMIT:
        errors.append("fact inventory base commit differs from the frozen Stage 2E commit")
    if set(data.get("classification_vocabulary", [])) != CLASSIFICATIONS:
        errors.append("fact inventory classification vocabulary is incomplete or contradictory")
    if set(data.get("finding_vocabulary", [])) != FINDING_CLASSES:
        errors.append("fact inventory finding vocabulary is incomplete or contradictory")

    state = data.get("audit_state")
    if not isinstance(state, dict):
        errors.append("fact inventory audit_state is missing")
        state = {}
    expected_state = {
        "current_raw_sample_width": 12,
        "current_raw_encoding": "UNKNOWN",
        "current_rtl_interpretation": "UNSIGNED",
        "current_threshold_domain": "UNSIGNED_RAW_CODE",
        "th_diff_domain": "UNSIGNED_RAW_CODE_DIFFERENCE",
        "raw_readback": "ZERO_EXTENDED_12_BIT",
        "threshold_write_range_behavior": "SILENT_LOW_12_BIT_TRUNCATION",
        "real_adc_device": "UNKNOWN",
        "real_afe_gain": "UNKNOWN",
        "real_sensor_sensitivity": "UNKNOWN",
        "real_zero_current_code": "UNKNOWN",
        "real_current_range": "UNKNOWN",
        "board_calibration_data": "NOT_AVAILABLE",
        "production_input_source": "SAFE_INERT_DIGITAL_PLACEHOLDER",
        "current_production_profile": "UNCONFIGURED",
        "current_production_normalized_telemetry": "UNAVAILABLE_UNCONFIGURED",
        "raw_protection_active_behavior": "UNCHANGED",
        "stage2f_implementation_started": False,
        "stage2f_contract_gap_closed": False,
        "remaining_contract_gaps": 2,
        "stage2_complete": False,
    }
    for key, expected in expected_state.items():
        if state.get(key) != expected:
            errors.append(f"audit_state {key} must be {expected!r}, got {state.get(key)!r}")

    facts = data.get("facts")
    if not isinstance(facts, list):
        errors.append("fact inventory facts must be an array")
        return
    rows = [row for row in facts if isinstance(row, dict)]
    if len(rows) != len(facts):
        errors.append("every fact inventory entry must be an object")
    ids = [str(row.get("id", "")) for row in rows]
    for duplicate in sorted(_duplicates(ids)):
        errors.append(f"duplicate fact id: {duplicate}")
    missing = REQUIRED_FACT_IDS - set(ids)
    if missing:
        errors.append(f"required fact ids missing: {', '.join(sorted(missing))}")

    authoritative_widths: set[Any] = {state.get("current_raw_sample_width")}
    authoritative_signedness: set[Any] = set()
    by_id = {str(row.get("id")): row for row in rows}
    for row in rows:
        classification = row.get("classification")
        finding = row.get("finding_classification")
        if classification not in CLASSIFICATIONS:
            errors.append(f"fact {row.get('id')} has invalid classification {classification!r}")
        if finding not in FINDING_CLASSES:
            errors.append(
                f"fact {row.get('id')} has invalid finding classification {finding!r}"
            )
        subject = row.get("subject")
        if subject == "production sample width" and classification == "REPOSITORY_FACT":
            authoritative_widths.add(row.get("value"))
        if subject == "current RTL sample signedness" and classification == "REPOSITORY_FACT":
            authoritative_signedness.add(row.get("value"))
        if subject in UNKNOWN_HARDWARE_SUBJECTS:
            if row.get("value") != "UNKNOWN" or classification == "REPOSITORY_FACT":
                errors.append(
                    f"unknown hardware constant represented as a fact: {subject}={row.get('value')!r}"
                )
        evidence = row.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            errors.append(f"fact {row.get('id')} must cite at least one evidence path")
        elif validate_references:
            for reference in evidence:
                if not isinstance(reference, str) or not (
                    root / _reference_path(reference)
                ).is_file():
                    errors.append(
                        f"fact {row.get('id')} evidence path does not exist: {reference!r}"
                    )

    if authoritative_widths != {12}:
        errors.append(f"conflicting authoritative raw widths: {sorted(map(str, authoritative_widths))}")
    if authoritative_signedness != {"UNSIGNED"}:
        errors.append(
            "signedness authority conflict: expected only UNSIGNED, got "
            + ", ".join(sorted(map(str, authoritative_signedness)))
        )
    if by_id.get("F-THRESHOLD-001", {}).get("value") != "UNSIGNED_RAW_CODE":
        errors.append("threshold domain undocumented or contradictory for TH_OC1/TH_OC2")
    if by_id.get("F-THRESHOLD-002", {}).get("value") != "UNSIGNED_RAW_CODE_DIFFERENCE":
        errors.append("threshold domain undocumented or contradictory for TH_DIFF")
    if by_id.get("F-PROFILE-001", {}).get("value") != "UNCONFIGURED":
        errors.append("current production source profile must remain UNCONFIGURED")


def _check_trace_inventory(
    root: Path,
    data: dict[str, Any],
    errors: list[str],
    validate_references: bool,
) -> None:
    if data.get("schema_version") != "stage2f-adc-data-path-inventory-v1":
        errors.append("data-path inventory schema_version is invalid")
    if data.get("audit_base_commit") != BASE_COMMIT:
        errors.append("data-path inventory base commit differs from the frozen Stage 2E commit")
    if data.get("payload_order") != "{sequence, channel_1, channel_2}":
        errors.append("data-path inventory atomic payload order is missing or changed")

    future = data.get("future_architecture")
    expected_future = {
        "selected_architecture": "ATOMIC_RAW_CDC_DESTINATION_DELIVERY_TO_RAW_PROTECTION_AND_PARALLEL_SIGNED_CODE_COUNT_TELEMETRY",
        "raw_path_unchanged": True,
        "stage2g_sample_event_authority": "ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT",
        "stage2g_fault_input_authority": "RAW_PROTECTION_EVALUATION",
        "normalized_telemetry_gates_fault_policy": False,
        "normalized_range_flags_gate_fault_policy": False,
        "normalized_configuration_valid_gates_fault_policy": False,
        "normalized_domain_protection": "FUTURE_VERSIONED_SAFETY_CONTRACT_REQUIRED",
        "current_production_profile": "UNCONFIGURED",
        "current_production_normalized_telemetry": "UNAVAILABLE_UNCONFIGURED",
    }
    if not isinstance(future, dict):
        errors.append("data-path future architecture is missing")
    else:
        for key, expected in expected_future.items():
            if future.get(key) != expected:
                errors.append(
                    f"data-path future architecture {key} must be {expected!r}, got {future.get(key)!r}"
                )

    nodes = data.get("nodes")
    if not isinstance(nodes, list):
        errors.append("data-path inventory nodes must be an array")
        return
    rows = [row for row in nodes if isinstance(row, dict)]
    node_ids = [str(row.get("node", "")) for row in rows]
    for duplicate in sorted(_duplicates(node_ids)):
        errors.append(f"duplicate data-path node: {duplicate}")
    missing = REQUIRED_NODE_IDS - set(node_ids)
    if missing:
        errors.append(f"required data-path nodes missing: {', '.join(sorted(missing))}")
    required_fields = {
        "node",
        "file",
        "symbol",
        "clock_domain",
        "width",
        "signedness",
        "encoding_claim",
        "unit_claim",
        "authority_type",
        "used_by",
        "confidence",
        "notes",
        "transformation",
    }
    physical_unit_pattern = re.compile(
        r"(^|_)(AMPERES?|MILLIAMPERES?|MICROAMPERES?|MA|UA)($|_)"
    )
    for row in rows:
        missing_fields = required_fields - set(row)
        if missing_fields:
            errors.append(
                f"data-path node {row.get('node')} missing fields: "
                + ", ".join(sorted(missing_fields))
            )
        unit_claim = str(row.get("unit_claim", "")).upper()
        if physical_unit_pattern.search(unit_claim):
            errors.append(
                f"unsupported physical-unit claim in data-path node {row.get('node')}: {unit_claim}"
            )
        file_value = row.get("file")
        if validate_references and (
            not isinstance(file_value, str) or not (root / file_value).is_file()
        ):
            errors.append(f"data-path node {row.get('node')} file does not exist: {file_value!r}")
    by_id = {str(row.get("node")): row for row in rows}
    for node_id in ("N09_OVERCURRENT_COMPARE", "N10_MISMATCH_COMPARE"):
        if by_id.get(node_id, {}).get("signedness") != "UNSIGNED":
            errors.append(f"signedness authority conflict at {node_id}")


def _check_authorities(data: dict[str, Any], errors: list[str]) -> None:
    if data.get("schema_version") != "stage2f-scaling-parameter-authority-v2":
        errors.append("scaling authority schema_version is invalid")
    if data.get("audit_base_commit") != BASE_COMMIT:
        errors.append("scaling authority base commit differs from the frozen Stage 2E commit")
    expected_top = {
        "recommended_architecture": "RAW_CODE_PROTECTION_WITH_PARALLEL_SIGNED_NORMALIZED_TELEMETRY",
        "digital_foundation_transform": "ENCODING_THEN_NOMINAL_ZERO_REMOVAL_THEN_POLARITY",
        "recommended_normalized_representation": "SIGNED_13_BIT_CODE_COUNTS",
        "recommended_threshold_domain": "UNSIGNED_RAW_CODE_COMPATIBILITY",
        "current_production_normalized_telemetry": "UNAVAILABLE_UNCONFIGURED",
        "calibration_arithmetic": "DEFERRED",
        "generic_rational_divider": False,
    }
    for key, expected in expected_top.items():
        if data.get(key) != expected:
            if key == "current_production_normalized_telemetry":
                errors.append("production UNCONFIGURED profile claimed as normalized functional")
            else:
                errors.append(f"scaling authority {key} must be {expected!r}")
    if set(data.get("encoding_taxonomy", [])) != ENCODING_TAXONOMY:
        errors.append("encoding taxonomy is incomplete or contains redundant modes")
    if set(data.get("authority_types", [])) != AUTHORITY_TYPES:
        errors.append("scaling authority type vocabulary is incomplete or contradictory")

    pipeline = data.get("pipeline_contract")
    if not isinstance(pipeline, dict):
        errors.append("pipeline latency and throughput contract is missing")
        pipeline = {}
    latency = pipeline.get("pipeline_latency")
    if isinstance(latency, (int, float)) and not isinstance(latency, bool):
        errors.append("numeric latency conflicts with implementation-derived authority")
    elif latency != "IMPLEMENTATION_DERIVED_FIXED_CONSTANT":
        errors.append("pipeline latency must be IMPLEMENTATION_DERIVED_FIXED_CONSTANT")
    if "pipeline_initiation_interval" not in pipeline:
        errors.append("missing initiation interval under no-ready input contract")
    elif pipeline.get("pipeline_initiation_interval") != 1:
        errors.append("pipeline initiation interval must be 1")
    expected_pipeline = {
        "no_data_dependent_latency": True,
        "no_backpressure_to_atomic_cdc": True,
        "no_transaction_drop": True,
        "latency_capability_metadata_required": True,
        "consumers_use_valid_and_sequence": True,
    }
    for key, expected in expected_pipeline.items():
        if pipeline.get(key) != expected:
            errors.append(f"pipeline contract {key} must be {expected!r}")

    stage2g = data.get("stage2g_contract")
    expected_stage2g = {
        "sample_event_authority": "ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT",
        "fault_input_authority": "RAW_PROTECTION_EVALUATION",
        "normalized_telemetry_gates_fault_policy": False,
        "normalized_range_flags_gate_fault_policy": False,
        "normalized_configuration_valid_gates_fault_policy": False,
        "normalized_domain_protection": "FUTURE_VERSIONED_SAFETY_CONTRACT_REQUIRED",
    }
    if not isinstance(stage2g, dict):
        errors.append("Stage 2G dependency contract is missing")
        stage2g = {}
    for key, expected in expected_stage2g.items():
        if stage2g.get(key) != expected:
            if key.startswith("normalized_") and key.endswith("gates_fault_policy"):
                errors.append("telemetry-only path paired with Stage 2G normalized gating")
            else:
                errors.append(f"Stage 2G contract {key} must be {expected!r}")

    arithmetic = data.get("arithmetic_scope")
    if not isinstance(arithmetic, dict):
        errors.append("arithmetic scope decision is missing")
        arithmetic = {}
    if arithmetic.get("runtime_offset_supported") is True and (
        arithmetic.get("offset_bounds") is None
        or arithmetic.get("fixed_intermediate_width_claim") is True
    ):
        errors.append("unbounded offset paired with fixed intermediate-width claim")
    expected_arithmetic = {
        "runtime_offset_supported": False,
        "offset_bounds": None,
        "fixed_intermediate_width_claim": False,
        "runtime_rational_gain_supported": False,
        "generic_signed_divider_supported": False,
        "board_calibration_arithmetic": "DEFERRED",
        "source_specific_generated_constant_transform": "DEFERRED_UNTIL_APPROVED_PHYSICAL_PROFILE",
    }
    for key, expected in expected_arithmetic.items():
        if arithmetic.get(key) != expected:
            errors.append(f"initial arithmetic scope {key} must be {expected!r}")

    register = data.get("register_contract")
    if not isinstance(register, dict):
        errors.append("register status semantics are missing")
        register = {}
    if register.get("sticky_status_supported") is True:
        sticky = register.get("sticky_clear_semantics")
        required_sticky = {
            "event_source",
            "access_type",
            "writable_mask",
            "clear_mechanism",
            "same_cycle_event_priority",
            "reset_behavior",
            "software_helper",
        }
        if not isinstance(sticky, dict) or not required_sticky.issubset(sticky):
            errors.append("read-only register paired with undefined sticky clear semantics")
        errors.append("sticky normalization status is not justified by the initial contract")
    expected_register = {
        "existing_offsets_through_0x60": "UNCHANGED",
        "new_register_offsets_finalized": False,
        "access_type": "READ_ONLY",
        "sticky_status_supported": False,
        "sticky_clear_semantics": None,
        "snapshot_consistency": "SEQUENCE_CHANNELS_FLAGS_SEQUENCE_RETRY_UNTIL_SEQUENCE_MATCHES",
        "field_and_offset_freeze_owner": "STAGE2H_SINGLE_SOURCE_REGISTER_GENERATION",
    }
    for key, expected in expected_register.items():
        if register.get(key) != expected:
            errors.append(f"register contract {key} must be {expected!r}")
    if set(register.get("conceptual_outputs", [])) != CONCEPTUAL_REGISTERS:
        errors.append("conceptual read-only register set is incomplete or over-allocated")

    parameters = data.get("parameters")
    if not isinstance(parameters, list):
        errors.append("scaling authority parameters must be an array")
        return
    rows = [row for row in parameters if isinstance(row, dict)]
    names = [str(row.get("parameter", "")) for row in rows]
    for duplicate in sorted(_duplicates(names)):
        errors.append(f"duplicate scaling-parameter authority: {duplicate}")
    missing = REQUIRED_PARAMETERS - set(names)
    extra = set(names) - REQUIRED_PARAMETERS
    if missing:
        errors.append(f"required scaling parameters missing: {', '.join(sorted(missing))}")
    if extra:
        errors.append(f"unsupported scaling parameters added: {', '.join(sorted(extra))}")
    for row in rows:
        if row.get("authority") not in AUTHORITY_TYPES:
            errors.append(
                f"parameter {row.get('parameter')} has invalid authority {row.get('authority')!r}"
            )
        if not row.get("authority_artifact"):
            errors.append(f"parameter {row.get('parameter')} has no authority artifact")

    by_name = {str(row.get("parameter")): row for row in rows}
    exact_parameters = {
        "raw_width": 12,
        "source_profile_state": "UNCONFIGURED",
        "encoding": "UNKNOWN",
        "zero_code": None,
        "channel_polarity": "UNKNOWN",
        "normalized_width": 13,
        "normalized_unit": "SIGNED_CODE_COUNT",
        "pipeline_latency": "IMPLEMENTATION_DERIVED_FIXED_CONSTANT",
        "pipeline_initiation_interval": 1,
        "configuration_identity": "UNCONFIGURED",
        "physical_unit_scale": "NONE",
        "board_calibration_arithmetic": "DEFERRED",
        "generic_rational_divider": False,
        "normalized_protection_thresholds": "NONE",
        "runtime_scaling_writes": "NONE",
        "configuration_valid": False,
        "production_normalized_telemetry": "UNAVAILABLE_UNCONFIGURED",
    }
    for name, expected in exact_parameters.items():
        if by_name.get(name, {}).get("target_value") != expected:
            errors.append(f"scaling parameter {name} must target {expected!r}")
    physical = by_name.get("physical_unit_scale", {})
    if physical.get("authority") != "NOT_SUPPORTED":
        errors.append("unsupported physical-unit claim without a scaling authority")
    if by_name.get("board_calibration_arithmetic", {}).get("authority") != "DEFERRED":
        errors.append("board calibration arithmetic must remain deferred")
    if by_name.get("pipeline_latency", {}).get("authority") != "IMPLEMENTATION_DERIVED":
        errors.append("conflicting pipeline latency authority")


def _check_closure(data: dict[str, Any], errors: list[str]) -> None:
    if data.get("schema_version") != "stage2f-closure-boundary-v2":
        errors.append("closure boundary schema_version is invalid")
    expected = {
        "frozen_gap": "ADC_ENCODING_AND_PHYSICAL_SCALING",
        "remaining_contract_gaps": 2,
        "digital_foundation_scope": "EXPLICIT_ENCODING_AND_SIGNED_CODE_NORMALIZATION",
        "physical_closure_scope": "SOURCE_SPECIFIC_CODE_TO_CURRENT_SCALING_AND_CALIBRATION_AUTHORITY",
        "digital_foundation_closes_frozen_stage2f_gap": False,
        "physical_scaling_status": "BLOCKED_EXTERNAL_HARDWARE_FACTS",
        "physical_closure_prerequisite": "APPROVED_ADC_AFE_SENSOR_PROFILE_OR_OWNER_APPROVED_SCOPE_CHANGE",
        "stage2_digital_foundation_requires_production_adc_selection": False,
        "stage2_digital_foundation_can_freeze_with_unconfigured_production_profile": True,
        "stage2_validation_profiles_may_select_explicit_encodings": True,
        "stage2_validation_profile_is_production_selection": False,
        "production_source_selection_owner": "STAGE3",
        "production_normalized_telemetry_while_unconfigured": "UNAVAILABLE",
        "STAGE2_DIGITAL_FOUNDATION_REQUIRES_PRODUCTION_ADC_SELECTION": "NO",
        "STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE": "YES",
        "STAGE2_VALIDATION_PROFILES_MAY_SELECT_EXPLICIT_ENCODINGS": "YES",
        "STAGE2_VALIDATION_PROFILE_IS_PRODUCTION_SELECTION": "NO",
        "PRODUCTION_SOURCE_SELECTION_OWNER": "STAGE3",
        "PRODUCTION_NORMALIZED_TELEMETRY_WHILE_UNCONFIGURED": "UNAVAILABLE",
        "SUPPORTED_ENCODING_CAPABILITY_IMPLEMENTED": "FUTURE_STAGE2F_D",
        "PRODUCTION_PROFILE": "UNCONFIGURED",
        "NON_PRODUCTION_SIMULATION_PROFILES": "SUPPORTED",
        "CONTROLLED_DIGITAL_BOARD_VALIDATION_PROFILE": "ALLOWED_NON_PRODUCTION",
        "RAW_PROTECTION_PATH_ACTIVE_AND_UNCHANGED": "YES",
        "NORMALIZED_VALID_WHEN_UNCONFIGURED": "NO",
    }
    for key, value in expected.items():
        if data.get(key) != value:
            if key == "remaining_contract_gaps":
                errors.append("digital foundation reduces remaining gap count")
            elif key == "digital_foundation_closes_frozen_stage2f_gap":
                errors.append("digital foundation incorrectly claims the frozen Stage 2F gap closed")
            elif key == "physical_scaling_status":
                errors.append("physical gap claimed closed while physical unit remains unsupported")
            elif key in {
                "stage2_digital_foundation_requires_production_adc_selection",
                "STAGE2_DIGITAL_FOUNDATION_REQUIRES_PRODUCTION_ADC_SELECTION",
            }:
                errors.append("digital capability incorrectly requires production ADC selection")
            elif key in {
                "stage2_digital_foundation_can_freeze_with_unconfigured_production_profile",
                "STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE",
            }:
                errors.append(
                    "Stage 2 digital freeze forbidden solely because production is unconfigured"
                )
            else:
                errors.append(f"closure boundary {key} must be {value!r}")

    subclaims = data.get("subclaims")
    if not isinstance(subclaims, list):
        errors.append("closure boundary subclaims must be an array")
        return
    rows = [row for row in subclaims if isinstance(row, dict)]
    ids = [str(row.get("id", "")) for row in rows]
    if set(ids) != REQUIRED_CLOSURE_IDS:
        errors.append("closure boundary subclaim set is incomplete or contradictory")
    for duplicate in sorted(_duplicates(ids)):
        errors.append(f"duplicate closure subclaim: {duplicate}")
    for row in rows:
        if row.get("id") in REQUIRED_CLOSURE_IDS:
            expected_owner = (
                "STAGE2" if str(row.get("id", "")).startswith("DF-") else "STAGE3"
            )
            if row.get("owner") != expected_owner:
                errors.append(
                    f"closure subclaim {row.get('id')} must declare {expected_owner} owner"
                )
            required_selection = expected_owner == "STAGE3"
            if row.get("production_adc_selection_required") is not required_selection:
                errors.append(
                    f"closure subclaim {row.get('id')} production selection dependency is incorrect"
                )
        evidence = row.get("evidence_required")
        if not isinstance(evidence, list) or not evidence or not all(
            isinstance(item, str) and item for item in evidence
        ):
            errors.append(f"closure subclaim {row.get('id')} lacks exact evidence requirements")
        closure_state = str(row.get("closure_state", ""))
        if closure_state in {"CLOSED", "PASS", "COMPLETE"}:
            errors.append(f"closure subclaim {row.get('id')} incorrectly marked closed")


def _check_source_profile(
    schema: dict[str, Any], profile: dict[str, Any], errors: list[str]
) -> None:
    errors.extend(validate_source_profile_contract(schema, profile))
    _check_source_profile_examples(schema, errors)
    if set(profile) != SOURCE_PROFILE_FIELDS:
        errors.append("tracked source profile field set is incomplete or over-general")
    expected = {
        "schema_version": "stage2f-adc-source-profile-v1",
        "profile_state": "UNCONFIGURED",
        "raw_width": 12,
        "encoding": "UNKNOWN",
        "zero_code": None,
        "profile_identity": "UNCONFIGURED",
        "physical_unit_status": "UNKNOWN",
        "production_selection": False,
    }
    for key, value in expected.items():
        if profile.get(key) != value:
            errors.append(f"tracked production source profile {key} must be {value!r}")
    polarity = profile.get("channel_polarity")
    if polarity != {"channel_1": "UNKNOWN", "channel_2": "UNKNOWN"}:
        errors.append("tracked production source profile polarities must remain UNKNOWN")


def _check_reference_profile(data: dict[str, Any], errors: list[str]) -> None:
    expected = {
        "schema_version": "stage3-reference-analog-profile-v1",
        "profile_id": "PYNQ_Z2_PMOD_AD1_DUAL_INA240_REFERENCE_V1",
        "profile_status": "REFERENCE_ONLY_NON_AUTHORITATIVE",
        "production_selection": False,
        "physical_accuracy_claim": False,
        "board_calibration_claim": False,
        "stage2_dependency": False,
        "final_hardware_selection_constrained": False,
        "purchase_authorized": False,
        "production_profile_freeze": False,
        "final_hardware_selection_gate": "STAGE3_ARCHITECTURE_AND_HARDWARE_REVIEW",
        "REFERENCE_BIDIRECTIONAL_NEGATIVE_OVERCURRENT_SUPPORTED_BY_CURRENT_RAW_PATH": "NO",
        "REFERENCE_PROFILE_IS_END_TO_END_PROTECTION_COMPATIBLE": "NO",
        "REFERENCE_PROFILE_REQUIRES_FUTURE_PROTECTION_DOMAIN_DECISION": "YES",
    }
    for key, value in expected.items():
        if data.get(key) != value:
            if key in {"profile_status", "production_selection", "production_profile_freeze"}:
                errors.append("reference profile promoted to production authority")
            elif key == "final_hardware_selection_constrained":
                errors.append("reference profile constraining final hardware selection")
            elif key == "purchase_authorized":
                errors.append("purchase authorization incorrectly implied")
            else:
                errors.append(f"reference profile {key} must be {value!r}")
    protection = data.get("protection_compatibility")
    expected_protection = {
        "reference_bidirectional_negative_overcurrent_supported_by_current_raw_path": False,
        "reference_profile_is_end_to_end_protection_compatible": False,
        "reference_profile_requires_future_protection_domain_decision": True,
    }
    if not isinstance(protection, dict):
        errors.append("reference protection compatibility boundary is missing")
        protection = {}
    for key, value in expected_protection.items():
        if protection.get(key) != value:
            if key.endswith("supported_by_current_raw_path"):
                errors.append("reference bidirectional negative overcurrent incorrectly marked supported")
            elif key.endswith("end_to_end_protection_compatible"):
                errors.append("reference profile incorrectly labeled end-to-end protection compatible")
            else:
                errors.append("reference profile missing future protection domain decision")
    if set(data.get("roles", [])) != {
        "REFERENCE_CANDIDATE",
        "ENGINEERING_COMPARISON_BASELINE",
    }:
        errors.append("reference profile roles are incomplete or authoritative")

    hardware = data.get("hardware")
    expected_hardware = {
        "host": "PYNQ-Z2",
        "adc_module": "Digilent Pmod AD1",
        "adc_device": "DUAL_AD7476A",
        "adc_channels": "2_SIMULTANEOUS",
        "adc_resolution_bits": 12,
        "adc_output_coding": "STRAIGHT_NATURAL_BINARY",
        "adc_input_range": "0_TO_VDD",
        "adc_nominal_throughput": "UP_TO_1_MSPS_PER_CHANNEL",
        "digital_interface": "SHARED_CS_SHARED_SCLK_TWO_SERIAL_DATA_OUTPUTS",
        "adc_reference_type": "VDD_RATIOMETRIC_NOT_PRECISION_EXTERNAL_REFERENCE",
        "vdd_scale_error_policy": "SUPPLY_VARIATION_CONTRIBUTES_DIRECTLY_UNLESS_MEASURED_OR_CALIBRATED",
        "current_sense_afe": "DUAL_SHUNT_PLUS_INA240",
        "bidirectional_bias": "NOMINAL_MIDSCALE_REFERENCE",
    }
    if not isinstance(hardware, dict):
        errors.append("reference hardware description is missing")
        hardware = {}
    for key, value in expected_hardware.items():
        if hardware.get(key) != value:
            if key == "adc_reference_type":
                errors.append("Pmod AD1 claimed as precision external-reference ADC")
            else:
                errors.append(f"reference hardware {key} must be {value!r}")

    example = data.get("illustrative_electrical_example")
    expected_example = {
        "current_range": "PLUS_MINUS_5_A",
        "shunt": "5_MILLIOHM_FOUR_TERMINAL",
        "amplifier": "INA240A2_GAIN_50",
        "adc_supply_reference": "3.3_V_NOMINAL",
        "zero_current_bias": "1.65_V_NOMINAL",
        "output_range": "0.4_TO_2.9_V_NOMINAL",
        "nominal_current_per_lsb": "APPROX_3.22_MA",
        "illustrative_only": True,
        "calibrated": False,
        "production_selected": False,
        "physical_accuracy_evidence": False,
    }
    if not isinstance(example, dict):
        errors.append("illustrative electrical example is missing")
        example = {}
    for key, value in expected_example.items():
        if example.get(key) != value:
            if key == "calibrated":
                errors.append("reference arithmetic labeled calibrated")
            else:
                errors.append(f"illustrative reference value {key} must be {value!r}")

    integration = data.get("integration_boundaries")
    expected_integration = {
        "low_voltage_current_limited_lab_reference_only": True,
        "separate_electrical_safety_review_required": True,
        "dma_mandatory_for_protection_path": False,
        "python_in_realtime_fault_path": False,
        "atomic_stage2d_cdc_replaced": False,
    }
    if not isinstance(integration, dict):
        errors.append("reference integration boundaries are missing")
        integration = {}
    for key, value in expected_integration.items():
        if integration.get(key) != value:
            if key == "dma_mandatory_for_protection_path":
                errors.append("DMA made mandatory for protection path")
            else:
                errors.append(f"reference integration boundary {key} must be {value!r}")

    projects = data.get("public_reference_projects")
    if not isinstance(projects, list):
        errors.append("public reference project inventory is missing")
        projects = []
    rows = [row for row in projects if isinstance(row, dict)]
    ids = [str(row.get("id", "")) for row in rows]
    if set(ids) != set(REFERENCE_PROJECTS):
        errors.append("public reference project set is incomplete or contradictory")
    for duplicate in sorted(_duplicates(ids)):
        errors.append(f"duplicate public reference project: {duplicate}")
    for row in rows:
        project_id = str(row.get("id", ""))
        classification = row.get("classification")
        if classification not in PUBLIC_CLASSIFICATIONS:
            errors.append(f"public project {project_id} has invalid classification")
        if classification != REFERENCE_PROJECTS.get(project_id):
            errors.append(f"public project {project_id} classification is incorrect")
        if row.get("hardware_authority") is not False:
            if row.get("owner_type") == "COMMUNITY":
                errors.append("community repository classified as hardware authority")
            else:
                errors.append("implementation reference promoted to hardware authority")
        if row.get("owner_type") == "COMMUNITY" and classification == "OFFICIAL_INTERFACE_AUTHORITY":
            errors.append("community repository classified as hardware authority")
        if row.get("dma_required_for_protection_path") is not False:
            errors.append("DMA made mandatory for protection path")
        if project_id == "ADI_AD7476A_PMOD_LINUX_DEVICE_TREE":
            if classification != "OFFICIAL_SOFTWARE_INTEGRATION_REFERENCE":
                errors.append("Linux device-tree reference classification is invalid")
            if row.get("complete_fpga_implementation") is not False:
                errors.append("Linux device-tree-only pin incorrectly labeled complete FPGA implementation")
        if project_id in {
            "ADI_AD7476A_PMOD_FPGA_REFERENCE_PAGE",
            "ADI_AD7476A_PMOD_XPS_OR_IPCORE_ARTIFACT",
        } and row.get("complete_fpga_implementation") is True:
            errors.append(f"ADI reference {project_id} incorrectly claims complete FPGA implementation")
        url = row.get("url")
        if not isinstance(url, str) or not url.startswith("https://"):
            errors.append(f"public project {project_id} lacks a pinned HTTPS reference")

    official = data.get("official_interface_authorities")
    if not isinstance(official, list) or len(official) != 3:
        errors.append("official interface authority set must contain three component sources")
    else:
        for row in official:
            if not isinstance(row, dict) or row.get("classification") != "OFFICIAL_INTERFACE_AUTHORITY":
                errors.append("official interface source classification is invalid")


def _check_documents(root: Path, errors: list[str]) -> None:
    texts: dict[Path, str] = {}
    for relative, tokens in REQUIRED_DOC_TOKENS.items():
        try:
            text = (root / relative).read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            errors.append(f"cannot read {relative.as_posix()}: {exc}")
            continue
        texts[relative] = text
        folded = text.casefold()
        for token in tokens:
            if token.casefold() not in folded:
                errors.append(f"{relative.as_posix()} missing required contract text: {token}")

    all_stage2 = "\n".join(texts.get(path, "") for path in DOCUMENT_PATHS[:4])
    forbidden_closure = (
        "STAGE2F_IMPLEMENTATION_STARTED=YES",
        "STAGE2F_CONTRACT_GAP_CLOSED=YES",
        "STAGE2_COMPLETE=YES",
        "REMAINING_CONTRACT_GAPS=1",
        "REMAINING_CONTRACT_GAPS=0",
        "DIGITAL_FOUNDATION_CLOSES_FROZEN_GAP=YES",
        "DIGITAL_FOUNDATION_CLOSES_FROZEN_STAGE2F_GAP=YES",
    )
    for token in forbidden_closure:
        if token in all_stage2:
            errors.append(f"incorrect Stage 2F closure claim in audit documents: {token}")

    latency_text = "\n".join(texts.get(path, "") for path in DOCUMENT_PATHS[:4])
    numeric_latency = re.compile(r"PIPELINE_(?:LATENCY|LATENCY_CONTRACT)\s*=\s*\d+", re.I)
    if numeric_latency.search(latency_text) or any(
        token in latency_text.casefold()
        for token in ("3_aclk_cycles", "exactly three aclk", "exactly 3 aclk")
    ):
        errors.append("numeric latency conflicts with implementation-derived authority")

    target = texts.get(TARGET_DOC, "")
    for match in re.finditer(r"0x([0-9a-fA-F]+)", target):
        if int(match.group(1), 16) > 0x60:
            errors.append(
                f"new register offset above 0x60 finalized without complete semantics: {match.group(0)}"
            )


def _check_cross_artifact(
    facts: dict[str, Any],
    trace: dict[str, Any],
    authorities: dict[str, Any],
    closure: dict[str, Any],
    source: dict[str, Any],
    reference: dict[str, Any],
    errors: list[str],
) -> None:
    state = facts.get("audit_state", {})
    if closure.get("remaining_contract_gaps") != state.get("remaining_contract_gaps"):
        errors.append("remaining contract gap count conflicts across closure and fact authorities")
    if closure.get("physical_scaling_status") != "BLOCKED_EXTERNAL_HARDWARE_FACTS":
        errors.append("physical gap claimed closed while physical unit remains unsupported")

    parameters = authorities.get("parameters", [])
    by_name = {
        str(row.get("parameter")): row
        for row in parameters
        if isinstance(row, dict)
    }
    physical = by_name.get("physical_unit_scale", {})
    if physical.get("authority") != "NOT_SUPPORTED" or physical.get("target_value") != "NONE":
        errors.append("unsupported physical-unit claim without a scaling authority")

    future = trace.get("future_architecture", {})
    stage2g = authorities.get("stage2g_contract", {})
    cross_pairs = {
        "sample_event_authority": "stage2g_sample_event_authority",
        "fault_input_authority": "stage2g_fault_input_authority",
        "normalized_telemetry_gates_fault_policy": "normalized_telemetry_gates_fault_policy",
        "normalized_range_flags_gate_fault_policy": "normalized_range_flags_gate_fault_policy",
        "normalized_configuration_valid_gates_fault_policy": "normalized_configuration_valid_gates_fault_policy",
        "normalized_domain_protection": "normalized_domain_protection",
    }
    for authority_key, trace_key in cross_pairs.items():
        if stage2g.get(authority_key) != future.get(trace_key):
            errors.append(f"Stage 2G authority conflict across artifacts: {authority_key}")

    unconfigured = source.get("profile_state") == "UNCONFIGURED"
    functional_claim = authorities.get("current_production_normalized_telemetry") != (
        "UNAVAILABLE_UNCONFIGURED"
    )
    if unconfigured and functional_claim:
        errors.append("production UNCONFIGURED profile claimed as normalized functional")
    if state.get("current_production_normalized_telemetry") != (
        authorities.get("current_production_normalized_telemetry")
    ):
        errors.append("production normalized telemetry status conflicts across artifacts")
    if reference.get("stage2_dependency") is not False:
        errors.append("non-authoritative reference profile incorrectly made a Stage 2 dependency")

    required_boundary = {
        "STAGE2_DIGITAL_FOUNDATION_REQUIRES_PRODUCTION_ADC_SELECTION": "NO",
        "STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE": "YES",
        "STAGE2_VALIDATION_PROFILES_MAY_SELECT_EXPLICIT_ENCODINGS": "YES",
        "STAGE2_VALIDATION_PROFILE_IS_PRODUCTION_SELECTION": "NO",
        "PRODUCTION_SOURCE_SELECTION_OWNER": "STAGE3",
        "PRODUCTION_NORMALIZED_TELEMETRY_WHILE_UNCONFIGURED": "UNAVAILABLE",
    }
    for key, expected in required_boundary.items():
        if closure.get(key) != expected:
            errors.append(f"digital capability and production selection boundary conflict: {key}")
    if closure.get("STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE") is not True and closure.get(
        "stage2_digital_foundation_can_freeze_with_unconfigured_production_profile"
    ) is not True:
        errors.append("Stage 2 digital freeze is incorrectly forbidden solely because production is unconfigured")


def _git_lines(root: Path, *args: str) -> list[str]:
    completed = subprocess.run(
        ["git", *args],
        cwd=root,
        check=False,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or f"git {' '.join(args)} failed")
    return [line for line in completed.stdout.splitlines() if line]


def _check_git_scope(root: Path, errors: list[str]) -> None:
    if not (root / ".git").exists():
        return
    try:
        branch = _git_lines(root, "branch", "--show-current")
        if branch != [EXPECTED_BRANCH]:
            errors.append(f"git branch must be {EXPECTED_BRANCH}, got {branch!r}")
        ancestor = subprocess.run(
            ["git", "merge-base", "--is-ancestor", BASE_COMMIT, "HEAD"],
            cwd=root,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if ancestor.returncode != 0:
            errors.append("frozen Stage 2E base is not an ancestor of HEAD")
        changed = set(_git_lines(root, "diff", "--name-only", f"{BASE_COMMIT}...HEAD"))
        for status_line in _git_lines(root, "status", "--porcelain", "--untracked-files=all"):
            path = status_line[3:].replace("\\", "/")
            if " -> " in path:
                path = path.split(" -> ", 1)[1]
            changed.add(path)
        unexpected = sorted(changed - ALLOWED_CHANGE_PATHS)
        if unexpected:
            errors.append("functional or out-of-scope files changed: " + ", ".join(unexpected))
    except (OSError, RuntimeError) as exc:
        errors.append(f"git scope check failed: {exc}")


def audit_contract(
    root: Path,
    *,
    validate_references: bool = True,
    check_git: bool = True,
) -> list[str]:
    root = root.resolve()
    errors: list[str] = []
    for relative in REQUIRED_PATHS:
        if not (root / relative).is_file():
            errors.append(f"required Stage 2F artifact missing: {relative.as_posix()}")
    if errors:
        return errors

    facts = _load_json(root, FACT_PATH, errors)
    trace = _load_json(root, TRACE_PATH, errors)
    authorities = _load_json(root, AUTHORITY_PATH, errors)
    closure = _load_json(root, CLOSURE_PATH, errors)
    schema = _load_json(root, SOURCE_SCHEMA_PATH, errors)
    source = _load_json(root, SOURCE_PROFILE_PATH, errors)
    reference = _load_json(root, REFERENCE_PROFILE_PATH, errors)

    if facts:
        _check_fact_inventory(root, facts, errors, validate_references)
    if trace:
        _check_trace_inventory(root, trace, errors, validate_references)
    if authorities:
        _check_authorities(authorities, errors)
    if closure:
        _check_closure(closure, errors)
    if schema and source:
        _check_source_profile(schema, source, errors)
    if reference:
        _check_reference_profile(reference, errors)
    _check_documents(root, errors)
    if all((facts, trace, authorities, closure, source, reference)):
        _check_cross_artifact(
            facts, trace, authorities, closure, source, reference, errors
        )
    if check_git:
        _check_git_scope(root, errors)
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--no-reference-check", action="store_true")
    parser.add_argument("--no-git-check", action="store_true")
    parser.add_argument("--json", action="store_true", dest="json_output")
    args = parser.parse_args(argv)

    errors = audit_contract(
        args.root,
        validate_references=not args.no_reference_check,
        check_git=not args.no_git_check,
    )
    result = {
        "audit": "STAGE2F_ADC_ENCODING_SCALING_HARDENED_CONTRACT",
        "base_commit": BASE_COMMIT,
        "result": "PASS" if not errors else "FAIL",
        "error_count": len(errors),
        "errors": errors,
    }
    if args.json_output:
        print(json.dumps(result, indent=2, sort_keys=True))
    elif errors:
        print("STAGE2F_ADC_CONTRACT_AUDIT=FAIL")
        for error in errors:
            print(f"ERROR: {error}")
    else:
        print("STAGE2F_ADC_CONTRACT_AUDIT=PASS")
        print(f"AUDIT_BASE_COMMIT={BASE_COMMIT}")
        print("FROZEN_GAP=ADC_ENCODING_AND_PHYSICAL_SCALING")
        print("DIGITAL_FOUNDATION_CLOSES_FROZEN_GAP=NO")
        print("STAGE2_DIGITAL_FOUNDATION_REQUIRES_PRODUCTION_ADC_SELECTION=NO")
        print("STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE=YES")
        print("STAGE2_VALIDATION_PROFILES_MAY_SELECT_EXPLICIT_ENCODINGS=YES")
        print("STAGE2_VALIDATION_PROFILE_IS_PRODUCTION_SELECTION=NO")
        print("PRODUCTION_SOURCE_SELECTION_OWNER=STAGE3")
        print("PRODUCTION_NORMALIZED_TELEMETRY_WHILE_UNCONFIGURED=UNAVAILABLE")
        print("CONFIGURED_PROFILE_RESERVED_IDENTITY_REJECTION=PASS")
        print("VALID_CONFIGURED_SIMULATION_PROFILE=PASS")
        print("PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS")
        print("STAGE2G_SAMPLE_EVENT_AUTHORITY=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT")
        print("STAGE2G_FAULT_INPUT_AUTHORITY=RAW_PROTECTION_EVALUATION")
        print("NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO")
        print("PIPELINE_LATENCY=IMPLEMENTATION_DERIVED_FIXED_CONSTANT")
        print("PIPELINE_INITIATION_INTERVAL=1")
        print("CALIBRATION_ARITHMETIC=DEFERRED")
        print("GENERIC_RATIONAL_DIVIDER=NO")
        print("CURRENT_PRODUCTION_NORMALIZED_TELEMETRY=UNAVAILABLE_UNCONFIGURED")
        print("REFERENCE_ANALOG_PROFILE_STATUS=REFERENCE_ONLY_NON_AUTHORITATIVE")
        print("REFERENCE_BIDIRECTIONAL_NEGATIVE_OVERCURRENT_SUPPORTED_BY_CURRENT_RAW_PATH=NO")
        print("REFERENCE_PROFILE_IS_END_TO_END_PROTECTION_COMPATIBLE=NO")
        print("REFERENCE_PROFILE_REQUIRES_FUTURE_PROTECTION_DOMAIN_DECISION=YES")
        print("ADI_REFERENCE_PIN_CLASSIFICATION=PASS")
        print("PUBLIC_REFERENCE_PROJECT_COMPARISON=PASS")
        print("PHYSICAL_ACCURACY_CLAIM=NOT_MADE")
        print("BOARD_CALIBRATION_CLAIM=NOT_MADE")
        print("STAGE2F_IMPLEMENTATION_STARTED=NO")
        print("STAGE2F_CONTRACT_GAP_CLOSED=NO")
        print("REMAINING_CONTRACT_GAPS=2")
        print("STAGE2_COMPLETE=NO")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
