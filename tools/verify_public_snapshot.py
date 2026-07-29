#!/usr/bin/env python3
"""Self-verifier for the generated public PYNQ-Z2 project snapshot."""

from __future__ import annotations

import csv
import hashlib
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "PUBLIC_SNAPSHOT_MANIFEST.tsv"
PROVENANCE = ROOT / "PUBLIC_SNAPSHOT_PROVENANCE.json"

DEVELOPMENT_COMMIT = "309a84bff651f73891309e02e1d02fc1f54bd3e6"
DEVELOPMENT_TREE = "2f87cd3dd5d41039607e2242ebaa00e0606a1d9f"
RELEASE_COMMIT = "e0f8dfdf481d91edd35b50848c86fa0c484e513d"
RELEASE_TREE = "99ad1db325caed406d23e5966abb1f7305010641"
BOARD_COMMIT = "1a365d5139f963ac4d8f92158dcd2928e86ccf36"
BOARD_TREE = "244cba11579c7fdc39353391ac35a78ede20ec97"
BIT_SHA256 = "f7dd0823e577cfee2aecfa3bf0a48e80d11108bdb12967e567ca64dc2e8ecfab"
HWH_SHA256 = "c97138493f8c4c568790a75bcc77551ad1f24952f6eb28c4238e6bda975b1e29"

PERSISTENT_RUNTIME_SHA256 = {
    "deploy/pynq/runtime/load_current_release.py":
        "524572d183047d14b226b699c33c40099122e2bfaabc9509432e0d9fb8e9b1f1",
    "deploy/pynq/runtime/load_current_release_once.sh":
        "9dd1719a30153b661e00d9459a7de37b247167ae4872b3a7ddf6315aadd3ffa4",
    "deploy/pynq/runtime/verify_installed_release.py":
        "652d7ae31ff17b23cd8216b2bdb99839e48a734f7b526fdbd822a04ec2db41c2",
    "deploy/pynq/systemd/current-sensing-protection-ip-load.service":
        "4aabef5535859ad2e05b6e69109584c84730c352a173c2b364388ab976be5980",
}

DEFERRED_STANDARD_FILES = {
    "LICENSE",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "CITATION.cff",
    "SECURITY.md",
}

FORBIDDEN_DIRECTORY_NAMES = {
    ".runs",
    ".gen",
    ".cache",
    ".ip_user_files",
    "Xil",
    "__pycache__",
    "staging",
    "backup",
    "copy",
    "old",
}

FORBIDDEN_SUFFIXES = {
    ".dcp",
    ".ltx",
    ".vvp",
    ".vcd",
    ".jou",
    ".log",
    ".zip",
    ".tar",
    ".gz",
}

TEXT_SUFFIXES = {
    ".c",
    ".h",
    ".json",
    ".md",
    ".py",
    ".service",
    ".sh",
    ".sv",
    ".tcl",
    ".tsv",
    ".txt",
    ".v",
    ".vh",
    ".xdc",
}

REQUIRED_README_HEADINGS = [
    "Project Overview",
    "Problem Addressed",
    "System Architecture",
    "Main Features",
    "Safety and Clear/Recovery Semantics",
    "Repository Structure",
    "Simulation Reproduction",
    "Vivado Rebuild",
    "PYNQ-Z2 Deployment",
    "Verification Status",
    "Proof Boundary",
    "Development Repository Relationship",
    "Provenance",
    "Known Limitations",
]

MANIFEST_FIELDS = [
    "relative_path",
    "bytes",
    "sha256",
    "component",
    "source_authority",
    "source_relative_path_or_identity",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def ordinary_files(include_manifest: bool = True) -> list[Path]:
    result = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT)
        if ".git" in rel.parts:
            continue
        if not include_manifest and path == MANIFEST:
            continue
        result.append(path)
    return sorted(result, key=relative)


def read_manifest() -> dict[str, dict[str, str]]:
    with MANIFEST.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != MANIFEST_FIELDS:
            raise ValueError(
                "manifest fields mismatch: "
                f"expected={MANIFEST_FIELDS} actual={reader.fieldnames}"
            )
        rows: dict[str, dict[str, str]] = {}
        for row in reader:
            rel = row["relative_path"]
            pure = PurePosixPath(rel)
            if (
                not rel
                or "\\" in rel
                or pure.is_absolute()
                or ".." in pure.parts
                or re.match(r"^[A-Za-z]:", rel)
            ):
                raise ValueError(f"invalid manifest relative path: {rel!r}")
            if rel in rows:
                raise ValueError(f"duplicate manifest path: {rel}")
            rows[rel] = row
        return rows


def check_manifest(errors: list[str]) -> int:
    try:
        rows = read_manifest()
    except (OSError, UnicodeError, csv.Error, ValueError) as exc:
        errors.append(f"manifest parse failed: {exc}")
        return 0

    actual = {relative(path): path for path in ordinary_files(False)}
    if set(rows) != set(actual):
        missing = sorted(set(actual) - set(rows))
        extra = sorted(set(rows) - set(actual))
        errors.append(f"manifest coverage mismatch: missing={missing} extra={extra}")

    for rel, row in rows.items():
        path = actual.get(rel)
        if path is None:
            continue
        try:
            expected_bytes = int(row["bytes"])
        except ValueError:
            errors.append(f"invalid byte count in manifest: {rel}")
            continue
        if expected_bytes != path.stat().st_size:
            errors.append(f"manifest byte mismatch: {rel}")
        if row["sha256"].lower() != sha256_file(path):
            errors.append(f"manifest SHA-256 mismatch: {rel}")
        if not row["component"] or not row["source_authority"]:
            errors.append(f"manifest authority metadata missing: {rel}")
    return len(rows)


def check_provenance(errors: list[str]) -> None:
    try:
        data = json.loads(PROVENANCE.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        errors.append(f"provenance parse failed: {exc}")
        return

    expected = {
        "public_repository_name": "current-sensing-protection-ip-pynq-z2",
        "development_source_commit": DEVELOPMENT_COMMIT,
        "development_source_tree": DEVELOPMENT_TREE,
        "release_source_commit": RELEASE_COMMIT,
        "release_source_tree": RELEASE_TREE,
        "board_validated_runtime_commit": BOARD_COMMIT,
        "board_validated_runtime_tree": BOARD_TREE,
        "bit_sha256": BIT_SHA256,
        "hwh_sha256": HWH_SHA256,
        "target_board": "PYNQ-Z2",
        "pynq_version": "3.1.1",
        "public_repository_remote_status": "NOT_CREATED",
    }
    for key, value in expected.items():
        if data.get(key) != value:
            errors.append(
                f"provenance mismatch for {key}: "
                f"expected={value!r} actual={data.get(key)!r}"
            )
    for key in (
        "public_snapshot_status",
        "local_repository_path",
        "generated_at_utc",
        "development_repository_remote",
        "proof_boundary",
        "included_categories",
        "excluded_categories",
        "deferred_standard_files",
    ):
        if key not in data:
            errors.append(f"provenance field missing: {key}")
    if set(data.get("deferred_standard_files", [])) != DEFERRED_STANDARD_FILES:
        errors.append("provenance deferred_standard_files mismatch")


def check_deploy(errors: list[str]) -> str:
    verifier = ROOT / "deploy" / "tools" / "verify_release.py"
    completed = subprocess.run(
        [sys.executable, str(verifier)],
        cwd=ROOT / "deploy",
        text=True,
        capture_output=True,
        check=False,
    )
    output = (completed.stdout + completed.stderr).strip()
    if completed.returncode != 0 or not output.startswith("PASS "):
        errors.append(
            "deploy release verifier failed: "
            f"exit={completed.returncode} output={output}"
        )
    return output


def check_artifacts(errors: list[str]) -> tuple[int, int]:
    expected = {
        "deploy/pynq/artifacts/protection_system.bit": BIT_SHA256,
        "deploy/pynq/artifacts/protection_system.hwh": HWH_SHA256,
    }
    for rel, digest in expected.items():
        path = ROOT / rel
        if not path.is_file():
            errors.append(f"artifact missing: {rel}")
        elif sha256_file(path) != digest:
            errors.append(f"artifact SHA-256 mismatch: {rel}")

    bit_paths = [path for path in ordinary_files() if path.suffix.lower() == ".bit"]
    hwh_paths = [path for path in ordinary_files() if path.suffix.lower() == ".hwh"]
    if [relative(path) for path in bit_paths] != [
        "deploy/pynq/artifacts/protection_system.bit"
    ]:
        errors.append(f"BIT physical copy mismatch: {[relative(p) for p in bit_paths]}")
    if [relative(path) for path in hwh_paths] != [
        "deploy/pynq/artifacts/protection_system.hwh"
    ]:
        errors.append(f"HWH physical copy mismatch: {[relative(p) for p in hwh_paths]}")
    return len(bit_paths), len(hwh_paths)


def check_runtime(errors: list[str]) -> None:
    for rel, digest in PERSISTENT_RUNTIME_SHA256.items():
        path = ROOT / rel
        if not path.is_file():
            errors.append(f"persistent runtime missing: {rel}")
        elif sha256_file(path) != digest:
            errors.append(f"persistent runtime SHA-256 mismatch: {rel}")


def text_files(errors: list[str]) -> list[tuple[Path, str]]:
    decoded = []
    for path in ordinary_files():
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name != ".gitignore":
            continue
        try:
            decoded.append((path, path.read_text(encoding="utf-8")))
        except (OSError, UnicodeError) as exc:
            errors.append(f"UTF-8 decode failed: {relative(path)}: {exc}")
    return decoded


def check_forbidden(errors: list[str]) -> int:
    findings = []
    for path in ROOT.rglob("*"):
        rel = path.relative_to(ROOT)
        if ".git" in rel.parts:
            continue
        if path.is_dir() and path.name in FORBIDDEN_DIRECTORY_NAMES:
            findings.append(relative(path))
        if path.is_file() and path.suffix.lower() in FORBIDDEN_SUFFIXES:
            findings.append(relative(path))
        if path.is_file() and path.name.lower().endswith((".tmp", ".temp", ".bak", ".swp")):
            findings.append(relative(path))
    for rel in sorted(set(findings)):
        errors.append(f"forbidden content: {rel}")
    for name in DEFERRED_STANDARD_FILES:
        if (ROOT / name).exists():
            errors.append(f"deferred standard file must not exist: {name}")
    return len(set(findings))


def check_credentials_and_stale_paths(
    decoded: list[tuple[Path, str]], errors: list[str]
) -> tuple[int, int]:
    credential_patterns = [
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
        re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
        re.compile(
            r"(?i)\b(?:password|passwd|api[_-]?key|access[_-]?token|secret)"
            r"\s*[:=]\s*[\"'][^\"']{4,}[\"']"
        ),
    ]
    stale_patterns = [
        re.compile(r"(?i)D:[/\\]current-sensing-protection-ip-release"),
        re.compile(r"(?i)D:[/\\]surf(?:[/\\]|\s)"),
        re.compile(r"(?i)C:[/\\]Users[/\\]"),
        re.compile(r"(?i)/home/[^/\\\s]+/"),
    ]
    credential_findings = 0
    stale_findings = 0
    for path, text in decoded:
        rel = relative(path)
        if rel != "tools/verify_public_snapshot.py":
            for pattern in credential_patterns:
                if pattern.search(text):
                    credential_findings += 1
                    errors.append(f"credential finding: {rel}: {pattern.pattern}")
        # The immutable deploy subtree is checked by its original verifier,
        # whose board-side paths are part of the release contract.
        if rel != "tools/verify_public_snapshot.py" and not rel.startswith("deploy/"):
            for pattern in stale_patterns:
                if pattern.search(text):
                    stale_findings += 1
                    errors.append(f"stale absolute path: {rel}: {pattern.pattern}")
    return credential_findings, stale_findings


def check_duplicates(errors: list[str]) -> int:
    groups: dict[tuple[int, str], list[str]] = defaultdict(list)
    for path in ordinary_files():
        size = path.stat().st_size
        if size == 0:
            continue
        groups[(size, sha256_file(path))].append(relative(path))
    duplicates = [paths for paths in groups.values() if len(paths) > 1]
    for paths in duplicates:
        errors.append(f"duplicate non-empty file group: {sorted(paths)}")
    return len(duplicates)


def check_markdown_links(
    decoded: list[tuple[Path, str]], errors: list[str]
) -> int:
    findings = 0
    link_pattern = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
    for path, text in decoded:
        if path.suffix.lower() != ".md":
            continue
        for target in link_pattern.findall(text):
            target = target.strip().split()[0].strip("<>")
            if (
                not target
                or target.startswith("#")
                or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target)
            ):
                continue
            target_path = target.split("#", 1)[0]
            resolved = (path.parent / target_path).resolve()
            try:
                resolved.relative_to(ROOT.resolve())
            except ValueError:
                findings += 1
                errors.append(f"Markdown link escapes repository: {relative(path)} -> {target}")
                continue
            if not resolved.exists():
                findings += 1
                errors.append(f"Markdown link missing: {relative(path)} -> {target}")
    return findings


def check_json_tsv(errors: list[str]) -> None:
    for path in ordinary_files():
        if path.suffix.lower() == ".json":
            try:
                json.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, json.JSONDecodeError) as exc:
                errors.append(f"JSON strict parse failed: {relative(path)}: {exc}")
        elif path.suffix.lower() == ".tsv":
            try:
                with path.open("r", encoding="utf-8", newline="") as stream:
                    rows = list(csv.reader(stream, delimiter="\t"))
                if not rows or not rows[0]:
                    raise ValueError("empty TSV")
                width = len(rows[0])
                if any(len(row) != width for row in rows):
                    raise ValueError("inconsistent TSV field count")
            except (OSError, UnicodeError, csv.Error, ValueError) as exc:
                errors.append(f"TSV strict parse failed: {relative(path)}: {exc}")


def check_readme_and_scope(errors: list[str]) -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    for heading in REQUIRED_README_HEADINGS:
        if f"## {heading}" not in readme:
            errors.append(f"README section missing: {heading}")
    scope = (ROOT / "PUBLIC_SNAPSHOT_SCOPE.md").read_text(encoding="utf-8")
    if "These files are deferred for a later public-governance step." not in scope:
        errors.append("deferred standard-file statement missing from scope")
    proof = (
        readme
        + (ROOT / "docs" / "clear_recovery_semantics.md").read_text(encoding="utf-8")
        + (ROOT / "docs" / "proof_boundary.md").read_text(encoding="utf-8")
    ).casefold()
    required_phrases = [
        "live fault prevents false recovery",
        "clear is a recovery request",
        "fault removal and clear are separate actions",
        "clear-only does not automatically enable pwm",
        "ctrl value 0x2",
        "ctrl value 0x3",
        "status value 0x3",
        "sensor history",
        "one real pynq-z2 cold boot autoload",
        "does not prove repeated cold boots",
    ]
    for phrase in required_phrases:
        if phrase not in proof:
            errors.append(f"proof-boundary phrase missing: {phrase}")


def check_git_remote(errors: list[str]) -> int:
    git_dir = ROOT / ".git"
    if not git_dir.exists():
        return 0
    completed = subprocess.run(
        ["git", "-C", str(ROOT), "remote"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        errors.append(f"cannot inspect public Git remotes: {completed.stderr.strip()}")
        return -1
    remotes = [line for line in completed.stdout.splitlines() if line.strip()]
    if remotes:
        errors.append(f"public Git remote must be absent: {remotes}")
    return len(remotes)


def main() -> int:
    errors: list[str] = []
    manifest_rows = check_manifest(errors)
    check_provenance(errors)
    deploy_output = check_deploy(errors)
    bit_count, hwh_count = check_artifacts(errors)
    check_runtime(errors)
    decoded = text_files(errors)
    forbidden_findings = check_forbidden(errors)
    credential_findings, stale_paths = check_credentials_and_stale_paths(
        decoded, errors
    )
    duplicate_groups = check_duplicates(errors)
    markdown_findings = check_markdown_links(decoded, errors)
    check_json_tsv(errors)
    check_readme_and_scope(errors)
    remote_count = check_git_remote(errors)

    summary = {
        "status": "FAIL" if errors else "PASS",
        "manifest_rows": manifest_rows,
        "bit_copy_count": bit_count,
        "hwh_copy_count": hwh_count,
        "duplicate_nonempty_groups": duplicate_groups,
        "credential_findings": credential_findings,
        "stale_absolute_paths": stale_paths,
        "forbidden_content_findings": forbidden_findings,
        "markdown_link_findings": markdown_findings,
        "public_remote_count": remote_count,
        "deploy_verifier": deploy_output,
    }
    if errors:
        for error in errors:
            print(f"FAIL {error}")
        print("FAIL " + json.dumps(summary, sort_keys=True))
        return 1
    print("PASS " + json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
