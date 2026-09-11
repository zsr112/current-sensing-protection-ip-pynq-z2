#!/usr/bin/env python3
"""Verify exported sources and run fresh digital and Vivado engineering builds."""
from __future__ import annotations

import argparse
import json
import os
import platform
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_directory, resolve_tool, resolve_vivado_bin
from tools.source_export import MANIFEST, identity, verify, write_json


def now():
    return datetime.now(timezone.utc).isoformat()


def tool_environment(args):
    if args.config:
        os.environ['CSIP_CONFIG'] = str(args.config.resolve(strict=True))
    tools = {}
    for name in ('iverilog', 'vvp', 'pwsh'):
        tool = resolve_tool(ROOT, name, getattr(args, name))
        tools[name] = tool
        if tool:
            os.environ['CSIP_' + name.upper()] = str(tool)
    vivado = resolve_vivado_bin(ROOT, args.vivado_bin)
    if vivado:
        os.environ['CSIP_VIVADO_BIN'] = str(vivado)
    board_repo = resolve_directory(ROOT, 'board_repo', args.board_repo, required=bool(args.board_repo))
    if board_repo:
        if not (board_repo / 'pynq-z2' / '1.0' / 'board.xml').is_file() and not list(board_repo.glob('**/board.xml')):
            raise ValueError('Board repository has no board.xml')
        os.environ['CSIP_BOARD_REPO'] = str(board_repo)
    os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
    # Older regression helpers use PATH. Prepend the explicitly resolved tools.
    os.environ['PATH'] = os.pathsep.join([*(str(p.parent) for p in tools.values() if p), os.environ.get('PATH', '')])
    return tools, vivado, board_repo


def version(executable, flag, *, vivado_banner=False):
    result = subprocess.run([str(executable), flag], capture_output=True, text=True, errors='replace')
    text = (result.stdout + result.stderr).strip()
    valid_banner = (vivado_banner and result.returncode in (0, 1)
                    and re.search(r'^vivado v2024\.1 \(64-bit\)', text, re.MULTILINE)
                    and 'SW Build 5076996' in text and 'ERROR:' not in text)
    if result.returncode and not valid_banner:
        raise RuntimeError(f'Tool version probe failed: {executable.name}')
    return text + f'\nVERSION_PROBE_EXIT_CODE={result.returncode}'


def run(args):
    if args.config:
        os.environ['CSIP_CONFIG'] = str(args.config.resolve())
    from tools.target_preflight import inventory
    target = args.target if args.phase == 'preflight' else args.phase
    readiness = inventory(ROOT, target, vars(args))
    if args.phase == 'preflight' or not readiness['target_ready']:
        print(json.dumps(readiness))
        return 0 if readiness['target_ready'] else 2
    source = verify(ROOT)
    tools, vivado, board_repo = tool_environment(args)
    if args.phase in ('digital', 'all') and any(tools[name] is None for name in ('iverilog', 'vvp')):
        raise ValueError('Icarus compiler and simulator are required')
    if args.phase in ('vivado', 'all') and (tools['pwsh'] is None or vivado is None):
        raise ValueError('PowerShell 7 and Vivado 2024.1 are required')
    if args.phase in ('digital', 'all') and vivado is None:
        raise ValueError('This complete regression includes vendor Tcl fixtures and requires Vivado')
    versions = {'python': platform.python_version()}
    for name in ('iverilog', 'vvp'):
        if tools[name]:
            versions[name] = version(tools[name], '-V')
    executable = vivado / ('vivado.bat' if os.name == 'nt' else 'vivado') if vivado else None
    if executable and args.phase != 'portable':
        versions['vivado'] = version(executable, '-version', vivado_banner=True)
        if '2024.1' not in versions['vivado'] or '5076996' not in versions['vivado']:
            raise ValueError('This build contract requires Vivado 2024.1 build 5076996')
    if tools['pwsh']:
        versions['pwsh'] = version(tools['pwsh'], '--version')
    if not args.execution_id or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{2,127}', args.execution_id):
        raise ValueError('Supply a new portable --execution-id')
    build_root = resolve_directory(ROOT, 'build_root', args.build_root)
    if build_root is None or build_root.is_relative_to(ROOT) or ROOT.is_relative_to(build_root):
        raise ValueError('Supply an external --build-root, CSIP_BUILD_ROOT or build_root configuration')
    build_root.mkdir(parents=True, exist_ok=False)
    receipt = {'schema': 'csip-independent-rebuild-v1', 'execution_id': args.execution_id,
               'start_utc': now(), 'source_manifest': identity(ROOT / MANIFEST), 'origin': source['origin'],
               'source_basis': 'HASH_VERIFIED_EXPORT', 'tool_versions': versions,
               'checks': {}, 'board_verified': 'NOT_RUN', 'formal_acceptance': 'NOT_FORMALLY_ACCEPTED'}
    if board_repo:
        receipt['board_files'] = {p.relative_to(board_repo).as_posix(): identity(p)
                                  for p in sorted(board_repo.rglob('*')) if p.is_file()}
    else:
        receipt['board_files'] = 'VIVADO_INSTALLATION_LOOKUP'
    def execute(name, command):
        print('CHECK_START=' + name, flush=True)
        with (build_root / (name + '.log')).open('wb') as stream:
            result = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        receipt['checks'][name] = {'exit_code': result.returncode, 'status': 'PASS' if result.returncode == 0 else 'FAIL'}
        print(f'CHECK_END={name} exit={result.returncode}', flush=True)
        write_json(build_root / 'rebuild_receipt.json', receipt)
        return result.returncode == 0
    try:
        if args.phase == 'portable':
            execute('portable', [sys.executable, '-B', 'tools/run_portable_regression.py', '--output', build_root / 'portable'])
        if args.phase in ('digital', 'all'):
            execute('digital', [sys.executable, '-B', 'tools/run_stage2g_functional_rtl.py', '--output', build_root / 'digital',
                               '--full-regression', '--xsim', '--vivado-bin', vivado])
            execute('software', [sys.executable, '-B', '-m', 'unittest', 'discover', '-s', 'sw/tests', '-v'])
            execute('engineering', [sys.executable, '-B', '-m', 'unittest', 'discover', '-s', 'tests', '-v'])
            execute('producer', [sys.executable, '-B', 'tools/run_stage2i_b2_producer_tests.py', '--output-root', build_root / 'producer'])
            execute('board_plan', [sys.executable, '-B', 'tools/run_stage2_board_plan_rtl.py', '--output', build_root / 'board-plan'])
        if args.phase in ('vivado', 'all'):
            request = {'schema_version': 'stage1e-execution-request-v2', 'run_kind': 'ENGINEERING',
                'execution_id': args.execution_id,
                'source': {'repository_root': ROOT.as_posix(), 'expected_commit': source['origin']['commit'],
                    'expected_tree': source['origin']['tree'], 'export_manifest_sha256': identity(ROOT / MANIFEST)['sha256']},
                'vivado': {'executable': executable.as_posix(), 'expected_version': '2024.1', 'expected_build': '5076996'},
                'hardware': {'part': 'xc7z020clg400-1', 'board_part': 'tul.com.tw:pynq-z2:part0:1.0'},
                'paths': {'workspace_root': (build_root / 'w').as_posix(), 'output_root': (build_root / 'v').as_posix()},
                'build_target': 'ARTIFACTS', 'implementation_profile': args.profile,
                'execution_contract_identity': identity(ROOT / 'fpga/vivado/build/config/stage1e_execution_contract_v1.json')['sha256'],
                'finding_decision_identity': 'NONE', 'timeout_seconds': 14400, 'retain_project': True}
            write_json(build_root / 'request-input.json', request)
            if not execute('seal', [tools['pwsh'], '-NoProfile', '-File', 'tools/create_rebuild_request.ps1',
                           '-InputJson', build_root / 'request-input.json', '-OutputJson', build_root / 'request.json']):
                raise RuntimeError('Request sealing failed')
            sealed = json.loads((build_root / 'request.json').read_text())
            execute('vivado', [tools['pwsh'], '-NoProfile', '-File',
                'fpga/vivado/build/runtime/entrypoint/v3/stage1e_production_runtime_entrypoint_v3.ps1',
                '-RequestPath', build_root / 'request.json', '-ExpectedRequestIdentity', sealed['request_identity']])
            # Process completion and report acceptance are separate checks.
            terminal = build_root / 'v/terminal_result.json'
            if terminal.is_file():
                receipt['terminal'] = json.loads(terminal.read_text())
            receipt['report_acceptance'] = 'NOT_RUN'
        verify(ROOT)
        receipt['source_after_execution'] = 'PASS'
    except Exception as error:
        receipt['error'] = str(error)
        receipt['checks']['orchestration'] = {'status': 'FAIL'}
    receipt['end_utc'] = now()
    receipt['status'] = 'PASS' if receipt['checks'] and all(row['status'] == 'PASS' for row in receipt['checks'].values()) else 'FAIL'
    receipt['outputs'] = {p.relative_to(build_root).as_posix(): identity(p) for p in sorted(build_root.rglob('*'))
                          if p.is_file() and p.name != 'rebuild_receipt.json' and 'w' not in p.relative_to(build_root).parts}
    write_json(build_root / 'rebuild_receipt.json', receipt)
    print('REBUILD_EXECUTION=' + receipt['status'])
    return 0 if receipt['status'] == 'PASS' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('preflight', 'portable', 'digital', 'vivado', 'all'))
    parser.add_argument('--target', choices=('portable', 'digital', 'vivado', 'all'), default='all')
    parser.add_argument('--config', type=Path)
    parser.add_argument('--execution-id')
    parser.add_argument('--build-root', type=Path)
    parser.add_argument('--profile', choices=('SAFE_INERT', 'READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS'), default='SAFE_INERT')
    for name in ('vivado-bin', 'board-repo', 'iverilog', 'vvp', 'pwsh'):
        parser.add_argument('--' + name)
    try:
        return run(parser.parse_args())
    except Exception as error:
        print('REBUILD_BLOCKED=' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
