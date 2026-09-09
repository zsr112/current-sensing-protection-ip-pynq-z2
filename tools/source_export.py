#!/usr/bin/env python3
"""Export and verify a complete committed source tree without Git history."""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import io
import json
import subprocess
import tarfile
from pathlib import Path, PurePosixPath

MANIFEST = "SOURCE_MANIFEST.json"


def identity(path):
    data = path.read_bytes()
    return {"size_bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")


def verify(root):
    root = root.resolve(strict=True)
    manifest = json.loads((root / MANIFEST).read_text(encoding="utf-8"))
    if manifest.get("schema") != "csip-source-export-v1":
        raise ValueError("Invalid source manifest schema")
    actual = set()
    for path in root.rglob("*"):
        if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
            raise ValueError("Links are not permitted in source exports")
        if path.is_file() and path != root / MANIFEST:
            actual.add(path.relative_to(root).as_posix())
    if actual != set(manifest["files"]):
        raise ValueError(f"Source file inventory mismatch: missing={set(manifest['files']) - actual}, extra={actual - set(manifest['files'])}")
    for relative, expected in manifest["files"].items():
        path = PurePosixPath(relative)
        if path.is_absolute() or ".." in path.parts or "\\" in relative or ":" in relative:
            raise ValueError(f"Invalid manifest path: {relative}")
        if identity(root / relative) != expected:
            raise ValueError(f"Source file changed: {relative}")
    return manifest


def select_files(names, selection):
    if selection is None:
        return set(names)
    if selection.get('schema') != 'csip-source-selection-v1':
        raise ValueError('Invalid source selection schema')
    selected = {name for name in names if any(fnmatch.fnmatchcase(name, pattern) for pattern in selection['include'])}
    for pattern, reason in selection.get('exclude', {}).items():
        if not reason.strip():
            raise ValueError('Every source exclusion requires a reason')
        selected = {name for name in selected if not fnmatch.fnmatchcase(name, pattern)}
    missing = set(selection['required']) - selected
    if missing:
        raise ValueError('Required delivery inputs missing: ' + str(sorted(missing)))
    return selected


def export(root, output, selection_path=None):
    root, output = root.resolve(strict=True), output.resolve()
    if output.is_relative_to(root) or root.is_relative_to(output):
        raise ValueError("Export must be disjoint from the working repository")
    def git(*args):
        return subprocess.check_output(["git", "-C", str(root), *args])
    if git("status", "--porcelain", "--untracked-files=all").strip():
        raise ValueError("Commit the source before creating an export")
    origin = {name: git("rev-parse", ref).decode().strip() for name, ref in (
        ("commit", "HEAD"), ("tree", "HEAD^{tree}"))}
    selection = None
    if selection_path is not None:
        selection_path = selection_path.resolve(strict=True)
        if not selection_path.is_relative_to(root):
            raise ValueError('Source selection must be committed in the engineering repository')
        selection = json.loads(selection_path.read_text(encoding='utf-8'))
    selected = select_files(git('ls-files', '-z').decode().split('\0')[:-1], selection)
    output.mkdir(parents=True, exist_ok=False)
    files = {}
    with tarfile.open(fileobj=io.BytesIO(git('archive', '--format=tar', 'HEAD'))) as archive:
        for entry in archive:
            if entry.isdir():
                continue
            relative = entry.name
            if relative not in selected:
                continue
            path = PurePosixPath(relative)
            if not entry.isfile() or path.is_absolute() or '..' in path.parts or ':' in relative or '\\' in relative:
                raise ValueError('Unsupported source entry: ' + relative)
            if relative == MANIFEST:
                raise ValueError('Source repository must not contain its own export manifest')
            target = output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.extractfile(entry).read())
            if entry.mode & 0o111:
                target.chmod(0o755)
            files[relative] = identity(target)
    write_json(output / MANIFEST, {"schema": "csip-source-export-v1", "origin": origin,
        "selection": None if selection_path is None else {'path': selection_path.relative_to(root).as_posix(), 'identity': identity(selection_path)},
        "files": files, "policy": "Origin commit/tree are export provenance, not a local Git checkout. File SHA-256 is the executable source identity."})
    verify(output)
    return {"status": "PASS", "files": len(files), "manifest": identity(output / MANIFEST), "origin": origin}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--selection", type=Path)
    args = parser.parse_args()
    print(json.dumps(export(args.root, args.output, args.selection) if args.output else {
        "status": "PASS", "files": len(verify(args.root)["files"])}))


if __name__ == "__main__":
    main()
