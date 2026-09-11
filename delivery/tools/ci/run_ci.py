#!/usr/bin/env python3
"""One maintained CI contract for engineering checkouts and generated releases."""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.rebuild_delivery import prepare
from tools.source_export import export, verify


def run(output):
    output = output.resolve()
    if output.is_relative_to(ROOT) or ROOT.is_relative_to(output):
        raise ValueError('CI output must be disjoint from source')
    output.mkdir(parents=True, exist_ok=False)
    os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
    os.environ['PYTHONUTF8'] = '1'
    os.environ['CSIP_SIM_SCRATCH_ROOT'] = str(output / 'scratch')
    checks = {}

    def execute(name, root, args):
        command = [sys.executable, '-B', *map(str, args)]
        with (output / (name + '.log')).open('wb') as stream:
            result = subprocess.run(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT)
        checks[name] = {'command': command, 'exit_code': result.returncode}
        (output / 'ci_result.json').write_text(json.dumps(checks, indent=2) + '\n', encoding='utf-8')
        if result.returncode:
            raise RuntimeError(name + ' failed; see saved log')

    if (ROOT / 'verify.py').exists():
        execute('delivery_verify', ROOT, ['verify.py'])
        execute('deployment_offline', ROOT, ['deploy/load.py'])
        selected = prepare(ROOT, output / 'isolated')
    else:
        execute('engineering_abi', ROOT, ['tools/check_register_map_implementation.py', '--scope', 'engineering'])
        selected = output / 'selected'
        export(ROOT, selected, ROOT / 'config/self_contained_source.json')
    execute('preflight', selected, ['tools/rebuild.py', 'preflight', '--target', 'portable'])
    execute('portable', selected, ['tools/run_portable_regression.py', '--output', output / 'portable'])
    verify(selected)
    print('CI_CHECKS=PASS; ONLINE_ACTIONS_STATUS_IS_EXTERNAL')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    try:
        run(parser.parse_args().output)
    except Exception as error:
        print('CI_CHECKS=FAIL: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
