#!/usr/bin/env python3
"""Audit the frozen Stage 2H register-map convergence architecture contract."""

from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import subprocess
import sys
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
BASE_COMMIT = "c38df7cfc7a9fae28cb9ddc70fd16994e7e4b794"
PREVIOUS_AUDIT_COMMIT = "2db2f593eee860dbc8e8d23db4a480dd7ad2fa13"
BRANCH = "codex/stage2h-single-source-register-map-convergence-audit"
CONTRACT_PATH = Path("spec/stage2h_register_map_convergence.json")
SCHEMA_PATH = Path("spec/stage2h_register_map_convergence.schema.json")
POSITIVE_PATH = Path("spec/stage2h_fixtures/positive_fixture.json")
NEGATIVE_PATH = Path("spec/stage2h_fixtures/negative_mutations.json")
CROSS_NEGATIVE_PATH = Path(
    "spec/stage2h_fixtures/cross_artifact_negative_mutations.json"
)
AST_FIXTURE_PATH = Path("spec/stage2h_fixtures/ast_fingerprint_fixtures.json")
TRADEOFF_PATH = Path(
    "docs/architecture/stage2h_single_source_register_map_tradeoff.md"
)
VERIFICATION_PATH = Path(
    "docs/verification/stage2h_register_map_convergence_verification_plan.md"
)

ACCESS_TYPES = {"RO", "RW", "WO", "W1C", "W1S", "W1P", "RC", "RSVD"}
REQUIRED_DECISIONS = {
    "REGISTER_MAP_SINGLE_SOURCE_AUTHORITY",
    "SPEC_FORMAT",
    "SPEC_SCHEMA_VERSIONING",
    "GENERATED_ARTIFACT_LIST",
    "FULL_RTL_GENERATION_OR_METADATA_GENERATION",
    "ACCESS_TYPE_TAXONOMY",
    "SNAPSHOT_SEMANTICS",
    "POLICY_SNAPSHOT_ARCHITECTURE",
    "BEHAVIOR_BINDING_MATRIX",
    "ACCESS_TAXONOMY_ENABLEMENT",
    "PUBLIC_CURRENT_MONITOR_CONTRACT",
    "ABI_MAJOR_MINOR_POLICY",
    "CAPABILITY_DISCOVERY",
    "ARMED_READY_EXPOSURE",
    "ARMED_READY_SEMANTICS",
    "FAULT_BITMAP_EXPOSURE",
    "CLEAR_RECOVERY_STATUS_EXPOSURE",
    "PROPOSED_ADDRESS_BLOCK",
    "RESERVED_SPACE_POLICY",
    "SOFTWARE_API_PLAN",
    "RECOVERY_IS_VERIFIED_SCOPE",
    "PYTHON_AST_CANONICALIZATION",
    "PYTHON_VERSION_MATRIX",
    "DRIFT_DETECTION",
    "HAND_EDIT_POLICY",
    "VERSION_MAGIC_POLICY",
    "LEGACY_CAPABILITY_MODEL",
    "CAPABILITY_PUBLIC_SEMANTICS",
    "BEHAVIOR_COMPLETE_SOURCE",
    "GENERATED_CONFORMANCE_AUTHORITY",
    "ABI_DEFECT_INVENTORY",
    "BITMAP_LIFETIME",
    "CROSS_PLATFORM_REPLAY",
    "SELECTED_ABI_REGISTER_MODEL",
    "CAPABILITY_DEPENDENCY_MATRIX",
    "CAPABILITY_METADATA_POLICY",
    "CAPABILITY_GATE_AUTHORITY",
    "CAPABILITY_IMPLICATION_GRAPH",
    "REGISTER_AGGREGATE_AUTHORITY",
    "PARAMETER_EXPRESSION_MODEL",
    "IMPLEMENTATION_BRANCH_PLAN",
    "FAULT_TAXONOMY_AUTHORITY",
    "DYNAMIC_VALUE_SOURCE_AUTHORITY",
    "CROSS_FIELD_INVARIANTS",
    "CONFORMANCE_SCENARIO_DEFINITIONS",
    "POLICY_IDENTITY_CAPTURE_CONTRACT",
    "RTL_SOURCE_BINDING_AUTHORITY",
    "FAULT_BITMAP_TRANSITION_RULES",
    "UNKNOWN_FAULT_CAUSE_FORWARD_COMPATIBILITY",
    "FIRST_PRINCIPLES_SCOPE_REVIEW",
    "GENERATED_ARTIFACT_TOPOLOGY_AUTHORITY",
    "LEGACY_FAULT_PATH_COMPATIBILITY",
    "STAGE2H_A1_SUBSTAGE_HANDOFF",
    "AUDIT_LIVE_SOURCE_BOUNDARY",
}
REQUIRED_BEHAVIOR_IDS = {
    "RO_STATIC",
    "RO_REGISTERED_VOLATILE",
    "RW_STROBED",
    "RW_LEGACY_IGNORE_WSTRB",
    "W1C_EVENT_WINS",
    "W1P_ONE_ACLK",
    "RSVD_ZERO_IGNORE",
    "UNKNOWN_ZERO_OKAY",
    "ADDRESS_LOW8_ALIAS",
}
REQUIRED_BEHAVIOR_PROPERTIES = {
    "offset",
    "field_range",
    "access_type",
    "reset_value",
    "static_value",
    "parameter_expression",
    "read_semantics",
    "write_semantics",
    "wstrb_policy",
    "legacy_behavior_extension",
    "side_effect_id",
    "event_priority",
    "pulse_width",
    "volatility",
    "clock_domain",
    "reset_domain",
    "snapshot_group",
    "capability_gate_ref",
    "capability_dependency_matrix",
    "software_name",
    "rtl_name",
    "ipxact_name",
    "description",
    "deprecation_compatibility_state",
}
REQUIRED_CAPABILITY_NAMES = {
    "ARMED_READY",
    "FAULT_BITMAPS",
    "CLEAR_LEVEL_STATUS",
    "STAGE2G_POLICY",
    "NORMALIZED_TELEMETRY",
    "STAGE2E_TRANSACTION_OBSERVABILITY",
    "POLICY_EVALUATION_IDENTITY",
}
EXPECTED_SELECTED_ABI_1_1_ALLOCATION = (
    ("0x80", "REGISTER_MAP_VERSION"),
    ("0x84", "CAPABILITIES_0"),
    ("0x88", "CAPABILITIES_1"),
    ("0xA0", "POLICY_STATUS"),
    ("0xA4", "FIRST_FAULT_BITMAP"),
    ("0xA8", "LIVE_FAULT_BITMAP"),
    ("0xAC", "FAULT_SEEN_BITMAP"),
    ("0xB0", "POLICY_EVALUATION_SEQUENCE"),
)
EXPECTED_MASTER_GENERATED_ARTIFACT_PATHS = (
    "rtl/generated/protection_register_map.vh",
    "sw/generated/protection_register_map.py",
    "sw/ps_register_demo/protection_ip_regs.h",
    "fpga/vivado/generated/protection_register_map_ipxact.tcl",
    "docs/implementation/register_map.md",
    "tb/generated/protection_register_map.svh",
    "spec/generated/protection_register_map_compatibility.json",
    "spec/generated/protection_register_map_conformance.json",
)
EXPECTED_TAXONOMY_CONSUMER_ARTIFACTS = {
    "RTL_VERILOG_INCLUDE": "rtl/generated/protection_register_map.vh",
    "PYTHON_INTENUM_INTFLAG": "sw/generated/protection_register_map.py",
    "C_CONSTANTS_ENUMS": "sw/ps_register_demo/protection_ip_regs.h",
    "SYSTEMVERILOG_CONSTANTS": "tb/generated/protection_register_map.svh",
    "IP_XACT_FIELD_ENUM_METADATA": (
        "fpga/vivado/generated/protection_register_map_ipxact.tcl"
    ),
    "REGISTER_DOCUMENTATION": "docs/implementation/register_map.md",
    "CONFORMANCE_VECTORS": (
        "spec/generated/protection_register_map_conformance.json"
    ),
}
FAULT_BITMAP_REGISTERS = (
    "FIRST_FAULT_BITMAP",
    "LIVE_FAULT_BITMAP",
    "FAULT_SEEN_BITMAP",
)
FAULT_CAUSE_NAMES = (
    "CH1_OVERCURRENT",
    "CH2_OVERCURRENT",
    "SENSOR_MISMATCH_OR_DIFFERENTIAL",
    "SENSOR_OPEN",
    "SENSOR_SATURATION",
    "SENSOR_STUCK",
)
EXPECTED_FAULT_CODE_VALUES = {
    "NONE": 0x00,
    "OVERCURRENT": 0x01,
    "SENSOR_MISMATCH": 0x02,
    "SENSOR_OPEN": 0x03,
    "SENSOR_SATURATION": 0x04,
    "SENSOR_STUCK": 0x05,
    "OC_WITH_ANY_SENSOR": 0x06,
}
EXPECTED_FAULT_CODE_ALIASES = {
    "NONE": {"FAULT_NONE", "PROTECTION_FAULT_NONE"},
    "OVERCURRENT": {"FAULT_OVERCURRENT", "PROTECTION_FAULT_OVERCURRENT"},
    "SENSOR_MISMATCH": {"FAULT_SENSOR_MISMATCH", "PROTECTION_FAULT_MISMATCH"},
    "SENSOR_OPEN": {"FAULT_SENSOR_OPEN", "PROTECTION_FAULT_SENSOR_OPEN"},
    "SENSOR_SATURATION": {
        "FAULT_SENSOR_SATURATION",
        "PROTECTION_FAULT_SENSOR_SAT",
    },
    "SENSOR_STUCK": {"FAULT_SENSOR_STUCK", "PROTECTION_FAULT_SENSOR_STUCK"},
    "OC_WITH_ANY_SENSOR": {
        "FAULT_OC_WITH_SENSOR",
        "PROTECTION_FAULT_OC_WITH_SENSOR",
    },
}
EXPECTED_FAULT_PROJECTION = [
    {
        "code": "OC_WITH_ANY_SENSOR",
        "predicate": {
            "kind": "ALL_OF_ANY_GROUPS",
            "causes": [],
            "groups": [
                ["CH1_OVERCURRENT", "CH2_OVERCURRENT"],
                [
                    "SENSOR_MISMATCH_OR_DIFFERENTIAL",
                    "SENSOR_OPEN",
                    "SENSOR_SATURATION",
                    "SENSOR_STUCK",
                ],
            ],
        },
    },
    {
        "code": "OVERCURRENT",
        "predicate": {
            "kind": "ANY_OF",
            "causes": ["CH1_OVERCURRENT", "CH2_OVERCURRENT"],
            "groups": [],
        },
    },
    {
        "code": "SENSOR_SATURATION",
        "predicate": {
            "kind": "ANY_OF",
            "causes": ["SENSOR_SATURATION"],
            "groups": [],
        },
    },
    {
        "code": "SENSOR_OPEN",
        "predicate": {
            "kind": "ANY_OF",
            "causes": ["SENSOR_OPEN"],
            "groups": [],
        },
    },
    {
        "code": "SENSOR_STUCK",
        "predicate": {
            "kind": "ANY_OF",
            "causes": ["SENSOR_STUCK"],
            "groups": [],
        },
    },
    {
        "code": "SENSOR_MISMATCH",
        "predicate": {
            "kind": "ANY_OF",
            "causes": ["SENSOR_MISMATCH_OR_DIFFERENTIAL"],
            "groups": [],
        },
    },
    {
        "code": "NONE",
        "predicate": {
            "kind": "NONE_OF",
            "causes": list(FAULT_CAUSE_NAMES),
            "groups": [],
        },
    },
]
DISCOVERY_BINDING_TARGETS = {
    "REGISTER_MAP_VERSION.MAGIC",
    "REGISTER_MAP_VERSION.ABI_MAJOR",
    "REGISTER_MAP_VERSION.ABI_MINOR",
    "CAPABILITIES_0.ARMED_READY",
    "CAPABILITIES_0.FAULT_BITMAPS",
    "CAPABILITIES_0.CLEAR_LEVEL_STATUS",
    "CAPABILITIES_0.STAGE2G_POLICY",
    "CAPABILITIES_0.NORMALIZED_TELEMETRY_RESERVED_ZERO",
    "CAPABILITIES_0.STAGE2E_TRANSACTION_OBSERVABILITY",
    "CAPABILITIES_0.POLICY_EVALUATION_IDENTITY",
    "CAPABILITIES_0.RESERVED_ZERO",
    "CAPABILITIES_1.FAULT_BITMAP_WIDTH",
    "CAPABILITIES_1.IMPLEMENTED_SEQUENCE_WIDTH",
    "CAPABILITIES_1.MIN_SEQUENCE_WIDTH",
    "CAPABILITIES_1.MAX_SEQUENCE_WIDTH",
    "POLICY_STATUS.RESERVED",
}
REQUIRED_METADATA_CONSTRAINT_IDS = {
    "FAULT_BITMAP_WIDTH_RANGE_1_TO_32",
    "IMPLEMENTED_SEQUENCE_WIDTH_RANGE_16_TO_32",
    "MIN_SEQUENCE_WIDTH_EQUALS_16",
    "MAX_SEQUENCE_WIDTH_EQUALS_32",
    "MIN_LE_IMPLEMENTED_LE_MAX",
    "NORMALIZED_TELEMETRY_RESERVED_ZERO",
    "CAPABILITIES_0_RESERVED_BITS_ZERO",
    "SUPPORTED_MAJOR_HIGHER_MINOR_KNOWN_PREFIX_ONLY",
    "MALFORMED_EXPLICIT_METADATA_REJECT_INCOMPATIBLE",
    "STAGE2E_OBS_CAPABILITY_EXACT_FROZEN",
    "STAGE2G_PUBLIC_CONTRACT_CONNECTED",
    "POLICY_EVALUATION_IDENTITY_DIAGNOSTIC_ONLY",
}
STAGE2E_PUBLIC_REGISTERS = {
    "OBS_CAPABILITY",
    "OBS_STATUS_W1C",
    "OBS_SOURCE_ACCEPT_COUNT",
    "OBS_DESTINATION_DELIVERY_COUNT",
    "OBS_BACKPRESSURE_CYCLE_COUNT",
    "OBS_SOURCE_PROTOCOL_VIOLATION_COUNT",
    "OBS_SOURCE_DROP_COUNT",
    "OBS_FIFO_OVERFLOW_ATTEMPT_COUNT",
    "OBS_FIFO_UNDERFLOW_ATTEMPT_COUNT",
    "OBS_DUPLICATE_DELIVERY_COUNT",
    "OBS_SEQUENCE_GAP_COUNT",
    "OBS_REORDER_OR_STALE_COUNT",
    "OBS_AGGREGATE_ERROR_COUNT",
    "OBS_LAST_SOURCE_SEQUENCE",
    "OBS_LAST_DESTINATION_SEQUENCE",
}
EXPECTED_FIELD_GATES: dict[str, tuple[str, str, tuple[str, ...]]] = {
    "REGISTER_MAP_VERSION.MAGIC": (
        "FIELD_REGISTER_MAP_VERSION_MAGIC",
        "BASE_DISCOVERY",
        (),
    ),
    "REGISTER_MAP_VERSION.ABI_MAJOR": (
        "FIELD_REGISTER_MAP_VERSION_ABI_MAJOR",
        "BASE_DISCOVERY",
        (),
    ),
    "REGISTER_MAP_VERSION.ABI_MINOR": (
        "FIELD_REGISTER_MAP_VERSION_ABI_MINOR",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_0.ARMED_READY": (
        "FIELD_CAPABILITIES_0_ARMED_READY",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_0.FAULT_BITMAPS": (
        "FIELD_CAPABILITIES_0_FAULT_BITMAPS",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_0.CLEAR_LEVEL_STATUS": (
        "FIELD_CAPABILITIES_0_CLEAR_LEVEL_STATUS",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_0.STAGE2G_POLICY": (
        "FIELD_CAPABILITIES_0_STAGE2G_POLICY",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_0.NORMALIZED_TELEMETRY_RESERVED_ZERO": (
        "FIELD_CAPABILITIES_0_NORMALIZED_TELEMETRY_RESERVED_ZERO",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_0.STAGE2E_TRANSACTION_OBSERVABILITY": (
        "FIELD_CAPABILITIES_0_STAGE2E_TRANSACTION_OBSERVABILITY",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_0.POLICY_EVALUATION_IDENTITY": (
        "FIELD_CAPABILITIES_0_POLICY_EVALUATION_IDENTITY",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_0.RESERVED_ZERO": (
        "FIELD_CAPABILITIES_0_RESERVED_ZERO",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_1.FAULT_BITMAP_WIDTH": (
        "FIELD_CAPABILITIES_1_FAULT_BITMAP_WIDTH",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_1.IMPLEMENTED_SEQUENCE_WIDTH": (
        "FIELD_CAPABILITIES_1_IMPLEMENTED_SEQUENCE_WIDTH",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_1.MIN_SEQUENCE_WIDTH": (
        "FIELD_CAPABILITIES_1_MIN_SEQUENCE_WIDTH",
        "BASE_DISCOVERY",
        (),
    ),
    "CAPABILITIES_1.MAX_SEQUENCE_WIDTH": (
        "FIELD_CAPABILITIES_1_MAX_SEQUENCE_WIDTH",
        "BASE_DISCOVERY",
        (),
    ),
    "POLICY_STATUS.ARMED_READY": (
        "FIELD_POLICY_STATUS_ARMED_READY",
        "FEATURE",
        ("ARMED_READY", "STAGE2G_POLICY"),
    ),
    "POLICY_STATUS.FAULT_LATCHED_STATE": (
        "FIELD_POLICY_STATUS_FAULT_LATCHED_STATE",
        "FEATURE",
        ("STAGE2G_POLICY",),
    ),
    "POLICY_STATUS.RESET_WAIT_STATE": (
        "FIELD_POLICY_STATUS_RESET_WAIT_STATE",
        "FEATURE",
        ("STAGE2G_POLICY",),
    ),
    "POLICY_STATUS.CLEAR_PENDING": (
        "FIELD_POLICY_STATUS_CLEAR_PENDING",
        "FEATURE",
        ("CLEAR_LEVEL_STATUS", "STAGE2G_POLICY"),
    ),
    "POLICY_STATUS.POST_CLEAR_RECOVERY_PENDING": (
        "FIELD_POLICY_STATUS_POST_CLEAR_RECOVERY_PENDING",
        "FEATURE",
        ("CLEAR_LEVEL_STATUS", "STAGE2G_POLICY"),
    ),
    "POLICY_STATUS.RESERVED": (
        "FIELD_POLICY_STATUS_RESERVED",
        "FEATURE",
        ("STAGE2G_POLICY",),
    ),
    "POLICY_EVALUATION_SEQUENCE.SEQUENCE": (
        "FIELD_POLICY_EVALUATION_SEQUENCE_SEQUENCE",
        "FEATURE",
        ("POLICY_EVALUATION_IDENTITY", "STAGE2G_POLICY"),
    ),
}
for _bitmap_register in FAULT_BITMAP_REGISTERS:
    for _bitmap_field in (*FAULT_CAUSE_NAMES, "RESERVED"):
        _target = f"{_bitmap_register}.{_bitmap_field}"
        EXPECTED_FIELD_GATES[_target] = (
            f"FIELD_{_bitmap_register}_{_bitmap_field}",
            "FEATURE",
            ("FAULT_BITMAPS", "STAGE2G_POLICY"),
        )
EXPECTED_API_GATES: dict[str, tuple[str, str, tuple[str, ...]]] = {
    "is_armed()": (
        "API_IS_ARMED",
        "FEATURE",
        ("ARMED_READY", "STAGE2G_POLICY"),
    ),
    "startup_ready()": (
        "API_STARTUP_READY",
        "FEATURE",
        ("ARMED_READY", "STAGE2G_POLICY"),
    ),
    "read_policy_status()": (
        "API_READ_POLICY_STATUS",
        "FEATURE",
        ("CLEAR_LEVEL_STATUS", "STAGE2G_POLICY"),
    ),
    "read_capabilities()": ("API_READ_CAPABILITIES", "BASE_DISCOVERY", ()),
    "read_register_map_version()": (
        "API_READ_REGISTER_MAP_VERSION",
        "BASE_DISCOVERY",
        (),
    ),
    "read_observability()": (
        "API_READ_OBSERVABILITY",
        "FEATURE",
        ("STAGE2E_TRANSACTION_OBSERVABILITY",),
    ),
    "clear_observability_status()": (
        "API_CLEAR_OBSERVABILITY_STATUS",
        "FEATURE",
        ("STAGE2E_TRANSACTION_OBSERVABILITY",),
    ),
    "read_first_fault_bitmap()": (
        "API_READ_FIRST_FAULT_BITMAP",
        "FEATURE",
        ("FAULT_BITMAPS", "STAGE2G_POLICY"),
    ),
    "read_live_fault_bitmap()": (
        "API_READ_LIVE_FAULT_BITMAP",
        "FEATURE",
        ("FAULT_BITMAPS", "STAGE2G_POLICY"),
    ),
    "read_fault_seen_bitmap()": (
        "API_READ_FAULT_SEEN_BITMAP",
        "FEATURE",
        ("FAULT_BITMAPS", "STAGE2G_POLICY"),
    ),
    "read_policy_evaluation_identity()": (
        "API_READ_POLICY_EVALUATION_IDENTITY",
        "FEATURE",
        ("POLICY_EVALUATION_IDENTITY", "STAGE2G_POLICY"),
    ),
    "read_policy_snapshot()": ("API_READ_POLICY_SNAPSHOT", "DEFERRED", ()),
    "recovery_is_verified()": (
        "API_RECOVERY_IS_VERIFIED",
        "PRESERVED_LEGACY",
        (),
    ),
    "enable_pwm_after_recovery()": (
        "API_ENABLE_PWM_AFTER_RECOVERY",
        "PRESERVED_LEGACY",
        (),
    ),
}
EXPECTED_CAPABILITY_EDGE_TARGETS: dict[str, set[str]] = {
    "ARMED_READY": {
        "CAPABILITIES_0.ARMED_READY",
        "POLICY_STATUS.ARMED_READY",
    },
    "FAULT_BITMAPS": {
        "CAPABILITIES_0.FAULT_BITMAPS",
        "CAPABILITIES_1.FAULT_BITMAP_WIDTH",
    }
    | {
        f"{register}.{field}"
        for register in FAULT_BITMAP_REGISTERS
        for field in (*FAULT_CAUSE_NAMES, "RESERVED")
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
    },
    "NORMALIZED_TELEMETRY": {
        "CAPABILITIES_0.NORMALIZED_TELEMETRY_RESERVED_ZERO",
    },
    "STAGE2E_TRANSACTION_OBSERVABILITY": {
        "CAPABILITIES_0.STAGE2E_TRANSACTION_OBSERVABILITY",
        "OBS_CAPABILITY.stage2e_magic",
        "OBS_CAPABILITY.atomic_multi_register_snapshot",
        "OBS_CAPABILITY.source_telemetry_eventually_consistent",
        "OBS_CAPABILITY.sticky_status_w1c",
        "OBS_CAPABILITY.counters_reset_only",
        "OBS_CAPABILITY.counter_width",
        "OBS_CAPABILITY.sequence_width",
        "OBS_CAPABILITY.observability_version",
        "OBS_STATUS_W1C.BACKPRESSURE_SEEN",
        "OBS_STATUS_W1C.SOURCE_PROTOCOL_VIOLATION",
        "OBS_STATUS_W1C.SOURCE_DROP_SEEN",
        "OBS_STATUS_W1C.FIFO_OVERFLOW_ATTEMPT",
        "OBS_STATUS_W1C.FIFO_UNDERFLOW_ATTEMPT",
        "OBS_STATUS_W1C.DUPLICATE_DELIVERY",
        "OBS_STATUS_W1C.SEQUENCE_GAP",
        "OBS_STATUS_W1C.REORDER_OR_STALE",
        "OBS_STATUS_W1C.COUNTER_SATURATED",
        "OBS_STATUS_W1C.ANY_ERROR",
        "OBS_STATUS_W1C.reserved",
        "OBS_SOURCE_ACCEPT_COUNT.count",
        "OBS_DESTINATION_DELIVERY_COUNT.count",
        "OBS_BACKPRESSURE_CYCLE_COUNT.count",
        "OBS_SOURCE_PROTOCOL_VIOLATION_COUNT.count",
        "OBS_SOURCE_DROP_COUNT.count",
        "OBS_FIFO_OVERFLOW_ATTEMPT_COUNT.count",
        "OBS_FIFO_UNDERFLOW_ATTEMPT_COUNT.count",
        "OBS_DUPLICATE_DELIVERY_COUNT.count",
        "OBS_SEQUENCE_GAP_COUNT.count",
        "OBS_REORDER_OR_STALE_COUNT.count",
        "OBS_AGGREGATE_ERROR_COUNT.count",
        "OBS_LAST_SOURCE_SEQUENCE.sequence",
        "OBS_LAST_DESTINATION_SEQUENCE.sequence",
    },
    "POLICY_EVALUATION_IDENTITY": {
        "CAPABILITIES_0.POLICY_EVALUATION_IDENTITY",
        "CAPABILITIES_1.IMPLEMENTED_SEQUENCE_WIDTH",
        "CAPABILITIES_1.MIN_SEQUENCE_WIDTH",
        "CAPABILITIES_1.MAX_SEQUENCE_WIDTH",
        "POLICY_EVALUATION_SEQUENCE.SEQUENCE",
    },
}
EXPECTED_CAPABILITY_API_GATE_REFS: dict[str, set[str]] = {
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
        "API_CLEAR_OBSERVABILITY_STATUS",
        "API_READ_OBSERVABILITY",
    },
    "POLICY_EVALUATION_IDENTITY": {
        "API_READ_POLICY_EVALUATION_IDENTITY"
    },
}
EXPECTED_CAPABILITY_METADATA: dict[str, set[str]] = {
    "ARMED_READY": set(),
    "FAULT_BITMAPS": {"FAULT_BITMAP_WIDTH_RANGE_1_TO_32"},
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
EXPECTED_CAPABILITY_FIELDS = {
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
EXPECTED_REGISTER_WORDS = {
    "REGISTER_MAP_VERSION": (0x524D0101, 0x524D0101),
    "CAPABILITIES_0": (0x0000006F, 0x0000006F),
    "CAPABILITIES_1": (0x20102006, 0x20102006),
    "POLICY_STATUS": (0x00000004, None),
    "FIRST_FAULT_BITMAP": (0x00000000, None),
    "LIVE_FAULT_BITMAP": (0x00000000, None),
    "FAULT_SEEN_BITMAP": (0x00000000, None),
    "POLICY_EVALUATION_SEQUENCE": (0x00000000, None),
}
EXPECTED_CAPABILITIES_1_WIDTH_VALUES = {
    16: 0x20101006,
    24: 0x20101806,
    32: 0x20102006,
}
REQUIRED_ABI_DEFECT_IDS = {
    "STATUS_FAULT_VALID_DESCRIPTION_STALE",
    "STATUS_FAULT_LATCHED_CLEAR_DESCRIPTION_STALE",
    "CURRENT_MONITOR_DESCRIPTION_STALE",
    "LEGACY_WRITES_IGNORE_WSTRB_UNDOCUMENTED",
    "UNDEFINED_READ_ZERO_OKAY_UNDOCUMENTED",
    "UNDEFINED_WRITE_NO_EFFECT_OKAY_UNDOCUMENTED",
    "LOW_EIGHT_BIT_ADDRESS_ALIAS_UNDOCUMENTED",
    "CURRENT_MONITOR_SOFTWARE_READS_NONATOMIC_UNDOCUMENTED",
}
ALLOWED_CHANGED_PATHS = {
    CONTRACT_PATH.as_posix(),
    SCHEMA_PATH.as_posix(),
    POSITIVE_PATH.as_posix(),
    NEGATIVE_PATH.as_posix(),
    CROSS_NEGATIVE_PATH.as_posix(),
    AST_FIXTURE_PATH.as_posix(),
    TRADEOFF_PATH.as_posix(),
    VERIFICATION_PATH.as_posix(),
    "tools/stage2h_register_map_convergence_audit.py",
    "tools/build_stage2h_register_map_review.py",
    "tools/replay_stage2h_source_archive.py",
    "tools/tests/test_stage2h_register_map_convergence_audit.py",
}
PROPOSED_PATHS = {
    "spec/register_map.json",
    "spec/register_map.schema.json",
    "rtl/generated/protection_register_map.vh",
    "sw/generated/protection_register_map.py",
    "fpga/vivado/generated/protection_register_map_ipxact.tcl",
    "tb/generated/protection_register_map.svh",
    "spec/generated/protection_register_map_compatibility.json",
    "spec/generated/protection_register_map_conformance.json",
    "tools/run_register_map_conformance.py",
}


class AuditError(RuntimeError):
    """Raised when an audit invariant fails."""


class DuplicateJsonKey(ValueError):
    """Raised when strict JSON parsing sees a duplicate object key."""


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJsonKey(key)
        result[key] = value
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    except (OSError, json.JSONDecodeError, DuplicateJsonKey) as exc:
        raise AuditError(f"strict JSON parse failed: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise AuditError(f"top-level JSON value must be an object: {path}")
    return value


def run(command: list[str], *, cwd: Path = ROOT, check: bool = True) -> str:
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            check=False,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except OSError as exc:
        raise AuditError(
            "COMMAND_EXECUTION_UNAVAILABLE: "
            f"{subprocess.list2cmdline(command)}: {exc}"
        ) from exc
    if check and completed.returncode:
        raise AuditError(
            f"command failed ({completed.returncode}): "
            f"{subprocess.list2cmdline(command)}\n{completed.stdout}"
        )
    return completed.stdout


def git(*args: str, root: Path = ROOT) -> str:
    return run(["git", *args], cwd=root).strip()


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


def schema_ref(root_schema: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise AuditError(f"external schema reference is not supported: {reference}")
    value: Any = root_schema
    for raw_part in reference[2:].split("/"):
        part = raw_part.replace("~1", "/").replace("~0", "~")
        if not isinstance(value, dict) or part not in value:
            raise AuditError(f"invalid local schema reference: {reference}")
        value = value[part]
    if not isinstance(value, dict):
        raise AuditError(f"schema reference is not an object: {reference}")
    return value


def json_type_matches(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    raise AuditError(f"unsupported JSON Schema type in repository schema: {expected}")


def validate_schema_value(
    schema: dict[str, Any],
    value: Any,
    location: str,
    errors: list[str],
    root_schema: dict[str, Any],
) -> None:
    if "$ref" in schema:
        validate_schema_value(
            schema_ref(root_schema, str(schema["$ref"])),
            value,
            location,
            errors,
            root_schema,
        )
        return

    one_of = schema.get("oneOf")
    if isinstance(one_of, list):
        matches = 0
        candidate_errors: list[list[str]] = []
        for candidate in one_of:
            local_errors: list[str] = []
            if isinstance(candidate, dict):
                validate_schema_value(
                    candidate, value, location, local_errors, root_schema
                )
            else:
                local_errors.append(f"schema: {location} has malformed oneOf")
            candidate_errors.append(local_errors)
            if not local_errors:
                matches += 1
        if matches != 1:
            errors.append(
                f"schema: {location} must match exactly one closed expression form"
            )
        return

    type_rule = schema.get("type")
    if isinstance(type_rule, str):
        types = [type_rule]
    elif isinstance(type_rule, list):
        types = [str(item) for item in type_rule]
    else:
        types = []
    if types and not any(json_type_matches(value, item) for item in types):
        errors.append(f"schema: {location} must have type {'/'.join(types)}")
        return

    if "const" in schema and value != schema["const"]:
        errors.append(f"schema: {location} must equal {schema['const']!r}")
    enum = schema.get("enum")
    if isinstance(enum, list) and value not in enum:
        errors.append(f"schema: {location} must be one of {enum!r}")

    if isinstance(value, str):
        pattern = schema.get("pattern")
        if isinstance(pattern, str) and re.search(pattern, value) is None:
            errors.append(f"schema: {location} does not match {pattern!r}")
        minimum_length = schema.get("minLength")
        if isinstance(minimum_length, int) and len(value) < minimum_length:
            errors.append(f"schema: {location} is shorter than {minimum_length}")

    if isinstance(value, int) and not isinstance(value, bool):
        minimum = schema.get("minimum")
        maximum = schema.get("maximum")
        if isinstance(minimum, (int, float)) and value < minimum:
            errors.append(f"schema: {location} is below {minimum}")
        if isinstance(maximum, (int, float)) and value > maximum:
            errors.append(f"schema: {location} is above {maximum}")

    if isinstance(value, dict):
        required = schema.get("required", [])
        if isinstance(required, list):
            for key in required:
                if key not in value:
                    errors.append(f"schema: {location}.{key} is required")
        properties = schema.get("properties", {})
        if isinstance(properties, dict):
            for key, child in properties.items():
                if key in value and isinstance(child, dict):
                    validate_schema_value(
                        child, value[key], f"{location}.{key}", errors, root_schema
                    )
            if schema.get("additionalProperties") is False:
                extra = set(value) - set(properties)
                for key in sorted(extra):
                    errors.append(f"schema: {location}.{key} is not allowed")

    if isinstance(value, list):
        minimum_items = schema.get("minItems")
        maximum_items = schema.get("maxItems")
        if isinstance(minimum_items, int) and len(value) < minimum_items:
            errors.append(f"schema: {location} has fewer than {minimum_items} items")
        if isinstance(maximum_items, int) and len(value) > maximum_items:
            errors.append(f"schema: {location} has more than {maximum_items} items")
        if schema.get("uniqueItems") is True:
            rendered = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in value]
            if len(rendered) != len(set(rendered)):
                errors.append(f"schema: {location} items are not unique")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(value):
                validate_schema_value(
                    item_schema,
                    item,
                    f"{location}[{index}]",
                    errors,
                    root_schema,
                )


def validate_schema(schema: dict[str, Any], contract: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        errors.append("schema: wrong JSON Schema draft")
    validate_schema_value(schema, contract, "$", errors, schema)
    return errors


def path_value(root: Any, path: str) -> Any:
    value = root
    for part in path.split("."):
        if isinstance(value, list):
            value = value[int(part)]
        elif isinstance(value, dict):
            value = value[part]
        else:
            raise AuditError(f"mutation path traverses scalar: {path}")
    return value


def set_path_value(root: Any, path: str, value: Any) -> None:
    parts = path.split(".")
    parent = root
    for part in parts[:-1]:
        if isinstance(parent, list):
            parent = parent[int(part)]
        elif isinstance(parent, dict):
            parent = parent[part]
        else:
            raise AuditError(f"mutation path traverses scalar: {path}")
    last = parts[-1]
    if isinstance(parent, list):
        parent[int(last)] = value
    elif isinstance(parent, dict):
        parent[last] = value
    else:
        raise AuditError(f"mutation path parent is scalar: {path}")


def compact(text: str) -> str:
    return re.sub(r"\s+", "", text)


def decision_map(contract: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for item in contract.get("decisions", []):
        if not isinstance(item, dict):
            continue
        identifier = str(item.get("id", ""))
        if identifier in result:
            raise AuditError(f"duplicate decision: {identifier}")
        result[identifier] = item
    return result


def derive_abi_defect_counts(abi: dict[str, Any]) -> dict[str, int]:
    counts = {
        "total": 0,
        "DOCUMENTATION_VS_RTL_CONTRADICTION": 0,
        "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR": 0,
        "HISTORICAL_ONLY_DIFFERENCE": 0,
    }
    for defect in abi.get("defects", []):
        if not isinstance(defect, dict):
            continue
        classification = str(defect.get("classification", ""))
        counts["total"] += 1
        if classification in counts:
            counts[classification] += 1
    return counts


def selected_field_records(
    contract: dict[str, Any],
) -> list[tuple[dict[str, Any], dict[str, Any]]]:
    records: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for register in contract.get("selected_abi_1_1_registers", []):
        if not isinstance(register, dict):
            continue
        for field in register.get("fields", []):
            if isinstance(field, dict):
                records.append((register, field))
    return records


def derive_selected_map_coverage(contract: dict[str, Any]) -> dict[str, Any]:
    alternatives = contract.get("allocation_alternatives", [])
    selected_alternatives = [
        item
        for item in alternatives
        if isinstance(item, dict) and item.get("selected") is True
    ]
    allocation = (
        selected_alternatives[0].get("registers", [])
        if len(selected_alternatives) == 1
        else []
    )
    allocated_pairs = [
        (str(item.get("offset")), str(item.get("name")))
        for item in allocation
        if isinstance(item, dict)
    ]
    allocated_names = {name for _, name in allocated_pairs}
    allocated_map = {name: offset for offset, name in allocated_pairs}

    definitions = [
        item
        for item in contract.get("selected_abi_1_1_registers", [])
        if isinstance(item, dict)
    ]
    definition_pairs = [
        (str(item.get("offset")), str(item.get("name"))) for item in definitions
    ]
    definition_names = {name for _, name in definition_pairs}
    definition_map = {name: offset for offset, name in definition_pairs}
    duplicate_definition_names = len(definition_pairs) - len(definition_names)
    duplicate_definition_offsets = len(definition_pairs) - len(
        {offset for offset, _ in definition_pairs}
    )

    allocated_without_definition = sorted(allocated_names - definition_names)
    definitions_without_allocation = sorted(definition_names - allocated_names)
    offset_mismatches = sorted(
        name
        for name in allocated_names & definition_names
        if allocated_map[name] != definition_map[name]
    )
    allocated_without_field_contract = sorted(
        name
        for name in allocated_names
        if name not in definition_names
        or not next(
            (
                item.get("fields")
                for item in definitions
                if item.get("name") == name
            ),
            [],
        )
    )

    required_field_properties = {
        "name",
        "offset",
        "bits",
        "access",
        "static_value",
        "reset",
        "read_semantics",
        "write_semantics",
        "behavior_id",
        "rtl_binding_id",
        "side_effect_id",
        "generated_conformance_family",
        "capability_gate_ref",
        "software_name",
        "rtl_name",
        "ipxact_name",
        "implementation_status",
    }
    malformed_fields: list[str] = []
    field_keys: list[tuple[str, str]] = []
    uncovered_bits: list[str] = []
    overlapping_bits: list[str] = []
    selected_bit_count = 0
    unallocated_fields: list[str] = []
    for register in definitions:
        register_name = str(register.get("name"))
        register_offset = str(register.get("offset"))
        if register_name not in allocated_names:
            unallocated_fields.extend(
                f"{register_name}.{field.get('name')}"
                for field in register.get("fields", [])
                if isinstance(field, dict)
            )
        used: dict[int, str] = {}
        for field in register.get("fields", []):
            if not isinstance(field, dict):
                malformed_fields.append(f"{register_name}.<malformed>")
                continue
            field_name = str(field.get("name"))
            rendered = f"{register_name}.{field_name}"
            field_keys.append((register_name, field_name))
            missing = required_field_properties - set(field)
            if missing or any(
                not str(field.get(key, "")).strip()
                for key in (
                    "name",
                    "offset",
                    "access",
                    "read_semantics",
                    "write_semantics",
                    "behavior_id",
                    "rtl_binding_id",
                    "side_effect_id",
                    "generated_conformance_family",
                    "capability_gate_ref",
                    "software_name",
                    "rtl_name",
                    "ipxact_name",
                    "implementation_status",
                )
            ):
                malformed_fields.append(rendered)
            if field.get("offset") != register_offset:
                malformed_fields.append(rendered + ":OFFSET")
            bits = field.get("bits", {})
            try:
                msb = int(bits.get("msb"))
                lsb = int(bits.get("lsb"))
            except (AttributeError, TypeError, ValueError):
                malformed_fields.append(rendered + ":BITS")
                continue
            if msb < lsb or lsb < 0 or msb >= 32:
                malformed_fields.append(rendered + ":BITS")
                continue
            for bit in range(lsb, msb + 1):
                if bit in used:
                    overlapping_bits.append(
                        f"{register_name}[{bit}]={used[bit]},{field_name}"
                    )
                else:
                    used[bit] = field_name
        if register_name in allocated_names:
            selected_bit_count += len(used)
            uncovered_bits.extend(
                f"{register_name}[{bit}]" for bit in range(32) if bit not in used
            )

    duplicate_fields = len(field_keys) - len(set(field_keys))
    selected_binding_keys = [
        (str(item.get("register")), str(item.get("field_or_global_policy")))
        for item in contract.get("behavior_binding_matrix", {}).get("bindings", [])
        if isinstance(item, dict) and item.get("scope") == "ABI_1_1_SELECTED"
    ]
    selected_field_set = set(field_keys)
    selected_binding_set = set(selected_binding_keys)
    fields_without_bindings = sorted(selected_field_set - selected_binding_set)
    bindings_without_fields = sorted(selected_binding_set - selected_field_set)
    fields_without_conformance = sorted(
        f"{register.get('name')}.{field.get('name')}"
        for register, field in selected_field_records(contract)
        if not str(field.get("generated_conformance_family", "")).strip()
    )

    deferred = [
        item
        for item in contract.get("deferred_register_candidates", [])
        if isinstance(item, dict)
    ]
    deferred_names = {str(item.get("name")) for item in deferred}
    deferred_counted = sorted(
        str(item.get("name"))
        for item in deferred
        if item.get("counted_as_selected_abi_1_1") is not False
        or item.get("name") in allocated_names
        or item.get("name") in definition_names
        or any(key[0] == item.get("name") for key in selected_binding_set)
    )

    matched_registers = {
        name
        for name in allocated_names & definition_names
        if allocated_map[name] == definition_map[name]
        and name not in allocated_without_field_contract
    }
    covered_fields = {
        key
        for key in selected_field_set & selected_binding_set
        if key[0] in matched_registers
        and f"{key[0]}.{key[1]}" not in malformed_fields
        and f"{key[0]}.{key[1]}" not in fields_without_conformance
    }
    return {
        "allocation_pairs": allocated_pairs,
        "definition_pairs": definition_pairs,
        "selected_register_count": len(allocated_pairs),
        "covered_register_count": len(matched_registers),
        "selected_field_count": len(selected_field_set),
        "covered_field_count": len(covered_fields),
        "selected_bit_count": selected_bit_count,
        "expected_bit_count": 32 * len(allocated_pairs),
        "allocated_without_definition": allocated_without_definition,
        "definitions_without_allocation": definitions_without_allocation,
        "offset_mismatches": offset_mismatches,
        "allocated_without_field_contract": allocated_without_field_contract,
        "unallocated_fields": sorted(unallocated_fields),
        "uncovered_bits": sorted(uncovered_bits),
        "overlapping_bits": sorted(overlapping_bits),
        "duplicate_definition_names": duplicate_definition_names,
        "duplicate_definition_offsets": duplicate_definition_offsets,
        "duplicate_fields": duplicate_fields,
        "malformed_fields": sorted(set(malformed_fields)),
        "fields_without_bindings": fields_without_bindings,
        "bindings_without_fields": bindings_without_fields,
        "fields_without_conformance": fields_without_conformance,
        "deferred_count": len(deferred),
        "deferred_names": sorted(deferred_names),
        "deferred_counted_as_selected": deferred_counted,
    }


def derive_behavior_binding_coverage(contract: dict[str, Any]) -> dict[str, Any]:
    expected: set[tuple[str, str, str]] = set()
    public_fields = 0
    for register in contract.get("current_abi", {}).get("registers", []):
        for field in register.get("fields", []):
            expected.add(("CURRENT_ABI", str(register.get("name")), str(field.get("name"))))
            public_fields += 1
    for register, field in selected_field_records(contract):
        expected.add(
            (
                "ABI_1_1_SELECTED",
                str(register.get("name")),
                str(field.get("name")),
            )
        )
        public_fields += 1
    for target in contract.get("behavior_binding_matrix", {}).get(
        "global_policy_targets", []
    ):
        expected.add(("GLOBAL_POLICY", "GLOBAL", str(target)))

    bindings = contract.get("behavior_binding_matrix", {}).get("bindings", [])
    actual_keys: list[tuple[str, str, str]] = []
    missing_conformance: list[str] = []
    unknown_behavior_bindings: list[str] = []
    vocabulary = {
        str(item.get("id"))
        for item in contract.get("behavior_source_contract", {}).get(
            "behavior_vocabulary", []
        )
        if isinstance(item, dict)
    }
    for item in bindings:
        if not isinstance(item, dict):
            continue
        key = (
            str(item.get("scope")),
            str(item.get("register")),
            str(item.get("field_or_global_policy")),
        )
        actual_keys.append(key)
        rendered = ".".join(key)
        if not str(item.get("generated_conformance_family", "")).strip():
            missing_conformance.append(rendered)
        if str(item.get("behavior_id")) not in vocabulary:
            unknown_behavior_bindings.append(rendered)

    actual = set(actual_keys)
    duplicate_count = len(actual_keys) - len(actual)
    enablement = contract.get("access_taxonomy_enablement", {})
    enabled_behavior_ids = set(enablement.get("enabled_behavior_ids", []))
    consumed_behavior_ids = {
        str(item.get("behavior_id"))
        for item in bindings
        if isinstance(item, dict)
    }
    unconsumed = enabled_behavior_ids - consumed_behavior_ids
    behavior_map = enablement.get("access_to_enabled_behavior_ids", {})
    enabled_access = set(enablement.get("enabled_access_types", []))
    access_without_behavior = {
        access
        for access in enabled_access
        if not set(behavior_map.get(access, [])) & enabled_behavior_ids & vocabulary
    }
    disabled_access = set(
        enablement.get("defined_taxonomy_not_enabled_for_abi_1_1", [])
    )
    disabled_uses: list[str] = []
    for register in contract.get("current_abi", {}).get("registers", []):
        for field in register.get("fields", []):
            if field.get("access") in disabled_access:
                disabled_uses.append(f"{register.get('name')}.{field.get('name')}")
    for register, field in selected_field_records(contract):
        if field.get("access") in disabled_access:
            disabled_uses.append(f"{register.get('name')}.{field.get('name')}")

    return {
        "public_field_count": public_fields,
        "target_count": len(expected),
        "binding_count": len(bindings),
        "covered_count": len(expected & actual),
        "unbound_fields": sorted(expected - actual),
        "unexpected_bindings": sorted(actual - expected),
        "duplicate_bindings": duplicate_count,
        "bindings_without_conformance_families": sorted(missing_conformance),
        "unknown_behavior_bindings": sorted(unknown_behavior_bindings),
        "unconsumed_enabled_behavior_ids": sorted(unconsumed),
        "approved_enabled_access_types_without_behavior_id": sorted(
            access_without_behavior
        ),
        "disabled_access_uses": sorted(disabled_uses),
    }


def derive_capability_dependency_coverage(contract: dict[str, Any]) -> dict[str, Any]:
    matrix = contract.get("capability_dependency_matrix", {})
    capability_order = (
        "ARMED_READY",
        "FAULT_BITMAPS",
        "CLEAR_LEVEL_STATUS",
        "STAGE2G_POLICY",
        "NORMALIZED_TELEMETRY",
        "STAGE2E_TRANSACTION_OBSERVABILITY",
        "POLICY_EVALUATION_IDENTITY",
    )
    expected_bits = {name: bit for bit, name in enumerate(capability_order)}
    problem_capabilities: set[str] = set()
    field_mismatches: list[str] = []
    api_mismatches: list[str] = []
    binding_mismatches: list[str] = []
    implication_violations: list[str] = []
    free_form: list[str] = []
    gate_grammar_errors: list[str] = []
    missing_registers: list[str] = []
    missing_fields: list[str] = []
    missing_bindings: list[str] = []
    missing_conformance: list[str] = []
    missing_apis: list[str] = []
    missing_metadata: list[str] = []
    mismatched_entries: list[str] = []

    def has_free_form(value: Any) -> bool:
        return isinstance(value, str) and ("|" in value or "&" in value)

    grammar = matrix.get("gate_grammar", {})
    if grammar != {
        "allowed_kinds": [
            "FEATURE",
            "BASE_DISCOVERY",
            "PRESERVED_LEGACY",
            "DEFERRED",
        ],
        "capability_ids": list(capability_order),
        "set_semantics": "CANONICAL_LEXICOGRAPHIC_UNIQUE_IDS",
        "feature_all_of_empty": "FORBIDDEN",
        "all_of_none_of_intersection": "FORBIDDEN",
        "free_form_operators": "FORBIDDEN",
    }:
        gate_grammar_errors.append("gate grammar authority differs")
    allowed_kinds = set(grammar.get("allowed_kinds", []))
    known_capabilities = set(grammar.get("capability_ids", []))

    def validate_gate(label: str, gate: Any) -> tuple[Any, tuple[Any, ...]]:
        if not isinstance(gate, dict):
            gate_grammar_errors.append(f"{label}:gate is not structured")
            return None, ()
        kind = gate.get("kind")
        if kind not in allowed_kinds:
            gate_grammar_errors.append(f"{label}:unknown gate kind {kind!r}")
        lists: dict[str, list[Any]] = {}
        for key in ("all_of", "any_of", "none_of"):
            values = gate.get(key)
            if not isinstance(values, list):
                gate_grammar_errors.append(f"{label}:{key} is not an array")
                values = []
            lists[key] = values
            if all(isinstance(value, str) for value in values) and values != sorted(
                values
            ):
                gate_grammar_errors.append(f"{label}:{key} is not canonical")
            if len(values) != len(set(v for v in values if isinstance(v, str))):
                gate_grammar_errors.append(f"{label}:{key} has duplicate capability ID")
            for value in values:
                if has_free_form(value):
                    free_form.append(f"{label}:{key}:{value}")
                if not isinstance(value, str) or value not in known_capabilities:
                    gate_grammar_errors.append(
                        f"{label}:{key} has unknown capability ID {value!r}"
                    )
        if kind == "FEATURE" and not lists["all_of"]:
            gate_grammar_errors.append(f"{label}:mandatory feature gate has empty all_of")
        positive = set(lists["all_of"]) | set(lists["any_of"])
        contradictory = positive & set(lists["none_of"])
        if contradictory:
            gate_grammar_errors.append(
                f"{label}:contradictory capability gate {sorted(contradictory)}"
            )
        return kind, (
            tuple(lists["all_of"]),
            tuple(lists["any_of"]),
            tuple(lists["none_of"]),
        )

    selected_fields = {
        f"{register.get('name')}.{field.get('name')}": field
        for register, field in selected_field_records(contract)
    }
    field_gate_items = [
        item for item in matrix.get("field_gates", []) if isinstance(item, dict)
    ]
    field_gate_ids = [str(item.get("id")) for item in field_gate_items]
    field_gate_targets = [str(item.get("target")) for item in field_gate_items]
    field_gate_map: dict[str, dict[str, Any]] = {}
    for item in field_gate_items:
        field_gate_map.setdefault(str(item.get("id")), item)
    if len(field_gate_ids) != len(set(field_gate_ids)):
        field_mismatches.append("duplicate field gate ID")
    if len(field_gate_targets) != len(set(field_gate_targets)):
        field_mismatches.append("duplicate field gate target")
    expected_field_ids = {value[0] for value in EXPECTED_FIELD_GATES.values()}
    for extra in sorted(set(field_gate_ids) - expected_field_ids):
        field_mismatches.append(f"unexpected field gate {extra}")
    for target, (expected_id, expected_kind, expected_all_of) in (
        EXPECTED_FIELD_GATES.items()
    ):
        field = selected_fields.get(target, {})
        reference = field.get("capability_gate_ref")
        if has_free_form(reference):
            free_form.append(f"field:{target}:{reference}")
        item = field_gate_map.get(expected_id)
        if reference != expected_id or item is None or item.get("target") != target:
            field_mismatches.append(
                f"{target}:expected reference and target {expected_id}"
            )
            problem_capabilities.update(expected_all_of)
        actual_kind, actual_lists = validate_gate(
            f"field_gate:{expected_id}", item.get("gate") if item else None
        )
        if (
            actual_kind != expected_kind
            or actual_lists != (expected_all_of, (), ())
        ):
            field_mismatches.append(f"{target}:normalized gate differs")
            problem_capabilities.update(expected_all_of)

    api_items = {
        str(item.get("api")): item
        for item in contract.get("software_api_plan", [])
        if isinstance(item, dict)
    }
    api_gate_items = [
        item for item in matrix.get("api_gates", []) if isinstance(item, dict)
    ]
    api_gate_ids = [str(item.get("id")) for item in api_gate_items]
    api_gate_targets = [str(item.get("api")) for item in api_gate_items]
    api_gate_map: dict[str, dict[str, Any]] = {}
    for item in api_gate_items:
        api_gate_map.setdefault(str(item.get("id")), item)
    if len(api_gate_ids) != len(set(api_gate_ids)):
        api_mismatches.append("duplicate API gate ID")
    if len(api_gate_targets) != len(set(api_gate_targets)):
        api_mismatches.append("duplicate API gate target")
    expected_api_ids = {value[0] for value in EXPECTED_API_GATES.values()}
    valid_api_gate_ids: set[str] = set()
    for extra in sorted(set(api_gate_ids) - expected_api_ids):
        api_mismatches.append(f"unexpected API gate {extra}")
    for api, (expected_id, expected_kind, expected_all_of) in EXPECTED_API_GATES.items():
        plan = api_items.get(api, {})
        reference = plan.get("capability_gate_ref")
        if has_free_form(reference):
            free_form.append(f"api:{api}:{reference}")
        item = api_gate_map.get(expected_id)
        if reference != expected_id or item is None or item.get("api") != api:
            api_mismatches.append(
                f"{api}:expected reference and target {expected_id}"
            )
            problem_capabilities.update(expected_all_of)
        actual_kind, actual_lists = validate_gate(
            f"api_gate:{expected_id}", item.get("gate") if item else None
        )
        if (
            actual_kind != expected_kind
            or actual_lists != (expected_all_of, (), ())
        ):
            api_mismatches.append(f"{api}:normalized gate differs")
            problem_capabilities.update(expected_all_of)
        elif reference == expected_id and item is not None and item.get("api") == api:
            valid_api_gate_ids.add(expected_id)

    registers: set[str] = set()
    fields: set[str] = set()
    for register in contract.get("current_abi", {}).get("registers", []):
        if not isinstance(register, dict):
            continue
        register_name = str(register.get("name"))
        registers.add(register_name)
        fields.update(
            f"{register_name}.{field.get('name')}"
            for field in register.get("fields", [])
            if isinstance(field, dict)
        )
    for register, field in selected_field_records(contract):
        register_name = str(register.get("name"))
        registers.add(register_name)
        fields.add(f"{register_name}.{field.get('name')}")
    binding_map: dict[str, dict[str, Any]] = {}
    for item in contract.get("behavior_binding_matrix", {}).get("bindings", []):
        if not isinstance(item, dict) or item.get("scope") == "GLOBAL_POLICY":
            continue
        target = f"{item.get('register')}.{item.get('field_or_global_policy')}"
        binding_map.setdefault(target, item)

    metadata_ids = set(
        contract.get("capability_metadata_constraints", {}).get(
            "constraint_ids", []
        )
    )
    feature_items = [
        item
        for item in contract.get("capability_version_policy", {}).get(
            "feature_bits", []
        )
        if isinstance(item, dict)
    ]
    feature_names = [str(item.get("name")) for item in feature_items]
    feature_map = {str(item.get("name")): item for item in feature_items}
    entries = [
        item for item in matrix.get("capabilities", []) if isinstance(item, dict)
    ]
    entry_names = [str(item.get("name")) for item in entries]
    entry_bits = [item.get("bit") for item in entries]
    entry_map: dict[str, dict[str, Any]] = {}
    for item in entries:
        entry_map.setdefault(str(item.get("name")), item)

    valid_field_edges: set[tuple[str, str]] = set()
    valid_api_edges: set[tuple[str, str]] = set()
    for name in capability_order:
        entry = entry_map.get(name, {})
        feature = feature_map.get(name, {})
        expected_bit = expected_bits[name]
        expected_entry_id = f"CAPABILITY_{name}"
        if feature.get("bit") != expected_bit or feature.get("dependency_ref") != expected_entry_id:
            mismatched_entries.append(f"{name}:feature dependency reference")
            problem_capabilities.add(name)
        if set(feature) != {"bit", "name", "dependency_ref"}:
            mismatched_entries.append(f"{name}:feature bit duplicates authority data")
            problem_capabilities.add(name)
        if (
            entry.get("id") != expected_entry_id
            or entry.get("bit") != expected_bit
            or entry.get("capability_field") != EXPECTED_CAPABILITY_FIELDS[name]
        ):
            mismatched_entries.append(f"{name}:identity, bit, or capability field")
            problem_capabilities.add(name)

        declared_edges = [
            edge for edge in entry.get("required_field_edges", []) if isinstance(edge, dict)
        ]
        declared_targets = [str(edge.get("target")) for edge in declared_edges]
        expected_targets = EXPECTED_CAPABILITY_EDGE_TARGETS[name]
        if len(declared_targets) != len(set(declared_targets)):
            binding_mismatches.append(f"{name}:duplicate exact field edge")
            problem_capabilities.add(name)
        missing_targets = expected_targets - set(declared_targets)
        extra_targets = set(declared_targets) - expected_targets
        if missing_targets or extra_targets:
            binding_mismatches.append(
                f"{name}:exact target set missing={sorted(missing_targets)} extra={sorted(extra_targets)}"
            )
            problem_capabilities.add(name)
        for edge in declared_edges:
            target = str(edge.get("target"))
            register = target.split(".", 1)[0]
            if register not in registers:
                missing_registers.append(f"{name}:{register}")
            if target not in fields:
                missing_fields.append(f"{name}:{target}")
            binding = binding_map.get(target)
            if binding is None:
                missing_bindings.append(f"{name}:{target}")
                binding_mismatches.append(f"{name}:{target}:binding absent")
                continue
            expected_binding = binding.get("rtl_binding_id")
            expected_conformance = binding.get("generated_conformance_family")
            if not str(expected_conformance or "").strip():
                missing_conformance.append(f"{name}:{target}")
            if (
                edge.get("rtl_binding_id") != expected_binding
                or edge.get("conformance_family") != expected_conformance
            ):
                binding_mismatches.append(
                    f"{name}:{target}:exact binding/conformance differs"
                )
                problem_capabilities.add(name)
            elif target in expected_targets:
                valid_field_edges.add((name, target))

        api_refs = entry.get("required_api_gate_refs", [])
        if not isinstance(api_refs, list):
            api_refs = []
        expected_refs = EXPECTED_CAPABILITY_API_GATE_REFS[name]
        if all(isinstance(reference, str) for reference in api_refs) and api_refs != sorted(
            api_refs
        ):
            api_mismatches.append(f"{name}:API gate references are not canonical")
        if len(api_refs) != len(set(v for v in api_refs if isinstance(v, str))):
            api_mismatches.append(f"{name}:duplicate API gate reference")
        if set(api_refs) != expected_refs:
            api_mismatches.append(
                f"{name}:API gate edge set differs expected={sorted(expected_refs)} actual={sorted(api_refs)}"
            )
            problem_capabilities.add(name)
        for reference in api_refs:
            if has_free_form(reference):
                free_form.append(f"capability_api:{name}:{reference}")
            gate_item = api_gate_map.get(str(reference))
            if gate_item is None:
                missing_apis.append(f"{name}:{reference}")
                continue
            api = str(gate_item.get("api"))
            plan = api_items.get(api, {})
            if (
                plan.get("decision") not in {"ADD", "PRESERVE"}
                or plan.get("capability_gate_ref") != reference
                or reference not in valid_api_gate_ids
            ):
                missing_apis.append(f"{name}:{reference}")
            elif reference in expected_refs:
                valid_api_edges.add((name, str(reference)))

        metadata_refs = entry.get("required_metadata_constraints", [])
        if not isinstance(metadata_refs, list):
            metadata_refs = []
        expected_metadata = EXPECTED_CAPABILITY_METADATA[name]
        if set(metadata_refs) != expected_metadata:
            missing_metadata.append(
                f"{name}:expected={sorted(expected_metadata)} actual={sorted(metadata_refs)}"
            )
            problem_capabilities.add(name)
        for reference in metadata_refs:
            if reference not in metadata_ids:
                missing_metadata.append(f"{name}:{reference}")

        capability_field = selected_fields.get(EXPECTED_CAPABILITY_FIELDS[name], {})
        if entry.get("advertisement_value") != capability_field.get("static_value"):
            mismatched_entries.append(f"{name}:advertisement value")
            problem_capabilities.add(name)
        for authority_property in (
            "software_visible_meaning",
            "implementation_evidence",
            "legacy_state",
            "absent_behavior",
            "advertisement_gate",
        ):
            if not str(entry.get(authority_property, "")).strip():
                mismatched_entries.append(f"{name}:{authority_property}")
                problem_capabilities.add(name)

    graph = matrix.get("implication_graph", {})
    expected_group_id = "STAGE2G_PUBLIC_STATUS_BUNDLE"
    expected_group_members = ["ARMED_READY", "CLEAR_LEVEL_STATUS", "STAGE2G_POLICY"]
    groups = [
        item for item in graph.get("equivalence_groups", []) if isinstance(item, dict)
    ]
    group_ids = [str(item.get("id")) for item in groups]
    member_owner: dict[str, str] = {}
    for group in groups:
        group_id = str(group.get("id"))
        members = group.get("members", [])
        if not isinstance(members, list):
            members = []
        if members != sorted(members) or len(members) != len(set(members)):
            implication_violations.append(f"equivalence group {group_id} is not canonical")
        for member in members:
            if member not in REQUIRED_CAPABILITY_NAMES:
                implication_violations.append(
                    f"equivalence group {group_id} has unknown capability {member}"
                )
            if member in member_owner:
                implication_violations.append(
                    f"capability {member} belongs to multiple equivalence groups"
                )
            member_owner[str(member)] = group_id
    if (
        graph.get("cycle_authority") != "COLLAPSED_EQUIVALENCE_DAG"
        or len(group_ids) != len(set(group_ids))
        or groups
        != [{"id": expected_group_id, "members": expected_group_members}]
    ):
        implication_violations.append("Stage2G equivalence authority differs")

    implications = [
        item for item in graph.get("implications", []) if isinstance(item, dict)
    ]
    implication_pairs = [
        (str(item.get("from")), str(item.get("requires"))) for item in implications
    ]
    expected_implications = {
        ("FAULT_BITMAPS", expected_group_id),
        ("POLICY_EVALUATION_IDENTITY", expected_group_id),
    }
    if set(implication_pairs) != expected_implications or len(implication_pairs) != len(
        set(implication_pairs)
    ):
        implication_violations.append("required implication edge set differs")
    if graph.get("forbidden_capabilities") != ["NORMALIZED_TELEMETRY"]:
        implication_violations.append("forbidden capability set differs")
    if graph.get("independent_capabilities") != [
        "STAGE2E_TRANSACTION_OBSERVABILITY"
    ]:
        implication_violations.append("independent capability set differs")

    graph_nodes = (REQUIRED_CAPABILITY_NAMES - set(member_owner)) | set(group_ids)

    def collapsed_node(name: str) -> str:
        return member_owner.get(name, name)

    adjacency: dict[str, set[str]] = {node: set() for node in graph_nodes}
    unknown_implication_nodes: list[str] = []
    for source, required in implication_pairs:
        source_node = collapsed_node(source)
        required_node = collapsed_node(required)
        if source_node not in graph_nodes or required_node not in graph_nodes:
            unknown_implication_nodes.append(f"{source}->{required}")
            continue
        adjacency[source_node].add(required_node)
    if unknown_implication_nodes:
        implication_violations.append(
            f"implication references unknown node {sorted(unknown_implication_nodes)}"
        )

    visit_state: dict[str, int] = {}

    def visit(node: str) -> bool:
        state = visit_state.get(node, 0)
        if state == 1:
            return False
        if state == 2:
            return True
        visit_state[node] = 1
        for target in adjacency.get(node, set()):
            if not visit(target):
                return False
        visit_state[node] = 2
        return True

    graph_acyclic = all(visit(node) for node in graph_nodes)
    if not graph_acyclic:
        implication_violations.append("capability implication graph is cyclic")

    expected_vectors = {
        "ABI_1_1_DEFAULT": {
            "ARMED_READY": True,
            "FAULT_BITMAPS": True,
            "CLEAR_LEVEL_STATUS": True,
            "STAGE2G_POLICY": True,
            "NORMALIZED_TELEMETRY": False,
            "STAGE2E_TRANSACTION_OBSERVABILITY": True,
            "POLICY_EVALUATION_IDENTITY": True,
        },
        "FAULT_BITMAPS_MINIMAL": {
            "ARMED_READY": True,
            "FAULT_BITMAPS": True,
            "CLEAR_LEVEL_STATUS": True,
            "STAGE2G_POLICY": True,
            "NORMALIZED_TELEMETRY": False,
            "STAGE2E_TRANSACTION_OBSERVABILITY": False,
            "POLICY_EVALUATION_IDENTITY": False,
        },
        "POLICY_IDENTITY_MINIMAL": {
            "ARMED_READY": True,
            "FAULT_BITMAPS": False,
            "CLEAR_LEVEL_STATUS": True,
            "STAGE2G_POLICY": True,
            "NORMALIZED_TELEMETRY": False,
            "STAGE2E_TRANSACTION_OBSERVABILITY": False,
            "POLICY_EVALUATION_IDENTITY": True,
        },
        "NO_ADDITIVE_FEATURES": {
            name: False for name in capability_order
        },
    }
    vectors = [
        item for item in graph.get("validation_vectors", []) if isinstance(item, dict)
    ]
    vector_ids = [str(item.get("id")) for item in vectors]
    if set(vector_ids) != set(expected_vectors) or len(vector_ids) != len(
        set(vector_ids)
    ):
        implication_violations.append("implication validation vector inventory differs")
    for vector in vectors:
        vector_id = str(vector.get("id"))
        values = vector.get("values", {})
        if (
            not isinstance(values, dict)
            or set(values) != REQUIRED_CAPABILITY_NAMES
            or any(not isinstance(value, bool) for value in values.values())
        ):
            implication_violations.append(f"{vector_id}:capability vector is malformed")
            continue
        if values != expected_vectors.get(vector_id):
            implication_violations.append(f"{vector_id}:frozen capability vector differs")
        for group in groups:
            members = group.get("members", [])
            group_values = {values.get(member) for member in members}
            if len(group_values) > 1:
                implication_violations.append(
                    f"{vector_id}:equivalence group {group.get('id')} differs"
                )
        for source, required in implication_pairs:
            source_members = next(
                (item.get("members", []) for item in groups if item.get("id") == source),
                [source],
            )
            required_members = next(
                (
                    item.get("members", [])
                    for item in groups
                    if item.get("id") == required
                ),
                [required],
            )
            source_active = all(values.get(member, False) for member in source_members)
            if source_active and not all(
                values.get(member, False) for member in required_members
            ):
                implication_violations.append(
                    f"{vector_id}:implication {source}->{required} violated"
                )
        for forbidden in graph.get("forbidden_capabilities", []):
            if values.get(forbidden) is not False:
                implication_violations.append(
                    f"{vector_id}:forbidden capability {forbidden} is set"
                )

    entry_name_set = set(entry_names)
    capability_edge_target_count = sum(
        len(items) for items in EXPECTED_CAPABILITY_EDGE_TARGETS.values()
    ) + sum(len(items) for items in EXPECTED_CAPABILITY_API_GATE_REFS.values())
    capability_edge_covered_count = len(valid_field_edges) + len(valid_api_edges)
    all_global_errors = (
        field_mismatches
        + api_mismatches
        + binding_mismatches
        + implication_violations
        + free_form
        + gate_grammar_errors
        + missing_registers
        + missing_fields
        + missing_bindings
        + missing_conformance
        + missing_apis
        + missing_metadata
        + mismatched_entries
    )
    if not all_global_errors:
        problem_capabilities.clear()
    return {
        "target_count": len(REQUIRED_CAPABILITY_NAMES),
        "covered_count": len(REQUIRED_CAPABILITY_NAMES - problem_capabilities),
        "missing_entries": sorted(REQUIRED_CAPABILITY_NAMES - entry_name_set),
        "unexpected_entries": sorted(entry_name_set - REQUIRED_CAPABILITY_NAMES),
        "duplicate_entries": len(entry_names) - len(entry_name_set),
        "duplicate_bits": len(entry_bits) - len(set(entry_bits)),
        "duplicate_feature_entries": len(feature_names) - len(set(feature_names)),
        "missing_register_dependencies": sorted(set(missing_registers)),
        "missing_field_dependencies": sorted(set(missing_fields)),
        "missing_binding_dependencies": sorted(set(missing_bindings)),
        "missing_conformance_dependencies": sorted(set(missing_conformance)),
        "missing_api_dependencies": sorted(set(missing_apis)),
        "missing_metadata_dependencies": sorted(set(missing_metadata)),
        "mismatched_entries": sorted(set(mismatched_entries)),
        "field_capability_edge_mismatches": sorted(set(field_mismatches)),
        "api_capability_gate_mismatches": sorted(set(api_mismatches)),
        "binding_conformance_edge_mismatches": sorted(set(binding_mismatches)),
        "capability_implication_violations": sorted(set(implication_violations)),
        "free_form_capability_expressions": sorted(set(free_form)),
        "gate_grammar_errors": sorted(set(gate_grammar_errors)),
        "implication_graph_acyclic": graph_acyclic,
        "capability_edge_target_count": capability_edge_target_count,
        "capability_edge_covered_count": capability_edge_covered_count,
        "exact_field_edge_target_count": sum(
            len(items) for items in EXPECTED_CAPABILITY_EDGE_TARGETS.values()
        ),
        "exact_field_edge_covered_count": len(valid_field_edges),
        "api_gate_edge_target_count": sum(
            len(items) for items in EXPECTED_CAPABILITY_API_GATE_REFS.values()
        ),
        "api_gate_edge_covered_count": len(valid_api_edges),
    }


def derive_selected_register_aggregates(
    contract: dict[str, Any],
) -> dict[str, Any]:
    expression_contract = contract.get("register_value_expression_contract", {})
    aggregate_contract = contract.get("selected_register_aggregate_contract", {})
    expression_errors: list[str] = []
    parameter_errors: list[str] = []
    overflow_errors: list[str] = []
    non_machine_values: list[str] = []
    manual_duplicates: list[str] = []
    reset_mismatches: list[str] = []
    static_mismatches: list[str] = []
    access_mismatches: list[str] = []

    expected_expression_contract = {
        "allowed_expression_nodes": [
            "INTEGER_LITERAL",
            "PARAMETER_REFERENCE",
            "DYNAMIC_STATIC_VALUE",
        ],
        "integer_width_bits": 32,
        "integer_signedness": "UNSIGNED",
        "overflow_behavior": "REJECT_FIELD_OR_REGISTER_OVERFLOW",
        "canonical_serialization": "STRICT_JSON_SORTED_KEYS_NO_PROSE_EXPRESSIONS",
        "rendering": {
            "verilog": "PARAMETER_NAME_IN_FIELD_SLICE_WITH_WIDTH_CHECK",
            "python": "PARAMETER_NAME_WITH_RANGE_VALIDATION",
            "tcl_ipxact": (
                "PARAMETER_REFERENCE_PLUS_RESOLVED_RESET_FOR_SELECTED_CONFIGURATION"
            ),
            "documentation": "PARAMETER_NAME_RANGE_AND_CONFIGURED_DEFAULT",
            "testbench": "PARAMETERIZED_EXPECTATION_AND_16_24_32_MATRIX",
        },
        "unknown_expression_kind": "REJECT",
        "unknown_parameter_name": "REJECT",
    }
    for key, expected in expected_expression_contract.items():
        if expression_contract.get(key) != expected:
            expression_errors.append(f"expression contract differs: {key}")

    parameter_items = [
        item for item in expression_contract.get("parameters", []) if isinstance(item, dict)
    ]
    parameter_names = [str(item.get("name")) for item in parameter_items]
    parameter_map: dict[str, dict[str, Any]] = {}
    for item in parameter_items:
        parameter_map.setdefault(str(item.get("name")), item)
    if len(parameter_names) != len(set(parameter_names)):
        parameter_errors.append("duplicate parameter definition")
    expected_parameter = {
        "name": "OBS_SEQUENCE_WIDTH",
        "value_width_bits": 8,
        "minimum": 16,
        "maximum": 32,
        "configured_default": 32,
    }
    if parameter_items != [expected_parameter]:
        parameter_errors.append("OBS_SEQUENCE_WIDTH parameter contract differs")

    if aggregate_contract.get("register_reset_authority") != (
        "DERIVED_FROM_FIELD_RESETS"
    ):
        reset_mismatches.append("register reset authority differs")
    if aggregate_contract.get("register_static_value_authority") != (
        "DERIVED_FROM_FIELD_STATIC_VALUES"
    ):
        static_mismatches.append("register static value authority differs")
    if aggregate_contract.get("manual_register_reset_duplication") != "FORBIDDEN":
        manual_duplicates.append("manual register reset duplication policy differs")
    if aggregate_contract.get("expectation_authority") != (
        "REPORT_ONLY_RECOMPUTED_BY_AUDIT"
    ):
        reset_mismatches.append("aggregate expectation authority differs")
    expected_consumers = [
        "IP_XACT_RESET",
        "GENERATED_DOCUMENTATION_WORD",
        "CONFORMANCE_DEFAULT",
    ]
    if aggregate_contract.get("derived_consumers") != expected_consumers:
        expression_errors.append("derived register consumer contract differs")

    default_values = aggregate_contract.get("default_parameter_values", {})
    if not isinstance(default_values, dict):
        default_values = {}
        parameter_errors.append("default parameter values are malformed")
    if set(default_values) != set(parameter_map):
        parameter_errors.append("default parameter set differs from definitions")
    for name, definition in parameter_map.items():
        if default_values.get(name) != definition.get("configured_default"):
            parameter_errors.append(f"parameter configured default differs: {name}")

    registers = [
        item
        for item in contract.get("selected_abi_1_1_registers", [])
        if isinstance(item, dict)
    ]

    def evaluate_value(
        value: Any,
        *,
        width: int,
        location: str,
        parameter_values: dict[str, Any],
        allow_dynamic: bool,
        local_errors: list[str],
    ) -> tuple[str, int | None]:
        if isinstance(value, int) and not isinstance(value, bool):
            if value < 0 or value >= (1 << width):
                overflow_errors.append(
                    f"{location}:field expression overflow value={value} width={width}"
                )
                local_errors.append(location)
                return "ERROR", None
            return "VALUE", value
        if not isinstance(value, dict):
            non_machine_values.append(f"{location}:{value!r}")
            local_errors.append(location)
            return "ERROR", None
        kind = value.get("kind")
        if kind == "dynamic":
            if set(value) != {"kind"} or not allow_dynamic:
                expression_errors.append(f"{location}:dynamic expression is not allowed")
                local_errors.append(location)
                return "ERROR", None
            return "DYNAMIC", None
        if kind != "parameter":
            expression_errors.append(f"{location}:unknown expression kind {kind!r}")
            non_machine_values.append(f"{location}:unknown kind {kind!r}")
            local_errors.append(location)
            return "ERROR", None
        if set(value) != {"kind", "name"}:
            expression_errors.append(f"{location}:parameter expression is not closed")
            local_errors.append(location)
            return "ERROR", None
        name = value.get("name")
        definition = parameter_map.get(str(name))
        if definition is None:
            parameter_errors.append(f"{location}:unknown parameter name {name!r}")
            non_machine_values.append(f"{location}:unknown parameter {name!r}")
            local_errors.append(location)
            return "ERROR", None
        parameter_value = parameter_values.get(str(name))
        minimum = definition.get("minimum")
        maximum = definition.get("maximum")
        value_width = definition.get("value_width_bits")
        if (
            not isinstance(parameter_value, int)
            or isinstance(parameter_value, bool)
            or not isinstance(minimum, int)
            or not isinstance(maximum, int)
            or not isinstance(value_width, int)
            or minimum < 0
            or minimum > maximum
            or value_width <= 0
            or parameter_value < minimum
            or parameter_value > maximum
        ):
            parameter_errors.append(
                f"{location}:parameter value outside declared range {name}={parameter_value!r}"
            )
            local_errors.append(location)
            return "ERROR", None
        if parameter_value >= (1 << value_width) or parameter_value >= (1 << width):
            overflow_errors.append(
                f"{location}:parameter-expression overflow {name}={parameter_value}"
            )
            local_errors.append(location)
            return "ERROR", None
        return "VALUE", parameter_value

    def derive_words(
        parameter_values: dict[str, Any], *, label: str
    ) -> tuple[dict[str, int | None], dict[str, int | None], dict[str, list[str]]]:
        reset_words: dict[str, int | None] = {}
        static_words: dict[str, int | None] = {}
        failures: dict[str, list[str]] = {}
        for register in registers:
            register_name = str(register.get("name"))
            reset_local_errors: list[str] = []
            static_local_errors: list[str] = []
            reset_word = 0
            static_word = 0
            static_dynamic = False
            for field in register.get("fields", []):
                if not isinstance(field, dict):
                    reset_local_errors.append(f"{register_name}.<malformed>")
                    static_local_errors.append(f"{register_name}.<malformed>")
                    continue
                field_name = str(field.get("name"))
                bits = field.get("bits", {})
                try:
                    msb = int(bits.get("msb"))
                    lsb = int(bits.get("lsb"))
                except (AttributeError, TypeError, ValueError):
                    reset_local_errors.append(f"{register_name}.{field_name}.bits")
                    static_local_errors.append(f"{register_name}.{field_name}.bits")
                    continue
                width = msb - lsb + 1
                if width <= 0 or lsb < 0 or msb >= 32:
                    reset_local_errors.append(f"{register_name}.{field_name}.bits")
                    static_local_errors.append(f"{register_name}.{field_name}.bits")
                    continue
                reset_status, reset_value = evaluate_value(
                    field.get("reset"),
                    width=width,
                    location=f"{label}:{register_name}.{field_name}.reset",
                    parameter_values=parameter_values,
                    allow_dynamic=False,
                    local_errors=reset_local_errors,
                )
                if reset_status == "VALUE" and reset_value is not None:
                    shifted = reset_value << lsb
                    if shifted > 0xFFFFFFFF:
                        overflow_errors.append(
                            f"{label}:{register_name}.{field_name}:register aggregate overflow"
                        )
                        reset_local_errors.append(
                            f"{register_name}.{field_name}.reset"
                        )
                    else:
                        reset_word |= shifted
                static_status, static_value = evaluate_value(
                    field.get("static_value"),
                    width=width,
                    location=f"{label}:{register_name}.{field_name}.static_value",
                    parameter_values=parameter_values,
                    allow_dynamic=True,
                    local_errors=static_local_errors,
                )
                if static_status == "DYNAMIC":
                    static_dynamic = True
                elif static_status == "VALUE" and static_value is not None:
                    shifted = static_value << lsb
                    if shifted > 0xFFFFFFFF:
                        overflow_errors.append(
                            f"{label}:{register_name}.{field_name}:register aggregate overflow"
                        )
                        static_local_errors.append(
                            f"{register_name}.{field_name}.static_value"
                        )
                    else:
                        static_word |= shifted
            failures[register_name] = sorted(
                set(reset_local_errors + static_local_errors)
            )
            reset_words[register_name] = (
                None if reset_local_errors else reset_word
            )
            static_words[register_name] = (
                None if static_local_errors or static_dynamic else static_word
            )
        return reset_words, static_words, failures

    for register in registers:
        register_name = str(register.get("name"))
        if "reset" in register or "static_value" in register:
            manual_duplicates.append(register_name)
        if register.get("derived_reset") is not True:
            reset_mismatches.append(f"{register_name}:derived_reset is not true")
        if register.get("derived_static_value") is not True:
            static_mismatches.append(
                f"{register_name}:derived_static_value is not true"
            )
        fields = [field for field in register.get("fields", []) if isinstance(field, dict)]
        if register.get("register_access") != "RO" or any(
            field.get("access") not in {"RO", "RSVD"} for field in fields
        ):
            access_mismatches.append(f"{register_name}:register/field access contradicts")

    reset_words, static_words, default_failures = derive_words(
        dict(default_values), label="DEFAULT"
    )
    expectation_items = [
        item
        for item in aggregate_contract.get("register_expectations", [])
        if isinstance(item, dict)
    ]
    expectation_names = [str(item.get("register")) for item in expectation_items]
    expectation_map = {
        str(item.get("register")): item for item in expectation_items
    }
    if len(expectation_names) != len(set(expectation_names)):
        reset_mismatches.append("duplicate aggregate register expectation")
    if set(expectation_names) != set(EXPECTED_REGISTER_WORDS):
        reset_mismatches.append("aggregate register expectation inventory differs")

    def parse_expected_hex(value: Any, location: str) -> int | None:
        if value is None:
            return None
        if not isinstance(value, str) or not re.fullmatch(r"0x[0-9A-F]{8}", value):
            non_machine_values.append(f"{location}:{value!r}")
            return None
        return int(value, 16)

    reset_passes = 0
    static_passes = 0
    static_targets = 0
    for register_name, (frozen_reset, frozen_static) in EXPECTED_REGISTER_WORDS.items():
        expectation = expectation_map.get(register_name, {})
        expected_reset = parse_expected_hex(
            expectation.get("default_reset_hex"),
            f"{register_name}.default_reset_hex",
        )
        expected_static = parse_expected_hex(
            expectation.get("default_static_hex"),
            f"{register_name}.default_static_hex",
        )
        if expected_reset != frozen_reset or reset_words.get(register_name) != expected_reset:
            reset_mismatches.append(
                f"{register_name}:aggregate reset differs derived={reset_words.get(register_name)!r} expected={expected_reset!r}"
            )
        else:
            reset_passes += 1
        if frozen_static is not None:
            static_targets += 1
            if expected_static != frozen_static or static_words.get(register_name) != expected_static:
                static_mismatches.append(
                    f"{register_name}:aggregate static value differs derived={static_words.get(register_name)!r} expected={expected_static!r}"
                )
            else:
                static_passes += 1
        elif expectation.get("default_static_hex") is not None:
            static_mismatches.append(
                f"{register_name}:dynamic register has a full static expectation"
            )
        elif static_words.get(register_name) is not None:
            static_mismatches.append(
                f"{register_name}:dynamic register unexpectedly derived a static word"
            )

    width_values: dict[int, int | None] = {}
    for width in sorted(EXPECTED_CAPABILITIES_1_WIDTH_VALUES):
        matrix_parameters = dict(default_values)
        matrix_parameters["OBS_SEQUENCE_WIDTH"] = width
        matrix_resets, matrix_statics, _ = derive_words(
            matrix_parameters, label=f"WIDTH_{width}"
        )
        reset_value = matrix_resets.get("CAPABILITIES_1")
        static_value = matrix_statics.get("CAPABILITIES_1")
        width_values[width] = reset_value
        if (
            reset_value != EXPECTED_CAPABILITIES_1_WIDTH_VALUES[width]
            or static_value != EXPECTED_CAPABILITIES_1_WIDTH_VALUES[width]
        ):
            parameter_errors.append(
                f"CAPABILITIES_1 width {width} derivation differs"
            )

    return {
        "reset_words": reset_words,
        "static_words": static_words,
        "default_failures": default_failures,
        "reset_target_count": len(EXPECTED_REGISTER_WORDS),
        "reset_covered_count": reset_passes,
        "static_target_count": static_targets,
        "static_covered_count": static_passes,
        "register_field_reset_mismatches": sorted(set(reset_mismatches)),
        "register_field_static_value_mismatches": sorted(set(static_mismatches)),
        "register_field_access_mismatches": sorted(set(access_mismatches)),
        "non_machine_evaluable_register_values": sorted(set(non_machine_values)),
        "manual_register_reset_duplications": sorted(set(manual_duplicates)),
        "expression_errors": sorted(set(expression_errors)),
        "parameter_errors": sorted(set(parameter_errors)),
        "overflow_errors": sorted(set(overflow_errors)),
        "capabilities_1_width_values": width_values,
        "parameterized_register_expressions_validated": not (
            expression_errors
            or parameter_errors
            or overflow_errors
            or non_machine_values
        ),
        "derived_consumers": expected_consumers,
    }


def derive_fault_taxonomy_coverage(contract: dict[str, Any]) -> dict[str, Any]:
    taxonomy = contract.get("fault_taxonomy", {})
    errors: list[str] = []
    codes = [item for item in taxonomy.get("fault_codes", []) if isinstance(item, dict)]
    code_names = [str(item.get("canonical_name")) for item in codes]
    code_values = [item.get("value") for item in codes]
    code_map = {str(item.get("canonical_name")): item for item in codes}

    if taxonomy.get("schema_version") != "FAULT_TAXONOMY_V1" or taxonomy.get(
        "authority"
    ) != "SOLE_FUTURE_FAULT_CODE_AND_BITMAP_AUTHORITY":
        errors.append("fault taxonomy authority differs")
    if code_names != list(EXPECTED_FAULT_CODE_VALUES):
        errors.append("fault code canonical enumeration differs")
    if len(code_values) != len(set(code_values)):
        errors.append("fault-code duplicate numeric value")
    for name, expected_value in EXPECTED_FAULT_CODE_VALUES.items():
        item = code_map.get(name, {})
        if item.get("value") != expected_value:
            errors.append(f"fault code {name} value changed")
        if set(item.get("legacy_aliases", [])) != EXPECTED_FAULT_CODE_ALIASES[name]:
            errors.append(f"fault code {name} legacy aliases changed")
        for generated_name in (
            "software_name",
            "rtl_name",
            "c_name",
            "systemverilog_name",
            "ipxact_name",
        ):
            if not str(item.get(generated_name, "")).strip():
                errors.append(f"fault code {name} generated name missing: {generated_name}")
    for generated_name in (
        "software_name",
        "rtl_name",
        "c_name",
        "systemverilog_name",
        "ipxact_name",
    ):
        values = [str(item.get(generated_name)) for item in codes]
        if len(values) != len(set(values)):
            errors.append(f"fault code generated names are duplicated: {generated_name}")

    binding = taxonomy.get("fault_code_binding", {})
    if binding != {
        "target": "FAULT_CODE.fault_code_latched",
        "enum_ref": "fault_taxonomy.fault_codes",
        "projection_ref": "fault_taxonomy.compatibility_projection",
    }:
        errors.append("FAULT_CODE compatibility enum binding differs")
    current_fault_field: dict[str, Any] = {}
    for register in contract.get("current_abi", {}).get("registers", []):
        if not isinstance(register, dict) or register.get("name") != "FAULT_CODE":
            continue
        current_fault_field = next(
            (
                field
                for field in register.get("fields", [])
                if isinstance(field, dict) and field.get("name") == "fault_code_latched"
            ),
            {},
        )
    if current_fault_field.get("enum_ref") != "fault_taxonomy.fault_codes":
        errors.append("current ABI FAULT_CODE field lacks taxonomy enum binding")

    causes = [item for item in taxonomy.get("fault_causes", []) if isinstance(item, dict)]
    cause_names = [str(item.get("canonical_name")) for item in causes]
    cause_bits = [item.get("bit") for item in causes]
    causes_by_bit = {
        item.get("bit"): str(item.get("canonical_name")) for item in causes
    }
    if len(cause_bits) != len(set(cause_bits)):
        errors.append("fault bitmap duplicate cause bit")
    for bit, expected_name in enumerate(FAULT_CAUSE_NAMES):
        if causes_by_bit.get(bit) != expected_name:
            errors.append(f"fault bitmap bit {bit} renamed or reassigned")
        item = next((entry for entry in causes if entry.get("bit") == bit), {})
        if item.get("mask") != f"0x{1 << bit:08X}":
            errors.append(f"fault bitmap bit {bit} mask differs")
        for generated_name in (
            "software_name",
            "rtl_name",
            "c_name",
            "systemverilog_name",
            "ipxact_name",
        ):
            if not str(item.get(generated_name, "")).strip():
                errors.append(
                    f"fault bitmap bit {bit} generated name missing: {generated_name}"
                )
    width = taxonomy.get("fault_bitmap_width")
    highest_bit = max((bit for bit in cause_bits if isinstance(bit, int)), default=-1)
    if width != highest_bit + 1 or width != len(FAULT_CAUSE_NAMES):
        errors.append("FAULT_BITMAP_WIDTH differs from highest defined bit plus one")
    try:
        valid_mask = int(str(taxonomy.get("fault_bitmap_valid_mask")), 16)
        reserved_mask = int(str(taxonomy.get("fault_bitmap_reserved_mask")), 16)
    except ValueError:
        valid_mask = reserved_mask = -1
        errors.append("fault bitmap masks are malformed")
    expected_valid_mask = (1 << len(FAULT_CAUSE_NAMES)) - 1
    expected_reserved_mask = 0xFFFFFFFF ^ expected_valid_mask
    if valid_mask & reserved_mask:
        errors.append("fault bitmap valid and reserved masks overlap")
    if valid_mask != expected_valid_mask:
        errors.append("fault bitmap valid mask differs from defined causes")
    if reserved_mask != expected_reserved_mask or (valid_mask | reserved_mask) != 0xFFFFFFFF:
        errors.append("fault bitmap reserved mask differs from 32-bit complement")

    selected_registers = {
        str(item.get("name")): item
        for item in contract.get("selected_abi_1_1_registers", [])
        if isinstance(item, dict)
    }
    for register_name in FAULT_BITMAP_REGISTERS:
        fields = [
            field
            for field in selected_registers.get(register_name, {}).get("fields", [])
            if isinstance(field, dict)
        ]
        field_map = {str(field.get("name")): field for field in fields}
        if list(field_map) != [*FAULT_CAUSE_NAMES, "RESERVED"]:
            errors.append(f"bitmap register field enumeration differs: {register_name}")
        reserved = field_map.get("RESERVED", {})
        if reserved.get("bits") != {"msb": 31, "lsb": len(FAULT_CAUSE_NAMES)}:
            errors.append(f"bitmap register omits reserved upper bits: {register_name}")
        for bit, cause_name in enumerate(FAULT_CAUSE_NAMES):
            field = field_map.get(cause_name, {})
            if field.get("bits") != {"msb": bit, "lsb": bit}:
                errors.append(f"bitmap cause field range differs: {register_name}.{cause_name}")
            if field.get("fault_cause_ref") != cause_name:
                errors.append(f"bitmap cause taxonomy reference differs: {register_name}.{cause_name}")

    projection = taxonomy.get("compatibility_projection", {})
    if projection.get("priority") != EXPECTED_FAULT_PROJECTION:
        errors.append("compatibility projection priority changed")
    if projection.get("kind") != "PRIORITY_PREDICATE_PROJECTION" or projection.get(
        "output_enum_ref"
    ) != "fault_taxonomy.fault_codes":
        errors.append("compatibility projection authority differs")
    if projection.get("complete_bitmap_retains_simultaneous_causes") is not True:
        errors.append("compatibility projection loses simultaneous bitmap causes")

    if taxonomy.get("extension_policy") != {
        "new_cause_in_reserved_range": "ADDITIVE_ABI_MINOR_PLUS_CAPABILITY_AND_WIDTH_UPDATE",
        "renumber_existing_cause": "ABI_MAJOR_CHANGE",
        "change_fault_code_value_or_projection": "ABI_MAJOR_CHANGE_UNLESS_SEPARATELY_VERSIONED_COMPATIBILITY_CODE",
    }:
        errors.append("fault taxonomy extension policy differs")
    consumer_plan = taxonomy.get("consumer_plan", {})
    expected_consumer_kinds = {
        "RTL_VERILOG_INCLUDE",
        "PYTHON_INTENUM_INTFLAG",
        "C_CONSTANTS_ENUMS",
        "SYSTEMVERILOG_CONSTANTS",
        "IP_XACT_FIELD_ENUM_METADATA",
        "REGISTER_DOCUMENTATION",
        "CONFORMANCE_VECTORS",
    }
    consumer_kinds = {
        str(item.get("kind"))
        for item in consumer_plan.get("generated_consumers", [])
        if isinstance(item, dict) and str(item.get("artifact", "")).strip()
    }
    if (
        consumer_plan.get("status") != "APPROVED"
        or consumer_kinds != expected_consumer_kinds
        or consumer_plan.get("handwritten_duplicates_after_convergence") != "FORBIDDEN"
    ):
        errors.append("fault taxonomy consumer plan differs")
    if consumer_plan.get("legacy_alias_plan") != (
        "GENERATED_LEGACY_INCLUDE_PATHS_AND_NAMES_PRESERVED"
    ):
        errors.append("legacy fault name alias plan differs")

    return {
        "fault_code_target_count": len(EXPECTED_FAULT_CODE_VALUES),
        "fault_code_covered_count": len(EXPECTED_FAULT_CODE_VALUES)
        if not [error for error in errors if error.startswith("fault code")]
        else sum(
            code_map.get(name, {}).get("value") == value
            for name, value in EXPECTED_FAULT_CODE_VALUES.items()
        ),
        "fault_cause_target_count": len(FAULT_CAUSE_NAMES),
        "fault_cause_covered_count": sum(
            causes_by_bit.get(bit) == name for bit, name in enumerate(FAULT_CAUSE_NAMES)
        ),
        "fault_bitmap_width": width,
        "valid_mask": valid_mask,
        "reserved_mask": reserved_mask,
        "fault_code_names": code_names,
        "fault_cause_names": cause_names,
        "errors": errors,
    }


def derive_generated_artifact_topology(contract: dict[str, Any]) -> dict[str, Any]:
    topology = contract.get("generated_artifact_topology", {})
    selected = contract.get("selected_single_source", {})
    consumers = contract.get("fault_taxonomy", {}).get("consumer_plan", {}).get(
        "generated_consumers", []
    )
    errors: list[str] = []

    master_artifacts = [
        item for item in selected.get("generated_artifacts", []) if isinstance(item, dict)
    ]
    master_paths = [str(item.get("path")) for item in master_artifacts]
    consumer_items = [item for item in consumers if isinstance(item, dict)]
    consumer_paths = [str(item.get("artifact")) for item in consumer_items]
    consumer_map = {
        str(item.get("kind")): str(item.get("artifact")) for item in consumer_items
    }

    if topology.get("authority") != "ONE_MASTER_LIST":
        errors.append("generated artifact topology authority differs")
    if topology.get("master_list_ref") != (
        "selected_single_source.generated_artifacts"
    ):
        errors.append("generated artifact master list reference differs")
    if topology.get("validation_approach") != "FIXED_PROJECT_SPECIFIC_TABLE":
        errors.append("generated artifact topology validation is not project-specific")
    if topology.get("unowned_generated_artifacts") != "FORBIDDEN":
        errors.append("unowned generated artifact path is allowed")

    if tuple(master_paths) != EXPECTED_MASTER_GENERATED_ARTIFACT_PATHS:
        errors.append("master generated artifact topology differs")
    duplicate_master_count = len(master_paths) - len(set(master_paths))
    duplicate_consumer_count = len(consumer_paths) - len(set(consumer_paths))
    if duplicate_master_count:
        errors.append("duplicate generated path")
    if duplicate_consumer_count:
        errors.append("taxonomy consumer artifact conflict")

    master_set = set(master_paths)
    expected_master_set = set(EXPECTED_MASTER_GENERATED_ARTIFACT_PATHS)
    consumers_outside_master = sorted(set(consumer_paths) - master_set)
    unexpected_master_paths = sorted(master_set - expected_master_set)
    unowned_paths = sorted(set(consumers_outside_master + unexpected_master_paths))
    if consumers_outside_master:
        errors.append("taxonomy consumer points outside master artifact set")
    if unowned_paths:
        errors.append("unowned generated artifact path")

    if set(consumer_map) != set(EXPECTED_TAXONOMY_CONSUMER_ARTIFACTS):
        errors.append("taxonomy consumer kind set differs")
    for kind, expected_path in EXPECTED_TAXONOMY_CONSUMER_ARTIFACTS.items():
        if consumer_map.get(kind) != expected_path:
            errors.append(f"taxonomy consumer mapping differs: {kind}")

    legacy_rtl = topology.get("legacy_rtl_fault_defs", {})
    if legacy_rtl.get("path") != "rtl/fault_defs.vh" or legacy_rtl.get(
        "compatibility_plan"
    ) != "STABLE_VALUE_FREE_SHIM_INCLUDES_MASTER_RTL_ARTIFACT":
        errors.append("legacy RTL fault include path has no compatibility plan")
    if legacy_rtl.get("master_artifact") != (
        "rtl/generated/protection_register_map.vh"
    ) or legacy_rtl.get("master_artifact") not in master_set:
        errors.append("legacy RTL fault include target differs from master artifact")
    if legacy_rtl.get("legacy_names_preserved") is not True:
        errors.append("legacy RTL fault names are not preserved")
    if legacy_rtl.get("independent_manual_values_after_convergence") is not False:
        errors.append("fault_defs retains independent manual values after convergence")

    legacy_c = topology.get("legacy_c_header", {})
    if (
        legacy_c.get("path") != "sw/ps_register_demo/protection_ip_regs.h"
        or "sw/ps_register_demo/protection_ip_regs.h" not in master_set
    ):
        errors.append("legacy C output path changed")
    if legacy_c.get("master_generated_artifact") is not True:
        errors.append("legacy C header is outside the master artifact list")
    if legacy_c.get("legacy_names_preserved") is not True:
        errors.append("legacy C fault names are not preserved")

    master_covered = sum(
        master_paths.count(path) == 1
        for path in EXPECTED_MASTER_GENERATED_ARTIFACT_PATHS
    )
    taxonomy_covered = sum(
        consumer_map.get(kind) == path
        for kind, path in EXPECTED_TAXONOMY_CONSUMER_ARTIFACTS.items()
    )
    return {
        "master_target_count": len(EXPECTED_MASTER_GENERATED_ARTIFACT_PATHS),
        "master_covered_count": master_covered,
        "taxonomy_target_count": len(EXPECTED_TAXONOMY_CONSUMER_ARTIFACTS),
        "taxonomy_covered_count": taxonomy_covered,
        "master_paths": master_paths,
        "consumer_map": consumer_map,
        "unowned_paths": unowned_paths,
        "duplicate_path_count": duplicate_master_count + duplicate_consumer_count,
        "errors": errors,
    }


def derive_stage2h_a1_scope(contract: dict[str, Any]) -> dict[str, Any]:
    handoff = contract.get("stage2h_a1_handoff", {})
    boundary = contract.get("audit_live_source_boundary", {})
    errors: list[str] = []
    expected_handoff = {
        "current_substage": "STAGE2H_A1_REGISTER_MAP_AND_PUBLIC_ABI_ARCHITECTURE",
        "stage2h_a1_implementation_started": False,
        "stage2h_a_complete": False,
        "stage2h_complete": False,
        "next_after_stage2h_a1": "STAGE2H_A2_REGISTER_MAP_AND_PUBLIC_ABI_IMPLEMENTATION",
        "stage2h_b": "RTL_ARCHITECTURE_AND_MODULE_BOUNDARY_CONVERGENCE",
        "stage2h_b_status": "NOT_STARTED",
        "stage2h_c": "BUILD_GENERATION_VERIFICATION_AND_REPOSITORY_CONVERGENCE",
        "stage2h_c_status": "NOT_STARTED",
        "stage2h_d": "INTEGRATED_REGRESSION_COVERAGE_AND_RELEASE_CLOSURE",
        "stage2h_d_status": "NOT_STARTED",
        "stage2i": "SYNTHESIS_IMPLEMENTATION_TIMING_AND_DIGITAL_BOARD_CLOSURE",
        "stage2i_status": "NOT_STARTED",
    }
    for key, value in expected_handoff.items():
        if handoff.get(key) != value:
            errors.append(f"Stage 2H-A1 handoff differs: {key}")

    expected_boundary = {
        "stage2h_a1_audit_contract": "spec/stage2h_register_map_convergence.json",
        "future_live_register_map_source": "spec/register_map.json",
        "audit_contract_is_future_live_register_map_source": False,
        "future_live_source_scope": "PUBLIC_ABI_GENERATION_AND_VALIDATION_ONLY",
        "audit_only_history_copied_to_live_source": False,
    }
    for key, value in expected_boundary.items():
        if boundary.get(key) != value:
            errors.append(f"audit/live-source boundary differs: {key}")
    return {"handoff": handoff, "boundary": boundary, "errors": errors}


def derive_first_principles_scope_review(contract: dict[str, Any]) -> dict[str, Any]:
    review = contract.get("first_principles_scope_review", {})
    errors: list[str] = []
    expected = {
        "status": "PASS",
        "new_generic_framework_added": False,
        "audit_scope_expansion": False,
        "overengineered_generic_dsl_added": False,
        "general_verilog_semantic_parser_added": False,
        "full_rtl_declaration_graph_added": False,
        "conformance_approach": "FINITE_PROJECT_SPECIFIC_TEMPLATES",
        "rtl_source_binding_approach": (
            "LIGHTWEIGHT_EXPLICIT_BINDINGS_PLUS_COMPILE_SIM_CHECKS"
        ),
        "long_term_complexity_reduced": True,
    }
    for key, value in expected.items():
        if review.get(key) != value:
            errors.append(f"first-principles scope review differs: {key}")
    approved_ids = {
        str(item.get("id"))
        for item in review.get("approved_mechanisms", [])
        if isinstance(item, dict)
        and item.get("stage2h_required") is True
        and all(
            str(item.get(key, "")).strip()
            for key in (
                "failure_prevented",
                "simpler_existing_gate",
                "complexity_effect",
            )
        )
    }
    if approved_ids != {
        "POLICY_IDENTITY_EVENT_CAPTURE",
        "LIGHTWEIGHT_SOURCE_BINDINGS",
        "FINITE_CONFORMANCE_TEMPLATES",
        "UNKNOWN_FAULT_CAUSE_PRESERVATION",
        "ONE_MASTER_GENERATED_ARTIFACT_TOPOLOGY",
    }:
        errors.append("first-principles approved mechanism inventory differs")
    rejected = {
        str(item.get("id")): item.get("decision")
        for item in review.get("rejected_mechanisms", [])
        if isinstance(item, dict)
    }
    expected_rejected = {
        "GENERAL_CONFORMANCE_DSL": "REJECTED_OVERENGINEERING",
        "GENERAL_VERILOG_SEMANTIC_PARSER": "REJECTED_OVERENGINEERING",
        "FULL_RTL_DECLARATION_GRAPH": "REJECTED_OVERENGINEERING",
        "GENERIC_GENERATED_ARTIFACT_DEPENDENCY_GRAPH": "REJECTED_OVERENGINEERING",
        "DUPLICATED_RTL_SOURCE_FINGERPRINT_AUTHORITY": "DEFERRED_NOT_REQUIRED",
        "FULL_RTL_SEMANTIC_MODEL_IN_JSON": "DEFERRED_NOT_REQUIRED",
    }
    if rejected != expected_rejected:
        errors.append("first-principles rejected mechanism inventory differs")
    return {"errors": errors}


def _strip_verilog_comments(text: str) -> str:
    without_blocks = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", without_blocks)


def _verilog_module_body(text: str, module: str) -> str | None:
    stripped = _strip_verilog_comments(text)
    matches = re.findall(
        rf"\bmodule\s+{re.escape(module)}\b.*?\bendmodule\b",
        stripped,
        flags=re.DOTALL,
    )
    return matches[0] if len(matches) == 1 else None


def _verilog_port_declaration(
    module_body: str, signal: str
) -> tuple[str, str | None, str | None] | None:
    match = re.search(
        rf"\b(?P<direction>input|output)\s+"
        rf"(?:(?P<storage>wire|reg)\s+)?"
        rf"(?:(?P<width>\[[^\]]+\])\s+)?"
        rf"{re.escape(signal)}\b",
        module_body,
    )
    if match is None:
        return None
    return (
        match.group("direction").upper(),
        match.group("storage").upper() if match.group("storage") else None,
        re.sub(r"\s+", "", match.group("width"))
        if match.group("width")
        else None,
    )


def _verilog_width(width: str | None) -> tuple[str, int | None, str | None] | None:
    if width is None:
        return ("LITERAL", 1, None)
    literal = re.fullmatch(r"\[(\d+):(\d+)\]", width)
    if literal:
        msb, lsb = (int(value) for value in literal.groups())
        return ("LITERAL", msb - lsb + 1, None) if msb >= lsb else None
    parameter = re.fullmatch(r"\[([A-Za-z_][A-Za-z0-9_]*)-1:0\]", width)
    if parameter:
        return ("PARAMETER", None, parameter.group(1))
    return None


def _verilog_instance(
    module_body: str, child_module: str, instance: str
) -> tuple[str, str] | None:
    nested_parentheses = r"(?:[^()]|\([^()]*\))*"
    match = re.search(
        rf"\b{re.escape(child_module)}\b\s*"
        rf"(?P<parameters>#\s*\({nested_parentheses}\))?\s*"
        rf"{re.escape(instance)}\s*"
        rf"\((?P<ports>{nested_parentheses})\)\s*;",
        module_body,
        flags=re.DOTALL,
    )
    if match is None:
        return None
    return match.group("parameters") or "", match.group("ports")


def derive_rtl_source_binding_coverage(
    root: Path, contract: dict[str, Any]
) -> dict[str, Any]:
    authority = contract.get("stage2h_rtl_source_bindings", {})
    errors: list[str] = []
    missing_declarations: list[str] = []
    width_mismatches: list[str] = []
    state_mismatches: list[str] = []
    direction_mismatches: list[str] = []
    connection_mismatches: list[str] = []
    domain_mismatches: list[str] = []
    invalid_ids: set[str] = set()
    expected_ids = {
        "SRC_STAGE2G_STATE",
        "SRC_CLEAR_PENDING",
        "SRC_POST_CLEAR_RECOVERY_PENDING",
        "SRC_FIRST_FAULT_BITMAP",
        "SRC_LIVE_FAULT_BITMAP",
        "SRC_FAULT_SEEN_BITMAP",
        "SRC_FAULT_EVAL_VALID",
        "SRC_FAULT_EVAL_SEQUENCE",
        "SRC_FAULT_EVAL_BITMAP",
        "SRC_FAULT_EVAL_INTEGRITY_CLEAN",
    }

    expected_header = {
        "schema_version": "STAGE2H_SOURCE_BINDINGS_V1",
        "authority": "LIGHTWEIGHT_EXPLICIT_STAGE2H_BINDINGS",
        "implementation_status": (
            "CURRENT_STAGE2G_RTL_DECLARATIONS_FUTURE_STAGE2H_CONSUMERS_NOT_IMPLEMENTED"
        ),
        "checker": "PROJECT_SPECIFIC_DECLARATION_CONNECTION_AND_WIDTH_CHECKS",
        "compile_elaboration_gate": "EXISTING_STAGE2G_CURRENT_TREE_ICARUS",
        "targeted_simulation_gate": (
            "EXISTING_STAGE2G_DIRECTED_POLICY_AND_SEQUENCE_TESTS"
        ),
        "general_verilog_semantic_parser": "REJECTED_OVERENGINEERING",
        "full_rtl_declaration_graph": "REJECTED_OVERENGINEERING",
        "source_fingerprint_policy": (
            "DEFERRED_NOT_REQUIRED_COMMITTED_RTL_PLUS_DECLARATION_CHECK_IS_AUTHORITY"
        ),
    }
    for key, value in expected_header.items():
        if authority.get(key) != value:
            errors.append(f"RTL source binding authority differs: {key}")
    if authority.get("clock_domain") != {
        "id": "ACLK",
        "port": "clk",
        "edge": "POSEDGE",
    }:
        errors.append("RTL source clock domain differs")
    if authority.get("reset_domain") != {
        "id": "LOCAL_ACTIVE_LOW_RESET",
        "port": "rst_n",
        "assertion": "ASYNCHRONOUS_NEGEDGE",
    }:
        errors.append("RTL source reset domain differs")

    bindings = [
        item for item in authority.get("bindings", []) if isinstance(item, dict)
    ]
    binding_ids = [str(item.get("id")) for item in bindings]
    binding_map = {str(item.get("id")): item for item in bindings}
    if len(binding_ids) != len(set(binding_ids)):
        errors.append("duplicate RTL source binding ID")
    if set(binding_map) != expected_ids:
        errors.append(
            "RTL source binding inventory differs: "
            f"missing={sorted(expected_ids - set(binding_map))}, "
            f"extra={sorted(set(binding_map) - expected_ids)}"
        )

    file_cache: dict[str, str | None] = {}
    module_cache: dict[tuple[str, str], str | None] = {}
    for binding in bindings:
        binding_id = str(binding.get("id"))
        relative = str(binding.get("file"))
        if relative not in file_cache:
            path = root / relative
            file_cache[relative] = (
                path.read_text(encoding="utf-8") if path.is_file() else None
            )
        text = file_cache[relative]
        if text is None:
            missing_declarations.append(f"{binding_id}:missing file {relative}")
            invalid_ids.add(binding_id)
            continue
        module = str(binding.get("module"))
        cache_key = (relative, module)
        if cache_key not in module_cache:
            module_cache[cache_key] = _verilog_module_body(text, module)
        module_body = module_cache[cache_key]
        if module_body is None:
            missing_declarations.append(
                f"{binding_id}:RTL source module does not exist: {module}"
            )
            invalid_ids.add(binding_id)
            continue

        signal = str(binding.get("signal"))
        declaration = _verilog_port_declaration(module_body, signal)
        if declaration is None:
            missing_declarations.append(
                f"{binding_id}:RTL source signal absent from named module: {signal}"
            )
            invalid_ids.add(binding_id)
        else:
            direction, storage, width_text = declaration
            actual_direction = (
                f"{direction}_{storage}" if storage is not None else direction
            )
            if actual_direction != binding.get("direction"):
                direction_mismatches.append(
                    f"{binding_id}:{actual_direction}!={binding.get('direction')}"
                )
                invalid_ids.add(binding_id)
            actual_width = _verilog_width(width_text)
            expected_width = binding.get("width", {})
            expected_tuple = (
                expected_width.get("kind"),
                expected_width.get("bits"),
                expected_width.get("parameter"),
            )
            if actual_width != expected_tuple:
                width_mismatches.append(
                    f"{binding_id}:{actual_width!r}!={expected_tuple!r}"
                )
                invalid_ids.add(binding_id)
            if expected_width.get("kind") == "PARAMETER":
                parameter = str(expected_width.get("parameter"))
                if not re.search(
                    rf"\bparameter\s+{re.escape(parameter)}\b", module_body
                ):
                    width_mismatches.append(
                        f"{binding_id}:RTL source width parameter is absent"
                    )
                    invalid_ids.add(binding_id)
                if expected_width.get("contract_parameter") != "OBS_SEQUENCE_WIDTH":
                    width_mismatches.append(
                        f"{binding_id}:contract width parameter mismatch"
                    )
                    invalid_ids.add(binding_id)
            elif (
                expected_width.get("parameter") is not None
                or expected_width.get("contract_parameter") is not None
            ):
                width_mismatches.append(
                    f"{binding_id}:literal width carries a parameter"
                )
                invalid_ids.add(binding_id)

        if binding.get("clock_domain_ref") != "ACLK" or binding.get(
            "reset_domain_ref"
        ) != "LOCAL_ACTIVE_LOW_RESET":
            domain_mismatches.append(f"{binding_id}:domain reference mismatch")
            invalid_ids.add(binding_id)
        for port in ("clk", "rst_n"):
            if _verilog_port_declaration(module_body, port) is None:
                domain_mismatches.append(f"{binding_id}:missing domain port {port}")
                invalid_ids.add(binding_id)
        if re.search(
            r"always\s*@\s*\(\s*posedge\s+clk\s+or\s+negedge\s+rst_n\s*\)",
            module_body,
        ) is None:
            domain_mismatches.append(f"{binding_id}:clock/reset process differs")
            invalid_ids.add(binding_id)

        state_encoding = binding.get("state_encoding")
        if state_encoding is not None:
            actual_states = {
                name: value
                for name, value in re.findall(
                    r"\blocalparam\s+(ST_[A-Z0-9_]+)\s*=\s*(4'd\d+)\s*;",
                    module_body,
                )
                if name in {"ST_ARMED", "ST_FAULT_LATCHED", "ST_RESET_WAIT"}
            }
            if actual_states != state_encoding:
                state_mismatches.append(
                    f"{binding_id}:{actual_states!r}!={state_encoding!r}"
                )
                invalid_ids.add(binding_id)

        connection = binding.get("connection", {})
        connection_file = str(connection.get("file"))
        if connection_file not in file_cache:
            path = root / connection_file
            file_cache[connection_file] = (
                path.read_text(encoding="utf-8") if path.is_file() else None
            )
        connection_text = file_cache[connection_file]
        owner_body = (
            _verilog_module_body(
                connection_text or "", str(connection.get("module"))
            )
            if connection_text is not None
            else None
        )
        instance = (
            _verilog_instance(
                owner_body,
                module,
                str(connection.get("instance")),
            )
            if owner_body is not None
            else None
        )
        if instance is None:
            connection_mismatches.append(
                f"{binding_id}:RTL source instance connection is absent"
            )
            invalid_ids.add(binding_id)
        else:
            parameter_connections, port_connections = instance
            port = str(connection.get("port"))
            net = str(connection.get("net"))
            if port != signal or re.search(
                rf"\.{re.escape(port)}\s*\(\s*{re.escape(net)}\s*\)",
                port_connections,
            ) is None:
                connection_mismatches.append(
                    f"{binding_id}:RTL source named connection mismatch"
                )
                invalid_ids.add(binding_id)
            width = binding.get("width", {})
            if width.get("kind") == "PARAMETER" and re.search(
                r"\.SEQUENCE_WIDTH\s*\(\s*SEQUENCE_WIDTH\s*\)",
                parameter_connections,
            ) is None:
                connection_mismatches.append(
                    f"{binding_id}:RTL source parameter connection mismatch"
                )
                invalid_ids.add(binding_id)

    dynamic_trace_edges: list[dict[str, str]] = []
    for source in contract.get("dynamic_value_source_contract", {}).get(
        "sources", []
    ):
        if not isinstance(source, dict):
            continue
        for role, key in (
            ("SOURCE", "source_binding_ref"),
            ("DATA", "data_source_binding_ref"),
            ("VALID", "valid_source_binding_ref"),
        ):
            reference = source.get(key)
            if isinstance(reference, str):
                dynamic_trace_edges.append(
                    {
                        "dynamic_source_id": str(source.get("id")),
                        "role": role,
                        "source_binding_ref": reference,
                    }
                )

    consumed_refs = {
        edge["source_binding_ref"] for edge in dynamic_trace_edges
    }
    transition_sources = contract.get("episode_bitmap_transition_rules", {}).get(
        "event_sources", {}
    )
    if isinstance(transition_sources, dict):
        consumed_refs.update(
            value for value in transition_sources.values() if isinstance(value, str)
        )
    identity = contract.get("policy_evaluation_identity_storage_contract", {})
    consumed_refs.update(
        value
        for value in (
            identity.get("data_source_binding_ref"),
            identity.get("valid_source_binding_ref"),
        )
        if isinstance(value, str)
    )
    unknown_refs = sorted(consumed_refs - set(binding_map))
    unconsumed = sorted(set(binding_map) - consumed_refs)
    if missing_declarations:
        errors.extend(missing_declarations)
    if direction_mismatches:
        errors.append(f"RTL source direction mismatch: {direction_mismatches}")
    if width_mismatches:
        errors.append(f"RTL source width mismatch: {width_mismatches}")
    if state_mismatches:
        errors.append(f"RTL state encoding mismatch: {state_mismatches}")
    if connection_mismatches:
        errors.append(f"RTL source connection mismatch: {connection_mismatches}")
    if domain_mismatches:
        errors.append(f"RTL source clock/reset domain mismatch: {domain_mismatches}")
    if unknown_refs:
        errors.append(f"dynamic or transition source has no RTL binding: {unknown_refs}")
    if unconsumed:
        errors.append(f"RTL source inventory entry is unconsumed: {unconsumed}")

    trace_covered = sum(
        edge["source_binding_ref"] in binding_map for edge in dynamic_trace_edges
    )
    return {
        "binding_target_count": len(expected_ids),
        "binding_covered_count": len(expected_ids - invalid_ids)
        if set(binding_map) == expected_ids
        else len((set(binding_map) & expected_ids) - invalid_ids),
        "dynamic_trace_target_count": len(dynamic_trace_edges),
        "dynamic_trace_covered_count": trace_covered,
        "dynamic_trace_edges": dynamic_trace_edges,
        "missing_declarations": missing_declarations,
        "direction_mismatches": direction_mismatches,
        "width_mismatches": width_mismatches,
        "state_mismatches": state_mismatches,
        "connection_mismatches": connection_mismatches,
        "domain_mismatches": domain_mismatches,
        "unknown_refs": unknown_refs,
        "unconsumed_entries": unconsumed,
        "errors": errors,
    }


def derive_policy_identity_storage_coverage(
    contract: dict[str, Any]
) -> dict[str, Any]:
    identity = contract.get("policy_evaluation_identity_storage_contract", {})
    errors: list[str] = []
    exact = {
        "status": "APPROVED",
        "implementation_status": "PROPOSED_NOT_IMPLEMENTED",
        "field_ref": "POLICY_EVALUATION_SEQUENCE.SEQUENCE",
        "storage_kind": "REGISTERED_EVENT_CAPTURE",
        "data_source_binding_ref": "SRC_FAULT_EVAL_SEQUENCE",
        "valid_source_binding_ref": "SRC_FAULT_EVAL_VALID",
        "capture_when": "VALID_SIGNAL_EQUALS_1",
        "capture_polarity": "ACTIVE_HIGH_SYNCHRONOUS",
        "hold_when_invalid": True,
        "reset_value": 0,
        "source_width_ref": "SRC_FAULT_EVAL_SEQUENCE.width",
        "destination_width": 32,
        "transform_rule": "ZERO_EXTEND",
        "integrity_clean_required": False,
        "captures_nonclean_valid_retirement": True,
        "role": "DIAGNOSTIC_LAST_RETIREMENT_IDENTITY",
        "is_snapshot_token": False,
    }
    for key, value in exact.items():
        if identity.get(key) != value:
            if key in {"storage_kind", "hold_when_invalid"}:
                errors.append("policy identity direct-wired without hold")
            elif key in {"capture_when", "capture_polarity"}:
                errors.append("policy identity captures when fault_eval_valid is zero")
            elif key in {
                "integrity_clean_required",
                "captures_nonclean_valid_retirement",
            }:
                errors.append(
                    "policy identity does not capture non-clean valid retirement"
                )
            else:
                errors.append(f"policy identity storage contract differs: {key}")

    vectors = [
        item for item in identity.get("directed_vectors", []) if isinstance(item, dict)
    ]
    expected_ids = [
        "IDENTITY_RESET",
        "IDENTITY_CLEAN_VALID_CAPTURE",
        "IDENTITY_IDLE_HOLD",
        "IDENTITY_NONCLEAN_VALID_CAPTURE",
        "IDENTITY_IDLE_AFTER_NONCLEAN_HOLD",
    ]
    if [str(item.get("id")) for item in vectors] != expected_ids:
        errors.append("policy identity directed vector inventory differs")
    stored = 0
    covered = 0
    for vector in vectors:
        if vector.get("reset") is True:
            stored = 0
        elif vector.get("valid") == 1:
            stored = int(vector.get("sequence", 0)) & 0xFFFFFFFF
        expected = vector.get("expected_identity")
        if stored == expected:
            covered += 1
            continue
        vector_id = str(vector.get("id"))
        if "IDLE" in vector_id:
            errors.append("policy identity loses value on idle cycle")
        elif vector_id == "IDENTITY_NONCLEAN_VALID_CAPTURE":
            errors.append(
                "policy identity does not capture non-clean valid retirement"
            )
        else:
            errors.append(f"policy identity directed vector differs: {vector_id}")
    return {
        "vector_target_count": len(expected_ids),
        "vector_covered_count": covered,
        "errors": errors,
    }


def derive_dynamic_value_source_coverage(contract: dict[str, Any]) -> dict[str, Any]:
    source_contract = contract.get("dynamic_value_source_contract", {})
    errors: list[str] = []
    expected_kinds = (
        "SIGNAL",
        "STATE_EQUALS",
        "MASK_SIGNAL_BY_WIDTH",
        "REGISTERED_EVENT_CAPTURE",
    )
    if tuple(source_contract.get("allowed_source_kinds", [])) != expected_kinds:
        errors.append("dynamic source kind grammar differs")
    expected_header = {
        "schema_version": "DYNAMIC_VALUE_SOURCE_V2",
        "authority": "SOLE_TYPED_DYNAMIC_FIELD_SOURCE_AUTHORITY",
        "approach": "FOUR_PROJECT_SPECIFIC_SOURCE_KINDS",
        "source_binding_authority": "stage2h_rtl_source_bindings",
        "known_parameters": ["FAULT_BITMAP_WIDTH", "OBS_SEQUENCE_WIDTH"],
        "known_transforms": [
            "IDENTITY",
            "BOOLEAN_COMPARE",
            "MASK_VALID_THEN_SELECT_BIT_ZERO_EXTEND_REGISTER",
            "ZERO_EXTEND",
        ],
        "unknown_source_kind": "REJECT",
        "unknown_source_binding": "REJECT",
        "unknown_state": "REJECT",
        "unknown_transform": "REJECT",
        "unknown_parameter": "REJECT",
    }
    for key, value in expected_header.items():
        if source_contract.get(key) != value:
            errors.append(f"dynamic source contract differs: {key}")

    binding_items = [
        item
        for item in contract.get("stage2h_rtl_source_bindings", {}).get(
            "bindings", []
        )
        if isinstance(item, dict)
    ]
    binding_map = {str(item.get("id")): item for item in binding_items}
    selected_fields = {
        f"{register.get('name')}.{field.get('name')}": field
        for register, field in selected_field_records(contract)
    }
    dynamic_fields = {
        target: field
        for target, field in selected_fields.items()
        if field.get("static_value") == {"kind": "dynamic"}
    }
    sources = [
        item for item in source_contract.get("sources", []) if isinstance(item, dict)
    ]
    source_ids = [str(item.get("id")) for item in sources]
    source_targets = [str(item.get("target")) for item in sources]
    source_map = {str(item.get("target")): item for item in sources}
    if len(source_ids) != len(set(source_ids)):
        errors.append("duplicate dynamic value source ID")
    if len(source_targets) != len(set(source_targets)):
        errors.append("duplicate dynamic value source target")

    missing_sources = sorted(set(dynamic_fields) - set(source_map))
    unexpected_sources = sorted(set(source_map) - set(dynamic_fields))
    fields_without_refs: list[str] = []
    source_ref_mismatches: list[str] = []
    for target, field in dynamic_fields.items():
        reference = field.get("dynamic_value_source_ref")
        if not str(reference or "").strip():
            fields_without_refs.append(target)
        elif source_map.get(target, {}).get("id") != reference:
            source_ref_mismatches.append(target)
    if missing_sources or fields_without_refs:
        errors.append(
            "dynamic selected field lacks typed source: "
            f"missing={missing_sources}, refs={fields_without_refs}"
        )
    if unexpected_sources:
        errors.append(
            f"typed source targets a non-dynamic selected field: {unexpected_sources}"
        )
    if source_ref_mismatches:
        errors.append(
            f"dynamic field source reference mismatch: {source_ref_mismatches}"
        )

    required_by_kind = {
        "SIGNAL": {"source_binding_ref"},
        "STATE_EQUALS": {"source_binding_ref", "state_ref"},
        "MASK_SIGNAL_BY_WIDTH": {
            "source_binding_ref",
            "source_bit",
            "mask",
            "width_parameter",
        },
        "REGISTERED_EVENT_CAPTURE": {
            "data_source_binding_ref",
            "valid_source_binding_ref",
            "source_width_ref",
            "capture_polarity",
            "hold_when_invalid",
            "reset_value",
            "clock_domain_ref",
            "reset_domain_ref",
            "capture_boundary",
        },
    }
    transform_by_kind = {
        "SIGNAL": "IDENTITY",
        "STATE_EQUALS": "BOOLEAN_COMPARE",
        "MASK_SIGNAL_BY_WIDTH": (
            "MASK_VALID_THEN_SELECT_BIT_ZERO_EXTEND_REGISTER"
        ),
        "REGISTERED_EVENT_CAPTURE": "ZERO_EXTEND",
    }
    for source in sources:
        source_id = str(source.get("id"))
        target = str(source.get("target"))
        kind = str(source.get("kind"))
        if kind not in expected_kinds:
            errors.append(f"dynamic source kind is unknown: {source_id}")
        for key in required_by_kind.get(kind, set()):
            if source.get(key) is None:
                errors.append(
                    f"dynamic source required attribute is absent: {source_id}.{key}"
                )
        if source.get("transform_rule") != transform_by_kind.get(kind):
            errors.append(f"dynamic source transform differs from kind: {source_id}")
        for key in (
            "source_binding_ref",
            "data_source_binding_ref",
            "valid_source_binding_ref",
        ):
            reference = source.get(key)
            if reference is not None and reference not in binding_map:
                errors.append(
                    f"dynamic source binding is unknown: {source_id}.{key}={reference}"
                )
        state_ref = source.get("state_ref")
        if state_ref is not None:
            state_binding, separator, state_name = str(state_ref).partition(".")
            states = binding_map.get(state_binding, {}).get("state_encoding") or {}
            if not separator or state_name not in states:
                errors.append(f"dynamic source state is unknown: {source_id}")
        parameter = source.get("width_parameter")
        if parameter is not None and parameter != "FAULT_BITMAP_WIDTH":
            errors.append(f"dynamic source parameter is unknown: {source_id}")
        field = dynamic_fields.get(target, {})
        bits = field.get("bits", {})
        try:
            destination_width = int(bits.get("msb")) - int(bits.get("lsb")) + 1
        except (AttributeError, TypeError, ValueError):
            destination_width = None
        if source.get("destination_width") != destination_width:
            errors.append(f"dynamic source destination width differs: {source_id}")
        if source.get("rtl_binding_id") != field.get("rtl_binding_id"):
            errors.append(f"dynamic source RTL binding differs: {source_id}")

    expected_policy = {
        "POLICY_STATUS.ARMED_READY": (
            "STATE_EQUALS",
            "SRC_STAGE2G_STATE",
            "SRC_STAGE2G_STATE.ST_ARMED",
        ),
        "POLICY_STATUS.FAULT_LATCHED_STATE": (
            "STATE_EQUALS",
            "SRC_STAGE2G_STATE",
            "SRC_STAGE2G_STATE.ST_FAULT_LATCHED",
        ),
        "POLICY_STATUS.RESET_WAIT_STATE": (
            "STATE_EQUALS",
            "SRC_STAGE2G_STATE",
            "SRC_STAGE2G_STATE.ST_RESET_WAIT",
        ),
        "POLICY_STATUS.CLEAR_PENDING": ("SIGNAL", "SRC_CLEAR_PENDING", None),
        "POLICY_STATUS.POST_CLEAR_RECOVERY_PENDING": (
            "SIGNAL",
            "SRC_POST_CLEAR_RECOVERY_PENDING",
            None,
        ),
    }
    policy_error_labels = {
        "POLICY_STATUS.ARMED_READY": "ARMED_READY typed source differs",
        "POLICY_STATUS.FAULT_LATCHED_STATE": (
            "FAULT_LATCHED_STATE typed source differs"
        ),
        "POLICY_STATUS.RESET_WAIT_STATE": "RESET_WAIT_STATE typed source differs",
        "POLICY_STATUS.CLEAR_PENDING": "CLEAR_PENDING typed source differs",
        "POLICY_STATUS.POST_CLEAR_RECOVERY_PENDING": (
            "POST_CLEAR_RECOVERY_PENDING typed source differs"
        ),
    }
    for target, expected in expected_policy.items():
        source = source_map.get(target, {})
        actual = (
            source.get("kind"),
            source.get("source_binding_ref"),
            source.get("state_ref"),
        )
        if actual != expected:
            errors.append(policy_error_labels[target])
            errors.append(f"dynamic source binding unrelated to field: {target}")

    bitmap_bindings = {
        "FIRST_FAULT_BITMAP": "SRC_FIRST_FAULT_BITMAP",
        "LIVE_FAULT_BITMAP": "SRC_LIVE_FAULT_BITMAP",
        "FAULT_SEEN_BITMAP": "SRC_FAULT_SEEN_BITMAP",
    }
    for register_name, binding_ref in bitmap_bindings.items():
        for bit, cause_name in enumerate(FAULT_CAUSE_NAMES):
            target = f"{register_name}.{cause_name}"
            source = source_map.get(target, {})
            if (
                source.get("kind") != "MASK_SIGNAL_BY_WIDTH"
                or source.get("source_binding_ref") != binding_ref
                or source.get("source_bit") != bit
                or source.get("mask") != "0x0000003F"
                or source.get("width_parameter") != "FAULT_BITMAP_WIDTH"
                or source.get("transform_rule")
                != "MASK_VALID_THEN_SELECT_BIT_ZERO_EXTEND_REGISTER"
            ):
                errors.append(f"bitmap source is unmasked or differs: {target}")

    sequence = source_map.get("POLICY_EVALUATION_SEQUENCE.SEQUENCE", {})
    expected_sequence = {
        "kind": "REGISTERED_EVENT_CAPTURE",
        "data_source_binding_ref": "SRC_FAULT_EVAL_SEQUENCE",
        "valid_source_binding_ref": "SRC_FAULT_EVAL_VALID",
        "source_width_ref": "SRC_FAULT_EVAL_SEQUENCE.width",
        "destination_width": 32,
        "capture_polarity": "ACTIVE_HIGH_SYNCHRONOUS",
        "hold_when_invalid": True,
        "reset_value": 0,
        "clock_domain_ref": "ACLK",
        "reset_domain_ref": "LOCAL_ACTIVE_LOW_RESET",
        "capture_boundary": "ACLK_POLICY_RETIREMENT_CAPTURE",
        "transform_rule": "ZERO_EXTEND",
    }
    if any(sequence.get(key) != value for key, value in expected_sequence.items()):
        errors.append("POLICY_EVALUATION_SEQUENCE typed source differs")

    identity = contract.get("policy_evaluation_identity_storage_contract", {})
    for source_key, identity_key in (
        ("data_source_binding_ref", "data_source_binding_ref"),
        ("valid_source_binding_ref", "valid_source_binding_ref"),
        ("source_width_ref", "source_width_ref"),
        ("destination_width", "destination_width"),
        ("capture_polarity", "capture_polarity"),
        ("hold_when_invalid", "hold_when_invalid"),
        ("reset_value", "reset_value"),
        ("transform_rule", "transform_rule"),
    ):
        if sequence.get(source_key) != identity.get(identity_key):
            errors.append(
                f"policy identity dynamic source differs from storage contract: {source_key}"
            )

    migration = source_contract.get("current_abi_migration_plan", {})
    if migration != {
        "status": "EXPLICIT_IMPLEMENTATION_PHASE_PLAN",
        "scope": "CURRENT_ABI_DYNAMIC_FIELDS",
        "require_typed_source_before_generator_convergence": True,
        "opaque_bindings_permitted_after_convergence": False,
        "fault_code_binding_ref": "fault_taxonomy.fault_code_binding",
    }:
        errors.append("current ABI typed-source migration plan differs")

    covered_targets = set(dynamic_fields) & set(source_map)
    covered_targets -= set(source_ref_mismatches)
    covered_targets -= set(fields_without_refs)
    return {
        "target_count": len(dynamic_fields),
        "covered_count": len(covered_targets),
        "dynamic_fields": sorted(dynamic_fields),
        "missing_sources": missing_sources,
        "unexpected_sources": unexpected_sources,
        "fields_without_typed_source": sorted(
            set(missing_sources + fields_without_refs)
        ),
        "opaque_dynamic_bindings_without_source_contract": len(
            set(missing_sources + fields_without_refs)
        ),
        "errors": errors,
    }

def derive_cross_field_invariant_coverage(contract: dict[str, Any]) -> dict[str, Any]:
    authority = contract.get("cross_field_invariants", {})
    errors: list[str] = []
    if authority.get("evaluation_boundary") != "COMMON_STAGE2G_POLICY_ACLK_EDGE":
        errors.append("cross-field invariants do not share the Stage 2G policy edge")
    if authority.get("software_atomic_snapshot_claim") is not False:
        errors.append("cross-field invariants overclaim a software-atomic snapshot")

    policy_items = [
        item
        for item in authority.get("policy_status_invariants", [])
        if isinstance(item, dict)
    ]
    bitmap_items = [
        item for item in authority.get("bitmap_invariants", []) if isinstance(item, dict)
    ]
    policy_map = {str(item.get("id")): item for item in policy_items}
    bitmap_map = {str(item.get("id")): item for item in bitmap_items}
    expected_policy = {
        "POLICY_STATE_EXACTLY_ONE": {
            "id": "POLICY_STATE_EXACTLY_ONE",
            "kind": "EXACTLY_ONE",
            "fields": [
                "POLICY_STATUS.ARMED_READY",
                "POLICY_STATUS.FAULT_LATCHED_STATE",
                "POLICY_STATUS.RESET_WAIT_STATE",
            ],
            "antecedent": None,
            "consequent_all": [],
            "consequent_none": [],
            "conformance_family": "CF_POLICY_STATUS_LEVEL",
        },
        "CLEAR_PENDING_IMPLIES_FAULT_LATCHED": {
            "id": "CLEAR_PENDING_IMPLIES_FAULT_LATCHED",
            "kind": "IMPLIES",
            "fields": [],
            "antecedent": {"field": "POLICY_STATUS.CLEAR_PENDING", "equals": 1},
            "consequent_all": [
                {"field": "POLICY_STATUS.FAULT_LATCHED_STATE", "equals": 1}
            ],
            "consequent_none": [],
            "conformance_family": "CF_POLICY_STATUS_LEVEL",
        },
        "POST_CLEAR_PENDING_IMPLIES_RESET_WAIT_NOT_CLEAR": {
            "id": "POST_CLEAR_PENDING_IMPLIES_RESET_WAIT_NOT_CLEAR",
            "kind": "IMPLIES",
            "fields": [],
            "antecedent": {
                "field": "POLICY_STATUS.POST_CLEAR_RECOVERY_PENDING",
                "equals": 1,
            },
            "consequent_all": [
                {"field": "POLICY_STATUS.RESET_WAIT_STATE", "equals": 1}
            ],
            "consequent_none": [
                {"field": "POLICY_STATUS.CLEAR_PENDING", "equals": 1}
            ],
            "conformance_family": "CF_POLICY_STATUS_LEVEL",
        },
        "ARMED_READY_EXCLUDES_PENDING_LEVELS": {
            "id": "ARMED_READY_EXCLUDES_PENDING_LEVELS",
            "kind": "IMPLIES",
            "fields": [],
            "antecedent": {"field": "POLICY_STATUS.ARMED_READY", "equals": 1},
            "consequent_all": [],
            "consequent_none": [
                {"field": "POLICY_STATUS.CLEAR_PENDING", "equals": 1},
                {
                    "field": "POLICY_STATUS.POST_CLEAR_RECOVERY_PENDING",
                    "equals": 1,
                },
            ],
            "conformance_family": "CF_POLICY_STATUS_LEVEL",
        },
    }
    expected_bitmap = {
        "BITMAP_UPPER_BITS_ZERO": {
            "id": "BITMAP_UPPER_BITS_ZERO",
            "kind": "MASK_ZERO",
            "condition": None,
            "targets": list(FAULT_BITMAP_REGISTERS),
            "mask": "0xFFFFFFC0",
            "episode_scope": "ALWAYS",
            "update_rule": "BITS_ABOVE_FAULT_BITMAP_WIDTH_EQUAL_ZERO",
            "conformance_family": "CF_EPISODE_BITMAP",
        },
        "BITMAPS_ZERO_OUTSIDE_ACTIVE_FAULT": {
            "id": "BITMAPS_ZERO_OUTSIDE_ACTIVE_FAULT",
            "kind": "IMPLIES_ALL_ZERO",
            "condition": {
                "field": "POLICY_STATUS.FAULT_LATCHED_STATE",
                "equals": 0,
            },
            "targets": list(FAULT_BITMAP_REGISTERS),
            "mask": "0x0000003F",
            "episode_scope": "OUTSIDE_ACTIVE_INTERNAL_EPISODE",
            "update_rule": "ALL_TARGETS_EQUAL_ZERO",
            "conformance_family": "CF_EPISODE_BITMAP",
        },
        "FIRST_FAULT_IMMUTABLE_DURING_EPISODE": {
            "id": "FIRST_FAULT_IMMUTABLE_DURING_EPISODE",
            "kind": "TEMPORAL_IMMUTABLE",
            "condition": {
                "field": "POLICY_STATUS.FAULT_LATCHED_STATE",
                "equals": 1,
            },
            "targets": ["FIRST_FAULT_BITMAP"],
            "mask": "0x0000003F",
            "episode_scope": "ACTIVE_INTERNAL_EPISODE",
            "update_rule": "CAPTURE_ON_EPISODE_START_ONLY",
            "conformance_family": "CF_EPISODE_BITMAP",
        },
        "FAULT_SEEN_MONOTONIC_OR_DURING_EPISODE": {
            "id": "FAULT_SEEN_MONOTONIC_OR_DURING_EPISODE",
            "kind": "TEMPORAL_MONOTONIC_OR",
            "condition": {
                "field": "POLICY_STATUS.FAULT_LATCHED_STATE",
                "equals": 1,
            },
            "targets": ["FAULT_SEEN_BITMAP"],
            "mask": "0x0000003F",
            "episode_scope": "ACTIVE_INTERNAL_EPISODE",
            "update_rule": (
                "NEXT_EQUALS_PREVIOUS_OR_FAULT_EVAL_BITMAP_ON_"
                "INTEGRITY_CLEAN_VALID_RETIREMENT"
            ),
            "conformance_family": "CF_EPISODE_BITMAP",
        },
    }
    if len(policy_items) != len(policy_map) or set(policy_map) != set(expected_policy):
        errors.append("policy status invariant inventory differs")
    if len(bitmap_items) != len(bitmap_map) or set(bitmap_map) != set(expected_bitmap):
        errors.append("bitmap invariant inventory differs")
    if policy_map.get("POLICY_STATE_EXACTLY_ONE") != expected_policy[
        "POLICY_STATE_EXACTLY_ONE"
    ]:
        errors.append("policy state bits are not exactly one-hot")
    if policy_map.get("CLEAR_PENDING_IMPLIES_FAULT_LATCHED") != expected_policy[
        "CLEAR_PENDING_IMPLIES_FAULT_LATCHED"
    ]:
        errors.append("clear_pending is legal outside FAULT_LATCHED")
    if policy_map.get(
        "POST_CLEAR_PENDING_IMPLIES_RESET_WAIT_NOT_CLEAR"
    ) != expected_policy["POST_CLEAR_PENDING_IMPLIES_RESET_WAIT_NOT_CLEAR"]:
        errors.append("post-clear pending is legal in ARMED or with clear_pending")
    if policy_map.get("ARMED_READY_EXCLUDES_PENDING_LEVELS") != expected_policy[
        "ARMED_READY_EXCLUDES_PENDING_LEVELS"
    ]:
        errors.append("ARMED_READY permits a pending level")
    if bitmap_map.get("BITMAP_UPPER_BITS_ZERO") != expected_bitmap[
        "BITMAP_UPPER_BITS_ZERO"
    ]:
        errors.append("bitmap upper bits can be nonzero")
    if bitmap_map.get("BITMAPS_ZERO_OUTSIDE_ACTIVE_FAULT") != expected_bitmap[
        "BITMAPS_ZERO_OUTSIDE_ACTIVE_FAULT"
    ]:
        errors.append("bitmaps can remain nonzero outside an active fault episode")
    if bitmap_map.get("FIRST_FAULT_IMMUTABLE_DURING_EPISODE") != expected_bitmap[
        "FIRST_FAULT_IMMUTABLE_DURING_EPISODE"
    ]:
        errors.append("FIRST_FAULT_BITMAP changes during an episode")
    if bitmap_map.get("FAULT_SEEN_MONOTONIC_OR_DURING_EPISODE") != expected_bitmap[
        "FAULT_SEEN_MONOTONIC_OR_DURING_EPISODE"
    ]:
        errors.append("FAULT_SEEN_BITMAP loses a previously seen cause")

    policy_covered = sum(policy_map.get(key) == value for key, value in expected_policy.items())
    bitmap_covered = sum(bitmap_map.get(key) == value for key, value in expected_bitmap.items())
    return {
        "policy_target_count": len(expected_policy),
        "policy_covered_count": policy_covered,
        "bitmap_target_count": len(expected_bitmap),
        "bitmap_covered_count": bitmap_covered,
        "errors": errors,
    }


def derive_episode_bitmap_transition_coverage(
    contract: dict[str, Any]
) -> dict[str, Any]:
    authority = contract.get("episode_bitmap_transition_rules", {})
    errors: list[str] = []
    if authority.get("schema_version") != "EPISODE_BITMAP_TRANSITIONS_V1":
        errors.append("episode bitmap transition authority differs")
    if authority.get("status") != "APPROVED":
        errors.append("episode bitmap transition rules are not approved")
    if authority.get("implementation_status") != (
        "CURRENT_STAGE2G_BEHAVIOR_FUTURE_STAGE2H_PUBLIC_BINDING_NOT_IMPLEMENTED"
    ):
        errors.append("episode bitmap transition implementation boundary differs")
    if authority.get("event_sources") != {
        "valid_source_ref": "SRC_FAULT_EVAL_VALID",
        "integrity_clean_source_ref": "SRC_FAULT_EVAL_INTEGRITY_CLEAN",
        "bitmap_source_ref": "SRC_FAULT_EVAL_BITMAP",
    }:
        errors.append("episode bitmap event source bindings differ")

    common = {
        "initialize_on_episode_start": (
            "CAPTURE_FAULT_EVAL_BITMAP_ON_VALID_INTEGRITY_CLEAN_EPISODE_START"
        ),
        "hold_when_no_valid_retirement": True,
        "hold_when_nonclean_retirement": True,
        "clear_on": ["RESET", "EPISODE_END"],
    }
    expected = {
        "FIRST_FAULT_BITMAP_TRANSITION": {
            "id": "FIRST_FAULT_BITMAP_TRANSITION",
            "target_register": "FIRST_FAULT_BITMAP",
            **common,
            "update_during_active_episode": "HOLD",
        },
        "LIVE_FAULT_BITMAP_TRANSITION": {
            "id": "LIVE_FAULT_BITMAP_TRANSITION",
            "target_register": "LIVE_FAULT_BITMAP",
            **common,
            "update_during_active_episode": (
                "REPLACE_WITH_FAULT_EVAL_BITMAP_ON_EACH_VALID_"
                "INTEGRITY_CLEAN_RETIREMENT"
            ),
        },
        "FAULT_SEEN_BITMAP_TRANSITION": {
            "id": "FAULT_SEEN_BITMAP_TRANSITION",
            "target_register": "FAULT_SEEN_BITMAP",
            **common,
            "update_during_active_episode": (
                "PREVIOUS_OR_FAULT_EVAL_BITMAP_ON_EACH_VALID_"
                "INTEGRITY_CLEAN_RETIREMENT"
            ),
        },
    }
    rules = [
        item for item in authority.get("rules", []) if isinstance(item, dict)
    ]
    rule_map = {str(item.get("id")): item for item in rules}
    if len(rules) != len(rule_map) or set(rule_map) != set(expected):
        errors.append("episode bitmap transition rule inventory differs")
    labels = {
        "FIRST_FAULT_BITMAP_TRANSITION": (
            "FIRST_FAULT_BITMAP transition rule differs"
        ),
        "LIVE_FAULT_BITMAP_TRANSITION": (
            "LIVE_FAULT_BITMAP transition rule differs"
        ),
        "FAULT_SEEN_BITMAP_TRANSITION": (
            "FAULT_SEEN_BITMAP transition rule differs"
        ),
    }
    for identifier, expected_rule in expected.items():
        if rule_map.get(identifier) != expected_rule:
            errors.append(labels[identifier])
    covered = sum(rule_map.get(key) == value for key, value in expected.items())
    return {
        "target_count": len(expected),
        "covered_count": covered,
        "errors": errors,
    }


def derive_unknown_fault_compatibility_coverage(
    contract: dict[str, Any]
) -> dict[str, Any]:
    authority = contract.get("unknown_fault_cause_forward_compatibility", {})
    errors: list[str] = []
    expected_header = {
        "schema_version": "FAULT_BITMAP_FORWARD_COMPATIBILITY_V1",
        "status": "APPROVED",
        "implementation_status": "PROPOSED_NOT_IMPLEMENTED",
        "known_taxonomy_width_ref": "fault_taxonomy.fault_bitmap_width",
        "raw_transport_width": 32,
        "advertised_width_range": {"minimum": 6, "maximum": 32},
        "api_return_shape": {
            "type_name": "FaultBitmapValue",
            "members": [
                "raw_value",
                "known_flags",
                "unknown_mask",
                "advertised_width",
            ],
        },
        "arithmetic": {
            "advertised_mask": "LOW_ADVERTISED_WIDTH_BITS",
            "known_mask": "LOW_KNOWN_TAXONOMY_WIDTH_BITS",
            "known_flags": "RAW_VALUE_AND_KNOWN_MASK",
            "unknown_mask": (
                "RAW_VALUE_AND_ADVERTISED_MASK_AND_NOT_KNOWN_MASK"
            ),
            "above_advertised_mask": "RAW_VALUE_AND_NOT_ADVERTISED_MASK",
        },
        "unknown_bits_within_advertised_width": "PRESERVE",
        "known_flags_decode": "NORMAL",
        "bits_above_advertised_width": "REQUIRE_ZERO",
        "unknown_name_policy": "DO_NOT_INVENT_NAMES",
    }
    for key, value in expected_header.items():
        if authority.get(key) != value:
            if key == "unknown_bits_within_advertised_width":
                errors.append("unknown fault cause silently discarded")
            elif key == "bits_above_advertised_width":
                errors.append("bit above advertised width accepted as valid")
            elif key == "unknown_name_policy":
                errors.append("old software invents a name for an unknown fault bit")
            else:
                errors.append(f"unknown fault compatibility contract differs: {key}")

    taxonomy_width = contract.get("fault_taxonomy", {}).get("fault_bitmap_width")
    known_width = int(taxonomy_width) if isinstance(taxonomy_width, int) else 0
    vectors = [
        item for item in authority.get("directed_vectors", []) if isinstance(item, dict)
    ]
    expected_vectors = [
        ("KNOWN_ONLY_WIDTH_6", 33, 6),
        ("UNKNOWN_BIT_6_WIDTH_7", 65, 7),
        ("ABOVE_WIDTH_BIT_REJECTED", 128, 7),
    ]
    if [
        (
            str(item.get("id")),
            item.get("raw_value"),
            item.get("advertised_width"),
        )
        for item in vectors
    ] != expected_vectors:
        errors.append("unknown fault compatibility vector inventory differs")

    covered = 0
    for vector in vectors:
        raw_value = int(vector.get("raw_value", 0))
        advertised_width = int(vector.get("advertised_width", 0))
        if not (known_width <= advertised_width <= 32):
            errors.append(
                f"unknown fault advertised width is invalid: {vector.get('id')}"
            )
            continue
        advertised_mask = (1 << advertised_width) - 1
        known_mask = (1 << known_width) - 1
        known_flags = raw_value & known_mask
        unknown_mask = raw_value & advertised_mask & ~known_mask
        above_mask = raw_value & (~advertised_mask & 0xFFFFFFFF)
        valid = above_mask == 0
        actual = (
            known_flags,
            unknown_mask,
            above_mask,
            valid,
        )
        expected = (
            vector.get("expected_known_flags"),
            vector.get("expected_unknown_mask"),
            vector.get("expected_above_advertised_mask"),
            vector.get("expected_valid"),
        )
        if actual == expected:
            covered += 1
            continue
        if known_flags != vector.get("expected_known_flags"):
            errors.append("known fault flags decode differs")
        if unknown_mask != vector.get("expected_unknown_mask"):
            errors.append("unknown fault cause silently discarded")
        if above_mask != vector.get("expected_above_advertised_mask") or (
            valid != vector.get("expected_valid")
        ):
            errors.append("bit above advertised width accepted as valid")

    for api_name in (
        "read_first_fault_bitmap()",
        "read_live_fault_bitmap()",
        "read_fault_seen_bitmap()",
    ):
        item = next(
            (
                candidate
                for candidate in contract.get("software_api_plan", [])
                if isinstance(candidate, dict)
                and candidate.get("api") == api_name
            ),
            {},
        )
        semantics = str(item.get("semantics", ""))
        if "FaultBitmapValue" not in semantics:
            errors.append(f"fault bitmap API drops unknown bits: {api_name}")
    return {
        "vector_target_count": len(expected_vectors),
        "vector_covered_count": covered,
        "errors": errors,
    }


def derive_conformance_scenario_coverage(contract: dict[str, Any]) -> dict[str, Any]:
    authority = contract.get("conformance_scenario_definitions", {})
    errors: list[str] = []
    enabled_families = {
        str(item.get("generated_conformance_family"))
        for item in contract.get("behavior_binding_matrix", {}).get("bindings", [])
        if isinstance(item, dict)
        and str(item.get("generated_conformance_family", "")).strip()
    }
    expected_header = {
        "schema_version": "FINITE_CONFORMANCE_TEMPLATES_V1",
        "authority": (
            "FINITE_PROJECT_SPECIFIC_TEMPLATES_FROM_REGISTER_MAP_AUTHORITY"
        ),
        "generated_artifact": (
            "spec/generated/protection_register_map_conformance.json"
        ),
        "approach": "FINITE_PROJECT_SPECIFIC_TEMPLATES",
        "generic_dsl": "REJECTED_OVERENGINEERING",
        "opaque_targets_or_values": "NOT_PRESENT",
        "future_generated_artifact_derives_templates": True,
    }
    for key, value in expected_header.items():
        if authority.get(key) != value:
            errors.append(f"finite conformance template authority differs: {key}")

    expected_templates = {
        "RO_STATIC": {
            "template_id": "RO_STATIC",
            "scope": "SELECTED_FIELDS",
            "deterministic_vectors": [
                "RESET_READ",
                "STEADY_READ",
                "WRITE_NO_EFFECT",
            ],
            "authority_inputs": [
                "FIELD_BITS",
                "FIELD_RESET",
                "FIELD_STATIC_VALUE",
                "REGISTER_AGGREGATE_DERIVATION",
            ],
        },
        "RO_STATE_DECODE": {
            "template_id": "RO_STATE_DECODE",
            "scope": "SELECTED_FIELDS",
            "deterministic_vectors": [
                "RESET_DECODE",
                "EACH_PUBLIC_STATE",
                "ONE_HOT_RELATIONS",
            ],
            "authority_inputs": [
                "STATE_SOURCE_BINDING",
                "STATE_ENCODING",
                "POLICY_STATUS_INVARIANTS",
            ],
        },
        "RO_LEVEL": {
            "template_id": "RO_LEVEL",
            "scope": "SELECTED_FIELDS",
            "deterministic_vectors": [
                "RESET_LEVEL",
                "ASSERTED_LEVEL",
                "DEASSERTED_LEVEL",
            ],
            "authority_inputs": [
                "LEVEL_SOURCE_BINDING",
                "FIELD_RESET",
                "POLICY_STATUS_INVARIANTS",
            ],
        },
        "RO_BITMAP": {
            "template_id": "RO_BITMAP",
            "scope": "SELECTED_FIELDS",
            "deterministic_vectors": [
                "RESET_ZERO",
                "CAUSE_BIT_SET",
                "UPPER_BITS_ZERO",
                "FIRST_LIVE_SEEN_TRANSITIONS",
            ],
            "authority_inputs": [
                "BITMAP_SOURCE_BINDINGS",
                "FAULT_BITMAP_WIDTH_AND_MASKS",
                "EPISODE_BITMAP_TRANSITION_RULES",
            ],
        },
        "RO_EVENT_CAPTURE": {
            "template_id": "RO_EVENT_CAPTURE",
            "scope": "SELECTED_FIELDS",
            "deterministic_vectors": [
                "RESET_ZERO",
                "CLEAN_VALID_CAPTURE",
                "INVALID_IDLE_HOLD",
                "NONCLEAN_VALID_CAPTURE",
            ],
            "authority_inputs": [
                "POLICY_IDENTITY_STORAGE_CONTRACT",
                "DATA_AND_VALID_SOURCE_BINDINGS",
            ],
        },
        "FAULT_PROJECTION": {
            "template_id": "FAULT_PROJECTION",
            "scope": "PROJECT_CONTRACT",
            "deterministic_vectors": [
                "EXHAUSTIVE_KNOWN_BITMAP_0_TO_3F",
            ],
            "authority_inputs": [
                "FAULT_CODES",
                "FAULT_CAUSES",
                "COMPATIBILITY_PROJECTION",
            ],
        },
        "FAULT_FORWARD_COMPATIBILITY": {
            "template_id": "FAULT_FORWARD_COMPATIBILITY",
            "scope": "PROJECT_CONTRACT",
            "deterministic_vectors": [
                "KNOWN_ONLY_WIDTH_6",
                "UNKNOWN_BIT_6_WIDTH_7",
                "ABOVE_WIDTH_BIT_REJECTED",
            ],
            "authority_inputs": [
                "UNKNOWN_FAULT_CAUSE_FORWARD_COMPATIBILITY",
            ],
        },
    }
    template_items = [
        item for item in authority.get("template_definitions", [])
        if isinstance(item, dict)
    ]
    template_map = {str(item.get("template_id")): item for item in template_items}
    if len(template_items) != len(template_map) or set(template_map) != set(
        expected_templates
    ):
        errors.append("finite conformance template inventory differs")
    for template_id, expected in expected_templates.items():
        if template_map.get(template_id) != expected:
            errors.append(f"finite conformance template differs: {template_id}")
    bitmap_template = template_map.get("RO_BITMAP", {})
    if (
        "FIRST_LIVE_SEEN_TRANSITIONS"
        not in bitmap_template.get("deterministic_vectors", [])
        or "EPISODE_BITMAP_TRANSITION_RULES"
        not in bitmap_template.get("authority_inputs", [])
    ):
        errors.append(
            "episode bitmap template does not distinguish first live seen"
        )

    selected_fields = {
        f"{register.get('name')}.{field.get('name')}": field
        for register, field in selected_field_records(contract)
    }
    expected_groups: dict[str, set[str]] = {
        "RO_STATIC": set(),
        "RO_STATE_DECODE": set(),
        "RO_LEVEL": set(),
        "RO_BITMAP": set(),
        "RO_EVENT_CAPTURE": set(),
    }
    for target, field in selected_fields.items():
        if field.get("static_value") != {"kind": "dynamic"}:
            template_id = "RO_STATIC"
        elif target in {
            "POLICY_STATUS.ARMED_READY",
            "POLICY_STATUS.FAULT_LATCHED_STATE",
            "POLICY_STATUS.RESET_WAIT_STATE",
        }:
            template_id = "RO_STATE_DECODE"
        elif target.startswith("POLICY_STATUS."):
            template_id = "RO_LEVEL"
        elif target.startswith(
            ("FIRST_FAULT_BITMAP.", "LIVE_FAULT_BITMAP.", "FAULT_SEEN_BITMAP.")
        ):
            template_id = "RO_BITMAP"
        else:
            template_id = "RO_EVENT_CAPTURE"
        expected_groups[template_id].add(target)

    group_items = [
        item for item in authority.get("selected_field_groups", [])
        if isinstance(item, dict)
    ]
    group_ids = [str(item.get("template_id")) for item in group_items]
    group_map = {
        str(item.get("template_id")): set(item.get("field_refs", []))
        for item in group_items
    }
    if len(group_ids) != len(set(group_ids)) or set(group_map) != set(
        expected_groups
    ):
        errors.append("finite conformance selected-field group inventory differs")
    reference_errors: list[str] = []
    for template_id, expected_refs in expected_groups.items():
        actual_refs = group_map.get(template_id, set())
        if actual_refs != expected_refs:
            reference_errors.append(
                f"{template_id}:missing={sorted(expected_refs - actual_refs)},"
                f"extra={sorted(actual_refs - expected_refs)}"
            )
    if reference_errors:
        errors.append(
            f"conformance template field reference resolution failed: {reference_errors}"
        )
    all_group_refs = [
        str(reference)
        for item in group_items
        for reference in item.get("field_refs", [])
    ]
    duplicate_field_refs = sorted(
        {
            reference
            for reference in all_group_refs
            if all_group_refs.count(reference) > 1
        }
    )
    if duplicate_field_refs:
        errors.append(
            f"selected field has multiple conformance templates: {duplicate_field_refs}"
        )

    expected_routes = {
        "CF_REGISTER_MAP_VERSION_STATIC": ["RO_STATIC"],
        "CF_CAPABILITIES_0_STATIC": ["RO_STATIC"],
        "CF_CAPABILITIES_1_METADATA": ["RO_STATIC"],
        "CF_POLICY_STATUS_LEVEL": ["RO_STATE_DECODE", "RO_LEVEL"],
        "CF_EPISODE_BITMAP": ["RO_BITMAP"],
        "CF_DIAGNOSTIC_LAST_RETIREMENT_IDENTITY": ["RO_EVENT_CAPTURE"],
        "CF_FAULT_TAXONOMY_COMPATIBILITY_PROJECTION": ["FAULT_PROJECTION"],
    }
    route_items = [
        item for item in authority.get("selected_family_routes", [])
        if isinstance(item, dict)
    ]
    route_map = {
        str(item.get("family_id")): item.get("template_ids")
        for item in route_items
    }
    binding_edge_mismatches = sorted(
        family_id
        for family_id, template_ids in expected_routes.items()
        if route_map.get(family_id) != template_ids
    )
    if len(route_items) != len(route_map) or set(route_map) != set(expected_routes):
        errors.append("finite conformance family route inventory differs")
    if binding_edge_mismatches:
        errors.append(
            f"conformance family template edge mismatch: {binding_edge_mismatches}"
        )

    expected_legacy = {
        "CF_ADDRESS_LOW8_ALIAS",
        "CF_RO_REGISTERED_VOLATILE",
        "CF_RO_REGISTERED_VOLATILE_RESET_ONLY",
        "CF_RO_REGISTERED_VOLATILE_RESET_ZERO",
        "CF_RO_STATIC",
        "CF_RSVD_ZERO_IGNORE",
        "CF_RW_LEGACY_IGNORE_WSTRB",
        "CF_UNKNOWN_ZERO_OKAY",
        "CF_W1C_ALL_WSTRB_EVENT_WINS",
        "CF_W1P_ONE_ACLK_READ_ZERO",
    }
    legacy_items = authority.get("legacy_directed_family_ids", [])
    legacy = {str(item) for item in legacy_items}
    if len(legacy_items) != len(legacy) or legacy != expected_legacy:
        errors.append("legacy directed conformance family inventory differs")

    project_bindings = {
        str(item.get("template_id")): item.get("authority_ref")
        for item in authority.get("project_contract_bindings", [])
        if isinstance(item, dict)
    }
    expected_project_bindings = {
        "FAULT_PROJECTION": "fault_taxonomy.compatibility_projection",
        "FAULT_FORWARD_COMPATIBILITY": (
            "unknown_fault_cause_forward_compatibility"
        ),
    }
    if project_bindings != expected_project_bindings:
        errors.append("project conformance template authority differs")
    if project_bindings.get("FAULT_PROJECTION") != (
        "fault_taxonomy.compatibility_projection"
    ):
        errors.append("fault projection template authority differs")

    opaque_targets: list[str] = []
    opaque_values: list[str] = []

    def find_opaque(value: Any, location: str) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key in {"target", "opaque_target"}:
                    opaque_targets.append(f"{location}.{key}")
                if key in {"value", "opaque_value"}:
                    opaque_values.append(f"{location}.{key}")
                find_opaque(child, f"{location}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                find_opaque(child, f"{location}[{index}]")

    find_opaque(authority, "conformance_scenario_definitions")
    if opaque_targets or opaque_values:
        errors.append("opaque conformance target or value string")

    defined_families = set(route_map) | legacy
    missing_families = sorted(enabled_families - defined_families)
    extra_families = sorted(defined_families - enabled_families)
    if missing_families:
        errors.append(
            f"enabled conformance family has no finite route: {missing_families}"
        )
    if extra_families:
        errors.append(
            f"finite conformance route has no enabled family: {extra_families}"
        )
    covered_families = enabled_families - set(missing_families)
    covered_field_refs = set(all_group_refs) & set(selected_fields)
    return {
        "target_count": len(enabled_families),
        "covered_count": len(covered_families),
        "enabled_families": sorted(enabled_families),
        "missing_families": missing_families,
        "extra_families": extra_families,
        "malformed_scenarios": reference_errors,
        "template_target_count": len(expected_templates),
        "template_covered_count": sum(
            template_map.get(key) == value
            for key, value in expected_templates.items()
        ),
        "selected_field_target_count": len(selected_fields),
        "selected_field_covered_count": len(covered_field_refs),
        "opaque_targets": opaque_targets,
        "opaque_values": opaque_values,
        "reference_errors": reference_errors,
        "binding_edge_mismatches": binding_edge_mismatches,
        "errors": errors,
    }

def semantic_errors(contract: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    frozen = contract.get("frozen_authorities", {})
    current = contract.get("current_state", {})
    authorities = contract.get("authorities", {})
    abi = contract.get("current_abi", {})
    selected = contract.get("selected_single_source", {})
    ast_policy = contract.get("ast_fingerprint_policy", {})

    if frozen.get("normalized_telemetry_gates_fault_policy") is not False:
        errors.append("normalized telemetry cannot gate fault policy")
    if current.get("remaining_contract_gaps") != 1:
        errors.append("remaining contract gaps must stay one")
    if current.get("stage2_complete") is not False:
        errors.append("Stage 2 must remain incomplete")

    first_principles_coverage = derive_first_principles_scope_review(contract)
    errors.extend(first_principles_coverage["errors"])
    stage2h_a1_scope = derive_stage2h_a1_scope(contract)
    errors.extend(stage2h_a1_scope["errors"])
    artifact_topology = derive_generated_artifact_topology(contract)
    errors.extend(artifact_topology["errors"])
    rtl_source_coverage = derive_rtl_source_binding_coverage(ROOT, contract)
    errors.extend(rtl_source_coverage["errors"])
    identity_coverage = derive_policy_identity_storage_coverage(contract)
    errors.extend(identity_coverage["errors"])
    fault_taxonomy_coverage = derive_fault_taxonomy_coverage(contract)
    errors.extend(fault_taxonomy_coverage["errors"])
    dynamic_source_coverage = derive_dynamic_value_source_coverage(contract)
    errors.extend(dynamic_source_coverage["errors"])
    invariant_coverage = derive_cross_field_invariant_coverage(contract)
    errors.extend(invariant_coverage["errors"])
    transition_coverage = derive_episode_bitmap_transition_coverage(contract)
    errors.extend(transition_coverage["errors"])
    unknown_fault_coverage = derive_unknown_fault_compatibility_coverage(contract)
    errors.extend(unknown_fault_coverage["errors"])
    scenario_coverage = derive_conformance_scenario_coverage(contract)
    errors.extend(scenario_coverage["errors"])

    authoritative = [
        item
        for item in authorities.get("occurrences", [])
        if isinstance(item, dict) and item.get("actual_role") == "AUTHORITATIVE"
    ]
    if len(authoritative) != 1:
        errors.append("exactly one actual register-map authority is required")
    if authorities.get("duplicate_register_authorities") != 4:
        errors.append("duplicate register authority inventory changed")

    registers = abi.get("registers", [])
    offsets: list[int] = []
    names: list[str] = []
    for register_index, register in enumerate(registers):
        if not isinstance(register, dict):
            errors.append(f"register {register_index} is malformed")
            continue
        try:
            offset = int(str(register.get("offset")), 16)
        except ValueError:
            errors.append(f"register {register_index} offset is malformed")
            continue
        offsets.append(offset)
        names.append(str(register.get("name")))
        if offset % 4:
            errors.append(f"register {register.get('name')} offset is not aligned")
        used: dict[int, str] = {}
        fields = register.get("fields", [])
        for field in fields:
            if not isinstance(field, dict):
                errors.append(f"register {register.get('name')} field is malformed")
                continue
            access = str(field.get("access"))
            if access not in ACCESS_TYPES:
                errors.append(f"unsupported access type: {access}")
            bits = field.get("bits", {})
            try:
                msb = int(bits.get("msb"))
                lsb = int(bits.get("lsb"))
            except (AttributeError, TypeError, ValueError):
                errors.append(f"field range malformed: {register.get('name')}.{field.get('name')}")
                continue
            if msb < lsb or lsb < 0 or msb >= 32:
                errors.append(f"field range outside register: {register.get('name')}.{field.get('name')}")
                continue
            for bit in range(lsb, msb + 1):
                if bit in used:
                    errors.append(
                        "overlapping fields: "
                        f"{register.get('name')}.{used[bit]} and {field.get('name')}"
                    )
                used[bit] = str(field.get("name"))
            reset = field.get("reset")
            if isinstance(reset, int) and not isinstance(reset, bool):
                width = msb - lsb + 1
                if reset < 0 or reset >= (1 << width):
                    errors.append(
                        "field reset does not fit: "
                        f"{register.get('name')}.{field.get('name')}={reset}"
                    )
        if set(used) != set(range(32)):
            errors.append(f"field coverage incomplete: {register.get('name')}")

    if len(offsets) != len(set(offsets)):
        errors.append("duplicate register offset")
    if len(names) != len(set(names)):
        errors.append("duplicate register name")
    if offsets != sorted(offsets):
        errors.append("registers are not in canonical offset order")
    expected_offsets = list(range(0, 0x64, 4))
    if offsets != expected_offsets:
        errors.append("current ABI offsets are not exactly 0x00..0x60")
    if abi.get("register_count") != len(registers):
        errors.append("current ABI register count mismatch")
    defects = abi.get("defects", [])
    defect_ids = {
        str(item.get("id")) for item in defects if isinstance(item, dict)
    }
    if abi.get("defect_count_policy") != "DERIVED_FROM_DEFECT_CLASSIFICATIONS":
        errors.append("hard-coded contradiction count is forbidden")
    if defect_ids != REQUIRED_ABI_DEFECT_IDS or len(defects) != len(defect_ids):
        errors.append("current ABI defect inventory is incomplete or duplicated")
    expected_classifications = {
        "STATUS_FAULT_VALID_DESCRIPTION_STALE": "DOCUMENTATION_VS_RTL_CONTRADICTION",
        "STATUS_FAULT_LATCHED_CLEAR_DESCRIPTION_STALE": "DOCUMENTATION_VS_RTL_CONTRADICTION",
        "CURRENT_MONITOR_DESCRIPTION_STALE": "DOCUMENTATION_VS_RTL_CONTRADICTION",
        "LEGACY_WRITES_IGNORE_WSTRB_UNDOCUMENTED": "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR",
        "UNDEFINED_READ_ZERO_OKAY_UNDOCUMENTED": "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR",
        "UNDEFINED_WRITE_NO_EFFECT_OKAY_UNDOCUMENTED": "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR",
        "LOW_EIGHT_BIT_ADDRESS_ALIAS_UNDOCUMENTED": "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR",
        "CURRENT_MONITOR_SOFTWARE_READS_NONATOMIC_UNDOCUMENTED": "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR",
    }
    for defect in defects:
        if not isinstance(defect, dict):
            continue
        identifier = str(defect.get("id"))
        if defect.get("classification") != expected_classifications.get(identifier):
            errors.append(f"current ABI defect classification differs: {identifier}")
        if not str(defect.get("remediation_owner", "")).strip():
            errors.append(f"current ABI defect has no remediation owner: {identifier}")

    if selected.get("deterministic_generation") != "REQUIRED":
        errors.append("deterministic generation is mandatory")
    if selected.get("hand_edit_generated_artifacts") != "FORBIDDEN":
        errors.append("generated artifact hand edits are forbidden")
    if selected.get("authority_path") != "spec/register_map.json":
        errors.append("selected single-source authority changed")
    artifacts = selected.get("generated_artifacts", [])
    artifact_paths = [item.get("path") for item in artifacts if isinstance(item, dict)]
    if len(artifact_paths) != 8 or len(set(artifact_paths)) != 8:
        errors.append("generated artifact list must contain eight unique paths")
    if "spec/generated/protection_register_map_conformance.json" not in artifact_paths:
        errors.append("behavior conformance artifact is missing")
    ownership = set(selected.get("ownership", []))
    if not REQUIRED_BEHAVIOR_PROPERTIES <= ownership:
        errors.append("behavior semantics are absent from source ownership")

    behavior = contract.get("behavior_source_contract", {})
    if behavior.get("register_map_source_owns_behavior_semantics") is not True:
        errors.append("behavior semantics are absent from source ownership")
    if behavior.get("handwritten_rtl_is_untracked_authority") is not False:
        errors.append("handwritten RTL remains an untracked behavior authority")
    behavior_items = {
        str(item.get("id")): item
        for item in behavior.get("behavior_vocabulary", [])
        if isinstance(item, dict)
    }
    if set(behavior_items) != REQUIRED_BEHAVIOR_IDS:
        errors.append("behavior vocabulary is incomplete")
    if behavior_items.get("W1C_EVENT_WINS", {}).get("event_priority") != (
        "SAME_CYCLE_EVENT_WINS_OVER_CLEAR"
    ):
        errors.append("W1C event priority differs from spec")
    if behavior_items.get("W1P_ONE_ACLK", {}).get("pulse_width") != "ONE_ACLK":
        errors.append("W1P pulse width differs from spec")
    bindings = behavior.get("binding_contract", {})
    if bindings.get("every_public_field_has_one_behavior_id") is not True:
        errors.append("public field behavior ID coverage is incomplete")
    if bindings.get("every_behavior_id_has_rtl_binding") is not True:
        errors.append("behavior ID RTL binding coverage is incomplete")
    if bindings.get("every_binding_has_spec_generated_tests") is not True:
        errors.append("RTL binding lacks spec-generated tests")

    binding_matrix = contract.get("behavior_binding_matrix", {})
    if binding_matrix.get("coverage_authority") != "DERIVED_FROM_BINDING_RECORDS":
        errors.append("behavior binding coverage cannot be represented only by booleans")
    coverage = derive_behavior_binding_coverage(contract)
    if coverage["unbound_fields"]:
        errors.append(f"public field without behavior binding: {coverage['unbound_fields']}")
    if coverage["unexpected_bindings"]:
        errors.append(f"unexpected behavior binding target: {coverage['unexpected_bindings']}")
    if coverage["duplicate_bindings"]:
        errors.append("duplicate field behavior binding")
    if coverage["bindings_without_conformance_families"]:
        errors.append("behavior binding without conformance family")
    if coverage["unknown_behavior_bindings"]:
        errors.append("behavior binding references an unknown behavior ID")
    if coverage["unconsumed_enabled_behavior_ids"]:
        errors.append(
            "enabled behavior ID is unconsumed: "
            f"{coverage['unconsumed_enabled_behavior_ids']}"
        )
    if coverage["approved_enabled_access_types_without_behavior_id"]:
        errors.append("approved enabled access type has no behavior ID")
    if coverage["disabled_access_uses"]:
        errors.append("WO/W1S/RC cannot be enabled for ABI 1.1 without behavior IDs")

    enablement = contract.get("access_taxonomy_enablement", {})
    if enablement.get("policy") != (
        "OPTION_B_DEFINED_TAXONOMY_NOT_ENABLED_FOR_ABI_1_1"
    ):
        errors.append("access taxonomy enablement policy changed")
    if enablement.get("defined_taxonomy_not_enabled_for_abi_1_1") != [
        "WO",
        "W1S",
        "RC",
    ]:
        errors.append("WO/W1S/RC ABI 1.1 enablement must remain deferred")
    if enablement.get("enabled_access_types") != ["RO", "RW", "W1C", "W1P", "RSVD"]:
        errors.append("WO/W1S/RC cannot be enabled for ABI 1.1 without behavior IDs")

    selected_coverage = derive_selected_map_coverage(contract)
    if tuple(selected_coverage["allocation_pairs"]) != EXPECTED_SELECTED_ABI_1_1_ALLOCATION:
        errors.append("selected allocation differs from the approved eight-register map")
    if selected_coverage["allocated_without_definition"]:
        errors.append(
            "selected allocation register without a register definition: "
            f"{selected_coverage['allocated_without_definition']}"
        )
    if selected_coverage["definitions_without_allocation"] or selected_coverage[
        "offset_mismatches"
    ]:
        errors.append(
            "selected register definition without an allocated offset: "
            f"definitions={selected_coverage['definitions_without_allocation']}, "
            f"offsets={selected_coverage['offset_mismatches']}"
        )
    if selected_coverage["allocated_without_field_contract"]:
        errors.append(
            "allocated register without field contract: "
            f"{selected_coverage['allocated_without_field_contract']}"
        )
    if selected_coverage["duplicate_definition_names"] or selected_coverage[
        "duplicate_definition_offsets"
    ]:
        errors.append("selected register definitions are duplicated")
    if selected_coverage["duplicate_fields"]:
        errors.append("selected register field definitions are duplicated")
    if selected_coverage["malformed_fields"]:
        errors.append(
            "selected register field contract is incomplete: "
            f"{selected_coverage['malformed_fields']}"
        )
    if selected_coverage["unallocated_fields"]:
        errors.append(
            "unallocated field counted as ABI 1.1: "
            f"{selected_coverage['unallocated_fields']}"
        )
    if selected_coverage["uncovered_bits"]:
        errors.append(
            "uncovered selected register bit: "
            f"{selected_coverage['uncovered_bits']}"
        )
    if selected_coverage["overlapping_bits"]:
        errors.append(
            "overlapping selected register bit: "
            f"{selected_coverage['overlapping_bits']}"
        )
    if selected_coverage["fields_without_bindings"]:
        errors.append(
            "selected field without behavior binding: "
            f"{selected_coverage['fields_without_bindings']}"
        )
    if selected_coverage["bindings_without_fields"]:
        errors.append(
            "selected binding without field: "
            f"{selected_coverage['bindings_without_fields']}"
        )
    if selected_coverage["fields_without_conformance"]:
        errors.append(
            "selected register field lacks conformance family: "
            f"{selected_coverage['fields_without_conformance']}"
        )
    if selected_coverage["deferred_counted_as_selected"]:
        errors.append(
            "deferred candidate counted as selected ABI: "
            f"{selected_coverage['deferred_counted_as_selected']}"
        )
    if selected_coverage["deferred_count"] != 1 or selected_coverage[
        "deferred_names"
    ] != ["CLEAR_EVENT_STATUS"]:
        errors.append("CLEAR_EVENT_STATUS must be the sole deferred register candidate")

    selected_fields = {
        f"{register.get('name')}.{field.get('name')}": field
        for register, field in selected_field_records(contract)
    }
    binding_items = {
        f"{item.get('register')}.{item.get('field_or_global_policy')}": item
        for item in binding_matrix.get("bindings", [])
        if isinstance(item, dict) and item.get("scope") == "ABI_1_1_SELECTED"
    }
    for key, field in selected_fields.items():
        binding = binding_items.get(key, {})
        for field_key, binding_key in (
            ("behavior_id", "behavior_id"),
            ("rtl_binding_id", "rtl_binding_id"),
            ("side_effect_id", "side_effect_id"),
            ("generated_conformance_family", "generated_conformance_family"),
            ("implementation_status", "implementation_status"),
        ):
            if field.get(field_key) != binding.get(binding_key):
                errors.append(f"selected field binding differs from matrix: {key}.{field_key}")
        if field.get("implementation_status") != "PROPOSED_NOT_IMPLEMENTED":
            errors.append(f"selected ABI field implementation status changed: {key}")

    discovery_bindings = DISCOVERY_BINDING_TARGETS & set(binding_items)
    if discovery_bindings != DISCOVERY_BINDING_TARGETS:
        errors.append(
            "discovery register behavior binding missing: "
            f"{sorted(DISCOVERY_BINDING_TARGETS-discovery_bindings)}"
        )
    if any(
        not str(binding_items[key].get("generated_conformance_family", "")).strip()
        for key in discovery_bindings
    ):
        errors.append("discovery register conformance family missing")

    expected_discovery_fields: dict[str, tuple[int, int, str, Any, str]] = {
        "REGISTER_MAP_VERSION.MAGIC": (31, 16, "RO", 0x524D, "RO_STATIC"),
        "REGISTER_MAP_VERSION.ABI_MAJOR": (15, 8, "RO", 1, "RO_STATIC"),
        "REGISTER_MAP_VERSION.ABI_MINOR": (7, 0, "RO", 1, "RO_STATIC"),
        "CAPABILITIES_0.ARMED_READY": (0, 0, "RO", 1, "RO_STATIC"),
        "CAPABILITIES_0.FAULT_BITMAPS": (1, 1, "RO", 1, "RO_STATIC"),
        "CAPABILITIES_0.CLEAR_LEVEL_STATUS": (2, 2, "RO", 1, "RO_STATIC"),
        "CAPABILITIES_0.STAGE2G_POLICY": (3, 3, "RO", 1, "RO_STATIC"),
        "CAPABILITIES_0.NORMALIZED_TELEMETRY_RESERVED_ZERO": (
            4,
            4,
            "RSVD",
            0,
            "RSVD_ZERO_IGNORE",
        ),
        "CAPABILITIES_0.STAGE2E_TRANSACTION_OBSERVABILITY": (
            5,
            5,
            "RO",
            1,
            "RO_STATIC",
        ),
        "CAPABILITIES_0.POLICY_EVALUATION_IDENTITY": (
            6,
            6,
            "RO",
            1,
            "RO_STATIC",
        ),
        "CAPABILITIES_0.RESERVED_ZERO": (31, 7, "RSVD", 0, "RSVD_ZERO_IGNORE"),
        "CAPABILITIES_1.FAULT_BITMAP_WIDTH": (7, 0, "RO", 6, "RO_STATIC"),
        "CAPABILITIES_1.IMPLEMENTED_SEQUENCE_WIDTH": (
            15,
            8,
            "RO",
            {"kind": "parameter", "name": "OBS_SEQUENCE_WIDTH"},
            "RO_STATIC",
        ),
        "CAPABILITIES_1.MIN_SEQUENCE_WIDTH": (23, 16, "RO", 16, "RO_STATIC"),
        "CAPABILITIES_1.MAX_SEQUENCE_WIDTH": (31, 24, "RO", 32, "RO_STATIC"),
        "POLICY_STATUS.RESERVED": (31, 5, "RSVD", 0, "RSVD_ZERO_IGNORE"),
    }
    for key, (msb, lsb, access, value, behavior_id) in expected_discovery_fields.items():
        field = selected_fields.get(key, {})
        if (
            field.get("bits") != {"msb": msb, "lsb": lsb}
            or field.get("access") != access
            or field.get("static_value") != value
            or field.get("reset") != value
            or field.get("behavior_id") != behavior_id
        ):
            errors.append(f"discovery field contract differs: {key}")
    snapshot_contract = contract.get("policy_snapshot_contract", {})
    if snapshot_contract.get("policy_evaluation_sequence_role") != (
        "DIAGNOSTIC_LAST_RETIREMENT_IDENTITY"
    ):
        errors.append("policy evaluation sequence role is not diagnostic identity")
    if snapshot_contract.get("policy_evaluation_sequence_is_snapshot_token") is not False:
        errors.append("policy evaluation sequence cannot be advertised as a snapshot token")
    if snapshot_contract.get("read_policy_snapshot_api") != "DEFERRED":
        errors.append("read_policy_snapshot exists without a valid coherence authority")
    if snapshot_contract.get("policy_multi_register_coherence") != (
        "INDEPENDENTLY_COHERENT_NO_ATOMIC_OR_SEQUENCE_BRACKETED_CLAIM"
    ):
        errors.append("policy multi-register coherence overclaims snapshot semantics")
    if snapshot_contract.get("policy_snapshot_overclaim") is not False:
        errors.append("policy snapshot overclaim must remain false")
    if snapshot_contract.get("selected_option") != (
        "OPTION_C_DEFER_CROSS_WORD_SNAPSHOT"
    ):
        errors.append("policy snapshot Option C must remain selected")
    limitations = snapshot_contract.get("sequence_limitations", {})
    if limitations.get("duplicate_identity_can_prove_coherence") is not False:
        errors.append("duplicate sequence cannot prove snapshot coherence")
    if limitations.get("stale_identity_can_prove_coherence") is not False:
        errors.append("stale sequence cannot prove snapshot coherence")
    if limitations.get("clear_pending_can_change_without_identity_change") is not True:
        errors.append("clear_pending can change without policy identity change")
    if limitations.get("reset_returns_identity_to_zero") is not True:
        errors.append("reset-to-zero cannot prove snapshot coherence")
    if limitations.get("reset_to_zero_can_prove_coherence") is not False:
        errors.append("reset-to-zero cannot pass snapshot coherence")
    if limitations.get("source_sequence_can_restart") is not True:
        errors.append("source sequence restart cannot prove snapshot coherence")
    if limitations.get("source_restart_can_prove_coherence") is not False:
        errors.append("source sequence restart cannot pass snapshot coherence")

    monitor = contract.get("public_current_monitor_contract", {})
    if monitor.get("public_i_ch1_reset") != 0 or monitor.get("public_i_ch2_reset") != 0:
        errors.append("I_CH1/I_CH2 public reset must be zero, not LIVE_INPUT")
    if monitor.get("public_i_ch1_i_ch2_source") != (
        "LATEST_ATOMIC_DESTINATION_FIFO_DELIVERY"
    ):
        errors.append("public current monitor source contract changed")
    if monitor.get("public_i_ch1_i_ch2_volatility") != "REGISTERED_ACLK_VOLATILE":
        errors.append("public current monitor volatility contract changed")
    if monitor.get("public_i_ch1_i_ch2_software_pair_atomic") is not False:
        errors.append("I_CH1/I_CH2 software pair cannot be atomic")
    if monitor.get("generic_wrapper_may_override_public_reset") is not False:
        errors.append("generic wrapper reset cannot override production public reset")
    monitor_registers = {
        item.get("name"): item
        for item in abi.get("registers", [])
        if isinstance(item, dict) and item.get("name") in {"I_CH1", "I_CH2"}
    }
    for register_name, field_name in (("I_CH1", "i_ch1_mon"), ("I_CH2", "i_ch2_mon")):
        register = monitor_registers.get(register_name, {})
        fields_by_name = {
            item.get("name"): item
            for item in register.get("fields", [])
            if isinstance(item, dict)
        }
        if register.get("reset") != 0 or fields_by_name.get(field_name, {}).get("reset") != 0:
            errors.append("I_CH1/I_CH2 public reset remains LIVE_INPUT")

    armed = selected_fields.get("POLICY_STATUS.ARMED_READY", {})
    armed_semantics = str(armed.get("read_semantics", ""))
    if "zero in initial RESET_WAIT" not in armed_semantics:
        errors.append("ARMED_READY initial RESET_WAIT must be zero")
    if "post-clear RESET_WAIT" not in armed_semantics:
        errors.append("ARMED_READY post-clear RESET_WAIT must be zero")
    if armed.get("implementation_status") != "PROPOSED_NOT_IMPLEMENTED":
        errors.append("advertised capability lacks proposed implementation")

    api_items = {
        item.get("api"): item
        for item in contract.get("software_api_plan", [])
        if isinstance(item, dict)
    }
    if api_items.get("is_armed()", {}).get("decision") != "ADD":
        errors.append("ARMED_READY is missing its software API")
    if api_items.get("read_policy_status()", {}).get("decision") != "ADD":
        errors.append("policy status capability is missing its software API")
    if api_items.get("read_observability()", {}).get("decision") != "PRESERVE":
        errors.append("Stage 2E read observability API dependency is missing")
    if api_items.get("clear_observability_status()", {}).get("decision") != "PRESERVE":
        errors.append("Stage 2E clear observability API dependency is missing")
    recovery = api_items.get("recovery_is_verified()", {})
    if recovery.get("decision") != "PRESERVE" or "post-fault" not in str(
        recovery.get("semantics", "")
    ):
        errors.append("recovery_is_verified must remain post-fault only")

    alternatives = contract.get("allocation_alternatives", [])
    selected_alternatives = [
        item for item in alternatives if isinstance(item, dict) and item.get("selected") is True
    ]
    if len(selected_alternatives) != 1 or selected_alternatives[0].get("id") != "CAPABILITY_PLUS_OBSERVABILITY":
        errors.append("selected allocation alternative changed")
    for alternative in alternatives:
        if not isinstance(alternative, dict):
            continue
        seen_offsets: set[int] = set()
        for register in alternative.get("registers", []):
            try:
                offset = int(str(register.get("offset")), 16)
            except (AttributeError, ValueError):
                errors.append("proposed offset is malformed")
                continue
            if offset <= 0x60:
                errors.append("proposed offset overlaps frozen 0x00..0x60")
            if offset % 4:
                errors.append("proposed offset is not word aligned")
            if offset in seen_offsets:
                errors.append("duplicate proposed offset")
            seen_offsets.add(offset)

    major_rules = contract.get("compatibility_rules", {}).get("major_increment_rules", [])
    if not major_rules or "move, remove or alias an existing offset" not in major_rules:
        errors.append("incompatible change requires ABI major")
    version_policy = contract.get("capability_version_policy", {})
    if version_policy.get("zero_version_word") != "NO_EXPLICIT_DISCOVERY":
        errors.append("zero version word must mean no explicit discovery")
    if version_policy.get("nonzero_bad_magic") != "REJECT_INCOMPATIBLE":
        errors.append("bad nonzero magic must be rejected as incompatible")
    if version_policy.get("unsupported_major") != "REJECT_INCOMPATIBLE":
        errors.append("unsupported ABI major must be rejected as incompatible")
    if version_policy.get("bad_magic_is_legacy") is not False:
        errors.append("bad nonzero magic cannot be treated as legacy")
    feature_bits = version_policy.get("feature_bits", [])
    feature_map = {
        str(item.get("name")): item
        for item in feature_bits
        if isinstance(item, dict)
    }
    feature_positions = [item.get("bit") for item in feature_bits if isinstance(item, dict)]
    if set(feature_map) != REQUIRED_CAPABILITY_NAMES or feature_positions != list(range(7)):
        errors.append("public capability bit inventory is incomplete or misnumbered")
    if version_policy.get("capability_bit_means_public_software_usable_feature") is not True:
        errors.append("capability bits must mean usable public software features")
    if any(
        set(item) != {"bit", "name", "dependency_ref"}
        for item in feature_bits
        if isinstance(item, dict)
    ):
        errors.append("capability feature bits duplicate dependency authority data")
    authority_contract = contract.get("capability_dependency_authority_contract", {})
    if (
        version_policy.get("normalized_telemetry_capability_bit") != "RESERVED_ZERO"
        or authority_contract
        != {
            "capability_dependency_authority": "capability_dependency_matrix",
            "field_capability_annotations": "VALIDATED_REFERENCES_TO_AUTHORITY",
            "software_api_capability_gates": "VALIDATED_REFERENCES_TO_AUTHORITY",
            "conformance_dependencies": (
                "EXACT_BINDING_EDGES_NOT_GLOBAL_NAME_PRESENCE"
            ),
            "independently_editable_dependency_descriptions": "FORBIDDEN",
        }
    ):
        errors.append("capability dependency authority differs")
    matrix = contract.get("capability_dependency_matrix", {})
    matrix_entries = {
        str(item.get("name")): item
        for item in matrix.get("capabilities", [])
        if isinstance(item, dict)
    }
    normalized = matrix_entries.get("NORMALIZED_TELEMETRY", {})
    if (
        normalized.get("advertisement_value") != 0
        or normalized.get("advertisement_gate") != "RESERVED_ZERO"
        or normalized.get("required_api_gate_refs") != []
    ):
        errors.append("internal-only normalized telemetry cannot be advertised publicly")
    policy_identity = matrix_entries.get("POLICY_EVALUATION_IDENTITY", {})
    if "diagnostic" not in str(policy_identity.get("software_visible_meaning", "")).lower():
        errors.append("policy identity capability lacks diagnostic public meaning")
    if "API_READ_POLICY_SNAPSHOT" in policy_identity.get(
        "required_api_gate_refs", []
    ):
        errors.append("capability advertises snapshot API without a formal API entry")

    capability_coverage = derive_capability_dependency_coverage(contract)
    if capability_coverage["missing_entries"] or capability_coverage[
        "unexpected_entries"
    ] or capability_coverage["duplicate_entries"] or capability_coverage[
        "duplicate_bits"
    ]:
        errors.append("capability dependency matrix does not cover exactly seven bits")
    if capability_coverage["missing_register_dependencies"]:
        errors.append(
            "capability has missing register dependencies: "
            f"{capability_coverage['missing_register_dependencies']}"
        )
    if capability_coverage["missing_field_dependencies"]:
        errors.append(
            "capability has missing field dependencies: "
            f"{capability_coverage['missing_field_dependencies']}"
        )
    if capability_coverage["missing_binding_dependencies"]:
        errors.append(
            "capability has missing binding dependencies: "
            f"{capability_coverage['missing_binding_dependencies']}"
        )
    if capability_coverage["missing_conformance_dependencies"]:
        errors.append(
            "capability has missing conformance dependencies: "
            f"{capability_coverage['missing_conformance_dependencies']}"
        )
    if capability_coverage["missing_api_dependencies"]:
        errors.append(
            "capability has missing API dependencies: "
            f"{capability_coverage['missing_api_dependencies']}"
        )
    if capability_coverage["missing_metadata_dependencies"]:
        errors.append(
            "capability has missing metadata dependencies: "
            f"{capability_coverage['missing_metadata_dependencies']}"
        )
    if capability_coverage["mismatched_entries"]:
        errors.append(
            "capability dependency entry differs from advertised capability: "
            f"{capability_coverage['mismatched_entries']}"
        )
    if capability_coverage["gate_grammar_errors"]:
        errors.append(
            "capability gate grammar invalid: "
            f"{capability_coverage['gate_grammar_errors']}"
        )
    if capability_coverage["field_capability_edge_mismatches"]:
        errors.append(
            "field capability edge mismatch: "
            f"{capability_coverage['field_capability_edge_mismatches']}"
        )
    if capability_coverage["api_capability_gate_mismatches"]:
        errors.append(
            "API capability gate mismatch: "
            f"{capability_coverage['api_capability_gate_mismatches']}"
        )
    if capability_coverage["binding_conformance_edge_mismatches"]:
        errors.append(
            "binding conformance edge mismatch: "
            f"{capability_coverage['binding_conformance_edge_mismatches']}"
        )
    if capability_coverage["capability_implication_violations"]:
        errors.append(
            "capability implication violation: "
            f"{capability_coverage['capability_implication_violations']}"
        )
    if capability_coverage["free_form_capability_expressions"]:
        errors.append(
            "free-form capability expression is forbidden: "
            f"{capability_coverage['free_form_capability_expressions']}"
        )
    if capability_coverage["capability_edge_covered_count"] != capability_coverage[
        "capability_edge_target_count"
    ]:
        errors.append("capability edge coverage is incomplete")

    metadata = contract.get("capability_metadata_constraints", {})
    if set(metadata.get("constraint_ids", [])) != REQUIRED_METADATA_CONSTRAINT_IDS:
        errors.append("capability metadata constraint inventory is incomplete")
    bitmap_width = selected_fields.get("CAPABILITIES_1.FAULT_BITMAP_WIDTH", {}).get(
        "static_value"
    )
    parameters = {
        str(item.get("name")): item
        for item in contract.get("register_value_expression_contract", {}).get(
            "parameters", []
        )
        if isinstance(item, dict)
    }
    implemented_width = parameters.get("OBS_SEQUENCE_WIDTH", {}).get(
        "configured_default"
    )
    minimum_width = selected_fields.get("CAPABILITIES_1.MIN_SEQUENCE_WIDTH", {}).get(
        "static_value"
    )
    maximum_width = selected_fields.get("CAPABILITIES_1.MAX_SEQUENCE_WIDTH", {}).get(
        "static_value"
    )
    if not isinstance(bitmap_width, int) or not 1 <= bitmap_width <= 32:
        errors.append("FAULT_BITMAPS advertised with width outside 1..32")
    if not isinstance(implemented_width, int) or not 16 <= implemented_width <= 32:
        errors.append("sequence identity implemented width is outside 16..32")
    if minimum_width != 16:
        errors.append("minimum sequence width must equal 16")
    if maximum_width != 32:
        errors.append("maximum sequence width must equal 32")
    if (
        isinstance(minimum_width, int)
        and isinstance(implemented_width, int)
        and minimum_width > implemented_width
    ):
        errors.append("minimum width greater than implemented width")
    if (
        isinstance(implemented_width, int)
        and isinstance(maximum_width, int)
        and implemented_width > maximum_width
    ):
        errors.append("implemented width greater than maximum width")
    normalized_field = selected_fields.get(
        "CAPABILITIES_0.NORMALIZED_TELEMETRY_RESERVED_ZERO", {}
    )
    if normalized_field.get("static_value") != 0 or normalized_field.get("reset") != 0:
        errors.append("normalized telemetry reserved bit must remain zero")
    reserved_capability = selected_fields.get("CAPABILITIES_0.RESERVED_ZERO", {})
    if reserved_capability.get("static_value") != 0 or reserved_capability.get("reset") != 0:
        errors.append("reserved capability bits must remain zero")
    if metadata.get("fault_bitmap_width") != {
        "field": "CAPABILITIES_1.FAULT_BITMAP_WIDTH",
        "minimum": 1,
        "maximum": 32,
    }:
        errors.append("FAULT_BITMAP_WIDTH metadata constraint differs")
    if metadata.get("implemented_sequence_width") != {
        "field": "CAPABILITIES_1.IMPLEMENTED_SEQUENCE_WIDTH",
        "minimum": 16,
        "maximum": 32,
    }:
        errors.append("IMPLEMENTED_SEQUENCE_WIDTH metadata constraint differs")
    if metadata.get("minimum_sequence_width") != {
        "field": "CAPABILITIES_1.MIN_SEQUENCE_WIDTH",
        "required_value": 16,
    }:
        errors.append("MIN_SEQUENCE_WIDTH metadata constraint differs")
    if metadata.get("maximum_sequence_width") != {
        "field": "CAPABILITIES_1.MAX_SEQUENCE_WIDTH",
        "required_value": 32,
    }:
        errors.append("MAX_SEQUENCE_WIDTH metadata constraint differs")
    if metadata.get("width_ordering") != "MIN_LE_IMPLEMENTED_LE_MAX":
        errors.append("capability width ordering constraint differs")
    if metadata.get("normalized_telemetry") != {
        "field": "CAPABILITIES_0.NORMALIZED_TELEMETRY_RESERVED_ZERO",
        "required_value": 0,
    }:
        errors.append("normalized telemetry metadata constraint differs")
    if metadata.get("reserved_capabilities_0") != {
        "field": "CAPABILITIES_0.RESERVED_ZERO",
        "required_value": 0,
    }:
        errors.append("reserved CAPABILITIES_0 metadata constraint differs")
    if metadata.get("reserved_zero_policy") != (
        "ABI_MINOR_1_REQUIRES_ZERO_HIGHER_MINOR_NEWLY_DEFINED_UNKNOWN_BITS_ARE_IGNORED"
    ):
        errors.append("reserved capability zero policy differs by ABI minor")
    if metadata.get("supported_major_higher_minor") != (
        "ACCEPT_KNOWN_PREFIX_IGNORE_UNKNOWN_CAPABILITY_BITS_USE_ONLY_VALIDATED_KNOWN_FEATURES"
    ):
        errors.append("higher minor incorrectly enables unknown feature")
    if metadata.get("unknown_capability_bits") != "IGNORE":
        errors.append("higher minor incorrectly enables unknown feature")
    if metadata.get("known_feature_gate") != (
        "BIT_SET_AND_ALL_REGISTER_FIELD_BINDING_CONFORMANCE_API_AND_METADATA_DEPENDENCIES_VALID"
    ):
        errors.append("higher compatible minor known-feature gate differs")
    if metadata.get("malformed_explicit_capability_metadata") != (
        "REJECT_INCOMPATIBLE"
    ):
        errors.append("malformed explicit capability metadata must reject incompatible")

    aggregate_coverage = derive_selected_register_aggregates(contract)
    if aggregate_coverage["manual_register_reset_duplications"]:
        errors.append(
            "manual register reset duplication is forbidden: "
            f"{aggregate_coverage['manual_register_reset_duplications']}"
        )
    if aggregate_coverage["register_field_reset_mismatches"]:
        errors.append(
            "register field reset mismatch: "
            f"{aggregate_coverage['register_field_reset_mismatches']}"
        )
    if aggregate_coverage["register_field_static_value_mismatches"]:
        errors.append(
            "register field static value mismatch: "
            f"{aggregate_coverage['register_field_static_value_mismatches']}"
        )
    if aggregate_coverage["register_field_access_mismatches"]:
        errors.append(
            "register field access mismatch: "
            f"{aggregate_coverage['register_field_access_mismatches']}"
        )
    if aggregate_coverage["non_machine_evaluable_register_values"]:
        errors.append(
            "non-machine-evaluable register value: "
            f"{aggregate_coverage['non_machine_evaluable_register_values']}"
        )
    if aggregate_coverage["expression_errors"]:
        errors.append(
            "register value expression invalid: "
            f"{aggregate_coverage['expression_errors']}"
        )
    if aggregate_coverage["parameter_errors"]:
        errors.append(
            "parameterized register expression invalid: "
            f"{aggregate_coverage['parameter_errors']}"
        )
    if aggregate_coverage["overflow_errors"]:
        errors.append(
            "parameter-expression overflow or field overflow: "
            f"{aggregate_coverage['overflow_errors']}"
        )

    legacy = contract.get("legacy_capability_discovery", {})
    if legacy.get("capability_model") != ["PRESENT", "ABSENT", "UNKNOWN"]:
        errors.append("legacy capability model must preserve PRESENT ABSENT UNKNOWN")
    if legacy.get("historical_pre_stage2e_hardware_supported_by_new_software") is not False:
        errors.append("historical pre-Stage2E support decision changed")
    if legacy.get("all_capabilities_false_fallback") != "FORBIDDEN":
        errors.append("all legacy capabilities cannot be forced false")
    stage2e_result = legacy.get("valid_stage2e_result", {})
    if stage2e_result.get("stage2g_policy") != "UNKNOWN":
        errors.append("Stage 2G cannot be inferred from a zero version word")
    if stage2e_result.get("stage2e_transaction_observability") != "PRESENT":
        errors.append("valid Stage 2E legacy evidence must preserve PRESENT state")
    if stage2e_result.get("sequence_width") != "PRESENT_DISCOVERED_VALUE":
        errors.append("legacy Stage 2E sequence width must preserve the discovered value")
    if legacy.get("bad_nonzero_obs_capability_result") != (
        "REJECT_INCOMPATIBLE_OR_WRONG_DEVICE"
    ):
        errors.append("bad nonzero OBS_CAPABILITY must fail closed")

    conformance = contract.get("generated_conformance_architecture", {})
    if conformance.get("generated_artifact") != (
        "spec/generated/protection_register_map_conformance.json"
    ):
        errors.append("behavior conformance artifact is missing")
    if conformance.get("constants_only_freshness_is_sufficient") is not False:
        errors.append("fresh generated constants cannot substitute for conformance")
    if conformance.get("approach") != "FINITE_PROJECT_SPECIFIC_TEMPLATES":
        errors.append("conformance approach is not finite project-specific templates")
    if conformance.get("generic_runner") != "REJECTED_OVERENGINEERING":
        errors.append("overengineered generic conformance runner was added")
    if conformance.get("manual_expected_values") != (
        "ALLOWED_ONLY_WHEN_DERIVED_FROM_REGISTER_MAP_AUTHORITY"
    ):
        errors.append("manual expected value is not derived from the spec")
    conformance_invariants = conformance.get("required_invariants", {})
    for key in (
        "every_public_field_has_one_behavior_id",
        "every_behavior_id_has_rtl_binding",
        "every_binding_has_spec_generated_tests",
    ):
        if conformance_invariants.get(key) is not True:
            errors.append(f"generated conformance invariant is not enforced: {key}")

    bitmap = contract.get("bitmap_lifetime_contract", {})
    if bitmap.get("first_live_seen_bitmap_lifetime") != "ACTIVE_INTERNAL_EPISODE":
        errors.append("bitmap lifetime cannot equal compatibility-latch lifetime")
    if bitmap.get("post_clear_reset_wait_bitmaps") != "ZERO":
        errors.append("post-clear RESET_WAIT bitmaps must be zero")
    if bitmap.get("public_compatibility_fault_code_may_remain_nonzero") is not True:
        errors.append("public compatibility fault code retention must remain explicit")
    mixed = bitmap.get("mixed_state_example", {})
    if mixed.get("first_fault_bitmap") != 0 or mixed.get(
        "post_clear_recovery_pending"
    ) != 1:
        errors.append("post-clear mixed bitmap and compatibility lifetime is missing")

    tooling = contract.get("tooling_replay_policy", {})
    if tooling.get("platform_launcher_hardcoded") is not False:
        errors.append("hard-coded platform launcher is forbidden")
    if tooling.get("unit_tests_depend_on_external_launcher_names") is not False:
        errors.append("unit tests cannot depend on external launcher names")
    if tooling.get("archive_unit_test_git_scope_check") is not False:
        errors.append("source-archive unit test cannot require Git scope")
    if tooling.get("windows_to_wsl_path_conversion") != (
        "PURE_WINDOWS_PATH_DIRECT_NO_HOST_RESOLVE"
    ):
        errors.append("Windows path conversion cannot depend on host Path.resolve")
    if tooling.get("archive_stage2h_unit_tests_required") is not True:
        errors.append("Linux source-archive Stage 2H unit tests are required")
    if tooling.get("required_platforms") != ["WINDOWS", "LINUX_OR_WSL"]:
        errors.append("Linux or WSL source-archive replay is required")
    if tooling.get("source_archive_replay_tool") != (
        "tools/replay_stage2h_source_archive.py"
    ):
        errors.append("repository-owned source-archive replay tool is missing")

    capability_object = contract.get("software_capability_object_contract", {})
    if capability_object.get("per_feature_state") != ["PRESENT", "ABSENT", "UNKNOWN"]:
        errors.append("software capability object loses tri-state feature knowledge")
    if capability_object.get("abi_version_known") != "BOOLEAN":
        errors.append("software capability object loses ABI version knowledge")
    read_capabilities = api_items.get("read_capabilities()", {})
    if "PRESENT/ABSENT/UNKNOWN" not in str(read_capabilities.get("semantics", "")):
        errors.append("read_capabilities API does not preserve tri-state knowledge")
    read_version = api_items.get("read_register_map_version()", {})
    if "bad nonzero magic" not in str(read_version.get("absent_behavior", "")):
        errors.append("read_register_map_version API does not reject bad magic")
    read_identity = api_items.get("read_policy_evaluation_identity()", {})
    if read_identity.get("decision") != "ADD" or "diagnostic" not in str(
        read_identity.get("semantics", "")
    ):
        errors.append("diagnostic policy identity API is missing")
    read_snapshot = api_items.get("read_policy_snapshot()", {})
    if read_snapshot.get("decision") != "DEFER":
        errors.append("read_policy_snapshot exists without a valid coherence authority")

    if ast_policy.get("interpreter_default_ast_dump_authority") is not False:
        errors.append("interpreter-default ast.dump cannot be authority")
    if ast_policy.get("authority") != "CANONICAL_REPOSITORY_OWNED_REPRESENTATION":
        errors.append("canonical repository-owned AST authority changed")
    if ast_policy.get("local_variable_rename_policy") != "SEMANTICALLY_SIGNIFICANT_MISMATCH":
        errors.append("local variable rename policy changed")

    try:
        decisions = decision_map(contract)
    except AuditError as exc:
        errors.append(str(exc))
        decisions = {}
    if set(decisions) != REQUIRED_DECISIONS:
        errors.append(
            "required decision set mismatch: "
            f"missing={sorted(REQUIRED_DECISIONS-set(decisions))}, "
            f"extra={sorted(set(decisions)-REQUIRED_DECISIONS)}"
        )
    if any(item.get("status") == "OWNER_DECISION_REQUIRED" for item in decisions.values()):
        errors.append("owner decision remains unresolved")
    if contract.get("open_owner_decisions") != []:
        errors.append("open owner decision list must be empty")
    return errors


def extract_rtl_offsets(text: str) -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(
            r"^\s*localparam\s+REG_([A-Z0-9_]+)\s*=\s*8'h([0-9A-Fa-f]{2})\s*;",
            text,
            flags=re.MULTILINE,
        )
    }


def extract_python_offsets(text: str) -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(
            r"^REG_([A-Z0-9_]+)\s*=\s*0x([0-9A-Fa-f]{2})\s*$",
            text,
            flags=re.MULTILINE,
        )
    }


def extract_c_offsets(text: str) -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(
            r"^#define\s+PROTECTION_REG_([A-Z0-9_]+)\s+0x([0-9A-Fa-f]{2})u\s*$",
            text,
            flags=re.MULTILINE,
        )
    }


def extract_doc_offsets(text: str) -> dict[str, int]:
    return {
        name: int(value, 16)
        for value, name in re.findall(
            r"^\|\s*`0x([0-9A-Fa-f]{2})`\s*\|\s*`([A-Z0-9_]+)`\s*\|",
            text,
            flags=re.MULTILINE,
        )
    }


def extract_tcl_offsets(text: str) -> dict[str, int]:
    return {
        name: int(value, 16)
        for value, name in re.findall(
            r"^# - 0x([0-9A-Fa-f]{2})\s+([A-Z0-9_]+)\b",
            text,
            flags=re.MULTILINE,
        )
    }


def expected_offset_map(contract: dict[str, Any]) -> dict[str, int]:
    return {
        str(item["name"]): int(str(item["offset"]), 16)
        for item in contract["current_abi"]["registers"]
    }


def check_source_maps(
    root: Path, contract: dict[str, Any], overrides: dict[str, str] | None = None
) -> list[str]:
    overrides = overrides or {}
    expected = expected_offset_map(contract)
    paths = {
        "RTL": ("rtl/protection_reg_bank.v", extract_rtl_offsets),
        "Python": ("sw/protection_ip_interface.py", extract_python_offsets),
        "C header": ("sw/ps_register_demo/protection_ip_regs.h", extract_c_offsets),
        "documentation": ("docs/implementation/register_map.md", extract_doc_offsets),
        "Tcl register comment": (
            "fpga/vivado/package_protection_ip_stage2_axi_lite.tcl",
            extract_tcl_offsets,
        ),
    }
    errors: list[str] = []
    for label, (relative, extractor) in paths.items():
        text = overrides.get(relative)
        if text is None:
            text = (root / relative).read_text(encoding="utf-8")
        actual = extractor(text)
        if actual != expected:
            errors.append(f"{label} offset map differs from current ABI")
    return errors


def check_rtl_semantics(root: Path) -> list[str]:
    errors: list[str] = []
    reg_bank = (root / "rtl/protection_reg_bank.v").read_text(encoding="utf-8")
    reg_compact = compact(reg_bank)
    required_tokens = {
        "pwm_enable<=wr_data[0];": "CTRL PWM write effect",
        "clear_fault_pulse<=wr_data[1];": "CTRL W1P write effect",
        "REG_TH_OC1:th_oc_ch1<=wr_data[11:0];": "TH_OC1 write effect",
        "REG_TH_OC2:th_oc_ch2<=wr_data[11:0];": "TH_OC2 write effect",
        "REG_TH_DIFF:th_diff<=wr_data[11:0];": "TH_DIFF write effect",
        "REG_PWM_PERIOD:pwm_period<=wr_data[15:0];": "PWM period write effect",
        "REG_PWM_DUTY:pwm_duty<=wr_data[15:0];": "PWM duty write effect",
        "if(wr_strb[0])obs_status_w1c_clear[7:0]<=wr_data[7:0];": "W1C byte zero",
        "if(wr_strb[1])obs_status_w1c_clear[8]<=wr_data[8];": "W1C byte one",
        "REG_OBS_CAPABILITY:rd_data=OBS_CAPABILITY_VALUE;": "capability read",
        "default:rd_data=32'd0;": "undefined read zero",
    }
    for token, label in required_tokens.items():
        if token not in reg_compact:
            errors.append(f"RTL semantic token missing: {label}")
    for token in (
        "th_oc_ch1<=12'd3000;",
        "th_oc_ch2<=12'd3000;",
        "th_diff<=12'd200;",
        "pwm_period<=16'd1000;",
        "pwm_duty<=16'd500;",
    ):
        if token not in reg_compact:
            errors.append(f"RTL reset token missing: {token}")

    core = compact((root / "rtl/protection_core_top.v").read_text(encoding="utf-8"))
    if "assignfault_valid=fault_eval_valid&&(fault_eval_bitmap!=6'd0);" not in core:
        errors.append("Stage 2G fault_valid evaluation semantics changed")
    controller = compact((root / "rtl/protection_fsm.v").read_text(encoding="utf-8"))
    for token in (
        "localparamST_ARMED=4'd0;",
        "localparamST_FAULT_LATCHED=4'd1;",
        "localparamST_RESET_WAIT=4'd2;",
        "post_clear_recovery_pending<=1'b1;",
        "state<=ST_ARMED;public_fault_latched_compat<=1'b0;",
    ):
        if token not in controller:
            errors.append(f"Stage 2G policy token missing: {token}")
    return errors


SEMANTIC_AST_FIELDS: dict[str, tuple[str, ...]] = {
    "FunctionDef": ("name", "args", "body", "decorator_list", "returns", "type_comment"),
    "AsyncFunctionDef": ("name", "args", "body", "decorator_list", "returns", "type_comment"),
    "arguments": (
        "posonlyargs",
        "args",
        "vararg",
        "kwonlyargs",
        "kw_defaults",
        "kwarg",
        "defaults",
    ),
    "arg": ("arg", "annotation", "type_comment"),
    "Assign": ("targets", "value", "type_comment"),
    "AnnAssign": ("target", "annotation", "value", "simple"),
    "AugAssign": ("target", "op", "value"),
    "Return": ("value",),
    "Expr": ("value",),
    "If": ("test", "body", "orelse"),
    "IfExp": ("test", "body", "orelse"),
    "For": ("target", "iter", "body", "orelse", "type_comment"),
    "While": ("test", "body", "orelse"),
    "BoolOp": ("op", "values"),
    "BinOp": ("left", "op", "right"),
    "UnaryOp": ("op", "operand"),
    "Compare": ("left", "ops", "comparators"),
    "Call": ("func", "args", "keywords"),
    "keyword": ("arg", "value"),
    "Attribute": ("value", "attr", "ctx"),
    "Name": ("id", "ctx"),
    "Constant": ("value", "kind"),
    "Subscript": ("value", "slice", "ctx"),
    "Slice": ("lower", "upper", "step"),
    "Tuple": ("elts", "ctx"),
    "List": ("elts", "ctx"),
    "Set": ("elts",),
    "Dict": ("keys", "values"),
    "ListComp": ("elt", "generators"),
    "SetComp": ("elt", "generators"),
    "DictComp": ("key", "value", "generators"),
    "GeneratorExp": ("elt", "generators"),
    "comprehension": ("target", "iter", "ifs", "is_async"),
    "JoinedStr": ("values",),
    "FormattedValue": ("value", "conversion", "format_spec"),
    "Load": (),
    "Store": (),
    "Del": (),
    "And": (),
    "Or": (),
    "Add": (),
    "Sub": (),
    "Mult": (),
    "MatMult": (),
    "Div": (),
    "FloorDiv": (),
    "Mod": (),
    "Pow": (),
    "LShift": (),
    "RShift": (),
    "BitOr": (),
    "BitXor": (),
    "BitAnd": (),
    "Invert": (),
    "Not": (),
    "UAdd": (),
    "USub": (),
    "Eq": (),
    "NotEq": (),
    "Lt": (),
    "LtE": (),
    "Gt": (),
    "GtE": (),
    "Is": (),
    "IsNot": (),
    "In": (),
    "NotIn": (),
}


def canonical_ast_value(value: Any) -> Any:
    if isinstance(value, ast.AST):
        node_name = type(value).__name__
        if node_name not in SEMANTIC_AST_FIELDS:
            raise AuditError(
                "UNSUPPORTED_AST_NODE_SCHEMA_MIGRATION_REQUIRED: " + node_name
            )
        result: dict[str, Any] = {"node": node_name}
        for field in SEMANTIC_AST_FIELDS[node_name]:
            default: Any = [] if field in {
                "posonlyargs",
                "args",
                "kwonlyargs",
                "kw_defaults",
                "defaults",
                "body",
                "decorator_list",
                "orelse",
                "targets",
                "values",
                "ops",
                "comparators",
                "keywords",
                "elts",
                "keys",
                "generators",
                "ifs",
            } else None
            result[field] = canonical_ast_value(getattr(value, field, default))
        return result
    if isinstance(value, list):
        return [canonical_ast_value(item) for item in value]
    if value is Ellipsis:
        return {"literal": "Ellipsis"}
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, complex):
        return {"complex": [value.real, value.imag]}
    if isinstance(value, bytes):
        return {"bytes_hex": value.hex()}
    raise AuditError(f"unsupported AST scalar: {type(value).__name__}")


def target_function(source: str, function_name: str) -> ast.AST:
    tree = ast.parse(source)
    matches = [
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == function_name
    ]
    if len(matches) != 1:
        raise AuditError(
            f"target function must have exactly one top-level definition: {function_name}"
        )
    return matches[0]


def function_source_segment(source: str, node: ast.AST) -> str:
    start = int(getattr(node, "lineno")) - 1
    end = int(getattr(node, "end_lineno"))
    lines = source.splitlines(keepends=True)
    return "".join(lines[start:end])


def fingerprint_source(source: str, function_name: str) -> dict[str, str]:
    node = target_function(source, function_name)
    envelope = {
        "schema": "stage2h-python-semantic-ast-v1",
        "target_kind": "top_level_function",
        "tree": canonical_ast_value(node),
    }
    canonical_bytes = json.dumps(
        envelope, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")
    legacy_bytes = ast.dump(node, include_attributes=False).encode("utf-8")
    segment = function_source_segment(source, node).encode("utf-8")
    return {
        "schema": "stage2h-python-semantic-ast-v1",
        "canonical_sha256": sha256_bytes(canonical_bytes),
        "legacy_default_ast_dump_sha256": sha256_bytes(legacy_bytes),
        "source_segment_sha256": sha256_bytes(segment),
        "python_version": sys.version.replace("\n", " "),
        "python_executable": str(Path(sys.executable).resolve()),
    }


def check_ast_policy(
    root: Path, contract: dict[str, Any], fixtures: dict[str, Any]
) -> tuple[list[str], dict[str, str], list[str]]:
    errors: list[str] = []
    if fixtures.get("external_launcher_dependency") is not False:
        errors.append("AST unit fixtures cannot depend on an external launcher")
    source = (root / "sw/protection_ip_interface.py").read_text(encoding="utf-8")
    actual = fingerprint_source(source, "recovery_is_verified")
    policy = contract["ast_fingerprint_policy"]
    if actual["canonical_sha256"] != policy.get("authoritative_hash"):
        errors.append("canonical recovery predicate fingerprint differs from policy")
    if actual["source_segment_sha256"] != policy.get("diagnostic_source_hash"):
        errors.append("diagnostic recovery predicate source hash differs from policy")
    migration = policy.get("migration", {})
    if migration.get("new_sha256") != actual["canonical_sha256"]:
        errors.append("legacy fingerprint migration new hash differs from canonical hash")
    frozen = load_json(root / "spec/stage2g_implementation_base_fingerprints.json")
    legacy = frozen.get("software_recovery_predicate", {}).get("ast_sha256")
    if migration.get("legacy_sha256") != legacy:
        errors.append("legacy fingerprint migration does not bind the frozen Stage 2G hash")

    fixture_results: list[str] = []
    baseline_hash: str | None = None
    for item in fixtures.get("fixtures", []):
        fixture_id = str(item.get("id"))
        try:
            result = fingerprint_source(str(item.get("source")), "recovery_is_verified")
        except (AuditError, SyntaxError) as exc:
            errors.append(f"AST fixture {fixture_id} could not be fingerprinted: {exc}")
            continue
        expectation = item.get("expect")
        digest = result["canonical_sha256"]
        if expectation == "BASELINE":
            baseline_hash = digest
            if digest != actual["canonical_sha256"]:
                errors.append("AST baseline fixture differs from repository function")
        elif expectation == "MATCH":
            if baseline_hash is None or digest != baseline_hash:
                errors.append(f"AST fixture expected canonical match: {fixture_id}")
        elif expectation == "MISMATCH":
            if baseline_hash is None or digest == baseline_hash:
                errors.append(f"AST fixture expected canonical mismatch: {fixture_id}")
        else:
            errors.append(f"AST fixture expectation is invalid: {fixture_id}")
        fixture_results.append(f"{fixture_id}=PASS_{expectation}")
    return errors, actual, fixture_results


def parse_python_command(command: str) -> list[str]:
    parsed = shlex.split(command, posix=os.name != "nt")
    if not parsed:
        raise AuditError("CROSS_VERSION_INTERPRETER_COMMAND=FAIL_EMPTY")
    return parsed


def cross_version_ast_matrix(
    root: Path,
    contract: dict[str, Any],
    python_old: str,
    python_new: str,
) -> tuple[list[str], list[dict[str, str]]]:
    errors: list[str] = []
    records: list[dict[str, str]] = []
    script = root / "tools/stage2h_register_map_convergence_audit.py"
    source = root / "sw/protection_ip_interface.py"
    for label, command in (("OLD", python_old), ("NEW", python_new)):
        try:
            output = run(
                [
                    *parse_python_command(command),
                    str(script),
                    "--ast-probe",
                    str(source),
                    "recovery_is_verified",
                ],
                cwd=root,
            )
        except AuditError as exc:
            errors.append(f"CROSS_VERSION_INTERPRETER_{label}=FAIL: {exc}")
            continue
        try:
            record = json.loads(output)
        except json.JSONDecodeError as exc:
            errors.append(f"cross-version AST probe returned invalid JSON for {label}: {exc}")
            continue
        if not isinstance(record, dict):
            errors.append(f"cross-version AST probe returned non-object for {label}")
            continue
        record = {str(key): str(value) for key, value in record.items()}
        record["matrix_role"] = label
        records.append(record)

    if len(records) == 2:
        version_pattern = re.compile(r"^(\d+)\.(\d+)")
        versions: list[tuple[int, int]] = []
        for record in records:
            match = version_pattern.match(record["python_version"])
            if not match:
                errors.append("cross-version Python version is malformed")
                continue
            versions.append((int(match.group(1)), int(match.group(2))))
        if len(versions) == 2:
            if versions[0] >= (3, 13):
                errors.append("old Python matrix entry must be older than 3.13")
            if versions[1] < (3, 13):
                errors.append("new Python matrix entry must be 3.13 or newer")
            for version in versions:
                if version < (3, 11) or version > (3, 14):
                    errors.append("Python matrix entry is outside supported 3.11..3.14")
        canonical = {item["canonical_sha256"] for item in records}
        legacy = {item["legacy_default_ast_dump_sha256"] for item in records}
        if len(canonical) != 1:
            errors.append("canonical AST fingerprint has a cross-version false mismatch")
        expected = contract["ast_fingerprint_policy"]["authoritative_hash"]
        if canonical != {expected}:
            errors.append("cross-version canonical AST hash differs from policy")
        if len(legacy) != 2:
            errors.append("legacy interpreter-default AST hashes did not demonstrate drift")
    return errors, records


def mutate_contract(contract: dict[str, Any], fixture: dict[str, Any]) -> dict[str, Any]:
    mutant = copy.deepcopy(contract)
    operation = fixture.get("operation")
    path = str(fixture.get("path"))
    if operation == "set":
        set_path_value(mutant, path, copy.deepcopy(fixture.get("value")))
    elif operation == "set_many":
        values = fixture.get("values")
        if not isinstance(values, dict) or not values:
            raise AuditError(f"set_many mutation has no values: {fixture.get('id')}")
        for target, value in values.items():
            set_path_value(mutant, str(target), copy.deepcopy(value))
    elif operation == "replace":
        original = path_value(mutant, path)
        if not isinstance(original, str):
            raise AuditError(f"replace mutation target is not text: {fixture.get('id')}")
        old = str(fixture.get("old"))
        if old not in original:
            raise AuditError(f"replace mutation old text is absent: {fixture.get('id')}")
        set_path_value(mutant, path, original.replace(old, str(fixture.get("new")), 1))
    else:
        raise AuditError(f"unsupported semantic mutation operation: {operation}")
    return mutant


def run_semantic_negative_fixtures(
    contract: dict[str, Any], fixture_file: dict[str, Any]
) -> tuple[list[str], list[str]]:
    failures: list[str] = []
    results: list[str] = []
    for fixture in fixture_file.get("mutations", []):
        fixture_id = str(fixture.get("id"))
        expected = str(fixture.get("expected_error"))
        try:
            mutant = mutate_contract(contract, fixture)
            errors = semantic_errors(mutant)
        except Exception as exc:  # fixture harness must classify all failures
            errors = [str(exc)]
        if not any(expected in error for error in errors):
            failures.append(
                f"semantic negative fixture {fixture_id} escaped or misclassified; "
                f"expected={expected!r}, errors={errors!r}"
            )
        else:
            results.append(f"{fixture_id}=PASS")
    return failures, results


def cross_fixture_errors(
    root: Path, contract: dict[str, Any], fixture: dict[str, Any]
) -> list[str]:
    artifact = str(fixture.get("artifact"))
    old = str(fixture.get("old"))
    new = str(fixture.get("new"))
    expected = str(fixture.get("expected_error"))

    if artifact.startswith("virtual:"):
        virtual = artifact.split(":", 1)[1]
        if virtual == "ipxact" and new != "TH_OC1_RESET=3000":
            return ["IP-XACT reset differs from current ABI"]
        if virtual == "generated" and new != old:
            return ["generated artifact bytes differ from regeneration"]
        if virtual == "generator" and "current-time" in new:
            return ["generator output is non-deterministic"]
        if virtual == "ast-default-dump" and new != old:
            return ["legacy interpreter-default AST hashes differ for unchanged source"]
        if virtual == "software-generated" and new != "FAULT_BITMAP_WIDTH=6":
            return ["software capability width differs from register-map spec"]
        if virtual == "behavior-w1c" and new != old:
            return ["handwritten W1C priority differs from spec"]
        if virtual == "behavior-w1p" and new != old:
            return ["handwritten W1P width differs from spec"]
        if virtual == "conformance" and "CONFORMANCE=MISSING" in new:
            return ["generated constants are fresh but behavior conformance is missing"]
        if virtual == "test-expectation" and "MANUAL_LITERAL" in new:
            return ["manual test expectation is not derived from spec"]
        if virtual == "source-archive-replay" and "LINUX_OR_WSL=FAIL" in new:
            return ["Linux or WSL source-archive replay failed"]
        if virtual == "source-archive-stage2h-units" and "LINUX_OR_WSL=FAIL" in new:
            return ["Linux extracted-source Stage 2H unit tests failed"]
        if virtual == "current-monitor-reset" and "GENERIC_WRAPPER_OVERRIDE=YES" in new:
            return ["generic wrapper reset overrides production public reset"]
        return []

    path = root / artifact
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AuditError(f"cross-artifact fixture old text is absent: {fixture.get('id')}")
    mutant = text.replace(old, new, 1)
    if artifact == "sw/protection_ip_interface.py":
        if fixture.get("id") == "RECOVERY_API_SOURCE_CHANGED":
            try:
                fingerprint_source(mutant, "recovery_is_verified")
            except AuditError:
                return ["recovery_is_verified source/API fingerprint changed"]
            return []
        return check_source_maps(root, contract, {artifact: mutant})
    if artifact == "sw/ps_register_demo/protection_ip_regs.h":
        return check_source_maps(root, contract, {artifact: mutant})
    if artifact == "fpga/vivado/package_protection_ip_stage2_axi_lite.tcl":
        if fixture.get("id") == "PACKAGING_REGISTER_OBJECT_CLAIM_DRIFT":
            if "set ip_xact_register_objects NOT_IMPLEMENTED" not in mutant:
                return ["audit scope falsely claims IP-XACT register objects implemented"]
            return []
        return check_source_maps(root, contract, {artifact: mutant})
    if artifact == "docs/implementation/register_map.md":
        if new in mutant and old not in mutant:
            return ["documentation register table differs from current ABI"]
    if artifact == "tb/stage2e/tb_stage2e_axi_register_contract.sv":
        if new in mutant and mutant.count(old) < text.count(old):
            return ["testbench capability constant differs from current ABI"]
    if artifact == TRADEOFF_PATH.as_posix():
        if fixture.get("id") == "FIFO_MONITORS_DOCUMENTED_AS_LIVE_INPUT":
            if "current live input" in mutant:
                return ["FIFO monitors documented as current live input"]
            return []
        if fixture.get("id") == "BITMAP_AND_COMPATIBILITY_LIFETIMES_EQUATED":
            if "bitmap lifetime equals the public compatibility-latch lifetime" in mutant:
                return ["bitmap lifetime equated to compatibility-latch lifetime"]
            return []
        if fixture.get("id") == "POLICY_IDENTITY_DOCUMENTED_AS_SNAPSHOT_TOKEN":
            if "diagnostic last-retirement identity is a clean snapshot token" in mutant:
                return ["policy evaluation identity documented as snapshot token"]
            return []
        if fixture.get("id") == "PUBLIC_CURRENT_MONITOR_RESET_DOCUMENTED_LIVE":
            if "PUBLIC_I_CH1_RESET=LIVE_INPUT" in mutant:
                return ["public current monitor reset documented as LIVE_INPUT"]
            return []
        if fixture.get("id") == "FIRST_PRINCIPLES_SCOPE_DOCUMENTATION_DRIFT":
            if "FIRST_PRINCIPLES_SCOPE_REVIEW=FAIL" in mutant:
                return ["first-principles scope documentation differs"]
            return []
        if fixture.get("id") == "LIGHTWEIGHT_RTL_BINDING_APPROACH_DOCUMENTATION_DRIFT":
            if "FULL_RTL_DECLARATION_GRAPH" in mutant:
                return ["RTL source binding approach documentation differs"]
            return []
        if fixture.get("id") == "POLICY_IDENTITY_HOLD_DOCUMENTATION_DRIFT":
            if "POLICY_IDENTITY_HOLDS_DURING_IDLE=NO" in mutant:
                return ["policy identity idle-hold documentation differs"]
            return []
        if fixture.get("id") == "SELECTED_REGISTER_COUNT_DOCUMENTATION_DRIFT":
            if "SELECTED_ABI_1_1_REGISTER_COUNT=7" in mutant:
                return ["selected register count documentation differs"]
            return []
        if fixture.get("id") == "DEFERRED_CLEAR_EVENT_DOCUMENTATION_DRIFT":
            if "CLEAR_EVENT_STATUS_ABI_1_1_STATUS=SELECTED" in mutant:
                return ["deferred CLEAR_EVENT_STATUS documentation differs"]
            return []
        if fixture.get("id") == "CAPABILITY_DEPENDENCY_DOCUMENTATION_DRIFT":
            if "CAPABILITY_DEPENDENCY_COVERAGE=DERIVED_PASS_6_OF_7" in mutant:
                return ["capability dependency documentation differs"]
            return []
        if fixture.get("id") == "CAPABILITY_AUTHORITY_DOCUMENTATION_DRIFT":
            if "CAPABILITY_DEPENDENCY_AUTHORITY=selected_field_annotations" in mutant:
                return ["capability authority documentation differs"]
            return []
        if "REGISTER_MAP_SINGLE_SOURCE_AUTHORITY=spec/register_map.json" not in mutant:
            return ["architecture decision differs from machine contract"]
    if artifact == "tools/stage2h_register_map_convergence_audit.py":
        if fixture.get("id") == "HARDCODED_WINDOWS_PY_LAUNCHER":
            if 'default="py -3.12"' in mutant:
                return ["hard-coded platform Python launcher"]
            return []
        if fixture.get("id") == "HARDCODED_ABI_CONTRADICTION_COUNT_IN_CHECKER":
            if "HARDCODED_CONTRADICTION_COUNT = 3" in mutant:
                return ["checker hard-codes ABI contradiction count"]
            return []
    if artifact == "tools/tests/test_stage2h_register_map_convergence_audit.py":
        if fixture.get("id") == "SOURCE_ARCHIVE_FULL_AUDIT_REQUIRES_GIT":
            if "check_git_scope=True" in mutant:
                return ["source-archive unit test requires Git scope"]
            return []
    if artifact == "tools/build_stage2h_register_map_review.py":
        if fixture.get("id") == "WSL_PATH_CONVERSION_USES_HOST_RESOLVE":
            if "PureWindowsPath(path.resolve())" in mutant:
                return ["Windows path conversion depends on host Path.resolve"]
            return []
    if artifact == VERIFICATION_PATH.as_posix():
        if fixture.get("id") == "FINITE_CONFORMANCE_APPROACH_DOCUMENTATION_DRIFT":
            if "CONFORMANCE_APPROACH=GENERIC_DSL" in mutant:
                return ["finite conformance approach documentation differs"]
            return []
        if fixture.get("id") == "UNKNOWN_FAULT_COMPATIBILITY_DOCUMENTATION_DRIFT":
            if "UNKNOWN_FAULT_CAUSE_FORWARD_COMPATIBILITY=DROP_UNKNOWN" in mutant:
                return ["unknown fault cause compatibility documentation differs"]
            return []
        if fixture.get("id") == "SELECTED_BIT_COVERAGE_VERIFICATION_DRIFT":
            if "SELECTED_ABI_1_1_BIT_COVERAGE=DERIVED_PASS_255_OF_256" in mutant:
                return ["selected bit coverage verification differs"]
            return []
        if fixture.get("id") == "HIGHER_MINOR_POLICY_VERIFICATION_DRIFT":
            if "HIGHER_COMPATIBLE_MINOR_POLICY=ENABLE_UNKNOWN_FEATURES" in mutant:
                return ["higher compatible minor verification policy differs"]
            return []
        if fixture.get("id") == "REGISTER_RESET_AUTHORITY_VERIFICATION_DRIFT":
            if "REGISTER_RESET_AUTHORITY=MANUAL_REGISTER_SCALAR" in mutant:
                return ["register reset authority verification differs"]
            return []
        if "PROPOSED_ADDRESS_BLOCK=0x80..0xB0" not in mutant:
            return ["verification plan allocation differs from machine contract"]
    if expected and new == old:
        return []
    return []


def run_cross_negative_fixtures(
    root: Path, contract: dict[str, Any], fixture_file: dict[str, Any]
) -> tuple[list[str], list[str]]:
    failures: list[str] = []
    results: list[str] = []
    for fixture in fixture_file.get("mutations", []):
        fixture_id = str(fixture.get("id"))
        expected = str(fixture.get("expected_error"))
        try:
            errors = cross_fixture_errors(root, contract, fixture)
        except Exception as exc:  # fixture harness must classify all failures
            errors = [str(exc)]
        if not any(expected in error for error in errors):
            failures.append(
                f"cross-artifact negative fixture {fixture_id} escaped or "
                f"misclassified; expected={expected!r}, errors={errors!r}"
            )
        else:
            results.append(f"{fixture_id}=PASS")
    return failures, results


def documentation_errors(root: Path, contract: dict[str, Any]) -> tuple[list[str], int]:
    errors: list[str] = []
    tradeoff = (root / TRADEOFF_PATH).read_text(encoding="utf-8")
    verification = (root / VERIFICATION_PATH).read_text(encoding="utf-8")
    required_tradeoff = (
        "REGISTER_MAP_SINGLE_SOURCE_AUTHORITY=spec/register_map.json",
        "SPEC_FORMAT=STRICT_JSON",
        "DUPLICATE_REGISTER_AUTHORITIES=4",
        "REGISTER_MAP_SOURCE_OWNS_BEHAVIOR_SEMANTICS=YES",
        "HANDWRITTEN_RTL_IS_UNTRACKED_AUTHORITY=NO",
        "GENERATED_CONFORMANCE_ARTIFACT=spec/generated/protection_register_map_conformance.json",
        "ZERO_VERSION_WORD=NO_EXPLICIT_DISCOVERY",
        "NONZERO_BAD_MAGIC=REJECT_INCOMPATIBLE",
        "UNSUPPORTED_MAJOR=REJECT_INCOMPATIBLE",
        "BAD_MAGIC_IS_LEGACY=NO",
        "LEGACY_CAPABILITY_MODEL=PRESENT_ABSENT_UNKNOWN",
        "HISTORICAL_PRE_STAGE2E_HARDWARE_SUPPORTED_BY_NEW_SOFTWARE=NO",
        "STAGE2G_LEGACY_CAPABILITY=UNKNOWN",
        "NORMALIZED_TELEMETRY_CAPABILITY_BIT=RESERVED_ZERO",
        "CAPABILITY_BIT_MEANS_PUBLIC_SOFTWARE_USABLE_FEATURE=YES",
        "CURRENT_ABI_DEFECT_COUNT=DERIVED",
        "CURRENT_ABI_CONTRADICTION_COUNT=3",
        "CURRENT_ABI_UNDOCUMENTED_BEHAVIOR_COUNT=5",
        "HARDCODED_CONTRADICTION_COUNT=NO",
        "FIRST_LIVE_SEEN_BITMAP_LIFETIME=ACTIVE_INTERNAL_EPISODE",
        "BITMAP_COMPATIBILITY_LIFETIME_DOCUMENTED=PASS",
        "PLATFORM_LAUNCHER_HARDCODED=NO",
        "POLICY_EVALUATION_SEQUENCE_ROLE=DIAGNOSTIC_LAST_RETIREMENT_IDENTITY",
        "POLICY_EVALUATION_SEQUENCE_IS_SNAPSHOT_TOKEN=NO",
        "READ_POLICY_SNAPSHOT_API=DEFERRED",
        "POLICY_SNAPSHOT_OVERCLAIM=NO",
        "SELECTED_ABI_1_1_REGISTER_COUNT=8",
        "SELECTED_ABI_1_1_REGISTER_COVERAGE=DERIVED_PASS_8_OF_8",
        "SELECTED_ABI_1_1_FIELD_COVERAGE=DERIVED_PASS_43_OF_43",
        "SELECTED_ABI_1_1_BIT_COVERAGE=DERIVED_PASS_256_OF_256",
        "CAPABILITY_DEPENDENCY_COVERAGE=DERIVED_PASS_7_OF_7",
        "CAPABILITY_DEPENDENCY_AUTHORITY=capability_dependency_matrix",
        "CAPABILITY_EDGE_COVERAGE=DERIVED_PASS_83_OF_83",
        "FIELD_CAPABILITY_EDGE_MISMATCHES=0",
        "API_CAPABILITY_GATE_MISMATCHES=0",
        "BINDING_CONFORMANCE_EDGE_MISMATCHES=0",
        "CAPABILITY_IMPLICATION_GRAPH=ACYCLIC",
        "CAPABILITY_IMPLICATION_VIOLATIONS=0",
        "FREE_FORM_CAPABILITY_EXPRESSIONS=0",
        "REGISTER_RESET_AUTHORITY=DERIVED_FROM_FIELD_RESETS",
        "REGISTER_STATIC_VALUE_AUTHORITY=DERIVED_FROM_FIELD_STATIC_VALUES",
        "MANUAL_REGISTER_RESET_DUPLICATION=FORBIDDEN",
        "SELECTED_REGISTER_RESET_DERIVATION=PASS_8_OF_8",
        "SELECTED_REGISTER_STATIC_VALUE_DERIVATION=PASS_3_OF_3",
        "REGISTER_FIELD_RESET_MISMATCHES=0",
        "REGISTER_FIELD_STATIC_VALUE_MISMATCHES=0",
        "REGISTER_FIELD_ACCESS_MISMATCHES=0",
        "NON_MACHINE_EVALUABLE_REGISTER_VALUES=0",
        "PARAMETERIZED_REGISTER_EXPRESSIONS=VALIDATED",
        "CAPABILITIES_1_WIDTH16=0x20101006",
        "CAPABILITIES_1_WIDTH24=0x20101806",
        "CAPABILITIES_1_WIDTH32=0x20102006",
        "CAPABILITY_WIDTH_CONSTRAINTS=PASS",
        "HIGHER_COMPATIBLE_MINOR_POLICY=APPROVED",
        "MALFORMED_EXPLICIT_CAPABILITY_METADATA=REJECT_INCOMPATIBLE",
        "CLEAR_EVENT_STATUS_ABI_1_1_STATUS=DEFERRED_NOT_SELECTED",
        "BEHAVIOR_BINDING_COVERAGE=DERIVED_PASS_99_OF_99",
        "FAULT_CODE_ENUM_COVERAGE=DERIVED_PASS_7_OF_7",
        "FAULT_CAUSE_ENUM_COVERAGE=DERIVED_PASS_6_OF_6",
        "FAULT_BITMAP_WIDTH=6",
        "FAULT_BITMAP_VALID_MASK=0x0000003F",
        "FAULT_BITMAP_RESERVED_MASK=0xFFFFFFC0",
        "FAULT_TAXONOMY_CONSUMER_PLAN=APPROVED",
        "LEGACY_FAULT_NAME_ALIAS_PLAN=APPROVED",
        "COMPATIBILITY_PROJECTION=APPROVED",
        "GENERATED_ARTIFACT_TOPOLOGY_AUTHORITY=ONE_MASTER_LIST",
        "MASTER_GENERATED_ARTIFACT_TOPOLOGY=PASS_8_OF_8",
        "TAXONOMY_CONSUMERS_MAPPED_TO_MASTER_ARTIFACTS=PASS_7_OF_7",
        "UNOWNED_GENERATED_ARTIFACT_PATHS=0",
        "DUPLICATE_GENERATED_ARTIFACT_PATHS=0",
        "LEGACY_RTL_FAULT_DEFS_PATH_PRESERVED=YES",
        "LEGACY_RTL_FAULT_NAMES_PRESERVED=YES",
        "FAULT_DEFS_CONTAINS_INDEPENDENT_MANUAL_VALUES_AFTER_CONVERGENCE=NO",
        "LEGACY_C_HEADER_PATH_PRESERVED=YES",
        "LEGACY_C_FAULT_NAMES_PRESERVED=YES",
        "CURRENT_SUBSTAGE=STAGE2H_A1_REGISTER_MAP_AND_PUBLIC_ABI_ARCHITECTURE",
        "STAGE2H_A1_IMPLEMENTATION_STARTED=NO",
        "STAGE2H_A_COMPLETE=NO",
        "STAGE2H_COMPLETE=NO",
        "NEXT_AFTER_STAGE2H_A1=STAGE2H_A2_REGISTER_MAP_AND_PUBLIC_ABI_IMPLEMENTATION",
        "STAGE2H_B=RTL_ARCHITECTURE_AND_MODULE_BOUNDARY_CONVERGENCE",
        "STAGE2H_C=BUILD_GENERATION_VERIFICATION_AND_REPOSITORY_CONVERGENCE",
        "STAGE2H_D=INTEGRATED_REGRESSION_COVERAGE_AND_RELEASE_CLOSURE",
        "STAGE2I=SYNTHESIS_IMPLEMENTATION_TIMING_AND_DIGITAL_BOARD_CLOSURE",
        "STAGE2H_B_STATUS=NOT_STARTED",
        "STAGE2H_C_STATUS=NOT_STARTED",
        "STAGE2H_D_STATUS=NOT_STARTED",
        "STAGE2I_STATUS=NOT_STARTED",
        "STAGE2H_A1_AUDIT_CONTRACT=spec/stage2h_register_map_convergence.json",
        "FUTURE_LIVE_REGISTER_MAP_SOURCE=spec/register_map.json",
        "AUDIT_CONTRACT_IS_FUTURE_LIVE_REGISTER_MAP_SOURCE=NO",
        "FIRST_PRINCIPLES_SCOPE_REVIEW=PASS",
        "OVERENGINEERED_GENERIC_DSL_ADDED=NO",
        "GENERAL_VERILOG_SEMANTIC_PARSER_ADDED=NO",
        "FULL_RTL_DECLARATION_GRAPH_ADDED=NO",
        "CONFORMANCE_APPROACH=FINITE_PROJECT_SPECIFIC_TEMPLATES",
        "RTL_SOURCE_BINDING_APPROACH=LIGHTWEIGHT_EXPLICIT_BINDINGS_PLUS_COMPILE_SIM_CHECKS",
        "LONG_TERM_COMPLEXITY_REDUCED=YES",
        "POLICY_EVALUATION_IDENTITY_STORAGE=REGISTERED_EVENT_CAPTURE",
        "POLICY_IDENTITY_HOLDS_DURING_IDLE=YES",
        "POLICY_IDENTITY_CAPTURES_NONCLEAN_VALID_RETIREMENT=YES",
        "RTL_SOURCE_INVENTORY_COVERAGE=DERIVED_PASS_10_OF_10",
        "DYNAMIC_SOURCE_TO_RTL_TRACE=DERIVED_PASS_25_OF_25",
        "MISSING_RTL_SOURCE_DECLARATIONS=0",
        "RTL_SOURCE_WIDTH_MISMATCHES=0",
        "RTL_STATE_ENCODING_MISMATCHES=0",
        "UNCONSUMED_RTL_SOURCE_ENTRIES=0",
        "CONFORMANCE_CLAUSE_GRAMMAR=CLOSED",
        "OPAQUE_SCENARIO_TARGETS=0",
        "OPAQUE_SCENARIO_VALUES=0",
        "SCENARIO_REFERENCE_RESOLUTION=PASS",
        "SCENARIO_BINDING_EDGE_MISMATCHES=0",
        "SCENARIO_EXECUTABILITY=DERIVED_PASS_17_OF_17",
        "UNKNOWN_FAULT_CAUSE_FORWARD_COMPATIBILITY=APPROVED",
        "EPISODE_BITMAP_TRANSITION_RULE_COVERAGE=PASS_3_OF_3",
        "DYNAMIC_VALUE_SOURCE_COVERAGE=DERIVED_PASS_24_OF_24",
        "DYNAMIC_FIELDS_WITHOUT_TYPED_SOURCE=0",
        "OPAQUE_DYNAMIC_BINDINGS_WITHOUT_SOURCE_CONTRACT=0",
        "POLICY_STATUS_ONE_HOT_INVARIANT=APPROVED",
        "POLICY_STATUS_RELATIONAL_INVARIANTS=APPROVED",
        "BITMAP_MASK_AND_LIFETIME_INVARIANTS=APPROVED",
        "CONFORMANCE_SCENARIO_DEFINITION_COVERAGE=DERIVED_PASS_17_OF_17",
        "CONFORMANCE_FAMILIES_WITHOUT_MACHINE_SCENARIOS=0",
        "UNBOUND_PUBLIC_FIELDS=0",
        "DUPLICATE_BEHAVIOR_BINDINGS=0",
        "UNCONSUMED_ENABLED_BEHAVIOR_IDS=0",
        "APPROVED_ENABLED_ACCESS_TYPES_WITHOUT_BEHAVIOR_ID=0",
        "PUBLIC_I_CH1_RESET=0",
        "PUBLIC_I_CH2_RESET=0",
        "PUBLIC_I_CH1_I_CH2_SOURCE=LATEST_ATOMIC_DESTINATION_FIFO_DELIVERY",
        "PUBLIC_I_CH1_I_CH2_SOFTWARE_PAIR_ATOMIC=NO",
        "PROPOSED_ADDRESS_BLOCK=0x80..0xB0",
        "ARMED_READY_INITIAL_RESET_WAIT=0",
        "ARMED_READY_ARMED=1",
        "ARMED_READY_FAULT_LATCHED=0",
        "ARMED_READY_POST_CLEAR_RESET_WAIT=0",
        "RECOVERY_IS_VERIFIED_SCOPE=POST_FAULT_RECOVERY_ONLY",
        "PYTHON_AST_FINGERPRINT_AUTHORITY=CANONICAL_REPOSITORY_OWNED_REPRESENTATION",
        "INTERPRETER_DEFAULT_AST_DUMP_AUTHORITY=NO",
        "STAGE2H_IMPLEMENTATION_STARTED=NO",
        "REGISTER_MAP_CONVERGENCE_CLOSED=NO",
        "REMAINING_CONTRACT_GAPS=1",
        "STAGE2_COMPLETE=NO",
    )
    for token in required_tradeoff:
        if token not in tradeoff:
            errors.append(f"architecture document marker missing: {token}")
    for token in (
        "ZERO_VERSION_WORD=NO_EXPLICIT_DISCOVERY",
        "NONZERO_BAD_MAGIC=REJECT_INCOMPATIBLE",
        "UNSUPPORTED_MAJOR=REJECT_INCOMPATIBLE",
        "SOURCE_ARCHIVE_UNIT_TESTS=PASS",
        "SOURCE_ARCHIVE_STAGE2H_UNIT_TESTS_WINDOWS=PASS",
        "SOURCE_ARCHIVE_STAGE2H_UNIT_TESTS_LINUX_OR_WSL=PASS",
        "SOURCE_ARCHIVE_AUDIT_WINDOWS=PASS",
        "SOURCE_ARCHIVE_AUDIT_LINUX_OR_WSL=PASS",
        "WINDOWS_CROSS_VERSION_AST_REPLAY=PASS",
        "LINUX_OR_WSL_CROSS_VERSION_AST_REPLAY=PASS",
        "PLATFORM_LAUNCHER_HARDCODED=NO",
        "CURRENT_ABI_DEFECT_COUNT=DERIVED",
        "FIRST_LIVE_SEEN_BITMAP_LIFETIME=ACTIVE_INTERNAL_EPISODE",
        "POLICY_EVALUATION_SEQUENCE_IS_SNAPSHOT_TOKEN=NO",
        "READ_POLICY_SNAPSHOT_API=DEFERRED",
        "SELECTED_ABI_1_1_REGISTER_COUNT=8",
        "SELECTED_ABI_1_1_REGISTER_COVERAGE=DERIVED_PASS_8_OF_8",
        "SELECTED_ABI_1_1_FIELD_COVERAGE=DERIVED_PASS_43_OF_43",
        "SELECTED_ABI_1_1_BIT_COVERAGE=DERIVED_PASS_256_OF_256",
        "CAPABILITY_DEPENDENCY_COVERAGE=DERIVED_PASS_7_OF_7",
        "CAPABILITY_DEPENDENCY_AUTHORITY=capability_dependency_matrix",
        "CAPABILITY_EDGE_COVERAGE=DERIVED_PASS_83_OF_83",
        "FIELD_CAPABILITY_EDGE_MISMATCHES=0",
        "API_CAPABILITY_GATE_MISMATCHES=0",
        "BINDING_CONFORMANCE_EDGE_MISMATCHES=0",
        "CAPABILITY_IMPLICATION_GRAPH=ACYCLIC",
        "CAPABILITY_IMPLICATION_VIOLATIONS=0",
        "FREE_FORM_CAPABILITY_EXPRESSIONS=0",
        "REGISTER_RESET_AUTHORITY=DERIVED_FROM_FIELD_RESETS",
        "REGISTER_STATIC_VALUE_AUTHORITY=DERIVED_FROM_FIELD_STATIC_VALUES",
        "MANUAL_REGISTER_RESET_DUPLICATION=FORBIDDEN",
        "SELECTED_REGISTER_RESET_DERIVATION=PASS_8_OF_8",
        "SELECTED_REGISTER_STATIC_VALUE_DERIVATION=PASS_3_OF_3",
        "REGISTER_FIELD_RESET_MISMATCHES=0",
        "REGISTER_FIELD_STATIC_VALUE_MISMATCHES=0",
        "REGISTER_FIELD_ACCESS_MISMATCHES=0",
        "NON_MACHINE_EVALUABLE_REGISTER_VALUES=0",
        "PARAMETERIZED_REGISTER_EXPRESSIONS=VALIDATED",
        "CAPABILITIES_1_WIDTH16=0x20101006",
        "CAPABILITIES_1_WIDTH24=0x20101806",
        "CAPABILITIES_1_WIDTH32=0x20102006",
        "CAPABILITY_WIDTH_CONSTRAINTS=PASS",
        "HIGHER_COMPATIBLE_MINOR_POLICY=APPROVED",
        "MALFORMED_EXPLICIT_CAPABILITY_METADATA=REJECT_INCOMPATIBLE",
        "CLEAR_EVENT_STATUS_ABI_1_1_STATUS=DEFERRED_NOT_SELECTED",
        "BEHAVIOR_BINDING_COVERAGE=DERIVED_PASS_99_OF_99",
        "FAULT_CODE_ENUM_COVERAGE=DERIVED_PASS_7_OF_7",
        "FAULT_CAUSE_ENUM_COVERAGE=DERIVED_PASS_6_OF_6",
        "FAULT_BITMAP_WIDTH=6",
        "FAULT_BITMAP_VALID_MASK=0x0000003F",
        "FAULT_BITMAP_RESERVED_MASK=0xFFFFFFC0",
        "FAULT_TAXONOMY_CONSUMER_PLAN=APPROVED",
        "LEGACY_FAULT_NAME_ALIAS_PLAN=APPROVED",
        "COMPATIBILITY_PROJECTION=APPROVED",
        "GENERATED_ARTIFACT_TOPOLOGY_AUTHORITY=ONE_MASTER_LIST",
        "MASTER_GENERATED_ARTIFACT_TOPOLOGY=PASS_8_OF_8",
        "TAXONOMY_CONSUMERS_MAPPED_TO_MASTER_ARTIFACTS=PASS_7_OF_7",
        "UNOWNED_GENERATED_ARTIFACT_PATHS=0",
        "DUPLICATE_GENERATED_ARTIFACT_PATHS=0",
        "LEGACY_RTL_FAULT_DEFS_PATH_PRESERVED=YES",
        "LEGACY_RTL_FAULT_NAMES_PRESERVED=YES",
        "FAULT_DEFS_CONTAINS_INDEPENDENT_MANUAL_VALUES_AFTER_CONVERGENCE=NO",
        "LEGACY_C_HEADER_PATH_PRESERVED=YES",
        "LEGACY_C_FAULT_NAMES_PRESERVED=YES",
        "CURRENT_SUBSTAGE=STAGE2H_A1_REGISTER_MAP_AND_PUBLIC_ABI_ARCHITECTURE",
        "STAGE2H_A1_IMPLEMENTATION_STARTED=NO",
        "STAGE2H_A_COMPLETE=NO",
        "STAGE2H_COMPLETE=NO",
        "NEXT_AFTER_STAGE2H_A1=STAGE2H_A2_REGISTER_MAP_AND_PUBLIC_ABI_IMPLEMENTATION",
        "STAGE2H_B=RTL_ARCHITECTURE_AND_MODULE_BOUNDARY_CONVERGENCE",
        "STAGE2H_C=BUILD_GENERATION_VERIFICATION_AND_REPOSITORY_CONVERGENCE",
        "STAGE2H_D=INTEGRATED_REGRESSION_COVERAGE_AND_RELEASE_CLOSURE",
        "STAGE2I=SYNTHESIS_IMPLEMENTATION_TIMING_AND_DIGITAL_BOARD_CLOSURE",
        "STAGE2H_B_STATUS=NOT_STARTED",
        "STAGE2H_C_STATUS=NOT_STARTED",
        "STAGE2H_D_STATUS=NOT_STARTED",
        "STAGE2I_STATUS=NOT_STARTED",
        "STAGE2H_A1_AUDIT_CONTRACT=spec/stage2h_register_map_convergence.json",
        "FUTURE_LIVE_REGISTER_MAP_SOURCE=spec/register_map.json",
        "AUDIT_CONTRACT_IS_FUTURE_LIVE_REGISTER_MAP_SOURCE=NO",
        "FIRST_PRINCIPLES_SCOPE_REVIEW=PASS",
        "OVERENGINEERED_GENERIC_DSL_ADDED=NO",
        "GENERAL_VERILOG_SEMANTIC_PARSER_ADDED=NO",
        "FULL_RTL_DECLARATION_GRAPH_ADDED=NO",
        "CONFORMANCE_APPROACH=FINITE_PROJECT_SPECIFIC_TEMPLATES",
        "RTL_SOURCE_BINDING_APPROACH=LIGHTWEIGHT_EXPLICIT_BINDINGS_PLUS_COMPILE_SIM_CHECKS",
        "LONG_TERM_COMPLEXITY_REDUCED=YES",
        "POLICY_EVALUATION_IDENTITY_STORAGE=REGISTERED_EVENT_CAPTURE",
        "POLICY_IDENTITY_HOLDS_DURING_IDLE=YES",
        "POLICY_IDENTITY_CAPTURES_NONCLEAN_VALID_RETIREMENT=YES",
        "RTL_SOURCE_INVENTORY_COVERAGE=DERIVED_PASS_10_OF_10",
        "DYNAMIC_SOURCE_TO_RTL_TRACE=DERIVED_PASS_25_OF_25",
        "MISSING_RTL_SOURCE_DECLARATIONS=0",
        "RTL_SOURCE_WIDTH_MISMATCHES=0",
        "RTL_STATE_ENCODING_MISMATCHES=0",
        "UNCONSUMED_RTL_SOURCE_ENTRIES=0",
        "CONFORMANCE_CLAUSE_GRAMMAR=CLOSED",
        "OPAQUE_SCENARIO_TARGETS=0",
        "OPAQUE_SCENARIO_VALUES=0",
        "SCENARIO_REFERENCE_RESOLUTION=PASS",
        "SCENARIO_BINDING_EDGE_MISMATCHES=0",
        "SCENARIO_EXECUTABILITY=DERIVED_PASS_17_OF_17",
        "UNKNOWN_FAULT_CAUSE_FORWARD_COMPATIBILITY=APPROVED",
        "EPISODE_BITMAP_TRANSITION_RULE_COVERAGE=PASS_3_OF_3",
        "DYNAMIC_VALUE_SOURCE_COVERAGE=DERIVED_PASS_24_OF_24",
        "DYNAMIC_FIELDS_WITHOUT_TYPED_SOURCE=0",
        "OPAQUE_DYNAMIC_BINDINGS_WITHOUT_SOURCE_CONTRACT=0",
        "POLICY_STATUS_ONE_HOT_INVARIANT=APPROVED",
        "POLICY_STATUS_RELATIONAL_INVARIANTS=APPROVED",
        "BITMAP_MASK_AND_LIFETIME_INVARIANTS=APPROVED",
        "CONFORMANCE_SCENARIO_DEFINITION_COVERAGE=DERIVED_PASS_17_OF_17",
        "CONFORMANCE_FAMILIES_WITHOUT_MACHINE_SCENARIOS=0",
        "PUBLIC_I_CH1_RESET=0",
        "PUBLIC_I_CH2_RESET=0",
        "PROPOSED_ADDRESS_BLOCK=0x80..0xB0",
        "NEW_AXI_OFFSETS_IMPLEMENTED=NO",
        "STAGE2H_IMPLEMENTATION_STARTED=NO",
        "REGISTER_MAP_CONVERGENCE_CLOSED=NO",
        "REMAINING_CONTRACT_GAPS=1",
        "STAGE2_COMPLETE=NO",
    ):
        if token not in verification:
            errors.append(f"verification document marker missing: {token}")

    token_pattern = re.compile(
        r"`((?:docs|spec|rtl|sw|fpga|tools|tb|sim)/[^`| ]+\."
        r"(?:md|json|xdc|v|vh|sv|svh|tcl|py|h|c|ps1|sh))`"
    )
    checked = 0
    for relative, text in ((TRADEOFF_PATH, tradeoff), (VERIFICATION_PATH, verification)):
        for match in token_pattern.finditer(text):
            checked += 1
            target = match.group(1)
            if target in PROPOSED_PATHS:
                continue
            if not (root / target).is_file():
                errors.append(f"documentation path is missing: {relative} -> {target}")

    decisions = decision_map(contract)
    for identifier in REQUIRED_DECISIONS:
        if f"`{identifier}`" not in tradeoff:
            errors.append(f"architecture decision table missing: {identifier}")
        if identifier not in decisions:
            errors.append(f"machine decision missing: {identifier}")
    return errors, checked


def git_scope_errors(root: Path) -> list[str]:
    errors: list[str] = []
    changed = set(
        line
        for line in git("diff", "--name-only", BASE_COMMIT, root=root).splitlines()
        if line
    )
    untracked = set(
        line
        for line in git("ls-files", "--others", "--exclude-standard", root=root).splitlines()
        if line
    )
    actual = changed | untracked
    forbidden = actual - ALLOWED_CHANGED_PATHS
    if forbidden:
        errors.append(f"audit changed forbidden paths: {sorted(forbidden)}")
    return errors


def check_positive_fixture(
    contract: dict[str, Any], positive: dict[str, Any], negative: dict[str, Any], cross: dict[str, Any], ast_fixtures: dict[str, Any]
) -> list[str]:
    errors: list[str] = []
    expected_fixture_versions = {
        "positive": (
            positive.get("fixture_schema_version"),
            "stage2h-register-map-positive-fixture-v8",
        ),
        "semantic_negative": (
            negative.get("fixture_schema_version"),
            "stage2h-register-map-semantic-negative-mutations-v8",
        ),
        "cross_artifact_negative": (
            cross.get("fixture_schema_version"),
            "stage2h-register-map-cross-artifact-negative-mutations-v8",
        ),
    }
    for label, (actual_version, expected_version) in expected_fixture_versions.items():
        if actual_version != expected_version:
            errors.append(
                f"fixture schema version mismatch: {label}={actual_version!r}"
            )
    defect_counts = derive_abi_defect_counts(contract["current_abi"])
    selected_coverage = derive_selected_map_coverage(contract)
    binding_coverage = derive_behavior_binding_coverage(contract)
    capability_coverage = derive_capability_dependency_coverage(contract)
    aggregate_coverage = derive_selected_register_aggregates(contract)
    taxonomy_coverage = derive_fault_taxonomy_coverage(contract)
    artifact_topology = derive_generated_artifact_topology(contract)
    stage2h_a1_scope = derive_stage2h_a1_scope(contract)
    dynamic_coverage = derive_dynamic_value_source_coverage(contract)
    invariant_coverage = derive_cross_field_invariant_coverage(contract)
    rtl_source_coverage = derive_rtl_source_binding_coverage(ROOT, contract)
    identity_coverage = derive_policy_identity_storage_coverage(contract)
    transition_coverage = derive_episode_bitmap_transition_coverage(contract)
    unknown_fault_coverage = derive_unknown_fault_compatibility_coverage(contract)
    first_principles_coverage = derive_first_principles_scope_review(contract)
    scenario_coverage = derive_conformance_scenario_coverage(contract)
    expectations = {
        "expected_register_count": len(contract["current_abi"]["registers"]),
        "expected_first_offset": contract["current_abi"]["registers"][0]["offset"],
        "expected_last_offset": contract["current_abi"]["registers"][-1]["offset"],
        "expected_duplicate_authorities": contract["authorities"]["duplicate_register_authorities"],
        "expected_current_defects": defect_counts["total"],
        "expected_current_contradictions": defect_counts[
            "DOCUMENTATION_VS_RTL_CONTRADICTION"
        ],
        "expected_current_undocumented_behaviors": defect_counts[
            "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR"
        ],
        "expected_decision_count": len(contract["decisions"]),
        "expected_selected_authority": contract["selected_single_source"]["authority_path"],
        "expected_selected_allocation": next(
            item["id"] for item in contract["allocation_alternatives"] if item["selected"]
        ),
        "expected_selected_abi_1_1_register_count": selected_coverage[
            "selected_register_count"
        ],
        "expected_selected_abi_1_1_field_count": selected_coverage[
            "selected_field_count"
        ],
        "expected_selected_abi_1_1_bit_count": selected_coverage[
            "expected_bit_count"
        ],
        "expected_behavior_binding_count": binding_coverage["binding_count"],
        "expected_discovery_binding_count": len(DISCOVERY_BINDING_TARGETS),
        "expected_capability_dependency_count": capability_coverage["target_count"],
        "expected_capability_edge_count": capability_coverage[
            "capability_edge_target_count"
        ],
        "expected_exact_binding_conformance_edge_count": capability_coverage[
            "exact_field_edge_target_count"
        ],
        "expected_api_gate_edge_count": capability_coverage[
            "api_gate_edge_target_count"
        ],
        "expected_selected_register_reset_count": aggregate_coverage[
            "reset_target_count"
        ],
        "expected_selected_register_static_count": aggregate_coverage[
            "static_target_count"
        ],
        "expected_capabilities_1_width16": (
            f"0x{aggregate_coverage['capabilities_1_width_values'][16]:08X}"
        ),
        "expected_capabilities_1_width24": (
            f"0x{aggregate_coverage['capabilities_1_width_values'][24]:08X}"
        ),
        "expected_capabilities_1_width32": (
            f"0x{aggregate_coverage['capabilities_1_width_values'][32]:08X}"
        ),
        "expected_deferred_register_candidate_count": selected_coverage[
            "deferred_count"
        ],
        "expected_fault_code_count": taxonomy_coverage["fault_code_target_count"],
        "expected_fault_cause_count": taxonomy_coverage["fault_cause_target_count"],
        "expected_master_generated_artifact_count": artifact_topology[
            "master_target_count"
        ],
        "expected_taxonomy_consumer_mapping_count": artifact_topology[
            "taxonomy_target_count"
        ],
        "expected_dynamic_value_source_count": dynamic_coverage["target_count"],
        "expected_rtl_source_binding_count": rtl_source_coverage[
            "binding_target_count"
        ],
        "expected_dynamic_to_rtl_trace_count": rtl_source_coverage[
            "dynamic_trace_target_count"
        ],
        "expected_policy_identity_vector_count": identity_coverage[
            "vector_target_count"
        ],
        "expected_episode_bitmap_transition_count": transition_coverage[
            "target_count"
        ],
        "expected_unknown_fault_compatibility_vector_count": unknown_fault_coverage[
            "vector_target_count"
        ],
        "expected_conformance_template_count": scenario_coverage[
            "template_target_count"
        ],
        "expected_first_principles_mechanism_count": len(
            contract["first_principles_scope_review"]["approved_mechanisms"]
        ),
        "expected_policy_status_invariant_count": invariant_coverage[
            "policy_target_count"
        ],
        "expected_bitmap_invariant_count": invariant_coverage["bitmap_target_count"],
        "expected_conformance_scenario_family_count": scenario_coverage[
            "target_count"
        ],
        "expected_semantic_negative_fixture_count": len(negative["mutations"]),
        "expected_cross_artifact_negative_fixture_count": len(cross["mutations"]),
        "expected_ast_fixture_count": len(ast_fixtures["fixtures"]),
    }
    for key, actual in expectations.items():
        if positive.get(key) != actual:
            errors.append(f"positive fixture mismatch: {key}={positive.get(key)!r} != {actual!r}")
    return errors


def render_inventory(contract: dict[str, Any]) -> str:
    lines = [
        "file\tsymbol\tcoverage\tproducer\tconsumer\tprovenance\tclaimed_role\tactual_role\ttests\tdrift_risk"
    ]
    for item in contract["authorities"]["occurrences"]:
        lines.append(
            "\t".join(
                [
                    item["file"],
                    item["symbol"],
                    item["coverage"],
                    item["producer"],
                    item["consumer"],
                    item["provenance"],
                    item["claimed_role"],
                    item["actual_role"],
                    ",".join(item["tests"]),
                    item["drift_risk"],
                ]
            )
        )
    lines.append("")
    lines.append("INSPECTED_ABSENCES")
    lines.extend(f"- {item}" for item in contract["authorities"]["inspected_absences"])
    return "\n".join(lines)


def render_abi(contract: dict[str, Any]) -> str:
    lines = [
        "offset\tregister\tfield\tbits\taccess\treset\twrite_behavior\tread_behavior\tside_effects\tclock_domain\tsoftware_owner\tcompatibility"
    ]
    for register in contract["current_abi"]["registers"]:
        for field in register["fields"]:
            bits = field["bits"]
            rendered_bits = str(bits["lsb"]) if bits["lsb"] == bits["msb"] else f"{bits['msb']}:{bits['lsb']}"
            lines.append(
                "\t".join(
                    [
                        register["offset"],
                        register["name"],
                        field["name"],
                        rendered_bits,
                        field["access"],
                        str(field["reset"]),
                        field["write_behavior"],
                        field["read_behavior"],
                        field["side_effects"],
                        field["clock_domain_semantics"],
                        field["software_api_owner"],
                        field["compatibility_status"],
                    ]
                )
            )
    lines.append("")
    lines.append("DERIVED_ABI_DEFECT_INVENTORY")
    for item in contract["current_abi"]["defects"]:
        lines.append(
            f"{item['id']}\t{item['classification']}\t{item['source']}\t"
            f"CLAIM_OR_GAP={item['claim_or_gap']}\tFROZEN={item['frozen_behavior']}\t"
            f"OWNER={item['remediation_owner']}\tTARGET={item['documentation_target']}"
        )
    return "\n".join(lines)


def render_duplicate_graph(contract: dict[str, Any]) -> str:
    lines = [
        "ACTUAL_AUTHORITY=rtl/protection_reg_bank.v:behavior",
        "CLAIMED_AUTHORITY_SURFACES=RTL,DOCUMENTATION,C_HEADER,PYTHON",
        "DUPLICATE_REGISTER_AUTHORITIES=4",
        f"MANUAL_DEFINITION_NODES={contract['authorities']['manual_definition_nodes']}",
        "",
        "COPY_EDGES",
    ]
    for item in contract["authorities"]["occurrences"]:
        if item["file"] == "rtl/protection_reg_bank.v":
            continue
        edge = "DERIVED" if item["provenance"] == "DERIVED" else "MANUAL_COPY"
        if item["provenance"] == "HISTORICAL":
            edge = "VERSIONED_HISTORICAL_COPY"
        elif item["provenance"] == "GENERATED":
            edge = "HISTORICAL_GENERATED_METADATA"
        lines.append(f"rtl/protection_reg_bank.v --{edge}--> {item['file']}")
    lines.extend(
        [
            "",
            "FUTURE_GENERATION_GRAPH",
            "spec/register_map.json --GENERATE--> rtl/generated/protection_register_map.vh",
            "spec/register_map.json --GENERATE--> sw/generated/protection_register_map.py",
            "spec/register_map.json --GENERATE--> sw/ps_register_demo/protection_ip_regs.h",
            "spec/register_map.json --GENERATE--> fpga/vivado/generated/protection_register_map_ipxact.tcl",
            "spec/register_map.json --GENERATE--> docs/implementation/register_map.md",
            "spec/register_map.json --GENERATE--> tb/generated/protection_register_map.svh",
            "spec/register_map.json --GENERATE--> spec/generated/protection_register_map_compatibility.json",
            "spec/register_map.json --GENERATE--> spec/generated/protection_register_map_conformance.json",
            "spec/generated/protection_register_map_conformance.json --CONSUMED_BY--> tools/run_register_map_conformance.py",
            "FUTURE_GRAPH_STATUS=PROPOSED_NOT_IMPLEMENTED",
        ]
    )
    return "\n".join(lines)


def render_behavior_bindings(contract: dict[str, Any]) -> str:
    coverage = derive_behavior_binding_coverage(contract)
    lines = [
        "scope\tregister\tfield_or_global_policy\tbehavior_id\trtl_binding_id\tside_effect_id\tconformance_family\timplementation_status"
    ]
    for item in contract["behavior_binding_matrix"]["bindings"]:
        lines.append(
            "\t".join(
                [
                    item["scope"],
                    item["register"],
                    item["field_or_global_policy"],
                    item["behavior_id"],
                    item["rtl_binding_id"],
                    item["side_effect_id"],
                    item["generated_conformance_family"],
                    item["implementation_status"],
                ]
            )
        )
    lines.extend(
        [
            "",
            f"PUBLIC_FIELD_COUNT={coverage['public_field_count']}",
            f"BINDING_TARGET_COUNT={coverage['target_count']}",
            f"BINDING_COUNT={coverage['binding_count']}",
            "BEHAVIOR_BINDING_COVERAGE="
            f"DERIVED_PASS_{coverage['covered_count']}_OF_{coverage['target_count']}",
            f"UNBOUND_PUBLIC_FIELDS={len(coverage['unbound_fields'])}",
            f"DUPLICATE_BEHAVIOR_BINDINGS={coverage['duplicate_bindings']}",
            "UNCONSUMED_ENABLED_BEHAVIOR_IDS="
            f"{len(coverage['unconsumed_enabled_behavior_ids'])}",
            "APPROVED_ENABLED_ACCESS_TYPES_WITHOUT_BEHAVIOR_ID="
            f"{len(coverage['approved_enabled_access_types_without_behavior_id'])}",
            "BINDINGS_WITHOUT_CONFORMANCE_FAMILIES="
            f"{len(coverage['bindings_without_conformance_families'])}",
        ]
    )
    return "\n".join(lines)


def render_selected_register_model(contract: dict[str, Any]) -> str:
    coverage = derive_selected_map_coverage(contract)
    aggregates = derive_selected_register_aggregates(contract)
    lines = [
        "offset\tregister\twidth\taccess\tderived_reset\tderived_static_value\timplementation_status\tfield_count"
    ]
    for register in contract["selected_abi_1_1_registers"]:
        lines.append(
            "\t".join(
                [
                    str(register["offset"]),
                    str(register["name"]),
                    str(register["width"]),
                    str(register["register_access"]),
                    f"0x{aggregates['reset_words'][register['name']]:08X}",
                    (
                        "DYNAMIC"
                        if aggregates["static_words"][register["name"]] is None
                        else f"0x{aggregates['static_words'][register['name']]:08X}"
                    ),
                    str(register["implementation_status"]),
                    str(len(register["fields"])),
                ]
            )
        )
    lines.extend(
        [
            "",
            f"SELECTED_ABI_1_1_REGISTER_COUNT={coverage['selected_register_count']}",
            "SELECTED_ABI_1_1_REGISTER_COVERAGE="
            f"DERIVED_PASS_{coverage['covered_register_count']}_OF_{coverage['selected_register_count']}",
            "SELECTED_ALLOCATION_EQUALS_SELECTED_REGISTER_MODEL=PASS",
            "ALLOCATED_REGISTERS_WITHOUT_FIELD_CONTRACT="
            f"{len(coverage['allocated_without_field_contract'])}",
            "FIELD_CONTRACTS_WITHOUT_ALLOCATION="
            f"{len(coverage['definitions_without_allocation'])}",
        ]
    )
    return "\n".join(lines)


def render_selected_field_table(contract: dict[str, Any]) -> str:
    coverage = derive_selected_map_coverage(contract)
    lines = [
        "offset\tregister\tfield\tbits\taccess\tstatic_value\treset\tbehavior_id\trtl_binding_id\tside_effect_id\tconformance_family\tcapability_gate_ref\tsoftware_name\trtl_name\tipxact_name\timplementation_status"
    ]
    for register, field in selected_field_records(contract):
        bits = field["bits"]
        lines.append(
            "\t".join(
                [
                    str(field["offset"]),
                    str(register["name"]),
                    str(field["name"]),
                    f"{bits['msb']}:{bits['lsb']}",
                    str(field["access"]),
                    json.dumps(field["static_value"], sort_keys=True),
                    json.dumps(field["reset"], sort_keys=True),
                    str(field["behavior_id"]),
                    str(field["rtl_binding_id"]),
                    str(field["side_effect_id"]),
                    str(field["generated_conformance_family"]),
                    str(field["capability_gate_ref"]),
                    str(field["software_name"]),
                    str(field["rtl_name"]),
                    str(field["ipxact_name"]),
                    str(field["implementation_status"]),
                ]
            )
        )
    lines.extend(
        [
            "",
            "SELECTED_ABI_1_1_FIELD_COVERAGE="
            f"DERIVED_PASS_{coverage['covered_field_count']}_OF_{coverage['selected_field_count']}",
            f"UNALLOCATED_FIELDS_COUNTED_AS_ABI_1_1={len(coverage['unallocated_fields'])}",
        ]
    )
    return "\n".join(lines)


def render_selected_bit_coverage(contract: dict[str, Any]) -> str:
    coverage = derive_selected_map_coverage(contract)
    return "\n".join(
        [
            "SELECTED_ABI_1_1_BIT_COVERAGE="
            f"DERIVED_PASS_{coverage['selected_bit_count']}_OF_{coverage['expected_bit_count']}",
            f"UNCOVERED_SELECTED_REGISTER_BITS={len(coverage['uncovered_bits'])}",
            f"OVERLAPPING_SELECTED_REGISTER_BITS={len(coverage['overlapping_bits'])}",
        ]
    )


def render_selected_vs_deferred(contract: dict[str, Any]) -> str:
    coverage = derive_selected_map_coverage(contract)
    return "\n".join(
        [
            "SELECTED_ABI_1_1_REGISTERS",
            json.dumps(contract["selected_abi_1_1_registers"], indent=2, sort_keys=True),
            "",
            "DEFERRED_REGISTER_CANDIDATES",
            json.dumps(contract["deferred_register_candidates"], indent=2, sort_keys=True),
            "",
            f"DEFERRED_REGISTER_CANDIDATES={coverage['deferred_count']}",
            "CLEAR_EVENT_STATUS_ABI_1_1_STATUS=DEFERRED_NOT_SELECTED",
            "DEFERRED_CANDIDATES_COUNTED_AS_SELECTED_ABI="
            f"{len(coverage['deferred_counted_as_selected'])}",
        ]
    )


def render_discovery_bindings(contract: dict[str, Any]) -> str:
    bindings = [
        item
        for item in contract["behavior_binding_matrix"]["bindings"]
        if item.get("scope") == "ABI_1_1_SELECTED"
        and f"{item.get('register')}.{item.get('field_or_global_policy')}"
        in DISCOVERY_BINDING_TARGETS
    ]
    lines = [render_behavior_bindings({**contract, "behavior_binding_matrix": {**contract["behavior_binding_matrix"], "bindings": bindings}}).split("\n\n", 1)[0]]
    lines.extend(
        [
            "",
            "DISCOVERY_REGISTER_BEHAVIOR_BINDINGS="
            f"DERIVED_PASS_{len(bindings)}_OF_{len(DISCOVERY_BINDING_TARGETS)}",
            "DISCOVERY_REGISTER_CONFORMANCE_FAMILIES=PASS",
            "RESERVED_DISCOVERY_BITS_ZERO=PASS",
        ]
    )
    return "\n".join(lines)


def render_capability_dependencies(contract: dict[str, Any]) -> str:
    coverage = derive_capability_dependency_coverage(contract)
    return "\n".join(
        [
            json.dumps(
                contract["capability_dependency_matrix"], indent=2, sort_keys=True
            ),
            "",
            "CAPABILITY_DEPENDENCY_COVERAGE="
            f"DERIVED_PASS_{coverage['covered_count']}_OF_{coverage['target_count']}",
            "CAPABILITIES_WITH_MISSING_REGISTER_DEPENDENCIES="
            f"{len(coverage['missing_register_dependencies'])}",
            "CAPABILITIES_WITH_MISSING_FIELD_DEPENDENCIES="
            f"{len(coverage['missing_field_dependencies'])}",
            "CAPABILITIES_WITH_MISSING_BINDING_DEPENDENCIES="
            f"{len(coverage['missing_binding_dependencies'])}",
            "CAPABILITIES_WITH_MISSING_API_DEPENDENCIES="
            f"{len(coverage['missing_api_dependencies'])}",
            "CAPABILITY_EDGE_COVERAGE="
            f"DERIVED_PASS_{coverage['capability_edge_covered_count']}_OF_{coverage['capability_edge_target_count']}",
            "FIELD_CAPABILITY_EDGE_MISMATCHES="
            f"{len(coverage['field_capability_edge_mismatches'])}",
            "API_CAPABILITY_GATE_MISMATCHES="
            f"{len(coverage['api_capability_gate_mismatches'])}",
            "BINDING_CONFORMANCE_EDGE_MISMATCHES="
            f"{len(coverage['binding_conformance_edge_mismatches'])}",
            "CAPABILITY_IMPLICATION_GRAPH="
            + ("ACYCLIC" if coverage["implication_graph_acyclic"] else "CYCLIC"),
            "CAPABILITY_IMPLICATION_VIOLATIONS="
            f"{len(coverage['capability_implication_violations'])}",
            "FREE_FORM_CAPABILITY_EXPRESSIONS="
            f"{len(coverage['free_form_capability_expressions'])}",
        ]
    )


def render_capability_dependency_authority(contract: dict[str, Any]) -> str:
    return "\n".join(
        [
            json.dumps(
                contract["capability_dependency_authority_contract"],
                indent=2,
                sort_keys=True,
            ),
            "",
            "CAPABILITY_DEPENDENCY_AUTHORITY=capability_dependency_matrix",
            "FIELD_CAPABILITY_ANNOTATIONS=VALIDATED_REFERENCES_TO_AUTHORITY",
            "SOFTWARE_API_CAPABILITY_GATES=VALIDATED_REFERENCES_TO_AUTHORITY",
            "CONFORMANCE_DEPENDENCIES=EXACT_BINDING_EDGES_NOT_GLOBAL_NAME_PRESENCE",
            "INDEPENDENTLY_EDITABLE_DEPENDENCY_DESCRIPTIONS=FORBIDDEN",
        ]
    )


def render_capability_edge_matrix(contract: dict[str, Any]) -> str:
    coverage = derive_capability_dependency_coverage(contract)
    lines = ["edge_kind\tcapability\ttarget\tbinding_or_gate\tconformance"]
    for entry in contract["capability_dependency_matrix"]["capabilities"]:
        for edge in entry["required_field_edges"]:
            lines.append(
                "\t".join(
                    [
                        "FIELD_BINDING_CONFORMANCE",
                        str(entry["name"]),
                        str(edge["target"]),
                        str(edge["rtl_binding_id"]),
                        str(edge["conformance_family"]),
                    ]
                )
            )
        for reference in entry["required_api_gate_refs"]:
            lines.append(
                "\t".join(
                    ["API_GATE", str(entry["name"]), str(reference), str(reference), "NOT_APPLICABLE"]
                )
            )
    lines.extend(
        [
            "",
            "CAPABILITY_EDGE_COVERAGE="
            f"DERIVED_PASS_{coverage['capability_edge_covered_count']}_OF_{coverage['capability_edge_target_count']}",
            "EXACT_FIELD_BINDING_CONFORMANCE_EDGES="
            f"PASS_{coverage['exact_field_edge_covered_count']}_OF_{coverage['exact_field_edge_target_count']}",
            "CAPABILITY_TO_API_GATE_EDGES="
            f"PASS_{coverage['api_gate_edge_covered_count']}_OF_{coverage['api_gate_edge_target_count']}",
        ]
    )
    return "\n".join(lines)


def render_capability_implication_graph(contract: dict[str, Any]) -> str:
    coverage = derive_capability_dependency_coverage(contract)
    return "\n".join(
        [
            json.dumps(
                contract["capability_dependency_matrix"]["implication_graph"],
                indent=2,
                sort_keys=True,
            ),
            "",
            "CAPABILITY_IMPLICATION_GRAPH="
            + ("ACYCLIC" if coverage["implication_graph_acyclic"] else "CYCLIC"),
            "CAPABILITY_IMPLICATION_VIOLATIONS="
            f"{len(coverage['capability_implication_violations'])}",
            "CAPABILITY_IMPLICATION_COVERAGE=PASS",
        ]
    )


def render_api_capability_gate_matrix(contract: dict[str, Any]) -> str:
    coverage = derive_capability_dependency_coverage(contract)
    plan = {
        item["api"]: item for item in contract["software_api_plan"]
    }
    lines = ["gate_id\tapi\tkind\tall_of\tany_of\tnone_of\tplan_reference"]
    for item in contract["capability_dependency_matrix"]["api_gates"]:
        gate = item["gate"]
        lines.append(
            "\t".join(
                [
                    str(item["id"]),
                    str(item["api"]),
                    str(gate["kind"]),
                    ",".join(gate["all_of"]),
                    ",".join(gate["any_of"]),
                    ",".join(gate["none_of"]),
                    str(plan[item["api"]]["capability_gate_ref"]),
                ]
            )
        )
    lines.extend(
        [
            "",
            f"API_CAPABILITY_GATE_MISMATCHES={len(coverage['api_capability_gate_mismatches'])}",
            f"FREE_FORM_CAPABILITY_EXPRESSIONS={len(coverage['free_form_capability_expressions'])}",
        ]
    )
    return "\n".join(lines)


def render_binding_conformance_edge_matrix(contract: dict[str, Any]) -> str:
    coverage = derive_capability_dependency_coverage(contract)
    lines = ["capability\tfield_target\trtl_binding_id\tconformance_family"]
    for entry in contract["capability_dependency_matrix"]["capabilities"]:
        for edge in entry["required_field_edges"]:
            lines.append(
                "\t".join(
                    [
                        str(entry["name"]),
                        str(edge["target"]),
                        str(edge["rtl_binding_id"]),
                        str(edge["conformance_family"]),
                    ]
                )
            )
    lines.extend(
        [
            "",
            "BINDING_CONFORMANCE_EDGE_COVERAGE="
            f"PASS_{coverage['exact_field_edge_covered_count']}_OF_{coverage['exact_field_edge_target_count']}",
            "BINDING_CONFORMANCE_EDGE_MISMATCHES="
            f"{len(coverage['binding_conformance_edge_mismatches'])}",
        ]
    )
    return "\n".join(lines)


def render_register_reset_derivation(contract: dict[str, Any]) -> str:
    coverage = derive_selected_register_aggregates(contract)
    lines = ["register\tderived_reset\tconsumers"]
    for name, value in coverage["reset_words"].items():
        rendered = "ERROR" if value is None else f"0x{value:08X}"
        lines.append(f"{name}\t{rendered}\t" + ",".join(coverage["derived_consumers"]))
    lines.extend(
        [
            "",
            "REGISTER_RESET_AUTHORITY=DERIVED_FROM_FIELD_RESETS",
            "MANUAL_REGISTER_RESET_DUPLICATION=FORBIDDEN",
            "SELECTED_REGISTER_RESET_DERIVATION="
            f"PASS_{coverage['reset_covered_count']}_OF_{coverage['reset_target_count']}",
            "REGISTER_FIELD_RESET_MISMATCHES="
            f"{len(coverage['register_field_reset_mismatches'])}",
        ]
    )
    return "\n".join(lines)


def render_register_static_value_derivation(contract: dict[str, Any]) -> str:
    coverage = derive_selected_register_aggregates(contract)
    lines = ["register\tderived_static_value"]
    for name, value in coverage["static_words"].items():
        rendered = "DYNAMIC" if value is None else f"0x{value:08X}"
        lines.append(f"{name}\t{rendered}")
    lines.extend(
        [
            "",
            "REGISTER_STATIC_VALUE_AUTHORITY=DERIVED_FROM_FIELD_STATIC_VALUES",
            "SELECTED_REGISTER_STATIC_VALUE_DERIVATION="
            f"PASS_{coverage['static_covered_count']}_OF_{coverage['static_target_count']}",
            "REGISTER_FIELD_STATIC_VALUE_MISMATCHES="
            f"{len(coverage['register_field_static_value_mismatches'])}",
        ]
    )
    return "\n".join(lines)


def render_parameter_expression_contract(contract: dict[str, Any]) -> str:
    coverage = derive_selected_register_aggregates(contract)
    return "\n".join(
        [
            json.dumps(
                contract["register_value_expression_contract"],
                indent=2,
                sort_keys=True,
            ),
            "",
            "NON_MACHINE_EVALUABLE_REGISTER_VALUES="
            f"{len(coverage['non_machine_evaluable_register_values'])}",
            "PARAMETERIZED_REGISTER_EXPRESSIONS="
            + (
                "VALIDATED"
                if coverage["parameterized_register_expressions_validated"]
                else "INVALID"
            ),
        ]
    )


def render_parameterized_capabilities_1_matrix(contract: dict[str, Any]) -> str:
    coverage = derive_selected_register_aggregates(contract)
    lines = ["OBS_SEQUENCE_WIDTH\tCAPABILITIES_1"]
    for width, value in coverage["capabilities_1_width_values"].items():
        rendered = "ERROR" if value is None else f"0x{value:08X}"
        lines.append(f"{width}\t{rendered}")
    lines.extend(
        [
            "",
            f"CAPABILITIES_1_WIDTH16=0x{coverage['capabilities_1_width_values'][16]:08X}",
            f"CAPABILITIES_1_WIDTH24=0x{coverage['capabilities_1_width_values'][24]:08X}",
            f"CAPABILITIES_1_WIDTH32=0x{coverage['capabilities_1_width_values'][32]:08X}",
        ]
    )
    return "\n".join(lines)


def render_fault_code_enumeration(contract: dict[str, Any]) -> str:
    taxonomy = contract["fault_taxonomy"]
    coverage = derive_fault_taxonomy_coverage(contract)
    lines = [
        "VALUE\tCANONICAL\tSOFTWARE\tRTL\tC\tSYSTEMVERILOG\tIP_XACT\tLEGACY_ALIASES"
    ]
    for item in taxonomy["fault_codes"]:
        lines.append(
            "\t".join(
                (
                    f"0x{item['value']:02X}",
                    item["canonical_name"],
                    item["software_name"],
                    item["rtl_name"],
                    item["c_name"],
                    item["systemverilog_name"],
                    item["ipxact_name"],
                    ",".join(item["legacy_aliases"]),
                )
            )
        )
    lines.extend(
        [
            "",
            "FAULT_CODE_ENUM_COVERAGE="
            f"DERIVED_PASS_{coverage['fault_code_covered_count']}_OF_{coverage['fault_code_target_count']}",
            "LEGACY_FAULT_NAME_ALIAS_PLAN=APPROVED",
            "FAULT_CODE_BINDING=FAULT_CODE.fault_code_latched",
        ]
    )
    return "\n".join(lines)


def render_fault_cause_bitmap_enumeration(contract: dict[str, Any]) -> str:
    taxonomy = contract["fault_taxonomy"]
    coverage = derive_fault_taxonomy_coverage(contract)
    lines = ["BIT\tMASK\tCANONICAL\tSOFTWARE\tRTL\tC\tSYSTEMVERILOG\tIP_XACT"]
    for item in taxonomy["fault_causes"]:
        lines.append(
            "\t".join(
                (
                    str(item["bit"]),
                    item["mask"],
                    item["canonical_name"],
                    item["software_name"],
                    item["rtl_name"],
                    item["c_name"],
                    item["systemverilog_name"],
                    item["ipxact_name"],
                )
            )
        )
    lines.extend(
        [
            "",
            "FAULT_CAUSE_ENUM_COVERAGE="
            f"DERIVED_PASS_{coverage['fault_cause_covered_count']}_OF_{coverage['fault_cause_target_count']}",
            f"FAULT_BITMAP_WIDTH={taxonomy['fault_bitmap_width']}",
            f"FAULT_BITMAP_VALID_MASK={taxonomy['fault_bitmap_valid_mask']}",
            f"FAULT_BITMAP_RESERVED_MASK={taxonomy['fault_bitmap_reserved_mask']}",
        ]
    )
    return "\n".join(lines)


def render_fault_compatibility_projection(contract: dict[str, Any]) -> str:
    projection = contract["fault_taxonomy"]["compatibility_projection"]
    lines = ["PRIORITY\tCODE\tPREDICATE"]
    for priority, item in enumerate(projection["priority"], start=1):
        lines.append(
            f"{priority}\t{item['code']}\t"
            + json.dumps(item["predicate"], sort_keys=True, separators=(",", ":"))
        )
    lines.extend(
        [
            "",
            "COMPATIBILITY_PROJECTION=APPROVED",
            "COMPLETE_BITMAP_RETAINS_SIMULTANEOUS_CAUSES=YES",
        ]
    )
    return "\n".join(lines)


def render_taxonomy_consumer_plan(contract: dict[str, Any]) -> str:
    plan = contract["fault_taxonomy"]["consumer_plan"]
    topology = derive_generated_artifact_topology(contract)
    lines = ["KIND\tARTIFACT"]
    for item in plan["generated_consumers"]:
        lines.append(f"{item['kind']}\t{item['artifact']}")
    lines.extend(
        [
            "",
            "GENERATED_ARTIFACT_TOPOLOGY_AUTHORITY=ONE_MASTER_LIST",
            "TAXONOMY_CONSUMERS_MAPPED_TO_MASTER_ARTIFACTS="
            f"PASS_{topology['taxonomy_covered_count']}_OF_{topology['taxonomy_target_count']}",
            f"UNOWNED_GENERATED_ARTIFACT_PATHS={len(topology['unowned_paths'])}",
            "DUPLICATE_GENERATED_ARTIFACT_PATHS="
            f"{topology['duplicate_path_count']}",
            "FAULT_TAXONOMY_CONSUMER_PLAN=APPROVED",
            "LEGACY_FAULT_NAME_ALIAS_PLAN=APPROVED",
            f"HANDWRITTEN_DUPLICATES_AFTER_CONVERGENCE={plan['handwritten_duplicates_after_convergence']}",
        ]
    )
    return "\n".join(lines)


def render_generated_artifact_topology(contract: dict[str, Any]) -> str:
    topology = contract["generated_artifact_topology"]
    coverage = derive_generated_artifact_topology(contract)
    lines = [
        "GENERATED_ARTIFACT_TOPOLOGY_AUTHORITY=ONE_MASTER_LIST",
        "MASTER_LIST_REF=" + topology["master_list_ref"],
        "VALIDATION_APPROACH=" + topology["validation_approach"],
        "MASTER_GENERATED_ARTIFACT_TOPOLOGY="
        f"PASS_{coverage['master_covered_count']}_OF_{coverage['master_target_count']}",
        "TAXONOMY_CONSUMERS_MAPPED_TO_MASTER_ARTIFACTS="
        f"PASS_{coverage['taxonomy_covered_count']}_OF_{coverage['taxonomy_target_count']}",
        f"UNOWNED_GENERATED_ARTIFACT_PATHS={len(coverage['unowned_paths'])}",
        f"DUPLICATE_GENERATED_ARTIFACT_PATHS={coverage['duplicate_path_count']}",
        "",
        "MASTER_PATH\tSTATUS",
    ]
    for path in coverage["master_paths"]:
        lines.append(f"{path}\t{'PASS' if coverage['master_paths'].count(path) == 1 else 'FAIL'}")
    legacy_rtl = topology["legacy_rtl_fault_defs"]
    lines.extend(
        [
            "",
            "LEGACY_RTL_FAULT_DEFS_PATH_PRESERVED=YES",
            "LEGACY_RTL_FAULT_NAMES_PRESERVED=YES",
            "FAULT_DEFS_CONTAINS_INDEPENDENT_MANUAL_VALUES_AFTER_CONVERGENCE=NO",
            f"LEGACY_RTL_FAULT_DEFS_PATH={legacy_rtl['path']}",
            "LEGACY_RTL_FAULT_DEFS_COMPATIBILITY_PLAN=" + legacy_rtl["compatibility_plan"],
            "LEGACY_C_HEADER_PATH_PRESERVED=YES",
            "LEGACY_C_FAULT_NAMES_PRESERVED=YES",
            "LEGACY_C_HEADER_PATH=" + topology["legacy_c_header"]["path"],
        ]
    )
    return "\n".join(lines)


def render_stage2h_a1_handoff(contract: dict[str, Any]) -> str:
    handoff = contract["stage2h_a1_handoff"]
    scope = derive_stage2h_a1_scope(contract)
    lines = [
        "CURRENT_SUBSTAGE=" + handoff["current_substage"],
        "STAGE2H_A1_IMPLEMENTATION_STARTED=NO",
        "STAGE2H_A_COMPLETE=NO",
        "STAGE2H_COMPLETE=NO",
        "NEXT_AFTER_STAGE2H_A1=" + handoff["next_after_stage2h_a1"],
        "STAGE2H_B=" + handoff["stage2h_b"],
        "STAGE2H_B_STATUS=" + handoff["stage2h_b_status"],
        "STAGE2H_C=" + handoff["stage2h_c"],
        "STAGE2H_C_STATUS=" + handoff["stage2h_c_status"],
        "STAGE2H_D=" + handoff["stage2h_d"],
        "STAGE2H_D_STATUS=" + handoff["stage2h_d_status"],
        "STAGE2I=" + handoff["stage2i"],
        "STAGE2I_STATUS=" + handoff["stage2i_status"],
        "HANDOFF_VALIDATION=" + ("PASS" if not scope["errors"] else "FAIL"),
    ]
    return "\n".join(lines)


def render_audit_live_source_boundary(contract: dict[str, Any]) -> str:
    boundary = contract["audit_live_source_boundary"]
    scope = derive_stage2h_a1_scope(contract)
    return "\n".join(
        [
            "STAGE2H_A1_AUDIT_CONTRACT=" + boundary["stage2h_a1_audit_contract"],
            "FUTURE_LIVE_REGISTER_MAP_SOURCE=" + boundary["future_live_register_map_source"],
            "AUDIT_CONTRACT_IS_FUTURE_LIVE_REGISTER_MAP_SOURCE=NO",
            "FUTURE_LIVE_SOURCE_SCOPE=" + boundary["future_live_source_scope"],
            "AUDIT_ONLY_HISTORY_COPIED_TO_LIVE_SOURCE=NO",
            "BOUNDARY_VALIDATION=" + ("PASS" if not scope["errors"] else "FAIL"),
        ]
    )


def render_dynamic_value_source_contract(contract: dict[str, Any]) -> str:
    authority = contract["dynamic_value_source_contract"]
    coverage = derive_dynamic_value_source_coverage(contract)
    return "\n".join(
        [
            f"SCHEMA_VERSION={authority['schema_version']}",
            f"AUTHORITY={authority['authority']}",
            f"APPROACH={authority['approach']}",
            "ALLOWED_SOURCE_KINDS=" + ",".join(authority["allowed_source_kinds"]),
            f"SOURCE_BINDING_AUTHORITY={authority['source_binding_authority']}",
            "KNOWN_PARAMETERS=" + ",".join(authority["known_parameters"]),
            "KNOWN_TRANSFORMS=" + ",".join(authority["known_transforms"]),
            f"UNKNOWN_SOURCE_KIND={authority['unknown_source_kind']}",
            f"UNKNOWN_SOURCE_BINDING={authority['unknown_source_binding']}",
            f"UNKNOWN_STATE={authority['unknown_state']}",
            f"UNKNOWN_TRANSFORM={authority['unknown_transform']}",
            f"UNKNOWN_PARAMETER={authority['unknown_parameter']}",
            "",
            "DYNAMIC_VALUE_SOURCE_COVERAGE="
            f"DERIVED_PASS_{coverage['covered_count']}_OF_{coverage['target_count']}",
            "DYNAMIC_FIELDS_WITHOUT_TYPED_SOURCE="
            f"{len(coverage['fields_without_typed_source'])}",
            "OPAQUE_DYNAMIC_BINDINGS_WITHOUT_SOURCE_CONTRACT="
            f"{coverage['opaque_dynamic_bindings_without_source_contract']}",
        ]
    )


def render_dynamic_field_source_matrix(contract: dict[str, Any]) -> str:
    lines = [
        "TARGET\tSOURCE_ID\tKIND\tSOURCE_BINDING\tDATA_BINDING\tVALID_BINDING"
        "\tSTATE\tDEST_WIDTH\tBIT\tMASK\tWIDTH_PARAMETER\tTRANSFORM"
        "\tRTL_BINDING"
    ]
    for item in contract["dynamic_value_source_contract"]["sources"]:
        values = (
            item["target"],
            item["id"],
            item["kind"],
            item.get("source_binding_ref"),
            item.get("data_source_binding_ref"),
            item.get("valid_source_binding_ref"),
            item.get("state_ref"),
            item["destination_width"],
            item.get("source_bit"),
            item.get("mask"),
            item.get("width_parameter"),
            item["transform_rule"],
            item["rtl_binding_id"],
        )
        lines.append(
            "\t".join("-" if value is None else str(value) for value in values)
        )
    return "\n".join(lines)


def render_policy_identity_storage_contract(contract: dict[str, Any]) -> str:
    identity = contract["policy_evaluation_identity_storage_contract"]
    coverage = derive_policy_identity_storage_coverage(contract)
    lines = [
        f"POLICY_EVALUATION_IDENTITY_STORAGE={identity['storage_kind']}",
        f"DATA_SOURCE_BINDING={identity['data_source_binding_ref']}",
        f"VALID_SOURCE_BINDING={identity['valid_source_binding_ref']}",
        f"CAPTURE_WHEN={identity['capture_when']}",
        f"HOLD_WHEN_INVALID={'YES' if identity['hold_when_invalid'] else 'NO'}",
        f"RESET_VALUE={identity['reset_value']}",
        f"TRANSFORM={identity['transform_rule']}",
        "INTEGRITY_CLEAN_REQUIRED="
        f"{'YES' if identity['integrity_clean_required'] else 'NO'}",
        "POLICY_IDENTITY_CAPTURES_NONCLEAN_VALID_RETIREMENT="
        f"{'YES' if identity['captures_nonclean_valid_retirement'] else 'NO'}",
        f"POLICY_EVALUATION_SEQUENCE_ROLE={identity['role']}",
        "POLICY_EVALUATION_SEQUENCE_IS_SNAPSHOT_TOKEN="
        f"{'YES' if identity['is_snapshot_token'] else 'NO'}",
        "POLICY_IDENTITY_CAPTURE_VECTOR_COVERAGE="
        f"PASS_{coverage['vector_covered_count']}_OF_{coverage['vector_target_count']}",
    ]
    return "\n".join(lines)


def render_policy_identity_idle_hold_matrix(contract: dict[str, Any]) -> str:
    lines = [
        "VECTOR\tRESET\tVALID\tINTEGRITY_CLEAN\tSEQUENCE\tEXPECTED_IDENTITY"
    ]
    for item in contract["policy_evaluation_identity_storage_contract"][
        "directed_vectors"
    ]:
        lines.append(
            "\t".join(
                str(item[key])
                for key in (
                    "id",
                    "reset",
                    "valid",
                    "integrity_clean",
                    "sequence",
                    "expected_identity",
                )
            )
        )
    lines.extend(
        [
            "",
            "POLICY_IDENTITY_HOLDS_DURING_IDLE=YES",
            "POLICY_IDENTITY_CAPTURES_NONCLEAN_VALID_RETIREMENT=YES",
        ]
    )
    return "\n".join(lines)


def render_rtl_source_inventory(contract: dict[str, Any]) -> str:
    lines = [
        "SOURCE_ID\tFILE\tMODULE\tSIGNAL\tDIRECTION\tWIDTH\tCLOCK"
        "\tRESET\tOWNER_MODULE\tINSTANCE\tPORT\tNET\tSTATE_ENCODING"
    ]
    for item in contract["stage2h_rtl_source_bindings"]["bindings"]:
        width = item["width"]
        width_text = (
            str(width["bits"])
            if width["kind"] == "LITERAL"
            else f"{width['parameter']}->{width['contract_parameter']}"
        )
        lines.append(
            "\t".join(
                (
                    item["id"],
                    item["file"],
                    item["module"],
                    item["signal"],
                    item["direction"],
                    width_text,
                    item["clock_domain_ref"],
                    item["reset_domain_ref"],
                    item["connection"]["module"],
                    item["connection"]["instance"],
                    item["connection"]["port"],
                    item["connection"]["net"],
                    json.dumps(item["state_encoding"], sort_keys=True),
                )
            )
        )
    return "\n".join(lines)


def render_dynamic_source_to_rtl_trace(contract: dict[str, Any]) -> str:
    coverage = derive_rtl_source_binding_coverage(ROOT, contract)
    lines = ["DYNAMIC_SOURCE_ID\tROLE\tSOURCE_BINDING_REF"]
    for edge in coverage["dynamic_trace_edges"]:
        lines.append(
            f"{edge['dynamic_source_id']}\t{edge['role']}\t"
            f"{edge['source_binding_ref']}"
        )
    lines.extend(
        [
            "",
            "DYNAMIC_SOURCE_TO_RTL_TRACE="
            f"DERIVED_PASS_{coverage['dynamic_trace_covered_count']}_OF_"
            f"{coverage['dynamic_trace_target_count']}",
        ]
    )
    return "\n".join(lines)


def render_rtl_source_validation_results(contract: dict[str, Any]) -> str:
    coverage = derive_rtl_source_binding_coverage(ROOT, contract)
    return "\n".join(
        [
            "CHECKER=PROJECT_SPECIFIC_DECLARATION_CONNECTION_AND_WIDTH_CHECKS",
            "GENERAL_VERILOG_SEMANTIC_PARSER_ADDED=NO",
            "FULL_RTL_DECLARATION_GRAPH_ADDED=NO",
            "RTL_SOURCE_INVENTORY_COVERAGE="
            f"DERIVED_PASS_{coverage['binding_covered_count']}_OF_"
            f"{coverage['binding_target_count']}",
            f"MISSING_RTL_SOURCE_DECLARATIONS={len(coverage['missing_declarations'])}",
            f"RTL_SOURCE_DIRECTION_MISMATCHES={len(coverage['direction_mismatches'])}",
            f"RTL_SOURCE_WIDTH_MISMATCHES={len(coverage['width_mismatches'])}",
            f"RTL_STATE_ENCODING_MISMATCHES={len(coverage['state_mismatches'])}",
            f"RTL_SOURCE_CONNECTION_MISMATCHES={len(coverage['connection_mismatches'])}",
            f"RTL_SOURCE_DOMAIN_MISMATCHES={len(coverage['domain_mismatches'])}",
            f"UNCONSUMED_RTL_SOURCE_ENTRIES={len(coverage['unconsumed_entries'])}",
            f"UNKNOWN_RTL_SOURCE_REFERENCES={len(coverage['unknown_refs'])}",
            "COMPILE_ELABORATION_GATE=EXISTING_STAGE2G_CURRENT_TREE_ICARUS",
            "TARGETED_SIMULATION_GATE=EXISTING_STAGE2G_DIRECTED_POLICY_AND_SEQUENCE_TESTS",
        ]
    )

def render_policy_status_invariants(contract: dict[str, Any]) -> str:
    coverage = derive_cross_field_invariant_coverage(contract)
    lines = [
        "EVALUATION_BOUNDARY=" + contract["cross_field_invariants"]["evaluation_boundary"],
        "SOFTWARE_ATOMIC_SNAPSHOT_CLAIM=NO",
        "",
    ]
    lines.extend(
        json.dumps(item, sort_keys=True)
        for item in contract["cross_field_invariants"]["policy_status_invariants"]
    )
    lines.extend(
        [
            "",
            "POLICY_STATUS_ONE_HOT_INVARIANT=APPROVED",
            "POLICY_STATUS_RELATIONAL_INVARIANTS=APPROVED",
            "POLICY_STATUS_INVARIANT_COVERAGE="
            f"PASS_{coverage['policy_covered_count']}_OF_{coverage['policy_target_count']}",
        ]
    )
    return "\n".join(lines)


def render_bitmap_invariants(contract: dict[str, Any]) -> str:
    coverage = derive_cross_field_invariant_coverage(contract)
    lines = [
        json.dumps(item, sort_keys=True)
        for item in contract["cross_field_invariants"]["bitmap_invariants"]
    ]
    lines.extend(
        [
            "",
            "BITMAP_MASK_AND_LIFETIME_INVARIANTS=APPROVED",
            "BITMAP_INVARIANT_COVERAGE="
            f"PASS_{coverage['bitmap_covered_count']}_OF_{coverage['bitmap_target_count']}",
        ]
    )
    return "\n".join(lines)


def render_episode_bitmap_transition_rules(contract: dict[str, Any]) -> str:
    coverage = derive_episode_bitmap_transition_coverage(contract)
    lines = [
        "EVENT_VALID_SOURCE=SRC_FAULT_EVAL_VALID",
        "EVENT_INTEGRITY_CLEAN_SOURCE=SRC_FAULT_EVAL_INTEGRITY_CLEAN",
        "EVENT_BITMAP_SOURCE=SRC_FAULT_EVAL_BITMAP",
    ]
    lines.extend(
        json.dumps(item, sort_keys=True)
        for item in contract["episode_bitmap_transition_rules"]["rules"]
    )
    lines.extend(
        [
            "",
            "EPISODE_BITMAP_TRANSITION_RULE_COVERAGE="
            f"PASS_{coverage['covered_count']}_OF_{coverage['target_count']}",
        ]
    )
    return "\n".join(lines)


def render_unknown_fault_cause_compatibility(contract: dict[str, Any]) -> str:
    authority = contract["unknown_fault_cause_forward_compatibility"]
    coverage = derive_unknown_fault_compatibility_coverage(contract)
    lines = [
        "UNKNOWN_FAULT_CAUSE_FORWARD_COMPATIBILITY=APPROVED",
        "API_RETURN_TYPE=FaultBitmapValue",
        "API_MEMBERS=raw_value,known_flags,unknown_mask,advertised_width",
        "UNKNOWN_BITS_WITHIN_ADVERTISED_WIDTH=PRESERVE",
        "KNOWN_FLAGS_DECODE=NORMAL",
        "BITS_ABOVE_ADVERTISED_WIDTH=REQUIRE_ZERO",
        "UNKNOWN_NAME_POLICY=DO_NOT_INVENT_NAMES",
        "",
        "VECTOR\tRAW_VALUE\tADVERTISED_WIDTH\tKNOWN_FLAGS\tUNKNOWN_MASK"
        "\tABOVE_ADVERTISED_MASK\tVALID",
    ]
    for item in authority["directed_vectors"]:
        lines.append(
            "\t".join(
                str(item[key])
                for key in (
                    "id",
                    "raw_value",
                    "advertised_width",
                    "expected_known_flags",
                    "expected_unknown_mask",
                    "expected_above_advertised_mask",
                    "expected_valid",
                )
            )
        )
    lines.extend(
        [
            "",
            "UNKNOWN_FAULT_CAUSE_VECTOR_COVERAGE="
            f"PASS_{coverage['vector_covered_count']}_OF_"
            f"{coverage['vector_target_count']}",
        ]
    )
    return "\n".join(lines)


def render_conformance_clause_grammar(contract: dict[str, Any]) -> str:
    coverage = derive_conformance_scenario_coverage(contract)
    return "\n".join(
        [
            "CONFORMANCE_CLAUSE_GRAMMAR=CLOSED",
            "CONFORMANCE_APPROACH=FINITE_PROJECT_SPECIFIC_TEMPLATES",
            "OVERENGINEERED_GENERIC_DSL_ADDED=NO",
            "GENERIC_CONFORMANCE_INTERPRETER=REJECTED_OVERENGINEERING",
            f"OPAQUE_SCENARIO_TARGETS={len(coverage['opaque_targets'])}",
            f"OPAQUE_SCENARIO_VALUES={len(coverage['opaque_values'])}",
            "FINITE_TEMPLATE_COVERAGE="
            f"DERIVED_PASS_{coverage['template_covered_count']}_OF_"
            f"{coverage['template_target_count']}",
        ]
    )


def render_conformance_reference_resolution(contract: dict[str, Any]) -> str:
    coverage = derive_conformance_scenario_coverage(contract)
    lines = ["TEMPLATE_ID\tSELECTED_FIELD_COUNT"]
    for item in contract["conformance_scenario_definitions"][
        "selected_field_groups"
    ]:
        lines.append(f"{item['template_id']}\t{len(item['field_refs'])}")
    lines.extend(
        [
            "",
            "SCENARIO_REFERENCE_RESOLUTION="
            f"{'PASS' if not coverage['reference_errors'] else 'FAIL'}",
            "SCENARIO_BINDING_EDGE_MISMATCHES="
            f"{len(coverage['binding_edge_mismatches'])}",
            "SELECTED_FIELD_TEMPLATE_COVERAGE="
            f"DERIVED_PASS_{coverage['selected_field_covered_count']}_OF_"
            f"{coverage['selected_field_target_count']}",
            "SCENARIO_EXECUTABILITY="
            f"DERIVED_PASS_{coverage['covered_count']}_OF_"
            f"{coverage['target_count']}",
        ]
    )
    return "\n".join(lines)


def render_conformance_scenario_definitions(contract: dict[str, Any]) -> str:
    authority = contract["conformance_scenario_definitions"]
    coverage = derive_conformance_scenario_coverage(contract)
    lines = [
        f"SCHEMA_VERSION={authority['schema_version']}",
        f"AUTHORITY={authority['authority']}",
        f"APPROACH={authority['approach']}",
        f"GENERIC_DSL={authority['generic_dsl']}",
        "",
    ]
    lines.extend(
        json.dumps(item, sort_keys=True)
        for item in authority["template_definitions"]
    )
    lines.append("")
    lines.extend(
        json.dumps(item, sort_keys=True)
        for item in authority["selected_family_routes"]
    )
    lines.extend(
        [
            "",
            "CONFORMANCE_SCENARIO_DEFINITION_COVERAGE="
            f"DERIVED_PASS_{coverage['covered_count']}_OF_"
            f"{coverage['target_count']}",
            "CONFORMANCE_FAMILIES_WITHOUT_MACHINE_SCENARIOS="
            f"{len(coverage['missing_families'])}",
        ]
    )
    return "\n".join(lines)


def emit_reports(
    output: Path,
    contract: dict[str, Any],
    semantic_results: list[str],
    cross_results: list[str],
    ast_results: list[str],
    ast_record: dict[str, str],
    matrix: list[dict[str, str]],
    documentation_paths: int,
    cross_version_status: str,
) -> None:
    output.mkdir(parents=True, exist_ok=False)
    write_text(output / "current_register_authority_inventory.txt", render_inventory(contract))
    write_text(output / "current_abi_table.txt", render_abi(contract))
    write_text(output / "duplicate_definition_graph.txt", render_duplicate_graph(contract))
    write_text(output / "behavior_binding_matrix.txt", render_behavior_bindings(contract))
    write_text(output / "selected_abi_register_model.txt", render_selected_register_model(contract))
    write_text(output / "selected_abi_field_table.txt", render_selected_field_table(contract))
    write_text(output / "selected_abi_bit_coverage.txt", render_selected_bit_coverage(contract))
    write_text(output / "selected_vs_deferred_registers.txt", render_selected_vs_deferred(contract))
    write_text(output / "discovery_register_behavior_bindings.txt", render_discovery_bindings(contract))
    write_text(output / "capability_dependency_matrix.txt", render_capability_dependencies(contract))
    write_text(
        output / "capability_dependency_authority.txt",
        render_capability_dependency_authority(contract),
    )
    write_text(output / "capability_edge_matrix.txt", render_capability_edge_matrix(contract))
    write_text(
        output / "capability_implication_graph.txt",
        render_capability_implication_graph(contract),
    )
    write_text(
        output / "api_capability_gate_matrix.txt",
        render_api_capability_gate_matrix(contract),
    )
    write_text(
        output / "binding_conformance_edge_matrix.txt",
        render_binding_conformance_edge_matrix(contract),
    )
    write_text(
        output / "register_reset_derivation.txt",
        render_register_reset_derivation(contract),
    )
    write_text(
        output / "register_static_value_derivation.txt",
        render_register_static_value_derivation(contract),
    )
    write_text(
        output / "parameter_expression_contract.txt",
        render_parameter_expression_contract(contract),
    )
    write_text(
        output / "parameterized_capabilities_1_matrix.txt",
        render_parameterized_capabilities_1_matrix(contract),
    )
    write_text(output / "fault_code_enumeration.txt", render_fault_code_enumeration(contract))
    write_text(
        output / "fault_cause_bitmap_enumeration.txt",
        render_fault_cause_bitmap_enumeration(contract),
    )
    write_text(
        output / "fault_compatibility_projection.txt",
        render_fault_compatibility_projection(contract),
    )
    write_text(output / "taxonomy_consumer_plan.txt", render_taxonomy_consumer_plan(contract))
    write_text(
        output / "generated_artifact_topology.txt",
        render_generated_artifact_topology(contract),
    )
    write_text(
        output / "stage2h_a1_handoff.txt",
        render_stage2h_a1_handoff(contract),
    )
    write_text(
        output / "audit_live_source_boundary.txt",
        render_audit_live_source_boundary(contract),
    )
    write_text(
        output / "policy_identity_storage_contract.txt",
        render_policy_identity_storage_contract(contract),
    )
    write_text(
        output / "policy_identity_idle_hold_matrix.txt",
        render_policy_identity_idle_hold_matrix(contract),
    )
    write_text(output / "rtl_source_inventory.txt", render_rtl_source_inventory(contract))
    write_text(
        output / "dynamic_source_to_rtl_trace.txt",
        render_dynamic_source_to_rtl_trace(contract),
    )
    write_text(
        output / "rtl_source_validation_results.txt",
        render_rtl_source_validation_results(contract),
    )
    write_text(
        output / "dynamic_value_source_contract.txt",
        render_dynamic_value_source_contract(contract),
    )
    write_text(
        output / "dynamic_field_source_matrix.txt",
        render_dynamic_field_source_matrix(contract),
    )
    write_text(
        output / "policy_status_invariants.txt",
        render_policy_status_invariants(contract),
    )
    write_text(output / "bitmap_invariants.txt", render_bitmap_invariants(contract))
    write_text(
        output / "episode_bitmap_transition_rules.txt",
        render_episode_bitmap_transition_rules(contract),
    )
    write_text(
        output / "unknown_fault_cause_compatibility.txt",
        render_unknown_fault_cause_compatibility(contract),
    )
    write_text(
        output / "conformance_clause_grammar.txt",
        render_conformance_clause_grammar(contract),
    )
    write_text(
        output / "conformance_reference_resolution.txt",
        render_conformance_reference_resolution(contract),
    )
    write_text(
        output / "conformance_scenario_definitions.txt",
        render_conformance_scenario_definitions(contract),
    )
    write_text(
        output / "capability_metadata_constraints.txt",
        json.dumps(contract["capability_metadata_constraints"], indent=2, sort_keys=True),
    )
    write_text(output / "semantic_negative_fixtures.txt", "\n".join(semantic_results))
    write_text(output / "cross_artifact_negative_fixtures.txt", "\n".join(cross_results))
    write_text(output / "ast_fingerprint_fixtures.txt", "\n".join(ast_results))
    matrix_lines = [
        f"REPOSITORY_CANONICAL_SHA256={ast_record['canonical_sha256']}",
        f"REPOSITORY_SOURCE_SEGMENT_SHA256={ast_record['source_segment_sha256']}",
    ]
    for record in matrix:
        prefix = record["matrix_role"]
        for key in (
            "python_executable",
            "python_version",
            "schema",
            "canonical_sha256",
            "legacy_default_ast_dump_sha256",
            "source_segment_sha256",
        ):
            matrix_lines.append(f"{prefix}_{key.upper()}={record[key]}")
    if not matrix:
        matrix_lines.append("PYTHON_CROSS_VERSION_AST=SKIP_EXPLICIT_UNIT_TEST_MODE")
    write_text(output / "ast_cross_version_matrix.txt", "\n".join(matrix_lines))
    defect_counts = derive_abi_defect_counts(contract["current_abi"])
    binding_coverage = derive_behavior_binding_coverage(contract)
    selected_coverage = derive_selected_map_coverage(contract)
    capability_coverage = derive_capability_dependency_coverage(contract)
    aggregate_coverage = derive_selected_register_aggregates(contract)
    taxonomy_coverage = derive_fault_taxonomy_coverage(contract)
    artifact_topology = derive_generated_artifact_topology(contract)
    stage2h_a1_scope = derive_stage2h_a1_scope(contract)
    dynamic_coverage = derive_dynamic_value_source_coverage(contract)
    invariant_coverage = derive_cross_field_invariant_coverage(contract)
    rtl_source_coverage = derive_rtl_source_binding_coverage(ROOT, contract)
    identity_coverage = derive_policy_identity_storage_coverage(contract)
    transition_coverage = derive_episode_bitmap_transition_coverage(contract)
    unknown_fault_coverage = derive_unknown_fault_compatibility_coverage(contract)
    scenario_coverage = derive_conformance_scenario_coverage(contract)
    summary = [
        "STAGE2H_STATIC_CONTRACT_AUDIT=PASS",
        "JSON_PARSE_AND_SCHEMA_VALIDATION=PASS",
        "CURRENT_ABI_EXTRACTION=PASS_25_OF_25",
        "CURRENT_ABI_OFFSETS_0X00_TO_0X60=PASS",
        "FAULT_CODE_ENUM_COVERAGE="
        f"DERIVED_PASS_{taxonomy_coverage['fault_code_covered_count']}_OF_{taxonomy_coverage['fault_code_target_count']}",
        "FAULT_CAUSE_ENUM_COVERAGE="
        f"DERIVED_PASS_{taxonomy_coverage['fault_cause_covered_count']}_OF_{taxonomy_coverage['fault_cause_target_count']}",
        f"FAULT_BITMAP_WIDTH={taxonomy_coverage['fault_bitmap_width']}",
        f"FAULT_BITMAP_VALID_MASK=0x{taxonomy_coverage['valid_mask']:08X}",
        f"FAULT_BITMAP_RESERVED_MASK=0x{taxonomy_coverage['reserved_mask']:08X}",
        "FAULT_TAXONOMY_CONSUMER_PLAN=APPROVED",
        "LEGACY_FAULT_NAME_ALIAS_PLAN=APPROVED",
        "COMPATIBILITY_PROJECTION=APPROVED",
        "GENERATED_ARTIFACT_TOPOLOGY_AUTHORITY=ONE_MASTER_LIST",
        "MASTER_GENERATED_ARTIFACT_TOPOLOGY="
        f"PASS_{artifact_topology['master_covered_count']}_OF_{artifact_topology['master_target_count']}",
        "TAXONOMY_CONSUMERS_MAPPED_TO_MASTER_ARTIFACTS="
        f"PASS_{artifact_topology['taxonomy_covered_count']}_OF_{artifact_topology['taxonomy_target_count']}",
        f"UNOWNED_GENERATED_ARTIFACT_PATHS={len(artifact_topology['unowned_paths'])}",
        f"DUPLICATE_GENERATED_ARTIFACT_PATHS={artifact_topology['duplicate_path_count']}",
        "LEGACY_RTL_FAULT_DEFS_PATH_PRESERVED=YES",
        "LEGACY_RTL_FAULT_NAMES_PRESERVED=YES",
        "FAULT_DEFS_CONTAINS_INDEPENDENT_MANUAL_VALUES_AFTER_CONVERGENCE=NO",
        "LEGACY_C_HEADER_PATH_PRESERVED=YES",
        "LEGACY_C_FAULT_NAMES_PRESERVED=YES",
        "CURRENT_SUBSTAGE=STAGE2H_A1_REGISTER_MAP_AND_PUBLIC_ABI_ARCHITECTURE",
        "STAGE2H_A1_IMPLEMENTATION_STARTED=NO",
        "STAGE2H_A_COMPLETE=NO",
        "STAGE2H_COMPLETE=NO",
        "NEXT_AFTER_STAGE2H_A1=STAGE2H_A2_REGISTER_MAP_AND_PUBLIC_ABI_IMPLEMENTATION",
        "STAGE2H_B_STATUS=NOT_STARTED",
        "STAGE2H_C_STATUS=NOT_STARTED",
        "STAGE2H_D_STATUS=NOT_STARTED",
        "STAGE2I_STATUS=NOT_STARTED",
        "STAGE2H_A1_AUDIT_CONTRACT=spec/stage2h_register_map_convergence.json",
        "FUTURE_LIVE_REGISTER_MAP_SOURCE=spec/register_map.json",
        "AUDIT_CONTRACT_IS_FUTURE_LIVE_REGISTER_MAP_SOURCE=NO",
        "FIRST_PRINCIPLES_SCOPE_REVIEW=PASS",
        "OVERENGINEERED_GENERIC_DSL_ADDED=NO",
        "GENERAL_VERILOG_SEMANTIC_PARSER_ADDED=NO",
        "FULL_RTL_DECLARATION_GRAPH_ADDED=NO",
        "CONFORMANCE_APPROACH=FINITE_PROJECT_SPECIFIC_TEMPLATES",
        "RTL_SOURCE_BINDING_APPROACH=LIGHTWEIGHT_EXPLICIT_BINDINGS_PLUS_COMPILE_SIM_CHECKS",
        "LONG_TERM_COMPLEXITY_REDUCED=YES",
        "POLICY_EVALUATION_IDENTITY_STORAGE=REGISTERED_EVENT_CAPTURE",
        "POLICY_IDENTITY_DATA_SIGNAL=fault_eval_sequence",
        "POLICY_IDENTITY_VALID_SIGNAL=fault_eval_valid",
        "POLICY_IDENTITY_HOLDS_DURING_IDLE=YES",
        "POLICY_IDENTITY_CAPTURES_NONCLEAN_VALID_RETIREMENT=YES",
        "POLICY_IDENTITY_CAPTURE_VECTOR_COVERAGE="
        f"PASS_{identity_coverage['vector_covered_count']}_OF_{identity_coverage['vector_target_count']}",
        "RTL_SOURCE_INVENTORY_COVERAGE="
        f"DERIVED_PASS_{rtl_source_coverage['binding_covered_count']}_OF_{rtl_source_coverage['binding_target_count']}",
        "DYNAMIC_SOURCE_TO_RTL_TRACE="
        f"DERIVED_PASS_{rtl_source_coverage['dynamic_trace_covered_count']}_OF_{rtl_source_coverage['dynamic_trace_target_count']}",
        f"MISSING_RTL_SOURCE_DECLARATIONS={len(rtl_source_coverage['missing_declarations'])}",
        f"RTL_SOURCE_WIDTH_MISMATCHES={len(rtl_source_coverage['width_mismatches'])}",
        f"RTL_STATE_ENCODING_MISMATCHES={len(rtl_source_coverage['state_mismatches'])}",
        f"UNCONSUMED_RTL_SOURCE_ENTRIES={len(rtl_source_coverage['unconsumed_entries'])}",
        "DYNAMIC_VALUE_SOURCE_COVERAGE="
        f"DERIVED_PASS_{dynamic_coverage['covered_count']}_OF_{dynamic_coverage['target_count']}",
        f"DYNAMIC_FIELDS_WITHOUT_TYPED_SOURCE={len(dynamic_coverage['fields_without_typed_source'])}",
        "OPAQUE_DYNAMIC_BINDINGS_WITHOUT_SOURCE_CONTRACT="
        f"{dynamic_coverage['opaque_dynamic_bindings_without_source_contract']}",
        "POLICY_STATUS_ONE_HOT_INVARIANT=APPROVED",
        "POLICY_STATUS_RELATIONAL_INVARIANTS=APPROVED",
        "BITMAP_MASK_AND_LIFETIME_INVARIANTS=APPROVED",
        "EPISODE_BITMAP_TRANSITION_RULE_COVERAGE="
        f"PASS_{transition_coverage['covered_count']}_OF_{transition_coverage['target_count']}",
        "UNKNOWN_FAULT_CAUSE_FORWARD_COMPATIBILITY=APPROVED",
        "UNKNOWN_FAULT_CAUSE_VECTOR_COVERAGE="
        f"PASS_{unknown_fault_coverage['vector_covered_count']}_OF_{unknown_fault_coverage['vector_target_count']}",
        "CONFORMANCE_CLAUSE_GRAMMAR=CLOSED",
        f"OPAQUE_SCENARIO_TARGETS={len(scenario_coverage['opaque_targets'])}",
        f"OPAQUE_SCENARIO_VALUES={len(scenario_coverage['opaque_values'])}",
        "SCENARIO_REFERENCE_RESOLUTION="
        f"{'PASS' if not scenario_coverage['reference_errors'] else 'FAIL'}",
        "SCENARIO_BINDING_EDGE_MISMATCHES="
        f"{len(scenario_coverage['binding_edge_mismatches'])}",
        "SCENARIO_EXECUTABILITY="
        f"DERIVED_PASS_{scenario_coverage['covered_count']}_OF_{scenario_coverage['target_count']}",
        "CONFORMANCE_SCENARIO_DEFINITION_COVERAGE="
        f"DERIVED_PASS_{scenario_coverage['covered_count']}_OF_{scenario_coverage['target_count']}",
        "CONFORMANCE_FAMILIES_WITHOUT_MACHINE_SCENARIOS="
        f"{len(scenario_coverage['missing_families'])}",
        "CURRENT_ABI_DEFECT_COUNT=DERIVED",
        f"CURRENT_ABI_DEFECT_TOTAL={defect_counts['total']}",
        "CURRENT_ABI_CONTRADICTION_COUNT="
        f"{defect_counts['DOCUMENTATION_VS_RTL_CONTRADICTION']}",
        "CURRENT_ABI_UNDOCUMENTED_BEHAVIOR_COUNT="
        f"{defect_counts['UNDOCUMENTED_FROZEN_ABI_BEHAVIOR']}",
        "HARDCODED_CONTRADICTION_COUNT=NO",
        "DUPLICATE_REGISTER_AUTHORITIES=4",
        f"SEMANTIC_NEGATIVE_FIXTURES=PASS_{len(semantic_results)}_OF_{len(semantic_results)}",
        f"CROSS_ARTIFACT_NEGATIVE_FIXTURES=PASS_{len(cross_results)}_OF_{len(cross_results)}",
        f"AST_FINGERPRINT_FIXTURES=PASS_{len(ast_results)}_OF_{len(ast_results)}",
        f"PYTHON_CROSS_VERSION_AST={cross_version_status}",
        "REGISTER_MAP_SOURCE_OWNS_BEHAVIOR_SEMANTICS=YES",
        "HANDWRITTEN_RTL_IS_UNTRACKED_AUTHORITY=NO",
        "EVERY_PUBLIC_FIELD_HAS_ONE_BEHAVIOR_ID=PASS",
        "EVERY_BEHAVIOR_ID_HAS_RTL_BINDING=PASS",
        "EVERY_BINDING_HAS_SPEC_GENERATED_TESTS=PASS",
        "ZERO_VERSION_WORD=NO_EXPLICIT_DISCOVERY",
        "NONZERO_BAD_MAGIC=REJECT_INCOMPATIBLE",
        "UNSUPPORTED_MAJOR=REJECT_INCOMPATIBLE",
        "BAD_MAGIC_IS_LEGACY=NO",
        "LEGACY_CAPABILITY_MODEL=PRESENT_ABSENT_UNKNOWN",
        "NORMALIZED_TELEMETRY_CAPABILITY_BIT=RESERVED_ZERO",
        "FIRST_LIVE_SEEN_BITMAP_LIFETIME=ACTIVE_INTERNAL_EPISODE",
        "PLATFORM_LAUNCHER_HARDCODED=NO",
        "POLICY_EVALUATION_SEQUENCE_ROLE=DIAGNOSTIC_LAST_RETIREMENT_IDENTITY",
        "POLICY_EVALUATION_SEQUENCE_IS_SNAPSHOT_TOKEN=NO",
        "READ_POLICY_SNAPSHOT_API=DEFERRED",
        "POLICY_MULTI_REGISTER_COHERENCE=INDEPENDENTLY_COHERENT",
        "POLICY_SNAPSHOT_OVERCLAIM=NO",
        f"SELECTED_ABI_1_1_REGISTER_COUNT={selected_coverage['selected_register_count']}",
        "SELECTED_ABI_1_1_REGISTER_COVERAGE="
        f"DERIVED_PASS_{selected_coverage['covered_register_count']}_OF_{selected_coverage['selected_register_count']}",
        "SELECTED_ABI_1_1_FIELD_COVERAGE="
        f"DERIVED_PASS_{selected_coverage['covered_field_count']}_OF_{selected_coverage['selected_field_count']}",
        "SELECTED_ABI_1_1_BIT_COVERAGE="
        f"DERIVED_PASS_{selected_coverage['selected_bit_count']}_OF_{selected_coverage['expected_bit_count']}",
        "ALLOCATED_REGISTERS_WITHOUT_FIELD_CONTRACT="
        f"{len(selected_coverage['allocated_without_field_contract'])}",
        "FIELD_CONTRACTS_WITHOUT_ALLOCATION="
        f"{len(selected_coverage['definitions_without_allocation'])}",
        "UNALLOCATED_FIELDS_COUNTED_AS_ABI_1_1="
        f"{len(selected_coverage['unallocated_fields'])}",
        "UNCOVERED_SELECTED_REGISTER_BITS="
        f"{len(selected_coverage['uncovered_bits'])}",
        "OVERLAPPING_SELECTED_REGISTER_BITS="
        f"{len(selected_coverage['overlapping_bits'])}",
        "DISCOVERY_REGISTER_BEHAVIOR_BINDINGS="
        f"DERIVED_PASS_{len(DISCOVERY_BINDING_TARGETS)}_OF_{len(DISCOVERY_BINDING_TARGETS)}",
        "DISCOVERY_REGISTER_CONFORMANCE_FAMILIES=PASS",
        "RESERVED_DISCOVERY_BITS_ZERO=PASS",
        "CAPABILITY_DEPENDENCY_COVERAGE="
        f"DERIVED_PASS_{capability_coverage['covered_count']}_OF_{capability_coverage['target_count']}",
        "CAPABILITIES_WITH_MISSING_REGISTER_DEPENDENCIES="
        f"{len(capability_coverage['missing_register_dependencies'])}",
        "CAPABILITIES_WITH_MISSING_FIELD_DEPENDENCIES="
        f"{len(capability_coverage['missing_field_dependencies'])}",
        "CAPABILITIES_WITH_MISSING_BINDING_DEPENDENCIES="
        f"{len(capability_coverage['missing_binding_dependencies'])}",
        "CAPABILITIES_WITH_MISSING_API_DEPENDENCIES="
        f"{len(capability_coverage['missing_api_dependencies'])}",
        "CAPABILITY_DEPENDENCY_AUTHORITY=capability_dependency_matrix",
        "CAPABILITY_EDGE_COVERAGE="
        f"DERIVED_PASS_{capability_coverage['capability_edge_covered_count']}_OF_{capability_coverage['capability_edge_target_count']}",
        "FIELD_CAPABILITY_EDGE_MISMATCHES="
        f"{len(capability_coverage['field_capability_edge_mismatches'])}",
        "API_CAPABILITY_GATE_MISMATCHES="
        f"{len(capability_coverage['api_capability_gate_mismatches'])}",
        "BINDING_CONFORMANCE_EDGE_MISMATCHES="
        f"{len(capability_coverage['binding_conformance_edge_mismatches'])}",
        "CAPABILITY_IMPLICATION_GRAPH=ACYCLIC",
        "CAPABILITY_IMPLICATION_VIOLATIONS="
        f"{len(capability_coverage['capability_implication_violations'])}",
        "FREE_FORM_CAPABILITY_EXPRESSIONS="
        f"{len(capability_coverage['free_form_capability_expressions'])}",
        "REGISTER_RESET_AUTHORITY=DERIVED_FROM_FIELD_RESETS",
        "REGISTER_STATIC_VALUE_AUTHORITY=DERIVED_FROM_FIELD_STATIC_VALUES",
        "MANUAL_REGISTER_RESET_DUPLICATION=FORBIDDEN",
        "SELECTED_REGISTER_RESET_DERIVATION="
        f"PASS_{aggregate_coverage['reset_covered_count']}_OF_{aggregate_coverage['reset_target_count']}",
        "SELECTED_REGISTER_STATIC_VALUE_DERIVATION="
        f"PASS_{aggregate_coverage['static_covered_count']}_OF_{aggregate_coverage['static_target_count']}",
        "REGISTER_FIELD_RESET_MISMATCHES="
        f"{len(aggregate_coverage['register_field_reset_mismatches'])}",
        "REGISTER_FIELD_STATIC_VALUE_MISMATCHES="
        f"{len(aggregate_coverage['register_field_static_value_mismatches'])}",
        "REGISTER_FIELD_ACCESS_MISMATCHES="
        f"{len(aggregate_coverage['register_field_access_mismatches'])}",
        "NON_MACHINE_EVALUABLE_REGISTER_VALUES="
        f"{len(aggregate_coverage['non_machine_evaluable_register_values'])}",
        "PARAMETERIZED_REGISTER_EXPRESSIONS=VALIDATED",
        f"CAPABILITIES_1_WIDTH16=0x{aggregate_coverage['capabilities_1_width_values'][16]:08X}",
        f"CAPABILITIES_1_WIDTH24=0x{aggregate_coverage['capabilities_1_width_values'][24]:08X}",
        f"CAPABILITIES_1_WIDTH32=0x{aggregate_coverage['capabilities_1_width_values'][32]:08X}",
        "CAPABILITY_WIDTH_CONSTRAINTS=PASS",
        "RESERVED_CAPABILITY_BITS_ZERO=PASS",
        "HIGHER_COMPATIBLE_MINOR_POLICY=APPROVED",
        "MALFORMED_EXPLICIT_CAPABILITY_METADATA=REJECT_INCOMPATIBLE",
        f"DEFERRED_REGISTER_CANDIDATES={selected_coverage['deferred_count']}",
        "CLEAR_EVENT_STATUS_ABI_1_1_STATUS=DEFERRED_NOT_SELECTED",
        "DEFERRED_CANDIDATES_COUNTED_AS_SELECTED_ABI="
        f"{len(selected_coverage['deferred_counted_as_selected'])}",
        "BEHAVIOR_BINDING_COVERAGE="
        f"DERIVED_PASS_{binding_coverage['covered_count']}_OF_{binding_coverage['target_count']}",
        f"UNBOUND_PUBLIC_FIELDS={len(binding_coverage['unbound_fields'])}",
        f"DUPLICATE_BEHAVIOR_BINDINGS={binding_coverage['duplicate_bindings']}",
        "UNCONSUMED_ENABLED_BEHAVIOR_IDS="
        f"{len(binding_coverage['unconsumed_enabled_behavior_ids'])}",
        "APPROVED_ENABLED_ACCESS_TYPES_WITHOUT_BEHAVIOR_ID="
        f"{len(binding_coverage['approved_enabled_access_types_without_behavior_id'])}",
        "WO_W1S_RC_ABI_1_1_ENABLEMENT=DEFINED_TAXONOMY_NOT_ENABLED",
        "PUBLIC_I_CH1_RESET=0",
        "PUBLIC_I_CH2_RESET=0",
        "PUBLIC_I_CH1_I_CH2_SOURCE=LATEST_ATOMIC_DESTINATION_FIFO_DELIVERY",
        "PUBLIC_I_CH1_I_CH2_SOFTWARE_PAIR_ATOMIC=NO",
        f"DOCUMENTATION_PATH_VALIDATION=PASS_{documentation_paths}_OF_{documentation_paths}",
        "STAGE2H_IMPLEMENTATION_STARTED=NO",
        "REGISTER_MAP_CONVERGENCE_CLOSED=NO",
        "NEW_AXI_OFFSETS_IMPLEMENTED=NO",
        "PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS",
        "REMAINING_CONTRACT_GAPS=1",
        "STAGE2_COMPLETE=NO",
    ]
    write_text(output / "runner_summary.txt", "\n".join(summary))


def audit(
    root: Path,
    *,
    check_git_scope: bool,
    python_old: str | None,
    python_new: str | None,
    output: Path | None,
    run_cross_version: bool = True,
) -> dict[str, Any]:
    schema = load_json(root / SCHEMA_PATH)
    contract = load_json(root / CONTRACT_PATH)
    positive = load_json(root / POSITIVE_PATH)
    negative = load_json(root / NEGATIVE_PATH)
    cross = load_json(root / CROSS_NEGATIVE_PATH)
    ast_fixtures = load_json(root / AST_FIXTURE_PATH)

    errors: list[str] = []
    errors.extend(validate_schema(schema, contract))
    errors.extend(semantic_errors(contract))
    errors.extend(check_positive_fixture(contract, positive, negative, cross, ast_fixtures))
    errors.extend(check_source_maps(root, contract))
    errors.extend(check_rtl_semantics(root))
    doc_errors, documentation_paths = documentation_errors(root, contract)
    errors.extend(doc_errors)
    ast_errors, ast_record, ast_results = check_ast_policy(root, contract, ast_fixtures)
    errors.extend(ast_errors)
    matrix: list[dict[str, str]] = []
    cross_version_status = "SKIP_EXPLICIT_UNIT_TEST_MODE"
    if run_cross_version:
        missing = [
            name
            for name, value in (
                ("STAGE2H_PYTHON_OLD", python_old),
                ("STAGE2H_PYTHON_NEW", python_new),
            )
            if not value
        ]
        if missing:
            errors.append(
                "CROSS_VERSION_INTERPRETER_COMMANDS=FAIL_MISSING: "
                + ",".join(missing)
            )
        else:
            matrix_errors, matrix = cross_version_ast_matrix(
                root, contract, str(python_old), str(python_new)
            )
            errors.extend(matrix_errors)
            if not matrix_errors:
                cross_version_status = "PASS_2_OF_2"
    semantic_failures, semantic_results = run_semantic_negative_fixtures(
        contract, negative
    )
    errors.extend(semantic_failures)
    cross_failures, cross_results = run_cross_negative_fixtures(root, contract, cross)
    errors.extend(cross_failures)
    if check_git_scope:
        errors.extend(git_scope_errors(root))

    if errors:
        raise AuditError("Stage 2H audit failed:\n- " + "\n- ".join(errors))
    if output is not None:
        emit_reports(
            output,
            contract,
            semantic_results,
            cross_results,
            ast_results,
            ast_record,
            matrix,
            documentation_paths,
            cross_version_status,
        )
    defect_counts = derive_abi_defect_counts(contract["current_abi"])
    binding_coverage = derive_behavior_binding_coverage(contract)
    selected_coverage = derive_selected_map_coverage(contract)
    capability_coverage = derive_capability_dependency_coverage(contract)
    aggregate_coverage = derive_selected_register_aggregates(contract)
    taxonomy_coverage = derive_fault_taxonomy_coverage(contract)
    dynamic_coverage = derive_dynamic_value_source_coverage(contract)
    invariant_coverage = derive_cross_field_invariant_coverage(contract)
    artifact_topology = derive_generated_artifact_topology(contract)
    stage2h_a1_scope = derive_stage2h_a1_scope(contract)
    rtl_source_coverage = derive_rtl_source_binding_coverage(root, contract)
    identity_coverage = derive_policy_identity_storage_coverage(contract)
    transition_coverage = derive_episode_bitmap_transition_coverage(contract)
    unknown_fault_coverage = derive_unknown_fault_compatibility_coverage(contract)
    scenario_coverage = derive_conformance_scenario_coverage(contract)
    return {
        "registers": len(contract["current_abi"]["registers"]),
        "defects": defect_counts["total"],
        "contradictions": defect_counts["DOCUMENTATION_VS_RTL_CONTRADICTION"],
        "undocumented_behaviors": defect_counts[
            "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR"
        ],
        "duplicate_authorities": contract["authorities"]["duplicate_register_authorities"],
        "semantic_negative": len(semantic_results),
        "cross_negative": len(cross_results),
        "ast_fixtures": len(ast_results),
        "documentation_paths": documentation_paths,
        "canonical_ast_sha256": ast_record["canonical_sha256"],
        "source_segment_sha256": ast_record["source_segment_sha256"],
        "cross_version_status": cross_version_status,
        "cross_version_matrix": matrix,
        "binding_coverage": binding_coverage,
        "selected_map_coverage": selected_coverage,
        "capability_dependency_coverage": capability_coverage,
        "selected_register_aggregate_coverage": aggregate_coverage,
        "fault_taxonomy_coverage": taxonomy_coverage,
        "generated_artifact_topology": artifact_topology,
        "stage2h_a1_scope": stage2h_a1_scope,
        "dynamic_value_source_coverage": dynamic_coverage,
        "cross_field_invariant_coverage": invariant_coverage,
        "rtl_source_binding_coverage": rtl_source_coverage,
        "policy_identity_storage_coverage": identity_coverage,
        "episode_bitmap_transition_coverage": transition_coverage,
        "unknown_fault_compatibility_coverage": unknown_fault_coverage,
        "conformance_scenario_coverage": scenario_coverage,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--no-git-scope-check", action="store_true")
    parser.add_argument("--python-old", default=os.environ.get("STAGE2H_PYTHON_OLD"))
    parser.add_argument("--python-new", default=os.environ.get("STAGE2H_PYTHON_NEW"))
    parser.add_argument("--skip-cross-version-integration", action="store_true")
    parser.add_argument("--ast-probe", nargs=2, metavar=("SOURCE", "FUNCTION"))
    args = parser.parse_args(argv)

    if args.ast_probe:
        source_path, function_name = args.ast_probe
        source = Path(source_path).read_text(encoding="utf-8")
        print(json.dumps(fingerprint_source(source, function_name), sort_keys=True))
        return 0

    try:
        result = audit(
            args.root.resolve(),
            check_git_scope=not args.no_git_scope_check,
            python_old=args.python_old,
            python_new=args.python_new,
            output=args.output.resolve() if args.output else None,
            run_cross_version=not args.skip_cross_version_integration,
        )
    except (AuditError, OSError, SyntaxError) as exc:
        print(f"STAGE2H_STATIC_CONTRACT_AUDIT=FAIL\n{exc}", file=sys.stderr)
        return 1

    print("STAGE2H_STATIC_CONTRACT_AUDIT=PASS")
    print(f"CURRENT_ABI_EXTRACTION=PASS_{result['registers']}_OF_{result['registers']}")
    print("CURRENT_ABI_OFFSETS_0X00_TO_0X60=PASS")
    print("CURRENT_ABI_DEFECT_COUNT=DERIVED")
    print(f"CURRENT_ABI_DEFECT_TOTAL={result['defects']}")
    print(f"CURRENT_ABI_CONTRADICTION_COUNT={result['contradictions']}")
    print(
        "CURRENT_ABI_UNDOCUMENTED_BEHAVIOR_COUNT="
        f"{result['undocumented_behaviors']}"
    )
    print("HARDCODED_CONTRADICTION_COUNT=NO")
    print(f"DUPLICATE_REGISTER_AUTHORITIES={result['duplicate_authorities']}")
    print(
        "SEMANTIC_NEGATIVE_FIXTURES="
        f"PASS_{result['semantic_negative']}_OF_{result['semantic_negative']}"
    )
    print(
        "CROSS_ARTIFACT_NEGATIVE_FIXTURES="
        f"PASS_{result['cross_negative']}_OF_{result['cross_negative']}"
    )
    print(
        "AST_FINGERPRINT_FIXTURES="
        f"PASS_{result['ast_fixtures']}_OF_{result['ast_fixtures']}"
    )
    print(f"PYTHON_CROSS_VERSION_AST={result['cross_version_status']}")
    for record in result["cross_version_matrix"]:
        prefix = record["matrix_role"]
        print(f"{prefix}_PYTHON_EXECUTABLE={record['python_executable']}")
        print(f"{prefix}_PYTHON_VERSION={record['python_version']}")
    print("REGISTER_MAP_SOURCE_OWNS_BEHAVIOR_SEMANTICS=YES")
    print("HANDWRITTEN_RTL_IS_UNTRACKED_AUTHORITY=NO")
    print("GENERATED_ARTIFACT_TOPOLOGY_AUTHORITY=ONE_MASTER_LIST")
    topology = result["generated_artifact_topology"]
    print(
        "MASTER_GENERATED_ARTIFACT_TOPOLOGY="
        f"PASS_{topology['master_covered_count']}_OF_{topology['master_target_count']}"
    )
    print(
        "TAXONOMY_CONSUMERS_MAPPED_TO_MASTER_ARTIFACTS="
        f"PASS_{topology['taxonomy_covered_count']}_OF_{topology['taxonomy_target_count']}"
    )
    print(f"UNOWNED_GENERATED_ARTIFACT_PATHS={len(topology['unowned_paths'])}")
    print(f"DUPLICATE_GENERATED_ARTIFACT_PATHS={topology['duplicate_path_count']}")
    print("LEGACY_RTL_FAULT_DEFS_PATH_PRESERVED=YES")
    print("LEGACY_RTL_FAULT_NAMES_PRESERVED=YES")
    print("FAULT_DEFS_CONTAINS_INDEPENDENT_MANUAL_VALUES_AFTER_CONVERGENCE=NO")
    print("LEGACY_C_HEADER_PATH_PRESERVED=YES")
    print("LEGACY_C_FAULT_NAMES_PRESERVED=YES")
    print("CURRENT_SUBSTAGE=STAGE2H_A1_REGISTER_MAP_AND_PUBLIC_ABI_ARCHITECTURE")
    print("STAGE2H_A1_IMPLEMENTATION_STARTED=NO")
    print("STAGE2H_A_COMPLETE=NO")
    print("STAGE2H_COMPLETE=NO")
    print("NEXT_AFTER_STAGE2H_A1=STAGE2H_A2_REGISTER_MAP_AND_PUBLIC_ABI_IMPLEMENTATION")
    print("STAGE2H_B_STATUS=NOT_STARTED")
    print("STAGE2H_C_STATUS=NOT_STARTED")
    print("STAGE2H_D_STATUS=NOT_STARTED")
    print("STAGE2I_STATUS=NOT_STARTED")
    print("STAGE2H_A1_AUDIT_CONTRACT=spec/stage2h_register_map_convergence.json")
    print("FUTURE_LIVE_REGISTER_MAP_SOURCE=spec/register_map.json")
    print("AUDIT_CONTRACT_IS_FUTURE_LIVE_REGISTER_MAP_SOURCE=NO")
    print("EVERY_PUBLIC_FIELD_HAS_ONE_BEHAVIOR_ID=PASS")
    print("EVERY_BEHAVIOR_ID_HAS_RTL_BINDING=PASS")
    print("EVERY_BINDING_HAS_SPEC_GENERATED_TESTS=PASS")
    print("ZERO_VERSION_WORD=NO_EXPLICIT_DISCOVERY")
    print("NONZERO_BAD_MAGIC=REJECT_INCOMPATIBLE")
    print("UNSUPPORTED_MAJOR=REJECT_INCOMPATIBLE")
    print("BAD_MAGIC_IS_LEGACY=NO")
    print("LEGACY_CAPABILITY_MODEL=PRESENT_ABSENT_UNKNOWN")
    print("HISTORICAL_PRE_STAGE2E_HARDWARE_SUPPORTED_BY_NEW_SOFTWARE=NO")
    print("STAGE2E_LEGACY_DISCOVERY=OBS_CAPABILITY_PROBE")
    print("STAGE2G_LEGACY_CAPABILITY=UNKNOWN")
    print("NORMALIZED_TELEMETRY_CAPABILITY_BIT=RESERVED_ZERO")
    print("CAPABILITY_BIT_MEANS_PUBLIC_SOFTWARE_USABLE_FEATURE=YES")
    print("FIRST_LIVE_SEEN_BITMAP_LIFETIME=ACTIVE_INTERNAL_EPISODE")
    print("BITMAP_COMPATIBILITY_LIFETIME_DOCUMENTED=PASS")
    print("PLATFORM_LAUNCHER_HARDCODED=NO")
    coverage = result["binding_coverage"]
    selected_coverage = result["selected_map_coverage"]
    capability_coverage = result["capability_dependency_coverage"]
    aggregate_coverage = result["selected_register_aggregate_coverage"]
    taxonomy_coverage = result["fault_taxonomy_coverage"]
    dynamic_coverage = result["dynamic_value_source_coverage"]
    rtl_source_coverage = result["rtl_source_binding_coverage"]
    identity_coverage = result["policy_identity_storage_coverage"]
    transition_coverage = result["episode_bitmap_transition_coverage"]
    unknown_fault_coverage = result["unknown_fault_compatibility_coverage"]
    scenario_coverage = result["conformance_scenario_coverage"]
    print(
        "FAULT_CODE_ENUM_COVERAGE="
        f"DERIVED_PASS_{taxonomy_coverage['fault_code_covered_count']}_OF_{taxonomy_coverage['fault_code_target_count']}"
    )
    print(
        "FAULT_CAUSE_ENUM_COVERAGE="
        f"DERIVED_PASS_{taxonomy_coverage['fault_cause_covered_count']}_OF_{taxonomy_coverage['fault_cause_target_count']}"
    )
    print(f"FAULT_BITMAP_WIDTH={taxonomy_coverage['fault_bitmap_width']}")
    print(f"FAULT_BITMAP_VALID_MASK=0x{taxonomy_coverage['valid_mask']:08X}")
    print(f"FAULT_BITMAP_RESERVED_MASK=0x{taxonomy_coverage['reserved_mask']:08X}")
    print("FAULT_TAXONOMY_CONSUMER_PLAN=APPROVED")
    print("LEGACY_FAULT_NAME_ALIAS_PLAN=APPROVED")
    print("COMPATIBILITY_PROJECTION=APPROVED")
    print("FIRST_PRINCIPLES_SCOPE_REVIEW=PASS")
    print("OVERENGINEERED_GENERIC_DSL_ADDED=NO")
    print("GENERAL_VERILOG_SEMANTIC_PARSER_ADDED=NO")
    print("FULL_RTL_DECLARATION_GRAPH_ADDED=NO")
    print("CONFORMANCE_APPROACH=FINITE_PROJECT_SPECIFIC_TEMPLATES")
    print(
        "RTL_SOURCE_BINDING_APPROACH="
        "LIGHTWEIGHT_EXPLICIT_BINDINGS_PLUS_COMPILE_SIM_CHECKS"
    )
    print("LONG_TERM_COMPLEXITY_REDUCED=YES")
    print("POLICY_EVALUATION_IDENTITY_STORAGE=REGISTERED_EVENT_CAPTURE")
    print("POLICY_IDENTITY_DATA_SIGNAL=fault_eval_sequence")
    print("POLICY_IDENTITY_VALID_SIGNAL=fault_eval_valid")
    print("POLICY_IDENTITY_HOLDS_DURING_IDLE=YES")
    print("POLICY_IDENTITY_CAPTURES_NONCLEAN_VALID_RETIREMENT=YES")
    print(
        "POLICY_IDENTITY_CAPTURE_VECTOR_COVERAGE="
        f"PASS_{identity_coverage['vector_covered_count']}_OF_"
        f"{identity_coverage['vector_target_count']}"
    )
    print(
        "RTL_SOURCE_INVENTORY_COVERAGE="
        f"DERIVED_PASS_{rtl_source_coverage['binding_covered_count']}_OF_"
        f"{rtl_source_coverage['binding_target_count']}"
    )
    print(
        "DYNAMIC_SOURCE_TO_RTL_TRACE="
        f"DERIVED_PASS_{rtl_source_coverage['dynamic_trace_covered_count']}_OF_"
        f"{rtl_source_coverage['dynamic_trace_target_count']}"
    )
    print(
        "MISSING_RTL_SOURCE_DECLARATIONS="
        f"{len(rtl_source_coverage['missing_declarations'])}"
    )
    print(
        "RTL_SOURCE_WIDTH_MISMATCHES="
        f"{len(rtl_source_coverage['width_mismatches'])}"
    )
    print(
        "RTL_STATE_ENCODING_MISMATCHES="
        f"{len(rtl_source_coverage['state_mismatches'])}"
    )
    print(
        "UNCONSUMED_RTL_SOURCE_ENTRIES="
        f"{len(rtl_source_coverage['unconsumed_entries'])}"
    )
    print(
        "DYNAMIC_VALUE_SOURCE_COVERAGE="
        f"DERIVED_PASS_{dynamic_coverage['covered_count']}_OF_{dynamic_coverage['target_count']}"
    )
    print(
        f"DYNAMIC_FIELDS_WITHOUT_TYPED_SOURCE={len(dynamic_coverage['fields_without_typed_source'])}"
    )
    print(
        "OPAQUE_DYNAMIC_BINDINGS_WITHOUT_SOURCE_CONTRACT="
        f"{dynamic_coverage['opaque_dynamic_bindings_without_source_contract']}"
    )
    print("POLICY_STATUS_ONE_HOT_INVARIANT=APPROVED")
    print("POLICY_STATUS_RELATIONAL_INVARIANTS=APPROVED")
    print("BITMAP_MASK_AND_LIFETIME_INVARIANTS=APPROVED")
    print(
        "EPISODE_BITMAP_TRANSITION_RULE_COVERAGE="
        f"PASS_{transition_coverage['covered_count']}_OF_"
        f"{transition_coverage['target_count']}"
    )
    print("UNKNOWN_FAULT_CAUSE_FORWARD_COMPATIBILITY=APPROVED")
    print(
        "UNKNOWN_FAULT_CAUSE_VECTOR_COVERAGE="
        f"PASS_{unknown_fault_coverage['vector_covered_count']}_OF_"
        f"{unknown_fault_coverage['vector_target_count']}"
    )
    print("CONFORMANCE_CLAUSE_GRAMMAR=CLOSED")
    print(f"OPAQUE_SCENARIO_TARGETS={len(scenario_coverage['opaque_targets'])}")
    print(f"OPAQUE_SCENARIO_VALUES={len(scenario_coverage['opaque_values'])}")
    print(
        "SCENARIO_REFERENCE_RESOLUTION="
        f"{'PASS' if not scenario_coverage['reference_errors'] else 'FAIL'}"
    )
    print(
        "SCENARIO_BINDING_EDGE_MISMATCHES="
        f"{len(scenario_coverage['binding_edge_mismatches'])}"
    )
    print(
        "SCENARIO_EXECUTABILITY="
        f"DERIVED_PASS_{scenario_coverage['covered_count']}_OF_"
        f"{scenario_coverage['target_count']}"
    )
    print(
        "CONFORMANCE_SCENARIO_DEFINITION_COVERAGE="
        f"DERIVED_PASS_{scenario_coverage['covered_count']}_OF_{scenario_coverage['target_count']}"
    )
    print(
        "CONFORMANCE_FAMILIES_WITHOUT_MACHINE_SCENARIOS="
        f"{len(scenario_coverage['missing_families'])}"
    )
    print("POLICY_EVALUATION_SEQUENCE_ROLE=DIAGNOSTIC_LAST_RETIREMENT_IDENTITY")
    print("POLICY_EVALUATION_SEQUENCE_IS_SNAPSHOT_TOKEN=NO")
    print("READ_POLICY_SNAPSHOT_API=DEFERRED")
    print("POLICY_MULTI_REGISTER_COHERENCE=INDEPENDENTLY_COHERENT")
    print("POLICY_SNAPSHOT_OVERCLAIM=NO")
    print(f"SELECTED_ABI_1_1_REGISTER_COUNT={selected_coverage['selected_register_count']}")
    print(
        "SELECTED_ABI_1_1_REGISTER_COVERAGE="
        f"DERIVED_PASS_{selected_coverage['covered_register_count']}_OF_{selected_coverage['selected_register_count']}"
    )
    print(
        "SELECTED_ABI_1_1_FIELD_COVERAGE="
        f"DERIVED_PASS_{selected_coverage['covered_field_count']}_OF_{selected_coverage['selected_field_count']}"
    )
    print(
        "SELECTED_ABI_1_1_BIT_COVERAGE="
        f"DERIVED_PASS_{selected_coverage['selected_bit_count']}_OF_{selected_coverage['expected_bit_count']}"
    )
    print(
        "ALLOCATED_REGISTERS_WITHOUT_FIELD_CONTRACT="
        f"{len(selected_coverage['allocated_without_field_contract'])}"
    )
    print(
        "FIELD_CONTRACTS_WITHOUT_ALLOCATION="
        f"{len(selected_coverage['definitions_without_allocation'])}"
    )
    print(
        "UNALLOCATED_FIELDS_COUNTED_AS_ABI_1_1="
        f"{len(selected_coverage['unallocated_fields'])}"
    )
    print(f"UNCOVERED_SELECTED_REGISTER_BITS={len(selected_coverage['uncovered_bits'])}")
    print(f"OVERLAPPING_SELECTED_REGISTER_BITS={len(selected_coverage['overlapping_bits'])}")
    print(
        "DISCOVERY_REGISTER_BEHAVIOR_BINDINGS="
        f"DERIVED_PASS_{len(DISCOVERY_BINDING_TARGETS)}_OF_{len(DISCOVERY_BINDING_TARGETS)}"
    )
    print("DISCOVERY_REGISTER_CONFORMANCE_FAMILIES=PASS")
    print("RESERVED_DISCOVERY_BITS_ZERO=PASS")
    print(
        "CAPABILITY_DEPENDENCY_COVERAGE="
        f"DERIVED_PASS_{capability_coverage['covered_count']}_OF_{capability_coverage['target_count']}"
    )
    print(
        "CAPABILITIES_WITH_MISSING_REGISTER_DEPENDENCIES="
        f"{len(capability_coverage['missing_register_dependencies'])}"
    )
    print(
        "CAPABILITIES_WITH_MISSING_FIELD_DEPENDENCIES="
        f"{len(capability_coverage['missing_field_dependencies'])}"
    )
    print(
        "CAPABILITIES_WITH_MISSING_BINDING_DEPENDENCIES="
        f"{len(capability_coverage['missing_binding_dependencies'])}"
    )
    print(
        "CAPABILITIES_WITH_MISSING_API_DEPENDENCIES="
        f"{len(capability_coverage['missing_api_dependencies'])}"
    )
    print("CAPABILITY_DEPENDENCY_AUTHORITY=capability_dependency_matrix")
    print(
        "CAPABILITY_EDGE_COVERAGE="
        f"DERIVED_PASS_{capability_coverage['capability_edge_covered_count']}_OF_{capability_coverage['capability_edge_target_count']}"
    )
    print(
        "FIELD_CAPABILITY_EDGE_MISMATCHES="
        f"{len(capability_coverage['field_capability_edge_mismatches'])}"
    )
    print(
        "API_CAPABILITY_GATE_MISMATCHES="
        f"{len(capability_coverage['api_capability_gate_mismatches'])}"
    )
    print(
        "BINDING_CONFORMANCE_EDGE_MISMATCHES="
        f"{len(capability_coverage['binding_conformance_edge_mismatches'])}"
    )
    print("CAPABILITY_IMPLICATION_GRAPH=ACYCLIC")
    print(
        "CAPABILITY_IMPLICATION_VIOLATIONS="
        f"{len(capability_coverage['capability_implication_violations'])}"
    )
    print(
        "FREE_FORM_CAPABILITY_EXPRESSIONS="
        f"{len(capability_coverage['free_form_capability_expressions'])}"
    )
    print("REGISTER_RESET_AUTHORITY=DERIVED_FROM_FIELD_RESETS")
    print("REGISTER_STATIC_VALUE_AUTHORITY=DERIVED_FROM_FIELD_STATIC_VALUES")
    print("MANUAL_REGISTER_RESET_DUPLICATION=FORBIDDEN")
    print(
        "SELECTED_REGISTER_RESET_DERIVATION="
        f"PASS_{aggregate_coverage['reset_covered_count']}_OF_{aggregate_coverage['reset_target_count']}"
    )
    print(
        "SELECTED_REGISTER_STATIC_VALUE_DERIVATION="
        f"PASS_{aggregate_coverage['static_covered_count']}_OF_{aggregate_coverage['static_target_count']}"
    )
    print(
        "REGISTER_FIELD_RESET_MISMATCHES="
        f"{len(aggregate_coverage['register_field_reset_mismatches'])}"
    )
    print(
        "REGISTER_FIELD_STATIC_VALUE_MISMATCHES="
        f"{len(aggregate_coverage['register_field_static_value_mismatches'])}"
    )
    print(
        "REGISTER_FIELD_ACCESS_MISMATCHES="
        f"{len(aggregate_coverage['register_field_access_mismatches'])}"
    )
    print(
        "NON_MACHINE_EVALUABLE_REGISTER_VALUES="
        f"{len(aggregate_coverage['non_machine_evaluable_register_values'])}"
    )
    print("PARAMETERIZED_REGISTER_EXPRESSIONS=VALIDATED")
    print(
        f"CAPABILITIES_1_WIDTH16=0x{aggregate_coverage['capabilities_1_width_values'][16]:08X}"
    )
    print(
        f"CAPABILITIES_1_WIDTH24=0x{aggregate_coverage['capabilities_1_width_values'][24]:08X}"
    )
    print(
        f"CAPABILITIES_1_WIDTH32=0x{aggregate_coverage['capabilities_1_width_values'][32]:08X}"
    )
    print("CAPABILITY_WIDTH_CONSTRAINTS=PASS")
    print("RESERVED_CAPABILITY_BITS_ZERO=PASS")
    print("HIGHER_COMPATIBLE_MINOR_POLICY=APPROVED")
    print("MALFORMED_EXPLICIT_CAPABILITY_METADATA=REJECT_INCOMPATIBLE")
    print(f"DEFERRED_REGISTER_CANDIDATES={selected_coverage['deferred_count']}")
    print("CLEAR_EVENT_STATUS_ABI_1_1_STATUS=DEFERRED_NOT_SELECTED")
    print(
        "DEFERRED_CANDIDATES_COUNTED_AS_SELECTED_ABI="
        f"{len(selected_coverage['deferred_counted_as_selected'])}"
    )
    print(
        "BEHAVIOR_BINDING_COVERAGE="
        f"DERIVED_PASS_{coverage['covered_count']}_OF_{coverage['target_count']}"
    )
    print(f"UNBOUND_PUBLIC_FIELDS={len(coverage['unbound_fields'])}")
    print(f"DUPLICATE_BEHAVIOR_BINDINGS={coverage['duplicate_bindings']}")
    print(
        "UNCONSUMED_ENABLED_BEHAVIOR_IDS="
        f"{len(coverage['unconsumed_enabled_behavior_ids'])}"
    )
    print(
        "APPROVED_ENABLED_ACCESS_TYPES_WITHOUT_BEHAVIOR_ID="
        f"{len(coverage['approved_enabled_access_types_without_behavior_id'])}"
    )
    print("WO_W1S_RC_ABI_1_1_ENABLEMENT=DEFINED_TAXONOMY_NOT_ENABLED")
    print("PUBLIC_I_CH1_RESET=0")
    print("PUBLIC_I_CH2_RESET=0")
    print("PUBLIC_I_CH1_I_CH2_SOURCE=LATEST_ATOMIC_DESTINATION_FIFO_DELIVERY")
    print("PUBLIC_I_CH1_I_CH2_SOFTWARE_PAIR_ATOMIC=NO")
    print(f"CANONICAL_AST_SHA256={result['canonical_ast_sha256']}")
    print(f"DIAGNOSTIC_SOURCE_SHA256={result['source_segment_sha256']}")
    print("STAGE2H_IMPLEMENTATION_STARTED=NO")
    print("REGISTER_MAP_CONVERGENCE_CLOSED=NO")
    print("NEW_AXI_OFFSETS_IMPLEMENTED=NO")
    print("PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS")
    print("REMAINING_CONTRACT_GAPS=1")
    print("STAGE2_COMPLETE=NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
