#!/usr/bin/env python3
"""Compatibility entry for target-aware exported-source preflight (no build)."""
from __future__ import annotations
import argparse
import json
import os
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.target_preflight import inventory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=('portable', 'digital', 'vivado', 'all'), default='all')
    parser.add_argument('--json', action='store_true', help='Retained for command compatibility; output is always structured JSON')
    parser.add_argument('--config', type=Path)
    for name in ('vivado-bin', 'board-repo', 'iverilog', 'vvp', 'pwsh', 'build-root'):
        parser.add_argument('--' + name)
    args = parser.parse_args()
    if args.config:
        os.environ['CSIP_CONFIG'] = str(args.config.resolve())
    result = inventory(ROOT, args.target, vars(args))
    print(json.dumps(result, indent=2))
    return 0 if result['target_ready'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
