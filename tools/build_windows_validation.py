#!/usr/bin/env python3
"""Build the Windows pre-seal validation record from immutable evidence."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.release_acceptance import (FINAL_EXECUTION_ID, RELEASE_ID, identity,
                                      load, validate_online_ci, validate_platform)
from tools.source_export import verify as verify_source
from tools.verify_windows_board_release import verify_board


EXPECTED_CHECKS = {
    'full_digital_regression',
    'python_engineering_tests',
    'software_tests',
    'producer_tests',
    'board_plan_rtl',
    'stage1_board_ila_binding_fixture_tests',
    'stage1_board_ila_capture_configuration_fixture_tests',
    'stage1_board_ila_attempt03_ltx_binding_fixture_tests',
}


def git_identity():
    git = lambda ref: subprocess.check_output(
        ['git', '-C', str(ROOT), 'rev-parse', ref], text=True).strip()
    if subprocess.check_output(
            ['git', '-C', str(ROOT), 'status', '--porcelain', '--untracked-files=all']).strip():
        raise ValueError('Commit publication tooling before Windows validation')
    return {'commit': git('HEAD'), 'tree': git('HEAD^{tree}'), 'branch': 'release-preparation'}


def build(args):
    source_root = args.source.resolve(strict=True)
    execution_root = args.execution.resolve(strict=True)
    board_root = args.board.resolve(strict=True)
    online_path = args.online_ci.resolve(strict=True)
    source = verify_source(source_root)
    publication_origin = git_identity()
    online = load(online_path)
    validate_online_ci(online, RELEASE_ID, publication_origin)
    receipt_path = execution_root / 'verification_receipt.json'
    receipt = load(receipt_path)
    if receipt.get('schema') != 'windows-final-verification-v1':
        raise ValueError('Windows execution schema differs')
    if receipt.get('execution_id') != FINAL_EXECUTION_ID or receipt.get('status') != 'PASS':
        raise ValueError('Windows final execution did not pass')
    if receipt.get('source_commit') != source['origin']['commit'] or receipt.get('source_tree') != source['origin']['tree']:
        raise ValueError('Windows final execution source differs')
    if set(receipt.get('checks', {})) != EXPECTED_CHECKS or not all(
            row.get('exit_code') == 0 for row in receipt['checks'].values()):
        raise ValueError('Windows final execution checks differ')
    files = receipt.get('files')
    if not isinstance(files, dict) or not files:
        raise ValueError('Windows final execution file inventory is missing')
    for relative, expected in files.items():
        path = PurePosixPath(relative)
        if path.is_absolute() or '..' in path.parts or ':' in relative or '\\' in relative:
            raise ValueError('Invalid Windows final evidence path: ' + relative)
        if identity(execution_root / relative) != expected:
            raise ValueError('Windows final execution file changed: ' + relative)
    engineering_log = (execution_root / 'python_engineering_tests.log').read_text(
        encoding='utf-8', errors='replace')
    if 'test_windows_junction_to_outside_is_rejected' not in engineering_log or not any(
            'test_windows_junction_to_outside_is_rejected' in line and line.rstrip().endswith('ok')
            for line in engineering_log.splitlines()):
        raise ValueError('Windows junction rejection result is missing')
    board, loaded = verify_board(board_root)
    if receipt.get('board_execution_id') != board['execution_id']:
        raise ValueError('Windows final execution board identity differs')
    artifacts = {name: {'bytes': loaded['identity']['artifact_identities'][name]['bytes'],
                        'sha256': loaded['identity']['artifact_identities'][name]['sha256']}
                 for name in ('bit', 'hwh', 'ltx')}
    source_manifest = identity(source_root / 'SOURCE_MANIFEST.json')
    value = {
        'schema': 'csip-platform-final-validation-v1',
        'platform': 'WINDOWS',
        'status': 'PASS',
        'release_id': RELEASE_ID,
        'validation_id': args.validation_id,
        'source_origin': source['origin'],
        'source_manifest': source_manifest,
        'publication_origin': publication_origin,
        'artifact_identities': artifacts,
        'evidence': {
            'windows_final_execution': identity(receipt_path),
            'online_ci': identity(online_path),
            'board_receipt': identity(board_root / 'board_verification_receipt.json'),
        },
        'checks': {name: 'PASS' for name in sorted(EXPECTED_CHECKS)} | {
            'windows_junction_rejection': 'PASS',
            'source_manifest_exact': 'PASS',
            'board_artifact_identity': 'PASS',
            'online_ci_windows': online['platforms']['windows-latest']['status'],
        },
    }
    validate_platform(value, 'WINDOWS', RELEASE_ID, source['origin'], source_manifest,
                      publication_origin, artifacts)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--execution', type=Path, required=True)
    parser.add_argument('--board', type=Path, required=True)
    parser.add_argument('--online-ci', type=Path, required=True)
    parser.add_argument('--validation-id', default='CSIP-V2R3-WINDOWS-001')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or output.name != 'windows_validation.json':
        raise ValueError('Windows validation output must be a new windows_validation.json')
    value = build(args)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n',
                      encoding='utf-8', newline='\n')
    print(json.dumps({'status': 'PASS', 'output': str(output), 'identity': identity(output)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('WINDOWS_VALIDATION=FAIL: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
