#!/usr/bin/env python3
"""Verify a self-contained Stage 2 delivery and reanalyze its original ILA CSVs."""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path, PurePosixPath

sys.dont_write_bytecode = True


def verify(root):
    root = root.resolve(strict=True)
    sys.path.insert(0, str(root))
    from tools.verify_windows_board_release import PRIVATE_PATH, identity, load, physical_findings, require, verify_board
    source = load(root / 'SOURCE_MANIFEST.json')
    require(source['schema'] == 'csip-source-export-v1', 'Source manifest schema differs')
    manifest = load(root / 'RELEASE_MANIFEST.json')
    require(manifest['schema'] == 'csip-self-contained-release-v2', 'Release schema differs')
    actual = set()
    for path in root.rglob('*'):
        if '.git' in path.relative_to(root).parts:
            continue
        require(not path.is_symlink() and not (hasattr(path, 'is_junction') and path.is_junction()), 'Links are forbidden')
        if path.is_file():
            require(not PRIVATE_PATH.search(path.read_bytes()), 'Private path in ' + path.relative_to(root).as_posix())
            if path != root / 'RELEASE_MANIFEST.json':
                actual.add(path.relative_to(root).as_posix())
    require(actual == set(manifest['files']), 'Release inventory differs')
    for relative, expected in manifest['files'].items():
        path = PurePosixPath(relative)
        require(not path.is_absolute() and '..' not in path.parts and ':' not in relative and '\\' not in relative, 'Invalid release path')
        require(identity(root / relative) == expected, 'Release file changed: ' + relative)
    for relative, expected in source['files'].items():
        require(relative in manifest['files'], 'Source omitted from release inventory')
        actual_source = identity(root / relative)
        require(actual_source == {'bytes': expected['size_bytes'], 'sha256': expected['sha256']}, 'Source input changed: ' + relative)
    provenance = load(root / 'EVIDENCE_PROVENANCE.json')
    records = provenance['records']
    for label, record in records.items():
        require(record['delivery_path'] in manifest['files'], 'Evidence path outside release inventory')
        require(record['delivered'] == identity(root / record['delivery_path']), 'Evidence representation differs: ' + label)
        require(record['representation'] in ('ORIGINAL_BYTES', 'PORTABLE_DERIVATIVE'), 'Unknown evidence representation')
        if record['representation'] == 'ORIGINAL_BYTES':
            require(record['original'] == record['delivered'], 'Original bytes differ: ' + label)
        if label.endswith(('.csv', '.bit', '.hwh', '.ltx')):
            require(record['representation'] == 'ORIGINAL_BYTES', 'Raw artifact or ILA bytes were changed')
    version = load(root / 'VERSION.json')
    require(version['schema'] == manifest['schema'] and version['release_id'] == manifest['release_id'], 'Release identity differs')
    require(version['formal_acceptance'] == 'NOT_FORMALLY_ACCEPTED', 'Unsupported acceptance claim')
    require(version['source_origin'] == source['origin'], 'Source origin differs')
    require(version['source_manifest'] == identity(root / 'SOURCE_MANIFEST.json'), 'Source manifest differs')
    require(version['publication_origin'] == provenance['publication_origin'], 'Publication origin differs')
    require(bool(provenance['publication_tools']), 'Publication tooling identities are missing')
    for relative, record in provenance['publication_tools'].items():
        require(relative in manifest['files'] and record['identity'] == identity(root / relative),
                'Publication tooling differs: ' + relative)
    board, loaded = verify_board(root / 'evidence/board', records)
    require(board['execution_id'] == version['board_execution_id'], 'Board execution differs')
    require(board['source_commit'] == source['origin']['commit'] and board['source_tree'] == source['origin']['tree'], 'Board source differs')
    require(len(list((root / 'evidence/board').rglob('*.csv'))) == 20, 'Raw ILA CSV count differs')
    physical = load(root / 'evidence/build/rebuild_receipt.json')
    require(physical['status'] == 'PASS' and physical['source_after_execution'] == 'PASS', 'Independent rebuild did not pass')
    require(physical['source_manifest']['sha256'] == version['source_manifest']['sha256'], 'Build source manifest differs')
    require(physical['origin'] == source['origin'], 'Build source origin differs')
    require(version['tool_versions'] == physical['tool_versions'], 'Tool versions differ')
    require('2024.1' in physical['tool_versions']['vivado'] and '5076996' in physical['tool_versions']['vivado'], 'Vivado version differs')
    require(physical['execution_id'] == board['physical_execution_id'] == version['physical_execution_id'], 'Physical execution differs')
    expected_checks = {'digital', 'software', 'engineering', 'producer', 'board_plan', 'seal', 'vivado'}
    require(set(physical['checks']) == expected_checks and all(row['status'] == 'PASS' and row['exit_code'] == 0 for row in physical['checks'].values()), 'Full regression/build checks differ')
    for check in expected_checks:
        require('build/' + check + '.log' in records, 'Required execution log is missing: ' + check)
    result = load(root / 'evidence/build/v/vivado_result.json')
    require(result['result_state'] == 'COMPLETED' and result['route_completed'], 'Routing incomplete')
    require(result['execution_id'] == physical['execution_id'] and
            result['source_commit'] == source['origin']['commit'] and
            result['source_tree'] == source['origin']['tree'], 'Vivado source or execution differs')
    require(result['implementation_profile'] == 'READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS', 'Vivado profile differs')
    artifacts = {row['role']: row for row in result['artifact_inventory']}
    for key, role in (('bit', 'BITSTREAM'), ('hwh', 'HWH'), ('ltx', 'LTX'), ('xsa', 'XSA')):
        expected = loaded['identity']['artifact_identities'][key]
        require(artifacts[role]['sha256'] == expected['sha256'] and
                artifacts[role]['bytes'] == expected['bytes'], 'Vivado/board artifact differs: ' + key)
    source_inputs = load(root / 'evidence/session/provenance/source_inputs.json')
    require({name: row['sha256'] for name, row in source_inputs['files'].items()} ==
            {name: row['sha256'] for name, row in source['files'].items()}, 'Board source input inventory differs')
    session = load(root / 'evidence/session/session_manifest.json')
    require(board['package_manifest'] == records['session/session_manifest.json']['original'], 'Board package manifest differs')
    for relative, row in session['files'].items():
        key = 'session/' + relative
        if key in records:
            require(row == records[key]['original'], 'Session input differs: ' + relative)
    for label, record in records.items():
        if label.startswith('build/') and label[6:] in physical['outputs']:
            require(physical['outputs'][label[6:]]['sha256'] == record['original']['sha256'], 'Rebuild output hash differs: ' + label)
    review = load(root / 'evidence/build/engineering_review.json')
    require(all(status == 'PASS' for status in review['checks'].values()), 'Physical report review did not pass')
    require(review['detailed_drc_methodology_review']['status'] == 'PASS', 'Detailed physical review incomplete')
    require(review['execution_id'] == physical['execution_id'], 'Review execution differs')
    require(review['rebuild_receipt']['sha256'] == records['build/rebuild_receipt.json']['original']['sha256'], 'Review build receipt differs')
    for relative, expected in review['detailed_drc_methodology_review']['evidence'].items():
        require(expected['sha256'] == records['build/' + relative]['original']['sha256'], 'Detailed review input differs')
    findings = physical_findings(root / 'evidence/build/v/reports')
    require(findings == review['new_findings'], 'Actual report findings differ')
    require(findings['cdc'].get('CDC-4') == {'severity': 'Critical', 'count': 1}, 'Retained CDC-4 severity/count differs')
    require(all(v >= 0 for k, v in findings['timing'].items() if k.endswith('_ns')), 'Negative timing slack')
    require(all(v == 0 for k, v in findings['timing'].items() if k.endswith('endpoints')), 'Failing timing endpoints')
    for key in ('bit', 'hwh', 'ltx'):
        expected = loaded['identity']['artifact_identities'][key]
        actual_artifact = identity(root / 'deploy/artifacts' / ('protection_system.' + key))
        require(actual_artifact == {'bytes': expected['bytes'], 'sha256': expected['sha256']}, 'Board/deployment artifact differs')
        require(review['artifact_comparison'][key]['rebuilt']['sha256'] == expected['sha256'], 'Review artifact differs')
    spec = importlib.util.spec_from_file_location('csip_deployment_verifier', root / 'deploy/load.py')
    deploy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(deploy)
    deploy_manifest, _ = deploy.verify(root / 'deploy')
    require(deploy_manifest['release_id'] == version['release_id'], 'Deployment release differs')
    annex = load(root / 'EVIDENCE_ANNEX.json')
    require(annex['release_id'] == version['release_id'], 'Annex release differs')
    require(annex['board_receipt'] == records['board/board_verification_receipt.json']['original'], 'Annex board receipt differs')
    require(annex['rebuilt'] == 'PASS' and annex['board_verified'] == 'PASS', 'Annex evidence states differ')
    require(annex['formal_acceptance'] == 'NOT_FORMALLY_ACCEPTED', 'Annex acceptance differs')
    require(annex['physical_findings'] == findings, 'Annex physical findings differ')
    require(annex['not_run'] == ['real analog ADC', 'external-pin PWM', 'external power stage', 'persistent boot', 'soak test', 'formal project acceptance'], 'Unvalidated scope claims differ')
    return {'status': 'PASS', 'release_id': version['release_id'], 'manifest_files': len(actual),
            'source_files': len(source['files']), 'raw_ila_csv': 20, 'private_paths': 0,
            'recorded_rebuilt': 'PASS', 'recorded_board_verified': 'PASS',
            'fresh_build_this_verification': 'NOT_RUN', 'formal_acceptance': 'NOT_FORMALLY_ACCEPTED'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.root), indent=2))
    except Exception as error:
        print('DELIVERY_VERIFICATION=FAIL: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
