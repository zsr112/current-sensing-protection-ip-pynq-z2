#!/usr/bin/env python3
"""Validate and optionally load the Stage2I SAFE_INERT current release."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Iterable


AUTHORITY_NAME = "release_authority.json"
AUTHORITY_SCHEMA = "stage2i-current-release-authority-v1"
PROFILE = "SAFE_INERT"
PROTECTION_IP = "protection_ip_axi_lite_0"
EXPECTED_IP = {
    "axi_gpio_stage1d_0": {"phys_addr": 0x41200000, "addr_range": 0x10000},
    PROTECTION_IP: {"phys_addr": 0x43C00000, "addr_range": 0x1000},
}
ARTIFACT_CONTRACT = {
    "bit": ("BITSTREAM", "protection_system.bit", "DEPLOY_REQUIRED"),
    "hwh": ("HWH", "protection_system.hwh", "DEPLOY_REQUIRED"),
    "ltx": ("LTX", None, "PROVENANCE_ONLY_REQUIRED"),
    "xsa": ("XSA", None, "PROVENANCE_ONLY_REQUIRED"),
}
RUNTIME_SOURCE_CONTRACT = {
    "pynq/runtime/stage2i_current_release.py": (
        "fpga/pynq/deployment/stage1g/stage2i_current_release.py"
    ),
    "pynq/runtime/protection_ip_interface.py": "sw/protection_ip_interface.py",
    "pynq/runtime/generated/protection_register_map.py": (
        "sw/generated/protection_register_map.py"
    ),
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9._:+-]{1,160}$")


class CurrentRuntimeError(RuntimeError):
    """The current release cannot be used without weakening a runtime check."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _reject_duplicate_keys(pairs: Iterable[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise CurrentRuntimeError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _load_json(path: Path) -> Any:
    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=lambda value: (_ for _ in ()).throw(
                CurrentRuntimeError(f"non-finite JSON value: {value}")
            ),
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise CurrentRuntimeError(f"invalid release authority: {exc}") from exc


def _require_exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise CurrentRuntimeError(f"{label} fields differ")
    return value


def _require_sha256(value: Any, label: str) -> str:
    text = str(value)
    if not SHA256_RE.fullmatch(text):
        raise CurrentRuntimeError(f"{label} is not a lowercase SHA-256")
    return text


def _require_commit(value: Any, label: str) -> str:
    text = str(value)
    if not COMMIT_RE.fullmatch(text):
        raise CurrentRuntimeError(f"{label} is not a Git object ID")
    return text


def _require_token(value: Any, label: str) -> str:
    text = str(value)
    if not TOKEN_RE.fullmatch(text):
        raise CurrentRuntimeError(f"{label} is not a canonical token")
    return text


def _require_positive_size(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise CurrentRuntimeError(f"{label} must be a positive integer")
    return value


def load_authority(release_root: Path) -> dict[str, Any]:
    authority = _require_exact_keys(
        _load_json(release_root / "pynq" / "artifacts" / AUTHORITY_NAME),
        {
            "schema_version",
            "implementation_profile",
            "engineering_main_commit",
            "engineering_main_tree",
            "physical_artifact_source_commit",
            "physical_artifact_source_tree",
            "physical_artifact_execution_id",
            "physical_artifact_request_identity",
            "physical_authority_receipt_sha256",
            "artifact_manifest",
            "artifacts",
            "expected_ip",
            "register_map_abi",
            "runtime_sources",
            "persistent_deployment_claim",
            "tree_equivalence",
        },
        "release authority",
    )
    if authority["schema_version"] != AUTHORITY_SCHEMA:
        raise CurrentRuntimeError("release authority schema mismatch")
    if authority["implementation_profile"] != PROFILE:
        raise CurrentRuntimeError("current release is not SAFE_INERT")
    if authority["persistent_deployment_claim"] != "NOT_CLAIMED":
        raise CurrentRuntimeError("persistent deployment is not closed as NOT_CLAIMED")
    if authority["tree_equivalence"] != "PASS":
        raise CurrentRuntimeError("physical and final-main tree equivalence is not PASS")

    _require_commit(authority["engineering_main_commit"], "engineering main commit")
    main_tree = _require_commit(authority["engineering_main_tree"], "engineering main tree")
    _require_commit(
        authority["physical_artifact_source_commit"], "physical source commit"
    )
    physical_tree = _require_commit(
        authority["physical_artifact_source_tree"], "physical source tree"
    )
    if main_tree != physical_tree:
        raise CurrentRuntimeError("physical source tree differs from engineering main tree")
    if not TOKEN_RE.fullmatch(str(authority["physical_artifact_execution_id"])):
        raise CurrentRuntimeError("physical execution ID is not canonical")
    _require_sha256(
        authority["physical_artifact_request_identity"], "physical request identity"
    )
    _require_sha256(
        authority["physical_authority_receipt_sha256"], "physical receipt identity"
    )

    manifest = _require_exact_keys(
        authority["artifact_manifest"],
        {"bytes", "sha256", "project_identity", "design_identity"},
        "artifact manifest",
    )
    _require_positive_size(manifest["bytes"], "artifact manifest bytes")
    _require_sha256(manifest["sha256"], "artifact manifest sha256")
    _require_token(manifest["project_identity"], "artifact manifest project_identity")
    _require_token(manifest["design_identity"], "artifact manifest design_identity")

    artifacts = _require_exact_keys(
        authority["artifacts"], set(ARTIFACT_CONTRACT), "artifact authority"
    )
    for key, (role, _filename, policy) in ARTIFACT_CONTRACT.items():
        record = _require_exact_keys(
            artifacts[key],
            {"role", "bytes", "sha256", "delivery_policy"},
            f"artifact {key}",
        )
        if record["role"] != role or record["delivery_policy"] != policy:
            raise CurrentRuntimeError(f"artifact policy mismatch: {key}")
        _require_positive_size(record["bytes"], f"artifact {key} bytes")
        _require_sha256(record["sha256"], f"artifact {key} identity")

    if authority["expected_ip"] != EXPECTED_IP:
        raise CurrentRuntimeError("release expected IP/address map differs")
    abi = _require_exact_keys(
        authority["register_map_abi"],
        {"major", "minor", "schema_version", "canonical_sha256"},
        "register-map ABI",
    )
    if abi["major"] != 1 or abi["minor"] != 1 or abi["schema_version"] != "1.1.0":
        raise CurrentRuntimeError("release authority is not bound to ABI 1.1")
    _require_sha256(abi["canonical_sha256"], "register-map canonical identity")

    runtime_sources = _require_exact_keys(
        authority["runtime_sources"],
        set(RUNTIME_SOURCE_CONTRACT),
        "runtime source inventory",
    )
    for release_path, source_path in RUNTIME_SOURCE_CONTRACT.items():
        record = _require_exact_keys(
            runtime_sources[release_path],
            {"source_relative_path", "bytes", "sha256"},
            f"runtime source {release_path}",
        )
        if record["source_relative_path"] != source_path:
            raise CurrentRuntimeError(f"runtime source path mismatch: {release_path}")
        _require_positive_size(record["bytes"], f"runtime source bytes: {release_path}")
        _require_sha256(record["sha256"], f"runtime source identity: {release_path}")
    return authority


def verify_artifacts(release_root: Path, authority: dict[str, Any]) -> dict[str, Any]:
    artifacts_root = release_root / "pynq" / "artifacts"
    observed: dict[str, Any] = {}
    for key, (_role, filename, _policy) in ARTIFACT_CONTRACT.items():
        record = authority["artifacts"][key]
        if filename is None:
            observed[key] = {"packaged": False, **record}
            continue
        path = artifacts_root / filename
        if not path.is_file():
            raise CurrentRuntimeError(f"release artifact is missing: {filename}")
        size = path.stat().st_size
        digest = sha256_file(path)
        if size != record["bytes"] or digest != record["sha256"]:
            raise CurrentRuntimeError(f"release artifact identity mismatch: {key}")
        observed[key] = {"packaged": True, "path": str(path), **record}
    return observed


def verify_runtime_sources(release_root: Path, authority: dict[str, Any]) -> dict[str, Any]:
    observed: dict[str, Any] = {}
    for relative, record in authority["runtime_sources"].items():
        path = release_root / Path(relative)
        if not path.is_file():
            raise CurrentRuntimeError(f"runtime source is missing: {relative}")
        size = path.stat().st_size
        digest = sha256_file(path)
        if size != record["bytes"] or digest != record["sha256"]:
            raise CurrentRuntimeError(f"runtime source identity mismatch: {relative}")
        observed[relative] = {"bytes": size, "sha256": digest}
    return observed


def _literal_assignments(path: Path) -> dict[str, Any]:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (OSError, UnicodeError, SyntaxError) as exc:
        raise CurrentRuntimeError(f"cannot parse generated register map: {exc}") from exc
    result: dict[str, Any] = {}
    for node in tree.body:
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        try:
            value = ast.literal_eval(node.value)
        except (ValueError, TypeError):
            continue
        for target in targets:
            if isinstance(target, ast.Name):
                result[target.id] = value
    return result


def verify_generated_abi(release_root: Path, authority: dict[str, Any]) -> dict[str, Any]:
    path = release_root / "pynq" / "runtime" / "generated" / "protection_register_map.py"
    values = _literal_assignments(path)
    observed = {
        "major": values.get("REGISTER_MAP_VERSION_ABI_MAJOR_RESET"),
        "minor": values.get("REGISTER_MAP_VERSION_ABI_MINOR_RESET"),
        "schema_version": values.get("REGISTER_MAP_SCHEMA_VERSION"),
        "canonical_sha256": values.get("REGISTER_MAP_CANONICAL_SHA256"),
    }
    if observed != authority["register_map_abi"]:
        raise CurrentRuntimeError(f"packaged generated ABI differs: {observed}")
    return observed


def verify_hwh(hwh_path: Path, authority: dict[str, Any]) -> dict[str, Any]:
    try:
        root = ET.parse(hwh_path).getroot()
    except (OSError, ET.ParseError) as exc:
        raise CurrentRuntimeError(f"cannot parse HWH: {exc}") from exc
    modules = {
        module.get("INSTANCE"): module
        for module in root.iter("MODULE")
        if module.get("INSTANCE")
    }
    for name in EXPECTED_IP:
        if name not in modules:
            raise CurrentRuntimeError(f"HWH module is missing: {name}")
    ranges: dict[str, dict[str, int]] = {}
    for item in root.iter("MEMRANGE"):
        instance = item.get("INSTANCE")
        if instance not in EXPECTED_IP:
            continue
        try:
            base = int(str(item.get("BASEVALUE")), 0)
            high = int(str(item.get("HIGHVALUE")), 0)
        except ValueError as exc:
            raise CurrentRuntimeError(f"HWH address metadata is invalid: {instance}") from exc
        ranges[str(instance)] = {"phys_addr": base, "addr_range": high - base + 1}
    if ranges != authority["expected_ip"]:
        raise CurrentRuntimeError(f"HWH address metadata mismatch: {ranges}")
    return {"modules": sorted(EXPECTED_IP), "address_map": ranges}


def execute_read_only(
    release_root: Path, authority: dict[str, Any], artifacts: dict[str, Any]
) -> dict[str, Any]:
    runtime_root = release_root / "pynq" / "runtime"
    sys.path.insert(0, str(runtime_root))
    try:
        import pynq  # type: ignore
        from pynq import MMIO, Overlay  # type: ignore
        from protection_ip_interface import (  # type: ignore
            read_capabilities,
            read_register_map_version,
            read_status,
        )
    except Exception as exc:
        raise CurrentRuntimeError(f"current runtime import failed: {exc}") from exc

    bit_path = Path(artifacts["bit"]["path"])
    overlay = Overlay(str(bit_path), download=True)
    checker = getattr(overlay, "is_loaded", None)
    if checker is None or not bool(checker()):
        raise CurrentRuntimeError("Overlay did not confirm the SAFE_INERT BIT")
    ip_dict = getattr(overlay, "ip_dict", None)
    if not isinstance(ip_dict, dict):
        raise CurrentRuntimeError("Overlay IP metadata is unavailable")
    for name, expected in authority["expected_ip"].items():
        observed = ip_dict.get(name)
        if not isinstance(observed, dict):
            raise CurrentRuntimeError(f"Overlay IP is missing: {name}")
        normalized = {
            "phys_addr": int(observed.get("phys_addr")),
            "addr_range": int(observed.get("addr_range")),
        }
        if normalized != expected:
            raise CurrentRuntimeError(f"Overlay IP metadata mismatch: {name}")

    protection = authority["expected_ip"][PROTECTION_IP]
    mmio = MMIO(protection["phys_addr"], protection["addr_range"])
    version = read_register_map_version(mmio)
    if not version.explicit or (version.major, version.minor) != (1, 1):
        raise CurrentRuntimeError("live protection IP is not explicit ABI 1.1")
    capabilities = read_capabilities(mmio)
    snapshot = read_status(mmio)
    if snapshot.ctrl != 0 or snapshot.status != 0 or snapshot.fault_code != 0:
        raise CurrentRuntimeError("SAFE_INERT startup state is not disabled and fault-free")
    return {
        "pynq_version": getattr(pynq, "__version__", "UNKNOWN"),
        "register_map_version": {
            "raw": version.raw_value,
            "major": version.major,
            "minor": version.minor,
        },
        "capabilities": {
            "raw_capabilities_0": capabilities.raw_capabilities_0,
            "raw_capabilities_1": capabilities.raw_capabilities_1,
        },
        "safe_startup": {
            "ctrl": snapshot.ctrl,
            "status": snapshot.status,
            "fault_code": snapshot.fault_code,
        },
    }


def validate_release(release_root: Path, execute: bool = False) -> dict[str, Any]:
    release_root = release_root.resolve(strict=True)
    authority = load_authority(release_root)
    artifacts = verify_artifacts(release_root, authority)
    runtime_sources = verify_runtime_sources(release_root, authority)
    abi = verify_generated_abi(release_root, authority)
    hwh = verify_hwh(Path(artifacts["hwh"]["path"]), authority)
    result: dict[str, Any] = {
        "status": "PASS_OFFLINE" if not execute else "PASS",
        "implementation_profile": PROFILE,
        "persistent_deployment_claim": "NOT_CLAIMED",
        "artifacts": artifacts,
        "runtime_sources": runtime_sources,
        "register_map_abi": abi,
        "hwh": hwh,
        "board_hardware_execution": (
            "NOT_RUN" if not execute else "READ_ONLY_B1_RUNTIME_PASS"
        ),
    }
    if execute:
        result["runtime"] = execute_read_only(release_root, authority, artifacts)
    return result


def default_release_root() -> Path:
    path = Path(__file__).resolve()
    if path.parent.name == "runtime" and path.parent.parent.name == "pynq":
        return path.parents[2]
    if path.parent.name == "stage1g" and path.parent.parent.name == "deployment":
        return path.parents[4]
    raise CurrentRuntimeError(f"cannot infer release root from runtime path: {path}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-root", type=Path, default=default_release_root())
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--output", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    try:
        args = build_parser().parse_args(argv)
        result = validate_release(args.release_root, execute=args.execute)
    except (OSError, CurrentRuntimeError) as exc:
        print(f"FAIL {exc}")
        return 1
    payload = (
        json.dumps(result, ensure_ascii=True, allow_nan=False, indent=2, sort_keys=True)
        + "\n"
    )
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8", newline="\n")
    print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
