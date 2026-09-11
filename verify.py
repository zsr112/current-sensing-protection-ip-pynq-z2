#!/usr/bin/env python3
"""Current v2r3 entry: verify the sealed delivery at its fixed repository path."""
import subprocess
import sys
from pathlib import Path

if __name__ == '__main__':
    delivery = Path(__file__).resolve().parent / 'delivery'
    raise SystemExit(subprocess.call(
        [sys.executable, '-B', str(delivery / 'verify.py'), str(delivery)], cwd=delivery))
