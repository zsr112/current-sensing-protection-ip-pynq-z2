"""Cross-platform path containment and link/reparse-point checks."""
from __future__ import annotations

import os
import stat
from pathlib import Path, PurePosixPath


FILE_ATTRIBUTE_REPARSE_POINT = 0x400


def canonical(path: Path, *, strict: bool = False) -> Path:
    """Resolve a caller-selected root once, including system ancestor aliases."""
    return path.expanduser().resolve(strict=strict)


def is_link_or_reparse(path: Path) -> bool:
    info = path.lstat()
    return stat.S_ISLNK(info.st_mode) or bool(
        getattr(info, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT
    )


def safe_relative_path(relative: str) -> PurePosixPath:
    path = PurePosixPath(relative)
    if (
        not relative
        or path.is_absolute()
        or ".." in path.parts
        or ":" in relative
        or "\\" in relative
        or path.as_posix() != relative
    ):
        raise ValueError("Invalid relative path: " + str(relative))
    return path


def path_below_root(root: Path, relative: str, *, require_exists: bool = True) -> Path:
    """Return a lexical child while rejecting every link below the root boundary."""
    root = canonical(root, strict=True)
    name = safe_relative_path(relative)
    current = root
    for part in name.parts:
        current = current / part
        try:
            if is_link_or_reparse(current):
                raise ValueError("Link or reparse point is not allowed below root: " + relative)
        except FileNotFoundError:
            if require_exists:
                raise
            break
    resolved = canonical(current, strict=require_exists)
    if not resolved.is_relative_to(root):
        raise ValueError("Path escapes selected root: " + relative)
    return current


def regular_files(root: Path) -> dict[str, Path]:
    """Inventory regular files without following links or directory reparse points."""
    root = canonical(root, strict=True)
    files = {}
    pending = [root]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                path = Path(entry.path)
                relative = path.relative_to(root).as_posix()
                info = entry.stat(follow_symlinks=False)
                if stat.S_ISLNK(info.st_mode) or bool(
                    getattr(info, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT
                ):
                    raise ValueError("Link or reparse point is not allowed below root: " + relative)
                if stat.S_ISDIR(info.st_mode):
                    pending.append(path)
                elif stat.S_ISREG(info.st_mode):
                    files[relative] = path
                else:
                    raise ValueError("Unsupported filesystem entry: " + relative)
    return files
