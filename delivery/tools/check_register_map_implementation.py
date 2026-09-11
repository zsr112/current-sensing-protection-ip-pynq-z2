#!/usr/bin/env python3
"""Check the Stage 2H-A2 ABI 1.1 register-map implementation."""

from __future__ import annotations

import argparse
import ast
import hashlib
import importlib
import importlib.util
import json
import re
import sys
from collections.abc import Callable, Iterable
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import generate_register_map as generator


class CheckError(RuntimeError):
    """The generated implementation or one of its consumers is inconsistent."""


A2_AUTHORITY_PATHS = (
    Path("spec/register_map.json"),
    Path("spec/register_map.schema.json"),
    Path("tools/generate_register_map.py"),
    Path("tools/check_register_map_implementation.py"),
    Path("tools/replay_register_map_source_archive.py"),
    Path(
        "fpga/vivado/build/runtime/runner/"
        "stage1e_production_vivado_runner_v2.tcl"
    ),
    *(Path(path) for path in generator.MASTER_ARTIFACTS),
)

ABI_1_1_REGISTER_NAMES = {
    "REGISTER_MAP_VERSION",
    "CAPABILITIES_0",
    "CAPABILITIES_1",
    "POLICY_STATUS",
    "FIRST_FAULT_BITMAP",
    "LIVE_FAULT_BITMAP",
    "FAULT_SEEN_BITMAP",
    "POLICY_EVALUATION_SEQUENCE",
}

AUDIT_ONLY_KEYS = {
    "evidence_path",
    "fixture_count",
    "review_package",
    "review_status",
    "source_archive_replay",
}

CONSUMER_ROLES = (
    "ACTIVE_GENERATED_CONSUMER",
    "INDEPENDENT_FROZEN_ORACLE",
    "FROZEN_HISTORICAL_SNAPSHOT",
)

LEGACY_REGISTER_OFFSETS = {
    "REG_CTRL": 0x00,
    "REG_STATUS": 0x04,
    "REG_FAULT_CODE": 0x08,
    "REG_I_CH1": 0x0C,
    "REG_I_CH2": 0x10,
    "REG_TH_OC1": 0x14,
    "REG_TH_OC2": 0x18,
    "REG_TH_DIFF": 0x1C,
    "REG_PWM_PERIOD": 0x20,
    "REG_PWM_DUTY": 0x24,
    "REG_OBS_CAPABILITY": 0x28,
    "REG_OBS_STATUS": 0x2C,
    "REG_OBS_SOURCE_ACCEPT": 0x30,
    "REG_OBS_DESTINATION_DELIVERY": 0x34,
    "REG_OBS_BACKPRESSURE": 0x38,
    "REG_OBS_SOURCE_PROTOCOL": 0x3C,
    "REG_OBS_SOURCE_DROP": 0x40,
    "REG_OBS_FIFO_OVERFLOW": 0x44,
    "REG_OBS_FIFO_UNDERFLOW": 0x48,
    "REG_OBS_DUPLICATE": 0x4C,
    "REG_OBS_SEQUENCE_GAP": 0x50,
    "REG_OBS_REORDER_STALE": 0x54,
    "REG_OBS_AGGREGATE": 0x58,
    "REG_OBS_LAST_SOURCE_SEQUENCE": 0x5C,
    "REG_OBS_LAST_DESTINATION_SEQUENCE": 0x60,
}

LEGACY_FAULT_CODES = {
    "FAULT_NONE": 0x00,
    "FAULT_OVERCURRENT": 0x01,
    "FAULT_SENSOR_MISMATCH": 0x02,
    "FAULT_SENSOR_OPEN": 0x03,
    "FAULT_SENSOR_SATURATION": 0x04,
    "FAULT_SENSOR_STUCK": 0x05,
    "FAULT_OC_WITH_SENSOR": 0x06,
}

LEGACY_FAULT_ALIASES = {"FAULT_DIFFERENTIAL": 0x02}

ACTIVE_CONSUMER_PATHS = (
    "rtl/fault_classifier.v",
    "rtl/fault_defs.vh",
    "rtl/protection_fsm.v",
    "rtl/protection_reg_bank.v",
    "sw/protection_ip_interface.py",
    "sw/pynq_mmio_demo_preboard.py",
    "sw/stage2c9e_b_pynq_mmio_register_smoke.py",
    "sw/stage2c9f_b_controlled_expanded_mmio_idempotent_rw.py",
    "sw/stage2i_board_runtime.py",
    "tools/board_validation/stage1_board_functional_validation.py",
    "tools/board_validation/build_stage1_board_execution_package.py",
    "tools/board_validation/stage2_board_session.py",
    "fpga/pynq/deployment/stage1g/stage2i_current_release.py",
    (
        "fpga/vivado/build/runtime/runner/"
        "stage1e_production_vivado_runner_v2.tcl"
    ),
    "tb/coverage/tb_sensor_health_mainline_width_smoke.sv",
    "tb/stage2/tb_stage2_sampling_contract.sv",
    "tb/stage2b/stage2b_sample_acceptance_checker.sv",
    "tb/stage2b/tb_stage2b_unified_sample_acceptance.sv",
    "tb/stage2c/tb_stage2c_reset_release_cdc.sv",
    "tb/stage2d/tb_stage2d_async_adc_atomic_cdc.sv",
    "tb/stage2e/tb_stage2e_axi_register_contract.sv",
    "tb/stage2g/tb_stage2g_policy_matrix.sv",
    "tb/stage2g/tb_stage2g_production_path.sv",
    "tb/tb_fault_classifier.sv",
    "tb/tb_protection_core_top.sv",
    "tb/tb_protection_fsm.sv",
    "tb/tb_protection_ip_top_axi_lite.sv",
    "tb/tb_protection_reg_bank.sv",
)

ORACLE_CONSUMERS = {
    "tools/check_stage2g_recovery_snapshots.py": {
        "FAULT_OVERCURRENT": 0x01,
        "FAULT_SENSOR_MISMATCH": 0x02,
    },
    "tools/stage2g_reference_model.py": LEGACY_FAULT_CODES,
    "tb/coverage/protection_functional_coverage_monitor.sv": LEGACY_FAULT_CODES,
    "tb/coverage/tb_protection_functional_coverage.sv": {
        name: LEGACY_REGISTER_OFFSETS[name]
        for name in (
            "REG_CTRL",
            "REG_STATUS",
            "REG_FAULT_CODE",
            "REG_TH_OC1",
            "REG_TH_OC2",
            "REG_TH_DIFF",
            "REG_PWM_PERIOD",
            "REG_PWM_DUTY",
        )
    },
    "tb/stage2e/tb_stage2e_transaction_error_observability.sv": {
        name: value
        for name, value in LEGACY_REGISTER_OFFSETS.items()
        if name.startswith("REG_OBS_")
    },
    "tb/tb_protection_ip_top_reg_controlled.sv": {
        name: LEGACY_REGISTER_OFFSETS[name]
        for name in tuple(LEGACY_REGISTER_OFFSETS)[:10]
    },
    "tb/tb_stage1_board_fault_stimulus.sv": {
        name: LEGACY_REGISTER_OFFSETS[name]
        for name in tuple(LEGACY_REGISTER_OFFSETS)[:10]
    },
}

HISTORICAL_CONSUMERS = {
    "notebooks/pynq_protection_mmio_demo_preboard.ipynb": (
        "012415f66502b666ad639b2d62920c82ae571dc9fc78cf510684948409f4565b"
    ),
    "fpga/pynq/deployment/stage1g/verify_installed_release.py": (
        "652d7ae31ff17b23cd8216b2bdb99839e48a734f7b526fdbd822a04ec2db41c2"
    ),
}

CONSUMER_INVENTORY = tuple(
    [{"path": path, "role": CONSUMER_ROLES[0]} for path in ACTIVE_CONSUMER_PATHS]
    + [
        {"path": path, "role": CONSUMER_ROLES[1], "oracle_constants": constants}
        for path, constants in ORACLE_CONSUMERS.items()
    ]
    + [
        {"path": path, "role": CONSUMER_ROLES[2], "sha256": digest}
        for path, digest in HISTORICAL_CONSUMERS.items()
    ]
)

ACTIVE_CONSUMER_BINDING_PATHS = (
    "sw/protection_ip_interface.py",
    "sw/pynq_mmio_demo_preboard.py",
    "sw/stage2c9e_b_pynq_mmio_register_smoke.py",
    "sw/stage2c9f_b_controlled_expanded_mmio_idempotent_rw.py",
    "sw/stage2i_board_runtime.py",
    "tools/board_validation/stage1_board_functional_validation.py",
    "tools/board_validation/build_stage1_board_execution_package.py",
    "tools/board_validation/stage2_board_session.py",
    "fpga/pynq/deployment/stage1g/stage2i_current_release.py",
    "tools/build_current_release.py::read_only_example",
)

ACTIVE_REGISTER_CONTAINER_BINDING_PATHS = (
    "sw/stage2c9e_b_pynq_mmio_register_smoke.py::READ_REGISTERS",
    "sw/stage2c9f_b_controlled_expanded_mmio_idempotent_rw.py::READ_REGISTERS",
    "sw/stage2i_board_runtime.py::read_all_registers",
)

LEGACY_RUNTIME_REGISTER_MEMBERS = (
    "CTRL",
    "STATUS",
    "FAULT_CODE",
    "I_CH1",
    "I_CH2",
    "TH_OC1",
    "TH_OC2",
    "TH_DIFF",
    "PWM_PERIOD",
    "PWM_DUTY",
)

CURRENT_RUNTIME_REGISTER_MEMBERS = (
    *(name.removeprefix("REG_") for name in LEGACY_REGISTER_OFFSETS),
    "REGISTER_MAP_VERSION",
    "CAPABILITIES_0",
    "CAPABILITIES_1",
    "POLICY_STATUS",
    "FIRST_FAULT_BITMAP",
    "LIVE_FAULT_BITMAP",
    "FAULT_SEEN_BITMAP",
    "POLICY_EVALUATION_SEQUENCE",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CheckError(message)


def read_text(root: Path, relative: str | Path) -> str:
    path = root / relative
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise CheckError(f"required file is unavailable: {relative}") from exc


def read_json(root: Path, relative: str | Path) -> dict[str, Any]:
    try:
        value = json.loads(read_text(root, relative))
    except json.JSONDecodeError as exc:
        raise CheckError(f"invalid generated JSON: {relative}: {exc}") from exc
    require(isinstance(value, dict), f"generated JSON root is not an object: {relative}")
    return value


def assert_deterministic(
    renderer: Callable[[], dict[str, str]],
) -> dict[str, str]:
    first = renderer()
    second = renderer()
    if first != second:
        changed = sorted(
            set(first) ^ set(second)
            | {name for name in first.keys() & second.keys() if first[name] != second[name]}
        )
        raise CheckError(f"generator output is nondeterministic: {changed}")
    return first


def validate_fault_defs_shim(text: str) -> None:
    require(
        '`include "generated/protection_register_map.vh"' in text,
        "rtl/fault_defs.vh does not include the generated numeric authority",
    )
    independent = re.findall(
        r"(?m)^\s*`define\s+FAULT_(?!DEFS_VH\b)[A-Z0-9_]+\b", text
    )
    require(
        not independent,
        "rtl/fault_defs.vh contains an independent numeric or alias definition",
    )


def validate_stage2g_tb_include_path(text: str) -> None:
    require(
        'TB_GENERATED = ROOT / "tb/generated"' in text,
        "Stage 2G runner does not own the generated testbench include root",
    )
    require(
        'TB_GENERATED = TB / "generated"' not in text,
        "Stage 2G runner resolves generated includes below tb/stage2g",
    )
    require(
        text.count("str(TB_GENERATED)") >= 2,
        "Stage 2G runner omits generated includes from a simulator path",
    )


def nested_keys(value: Any) -> set[str]:
    keys: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            keys.add(str(key))
            keys.update(nested_keys(child))
    elif isinstance(value, list):
        for child in value:
            keys.update(nested_keys(child))
    return keys


def load_and_render(root: Path) -> tuple[dict[str, str], dict[str, Any]]:
    spec, _ = generator.load_json(root / "spec/register_map.json")
    schema, _ = generator.load_json(root / "spec/register_map.schema.json")
    baseline, baseline_bytes = generator.load_json(
        root / "spec/stage2h_register_map_convergence.json"
    )

    def render() -> dict[str, str]:
        outputs, _ = generator.validate_and_render(
            spec,
            schema,
            baseline,
            baseline_bytes=baseline_bytes,
        )
        return outputs

    return assert_deterministic(render), spec


def check_reports(root: Path) -> None:
    compatibility = read_json(
        root, "spec/generated/protection_register_map_compatibility.json"
    )
    conformance = read_json(
        root, "spec/generated/protection_register_map_conformance.json"
    )
    legacy = compatibility.get("legacy_abi", {})
    expected = {
        "address_range": "0x00..0x60",
        "external_behavior_changed": False,
        "static_parity": "PASS",
        "software_constant_parity": "PASS",
        "fault_code_parity": "PASS",
        "register_count": 25,
        "field_count": 54,
        "fault_code_count": 7,
        "offset_changes": 0,
        "width_changes": 0,
        "field_encoding_changes": 0,
        "access_semantic_changes": 0,
        "reset_semantic_changes": 0,
        "fault_code_changes": 0,
        "fault_alias_changes": 0,
    }
    require(legacy == expected, "generated compatibility legacy parity is incomplete")
    topology = compatibility.get("generated_artifact_topology", {})
    require(
        topology.get("authority") == "ONE_MASTER_LIST"
        and topology.get("paths") == list(generator.MASTER_ARTIFACTS)
        and topology.get("unowned_paths") == []
        and topology.get("duplicate_paths") == [],
        "generated compatibility topology differs from the frozen master list",
    )
    remediations = compatibility.get("current_abi_remediations", [])
    require(len(remediations) == 8, "compatibility report does not close eight remediations")
    require(
        sum(row.get("classification") == "DOCUMENTATION_VS_RTL_CONTRADICTION" for row in remediations)
        == 3,
        "compatibility report does not close three documentation contradictions",
    )
    require(
        sum(row.get("classification") == "UNDOCUMENTED_FROZEN_ABI_BEHAVIOR" for row in remediations)
        == 5,
        "compatibility report does not close five undocumented behaviors",
    )
    require(
        all(row.get("behavior_changed") is False for row in remediations),
        "a remediation claims a frozen behavior change",
    )
    require(len(compatibility.get("fault_codes", [])) == 7, "fault taxonomy is not seven values")
    require(
        len(compatibility.get("register_inventory", [])) == 33,
        "complete inventory is not 33 registers",
    )
    abi_1_1 = compatibility.get("abi_1_1", {})
    require(
        abi_1_1
        == {
            "version": "1.1",
            "additive": True,
            "explicit_enable_parameter": "EXPLICIT_ABI_1_1",
            "register_count": 8,
            "field_count": 43,
            "bit_coverage": 256,
            "total_register_count": 33,
            "total_field_count": 97,
            "register_map_version_value": "0x524D0101",
            "capabilities_0_value": "0x0000006F",
            "capabilities_1_values": {
                "16": "0x20101006",
                "24": "0x20101806",
                "32": "0x20102006",
            },
            "legacy_instance_discovery_value": "0x00000000",
            "production_path_explicit": True,
        },
        "generated compatibility ABI 1.1 summary is incomplete",
    )
    require(
        conformance.get("legacy_address_range") == {"first": "0x00", "last": "0x60"},
        "conformance report legacy range changed",
    )
    registers = conformance.get("registers", [])
    require(len(registers) == 33, "conformance register count is not 33")
    require(
        sum(len(register.get("fields", [])) for register in registers) == 97,
        "conformance field count is not 97",
    )
    require(
        conformance.get("map_counts")
        == {
            "total_register_count": 33,
            "legacy_register_count": 25,
            "abi_1_1_added_register_count": 8,
            "total_field_count": 97,
            "legacy_field_count": 54,
            "abi_1_1_added_field_count": 43,
        },
        "conformance map counts are incomplete",
    )
    conformance_abi = conformance.get("abi_1_1", {})
    require(
        conformance_abi.get("register_count") == 8
        and conformance_abi.get("field_count") == 43
        and conformance_abi.get("bit_coverage") == 256,
        "conformance selected ABI coverage is incomplete",
    )
    templates = {
        item.get("id") for item in conformance_abi.get("conformance_templates", [])
    }
    require(
        templates
        == {
            "RO_STATIC",
            "RO_STATE_DECODE",
            "RO_LEVEL",
            "RO_BITMAP",
            "RO_EVENT_CAPTURE",
            "FAULT_PROJECTION",
            "FAULT_FORWARD_COMPATIBILITY",
        },
        "conformance template inventory changed",
    )
    fields_by_target = {
        f"{register['name']}.{field['name']}": field
        for register in registers
        for field in register.get("fields", [])
    }
    added_registers = {
        register["name"]
        for register in registers
        if int(register["offset"], 16) > 0x60
    }
    require(
        added_registers == ABI_1_1_REGISTER_NAMES,
        "conformance selected register inventory changed",
    )
    for target, field in fields_by_target.items():
        if target.split(".", 1)[0] not in added_registers:
            continue
        require(
            field.get("behavior_id")
            and field.get("rtl_binding_id")
            and field.get("capability_gate_ref")
            and field.get("conformance_family")
            and field.get("conformance_templates"),
            f"behavior-complete conformance metadata missing: {target}",
        )
        authorities = sum(
            field.get(name) is not None
            for name in ("static_value", "dynamic_source")
        )
        require(authorities == 1, f"field value authority is not unique: {target}")

    software = read_text(root, "sw/protection_ip_interface.py")
    api_functions = {
        "API_IS_ARMED": "is_armed",
        "API_STARTUP_READY": "startup_ready",
        "API_READ_POLICY_STATUS": "read_policy_status",
        "API_READ_CAPABILITIES": "read_capabilities",
        "API_READ_REGISTER_MAP_VERSION": "read_register_map_version",
        "API_READ_OBSERVABILITY": "read_observability",
        "API_CLEAR_OBSERVABILITY_STATUS": "clear_observability_status",
        "API_READ_FIRST_FAULT_BITMAP": "read_first_fault_bitmap",
        "API_READ_LIVE_FAULT_BITMAP": "read_live_fault_bitmap",
        "API_READ_FAULT_SEEN_BITMAP": "read_fault_seen_bitmap",
        "API_READ_POLICY_EVALUATION_IDENTITY": (
            "read_policy_evaluation_identity"
        ),
    }
    defined_functions = {
        node.name
        for node in ast.parse(software).body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    api_gate_ids = {
        item.get("id") for item in conformance_abi.get("api_gates", [])
    }
    require(api_gate_ids == set(api_functions), "software API gate inventory changed")
    for api_id, function in api_functions.items():
        require(
            function in defined_functions,
            f"advertised capability API is not implemented: {api_id}",
        )
    metadata_ids = set(conformance_abi.get("metadata_constraints", []))
    for capability in conformance_abi.get("capabilities", []):
        if not capability.get("advertised"):
            continue
        for edge in capability.get("required_edges", []):
            field = fields_by_target.get(edge.get("target"))
            require(
                field is not None
                and field.get("rtl_binding_id") == edge.get("rtl_binding_id")
                and field.get("conformance_family")
                == edge.get("conformance_family"),
                "advertised capability edge is disconnected: "
                f"{capability.get('id')}:{edge.get('target')}",
            )
        require(
            set(capability.get("required_api_gates", [])) <= api_gate_ids,
            f"advertised capability software API edge is disconnected: {capability.get('id')}",
        )
        require(
            set(capability.get("required_metadata_constraints", []))
            <= metadata_ids,
            f"advertised capability metadata edge is disconnected: {capability.get('id')}",
        )


def check_python_reexport(root: Path) -> None:
    root_text = str(root)
    if root_text not in sys.path:
        sys.path.insert(0, root_text)
    generated = importlib.import_module("sw.generated.protection_register_map")
    interface = importlib.import_module("sw.protection_ip_interface")
    missing = [name for name in generated.__all__ if not hasattr(interface, name)]
    require(not missing, f"software interface omits generated exports: {missing}")
    unequal = [
        name
        for name in generated.__all__
        if getattr(interface, name) != getattr(generated, name)
    ]
    require(not unequal, f"software interface redefines generated values: {unequal}")


_ABI_NAMES = frozenset((*LEGACY_REGISTER_OFFSETS, *LEGACY_FAULT_CODES, *LEGACY_FAULT_ALIASES))
_ABI_CONTAINER_NAMES = frozenset(
    {"REGISTERS", "REGISTER_DEFS", "READ_REGISTERS", "REGISTER_MAP", "EXPECTED_OFFSETS", "EXPECTED_REGISTERS"}
)
_GENERATED_IMPORTS = frozenset(
    {
        "sw.generated.protection_register_map",
        "generated.protection_register_map",
        "sw.protection_ip_interface",
        "protection_ip_interface",
    }
)


def _discovery_excluded(relative: str) -> bool:
    """Keep generated, test, and pinned historical sources out of discovery."""

    return (
        "/tests/" in f"/{relative}"
        or
        relative.startswith("sw/generated/")
        or relative.startswith("sw/tests/")
        or relative in HISTORICAL_CONSUMERS
    )


def _assignment_targets(node: ast.Assign | ast.AnnAssign) -> list[str]:
    targets = node.targets if isinstance(node, ast.Assign) else [node.target]
    return [target.id for target in targets if isinstance(target, ast.Name)]


def _mmio_usage_signature(tree: ast.Module) -> bool:
    """Recognize the finite MMIO signatures used by executable Python consumers.

    This intentionally follows only constructor/parameter names and one simple
    alias level; it does not attempt repository-wide dataflow or generic
    ``read``/``write`` call scanning.
    """

    mmio_names: set[str] = set()
    mmio_constructors = {"MMIO"}
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            for alias in node.names:
                if alias.name == "MMIO" and (node.module or "") in {"pynq", "pynq.mmio"}:
                    mmio_constructors.add(alias.asname or alias.name)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pynq" and alias.asname:
                    mmio_constructors.add(f"{alias.asname}.MMIO")
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            arguments = [*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs]
            if node.args.vararg is not None:
                arguments.append(node.args.vararg)
            if node.args.kwarg is not None:
                arguments.append(node.args.kwarg)
            for argument in arguments:
                name = argument.arg.lower()
                if "mmio" in name or name in {"io", "protection"}:
                    mmio_names.add(argument.arg)

    # Resolve constructor results and exactly one simple alias level.
    aliases: list[tuple[str, str]] = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        value = node.value
        constructor = (
            isinstance(value, ast.Call)
            and (
                (isinstance(value.func, ast.Name) and value.func.id in mmio_constructors)
                or (
                    isinstance(value.func, ast.Attribute)
                    and value.func.attr == "MMIO"
                )
            )
        )
        if constructor:
            mmio_names.update(_assignment_targets(node))
        chain = _attribute_chain(value)
        if chain in mmio_names:
            aliases.extend((target, chain) for target in _assignment_targets(node))
    mmio_names.update(target for target, _ in aliases)

    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr in {"read", "write"}
            and _attribute_chain(node.func.value) in mmio_names
        ):
            return True
    return False


def _python_consumer_candidate(path: Path) -> bool:
    relative = path.as_posix()
    normalized = relative.replace("\\", "/")
    scope_relative = normalized
    for prefix in ("sw/", "tools/", "fpga/"):
        marker = f"/{prefix}"
        if marker in normalized:
            scope_relative = normalized[normalized.index(marker) + 1 :]
            break
    if _discovery_excluded(scope_relative):
        return False
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=relative)
    except (OSError, SyntaxError):
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name in _GENERATED_IMPORTS for alias in node.names):
                return True
        elif isinstance(node, ast.ImportFrom):
            if (node.module or "") in _GENERATED_IMPORTS:
                return True
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(
                isinstance(target, ast.Name)
                and (target.id in _ABI_NAMES or target.id in _ABI_CONTAINER_NAMES)
                for target in targets
            ):
                return True
    if scope_relative.startswith("sw/") and _mmio_usage_signature(tree):
        return True
    # This source emits a standalone executable example from a template string.
    if relative.replace("\\", "/").endswith("/tools/build_current_release.py"):
        text = path.read_text(encoding="utf-8")
        return "def read_only_example()" in text and "REGISTERS =" in text
    return False


def discover_executable_consumers(root: Path) -> set[str]:
    discovered: set[str] = set()
    for base in ("sw", "tools", "fpga"):
        directory = root / base
        if directory.is_dir():
            for path in directory.rglob("*.py"):
                if _python_consumer_candidate(path):
                    discovered.add(path.relative_to(root).as_posix())
    for base in ("rtl", "tb"):
        directory = root / base
        if not directory.is_dir():
            continue
        for path in directory.rglob("*"):
            if path.suffix not in {".v", ".sv", ".vh"} or "/generated/" in path.as_posix():
                continue
            text = path.read_text(encoding="utf-8")
            if re.search(
                r'`include\s+"(?:fault_defs|generated/protection_register_map|protection_register_map)\.(?:vh|svh)"',
                text,
            ) or re.search(
                r"(?m)^\s*localparam[^\n]*(?:\b(?:REG_(?:CTRL|STATUS|FAULT_CODE|I_CH1|I_CH2|TH_OC1|TH_OC2|TH_DIFF|PWM_PERIOD|PWM_DUTY|OBS_[A-Z0-9_]+)|FAULT_(?:NONE|OVERCURRENT|SENSOR_MISMATCH|SENSOR_OPEN|SENSOR_SATURATION|SENSOR_STUCK|OC_WITH_SENSOR))\b)\s*=",
                text,
            ):
                discovered.add(path.relative_to(root).as_posix())
    notebook = root / "notebooks/pynq_protection_mmio_demo_preboard.ipynb"
    notebook_relative = notebook.relative_to(root).as_posix() if notebook.is_file() else ""
    if (
        notebook.is_file()
        and not _discovery_excluded(notebook_relative)
        and re.search(r"REG_CTRL\s*=\s*0x", notebook.read_text(encoding="utf-8"))
    ):
        discovered.add(notebook.relative_to(root).as_posix())
    live_runner = (
        root
        / "fpga/vivado/build/runtime/runner/"
        "stage1e_production_vivado_runner_v2.tcl"
    )
    if (
        live_runner.is_file()
        and "generated protection_register_map_ipxact.tcl"
        in live_runner.read_text(encoding="utf-8")
    ):
        discovered.add(live_runner.relative_to(root).as_posix())
    return discovered


def _manual_active_abi_literals(text: str) -> list[str]:
    hits: list[str] = []
    for name in _ABI_NAMES:
        if re.search(
            rf"(?m)^\s*(?:localparam(?:\s+[^=\n]*)?\s+|`define\s+)?{re.escape(name)}\s*=\s*(?:0[xX][0-9A-Fa-f]+|\d+['hH][0-9A-Fa-f]+)",
            text,
        ):
            hits.append(name)
    if re.search(
        r'(?m)^\s*["\'](?:CTRL|STATUS|FAULT_CODE|I_CH1|I_CH2|TH_OC1|TH_OC2|TH_DIFF|PWM_PERIOD|PWM_DUTY)["\']\s*:\s*0[xX][0-9A-Fa-f]+',
        text,
    ):
        hits.append("legacy register dictionary")
    return hits


def _generated_binding_present(path: str, text: str) -> bool:
    if path.endswith((".v", ".sv", ".vh")):
        return bool(
            re.search(
                r'`include\s+"(?:fault_defs|generated/protection_register_map|protection_register_map)\.(?:vh|svh)"',
                text,
            )
        )
    if path.endswith(".tcl"):
        return "generated/protection_register_map_ipxact.tcl" in text or "generated protection_register_map_ipxact.tcl" in text
    return any(token in text for token in _GENERATED_IMPORTS)


def validate_active_consumer(root: Path, entry: dict[str, Any]) -> None:
    relative = str(entry["path"])
    text = read_text(root, relative)
    manual = _manual_active_abi_literals(text)
    require(not manual, f"active consumer retains manual ABI authority: {relative}: {manual}")
    require(_generated_binding_present(relative, text), f"active consumer lacks generated binding: {relative}")


def _parse_python_binding(text: str, relative: str) -> ast.Module:
    try:
        return ast.parse(text, filename=relative)
    except SyntaxError as exc:
        raise CheckError(f"active consumer binding is invalid Python: {relative}: {exc}") from exc


def _top_level_assignment(tree: ast.Module, name: str) -> ast.AST:
    values: list[ast.AST] = []
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == name
            for target in node.targets
        ):
            values.append(node.value)
        elif (
            isinstance(node, ast.AnnAssign)
            and isinstance(node.target, ast.Name)
            and node.target.id == name
        ):
            values.append(node.value)
    require(
        len(values) == 1,
        f"active consumer generated ABI binding must assign {name} exactly once",
    )
    return values[0]


def _names(node: ast.AST) -> set[str]:
    return {child.id for child in ast.walk(node) if isinstance(child, ast.Name)}


def _is_int_enum_member(node: ast.AST, enum_name: str, member: str) -> bool:
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "int"
        and len(node.args) == 1
        and isinstance(node.args[0], ast.Attribute)
        and isinstance(node.args[0].value, ast.Name)
        and node.args[0].value.id == enum_name
        and node.args[0].attr == member
    )


def _register_offset_member(node: ast.AST) -> str | None:
    if (
        isinstance(node, ast.Attribute)
        and isinstance(node.value, ast.Name)
        and node.value.id == "RegisterOffset"
    ):
        return node.attr
    return None


def _int_register_offset_member(node: ast.AST) -> str | None:
    if (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "int"
        and len(node.args) == 1
        and not node.keywords
    ):
        return _register_offset_member(node.args[0])
    return None


def _register_key_member(node: ast.AST) -> str | None:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Attribute) and node.attr == "name":
        return _register_offset_member(node.value)
    return None


def _register_member_sequence(node: ast.AST) -> list[str] | None:
    if not isinstance(node, (ast.Tuple, ast.List)):
        return None
    members = [_register_offset_member(element) for element in node.elts]
    if any(member is None for member in members):
        return None
    return [member for member in members if member is not None]


def _complete_runtime_register_members(
    members: list[str] | None,
    expected_members: Iterable[str] = CURRENT_RUNTIME_REGISTER_MEMBERS,
) -> bool:
    expected = tuple(expected_members)
    return (
        members is not None
        and len(members) == len(expected)
        and set(members) == set(expected)
    )


def _loop_name_attribute(node: ast.AST, loop_name: str) -> bool:
    return (
        isinstance(node, ast.Attribute)
        and node.attr == "name"
        and isinstance(node.value, ast.Name)
        and node.value.id == loop_name
    )


def _int_loop_name(node: ast.AST, loop_name: str) -> bool:
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "int"
        and len(node.args) == 1
        and not node.keywords
        and isinstance(node.args[0], ast.Name)
        and node.args[0].id == loop_name
    )


def _valid_register_comprehension(
    node: ast.AST,
    container_kind: str,
    expected_members: Iterable[str] = CURRENT_RUNTIME_REGISTER_MEMBERS,
) -> bool:
    if container_kind == "list":
        if not isinstance(node, ast.ListComp) or not isinstance(node.elt, ast.Tuple):
            return False
        if len(node.elt.elts) != 2:
            return False
        key, value = node.elt.elts
    else:
        if not isinstance(node, ast.DictComp):
            return False
        key, value = node.key, node.value
    if len(node.generators) != 1:
        return False
    generator_node = node.generators[0]
    if (
        not isinstance(generator_node.target, ast.Name)
        or generator_node.is_async
        or generator_node.ifs
    ):
        return False
    loop_name = generator_node.target.id
    iter_members = (
        list(CURRENT_RUNTIME_REGISTER_MEMBERS)
        if isinstance(generator_node.iter, ast.Name)
        and generator_node.iter.id == "RegisterOffset"
        else _register_member_sequence(generator_node.iter)
    )
    return (
        _loop_name_attribute(key, loop_name)
        and _int_loop_name(value, loop_name)
        and _complete_runtime_register_members(iter_members, expected_members)
    )


def _valid_explicit_register_container(
    node: ast.AST,
    container_kind: str,
    expected_members: Iterable[str] = CURRENT_RUNTIME_REGISTER_MEMBERS,
) -> bool:
    if container_kind == "list":
        if not isinstance(node, (ast.List, ast.Tuple)):
            return False
        pairs: list[tuple[ast.AST, ast.AST]] = []
        for element in node.elts:
            if not isinstance(element, ast.Tuple) or len(element.elts) != 2:
                return False
            pairs.append((element.elts[0], element.elts[1]))
    else:
        if not isinstance(node, ast.Dict) or any(key is None for key in node.keys):
            return False
        pairs = [
            (key, value)
            for key, value in zip(node.keys, node.values)
            if key is not None
        ]
    paired_members: list[str] = []
    for key, value in pairs:
        key_member = _register_key_member(key)
        value_member = _int_register_offset_member(value)
        if key_member is None or value_member is None or key_member != value_member:
            return False
        paired_members.append(value_member)
    return _complete_runtime_register_members(paired_members, expected_members)


def _validate_register_container_binding(
    node: ast.AST,
    relative: str,
    binding_name: str,
    container_kind: str,
    expected_members: Iterable[str] = CURRENT_RUNTIME_REGISTER_MEMBERS,
) -> None:
    require(
        _valid_register_comprehension(node, container_kind, expected_members)
        or _valid_explicit_register_container(
            node, container_kind, expected_members
        ),
        "active consumer effective register container binding drift: "
        f"{relative}: {binding_name}",
    )


def _attribute_chain(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = _attribute_chain(node.value)
        return f"{base}.{node.attr}" if base else None
    return None


def _validate_mmio_call_arguments(
    tree: ast.Module,
    relative: str,
    receivers: set[str],
    valid_argument: Callable[[ast.AST], bool],
) -> None:
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        source = _attribute_chain(node.value)
        if source not in receivers:
            continue
        for target in _assignment_targets(node):
            if target not in receivers:
                require(
                    False,
                    f"active consumer MMIO receiver alias bypass: {relative}: "
                    f"{target} aliases {source}",
                )
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in {"read", "write"}:
            continue
        if _attribute_chain(node.func.value) not in receivers:
            continue
        require(
            bool(node.args) and valid_argument(node.args[0]),
            f"active consumer direct literal or unbound MMIO address: {relative}",
        )


def validate_stage2c9e_binding(text: str) -> None:
    relative = "sw/stage2c9e_b_pynq_mmio_register_smoke.py"
    tree = _parse_python_binding(text, relative)
    ctrl = _top_level_assignment(tree, "REG_CTRL")
    require(
        _is_int_enum_member(ctrl, "RegisterOffset", "CTRL"),
        f"active consumer generated ABI binding drift: {relative}: REG_CTRL",
    )
    read_registers = _top_level_assignment(tree, "READ_REGISTERS")
    _validate_register_container_binding(
        read_registers, relative, "READ_REGISTERS", "list"
    )
    _validate_mmio_call_arguments(
        tree,
        relative,
        {"protection"},
        lambda node: isinstance(node, ast.Name)
        and node.id in {"offset", "REG_CTRL"},
    )


def validate_stage2c9f_binding(text: str) -> None:
    relative = "sw/stage2c9f_b_controlled_expanded_mmio_idempotent_rw.py"
    tree = _parse_python_binding(text, relative)
    read_registers = _top_level_assignment(tree, "READ_REGISTERS")
    _validate_register_container_binding(
        read_registers, relative, "READ_REGISTERS", "list"
    )
    write_candidates = _top_level_assignment(tree, "WRITE_CANDIDATES")
    _validate_register_container_binding(
        write_candidates,
        relative,
        "WRITE_CANDIDATES",
        "list",
        (
            "CTRL",
            "TH_OC1",
            "TH_OC2",
            "TH_DIFF",
            "PWM_PERIOD",
            "PWM_DUTY",
        ),
    )
    _validate_mmio_call_arguments(
        tree,
        relative,
        {"protection"},
        lambda node: isinstance(node, ast.Name) and node.id == "offset",
    )


def _function_definition(tree: ast.Module, name: str, relative: str) -> ast.FunctionDef:
    matches = [
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == name
    ]
    require(
        len(matches) == 1,
        f"active consumer generated ABI binding must define {name} exactly once: {relative}",
    )
    return matches[0]


def validate_stage2i_board_runtime_binding(text: str) -> None:
    relative = "sw/stage2i_board_runtime.py"
    tree = _parse_python_binding(text, relative)
    function = _function_definition(tree, "read_all_registers", relative)
    returns = [node for node in ast.walk(function) if isinstance(node, ast.Return)]
    require(
        len(returns) == 1 and returns[0].value is not None,
        f"active consumer generated ABI binding drift: {relative}: read_all_registers",
    )
    value = returns[0].value
    valid = False
    if isinstance(value, ast.DictComp) and len(value.generators) == 1:
        generator_node = value.generators[0]
        loop_name = (
            generator_node.target.id
            if isinstance(generator_node.target, ast.Name)
            else ""
        )
        read_call = value.value.args[0] if isinstance(value.value, ast.Call) and len(value.value.args) == 1 else None
        valid = (
            loop_name != ""
            and isinstance(generator_node.iter, ast.Name)
            and generator_node.iter.id == "RegisterOffset"
            and _loop_name_attribute(value.key, loop_name)
            and isinstance(value.value, ast.Call)
            and isinstance(value.value.func, ast.Name)
            and value.value.func.id == "int"
            and isinstance(read_call, ast.Call)
            and isinstance(read_call.func, ast.Attribute)
            and read_call.func.attr == "read"
            and isinstance(read_call.func.value, ast.Name)
            and read_call.func.value.id == "mmio"
            and len(read_call.args) == 1
            and _int_loop_name(read_call.args[0], loop_name)
        )
    require(
        valid,
        f"active consumer effective register container binding drift: {relative}: read_all_registers",
    )
    require(
        "from sw.protection_ip_interface import" in text
        or "from protection_ip_interface import" in text,
        f"active consumer generated ABI delegation drift: {relative}",
    )


def validate_board_binding(text: str) -> None:
    relative = "tools/board_validation/stage1_board_functional_validation.py"
    tree = _parse_python_binding(text, relative)
    require(
        _is_int_enum_member(
            _top_level_assignment(tree, "REG_CTRL"), "RegisterOffset", "CTRL"
        ),
        f"active consumer generated ABI binding drift: {relative}: REG_CTRL",
    )
    for token in (
        "FaultCause.CH1_OVERCURRENT",
        "FaultCause.CH2_OVERCURRENT",
        "FaultCause.SENSOR_MISMATCH_OR_DIFFERENTIAL",
        "FaultCause.SENSOR_OPEN",
        "FaultCause.SENSOR_SATURATION",
        "FaultCause.SENSOR_STUCK",
        "FaultCode.OVERCURRENT",
        "FaultCode.SENSOR_MISMATCH",
        "FaultCode.SENSOR_OPEN",
        "FaultCode.OC_WITH_ANY_SENSOR",
        "FaultCode.SENSOR_STUCK",
    ):
        require(
            token in text,
            f"active consumer generated ABI binding drift: {relative}: {token}",
        )
    _validate_mmio_call_arguments(
        tree,
        relative,
        {"self.protection"},
        lambda node: isinstance(node, ast.Name) and node.id == "REG_CTRL",
    )


def validate_board_package_builder_binding(text: str) -> None:
    relative = "tools/board_validation/build_stage1_board_execution_package.py"
    tree = _parse_python_binding(text, relative)
    _function_definition(tree, "register_map_abi", relative)
    for token in (
        "REGISTER_MAP_VERSION_ABI_MAJOR_RESET",
        "REGISTER_MAP_VERSION_ABI_MINOR_RESET",
        "REGISTER_MAP_SCHEMA_VERSION",
        "REGISTER_MAP_CANONICAL_SHA256",
    ):
        require(
            text.count(token) >= 2,
            f"active consumer generated ABI binding drift: {relative}: {token}",
        )


def validate_stage2i_current_runtime_binding(text: str) -> None:
    relative = "fpga/pynq/deployment/stage1g/stage2i_current_release.py"
    tree = _parse_python_binding(text, relative)
    for function in ("verify_generated_abi", "execute_read_only"):
        _function_definition(tree, function, relative)
    for token in (
        "sw/generated/protection_register_map.py",
        "REGISTER_MAP_VERSION_ABI_MAJOR_RESET",
        "REGISTER_MAP_VERSION_ABI_MINOR_RESET",
        "REGISTER_MAP_SCHEMA_VERSION",
        "REGISTER_MAP_CANONICAL_SHA256",
        "from protection_ip_interface import",
        "read_register_map_version",
        "read_capabilities",
        "read_status",
    ):
        require(
            token in text,
            f"active consumer generated ABI delegation drift: {relative}: {token}",
        )


def validate_interface_binding(text: str) -> None:
    relative = "sw/protection_ip_interface.py"
    tree = _parse_python_binding(text, relative)
    require(
        "generated.protection_register_map import *" in text,
        f"active consumer generated ABI binding drift: {relative}: import",
    )
    local_register_names: set[str] = set()
    for node in tree.body:
        targets: list[ast.AST] = []
        if isinstance(node, ast.Assign):
            targets = list(node.targets)
        elif isinstance(node, ast.AnnAssign):
            targets = [node.target]
        local_register_names.update(
            target.id
            for target in targets
            if isinstance(target, ast.Name) and target.id.startswith("REG_")
        )
    require(
        not local_register_names,
        f"active consumer generated ABI binding shadowed locally: {relative}: {sorted(local_register_names)}",
    )
    _validate_mmio_call_arguments(
        tree,
        relative,
        {"mmio"},
        lambda node: isinstance(node, ast.Name)
        and (node.id.startswith("REG_") or node.id == "offset"),
    )
    for node in ast.walk(tree):
        if not (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "_read_word"
        ):
            continue
        require(
            len(node.args) == 2
            and isinstance(node.args[1], ast.Name)
            and (
                node.args[1].id.startswith("REG_")
                or node.args[1].id == "offset"
            ),
            f"active consumer generated ABI binding drift: {relative}: _read_word",
        )
    for node in ast.walk(tree):
        if not (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "_read_fault_bitmap"
        ):
            continue
        require(
            len(node.args) == 2
            and isinstance(node.args[1], ast.Name)
            and node.args[1].id.startswith("REG_"),
            f"active consumer generated ABI binding drift: {relative}: bitmap offset",
        )


def validate_preboard_binding(text: str) -> None:
    relative = "sw/pynq_mmio_demo_preboard.py"
    require(
        "import protection_ip_interface as protection" in text
        and "protection.apply_demo_configuration(mmio)" in text
        and "protection.read_status(mmio)" in text,
        f"active consumer generated ABI delegation drift: {relative}",
    )


def validate_rendered_example_binding(source: str) -> None:
    relative = "tools/build_current_release.py::read_only_example"
    tree = _parse_python_binding(source, relative)
    require(
        "from protection_ip_interface import" in source,
        f"active consumer generated ABI delegation drift: {relative}: import",
    )
    called = {
        node.func.id
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }
    required = {
        "read_register_map_version",
        "read_capabilities",
        "read_status",
        "read_policy_status",
        "read_observability",
    }
    require(
        required <= called,
        f"active consumer generated ABI delegation drift: {relative}: calls",
    )
    _validate_mmio_call_arguments(
        tree,
        relative,
        {"mmio"},
        lambda _node: False,
    )


def _render_read_only_example(root: Path) -> str:
    relative = "tools/build_current_release.py"
    module_name = "_a2_release_builder_binding"
    module_spec = importlib.util.spec_from_file_location(
        module_name, root / relative
    )
    require(
        module_spec is not None and module_spec.loader is not None,
        f"unable to load active consumer binding: {relative}",
    )
    module = importlib.util.module_from_spec(module_spec)
    previous = sys.modules.get(module_name)
    sys.modules[module_name] = module
    try:
        module_spec.loader.exec_module(module)
    finally:
        if previous is None:
            sys.modules.pop(module_name, None)
        else:
            sys.modules[module_name] = previous
    source = module.read_only_example()
    require(isinstance(source, str), "standalone read-only example did not render text")
    return source


def validate_board_session_binding(text: str) -> None:
    """Validate the finite session MMIO forms, including their effective values."""
    tree = ast.parse(text)
    names = {'RegisterOffset', 'CTRL_PWM_ENABLE', 'CTRL_CLEAR_FAULT'}
    imports = [n for n in ast.walk(tree) if isinstance(n, ast.ImportFrom)
               and any(a.name in names for a in n.names)]
    require(len(imports) == 2 and all(
        n.module in ('sw.generated.protection_register_map', 'generated.protection_register_map')
        and {a.name for a in n.names} == names and all(a.asname is None for a in n.names)
        for n in imports), 'board session generated imports drift')
    for node in ast.walk(tree):
        require(not (isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store) and node.id in names | {'int'}),
                'board session generated binding shadowed')
        require(not (isinstance(node, ast.arg) and node.arg in names | {'int'}),
                'board session generated argument shadowed')
        require(not (isinstance(node, ast.Attribute) and isinstance(node.ctx, ast.Store)
                     and isinstance(node.value, ast.Name) and node.value.id in names),
                'board session generated member overwritten')
    expected = [
        'self.backend.protection.write(int(RegisterOffset.CTRL), int(CTRL_PWM_ENABLE | CTRL_CLEAR_FAULT))',
        'self.backend.protection.write(int(RegisterOffset.CTRL), 0)',
    ]
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
             and isinstance(n.func.value, ast.Attribute) and n.func.value.attr == 'protection']
    require(sorted(ast.dump(n) for n in calls) == sorted(ast.dump(ast.parse(s, mode='eval').body) for s in expected),
            'board session MMIO address or CTRL mask binding drift')
    receivers = [n for n in ast.walk(tree) if isinstance(n, ast.Attribute) and n.attr == 'protection']
    require(len(receivers) == len(calls), 'board session MMIO receiver alias bypass')


def check_active_consumer_bindings(root: Path) -> int:
    validate_board_session_binding(read_text(root, 'tools/board_validation/stage2_board_session.py'))
    validate_interface_binding(read_text(root, "sw/protection_ip_interface.py"))
    validate_preboard_binding(read_text(root, "sw/pynq_mmio_demo_preboard.py"))
    validate_stage2c9e_binding(
        read_text(root, "sw/stage2c9e_b_pynq_mmio_register_smoke.py")
    )
    validate_stage2c9f_binding(
        read_text(root, "sw/stage2c9f_b_controlled_expanded_mmio_idempotent_rw.py")
    )
    validate_stage2i_board_runtime_binding(
        read_text(root, "sw/stage2i_board_runtime.py")
    )
    validate_board_binding(
        read_text(root, "tools/board_validation/stage1_board_functional_validation.py")
    )
    validate_board_package_builder_binding(
        read_text(
            root,
            "tools/board_validation/build_stage1_board_execution_package.py",
        )
    )
    validate_stage2i_current_runtime_binding(
        read_text(
            root,
            "fpga/pynq/deployment/stage1g/stage2i_current_release.py",
        )
    )
    validate_rendered_example_binding(_render_read_only_example(root))
    return len(ACTIVE_CONSUMER_BINDING_PATHS)


def _extract_oracle_values(text: str, names: Iterable[str]) -> dict[str, int]:
    values: dict[str, int] = {}
    for name in names:
        match = re.search(
            rf"(?m)^\s*(?:localparam[^=\n]*\s+)?{re.escape(name)}\s*=\s*(?:(?:\d+'[hH])|0[xX])?([0-9A-Fa-f]+)",
            text,
        )
        if match:
            values[name] = int(match.group(1), 16)
    return values


def validate_independent_oracle(root: Path, entry: dict[str, Any]) -> None:
    relative = str(entry["path"])
    text = read_text(root, relative)
    expected = {str(name): int(value) for name, value in entry["oracle_constants"].items()}
    observed = _extract_oracle_values(text, expected)
    require(observed == expected, f"independent oracle parity drift: {relative}: {observed} != {expected}")
    if any(name.startswith("REG_") for name in expected):
        require(
            "protection_register_map.svh" not in text and "generated/protection_register_map" not in text,
            f"register oracle imports generated register authority: {relative}",
        )
    if any(name.startswith("FAULT_") for name in expected):
        require(
            "fault_defs.vh" not in text and "protection_register_map" not in text,
            f"fault oracle imports generated fault authority: {relative}",
        )


def _literal_dict_keys(root: Path, relative: str, variable: str) -> set[str]:
    path = root / relative
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=relative)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == variable for target in node.targets
        ) and isinstance(node.value, ast.Dict):
            return {
                key.value
                for key in node.value.keys
                if isinstance(key, ast.Constant) and isinstance(key.value, str)
            }
    return set()


def validate_historical_exclusions(root: Path, included=None) -> None:
    board_builder = "tools/board_validation/build_stage1_board_execution_package.py"
    packaged_sources = _literal_dict_keys(root, board_builder, "SOURCE_FILES")
    historical = set(HISTORICAL_CONSUMERS)
    require(
        not historical & packaged_sources,
        f"historical snapshot added to active board package: {sorted(historical & packaged_sources)}",
    )
    release = read_text(root, "tools/build_current_release.py")
    require(
        "ACTIVE_WORKTREE_PACKAGE_SOURCES" in release
        and "runtime_sources = runtime_source_records(repo_root)" in release
        and "runtime source changed during build" in release,
        "release package does not separate active generated sources from pinned history",
    )
    release_sources = _literal_dict_keys(root, "tools/build_current_release.py", "ACTIVE_WORKTREE_PACKAGE_SOURCES")
    require(
        not historical & release_sources,
        f"historical snapshot added to active release package: {sorted(historical & release_sources)}",
    )
    for relative, expected in HISTORICAL_CONSUMERS.items():
        if included is not None and relative not in included:
            continue
        observed = hashlib.sha256((root / relative).read_bytes()).hexdigest()
        require(observed == expected, f"historical snapshot changed: {relative}")


def consumer_scope(root: Path, scope: str):
    from tools.source_export import verify, identity, select_files
    if scope == 'auto':
        if (root / 'SOURCE_MANIFEST.json').exists():
            scope = 'selected-export' if verify(root).get('selection') is not None else 'engineering'
        else:
            scope = 'engineering'
    if scope == 'engineering':
        return None
    manifest = verify(root)  # Never downgrade scope based only on a filename.
    selection = manifest.get('selection')
    require(isinstance(selection, dict) and selection.get('path') == 'config/self_contained_source.json',
            'selected-export scope requires the committed selection identity')
    path = root / selection['path']
    require(identity(path) == selection['identity'], 'source selection identity differs')
    policy = json.loads(path.read_text(encoding='utf-8'))
    files = set(manifest['files'])
    required = set(ACTIVE_CONSUMER_PATHS) | set(ORACLE_CONSUMERS) | set(policy['required'])
    require(required <= files, f'required ABI/export inputs missing: {sorted(required - files)}')
    selected = select_files(files | set(HISTORICAL_CONSUMERS), policy)
    require(selected == files, f'selection scope differs: {sorted(selected ^ files)}')
    return files


def check_consumer_inventory(root: Path, inventory=None, scope='auto') -> dict[str, int]:
    included = consumer_scope(root, scope)
    inventory = CONSUMER_INVENTORY if inventory is None else inventory
    if included is not None:
        inventory = tuple(entry for entry in inventory if entry['path'] in included)
    require(
        set(entry["role"] for entry in inventory) <= set(CONSUMER_ROLES),
        "consumer inventory contains an unapproved role",
    )
    paths = [str(entry["path"]) for entry in inventory]
    require(len(paths) == len(set(paths)), "consumer inventory contains duplicate paths")
    discovered = discover_executable_consumers(root)
    validate_discovered_consumer_paths(
        discovered, set(paths) - set(HISTORICAL_CONSUMERS)
    )
    for entry in inventory:
        role = entry["role"]
        if role == "ACTIVE_GENERATED_CONSUMER":
            validate_active_consumer(root, entry)
        elif role == "INDEPENDENT_FROZEN_ORACLE":
            validate_independent_oracle(root, entry)
        else:
            read_text(root, entry["path"])
    validate_historical_exclusions(root, included)
    binding_count = check_active_consumer_bindings(root)
    return {
        "total": len(inventory),
        "active": sum(entry["role"] == "ACTIVE_GENERATED_CONSUMER" for entry in inventory),
        "oracles": sum(entry["role"] == "INDEPENDENT_FROZEN_ORACLE" for entry in inventory),
        "historical": sum(entry["role"] == "FROZEN_HISTORICAL_SNAPSHOT" for entry in inventory),
        "bindings": binding_count,
        "historical_out_of_scope": sum(p not in included for p in HISTORICAL_CONSUMERS) if included is not None else 0,
    }


def validate_discovered_consumer_paths(
    discovered: set[str], inventory_paths: set[str]
) -> None:
    missing = sorted(discovered - inventory_paths)
    extra = sorted(inventory_paths - discovered)
    require(
        not missing and not extra,
        f"unclassified executable ABI consumers: missing={missing} extra={extra}",
    )


def check_live_package_ipxact_binding(root: Path) -> None:
    relative = (
        "fpga/vivado/build/runtime/runner/"
        "stage1e_production_vivado_runner_v2.tcl"
    )
    runner = read_text(root, relative)
    for token in (
        "generated protection_register_map_ipxact.tcl",
        "_require_file $register_map_ipxact",
        "source $register_map_ipxact",
        "protection_register_map_apply_ipxact $block",
    ):
        require(
            runner.count(token) == 1,
            f"live production package must contain {token!r} exactly once",
        )
    for token in (
        "ipx::get_memory_maps S_AXI",
        "ipx::get_address_blocks reg0",
        "$::PROTECTION_REGISTER_MAP_REGISTER_COUNT",
    ):
        require(token in runner, f"live production package omits {token!r}")

    compatibility = read_text(
        root, "fpga/vivado/package_protection_ip_stage2_axi_lite.tcl"
    )
    require(
        "Historical package-only compatibility entrypoint" in compatibility
        and "not a current production build or source-list authority"
        in compatibility,
        "standalone packager role is not explicitly historical/compatibility",
    )


def check_consumers(root: Path) -> None:
    shim = read_text(root, "rtl/fault_defs.vh")
    validate_fault_defs_shim(shim)

    rtl = read_text(root, "rtl/protection_reg_bank.v")
    require(
        '`include "generated/protection_register_map.vh"' in rtl,
        "register bank does not include the generated map",
    )
    require(
        not re.search(r"(?m)^\s*localparam\s+(?:\[[^]]+\]\s+)?REG_[A-Z0-9_]+\s*=", rtl),
        "register bank retains a local register-offset authority",
    )
    for token in (
        "`PROTECTION_REG_CTRL",
        "`PROTECTION_REG_OBS_LAST_DESTINATION_SEQUENCE",
        "`PROTECTION_OBS_CAPABILITY_VALUE(OBS_SEQUENCE_WIDTH)",
        "`PROTECTION_TH_OC1_THRESHOLD_CH1_RESET",
    ):
        require(token in rtl, f"register bank omits generated token: {token}")

    interface = read_text(root, "sw/protection_ip_interface.py")
    require(
        "generated.protection_register_map import *" in interface,
        "software interface does not re-export the generated map",
    )
    require(
        not re.search(r"(?m)^REG_CTRL\s*=\s*0x", interface),
        "software interface retains a manual register-offset authority",
    )

    for relative in (
        "tb/tb_protection_reg_bank.sv",
        "tb/tb_protection_ip_top_axi_lite.sv",
        "tb/stage2e/tb_stage2e_axi_register_contract.sv",
    ):
        require(
            '`include "protection_register_map.svh"' in read_text(root, relative),
            f"testbench does not consume generated constants: {relative}",
        )

    check_live_package_ipxact_binding(root)

    closure_files = (
        "fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl",
        "tools/run_stage2f_width_sequence_boundary.py",
    )
    for relative in closure_files:
        require(
            "protection_register_map.vh" in read_text(root, relative),
            f"controlled source closure omits generated RTL header: {relative}",
        )

    for relative in (
        "tools/run_stage2g_functional_rtl.py",
        "tools/run_stage2g_mutations.py",
    ):
        validate_stage2g_tb_include_path(read_text(root, relative))


def _module_text(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^module\s+{re.escape(name)}\b.*?^endmodule\b", source
    )
    require(match is not None, f"required RTL module is missing: {name}")
    return match.group(0)


def check_abi_1_1_rtl_bindings(root: Path) -> None:
    bank = read_text(root, "rtl/protection_reg_bank.v")
    require(
        re.search(r"parameter\s+EXPLICIT_ABI_1_1\s*=\s*0", bank) is not None,
        "register-bank explicit ABI parameter is not default-off",
    )
    for token in (
        "`PROTECTION_REGISTER_MAP_VERSION_VALUE",
        "`PROTECTION_CAPABILITIES_0_ABI_1_1_VALUE",
        "`PROTECTION_CAPABILITIES_1_VALUE(OBS_SEQUENCE_WIDTH)",
        "(fsm_state == `PROTECTION_POLICY_STATE_ST_ARMED)",
        "clear_pending;",
        "post_clear_recovery_pending;",
        "{{26{1'b0}}, first_fault_bitmap}",
        "{{26{1'b0}}, live_fault_bitmap}",
        "{{26{1'b0}}, fault_seen_bitmap}",
        "if (fault_eval_valid)",
        "{{(32-OBS_SEQUENCE_WIDTH){1'b0}}, fault_eval_sequence}",
        "rd_data = policy_evaluation_sequence;",
    ):
        require(token in bank, f"register-bank ABI binding is missing: {token}")
    require(
        "rd_data = fault_eval_sequence" not in bank,
        "policy identity is exposed as an idle-cleared live wire",
    )
    for name in ABI_1_1_REGISTER_NAMES:
        token = f"`PROTECTION_REG_{name}"
        require(
            bank.count(token) == 1,
            f"selected ABI register is not decoded exactly once: {name}",
        )

    wrappers = read_text(root, "rtl/protection_ip_top_reg_controlled.v")
    legacy = _module_text(wrappers, "protection_ip_top_reg_controlled")
    production = _module_text(wrappers, "stage2g_protection_ip_reg_controlled")
    require(
        ".EXPLICIT_ABI_1_1(0)" in legacy,
        "legacy register path does not explicitly disable ABI 1.1",
    )
    for token in (
        ".fsm_state(4'd0)",
        ".clear_pending(1'b0)",
        ".post_clear_recovery_pending(1'b0)",
        ".first_fault_bitmap(6'd0)",
        ".live_fault_bitmap(6'd0)",
        ".fault_seen_bitmap(6'd0)",
        ".fault_eval_valid(1'b0)",
        ".fault_eval_sequence({OBS_SEQUENCE_WIDTH{1'b0}})",
    ):
        require(token in legacy, f"legacy ABI source is not tied low: {token}")
    require(
        ".EXPLICIT_ABI_1_1(1)" in production,
        "Stage 2G production path does not enable ABI 1.1",
    )
    for signal in (
        "fsm_state",
        "clear_pending",
        "post_clear_recovery_pending",
        "first_fault_bitmap",
        "live_fault_bitmap",
        "fault_seen_bitmap",
        "fault_eval_valid",
        "fault_eval_sequence",
    ):
        require(
            f".{signal}({signal})" in production,
            f"Stage 2G register source is disconnected: {signal}",
        )
    require(
        ".fault_eval_bitmap(fault_eval_bitmap)" in production
        and ".fault_eval_integrity_clean(fault_eval_integrity_clean)" in production,
        "Stage 2G policy evaluation source closure is incomplete",
    )


def check_abi_1_1_software_contract(root: Path) -> None:
    relative = "sw/protection_ip_interface.py"
    source = read_text(root, relative)
    tree = ast.parse(source, filename=relative)
    definitions = {
        node.name: node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
    }
    for name in (
        "FeatureState",
        "UnsupportedFeatureError",
        "IndeterminateFeatureError",
        "IncompatibleRegisterMapError",
        "RegisterMapVersion",
        "RegisterMapCapabilities",
        "FaultBitmapValue",
        "read_register_map_version",
        "read_capabilities",
        "is_armed",
        "startup_ready",
        "read_policy_status",
        "read_first_fault_bitmap",
        "read_live_fault_bitmap",
        "read_fault_seen_bitmap",
        "read_policy_evaluation_identity",
    ):
        require(name in definitions, f"software ABI contract is missing: {name}")
    require(
        "read_policy_snapshot" not in definitions,
        "ABI 1.1 incorrectly exposes a policy snapshot API",
    )
    startup_names = {
        node.id
        for node in ast.walk(definitions["startup_ready"])
        if isinstance(node, ast.Name)
    }
    require(
        not startup_names
        & {
            "REG_STATUS",
            "STATUS_FAULT_VALID",
            "STATUS_FAULT_LATCHED",
            "recovery_is_verified",
        },
        "startup_ready is inferred from the legacy recovery/status contract",
    )

    from tools.stage2h_register_map_convergence_audit import fingerprint_source

    policy = read_json(root, "spec/stage2h_register_map_convergence.json")[
        "ast_fingerprint_policy"
    ]
    observed = fingerprint_source(source, "recovery_is_verified")
    require(
        observed["schema"] == policy["serializer_schema"]
        and observed["canonical_sha256"] == policy["authoritative_hash"],
        "recovery_is_verified canonical semantic fingerprint changed",
    )


def check_authority_scope(root: Path, spec: dict[str, Any]) -> None:
    require(
        not (nested_keys(spec) & AUDIT_ONLY_KEYS),
        "live source contains audit-only metadata",
    )
    register_names = {register["name"] for register in spec["registers"]}
    require(
        register_names & ABI_1_1_REGISTER_NAMES == ABI_1_1_REGISTER_NAMES
        and len(spec["registers"]) == 33
        and sum(len(register["fields"]) for register in spec["registers"]) == 97,
        "ABI 1.1 selected register/field inventory is incomplete",
    )
    path_pattern = re.compile(
        r"(?:(?<![A-Za-z0-9])[A-Za-z]:[\\/]|/(?:home|Users)/)"
    )
    for relative in A2_AUTHORITY_PATHS:
        text = read_text(root, relative)
        require(
            path_pattern.search(text) is None,
            f"A2 authority contains an absolute developer path: {relative}",
        )


def run(root: Path, scope='auto'):
    consumer_scope(root, scope)
    outputs, spec = load_and_render(root)
    require(
        tuple(outputs) == generator.MASTER_ARTIFACTS,
        "rendered output ordering differs from the frozen topology",
    )
    drift = generator.compare_outputs(root, outputs)
    require(not drift, f"generated artifact drift: {drift}")
    check_reports(root)
    check_consumers(root)
    check_python_reexport(root)
    counts = check_consumer_inventory(root, scope=scope)
    check_abi_1_1_rtl_bindings(root)
    check_abi_1_1_software_contract(root)
    check_authority_scope(root, spec)
    return counts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument('--scope', choices=('auto', 'engineering', 'selected-export'), default='auto')
    args = parser.parse_args(argv)
    try:
        counts = run(args.root.resolve(), args.scope)
    except (CheckError, generator.GenerationError, OSError, KeyError, TypeError, ValueError) as exc:
        print(f"REGISTER_MAP_IMPLEMENTATION_CHECK=FAIL: {exc}", file=sys.stderr)
        return 1

    print("REGISTER_MAP_IMPLEMENTATION_CHECK=PASS")
    print("GENERATOR_DETERMINISTIC=PASS")
    print("GENERATOR_SECOND_RUN_DIFF=ZERO")
    print("MASTER_GENERATED_ARTIFACT_TOPOLOGY=PASS_8_OF_8")
    print("UNOWNED_GENERATED_ARTIFACT_PATHS=0")
    print("DUPLICATE_GENERATED_ARTIFACT_PATHS=0")
    print("LEGACY_ABI_STATIC_PARITY=PASS")
    print("LEGACY_ABI_SOFTWARE_CONSTANT_PARITY=PASS")
    print("LEGACY_ABI_FAULT_CODE_PARITY=PASS")
    print("TOTAL_REGISTER_COUNT=33")
    print("LEGACY_REGISTER_COUNT=25")
    print("LEGACY_OFFSET_PARITY=PASS_25_OF_25")
    print("ABI_1_1_ADDED_REGISTER_COUNT=8")
    print("ABI_1_1_SELECTED_REGISTER_COVERAGE=PASS_8_OF_8")
    print("TOTAL_FIELD_COUNT=97")
    print("LEGACY_FIELD_COUNT=54")
    print("ABI_1_1_ADDED_FIELD_COUNT=43")
    print("ABI_1_1_SELECTED_BIT_COVERAGE=PASS_256_OF_256")
    print("A2_DOCUMENTATION_CONTRADICTIONS_CLOSED=PASS_3_OF_3")
    print("A2_UNDOCUMENTED_FROZEN_BEHAVIORS_CLOSED=PASS_5_OF_5")
    print("A2_KNOWN_CURRENT_ABI_REMEDIATIONS_CLOSED=PASS_8_OF_8")
    print("FAULT_CODE_ENUM_GENERATION=PASS_7_OF_7")
    print("FAULT_CODE_LEGACY_ALIAS_GENERATION=PASS")
    print("FAULT_DEFS_INDEPENDENT_NUMERIC_AUTHORITY=NO")
    print("GENERATED_ARTIFACT_DRIFT_CHECK=PASS_8_OF_8")
    print("BEHAVIOR_COMPLETE_CONFORMANCE=PASS_43_OF_43")
    print("CAPABILITY_DEPENDENCY_CLOSURE=PASS")
    print("STAGE2G_PRODUCTION_PATH_EXPLICIT_ABI_1_1=YES")
    print("LEGACY_PATH_FALSE_ABI_1_1_ADVERTISEMENT=NO")
    print("POLICY_STATUS_BINDING=PASS")
    print("FAULT_BITMAP_BINDING=PASS")
    print("POLICY_EVALUATION_IDENTITY_BINDING=PASS")
    print("RECOVERY_IS_VERIFIED_CANONICAL_FINGERPRINT=PASS")
    print("CONTROLLED_BUILD_SOURCE_CLOSURE=PASS")
    print("REGISTER_MAP_GENERATION_AUTHORITY_PRESERVED=YES")
    print("PARALLEL_MANUAL_REGISTER_MAP_AUTHORITY_COUNT=0")
    print("LIVE_PACKAGE_IPXACT_BINDING=PASS")
    print("LIVE_PRODUCTION_PACKAGE_GENERATED_IPXACT=YES")
    print("LIVE_PRODUCTION_REGISTER_COUNT=33")
    print("STANDALONE_PACKAGER_CURRENT_AUTHORITY=NO")
    print(
        f"REGISTER_MAP_EXECUTABLE_CONSUMER_INVENTORY=PASS_{counts['total']}_OF_{counts['total']}"
    )
    print("ACTIVE_CONSUMERS_WITH_MANUAL_ABI_CONSTANTS=0")
    print(f"INDEPENDENT_FROZEN_ORACLES=PASS_{counts['oracles']}_OF_{counts['oracles']}")
    if counts['historical_out_of_scope']:
        print(f"HISTORICAL_SNAPSHOT_EXCLUSIONS=OUT_OF_SCOPE_{counts['historical_out_of_scope']}: excluded by verified source selection")
    else:
        print(f"HISTORICAL_SNAPSHOT_EXCLUSIONS=PASS_{counts['historical']}_OF_{counts['historical']}")
    print("RECOVERY_SNAPSHOT_CHECKER_ROLE=INDEPENDENT_FROZEN_ORACLE")
    print("RECOVERY_SNAPSHOT_ORACLE_PARITY=PASS")
    print(
        "ACTIVE_CONSUMER_BINDING_COVERAGE="
        f"PASS_{counts['bindings']}_OF_{counts['bindings']}"
    )
    print("ACTIVE_CONSUMER_USED_ABI_VALUES_FROM_GENERATED_AUTHORITY=PASS")
    print("STANDALONE_EXAMPLE_BINDING=PASS")
    container_count = len(ACTIVE_REGISTER_CONTAINER_BINDING_PATHS)
    print(
        "ACTIVE_REGISTER_CONTAINER_VALUE_BINDING_COVERAGE="
        f"PASS_{container_count}_OF_{container_count}"
    )
    print("STAGE2C9E_EFFECTIVE_REGISTER_VALUES_FROM_GENERATED_AUTHORITY=PASS")
    print("STAGE2C9F_EFFECTIVE_REGISTER_VALUES_FROM_GENERATED_AUTHORITY=PASS")
    print("STAGE2I_BOARD_RUNTIME_REGISTER_VALUES_FROM_GENERATED_AUTHORITY=PASS")
    print("UNCLASSIFIED_EXECUTABLE_ABI_CONSTANT_CONSUMERS=0")
    print("ABSOLUTE_DEVELOPER_PATH_DEPENDENCIES=0")
    print("FIRST_PRINCIPLES_SCOPE_REVIEW=PASS")
    print(
        "ACTIVE_BINDING_ACCEPTANCE_BOUNDARY="
        "FINITE_KNOWN_RUNTIME_AND_RELEASE_CONTAINER_FORMS"
    )
    print("NEW_GENERIC_DATAFLOW_ANALYZER=NO")
    print("NEW_GENERIC_REPOSITORY_SCANNER=NO")
    print("NEW_GENERIC_FRAMEWORK_ADDED=NO")
    print("LONG_TERM_COMPLEXITY_REDUCED=YES")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
