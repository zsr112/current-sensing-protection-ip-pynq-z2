#!/usr/bin/env python3
"""Validate the frozen pre-seal payload and emit a Mac-owned record."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.release_acceptance import (MAC_PAYLOAD_SCHEMA, RELEASE_ID, identity,
                                      load, validate_payload_tree)
from tools.verify_post_seal_release import inspect_and_extract, write_json


def execute(name, command, cwd, log, checks):
    with log.open('xb') as stream:
        result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                check=False)
    if result.returncode:
        raise RuntimeError(name + ' failed; see ' + str(log))
    checks[name] = 'PASS'


def portable_validation_commands(work_root):
    return [
        ('portable_preflight',
         [sys.executable, '-B', 'tools/rebuild_delivery.py', 'preflight',
          '--build-root', str(work_root / 'source-preflight'), '--target', 'portable']),
        ('portable_regression',
         [sys.executable, '-B', 'tools/rebuild_delivery.py', 'portable',
          '--build-root', str(work_root / 'source-portable'),
          '--execution-id', 'CSIP-V2R3-MAC-PAYLOAD-PORTABLE-001']),
    ]


def validate(archive_path, work_root):
    archive_path = Path(archive_path).resolve(strict=True)
    if archive_path.name != RELEASE_ID + '-payload.zip':
        raise ValueError('Pre-seal ZIP name differs')
    extracted = work_root / 'extracted'
    extracted.mkdir()
    inspect_and_extract(archive_path, extracted)
    manifest_path = extracted / 'PAYLOAD_MANIFEST.json'
    payload = load(manifest_path)
    validate_payload_tree(
        payload, extracted, RELEASE_ID, payload['source_origin'], payload['source_manifest'],
        payload['publication_origin'], payload['artifact_identities'])
    checks = {'zip_integrity': 'PASS', 'safe_unique_members': 'PASS',
              'payload_manifest_exact': 'PASS'}
    execute('publication_tests',
            [sys.executable, '-B', '-m', 'unittest', 'discover', '-s',
             'publication/tests', '-v'],
            extracted, work_root / 'publication_tests.log', checks)
    for name, command in portable_validation_commands(work_root):
        execute(name, command, extracted, work_root / (name + '.log'), checks)
    return payload, identity(manifest_path), checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--validation-id', default='CSIP-V2R3-MAC-PAYLOAD-001')
    parser.add_argument('--validated-at', help='ISO-8601 UTC time; defaults to current UTC')
    parser.add_argument('--work-root', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or output.name != 'mac_validation.json':
        raise ValueError('Mac payload validation output must be a new mac_validation.json')
    if args.work_root:
        work_root = args.work_root.resolve()
        work_root.mkdir(parents=True, exist_ok=False)
        cleanup = None
    else:
        cleanup = tempfile.TemporaryDirectory(prefix='csip mac payload ')
        work_root = Path(cleanup.name)
    try:
        payload, payload_manifest, checks = validate(args.archive, work_root)
        record = {
            'schema': MAC_PAYLOAD_SCHEMA,
            'platform': 'MACOS',
            'status': 'PASS',
            'release_id': RELEASE_ID,
            'validation_id': args.validation_id,
            'validated_at_utc': args.validated_at or datetime.now(timezone.utc).isoformat(),
            'source_origin': payload['source_origin'],
            'source_manifest': payload['source_manifest'],
            'publication_origin': payload['publication_origin'],
            'artifact_identities': payload['artifact_identities'],
            'payload_manifest': payload_manifest,
            'preseal_archive': identity(args.archive.resolve(strict=True)),
            'checks': checks,
        }
        write_json(output, record)
        print(json.dumps({'status': 'PASS', 'record': str(output),
                          'preseal_archive': record['preseal_archive'],
                          'payload_manifest': payload_manifest}))
    finally:
        if cleanup is not None:
            cleanup.cleanup()


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('PAYLOAD_VALIDATION=FAIL: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
