#!/usr/bin/env python3
"""Verify an installed Stage 1G release without touching programmable logic."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import tempfile
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = "stage1g-release-manifest-v1"
DEPLOYMENT_ROOT = Path("/opt/current-sensing-protection-ip")
RELEASES_ROOT = DEPLOYMENT_ROOT / "releases"
CURRENT_LINK = DEPLOYMENT_ROOT / "current"

ACCEPTED_EXECUTION_ID = "S1E-ENGINEERING-ARTIFACTS-20260725T070234792Z"
ACCEPTED_SOURCE_COMMIT = "335e88f724f255bff495a851efefbe6fcd28bd83"
ACCEPTED_SOURCE_TREE = "1caa95bd9153eb4bdd29ae70b9a646d18d8faf7f"
ACCEPTED_ARTIFACT_MANIFEST = {
    "filename": "artifact-manifest.tsv",
    "bytes": 5193,
    "sha256": "81ed62823b34a83622a27c3063243ad03f780fe504000e1a0111634c198eed1c",
}
ACCEPTED_ARTIFACTS = {
    "bit": {
        "filename": "protection_system.bit",
        "bytes": 4045685,
        "sha256": "f7dd0823e577cfee2aecfa3bf0a48e80d11108bdb12967e567ca64dc2e8ecfab",
    },
    "hwh": {
        "filename": "protection_system.hwh",
        "bytes": 388536,
        "sha256": "c97138493f8c4c568790a75bcc77551ad1f24952f6eb28c4238e6bda975b1e29",
    },
}
EXPECTED_RUNTIME = {
    "xilinx_xrt": "/usr",
    "python_executable": "/usr/local/share/pynq-venv/bin/python3",
    "python_version": "3.10.4",
    "pynq_version": "3.1.1",
}
EXPECTED_DEVICE = {"board_name": "Pynq-Z2", "device_tag": "embedded_xrt0"}
EXPECTED_IP = {
    "axi_gpio_stage1d_0": {"phys_addr": 0x41200000, "addr_range": 0x00010000},
    "protection_ip_axi_lite_0": {
        "phys_addr": 0x43C00000,
        "addr_range": 0x00001000,
    },
}
EXPECTED_REGISTERS = {
    "CTRL": 0,
    "FAULT_CODE": 0,
    "I_CH1": 1024,
    "I_CH2": 1024,
    "PWM_DUTY": 500,
    "PWM_PERIOD": 1000,
    "STATUS": 0,
    "TH_DIFF": 200,
    "TH_OC1": 3000,
    "TH_OC2": 3000,
}
EXPECTED_GPIO = {"DATA": 0x00400400, "TRI": 0xFFFFFFFF}
RELEASE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


class ReleaseVerificationError(RuntimeError):
    """A release failed identity, structure, or containment verification."""

    def __init__(self, message: str, classification: str = "RELEASE_VERIFICATION_FAILED"):
        super().__init__(message)
        self.classification = classification


def _reject_duplicate_keys(pairs: Iterable[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReleaseVerificationError(
                f"duplicate JSON key: {key}", "MANIFEST_DUPLICATE_KEY"
            )
        result[key] = value
    return result


def canonical_json_bytes(value: Any) -> bytes:
    """Return the repository's canonical compact JSON representation."""

    return json.dumps(
        value,
        ensure_ascii=True,
        allow_nan=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def load_canonical_json(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise ReleaseVerificationError(
            f"cannot read manifest {path}: {exc}", "MANIFEST_MISSING"
        ) from exc
    try:
        parsed = json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ReleaseVerificationError(
            f"invalid UTF-8 JSON manifest: {exc}", "MANIFEST_PARSE_FAILED"
        ) from exc
    if not isinstance(parsed, dict):
        raise ReleaseVerificationError(
            "release manifest root must be an object", "MANIFEST_SCHEMA_MISMATCH"
        )
    if raw != canonical_json_bytes(parsed):
        raise ReleaseVerificationError(
            "release manifest is not canonical compact JSON",
            "MANIFEST_CANONICALIZATION_MISMATCH",
        )
    return parsed


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise ReleaseVerificationError(
            f"cannot hash {path}: {exc}", "ARTIFACT_MISSING"
        ) from exc
    return digest.hexdigest()


def fsync_directory(path: Path) -> None:
    if os.name == "nt":
        return
    descriptor = os.open(str(path), os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_write_bytes(path: Path, payload: bytes, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
        fsync_directory(path.parent)
    except Exception:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def atomic_write_json(path: Path, value: Any, mode: int = 0o600) -> None:
    atomic_write_bytes(path, canonical_json_bytes(value), mode)


def _require_exact(actual: Any, expected: Any, field: str) -> None:
    if actual != expected:
        raise ReleaseVerificationError(
            f"manifest field {field} mismatch: {actual!r}",
            "MANIFEST_CONTRACT_MISMATCH",
        )


def validate_release_id(release_id: str) -> str:
    if not RELEASE_ID_RE.fullmatch(release_id) or release_id in {".", ".."}:
        raise ReleaseVerificationError(
            f"unsafe release ID: {release_id!r}", "RELEASE_ID_INVALID"
        )
    return release_id


def validate_manifest_contract(manifest: dict[str, Any], directory_name: str) -> None:
    required = {
        "schema_version",
        "release_id",
        "stage1e_execution",
        "accepted_source",
        "artifact_manifest",
        "artifacts",
        "expected_device",
        "runtime_expectations",
        "expected_ip_dict",
        "expected_fclk0",
        "expected_register_defaults",
        "expected_gpio",
        "creation_provenance",
        "activation_status",
    }
    missing = required - set(manifest)
    if missing:
        raise ReleaseVerificationError(
            f"release manifest is missing fields: {sorted(missing)}",
            "MANIFEST_SCHEMA_MISMATCH",
        )
    extra = set(manifest) - required
    if extra:
        raise ReleaseVerificationError(
            f"release manifest has unexpected fields: {sorted(extra)}",
            "MANIFEST_SCHEMA_MISMATCH",
        )
    _require_exact(manifest["schema_version"], SCHEMA_VERSION, "schema_version")
    release_id = validate_release_id(str(manifest["release_id"]))
    _require_exact(release_id, directory_name, "release_id")
    _require_exact(manifest["stage1e_execution"], ACCEPTED_EXECUTION_ID, "stage1e_execution")
    _require_exact(
        manifest["accepted_source"],
        {"commit": ACCEPTED_SOURCE_COMMIT, "tree": ACCEPTED_SOURCE_TREE},
        "accepted_source",
    )
    _require_exact(
        manifest["artifact_manifest"], ACCEPTED_ARTIFACT_MANIFEST, "artifact_manifest"
    )
    _require_exact(manifest["artifacts"], ACCEPTED_ARTIFACTS, "artifacts")
    _require_exact(manifest["expected_device"], EXPECTED_DEVICE, "expected_device")
    _require_exact(
        manifest["runtime_expectations"], EXPECTED_RUNTIME, "runtime_expectations"
    )
    _require_exact(manifest["expected_ip_dict"], EXPECTED_IP, "expected_ip_dict")
    _require_exact(
        manifest["expected_fclk0"],
        {
            "inclusive_mhz": [99.0, 101.0],
            "maximum_spread_mhz": 0.1,
            "sample_count": 5,
        },
        "expected_fclk0",
    )
    _require_exact(
        manifest["expected_register_defaults"],
        EXPECTED_REGISTERS,
        "expected_register_defaults",
    )
    _require_exact(manifest["expected_gpio"], EXPECTED_GPIO, "expected_gpio")
    _require_exact(
        manifest["activation_status"],
        {
            "boot_validated": False,
            "eligible": True,
            "selector": "ATOMIC_CURRENT_SYMLINK",
            "state": "ELIGIBLE_NOT_BOOT_VALIDATED",
        },
        "activation_status",
    )
    _require_exact(
        manifest["creation_provenance"],
        {
            "source_package_id": (
                "stage1f_board_validation_package_v1_20260725T173211988Z"
            ),
            "source_package_manifest_sha256": (
                "01e8495b9b422c14cd81148599acd6a936d26f157ed40f5cdb9ad584d9fb4645"
            ),
            "installer_contract": "STAGE1G_PERSISTENT_DEPLOYMENT_FOUNDATION_V1",
            "cryptographic_signing": (
                "OUTSIDE_INITIAL_RELEASE_NO_APPROVED_SIGNING_KEY"
            ),
        },
        "creation_provenance",
    )


def contained_release_path(release_path: Path, releases_root: Path = RELEASES_ROOT) -> Path:
    try:
        resolved_root = releases_root.resolve(strict=True)
        resolved_release = release_path.resolve(strict=True)
    except OSError as exc:
        raise ReleaseVerificationError(
            f"release path cannot be resolved: {exc}", "RELEASE_PATH_MISSING"
        ) from exc
    if resolved_release.parent != resolved_root:
        raise ReleaseVerificationError(
            f"release path escapes release root: {release_path}", "RELEASE_PATH_ESCAPE"
        )
    return resolved_release


def _verify_immutable_permissions(paths: list[Path]) -> None:
    if os.name == "nt":
        return
    for path in paths:
        metadata = path.stat()
        if metadata.st_uid != 0:
            raise ReleaseVerificationError(
                f"installed path is not owned by root: {path}",
                "RELEASE_OWNERSHIP_MISMATCH",
            )
        if stat.S_IMODE(metadata.st_mode) & 0o022:
            raise ReleaseVerificationError(
                f"installed path is group/world writable: {path}",
                "RELEASE_PERMISSIONS_UNSAFE",
            )


def verify_release(
    release_path: Path,
    releases_root: Path = RELEASES_ROOT,
    *,
    check_permissions: bool = True,
) -> dict[str, Any]:
    resolved = contained_release_path(release_path, releases_root)
    manifest_path = resolved / "release_manifest.json"
    digest_path = resolved / "release_manifest.sha256"
    for path in (manifest_path, digest_path):
        if not path.is_file() or path.is_symlink():
            raise ReleaseVerificationError(
                f"required release file missing or symlinked: {path.name}",
                "MANIFEST_MISSING",
            )

    manifest = load_canonical_json(manifest_path)
    validate_manifest_contract(manifest, resolved.name)
    manifest_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    expected_digest_line = f"{manifest_hash}  release_manifest.json\n"
    try:
        digest_line = digest_path.read_text(encoding="ascii")
    except (OSError, UnicodeDecodeError) as exc:
        raise ReleaseVerificationError(
            f"cannot read release manifest digest: {exc}", "MANIFEST_HASH_MISMATCH"
        ) from exc
    if digest_line != expected_digest_line:
        raise ReleaseVerificationError(
            "release manifest SHA-256 sidecar mismatch", "MANIFEST_HASH_MISMATCH"
        )

    observed: dict[str, Any] = {}
    verified_paths = [resolved, manifest_path, digest_path]
    for role in ("bit", "hwh"):
        expected = manifest["artifacts"][role]
        artifact_path = resolved / expected["filename"]
        if not artifact_path.is_file() or artifact_path.is_symlink():
            raise ReleaseVerificationError(
                f"required {role.upper()} artifact missing or symlinked",
                "ARTIFACT_MISSING",
            )
        actual_bytes = artifact_path.stat().st_size
        actual_hash = sha256_file(artifact_path)
        if actual_bytes != expected["bytes"] or actual_hash != expected["sha256"]:
            raise ReleaseVerificationError(
                f"{role.upper()} identity mismatch", f"{role.upper()}_HASH_MISMATCH"
            )
        observed[role] = {
            "path": str(artifact_path),
            "bytes": actual_bytes,
            "sha256": actual_hash,
        }
        verified_paths.append(artifact_path)
    if check_permissions:
        _verify_immutable_permissions(verified_paths)
    return {
        "status": "PASS",
        "release_id": manifest["release_id"],
        "release_path": str(resolved),
        "manifest_sha256": manifest_hash,
        "artifact_manifest_sha256": manifest["artifact_manifest"]["sha256"],
        "artifacts": observed,
        "manifest": manifest,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    selector = parser.add_mutually_exclusive_group()
    selector.add_argument("--release-id")
    selector.add_argument("--release-path", type=Path)
    parser.add_argument("--releases-root", type=Path, default=RELEASES_ROOT)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.release_path is not None:
        release_path = args.release_path
    elif args.release_id is not None:
        release_path = args.releases_root / validate_release_id(args.release_id)
    else:
        release_path = CURRENT_LINK
    try:
        result = verify_release(release_path, args.releases_root)
    except ReleaseVerificationError as exc:
        print(
            json.dumps(
                {
                    "status": "FAIL",
                    "terminal_state": exc.classification,
                    "error": str(exc),
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
