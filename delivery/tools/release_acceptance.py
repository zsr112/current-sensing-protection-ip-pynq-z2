#!/usr/bin/env python3
"""Validate the bounded project-owner decision for a v2r3 digital release."""
from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath


SCHEMA = 'csip-release-acceptance-v1'
PAYLOAD_SCHEMA = 'csip-release-payload-v1'
MAC_PAYLOAD_SCHEMA = 'csip-mac-payload-validation-v1'
FINAL_SCHEMA = 'csip-final-validation-v2'
POST_SEAL_SCHEMA = 'csip-post-seal-archive-validation-v1'
POST_SEAL_STATUS = 'EXTERNAL_PASS_REQUIRED_BEFORE_PUBLICATION'
POST_SEAL_PLATFORMS = {'MACOS', 'WINDOWS'}
STATUS = 'PROJECT_OWNER_ACCEPTED'
AUTHORITY = 'PROJECT_OWNER_INTERNAL_REVIEW'
SCOPE = 'V2R3_DIGITAL_RELEASE'
DECISION_ID = 'CSIP-V2R3-ACCEPT-001'
BUILD_EXECUTION_ID = 'CSIP-V2R3-BUILD-001'
BOARD_EXECUTION_ID = 'CSIP-V2R3-BOARD-001'
FINAL_EXECUTION_ID = 'CSIP-V2R3-FINAL-001'
RELEASE_ID = 'stage2-self-contained-v2r3'
CAPABILITIES = [
    'DIGITAL_PROTECTION_SOURCE',
    'PORTABLE_REGRESSION',
    'VIVADO_2024_1_ROUTED_BUILD',
    'SYNTHETIC_DIGITAL_PYNQ_Z2_BOARD_SCENARIOS',
    'OFFLINE_VERIFIABLE_DELIVERY',
]
LIMITATIONS = [
    'REAL_ADC_INPUT_CHAIN',
    'ACTUAL_CALIBRATION',
    'EXTERNAL_PIN_PWM',
    'EXTERNAL_POWER_STAGE',
    'PERSISTENT_BOOT',
    'LONG_DURATION_SOAK',
    'ANALOG_SYSTEM_VALIDATION',
]
PLATFORMS = {'ubuntu-latest', 'macos-latest', 'windows-latest'}
SHA256 = re.compile(r'^[0-9a-f]{64}$')
GIT_ID = re.compile(r'^[0-9a-f]{40}$')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def identity(path):
    data = Path(path).read_bytes()
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def validate_identity(value, label):
    require(isinstance(value, dict) and set(value) == {'bytes', 'sha256'}, label + ' identity shape differs')
    require(isinstance(value['bytes'], int) and value['bytes'] >= 0, label + ' byte count differs')
    require(isinstance(value['sha256'], str) and SHA256.fullmatch(value['sha256']), label + ' SHA256 differs')


def validate_origin(value, label):
    require(isinstance(value, dict), label + ' origin is missing')
    require(set(value) >= {'commit', 'tree'}, label + ' origin shape differs')
    require(GIT_ID.fullmatch(str(value['commit'])) is not None, label + ' commit differs')
    require(GIT_ID.fullmatch(str(value['tree'])) is not None, label + ' tree differs')


def validate_timestamp(value):
    require(isinstance(value, str) and value, 'Decision timestamp is missing')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None and parsed.utcoffset() == timezone.utc.utcoffset(parsed),
            'Decision timestamp must be UTC')


def build_payload_manifest(root, release_id, source_origin, source_manifest,
                           publication_origin, artifacts):
    root = Path(root).resolve(strict=True)
    files = {}
    for path in sorted(root.rglob('*')):
        require(not path.is_symlink() and not (hasattr(path, 'is_junction') and path.is_junction()),
                'Payload links are forbidden')
        if path.is_file() and path.name != 'PAYLOAD_MANIFEST.json':
            files[path.relative_to(root).as_posix()] = identity(path)
    require(files, 'Release payload is empty')
    return {
        'schema': PAYLOAD_SCHEMA,
        'release_id': release_id,
        'source_origin': source_origin,
        'source_manifest': source_manifest,
        'publication_origin': publication_origin,
        'artifact_identities': artifacts,
        'files': files,
    }


def validate_payload_manifest(value, root, release_id, source_origin, source_manifest,
                              publication_origin, artifacts):
    require(isinstance(value, dict), 'Payload manifest is missing')
    require(set(value) == {'schema', 'release_id', 'source_origin', 'source_manifest',
                           'publication_origin', 'artifact_identities', 'files'},
            'Payload manifest shape differs')
    require(value.get('schema') == PAYLOAD_SCHEMA, 'Payload manifest schema differs')
    require(value.get('release_id') == release_id, 'Payload release differs')
    require(value.get('source_origin') == source_origin, 'Payload source origin differs')
    require(value.get('source_manifest') == source_manifest, 'Payload source manifest differs')
    require(value.get('publication_origin') == publication_origin, 'Payload publication origin differs')
    require(value.get('artifact_identities') == artifacts, 'Payload artifact identities differ')
    files = value.get('files')
    require(isinstance(files, dict) and files, 'Payload file inventory is missing')
    root = Path(root).resolve(strict=True)
    for relative, expected in files.items():
        path = PurePosixPath(relative)
        require(relative == path.as_posix() and not path.is_absolute() and '..' not in path.parts and
                ':' not in relative and '\\' not in relative, 'Invalid payload path')
        validate_identity(expected, 'Payload file ' + relative)
        target = root / relative
        require(target.is_file() and identity(target) == expected, 'Payload file changed: ' + relative)
    return value


def validate_payload_tree(value, root, release_id, source_origin, source_manifest,
                          publication_origin, artifacts):
    root = Path(root).resolve(strict=True)
    validate_payload_manifest(value, root, release_id, source_origin, source_manifest,
                              publication_origin, artifacts)
    actual = {path.relative_to(root).as_posix() for path in root.rglob('*') if path.is_file()}
    expected = set(value['files']) | {'PAYLOAD_MANIFEST.json'}
    require(actual == expected, 'Pre-seal payload inventory differs')
    return value


def validate_online_ci(value, release_id, publication_origin):
    require(value.get('schema') == 'csip-online-ci-v1', 'Online CI schema differs')
    require(value.get('status') == 'PASS', 'Online CI did not pass')
    require(value.get('release_id') == release_id, 'Online CI release differs')
    require(value.get('workflow') == 'Portable source and delivery checks', 'Online CI workflow differs')
    require(value.get('workflow_file') == '.github/workflows/portable.yml', 'Online CI workflow file differs')
    require(value.get('tested_commit') == publication_origin['commit'], 'Online CI tested commit differs')
    require(value.get('workflow_commit') == publication_origin['commit'], 'Online CI workflow commit differs')
    require(isinstance(value.get('run_url'), str) and
            value['run_url'].startswith('https://github.com/') and '/actions/runs/' in value['run_url'],
            'Online CI run URL differs')
    platforms = value.get('platforms')
    require(isinstance(platforms, dict) and set(platforms) == PLATFORMS, 'Online CI platform set differs')
    require(all(row.get('status') == 'PASS' for row in platforms.values()), 'Online CI platform failed')
    for name, row in platforms.items():
        require(set(row) == {'status', 'artifact_id', 'artifact', 'selected_origin',
                             'selected_manifest', 'ci_result', 'portable_result'},
                'Online CI platform evidence shape differs: ' + name)
        require(isinstance(row.get('artifact_id'), int) and row['artifact_id'] > 0,
                'Online CI artifact ID is missing: ' + name)
        artifact = row.get('artifact')
        require(isinstance(artifact, dict), 'Online CI artifact is missing: ' + name)
        validate_identity(artifact, 'Online CI artifact ' + name)
        require(row.get('selected_origin') == {key: publication_origin[key] for key in ('commit', 'tree')},
                'Online CI selected origin differs: ' + name)
        for key in ('selected_manifest', 'ci_result', 'portable_result'):
            validate_identity(row.get(key), 'Online CI ' + key + ' ' + name)


def validate_platform(value, platform_name, release_id, source_origin, source_manifest,
                      publication_origin, artifacts):
    require(value.get('schema') == 'csip-platform-final-validation-v1', platform_name + ' validation schema differs')
    require(value.get('platform') == platform_name, platform_name + ' validation platform differs')
    require(value.get('status') == 'PASS', platform_name + ' validation did not pass')
    require(value.get('release_id') == release_id, platform_name + ' validation release differs')
    require(isinstance(value.get('validation_id'), str) and value['validation_id'], platform_name + ' validation ID is missing')
    require(value.get('source_origin') == source_origin, platform_name + ' source origin differs')
    require(value.get('source_manifest') == source_manifest, platform_name + ' source manifest differs')
    require(value.get('publication_origin') == publication_origin, platform_name + ' publication origin differs')
    require(value.get('artifact_identities') == artifacts, platform_name + ' artifact identity differs')
    evidence = value.get('evidence')
    require(isinstance(evidence, dict) and evidence, platform_name + ' validation evidence is missing')
    for name, row in evidence.items():
        require(isinstance(name, str) and name, platform_name + ' validation evidence name differs')
        validate_identity(row, platform_name + ' validation evidence ' + name)
    checks = value.get('checks')
    require(isinstance(checks, dict) and checks and all(status == 'PASS' for status in checks.values()),
            platform_name + ' final checks did not all pass')


def validate_mac_payload(value, release_id, source_origin, source_manifest,
                         publication_origin, artifacts, payload_manifest):
    require(value.get('schema') == MAC_PAYLOAD_SCHEMA, 'Mac payload validation schema differs')
    require(value.get('platform') == 'MACOS', 'Mac payload validation platform differs')
    require(value.get('status') == 'PASS', 'Mac payload validation did not pass')
    require(value.get('release_id') == release_id, 'Mac payload validation release differs')
    require(isinstance(value.get('validation_id'), str) and value['validation_id'],
            'Mac payload validation ID is missing')
    validate_timestamp(value.get('validated_at_utc'))
    require(value.get('source_origin') == source_origin, 'Mac payload source origin differs')
    require(value.get('source_manifest') == source_manifest, 'Mac payload source manifest differs')
    require(value.get('publication_origin') == publication_origin, 'Mac payload publication origin differs')
    require(value.get('artifact_identities') == artifacts, 'Mac payload artifact identity differs')
    require(value.get('payload_manifest') == payload_manifest, 'Mac validated payload manifest differs')
    validate_identity(value.get('preseal_archive'), 'Mac pre-seal archive')
    checks = value.get('checks')
    require(isinstance(checks, dict) and checks and all(status == 'PASS' for status in checks.values()),
            'Mac payload checks did not all pass')


def validate_preseal_evidence(root, release_id, source_origin, source_manifest,
                              publication_origin, artifacts):
    root = Path(root).resolve(strict=True)
    paths = {
        'online_ci': root / 'online_ci.json',
        'windows_final': root / 'windows_validation.json',
    }
    require(all(path.is_file() for path in paths.values()), 'Pre-seal evidence files are incomplete')
    online = load(paths['online_ci'])
    windows = load(paths['windows_final'])
    validate_online_ci(online, release_id, publication_origin)
    validate_platform(windows, 'WINDOWS', release_id, source_origin, source_manifest,
                      publication_origin, artifacts)
    return online, windows, paths


def validate_final_evidence(root, release_id, source_origin, source_manifest,
                            publication_origin, artifacts, payload_manifest):
    root = Path(root).resolve(strict=True)
    online, windows, preseal_paths = validate_preseal_evidence(
        root, release_id, source_origin, source_manifest, publication_origin, artifacts)
    paths = {
        **preseal_paths,
        'mac_payload': root / 'mac_validation.json',
        'final': root / 'final_validation_receipt.json',
    }
    require(all(path.is_file() for path in paths.values()), 'Final evidence files are incomplete')
    mac = load(paths['mac_payload'])
    final = load(paths['final'])
    validate_mac_payload(mac, release_id, source_origin, source_manifest,
                         publication_origin, artifacts, payload_manifest)
    require(final.get('schema') == FINAL_SCHEMA, 'Final validation schema differs')
    require(final.get('execution_id') == FINAL_EXECUTION_ID, 'Final validation execution differs')
    require(final.get('status') == 'PASS', 'Final validation did not pass')
    require(final.get('release_id') == release_id, 'Final validation release differs')
    require(final.get('source_origin') == source_origin, 'Final validation source differs')
    require(final.get('source_manifest') == source_manifest, 'Final validation manifest differs')
    require(final.get('publication_origin') == publication_origin, 'Final validation publication origin differs')
    require(final.get('artifact_identities') == artifacts, 'Final validation artifacts differ')
    require(final.get('payload_manifest') == payload_manifest, 'Final validation payload manifest differs')
    expected = {name: identity(path) for name, path in paths.items() if name != 'final'}
    require(final.get('evidence') == expected, 'Final validation evidence identities differ')
    return final, online, windows, mac, paths


def build_acceptance(*, release_id, accepted_at, build_execution_id, board_execution_id,
                     source_origin, source_manifest, publication_origin, publication_tools,
                     artifact_identities, manifest_identities, final_records,
                     build_evidence_path, board_evidence_path):
    validate_timestamp(accepted_at)
    final, online, windows, mac, paths = final_records
    value = {
        'schema': SCHEMA,
        'decision_id': DECISION_ID,
        'status': STATUS,
        'authority': AUTHORITY,
        'scope': SCOPE,
        'release_id': release_id,
        'decision_timestamp_utc': accepted_at,
        'accepted_capabilities': CAPABILITIES,
        'accepted_limitations': LIMITATIONS,
        'acceptance_basis': {
            'build': {'execution_id': build_execution_id, 'status': 'PASS',
                      'evidence_path': 'evidence/build/rebuild_receipt.json'},
            'board': {'execution_id': board_execution_id, 'status': 'PASS',
                      'evidence_path': 'evidence/board/board_verification_receipt.json'},
            'final': {'execution_id': final['execution_id'], 'status': final['status'],
                      'evidence_path': 'evidence/final/final_validation_receipt.json'},
            'online_ci': {'status': online['status'], 'tested_commit': online['tested_commit'],
                          'platforms': {name: row['status'] for name, row in online['platforms'].items()},
                          'evidence_path': 'evidence/final/online_ci.json'},
            'windows_final': {'status': windows['status'], 'validation_id': windows['validation_id'],
                              'evidence_path': 'evidence/final/windows_validation.json'},
            'mac_payload': {'status': mac['status'], 'validation_id': mac['validation_id'],
                          'payload_manifest': mac['payload_manifest'],
                          'evidence_path': 'evidence/final/mac_validation.json'},
            'post_seal_gate': {'status': POST_SEAL_STATUS, 'record_schema': POST_SEAL_SCHEMA,
                               'archive_name': RELEASE_ID + '.zip',
                               'record_location': 'OUTSIDE_ARCHIVE',
                               'required_platforms': sorted(POST_SEAL_PLATFORMS),
                               'required_records': {
                                   'MACOS': RELEASE_ID + '.macos-post-seal.json',
                                   'WINDOWS': RELEASE_ID + '.windows-post-seal.json',
                               }},
            'source': {'origin': source_origin, 'manifest': source_manifest},
            'publication': {'origin': publication_origin, 'tools': publication_tools},
            'artifacts': artifact_identities,
            'manifests': manifest_identities,
        },
    }
    evidence_paths = {
        **paths,
        'build': Path(build_evidence_path),
        'board': Path(board_evidence_path),
    }
    require(set(evidence_paths) == {
        'build', 'board', 'final', 'online_ci', 'windows_final', 'mac_payload',
    }, 'Acceptance evidence path set differs')
    for key, path in evidence_paths.items():
        value['acceptance_basis'][key]['identity'] = identity(path)
    validate_acceptance(value, release_id)
    return value


def validate_acceptance(value, expected_release_id=RELEASE_ID):
    require(isinstance(value, dict), 'ACCEPTANCE.json is missing')
    require(value.get('schema') == SCHEMA, 'Acceptance schema differs')
    require(value.get('decision_id') == DECISION_ID, 'Acceptance decision differs')
    require(value.get('status') == STATUS, 'Acceptance status differs')
    require(value.get('authority') == AUTHORITY, 'Acceptance authority differs')
    require(value.get('scope') == SCOPE, 'Acceptance scope includes an unverified capability')
    require(value.get('release_id') == expected_release_id, 'Acceptance release differs')
    validate_timestamp(value.get('decision_timestamp_utc'))
    require(value.get('accepted_capabilities') == CAPABILITIES, 'Accepted capability set differs')
    require(value.get('accepted_limitations') == LIMITATIONS, 'Accepted limitations differ')
    basis = value.get('acceptance_basis')
    expected_keys = {'build', 'board', 'final', 'online_ci', 'windows_final', 'mac_payload',
                     'post_seal_gate', 'source', 'publication', 'artifacts', 'manifests'}
    require(isinstance(basis, dict) and set(basis) == expected_keys, 'Acceptance basis is incomplete')
    require(basis['build'].get('status') == 'PASS', 'Build acceptance basis failed')
    require(basis['board'].get('status') == 'PASS', 'Board acceptance basis failed')
    require(basis['final'].get('status') == 'PASS', 'Final acceptance basis failed')
    require(basis['build'].get('execution_id') == BUILD_EXECUTION_ID, 'Build acceptance execution differs')
    require(basis['board'].get('execution_id') == BOARD_EXECUTION_ID, 'Board acceptance execution differs')
    require(basis['final'].get('execution_id') == FINAL_EXECUTION_ID, 'Final acceptance execution differs')
    require(basis['online_ci'].get('status') == 'PASS', 'Online CI acceptance basis failed')
    require(set(basis['online_ci'].get('platforms', {})) == PLATFORMS and
            all(status == 'PASS' for status in basis['online_ci']['platforms'].values()),
            'Online CI acceptance platforms failed')
    require(basis['windows_final'].get('status') == 'PASS', 'Windows acceptance basis failed')
    require(basis['mac_payload'].get('status') == 'PASS', 'Mac payload acceptance basis failed')
    validate_identity(basis['mac_payload'].get('payload_manifest'), 'Mac accepted payload manifest')
    require(basis['post_seal_gate'] == {
        'status': POST_SEAL_STATUS,
        'record_schema': POST_SEAL_SCHEMA,
        'archive_name': RELEASE_ID + '.zip',
        'record_location': 'OUTSIDE_ARCHIVE',
        'required_platforms': sorted(POST_SEAL_PLATFORMS),
        'required_records': {
            'MACOS': RELEASE_ID + '.macos-post-seal.json',
            'WINDOWS': RELEASE_ID + '.windows-post-seal.json',
        },
    }, 'Post-seal publication gate differs')
    evidence_paths = {
        'build': 'evidence/build/rebuild_receipt.json',
        'board': 'evidence/board/board_verification_receipt.json',
        'final': 'evidence/final/final_validation_receipt.json',
        'online_ci': 'evidence/final/online_ci.json',
        'windows_final': 'evidence/final/windows_validation.json',
        'mac_payload': 'evidence/final/mac_validation.json',
    }
    for key, expected_path in evidence_paths.items():
        require(basis[key].get('evidence_path') == expected_path, key + ' evidence path differs')
        validate_identity(basis[key].get('identity'), key)
    validate_origin(basis['source'].get('origin'), 'Source')
    validate_identity(basis['source'].get('manifest'), 'Source manifest')
    validate_origin(basis['publication'].get('origin'), 'Publication')
    require(isinstance(basis['publication'].get('tools'), dict) and basis['publication']['tools'],
            'Publication tool identities are missing')
    for name, row in basis['publication']['tools'].items():
        require(isinstance(name, str) and name, 'Publication tool path differs')
        validate_identity(row.get('identity'), 'Publication tool ' + name)
    require(set(basis['artifacts']) == {'bit', 'hwh', 'ltx'}, 'Accepted artifact set differs')
    for name, row in basis['artifacts'].items():
        validate_identity(row, 'Artifact ' + name)
    require(set(basis['manifests']) == {'source', 'board_session', 'artifact', 'release_payload'},
            'Accepted manifest set differs')
    for name, row in basis['manifests'].items():
        validate_identity(row, 'Manifest ' + name)
    return value
