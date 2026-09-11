#!/usr/bin/env python3
"""Read-only validation for repository and external project authorities."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable


DEFAULT_CONFIG = Path(__file__).resolve().parents[1] / "docs" / "project" / "external_data_authorities.json"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _expected_kind_matches(path: Path, expected_type: str) -> bool:
    if expected_type == "file":
        return path.is_file()
    if expected_type == "directory":
        return path.is_dir()
    raise ValueError(f"unsupported expected_type: {expected_type}")


def _root_for(authority: dict[str, Any], roots: dict[str, Path]) -> Path:
    scope = authority.get("root_scope", "data")
    if scope not in roots:
        raise ValueError(f"unsupported root_scope: {scope}")
    return roots[scope]


def _run_git(path: Path, *args: str) -> tuple[int, str, str]:
    completed = subprocess.run(
        ["git", "-C", str(path), *args],
        text=True,
        capture_output=True,
        check=False,
    )
    return completed.returncode, completed.stdout.strip(), completed.stderr.strip()


def _check_git_identity(
    logical_id: str, path: Path, expected: dict[str, Any]
) -> tuple[str, str] | None:
    checks = {
        "head": ("rev-parse", "HEAD"),
        "tree": ("rev-parse", "HEAD^{tree}"),
        "branch": ("branch", "--show-current"),
        "origin_main": ("rev-parse", "origin/main"),
    }
    for field, command in checks.items():
        wanted = expected.get(field)
        if wanted is None:
            continue
        code, output, error = _run_git(path, *command)
        if code != 0:
            return "FAIL", f"{logical_id}: Git {field} query failed at {path}: {error}"
        if output != str(wanted):
            return (
                "FAIL",
                f"{logical_id}: Git {field} mismatch at {path}; "
                f"expected={wanted} actual={output}",
            )

    code, output, error = _run_git(path, "remote")
    if code != 0:
        return "FAIL", f"{logical_id}: Git remote query failed at {path}: {error}"
    remotes = [line for line in output.splitlines() if line.strip()]
    expected_remote_count = expected.get("remote_count")
    if expected_remote_count is not None and len(remotes) != int(expected_remote_count):
        return (
            "FAIL",
            f"{logical_id}: Git remote count mismatch at {path}; "
            f"expected={expected_remote_count} actual={len(remotes)}",
        )

    expected_origin_url = expected.get("origin_url")
    if expected_origin_url is not None:
        if "origin" not in remotes:
            return "FAIL", f"{logical_id}: expected origin remote is missing at {path}"
        for label, command in (
            ("fetch", ("remote", "get-url", "origin")),
            ("push", ("remote", "get-url", "--push", "origin")),
        ):
            code, output, error = _run_git(path, *command)
            if code != 0:
                return (
                    "FAIL",
                    f"{logical_id}: Git origin {label} URL query failed at {path}: {error}",
                )
            if output != str(expected_origin_url):
                return (
                    "FAIL",
                    f"{logical_id}: Git origin {label} URL mismatch at {path}; "
                    f"expected={expected_origin_url} actual={output}",
                )

    if bool(expected.get("clean", False)):
        code, output, error = _run_git(path, "status", "--porcelain")
        if code != 0:
            return "FAIL", f"{logical_id}: Git status query failed at {path}: {error}"
        if output:
            return "FAIL", f"{logical_id}: Git worktree is not clean at {path}"
    return None


def _check_json_contract(
    logical_id: str, path: Path, check: dict[str, Any]
) -> tuple[str, str] | None:
    json_path = path / str(check.get("relative_path", ""))
    try:
        with json_path.open("r", encoding="utf-8") as stream:
            payload = json.load(stream)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return "FAIL", f"{logical_id}: JSON contract parse failed at {json_path}: {exc}"
    if not isinstance(payload, dict):
        return "FAIL", f"{logical_id}: JSON contract is not an object: {json_path}"
    expected = check.get("expected", {})
    if not isinstance(expected, dict):
        return "FAIL", f"{logical_id}: JSON expected contract must be an object"
    for key, wanted in expected.items():
        actual = payload.get(str(key))
        if actual != wanted:
            return (
                "FAIL",
                f"{logical_id}: JSON field mismatch at {json_path}; "
                f"field={key} expected={wanted!r} actual={actual!r}",
            )
    return None


def _check_python_verifier(
    logical_id: str, path: Path, check: dict[str, Any]
) -> tuple[str, str] | None:
    verifier = path / str(check.get("relative_path", ""))
    if not verifier.is_file():
        return "FAIL", f"{logical_id}: verifier missing: {verifier}"
    completed = subprocess.run(
        [sys.executable, str(verifier)],
        cwd=path,
        text=True,
        capture_output=True,
        check=False,
    )
    output = (completed.stdout + completed.stderr).strip()
    prefix = str(check.get("expected_output_prefix", "PASS"))
    if completed.returncode != 0 or not output.startswith(prefix):
        return (
            "FAIL",
            f"{logical_id}: verifier failed at {verifier}; "
            f"exit={completed.returncode} output={output}",
        )
    return None


def check_authority(authority: dict[str, Any], roots: dict[str, Path]) -> tuple[str, str]:
    logical_id = str(authority.get("logical_id", "<missing-logical-id>"))
    required = bool(authority.get("required", True))
    try:
        path = _root_for(authority, roots) / str(authority["relative_path"])
        expected_type = str(authority["expected_type"])
    except (KeyError, TypeError, ValueError) as exc:
        return "FAIL", f"{logical_id}: invalid authority entry: {exc}"

    if not path.exists():
        status = "FAIL" if required else "SKIP"
        return status, f"{logical_id}: missing {expected_type}: {path}"
    try:
        if not _expected_kind_matches(path, expected_type):
            return "FAIL", f"{logical_id}: type mismatch at {path}; expected {expected_type}"
    except ValueError as exc:
        return "FAIL", f"{logical_id}: {exc}; path={path}"

    if expected_type == "file":
        expected_bytes = authority.get("bytes_if_immutable")
        expected_sha = authority.get("sha256_if_immutable")
        actual_bytes = path.stat().st_size
        if expected_bytes is not None and actual_bytes != int(expected_bytes):
            return "FAIL", f"{logical_id}: bytes mismatch at {path}; expected={expected_bytes} actual={actual_bytes}"
        if expected_sha is not None:
            actual_sha = sha256_file(path)
            if actual_sha.lower() != str(expected_sha).lower():
                return "FAIL", f"{logical_id}: SHA-256 mismatch at {path}; expected={expected_sha} actual={actual_sha}"

    for marker in authority.get("markers", []):
        marker_path = path / str(marker)
        if not marker_path.exists():
            return "FAIL", f"{logical_id}: required marker missing: {marker_path}"

    for artifact in authority.get("artifact_checks", []):
        artifact_name = str(artifact.get("name", "artifact"))
        artifact_path = path / str(artifact.get("relative_path", ""))
        if not artifact_path.is_file():
            return "FAIL", f"{logical_id}: {artifact_name} missing or not a file: {artifact_path}"
        actual_bytes = artifact_path.stat().st_size
        expected_bytes = artifact.get("bytes")
        if expected_bytes is not None and actual_bytes != int(expected_bytes):
            return "FAIL", f"{logical_id}: {artifact_name} bytes mismatch at {artifact_path}; expected={expected_bytes} actual={actual_bytes}"
        expected_sha = artifact.get("sha256")
        if expected_sha is not None:
            actual_sha = sha256_file(artifact_path)
            if actual_sha.lower() != str(expected_sha).lower():
                return "FAIL", f"{logical_id}: {artifact_name} SHA-256 mismatch at {artifact_path}; expected={expected_sha} actual={actual_sha}"

    git_identity = authority.get("git_identity")
    if git_identity is not None:
        if not isinstance(git_identity, dict):
            return "FAIL", f"{logical_id}: git_identity must be an object"
        result = _check_git_identity(logical_id, path, git_identity)
        if result is not None:
            return result

    for check in authority.get("json_checks", []):
        if not isinstance(check, dict):
            return "FAIL", f"{logical_id}: JSON check must be an object"
        result = _check_json_contract(logical_id, path, check)
        if result is not None:
            return result

    for check in authority.get("python_verifier_checks", []):
        if not isinstance(check, dict):
            return "FAIL", f"{logical_id}: verifier check must be an object"
        result = _check_python_verifier(logical_id, path, check)
        if result is not None:
            return result

    return "PASS", f"{logical_id}: verified {path}"


def run(config_path: Path, data_root: Path | None = None, public_root: Path | None = None) -> int:
    try:
        with config_path.open("r", encoding="utf-8") as stream:
            config = json.load(stream)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"FAIL configuration: {config_path}: {exc}")
        return 2

    if not isinstance(config, dict) or not isinstance(config.get("authorities"), list):
        print(f"FAIL configuration: {config_path}: authorities must be a list")
        return 2

    repository_root = config_path.resolve().parents[2]
    data_env = str(config.get("data_root_env", "CURRENT_SENSING_PROTECTION_IP_DATA_ROOT"))
    public_env = str(config.get("public_root_env", "CURRENT_SENSING_PROTECTION_IP_PUBLIC_ROOT"))
    resolved_data = data_root or Path(os.environ.get(data_env, str(config.get("default_data_root", ""))))
    resolved_public = public_root or Path(os.environ.get(public_env, str(config.get("default_public_root", ""))))
    roots = {"repository": repository_root, "data": resolved_data, "public": resolved_public}

    counts = {"PASS": 0, "FAIL": 0, "SKIP": 0}
    for authority in config["authorities"]:
        if not isinstance(authority, dict):
            status, message = "FAIL", "<missing-logical-id>: authority entry must be an object"
        else:
            status, message = check_authority(authority, roots)
        counts[status] += 1
        print(f"{status} {message}")
    print(f"SUMMARY PASS={counts['PASS']} FAIL={counts['FAIL']} SKIP={counts['SKIP']}")
    return 1 if counts["FAIL"] else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG, help="authority JSON path")
    parser.add_argument("--data-root", type=Path, help="override the external data root")
    parser.add_argument("--public-root", type=Path, help="override the local public repository root")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return run(args.config, args.data_root, args.public_root)


if __name__ == "__main__":
    raise SystemExit(main())
