#!/usr/bin/env python3
"""Assemble a flat, complete rebuild source delivery from new verified evidence."""
from __future__ import annotations

import argparse
import copy
import csv
import io
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUBLICATION_ROOT = ROOT
if ROOT.name == 'publication' and (ROOT.parent / 'SOURCE_MANIFEST.json').is_file():
    ROOT = ROOT.parent
sys.path.insert(0, str(ROOT))
from tools.source_export import verify as verify_source
from tools.runtime_config import optional_git_identity
from tools.build_windows_board_release import portable_json, portable_text
from tools.verify_windows_board_release import PRIVATE_PATH, identity, load, require, verify_board
from tools.board_validation.build_stage1_board_execution_package import write_deterministic_zip
from tools.board_validation.stage2_board_session import verify_session_package
from tools.release_acceptance import (LIMITATIONS, RELEASE_ID, STATUS, build_acceptance,
                                      build_payload_manifest, validate_final_evidence,
                                      validate_payload_tree, validate_preseal_evidence)
from sw import stage2i_board_runtime as runtime


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n', encoding='utf-8', newline='\n')


def portable_log(data, roots):
    # Windows subprocess logs may mix UTF-8 and local-codepage diagnostics.
    # Escape undecodable bytes instead of dropping them or guessing an encoding.
    # The provenance record retains the hash of the untouched original log.
    return portable_text(data.decode('utf-8', errors='backslashreplace'), roots).encode('utf-8')


def publish_file(output, relative, destination):
    source = publication_source(relative)
    target = output / destination
    if target.exists() and identity(target) != identity(source):
        # A later publication tool must never replace a physical source input.
        target = output / 'publication' / destination
        require(not target.exists(), 'Publication destination already exists')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    return target.relative_to(output).as_posix(), {'source_path': relative, 'identity': identity(target)}


def publication_source(relative):
    if PUBLICATION_ROOT != ROOT and (PUBLICATION_ROOT / relative).is_file():
        return PUBLICATION_ROOT / relative
    return ROOT / relative


def build(args):
    require(args.release_id == RELEASE_ID, 'Formal release ID differs')
    expected_output_name = args.release_id if args.phase == 'final' else args.release_id + '-payload'
    require(args.output.name == expected_output_name,
            'Release output name differs for ' + args.phase + ' phase')
    if args.phase == 'final':
        require(args.accepted_at is not None, 'Final phase requires --accepted-at')
    source_root = args.source.resolve(strict=True)
    source = verify_source(source_root)
    physical_root = args.build.resolve(strict=True)
    board_root = args.board.resolve(strict=True)
    session_root = args.session.resolve(strict=True)
    final_root = args.final.resolve(strict=True)
    run = load(physical_root / 'rebuild_receipt.json')
    review = load(physical_root / 'engineering_review.json')
    board, loaded = verify_board(board_root)
    session = verify_session_package(session_root)
    require(run['status'] == 'PASS' and run['source_after_execution'] == 'PASS', 'Build incomplete')
    require(run['origin'] == source['origin'] and run['source_manifest']['sha256'] == identity(source_root / 'SOURCE_MANIFEST.json')['sha256'], 'Independent source identity differs')
    require(board['physical_execution_id'] == run['execution_id'] and board['source_commit'] == source['origin']['commit'], 'Board does not cover the selected build')
    require(board['package_manifest'] == identity(session_root / 'session_manifest.json'), 'Board session identity differs')
    require(review['execution_id'] == run['execution_id'] and review['detailed_drc_methodology_review']['status'] == 'PASS', 'Current physical review incomplete')
    output = args.output.resolve()
    require(not output.exists() and not output.with_suffix('.zip').exists(), 'Release output already exists')
    for root in (ROOT, source_root, physical_root, board_root, session_root, final_root):
        require(not output.is_relative_to(root) and not root.is_relative_to(output), 'Release overlaps an input authority')
    shutil.copytree(source_root, output)
    records = {}
    roots = {ROOT: 'ENGINEERING', source_root: 'SOURCE', physical_root: 'BUILD', board_root: 'BOARD',
             session_root: 'SESSION', final_root: 'FINAL'}

    def evidence(label, path, destination=None, raw=False):
        destination = destination or 'evidence/' + label
        target = output / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        original = path.read_bytes()
        delivered = original
        if PRIVATE_PATH.search(original):
            require(not raw, 'Private path in immutable raw evidence: ' + label)
            if path.suffix == '.json':
                delivered = (json.dumps(portable_json(load(path), roots), sort_keys=True, indent=2) + '\n').encode()
            else:
                delivered = portable_log(original, roots)
        target.write_bytes(delivered)
        records[label] = {'source_relative_path': label, 'original': identity(path), 'delivery_path': destination,
                          'delivered': identity(target), 'representation': 'ORIGINAL_BYTES' if original == delivered else 'PORTABLE_DERIVATIVE'}

    for relative in ['board_verification_receipt.json', *board['files']]:
        evidence('board/' + relative, board_root / relative, raw=relative.endswith('.csv'))
    for name in ('board-service.log', 'host-session.log'):
        if (board_root.parent / name).is_file():
            evidence('transport/' + name, board_root.parent / name)
    for relative in ('session_manifest.json', 'provenance/source_inputs.json', 'provenance/rebuilt_evidence.json', runtime.PROFILE_FILENAME):
        evidence('session/' + relative, session_root / relative)
    evidence('build/rebuild_receipt.json', physical_root / 'rebuild_receipt.json')
    evidence('build/engineering_review.json', physical_root / 'engineering_review.json')
    for relative, expected in run['outputs'].items():
        path = physical_root / relative
        if path.suffix not in ('.log', '.rpt', '.json', '.tsv', '.txt', '.csv'):
            continue
        if any(part in ('.Xil', 'xsim.dir') for part in path.relative_to(physical_root).parts):
            continue
        require(identity(path)['sha256'] == expected['sha256'], 'Build evidence changed: ' + relative)
        evidence('build/' + relative, path)
    for relative, expected in review['detailed_drc_methodology_review']['evidence'].items():
        require(identity(physical_root / relative)['sha256'] == expected['sha256'], 'Routed review evidence changed')
        evidence('build/' + relative, physical_root / relative)
    for name in ('fifo-routed-audit.log', 'drc-routed-audit-2.log'):
        evidence('build/' + name, physical_root / name)
    for suffix in ('bit', 'hwh', 'ltx'):
        path = physical_root / 'v/artifacts' / ('protection_system.' + suffix)
        expected = loaded['identity']['artifact_identities'][suffix]
        require(identity(path) == {'bytes': expected['bytes'], 'sha256': expected['sha256']}, 'Board artifact differs')
        evidence('artifact/' + suffix, path, 'deploy/artifacts/' + path.name, raw=True)

    deploy = output / 'deploy'
    for relative, name in (
        ('sw/stage2i_board_runtime.py', 'stage2i_board_runtime.py'),
        ('sw/protection_ip_interface.py', 'protection_ip_interface.py'),
        ('sw/generated/protection_register_map.py', 'generated/protection_register_map.py')):
        target = deploy / 'runtime' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_root / relative, target)
    # This is a new deployable relative-path manifest, not the original build TSV.
    artifact_manifest = physical_root / 'v/artifacts/artifact-manifest.tsv'
    rows = list(csv.DictReader(artifact_manifest.read_text().splitlines(), delimiter='\t'))
    for row in rows:
        filename = Path(row['canonical_path']).name
        row['canonical_path'] = ('external-physical/artifacts/' if row['role'] == 'XSA' else 'artifacts/') + filename if row['kind'] == 'artifact' else 'external-physical/reports/' + filename
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]), delimiter='\t', lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
    (deploy / 'provenance').mkdir()
    (deploy / 'provenance/artifact-manifest.tsv').write_text(stream.getvalue(), encoding='utf-8', newline='\n')
    profile = copy.deepcopy(runtime.load_profile(session_root, runtime.READY_AWARE))
    profile['artifact_manifest'].update(identity(deploy / 'provenance/artifact-manifest.tsv'))
    write_json(deploy / runtime.PROFILE_FILENAME, profile)
    publication_files = [
        ('.github/workflows/portable.yml', '.github/workflows/portable.yml'),
        ('tools/board_validation/load_deployment.py', 'deploy/load.py'),
        ('tools/board_validation/load_deployment.py', 'tools/board_validation/load_deployment.py'),
        ('tools/self_contained_verify.py', 'verify.py'),
        ('tools/self_contained_verify.py', 'tools/self_contained_verify.py'),
        ('tools/rebuild_delivery.py', 'tools/rebuild_delivery.py'),
        ('tools/build_self_contained_release.py', 'tools/build_self_contained_release.py'),
        ('tools/release_acceptance.py', 'release_acceptance.py'),
        ('tools/release_acceptance.py', 'tools/release_acceptance.py'),
        ('tools/release_acceptance.py', 'deploy/release_acceptance.py'),
        ('tools/build_online_ci_evidence.py', 'tools/build_online_ci_evidence.py'),
        ('tools/build_release_final_evidence.py', 'tools/build_release_final_evidence.py'),
        ('tools/build_windows_validation.py', 'tools/build_windows_validation.py'),
        ('tools/validate_release_payload.py', 'tools/validate_release_payload.py'),
        ('tools/verify_post_seal_release.py', 'tools/verify_post_seal_release.py'),
        ('docs/architecture/current_architecture.md', 'publication/docs/architecture/current_architecture.md'),
        ('docs/delivery/self_contained_readme.md', 'docs/delivery/self_contained_readme.md'),
        ('docs/delivery/v2r3_release_seal.md', 'docs/delivery/v2r3_release_seal.md'),
        ('tests/test_rebuild_delivery.py', 'tests/test_rebuild_delivery.py'),
        ('tests/test_publication_evidence.py', 'publication/tests/test_publication_evidence.py'),
        ('tests/test_release_acceptance.py', 'publication/tests/test_release_acceptance.py'),
        ('tests/test_release_seal.py', 'publication/tests/test_release_seal.py'),
    ]
    publication_tools = {}
    for relative, destination in publication_files:
        destination, record = publish_file(output, relative, destination)
        publication_tools[destination] = record
    publication_origin = optional_git_identity(ROOT)
    if publication_origin is not None:
        publication_origin = {key: value for key, value in publication_origin.items() if key != 'branch'}
        publication_origin['branch'] = 'release-preparation'
    if publication_origin is not None:
        for relative, _ in publication_files:
            committed = subprocess.check_output(['git', '-C', str(ROOT), 'show', 'HEAD:' + relative])
            require(committed == (ROOT / relative).read_bytes(), 'Publication tool is not committed: ' + relative)
    require(publication_origin is not None, 'Formal publication requires a committed Git identity')
    source_manifest = identity(source_root / 'SOURCE_MANIFEST.json')
    artifact_identities = {name: {'bytes': loaded['identity']['artifact_identities'][name]['bytes'],
                                  'sha256': loaded['identity']['artifact_identities'][name]['sha256']}
                           for name in ('bit', 'hwh', 'ltx')}
    validate_preseal_evidence(final_root, args.release_id, source['origin'], source_manifest,
                              publication_origin, artifact_identities)
    for filename in ('online_ci.json', 'windows_validation.json'):
        evidence('final/' + filename, final_root / filename, raw=True)
    readme = publication_source('docs/delivery/self_contained_readme.md')
    shutil.copyfile(readme, output / 'README.md')
    (output / '.gitignore').write_text('__pycache__/\n*.pyc\n.Xil/\n', encoding='utf-8')
    (output / '.gitattributes').write_text('* -text\n', encoding='utf-8')
    write_json(output / 'EVIDENCE_PROVENANCE.json', {'schema': 'csip-evidence-provenance-v2', 'records': records,
        'publication_tools': publication_tools, 'publication_origin': publication_origin,
        'policy': 'Raw artifacts and ILA bytes are unchanged. Portable report representations have separate original and delivered hashes; undecodable UTF-8 log bytes use backslash escapes. Complete physical source inputs remain unchanged in their original directory relationships. Differing later publication tooling is stored under publication/ and identified by publication_origin. Mac payload validation and the final decision are post-payload records bound separately by ACCEPTANCE.json.'})
    payload = build_payload_manifest(output, args.release_id, source['origin'], source_manifest,
                                     publication_origin, artifact_identities)
    write_json(output / 'PAYLOAD_MANIFEST.json', payload)
    validate_payload_tree(payload, output, args.release_id, source['origin'], source_manifest,
                          publication_origin, artifact_identities)
    if args.phase == 'preseal':
        archive = output.with_suffix('.zip')
        write_deterministic_zip(output, archive)
        with tempfile.TemporaryDirectory(prefix='payload extraction ', dir=output.parent) as name:
            extracted = Path(name)
            with zipfile.ZipFile(archive) as zipped:
                require(zipped.testzip() is None, 'Pre-seal ZIP integrity failure')
                zipped.extractall(extracted)
            validate_payload_tree(load(extracted / 'PAYLOAD_MANIFEST.json'), extracted, args.release_id,
                                  source['origin'], source_manifest, publication_origin, artifact_identities)
        print(json.dumps({'release_id': args.release_id, 'phase': args.phase, 'zip': str(archive),
                          'identity': identity(archive),
                          'payload_manifest': identity(output / 'PAYLOAD_MANIFEST.json'),
                          'verification': 'PASS'}))
        return
    payload_manifest = identity(output / 'PAYLOAD_MANIFEST.json')
    final_records = validate_final_evidence(final_root, args.release_id, source['origin'], source_manifest,
                                            publication_origin, artifact_identities, payload_manifest)
    for filename in ('mac_validation.json', 'final_validation_receipt.json'):
        evidence('final/' + filename, final_root / filename, raw=True)
    manifest_identities = {
        'source': source_manifest,
        'board_session': identity(session_root / 'session_manifest.json'),
        'artifact': identity(deploy / 'provenance/artifact-manifest.tsv'),
        'release_payload': payload_manifest,
    }
    acceptance = build_acceptance(
        release_id=args.release_id,
        accepted_at=args.accepted_at,
        build_execution_id=run['execution_id'],
        board_execution_id=board['execution_id'],
        source_origin=source['origin'],
        source_manifest=source_manifest,
        publication_origin=publication_origin,
        publication_tools=publication_tools,
        artifact_identities=artifact_identities,
        manifest_identities=manifest_identities,
        final_records=final_records,
        build_evidence_path=output / 'evidence/build/rebuild_receipt.json',
        board_evidence_path=output / 'evidence/board/board_verification_receipt.json',
    )
    write_json(output / 'ACCEPTANCE.json', acceptance)
    write_json(deploy / 'ACCEPTANCE.json', acceptance)
    write_json(deploy / 'DEPLOY_MANIFEST.json', {'schema': 'csip-deployment-v2', 'release_id': args.release_id,
        'files': {p.relative_to(deploy).as_posix(): identity(p) for p in sorted(deploy.rglob('*')) if p.is_file()}})
    write_json(output / 'VERSION.json', {'schema': 'csip-self-contained-release-v2', 'release_id': args.release_id,
        'source_origin': source['origin'], 'source_manifest': identity(source_root / 'SOURCE_MANIFEST.json'),
        'physical_execution_id': run['execution_id'], 'board_execution_id': board['execution_id'],
        'board_tooling_commit': session['tooling_commit'], 'tool_versions': portable_json(run['tool_versions'], roots),
        'publication_origin': publication_origin,
        'evidence_states': ['REBUILT', 'BOARD_VERIFIED', 'FINAL_VERIFIED', STATUS],
        'formal_acceptance': STATUS,
        'acceptance': identity(output / 'ACCEPTANCE.json')})
    write_json(output / 'EVIDENCE_ANNEX.json', {'schema': 'csip-evidence-annex-v2', 'release_id': args.release_id,
        'rebuilt': 'PASS', 'board_verified': 'PASS', 'final_verified': 'PASS', 'formal_acceptance': STATUS,
        'acceptance': identity(output / 'ACCEPTANCE.json'),
        'board_receipt': identity(board_root / 'board_verification_receipt.json'), 'physical_findings': review['new_findings'],
        'cdc_4': 'Critical retained; bounded FIFO engineering review PASS',
        'accepted_limitations': LIMITATIONS,
        'not_run': LIMITATIONS,
        'historical': {'classification': 'HISTORICAL_ACCEPTED', 'used_as_new_board_proof': False,
                       'r4_manifest': review['r4_reference_manifest']}})
    write_json(output / 'RELEASE_MANIFEST.json', {'schema': 'csip-self-contained-release-v2', 'release_id': args.release_id,
        'files': {p.relative_to(output).as_posix(): identity(p) for p in sorted(output.rglob('*')) if p.is_file()}})
    subprocess.run([sys.executable, '-B', str(output / 'verify.py'), str(output)], check=True, cwd=output)
    archive = output.with_suffix('.zip')
    write_deterministic_zip(output, archive)
    with tempfile.TemporaryDirectory(prefix='delivery extraction ', dir=output.parent) as name:
        extracted = Path(name)
        with zipfile.ZipFile(archive) as zipped:
            require(zipped.testzip() is None, 'ZIP integrity failure')
            zipped.extractall(extracted)
        subprocess.run([sys.executable, '-B', str(extracted / 'verify.py'), str(extracted)], check=True, cwd=extracted)
    print(json.dumps({'release_id': args.release_id, 'zip': str(archive), 'identity': identity(archive), 'verification': 'PASS'}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'build', 'board', 'session', 'final', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--release-id', required=True)
    parser.add_argument('--phase', choices=('preseal', 'final'), default='final')
    parser.add_argument('--accepted-at', help='Project-owner decision time as an ISO-8601 UTC value')
    build(parser.parse_args())
