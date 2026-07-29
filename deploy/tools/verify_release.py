#!/usr/bin/env python3
"""Read-only verifier for the current-use release directory."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


MANIFEST_NAME = "MANIFEST_SHA256.tsv"
VERSION_NAME = "VERSION.json"
PROVENANCE_NAME = "SOURCE_PROVENANCE.json"
EXPECTED_BIT_SHA256 = "f7dd0823e577cfee2aecfa3bf0a48e80d11108bdb12967e567ca64dc2e8ecfab"
EXPECTED_HWH_SHA256 = "c97138493f8c4c568790a75bcc77551ad1f24952f6eb28c4238e6bda975b1e29"
EXPECTED_BOARD_COMMIT = "1a365d5139f963ac4d8f92158dcd2928e86ccf36"
EXPECTED_BOARD_TREE = "244cba11579c7fdc39353391ac35a78ede20ec97"
MANIFEST_SELF_REFERENCE = "RECORDED_IN_EXTERNAL_BUILD_RECEIPT"
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
REQUIRED_VERSION_FIELDS = {
    "release_id",
    "release_status",
    "generated_at_utc",
    "engineering_source_commit",
    "engineering_source_tree",
    "board_validated_runtime_commit",
    "board_validated_runtime_tree",
    "target_board",
    "pynq_version",
    "bit_sha256",
    "hwh_sha256",
    "release_manifest_sha256",
    "proof_boundary",
    "release_builder_version",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
STALE_PATH_PATTERNS = (
    re.compile(r"(?i)[A-Z]:\\(?:surf|s1e|s1eo|s1g_packages)(?:\\|\b)"),
    re.compile(r"(?i)C:\\dev\\current-sensing-protection-ip(?:\\|\b)"),
    re.compile(r"(?i)/Users/" + "nightsseven" + r"/Desktop/surf(?:/|\b)"),
)
CREDENTIAL_PATTERNS = (
    re.compile(rb"AKIA[0-9A-Z]{16}"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(
        rb"(?i)(?:password|passwd|api[_-]?key|client[_-]?secret|access[_-]?token)"
        rb"\s*[:=]\s*['\"][^'\"]{8,}['\"]"
    ),
)


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


def verify_version(version: Any) -> None:
    if not isinstance(version, dict):
        raise ReleaseVerificationError("VERSION.json root must be an object")
    missing = REQUIRED_VERSION_FIELDS - set(version)
    if missing:
        raise ReleaseVerificationError(f"VERSION.json missing fields: {sorted(missing)}")
    for field in (
        "engineering_source_commit",
        "board_validated_runtime_commit",
    ):
        if not COMMIT_RE.fullmatch(str(version[field])):
            raise ReleaseVerificationError(f"invalid commit identity: {field}")
    for field in ("engineering_source_tree", "board_validated_runtime_tree"):
        if not COMMIT_RE.fullmatch(str(version[field])):
            raise ReleaseVerificationError(f"invalid tree identity: {field}")
    expected = {
        "board_validated_runtime_commit": EXPECTED_BOARD_COMMIT,
        "board_validated_runtime_tree": EXPECTED_BOARD_TREE,
        "target_board": "PYNQ-Z2",
        "pynq_version": "3.1.1",
        "bit_sha256": EXPECTED_BIT_SHA256,
        "hwh_sha256": EXPECTED_HWH_SHA256,
        "release_manifest_sha256": MANIFEST_SELF_REFERENCE,
    }
    for field, value in expected.items():
        if version.get(field) != value:
            raise ReleaseVerificationError(f"VERSION.json identity mismatch: {field}")
    proof = version.get("proof_boundary")
    if not isinstance(proof, dict) or not proof.get("proved") or not proof.get("not_proved"):
        raise ReleaseVerificationError("VERSION.json proof_boundary is incomplete")


def verify_provenance(provenance: Any, version: dict[str, Any]) -> None:
    if not isinstance(provenance, dict) or not isinstance(provenance.get("entries"), list):
        raise ReleaseVerificationError("SOURCE_PROVENANCE.json entries must be a list")
    required = {
        "logical_component",
        "release_relative_path",
        "source_authority",
        "source_path_or_commit",
        "source_relative_path",
        "bytes",
        "sha256",
        "board_validation_status",
        "notes",
    }
    seen: set[str] = set()
    for entry in provenance["entries"]:
        if not isinstance(entry, dict) or not required.issubset(entry):
            raise ReleaseVerificationError("provenance entry schema mismatch")
        relative = safe_relative_path(str(entry["release_relative_path"]))
        if relative in seen:
            raise ReleaseVerificationError(f"duplicate provenance path: {relative}")
        seen.add(relative)
        if not isinstance(entry["bytes"], int) or entry["bytes"] < 0:
            raise ReleaseVerificationError(f"invalid provenance bytes: {relative}")
        if not SHA256_RE.fullmatch(str(entry["sha256"])):
            raise ReleaseVerificationError(f"invalid provenance SHA-256: {relative}")
    if provenance.get("engineering_source_commit") != version["engineering_source_commit"]:
        raise ReleaseVerificationError("provenance engineering commit mismatch")


def verify_forbidden_paths(files: dict[str, Path]) -> None:
    bit_paths: list[str] = []
    hwh_paths: list[str] = []
    for relative in files:
        path = PurePosixPath(relative)
        lower_parts = {part.lower() for part in path.parts}
        if lower_parts & FORBIDDEN_PARTS:
            raise ReleaseVerificationError(f"forbidden path in release: {relative}")
        lower_name = path.name.lower()
        if any(lower_name.endswith(suffix) for suffix in FORBIDDEN_SUFFIXES):
            raise ReleaseVerificationError(f"forbidden file in release: {relative}")
        if lower_name.endswith(".bit"):
            bit_paths.append(relative)
        if lower_name.endswith(".hwh"):
            hwh_paths.append(relative)
    if len(bit_paths) != 1 or len(hwh_paths) != 1:
        raise ReleaseVerificationError(
            f"BIT/HWH copy count mismatch: bit={len(bit_paths)} hwh={len(hwh_paths)}"
        )
    if sha256_file(files[bit_paths[0]]) != EXPECTED_BIT_SHA256:
        raise ReleaseVerificationError("BIT SHA-256 mismatch")
    if sha256_file(files[hwh_paths[0]]) != EXPECTED_HWH_SHA256:
        raise ReleaseVerificationError("HWH SHA-256 mismatch")


def scan_text_and_credentials(files: dict[str, Path]) -> tuple[int, int]:
    stale = 0
    credentials = 0
    text_suffixes = {".md", ".json", ".tsv", ".py", ".sh", ".service", ".txt"}
    for relative, path in files.items():
        raw = path.read_bytes()
        for pattern in CREDENTIAL_PATTERNS:
            credentials += len(pattern.findall(raw))
        if path.suffix.lower() in text_suffixes:
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise ReleaseVerificationError(f"invalid UTF-8: {relative}: {exc}") from exc
            for pattern in STALE_PATH_PATTERNS:
                stale += len(pattern.findall(text))
    if credentials:
        raise ReleaseVerificationError(f"credential findings: {credentials}")
    if stale:
        raise ReleaseVerificationError(f"stale absolute path findings: {stale}")
    return stale, credentials


def verify_release(root: Path) -> dict[str, Any]:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ReleaseVerificationError(f"release root is not a directory: {root}")
    files = regular_files(root)
    for required in (MANIFEST_NAME, VERSION_NAME, PROVENANCE_NAME):
        if required not in files:
            raise ReleaseVerificationError(f"missing required file: {required}")
    rows = read_manifest(files[MANIFEST_NAME])
    listed = {row["relative_path"]: row for row in rows}
    expected = set(files) - {MANIFEST_NAME}
    if set(listed) != expected:
        missing = sorted(expected - set(listed))
        extra = sorted(set(listed) - expected)
        raise ReleaseVerificationError(f"manifest coverage mismatch: missing={missing} extra={extra}")
    digest_groups: dict[str, list[str]] = defaultdict(list)
    total_bytes = 0
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
        total_bytes += actual_bytes
    duplicate_groups = [paths for paths in digest_groups.values() if len(paths) > 1]
    if duplicate_groups:
        raise ReleaseVerificationError(f"duplicate payload groups: {duplicate_groups}")
    version = load_json(files[VERSION_NAME])
    verify_version(version)
    provenance = load_json(files[PROVENANCE_NAME])
    verify_provenance(provenance, version)
    verify_forbidden_paths(files)
    stale, credentials = scan_text_and_credentials(files)
    directory_count = sum(1 for path in root.rglob("*") if path.is_dir())
    return {
        "status": "PASS",
        "release_id": version["release_id"],
        "file_count": len(files),
        "directory_count": directory_count,
        "total_bytes": sum(path.stat().st_size for path in files.values()),
        "manifest_bytes": files[MANIFEST_NAME].stat().st_size,
        "manifest_sha256": sha256_file(files[MANIFEST_NAME]),
        "duplicate_payload_groups": 0,
        "release_bit_copy_count": 1,
        "release_hwh_copy_count": 1,
        "stale_absolute_paths": stale,
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
