#!/usr/bin/env python3
"""Verify the packaged overlay, or explicitly load it with PWM disabled."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

sys.dont_write_bytecode = True


def identity(path):
    data = path.read_bytes()
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def verify(root):
    manifest = json.loads((root / 'DEPLOY_MANIFEST.json').read_text())
    if manifest['schema'] != 'csip-deployment-v2':
        raise ValueError('Unsupported deployment manifest')
    actual = set()
    for path in root.rglob('*'):
        if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
            raise ValueError('Deployment links are not allowed')
        if path.is_file() and path.name != 'DEPLOY_MANIFEST.json':
            actual.add(path.relative_to(root).as_posix())
    if actual != set(manifest['files']):
        raise ValueError('Deployment inventory differs')
    for relative, expected in manifest['files'].items():
        path = PurePosixPath(relative)
        if path.is_absolute() or '..' in path.parts or ':' in relative or '\\' in relative:
            raise ValueError('Invalid deployment path')
        if identity(root / relative) != expected:
            raise ValueError('Deployment file changed: ' + relative)
    sys.path.insert(0, str(root / 'runtime'))
    import stage2i_board_runtime as runtime
    runtime.validate_package(root, runtime.READY_AWARE)
    return manifest, runtime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package-root', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = args.package_root.resolve(strict=True)
    manifest, runtime = verify(root)
    if not args.execute:
        print(json.dumps({'verification': 'PASS', 'overlay_load': 'NOT_RUN',
                          'release_id': manifest['release_id']}))
        return 0
    if args.output is None or args.output.resolve().is_relative_to(root):
        raise ValueError('Supply a fresh external --output for the load receipt')
    args.output.mkdir(parents=True, exist_ok=False)
    record = {'release_id': manifest['release_id'], 'deployment_manifest': identity(root / 'DEPLOY_MANIFEST.json'),
              'python': platform.python_version(), 'hostname': platform.node(), 'kernel': platform.platform(),
              'board_time_utc': datetime.now(timezone.utc).isoformat(), 'board_time_trusted': False,
              'overlay_load': 'NOT_RUN', 'board_verification_this_execution': 'NOT_RUN',
              'formal_acceptance': 'NOT_FORMALLY_ACCEPTED'}
    if hasattr(platform, 'freedesktop_os_release'):
        record['image'] = platform.freedesktop_os_release()
    target = args.output / 'deployment_receipt.json'
    def save():
        target.write_text(json.dumps(record, sort_keys=True, indent=2) + '\n', encoding='utf-8')
    save()
    protection = None
    try:
        if hasattr(os, 'geteuid') and os.geteuid() != 0:
            raise ValueError('Overlay loading requires root in the PYNQ environment')
        profile = runtime.load_profile(root, runtime.READY_AWARE)
        record['artifacts'] = profile['artifacts']
        record['source_commit'] = profile['source_commit']
        save()
        overlay, protection, gpio, pynq_version = runtime.open_overlay_mmio(root, profile)
        from pynq import Clocks
        if not overlay.is_loaded():
            raise ValueError('Overlay did not report a loaded state')
        state = runtime.read_current_state(protection)
        clocks = {'fclk0': float(Clocks.fclk0_mhz), 'fclk1': float(Clocks.fclk1_mhz)}
        if state['status']['ctrl'] != 0 or abs(clocks['fclk0'] - 100) > .1 or abs(clocks['fclk1'] - 125) > .1:
            raise ValueError('Unexpected startup control or clock state')
        record.update(overlay_load='PASS', pwm_enabled=False, state=state, clocks_mhz=clocks,
                      pynq_version=pynq_version, overlay_loaded=bool(overlay.is_loaded()))
    except Exception as error:
        record.update(overlay_load='FAIL', error=str(error))
        if protection is not None:
            protection.write(int(runtime.RegisterOffset.CTRL), 0)
        raise
    finally:
        save()
    print(json.dumps({'overlay_load': 'PASS', 'pwm_enabled': False, 'receipt': str(target)}))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('DEPLOYMENT_FAILED=' + str(error), file=sys.stderr)
        raise SystemExit(1)
