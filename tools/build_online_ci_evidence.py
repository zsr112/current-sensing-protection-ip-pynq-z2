#!/usr/bin/env python3
"""Build online-CI evidence from downloaded GitHub Actions artifacts."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.release_acceptance import RELEASE_ID, identity, validate_online_ci
from tools.runtime_config import optional_git_identity


MEMBERS = ('ci_result.json', 'portable/portable_result.json', 'selected/SOURCE_MANIFEST.json')


def member_identity(data):
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def inspect(path, artifact_id, publication_origin):
    path = Path(path).resolve(strict=True)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('CI artifact ZIP integrity failed: ' + path.name)
        names = [info.filename for info in archive.infolist()]
        if len(names) != len(set(names)):
            raise ValueError('CI artifact contains duplicate members: ' + path.name)
        if not all(name in names for name in MEMBERS):
            raise ValueError('CI artifact evidence is incomplete: ' + path.name)
        values = {name: archive.read(name) for name in MEMBERS}
    ci = json.loads(values[MEMBERS[0]])
    portable = json.loads(values[MEMBERS[1]])
    selected = json.loads(values[MEMBERS[2]])
    if not ci or not all(row.get('exit_code') == 0 for row in ci.values()):
        raise ValueError('CI artifact contains a failed command: ' + path.name)
    if portable.get('status') != 'PASS' or not portable.get('checks') or not all(
            row.get('status') == 'PASS' and row.get('exit_code') == 0
            for row in portable['checks'].values()):
        raise ValueError('CI artifact portable regression failed: ' + path.name)
    expected_origin = {key: publication_origin[key] for key in ('commit', 'tree')}
    if selected.get('origin') != expected_origin:
        raise ValueError('CI artifact selected origin differs: ' + path.name)
    return {
        'status': 'PASS',
        'artifact_id': artifact_id,
        'artifact': identity(path),
        'selected_origin': selected['origin'],
        'selected_manifest': member_identity(values[MEMBERS[2]]),
        'ci_result': member_identity(values[MEMBERS[0]]),
        'portable_result': member_identity(values[MEMBERS[1]]),
    }


def build(args):
    publication_origin = optional_git_identity(ROOT)
    if publication_origin is None:
        raise ValueError('Online CI evidence requires a Git publication identity')
    publication_origin = {key: publication_origin[key] for key in ('commit', 'tree')}
    rows = {
        'ubuntu-latest': inspect(args.ubuntu_zip, args.ubuntu_artifact_id, publication_origin),
        'macos-latest': inspect(args.macos_zip, args.macos_artifact_id, publication_origin),
        'windows-latest': inspect(args.windows_zip, args.windows_artifact_id, publication_origin),
    }
    value = {
        'schema': 'csip-online-ci-v1',
        'status': 'PASS',
        'release_id': RELEASE_ID,
        'workflow': 'Portable source and delivery checks',
        'workflow_file': '.github/workflows/portable.yml',
        'run_url': args.run_url,
        'tested_commit': publication_origin['commit'],
        'workflow_commit': publication_origin['commit'],
        'platforms': rows,
    }
    validate_online_ci(value, RELEASE_ID, publication_origin)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-url', required=True)
    for name in ('ubuntu', 'macos', 'windows'):
        parser.add_argument('--' + name + '-zip', type=Path, required=True)
        parser.add_argument('--' + name + '-artifact-id', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise ValueError('Online CI evidence output already exists')
    value = build(args)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n',
                      encoding='utf-8', newline='\n')
    print(json.dumps({'status': 'PASS', 'output': str(output), 'identity': identity(output)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('ONLINE_CI_EVIDENCE=FAIL: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
