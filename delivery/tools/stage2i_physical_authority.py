#!/usr/bin/env python3
"""Validate an external Stage2I physical-artifact authority receipt."""

from __future__ import annotations

import csv
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = "stage2i-physical-authority-receipt-v1"
AUTHORITY_STATE = "STAGE2I_B1_PHYSICAL_AUTHORITY_ACCEPTED"
PRODUCTION_PROFILE = "SAFE_INERT"
BOARD_TEST_PROFILE = "READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS"
SUPPORTED_PROFILES = (PRODUCTION_PROFILE, BOARD_TEST_PROFILE)
ARTIFACT_KEYS = ("bit", "hwh", "ltx", "xsa")
ARTIFACT_ROLES = {
    "bit": "BITSTREAM",
    "hwh": "HWH",
    "ltx": "LTX",
    "xsa": "XSA",
}
DELIVERY_POLICIES = {
    "bit": "DEPLOY_REQUIRED",
    "hwh": "DEPLOY_REQUIRED",
    "ltx": "PROVENANCE_ONLY_REQUIRED",
    "xsa": "PROVENANCE_ONLY_REQUIRED",
}
MANIFEST_HEADER = [
    "kind",
    "role",
    "canonical_path",
    "bytes",
    "sha256",
    "implementation_profile",
    "execution_id",
    "source_commit",
    "source_tree",
    "project_identity",
    "design_identity",
]
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9._:+-]{1,160}$")


class PhysicalAuthorityError(RuntimeError):
    """The external physical authority is missing, malformed, or inconsistent."""


@dataclass(frozen=True)
class ArtifactAuthority:
    key: str
    role: str
    path: Path
    bytes: int
    sha256: str
    delivery_policy: str


@dataclass(frozen=True)
class PhysicalAuthority:
    receipt_path: Path
    receipt_sha256: str
    implementation_profile: str
    source_commit: str
    source_tree: str
    execution_id: str
    request_identity: str
    artifact_manifest_path: Path
    artifact_manifest_bytes: int
    artifact_manifest_sha256: str
    artifacts: dict[str, ArtifactAuthority]
    project_identity: str
    design_identity: str


@dataclass(frozen=True)
class ArtifactManifestAuthority:
    manifest_path: Path
    manifest_bytes: int
    manifest_sha256: str
    implementation_profile: str
    source_commit: str
    source_tree: str
    execution_id: str
    project_identity: str
    design_identity: str
    artifacts: dict[str, ArtifactAuthority]
    report_count: int


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
            raise PhysicalAuthorityError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _load_json(path: Path) -> Any:
    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=lambda value: (_ for _ in ()).throw(
                PhysicalAuthorityError(f"non-finite JSON value: {value}")
            ),
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise PhysicalAuthorityError(f"invalid authority receipt: {exc}") from exc


def _require_object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise PhysicalAuthorityError(f"{label} must be an object")
    return value


def _require_exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    observed = set(value)
    if observed != expected:
        raise PhysicalAuthorityError(
            f"{label} keys differ: missing={sorted(expected - observed)} "
            f"extra={sorted(observed - expected)}"
        )


def _require_sha256(value: Any, label: str) -> str:
    text = str(value)
    if not SHA256_RE.fullmatch(text):
        raise PhysicalAuthorityError(f"{label} is not a lowercase SHA-256")
    return text


def _require_commit(value: Any, label: str) -> str:
    text = str(value)
    if not COMMIT_RE.fullmatch(text):
        raise PhysicalAuthorityError(f"{label} is not a lowercase Git object ID")
    return text


def _require_token(value: Any, label: str) -> str:
    text = str(value)
    if not TOKEN_RE.fullmatch(text):
        raise PhysicalAuthorityError(f"{label} is not a canonical token")
    return text


def _require_positive_size(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise PhysicalAuthorityError(f"{label} must be a positive integer")
    return value


def _resolve_existing_file(value: Any, receipt_path: Path, label: str) -> Path:
    raw = Path(str(value))
    if not raw.is_absolute():
        raw = receipt_path.parent / raw
    try:
        path = raw.resolve(strict=True)
    except OSError as exc:
        raise PhysicalAuthorityError(f"{label} is missing: {raw}") from exc
    if not path.is_file():
        raise PhysicalAuthorityError(f"{label} is not a regular file: {path}")
    return path


def _verify_file(path: Path, expected_bytes: int, expected_sha256: str, label: str) -> None:
    observed_bytes = path.stat().st_size
    observed_sha256 = sha256_file(path)
    if observed_bytes != expected_bytes or observed_sha256 != expected_sha256:
        raise PhysicalAuthorityError(
            f"{label} identity mismatch: bytes={observed_bytes} "
            f"sha256={observed_sha256}"
        )


def load_artifact_manifest(
    manifest_path: Path,
    *,
    expected_profile: str | None = None,
    expected_tree: str | None = None,
) -> ArtifactManifestAuthority:
    manifest_path = manifest_path.resolve(strict=True)
    if not manifest_path.is_file():
        raise PhysicalAuthorityError("artifact manifest is not a regular file")
    try:
        with manifest_path.open("r", encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream, dialect="excel-tab", strict=True)
            if reader.fieldnames != MANIFEST_HEADER:
                raise PhysicalAuthorityError(
                    f"artifact manifest header mismatch: {reader.fieldnames}"
                )
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        raise PhysicalAuthorityError(f"invalid artifact manifest: {exc}") from exc

    if not rows:
        raise PhysicalAuthorityError("artifact manifest is empty")
    profiles: set[str] = set()
    execution_ids: set[str] = set()
    source_commits: set[str] = set()
    source_trees: set[str] = set()
    project_identities: set[str] = set()
    design_identities: set[str] = set()
    artifact_rows: dict[str, dict[str, str]] = {}
    report_count = 0
    for row in rows:
        kind = row["kind"]
        if kind not in {"artifact", "report"}:
            raise PhysicalAuthorityError(f"artifact manifest kind is invalid: {kind}")
        profiles.add(str(row["implementation_profile"]))
        execution_ids.add(_require_token(row["execution_id"], "execution ID"))
        source_commits.add(_require_commit(row["source_commit"], "source commit"))
        source_trees.add(_require_commit(row["source_tree"], "source tree"))
        project_identities.add(_require_token(row["project_identity"], "project identity"))
        design_identities.add(_require_token(row["design_identity"], "design identity"))
        try:
            row_path = Path(row["canonical_path"]).resolve(strict=True)
            row_bytes = int(row["bytes"])
        except (OSError, ValueError) as exc:
            raise PhysicalAuthorityError(
                f"artifact manifest row is invalid: {row['role']}"
            ) from exc
        row_sha256 = _require_sha256(row["sha256"], f"manifest row {row['role']}")
        _verify_file(
            row_path,
            _require_positive_size(row_bytes, f"manifest row bytes: {row['role']}"),
            row_sha256,
            f"manifest row {row['role']}",
        )
        if kind == "artifact":
            role = row["role"]
            if role in artifact_rows:
                raise PhysicalAuthorityError(f"duplicate artifact manifest role: {role}")
            artifact_rows[role] = row
        else:
            report_count += 1

    if not all(
        len(values) == 1
        for values in (
            profiles,
            execution_ids,
            source_commits,
            source_trees,
            project_identities,
            design_identities,
        )
    ):
        raise PhysicalAuthorityError("artifact manifest execution binding is not singular")
    profile = next(iter(profiles))
    if profile not in SUPPORTED_PROFILES:
        raise PhysicalAuthorityError(f"artifact manifest profile is unsupported: {profile}")
    if expected_profile is not None and profile != expected_profile:
        raise PhysicalAuthorityError("artifact manifest profile differs from caller")
    source_tree = next(iter(source_trees))
    if expected_tree is not None and source_tree != expected_tree:
        raise PhysicalAuthorityError("artifact manifest source tree differs from caller")
    expected_roles = set(ARTIFACT_ROLES.values())
    if set(artifact_rows) != expected_roles:
        raise PhysicalAuthorityError(
            f"artifact manifest roles differ: {sorted(artifact_rows)}"
        )
    role_to_key = {role: key for key, role in ARTIFACT_ROLES.items()}
    artifacts: dict[str, ArtifactAuthority] = {}
    for role, row in artifact_rows.items():
        key = role_to_key[role]
        artifacts[key] = ArtifactAuthority(
            key=key,
            role=role,
            path=Path(row["canonical_path"]).resolve(strict=True),
            bytes=int(row["bytes"]),
            sha256=row["sha256"],
            delivery_policy=DELIVERY_POLICIES[key],
        )
    return ArtifactManifestAuthority(
        manifest_path=manifest_path,
        manifest_bytes=manifest_path.stat().st_size,
        manifest_sha256=sha256_file(manifest_path),
        implementation_profile=profile,
        source_commit=next(iter(source_commits)),
        source_tree=source_tree,
        execution_id=next(iter(execution_ids)),
        project_identity=next(iter(project_identities)),
        design_identity=next(iter(design_identities)),
        artifacts=artifacts,
        report_count=report_count,
    )


def load_physical_authority(
    receipt_path: Path,
    *,
    expected_profile: str | None = None,
    expected_tree: str | None = None,
) -> PhysicalAuthority:
    receipt_path = receipt_path.resolve(strict=True)
    if not receipt_path.is_file():
        raise PhysicalAuthorityError("physical authority receipt is not a regular file")
    payload = _require_object(_load_json(receipt_path), "physical authority receipt")
    _require_exact_keys(
        payload,
        {
            "schema_version",
            "authority_state",
            "implementation_profile",
            "source_commit",
            "source_tree",
            "execution_id",
            "request_identity",
            "artifact_manifest",
            "artifacts",
        },
        "physical authority receipt",
    )
    if payload["schema_version"] != SCHEMA_VERSION:
        raise PhysicalAuthorityError("physical authority schema version mismatch")
    if payload["authority_state"] != AUTHORITY_STATE:
        raise PhysicalAuthorityError("physical authority is not accepted")
    profile = str(payload["implementation_profile"])
    if profile != PRODUCTION_PROFILE:
        raise PhysicalAuthorityError("physical authority profile is not SAFE_INERT")
    if expected_profile is not None and profile != expected_profile:
        raise PhysicalAuthorityError("physical authority profile differs from caller")
    source_commit = _require_commit(payload["source_commit"], "source commit")
    source_tree = _require_commit(payload["source_tree"], "source tree")
    if expected_tree is not None and source_tree != expected_tree:
        raise PhysicalAuthorityError("physical authority source tree differs from final main")
    execution_id = _require_token(payload["execution_id"], "execution ID")
    request_identity = _require_sha256(payload["request_identity"], "request identity")

    manifest = _require_object(payload["artifact_manifest"], "artifact manifest authority")
    _require_exact_keys(manifest, {"path", "bytes", "sha256"}, "artifact manifest authority")
    manifest_path = _resolve_existing_file(
        manifest["path"], receipt_path, "artifact manifest"
    )
    manifest_bytes = _require_positive_size(manifest["bytes"], "artifact manifest bytes")
    manifest_sha256 = _require_sha256(
        manifest["sha256"], "artifact manifest SHA-256"
    )
    _verify_file(manifest_path, manifest_bytes, manifest_sha256, "artifact manifest")

    raw_artifacts = _require_object(payload["artifacts"], "artifacts")
    _require_exact_keys(raw_artifacts, set(ARTIFACT_KEYS), "artifacts")
    artifacts: dict[str, ArtifactAuthority] = {}
    for key in ARTIFACT_KEYS:
        raw = _require_object(raw_artifacts[key], f"artifact {key}")
        _require_exact_keys(
            raw,
            {"role", "path", "bytes", "sha256", "delivery_policy"},
            f"artifact {key}",
        )
        if raw["role"] != ARTIFACT_ROLES[key]:
            raise PhysicalAuthorityError(f"artifact role mismatch: {key}")
        if raw["delivery_policy"] != DELIVERY_POLICIES[key]:
            raise PhysicalAuthorityError(f"artifact delivery policy mismatch: {key}")
        path = _resolve_existing_file(raw["path"], receipt_path, f"artifact {key}")
        size = _require_positive_size(raw["bytes"], f"artifact {key} bytes")
        digest = _require_sha256(raw["sha256"], f"artifact {key} SHA-256")
        _verify_file(path, size, digest, f"artifact {key}")
        artifacts[key] = ArtifactAuthority(
            key=key,
            role=ARTIFACT_ROLES[key],
            path=path,
            bytes=size,
            sha256=digest,
            delivery_policy=DELIVERY_POLICIES[key],
        )

    manifest_authority = load_artifact_manifest(
        manifest_path,
        expected_profile=profile,
        expected_tree=source_tree,
    )
    if (
        manifest_authority.execution_id != execution_id
        or manifest_authority.source_commit != source_commit
    ):
        raise PhysicalAuthorityError("artifact manifest execution/source mismatch")
    for key, artifact in artifacts.items():
        manifest_artifact = manifest_authority.artifacts[key]
        if (
            manifest_artifact.path != artifact.path
            or manifest_artifact.bytes != artifact.bytes
            or manifest_artifact.sha256 != artifact.sha256
        ):
            raise PhysicalAuthorityError(f"artifact manifest row differs from receipt: {key}")
    return PhysicalAuthority(
        receipt_path=receipt_path,
        receipt_sha256=sha256_file(receipt_path),
        implementation_profile=profile,
        source_commit=source_commit,
        source_tree=source_tree,
        execution_id=execution_id,
        request_identity=request_identity,
        artifact_manifest_path=manifest_path,
        artifact_manifest_bytes=manifest_bytes,
        artifact_manifest_sha256=manifest_sha256,
        artifacts=artifacts,
        project_identity=manifest_authority.project_identity,
        design_identity=manifest_authority.design_identity,
    )


def sanitized_authority_record(authority: PhysicalAuthority) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "authority_state": AUTHORITY_STATE,
        "implementation_profile": authority.implementation_profile,
        "source_commit": authority.source_commit,
        "source_tree": authority.source_tree,
        "execution_id": authority.execution_id,
        "request_identity": authority.request_identity,
        "receipt_sha256": authority.receipt_sha256,
        "artifact_manifest": {
            "bytes": authority.artifact_manifest_bytes,
            "sha256": authority.artifact_manifest_sha256,
        },
        "project_identity": authority.project_identity,
        "design_identity": authority.design_identity,
        "artifacts": {
            key: {
                "role": artifact.role,
                "bytes": artifact.bytes,
                "sha256": artifact.sha256,
                "delivery_policy": artifact.delivery_policy,
            }
            for key, artifact in authority.artifacts.items()
        },
    }
