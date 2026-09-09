#!/usr/bin/env python3
"""Report configured toolchain availability without running a build."""

from __future__ import annotations

import argparse
import json
import platform
from pathlib import Path

try:
    from tools.runtime_config import resolve_vivado_bin, resolve_tool
except ModuleNotFoundError:
    from runtime_config import resolve_vivado_bin, resolve_tool  # type: ignore


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--vivado-bin")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    tools = {
        "python": resolve_tool(root, "python", aliases=("python3", "py")),
        "iverilog": resolve_tool(root, "iverilog", aliases=("iverilog.exe",)),
        "vvp": resolve_tool(root, "vvp", aliases=("vvp.exe",)),
        "bash": resolve_tool(root, "bash", aliases=("bash.exe",)),
    }
    vivado = resolve_vivado_bin(root, args.vivado_bin)
    payload = {
        "schema": "stage2-toolchain-preflight-v2",
        "platform": platform.platform(),
        "root": ".",
        "tools": {name: (str(path) if path else None) for name, path in tools.items()},
        "vivado_bin": str(vivado) if vivado else None,
        "portable_status": "PASS" if all(tools[name] for name in ("python", "iverilog", "vvp")) else "BLOCKED",
        "vivado_status": "PASS" if vivado else "NOT_CONFIGURED",
        "path_policy": "NO_PERSONAL_DEFAULT_PATHS",
    }
    if args.json:
        print(json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True))
    else:
        for name, value in payload["tools"].items():
            print(f"{name.upper()}={'FOUND' if value else 'MISSING'}{('=' + value) if value else ''}")
        print(f"VIVADO_BIN={'FOUND='+payload['vivado_bin'] if payload['vivado_bin'] else 'NOT_CONFIGURED'}")
        print(f"PORTABLE_TOOLCHAIN={payload['portable_status']}")
        print(f"VIVADO_TOOLCHAIN={payload['vivado_status']}")
    return 0 if payload["portable_status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
