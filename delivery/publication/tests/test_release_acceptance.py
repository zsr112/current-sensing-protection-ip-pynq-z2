import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


test_root = Path(__file__).resolve().parents[1]
if test_root.name == 'publication':
    spec = importlib.util.spec_from_file_location('publication_acceptance', test_root.parent / 'tools/release_acceptance.py')
    acceptance = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(acceptance)
else:
    from tools import release_acceptance as acceptance


def ident(character='a'):
    return {'bytes': 1, 'sha256': character * 64}


def valid_acceptance():
    source_origin = {'commit': '1' * 40, 'tree': '2' * 40}
    publication_origin = {'commit': '3' * 40, 'tree': '4' * 40, 'branch': 'release-preparation'}
    evidence = lambda path: {'status': 'PASS', 'evidence_path': path, 'identity': ident()}
    basis = {
        'build': dict(evidence('evidence/build/rebuild_receipt.json'), execution_id='CSIP-V2R3-BUILD-001'),
        'board': dict(evidence('evidence/board/board_verification_receipt.json'), execution_id='CSIP-V2R3-BOARD-001'),
        'final': dict(evidence('evidence/final/final_validation_receipt.json'), execution_id=acceptance.FINAL_EXECUTION_ID),
        'online_ci': dict(evidence('evidence/final/online_ci.json'), tested_commit=publication_origin['commit'],
                          platforms={name: 'PASS' for name in acceptance.PLATFORMS}),
        'windows_final': dict(evidence('evidence/final/windows_validation.json'), validation_id='CSIP-V2R3-WINDOWS-001'),
        'mac_payload': dict(evidence('evidence/final/mac_validation.json'),
                            validation_id='CSIP-V2R3-MAC-PAYLOAD-001', payload_manifest=ident('9')),
        'post_seal_gate': {
            'status': acceptance.POST_SEAL_STATUS,
            'record_schema': acceptance.POST_SEAL_SCHEMA,
            'archive_name': acceptance.RELEASE_ID + '.zip',
            'record_location': 'OUTSIDE_ARCHIVE',
            'required_platforms': sorted(acceptance.POST_SEAL_PLATFORMS),
            'required_records': {
                'MACOS': acceptance.RELEASE_ID + '.macos-post-seal.json',
                'WINDOWS': acceptance.RELEASE_ID + '.windows-post-seal.json',
            },
        },
        'source': {'origin': source_origin, 'manifest': ident('b')},
        'publication': {'origin': publication_origin,
                        'tools': {'publication/tools/tool.py': {'identity': ident('c')}}},
        'artifacts': {name: ident(character) for name, character in zip(('bit', 'hwh', 'ltx'), 'def')},
        'manifests': {name: ident(character) for name, character in
                      zip(('source', 'board_session', 'artifact', 'release_payload'), 'abc9')},
    }
    return {
        'schema': acceptance.SCHEMA,
        'decision_id': acceptance.DECISION_ID,
        'status': acceptance.STATUS,
        'authority': acceptance.AUTHORITY,
        'scope': acceptance.SCOPE,
        'release_id': acceptance.RELEASE_ID,
        'decision_timestamp_utc': '2026-09-10T12:00:00+00:00',
        'accepted_capabilities': acceptance.CAPABILITIES,
        'accepted_limitations': acceptance.LIMITATIONS,
        'acceptance_basis': basis,
    }


class ReleaseAcceptanceTests(unittest.TestCase):
    def test_complete_bounded_acceptance_passes(self):
        value = valid_acceptance()
        self.assertIs(value, acceptance.validate_acceptance(value))

    def test_missing_acceptance_fails(self):
        with self.assertRaisesRegex(ValueError, 'missing'):
            acceptance.validate_acceptance(None)

    def test_acceptance_status_mismatch_fails(self):
        value = valid_acceptance()
        value['status'] = 'NOT_FORMALLY_ACCEPTED'
        with self.assertRaisesRegex(ValueError, 'status'):
            acceptance.validate_acceptance(value)

    def test_release_id_mismatch_fails(self):
        value = valid_acceptance()
        value['release_id'] = 'stage2-self-contained-v2r2'
        with self.assertRaisesRegex(ValueError, 'release'):
            acceptance.validate_acceptance(value)

    def test_missing_evidence_basis_fails(self):
        value = valid_acceptance()
        del value['acceptance_basis']['mac_payload']
        with self.assertRaisesRegex(ValueError, 'basis'):
            acceptance.validate_acceptance(value)

    def test_failed_evidence_basis_fails(self):
        value = valid_acceptance()
        value['acceptance_basis']['board']['status'] = 'FAIL'
        with self.assertRaisesRegex(ValueError, 'Board'):
            acceptance.validate_acceptance(value)

    def test_evidence_path_escape_fails(self):
        value = valid_acceptance()
        value['acceptance_basis']['mac_payload']['evidence_path'] = '../../mac_validation.json'
        with self.assertRaisesRegex(ValueError, 'path'):
            acceptance.validate_acceptance(value)

    def test_unverified_capability_in_scope_fails(self):
        value = valid_acceptance()
        value['scope'] = 'V2R3_DIGITAL_RELEASE_AND_REAL_ADC'
        with self.assertRaisesRegex(ValueError, 'unverified capability'):
            acceptance.validate_acceptance(value)

    def test_added_or_removed_capability_fails(self):
        value = valid_acceptance()
        value['accepted_capabilities'] = value['accepted_capabilities'] + ['REAL_ADC_INPUT_CHAIN']
        with self.assertRaisesRegex(ValueError, 'capability'):
            acceptance.validate_acceptance(value)

    def test_limitations_cannot_be_omitted(self):
        value = valid_acceptance()
        value['accepted_limitations'] = value['accepted_limitations'][:-1]
        with self.assertRaisesRegex(ValueError, 'limitations'):
            acceptance.validate_acceptance(value)

    def test_online_ci_platform_failure_fails(self):
        value = valid_acceptance()
        value['acceptance_basis']['online_ci']['platforms']['windows-latest'] = 'FAIL'
        with self.assertRaisesRegex(ValueError, 'platforms'):
            acceptance.validate_acceptance(value)

    def test_acceptance_copy_is_independent_of_historical_evidence(self):
        value = valid_acceptance()
        original = copy.deepcopy(value)
        acceptance.validate_acceptance(value)
        self.assertEqual(original, value)

    def test_final_evidence_binds_ci_windows_and_mac_records(self):
        source_origin = {'commit': '1' * 40, 'tree': '2' * 40}
        publication_origin = {'commit': '3' * 40, 'tree': '4' * 40, 'branch': 'release-preparation'}
        source_manifest = ident('a')
        artifacts = {name: ident(character) for name, character in zip(('bit', 'hwh', 'ltx'), 'bcd')}
        payload_manifest = ident('9')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            online = {
                'schema': 'csip-online-ci-v1', 'status': 'PASS', 'release_id': acceptance.RELEASE_ID,
                'workflow': 'Portable source and delivery checks',
                'workflow_file': '.github/workflows/portable.yml',
                'run_url': 'https://github.com/example/project/actions/runs/1',
                'tested_commit': publication_origin['commit'], 'workflow_commit': publication_origin['commit'],
                'platforms': {name: {'status': 'PASS', 'artifact_id': index,
                                    'artifact': ident(character),
                                    'selected_origin': {key: publication_origin[key] for key in ('commit', 'tree')},
                                    'selected_manifest': ident('a'), 'ci_result': ident('b'),
                                    'portable_result': ident('c')} for index, (name, character) in
                              enumerate(zip(sorted(acceptance.PLATFORMS), 'def'), 1)},
            }
            def platform(name):
                return {
                    'schema': 'csip-platform-final-validation-v1', 'platform': name, 'status': 'PASS',
                    'release_id': acceptance.RELEASE_ID, 'validation_id': 'CSIP-V2R3-' + name + '-001',
                    'source_origin': source_origin, 'source_manifest': source_manifest,
                    'publication_origin': publication_origin, 'artifact_identities': artifacts,
                    'evidence': {'execution': ident('e')},
                    'checks': {'full_regression': 'PASS', 'exact_identity': 'PASS'},
                }
            mac = {
                'schema': acceptance.MAC_PAYLOAD_SCHEMA, 'platform': 'MACOS', 'status': 'PASS',
                'release_id': acceptance.RELEASE_ID, 'validation_id': 'CSIP-V2R3-MAC-PAYLOAD-001',
                'validated_at_utc': '2026-09-10T12:00:00+00:00',
                'source_origin': source_origin, 'source_manifest': source_manifest,
                'publication_origin': publication_origin, 'artifact_identities': artifacts,
                'payload_manifest': payload_manifest, 'preseal_archive': ident('8'),
                'checks': {'payload_manifest': 'PASS', 'portable_regression': 'PASS'},
            }
            documents = {'online_ci.json': online, 'windows_validation.json': platform('WINDOWS'),
                         'mac_validation.json': mac}
            for name, value in documents.items():
                (root / name).write_text(json.dumps(value) + '\n', encoding='utf-8')
            final = {
                'schema': acceptance.FINAL_SCHEMA, 'execution_id': acceptance.FINAL_EXECUTION_ID,
                'status': 'PASS', 'release_id': acceptance.RELEASE_ID, 'source_origin': source_origin,
                'source_manifest': source_manifest, 'publication_origin': publication_origin,
                'artifact_identities': artifacts, 'payload_manifest': payload_manifest,
                'evidence': {
                    'online_ci': acceptance.identity(root / 'online_ci.json'),
                    'windows_final': acceptance.identity(root / 'windows_validation.json'),
                    'mac_payload': acceptance.identity(root / 'mac_validation.json'),
                },
            }
            (root / 'final_validation_receipt.json').write_text(json.dumps(final) + '\n', encoding='utf-8')
            records = acceptance.validate_final_evidence(root, acceptance.RELEASE_ID, source_origin,
                                                          source_manifest, publication_origin, artifacts,
                                                          payload_manifest)
            self.assertEqual(acceptance.FINAL_EXECUTION_ID, records[0]['execution_id'])
            build_evidence = root / 'rebuild_receipt.json'
            board_evidence = root / 'board_verification_receipt.json'
            build_evidence.write_text('build evidence\n', encoding='utf-8')
            board_evidence.write_text('board evidence\n', encoding='utf-8')
            value = acceptance.build_acceptance(
                release_id=acceptance.RELEASE_ID,
                accepted_at='2026-09-10T12:00:00+00:00',
                build_execution_id=acceptance.BUILD_EXECUTION_ID,
                board_execution_id=acceptance.BOARD_EXECUTION_ID,
                source_origin=source_origin,
                source_manifest=source_manifest,
                publication_origin=publication_origin,
                publication_tools={'publication/tools/tool.py': {'identity': ident('c')}},
                artifact_identities=artifacts,
                manifest_identities={name: ident(character) for name, character in
                                     zip(('source', 'board_session', 'artifact', 'release_payload'),
                                         'abc9')},
                final_records=records,
                build_evidence_path=build_evidence,
                board_evidence_path=board_evidence,
            )
            self.assertEqual(acceptance.identity(build_evidence),
                             value['acceptance_basis']['build']['identity'])
            self.assertEqual(acceptance.identity(board_evidence),
                             value['acceptance_basis']['board']['identity'])

    def test_failed_mac_final_record_is_rejected(self):
        value = valid_acceptance()
        value['acceptance_basis']['mac_payload']['status'] = 'FAIL'
        with self.assertRaisesRegex(ValueError, 'Mac payload'):
            acceptance.validate_acceptance(value)

    def test_embedded_post_seal_claim_is_rejected(self):
        value = valid_acceptance()
        value['acceptance_basis']['post_seal_gate']['status'] = 'PASS'
        with self.assertRaisesRegex(ValueError, 'Post-seal'):
            acceptance.validate_acceptance(value)

    def test_payload_manifest_detects_changed_file(self):
        source_origin = {'commit': '1' * 40, 'tree': '2' * 40}
        publication_origin = {'commit': '3' * 40, 'tree': '4' * 40}
        artifacts = {name: ident(character) for name, character in zip(('bit', 'hwh', 'ltx'), 'bcd')}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'payload.txt').write_text('original', encoding='utf-8')
            value = acceptance.build_payload_manifest(
                root, acceptance.RELEASE_ID, source_origin, ident('a'), publication_origin, artifacts)
            (root / 'PAYLOAD_MANIFEST.json').write_text(json.dumps(value), encoding='utf-8')
            acceptance.validate_payload_tree(
                value, root, acceptance.RELEASE_ID, source_origin, ident('a'), publication_origin, artifacts)
            (root / 'payload.txt').write_text('changed', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Payload file changed'):
                acceptance.validate_payload_tree(
                    value, root, acceptance.RELEASE_ID, source_origin, ident('a'), publication_origin, artifacts)


if __name__ == '__main__':
    unittest.main()
