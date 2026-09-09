#!/usr/bin/env python3
"""Safely replay Stage 2H-A2 generator checks from a source ZIP."""

from __future__ import annotations

import argparse
import hashlib
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


class ReplayError(RuntimeError):
    """The source archive or extracted register-map replay failed."""


REQUIRED_PATHS = {
    "spec/register_map.json",
    "spec/register_map.schema.json",
    "spec/stage2h_register_map_convergence.json",
    "tools/generate_register_map.py",
    "tools/check_register_map_implementation.py",
    "tools/tests/test_register_map_generator.py",
    "rtl/fault_defs.vh",
    "rtl/protection_reg_bank.v",
    "sw/protection_ip_interface.py",
    "sw/tests/test_protection_ip_interface.py",
    *{
        "rtl/generated/protection_register_map.vh",
        "sw/generated/protection_register_map.py",
        "sw/ps_register_demo/protection_ip_regs.h",
        "fpga/vivado/generated/protection_register_map_ipxact.tcl",
        "docs/implementation/register_map.md",
        "tb/generated/protection_register_map.svh",
        "spec/generated/protection_register_map_compatibility.json",
        "spec/generated/protection_register_map_conformance.json",
    },
}

PRECOMMIT_MATRIX_ARCHIVE_SHA256 = (
    "279e85493511e4011cea4b71401c490c9eb8ccdb3f9b1269205f90e65335f6a6"
)
GENERATED_ARTIFACT_PATHS = {
    "rtl/generated/protection_register_map.vh",
    "sw/generated/protection_register_map.py",
    "sw/ps_register_demo/protection_ip_regs.h",
    "fpga/vivado/generated/protection_register_map_ipxact.tcl",
    "docs/implementation/register_map.md",
    "tb/generated/protection_register_map.svh",
    "spec/generated/protection_register_map_compatibility.json",
    "spec/generated/protection_register_map_conformance.json",
}
LIVE_SPEC_PATHS = {"spec/register_map.json", "spec/register_map.schema.json"}
SOFTWARE_INTERFACE_PATHS = {
    "sw/protection_ip_interface.py",
    "sw/generated/protection_register_map.py",
}
STAGE2G_BUILD_SOURCE_PATHS = {
    "fpga/vivado/package_protection_ip_stage2_axi_lite.tcl",
    "fpga/vivado/build/config/stage1d_build_config.dict",
    "fpga/vivado/build/config/stage1e_phase2_synthesis_config_v1.dict",
    "fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl",
    "tools/run_stage2f_width_sequence_boundary.py",
}
STAGE2G_BEHAVIORAL_INPUT_PATHS = {
    *LIVE_SPEC_PATHS,
    *GENERATED_ARTIFACT_PATHS,
    *SOFTWARE_INTERFACE_PATHS,
    "tools/stage2g_reference_model.py",
    "tools/run_stage2g_functional_rtl.py",
    "tools/run_stage2g_mutations.py",
    *STAGE2G_BUILD_SOURCE_PATHS,
}

# The preserved behavioral matrix ran before this exact, finite closure set.
# Any other changed path invalidates reuse until the affected matrix is rerun.
APPROVED_POST_MATRIX_CHANGED_PATHS = frozenset(
    {
        "sw/stage2c9e_b_pynq_mmio_register_smoke.py",
        "tools/board_validation/build_stage1_board_execution_package.py",
        "tools/board_validation/stage1_board_functional_validation.py",
        "tools/build_current_release.py",
        "tools/check_register_map_implementation.py",
        "tools/check_stage2g_recovery_snapshots.py",
        "tools/generate_register_map.py",
        "tools/replay_register_map_source_archive.py",
        "tools/stage2g_reset_wait_first_fault_policy_audit.py",
        "tools/tests/test_register_map_generator.py",
        "tools/tests/test_stage2g_reset_wait_first_fault_policy_audit.py",
    }
)

TARGETED_VALIDATION_MARKERS = {
    "sw/stage2c9e_b_pynq_mmio_register_smoke.py": (
        "ACTIVE_CONSUMER_BINDING_COVERAGE=PASS_5_OF_5",
        "STAGE2C9E_EFFECTIVE_REGISTER_VALUES_FROM_GENERATED_AUTHORITY=PASS",
    ),
    "tools/board_validation/build_stage1_board_execution_package.py": (
        "BOARD_VALIDATION_PACKAGE_TESTS=PASS",
    ),
    "tools/board_validation/stage1_board_functional_validation.py": (
        "BOARD_VALIDATION_TESTS=PASS_19_OF_19",
        "BOARD_VALIDATION_EFFECTIVE_REGISTER_VALUES_FROM_GENERATED_AUTHORITY=PASS",
    ),
    "tools/build_current_release.py": (
        "RELEASE_BUILDER_TESTS=PASS_6_OF_6",
        "STANDALONE_EXAMPLE_BINDING=PASS",
        "RENDERED_EXAMPLE_EFFECTIVE_REGISTER_VALUES_FROM_GENERATED_AUTHORITY=PASS",
    ),
    "tools/check_register_map_implementation.py": (
        "REGISTER_MAP_IMPLEMENTATION_CHECK=PASS",
        "ACTIVE_CONSUMER_BINDING_COVERAGE=PASS_5_OF_5",
        "ACTIVE_REGISTER_CONTAINER_VALUE_BINDING_COVERAGE=PASS_3_OF_3",
    ),
    "tools/check_stage2g_recovery_snapshots.py": (
        "RECOVERY_SNAPSHOT_ORACLE_PARITY=PASS",
    ),
    "tools/generate_register_map.py": (
        "GENERATOR_DETERMINISTIC=PASS",
        "GENERATED_ARTIFACT_DRIFT_CHECK=PASS_8_OF_8",
    ),
    "tools/replay_register_map_source_archive.py": (
        "COVERAGE_BOUNDARY_INDEPENDENT_REPLAY=PASS",
        "MATRIX_REUSE_MUTATIONS=PASS_5_OF_5",
    ),
    "tools/stage2g_reset_wait_first_fault_policy_audit.py": (
        "STAGE2G_STATIC_CONTRACT_AUDIT=PASS",
    ),
    "tools/tests/test_register_map_generator.py": (
        "A2_LEGACY_ABI_MUTATION_SUITE=PASS_20_OF_20",
        "A2_CONSUMER_PROVENANCE_MUTATIONS=PASS_6_OF_6",
        "ACTIVE_CONSUMER_BINDING_MUTATIONS=PASS_8_OF_8",
        "ACTIVE_REGISTER_CONTAINER_BINDING_MUTATIONS=PASS_4_OF_4",
        "STAGE2C9E_CONTAINER_VALUE_LITERAL_MUTATION=DETECTED",
        "BOARD_VALIDATION_CONTAINER_VALUE_LITERAL_MUTATION=DETECTED",
        "RENDERED_EXAMPLE_CONTAINER_VALUE_LITERAL_MUTATION=DETECTED",
        "GENERATED_REGISTER_KEY_VALUE_MISMATCH_MUTATION=DETECTED",
        "RECOVERY_SNAPSHOT_ORACLE_PARITY_MUTATION=DETECTED",
        "ACTIVE_CONSUMER_MMIO_RECEIVER_ALIAS_BYPASS=DETECTED",
        "ACTIVE_CONSUMER_GENERATED_BINDING_UNUSED=DETECTED",
        "NEW_UNCLASSIFIED_MMIO_CONSUMER_MUTATION=DETECTED",
        "ARBITRARY_NAME_MMIO_CONSUMER_DISCOVERY=PASS",
    ),
    "tools/tests/test_stage2g_reset_wait_first_fault_policy_audit.py": (
        "STAGE2G_FROZEN_AUDIT_UNIT_TESTS=PASS_14_OF_14",
    ),
}


def safe_name(name: str) -> bool:
    if not name or "\\" in name or "\x00" in name or name.startswith("/"):
        return False
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        return False
    return not (path.parts and ":" in path.parts[0])


def validate_archive(path: Path) -> tuple[list[zipfile.ZipInfo], int]:
    try:
        with zipfile.ZipFile(path, "r") as archive:
            bad = archive.testzip()
            if bad is not None:
                raise ReplayError(f"source archive CRC failure: {bad}")
            members = archive.infolist()
            names: set[str] = set()
            folded: set[str] = set()
            total = 0
            for member in members:
                name = member.filename.rstrip("/")
                if member.is_dir():
                    continue
                if not safe_name(name):
                    raise ReplayError(f"unsafe source archive member: {member.filename!r}")
                if name in names or name.casefold() in folded:
                    raise ReplayError(f"duplicate source archive member: {name}")
                mode = member.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ReplayError(f"source archive symlink is forbidden: {name}")
                names.add(name)
                folded.add(name.casefold())
                total += member.file_size
            missing = sorted(REQUIRED_PATHS - names)
            if missing:
                raise ReplayError(f"source archive omits A2 replay inputs: {missing}")
            return [item for item in members if not item.is_dir()], total
    except (OSError, zipfile.BadZipFile) as exc:
        raise ReplayError(f"invalid source archive: {path}: {exc}") from exc


def extract_archive(path: Path, destination: Path) -> tuple[int, int]:
    members, expected_bytes = validate_archive(path)
    written = 0
    with zipfile.ZipFile(path, "r") as archive:
        for member in members:
            target = destination.joinpath(*PurePosixPath(member.filename).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member, "r") as source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            written += target.stat().st_size
    if written != expected_bytes:
        raise ReplayError(
            f"source archive extraction byte mismatch: expected={expected_bytes} actual={written}"
        )
    return len(members), written


def run_command(root: Path, command: list[str], label: str) -> str:
    completed = subprocess.run(
        command,
        cwd=root,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode != 0:
        raise ReplayError(
            f"{label} failed with exit {completed.returncode}:\n{completed.stdout}"
        )
    return completed.stdout


def replay(archive: Path, output: Path | None = None) -> str:
    validated_members, byte_count = validate_archive(archive)
    with tempfile.TemporaryDirectory(prefix="stage2h-a2-source-replay-") as temporary:
        extracted = Path(temporary) / "source"
        extracted.mkdir()
        extracted_count, extracted_bytes = extract_archive(archive, extracted)
        if (len(validated_members), byte_count) != (extracted_count, extracted_bytes):
            raise ReplayError("validated and extracted source archive inventories differ")

        commands = (
            (
                "generator_drift",
                [sys.executable, "tools/generate_register_map.py", "--check"],
                "GENERATED_ARTIFACT_DRIFT_CHECK=PASS_8_OF_8",
            ),
            (
                "implementation",
                [sys.executable, "tools/check_register_map_implementation.py"],
                "REGISTER_MAP_IMPLEMENTATION_CHECK=PASS",
            ),
            (
                "mutations",
                [sys.executable, "tools/tests/test_register_map_generator.py"],
                "A2_LEGACY_ABI_MUTATION_SUITE=PASS_20_OF_20",
            ),
            (
                "software",
                [
                    sys.executable,
                    "-m",
                    "unittest",
                    "sw.tests.test_protection_ip_interface",
                    "-v",
                ],
                "OK",
            ),
        )
        logs: dict[str, str] = {}
        for label, command, marker in commands:
            text = run_command(extracted, command, label)
            if marker not in text:
                raise ReplayError(f"{label} replay omitted marker: {marker}")
            logs[label] = text

        summary = "\n".join(
            (
                "SOURCE_ARCHIVE_GENERATOR_REPLAY=PASS",
                "REPOSITORY_FALLBACK_USED=NO",
                "SOURCE_ARCHIVE_FULL_READ=PASS",
                "SOURCE_ARCHIVE_PATH_SAFETY=PASS",
                "SOURCE_ARCHIVE_DUPLICATE_PATHS=0",
                f"SOURCE_ARCHIVE_FILE_COUNT={extracted_count}",
                f"SOURCE_ARCHIVE_UNCOMPRESSED_BYTES={extracted_bytes}",
                "SOURCE_ARCHIVE_GENERATOR_DRIFT=PASS_8_OF_8",
                "SOURCE_ARCHIVE_MUTATIONS=PASS_20_OF_20",
                "SOURCE_ARCHIVE_SOFTWARE_TESTS=PASS",
                "",
            )
        )
        if output is not None:
            if output.exists():
                raise ReplayError(f"output directory already exists: {output}")
            output.mkdir(parents=True)
            (output / "source_archive_replay.txt").write_text(
                summary, encoding="utf-8", newline="\n"
            )
            for label, text in logs.items():
                (output / f"{label}.log").write_text(
                    text, encoding="utf-8", newline="\n"
                )
        return summary


def _archive_inventory(path: Path) -> dict[str, tuple[int, str]]:
    members, _ = validate_archive(path)
    inventory: dict[str, tuple[int, str]] = {}
    with zipfile.ZipFile(path, "r") as archive:
        for member in members:
            inventory[member.filename.rstrip("/")] = (
                member.file_size,
                hashlib.sha256(archive.read(member)).hexdigest(),
            )
    return inventory


def _inventory_text(inventory: dict[str, tuple[int, str]]) -> str:
    return "".join(
        f"{path}\t{size}\t{digest}\n"
        for path, (size, digest) in sorted(inventory.items())
    )


def _count_changed(changed: set[str], allowed: set[str]) -> int:
    return len(changed & allowed)


def validate_matrix_reuse_change_set(
    changed: set[str],
    added: set[str],
    removed: set[str],
    targeted_validation_text: str | None,
) -> dict[str, object]:
    """Apply the finite post-matrix policy without inferring dependencies."""
    unapproved = sorted(changed - APPROVED_POST_MATRIX_CHANGED_PATHS)
    validation_text = targeted_validation_text or ""
    missing = sorted(
        path
        for path in changed & APPROVED_POST_MATRIX_CHANGED_PATHS
        if any(
            marker not in validation_text
            for marker in TARGETED_VALIDATION_MARKERS[path]
        )
    )
    return {
        "unapproved": unapproved,
        "missing_targeted_validation": missing,
        "behavioral_inputs_changed": bool(added or removed or unapproved),
        "valid": not added and not removed and not unapproved and not missing,
    }


def replay_coverage_boundary(
    precommit: Path,
    final: Path,
    output: Path | None = None,
    targeted_validation: Path | None = None,
) -> str:
    precommit_digest = hashlib.sha256(precommit.read_bytes()).hexdigest()
    if precommit_digest != PRECOMMIT_MATRIX_ARCHIVE_SHA256:
        raise ReplayError(
            "precommit matrix archive SHA256 mismatch: "
            f"{precommit_digest} != {PRECOMMIT_MATRIX_ARCHIVE_SHA256}"
        )
    before = _archive_inventory(precommit)
    after = _archive_inventory(final)
    before_text = _inventory_text(before)
    after_text = _inventory_text(after)
    before_inventory_digest = hashlib.sha256(before_text.encode("utf-8")).hexdigest()
    after_inventory_digest = hashlib.sha256(after_text.encode("utf-8")).hexdigest()
    added = sorted(set(after) - set(before))
    removed = sorted(set(before) - set(after))
    changed = sorted(path for path in set(before) & set(after) if before[path] != after[path])
    changed_set = set(changed)
    targeted_text = (
        targeted_validation.read_text(encoding="utf-8")
        if targeted_validation is not None
        else None
    )
    policy = validate_matrix_reuse_change_set(
        changed_set,
        set(added),
        set(removed),
        targeted_text,
    )
    lines = [
        f"PRECOMMIT_MATRIX_SOURCE_ARCHIVE={precommit.resolve()}",
        f"PRECOMMIT_MATRIX_SOURCE_ARCHIVE_SHA256={precommit_digest}",
        f"FINAL_SOURCE_ARCHIVE={final.resolve()}",
        f"FINAL_SOURCE_ARCHIVE_SHA256={hashlib.sha256(final.read_bytes()).hexdigest()}",
        f"PRECOMMIT_FILE_COUNT={len(before)}",
        f"FINAL_FILE_COUNT={len(after)}",
        f"ARCHIVE_ADDED_PATHS={len(added)}",
        f"ARCHIVE_REMOVED_PATHS={len(removed)}",
        f"PRECOMMIT_SOURCE_INVENTORY_SHA256={before_inventory_digest}",
        f"FINAL_SOURCE_INVENTORY_SHA256={after_inventory_digest}",
        "ADDED_PATHS=" + ("<none>" if not added else ",".join(added)),
        "REMOVED_PATHS=" + ("<none>" if not removed else ",".join(removed)),
        "CHANGED_FILES=" + ("<none>" if not changed else ",".join(changed)),
        f"RTL_BYTE_DIFF_COUNT={_count_changed(changed_set, {path for path in after if path.startswith('rtl/')})}",
        f"LIVE_SPEC_BYTE_DIFF_COUNT={_count_changed(changed_set, LIVE_SPEC_PATHS)}",
        f"LIVE_SCHEMA_BYTE_DIFF_COUNT={_count_changed(changed_set, {'spec/register_map.schema.json'})}",
        f"GENERATED_ARTIFACT_BYTE_DIFF_COUNT={_count_changed(changed_set, GENERATED_ARTIFACT_PATHS)}",
        f"SOFTWARE_INTERFACE_BYTE_DIFF_COUNT={_count_changed(changed_set, SOFTWARE_INTERFACE_PATHS)}",
        f"BUILD_SOURCE_BYTE_DIFF_COUNT={_count_changed(changed_set, STAGE2G_BUILD_SOURCE_PATHS)}",
        f"STAGE2G_BEHAVIORAL_INPUT_BYTE_DIFF_COUNT={_count_changed(changed_set, STAGE2G_BEHAVIORAL_INPUT_PATHS)}",
        "FULL_MATRIX_REUSE_POLICY=EXACT_APPROVED_POST_MATRIX_CHANGE_SET",
        f"APPROVED_POST_MATRIX_CHANGE_SET_SIZE={len(APPROVED_POST_MATRIX_CHANGED_PATHS)}",
        f"APPROVED_POST_MATRIX_CHANGED_PATHS={len(changed_set & APPROVED_POST_MATRIX_CHANGED_PATHS)}",
        f"UNAPPROVED_POST_MATRIX_CHANGED_PATHS={len(policy['unapproved'])}",
        f"APPROVED_POST_MATRIX_CHANGED_PATHS_WITHOUT_TARGETED_VALIDATION={len(policy['missing_targeted_validation'])}",
        "UNAPPROVED_PATHS="
        + ("<none>" if not policy["unapproved"] else ",".join(policy["unapproved"])),
        "MISSING_TARGETED_VALIDATION="
        + (
            "<none>"
            if not policy["missing_targeted_validation"]
            else ",".join(policy["missing_targeted_validation"])
        ),
        "FULL_MATRIX_BEHAVIORAL_INPUTS_CHANGED=NO"
        if not policy["behavioral_inputs_changed"]
        else "FULL_MATRIX_BEHAVIORAL_INPUTS_CHANGED=YES",
        "COVERAGE_BOUNDARY_INDEPENDENT_REPLAY=PASS",
        "FULL_BEHAVIORAL_MATRIX_REUSE_VALID=YES"
        if policy["valid"]
        else "FULL_BEHAVIORAL_MATRIX_REUSE_VALID=NO",
        "",
    ]
    summary = "\n".join(lines)
    if output is not None:
        if output.exists():
            raise ReplayError(f"output directory already exists: {output}")
        output.mkdir(parents=True)
        (output / "precommit_source_inventory_sha256.txt").write_text(
            before_text, encoding="utf-8", newline="\n"
        )
        (output / "final_source_inventory_sha256.txt").write_text(
            after_text, encoding="utf-8", newline="\n"
        )
        (output / "coverage_boundary_replay.txt").write_text(
            summary, encoding="utf-8", newline="\n"
        )
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, nargs="?")
    parser.add_argument("--compare-precommit", type=Path)
    parser.add_argument("--compare-final", type=Path)
    parser.add_argument("--targeted-validation", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.compare_precommit is not None or args.compare_final is not None:
            if args.compare_precommit is None or args.compare_final is None:
                raise ReplayError("both --compare-precommit and --compare-final are required")
            print(
                replay_coverage_boundary(
                    args.compare_precommit.resolve(),
                    args.compare_final.resolve(),
                    args.output.resolve() if args.output is not None else None,
                    args.targeted_validation.resolve()
                    if args.targeted_validation is not None
                    else None,
                ),
                end="",
            )
            return 0
        if args.archive is None:
            raise ReplayError("archive is required for source replay")
        print(
            replay(
                args.archive.resolve(),
                args.output.resolve() if args.output is not None else None,
            ),
            end="",
        )
    except (ReplayError, OSError) as exc:
        print(f"SOURCE_ARCHIVE_GENERATOR_REPLAY=FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
