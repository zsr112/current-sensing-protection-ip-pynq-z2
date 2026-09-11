#!/usr/bin/env python3
"""Safely replay the Stage 2H audit from a clean Git source archive."""

from __future__ import annotations

import argparse
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import shlex
import subprocess
import sys
import tarfile
import tempfile
from typing import BinaryIO


class ReplayError(RuntimeError):
    """Raised when source-archive integrity or replay cannot be proven."""


def safe_archive_name(name: str) -> bool:
    if not name or "\\" in name or "\x00" in name:
        return False
    posix = PurePosixPath(name)
    windows = PureWindowsPath(name)
    if posix.is_absolute() or windows.is_absolute() or windows.drive:
        return False
    return all(part not in {"", ".", ".."} for part in posix.parts)


def read_member_fully(stream: BinaryIO, expected_size: int) -> int:
    total = 0
    while True:
        chunk = stream.read(1024 * 1024)
        if not chunk:
            break
        total += len(chunk)
    if total != expected_size:
        raise ReplayError(
            "SOURCE_ARCHIVE_FULL_READ=FAIL_SIZE_MISMATCH: "
            f"expected={expected_size}, actual={total}"
        )
    return total


def validate_source_archive(path: Path) -> tuple[int, int]:
    seen: set[str] = set()
    regular_members = 0
    payload_bytes = 0
    try:
        archive = tarfile.open(path, "r:*")
    except (OSError, tarfile.TarError) as exc:
        raise ReplayError(f"SOURCE_ARCHIVE_OPEN=FAIL: {path}: {exc}") from exc
    with archive:
        for member in archive:
            if member.name in seen:
                raise ReplayError(
                    f"SOURCE_ARCHIVE_DUPLICATE_MEMBER=FAIL: {member.name}"
                )
            seen.add(member.name)
            if not safe_archive_name(member.name):
                raise ReplayError(
                    f"SOURCE_ARCHIVE_PATH_SAFETY=FAIL: {member.name}"
                )
            if member.isdir():
                continue
            if not member.isfile():
                raise ReplayError(
                    "SOURCE_ARCHIVE_UNSUPPORTED_MEMBER=FAIL: "
                    f"{member.name} type={member.type!r}"
                )
            stream = archive.extractfile(member)
            if stream is None:
                raise ReplayError(
                    f"SOURCE_ARCHIVE_FULL_READ=FAIL_UNREADABLE: {member.name}"
                )
            with stream:
                payload_bytes += read_member_fully(stream, member.size)
            regular_members += 1
    return regular_members, payload_bytes


def extract_source_archive(path: Path, destination: Path) -> tuple[int, int]:
    if destination.exists():
        raise ReplayError(f"SOURCE_ARCHIVE_DESTINATION=FAIL_EXISTS: {destination}")
    destination.mkdir(parents=True)
    regular_members = 0
    payload_bytes = 0
    with tarfile.open(path, "r:*") as archive:
        for member in archive:
            if not safe_archive_name(member.name):
                raise ReplayError(
                    f"SOURCE_ARCHIVE_PATH_SAFETY=FAIL: {member.name}"
                )
            target = destination.joinpath(*PurePosixPath(member.name).parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if not member.isfile():
                raise ReplayError(
                    "SOURCE_ARCHIVE_UNSUPPORTED_MEMBER=FAIL: "
                    f"{member.name} type={member.type!r}"
                )
            target.parent.mkdir(parents=True, exist_ok=True)
            stream = archive.extractfile(member)
            if stream is None:
                raise ReplayError(
                    f"SOURCE_ARCHIVE_EXTRACT=FAIL_UNREADABLE: {member.name}"
                )
            written = 0
            with stream, target.open("xb") as output:
                while True:
                    chunk = stream.read(1024 * 1024)
                    if not chunk:
                        break
                    output.write(chunk)
                    written += len(chunk)
            if written != member.size or target.stat().st_size != member.size:
                raise ReplayError(
                    "SOURCE_ARCHIVE_EXTRACT=FAIL_SIZE_MISMATCH: "
                    f"{member.name} expected={member.size}, actual={written}"
                )
            payload_bytes += written
            regular_members += 1
    return regular_members, payload_bytes


def parse_command(command: str) -> list[str]:
    parsed = shlex.split(command, posix=os.name != "nt")
    if not parsed:
        raise ReplayError("SOURCE_ARCHIVE_INTERPRETER_COMMAND=FAIL_EMPTY")
    return parsed


def run_command(command: list[str], *, cwd: Path) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            check=False,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except OSError as exc:
        raise ReplayError(
            "SOURCE_ARCHIVE_AUDIT_COMMAND=FAIL_UNAVAILABLE: "
            f"{subprocess.list2cmdline(command)}: {exc}"
        ) from exc


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value.rstrip() + "\n", encoding="utf-8", newline="\n")


def replay_source_archive(
    archive_path: Path,
    *,
    python_old: str,
    python_new: str,
    platform_label: str,
    output: Path | None,
) -> dict[str, object]:
    parse_command(python_old)
    parse_command(python_new)
    archive_path = archive_path.resolve()
    validated_members, validated_bytes = validate_source_archive(archive_path)

    with tempfile.TemporaryDirectory(prefix="stage2h_source_replay_") as temporary:
        extracted = Path(temporary) / "source"
        extracted_members, extracted_bytes = extract_source_archive(
            archive_path, extracted
        )
        if (extracted_members, extracted_bytes) != (
            validated_members,
            validated_bytes,
        ):
            raise ReplayError(
                "SOURCE_ARCHIVE_EXTRACT=FAIL_VALIDATION_COUNT_MISMATCH"
            )
        audit_script = extracted / "tools/stage2h_register_map_convergence_audit.py"
        if not audit_script.is_file():
            raise ReplayError(
                f"SOURCE_ARCHIVE_AUDIT_SCRIPT=FAIL_MISSING: {audit_script}"
            )
        unit_command = [
            sys.executable,
            "-m",
            "unittest",
            "tools.tests.test_stage2h_register_map_convergence_audit",
            "-v",
        ]
        unit_completed = run_command(unit_command, cwd=extracted)
        if unit_completed.returncode:
            raise ReplayError(
                "SOURCE_ARCHIVE_UNIT_TEST_COMMAND=FAIL_EXIT_"
                f"{unit_completed.returncode}:\n{unit_completed.stdout}"
            )
        if "OK" not in unit_completed.stdout:
            raise ReplayError(
                "SOURCE_ARCHIVE_UNIT_TEST_COMMAND=FAIL_MISSING_OK_MARKER"
            )
        command = [
            sys.executable,
            str(audit_script),
            "--root",
            str(extracted),
            "--no-git-scope-check",
            "--python-old",
            python_old,
            "--python-new",
            python_new,
        ]
        audit_output = None
        if output is not None:
            output = output.resolve()
            output.mkdir(parents=True, exist_ok=False)
            audit_output = output / "audit_reports"
            command.extend(["--output", str(audit_output)])
        completed = run_command(command, cwd=extracted)
        if completed.returncode:
            raise ReplayError(
                "SOURCE_ARCHIVE_AUDIT_COMMAND=FAIL_EXIT_"
                f"{completed.returncode}:\n{completed.stdout}"
            )
        if "STAGE2H_STATIC_CONTRACT_AUDIT=PASS" not in completed.stdout:
            raise ReplayError(
                "SOURCE_ARCHIVE_AUDIT_COMMAND=FAIL_MISSING_PASS_MARKER"
            )

    summary = {
        "platform": platform_label,
        "archive": str(archive_path),
        "members": validated_members,
        "payload_bytes": validated_bytes,
        "python_old_command": python_old,
        "python_new_command": python_new,
        "unit_test_stdout": unit_completed.stdout.rstrip(),
        "audit_stdout": completed.stdout.rstrip(),
    }
    if output is not None:
        write_text(
            output / "source_archive_replay_summary.txt",
            "\n".join(
                [
                    "SOURCE_ARCHIVE_REPLAY=PASS",
                    "SOURCE_ARCHIVE_PATH_SAFETY=PASS",
                    "SOURCE_ARCHIVE_DUPLICATE_MEMBER_CHECK=PASS",
                    "SOURCE_ARCHIVE_FULL_READ=PASS",
                    "REPOSITORY_FALLBACK_USED=NO",
                    f"PLATFORM={platform_label}",
                    f"ARCHIVE={archive_path}",
                    f"SOURCE_ARCHIVE_MEMBERS={validated_members}",
                    f"SOURCE_ARCHIVE_PAYLOAD_BYTES={validated_bytes}",
                    f"PYTHON_OLD_COMMAND={python_old}",
                    f"PYTHON_NEW_COMMAND={python_new}",
                    "",
                    "STAGE2H_UNIT_TEST_STDOUT",
                    unit_completed.stdout.rstrip(),
                    "",
                    "AUDIT_STDOUT",
                    completed.stdout.rstrip(),
                ]
            ),
        )
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--python-old", default=os.environ.get("STAGE2H_PYTHON_OLD"))
    parser.add_argument("--python-new", default=os.environ.get("STAGE2H_PYTHON_NEW"))
    parser.add_argument(
        "--platform-label", choices=("WINDOWS", "LINUX_OR_WSL"), required=True
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)

    missing = [
        name
        for name, value in (
            ("STAGE2H_PYTHON_OLD", args.python_old),
            ("STAGE2H_PYTHON_NEW", args.python_new),
        )
        if not value
    ]
    if missing:
        print(
            "SOURCE_ARCHIVE_INTERPRETER_COMMANDS=FAIL_MISSING: "
            + ",".join(missing),
            file=sys.stderr,
        )
        return 1
    try:
        result = replay_source_archive(
            args.archive,
            python_old=str(args.python_old),
            python_new=str(args.python_new),
            platform_label=args.platform_label,
            output=args.output,
        )
    except (ReplayError, OSError, tarfile.TarError) as exc:
        print(f"SOURCE_ARCHIVE_REPLAY=FAIL\n{exc}", file=sys.stderr)
        return 1

    print("SOURCE_ARCHIVE_REPLAY=PASS")
    print(f"SOURCE_ARCHIVE_PLATFORM={result['platform']}")
    print(f"SOURCE_ARCHIVE_MEMBERS={result['members']}")
    print(f"SOURCE_ARCHIVE_PAYLOAD_BYTES={result['payload_bytes']}")
    print("REPOSITORY_FALLBACK_USED=NO")
    print(f"SOURCE_ARCHIVE_STAGE2H_UNIT_TESTS_{result['platform']}=PASS")
    print(f"SOURCE_ARCHIVE_AUDIT_{result['platform']}=PASS")
    print("STAGE2H_UNIT_TEST_STDOUT_BEGIN")
    print(result["unit_test_stdout"])
    print("STAGE2H_UNIT_TEST_STDOUT_END")
    print("AUDIT_STDOUT_BEGIN")
    print(result["audit_stdout"])
    print("AUDIT_STDOUT_END")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
