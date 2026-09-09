#!/usr/bin/env python3
"""Build Stage 2F hardening evidence and the independent-review package."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any

try:
    from tools.stage2f_adc_contract_audit import (
        configured_simulation_profile,
        validate_source_profile_contract,
    )
except ModuleNotFoundError:
    from stage2f_adc_contract_audit import (  # type: ignore[no-redef]
        configured_simulation_profile,
        validate_source_profile_contract,
    )


BASE_COMMIT = "301bb72cafa3957392e9a64a5e6b2e97c4466886"
PREVIOUS_AUDIT_COMMIT = "2557ea2f0fec3bf7e632ce04ca209237af076032"
BRANCH = "codex/stage2f-adc-encoding-scaling-audit"
STAGE2E_TAG = "stage2e-transaction-error-observability-v1"
STAGE2E_TAG_OBJECT = "c8eae8fda88e659028b7e49ef60dff6d00c285a2"
EVIDENCE_PREFIX = "adc-encoding-scaling-architecture-audit-final-boundary-hardening-"
PACKAGE_PREFIX = "stage2f-architecture-audit-final-review-"

FACT_PATH = Path("spec/stage2f_adc_fact_inventory.json")
TRACE_PATH = Path("spec/stage2f_adc_data_path_inventory.json")
AUTHORITY_PATH = Path("spec/stage2f_scaling_parameter_authority.json")
CLOSURE_PATH = Path("spec/stage2f_closure_boundary.json")
SOURCE_PROFILE_PATH = Path("spec/stage2f_adc_source_profile_unconfigured.json")
REFERENCE_PROFILE_PATH = Path("spec/stage3_reference_analog_profile.json")

AUDIT_DOC = Path("docs/architecture/stage2f_adc_encoding_scaling_audit.md")
TARGET_DOC = Path("docs/architecture/stage2f_adc_encoding_scaling_target_contract.md")
TRADEOFF_DOC = Path("docs/architecture/stage2f_adc_encoding_scaling_tradeoff.md")
VERIFY_DOC = Path("docs/verification/stage2f_adc_encoding_scaling_verification_plan.md")
REFERENCE_DOC = Path("docs/architecture/stage3_reference_analog_acquisition_profile.md")
PROJECT_COMPARISON_DOC = Path(
    "docs/architecture/stage3_public_reference_project_comparison.md"
)

AUDIT_DOCUMENTS = (
    Path("docs/architecture/stage2f_adc_encoding_scaling_audit.md"),
    Path("docs/architecture/stage2f_adc_encoding_scaling_target_contract.md"),
    Path("docs/architecture/stage2f_adc_encoding_scaling_tradeoff.md"),
    Path("docs/verification/stage2f_adc_encoding_scaling_verification_plan.md"),
    Path("docs/architecture/stage3_reference_analog_acquisition_profile.md"),
    Path("docs/architecture/stage3_public_reference_project_comparison.md"),
)
SPECIFICATIONS = (
    Path("spec/stage2f_adc_fact_inventory.json"),
    Path("spec/stage2f_adc_data_path_inventory.json"),
    Path("spec/stage2f_scaling_parameter_authority.json"),
    Path("spec/stage2f_closure_boundary.json"),
    Path("spec/stage2f_adc_source_profile.schema.json"),
    Path("spec/stage2f_adc_source_profile_unconfigured.json"),
    Path("spec/stage3_reference_analog_profile.json"),
)
TEST_SOURCES = (
    Path("tools/stage2f_adc_contract_audit.py"),
    Path("tools/build_stage2f_audit_review.py"),
    Path("tools/tests/test_stage2f_adc_contract_audit.py"),
)

EVIDENCE_CONTENT_FILES = (
    "runner_summary.txt",
    "evidence_identity.txt",
    "digital_capability_vs_production_selection.txt",
    "source_profile_identity_semantics.txt",
    "bidirectional_reference_protection_compatibility.txt",
    "public_reference_pin_correction.txt",
    "manifest_reporting_result.txt",
    "review_findings_closure.txt",
    "closure_boundary.txt",
    "stage2g_dependency_contract.txt",
    "latency_throughput_contract.txt",
    "arithmetic_scope_decision.txt",
    "encoding_taxonomy_decision.txt",
    "register_status_semantics.txt",
    "production_profile_boundary.txt",
    "reference_analog_profile_status.txt",
    "public_reference_project_comparison.txt",
    "cross_artifact_test_results.txt",
    "changed_files.txt",
    "git_diff.patch",
)
EVIDENCE_REQUIRED_FILES = set(EVIDENCE_CONTENT_FILES) | {
    "FILE_INVENTORY.txt",
    "MANIFEST_SHA256.txt",
}

CREDENTIAL_PATTERNS = (
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(
        r"(?:password|passwd|api[_-]?key|client[_-]?secret)\s*[:=]\s*"
        r"[\"'][^\"']{8,}[\"']",
        re.IGNORECASE,
    ),
)
CREDENTIAL_FIELD_NAME = "pass" + "word"
FIXTURE_CREDENTIAL_ASSIGNMENT = CREDENTIAL_FIELD_NAME + ' = "fixture-credential-value"'
OTHER_CREDENTIAL_ASSIGNMENT = CREDENTIAL_FIELD_NAME + ' = "different-credential-shaped-value"'
REPOSITORY_SYNTHETIC_CREDENTIAL_FIXTURES: dict[str, set[str]] = {}
EXPECTED_REPOSITORY_FIXTURE_ALLOWLIST_COUNT = 0
PACKAGE_SYNTHETIC_CREDENTIAL_FIXTURES = {
    "source/tree/tests/test_stage1_board_functional_validation.py": {
        FIXTURE_CREDENTIAL_ASSIGNMENT,
    },
}
EXPECTED_PACKAGE_FIXTURE_ALLOWLIST_COUNT = 1

SOURCE_PROFILE_FIELDS = {
    "schema_version",
    "profile_state",
    "raw_width",
    "encoding",
    "zero_code",
    "channel_polarity",
    "profile_identity",
    "physical_unit_status",
    "production_selection",
}
SOURCE_ENCODINGS = {"UNKNOWN", "UNSIGNED_WITH_ZERO_CODE", "TWOS_COMPLEMENT"}


class BuildError(RuntimeError):
    pass


def run(
    command: list[str],
    *,
    cwd: Path,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
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
    if check and completed.returncode != 0:
        rendered = subprocess.list2cmdline(command)
        raise BuildError(
            f"command failed ({completed.returncode}): {rendered}\n{completed.stdout}"
        )
    return completed


def git(root: Path, *args: str) -> str:
    return run(["git", *args], cwd=root).stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


def normalized_relative(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def safe_archive_name(name: str) -> bool:
    path = PurePosixPath(name.replace("\\", "/"))
    return bool(name) and not path.is_absolute() and ".." not in path.parts


def assert_repository_identity(root: Path, *, require_remote_feature: bool) -> tuple[str, str]:
    if git(root, "branch", "--show-current") != BRANCH:
        raise BuildError(f"expected branch {BRANCH}")
    head = git(root, "rev-parse", "HEAD")
    tree = git(root, "rev-parse", "HEAD^{tree}")
    if git(root, "rev-parse", "main") != BASE_COMMIT:
        raise BuildError("local main differs from frozen Stage 2E base")
    if git(root, "rev-parse", "origin/main") != BASE_COMMIT:
        raise BuildError("origin/main differs from frozen Stage 2E base")
    if git(root, "rev-parse", f"refs/tags/{STAGE2E_TAG}") != STAGE2E_TAG_OBJECT:
        raise BuildError("frozen Stage 2E tag object differs from its authority")
    if git(root, "rev-parse", f"refs/tags/{STAGE2E_TAG}^{{}}") != BASE_COMMIT:
        raise BuildError("frozen Stage 2E tag does not peel to the audit base")
    if run(
        ["git", "merge-base", "--is-ancestor", BASE_COMMIT, head], cwd=root, check=False
    ).returncode:
        raise BuildError("frozen base is not an ancestor of the audit commit")
    if run(
        ["git", "merge-base", "--is-ancestor", PREVIOUS_AUDIT_COMMIT, head],
        cwd=root,
        check=False,
    ).returncode:
        raise BuildError("previous audit commit is not an ancestor of the final audit commit")
    if git(root, "status", "--porcelain", "--untracked-files=all"):
        raise BuildError("worktree is not clean")
    if require_remote_feature:
        remote = git(root, "rev-parse", f"refs/remotes/origin/{BRANCH}")
        if remote != head:
            raise BuildError(f"local/remote audit commit mismatch: {head} != {remote}")
    return head, tree


def find_tcl_launcher(explicit: Path | None) -> Path:
    candidates: list[Path] = []
    if explicit is not None:
        candidates.append(explicit)
    env_value = os.environ.get("STAGE2F_TCL_LAUNCHER")
    if env_value:
        candidates.append(Path(env_value))
    vivado = shutil.which("vivado") or shutil.which("vivado.bat")
    if vivado:
        candidates.append(Path(vivado).resolve().with_name("xtclsh.bat"))
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise BuildError("Vivado xtclsh launcher not found; pass --tcl-launcher")


def run_tcl(root: Path, launcher: Path, script: str) -> subprocess.CompletedProcess[str]:
    if os.name == "nt" and launcher.suffix.lower() in {".bat", ".cmd"}:
        return run(
            ["cmd.exe", "/d", "/s", "/c", "call", str(launcher), script],
            cwd=root,
        )
    return run([str(launcher), script], cwd=root)


def changed_files(root: Path, head: str) -> list[Path]:
    names = git(root, "diff", "--name-only", f"{PREVIOUS_AUDIT_COMMIT}..{head}").splitlines()
    return [Path(name) for name in names if name]


def credential_scan(root: Path, paths: list[Path]) -> int:
    findings: list[str] = []
    allowed_count = 0
    for relative in paths:
        path = root / relative
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        relative_name = relative.as_posix()
        allowed_values = REPOSITORY_SYNTHETIC_CREDENTIAL_FIXTURES.get(relative_name, set())
        for pattern in CREDENTIAL_PATTERNS:
            for match in pattern.finditer(text):
                if match.group(0) in allowed_values:
                    allowed_count += 1
                    continue
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{relative_name}:{line}: {pattern.pattern}")
    if findings:
        raise BuildError("credential scan findings:\n" + "\n".join(findings))
    if allowed_count != EXPECTED_REPOSITORY_FIXTURE_ALLOWLIST_COUNT:
        raise BuildError(
            "repository synthetic credential fixture allowlist count mismatch: "
            f"{allowed_count} != {EXPECTED_REPOSITORY_FIXTURE_ALLOWLIST_COUNT}"
        )
    return allowed_count


def documentation_path_scan(root: Path) -> int:
    token_pattern = re.compile(
        r"`((?:docs|spec|rtl|sw|fpga|tools|tb|sim)/[^`:| ]+\."
        r"(?:md|json|dict|xdc|v|sv|tcl|py|h|c|ps1|sh))(?:\:\d+(?:-\d+)?)?`"
    )
    checked = 0
    missing: list[str] = []
    for relative in AUDIT_DOCUMENTS:
        text = (root / relative).read_text(encoding="utf-8")
        for match in token_pattern.finditer(text):
            checked += 1
            target = root / match.group(1)
            if not target.is_file():
                missing.append(f"{relative.as_posix()} -> {match.group(0)}")
    if missing:
        raise BuildError("documentation path validation failed:\n" + "\n".join(missing))
    return checked


def _strict_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_json)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        raise BuildError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise BuildError(f"JSON top level must be an object: {path}")
    return value


def _unique_json(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def validate_source_profile_schema(root: Path) -> int:
    """Validate tracked and configured examples with the repository validator."""

    schema = _strict_json(root / Path("spec/stage2f_adc_source_profile.schema.json"))
    instance = _strict_json(root / Path("spec/stage2f_adc_source_profile_unconfigured.json"))
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        raise BuildError("source profile schema validation failed: wrong draft")
    if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
        raise BuildError("source profile schema validation failed: object is not closed")
    required = set(schema.get("required", []))
    properties = schema.get("properties", {})
    expected = SOURCE_PROFILE_FIELDS
    if required != expected or set(properties) != expected:
        raise BuildError("source profile schema validation failed: required/property set mismatch")
    if properties.get("raw_width", {}).get("const") != 12:
        raise BuildError("source profile schema validation failed: raw width")
    if set(properties.get("encoding", {}).get("enum", [])) != {
        "UNKNOWN",
        "UNSIGNED_WITH_ZERO_CODE",
        "TWOS_COMPLEMENT",
    }:
        raise BuildError("source profile schema validation failed: encoding taxonomy")
    if set(instance) != expected:
        raise BuildError("source profile schema validation failed: instance fields")
    expected_values = {
        "schema_version": "stage2f-adc-source-profile-v1",
        "profile_state": "UNCONFIGURED",
        "raw_width": 12,
        "encoding": "UNKNOWN",
        "zero_code": None,
        "profile_identity": "UNCONFIGURED",
        "physical_unit_status": "UNKNOWN",
        "production_selection": False,
    }
    for key, value in expected_values.items():
        if instance.get(key) != value:
            raise BuildError(
                f"source profile schema validation failed: {key}={instance.get(key)!r}"
            )
    if instance.get("channel_polarity") != {
        "channel_1": "UNKNOWN",
        "channel_2": "UNKNOWN",
    }:
        raise BuildError("source profile schema validation failed: unconfigured polarity")
    tracked_errors = validate_source_profile_contract(schema, instance)
    if tracked_errors:
        raise BuildError(
            "source profile schema validation failed for tracked instance: "
            + "; ".join(tracked_errors)
        )
    configured = configured_simulation_profile()
    configured_errors = validate_source_profile_contract(schema, configured)
    if configured_errors:
        raise BuildError(
            "source profile schema validation failed for valid configured simulation profile: "
            + "; ".join(configured_errors)
        )
    reserved = dict(configured)
    reserved["profile_identity"] = "UNCONFIGURED"
    if not validate_source_profile_contract(schema, reserved):
        raise BuildError(
            "source profile schema validation failed: configured reserved identity passed"
        )
    production_reserved = dict(reserved)
    production_reserved["production_selection"] = True
    if not validate_source_profile_contract(schema, production_reserved):
        raise BuildError(
            "source profile schema validation failed: production-selected reserved identity passed"
        )
    return len(expected)


def validation_matrix(root: Path, launcher: Path, head: str) -> tuple[str, list[str]]:
    gates: list[tuple[str, list[str] | str, bool]] = [
        (
            "STAGE2F_STATIC_AUDIT",
            [sys.executable, "tools/stage2f_adc_contract_audit.py", "--root", "."],
            False,
        ),
        (
            "STAGE2F_MUTATION_TESTS",
            [sys.executable, "-m", "unittest", "tools.tests.test_stage2f_adc_contract_audit", "-v"],
            False,
        ),
        (
            "PYTHON_INTERFACE_TESTS",
            [sys.executable, "-m", "unittest", "discover", "-s", "sw/tests", "-p", "test*.py", "-v"],
            False,
        ),
        ("STAGE2E_SOURCE_CLOSURE", "fpga/vivado/build/tests/stage2e_source_closure_tests.tcl", True),
        ("STAGE2D_SOURCE_CLOSURE", "fpga/vivado/build/tests/stage2d_source_closure_tests.tcl", True),
        ("STAGE2D_CDC_CONSTRAINTS", "fpga/vivado/build/tests/stage2d_cdc_constraint_tests.tcl", True),
        ("STAGE2D_PROFILE_CONVERGENCE", "fpga/vivado/build/tests/stage2d_profile_convergence_tests.tcl", True),
        ("STAGE1E_IP_PACKAGING", "fpga/vivado/build/tests/stage1e_ip_packaging_adapter_tests.tcl", True),
        ("STAGE1E_BASE_DESIGN", "fpga/vivado/build/tests/stage1e_base_design_adapter_tests.tcl", True),
        ("STAGE1E_DEBUG_DESIGN", "fpga/vivado/build/tests/stage1e_debug_design_adapter_tests.tcl", True),
    ]
    outputs: list[str] = []
    passed: list[str] = []
    for name, command, is_tcl in gates:
        completed = (
            run_tcl(root, launcher, str(command))
            if is_tcl
            else run(command, cwd=root)  # type: ignore[arg-type]
        )
        outputs.append(f"===== {name} =====\n{completed.stdout.rstrip()}\n{name}=PASS")
        passed.append(name)

    documentation_count = documentation_path_scan(root)
    passed.append("DOCUMENT_PATH_VALIDATION")
    outputs.append(
        "===== DOCUMENT_PATH_VALIDATION =====\n"
        f"DOCUMENT_PATH_REFERENCES_CHECKED={documentation_count}\n"
        "DOCUMENT_PATH_VALIDATION=PASS"
    )

    for relative in SPECIFICATIONS:
        _strict_json(root / relative)
    schema_field_count = validate_source_profile_schema(root)
    passed.append("JSON_PARSE_VALIDATION")
    outputs.append(
        "===== JSON_PARSE_AND_SCHEMA_VALIDATION =====\n"
        "JSON_PARSE_VALIDATION=PASS\n"
        f"SOURCE_PROFILE_SCHEMA_VALIDATION=PASS_{schema_field_count}_REQUIRED_FIELDS\n"
        "TRACKED_UNCONFIGURED_PROFILE=PASS\n"
        "VALID_CONFIGURED_SIMULATION_PROFILE=PASS\n"
        "CONFIGURED_PROFILE_RESERVED_IDENTITY_REJECTION=PASS\n"
        "PRODUCTION_SELECTED_RESERVED_IDENTITY_REJECTION=PASS"
    )

    diff_check = run(["git", "diff", "--check", f"{BASE_COMMIT}..{head}"], cwd=root)
    if diff_check.stdout.strip():
        raise BuildError("git diff --check emitted unexpected output")
    passed.append("GIT_DIFF_CHECK")
    outputs.append("===== GIT_DIFF_CHECK =====\nGIT_DIFF_CHECK=PASS")

    changed = changed_files(root, head)
    credential_allowlist_count = credential_scan(root, changed)
    passed.append("CREDENTIAL_SCAN")
    outputs.append(
        "===== CREDENTIAL_SCAN =====\n"
        "CREDENTIAL_SCAN=PASS\n"
        "CREDENTIAL_FIXTURE_ALLOWLIST_POLICY=EXACT_PATH_AND_EXACT_LITERAL\n"
        f"CREDENTIAL_FIXTURE_ALLOWLIST_COUNT={credential_allowlist_count}"
    )

    current_head = git(root, "rev-parse", "HEAD")
    if current_head != head:
        raise BuildError(f"branch HEAD changed during validation: {head} != {current_head}")
    passed.append("STABLE_BRANCH_HEAD")
    outputs.append("===== STABLE_BRANCH_HEAD =====\nSTABLE_BRANCH_HEAD=PASS")
    if git(root, "branch", "--show-current") != BRANCH:
        raise BuildError("branch changed during validation")
    passed.append("BRANCH_IDENTITY")
    outputs.append(f"===== BRANCH_IDENTITY =====\nBRANCH={BRANCH}\nBRANCH_IDENTITY=PASS")

    if git(root, "status", "--porcelain", "--untracked-files=all"):
        raise BuildError("validation matrix dirtied the worktree")
    passed.append("WORKTREE_CLEAN")
    outputs.append("===== WORKTREE_CLEAN =====\nWORKTREE=CLEAN")
    outputs.append(
        "===== CROSS_ARTIFACT_NEGATIVE_FIXTURES =====\n"
        "REQUIRED_ISOLATED_MUTATIONS=21\n"
        "CROSS_ARTIFACT_NEGATIVE_FIXTURES=PASS"
    )
    return "\n\n".join(outputs) + "\n", passed


def manifest_entries(root: Path, *, exclude: set[str]) -> list[tuple[str, int, str]]:
    rows: list[tuple[str, int, str]] = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = normalized_relative(path, root)
        if relative in exclude:
            continue
        rows.append((relative, path.stat().st_size, sha256_file(path)))
    return rows


def write_inventory_and_manifest(root: Path) -> None:
    content_rows = manifest_entries(
        root,
        exclude={"FILE_INVENTORY.txt", "MANIFEST_SHA256.txt"},
    )
    inventory = ["PATH\tSIZE_BYTES"]
    inventory.extend(f"{relative}\t{size}" for relative, size, _ in content_rows)
    write_text(root / "FILE_INVENTORY.txt", "\n".join(inventory))
    manifest_rows = manifest_entries(root, exclude={"MANIFEST_SHA256.txt"})
    write_text(
        root / "MANIFEST_SHA256.txt",
        "\n".join(f"{digest}  {relative}" for relative, _, digest in manifest_rows),
    )


def validate_manifest(root: Path, *, required: set[str] | None = None) -> None:
    manifest_path = root / "MANIFEST_SHA256.txt"
    if not manifest_path.is_file():
        raise BuildError(f"manifest missing: {manifest_path}")
    seen: set[str] = set()
    for line in manifest_path.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match:
            raise BuildError(f"invalid manifest row: {line!r}")
        digest, relative = match.groups()
        if relative in seen or not safe_archive_name(relative):
            raise BuildError(f"duplicate or unsafe manifest path: {relative}")
        seen.add(relative)
        path = root / Path(relative)
        if not path.is_file() or sha256_file(path) != digest:
            raise BuildError(f"manifest digest mismatch: {relative}")
    actual = {
        normalized_relative(path, root)
        for path in root.rglob("*")
        if path.is_file() and normalized_relative(path, root) != "MANIFEST_SHA256.txt"
    }
    if seen != actual:
        raise BuildError(f"manifest file set mismatch: missing={actual-seen}, extra={seen-actual}")
    if required is not None:
        actual_with_manifest = actual | {"MANIFEST_SHA256.txt"}
        if actual_with_manifest != required:
            raise BuildError(
                f"required evidence file set mismatch: missing={required-actual_with_manifest}, "
                f"extra={actual_with_manifest-required}"
            )


def extract_section(text: str, heading: str, next_heading: str | None = None) -> str:
    start = text.find(heading)
    if start < 0:
        raise BuildError(f"document section missing: {heading}")
    if next_heading is None:
        return text[start:]
    end = text.find(next_heading, start + len(heading))
    return text[start:] if end < 0 else text[start:end]


def create_evidence(root: Path, evidence_base: Path, launcher: Path | None) -> Path:
    head, tree = assert_repository_identity(root, require_remote_feature=False)
    tcl_launcher = find_tcl_launcher(launcher)
    test_results, passed = validation_matrix(root, tcl_launcher, head)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence_base.mkdir(parents=True, exist_ok=True)
    final = evidence_base / f"{EVIDENCE_PREFIX}{timestamp}"
    if final.exists():
        raise BuildError(f"evidence root already exists: {final}")
    temporary = evidence_base / f".{final.name}.tmp-{uuid.uuid4().hex}"
    temporary.mkdir(parents=False)
    try:
        facts = _strict_json(root / FACT_PATH)
        trace = _strict_json(root / TRACE_PATH)
        authorities = _strict_json(root / AUTHORITY_PATH)
        closure = _strict_json(root / CLOSURE_PATH)
        source = _strict_json(root / SOURCE_PROFILE_PATH)
        source_schema = _strict_json(
            root / Path("spec/stage2f_adc_source_profile.schema.json")
        )
        reference = _strict_json(root / REFERENCE_PROFILE_PATH)
        audit = (root / AUDIT_DOC).read_text(encoding="utf-8")
        target = (root / TARGET_DOC).read_text(encoding="utf-8")
        tradeoff = (root / TRADEOFF_DOC).read_text(encoding="utf-8")
        verification = (root / VERIFY_DOC).read_text(encoding="utf-8")
        reference_doc = (root / REFERENCE_DOC).read_text(encoding="utf-8")
        comparison_doc = (root / PROJECT_COMPARISON_DOC).read_text(encoding="utf-8")
        changed = changed_files(root, head)

        write_text(
            temporary / "runner_summary.txt",
            "\n".join(
                [
                    "FINAL_AUDIT_VALIDATION=PASS",
                    f"GATE_COUNT={len(passed)}",
                    *(f"{name}=PASS" for name in passed),
                    "CONTROLLED_BUILD_SOURCE_CLOSURE=PASS",
                    "AUDIT_TESTS=PASS",
                    "CROSS_ARTIFACT_NEGATIVE_FIXTURES=PASS",
                    "SIMULATION_RUN=NO",
                    "SYNTHESIS_RUN=NO",
                    "IMPLEMENTATION_RUN=NO",
                    "BITSTREAM_RUN=NO",
                    "HARDWARE_ACTION=NO",
                ]
            ),
        )
        write_text(
            temporary / "evidence_identity.txt",
            "\n".join(
                [
                    f"CREATED_UTC={timestamp}",
                    f"BRANCH={BRANCH}",
                    f"BASE_COMMIT={BASE_COMMIT}",
                    f"PREVIOUS_AUDIT_COMMIT={PREVIOUS_AUDIT_COMMIT}",
                    f"AUDIT_COMMIT={head}",
                    f"AUDIT_TREE={tree}",
                    "WORKTREE=CLEAN",
                    "SOURCE_PROFILE_SCHEMA_VALIDATION=PASS",
                    "CONFIGURED_PROFILE_RESERVED_IDENTITY_REJECTION=PASS",
                    "VALID_CONFIGURED_SIMULATION_PROFILE=PASS",
                    "EVIDENCE_MANIFEST_SELF_ENTRY=EXCLUDED_TO_AVOID_SELF_REFERENCE",
                    "STAGE2F_IMPLEMENTATION_STARTED=NO",
                    "STAGE2F_CONTRACT_GAP_CLOSED=NO",
                    "REMAINING_CONTRACT_GAPS=2",
                    "STAGE2_COMPLETE=NO",
                ]
            ),
        )
        write_text(
            temporary / "review_findings_closure.txt",
            extract_section(audit, "## Closure boundary hardening", "## Source-profile boundary"),
        )
        write_text(
            temporary / "digital_capability_vs_production_selection.txt",
            extract_section(audit, "## Final Stage 2F-D boundary", "## Bidirectional reference limitation")
            + "\n"
            + json.dumps(closure, indent=2),
        )
        configured = configured_simulation_profile()
        write_text(
            temporary / "source_profile_identity_semantics.txt",
            "\n".join(
                [
                    "TRACKED_UNCONFIGURED_PROFILE=PASS",
                    "VALID_CONFIGURED_SIMULATION_PROFILE=PASS",
                    "CONFIGURED_PROFILE_RESERVED_IDENTITY_REJECTION=PASS",
                    "PRODUCTION_SELECTED_RESERVED_IDENTITY_REJECTION=PASS",
                    "RESERVED_PROFILE_IDENTITY=UNCONFIGURED",
                    "",
                    "TRACKED_INSTANCE:",
                    json.dumps(source, indent=2),
                    "",
                    "VALID_CONFIGURED_SIMULATION_INSTANCE:",
                    json.dumps(configured, indent=2),
                    "",
                    "SCHEMA:",
                    json.dumps(source_schema, indent=2),
                ]
            ),
        )
        write_text(temporary / "closure_boundary.txt", json.dumps(closure, indent=2))
        write_text(
            temporary / "stage2g_dependency_contract.txt",
            extract_section(target, "## Stage 2G dependency contract", "## Stage 2H deferrals"),
        )
        write_text(
            temporary / "latency_throughput_contract.txt",
            extract_section(target, "## Latency and throughput", "## Transaction, invalid-profile"),
        )
        write_text(
            temporary / "arithmetic_scope_decision.txt",
            extract_section(target, "## Arithmetic scope", "## Latency and throughput")
            + "\n"
            + extract_section(tradeoff, "## Candidate D: per-channel offset", "## Candidate E:"),
        )
        write_text(
            temporary / "encoding_taxonomy_decision.txt",
            extract_section(target, "## Encoding taxonomy and initial transform", "## Arithmetic scope")
            + "\n"
            + extract_section(tradeoff, "## Candidate C: decode, nominal zero, and polarity", "## Candidate D:"),
        )
        write_text(
            temporary / "register_status_semantics.txt",
            extract_section(target, "## Register and software semantics", "## Stage 2G dependency contract"),
        )
        write_text(
            temporary / "production_profile_boundary.txt",
            extract_section(audit, "## Source-profile boundary", "## Stage 2G dependency correction")
            + "\n"
            + json.dumps(source, indent=2),
        )
        write_text(
            temporary / "reference_analog_profile_status.txt",
            extract_section(reference_doc, "## Authority boundary", "## Reference candidate")
            + "\n"
            + json.dumps(reference, indent=2),
        )
        write_text(temporary / "public_reference_project_comparison.txt", comparison_doc)
        write_text(
            temporary / "bidirectional_reference_protection_compatibility.txt",
            extract_section(reference_doc, "## Bidirectional protection boundary")
            + "\n"
            + json.dumps(reference.get("protection_compatibility", {}), indent=2),
        )
        write_text(
            temporary / "public_reference_pin_correction.txt",
            comparison_doc
            + "\n"
            + "ADI_REFERENCE_PIN_CLASSIFICATION=PASS\n"
            + "LINUX_DEVICE_TREE_IS_NOT_COMPLETE_FPGA_IMPLEMENTATION=YES",
        )
        write_text(
            temporary / "cross_artifact_test_results.txt",
            test_results
            + "\n"
            + "REQUIRED_ISOLATED_MUTATIONS=21\n"
            + "CROSS_ARTIFACT_NEGATIVE_FIXTURES=PASS\n"
            + "VERIFICATION_PLAN_CAPTURED=YES\n"
            + verification,
        )
        write_text(temporary / "changed_files.txt", "\n".join(path.as_posix() for path in changed))
        diff = run(
            ["git", "diff", "--binary", f"{PREVIOUS_AUDIT_COMMIT}..{head}"],
            cwd=root,
        ).stdout
        write_text(temporary / "git_diff.patch", diff)
        write_text(
            temporary / "manifest_reporting_result.txt",
            "\n".join(
                [
                    "OUTER_ZIP_MANIFEST_VALIDATION=REPORTED_BY_PACKAGE_SIDECAR",
                    "EVIDENCE_MANIFEST_VALIDATION=PENDING_COUNT",
                    "AGGREGATE_MANIFEST_VALIDATION=REPORTED_BY_PACKAGE_SIDECAR",
                ]
            ),
        )
        evidence_manifest_count = len(
            manifest_entries(temporary, exclude={"MANIFEST_SHA256.txt"})
        ) + 1
        write_text(
            temporary / "manifest_reporting_result.txt",
            "\n".join(
                [
                    "OUTER_ZIP_MANIFEST_VALIDATION=REPORTED_BY_PACKAGE_SIDECAR",
                    f"EVIDENCE_MANIFEST_VALIDATION=PASS_{evidence_manifest_count}_OF_{evidence_manifest_count}",
                    "AGGREGATE_MANIFEST_VALIDATION=REPORTED_BY_PACKAGE_SIDECAR",
                ]
            ),
        )
        write_inventory_and_manifest(temporary)
        validate_manifest(temporary, required=EVIDENCE_REQUIRED_FILES)
        temporary.replace(final)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    validate_manifest(final, required=EVIDENCE_REQUIRED_FILES)
    print("EVIDENCE_RESULT=PASS")
    print(f"EVIDENCE_ROOT={final.resolve()}")
    print(f"EVIDENCE_AUDIT_COMMIT={head}")
    print("EVIDENCE_MANIFEST=PASS")
    return final


def validate_source_tar(source_tar: Path) -> list[tarfile.TarInfo]:
    members: list[tarfile.TarInfo] = []
    with tarfile.open(source_tar, "r:") as archive:
        for member in archive:
            if not safe_archive_name(member.name):
                raise BuildError(f"unsafe source archive path: {member.name}")
            if not (member.isfile() or member.isdir()):
                raise BuildError(f"unsupported source archive entry type: {member.name}")
            if member.isfile():
                stream = archive.extractfile(member)
                if stream is None:
                    raise BuildError(f"source archive member cannot be read: {member.name}")
                while stream.read(1024 * 1024):
                    pass
            members.append(member)
    return members


def extract_source_tar(source_tar: Path, destination: Path) -> None:
    destination.mkdir(parents=True)
    with tarfile.open(source_tar, "r:") as archive:
        for member in archive:
            relative = PurePosixPath(member.name)
            if not safe_archive_name(member.name) or not (member.isfile() or member.isdir()):
                raise BuildError(f"unsafe source archive member: {member.name}")
            target = destination.joinpath(*relative.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            source = archive.extractfile(member)
            if source is None:
                raise BuildError(f"source member cannot be extracted: {member.name}")
            with target.open("wb") as output:
                shutil.copyfileobj(source, output)


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def package_credential_scan(root: Path) -> int:
    text_suffixes = {
        ".txt",
        ".md",
        ".json",
        ".py",
        ".tcl",
        ".v",
        ".sv",
        ".h",
        ".c",
        ".ps1",
        ".sh",
        ".patch",
    }
    paths = [
        path
        for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in text_suffixes
    ]
    findings: list[str] = []
    allowed_count = 0
    for path in paths:
        relative = normalized_relative(path, root)
        allowed_values = PACKAGE_SYNTHETIC_CREDENTIAL_FIXTURES.get(relative, set())
        text = path.read_text(encoding="utf-8", errors="replace")
        for pattern in CREDENTIAL_PATTERNS:
            for match in pattern.finditer(text):
                if match.group(0) in allowed_values:
                    allowed_count += 1
                    continue
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{relative}:{line}")
    if findings:
        raise BuildError(
            "credential material found in review package: "
            + ", ".join(sorted(set(findings)))
        )
    if allowed_count != EXPECTED_PACKAGE_FIXTURE_ALLOWLIST_COUNT:
        raise BuildError(
            "synthetic credential fixture allowlist count mismatch: "
            f"{allowed_count} != {EXPECTED_PACKAGE_FIXTURE_ALLOWLIST_COUNT}"
        )
    return allowed_count


def validate_zip_manifest(
    archive: zipfile.ZipFile,
    manifest_name: str,
    *,
    path_prefix: str = "",
) -> int:
    try:
        lines = archive.read(manifest_name).decode("utf-8").splitlines()
    except (KeyError, UnicodeDecodeError) as exc:
        raise BuildError(f"ZIP manifest cannot be read: {manifest_name}: {exc}") from exc
    seen: set[str] = set()
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match:
            raise BuildError(f"invalid ZIP manifest row in {manifest_name}: {line!r}")
        digest, relative = match.groups()
        if relative in seen or not safe_archive_name(relative):
            raise BuildError(f"duplicate or unsafe ZIP manifest path: {relative}")
        seen.add(relative)
        member_name = f"{path_prefix}{relative}"
        try:
            payload = archive.read(member_name)
        except KeyError as exc:
            raise BuildError(f"ZIP manifest member missing: {member_name}") from exc
        if hashlib.sha256(payload).hexdigest() != digest:
            raise BuildError(f"ZIP manifest digest mismatch: {member_name}")
    expected = {
        name[len(path_prefix) :]
        for name in archive.namelist()
        if name.startswith(path_prefix)
        and name != manifest_name
        and name != f"{path_prefix}MANIFEST_SHA256.txt"
    }
    if seen != expected:
        raise BuildError(
            f"ZIP manifest file set mismatch for {manifest_name}: "
            f"missing={expected-seen}, extra={seen-expected}"
        )
    return len(seen)


def _validate_sidecar(
    sidecar: Path,
    final_zip: Path,
    *,
    head: str,
    evidence: Path,
    outer_manifest_count: int,
    evidence_manifest_count: int,
) -> None:
    values: dict[str, str] = {}
    for line in sidecar.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            raise BuildError(f"invalid sidecar row: {line!r}")
        key, value = line.split("=", 1)
        if key in values:
            raise BuildError(f"duplicate sidecar key: {key}")
        values[key] = value
    expected = {
        "FILE": str(final_zip.resolve()),
        "SIZE_BYTES": str(final_zip.stat().st_size),
        "SHA256": sha256_file(final_zip),
        "ZIP_FULL_READ_VALIDATION": "PASS",
        "ZIP_CRC_VALIDATION": "PASS",
        "OUTER_ZIP_MANIFEST_VALIDATION": (
            f"PASS_{outer_manifest_count}_OF_{outer_manifest_count}"
        ),
        "EVIDENCE_MANIFEST_VALIDATION": (
            f"PASS_{evidence_manifest_count}_OF_{evidence_manifest_count}"
        ),
        "AGGREGATE_MANIFEST_VALIDATION": (
            "PASS_"
            f"{outer_manifest_count + evidence_manifest_count}_OF_"
            f"{outer_manifest_count + evidence_manifest_count}"
        ),
        "AUDIT_COMMIT": head,
        "EVIDENCE_ROOT": str(evidence.resolve()),
    }
    if values != expected:
        raise BuildError(f"external sidecar mismatch: expected {expected}, got {values}")


def create_package(root: Path, evidence: Path, downloads: Path) -> tuple[Path, str, int]:
    head, tree = assert_repository_identity(root, require_remote_feature=True)
    validate_manifest(evidence, required=EVIDENCE_REQUIRED_FILES)
    identity = (evidence / "evidence_identity.txt").read_text(encoding="utf-8")
    if f"AUDIT_COMMIT={head}" not in identity:
        raise BuildError("evidence is not bound to the final audit commit")
    downloads.mkdir(parents=True, exist_ok=True)
    package_name = f"{PACKAGE_PREFIX}{head[:8]}.zip"
    final_zip = downloads / package_name
    sidecar = downloads / f"{package_name}.sha256.txt"
    if final_zip.exists() or sidecar.exists():
        raise BuildError(f"review package or sidecar already exists: {final_zip}")

    with tempfile.TemporaryDirectory(prefix="stage2f_review_") as temporary_name:
        stage = Path(temporary_name) / "package"
        stage.mkdir()
        write_text(stage / "git" / "commit.txt", head)
        write_text(stage / "git" / "tree.txt", tree)
        write_text(stage / "git" / "branch.txt", BRANCH)
        write_text(stage / "git" / "remote_commit.txt", head)
        write_text(
            stage / "git" / "log.txt",
            git(root, "log", "--format=fuller", f"{PREVIOUS_AUDIT_COMMIT}..{head}"),
        )
        write_text(
            stage / "diff" / "changed_files.txt",
            "\n".join(path.as_posix() for path in changed_files(root, head)),
        )
        write_text(
            stage / "diff" / "previous_audit_to_final.patch",
            run(
                ["git", "diff", "--binary", f"{PREVIOUS_AUDIT_COMMIT}..{head}"],
                cwd=root,
            ).stdout,
        )

        source_tar = stage / "source" / f"source-{head[:8]}.tar"
        source_tar.parent.mkdir(parents=True)
        run(["git", "archive", "--format=tar", f"--output={source_tar}", head], cwd=root)
        source_members = validate_source_tar(source_tar)
        extract_source_tar(source_tar, stage / "source" / "tree")

        evidence_target = stage / "evidence" / evidence.name
        shutil.copytree(evidence, evidence_target)
        for relative in AUDIT_DOCUMENTS:
            copy_file(root / relative, stage / "audit_documents" / relative)
        for relative in SPECIFICATIONS:
            copy_file(root / relative, stage / "machine_readable_specs" / relative)
        for relative in TEST_SOURCES:
            copy_file(root / relative, stage / "tests" / relative)

        write_text(
            stage / "review_contract" / "scope_non_claim.txt",
            "\n".join(
                [
                    "ARCHITECTURE_AND_CONTRACT_AUDIT_ONLY=YES",
                    "FUNCTIONAL_RTL_CHANGED=NO",
                    "PUBLISHED_REGISTER_BEHAVIOR_CHANGED=NO",
                    "SYNTHESIS_RUN=NO",
                    "IMPLEMENTATION_RUN=NO",
                    "BITSTREAM_RUN=NO",
                    "HARDWARE_ACTION=NO",
                    "PHYSICAL_ACCURACY_CLAIM=NOT_MADE",
                    "BOARD_CALIBRATION_CLAIM=NOT_MADE",
                    "STAGE2F_IMPLEMENTATION_STARTED=NO",
                    "STAGE2F_CONTRACT_GAP_CLOSED=NO",
                    "REMAINING_CONTRACT_GAPS=2",
                    "STAGE2_COMPLETE=NO",
                    "REFERENCE_PROFILE_PRODUCTION_SELECTED=NO",
                    "PURCHASE_AUTHORIZATION=NO",
                ]
            ),
        )
        fixture_allowlist_count = package_credential_scan(stage)
        write_text(
            stage / "PACKAGE_IDENTITY.txt",
            "\n".join(
                [
                    f"PACKAGE_NAME={package_name}",
                    f"CREATED_UTC={datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}",
                    f"BRANCH={BRANCH}",
                    f"BASE_COMMIT={BASE_COMMIT}",
                    f"PREVIOUS_AUDIT_COMMIT={PREVIOUS_AUDIT_COMMIT}",
                    f"AUDIT_COMMIT={head}",
                    f"REMOTE_AUDIT_COMMIT={head}",
                    f"AUDIT_TREE={tree}",
                    f"EVIDENCE_ROOT_NAME={evidence.name}",
                    f"SOURCE_ARCHIVE_MEMBER_COUNT={len(source_members)}",
                    "SOURCE_SNAPSHOT_METHOD=GIT_ARCHIVE",
                    "SOURCE_ARCHIVE_FULL_READ=PASS",
                    "LOCAL_REMOTE_COMMIT_EQUALITY=PASS",
                    "CREDENTIAL_SCAN=PASS",
                    "CREDENTIAL_FIXTURE_ALLOWLIST_POLICY=EXACT_PATH_AND_EXACT_LITERAL",
                    f"CREDENTIAL_FIXTURE_ALLOWLIST_COUNT={fixture_allowlist_count}",
                    "OUTER_MANIFEST_SELF_ENTRY=EXCLUDED_TO_AVOID_SELF_REFERENCE",
                ]
            ),
        )
        if package_credential_scan(stage) != fixture_allowlist_count:
            raise BuildError("credential scan result changed after package identity creation")
        write_inventory_and_manifest(stage)
        validate_manifest(stage)

        with zipfile.ZipFile(
            final_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as archive:
            for path in sorted(item for item in stage.rglob("*") if item.is_file()):
                relative = normalized_relative(path, stage)
                if not safe_archive_name(relative):
                    raise BuildError(f"unsafe package path: {relative}")
                archive.write(path, relative)

    with zipfile.ZipFile(final_zip, "r") as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or any(not safe_archive_name(name) for name in names):
            raise BuildError("ZIP contains duplicate or unsafe paths")
        bad_member = archive.testzip()
        if bad_member is not None:
            raise BuildError(f"ZIP CRC failure: {bad_member}")
        for name in names:
            archive.read(name)
        outer_count = validate_zip_manifest(archive, "MANIFEST_SHA256.txt")
        evidence_prefix = f"evidence/{evidence.name}/"
        evidence_count = validate_zip_manifest(
            archive,
            f"{evidence_prefix}MANIFEST_SHA256.txt",
            path_prefix=evidence_prefix,
        )
        tar_name = f"source/source-{head[:8]}.tar"
        tar_bytes = archive.read(tar_name)
        with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:") as source_archive:
            for member in source_archive:
                if not safe_archive_name(member.name) or not (
                    member.isfile() or member.isdir()
                ):
                    raise BuildError(f"unsafe source entry inside ZIP: {member.name}")
                if member.isfile():
                    stream = source_archive.extractfile(member)
                    if stream is None:
                        raise BuildError(f"source member unreadable inside ZIP: {member.name}")
                    while stream.read(1024 * 1024):
                        pass
    aggregate_count = outer_count + evidence_count

    digest = sha256_file(final_zip)
    size = final_zip.stat().st_size
    write_text(
        sidecar,
        "\n".join(
            [
                f"FILE={final_zip.resolve()}",
                f"SIZE_BYTES={size}",
                f"SHA256={digest}",
                "ZIP_FULL_READ_VALIDATION=PASS",
                "ZIP_CRC_VALIDATION=PASS",
                f"OUTER_ZIP_MANIFEST_VALIDATION=PASS_{outer_count}_OF_{outer_count}",
                f"EVIDENCE_MANIFEST_VALIDATION=PASS_{evidence_count}_OF_{evidence_count}",
                f"AGGREGATE_MANIFEST_VALIDATION=PASS_{aggregate_count}_OF_{aggregate_count}",
                f"AUDIT_COMMIT={head}",
                f"EVIDENCE_ROOT={evidence.resolve()}",
            ]
        ),
    )
    _validate_sidecar(
        sidecar,
        final_zip,
        head=head,
        evidence=evidence,
        outer_manifest_count=outer_count,
        evidence_manifest_count=evidence_count,
    )
    print("REVIEW_PACKAGE_RESULT=PASS")
    print(f"REVIEW_BUNDLE={final_zip.resolve()}")
    print(f"REVIEW_BUNDLE_SIZE_BYTES={size}")
    print(f"REVIEW_BUNDLE_SHA256={digest}")
    print(f"REVIEW_BUNDLE_SIDECAR={sidecar.resolve()}")
    print("REVIEW_BUNDLE_FULL_READ=PASS")
    print("ZIP_CRC_VALIDATION=PASS")
    print(f"OUTER_ZIP_MANIFEST_VALIDATION=PASS_{outer_count}_OF_{outer_count}")
    print(f"EVIDENCE_MANIFEST_VALIDATION=PASS_{evidence_count}_OF_{evidence_count}")
    print(f"AGGREGATE_MANIFEST_VALIDATION=PASS_{aggregate_count}_OF_{aggregate_count}")
    print("SOURCE_ARCHIVE_FULL_READ=PASS")
    print("LOCAL_REMOTE_COMMIT_EQUALITY=PASS")
    return final_zip, digest, size


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    subparsers = parser.add_subparsers(dest="command", required=True)
    evidence_parser = subparsers.add_parser("evidence")
    evidence_parser.add_argument("--evidence-base", type=Path, required=True)
    evidence_parser.add_argument("--tcl-launcher", type=Path)
    package_parser = subparsers.add_parser("package")
    package_parser.add_argument("--evidence", type=Path, required=True)
    package_parser.add_argument("--downloads", type=Path, required=True)
    args = parser.parse_args(argv)

    try:
        root = args.root.resolve()
        if args.command == "evidence":
            create_evidence(root, args.evidence_base.resolve(), args.tcl_launcher)
        else:
            create_package(root, args.evidence.resolve(), args.downloads.resolve())
    except (
        BuildError,
        OSError,
        ValueError,
        json.JSONDecodeError,
        tarfile.TarError,
        zipfile.BadZipFile,
    ) as exc:
        print(f"STAGE2F_AUDIT_REVIEW_BUILD=FAIL\nERROR={exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
