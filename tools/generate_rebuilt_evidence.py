#!/usr/bin/env python3
"""Create an auditable REBUILT evidence receipt from one clean execution."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tool_version(executable: str) -> str:
    try:
        lower = executable.lower()
        if lower.endswith(("vivado.exe", "vivado.bat")):
            flag = "-version"
        elif lower.endswith(("iverilog", "iverilog.exe", "vvp", "vvp.exe")):
            flag = "-V"
        else:
            flag = "--version"
        result = subprocess.run([executable, flag], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        return result.stdout.strip().splitlines()[0] if result.stdout.strip() else f"exit={result.returncode}"
    except OSError as exc:
        return f"UNAVAILABLE: {exc}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--execution-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--input", dest="inputs", action="append", default=[])
    parser.add_argument("--artifact", dest="artifacts", action="append", default=[])
    parser.add_argument("--tool", dest="tools", action="append", default=[])
    parser.add_argument("--source-commit", default="UNAVAILABLE")
    parser.add_argument("--source-tree", default="UNAVAILABLE")
    args = parser.parse_args(argv)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    def records(values: list[str], label: str) -> list[dict[str, object]]:
        result = []
        for value in values:
            path = Path(value).resolve(strict=True)
            result.append({"role": label, "path": path.name, "bytes": path.stat().st_size, "sha256": sha256(path)})
        return result

    receipt = {
        "schema": "stage2-rebuilt-evidence-v1",
        "evidence_state": "REBUILT",
        "execution_id": args.execution_id,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "host": {"platform": platform.platform(), "python": sys.version.split()[0]},
        "source": {"commit": args.source_commit, "tree": args.source_tree},
        "tool_versions": {Path(tool).name: tool_version(tool) for tool in args.tools},
        "inputs": records(args.inputs, "INPUT"),
        "outputs": records(args.artifacts, "REBUILT_OUTPUT"),
    }
    receipt_path = output / "rebuilt_evidence.json"
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=True, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"REBUILT_EVIDENCE=PASS execution_id={args.execution_id} receipt={receipt_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
