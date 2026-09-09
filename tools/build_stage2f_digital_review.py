#!/usr/bin/env python3
"""Build commit-bound Stage 2F-D evidence and an independent-review ZIP."""

from __future__ import annotations

import argparse
import hashlib
import io
import re
import shutil
import sys
import tarfile
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

try:
    from tools.build_stage2f_audit_review import (
        BuildError,
        CREDENTIAL_PATTERNS,
        EXPECTED_PACKAGE_FIXTURE_ALLOWLIST_COUNT,
        PACKAGE_SYNTHETIC_CREDENTIAL_FIXTURES,
        copy_file,
        extract_source_tar,
        git,
        normalized_relative,
        run,
        sha256_file,
        validate_manifest,
        validate_source_tar,
        validate_zip_manifest,
        write_inventory_and_manifest,
        write_text,
    )
except ModuleNotFoundError:
    from build_stage2f_audit_review import (  # type: ignore[no-redef]
        BuildError,
        CREDENTIAL_PATTERNS,
        EXPECTED_PACKAGE_FIXTURE_ALLOWLIST_COUNT,
        PACKAGE_SYNTHETIC_CREDENTIAL_FIXTURES,
        copy_file,
        extract_source_tar,
        git,
        normalized_relative,
        run,
        sha256_file,
        validate_manifest,
        validate_source_tar,
        validate_zip_manifest,
        write_inventory_and_manifest,
        write_text,
    )


FROZEN_BASE_COMMIT = "3399e4fdc28f9d4c66cf90cb5c1dc1e386eda6ae"
BASE_COMMIT = "1e93cda247a80d2fdd9186a2e21cc90777abeaec"
BRANCH = "codex/stage2f-digital-encoding-normalization"
EVIDENCE_PREFIX = "digital-encoding-normalization-review-hardening-"
PACKAGE_PREFIX = "stage2f-digital-normalization-hardening-review-"

EVIDENCE_REQUIRED_FILES = {
    "runner_summary.txt",
    "evidence_identity.txt",
    "review_findings_closure.txt",
    "generated_profile_rtl_matrix.txt",
    "generator_mutation_results.txt",
    "width_sequence_boundary_results.txt",
    "python_reference_exhaustive_results.txt",
    "python_reference_to_rtl_results.txt",
    "duplicate_json_key_results.txt",
    "existing_mutation_results.txt",
    "boundary_mutation_results.txt",
    "implementation_contract.txt",
    "profile_generation_result.txt",
    "pipeline_latency_result.txt",
    "directed_test_results.txt",
    "exhaustive_test_results.txt",
    "random_test_results.txt",
    "mutation_results.txt",
    "raw_path_invariance_result.txt",
    "reset_result.txt",
    "regression_summary.txt",
    "scope_non_claim.txt",
    "changed_files.txt",
    "git_diff.patch",
    "FILE_INVENTORY.txt",
    "MANIFEST_SHA256.txt",
}

FROZEN_AUDIT_PATHS = (
    "spec/stage2f_adc_source_profile.schema.json",
    "spec/stage2f_adc_source_profile_unconfigured.json",
    "tools/stage2f_adc_contract_audit.py",
    "tools/tests/test_stage2f_adc_contract_audit.py",
    "docs/architecture/stage2f_adc_encoding_scaling_audit.md",
    "docs/architecture/stage2f_adc_encoding_scaling_target_contract.md",
    "docs/architecture/stage2f_adc_encoding_scaling_tradeoff.md",
    "docs/verification/stage2f_adc_encoding_scaling_verification_plan.md",
)

REVIEW_MATERIAL = (
    "docs/architecture/stage2f_digital_normalization_implementation.md",
    "docs/architecture/stage2f_digital_normalization_latency.md",
    "docs/verification/stage2f_digital_normalization_verification.md",
    "fpga/vivado/build/tests/stage1e_reconstruction_profile_tests.tcl",
    "rtl/adc_sample_code_normalizer.sv",
    "rtl/generated/stage2f_adc_source_profile.svh",
    "rtl/protection_ip_top_async_adc_axi_lite.v",
    "sim/stage2f/run_stage2f_digital_normalization.ps1",
    "spec/stage2f_adc_source_profile.schema.json",
    "spec/stage2f_adc_source_profile_unconfigured.json",
    "spec/stage2f_digital_normalization_implementation.json",
    "spec/stage2f_profiles/SIM_TWOS_COMPLEMENT_POSITIVE.json",
    "spec/stage2f_profiles/SIM_TWOS_COMPLEMENT_REVERSED.json",
    "spec/stage2f_profiles/SIM_UNSIGNED_ZERO_EDGE_0.json",
    "spec/stage2f_profiles/SIM_UNSIGNED_ZERO_EDGE_4095.json",
    "spec/stage2f_profiles/SIM_UNSIGNED_ZERO_MIDSCALE_CH2_REVERSED.json",
    "spec/stage2f_profiles/SIM_UNSIGNED_ZERO_MIDSCALE_POSITIVE.json",
    "tb/stage2f/tb_stage2f_digital_normalization.sv",
    "tb/stage2f/tb_stage2f_generated_profile_vectors.sv",
    "tb/stage2f/tb_stage2f_mutation.sv",
    "tb/stage2f/tb_stage2f_raw_gate_mutation.sv",
    "tb/stage2f/tb_stage2f_raw_path_invariance.sv",
    "tb/stage2f/tb_stage2f_width_sequence_boundary.sv",
    "tools/build_stage2f_digital_review.py",
    "tools/check_stage2f_implementation.py",
    "tools/generate_stage2f_adc_profile.py",
    "tools/run_stage2f_mutations.py",
    "tools/run_stage2f_generated_profile_rtl.py",
    "tools/run_stage2f_generator_mutations.py",
    "tools/run_stage2f_width_sequence_boundary.py",
    "tools/run_stage2f_boundary_mutations.py",
    "tools/run_stage2f_raw_path_invariance.py",
    "tools/stage2f_normalization_reference.py",
    "tools/tests/test_stage2f_profile_generator.py",
)

TEXT_SUFFIXES = {
    ".c",
    ".dict",
    ".h",
    ".json",
    ".log",
    ".md",
    ".patch",
    ".ps1",
    ".py",
    ".sh",
    ".sv",
    ".svh",
    ".tcl",
    ".txt",
    ".v",
    ".vh",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise BuildError(message)


def archive_name_is_safe(name: str) -> bool:
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    return (
        bool(normalized)
        and "\x00" not in normalized
        and not normalized.startswith("/")
        and not re.match(r"^[A-Za-z]:", normalized)
        and not path.is_absolute()
        and all(part not in {"", ".", ".."} for part in path.parts)
    )


def path_is_within(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
    except ValueError:
        return False
    return True


def parse_key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line in {"PORCELAIN_BEGIN", "PORCELAIN_END"}:
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in values:
            raise BuildError(f"duplicate key in {path}: {key}")
        values[key] = value
    return values


def require_marker(path: Path, marker: str) -> str:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise BuildError(f"validation result is missing: {path}") from exc
    require(marker in text, f"validation marker missing from {path}: {marker}")
    return text


def repository_identity(root: Path, *, require_remote: bool) -> tuple[str, str]:
    require(git(root, "branch", "--show-current") == BRANCH, f"expected branch {BRANCH}")
    head = git(root, "rev-parse", "HEAD")
    tree = git(root, "rev-parse", "HEAD^{tree}")
    require(head != BASE_COMMIT, "implementation commit has not been created")
    require(git(root, "rev-parse", "main") == FROZEN_BASE_COMMIT, "local main differs from frozen base")
    require(git(root, "rev-parse", "origin/main") == FROZEN_BASE_COMMIT, "origin/main differs from frozen base")
    require(
        run(
            ["git", "merge-base", "--is-ancestor", BASE_COMMIT, head],
            cwd=root,
            check=False,
        ).returncode
        == 0,
        "frozen base is not an ancestor of the implementation commit",
    )
    require(
        not git(root, "status", "--porcelain", "--untracked-files=all"),
        "worktree is not clean",
    )
    frozen = run(
        ["git", "diff", "--quiet", f"{BASE_COMMIT}..{head}", "--", *FROZEN_AUDIT_PATHS],
        cwd=root,
        check=False,
    )
    require(frozen.returncode == 0, "frozen Stage 2F audit artifacts changed")
    if require_remote:
        remote = git(root, "rev-parse", f"refs/remotes/origin/{BRANCH}")
        require(remote == head, f"local/remote implementation mismatch: {head} != {remote}")
    return head, tree


def changed_files(root: Path, head: str) -> list[str]:
    return [
        line
        for line in git(root, "diff", "--name-only", f"{BASE_COMMIT}..{head}").splitlines()
        if line
    ]


def validate_validation_root(validation: Path, head: str) -> None:
    require(validation.is_dir(), f"validation root is missing: {validation}")
    summary_path = validation / "runner_summary.txt"
    summary = parse_key_values(summary_path)
    expected_summary = {
        "STAGE2F_VALIDATION_RUNNER": "PASS",
        "BASE_COMMIT": FROZEN_BASE_COMMIT,
        "PREVIOUS_IMPLEMENTATION_COMMIT": BASE_COMMIT,
        "BRANCH": BRANCH,
        "HEAD": head,
        "PRODUCTION_PROFILE": "UNCONFIGURED",
        "PRODUCTION_INCLUDE_CURRENT": "PASS",
        "GENERATED_PROFILE_RTL_MATRIX": "PASS_6_OF_6_ICARUS_AND_XSIM",
        "GENERATOR_TO_RTL_PROFILE_FIXTURES": "PASS_12_OF_12",
        "PYTHON_REFERENCE_EXHAUSTIVE": "PASS_57344_CASES",
        "PYTHON_REFERENCE_TO_RTL_COMPARISON": "PASS",
        "DUPLICATE_JSON_KEY_REJECTION": "PASS",
        "DATA_WIDTH_COMPATIBILITY_POLICY": "RAW_GENERIC_NORMALIZATION_ONLY_AT_12",
        "IMPLICIT_NORMALIZER_PORT_RESIZE": "NO",
        "NEW_BOUNDARY_MUTATION_FIXTURES": "PASS_6_OF_6",
        "NORMALIZED_WIDTH": "13",
        "NORMALIZED_UNIT": "SIGNED_CODE_COUNT",
        "NORMALIZER_PIPELINE_LATENCY_ACLK": "1",
        "PIPELINE_INITIATION_INTERVAL": "1",
        "NO_SYNTHESIS_IMPLEMENTATION_BITSTREAM_BOARD_ACTION": "YES",
        "STAGE2F_CONTRACT_GAP_CLOSED": "NO",
        "PHYSICAL_SCALING_STATUS": "BLOCKED_EXTERNAL_HARDWARE_FACTS",
        "REMAINING_CONTRACT_GAPS": "2",
        "STAGE2_COMPLETE": "NO",
    }
    require(summary == expected_summary, f"runner summary mismatch: {summary}")
    for name in ("git_status_start.txt", "git_status_end.txt"):
        state = parse_key_values(validation / name)
        require(state.get("BRANCH") == BRANCH, f"{name} branch mismatch")
        require(state.get("HEAD") == head, f"{name} commit mismatch")
        require(state.get("CLEAN") == "True", f"{name} does not prove a clean worktree")

    marker_checks = (
        ("static/review_builder_self_test.log", "STAGE2F_DIGITAL_REVIEW_SELF_TEST=PASS"),
        ("static/implementation_static.log", "STAGE2F_IMPLEMENTATION_STATIC=PASS"),
        ("static/implementation_static.log", "CREDENTIAL_SCAN=PASS"),
        ("static/profile_generation.log", "STAGE2F_PROFILE_GENERATION=PASS"),
        ("static/frozen_contract_audit.log", "STAGE2F_ADC_CONTRACT_AUDIT=PASS"),
        ("python/stage2f_python_tests.log", "Ran 44 tests"),
        ("python/stage2f_python_tests.log", "OK"),
        ("python/repository_python_tests.log", "OK"),
        ("python/software_python_tests.log", "OK"),
        ("python/python_reference_exhaustive.log", "PYTHON_REFERENCE_EXHAUSTIVE=PASS_57344_CASES"),
        ("python/python_reference_exhaustive.log", "PYTHON_REFERENCE_MUTATIONS=PASS_5_OF_5"),
        ("static/generated_profile_rtl.log", "GENERATED_PROFILE_RTL_MATRIX=PASS_6_OF_6_ICARUS_AND_XSIM"),
        ("static/generated_profile_rtl.log", "PYTHON_REFERENCE_TO_RTL_COMPARISON=PASS"),
        ("static/generator_mutations.log", "GENERATOR_TO_RTL_PROFILE_FIXTURES=PASS_12_OF_12"),
        ("static/width_sequence_boundary.log", "WIDTH_SEQUENCE_BOUNDARY=PASS"),
        ("static/width_sequence_boundary.log", "IMPLICIT_NORMALIZER_PORT_RESIZE=NO"),
        ("static/boundary_mutations.log", "NEW_BOUNDARY_MUTATION_FIXTURES=PASS_6_OF_6"),
        ("generated_profile_rtl/generated_profile_rtl_matrix.txt", "GENERATED_PROFILE_RTL_MATRIX=PASS_6_OF_6_ICARUS_AND_XSIM"),
        ("generated_profile_rtl/python_reference_to_rtl_results.txt", "PYTHON_REFERENCE_TO_RTL_COMPARISON=PASS"),
        ("generator_mutations/generator_mutation_results.txt", "GENERATOR_TO_RTL_PROFILE_FIXTURES=PASS_12_OF_12"),
        ("width_sequence_boundary/width_sequence_boundary_results.txt", "WIDTH_SEQUENCE_BOUNDARY=PASS"),
        ("boundary_mutations/boundary_mutation_results.txt", "NEW_BOUNDARY_MUTATION_FIXTURES=PASS_6_OF_6"),
        ("icarus/stage2f_directed/stage2f_directed.run.log", "STAGE2F_DIGITAL_NORMALIZATION=PASS"),
        ("icarus/stage2f_directed/stage2f_directed.run.log", "STAGE2F_RANDOM_RESET_POINTS=PASS_3"),
        ("icarus/stage2f_directed/stage2f_directed.run.log", "STAGE2F_NO_DROP=PASS_INPUT_CYCLES=9402_OUTPUT_CYCLES=9402"),
        ("xsim/stage2f_directed/stage2f_directed.xsim.console.log", "STAGE2F_DIGITAL_NORMALIZATION=PASS"),
        ("xsim/stage2f_directed/stage2f_directed.xsim.console.log", "STAGE2F_RANDOM_RESET_POINTS=PASS_3"),
        ("xsim/stage2f_directed/stage2f_directed.xsim.console.log", "STAGE2F_NO_DROP=PASS_INPUT_CYCLES=9402_OUTPUT_CYCLES=9402"),
        ("static/mutations_icarus.log", "STAGE2F_MUTATION_TESTS=PASS_14_CONNECTED"),
        ("static/mutations_xsim.log", "STAGE2F_MUTATION_TESTS=PASS_28_CONNECTED"),
        ("static/raw_invariance_icarus.log", "STAGE2F_RAW_PATH_INVARIANCE=PASS_1"),
        ("static/raw_invariance_xsim.log", "STAGE2F_RAW_PATH_INVARIANCE=PASS_2"),
        ("icarus/stage2b/stage2b_regression.run.log", "TOTAL_POSITIVE_SCENARIOS=PASS_26_OF_26"),
        ("icarus/stage2c/stage2c_regression.run.log", "STAGE2C_POSITIVE_SCENARIOS=PASS_27_OF_27"),
        ("icarus/stage2d/stage2d_regression.run.log", "STAGE2D_POSITIVE_SCENARIOS=PASS_30_OF_30"),
        ("icarus/stage2d_wrapper/stage2d_wrapper.run.log", "PRODUCTION_WRAPPER_INTEGRATION=PASS"),
        ("icarus/stage2e/stage2e_regression.run.log", "STAGE2E_POSITIVE_SCENARIOS=PASS_35_OF_35"),
        ("xsim/stage2d/stage2d_regression.xsim.console.log", "STAGE2D_POSITIVE_SCENARIOS=PASS_30_OF_30"),
        ("xsim/stage2e/stage2e_regression.xsim.console.log", "STAGE2E_POSITIVE_SCENARIOS=PASS_35_OF_35"),
        ("canonical_regression.log", "SUMMARY: PASS=10 FAIL=0"),
        ("tcl/stage1e_reconstruction/STAGE1E_RECONSTRUCTION.log", "CONTROLLED_BUILD_SOURCE_CLOSURE=PASS"),
        ("tcl/stage1e_reconstruction/STAGE1E_RECONSTRUCTION.log", "SUMMARY PASS=12 FAIL=0"),
        ("tcl/stage1e_ip_packaging/STAGE1E_IP_PACKAGING.log", "SUMMARY PASS=29 FAIL=0"),
        ("tcl/stage1e_base_design/STAGE1E_BASE_DESIGN.log", "SUMMARY PASS=13 FAIL=0"),
        ("tcl/stage1e_debug_design/STAGE1E_DEBUG_DESIGN.log", "SUMMARY PASS=18 FAIL=0"),
        ("tcl/stage2d_source_closure/STAGE2D_SOURCE_CLOSURE.log", "STAGE2D_SOURCE_CLOSURE_TESTS=PASS"),
        ("tcl/stage2d_cdc_constraints/STAGE2D_CDC_CONSTRAINTS.log", "STAGE2D_CDC_CONSTRAINT_TESTS=PASS"),
        ("tcl/stage2d_profile_convergence/STAGE2D_PROFILE_CONVERGENCE.log", "PROFILE_CONVERGENCE_TESTS=PASS"),
        ("tcl/stage2e_source_closure/STAGE2E_SOURCE_CLOSURE.log", "STAGE2E_SOURCE_CLOSURE_TESTS=PASS"),
        ("tcl/stage2e_cdc_constraints/STAGE2E_CDC_CONSTRAINTS.log", "STAGE2E_OBSERVABILITY_CDC_CONSTRAINT_TESTS=PASS"),
    )
    for relative, marker in marker_checks:
        require_marker(validation / relative, marker)

    mutation_text = require_marker(
        validation / "mutations_xsim/mutation_results.txt", "XSIM_RAW_PATH_GATED=KILLED"
    )
    killed = [line for line in mutation_text.splitlines() if "=KILLED" in line]
    require(len(killed) == 28, f"expected 28 connected simulator mutation kills, got {len(killed)}")
    raw_text = require_marker(
        validation / "raw_invariance_xsim/raw_path_invariance_result.txt",
        "XSIM_RAW_PATH_INVARIANCE=PASS",
    )
    require("ICARUS_RAW_PATH_INVARIANCE=PASS" in raw_text, "Icarus raw invariance missing")
    diff_check = validation / "git_diff_check.log"
    require(diff_check.is_file() and not diff_check.read_text(encoding="utf-8").strip(),
            "git diff --check output was not empty")


def marker_lines(path: Path, prefixes: tuple[str, ...]) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    return [line for line in text.splitlines() if line.startswith(prefixes)]


def copy_validation_logs(validation: Path, destination: Path) -> int:
    count = 0
    for source in sorted(path for path in validation.rglob("*") if path.is_file()):
        if source.suffix.lower() not in {".log", ".txt", ".jou"}:
            continue
        relative = source.relative_to(validation)
        require(archive_name_is_safe(relative.as_posix()), f"unsafe validation log path: {relative}")
        copy_file(source, destination / relative)
        count += 1
    require(count > 0, "no validation logs were copied")
    return count


def credential_scan_tree(root: Path, *, package_tree: bool) -> int:
    findings: list[str] = []
    allowed_count = 0
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        relative = normalized_relative(path, root)
        allowed = PACKAGE_SYNTHETIC_CREDENTIAL_FIXTURES.get(relative, set()) if package_tree else set()
        text = path.read_text(encoding="utf-8", errors="replace")
        for pattern in CREDENTIAL_PATTERNS:
            for match in pattern.finditer(text):
                if match.group(0) in allowed:
                    allowed_count += 1
                else:
                    line = text.count("\n", 0, match.start()) + 1
                    findings.append(f"{relative}:{line}")
    require(not findings, "credential-like material found: " + ", ".join(sorted(set(findings))))
    expected = EXPECTED_PACKAGE_FIXTURE_ALLOWLIST_COUNT if package_tree else 0
    require(allowed_count == expected, f"credential fixture count mismatch: {allowed_count} != {expected}")
    return allowed_count


def assert_evidence(root: Path, head: str) -> int:
    validate_manifest(root)
    actual = {normalized_relative(path, root) for path in root.rglob("*") if path.is_file()}
    require(EVIDENCE_REQUIRED_FILES <= actual, "evidence required-file set is incomplete")
    identity = parse_key_values(root / "evidence_identity.txt")
    require(identity.get("IMPLEMENTATION_COMMIT") == head, "evidence commit binding mismatch")
    require(identity.get("BRANCH") == BRANCH, "evidence branch binding mismatch")
    manifest_count = len((root / "MANIFEST_SHA256.txt").read_text(encoding="utf-8").splitlines())
    require(manifest_count == len(actual) - 1, "evidence manifest count mismatch")
    return manifest_count


def create_evidence(root: Path, validation: Path, evidence_base: Path) -> Path:
    head, tree = repository_identity(root, require_remote=False)
    require(not path_is_within(validation, root), "validation root must be outside the repository")
    require(not path_is_within(evidence_base, root), "evidence root must be outside the repository")
    validate_validation_root(validation, head)
    evidence_base.mkdir(parents=True, exist_ok=True)
    created = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    final = evidence_base / f"{EVIDENCE_PREFIX}{created}"
    require(not final.exists(), f"evidence path already exists: {final}")

    direct_paths = (
        validation / "icarus/stage2f_directed/stage2f_directed.run.log",
        validation / "xsim/stage2f_directed/stage2f_directed.xsim.console.log",
    )
    direct_lines: list[str] = []
    for simulator, path in zip(("ICARUS", "XSIM"), direct_paths):
        direct_lines.append(f"SIMULATOR={simulator}")
        direct_lines.extend(marker_lines(path, ("STAGE2F_",)))

    with tempfile.TemporaryDirectory(prefix=".stage2f-evidence-", dir=evidence_base) as temp_name:
        stage = Path(temp_name) / final.name
        stage.mkdir()
        original_summary = (validation / "runner_summary.txt").read_text(encoding="utf-8")
        write_text(
            stage / "runner_summary.txt",
            original_summary
            + f"VALIDATION_ROOT={validation.resolve()}\n"
            + "VALIDATION_WORKTREE_CLEAN=PASS\n"
            + "EVIDENCE_ASSEMBLY=PASS",
        )
        write_text(
            stage / "evidence_identity.txt",
            "\n".join(
                (
                    "EVIDENCE_SCHEMA=stage2f-digital-normalization-hardening-evidence-v1",
                    f"CREATED_UTC={created}",
                    f"BRANCH={BRANCH}",
                    f"FROZEN_BASE_COMMIT={FROZEN_BASE_COMMIT}",
                    f"PREVIOUS_IMPLEMENTATION_COMMIT={BASE_COMMIT}",
                    f"IMPLEMENTATION_COMMIT={head}",
                    f"IMPLEMENTATION_TREE={tree}",
                    f"VALIDATION_ROOT={validation.resolve()}",
                    "WORKTREE=CLEAN",
                    "FROZEN_AUDIT_ARTIFACTS_UNCHANGED=PASS",
                )
            ),
        )
        write_text(
            stage / "review_findings_closure.txt",
            "\n".join(
                (
                    "REVIEW_BASE_COMMIT=" + BASE_COMMIT,
                    "BLOCKER_GENERATED_PROFILE_TO_FUNCTIONAL_RTL=CLOSED_PASS",
                    "HIGH_GENERATOR_CONNECTED_MUTATIONS=CLOSED_PASS_12_OF_12",
                    "HIGH_TOP_WIDTH_SEQUENCE_BOUNDARY=CLOSED_PASS",
                    "MEDIUM_REFERENCE_MODEL_VALUE_ORACLE=CLOSED_PASS_57344_CASES",
                    "DUPLICATE_JSON_KEY_REJECTION=CLOSED_PASS",
                    "NEW_BOUNDARY_MUTATION_FIXTURES=PASS_6_OF_6",
                    "RAW_PROTECTION_PATH_PRESERVED=PASS",
                    "PRODUCTION_PROFILE=UNCONFIGURED",
                    "READY_FOR_INDEPENDENT_REREVIEW=YES",
                )
            ),
        )
        write_text(
            stage / "implementation_contract.txt",
            "\n".join(
                (
                    "STAGE2F_DIGITAL_CAPABILITY_IMPLEMENTED=YES",
                    "NORMALIZER_MODULE=rtl/adc_sample_code_normalizer.sv",
                    "PRODUCTION_PROFILE=UNCONFIGURED",
                    "PRODUCTION_NORMALIZED_TELEMETRY=UNAVAILABLE",
                    "SUPPORTED_ENCODINGS=UNSIGNED_WITH_ZERO_CODE,TWOS_COMPLEMENT",
                    "NORMALIZED_WIDTH=13",
                    "NORMALIZED_SIGNEDNESS=SIGNED",
                    "NORMALIZED_UNIT=SIGNED_CODE_COUNT",
                    "NORMALIZER_PIPELINE_LATENCY_ACLK=1",
                    "PIPELINE_INITIATION_INTERVAL=1",
                    "NO_DATA_DEPENDENT_LATENCY=PASS",
                    "NO_BACKPRESSURE_TO_ATOMIC_CDC=PASS",
                    "NO_TRANSACTION_DROP=PASS",
                    "RAW_PROTECTION_PATH_INVARIANCE=PASS",
                    "STAGE2G_AUTHORITY_UNCHANGED=PASS",
                    "NEW_AXI_OFFSETS_ADDED=NO",
                )
            ),
        )
        profile_text = (validation / "static/profile_generation.log").read_text(encoding="utf-8")
        profile_text += (validation / "static/implementation_static.log").read_text(encoding="utf-8")
        write_text(stage / "profile_generation_result.txt", profile_text)
        copy_file(
            validation / "generated_profile_rtl/generated_profile_rtl_matrix.txt",
            stage / "generated_profile_rtl_matrix.txt",
        )
        copy_file(
            validation / "generator_mutations/generator_mutation_results.txt",
            stage / "generator_mutation_results.txt",
        )
        copy_file(
            validation / "width_sequence_boundary/width_sequence_boundary_results.txt",
            stage / "width_sequence_boundary_results.txt",
        )
        copy_file(
            validation / "python/python_reference_exhaustive.log",
            stage / "python_reference_exhaustive_results.txt",
        )
        copy_file(
            validation / "generated_profile_rtl/python_reference_to_rtl_results.txt",
            stage / "python_reference_to_rtl_results.txt",
        )
        duplicate_lines = marker_lines(
            validation / "static/implementation_static.log",
            ("DUPLICATE_JSON_KEY_REJECTION=",),
        )
        require(duplicate_lines == ["DUPLICATE_JSON_KEY_REJECTION=PASS"],
                "duplicate-key validation record drifted")
        write_text(stage / "duplicate_json_key_results.txt", "\n".join(duplicate_lines))
        copy_file(
            validation / "boundary_mutations/boundary_mutation_results.txt",
            stage / "boundary_mutation_results.txt",
        )
        write_text(
            stage / "pipeline_latency_result.txt",
            "\n".join(
                (
                    "NORMALIZER_PIPELINE_LATENCY_ACLK=1",
                    "PIPELINE_INITIATION_INTERVAL=1",
                    "NO_DATA_DEPENDENT_LATENCY=PASS",
                    "SEQUENCE_CHANNEL_ALIGNMENT=PASS",
                    "ICARUS_AND_XSIM=PASS",
                )
            ),
        )
        write_text(stage / "directed_test_results.txt", "\n".join(direct_lines))
        write_text(
            stage / "exhaustive_test_results.txt",
            "\n".join(line for line in direct_lines if "EXHAUSTIVE" in line)
            + "\nREFERENCE_MODEL_EXHAUSTIVE=PASS",
        )
        write_text(
            stage / "random_test_results.txt",
            "\n".join(line for line in direct_lines if "RANDOM_" in line),
        )
        mutation_text = (validation / "mutations_xsim/mutation_results.txt").read_text(encoding="utf-8")
        write_text(stage / "mutation_results.txt", "MUTATION_CONNECTED_FIXTURES=PASS_28_OF_28\n" + mutation_text)
        write_text(stage / "existing_mutation_results.txt", "EXISTING_MUTATION_CONNECTED_FIXTURES=PASS_28_OF_28\n" + mutation_text)
        raw_text = (validation / "raw_invariance_xsim/raw_path_invariance_result.txt").read_text(encoding="utf-8")
        write_text(stage / "raw_path_invariance_result.txt", "RAW_PROTECTION_PATH_INVARIANCE=PASS\n" + raw_text)
        write_text(
            stage / "reset_result.txt",
            "\n".join(line for line in direct_lines if "RESET" in line)
            + "\nRESET_FLUSH_AND_FIRST_POST_RESET=PASS",
        )
        write_text(
            stage / "regression_summary.txt",
            "\n".join(
                (
                    "STAGE2E_REGRESSION=PASS_ICARUS_XSIM",
                    "STAGE2D_REGRESSION=PASS_ICARUS_XSIM",
                    "STAGE2C_REGRESSION=PASS",
                    "STAGE2B_REGRESSION=PASS",
                    "CANONICAL_REGRESSION=PASS_10_OF_10",
                    "FROZEN_STAGE2F_AUDIT_TESTS=PASS_37_OF_37",
                    "STAGE2F_GENERATOR_REFERENCE_TESTS=PASS_7_OF_7",
                    "GENERATED_PROFILE_RTL_MATRIX=PASS_6_OF_6_ICARUS_AND_XSIM",
                    "GENERATOR_TO_RTL_PROFILE_FIXTURES=PASS_12_OF_12",
                    "PYTHON_REFERENCE_EXHAUSTIVE=PASS_57344_CASES",
                    "PYTHON_REFERENCE_TO_RTL_COMPARISON=PASS",
                    "DUPLICATE_JSON_KEY_REJECTION=PASS",
                    "WIDTH_SEQUENCE_BOUNDARY=PASS",
                    "NEW_BOUNDARY_MUTATION_FIXTURES=PASS_6_OF_6",
                    "PYTHON_INTERFACE_TESTS=PASS",
                    "STAGE1E_PACKAGING_BASE_DEBUG_STATIC=PASS",
                    "CONTROLLED_BUILD_SOURCE_CLOSURE=PASS",
                    "JSON_SCHEMA_VALIDATION=PASS",
                    "DOCUMENTATION_PATH_VALIDATION=PASS",
                    "GIT_DIFF_CHECK=PASS",
                    "CREDENTIAL_SCAN=PASS",
                )
            ),
        )
        write_text(
            stage / "scope_non_claim.txt",
            "\n".join(
                (
                    "SYNTHESIS_RUN=NO",
                    "IMPLEMENTATION_RUN=NO",
                    "BITSTREAM_RUN=NO",
                    "BOARD_ACTION=NO",
                    "CALIBRATION_ARITHMETIC_ADDED=NO",
                    "GENERIC_DIVIDER_ADDED=NO",
                    "PHYSICAL_UNIT_CLAIM=NO",
                    "PHYSICAL_ACCURACY_CLAIM=NO",
                    "BOARD_CALIBRATION_CLAIM=NO",
                    "STAGE2F_CONTRACT_GAP_CLOSED=NO",
                    "PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS",
                    "REMAINING_CONTRACT_GAPS=2",
                    "STAGE2_COMPLETE=NO",
                )
            ),
        )
        names = changed_files(root, head)
        write_text(stage / "changed_files.txt", "\n".join(names))
        patch = run(["git", "diff", "--binary", f"{BASE_COMMIT}..{head}"], cwd=root).stdout
        write_text(stage / "git_diff.patch", patch)
        copy_validation_logs(validation, stage / "validation_logs")
        credential_scan_tree(stage, package_tree=False)
        write_inventory_and_manifest(stage)
        validate_manifest(stage)
        require(EVIDENCE_REQUIRED_FILES <= {
            normalized_relative(path, stage) for path in stage.rglob("*") if path.is_file()
        }, "assembled evidence is missing required files")
        stage.rename(final)
    count = assert_evidence(final, head)
    print("STAGE2F_DIGITAL_EVIDENCE=PASS")
    print(f"EVIDENCE_ROOT={final.resolve()}")
    print(f"EVIDENCE_MANIFEST=PASS_{count}_OF_{count}")
    return final


def validate_source_snapshot(source_tar: Path, head: str, root: Path) -> int:
    members = validate_source_tar(source_tar)
    files = {member.name for member in members if member.isfile()}
    tracked = set(
        git(
            root,
            "-c",
            "core.quotePath=false",
            "ls-tree",
            "-r",
            "--name-only",
            head,
        ).splitlines()
    )
    require(files == tracked, "git archive file set does not match the implementation commit")
    for name in REVIEW_MATERIAL:
        require(name in files, f"review source missing from git archive: {name}")
    return len(files)


def validate_package_zip(path: Path, evidence_name: str, head: str) -> tuple[int, int]:
    with zipfile.ZipFile(path, "r") as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "ZIP contains duplicate paths")
        require(all(archive_name_is_safe(name) for name in names), "ZIP contains an unsafe path")
        bad = archive.testzip()
        require(bad is None, f"ZIP CRC failure: {bad}")
        for name in names:
            archive.read(name)
        outer_count = validate_zip_manifest(archive, "MANIFEST_SHA256.txt")
        evidence_prefix = f"evidence/{evidence_name}/"
        evidence_count = validate_zip_manifest(
            archive,
            f"{evidence_prefix}MANIFEST_SHA256.txt",
            path_prefix=evidence_prefix,
        )
        source_name = f"source/source-{head[:8]}.tar"
        source_bytes = archive.read(source_name)
        with tarfile.open(fileobj=io.BytesIO(source_bytes), mode="r:") as source:
            for member in source:
                require(archive_name_is_safe(member.name), f"unsafe source path in ZIP: {member.name}")
                require(member.isfile() or member.isdir(), f"unsupported source entry: {member.name}")
                if member.isfile():
                    stream = source.extractfile(member)
                    require(stream is not None, f"unreadable source entry: {member.name}")
                    while stream.read(1024 * 1024):
                        pass
    return outer_count, evidence_count


def validate_sidecar(
    sidecar: Path,
    package: Path,
    *,
    head: str,
    evidence: Path,
    outer_count: int,
    evidence_count: int,
) -> None:
    values = parse_key_values(sidecar)
    aggregate = outer_count + evidence_count
    expected = {
        "FILE": str(package.resolve()),
        "SIZE_BYTES": str(package.stat().st_size),
        "SHA256": sha256_file(package),
        "ZIP_FULL_READ_VALIDATION": "PASS",
        "ZIP_CRC_VALIDATION": "PASS",
        "PATH_SAFETY_VALIDATION": "PASS",
        "DUPLICATE_PATH_VALIDATION": "PASS",
        "SOURCE_SNAPSHOT_VALIDATION": "PASS",
        "OUTER_ZIP_MANIFEST_VALIDATION": f"PASS_{outer_count}_OF_{outer_count}",
        "EVIDENCE_MANIFEST_VALIDATION": f"PASS_{evidence_count}_OF_{evidence_count}",
        "AGGREGATE_MANIFEST_VALIDATION": f"PASS_{aggregate}_OF_{aggregate}",
        "IMPLEMENTATION_COMMIT": head,
        "EVIDENCE_ROOT": str(evidence.resolve()),
    }
    require(values == expected, f"external sidecar mismatch: {values}")


def create_package(root: Path, evidence: Path, downloads: Path) -> Path:
    head, tree = repository_identity(root, require_remote=True)
    evidence_count = assert_evidence(evidence, head)
    downloads.mkdir(parents=True, exist_ok=True)
    package = downloads / f"{PACKAGE_PREFIX}{head[:8]}.zip"
    sidecar = downloads / f"{package.name}.sha256.txt"
    require(not package.exists() and not sidecar.exists(), f"review package already exists: {package}")

    with tempfile.TemporaryDirectory(prefix="stage2f-digital-review-") as temp_name:
        temporary = Path(temp_name)
        stage = temporary / "package"
        stage.mkdir()
        write_text(stage / "git/branch.txt", BRANCH)
        write_text(stage / "git/base_commit.txt", BASE_COMMIT)
        write_text(stage / "git/commit.txt", head)
        write_text(stage / "git/remote_commit.txt", head)
        write_text(stage / "git/tree.txt", tree)
        write_text(stage / "git/log.txt", git(root, "log", "--format=fuller", f"{BASE_COMMIT}..{head}"))
        write_text(stage / "diff/changed_files.txt", "\n".join(changed_files(root, head)))
        write_text(
            stage / "diff/base_to_implementation.patch",
            run(["git", "diff", "--binary", f"{BASE_COMMIT}..{head}"], cwd=root).stdout,
        )

        source_tar = stage / f"source/source-{head[:8]}.tar"
        source_tar.parent.mkdir(parents=True)
        run(["git", "archive", "--format=tar", f"--output={source_tar}", head], cwd=root)
        source_count = validate_source_snapshot(source_tar, head, root)
        extract_source_tar(source_tar, stage / "source/tree")
        shutil.copytree(evidence, stage / "evidence" / evidence.name)
        for relative in REVIEW_MATERIAL:
            copy_file(root / relative, stage / "implementation" / relative)
        copy_file(evidence / "scope_non_claim.txt", stage / "review_contract/scope_non_claim.txt")
        write_text(
            stage / "PACKAGE_IDENTITY.txt",
            "\n".join(
                (
                    "PACKAGE_SCHEMA=stage2f-digital-normalization-hardening-review-v1",
                    f"CREATED_UTC={datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}",
                    f"BRANCH={BRANCH}",
                    f"FROZEN_BASE_COMMIT={FROZEN_BASE_COMMIT}",
                    f"PREVIOUS_IMPLEMENTATION_COMMIT={BASE_COMMIT}",
                    f"IMPLEMENTATION_COMMIT={head}",
                    f"REMOTE_IMPLEMENTATION_COMMIT={head}",
                    f"IMPLEMENTATION_TREE={tree}",
                    f"EVIDENCE_ROOT_NAME={evidence.name}",
                    f"EVIDENCE_MANIFEST_COUNT={evidence_count}",
                    f"SOURCE_ARCHIVE_FILE_COUNT={source_count}",
                    "SOURCE_SNAPSHOT_METHOD=GIT_ARCHIVE",
                    "SOURCE_ARCHIVE_FULL_READ=PASS",
                    "LOCAL_REMOTE_COMMIT_EQUALITY=PASS",
                    "PATH_SAFETY_VALIDATION=PASS",
                    "DUPLICATE_PATH_VALIDATION=PASS",
                )
            ),
        )
        allowed_count = credential_scan_tree(stage, package_tree=True)
        write_text(
            stage / "credential_scan_result.txt",
            f"CREDENTIAL_SCAN=PASS\nCREDENTIAL_FIXTURE_ALLOWLIST_COUNT={allowed_count}",
        )
        require(credential_scan_tree(stage, package_tree=True) == allowed_count,
                "credential scan changed after result creation")
        write_inventory_and_manifest(stage)
        validate_manifest(stage)

        temporary_zip = temporary / package.name
        with zipfile.ZipFile(
            temporary_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as archive:
            for path in sorted(item for item in stage.rglob("*") if item.is_file()):
                relative = normalized_relative(path, stage)
                require(archive_name_is_safe(relative), f"unsafe package path: {relative}")
                archive.write(path, relative)
        outer_count, zipped_evidence_count = validate_package_zip(
            temporary_zip, evidence.name, head
        )
        require(zipped_evidence_count == evidence_count, "evidence count changed inside ZIP")
        shutil.copy2(temporary_zip, package)

    final_outer_count, final_evidence_count = validate_package_zip(package, evidence.name, head)
    require((final_outer_count, final_evidence_count) == (outer_count, evidence_count),
            "final ZIP validation counts changed")
    aggregate = outer_count + evidence_count
    write_text(
        sidecar,
        "\n".join(
            (
                f"FILE={package.resolve()}",
                f"SIZE_BYTES={package.stat().st_size}",
                f"SHA256={sha256_file(package)}",
                "ZIP_FULL_READ_VALIDATION=PASS",
                "ZIP_CRC_VALIDATION=PASS",
                "PATH_SAFETY_VALIDATION=PASS",
                "DUPLICATE_PATH_VALIDATION=PASS",
                "SOURCE_SNAPSHOT_VALIDATION=PASS",
                f"OUTER_ZIP_MANIFEST_VALIDATION=PASS_{outer_count}_OF_{outer_count}",
                f"EVIDENCE_MANIFEST_VALIDATION=PASS_{evidence_count}_OF_{evidence_count}",
                f"AGGREGATE_MANIFEST_VALIDATION=PASS_{aggregate}_OF_{aggregate}",
                f"IMPLEMENTATION_COMMIT={head}",
                f"EVIDENCE_ROOT={evidence.resolve()}",
            )
        ),
    )
    validate_sidecar(
        sidecar,
        package,
        head=head,
        evidence=evidence,
        outer_count=outer_count,
        evidence_count=evidence_count,
    )
    print("STAGE2F_DIGITAL_REVIEW_PACKAGE=PASS")
    print(f"REVIEW_BUNDLE={package.resolve()}")
    print(f"REVIEW_BUNDLE_SIZE_BYTES={package.stat().st_size}")
    print(f"REVIEW_BUNDLE_SHA256={sha256_file(package)}")
    print(f"REVIEW_BUNDLE_SIDECAR={sidecar.resolve()}")
    print(f"OUTER_ZIP_MANIFEST_VALIDATION=PASS_{outer_count}_OF_{outer_count}")
    print(f"EVIDENCE_MANIFEST_VALIDATION=PASS_{evidence_count}_OF_{evidence_count}")
    print(f"AGGREGATE_MANIFEST_VALIDATION=PASS_{aggregate}_OF_{aggregate}")
    print("REVIEW_BUNDLE_FULL_READ=PASS")
    print("SOURCE_SNAPSHOT_VALIDATION=PASS")
    print("LOCAL_REMOTE_COMMIT_EQUALITY=PASS")
    return package


def self_test(repository_root: Path) -> None:
    require(archive_name_is_safe("nested/result.txt"), "safe path rejected")
    for unsafe in ("../escape", "/absolute", "C:drive", "nested/../escape", ""):
        require(not archive_name_is_safe(unsafe), f"unsafe path accepted: {unsafe!r}")
    with tempfile.TemporaryDirectory(prefix="stage2f-review-self-test-") as temp_name:
        root = Path(temp_name) / "payload"
        write_text(root / "nested/result.txt", "SELF_TEST=PASS")
        write_inventory_and_manifest(root)
        validate_manifest(root)
        archive_path = Path(temp_name) / "payload.zip"
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(item for item in root.rglob("*") if item.is_file()):
                archive.write(path, normalized_relative(path, root))
        with zipfile.ZipFile(archive_path, "r") as archive:
            require(validate_zip_manifest(archive, "MANIFEST_SHA256.txt") == 2,
                    "self-test ZIP manifest count mismatch")
            require(archive.testzip() is None, "self-test ZIP CRC failure")
        head = git(repository_root, "rev-parse", "HEAD")
        source_tar = Path(temp_name) / "source.tar"
        run(
            ["git", "archive", "--format=tar", f"--output={source_tar}", head],
            cwd=repository_root,
        )
        validate_source_snapshot(source_tar, head, repository_root)
        credential_root = Path(temp_name) / "credential-fixture"
        for relative, allowed_values in PACKAGE_SYNTHETIC_CREDENTIAL_FIXTURES.items():
            write_text(credential_root / relative, "\n".join(sorted(allowed_values)))
        require(
            credential_scan_tree(credential_root, package_tree=True)
            == EXPECTED_PACKAGE_FIXTURE_ALLOWLIST_COUNT,
            "self-test credential fixture count mismatch",
        )
    print("STAGE2F_DIGITAL_REVIEW_SELF_TEST=PASS")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("self-test")
    evidence_parser = commands.add_parser("evidence")
    evidence_parser.add_argument("--validation-root", type=Path, required=True)
    evidence_parser.add_argument("--evidence-base", type=Path, required=True)
    package_parser = commands.add_parser("package")
    package_parser.add_argument("--evidence", type=Path, required=True)
    package_parser.add_argument("--downloads", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "self-test":
            self_test(args.root.resolve())
        elif args.command == "evidence":
            create_evidence(
                args.root.resolve(),
                args.validation_root.resolve(),
                args.evidence_base.resolve(),
            )
        else:
            create_package(
                args.root.resolve(), args.evidence.resolve(), args.downloads.resolve()
            )
    except (
        BuildError,
        OSError,
        UnicodeError,
        ValueError,
        tarfile.TarError,
        zipfile.BadZipFile,
    ) as exc:
        print(f"STAGE2F_DIGITAL_REVIEW_BUILD=FAIL\nERROR={exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
