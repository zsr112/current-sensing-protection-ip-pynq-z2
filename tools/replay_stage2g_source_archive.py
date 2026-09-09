#!/usr/bin/env python3
"""Extract and statically replay a Stage 2G source archive without Git."""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import subprocess
import sys
import unicodedata
import zipfile
from pathlib import Path, PurePosixPath


class ReplayError(RuntimeError):
    """Raised when an archive cannot be replayed independently."""


def canonical_member(name: str) -> str:
    if (
        not name
        or "\\" in name
        or "\x00" in name
        or any(part == "" for part in name.split("/"))
    ):
        raise ReplayError(f"unsafe source archive member: {name!r}")
    normalized = unicodedata.normalize("NFC", name)
    if normalized != name:
        raise ReplayError(f"non-canonical source archive member: {name!r}")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ReplayError(f"unsafe source archive member: {name!r}")
    return path.as_posix()


def extract_archive(archive_path: Path, destination: Path) -> int:
    if destination.exists():
        raise ReplayError(f"replay output must not already exist: {destination}")
    destination.mkdir(parents=True)
    seen: set[str] = set()
    file_count = 0
    with zipfile.ZipFile(archive_path, "r") as archive:
        bad = archive.testzip()
        if bad is not None:
            raise ReplayError(f"source archive CRC failure: {bad}")
        for member in archive.infolist():
            name = canonical_member(member.filename.rstrip("/"))
            identity = name.casefold()
            if identity in seen:
                raise ReplayError(f"duplicate source archive member: {name}")
            seen.add(identity)
            mode = member.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise ReplayError(f"source archive symlink is forbidden: {name}")
            target = destination.joinpath(*PurePosixPath(name).parts)
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member, "r") as source, target.open("xb") as sink:
                shutil.copyfileobj(source, sink)
            file_count += 1
    if file_count == 0:
        raise ReplayError("source archive is empty")
    return file_count


def replay(
    archive_path: Path, output: Path, *, cleanup_repository: bool
) -> tuple[int, str]:
    repository = output / "repository"
    file_count = extract_archive(archive_path, repository)
    checker = repository / "tools/check_stage2g_implementation.py"
    if not checker.is_file():
        raise ReplayError("source archive omits the Stage 2G static checker")
    environment = os.environ.copy()
    environment["STAGE2G_FORBID_GIT"] = "1"
    result = subprocess.run(
        [
            sys.executable,
            str(checker),
            "--root",
            str(repository),
            "--no-git-check",
        ],
        cwd=repository,
        env=environment,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    transcript = result.stdout
    required = (
        "STAGE2G_IMPLEMENTATION_STATIC=PASS",
        "REPOSITORY_FALLBACK_USED=NO",
    )
    if result.returncode != 0 or any(marker not in transcript for marker in required):
        raise ReplayError(
            "archive static checker failed\n" + transcript.rstrip()
        )
    summary = transcript.rstrip() + "\n" + "\n".join(
        (
            "SOURCE_ARCHIVE_STATIC_REPLAY=PASS",
            "REPOSITORY_FALLBACK_USED=NO",
            f"SOURCE_ARCHIVE_REPLAY_FILES={file_count}",
        )
    ) + "\n"
    (output / "source_archive_replay_result.txt").write_text(
        summary, encoding="utf-8", newline="\n"
    )
    if cleanup_repository:
        shutil.rmtree(repository)
    return file_count, summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cleanup-repository", action="store_true")
    args = parser.parse_args(argv)
    try:
        archive_path = args.archive.resolve(strict=True)
        _, summary = replay(
            archive_path,
            args.output.resolve(),
            cleanup_repository=args.cleanup_repository,
        )
    except (OSError, ReplayError, zipfile.BadZipFile) as exc:
        print(f"SOURCE_ARCHIVE_STATIC_REPLAY=FAIL: {exc}", file=sys.stderr)
        return 1
    print(summary, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
