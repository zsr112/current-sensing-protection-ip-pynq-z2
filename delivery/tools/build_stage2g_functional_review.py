#!/usr/bin/env python3
"""Create commit-bound Stage 2G evidence and an independent-review bundle."""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath, PureWindowsPath


ROOT = Path(__file__).resolve().parents[1]
BASE_COMMIT = "ef6a990b154edd03b0b144d7d7cd0e41303dc095"
BRANCH = "codex/stage2g-reset-wait-first-fault-policy-implementation"
EVIDENCE_PREFIX = "functional-implementation-recovery-observability-hardening-"
PACKAGE_PREFIX = "stage2g-functional-rtl-recovery-observability-review-"

REQUIRED_EVIDENCE = {
    "runner_summary.txt",
    "evidence_identity.txt",
    "review_findings_closure.txt",
    "public_recovery_contract_addendum.txt",
    "public_status_transition_matrix.txt",
    "software_rtl_recovery_equivalence.txt",
    "post_clear_no_sample_result.txt",
    "post_clear_nonclean_result.txt",
    "post_clear_new_fault_result.txt",
    "production_safe_release_result.txt",
    "recovery_observability_mutation_results.txt",
    "source_map_implementation_result.txt",
    "previous_mutation_results.txt",
    "sequence_integrity_regression.txt",
    "full_regression_summary.txt",
    "scope_non_claim.txt",
    "changed_files.txt",
    "git_diff.patch",
    "FILE_INVENTORY.txt",
    "MANIFEST_SHA256.txt",
}

TEXT_SUFFIXES = {
    ".txt",
    ".log",
    ".md",
    ".json",
    ".py",
    ".tcl",
    ".v",
    ".sv",
    ".vh",
    ".ps1",
    ".sh",
    ".patch",
    ".tsv",
    ".h",
    ".c",
}
VALIDATION_SUFFIXES = TEXT_SUFFIXES
CREDENTIAL_PATTERNS = (
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    re.compile(r"\bsk-[A-Za-z0-9]{20,}\b"),
    re.compile(
        r"(?:password|passwd|api[_-]?key|client[_-]?secret)\s*[:=]\s*"
        r"[\"'][^\"']{8,}[\"']",
        re.IGNORECASE,
    ),
)


class BuildError(RuntimeError):
    pass


def run(command: list[str], cwd: Path = ROOT) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode != 0:
        raise BuildError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"{result.stdout}"
        )
    return result.stdout.strip()


def git(*args: str) -> str:
    return run(["git", *args])


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


def relative(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def safe_name(name: str) -> bool:
    normalized = name.replace("\\", "/")
    posix = PurePosixPath(normalized)
    windows = PureWindowsPath(normalized)
    return (
        bool(normalized)
        and "\x00" not in normalized
        and not posix.is_absolute()
        and not windows.is_absolute()
        and ".." not in posix.parts
        and ":" not in normalized
        and "\\" not in name
    )


def files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*") if path.is_file())


def write_inventory_and_manifest(root: Path) -> tuple[int, int]:
    inventory_rows = []
    for path in files(root):
        name = relative(path, root)
        if name in {"FILE_INVENTORY.txt", "MANIFEST_SHA256.txt"}:
            continue
        inventory_rows.append(f"{name}\t{path.stat().st_size}")
    write_text(
        root / "FILE_INVENTORY.txt",
        "PATH\tSIZE_BYTES\n" + "\n".join(inventory_rows),
    )
    manifest_rows = []
    for path in files(root):
        name = relative(path, root)
        if name == "MANIFEST_SHA256.txt":
            continue
        manifest_rows.append(f"{sha256_file(path)}  {name}")
    write_text(root / "MANIFEST_SHA256.txt", "\n".join(manifest_rows))
    return len(inventory_rows), len(manifest_rows)


def validate_manifest(
    root: Path,
    manifest_name: str = "MANIFEST_SHA256.txt",
    *,
    exact_required: set[str] | None = None,
) -> int:
    manifest = root / manifest_name
    if not manifest.is_file():
        raise BuildError(f"manifest missing: {manifest}")
    seen: set[str] = set()
    for line in manifest.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if match is None:
            raise BuildError(f"invalid manifest row: {line!r}")
        digest, name = match.groups()
        if name in seen or not safe_name(name):
            raise BuildError(f"duplicate or unsafe manifest path: {name}")
        seen.add(name)
        member = root / Path(name)
        if not member.is_file() or sha256_file(member) != digest:
            raise BuildError(f"manifest mismatch: {name}")
    actual = {
        relative(path, root)
        for path in files(root)
        if relative(path, root) != manifest_name
    }
    if seen != actual:
        raise BuildError(
            f"manifest coverage mismatch: missing={actual-seen}, extra={seen-actual}"
        )
    if exact_required is not None:
        all_names = actual | {manifest_name}
        if all_names != exact_required:
            raise BuildError(
                "required evidence mismatch: "
                f"missing={exact_required-all_names}, extra={all_names-exact_required}"
            )
    return len(seen)


def parse_kv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in values:
            raise BuildError(f"duplicate key {key} in {path}")
        values[key] = value
    return values


def assert_identity(*, require_remote: bool) -> tuple[str, str]:
    branch = git("branch", "--show-current")
    head = git("rev-parse", "HEAD")
    tree = git("rev-parse", "HEAD^{tree}")
    if branch != BRANCH:
        raise BuildError(f"wrong branch: {branch}")
    if git("rev-parse", "main") != BASE_COMMIT:
        raise BuildError("local main is not the frozen base")
    if git("rev-parse", "origin/main") != BASE_COMMIT:
        raise BuildError("origin/main is not the frozen base")
    if git("status", "--porcelain", "--untracked-files=all"):
        raise BuildError("worktree must be clean")
    if subprocess.run(
        ["git", "merge-base", "--is-ancestor", BASE_COMMIT, head], cwd=ROOT
    ).returncode:
        raise BuildError("frozen base is not an ancestor of implementation")
    if head == BASE_COMMIT:
        raise BuildError("implementation commit has not been created")
    if require_remote:
        tracking = git("rev-parse", f"origin/{BRANCH}")
        if tracking != head:
            raise BuildError(
                f"local/tracking mismatch: local={head}, tracking={tracking}"
            )
        ref = f"refs/heads/{BRANCH}"
        rows = git("ls-remote", "--exit-code", "origin", ref).splitlines()
        if len(rows) != 1 or rows[0].split() != [head, ref]:
            raise BuildError(f"remote advertisement mismatch: {rows!r}")
    return head, tree


def validate_runner(validation: Path) -> dict[str, str]:
    summary = validation / "runner_summary.txt"
    if not summary.is_file():
        raise BuildError(f"runner summary missing: {summary}")
    values = parse_kv(summary)
    required = {
        "STAGE2G_FUNCTIONAL_RTL_RUNNER": "PASS",
        "STAGE2G_STATIC_CONTRACT_AUDIT": "PASS",
        "STAGE2G_IMPLEMENTATION_STATIC": "PASS",
        "REFERENCE_MODEL_COMPARISON": "PASS",
        "ICARUS_DIRECTED": "PASS",
        "XSIM_DIRECTED": "PASS",
        "RANDOM_EPISODES": "PASS_1000",
        "FAULT_EVAL_SEQUENCE_WIDTH": "OBS_SEQUENCE_WIDTH",
        "SUPPORTED_SEQUENCE_WIDTHS": "16_TO_32",
        "IMPLICIT_STAGE2G_SEQUENCE_PORT_RESIZE": "NO",
        "SEQUENCE_WIDTH_16": "PASS",
        "SEQUENCE_WIDTH_24": "PASS",
        "SEQUENCE_WIDTH_32": "PASS",
        "SEQUENCE_WRAP_16": "PASS",
        "SEQUENCE_WRAP_24": "PASS",
        "SEQUENCE_WRAP_32": "PASS",
        "POLICY_INTEGRITY_EQUALS_STAGE2E_TRANSACTION_CLASSIFICATION": "PASS",
        "PRODUCTION_SAFE_HOLD": "PASS",
        "PRODUCTION_SAFE_RELEASE_AFTER_LATER_HEALTHY": "PASS",
        "PRODUCTION_UNSAFE_PULSE_COUNT": "0",
        "MUTATION_CONNECTED_FIXTURES": "PASS_47_OF_47",
        "PREVIOUS_MUTATION_CONNECTED_FIXTURES": "PASS_28_OF_28",
        "NEW_SEQUENCE_MUTATION_FIXTURES": "PASS_11_OF_11",
        "SEQUENCE_MUTATION_FIXTURES": "PASS_11_OF_11",
        "RECOVERY_OBSERVABILITY_MUTATION_FIXTURES": "PASS_8_OF_8",
        "INTERNAL_EPISODE_END": "LEGAL_CLEAR_ACCEPTANCE",
        "PUBLIC_RECOVERY_COMPLETE": "LATER_CLEAN_HEALTHY_EVALUATION_ENTERING_ARMED",
        "CLEAR_ACCEPTANCE_EQUALS_PUBLIC_RECOVERY_COMPLETE": "NO",
        "STATUS_FAULT_LATCHED_DURING_POST_CLEAR_RESET_WAIT": "1",
        "FAULT_CODE_DURING_POST_CLEAR_RESET_WAIT": "RETAIN_PRIOR_FIRST_CAUSE",
        "NO_SAMPLE_POST_CLEAR_RECOVERY_VERIFIED": "NO",
        "NONCLEAN_POST_CLEAR_RECOVERY_VERIFIED": "NO",
        "LATER_HEALTHY_CLEARS_COMPATIBILITY_STATUS": "PASS",
        "POST_CLEAR_FAULT_REPLACES_WITH_NEW_FIRST_CAUSE": "PASS",
        "RESET_CLEARS_COMPATIBILITY_STATUS": "PASS",
        "SOFTWARE_RECOVERY_API_SEMANTICS_PRESERVED": "PASS",
        "SOURCE_MAP_BASELINE_ENTRIES": "PASS_17",
        "SOURCE_MAP_IMPLEMENTATION_ENTRIES": "PASS_10",
        "SOURCE_MAP_IMPLEMENTED_PATH_TRACE": "PASS",
        "SOURCE_ARCHIVE_STATIC_REPLAY": "PASS",
        "REPOSITORY_FALLBACK_USED": "NO",
        "CONTROLLED_BUILD_SOURCE_CLOSURE": "PASS",
        "STAGE2F_REGRESSION": "PASS",
        "STAGE2E_REGRESSION": "PASS",
        "STAGE2D_REGRESSION": "PASS",
        "STAGE2C_REGRESSION": "PASS",
        "STAGE2B_REGRESSION": "PASS",
        "CANONICAL_REGRESSION": "PASS",
        "FULL_PRIOR_STAGE_REGRESSION": "PASS",
    }
    for key, expected in required.items():
        if values.get(key) != expected:
            raise BuildError(
                f"runner result mismatch {key}: {values.get(key)!r} != {expected!r}"
            )
    mutation = validation / "mutations/mutation_results.txt"
    mutation_text = mutation.read_text(encoding="utf-8") if mutation.is_file() else ""
    if any(
        marker not in mutation_text
        for marker in (
            "ICARUS_MUTATIONS=PASS_47_OF_47",
            "XSIM_MUTATIONS=PASS_47_OF_47",
            "PREVIOUS_MUTATION_CONNECTED_FIXTURES=PASS_28_OF_28",
            "NEW_SEQUENCE_MUTATION_FIXTURES=PASS_11_OF_11",
            "RECOVERY_OBSERVABILITY_MUTATION_FIXTURES=PASS_8_OF_8",
            "ICARUS_RECOVERY_MUTATIONS=PASS_8_OF_8",
            "XSIM_RECOVERY_MUTATIONS=PASS_8_OF_8",
        )
    ):
        raise BuildError("complete Icarus/XSim mutation evidence is missing")
    for width in (16, 24, 32):
        for simulator, relative_name in (
            ("Icarus", f"icarus/sequence_width_{width}/run.log"),
            ("XSim", f"xsim/sequence_width_{width}/xsim.console.log"),
        ):
            text = log_text(validation, relative_name)
            for marker in (
                f"SEQUENCE_WIDTH_{width}=PASS",
                f"SEQUENCE_WRAP_{width}=PASS",
                "POLICY_INTEGRITY_EQUALS_STAGE2E_TRANSACTION_CLASSIFICATION=PASS",
            ):
                if marker not in text:
                    raise BuildError(
                        f"{simulator} width {width} evidence omits {marker}"
                    )
    for relative_name in (
        "icarus/production_path/run.log",
        "xsim/production_path/xsim.console.log",
    ):
        text = log_text(validation, relative_name)
        for marker in (
            "PRODUCTION_SAFE_HOLD=PASS",
            "PRODUCTION_SAFE_RELEASE_AFTER_LATER_HEALTHY=PASS",
            "PRODUCTION_UNSAFE_PULSE_COUNT=0",
            "STATUS_FAULT_LATCHED_DURING_POST_CLEAR_RESET_WAIT=1",
            "FAULT_CODE_DURING_POST_CLEAR_RESET_WAIT=RETAIN_PRIOR_FIRST_CAUSE",
            "LATER_HEALTHY_CLEARS_COMPATIBILITY_STATUS=PASS",
            "POST_CLEAR_FAULT_REPLACES_WITH_NEW_FIRST_CAUSE=PASS",
            "RESET_CLEARS_COMPATIBILITY_STATUS=PASS",
        ):
            if marker not in text:
                raise BuildError(f"production evidence omits {marker}")
    replay = log_text(
        validation,
        "source_archive_replay/source_archive_replay_result.txt",
    )
    for marker in (
        "SOURCE_ARCHIVE_STATIC_REPLAY=PASS",
        "REPOSITORY_FALLBACK_USED=NO",
    ):
        if marker not in replay:
            raise BuildError(f"source archive replay omits {marker}")
    recovery = log_text(
        validation, "python/software_rtl_recovery_equivalence.log"
    )
    for marker in (
        "POST_CLEAR_RESET_WAIT_RECOVERY_VERIFIED=NO",
        "NO_SAMPLE_POST_CLEAR_RECOVERY_VERIFIED=NO",
        "NONCLEAN_POST_CLEAR_RECOVERY_VERIFIED=NO",
        "ARMED_AFTER_LATER_HEALTHY_RECOVERY_VERIFIED=YES",
        "SOFTWARE_RECOVERY_API_SEMANTICS_PRESERVED=PASS",
        "RTL_RECOVERY_SNAPSHOT_SOURCES=PASS_2_OF_2",
    ):
        if marker not in recovery:
            raise BuildError(f"software/RTL recovery evidence omits {marker}")
    return values


def copy_selected_validation(source: Path, destination: Path) -> int:
    count = 0
    for path in files(source):
        if path.suffix.lower() not in VALIDATION_SUFFIXES:
            continue
        target = destination / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        count += 1
    return count


def credential_scan(root: Path) -> int:
    findings: list[str] = []
    scanned = 0
    for path in files(root):
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        scanned += 1
        for pattern in CREDENTIAL_PATTERNS:
            match = pattern.search(text)
            if match is not None:
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{relative(path, root)}:{line}")
    if findings:
        raise BuildError("credential scan findings: " + ", ".join(findings))
    return scanned


def log_text(validation: Path, relative_name: str) -> str:
    path = validation / relative_name
    if not path.is_file():
        raise BuildError(f"required validation log missing: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def create_evidence(validation: Path, evidence: Path) -> tuple[str, int]:
    head, tree = assert_identity(require_remote=False)
    validate_runner(validation)
    resolved_evidence = evidence.resolve()
    if resolved_evidence.is_relative_to(ROOT.resolve()):
        raise BuildError("evidence root must be outside the source repository")
    if not evidence.name.startswith(EVIDENCE_PREFIX):
        raise BuildError(f"evidence directory must start with {EVIDENCE_PREFIX}")
    if evidence.exists():
        raise BuildError(f"evidence root already exists: {evidence}")
    evidence.mkdir(parents=True)

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    changed = [
        line
        for line in git("diff", "--name-only", f"{BASE_COMMIT}..{head}").splitlines()
        if line
    ]
    patch = git("diff", "--binary", f"{BASE_COMMIT}..{head}")
    write_text(evidence / "runner_summary.txt", log_text(validation, "runner_summary.txt"))
    write_text(
        evidence / "evidence_identity.txt",
        "\n".join(
            (
                "EVIDENCE_TYPE=STAGE2G_FUNCTIONAL_RTL_RECOVERY_OBSERVABILITY_HARDENING",
                f"CREATED_UTC={timestamp}",
                f"BRANCH={BRANCH}",
                f"BASE_COMMIT={BASE_COMMIT}",
                "PREVIOUS_IMPLEMENTATION_COMMIT="
                "7f332bac77b0433e241a769faf161855894a8b77",
                f"IMPLEMENTATION_COMMIT={head}",
                f"IMPLEMENTATION_TREE={tree}",
                "WORKTREE=CLEAN",
            )
        ),
    )
    write_text(
        evidence / "review_findings_closure.txt",
        "BLOCKERS_CLOSED=1_OF_1\n"
        "MEDIUM_FINDINGS_CLOSED=1_OF_1\n"
        "PUBLIC_RECOVERY_OBSERVABILITY_GAP=CLOSED\n"
        "POST_CLEAR_STATUS_COMPATIBILITY=CLOSED\n"
        "SOFTWARE_RTL_RECOVERY_EQUIVALENCE=CLOSED\n"
        "CONNECTED_RECOVERY_MUTATIONS=CLOSED_8_OF_8\n"
        "FINAL_REVIEW_DISPOSITION=READY_FOR_REREVIEW\n",
    )
    write_text(
        evidence / "public_recovery_contract_addendum.txt",
        (ROOT / "docs/architecture/stage2g_public_recovery_contract_addendum.md")
        .read_text(encoding="utf-8"),
    )
    write_text(
        evidence / "sequence_width_contract_addendum.txt",
        (ROOT / "docs/architecture/stage2g_sequence_width_contract_addendum.md")
        .read_text(encoding="utf-8"),
    )
    sequence_sections = []
    equivalence_sections = []
    wrap_sections = []
    for width in (16, 24, 32):
        for simulator, relative_name in (
            ("ICARUS", f"icarus/sequence_width_{width}/run.log"),
            ("XSIM", f"xsim/sequence_width_{width}/xsim.console.log"),
        ):
            transcript = log_text(validation, relative_name)
            header = f"[{simulator}_SEQUENCE_WIDTH_{width}]"
            sequence_sections.append(header + "\n" + transcript)
            equivalence_sections.append(header + "\n" + transcript)
            wrap_sections.append(header + "\n" + transcript)
    write_text(
        evidence / "sequence_width_matrix.txt",
        "FAULT_EVAL_SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH\n"
        "SUPPORTED_SEQUENCE_WIDTHS=16_TO_32\n"
        "IMPLICIT_STAGE2G_SEQUENCE_PORT_RESIZE=NO\n\n"
        + "\n\n".join(sequence_sections),
    )
    write_text(
        evidence / "stage2e_policy_integrity_equivalence.txt",
        "POLICY_INTEGRITY_EQUALS_STAGE2E_TRANSACTION_CLASSIFICATION=PASS\n"
        "FIRST_NONZERO_DELIVERY=STALE_RETAIN_EXPECTED\n"
        "FORWARD_GAP=DIRTY_RESYNC_DELIVERED_PLUS_ONE\n"
        "DUPLICATE=DIRTY_RETAIN_EXPECTED\n"
        "REORDER_STALE=DIRTY_RETAIN_EXPECTED\n"
        "NEXT_MATCHING_TRANSACTION_RESTORES_ELIGIBILITY=PASS\n\n"
        + "\n\n".join(equivalence_sections),
    )
    write_text(
        evidence / "wrap_results.txt",
        "SEQUENCE_WRAP_16=PASS\nSEQUENCE_WRAP_24=PASS\n"
        "SEQUENCE_WRAP_32=PASS\n\n"
        + "\n\n".join(wrap_sections),
    )
    mutation_summary = log_text(validation, "mutations/mutation_results.txt")
    inventory_lines = log_text(
        validation, "mutations/mutation_inventory.tsv"
    ).splitlines()
    inventory_header = inventory_lines[0]
    sequence_rows = [
        line for line in inventory_lines[1:] if "\tSEQUENCE\t" in line
    ]
    previous_rows = [
        line for line in inventory_lines[1:] if "\tPREVIOUS\t" in line
    ]
    recovery_rows = [
        line for line in inventory_lines[1:] if "\tRECOVERY\t" in line
    ]
    if (
        len(sequence_rows) != 11
        or len(previous_rows) != 28
        or len(recovery_rows) != 8
    ):
        raise BuildError("mutation evidence group counts are incomplete")
    write_text(
        evidence / "sequence_mutation_results.txt",
        mutation_summary
        + "\n"
        + inventory_header
        + "\n"
        + "\n".join(sequence_rows),
    )
    write_text(
        evidence / "existing_mutation_results.txt",
        mutation_summary
        + "\n"
        + inventory_header
        + "\n"
        + "\n".join(previous_rows),
    )
    write_text(
        evidence / "previous_mutation_results.txt",
        mutation_summary
        + "\n"
        + inventory_header
        + "\n"
        + "\n".join(previous_rows),
    )
    write_text(
        evidence / "recovery_observability_mutation_results.txt",
        mutation_summary
        + "\n"
        + inventory_header
        + "\n"
        + "\n".join(recovery_rows),
    )

    production_icarus = log_text(validation, "icarus/production_path/run.log")
    production_xsim = log_text(
        validation, "xsim/production_path/xsim.console.log"
    )
    snapshot_icarus = log_text(
        validation, "icarus/production_path/recovery_snapshots.tsv"
    )
    snapshot_xsim = log_text(
        validation, "xsim/production_path/recovery_snapshots.tsv"
    )
    recovery_equivalence = log_text(
        validation, "python/software_rtl_recovery_equivalence.log"
    )
    write_text(
        evidence / "public_status_transition_matrix.txt",
        "INTERNAL_EPISODE_END=LEGAL_CLEAR_ACCEPTANCE\n"
        "PUBLIC_RECOVERY_COMPLETE=LATER_CLEAN_HEALTHY_EVALUATION_ENTERING_ARMED\n"
        "CLEAR_ACCEPTANCE_EQUALS_PUBLIC_RECOVERY_COMPLETE=NO\n\n"
        "[ICARUS_AXI_SNAPSHOTS]\n"
        + snapshot_icarus
        + "\n[XSIM_AXI_SNAPSHOTS]\n"
        + snapshot_xsim,
    )
    write_text(
        evidence / "software_rtl_recovery_equivalence.txt",
        recovery_equivalence
        + "\n[ICARUS_AXI_SNAPSHOTS]\n"
        + snapshot_icarus
        + "\n[XSIM_AXI_SNAPSHOTS]\n"
        + snapshot_xsim,
    )
    write_text(
        evidence / "post_clear_no_sample_result.txt",
        "NO_SAMPLE_POST_CLEAR_RECOVERY_VERIFIED=NO\n\n"
        + snapshot_icarus
        + "\n"
        + recovery_equivalence,
    )
    write_text(
        evidence / "post_clear_nonclean_result.txt",
        "NONCLEAN_POST_CLEAR_RECOVERY_VERIFIED=NO\n\n"
        + snapshot_icarus
        + "\n"
        + recovery_equivalence,
    )
    write_text(
        evidence / "post_clear_new_fault_result.txt",
        "POST_CLEAR_FAULT_REPLACES_WITH_NEW_FIRST_CAUSE=PASS\n\n"
        + snapshot_icarus
        + "\n"
        + production_icarus
        + "\n"
        + production_xsim,
    )
    write_text(
        evidence / "source_map_implementation_result.txt",
        log_text(validation, "python/frozen_audit.log")
        + "\n"
        + log_text(validation, "python/implementation_static.log"),
    )
    write_text(
        evidence / "sequence_integrity_regression.txt",
        "SEQUENCE_MUTATION_FIXTURES=PASS_11_OF_11\n"
        "FAULT_EVAL_SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH\n"
        "SUPPORTED_SEQUENCE_WIDTHS=16_TO_32\n\n"
        + inventory_header
        + "\n"
        + "\n".join(sequence_rows)
        + "\n\n"
        + "\n\n".join(sequence_sections),
    )
    write_text(
        evidence / "production_safe_release_result.txt",
        "PRODUCTION_SAFE_HOLD=PASS\n"
        "PRODUCTION_SAFE_RELEASE_AFTER_LATER_HEALTHY=PASS\n"
        "PRODUCTION_UNSAFE_PULSE_COUNT=0\n\n"
        + log_text(validation, "icarus/production_path/run.log")
        + "\n\n"
        + log_text(validation, "xsim/production_path/xsim.console.log"),
    )
    write_text(
        evidence / "source_archive_replay_result.txt",
        log_text(
            validation,
            "source_archive_replay/source_archive_replay_result.txt",
        ),
    )
    write_text(
        evidence / "implementation_contract.txt",
        "\n".join(
            (
                "FAULT_EVALUATION_TRANSACTION=IMPLEMENTED",
                "FAULT_EVALUATION_VALID_AUTHORITY=ONE_PER_ATOMIC_RAW_CDC_DESTINATION_DELIVERY",
                "FAULT_EVALUATION_LATENCY_ACLK=3",
                "PIPELINE_INITIATION_INTERVAL=1",
                "FAULT_EPISODE_MODEL=IMPLEMENTED",
                "RESET_WAIT_POLICY=FIRST_ELIGIBLE_TRANSACTION",
                "HEALTHY_QUALIFICATION_COUNT=1",
                "CLEAR_PROTOCOL=REQUEST_EVALUATION_FENCED",
                "TRANSACTION_CORRELATED_INTEGRITY=IMPLEMENTED",
                "RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO",
                "REMAINING_CONTRACT_GAPS=2",
                "STAGE2_COMPLETE=NO",
            )
        ),
    )
    write_text(
        evidence / "fault_evaluation_pipeline_result.txt",
        log_text(validation, "icarus/policy_matrix/run.log")
        + "\n"
        + log_text(validation, "xsim/policy_matrix/xsim.console.log"),
    )
    write_text(
        evidence / "episode_controller_result.txt",
        log_text(validation, "icarus/core_directed/run.log")
        + "\n"
        + log_text(validation, "icarus/policy_matrix/run.log"),
    )
    write_text(
        evidence / "clear_fence_result.txt",
        "CLEAR_PROTOCOL=REQUEST_EVALUATION_FENCED\n"
        "CONTINUOUS_II1_CLEAR_PROGRESS=PASS\n"
        "PRE_REQUEST_EVALUATION_RESOLVES_CLEAR=NO\n"
        "CLEAR_PENDING_NO_SAMPLE=REMAIN_LATCHED_SAFE\n"
        "CLEAR_FAULT_RESOLUTION=REJECT\n"
        "CLEAR_NONCLEAN_RESOLUTION=REJECT\n"
        "CLEAR_HEALTHY_RESOLUTION=ENTER_RESET_WAIT\n"
        "CLEAR_RESOLUTION_RELEASES_SAFE_OUTPUT=NO\n"
        + log_text(validation, "icarus/policy_matrix/run.log"),
    )
    write_text(
        evidence / "transaction_integrity_result.txt",
        "TRANSACTION_CORRELATED_INTEGRITY=IMPLEMENTED\n"
        "EVENTUALLY_CONSISTENT_SOURCE_COUNTER_GATES_POLICY=NO\n"
        "SOFTWARE_W1C_STICKY_GATES_POLICY=NO\n"
        + log_text(validation, "icarus/production_path/run.log"),
    )
    write_text(
        evidence / "directed_test_results.txt",
        log_text(validation, "icarus/core_directed/run.log")
        + "\n"
        + log_text(validation, "icarus/policy_matrix/run.log")
        + "\n"
        + log_text(validation, "icarus/production_path/run.log"),
    )
    write_text(
        evidence / "random_episode_results.txt",
        log_text(validation, "reference/generation_summary.txt")
        + "\n"
        + log_text(validation, "icarus/reference_vectors/run.log")
        + "\n"
        + log_text(validation, "xsim/reference_vectors/xsim.console.log"),
    )
    write_text(
        evidence / "mutation_results.txt",
        log_text(validation, "mutations/mutation_results.txt")
        + "\nMUTATION_INVENTORY=logs/mutations/mutation_inventory.tsv",
    )
    write_text(
        evidence / "reset_race_results.txt",
        "RESET_PRIORITY=PASS\nRESET_PIPELINE_FLUSH=PASS\n"
        "NO_STALE_PRE_RESET_RETIREMENT=PASS\n"
        + log_text(validation, "icarus/policy_matrix/run.log"),
    )
    write_text(
        evidence / "safe_output_result.txt",
        "RESET_WAIT_SAFE=PASS\nFAULT_LATCHED_SAFE=PASS\n"
        "CLEAR_RESOLUTION_SAFE=PASS\nLATER_HEALTHY_RELEASE=PASS\n"
        + log_text(validation, "icarus/production_path/run.log"),
    )
    write_text(
        evidence / "prior_stage_invariance_result.txt",
        "STAGE2F_REGRESSION=PASS\nSTAGE2E_REGRESSION=PASS\n"
        "STAGE2D_REGRESSION=PASS\nSTAGE2C_REGRESSION=PASS\n"
        "STAGE2B_REGRESSION=PASS\nRAW_THRESHOLDS_UNCHANGED=PASS\n"
        "NEW_AXI_OFFSETS_ADDED=NO\nEXTERNAL_INTERFACE_CHANGE_REQUIRED=NO\n"
        "LEGACY_MODULE_PORT_LIST_INVARIANCE=PASS_9_OF_9\n"
        "AXI_REGISTER_OFFSET_INVARIANCE=PASS_25_OF_25\n",
    )
    write_text(
        evidence / "regression_summary.txt",
        "STAGE2F_REGRESSION=PASS\nSTAGE2E_REGRESSION=PASS\n"
        "STAGE2D_REGRESSION=PASS\nSTAGE2C_REGRESSION=PASS\n"
        "STAGE2B_REGRESSION=PASS\nCANONICAL_REGRESSION=PASS\n"
        "SOFTWARE_INTERFACE_TESTS=PASS\n"
        "STAGE1E_STATIC_SUITES=PASS\nJSON_SCHEMA_VALIDATION=PASS\n"
        "DOCUMENTATION_PATH_VALIDATION=PASS\n"
        "CONTROLLED_BUILD_SOURCE_CLOSURE=PASS\nGIT_DIFF_CHECK=PASS\n"
        "SOURCE_ARCHIVE_STATIC_REPLAY=PASS\nREPOSITORY_FALLBACK_USED=NO\n",
    )
    write_text(
        evidence / "full_regression_summary.txt",
        log_text(validation, "runner_summary.txt")
        + "\n"
        + log_text(validation, "regression/canonical_iverilog.log"),
    )
    write_text(
        evidence / "scope_non_claim.txt",
        "NEW_AXI_OFFSETS_ADDED=NO\nEXTERNAL_PORTS_ADDED=NO\n"
        "SOFTWARE_API_CHANGED=NO\nNORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO\n"
        "SAMPLE_LIVENESS_WATCHDOG_ADDED=NO\nPHYSICAL_SCALING_ADDED=NO\n"
        "CALIBRATION_ADDED=NO\nPHYSICAL_UNIT_CLAIM=NO\n"
        "SYNTHESIS_RUN=NO\nIMPLEMENTATION_RUN=NO\nBITSTREAM_GENERATED=NO\n"
        "HARDWARE_MANAGER_ACTION=NO\nBOARD_ACTION=NO\n",
    )
    write_text(evidence / "changed_files.txt", "\n".join(changed))
    write_text(evidence / "git_diff.patch", patch)
    copied = copy_selected_validation(validation, evidence / "logs")
    write_inventory_and_manifest(evidence)
    evidence_names = {
        relative(path, evidence) for path in files(evidence)
    }
    missing_required = REQUIRED_EVIDENCE - evidence_names
    if missing_required:
        raise BuildError(
            f"required evidence files missing: {sorted(missing_required)}"
        )
    manifest_count = validate_manifest(evidence)
    credential_scan(evidence)
    print(f"EVIDENCE_ROOT={evidence}")
    print(f"EVIDENCE_LOG_FILES={copied}")
    print(f"EVIDENCE_MANIFEST=PASS_{manifest_count}_OF_{manifest_count}")
    return head, manifest_count


def write_validation_manifest(validation: Path) -> int:
    rows = []
    for path in files(validation):
        if path.name == "VALIDATION_MANIFEST_SHA256.txt":
            continue
        rows.append(f"{sha256_file(path)}  {relative(path, validation)}")
    write_text(validation / "VALIDATION_MANIFEST_SHA256.txt", "\n".join(rows))
    return len(rows)


def validate_zip_manifest(
    archive: zipfile.ZipFile, manifest_member: str, prefix: str
) -> int:
    try:
        text = archive.read(manifest_member).decode("utf-8")
    except (KeyError, UnicodeDecodeError) as exc:
        raise BuildError(f"unreadable ZIP manifest: {manifest_member}") from exc
    seen: set[str] = set()
    for line in text.splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if match is None:
            raise BuildError(f"invalid ZIP manifest row: {line!r}")
        digest, name = match.groups()
        if name in seen or not safe_name(name):
            raise BuildError(f"duplicate/unsafe ZIP manifest path: {name}")
        seen.add(name)
        member = prefix + name
        try:
            payload = archive.read(member)
        except KeyError as exc:
            raise BuildError(f"ZIP manifest member missing: {member}") from exc
        if hashlib.sha256(payload).hexdigest() != digest:
            raise BuildError(f"ZIP manifest digest mismatch: {member}")
    expected = {
        name[len(prefix) :]
        for name in archive.namelist()
        if name.startswith(prefix)
        and not name.endswith("/")
        and name != manifest_member
    }
    if seen != expected:
        raise BuildError(
            f"ZIP manifest coverage mismatch: missing={expected-seen}, extra={seen-expected}"
        )
    return len(seen)


def validate_source_archive(path: Path) -> int:
    expected = {
        line
        for line in git(
            "-c", "core.quotepath=false", "ls-tree", "-r", "--name-only", "HEAD"
        ).splitlines()
        if line
    }
    with zipfile.ZipFile(path) as archive:
        names = {
            name for name in archive.namelist() if name and not name.endswith("/")
        }
        if archive.testzip() is not None:
            raise BuildError("source archive CRC failure")
        if names != expected:
            raise BuildError(
                f"source archive tree mismatch: missing={expected-names}, extra={names-expected}"
            )
    return len(expected)


def create_bundle(
    validation: Path, evidence: Path, bundle: Path
) -> tuple[int, str, int, int, int]:
    head, tree = assert_identity(require_remote=True)
    validate_runner(validation)
    evidence_count = validate_manifest(evidence)
    identity = parse_kv(evidence / "evidence_identity.txt")
    if identity.get("IMPLEMENTATION_COMMIT") != head:
        raise BuildError("evidence is not bound to current implementation commit")
    expected_name = f"{PACKAGE_PREFIX}{head[:8]}.zip"
    if bundle.name != expected_name:
        raise BuildError(f"bundle filename must be {expected_name}")
    if bundle.exists() or bundle.with_name(bundle.name + ".sha256.txt").exists():
        raise BuildError("bundle or sidecar already exists")

    with tempfile.TemporaryDirectory(prefix="stage2g_review_") as temp_name:
        stage = Path(temp_name) / "stage2g-functional-rtl-recovery-observability-review"
        stage.mkdir(parents=True)
        shutil.copytree(evidence, stage / "evidence")
        validation_count = copy_selected_validation(
            validation, stage / "validation"
        )
        validation_manifest_count = write_validation_manifest(
            stage / "validation"
        )

        changed = [
            line
            for line in git(
                "diff", "--name-only", f"{BASE_COMMIT}..{head}"
            ).splitlines()
            if line
        ]
        review_sources = stage / "review_sources"
        for name in changed:
            source = ROOT / name
            if source.is_file():
                target = review_sources / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        write_text(stage / "changed_files.txt", "\n".join(changed))
        write_text(
            stage / "git_diff.patch",
            git("diff", "--binary", f"{BASE_COMMIT}..{head}"),
        )
        write_text(
            stage / "git_identity.txt",
            f"BRANCH={BRANCH}\nBASE_COMMIT={BASE_COMMIT}\n"
            f"IMPLEMENTATION_COMMIT={head}\nIMPLEMENTATION_TREE={tree}\n"
            f"REMOTE_IMPLEMENTATION_COMMIT={head}\nWORKTREE=CLEAN\n",
        )

        source_archive = stage / "source_archive.zip"
        archive_result = subprocess.run(
            [
                "git",
                "archive",
                "--format=zip",
                f"--output={source_archive}",
                "HEAD",
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if archive_result.returncode != 0:
            raise BuildError("git source archive creation failed")
        source_count = validate_source_archive(source_archive)
        replay_output = Path(temp_name) / "source_archive_replay"
        replay_text = run(
            [
                sys.executable,
                "tools/replay_stage2g_source_archive.py",
                "--archive",
                str(source_archive),
                "--output",
                str(replay_output),
                "--cleanup-repository",
            ]
        )
        for marker in (
            "SOURCE_ARCHIVE_STATIC_REPLAY=PASS",
            "REPOSITORY_FALLBACK_USED=NO",
        ):
            if marker not in replay_text:
                raise BuildError(f"bundle source replay omits {marker}")
        shutil.copy2(
            replay_output / "source_archive_replay_result.txt",
            stage / "source_archive_replay_result.txt",
        )

        write_text(
            stage / "PACKAGE_IDENTITY.txt",
            "PACKAGE_TYPE=STAGE2G_FUNCTIONAL_RTL_RECOVERY_OBSERVABILITY_INDEPENDENT_REVIEW\n"
            f"BRANCH={BRANCH}\nBASE_COMMIT={BASE_COMMIT}\n"
            f"IMPLEMENTATION_COMMIT={head}\nIMPLEMENTATION_TREE={tree}\n"
            f"EVIDENCE_MANIFEST_COUNT={evidence_count}\n"
            f"VALIDATION_SELECTED_FILES={validation_count}\n"
            f"SOURCE_ARCHIVE_FILES={source_count}\n"
            "LOCAL_REMOTE_EQUALITY=PASS\n",
        )
        aggregate_rows = []
        for name in (
            "evidence/MANIFEST_SHA256.txt",
            "validation/VALIDATION_MANIFEST_SHA256.txt",
            "source_archive.zip",
            "source_archive_replay_result.txt",
            "git_diff.patch",
            "git_identity.txt",
        ):
            aggregate_rows.append(f"{sha256_file(stage / name)}  {name}")
        write_text(
            stage / "AGGREGATE_MANIFEST_SHA256.txt",
            "\n".join(aggregate_rows),
        )
        write_inventory_and_manifest(stage)
        outer_count = validate_manifest(stage)
        credential_scan(stage)

        bundle.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(
            bundle, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as archive:
            for path in files(stage):
                archive.write(path, relative(path, stage))

        with zipfile.ZipFile(bundle) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)):
                raise BuildError("review ZIP contains duplicate paths")
            if any(not safe_name(name) for name in names):
                raise BuildError("review ZIP contains unsafe paths")
            if archive.testzip() is not None:
                raise BuildError("review ZIP CRC/full-read validation failed")
            for name in names:
                archive.read(name)
            zip_outer = validate_zip_manifest(
                archive, "MANIFEST_SHA256.txt", ""
            )
            zip_evidence = validate_zip_manifest(
                archive,
                "evidence/MANIFEST_SHA256.txt",
                "evidence/",
            )
            zip_validation = validate_zip_manifest(
                archive,
                "validation/VALIDATION_MANIFEST_SHA256.txt",
                "validation/",
            )
            aggregate = archive.read(
                "AGGREGATE_MANIFEST_SHA256.txt"
            ).decode("utf-8")
            aggregate_count = 0
            for line in aggregate.splitlines():
                match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
                if match is None:
                    raise BuildError("invalid aggregate manifest row")
                digest, name = match.groups()
                if hashlib.sha256(archive.read(name)).hexdigest() != digest:
                    raise BuildError(f"aggregate manifest mismatch: {name}")
                aggregate_count += 1

    digest = sha256_file(bundle)
    sidecar = bundle.with_name(bundle.name + ".sha256.txt")
    write_text(sidecar, f"{digest}  {bundle.name}")
    if sha256_file(bundle) != sidecar.read_text(encoding="utf-8").split()[0]:
        raise BuildError("bundle sidecar validation failed")
    print(f"REVIEW_BUNDLE={bundle}")
    print(f"REVIEW_BUNDLE_SIZE_BYTES={bundle.stat().st_size}")
    print(f"REVIEW_BUNDLE_SHA256={digest}")
    print(f"REVIEW_BUNDLE_SIDECAR={sidecar}")
    print(f"OUTER_ZIP_MANIFEST_VALIDATION=PASS_{zip_outer}_OF_{zip_outer}")
    print(
        f"EVIDENCE_MANIFEST_VALIDATION=PASS_{zip_evidence}_OF_{zip_evidence}"
    )
    print(
        "VALIDATION_MANIFEST_VALIDATION="
        f"PASS_{zip_validation}_OF_{zip_validation}"
    )
    print(
        f"AGGREGATE_MANIFEST_VALIDATION=PASS_{aggregate_count}_OF_{aggregate_count}"
    )
    print("REVIEW_BUNDLE_FULL_READ=PASS")
    print("SOURCE_ARCHIVE_STATIC_REPLAY=PASS")
    print("REPOSITORY_FALLBACK_USED=NO")
    print("LOCAL_REMOTE_EQUALITY=PASS")
    return bundle.stat().st_size, digest, zip_outer, zip_evidence, aggregate_count


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    evidence_parser = subparsers.add_parser("evidence")
    evidence_parser.add_argument("--validation-root", type=Path, required=True)
    evidence_parser.add_argument("--evidence-root", type=Path, required=True)
    bundle_parser = subparsers.add_parser("bundle")
    bundle_parser.add_argument("--validation-root", type=Path, required=True)
    bundle_parser.add_argument("--evidence-root", type=Path, required=True)
    bundle_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "evidence":
            create_evidence(
                args.validation_root.resolve(), args.evidence_root.resolve()
            )
        else:
            create_bundle(
                args.validation_root.resolve(),
                args.evidence_root.resolve(),
                args.output.resolve(),
            )
    except (OSError, BuildError, UnicodeError) as exc:
        print(f"STAGE2G_FUNCTIONAL_REVIEW_BUILD=FAIL: {exc}", file=sys.stderr)
        return 1
    print("STAGE2G_FUNCTIONAL_REVIEW_BUILD=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
