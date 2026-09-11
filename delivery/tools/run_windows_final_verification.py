#!/usr/bin/env python3
"""Run final digital/tool verification in a new external output directory."""
from __future__ import annotations

import argparse
import os
import platform
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_vivado_bin
from tools.board_validation.stage2_board_session import identity, utc_now, write_json
from tools.verify_windows_board_release import verify_board


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--board-evidence", type=Path, required=True)
    parser.add_argument("--execution-id", required=True)
    parser.add_argument("--vivado-bin", type=Path)
    args = parser.parse_args()
    board, _ = verify_board(args.board_evidence.resolve(strict=True))
    git = lambda *a: subprocess.check_output(["git", "-C", str(ROOT), *a], text=True).strip()
    if git("status", "--porcelain", "--untracked-files=all"):
        raise RuntimeError("Commit tooling before final verification")
    vivado = resolve_vivado_bin(ROOT, args.vivado_bin)
    if vivado is None:
        raise RuntimeError("Vivado is required through PATH, configuration, environment, or --vivado-bin")
    output = args.output.resolve()
    if output.is_relative_to(ROOT):
        raise RuntimeError("Final verification requires an external build root")
    output.mkdir(parents=True, exist_ok=False)
    commands = {
        "full_digital_regression": [sys.executable, "tools/run_stage2g_functional_rtl.py", "--output", str(output / "digital"),
                                    "--full-regression", "--xsim", "--require-clean", "--vivado-bin", str(vivado)],
        "python_engineering_tests": [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"],
        "software_tests": [sys.executable, "-m", "unittest", "discover", "-s", "sw/tests", "-v"],
        "producer_tests": [sys.executable, "tools/run_stage2i_b2_producer_tests.py", "--output-root", str(output / "producer")],
        "board_plan_rtl": [sys.executable, "tools/run_stage2_board_plan_rtl.py", "--output", str(output / "board-plan")],
    }
    for name in ("stage1_board_ila_binding_fixture_tests", "stage1_board_ila_capture_configuration_fixture_tests",
                 "stage1_board_ila_attempt03_ltx_binding_fixture_tests"):
        commands[name] = [sys.executable, "-c", f"import tkinter; tkinter.Tcl().eval('source {{tests/{name}.tcl}}')"]
    receipt = {"schema": "windows-final-verification-v1", "execution_id": args.execution_id,
               "board_execution_id": board["execution_id"], "board_receipt": identity(args.board_evidence / "board_verification_receipt.json"),
               "source_commit": git("rev-parse", "HEAD"), "source_tree": git("rev-parse", "HEAD^{tree}"),
               "python_version": platform.python_version(), "host_start_utc": utc_now(), "checks": {}}
    for name, command in commands.items():
        print(f"CHECK_START={name}", flush=True)
        with (output / f"{name}.log").open("xb") as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                    env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}, check=False)
        receipt["checks"][name] = {"command": command, "exit_code": result.returncode}
        print(f"CHECK_END={name} exit={result.returncode}", flush=True)
    receipt["host_end_utc"] = utc_now()
    receipt["status"] = "PASS" if all(c["exit_code"] == 0 for c in receipt["checks"].values()) else "FAIL"
    receipt["files"] = {p.relative_to(output).as_posix(): identity(p) for p in sorted(output.rglob("*"))
                        if p.is_file() and p.suffix in (".log", ".txt", ".json", ".tsv")}
    write_json(output / "verification_receipt.json", receipt)
    return 0 if receipt["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
