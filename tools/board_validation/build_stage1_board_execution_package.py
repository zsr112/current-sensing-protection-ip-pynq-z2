#!/usr/bin/env python3
"""Build a deterministic Stage2I C1/C2 board execution package."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

try:
    from sw.generated.protection_register_map import (
        REGISTER_MAP_CANONICAL_SHA256,
        REGISTER_MAP_SCHEMA_VERSION,
        REGISTER_MAP_VERSION_ABI_MAJOR_RESET,
        REGISTER_MAP_VERSION_ABI_MINOR_RESET,
    )
    from sw import stage2i_board_runtime as board_runtime
    from tools import stage2i_physical_authority as physical_authority
except ModuleNotFoundError:
    raise RuntimeError("run the package builder from the repository source tree")


PACKAGE_SCHEMA = "stage2i-board-execution-package-v1"
SOURCE_FILES = {
    "sw/stage2i_board_runtime.py": "runtime/stage2i_board_runtime.py",
    "sw/protection_ip_interface.py": "runtime/protection_ip_interface.py",
    "sw/generated/protection_register_map.py": (
        "runtime/generated/protection_register_map.py"
    ),
    "sw/stage2c9e_b_pynq_mmio_register_smoke.py": (
        "runtime/stage2c9e_b_pynq_mmio_register_smoke.py"
    ),
    "sw/stage2c9f_b_controlled_expanded_mmio_idempotent_rw.py": (
        "runtime/stage2c9f_b_controlled_expanded_mmio_idempotent_rw.py"
    ),
    "sw/stage2c9g_b_read_only_semantic_status_observation.py": (
        "runtime/stage2c9g_b_read_only_semantic_status_observation.py"
    ),
    "sw/stage2c10b_a_controlled_prefunctional_probe_candidate.py": (
        "runtime/stage2c10b_a_controlled_prefunctional_probe_candidate.py"
    ),
    "tools/board_validation/stage1_board_functional_validation.py": (
        "runtime/stage1_board_functional_validation.py"
    ),
    "tools/board_validation/stage1_board_evidence_analyzer.py": (
        "runtime/stage1_board_evidence_analyzer.py"
    ),
    "tools/board_validation/stage1_board_ila_common.tcl": (
        "host/stage1_board_ila_common.tcl"
    ),
    "tools/board_validation/stage1_board_ila_binding_preflight.tcl": (
        "host/stage1_board_ila_binding_preflight.tcl"
    ),
    "tools/board_validation/stage1_board_ila_capture_configuration.tcl": (
        "host/stage1_board_ila_capture_configuration.tcl"
    ),
    "tools/board_validation/stage1_board_ila_capture_configuration_preflight.tcl": (
        "host/stage1_board_ila_capture_configuration_preflight.tcl"
    ),
    "tools/board_validation/stage1_board_ila_capture.tcl": (
        "host/stage1_board_ila_capture.tcl"
    ),
}
ARTIFACT_PACKAGE_PATHS = {
    "bit": "artifacts/protection_system.bit",
    "hwh": "artifacts/protection_system.hwh",
    "ltx": "artifacts/protection_system.ltx",
}
MANIFEST_NAME = "MANIFEST_SHA256.tsv"
INVENTORY_NAME = "FILE_INVENTORY.txt"
PACKAGE_IDENTITY_NAME = "PACKAGE_IDENTITY.json"
OFFLINE_VALIDATION_NAME = "OFFLINE_VALIDATION.json"
ARTIFACT_MANIFEST_PACKAGE_PATH = "provenance/artifact-manifest.tsv"


class PackageBuildError(RuntimeError):
    """The Stage2I board package could not be built without ambiguity."""


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2, sort_keys=True)
        + "\n"
    ).encode("utf-8")


def run_git(repo_root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def verify_git_source(repo_root: Path, expected_tree: str) -> tuple[str, str, str]:
    branch = run_git(repo_root, "branch", "--show-current")
    commit = run_git(repo_root, "rev-parse", "HEAD")
    tree = run_git(repo_root, "rev-parse", "HEAD^{tree}")
    status = run_git(repo_root, "status", "--porcelain", "--untracked-files=all")
    if not branch or status:
        raise PackageBuildError("board package source must be a clean named branch")
    if tree != expected_tree:
        raise PackageBuildError("board package source tree differs from artifact source tree")
    try:
        remote = run_git(repo_root, "rev-parse", f"origin/{branch}")
    except subprocess.CalledProcessError as exc:
        raise PackageBuildError("board package feature branch is not published") from exc
    if remote != commit:
        raise PackageBuildError("local and remote board package commits differ")
    return branch, commit, tree


def register_map_abi() -> dict[str, Any]:
    return {
        "major": int(REGISTER_MAP_VERSION_ABI_MAJOR_RESET),
        "minor": int(REGISTER_MAP_VERSION_ABI_MINOR_RESET),
        "schema_version": REGISTER_MAP_SCHEMA_VERSION,
        "canonical_sha256": REGISTER_MAP_CANONICAL_SHA256,
    }


def build_profile(
    manifest: physical_authority.ArtifactManifestAuthority,
) -> dict[str, Any]:
    profile = manifest.implementation_profile
    artifacts: dict[str, Any] = {}
    for key, artifact in manifest.artifacts.items():
        package_path = ARTIFACT_PACKAGE_PATHS.get(key)
        policy = (
            "PACKAGE_REQUIRED" if package_path is not None else "PROVENANCE_ONLY_REQUIRED"
        )
        artifacts[key] = {
            "role": artifact.role,
            "bytes": artifact.bytes,
            "sha256": artifact.sha256,
            "package_path": package_path,
            "delivery_policy": policy,
        }
    return {
        "schema_version": board_runtime.PROFILE_SCHEMA,
        "implementation_profile": profile,
        "source_commit": manifest.source_commit,
        "source_tree": manifest.source_tree,
        "execution_id": manifest.execution_id,
        "artifact_manifest": {
            "package_path": "provenance/artifact-manifest.tsv",
            "bytes": manifest.manifest_bytes,
            "sha256": manifest.manifest_sha256,
        },
        "artifacts": artifacts,
        "expected_ip": board_runtime.EXPECTED_IP,
        "debug_cores": board_runtime.debug_core_contract(profile),
        "control": board_runtime.control_contract(profile),
        "register_map_abi": register_map_abi(),
    }


def _write_new(root: Path, relative: str, payload: bytes) -> None:
    destination = root / Path(relative)
    if destination.exists():
        raise PackageBuildError(f"package path collision: {relative}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)


def _regular_files(root: Path) -> dict[str, Path]:
    return {
        path.relative_to(root).as_posix(): path
        for path in root.rglob("*")
        if path.is_file()
    }


def expected_package_entries() -> set[str]:
    return {
        *SOURCE_FILES.values(),
        *ARTIFACT_PACKAGE_PATHS.values(),
        ARTIFACT_MANIFEST_PACKAGE_PATH,
        board_runtime.PROFILE_FILENAME,
        PACKAGE_IDENTITY_NAME,
        OFFLINE_VALIDATION_NAME,
        INVENTORY_NAME,
        MANIFEST_NAME,
    }


def _write_inventory_and_manifest(root: Path) -> None:
    files = _regular_files(root)
    inventory_lines = [
        f"{relative}\t{path.stat().st_size}\t{sha256_bytes(path.read_bytes())}\n"
        for relative, path in sorted(files.items())
    ]
    _write_new(root, INVENTORY_NAME, "".join(inventory_lines).encode("utf-8"))
    files = _regular_files(root)
    lines = ["relative_path\tbytes\tsha256\n"]
    for relative, path in sorted(files.items()):
        payload = path.read_bytes()
        lines.append(f"{relative}\t{len(payload)}\t{sha256_bytes(payload)}\n")
    _write_new(root, MANIFEST_NAME, "".join(lines).encode("utf-8"))


def write_package_tree(
    root: Path,
    repo_root: Path,
    manifest: physical_authority.ArtifactManifestAuthority,
    source_branch: str,
    source_commit: str,
    source_tree: str,
) -> dict[str, Any]:
    if source_tree != manifest.source_tree or source_commit != manifest.source_commit:
        raise PackageBuildError("package source identity differs from artifact manifest")
    for source_relative, package_relative in SOURCE_FILES.items():
        source = repo_root / Path(source_relative)
        if not source.is_file():
            raise PackageBuildError(f"package source is missing: {source_relative}")
        _write_new(root, package_relative, source.read_bytes())
    for key, package_relative in ARTIFACT_PACKAGE_PATHS.items():
        _write_new(root, package_relative, manifest.artifacts[key].path.read_bytes())
    _write_new(
        root,
        ARTIFACT_MANIFEST_PACKAGE_PATH,
        manifest.manifest_path.read_bytes(),
    )
    profile = build_profile(manifest)
    _write_new(root, board_runtime.PROFILE_FILENAME, canonical_json(profile))
    package_identity = {
        "schema_version": PACKAGE_SCHEMA,
        "source_branch": source_branch,
        "source_commit": source_commit,
        "source_tree": source_tree,
        "implementation_profile": manifest.implementation_profile,
        "physical_execution_id": manifest.execution_id,
        "artifact_manifest_sha256": manifest.manifest_sha256,
        "board_hardware_execution": "NOT_RUN",
        "persistent_deployment_claim": "NOT_CLAIMED",
    }
    _write_new(root, PACKAGE_IDENTITY_NAME, canonical_json(package_identity))
    offline = board_runtime.validate_package(
        root, expected_profile=manifest.implementation_profile
    )
    _write_new(root, OFFLINE_VALIDATION_NAME, canonical_json(offline))
    _write_inventory_and_manifest(root)
    return {"package_identity": package_identity, "offline_validation": offline}


def _safe_zip_name(name: str) -> str:
    path = PurePosixPath(name)
    if (
        not name
        or "\\" in name
        or path.is_absolute()
        or any(part in {"", ".", ".."} for part in path.parts)
    ):
        raise PackageBuildError(f"unsafe ZIP path: {name!r}")
    return path.as_posix()


def write_deterministic_zip(root: Path, output: Path) -> None:
    if output.exists():
        raise PackageBuildError(f"refusing to overwrite package ZIP: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative, path in sorted(_regular_files(root).items()):
            info = zipfile.ZipInfo(_safe_zip_name(relative), date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())


def validate_package_tree(root: Path) -> dict[str, Any]:
    files = _regular_files(root)
    expected_entries = expected_package_entries()
    if set(files) != expected_entries:
        raise PackageBuildError(
            "package entry set differs: "
            f"missing={sorted(expected_entries - set(files))} "
            f"extra={sorted(set(files) - expected_entries)}"
        )
    for required in (MANIFEST_NAME, INVENTORY_NAME, board_runtime.PROFILE_FILENAME):
        if required not in files:
            raise PackageBuildError(f"package file is missing: {required}")
    try:
        with files[MANIFEST_NAME].open("r", encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream, dialect="excel-tab", strict=True)
            if reader.fieldnames != ["relative_path", "bytes", "sha256"]:
                raise PackageBuildError("package manifest header differs")
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        raise PackageBuildError(f"package manifest is invalid: {exc}") from exc
    listed = {row["relative_path"]: row for row in rows}
    if len(listed) != len(rows):
        raise PackageBuildError("package manifest contains duplicate paths")
    expected = set(files) - {MANIFEST_NAME}
    if set(listed) != expected:
        raise PackageBuildError("package manifest coverage differs")
    for relative, row in listed.items():
        path = files[relative]
        try:
            row_bytes = int(row["bytes"])
        except (TypeError, ValueError) as exc:
            raise PackageBuildError(
                f"package manifest size is invalid: {relative}"
            ) from exc
        if row_bytes != path.stat().st_size or row["sha256"] != sha256_bytes(path.read_bytes()):
            raise PackageBuildError(f"package manifest identity differs: {relative}")

    inventory_rows: dict[str, tuple[int, str]] = {}
    try:
        for line in files[INVENTORY_NAME].read_text(encoding="utf-8").splitlines():
            fields = line.split("\t")
            if len(fields) != 3:
                raise PackageBuildError("package inventory row is malformed")
            relative, raw_bytes, sha256 = fields
            if relative in inventory_rows:
                raise PackageBuildError("package inventory contains duplicate paths")
            inventory_rows[relative] = (int(raw_bytes), sha256)
    except (OSError, UnicodeError, ValueError) as exc:
        raise PackageBuildError(f"package inventory is invalid: {exc}") from exc
    expected_inventory = set(files) - {INVENTORY_NAME, MANIFEST_NAME}
    if set(inventory_rows) != expected_inventory:
        raise PackageBuildError("package inventory coverage differs")
    for relative, (row_bytes, row_sha256) in inventory_rows.items():
        path = files[relative]
        if row_bytes != path.stat().st_size or row_sha256 != sha256_bytes(path.read_bytes()):
            raise PackageBuildError(f"package inventory identity differs: {relative}")
    offline = board_runtime.validate_package(root)
    return {
        "status": "PASS",
        "file_count": len(files),
        "manifest_coverage": len(listed),
        "implementation_profile": offline["implementation_profile"],
        "source_tree": offline["source_tree"],
    }


def validate_package_zip(path: Path) -> dict[str, Any]:
    with zipfile.ZipFile(path, "r") as archive:
        names = [_safe_zip_name(info.filename) for info in archive.infolist()]
        if len(names) != len(set(names)) or len(names) != len({name.casefold() for name in names}):
            raise PackageBuildError("package ZIP contains duplicate paths")
        bad = archive.testzip()
        if bad is not None:
            raise PackageBuildError(f"package ZIP CRC failed: {bad}")
        with tempfile.TemporaryDirectory() as temporary:
            extracted = Path(temporary) / "package"
            extracted.mkdir()
            archive.extractall(extracted)
            tree_result = validate_package_tree(extracted)
    return {
        **tree_result,
        "zip_bytes": path.stat().st_size,
        "zip_sha256": sha256_bytes(path.read_bytes()),
        "zip_full_read": "PASS",
        "zip_crc": "PASS",
        "zip_path_safety": "PASS",
    }


def build_package(
    output: Path,
    repo_root: Path,
    artifact_manifest: Path,
    profile: str,
) -> dict[str, Any]:
    manifest = physical_authority.load_artifact_manifest(
        artifact_manifest, expected_profile=profile
    )
    branch, commit, tree = verify_git_source(repo_root, manifest.source_tree)
    staging = Path(tempfile.mkdtemp(prefix="stage2i-board-package-"))
    try:
        write_result = write_package_tree(
            staging, repo_root, manifest, branch, commit, tree
        )
        validate_package_tree(staging)
        write_deterministic_zip(staging, output)
        validation = validate_package_zip(output)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    return {**write_result, "zip_validation": validation}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--artifact-manifest", type=Path, required=True)
    result.add_argument("--profile", choices=board_runtime.SUPPORTED_PROFILES, required=True)
    result.add_argument("--output", type=Path, required=True)
    result.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        result = build_package(
            args.output.resolve(),
            args.repo_root.resolve(),
            args.artifact_manifest.resolve(),
            args.profile,
        )
    except (
        OSError,
        ValueError,
        json.JSONDecodeError,
        subprocess.CalledProcessError,
        zipfile.BadZipFile,
        PackageBuildError,
        physical_authority.PhysicalAuthorityError,
        board_runtime.Stage2IBoardError,
    ) as exc:
        print(f"FAIL {exc}")
        return 1
    print("PASS " + json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
