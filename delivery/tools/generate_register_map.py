#!/usr/bin/env python3
"""Validate and deterministically generate the frozen public register-map ABI."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SPEC = ROOT / "spec/register_map.json"
DEFAULT_SCHEMA = ROOT / "spec/register_map.schema.json"
DEFAULT_BASELINE = ROOT / "spec/stage2h_register_map_convergence.json"
GENERATOR_VERSION = "1.1.0"
SCHEMA_VERSION = "1.1.0"
MASTER_ARTIFACTS = (
    "rtl/generated/protection_register_map.vh",
    "sw/generated/protection_register_map.py",
    "sw/ps_register_demo/protection_ip_regs.h",
    "fpga/vivado/generated/protection_register_map_ipxact.tcl",
    "docs/implementation/register_map.md",
    "tb/generated/protection_register_map.svh",
    "spec/generated/protection_register_map_compatibility.json",
    "spec/generated/protection_register_map_conformance.json",
)
ACCESS_REGISTER = {"RO", "RW", "RW/W1P", "RO/W1C"}
ACCESS_FIELD = {"RO", "RW", "W1C", "W1P", "RSVD"}
WRITE_STROBES = {
    "NOT_APPLICABLE",
    "IGNORED_AFTER_ACCEPTED_WRITE",
    "BYTE_QUALIFIED",
}
VALUE_KINDS = {"stored", "dynamic", "static", "parameterized_static"}
LANGUAGES = ("rtl", "c", "python", "systemverilog", "ipxact", "documentation")
ALIAS_LANGUAGES = ("rtl", "c", "python", "systemverilog")
UPPER_NAME_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
DOC_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
HEX_RE = re.compile(r"^0x[0-9A-Fa-f]+$")
LEGACY_FIRST_OFFSET = 0x00
LEGACY_LAST_OFFSET = 0x60
ABI_1_1_ADDED_OFFSETS = {
    "REGISTER_MAP_VERSION": 0x80,
    "CAPABILITIES_0": 0x84,
    "CAPABILITIES_1": 0x88,
    "POLICY_STATUS": 0xA0,
    "FIRST_FAULT_BITMAP": 0xA4,
    "LIVE_FAULT_BITMAP": 0xA8,
    "FAULT_SEEN_BITMAP": 0xAC,
    "POLICY_EVALUATION_SEQUENCE": 0xB0,
}
FAULT_CAUSE_BITS = {
    "CH1_OVERCURRENT": 0,
    "CH2_OVERCURRENT": 1,
    "SENSOR_MISMATCH_OR_DIFFERENTIAL": 2,
    "SENSOR_OPEN": 3,
    "SENSOR_SATURATION": 4,
    "SENSOR_STUCK": 5,
}
ABI_1_1_BEHAVIORS = {
    "RO_STATIC",
    "RO_STATE_DECODE",
    "RO_LEVEL",
    "RO_BITMAP",
    "RO_EVENT_CAPTURE",
    "RSVD_ZERO_IGNORE",
}
CONFORMANCE_TEMPLATE_FOR_BEHAVIOR = {
    "RO_STATIC": "RO_STATIC",
    "RO_STATE_DECODE": "RO_STATE_DECODE",
    "RO_LEVEL": "RO_LEVEL",
    "RO_BITMAP": "RO_BITMAP",
    "RO_EVENT_CAPTURE": "RO_EVENT_CAPTURE",
    "RSVD_ZERO_IGNORE": "RO_STATIC",
}
EXPECTED_API_GATES = {
    "API_IS_ARMED": {"ARMED_READY", "STAGE2G_POLICY"},
    "API_STARTUP_READY": {"ARMED_READY", "STAGE2G_POLICY"},
    "API_READ_POLICY_STATUS": {"CLEAR_LEVEL_STATUS", "STAGE2G_POLICY"},
    "API_READ_CAPABILITIES": set(),
    "API_READ_REGISTER_MAP_VERSION": set(),
    "API_READ_OBSERVABILITY": {"STAGE2E_TRANSACTION_OBSERVABILITY"},
    "API_CLEAR_OBSERVABILITY_STATUS": {"STAGE2E_TRANSACTION_OBSERVABILITY"},
    "API_READ_FIRST_FAULT_BITMAP": {"FAULT_BITMAPS", "STAGE2G_POLICY"},
    "API_READ_LIVE_FAULT_BITMAP": {"FAULT_BITMAPS", "STAGE2G_POLICY"},
    "API_READ_FAULT_SEEN_BITMAP": {"FAULT_BITMAPS", "STAGE2G_POLICY"},
    "API_READ_POLICY_EVALUATION_IDENTITY": {
        "POLICY_EVALUATION_IDENTITY",
        "STAGE2G_POLICY",
    },
}
EXPECTED_CAPABILITY_TARGETS = {
    "ARMED_READY": {
        "CAPABILITIES_0.ARMED_READY",
        "POLICY_STATUS.ARMED_READY",
    },
    "FAULT_BITMAPS": {
        "CAPABILITIES_0.FAULT_BITMAPS",
        "CAPABILITIES_1.FAULT_BITMAP_WIDTH",
        *{
            f"{register}.{field}"
            for register in (
                "FIRST_FAULT_BITMAP",
                "LIVE_FAULT_BITMAP",
                "FAULT_SEEN_BITMAP",
            )
            for field in (*FAULT_CAUSE_BITS, "RESERVED")
        },
    },
    "CLEAR_LEVEL_STATUS": {
        "CAPABILITIES_0.CLEAR_LEVEL_STATUS",
        "POLICY_STATUS.CLEAR_PENDING",
        "POLICY_STATUS.POST_CLEAR_RECOVERY_PENDING",
    },
    "STAGE2G_POLICY": {
        "CAPABILITIES_0.STAGE2G_POLICY",
        "POLICY_STATUS.ARMED_READY",
        "POLICY_STATUS.FAULT_LATCHED_STATE",
        "POLICY_STATUS.RESET_WAIT_STATE",
        "POLICY_STATUS.CLEAR_PENDING",
        "POLICY_STATUS.POST_CLEAR_RECOVERY_PENDING",
        "POLICY_STATUS.RESERVED",
    },
    "NORMALIZED_TELEMETRY": {
        "CAPABILITIES_0.NORMALIZED_TELEMETRY_RESERVED_ZERO",
    },
    "STAGE2E_TRANSACTION_OBSERVABILITY": {
        "CAPABILITIES_0.STAGE2E_TRANSACTION_OBSERVABILITY",
    },
    "POLICY_EVALUATION_IDENTITY": {
        "CAPABILITIES_0.POLICY_EVALUATION_IDENTITY",
        "CAPABILITIES_1.IMPLEMENTED_SEQUENCE_WIDTH",
        "CAPABILITIES_1.MIN_SEQUENCE_WIDTH",
        "CAPABILITIES_1.MAX_SEQUENCE_WIDTH",
        "POLICY_EVALUATION_SEQUENCE.SEQUENCE",
    },
}
EXPECTED_CAPABILITY_API_REFS = {
    "ARMED_READY": {"API_IS_ARMED", "API_STARTUP_READY"},
    "FAULT_BITMAPS": {
        "API_READ_FIRST_FAULT_BITMAP",
        "API_READ_LIVE_FAULT_BITMAP",
        "API_READ_FAULT_SEEN_BITMAP",
    },
    "CLEAR_LEVEL_STATUS": {"API_READ_POLICY_STATUS"},
    "STAGE2G_POLICY": {"API_READ_POLICY_STATUS"},
    "NORMALIZED_TELEMETRY": set(),
    "STAGE2E_TRANSACTION_OBSERVABILITY": {
        "API_READ_OBSERVABILITY",
        "API_CLEAR_OBSERVABILITY_STATUS",
    },
    "POLICY_EVALUATION_IDENTITY": {"API_READ_POLICY_EVALUATION_IDENTITY"},
}
EXPECTED_CAPABILITY_METADATA_REFS = {
    "ARMED_READY": {"STAGE2G_PUBLIC_CONTRACT_CONNECTED"},
    "FAULT_BITMAPS": {"FAULT_BITMAP_WIDTH_RANGE_6_TO_32"},
    "CLEAR_LEVEL_STATUS": set(),
    "STAGE2G_POLICY": {"STAGE2G_PUBLIC_CONTRACT_CONNECTED"},
    "NORMALIZED_TELEMETRY": {"NORMALIZED_TELEMETRY_RESERVED_ZERO"},
    "STAGE2E_TRANSACTION_OBSERVABILITY": {
        "STAGE2E_OBS_CAPABILITY_EXACT_FROZEN"
    },
    "POLICY_EVALUATION_IDENTITY": {
        "IMPLEMENTED_SEQUENCE_WIDTH_RANGE_16_TO_32",
        "POLICY_EVALUATION_IDENTITY_DIAGNOSTIC_ONLY",
    },
}
FROZEN_LEGACY_FIELD_CONSTANTS = {
    ("CTRL", "pwm_enable"): "CTRL_PWM_ENABLE",
    ("CTRL", "clear_fault_pulse"): "CTRL_CLEAR_FAULT",
    ("STATUS", "fault_valid"): "STATUS_FAULT_VALID",
    ("STATUS", "fault_latched"): "STATUS_FAULT_LATCHED",
    ("OBS_STATUS_W1C", "BACKPRESSURE_SEEN"): "OBS_BACKPRESSURE_SEEN",
    ("OBS_STATUS_W1C", "SOURCE_PROTOCOL_VIOLATION"): "OBS_SOURCE_PROTOCOL_VIOLATION",
    ("OBS_STATUS_W1C", "SOURCE_DROP_SEEN"): "OBS_SOURCE_DROP_SEEN",
    ("OBS_STATUS_W1C", "FIFO_OVERFLOW_ATTEMPT"): "OBS_FIFO_OVERFLOW_ATTEMPT",
    ("OBS_STATUS_W1C", "FIFO_UNDERFLOW_ATTEMPT"): "OBS_FIFO_UNDERFLOW_ATTEMPT",
    ("OBS_STATUS_W1C", "DUPLICATE_DELIVERY"): "OBS_DUPLICATE_DELIVERY",
    ("OBS_STATUS_W1C", "SEQUENCE_GAP"): "OBS_SEQUENCE_GAP",
    ("OBS_STATUS_W1C", "REORDER_OR_STALE"): "OBS_REORDER_OR_STALE",
    ("OBS_STATUS_W1C", "COUNTER_SATURATED"): "OBS_COUNTER_SATURATED",
    ("OBS_STATUS_W1C", "ANY_ERROR"): "OBS_ANY_ERROR",
}


class GenerationError(RuntimeError):
    """The live source, frozen baseline, or generated output is invalid."""


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise GenerationError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_constant(value: str) -> None:
    raise GenerationError(f"non-finite JSON number is forbidden: {value}")


def load_json(path: Path) -> tuple[dict[str, Any], bytes]:
    try:
        raw = path.read_bytes()
        value = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=unique_object,
            parse_constant=reject_constant,
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise GenerationError(f"invalid JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise GenerationError(f"JSON root must be an object: {path}")
    return value, raw


def parse_uint(value: Any, label: str) -> int:
    if isinstance(value, bool):
        raise GenerationError(f"{label} must be an unsigned integer")
    if isinstance(value, int) and value >= 0:
        return value
    if isinstance(value, str) and HEX_RE.fullmatch(value):
        return int(value, 16)
    raise GenerationError(f"{label} must be a nonnegative integer or 0x hex string")


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
        + "\n"
    ).encode("utf-8")


def pretty_json(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=True) + "\n"


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_object_shape(
    value: Any, definition: dict[str, Any], label: str
) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise GenerationError(f"{label} must be an object")
    required = set(definition.get("required", []))
    properties = set(definition.get("properties", {}))
    missing = sorted(required - set(value))
    extra = sorted(set(value) - properties)
    if missing:
        raise GenerationError(f"{label} missing schema fields: {missing}")
    if definition.get("additionalProperties") is False and extra:
        raise GenerationError(f"{label} has unknown schema fields: {extra}")
    return value


def schema_definition(schema: dict[str, Any], name: str) -> dict[str, Any]:
    try:
        value = schema["$defs"][name]
    except (KeyError, TypeError) as exc:
        raise GenerationError(f"schema definition missing: {name}") from exc
    if not isinstance(value, dict):
        raise GenerationError(f"schema definition must be an object: {name}")
    return value


def validate_name(value: Any, label: str, *, documentation: bool = False) -> str:
    pattern = DOC_NAME_RE if documentation else UPPER_NAME_RE
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise GenerationError(f"invalid public name {label}: {value!r}")
    return value


def validate_public_names(
    schema: dict[str, Any], value: Any, label: str
) -> dict[str, str]:
    names = require_object_shape(value, schema_definition(schema, "public_names"), label)
    for language in LANGUAGES:
        validate_name(
            names[language],
            f"{label}.{language}",
            documentation=(language == "documentation"),
        )
    return names


def validate_schema_contract(schema: dict[str, Any]) -> None:
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        raise GenerationError("schema must declare JSON Schema draft 2020-12")
    if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
        raise GenerationError("schema root must be a closed object")
    required_defs = {
        "abi",
        "parameter",
        "bus_behavior",
        "fault_code",
        "fault_cause",
        "abi_1_1_contract",
        "rtl_source",
        "capability",
        "dependency_edge",
        "api_gate",
        "invariant",
        "conformance_template",
        "conformance_route",
        "fault_projection_rule",
        "fault_forward_compatibility",
        "policy_identity",
        "register",
        "field",
        "dynamic_source",
        "parameter_expression",
        "public_names",
        "legacy_aliases",
        "uint",
    }
    definitions = schema.get("$defs")
    if not isinstance(definitions, dict) or not required_defs.issubset(definitions):
        raise GenerationError("schema is missing required project definitions")
    root_required = set(schema.get("required", []))
    root_properties = set(schema.get("properties", {}))
    if root_required != root_properties:
        raise GenerationError("schema root properties must all be required")
    if set(
        schema_definition(schema, "register")["properties"]["access"]["enum"]
    ) != ACCESS_REGISTER:
        raise GenerationError("schema register access taxonomy changed")
    if set(schema_definition(schema, "field")["properties"]["access"]["enum"]) != ACCESS_FIELD:
        raise GenerationError("schema field access taxonomy changed")


def validate_spec_schema_shape(schema: dict[str, Any], spec: dict[str, Any]) -> None:
    require_object_shape(spec, schema, "register_map")
    if spec.get("$schema") != "register_map.schema.json":
        raise GenerationError("register_map.$schema must name register_map.schema.json")
    if spec.get("schema_version") != SCHEMA_VERSION:
        raise GenerationError(f"unsupported register-map schema version: {spec.get('schema_version')}")

    abi = require_object_shape(spec["abi"], schema_definition(schema, "abi"), "abi")
    if abi.get("version") != "1.1":
        raise GenerationError("the A2-2 generator requires ABI version 1.1")
    if abi.get("data_width") != 32 or abi.get("address_width") != 8:
        raise GenerationError("the frozen legacy ABI is 32-bit data with 8-bit decode")
    if abi.get("byte_order") != "little":
        raise GenerationError("the frozen legacy ABI is little-endian")
    address_range = abi.get("legacy_address_range")
    if not isinstance(address_range, dict) or set(address_range) != {"first", "last"}:
        raise GenerationError("abi.legacy_address_range schema mismatch")
    parse_uint(address_range["first"], "abi.legacy_address_range.first")
    parse_uint(address_range["last"], "abi.legacy_address_range.last")

    if not isinstance(spec["generated_artifacts"], list):
        raise GenerationError("generated_artifacts must be an array")
    if not isinstance(spec["parameters"], list):
        raise GenerationError("parameters must be an array")
    if not isinstance(spec["fault_codes"], list) or not spec["fault_codes"]:
        raise GenerationError("fault_codes must be a nonempty array")
    if not isinstance(spec["fault_causes"], list) or not spec["fault_causes"]:
        raise GenerationError("fault_causes must be a nonempty array")
    if not isinstance(spec["abi_1_1_contract"], dict):
        raise GenerationError("abi_1_1_contract must be an object")
    if not isinstance(spec["registers"], list) or not spec["registers"]:
        raise GenerationError("registers must be a nonempty array")

    parameter_def = schema_definition(schema, "parameter")
    for index, parameter in enumerate(spec["parameters"]):
        item = require_object_shape(parameter, parameter_def, f"parameters[{index}]")
        validate_name(item.get("name"), f"parameters[{index}].name")
        for key in ("minimum", "maximum", "default"):
            if isinstance(item.get(key), bool) or not isinstance(item.get(key), int):
                raise GenerationError(f"parameters[{index}].{key} must be an integer")
        if not isinstance(item.get("description"), str) or not item["description"]:
            raise GenerationError(f"parameters[{index}].description must be nonempty")

    bus = require_object_shape(
        spec["bus_behavior"], schema_definition(schema, "bus_behavior"), "bus_behavior"
    )
    nested_bus_shapes = {
        "address_decode": {"lsb", "msb", "outer_address_aliases"},
        "accepted_write": {"requires_any_wstrb", "legacy_unstrobed_registers"},
        "undefined_read": {"value", "response"},
        "undefined_write": {"effect", "response"},
        "read_data": {"combinational_decode", "rd_en_gates_value"},
        "current_monitor_pair": {
            "hardware_delivery_atomic",
            "software_reads_atomic",
            "description",
        },
    }
    for key, expected in nested_bus_shapes.items():
        if not isinstance(bus.get(key), dict) or set(bus[key]) != expected:
            raise GenerationError(f"bus_behavior.{key} schema mismatch")

    fault_def = schema_definition(schema, "fault_code")
    alias_def = schema_definition(schema, "legacy_aliases")
    for index, fault in enumerate(spec["fault_codes"]):
        item = require_object_shape(fault, fault_def, f"fault_codes[{index}]")
        validate_name(item.get("name"), f"fault_codes[{index}].name")
        if isinstance(item.get("value"), bool) or not isinstance(item.get("value"), int):
            raise GenerationError(f"fault_codes[{index}].value must be an integer")
        if not 0 <= item["value"] <= 0xFF:
            raise GenerationError(f"fault_codes[{index}].value exceeds 8 bits")
        if not isinstance(item.get("description"), str) or not item["description"]:
            raise GenerationError(f"fault_codes[{index}].description must be nonempty")
        validate_public_names(schema, item.get("public_names"), f"fault_codes[{index}].public_names")
        aliases = require_object_shape(
            item.get("legacy_aliases"), alias_def, f"fault_codes[{index}].legacy_aliases"
        )
        for language in ALIAS_LANGUAGES:
            if not isinstance(aliases.get(language), list):
                raise GenerationError(f"fault_codes[{index}].legacy_aliases.{language} must be an array")
            for alias in aliases[language]:
                validate_name(alias, f"fault_codes[{index}].legacy_aliases.{language}")

    fault_cause_def = schema_definition(schema, "fault_cause")
    for index, cause in enumerate(spec["fault_causes"]):
        item = require_object_shape(
            cause, fault_cause_def, f"fault_causes[{index}]"
        )
        validate_name(item.get("name"), f"fault_causes[{index}].name")
        if isinstance(item.get("bit"), bool) or not isinstance(item.get("bit"), int):
            raise GenerationError(f"fault_causes[{index}].bit must be an integer")
        if not isinstance(item.get("description"), str) or not item["description"]:
            raise GenerationError(
                f"fault_causes[{index}].description must be nonempty"
            )
        validate_public_names(
            schema,
            item.get("public_names"),
            f"fault_causes[{index}].public_names",
        )

    contract = require_object_shape(
        spec["abi_1_1_contract"],
        schema_definition(schema, "abi_1_1_contract"),
        "abi_1_1_contract",
    )
    contract_arrays = {
        "rtl_sources": "rtl_source",
        "capabilities": "capability",
        "api_gates": "api_gate",
        "invariants": "invariant",
        "conformance_templates": "conformance_template",
        "conformance_routes": "conformance_route",
        "fault_projection": "fault_projection_rule",
    }
    for key, definition_name in contract_arrays.items():
        if not isinstance(contract.get(key), list):
            raise GenerationError(f"abi_1_1_contract.{key} must be an array")
        definition = schema_definition(schema, definition_name)
        for index, value in enumerate(contract[key]):
            require_object_shape(
                value, definition, f"abi_1_1_contract.{key}[{index}]"
            )
    if not isinstance(contract.get("metadata_constraints"), list):
        raise GenerationError(
            "abi_1_1_contract.metadata_constraints must be an array"
        )
    require_object_shape(
        contract.get("fault_forward_compatibility"),
        schema_definition(schema, "fault_forward_compatibility"),
        "abi_1_1_contract.fault_forward_compatibility",
    )
    require_object_shape(
        contract.get("policy_identity"),
        schema_definition(schema, "policy_identity"),
        "abi_1_1_contract.policy_identity",
    )

    for source_index, source in enumerate(contract["rtl_sources"]):
        validate_name(source.get("id"), f"rtl_sources[{source_index}].id")
        encodings = source.get("state_encodings")
        if encodings is not None:
            if not isinstance(encodings, dict) or set(encodings) != {
                "ST_ARMED",
                "ST_FAULT_LATCHED",
                "ST_RESET_WAIT",
            }:
                raise GenerationError(
                    f"rtl_sources[{source_index}].state_encodings is invalid"
                )

    dynamic_source_def = schema_definition(schema, "dynamic_source")

    register_def = schema_definition(schema, "register")
    field_def = schema_definition(schema, "field")
    for reg_index, register in enumerate(spec["registers"]):
        item = require_object_shape(register, register_def, f"registers[{reg_index}]")
        validate_name(item.get("name"), f"registers[{reg_index}].name")
        parse_uint(item.get("offset"), f"registers[{reg_index}].offset")
        parse_uint(item.get("reset"), f"registers[{reg_index}].reset")
        if item.get("width") != 32:
            raise GenerationError(f"registers[{reg_index}].width must be 32")
        if item.get("access") not in ACCESS_REGISTER:
            raise GenerationError(f"registers[{reg_index}].access is invalid")
        if item.get("value_kind") not in VALUE_KINDS:
            raise GenerationError(f"registers[{reg_index}].value_kind is invalid")
        if item.get("write_strobe") not in WRITE_STROBES:
            raise GenerationError(f"registers[{reg_index}].write_strobe is invalid")
        if not isinstance(item.get("description"), str) or not item["description"]:
            raise GenerationError(f"registers[{reg_index}].description must be nonempty")
        validate_public_names(schema, item.get("public_names"), f"registers[{reg_index}].public_names")
        if not isinstance(item.get("fields"), list) or not item["fields"]:
            raise GenerationError(f"registers[{reg_index}].fields must be nonempty")
        for field_index, field in enumerate(item["fields"]):
            field_label = f"registers[{reg_index}].fields[{field_index}]"
            field_item = require_object_shape(field, field_def, field_label)
            if not isinstance(field_item.get("name"), str) or not re.fullmatch(
                r"[A-Za-z][A-Za-z0-9_]*", field_item["name"]
            ):
                raise GenerationError(f"{field_label}.name is invalid")
            for key in ("lsb", "msb"):
                if isinstance(field_item.get(key), bool) or not isinstance(field_item.get(key), int):
                    raise GenerationError(f"{field_label}.{key} must be an integer")
            if field_item.get("access") not in ACCESS_FIELD:
                raise GenerationError(f"{field_label}.access is invalid")
            parse_uint(field_item.get("reset"), f"{field_label}.reset")
            for key in ("description", "read_behavior", "write_behavior"):
                if not isinstance(field_item.get(key), str) or not field_item[key]:
                    raise GenerationError(f"{field_label}.{key} must be nonempty")
            validate_public_names(schema, field_item.get("public_names"), f"{field_label}.public_names")
            if "dynamic_source" in field_item:
                require_object_shape(
                    field_item["dynamic_source"],
                    dynamic_source_def,
                    f"{field_label}.dynamic_source",
                )
            if isinstance(field_item.get("static_value"), dict):
                require_object_shape(
                    field_item["static_value"],
                    schema_definition(schema, "parameter_expression"),
                    f"{field_label}.static_value",
                )


def validate_semantics(spec: dict[str, Any]) -> None:
    artifacts = spec["generated_artifacts"]
    if tuple(artifacts) != MASTER_ARTIFACTS:
        raise GenerationError(
            "generated_artifacts must exactly match the frozen eight-path master topology"
        )
    if len(artifacts) != len(set(artifacts)):
        raise GenerationError("duplicate generated artifact path")
    for path in artifacts:
        candidate = Path(path)
        if candidate.is_absolute() or ".." in candidate.parts or "\\" in path:
            raise GenerationError(f"unsafe generated artifact path: {path}")

    parameters: dict[str, dict[str, Any]] = {}
    for parameter in spec["parameters"]:
        name = parameter["name"]
        if name in parameters:
            raise GenerationError(f"duplicate parameter: {name}")
        if not parameter["minimum"] <= parameter["default"] <= parameter["maximum"]:
            raise GenerationError(f"parameter default outside range: {name}")
        parameters[name] = parameter

    fault_names: set[str] = set()
    fault_values: set[int] = set()
    language_owners: dict[str, dict[str, str]] = {name: {} for name in ALIAS_LANGUAGES}
    for fault in spec["fault_codes"]:
        name = fault["name"]
        value = fault["value"]
        if name in fault_names:
            raise GenerationError(f"duplicate fault-code name: {name}")
        if value in fault_values:
            raise GenerationError(f"duplicate fault-code value: 0x{value:02X}")
        fault_names.add(name)
        fault_values.add(value)
        for language in ALIAS_LANGUAGES:
            public = fault["public_names"][language]
            candidates = [public, *fault["legacy_aliases"][language]]
            if len(candidates) != len(set(candidates)):
                raise GenerationError(f"duplicate aliases within fault {name} for {language}")
            for candidate in candidates:
                owner = language_owners[language].get(candidate)
                if owner is not None and owner != name:
                    raise GenerationError(
                        f"conflicting {language} fault alias {candidate}: {owner} and {name}"
                    )
                language_owners[language][candidate] = name

    register_names: set[str] = set()
    offsets: set[int] = set()
    public_register_names: dict[str, set[str]] = {name: set() for name in LANGUAGES}
    first = parse_uint(spec["abi"]["legacy_address_range"]["first"], "legacy first")
    last = parse_uint(spec["abi"]["legacy_address_range"]["last"], "legacy last")
    for register in spec["registers"]:
        name = register["name"]
        offset = parse_uint(register["offset"], f"{name}.offset")
        reset = parse_uint(register["reset"], f"{name}.reset")
        if name in register_names:
            raise GenerationError(f"duplicate register name: {name}")
        if offset in offsets:
            raise GenerationError(f"duplicate register offset: 0x{offset:02X}")
        if offset % 4:
            raise GenerationError(f"register offset is not 32-bit aligned: {name}")
        if not first <= offset <= last:
            expected_added = ABI_1_1_ADDED_OFFSETS.get(name)
            if expected_added != offset:
                raise GenerationError(
                    f"register is outside the selected ABI 1.1 allocation: {name}"
                )
        if reset >= (1 << register["width"]):
            raise GenerationError(f"register reset exceeds width: {name}")
        register_names.add(name)
        offsets.add(offset)
        for language in LANGUAGES:
            public = register["public_names"][language]
            if public in public_register_names[language]:
                raise GenerationError(f"duplicate {language} register name: {public}")
            public_register_names[language].add(public)

        field_names: set[str] = set()
        used_bits = 0
        for field in register["fields"]:
            field_name = field["name"]
            lsb = field["lsb"]
            msb = field["msb"]
            if field_name in field_names:
                raise GenerationError(f"duplicate field name: {name}.{field_name}")
            if not 0 <= lsb <= msb < register["width"]:
                raise GenerationError(f"field outside register width: {name}.{field_name}")
            width = msb - lsb + 1
            mask = ((1 << width) - 1) << lsb
            if used_bits & mask:
                raise GenerationError(f"overlapping fields in {name}: {field_name}")
            used_bits |= mask
            field_names.add(field_name)
            reset_value = parse_uint(field["reset"], f"{name}.{field_name}.reset")
            if reset_value >= (1 << width):
                raise GenerationError(f"field reset exceeds width: {name}.{field_name}")
            parameter_ref = field.get("parameter_ref")
            if parameter_ref is not None and parameter_ref not in parameters:
                raise GenerationError(f"unknown parameter reference: {name}.{field_name}")
            enum_ref = field.get("enum_ref")
            if enum_ref is not None and enum_ref != "fault_codes":
                raise GenerationError(f"unknown enum reference: {name}.{field_name}")
        if used_bits != (1 << register["width"]) - 1:
            raise GenerationError(f"fields do not cover all bits in register {name}")

    expected_legacy_offsets = set(range(first, last + 1, 4))
    actual_legacy_offsets = {offset for offset in offsets if first <= offset <= last}
    if actual_legacy_offsets != expected_legacy_offsets:
        missing = sorted(expected_legacy_offsets - actual_legacy_offsets)
        extra = sorted(actual_legacy_offsets - expected_legacy_offsets)
        raise GenerationError(f"legacy register range is not contiguous: missing={missing} extra={extra}")
    actual_added = {
        register["name"]: parse_uint(register["offset"], register["name"])
        for register in spec["registers"]
        if parse_uint(register["offset"], register["name"]) > last
    }
    if actual_added != ABI_1_1_ADDED_OFFSETS:
        raise GenerationError(
            "selected ABI 1.1 register allocation differs from the eight approved offsets"
        )

    bus = spec["bus_behavior"]
    if bus["address_decode"] != {"lsb": 0, "msb": 7, "outer_address_aliases": True}:
        raise GenerationError("frozen low-eight-bit address alias behavior changed")
    if bus["undefined_read"] != {"value": 0, "response": "OKAY"}:
        raise GenerationError("frozen undefined-read behavior changed")
    if bus["undefined_write"] != {"effect": "NONE", "response": "OKAY"}:
        raise GenerationError("frozen undefined-write behavior changed")
    if bus["read_data"] != {"combinational_decode": True, "rd_en_gates_value": False}:
        raise GenerationError("frozen register-bank read-data behavior changed")
    monitor = bus["current_monitor_pair"]
    if monitor["hardware_delivery_atomic"] is not True or monitor["software_reads_atomic"] is not False:
        raise GenerationError("frozen current-monitor atomicity behavior changed")
    unstrobed = set(bus["accepted_write"]["legacy_unstrobed_registers"])
    if bus["accepted_write"]["requires_any_wstrb"] is not True:
        raise GenerationError("AXI accepted-write WSTRB gate changed")
    unknown_unstrobed = unstrobed - register_names
    if unknown_unstrobed:
        raise GenerationError(f"unknown legacy unstrobed registers: {sorted(unknown_unstrobed)}")
    actual_unstrobed = {
        register["name"]
        for register in spec["registers"]
        if register["write_strobe"] == "IGNORED_AFTER_ACCEPTED_WRITE"
    }
    if unstrobed != actual_unstrobed:
        raise GenerationError("legacy unstrobed register list disagrees with register entries")

    validate_abi_1_1_semantics(spec, parameters)


def evaluate_static_value(
    field: dict[str, Any], parameter_values: dict[str, int]
) -> int:
    value = field.get("static_value")
    if isinstance(value, dict):
        parameter_ref = value.get("parameter_ref")
        if parameter_ref not in parameter_values:
            raise GenerationError(
                f"unknown static parameter expression: {parameter_ref}"
            )
        return parameter_values[parameter_ref]
    return parse_uint(value, f"{field['name']}.static_value")


def composed_register_value(
    register: dict[str, Any], parameter_values: dict[str, int]
) -> int:
    value = 0
    for field in register["fields"]:
        if "static_value" in field:
            field_value = evaluate_static_value(field, parameter_values)
        else:
            field_value = parse_uint(
                field["reset"], f"{register['name']}.{field['name']}.reset"
            )
        width = field["msb"] - field["lsb"] + 1
        if field_value >= (1 << width):
            raise GenerationError(
                f"field value exceeds width: {register['name']}.{field['name']}"
            )
        value |= field_value << field["lsb"]
    return value


def validate_abi_1_1_semantics(
    spec: dict[str, Any], parameters: dict[str, dict[str, Any]]
) -> None:
    registers = {register["name"]: register for register in spec["registers"]}
    legacy_registers = [
        register
        for register in spec["registers"]
        if parse_uint(register["offset"], register["name"]) <= LEGACY_LAST_OFFSET
    ]
    added_registers = [registers[name] for name in ABI_1_1_ADDED_OFFSETS]
    legacy_field_count = sum(len(register["fields"]) for register in legacy_registers)
    added_field_count = sum(len(register["fields"]) for register in added_registers)
    if (len(spec["registers"]), len(legacy_registers), len(added_registers)) != (
        33,
        25,
        8,
    ):
        raise GenerationError("ABI 1.1 register counts must be total=33 legacy=25 added=8")
    if (legacy_field_count, added_field_count) != (54, 43):
        raise GenerationError("ABI 1.1 field counts must be legacy=54 added=43")
    if sum(register["width"] for register in added_registers) != 256:
        raise GenerationError("ABI 1.1 selected register bit coverage must be 256")

    causes = {cause["name"]: cause for cause in spec["fault_causes"]}
    if len(causes) != len(spec["fault_causes"]) or {
        name: cause["bit"] for name, cause in causes.items()
    } != FAULT_CAUSE_BITS:
        raise GenerationError("fault-cause taxonomy must be the selected six-bit mapping")
    for name, cause in causes.items():
        expected_names = {
            "rtl": f"FAULT_CAUSE_{name}",
            "c": f"PROTECTION_FAULT_CAUSE_{name}",
            "python": f"FAULT_CAUSE_{name}",
            "systemverilog": f"FAULT_CAUSE_{name}",
            "ipxact": name,
            "documentation": name,
        }
        if cause["public_names"] != expected_names:
            raise GenerationError(f"fault-cause public names changed: {name}")

    contract = spec["abi_1_1_contract"]
    if contract["explicit_enable_parameter"] != "EXPLICIT_ABI_1_1":
        raise GenerationError("explicit ABI enable parameter identity changed")
    expected_sources = {
        "SRC_STAGE2G_STATE": (
            "rtl/protection_fsm.v",
            "stage2g_fault_episode_controller",
            "state",
            4,
        ),
        "SRC_CLEAR_PENDING": (
            "rtl/protection_fsm.v",
            "stage2g_fault_episode_controller",
            "clear_pending",
            1,
        ),
        "SRC_POST_CLEAR_RECOVERY_PENDING": (
            "rtl/protection_fsm.v",
            "stage2g_fault_episode_controller",
            "post_clear_recovery_pending",
            1,
        ),
        "SRC_FIRST_FAULT_BITMAP": (
            "rtl/protection_fsm.v",
            "stage2g_fault_episode_controller",
            "first_fault_bitmap",
            6,
        ),
        "SRC_LIVE_FAULT_BITMAP": (
            "rtl/protection_fsm.v",
            "stage2g_fault_episode_controller",
            "live_fault_bitmap",
            6,
        ),
        "SRC_FAULT_SEEN_BITMAP": (
            "rtl/protection_fsm.v",
            "stage2g_fault_episode_controller",
            "fault_seen_bitmap",
            6,
        ),
        "SRC_FAULT_EVAL_VALID": (
            "rtl/fault_classifier.v",
            "stage2g_fault_evaluation_pipeline",
            "fault_eval_valid",
            1,
        ),
        "SRC_FAULT_EVAL_SEQUENCE": (
            "rtl/fault_classifier.v",
            "stage2g_fault_evaluation_pipeline",
            "fault_eval_sequence",
            "OBS_SEQUENCE_WIDTH",
        ),
        "SRC_FAULT_EVAL_BITMAP": (
            "rtl/fault_classifier.v",
            "stage2g_fault_evaluation_pipeline",
            "fault_eval_bitmap",
            6,
        ),
        "SRC_FAULT_EVAL_INTEGRITY_CLEAN": (
            "rtl/fault_classifier.v",
            "stage2g_fault_evaluation_pipeline",
            "fault_eval_integrity_clean",
            1,
        ),
    }
    sources = {source["id"]: source for source in contract["rtl_sources"]}
    if len(sources) != len(contract["rtl_sources"]) or set(sources) != set(
        expected_sources
    ):
        raise GenerationError("ABI 1.1 RTL source inventory changed")
    for source_id, expected in expected_sources.items():
        source = sources[source_id]
        actual = (
            source["file"],
            source["module"],
            source["signal"],
            source["width"],
        )
        if actual != expected:
            raise GenerationError(f"wrong ABI 1.1 RTL source: {source_id}")
        if source["clock_domain"] != "ACLK" or source["reset_domain"] != (
            "LOCAL_ACTIVE_LOW_RESET"
        ):
            raise GenerationError(f"wrong ABI 1.1 source domain: {source_id}")
    if sources["SRC_STAGE2G_STATE"].get("state_encodings") != {
        "ST_ARMED": 0,
        "ST_FAULT_LATCHED": 1,
        "ST_RESET_WAIT": 2,
    }:
        raise GenerationError("Stage 2G public state encodings changed")
    if any(
        "state_encodings" in source
        for source_id, source in sources.items()
        if source_id != "SRC_STAGE2G_STATE"
    ):
        raise GenerationError("state encodings are attached to a non-state source")

    template_ids = [item["id"] for item in contract["conformance_templates"]]
    expected_templates = {
        "RO_STATIC",
        "RO_STATE_DECODE",
        "RO_LEVEL",
        "RO_BITMAP",
        "RO_EVENT_CAPTURE",
        "FAULT_PROJECTION",
        "FAULT_FORWARD_COMPATIBILITY",
    }
    if len(template_ids) != len(set(template_ids)) or set(template_ids) != (
        expected_templates
    ):
        raise GenerationError("finite ABI 1.1 conformance template inventory changed")
    expected_routes = {
        "CF_REGISTER_MAP_VERSION_STATIC": {"RO_STATIC"},
        "CF_CAPABILITIES_0_STATIC": {"RO_STATIC"},
        "CF_CAPABILITIES_1_METADATA": {"RO_STATIC"},
        "CF_POLICY_STATUS_LEVEL": {"RO_STATE_DECODE", "RO_LEVEL"},
        "CF_EPISODE_BITMAP": {"RO_BITMAP"},
        "CF_DIAGNOSTIC_LAST_RETIREMENT_IDENTITY": {"RO_EVENT_CAPTURE"},
        "CF_RSVD_ZERO_IGNORE": {"RO_STATIC"},
        "CF_FAULT_TAXONOMY_COMPATIBILITY_PROJECTION": {"FAULT_PROJECTION"},
        "CF_FAULT_FORWARD_COMPATIBILITY": {"FAULT_FORWARD_COMPATIBILITY"},
    }
    routes = {
        route["family"]: set(route["templates"])
        for route in contract["conformance_routes"]
    }
    if len(routes) != len(contract["conformance_routes"]) or routes != expected_routes:
        raise GenerationError("finite ABI 1.1 conformance routes changed")

    field_refs: dict[str, dict[str, Any]] = {}
    binding_owners: dict[str, str] = {}
    for register in added_registers:
        for field in register["fields"]:
            target = f"{register['name']}.{field['name']}"
            field_refs[target] = field
            behavior = field.get("behavior_id")
            binding = field.get("rtl_binding_id")
            gate = field.get("capability_gate_ref")
            family = field.get("conformance_family")
            if behavior not in ABI_1_1_BEHAVIORS:
                raise GenerationError(f"missing or invalid behavior identity: {target}")
            if not binding or not gate or not family:
                raise GenerationError(f"missing ABI 1.1 binding or route: {target}")
            owner = binding_owners.get(binding)
            if owner is not None:
                raise GenerationError(
                    f"duplicate RTL binding identity: {binding}: {owner}, {target}"
                )
            binding_owners[binding] = target
            if gate != f"FIELD_{register['name']}_{field['name']}":
                raise GenerationError(f"wrong field capability gate identity: {target}")
            required_template = CONFORMANCE_TEMPLATE_FOR_BEHAVIOR[behavior]
            if family not in routes or required_template not in routes[family]:
                raise GenerationError(f"wrong conformance route for behavior: {target}")
            has_static = "static_value" in field
            has_dynamic = "dynamic_source" in field
            if has_static == has_dynamic:
                raise GenerationError(
                    f"ABI 1.1 field must have exactly one value authority: {target}"
                )
            if behavior in {"RO_STATIC", "RSVD_ZERO_IGNORE"} and not has_static:
                raise GenerationError(f"static behavior lacks static value: {target}")
            if behavior not in {"RO_STATIC", "RSVD_ZERO_IGNORE"} and not has_dynamic:
                raise GenerationError(f"dynamic behavior lacks source: {target}")
            if has_static and not isinstance(field["static_value"], dict):
                static_value = parse_uint(field["static_value"], f"{target}.static_value")
                if static_value != parse_uint(field["reset"], f"{target}.reset"):
                    raise GenerationError(f"static value/reset disagreement: {target}")
            if has_dynamic:
                dynamic = field["dynamic_source"]
                source_ref = dynamic.get("source_ref")
                if source_ref not in sources:
                    raise GenerationError(f"unknown dynamic source: {target}")
                expected_keys = {
                    "STATE_EQUALS": {
                        "kind",
                        "source_ref",
                        "transform",
                        "state_ref",
                    },
                    "SIGNAL": {"kind", "source_ref", "transform"},
                    "BITMAP_BIT": {
                        "kind",
                        "source_ref",
                        "transform",
                        "source_bit",
                        "mask",
                    },
                    "EVENT_CAPTURE": {
                        "kind",
                        "source_ref",
                        "transform",
                        "valid_source_ref",
                    },
                }
                kind = dynamic.get("kind")
                if kind not in expected_keys or set(dynamic) != expected_keys[kind]:
                    raise GenerationError(f"opaque or malformed dynamic source: {target}")
                expected_transform = {
                    "STATE_EQUALS": "BOOLEAN_COMPARE",
                    "SIGNAL": "IDENTITY",
                    "BITMAP_BIT": "MASK_AND_SELECT",
                    "EVENT_CAPTURE": "ZERO_EXTEND",
                }[kind]
                if dynamic["transform"] != expected_transform:
                    raise GenerationError(f"wrong dynamic transform: {target}")
                if kind == "STATE_EQUALS":
                    if source_ref != "SRC_STAGE2G_STATE" or dynamic["state_ref"] not in (
                        sources[source_ref]["state_encodings"]
                    ):
                        raise GenerationError(f"wrong state decode source: {target}")
                elif kind == "SIGNAL":
                    if sources[source_ref]["width"] != 1:
                        raise GenerationError(f"level source is not one bit: {target}")
                elif kind == "BITMAP_BIT":
                    if (
                        dynamic["source_bit"] != field["lsb"]
                        or parse_uint(dynamic["mask"], f"{target}.mask") != 0x3F
                        or sources[source_ref]["width"] != 6
                    ):
                        raise GenerationError(f"wrong bitmap source, bit, width, or mask: {target}")
                elif kind == "EVENT_CAPTURE":
                    if (
                        source_ref != "SRC_FAULT_EVAL_SEQUENCE"
                        or dynamic["valid_source_ref"] != "SRC_FAULT_EVAL_VALID"
                    ):
                        raise GenerationError(f"wrong event-capture source: {target}")

    default_parameters = {
        name: parameter["default"] for name, parameter in parameters.items()
    }
    for register in added_registers:
        if composed_register_value(register, default_parameters) != parse_uint(
            register["reset"], f"{register['name']}.reset"
        ):
            raise GenerationError(
                f"register reset disagrees with field authorities: {register['name']}"
            )
    if parse_uint(registers["REGISTER_MAP_VERSION"]["reset"], "version") != (
        0x524D0101
    ):
        raise GenerationError("REGISTER_MAP_VERSION must equal 0x524D0101")
    if parse_uint(registers["CAPABILITIES_0"]["reset"], "capabilities_0") != (
        0x0000006F
    ):
        raise GenerationError("CAPABILITIES_0 must equal 0x0000006F")
    for width, expected in ((16, 0x20101006), (24, 0x20101806), (32, 0x20102006)):
        values = dict(default_parameters)
        values["OBS_SEQUENCE_WIDTH"] = width
        if composed_register_value(registers["CAPABILITIES_1"], values) != expected:
            raise GenerationError(f"wrong CAPABILITIES_1 value for width {width}")

    api_gates = {
        item["id"]: set(item["features"]) for item in contract["api_gates"]
    }
    if len(api_gates) != len(contract["api_gates"]) or api_gates != EXPECTED_API_GATES:
        raise GenerationError("ABI 1.1 software API gate inventory changed")
    capabilities = {item["id"]: item for item in contract["capabilities"]}
    if len(capabilities) != len(contract["capabilities"]) or set(capabilities) != set(
        EXPECTED_CAPABILITY_TARGETS
    ):
        raise GenerationError("ABI 1.1 capability inventory changed")
    expected_capability_fields = {
        "ARMED_READY": "CAPABILITIES_0.ARMED_READY",
        "FAULT_BITMAPS": "CAPABILITIES_0.FAULT_BITMAPS",
        "CLEAR_LEVEL_STATUS": "CAPABILITIES_0.CLEAR_LEVEL_STATUS",
        "STAGE2G_POLICY": "CAPABILITIES_0.STAGE2G_POLICY",
        "NORMALIZED_TELEMETRY": (
            "CAPABILITIES_0.NORMALIZED_TELEMETRY_RESERVED_ZERO"
        ),
        "STAGE2E_TRANSACTION_OBSERVABILITY": (
            "CAPABILITIES_0.STAGE2E_TRANSACTION_OBSERVABILITY"
        ),
        "POLICY_EVALUATION_IDENTITY": (
            "CAPABILITIES_0.POLICY_EVALUATION_IDENTITY"
        ),
    }
    for capability_id, capability in capabilities.items():
        if capability["bit"] != list(EXPECTED_CAPABILITY_TARGETS).index(capability_id):
            raise GenerationError(f"wrong capability bit: {capability_id}")
        if capability["field_ref"] != expected_capability_fields[capability_id]:
            raise GenerationError(f"wrong capability field reference: {capability_id}")
        if capability["advertised"] is (capability_id == "NORMALIZED_TELEMETRY"):
            raise GenerationError(f"wrong capability advertisement: {capability_id}")
        edges = {edge["target"]: edge for edge in capability["required_edges"]}
        if len(edges) != len(capability["required_edges"]) or set(edges) != (
            EXPECTED_CAPABILITY_TARGETS[capability_id]
        ):
            raise GenerationError(f"incomplete capability dependencies: {capability_id}")
        for target, edge in edges.items():
            field = field_refs.get(target)
            if field is None:
                raise GenerationError(f"capability dependency target is not a field: {target}")
            if (
                edge["rtl_binding_id"] != field["rtl_binding_id"]
                or edge["conformance_family"] != field["conformance_family"]
            ):
                raise GenerationError(
                    f"capability dependency uses unrelated binding or route: {target}"
                )
        if set(capability["required_api_gates"]) != EXPECTED_CAPABILITY_API_REFS[
            capability_id
        ]:
            raise GenerationError(f"incomplete capability API gates: {capability_id}")

    expected_metadata = {
        "FAULT_BITMAP_WIDTH_RANGE_6_TO_32",
        "IMPLEMENTED_SEQUENCE_WIDTH_RANGE_16_TO_32",
        "MIN_SEQUENCE_WIDTH_EQUALS_16",
        "MAX_SEQUENCE_WIDTH_EQUALS_32",
        "MIN_LE_IMPLEMENTED_LE_MAX",
        "NORMALIZED_TELEMETRY_RESERVED_ZERO",
        "CAPABILITIES_0_RESERVED_BITS_ZERO",
        "STAGE2E_OBS_CAPABILITY_EXACT_FROZEN",
        "STAGE2G_PUBLIC_CONTRACT_CONNECTED",
        "POLICY_EVALUATION_IDENTITY_DIAGNOSTIC_ONLY",
    }
    metadata = set(contract["metadata_constraints"])
    if len(metadata) != len(contract["metadata_constraints"]) or metadata != expected_metadata:
        raise GenerationError("ABI 1.1 metadata constraint inventory changed")
    for capability_id, capability in capabilities.items():
        required_metadata = set(capability["required_metadata_constraints"])
        if required_metadata != EXPECTED_CAPABILITY_METADATA_REFS[capability_id]:
            raise GenerationError(
                f"incomplete capability metadata constraints: {capability_id}"
            )

    invariant_ids = [item["id"] for item in contract["invariants"]]
    expected_invariants = {
        "POLICY_STATE_EXACTLY_ONE",
        "CLEAR_PENDING_IMPLIES_FAULT_LATCHED",
        "POST_CLEAR_PENDING_IMPLIES_RESET_WAIT",
        "ARMED_READY_EXCLUDES_PENDING_LEVELS",
        "BITMAP_UPPER_BITS_ZERO",
        "BITMAPS_ZERO_OUTSIDE_ACTIVE_EPISODE",
        "FIRST_FAULT_IMMUTABLE_DURING_EPISODE",
        "FAULT_SEEN_MONOTONIC_OR_DURING_EPISODE",
    }
    if len(invariant_ids) != len(set(invariant_ids)) or set(invariant_ids) != (
        expected_invariants
    ):
        raise GenerationError("ABI 1.1 invariant inventory changed")
    for invariant in contract["invariants"]:
        for target in invariant["targets"]:
            if target not in field_refs and target not in registers:
                raise GenerationError(f"invariant has unknown target: {target}")

    projection_rules = contract["fault_projection"]
    fault_values = {fault["name"]: fault["value"] for fault in spec["fault_codes"]}
    if {rule["code"] for rule in projection_rules} != set(fault_values):
        raise GenerationError("fault projection does not cover all compatibility codes")
    for rule in projection_rules:
        if any(cause not in causes for cause in rule["causes"]):
            raise GenerationError(f"fault projection references an unknown cause: {rule['code']}")

    def projected_code(bitmap: int) -> int:
        asserted = {
            name for name, bit in FAULT_CAUSE_BITS.items() if bitmap & (1 << bit)
        }
        for rule in projection_rules:
            selected = set(rule["causes"])
            if rule["kind"] == "OVERCURRENT_AND_SENSOR":
                matches = bool(
                    asserted & {"CH1_OVERCURRENT", "CH2_OVERCURRENT"}
                ) and bool(asserted - {"CH1_OVERCURRENT", "CH2_OVERCURRENT"})
            elif rule["kind"] == "ANY_OF":
                matches = bool(asserted & selected)
            else:
                matches = not bool(asserted & selected)
            if matches:
                return fault_values[rule["code"]]
        raise GenerationError(f"fault projection has no result for bitmap 0x{bitmap:02X}")

    for bitmap in range(64):
        overcurrent = bool(bitmap & 0x03)
        sensor = bool(bitmap & 0x3C)
        expected = (
            6
            if overcurrent and sensor
            else 1
            if overcurrent
            else 4
            if bitmap & (1 << FAULT_CAUSE_BITS["SENSOR_SATURATION"])
            else 3
            if bitmap & (1 << FAULT_CAUSE_BITS["SENSOR_OPEN"])
            else 5
            if bitmap & (1 << FAULT_CAUSE_BITS["SENSOR_STUCK"])
            else 2
            if bitmap & (1 << FAULT_CAUSE_BITS["SENSOR_MISMATCH_OR_DIFFERENTIAL"])
            else 0
        )
        if projected_code(bitmap) != expected:
            raise GenerationError(
                f"fault projection differs from frozen priority at bitmap 0x{bitmap:02X}"
            )

    if contract["fault_forward_compatibility"] != {
        "known_width": 6,
        "minimum_advertised_width": 6,
        "maximum_advertised_width": 32,
        "preserve_unknown_within_width": True,
        "reject_bits_above_width": True,
    }:
        raise GenerationError("fault forward-compatibility contract changed")
    if contract["policy_identity"] != {
        "data_source_ref": "SRC_FAULT_EVAL_SEQUENCE",
        "valid_source_ref": "SRC_FAULT_EVAL_VALID",
        "destination_width": 32,
        "capture_clean": True,
        "capture_nonclean": True,
        "hold_when_invalid": True,
        "reset": 0,
        "transform": "ZERO_EXTEND",
        "snapshot_token": False,
    }:
        raise GenerationError("policy evaluation identity contract changed")


def baseline_uint(value: Any, label: str) -> int:
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, str):
        match = re.search(r"0x[0-9A-Fa-f]+", value)
        if match:
            return int(match.group(0), 16)
        match = re.search(r"(?:default|production default)\s+([0-9]+)", value)
        if match:
            return int(match.group(1))
        if value.isdigit():
            return int(value)
    raise GenerationError(f"cannot parse frozen baseline value {label}: {value!r}")


def source_register_access(register: dict[str, Any]) -> str:
    access = register["access"]
    if register["write_strobe"] == "IGNORED_AFTER_ACCEPTED_WRITE":
        return f"{access} with legacy unstrobed writes"
    return access


def remediation_rows(
    spec: dict[str, Any], baseline: dict[str, Any]
) -> list[dict[str, Any]]:
    registers = {register["name"]: register for register in spec["registers"]}
    fields = {
        f"{register['name']}.{field['name']}": field
        for register in spec["registers"]
        for field in register["fields"]
    }
    bus = spec["bus_behavior"]
    corrections: dict[str, tuple[str, str, str]] = {
        "STATUS_FAULT_VALID_DESCRIPTION_STALE": (
            "STATUS.fault_valid",
            fields["STATUS.fault_valid"]["read_behavior"],
            "generated field description and A1 parity test",
        ),
        "STATUS_FAULT_LATCHED_CLEAR_DESCRIPTION_STALE": (
            "STATUS.fault_latched",
            fields["STATUS.fault_latched"]["read_behavior"],
            "generated field description and Stage 2G production regression",
        ),
        "CURRENT_MONITOR_DESCRIPTION_STALE": (
            "I_CH1.i_ch1_mon / I_CH2.i_ch2_mon",
            bus["current_monitor_pair"]["description"],
            "generated monitor contract and Stage 2G production regression",
        ),
        "LEGACY_WRITES_IGNORE_WSTRB_UNDOCUMENTED": (
            ", ".join(bus["accepted_write"]["legacy_unstrobed_registers"]),
            "After an AXI write is accepted by any nonzero WSTRB, these legacy fields consume their WDATA bits without byte qualification.",
            "generated bus contract and legacy AXI simulation",
        ),
        "UNDEFINED_READ_ZERO_OKAY_UNDOCUMENTED": (
            "undefined read",
            "Undefined reads return zero with an OKAY response.",
            "generated bus contract and legacy AXI simulation",
        ),
        "UNDEFINED_WRITE_NO_EFFECT_OKAY_UNDOCUMENTED": (
            "undefined write",
            "Undefined writes have no effect and return an OKAY response.",
            "generated bus contract and legacy AXI simulation",
        ),
        "LOW_EIGHT_BIT_ADDRESS_ALIAS_UNDOCUMENTED": (
            "address decode",
            "Only address bits 7:0 participate in decode, so wider outer segments alias on matching low eight bits.",
            "generated bus contract and packaging metadata test",
        ),
        "CURRENT_MONITOR_SOFTWARE_READS_NONATOMIC_UNDOCUMENTED": (
            "I_CH1 / I_CH2 software reads",
            bus["current_monitor_pair"]["description"],
            "generated monitor contract and software-interface documentation",
        ),
    }
    try:
        defects = baseline["current_abi"]["defects"]
    except (KeyError, TypeError) as exc:
        raise GenerationError("frozen A1 baseline lacks current_abi.defects") from exc
    if not isinstance(defects, list) or len(defects) != 8:
        raise GenerationError("frozen A1 baseline must contain exactly eight current-ABI defects")
    rows: list[dict[str, Any]] = []
    for defect in defects:
        defect_id = defect.get("id")
        if defect_id not in corrections:
            raise GenerationError(f"unmapped frozen A1 remediation: {defect_id}")
        target, correction, verification = corrections[defect_id]
        rows.append(
            {
                "id": defect_id,
                "register_field_or_behavior": target,
                "current_rtl_truth": defect.get("frozen_behavior"),
                "old_documentation_or_software_statement": defect.get("claim_or_gap"),
                "classification": defect.get("classification"),
                "a2_correction": correction,
                "behavior_changed": False,
                "verification": verification,
            }
        )
    return rows


def validate_legacy_parity(
    spec: dict[str, Any], baseline: dict[str, Any]
) -> dict[str, Any]:
    try:
        current = baseline["current_abi"]
        baseline_registers = current["registers"]
        baseline_faults = baseline["fault_taxonomy"]["fault_codes"]
        baseline_artifacts = [
            item["path"] for item in baseline["selected_single_source"]["generated_artifacts"]
        ]
    except (KeyError, TypeError) as exc:
        raise GenerationError("frozen A1 baseline does not expose the required ABI inventory") from exc

    if current.get("occupied_range") != "0x00..0x60":
        raise GenerationError("frozen A1 occupied range changed")
    if baseline_artifacts != list(MASTER_ARTIFACTS):
        raise GenerationError("live generated topology differs from frozen A1 master list")

    source_registers = {
        register["name"]: register
        for register in spec["registers"]
        if parse_uint(register["offset"], register["name"])
        <= LEGACY_LAST_OFFSET
    }
    if len(baseline_registers) != len(source_registers):
        raise GenerationError("legacy register count differs from frozen A1 baseline")
    offset_changes = 0
    width_changes = 0
    access_changes = 0
    reset_changes = 0
    field_changes = 0
    for frozen in baseline_registers:
        name = frozen["name"]
        source = source_registers.get(name)
        if source is None:
            raise GenerationError(f"legacy register removed: {name}")
        expected_register_names = {
            "rtl": f"PROTECTION_REG_{name}",
            "c": f"PROTECTION_REG_{name}",
            "python": f"REG_{name}",
            "systemverilog": f"REG_{name}",
            "ipxact": name,
            "documentation": name,
        }
        if source["public_names"] != expected_register_names:
            raise GenerationError(f"legacy software register name changed: {name}")
        offset_changes += parse_uint(source["offset"], f"{name}.offset") != baseline_uint(
            frozen["offset"], f"baseline {name}.offset"
        )
        width_changes += source["width"] != frozen["width"]
        access_changes += source_register_access(source) != frozen["register_access"]
        reset_changes += parse_uint(source["reset"], f"{name}.reset") != baseline_uint(
            frozen["reset"], f"baseline {name}.reset"
        )
        source_fields = {field["name"]: field for field in source["fields"]}
        if len(source_fields) != len(frozen["fields"]):
            field_changes += 1
        for frozen_field in frozen["fields"]:
            field_name = frozen_field["name"]
            source_field = source_fields.get(field_name)
            if source_field is None:
                field_changes += 1
                continue
            field_changes += (
                source_field["lsb"] != frozen_field["bits"]["lsb"]
                or source_field["msb"] != frozen_field["bits"]["msb"]
                or source_field["access"] != frozen_field["access"]
                or parse_uint(source_field["reset"], f"{name}.{field_name}.reset")
                != baseline_uint(
                    frozen_field["reset"], f"baseline {name}.{field_name}.reset"
                )
            )
            legacy_constant = FROZEN_LEGACY_FIELD_CONSTANTS.get((name, field_name))
            if legacy_constant is not None:
                names = source_field["public_names"]
                if (
                    names["python"] != legacy_constant
                    or names["c"] != f"PROTECTION_{legacy_constant}"
                ):
                    raise GenerationError(
                        f"legacy software field name changed: {name}.{field_name}"
                    )
    changes = offset_changes + width_changes + access_changes + reset_changes + field_changes
    if changes:
        raise GenerationError(
            "legacy ABI parity failed: "
            f"offset={offset_changes} width={width_changes} access={access_changes} "
            f"reset={reset_changes} field={field_changes}"
        )

    source_faults = {fault["name"]: fault for fault in spec["fault_codes"]}
    if len(source_faults) != len(baseline_faults):
        raise GenerationError("fault taxonomy count differs from frozen A1 baseline")
    fault_changes = 0
    alias_changes = 0
    for frozen in baseline_faults:
        name = frozen["canonical_name"]
        source = source_faults.get(name)
        if source is None:
            fault_changes += 1
            continue
        for language, baseline_key in (
            ("rtl", "rtl_name"),
            ("c", "c_name"),
            ("systemverilog", "systemverilog_name"),
            ("ipxact", "ipxact_name"),
        ):
            if source["public_names"][language] != frozen[baseline_key]:
                raise GenerationError(
                    f"legacy fault public name changed: {name}.{language}"
                )
        if source["public_names"]["python"] != f"FAULT_{name}":
            raise GenerationError(f"legacy Python fault name changed: {name}")
        fault_changes += source["value"] != frozen["value"]
        actual_rtl_aliases = {
            source["public_names"]["rtl"],
            *source["legacy_aliases"]["rtl"],
        }
        actual_c_aliases = {
            source["public_names"]["c"],
            *source["legacy_aliases"]["c"],
        }
        for alias in frozen["legacy_aliases"]:
            aliases = actual_c_aliases if alias.startswith("PROTECTION_") else actual_rtl_aliases
            alias_changes += alias not in aliases
    if fault_changes or alias_changes:
        raise GenerationError(
            f"legacy fault taxonomy parity failed: values={fault_changes} aliases={alias_changes}"
        )

    remediations = remediation_rows(spec, baseline)
    contradiction_count = sum(
        row["classification"] == "DOCUMENTATION_VS_RTL_CONTRADICTION"
        for row in remediations
    )
    undocumented_count = sum(
        row["classification"] == "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR"
        for row in remediations
    )
    if (contradiction_count, undocumented_count) != (3, 5):
        raise GenerationError("frozen A1 remediation classification count changed")
    return {
        "register_count": len(source_registers),
        "field_count": sum(len(register["fields"]) for register in source_registers.values()),
        "total_register_count": len(spec["registers"]),
        "total_field_count": sum(len(register["fields"]) for register in spec["registers"]),
        "added_register_count": len(spec["registers"]) - len(source_registers),
        "added_field_count": (
            sum(len(register["fields"]) for register in spec["registers"])
            - sum(len(register["fields"]) for register in source_registers.values())
        ),
        "fault_code_count": len(source_faults),
        "offset_changes": offset_changes,
        "width_changes": width_changes,
        "field_encoding_changes": field_changes,
        "access_semantic_changes": access_changes,
        "reset_semantic_changes": reset_changes,
        "fault_code_changes": fault_changes,
        "fault_alias_changes": alias_changes,
        "documentation_contradictions_closed": contradiction_count,
        "undocumented_behaviors_closed": undocumented_count,
        "remediations": remediations,
    }


def field_mask(field: dict[str, Any]) -> int:
    width = field["msb"] - field["lsb"] + 1
    return ((1 << width) - 1) << field["lsb"]


def hex_value(value: int, digits: int = 8) -> str:
    return f"0x{value:0{digits}X}"


def register_named(spec: dict[str, Any], name: str) -> dict[str, Any]:
    return next(register for register in spec["registers"] if register["name"] == name)


def abi_1_1_render_values(spec: dict[str, Any]) -> dict[str, Any]:
    version = register_named(spec, "REGISTER_MAP_VERSION")
    capabilities_0 = register_named(spec, "CAPABILITIES_0")
    capabilities_1 = register_named(spec, "CAPABILITIES_1")
    sequence_field = next(
        field
        for field in capabilities_1["fields"]
        if field["name"] == "IMPLEMENTED_SEQUENCE_WIDTH"
    )
    sequence_mask = field_mask(sequence_field)
    capabilities_1_base = (
        parse_uint(capabilities_1["reset"], "CAPABILITIES_1.reset")
        & ~sequence_mask
    )
    fault_width = len(spec["fault_causes"])
    valid_mask = (1 << fault_width) - 1
    state_source = next(
        source
        for source in spec["abi_1_1_contract"]["rtl_sources"]
        if source["id"] == "SRC_STAGE2G_STATE"
    )
    return {
        "version": parse_uint(version["reset"], "REGISTER_MAP_VERSION.reset"),
        "capabilities_0": parse_uint(
            capabilities_0["reset"], "CAPABILITIES_0.reset"
        ),
        "capabilities_0_known_mask": sum(
            field_mask(field)
            for field in capabilities_0["fields"]
            if field["name"] != "RESERVED_ZERO"
        ),
        "capabilities_0_reserved_mask": (
            field_mask(
                next(
                    field
                    for field in capabilities_0["fields"]
                    if field["name"] == "RESERVED_ZERO"
                )
            )
        ),
        "capabilities_0_normalized_reserved_mask": field_mask(
            next(
                field
                for field in capabilities_0["fields"]
                if field["name"] == "NORMALIZED_TELEMETRY_RESERVED_ZERO"
            )
        ),
        "capabilities_1_base": capabilities_1_base,
        "capabilities_1_sequence_lsb": sequence_field["lsb"],
        "capabilities_1_sequence_mask": sequence_mask,
        "capabilities_1_widths": {
            width: capabilities_1_base | (width << sequence_field["lsb"])
            for width in (16, 24, 32)
        },
        "fault_bitmap_width": fault_width,
        "fault_bitmap_valid_mask": valid_mask,
        "fault_bitmap_reserved_mask": (~valid_mask) & 0xFFFF_FFFF,
        "state_encodings": state_source["state_encodings"],
    }


def generated_banner(prefix: str, spec_hash: str) -> list[str]:
    return [
        f"{prefix} Generated by tools/generate_register_map.py; do not edit.",
        f"{prefix} GENERATOR_VERSION={GENERATOR_VERSION}",
        f"{prefix} REGISTER_MAP_SCHEMA_VERSION={SCHEMA_VERSION}",
        f"{prefix} REGISTER_MAP_CANONICAL_SHA256={spec_hash}",
    ]


def render_rtl(spec: dict[str, Any], spec_hash: str) -> str:
    abi_values = abi_1_1_render_values(spec)
    lines = [*generated_banner("//", spec_hash), "", "`ifndef PROTECTION_REGISTER_MAP_VH", "`define PROTECTION_REGISTER_MAP_VH", ""]
    for register in spec["registers"]:
        offset = parse_uint(register["offset"], register["name"])
        reset = parse_uint(register["reset"], register["name"])
        rtl_name = register["public_names"]["rtl"]
        lines.extend(
            [
                f"`define {rtl_name} 8'h{offset:02X}",
                f"`define {rtl_name}_RESET 32'h{reset:08X}",
            ]
        )
        for field in register["fields"]:
            public = field["public_names"]["rtl"]
            mask = field_mask(field)
            reset_value = parse_uint(field["reset"], public)
            lines.extend(
                [
                    f"`define {public}_LSB {field['lsb']}",
                    f"`define {public}_MSB {field['msb']}",
                    f"`define {public}_MASK 32'h{mask:08X}",
                    f"`define {public}_RESET 32'h{reset_value:08X}",
                    f"`define {public} 32'h{mask:08X}",
                ]
            )
        lines.append("")

    capability = next(register for register in spec["registers"] if register["name"] == "OBS_CAPABILITY")
    parameter_field = next(field for field in capability["fields"] if field.get("parameter_ref"))
    base_value = parse_uint(capability["reset"], "OBS_CAPABILITY.reset") & ~field_mask(parameter_field)
    lines.extend(
        [
            f"`define PROTECTION_OBS_CAPABILITY_VALUE(_sequence_width) (32'h{base_value:08X} | ((_sequence_width) << {parameter_field['lsb']}))",
            "",
            f"`define PROTECTION_REGISTER_MAP_VERSION_VALUE 32'h{abi_values['version']:08X}",
            f"`define PROTECTION_CAPABILITIES_0_ABI_1_1_VALUE 32'h{abi_values['capabilities_0']:08X}",
            "`define PROTECTION_CAPABILITIES_1_VALUE(_sequence_width) "
            f"(32'h{abi_values['capabilities_1_base']:08X} | "
            f"((_sequence_width) << {abi_values['capabilities_1_sequence_lsb']}))",
            f"`define PROTECTION_CAPABILITIES_1_WIDTH16 32'h{abi_values['capabilities_1_widths'][16]:08X}",
            f"`define PROTECTION_CAPABILITIES_1_WIDTH24 32'h{abi_values['capabilities_1_widths'][24]:08X}",
            f"`define PROTECTION_CAPABILITIES_1_WIDTH32 32'h{abi_values['capabilities_1_widths'][32]:08X}",
            f"`define PROTECTION_CAPABILITIES_0_KNOWN_MASK 32'h{abi_values['capabilities_0_known_mask']:08X}",
            f"`define PROTECTION_CAPABILITIES_0_RESERVED_MASK 32'h{abi_values['capabilities_0_reserved_mask']:08X}",
            f"`define PROTECTION_CAPABILITIES_0_NORMALIZED_TELEMETRY_RESERVED_MASK 32'h{abi_values['capabilities_0_normalized_reserved_mask']:08X}",
            f"`define PROTECTION_FAULT_BITMAP_WIDTH {abi_values['fault_bitmap_width']}",
            f"`define PROTECTION_FAULT_BITMAP_VALID_MASK 32'h{abi_values['fault_bitmap_valid_mask']:08X}",
            f"`define PROTECTION_FAULT_BITMAP_RESERVED_MASK 32'h{abi_values['fault_bitmap_reserved_mask']:08X}",
            "",
        ]
    )
    for state, value in abi_values["state_encodings"].items():
        lines.append(f"`define PROTECTION_POLICY_STATE_{state} 4'd{value}")
    lines.append("")
    for cause in spec["fault_causes"]:
        public = cause["public_names"]["rtl"]
        lines.append(f"`define {public} 32'h{1 << cause['bit']:08X}")
    lines.append("")
    for fault in spec["fault_codes"]:
        public = fault["public_names"]["rtl"]
        lines.append(f"`define {public} 8'h{fault['value']:02X}")
        for alias in fault["legacy_aliases"]["rtl"]:
            lines.append(f"`define {alias} `{public}")
    lines.extend(["", "`endif", ""])
    return "\n".join(lines)


def python_export_names(spec: dict[str, Any]) -> list[str]:
    names = ["RegisterOffset", "FaultCode", "FaultCause", "ObservabilityStatus"]
    for register in spec["registers"]:
        names.append(register["public_names"]["python"])
        for field in register["fields"]:
            if field["access"] != "RSVD":
                public = field["public_names"]["python"]
                names.extend([public, f"{public}_LSB", f"{public}_MSB", f"{public}_MASK", f"{public}_RESET"])
    for fault in spec["fault_codes"]:
        names.append(fault["public_names"]["python"])
        names.extend(fault["legacy_aliases"]["python"])
    for cause in spec["fault_causes"]:
        names.append(cause["public_names"]["python"])
    names.extend(
        [
            "OBS_STATUS_W1C_MASK",
            "OBS_STATUS_MASK",
            "OBS_CAPABILITY_DEFAULT",
            "REGISTER_MAP_VERSION_VALUE",
            "CAPABILITIES_0_ABI_1_1_VALUE",
            "CAPABILITIES_0_KNOWN_MASK",
            "CAPABILITIES_0_RESERVED_MASK",
            "CAPABILITIES_0_NORMALIZED_TELEMETRY_RESERVED_MASK",
            "CAPABILITIES_1_WIDTH16",
            "CAPABILITIES_1_WIDTH24",
            "CAPABILITIES_1_WIDTH32",
            "FAULT_BITMAP_WIDTH",
            "FAULT_BITMAP_VALID_MASK",
            "FAULT_BITMAP_RESERVED_MASK",
            "capabilities_1_value",
            "GENERATOR_VERSION",
            "REGISTER_MAP_SCHEMA_VERSION",
            "REGISTER_MAP_CANONICAL_SHA256",
        ]
    )
    return list(dict.fromkeys(names))


def render_python(spec: dict[str, Any], spec_hash: str) -> str:
    abi_values = abi_1_1_render_values(spec)
    lines = [
        *generated_banner("#", spec_hash),
        '"""Generated public register-map constants and compatibility enums."""',
        "",
        "from enum import IntEnum, IntFlag",
        "",
        f'GENERATOR_VERSION = "{GENERATOR_VERSION}"',
        f'REGISTER_MAP_SCHEMA_VERSION = "{SCHEMA_VERSION}"',
        f'REGISTER_MAP_CANONICAL_SHA256 = "{spec_hash}"',
        "",
        "",
        "class RegisterOffset(IntEnum):",
    ]
    for register in spec["registers"]:
        lines.append(
            f"    {register['name']} = 0x{parse_uint(register['offset'], register['name']):02X}"
        )
    lines.extend(["", "", "class FaultCode(IntEnum):"])
    for fault in spec["fault_codes"]:
        lines.append(f"    {fault['name']} = 0x{fault['value']:02X}")
    lines.extend(["", "", "class FaultCause(IntFlag):"])
    for cause in spec["fault_causes"]:
        lines.append(f"    {cause['name']} = 0x{1 << cause['bit']:08X}")
    lines.extend(["", "", "class ObservabilityStatus(IntFlag):"])
    obs_status = next(register for register in spec["registers"] if register["name"] == "OBS_STATUS_W1C")
    for field in obs_status["fields"]:
        if field["access"] != "RSVD":
            lines.append(f"    {field['name']} = 0x{field_mask(field):08X}")
    lines.extend(["", ""])
    for register in spec["registers"]:
        public = register["public_names"]["python"]
        lines.append(f"{public} = int(RegisterOffset.{register['name']})")
    lines.append("")
    for register in spec["registers"]:
        for field in register["fields"]:
            if field["access"] == "RSVD":
                continue
            public = field["public_names"]["python"]
            mask = field_mask(field)
            reset = parse_uint(field["reset"], public)
            lines.extend(
                [
                    f"{public}_LSB = {field['lsb']}",
                    f"{public}_MSB = {field['msb']}",
                    f"{public}_MASK = 0x{mask:08X}",
                    f"{public}_RESET = 0x{reset:08X}",
                    f"{public} = {public}_MASK",
                ]
            )
    lines.append("")
    for fault in spec["fault_codes"]:
        public = fault["public_names"]["python"]
        lines.append(f"{public} = int(FaultCode.{fault['name']})")
        for alias in fault["legacy_aliases"]["python"]:
            lines.append(f"{alias} = {public}")
    lines.append("")
    for cause in spec["fault_causes"]:
        public = cause["public_names"]["python"]
        lines.append(f"{public} = int(FaultCause.{cause['name']})")
    w1c_mask = sum(field_mask(field) for field in obs_status["fields"] if field["access"] == "W1C")
    status_mask = sum(field_mask(field) for field in obs_status["fields"] if field["access"] != "RSVD")
    capability = next(register for register in spec["registers"] if register["name"] == "OBS_CAPABILITY")
    lines.extend(
        [
            "",
            f"OBS_STATUS_W1C_MASK = 0x{w1c_mask:08X}",
            f"OBS_STATUS_MASK = 0x{status_mask:08X}",
            f"OBS_CAPABILITY_DEFAULT = 0x{parse_uint(capability['reset'], 'capability'):08X}",
            f"REGISTER_MAP_VERSION_VALUE = 0x{abi_values['version']:08X}",
            f"CAPABILITIES_0_ABI_1_1_VALUE = 0x{abi_values['capabilities_0']:08X}",
            f"CAPABILITIES_0_KNOWN_MASK = 0x{abi_values['capabilities_0_known_mask']:08X}",
            f"CAPABILITIES_0_RESERVED_MASK = 0x{abi_values['capabilities_0_reserved_mask']:08X}",
            "CAPABILITIES_0_NORMALIZED_TELEMETRY_RESERVED_MASK = "
            f"0x{abi_values['capabilities_0_normalized_reserved_mask']:08X}",
            f"CAPABILITIES_1_WIDTH16 = 0x{abi_values['capabilities_1_widths'][16]:08X}",
            f"CAPABILITIES_1_WIDTH24 = 0x{abi_values['capabilities_1_widths'][24]:08X}",
            f"CAPABILITIES_1_WIDTH32 = 0x{abi_values['capabilities_1_widths'][32]:08X}",
            f"FAULT_BITMAP_WIDTH = {abi_values['fault_bitmap_width']}",
            f"FAULT_BITMAP_VALID_MASK = 0x{abi_values['fault_bitmap_valid_mask']:08X}",
            f"FAULT_BITMAP_RESERVED_MASK = 0x{abi_values['fault_bitmap_reserved_mask']:08X}",
            "",
            "",
            "def capabilities_1_value(sequence_width):",
            "    return (",
            f"        0x{abi_values['capabilities_1_base']:08X}",
            f"        | ((int(sequence_width) << {abi_values['capabilities_1_sequence_lsb']})",
            f"           & 0x{abi_values['capabilities_1_sequence_mask']:08X})",
            "    )",
            "",
            "__all__ = [",
        ]
    )
    for name in python_export_names(spec):
        lines.append(f'    "{name}",')
    lines.extend(["]", ""])
    return "\n".join(lines)


def render_c(spec: dict[str, Any], spec_hash: str) -> str:
    abi_values = abi_1_1_render_values(spec)
    lines = [
        *generated_banner("/*", spec_hash),
    ]
    # Close each banner comment emitted with a compact, C-safe suffix.
    lines = [line + " */" for line in lines]
    lines.extend(
        [
            "",
            "#ifndef PROTECTION_IP_REGS_H",
            "#define PROTECTION_IP_REGS_H",
            "",
            "#include <stdint.h>",
            "",
            "/* Placeholder only; use the address assigned by Vivado Address Editor. */",
            "#ifndef PROTECTION_IP_BASEADDR",
            "#define PROTECTION_IP_BASEADDR 0x43C00000u",
            "#endif",
            "",
        ]
    )
    for register in spec["registers"]:
        public = register["public_names"]["c"]
        offset = parse_uint(register["offset"], register["name"])
        reset = parse_uint(register["reset"], register["name"])
        lines.append(f"#define {public} 0x{offset:02X}u")
        lines.append(f"#define {public}_RESET 0x{reset:08X}u")
    lines.append("")
    for register in spec["registers"]:
        for field in register["fields"]:
            if field["access"] == "RSVD":
                continue
            public = field["public_names"]["c"]
            mask = field_mask(field)
            reset = parse_uint(field["reset"], public)
            lines.extend(
                [
                    f"#define {public}_LSB {field['lsb']}u",
                    f"#define {public}_MSB {field['msb']}u",
                    f"#define {public}_MASK 0x{mask:08X}u",
                    f"#define {public}_RESET 0x{reset:08X}u",
                    f"#define {public} {public}_MASK",
                ]
            )
    obs_status = next(register for register in spec["registers"] if register["name"] == "OBS_STATUS_W1C")
    w1c_mask = sum(field_mask(field) for field in obs_status["fields"] if field["access"] == "W1C")
    status_mask = sum(field_mask(field) for field in obs_status["fields"] if field["access"] != "RSVD")
    lines.extend(
        [
            "",
            f"#define PROTECTION_OBS_STATUS_W1C_MASK 0x{w1c_mask:08X}u",
            f"#define PROTECTION_OBS_STATUS_MASK 0x{status_mask:08X}u",
            f"#define PROTECTION_REGISTER_MAP_VERSION_VALUE 0x{abi_values['version']:08X}u",
            f"#define PROTECTION_CAPABILITIES_0_ABI_1_1_VALUE 0x{abi_values['capabilities_0']:08X}u",
            "#define PROTECTION_CAPABILITIES_1_VALUE(sequence_width) "
            f"(0x{abi_values['capabilities_1_base']:08X}u | "
            f"((uint32_t)(sequence_width) << {abi_values['capabilities_1_sequence_lsb']}u))",
            f"#define PROTECTION_CAPABILITIES_1_WIDTH16 0x{abi_values['capabilities_1_widths'][16]:08X}u",
            f"#define PROTECTION_CAPABILITIES_1_WIDTH24 0x{abi_values['capabilities_1_widths'][24]:08X}u",
            f"#define PROTECTION_CAPABILITIES_1_WIDTH32 0x{abi_values['capabilities_1_widths'][32]:08X}u",
            f"#define PROTECTION_CAPABILITIES_0_KNOWN_MASK 0x{abi_values['capabilities_0_known_mask']:08X}u",
            f"#define PROTECTION_CAPABILITIES_0_RESERVED_MASK 0x{abi_values['capabilities_0_reserved_mask']:08X}u",
            "#define PROTECTION_CAPABILITIES_0_NORMALIZED_TELEMETRY_RESERVED_MASK "
            f"0x{abi_values['capabilities_0_normalized_reserved_mask']:08X}u",
            f"#define PROTECTION_FAULT_BITMAP_WIDTH {abi_values['fault_bitmap_width']}u",
            f"#define PROTECTION_FAULT_BITMAP_VALID_MASK 0x{abi_values['fault_bitmap_valid_mask']:08X}u",
            f"#define PROTECTION_FAULT_BITMAP_RESERVED_MASK 0x{abi_values['fault_bitmap_reserved_mask']:08X}u",
            "",
        ]
    )
    for cause in spec["fault_causes"]:
        public = cause["public_names"]["c"]
        lines.append(f"#define {public} 0x{1 << cause['bit']:08X}u")
    lines.append("")
    for fault in spec["fault_codes"]:
        public = fault["public_names"]["c"]
        lines.append(f"#define {public} 0x{fault['value']:02X}u")
        for alias in fault["legacy_aliases"]["c"]:
            lines.append(f"#define {alias} {public}")
    lines.extend(
        [
            "",
            "static inline void protection_write(uint32_t offset, uint32_t value)",
            "{",
            "    volatile uint32_t *addr =",
            "        (volatile uint32_t *)(uintptr_t)(PROTECTION_IP_BASEADDR + offset);",
            "    *addr = value;",
            "}",
            "",
            "static inline uint32_t protection_read(uint32_t offset)",
            "{",
            "    volatile uint32_t *addr =",
            "        (volatile uint32_t *)(uintptr_t)(PROTECTION_IP_BASEADDR + offset);",
            "    return *addr;",
            "}",
            "",
            "#endif",
            "",
        ]
    )
    return "\n".join(lines)


def ipxact_access(access: str) -> str:
    return "read-only" if access in {"RO", "RSVD"} else "read-write"


def tcl_brace(value: str) -> str:
    return "{" + value.replace("}", "\\}") + "}"


def render_ipxact(spec: dict[str, Any], spec_hash: str) -> str:
    lines = [
        *generated_banner("#", spec_hash),
        "# Source this file, then call protection_register_map_apply_ipxact.",
        "",
        "proc protection_register_map_apply_ipxact {address_block} {",
        "    if {[llength $address_block] != 1} {",
        "        error {protection register-map generator requires one address block}",
        "    }",
    ]
    for register in spec["registers"]:
        name = register["public_names"]["ipxact"]
        offset = parse_uint(register["offset"], register["name"])
        reset = parse_uint(register["reset"], register["name"])
        lines.extend(
            [
                f"    set register [ipx::get_registers {tcl_brace(name)} -of_objects $address_block -quiet]",
                "    if {[llength $register] == 0} {",
                f"        set register [ipx::add_register {tcl_brace(name)} $address_block]",
                "    }",
                f"    set_property address_offset 0x{offset:02X} $register",
                "    set_property size 32 $register",
                f"    set_property access {ipxact_access(register['access'])} $register",
                f"    set_property description {tcl_brace(register['description'])} $register",
                "    set reset_parameter [ipx::get_register_parameters RESET_VALUE -of_objects $register -quiet]",
                "    if {[llength $reset_parameter] == 0} {",
                "        set reset_parameter [ipx::add_register_parameter RESET_VALUE $register]",
                "    }",
                f"    set_property value 0x{reset:08X} $reset_parameter",
            ]
        )
        for field in register["fields"]:
            field_name = field["public_names"]["ipxact"]
            width = field["msb"] - field["lsb"] + 1
            lines.extend(
                [
                    f"    set field [ipx::get_fields {tcl_brace(field_name)} -of_objects $register -quiet]",
                    "    if {[llength $field] == 0} {",
                    f"        set field [ipx::add_field {tcl_brace(field_name)} $register]",
                    "    }",
                    f"    set_property bit_offset {field['lsb']} $field",
                    f"    set_property bit_width {width} $field",
                    f"    set_property access {ipxact_access(field['access'])} $field",
                    f"    set_property description {tcl_brace(field['description'])} $field",
                ]
            )
            if field["access"] == "W1C":
                lines.append("    set_property modified_write_value oneToClear $field")
            elif field["access"] == "W1P":
                lines.append("    set_property modified_write_value oneToSet $field")
            if field.get("enum_ref") == "fault_codes":
                # Vivado 2024.1 models field enums as Name/Value/Usage triples.
                enum_values = []
                for fault in spec["fault_codes"]:
                    enum_values.extend(
                        [
                            tcl_brace(fault["public_names"]["ipxact"]),
                            f"0x{fault['value']:02X}",
                            "read",
                        ]
                    )
                lines.append(
                    "    set_property enumerated_values "
                    f"[list {' '.join(enum_values)}] $field"
                )
        lines.append("")
    lines.extend(
        [
            "    return [llength [ipx::get_registers -of_objects $address_block]]",
            "}",
            "",
            f"set ::PROTECTION_REGISTER_MAP_REGISTER_COUNT {len(spec['registers'])}",
            f"set ::PROTECTION_REGISTER_MAP_GENERATOR_VERSION {tcl_brace(GENERATOR_VERSION)}",
            f"set ::PROTECTION_REGISTER_MAP_SCHEMA_VERSION {tcl_brace(SCHEMA_VERSION)}",
            f"set ::PROTECTION_REGISTER_MAP_CANONICAL_SHA256 {tcl_brace(spec_hash)}",
            "",
        ]
    )
    return "\n".join(lines)


def bits_label(field: dict[str, Any]) -> str:
    return str(field["lsb"]) if field["lsb"] == field["msb"] else f"{field['msb']}:{field['lsb']}"


def render_docs(
    spec: dict[str, Any], spec_hash: str, parity: dict[str, Any]
) -> str:
    lines = [
        "<!-- Generated by tools/generate_register_map.py; do not edit. -->",
        f"<!-- GENERATOR_VERSION={GENERATOR_VERSION} -->",
        f"<!-- REGISTER_MAP_SCHEMA_VERSION={SCHEMA_VERSION} -->",
        f"<!-- REGISTER_MAP_CANONICAL_SHA256={spec_hash} -->",
        "",
        "# Authoritative Register Map",
        "",
        "The live public-ABI source is `spec/register_map.json`. The map preserves the frozen ABI 1.0 compatibility block at `0x00..0x60` and adds the explicit ABI 1.1 discovery and Stage 2G policy block at `0x80..0xB0` using only the selected offsets.",
        "",
        "## ABI Boundaries and Coherence",
        "",
        "- Legacy instances leave `EXPLICIT_ABI_1_1` disabled, so reads in the additive discovery space return zero. The connected Stage 2G production instance enables ABI 1.1.",
        "- Each register read is coherent for that word. ABI 1.1 provides no cross-word atomic snapshot and software must not treat a sequence value as a multi-register epoch.",
        "- `POLICY_EVALUATION_SEQUENCE` is the diagnostic identity of the latest valid policy retirement. It captures clean and nonclean retirements and holds during idle; it is not a snapshot or recovery-completion token.",
        "- Episode bitmaps follow the internal Stage 2G episode lifetime. The legacy compatibility `FAULT_CODE` latch can remain nonzero after those bitmaps clear during post-clear recovery.",
        "",
        "## Register Summary",
        "",
        "| Offset | Register | Access | Reset/static default | Description |",
        "|---:|---|---|---:|---|",
    ]
    for register in spec["registers"]:
        offset = parse_uint(register["offset"], register["name"])
        reset = parse_uint(register["reset"], register["name"])
        lines.append(
            f"| `0x{offset:02X}` | `{register['name']}` | {register['access']} | `0x{reset:08X}` | {register['description']} |"
        )
    bus = spec["bus_behavior"]
    lines.extend(
        [
            "",
            "## Frozen Bus Behavior",
            "",
            "- Only address bits `7:0` participate in register decode. A wider outer address segment therefore aliases when its low eight bits match.",
            "- Undefined reads return `0x00000000` with an AXI `OKAY` response.",
            "- Undefined writes have no effect and return an AXI `OKAY` response.",
            "- Register-bank read data is a combinational address decode; `rd_en` does not gate the decoded value.",
            "- The AXI wrapper accepts a write only when at least one WSTRB is set.",
            "- After acceptance, `CTRL`, `TH_OC1`, `TH_OC2`, `TH_DIFF`, `PWM_PERIOD`, and `PWM_DUTY` consume their defined WDATA bits without byte-strobe qualification. This frozen legacy behavior is intentional.",
            "- `OBS_STATUS_W1C` is byte-qualified: WSTRB byte 0 controls bits 7:0 and byte 1 controls bit 8. A new cause wins over a same-cycle clear.",
            "",
            "## Current-Monitor Snapshot Contract",
            "",
            bus["current_monitor_pair"]["description"],
            " The values are raw digital monitor codes, not calibrated physical current.",
            "",
            "## Fault-Code Taxonomy",
            "",
            "| Value | Canonical name | RTL name | C name | Legacy aliases | Description |",
            "|---:|---|---|---|---|---|",
        ]
    )
    for fault in spec["fault_codes"]:
        aliases = [
            *fault["legacy_aliases"]["rtl"],
            *fault["legacy_aliases"]["c"],
        ]
        lines.append(
            f"| `0x{fault['value']:02X}` | `{fault['name']}` | `{fault['public_names']['rtl']}` | `{fault['public_names']['c']}` | {', '.join(f'`{item}`' for item in aliases) if aliases else 'none'} | {fault['description']} |"
        )
    lines.extend(["", "## Register Details", ""])
    for register in spec["registers"]:
        offset = parse_uint(register["offset"], register["name"])
        lines.extend(
            [
                f"### `0x{offset:02X} {register['name']}`",
                "",
                register["description"],
                "",
                "| Bits | Field | Access | Reset/static default | Read behavior | Write behavior |",
                "|---:|---|---|---:|---|---|",
            ]
        )
        for field in sorted(register["fields"], key=lambda item: item["lsb"]):
            reset = parse_uint(field["reset"], f"{register['name']}.{field['name']}")
            parameter = f" (`{field['parameter_ref']}`)" if field.get("parameter_ref") else ""
            lines.append(
                f"| `{bits_label(field)}` | `{field['name']}` | {field['access']} | `0x{reset:X}`{parameter} | {field['read_behavior']} | {field['write_behavior']} |"
            )
        lines.append("")
    lines.extend(
        [
            "## A2 Current-ABI Remediation Closure",
            "",
            "These corrections align specification and generated outputs with frozen RTL behavior. No external behavior changes are made.",
            "",
            "| ID | Register/field or behavior | Current RTL truth | Old statement/gap | Classification | A2 correction | Behavior changed? | Verification |",
            "|---|---|---|---|---|---|---|---|",
        ]
    )
    for row in parity["remediations"]:
        values = [
            row["id"],
            row["register_field_or_behavior"],
            row["current_rtl_truth"],
            row["old_documentation_or_software_statement"],
            row["classification"],
            row["a2_correction"],
            "NO",
            row["verification"],
        ]
        escaped = [str(value).replace("|", "\\|").replace("\n", " ") for value in values]
        lines.append("| " + " | ".join(escaped) + " |")
    lines.extend(
        [
            "",
            "## Compatibility Status",
            "",
            f"- Legacy register parity: PASS ({parity['register_count']} registers).",
            f"- Legacy field parity: PASS ({parity['field_count']} fields).",
            f"- Fault-code parity: PASS ({parity['fault_code_count']} values).",
            "- Legacy RTL fault names remain available through `rtl/fault_defs.vh`.",
            "- The existing C header path and public names remain available.",
            "- Hand edits to this file are rejected by `python tools/generate_register_map.py --check`.",
            "",
        ]
    )
    return "\n".join(lines)


def render_tb(spec: dict[str, Any], spec_hash: str) -> str:
    abi_values = abi_1_1_render_values(spec)
    lines = [*generated_banner("//", spec_hash), "", "`ifndef TB_PROTECTION_REGISTER_MAP_SVH", "`define TB_PROTECTION_REGISTER_MAP_SVH", ""]
    for register in spec["registers"]:
        public = register["public_names"]["systemverilog"]
        offset = parse_uint(register["offset"], register["name"])
        reset = parse_uint(register["reset"], register["name"])
        lines.extend(
            [
                f"`define {public} 8'h{offset:02X}",
                f"`define {public}_RESET 32'h{reset:08X}",
            ]
        )
        for field in register["fields"]:
            if field["access"] == "RSVD":
                continue
            field_public = field["public_names"]["systemverilog"]
            lines.extend(
                [
                    f"`define {field_public}_LSB {field['lsb']}",
                    f"`define {field_public}_MSB {field['msb']}",
                    f"`define {field_public}_MASK 32'h{field_mask(field):08X}",
                    f"`define {field_public}_RESET 32'h{parse_uint(field['reset'], field_public):08X}",
                    f"`define {field_public} 32'h{field_mask(field):08X}",
                ]
            )
        lines.append("")
    obs_status = next(register for register in spec["registers"] if register["name"] == "OBS_STATUS_W1C")
    w1c_mask = sum(field_mask(field) for field in obs_status["fields"] if field["access"] == "W1C")
    status_mask = sum(field_mask(field) for field in obs_status["fields"] if field["access"] != "RSVD")
    lines.extend(
        [
            f"`define OBS_STATUS_W1C_MASK 32'h{w1c_mask:08X}",
            f"`define OBS_STATUS_MASK 32'h{status_mask:08X}",
            f"`define REGISTER_MAP_VERSION_VALUE 32'h{abi_values['version']:08X}",
            f"`define CAPABILITIES_0_ABI_1_1_VALUE 32'h{abi_values['capabilities_0']:08X}",
            "`define CAPABILITIES_1_VALUE(_sequence_width) "
            f"(32'h{abi_values['capabilities_1_base']:08X} | "
            f"((_sequence_width) << {abi_values['capabilities_1_sequence_lsb']}))",
            f"`define CAPABILITIES_1_WIDTH16 32'h{abi_values['capabilities_1_widths'][16]:08X}",
            f"`define CAPABILITIES_1_WIDTH24 32'h{abi_values['capabilities_1_widths'][24]:08X}",
            f"`define CAPABILITIES_1_WIDTH32 32'h{abi_values['capabilities_1_widths'][32]:08X}",
            f"`define FAULT_BITMAP_WIDTH {abi_values['fault_bitmap_width']}",
            f"`define FAULT_BITMAP_VALID_MASK 32'h{abi_values['fault_bitmap_valid_mask']:08X}",
            f"`define FAULT_BITMAP_RESERVED_MASK 32'h{abi_values['fault_bitmap_reserved_mask']:08X}",
            "",
        ]
    )
    for cause in spec["fault_causes"]:
        public = cause["public_names"]["systemverilog"]
        lines.append(f"`define {public} 32'h{1 << cause['bit']:08X}")
    lines.append("")
    for fault in spec["fault_codes"]:
        public = fault["public_names"]["systemverilog"]
        lines.append(f"`define {public} 8'h{fault['value']:02X}")
        for alias in fault["legacy_aliases"]["systemverilog"]:
            lines.append(f"`define {alias} `{public}")
    lines.extend(["", "`endif", ""])
    return "\n".join(lines)


def render_conformance(
    spec: dict[str, Any], spec_hash: str, parity: dict[str, Any]
) -> str:
    contract = spec["abi_1_1_contract"]
    route_templates = {
        route["family"]: route["templates"]
        for route in contract["conformance_routes"]
    }
    registers = []
    for register in spec["registers"]:
        fields = []
        for field in sorted(register["fields"], key=lambda item: item["lsb"]):
            fields.append(
                {
                    "name": field["name"],
                    "lsb": field["lsb"],
                    "msb": field["msb"],
                    "width": field["msb"] - field["lsb"] + 1,
                    "mask": hex_value(field_mask(field)),
                    "access": field["access"],
                    "reset": hex_value(parse_uint(field["reset"], field["name"])),
                    "parameter_ref": field.get("parameter_ref"),
                    "enum_ref": field.get("enum_ref"),
                    "read_behavior": field["read_behavior"],
                    "write_behavior": field["write_behavior"],
                    "behavior_id": field.get("behavior_id"),
                    "static_value": field.get("static_value"),
                    "dynamic_source": field.get("dynamic_source"),
                    "rtl_binding_id": field.get("rtl_binding_id"),
                    "capability_gate_ref": field.get("capability_gate_ref"),
                    "conformance_family": field.get("conformance_family"),
                    "conformance_templates": route_templates.get(
                        field.get("conformance_family"), []
                    ),
                }
            )
        registers.append(
            {
                "name": register["name"],
                "offset": hex_value(parse_uint(register["offset"], register["name"]), 2),
                "width": register["width"],
                "access": register["access"],
                "value_kind": register["value_kind"],
                "reset": hex_value(parse_uint(register["reset"], register["name"])),
                "write_strobe": register["write_strobe"],
                "fields": fields,
            }
        )
    value = {
        "format": "protection-register-map-conformance-v2",
        "generator_version": GENERATOR_VERSION,
        "register_map_schema_version": SCHEMA_VERSION,
        "canonical_spec_sha256": spec_hash,
        "abi": spec["abi"],
        "legacy_address_range": {"first": "0x00", "last": "0x60"},
        "abi_1_1": {
            "explicit_enable_parameter": contract["explicit_enable_parameter"],
            "selected_register_offsets": [
                hex_value(parse_uint(register["offset"], register["name"]), 2)
                for register in spec["registers"]
                if parse_uint(register["offset"], register["name"]) > 0x60
            ],
            "register_count": parity["added_register_count"],
            "field_count": parity["added_field_count"],
            "bit_coverage": sum(
                register["width"]
                for register in spec["registers"]
                if parse_uint(register["offset"], register["name"]) > 0x60
            ),
            "rtl_sources": contract["rtl_sources"],
            "capabilities": contract["capabilities"],
            "api_gates": contract["api_gates"],
            "metadata_constraints": contract["metadata_constraints"],
            "invariants": contract["invariants"],
            "conformance_templates": contract["conformance_templates"],
            "conformance_routes": contract["conformance_routes"],
            "fault_projection": contract["fault_projection"],
            "fault_forward_compatibility": contract[
                "fault_forward_compatibility"
            ],
            "policy_identity": contract["policy_identity"],
        },
        "bus_behavior": spec["bus_behavior"],
        "fault_causes": [
            {
                "name": cause["name"],
                "bit": cause["bit"],
                "mask": hex_value(1 << cause["bit"]),
                "description": cause["description"],
                "public_names": cause["public_names"],
            }
            for cause in spec["fault_causes"]
        ],
        "fault_codes": [
            {
                "name": fault["name"],
                "value": hex_value(fault["value"], 2),
                "public_names": fault["public_names"],
                "legacy_aliases": fault["legacy_aliases"],
            }
            for fault in spec["fault_codes"]
        ],
        "registers": registers,
        "scenarios": [
            {
                "id": "UNKNOWN_READ_ZERO_OKAY",
                "address": "0x64",
                "expected_data": "0x00000000",
                "expected_response": "OKAY",
            },
            {
                "id": "UNKNOWN_WRITE_NO_EFFECT_OKAY",
                "addresses": ["0x64..0x7C", "0x8C..0x9C"],
                "expected_effect": "NONE",
                "expected_response": "OKAY",
            },
            {
                "id": "LOW_EIGHT_BIT_ADDRESS_ALIAS",
                "decode_bits": "7:0",
                "expected_outer_alias": True,
            },
            {
                "id": "LEGACY_WRITES_IGNORE_WSTRB_AFTER_ACCEPTANCE",
                "registers": spec["bus_behavior"]["accepted_write"]["legacy_unstrobed_registers"],
                "accepted_write_requires_any_wstrb": True,
            },
            {
                "id": "OBS_STATUS_W1C_BYTE_QUALIFIED_EVENT_WINS",
                "w1c_mask": "0x000001FF",
                "event_priority": "NEW_CAUSE_WINS",
            },
            {
                "id": "CURRENT_MONITOR_SOFTWARE_READS_NONATOMIC",
                "hardware_delivery_atomic": True,
                "software_pair_atomic": False,
            },
        ],
        "legacy_parity": {
            key: parity[key]
            for key in (
                "register_count",
                "field_count",
                "fault_code_count",
                "offset_changes",
                "width_changes",
                "field_encoding_changes",
                "access_semantic_changes",
                "reset_semantic_changes",
                "fault_code_changes",
                "fault_alias_changes",
            )
        },
        "map_counts": {
            "total_register_count": parity["total_register_count"],
            "legacy_register_count": parity["register_count"],
            "abi_1_1_added_register_count": parity["added_register_count"],
            "total_field_count": parity["total_field_count"],
            "legacy_field_count": parity["field_count"],
            "abi_1_1_added_field_count": parity["added_field_count"],
        },
    }
    return pretty_json(value)


def render_compatibility(
    spec: dict[str, Any],
    spec_hash: str,
    schema_hash: str,
    baseline_hash: str,
    parity: dict[str, Any],
    primary_outputs: dict[str, str],
) -> str:
    output_hashes = {
        path: sha256_bytes(text.encode("utf-8"))
        for path, text in sorted(primary_outputs.items())
    }
    output_hashes["spec/generated/protection_register_map_compatibility.json"] = (
        "RECORDED_BY_EVIDENCE_MANIFEST"
    )
    value = {
        "format": "protection-register-map-compatibility-v2",
        "generator_version": GENERATOR_VERSION,
        "register_map_schema_version": SCHEMA_VERSION,
        "canonical_spec_sha256": spec_hash,
        "schema_sha256": schema_hash,
        "frozen_a1_baseline": {
            "path": "spec/stage2h_register_map_convergence.json",
            "sha256": baseline_hash,
        },
        "generated_artifact_topology": {
            "authority": "ONE_MASTER_LIST",
            "paths": list(MASTER_ARTIFACTS),
            "path_count": len(MASTER_ARTIFACTS),
            "unowned_paths": [],
            "duplicate_paths": [],
        },
        "generated_output_sha256": dict(sorted(output_hashes.items())),
        "legacy_abi": {
            "address_range": "0x00..0x60",
            "external_behavior_changed": False,
            "static_parity": "PASS",
            "software_constant_parity": "PASS",
            "fault_code_parity": "PASS",
            "register_count": parity["register_count"],
            "field_count": parity["field_count"],
            "fault_code_count": parity["fault_code_count"],
            "offset_changes": parity["offset_changes"],
            "width_changes": parity["width_changes"],
            "field_encoding_changes": parity["field_encoding_changes"],
            "access_semantic_changes": parity["access_semantic_changes"],
            "reset_semantic_changes": parity["reset_semantic_changes"],
            "fault_code_changes": parity["fault_code_changes"],
            "fault_alias_changes": parity["fault_alias_changes"],
        },
        "abi_1_1": {
            "version": spec["abi"]["version"],
            "additive": True,
            "explicit_enable_parameter": spec["abi_1_1_contract"][
                "explicit_enable_parameter"
            ],
            "register_count": parity["added_register_count"],
            "field_count": parity["added_field_count"],
            "bit_coverage": sum(
                register["width"]
                for register in spec["registers"]
                if parse_uint(register["offset"], register["name"]) > 0x60
            ),
            "total_register_count": parity["total_register_count"],
            "total_field_count": parity["total_field_count"],
            "register_map_version_value": hex_value(
                abi_1_1_render_values(spec)["version"]
            ),
            "capabilities_0_value": hex_value(
                abi_1_1_render_values(spec)["capabilities_0"]
            ),
            "capabilities_1_values": {
                str(width): hex_value(value)
                for width, value in abi_1_1_render_values(spec)[
                    "capabilities_1_widths"
                ].items()
            },
            "legacy_instance_discovery_value": "0x00000000",
            "production_path_explicit": True,
        },
        "current_abi_remediations": parity["remediations"],
        "fault_codes": [
            {
                "name": fault["name"],
                "value": hex_value(fault["value"], 2),
                "public_names": fault["public_names"],
                "legacy_aliases": fault["legacy_aliases"],
            }
            for fault in spec["fault_codes"]
        ],
        "register_inventory": [
            {
                "name": register["name"],
                "offset": hex_value(parse_uint(register["offset"], register["name"]), 2),
                "width": register["width"],
                "access": register["access"],
                "reset": hex_value(parse_uint(register["reset"], register["name"])),
                "public_names": register["public_names"],
            }
            for register in spec["registers"]
        ],
    }
    return pretty_json(value)


def render_outputs(
    spec: dict[str, Any],
    schema: dict[str, Any],
    baseline: dict[str, Any],
    *,
    baseline_bytes: bytes,
) -> tuple[dict[str, str], dict[str, Any]]:
    spec_hash = sha256_bytes(canonical_json(spec))
    schema_hash = sha256_bytes(canonical_json(schema))
    baseline_hash = sha256_bytes(baseline_bytes)
    parity = validate_legacy_parity(spec, baseline)
    outputs: dict[str, str] = {
        "rtl/generated/protection_register_map.vh": render_rtl(spec, spec_hash),
        "sw/generated/protection_register_map.py": render_python(spec, spec_hash),
        "sw/ps_register_demo/protection_ip_regs.h": render_c(spec, spec_hash),
        "fpga/vivado/generated/protection_register_map_ipxact.tcl": render_ipxact(spec, spec_hash),
        "docs/implementation/register_map.md": render_docs(spec, spec_hash, parity),
        "tb/generated/protection_register_map.svh": render_tb(spec, spec_hash),
        "spec/generated/protection_register_map_conformance.json": render_conformance(
            spec, spec_hash, parity
        ),
    }
    compatibility = render_compatibility(
        spec,
        spec_hash,
        schema_hash,
        baseline_hash,
        parity,
        outputs,
    )
    outputs["spec/generated/protection_register_map_compatibility.json"] = compatibility
    ordered = {path: outputs[path] for path in MASTER_ARTIFACTS}
    return ordered, parity


def validate_and_render(
    spec: dict[str, Any],
    schema: dict[str, Any],
    baseline: dict[str, Any],
    *,
    baseline_bytes: bytes,
) -> tuple[dict[str, str], dict[str, Any]]:
    validate_schema_contract(schema)
    validate_spec_schema_shape(schema, spec)
    validate_semantics(spec)
    return render_outputs(
        spec, schema, baseline, baseline_bytes=baseline_bytes
    )


def compare_outputs(output_root: Path, outputs: dict[str, str]) -> list[str]:
    drift: list[str] = []
    for relative, rendered in outputs.items():
        path = output_root / relative
        try:
            current = path.read_bytes()
        except OSError:
            drift.append(f"MISSING:{relative}")
            continue
        expected = rendered.encode("utf-8")
        if current != expected:
            drift.append(f"CONTENT:{relative}")
    return drift


def write_outputs(output_root: Path, outputs: dict[str, str]) -> int:
    output_root.mkdir(parents=True, exist_ok=True)
    changed = 0
    with tempfile.TemporaryDirectory(
        prefix="register-map-generation-", dir=output_root
    ) as temporary_name:
        temporary = Path(temporary_name)
        for relative, rendered in outputs.items():
            staged = temporary / relative
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_text(rendered, encoding="utf-8", newline="\n")
        for relative in MASTER_ARTIFACTS:
            target = output_root / relative
            staged = temporary / relative
            expected = staged.read_bytes()
            try:
                identical = target.read_bytes() == expected
            except OSError:
                identical = False
            if identical:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            replacement = target.with_name(target.name + ".register-map-new")
            shutil.copyfile(staged, replacement)
            os.replace(replacement, target)
            changed += 1
    return changed


def generate(
    *,
    spec_path: Path,
    schema_path: Path,
    baseline_path: Path,
    output_root: Path,
    check: bool,
    validate_only: bool,
) -> dict[str, Any]:
    spec, _ = load_json(spec_path)
    schema, _ = load_json(schema_path)
    baseline, baseline_bytes = load_json(baseline_path)
    outputs, parity = validate_and_render(
        spec, schema, baseline, baseline_bytes=baseline_bytes
    )
    if validate_only:
        return {"mode": "VALIDATE", "changed": 0, "drift": [], "parity": parity}
    if check:
        drift = compare_outputs(output_root, outputs)
        if drift:
            raise GenerationError("generated artifact drift: " + ", ".join(drift))
        return {"mode": "CHECK", "changed": 0, "drift": [], "parity": parity}
    changed = write_outputs(output_root, outputs)
    return {"mode": "WRITE", "changed": changed, "drift": [], "parity": parity}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--output-root", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true", help="compare all eight outputs without writing")
    parser.add_argument("--validate-only", action="store_true", help="validate schema, semantics, and frozen parity without writing")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.check and args.validate_only:
        print("REGISTER_MAP_GENERATION=FAIL: --check and --validate-only are mutually exclusive", file=sys.stderr)
        return 2
    try:
        result = generate(
            spec_path=args.spec.resolve(),
            schema_path=args.schema.resolve(),
            baseline_path=args.baseline.resolve(),
            output_root=args.output_root.resolve(),
            check=args.check,
            validate_only=args.validate_only,
        )
    except (GenerationError, OSError, KeyError, TypeError, ValueError) as exc:
        print(f"REGISTER_MAP_GENERATION=FAIL: {exc}", file=sys.stderr)
        return 1
    parity = result["parity"]
    print("REGISTER_MAP_GENERATION=PASS")
    print(f"MODE={result['mode']}")
    print(f"GENERATED_ARTIFACTS={len(MASTER_ARTIFACTS)}")
    print(f"GENERATED_ARTIFACTS_CHANGED={result['changed']}")
    print("LEGACY_ABI_STATIC_PARITY=PASS")
    print("LEGACY_ABI_SOFTWARE_CONSTANT_PARITY=PASS")
    print("LEGACY_ABI_FAULT_CODE_PARITY=PASS")
    print(
        "A2_KNOWN_CURRENT_ABI_REMEDIATIONS_CLOSED="
        f"PASS_{len(parity['remediations'])}_OF_{len(parity['remediations'])}"
    )
    if result["mode"] == "CHECK":
        print("GENERATED_ARTIFACT_DRIFT_CHECK=PASS_8_OF_8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
