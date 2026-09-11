#!/usr/bin/env python3
"""Replay the board C2 protection stimuli against the actual production core RTL.

This is a protection-policy preflight, not a replacement for CDC or board evidence.
"""
from __future__ import annotations
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_tool
from tools.simulation_workspace import ascii_simulation_workspace
from tools.board_validation.stage1_board_functional_validation import INDIVIDUAL_FAULT_CASES


class SimulationFailure(RuntimeError):
    def __init__(self, returncode):
        self.returncode = returncode


def vectors():
    commands = []
    def issue(a, b, n): commands.append((0, a, b, n, 0))
    def check(first, live, code, state=1): commands.append((2, first, live, code, state))
    def recover():
        commands.append((1, 0, 0, 0, 0))
        issue(1024, 1025, 2)
        check(0, 0, 0, 0)
    issue(1024, 1025, 2)
    issue(1500, 1501, 127)
    issue(1024, 1025, 1)
    check(0, 0, 0, 0)
    for case in INDIVIDUAL_FAULT_CASES:
        for command in case.get("prelude", ()):
            issue(*command)
        for index, (a, b, n) in enumerate(case["commands"]):
            if case["id"] == "SENSOR_STUCK" and index == 2:
                issue(a, b, n - 1)
                check(0, 0, 0, 0)
                issue(a, b, 1)
            else:
                issue(a, b, n)
        check(case.get("expected_first_bitmap", case["expected_bitmap"]), case["expected_bitmap"], case["expected_code"])
        recover()
    issue(3200, 2500, 1)
    check(5, 5, 6)
    recover()
    for _ in range(2):
        issue(1000, 1300, 1)
        check(4, 4, 2)
    commands.append((1, 0, 0, 0, 0))
    issue(1000, 1300, 1)
    check(4, 4, 2)
    recover()
    return commands


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    try:
        with ascii_simulation_workspace(ROOT, output, "stage2-board-c2-plan") as work:
            path = work / "vectors.txt"
            path.write_text("".join(" ".join(map(str, row)) + "\n" for row in vectors()), encoding="ascii")
            image = work / "c2_plan.vvp"
            sources = [ROOT / "rtl" / name for name in (
                "current_compare_dual.v", "sensor_health_monitor.v", "fault_classifier.v", "protection_fsm.v",
                "pwm_gen.v", "pwm_gate.v", "protection_core_top.v")]
            for name, command in (
                ("compile", [str(resolve_tool(ROOT, "iverilog")), "-g2012", "-I", str(ROOT / "rtl"), "-s", "tb_stage2_board_c2_plan", "-o", str(image),
                             str(ROOT / "tb/stage2i/tb_stage2_board_c2_plan.sv"), *map(str, sources)]),
                ("simulation", [str(resolve_tool(ROOT, "vvp")), str(image), "+vectors=vectors.txt"]),
            ):
                result = subprocess.run(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                (work / f'{name}.raw.log').write_bytes(result.stdout)
                result.stdout = result.stdout.decode('utf-8', errors='replace')
                (work / f"{name}.log").write_text(result.stdout, encoding="utf-8")
                (work / f'{name}.command.json').write_text(json.dumps({'command': command, 'cwd': str(work), 'exit_code': result.returncode}, indent=2) + '\n', encoding='utf-8')
                print(result.stdout, end="")
                if result.returncode:
                    raise SimulationFailure(result.returncode)
                if name == 'simulation' and 'C2_PROTECTION_PLAN_RTL=PASS checks=20 samples=923' not in result.stdout:
                    raise SimulationFailure(1)
    except SimulationFailure as error:
        return error.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
