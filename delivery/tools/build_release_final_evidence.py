#!/usr/bin/env python3
"""Build the final pre-seal evidence receipt from platform-owned records."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.release_acceptance import (FINAL_EXECUTION_ID, FINAL_SCHEMA, identity,
                                      load, validate_mac_payload, validate_online_ci,
                                      validate_platform)


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n',
                    encoding='utf-8', newline='\n')


def build(root):
    root = Path(root).resolve(strict=True)
    paths = {
        'online_ci': root / 'online_ci.json',
        'windows_final': root / 'windows_validation.json',
        'mac_payload': root / 'mac_validation.json',
    }
    if not all(path.is_file() for path in paths.values()):
        raise ValueError('Final evidence inputs are incomplete')
    online, windows, mac = (load(paths[name]) for name in ('online_ci', 'windows_final', 'mac_payload'))
    release_id = windows['release_id']
    source_origin = windows['source_origin']
    source_manifest = windows['source_manifest']
    publication_origin = windows['publication_origin']
    artifacts = windows['artifact_identities']
    payload_manifest = mac['payload_manifest']
    validate_online_ci(online, release_id, publication_origin)
    validate_platform(windows, 'WINDOWS', release_id, source_origin, source_manifest,
                      publication_origin, artifacts)
    validate_mac_payload(mac, release_id, source_origin, source_manifest,
                         publication_origin, artifacts, payload_manifest)
    return {
        'schema': FINAL_SCHEMA,
        'execution_id': FINAL_EXECUTION_ID,
        'status': 'PASS',
        'release_id': release_id,
        'source_origin': source_origin,
        'source_manifest': source_manifest,
        'publication_origin': publication_origin,
        'artifact_identities': artifacts,
        'payload_manifest': payload_manifest,
        'evidence': {name: identity(path) for name, path in paths.items()},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    output = args.root.resolve() / 'final_validation_receipt.json'
    if output.exists():
        raise ValueError('Final validation receipt already exists')
    value = build(args.root)
    write_json(output, value)
    print(json.dumps({'status': 'PASS', 'receipt': str(output), 'identity': identity(output)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('FINAL_EVIDENCE_BUILD=FAIL: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
