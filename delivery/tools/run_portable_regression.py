#!/usr/bin/env python3
"""Run maintained Python and Icarus suites without vendor tools or hardware."""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.simulation_workspace import ascii_simulation_workspace


def run_checks(root, work, *, rtl_only=False):
    commands = []
    if not rtl_only:
        commands += [
            ('generation', ['tools/generate_register_map.py', '--check']),
            ('abi', ['tools/check_register_map_implementation.py']),
            ('tool_tests', ['-m', 'unittest', '-v',
                            'tools.tests.test_register_map_generator',
                            'tools.tests.test_stage2f_adc_contract_audit',
                            'tools.tests.test_stage2f_profile_generator',
                            'tools.tests.test_stage2g_reset_wait_first_fault_policy_audit',
                            'tools.tests.test_stage2h_c2_convergence']),
            ('software', ['-m', 'unittest', 'discover', '-s', 'sw/tests', '-v']),
            ('engineering', ['-m', 'unittest', 'discover', '-s', 'tests', '-v']),
        ]
    commands += [
        ('basic_rtl', ['sim/run_iverilog.py', '--output', str(work / 'basic')]),
        ('functional', ['tools/run_stage2g_functional_rtl.py', '--portable', '--output', str(work / 'functional')]),
        ('producer', ['tools/run_stage2i_b2_producer_tests.py', '--output-root', str(work / 'producer')]),
        ('board_plan', ['tools/run_stage2_board_plan_rtl.py', '--output', str(work / 'board-plan')]),
    ]
    receipt = {'schema': 'csip-portable-regression-v1', 'checks': {}, 'vendor_tcl': 'NOT_RUN',
               'xsim': 'NOT_RUN', 'board_verified': 'NOT_RUN', 'status': 'FAIL',
               'historical_stage2h_audit': 'OUT_OF_SCOPE: superseded pre-generated ABI audit, excluded by source selection'}
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1')
    for name, args in commands:
        command = [sys.executable, '-B', *args]
        with (work / (name + '.log')).open('wb') as stream:
            result = subprocess.run(command, cwd=root, env=environment, stdout=stream, stderr=subprocess.STDOUT)
        receipt['checks'][name] = {'command': command, 'exit_code': result.returncode,
                                  'status': 'PASS' if result.returncode == 0 else 'FAIL'}
        (work / 'portable_result.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
        print(f'PORTABLE_{name}={receipt["checks"][name]["status"]}', flush=True)
    receipt['status'] = 'PASS' if all(r['exit_code'] == 0 for r in receipt['checks'].values()) else 'FAIL'
    (work / 'portable_result.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    if receipt['status'] != 'PASS':
        raise RuntimeError('Portable regression failed; see preserved logs')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rtl-only', action='store_true', help='Run shared RTL suites; omit Python suites already run separately')
    args = parser.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(ROOT) or ROOT.is_relative_to(output):
        parser.error('Output must be external and disjoint from source')
    try:
        with ascii_simulation_workspace(ROOT, output, 'portable') as work:
            run_checks(ROOT, work, rtl_only=args.rtl_only)
        print('PORTABLE_REGRESSION=PASS')
        return 0
    except Exception as error:
        print('PORTABLE_REGRESSION=FAIL: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
