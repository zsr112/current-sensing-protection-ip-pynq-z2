#!/usr/bin/env python3
"""Read-only verifier for the authoritative Stage2I current release."""

from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


MANIFEST_NAME = "MANIFEST_SHA256.tsv"
VERSION_NAME = "VERSION.json"
PROVENANCE_NAME = "SOURCE_PROVENANCE.json"
AUTHORITY_PATH = "pynq/artifacts/release_authority.json"
AUTHORITY_SCHEMA = "stage2i-current-release-authority-v1"
PROFILE = "SAFE_INERT"
MANIFEST_SELF_REFERENCE = "RECORDED_IN_EXTERNAL_BUILD_RECEIPT"
EXPECTED_IP = {
    "axi_gpio_stage1d_0": {"phys_addr": 0x41200000, "addr_range": 0x10000},
    "protection_ip_axi_lite_0": {"phys_addr": 0x43C00000, "addr_range": 0x1000},
}
ARTIFACT_CONTRACT = {
    "bit": ("BITSTREAM", "pynq/artifacts/protection_system.bit", "DEPLOY_REQUIRED"),
    "hwh": ("HWH", "pynq/artifacts/protection_system.hwh", "DEPLOY_REQUIRED"),
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
REQUIRED_VERSION_FIELDS = {
    "release_id",
    "release_status",
    "generated_at_utc",
    "engineering_main_commit",
    "engineering_main_tree",
    "physical_artifact_source_commit",
    "physical_artifact_source_tree",
    "physical_artifact_execution_id",
    "physical_authority_receipt_sha256",
    "implementation_profile",
    "target_board",
    "pynq_version",
    "register_map_abi",
    "persistent_deployment_claim",
    "artifact_delivery_policy",
    "release_manifest_sha256",
    "proof_boundary",
    "release_builder_version",
}
FORBIDDEN_PARTS = {
    ".git",
    ".runs",
    ".gen",
    ".cache",
    ".xil",
    "__pycache__",
    "rtl",
    "tb",
    "inventory",
    "evidence",
    "computer-audit",
    "systemd",
    "install",
}
FORBIDDEN_SUFFIXES = {
    ".dcp",
    ".ltx",
    ".xpr",
    ".xsa",
    ".zip",
    ".gz",
    ".pyc",
    ".jou",
    ".log",
    ".rpt",
}
STALE_STAGE1_TOKENS = (
    "S1E-ENGINEERING-" + "ARTIFACTS-20260725T070234792Z",
    "1a365d5139f963ac4d8f92158dcd2928" + "e86ccf36",
    "244cba11579c7fdc39353391ac35a78ed" + "e20ec97",
    "f7dd0823e577cfee2aecfa3bf0a48e80" + "d11108bdb12967e567ca64dc2e8ecfab",
    "c97138493f8c4c568790a75bcc77551a" + "d1f24952f6eb28c4238e6bda975b1e29",
    "stage1g-release-" + "manifest-v1",
    "current-sensing-protection-ip-" + "load.service",
)
STALE_PATH_PATTERNS = (
    re.compile(r"(?i)[A-Z]:\\(?:surf|s1e|s1eo|s1g_packages)(?:\\|\b)"),
    re.compile(r"(?i)[A-Z]:\\dev\\current-sensing-protection-ip(?:\\|\b)"),
    re.compile(r"(?i)/(?:Users|home)/[^/]+/"),
)
CREDENTIAL_PATTERNS = (
    re.compile(rb"AKIA[0-9A-Z]{16}"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(
        rb"(?i)(?:password|passwd|api[_-]?key|client[_-]?secret|access[_-]?token)"
        rb"\s*[:=]\s*['\"][^'\"]{8,}['\"]"
    ),
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9._:+-]{1,160}$")


class ReleaseVerificationError(RuntimeError):
    """The release failed a structural or identity check."""


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
            raise ReleaseVerificationError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=lambda value: (_ for _ in ()).throw(
                ReleaseVerificationError(f"non-finite JSON value: {value}")
            ),
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ReleaseVerificationError(f"invalid JSON {path.name}: {exc}") from exc


def _require_exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise ReleaseVerificationError(f"{label} fields differ")
    return value


def _require_sha256(value: Any, label: str) -> str:
    text = str(value)
    if not SHA256_RE.fullmatch(text):
        raise ReleaseVerificationError(f"{label} is not a lowercase SHA-256")
    return text


def _require_commit(value: Any, label: str) -> str:
    text = str(value)
    if not COMMIT_RE.fullmatch(text):
        raise ReleaseVerificationError(f"{label} is not a Git object ID")
    return text


def _require_token(value: Any, label: str) -> str:
    text = str(value)
    if not TOKEN_RE.fullmatch(text):
        raise ReleaseVerificationError(f"{label} is not a canonical token")
    return text


def _require_positive_size(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ReleaseVerificationError(f"{label} must be a positive integer")
    return value


def safe_relative_path(value: str) -> str:
    if not value or "\\" in value or "\0" in value:
        raise ReleaseVerificationError(f"unsafe manifest path: {value!r}")
    candidate = PurePosixPath(value)
    if candidate.is_absolute() or any(part in {"", ".", ".."} for part in candidate.parts):
        raise ReleaseVerificationError(f"unsafe manifest path: {value!r}")
    return candidate.as_posix()


def regular_files(root: Path) -> dict[str, Path]:
    files: dict[str, Path] = {}
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            raise ReleaseVerificationError(f"symlink is forbidden: {relative}")
        if path.is_file():
            files[relative] = path
    return files


def read_manifest(path: Path) -> list[dict[str, str]]:
    try:
        with path.open("r", encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream, dialect="excel-tab", strict=True)
            expected = ["relative_path", "bytes", "sha256", "component", "source_authority"]
            if reader.fieldnames != expected:
                raise ReleaseVerificationError(f"manifest header mismatch: {reader.fieldnames}")
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        raise ReleaseVerificationError(f"invalid manifest: {exc}") from exc
    paths = [safe_relative_path(row["relative_path"]) for row in rows]
    if paths != sorted(paths) or len(paths) != len(set(paths)):
        raise ReleaseVerificationError("manifest paths are not unique and stably sorted")
    return rows


def load_authority(path: Path) -> dict[str, Any]:
    authority = _require_exact_keys(
        load_json(path),
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
        raise ReleaseVerificationError("release authority schema mismatch")
    if authority["implementation_profile"] != PROFILE:
        raise ReleaseVerificationError("release authority is not SAFE_INERT")
    if authority["persistent_deployment_claim"] != "NOT_CLAIMED":
        raise ReleaseVerificationError("persistent deployment claim differs")
    if authority["tree_equivalence"] != "PASS":
        raise ReleaseVerificationError("tree equivalence is not PASS")
    _require_commit(authority["engineering_main_commit"], "engineering main commit")
    main_tree = _require_commit(authority["engineering_main_tree"], "engineering main tree")
    _require_commit(authority["physical_artifact_source_commit"], "physical source commit")
    physical_tree = _require_commit(authority["physical_artifact_source_tree"], "physical source tree")
    if main_tree != physical_tree:
        raise ReleaseVerificationError("physical artifact source tree differs from engineering main tree")
    if not TOKEN_RE.fullmatch(str(authority["physical_artifact_execution_id"])):
        raise ReleaseVerificationError("physical execution ID is not canonical")
    _require_sha256(authority["physical_artifact_request_identity"], "physical request identity")
    _require_sha256(authority["physical_authority_receipt_sha256"], "physical receipt identity")

    manifest = _require_exact_keys(
        authority["artifact_manifest"],
        {"bytes", "sha256", "project_identity", "design_identity"},
        "artifact manifest",
    )
    _require_positive_size(manifest["bytes"], "artifact manifest bytes")
    _require_sha256(manifest["sha256"], "artifact manifest sha256")
    _require_token(manifest["project_identity"], "artifact manifest project_identity")
    _require_token(manifest["design_identity"], "artifact manifest design_identity")

    artifacts = _require_exact_keys(authority["artifacts"], set(ARTIFACT_CONTRACT), "artifacts")
    for key, (role, _path, policy) in ARTIFACT_CONTRACT.items():
        record = _require_exact_keys(
            artifacts[key],
            {"role", "bytes", "sha256", "delivery_policy"},
            f"artifact {key}",
        )
        if record["role"] != role or record["delivery_policy"] != policy:
            raise ReleaseVerificationError(f"artifact contract mismatch: {key}")
        _require_positive_size(record["bytes"], f"artifact {key} bytes")
        _require_sha256(record["sha256"], f"artifact {key} identity")

    if authority["expected_ip"] != EXPECTED_IP:
        raise ReleaseVerificationError("expected IP/address map differs")
    abi = _require_exact_keys(
        authority["register_map_abi"],
        {"major", "minor", "schema_version", "canonical_sha256"},
        "register-map ABI",
    )
    if abi["major"] != 1 or abi["minor"] != 1 or abi["schema_version"] != "1.1.0":
        raise ReleaseVerificationError("release authority is not ABI 1.1")
    _require_sha256(abi["canonical_sha256"], "register-map canonical identity")

    runtime_sources = _require_exact_keys(
        authority["runtime_sources"], set(RUNTIME_SOURCE_CONTRACT), "runtime source inventory"
    )
    for release_path, source_path in RUNTIME_SOURCE_CONTRACT.items():
        record = _require_exact_keys(
            runtime_sources[release_path],
            {"source_relative_path", "bytes", "sha256"},
            f"runtime source {release_path}",
        )
        if record["source_relative_path"] != source_path:
            raise ReleaseVerificationError(f"runtime source path mismatch: {release_path}")
        _require_positive_size(record["bytes"], f"runtime source bytes: {release_path}")
        _require_sha256(record["sha256"], f"runtime source identity: {release_path}")
    return authority


def verify_version(version: Any, authority: dict[str, Any]) -> None:
    version = _require_exact_keys(version, REQUIRED_VERSION_FIELDS, "VERSION.json")
    for field in (
        "engineering_main_commit",
        "physical_artifact_source_commit",
    ):
        _require_commit(version[field], field)
    for field in ("engineering_main_tree", "physical_artifact_source_tree"):
        _require_commit(version[field], field)
    expected = {
        "release_status": "CURRENT_USE_AND_DELIVERY",
        "engineering_main_commit": authority["engineering_main_commit"],
        "engineering_main_tree": authority["engineering_main_tree"],
        "physical_artifact_source_commit": authority["physical_artifact_source_commit"],
        "physical_artifact_source_tree": authority["physical_artifact_source_tree"],
        "physical_artifact_execution_id": authority["physical_artifact_execution_id"],
        "physical_authority_receipt_sha256": authority["physical_authority_receipt_sha256"],
        "implementation_profile": PROFILE,
        "target_board": "PYNQ-Z2",
        "pynq_version": "3.1.1",
        "register_map_abi": authority["register_map_abi"],
        "persistent_deployment_claim": "NOT_CLAIMED",
        "artifact_delivery_policy": {
            key: authority["artifacts"][key]["delivery_policy"]
            for key in ARTIFACT_CONTRACT
        },
        "release_manifest_sha256": MANIFEST_SELF_REFERENCE,
    }
    for field, value in expected.items():
        if version.get(field) != value:
            raise ReleaseVerificationError(f"VERSION.json identity mismatch: {field}")
    proof = version.get("proof_boundary")
    if not isinstance(proof, dict) or not proof.get("proved") or not proof.get("not_proved"):
        raise ReleaseVerificationError("VERSION.json proof_boundary is incomplete")


def verify_provenance(
    provenance: Any, version: dict[str, Any], authority: dict[str, Any]
) -> None:
    provenance = _require_exact_keys(
        provenance,
        {
            "schema_version",
            "engineering_main_commit",
            "engineering_main_tree",
            "physical_artifact_source_commit",
            "physical_artifact_source_tree",
            "physical_artifact_execution_id",
            "physical_authority_receipt_sha256",
            "tree_equivalence",
            "entries",
        },
        "SOURCE_PROVENANCE.json",
    )
    expected = {
        "schema_version": 2,
        "engineering_main_commit": version["engineering_main_commit"],
        "engineering_main_tree": version["engineering_main_tree"],
        "physical_artifact_source_commit": version["physical_artifact_source_commit"],
        "physical_artifact_source_tree": version["physical_artifact_source_tree"],
        "physical_artifact_execution_id": version["physical_artifact_execution_id"],
        "physical_authority_receipt_sha256": authority["physical_authority_receipt_sha256"],
        "tree_equivalence": "PASS",
    }
    for field, value in expected.items():
        if provenance.get(field) != value:
            raise ReleaseVerificationError(f"provenance identity mismatch: {field}")
    entries = provenance["entries"]
    if not isinstance(entries, list):
        raise ReleaseVerificationError("SOURCE_PROVENANCE.json entries must be a list")
    required = {
        "logical_component",
        "release_relative_path",
        "source_authority",
        "source_path_or_commit",
        "source_relative_path",
        "bytes",
        "sha256",
        "validation_status",
        "notes",
    }
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != required:
            raise ReleaseVerificationError("provenance entry schema mismatch")
        relative = safe_relative_path(str(entry["release_relative_path"]))
        if relative in seen:
            raise ReleaseVerificationError(f"duplicate provenance path: {relative}")
        seen.add(relative)
        if not isinstance(entry["bytes"], int) or entry["bytes"] <= 0:
            raise ReleaseVerificationError(f"invalid provenance bytes: {relative}")
        _require_sha256(entry["sha256"], f"provenance identity: {relative}")


def _literal_assignments(path: Path) -> dict[str, Any]:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (OSError, UnicodeError, SyntaxError) as exc:
        raise ReleaseVerificationError(f"cannot parse generated register map: {exc}") from exc
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


def verify_runtime_sources(
    files: dict[str, Path], authority: dict[str, Any]
) -> dict[str, Any]:
    runtime_files = {path for path in files if path.startswith("pynq/runtime/")}
    if runtime_files != set(RUNTIME_SOURCE_CONTRACT):
        raise ReleaseVerificationError(
            f"runtime source inventory differs: {sorted(runtime_files)}"
        )
    observed: dict[str, Any] = {}
    for relative, record in authority["runtime_sources"].items():
        path = files[relative]
        size = path.stat().st_size
        digest = sha256_file(path)
        if size != record["bytes"] or digest != record["sha256"]:
            raise ReleaseVerificationError(f"runtime source identity mismatch: {relative}")
        observed[relative] = {"bytes": size, "sha256": digest}

    generated_path = files["pynq/runtime/generated/protection_register_map.py"]
    values = _literal_assignments(generated_path)
    abi = {
        "major": values.get("REGISTER_MAP_VERSION_ABI_MAJOR_RESET"),
        "minor": values.get("REGISTER_MAP_VERSION_ABI_MINOR_RESET"),
        "schema_version": values.get("REGISTER_MAP_SCHEMA_VERSION"),
        "canonical_sha256": values.get("REGISTER_MAP_CANONICAL_SHA256"),
    }
    if abi != authority["register_map_abi"]:
        raise ReleaseVerificationError(f"packaged generated ABI differs: {abi}")
    interface_text = files["pynq/runtime/protection_ip_interface.py"].read_text(encoding="utf-8")
    if "generated.protection_register_map import *" not in interface_text:
        raise ReleaseVerificationError("current interface lacks generated ABI binding")
    runtime_text = files["pynq/runtime/stage2i_current_release.py"].read_text(encoding="utf-8")
    if "--execute" not in runtime_text or AUTHORITY_SCHEMA not in runtime_text:
        raise ReleaseVerificationError("current one-shot runtime contract differs")
    if "systemctl" in runtime_text or "download=True" not in runtime_text:
        raise ReleaseVerificationError("current runtime execution/persistence boundary differs")
    return observed


def verify_artifacts(files: dict[str, Path], authority: dict[str, Any]) -> None:
    bit_paths = sorted(path for path in files if path.lower().endswith(".bit"))
    hwh_paths = sorted(path for path in files if path.lower().endswith(".hwh"))
    if bit_paths != [ARTIFACT_CONTRACT["bit"][1]] or hwh_paths != [ARTIFACT_CONTRACT["hwh"][1]]:
        raise ReleaseVerificationError(
            f"BIT/HWH copy inventory mismatch: bit={bit_paths} hwh={hwh_paths}"
        )
    for key in ("bit", "hwh"):
        relative = ARTIFACT_CONTRACT[key][1]
        assert relative is not None
        path = files[relative]
        record = authority["artifacts"][key]
        if path.stat().st_size != record["bytes"] or sha256_file(path) != record["sha256"]:
            raise ReleaseVerificationError(f"{key.upper()} identity mismatch")
    for key, suffix in (("ltx", ".ltx"), ("xsa", ".xsa")):
        if any(path.lower().endswith(suffix) for path in files):
            raise ReleaseVerificationError(f"{key.upper()} violates provenance-only policy")


def verify_hwh(path: Path, authority: dict[str, Any]) -> dict[str, Any]:
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError) as exc:
        raise ReleaseVerificationError(f"cannot parse HWH: {exc}") from exc
    modules = {
        module.get("INSTANCE")
        for module in root.iter("MODULE")
        if module.get("INSTANCE")
    }
    missing = sorted(set(EXPECTED_IP) - modules)
    if missing:
        raise ReleaseVerificationError(f"HWH expected IP is missing: {missing}")
    ranges: dict[str, dict[str, int]] = {}
    for item in root.iter("MEMRANGE"):
        instance = item.get("INSTANCE")
        if instance not in EXPECTED_IP:
            continue
        try:
            base = int(str(item.get("BASEVALUE")), 0)
            high = int(str(item.get("HIGHVALUE")), 0)
        except ValueError as exc:
            raise ReleaseVerificationError(f"HWH address metadata is invalid: {instance}") from exc
        ranges[str(instance)] = {"phys_addr": base, "addr_range": high - base + 1}
    if ranges != authority["expected_ip"]:
        raise ReleaseVerificationError(f"HWH address metadata mismatch: {ranges}")
    return ranges


def verify_forbidden_paths(files: dict[str, Path]) -> None:
    for relative in files:
        path = PurePosixPath(relative)
        lower_parts = {part.lower() for part in path.parts}
        if lower_parts & FORBIDDEN_PARTS:
            raise ReleaseVerificationError(f"forbidden path in release: {relative}")
        lower_name = path.name.lower()
        if any(lower_name.endswith(suffix) for suffix in FORBIDDEN_SUFFIXES):
            raise ReleaseVerificationError(f"forbidden file in release: {relative}")


def scan_text_and_credentials(files: dict[str, Path]) -> tuple[int, int, int]:
    stale_paths = 0
    stale_stage1 = 0
    credentials = 0
    text_suffixes = {".md", ".json", ".tsv", ".py", ".sh", ".service", ".txt"}
    for relative, path in files.items():
        raw = path.read_bytes()
        for pattern in CREDENTIAL_PATTERNS:
            credentials += len(pattern.findall(raw))
        if path.suffix.lower() not in text_suffixes:
            continue
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ReleaseVerificationError(f"invalid UTF-8: {relative}: {exc}") from exc
        for pattern in STALE_PATH_PATTERNS:
            stale_paths += len(pattern.findall(text))
        stale_stage1 += sum(text.count(token) for token in STALE_STAGE1_TOKENS)
    if credentials:
        raise ReleaseVerificationError(f"credential findings: {credentials}")
    if stale_paths:
        raise ReleaseVerificationError(f"stale absolute path findings: {stale_paths}")
    if stale_stage1:
        raise ReleaseVerificationError(f"stale Stage1 runtime/artifact findings: {stale_stage1}")
    return stale_paths, stale_stage1, credentials


def verify_release(root: Path) -> dict[str, Any]:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ReleaseVerificationError(f"release root is not a directory: {root}")
    if (root / "RELEASE_MANIFEST.json").is_file():
        try:
            try:
                from tools.verify_windows_board_release import verify
            except ModuleNotFoundError:
                from verify_windows_board_release import verify
            return verify(root)
        except (OSError, ValueError, KeyError, RuntimeError) as exc:
            raise ReleaseVerificationError(str(exc)) from exc
    files = regular_files(root)
    for required in (MANIFEST_NAME, VERSION_NAME, PROVENANCE_NAME, AUTHORITY_PATH):
        if required not in files:
            raise ReleaseVerificationError(f"missing required file: {required}")
    verify_forbidden_paths(files)

    rows = read_manifest(files[MANIFEST_NAME])
    listed = {row["relative_path"]: row for row in rows}
    expected = set(files) - {MANIFEST_NAME}
    if set(listed) != expected:
        missing = sorted(expected - set(listed))
        extra = sorted(set(listed) - expected)
        raise ReleaseVerificationError(
            f"manifest coverage mismatch: missing={missing} extra={extra}"
        )
    digest_groups: dict[str, list[str]] = defaultdict(list)
    for relative, row in listed.items():
        path = files[relative]
        try:
            expected_bytes = int(row["bytes"])
        except ValueError as exc:
            raise ReleaseVerificationError(f"invalid manifest bytes: {relative}") from exc
        actual_bytes = path.stat().st_size
        actual_sha = sha256_file(path)
        if expected_bytes != actual_bytes or row["sha256"] != actual_sha:
            raise ReleaseVerificationError(f"manifest identity mismatch: {relative}")
        if not row["component"] or not row["source_authority"]:
            raise ReleaseVerificationError(f"manifest classification missing: {relative}")
        digest_groups[actual_sha].append(relative)
    duplicate_groups = [paths for paths in digest_groups.values() if len(paths) > 1]
    if duplicate_groups:
        raise ReleaseVerificationError(f"duplicate payload groups: {duplicate_groups}")

    authority = load_authority(files[AUTHORITY_PATH])
    version = load_json(files[VERSION_NAME])
    verify_version(version, authority)
    provenance = load_json(files[PROVENANCE_NAME])
    verify_provenance(provenance, version, authority)
    verify_artifacts(files, authority)
    runtime_sources = verify_runtime_sources(files, authority)
    hwh_map = verify_hwh(files[ARTIFACT_CONTRACT["hwh"][1]], authority)
    stale_paths, stale_stage1, credentials = scan_text_and_credentials(files)
    directory_count = sum(1 for path in root.rglob("*") if path.is_dir())
    return {
        "status": "PASS",
        "release_id": version["release_id"],
        "implementation_profile": PROFILE,
        "engineering_main_commit": version["engineering_main_commit"],
        "engineering_main_tree": version["engineering_main_tree"],
        "physical_artifact_source_commit": version["physical_artifact_source_commit"],
        "physical_artifact_source_tree": version["physical_artifact_source_tree"],
        "tree_equivalence": "PASS",
        "register_map_abi": authority["register_map_abi"],
        "persistent_deployment_claim": "NOT_CLAIMED",
        "ltx_policy": authority["artifacts"]["ltx"]["delivery_policy"],
        "xsa_policy": authority["artifacts"]["xsa"]["delivery_policy"],
        "runtime_source_count": len(runtime_sources),
        "hwh_address_map": hwh_map,
        "file_count": len(files),
        "directory_count": directory_count,
        "total_bytes": sum(path.stat().st_size for path in files.values()),
        "manifest_bytes": files[MANIFEST_NAME].stat().st_size,
        "manifest_sha256": sha256_file(files[MANIFEST_NAME]),
        "duplicate_payload_groups": 0,
        "release_bit_copy_count": 1,
        "release_hwh_copy_count": 1,
        "release_ltx_copy_count": 0,
        "release_xsa_copy_count": 0,
        "stale_absolute_paths": stale_paths,
        "stale_stage1_findings": stale_stage1,
        "credential_findings": credentials,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "release_root",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = verify_release(args.release_root)
    except (OSError, ReleaseVerificationError) as exc:
        print(f"FAIL {exc}")
        return 1
    print("PASS " + json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
