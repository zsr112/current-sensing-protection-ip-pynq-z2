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
sys.path.insert(0, str(ROOT))
from tools.source_export import verify as verify_source
from tools.runtime_config import optional_git_identity
from tools.build_windows_board_release import portable_json, portable_text
from tools.verify_windows_board_release import PRIVATE_PATH, identity, load, require, verify_board
from tools.board_validation.build_stage1_board_execution_package import write_deterministic_zip
from tools.board_validation.stage2_board_session import verify_session_package
from sw import stage2i_board_runtime as runtime


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n', encoding='utf-8', newline='\n')


def build(args):
    source_root = args.source.resolve(strict=True)
    source = verify_source(source_root)
    physical_root = args.build.resolve(strict=True)
    board_root = args.board.resolve(strict=True)
    session_root = args.session.resolve(strict=True)
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
    for root in (ROOT, source_root, physical_root, board_root, session_root):
        require(not output.is_relative_to(root) and not root.is_relative_to(output), 'Release overlaps an input authority')
    shutil.copytree(source_root, output)
    records = {}
    roots = {ROOT: 'ENGINEERING', source_root: 'SOURCE', physical_root: 'BUILD', board_root: 'BOARD', session_root: 'SESSION'}

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
                delivered = portable_text(original.decode('utf-8'), roots).encode()
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
        ('tools/board_validation/load_deployment.py', 'deploy/load.py'),
        ('tools/board_validation/load_deployment.py', 'tools/board_validation/load_deployment.py'),
        ('tools/self_contained_verify.py', 'verify.py'),
        ('tools/self_contained_verify.py', 'tools/self_contained_verify.py'),
        ('tools/rebuild_delivery.py', 'tools/rebuild_delivery.py'),
        ('tools/build_self_contained_release.py', 'tools/build_self_contained_release.py'),
        ('docs/delivery/self_contained_readme.md', 'docs/delivery/self_contained_readme.md'),
        ('tests/test_rebuild_delivery.py', 'tests/test_rebuild_delivery.py'),
    ]
    publication_tools = {}
    for relative, destination in publication_files:
        target = output / destination
        require(not target.exists() or identity(target) == identity(ROOT / relative),
                'Publication tool differs from bound physical source: ' + destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
        publication_tools[destination] = {'source_path': relative, 'identity': identity(target)}
    publication_origin = optional_git_identity(ROOT)
    if publication_origin is not None:
        publication_origin = {key: value for key, value in publication_origin.items() if key != 'branch'}
        publication_origin['branch'] = 'release-preparation'
    if publication_origin is not None:
        for relative, _ in publication_files:
            committed = subprocess.check_output(['git', '-C', str(ROOT), 'show', 'HEAD:' + relative])
            require(committed == (ROOT / relative).read_bytes(), 'Publication tool is not committed: ' + relative)
    write_json(deploy / 'DEPLOY_MANIFEST.json', {'schema': 'csip-deployment-v2', 'release_id': args.release_id,
        'files': {p.relative_to(deploy).as_posix(): identity(p) for p in sorted(deploy.rglob('*')) if p.is_file()}})
    write_json(output / 'VERSION.json', {'schema': 'csip-self-contained-release-v2', 'release_id': args.release_id,
        'source_origin': source['origin'], 'source_manifest': identity(source_root / 'SOURCE_MANIFEST.json'),
        'physical_execution_id': run['execution_id'], 'board_execution_id': board['execution_id'],
        'board_tooling_commit': session['tooling_commit'], 'tool_versions': portable_json(run['tool_versions'], roots),
        'publication_origin': publication_origin,
        'evidence_states': ['REBUILT', 'BOARD_VERIFIED'], 'formal_acceptance': 'NOT_FORMALLY_ACCEPTED'})
    write_json(output / 'EVIDENCE_PROVENANCE.json', {'schema': 'csip-evidence-provenance-v2', 'records': records,
        'publication_tools': publication_tools, 'publication_origin': publication_origin,
        'policy': 'Raw artifacts and ILA bytes are unchanged. Portable report representations have separate original and delivered hashes. Complete source inputs remain ordinary files in their original directory relationships.'})
    write_json(output / 'EVIDENCE_ANNEX.json', {'schema': 'csip-evidence-annex-v2', 'release_id': args.release_id,
        'rebuilt': 'PASS', 'board_verified': 'PASS', 'formal_acceptance': 'NOT_FORMALLY_ACCEPTED',
        'board_receipt': identity(board_root / 'board_verification_receipt.json'), 'physical_findings': review['new_findings'],
        'cdc_4': 'Critical retained; bounded FIFO engineering review PASS',
        'not_run': ['real analog ADC', 'external-pin PWM', 'external power stage', 'persistent boot', 'soak test', 'formal project acceptance'],
        'historical': {'classification': 'HISTORICAL_ACCEPTED', 'used_as_new_board_proof': False,
                       'r4_manifest': review['r4_reference_manifest']}})
    readme = ROOT / 'docs/delivery/self_contained_readme.md'
    shutil.copyfile(readme, output / 'README.md')
    (output / '.gitignore').write_text('__pycache__/\n*.pyc\n.Xil/\n', encoding='utf-8')
    (output / '.gitattributes').write_text('* -text\n', encoding='utf-8')
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
    for name in ('source', 'build', 'board', 'session', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--release-id', required=True)
    build(parser.parse_args())
