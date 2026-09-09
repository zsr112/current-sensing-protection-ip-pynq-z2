#!/usr/bin/env python3
"""Rebuild delivered source files in a fresh external execution directory."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_directory
from tools.source_export import identity, verify


def prepare(root, output):
    source = json.loads((root / 'SOURCE_MANIFEST.json').read_text())
    if source['schema'] != 'csip-source-export-v1':
        raise ValueError('Unsupported source manifest')
    if output.is_relative_to(root) or root.is_relative_to(output):
        raise ValueError('Rebuild workspace must be disjoint from the delivery')
    output.mkdir(parents=True, exist_ok=False)
    isolated = output / 'source'
    isolated.mkdir()
    for relative, expected in source['files'].items():
        name = PurePosixPath(relative)
        if name.is_absolute() or '..' in name.parts or ':' in relative or '\\' in relative:
            raise ValueError('Invalid source path')
        path = root / relative
        if any(p.is_symlink() or (hasattr(p, 'is_junction') and p.is_junction()) for p in (path, *path.parents)):
            raise ValueError('Source links are not permitted')
        if identity(path) != expected:
            raise ValueError('Delivered source changed: ' + relative)
        target = isolated / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    shutil.copyfile(root / 'SOURCE_MANIFEST.json', isolated / 'SOURCE_MANIFEST.json')
    verify(isolated)
    return isolated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('preflight', 'digital', 'vivado', 'all'))
    parser.add_argument('--build-root', type=Path)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--execution-id')
    args, extra = parser.parse_known_args()
    if args.config:
        os.environ['CSIP_CONFIG'] = str(args.config.resolve(strict=True))
    output = resolve_directory(ROOT, 'build_root', args.build_root)
    if output is None:
        raise ValueError('Supply --build-root, CSIP_BUILD_ROOT or build_root in configuration')
    isolated = prepare(ROOT, output)
    command = [sys.executable, '-B', str(isolated / 'tools/rebuild.py'), args.phase,
               '--build-root', str(output / 'run')]
    if args.config:
        command += ['--config', str(args.config.resolve())]
    if args.execution_id:
        command += ['--execution-id', args.execution_id]
    command += extra
    result = subprocess.run(command, cwd=isolated)
    verify(isolated)
    return result.returncode


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('DELIVERY_REBUILD_BLOCKED=' + str(error), file=sys.stderr)
        raise SystemExit(2)
