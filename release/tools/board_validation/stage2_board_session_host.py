#!/usr/bin/env python3
"""Coordinate authenticated board actions with bounded Vivado ILA captures."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if (ROOT / "sw").is_dir():
    sys.path.insert(0, str(ROOT))
    from tools.board_validation import stage1_board_evidence_analyzer as analyzer
    from tools.board_validation.stage2_board_session import SCENARIOS, EXTRA_SCENARIOS, FAULTS, identity, write_json, verify_session_package
    from sw import stage2i_board_runtime as runtime
else:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "runtime"))
    import stage1_board_evidence_analyzer as analyzer
    from stage2_board_session import SCENARIOS, EXTRA_SCENARIOS, FAULTS, identity, write_json, verify_session_package
    import stage2i_board_runtime as runtime

MODES = {
    "normal_pwm": ("source_accept", "destination_trigger_now"),
    "ch1_overcurrent": ("source_accept", "destination_fault_latched"),
    "ch2_overcurrent": ("source_accept", "destination_fault_latched"),
    "differential_fault": ("source_accept", "destination_fault_latched"),
    "live_clear_rejected": ("source_accept", "destination_fault_valid"),
    "sample_source_removal": ("source_trigger_now", "destination_trigger_now"),
    "clear_recovery": ("source_accept", "destination_reset_wait"),
    "recovered_pwm": ("source_accept", "destination_armed"),
    "source_protocol": ("source_stall", "destination_trigger_now"),
    "legacy_c2": ("source_accept", "destination_fault_latched"),
}


def require(condition, message):
    if not condition:
        raise analyzer.EvidenceError(message)


def verify_pwm(rows):
    require(len(rows) >= 1001, "Insufficient stable PWM samples")
    require(all(row["pwm_out"] == row["pwm_raw"] for row in rows), "PWM output differs from enabled raw PWM")
    rises = [i for i in range(1, len(rows)) if rows[i - 1]["pwm_raw"] == 0 and rows[i]["pwm_raw"] == 1]
    require(len(rises) >= 2, "No complete PWM period")
    for start, end in zip(rises, rises[1:]):
        require(end - start == 1000, "PWM period differs from 1000 destination cycles")
        require(sum(row["pwm_raw"] for row in rows[start:end]) == 500, "PWM duty differs from 500 destination cycles")
    return {"period_cycles": 1000, "high_cycles": 500, "complete_periods": len(rises) - 1}


def analyze_rows(scenario, source, destination):
    require(len(source) == 4096 and len(destination) == 4096, "ILA depth must be 4096 per core")
    require(all(row["aresetn"] == 1 and row["fsm_state"] in (0, 1, 2) for row in destination), "Unexpected reset or undefined FSM state")
    require({row["pwm_raw"] for row in destination} == {0, 1}, "Raw PWM was not running during the scenario")
    require(all(row["pwm_out"] == 0 for row in destination if row["fault_latched"] or row["fsm_state"] != 0), "PWM escaped fault/recovery gating")
    accepted = [row for row in source if row["producer_accept"]]
    for row in source:
        require(row["producer_accept"] == (row["adc_sample_valid"] & row["adc_sample_ready"]), "Source handshake mismatch")
    proof = {"source_samples": len(source), "destination_samples": len(destination), "captured_accepts": len(accepted)}
    if scenario == "sample_source_removal":
        require(all(not row["adc_sample_valid"] and not row["producer_active"] and not row["producer_remaining"] for row in source), "Sample source did not remain removed")
        require(all(row["fault_latched"] == 1 and row["fault_code_latched"] == 2 and row["fsm_state"] == 1 for row in destination), "Removing samples released the fault")
    else:
        sample = (1500, 1501) if scenario == "source_protocol" else (1024, 1025)
        if scenario in FAULTS:
            sample = FAULTS[scenario][:2]
        elif scenario == "live_clear_rejected":
            sample = (1000, 1300)
        count = 127 if scenario in ("normal_pwm", "source_protocol") else 1
        require(len(accepted) == count, f"Captured source acceptance count differs: {len(accepted)} != {count}")
        require(all((row["adc_sample_ch1"], row["adc_sample_ch2"]) == sample for row in accepted), "Accepted payload differs from scenario")
    if scenario in FAULTS:
        code = FAULTS[scenario][3]
        fault = [row for row in destination if row["fault_latched"]]
        require(len(fault) >= 1000, "Fault latch evidence is too short")
        require(all(row["fault_code_latched"] == code and row["fsm_state"] == 1 for row in fault), "Wrong latched fault identity")
        require(any(row["fault_valid"] and row["fault_code"] == code for row in destination), "Fault evaluation was not captured")
        require(any(row["pwm_out"] for row in destination if not row["fault_latched"]), "No pre-fault PWM observed")
    elif scenario == "live_clear_rejected":
        require(all(row["fault_latched"] and row["fault_code_latched"] == 2 and row["fsm_state"] == 1 for row in destination), "Clear request released a live fault")
        require(any(row["fault_valid"] for row in destination), "Live-fault evaluation missing")
    elif scenario == "clear_recovery":
        require(any(row["fsm_state"] == 1 for row in destination) and any(row["fsm_state"] == 2 for row in destination), "First clean sample did not transition FAULT to RESET_WAIT")
        require(all(row["pwm_out"] == 0 for row in destination), "PWM released before second clean transaction")
        require(destination[-1]["fsm_state"] == 2, "Recovery did not remain in RESET_WAIT")
    elif scenario in ("normal_pwm", "recovered_pwm", "source_protocol"):
        start = max((i for i, row in enumerate(destination) if row["fsm_state"] != 0), default=-1) + 1
        stable = destination[start + 2:]
        require(all(not row["fault_latched"] and row["fault_code_latched"] == 0 for row in stable), "PWM recovery retained a fault")
        proof["pwm"] = verify_pwm(stable)
        if scenario == "source_protocol":
            proof["stall"] = analyzer.require_source_stall(source)
    return proof


def analyze_scenario(directory, scenario, execution_id):
    rows = {}
    for role, probes in (("source", runtime.SOURCE_PROBES), ("destination", runtime.READY_AWARE_DESTINATION_PROBES)):
        metadata = analyzer.load_metadata(directory / f"{role}.metadata.tsv")
        mode = MODES[scenario][0 if role == "source" else 1]
        analyzer.validate_capture_metadata(metadata, role=role, mode=mode, probe_count=8)
        require(metadata["execution_id"] == execution_id, "Capture execution identity differs")
        for suffix in ("probes.tsv", "trigger.tsv", "properties.txt"):
            require((directory / f"{role}.{suffix}").stat().st_size > 0, "Missing actual capture configuration")
        rows[role], _ = analyzer.load_capture(directory / f"{role}.csv", probes)
    return analyze_rows(scenario, rows["source"], rows["destination"])


class HostSession:
    def __init__(self, args):
        self.args = args
        self.package = args.package_root.resolve(strict=True)
        self.manifest = verify_session_package(self.package)
        self.execution_id = self.manifest["execution_id"]
        self.output = args.output_root.resolve()
        self.output.mkdir(parents=True, exist_ok=False)
        self.actions = []

    def action(self, name):
        payload = {"execution_id": self.execution_id, "action": name}
        request = urllib.request.Request(f"http://127.0.0.1:{self.args.port}/action", json.dumps(payload).encode(), {"Content-Type": "application/json"})
        started = datetime.now(timezone.utc).isoformat()
        with urllib.request.urlopen(request, timeout=120) as response:
            raw = response.read()
        index = len(self.actions)
        (self.output / f"board_action_{index:02d}.http.json").write_bytes(raw)
        result = json.loads(raw)
        write_json(self.output / f"host_action_{index:02d}.json", {
            "request": payload, "host_start_utc": started,
            "host_end_utc": datetime.now(timezone.utc).isoformat(),
            "response_sha256": identity(self.output / f"board_action_{index:02d}.http.json")["sha256"],
        })
        self.actions.append(result)
        require(result.get("execution_id") == self.execution_id and result.get("index") == index and result.get("action") == name, "Board action receipt identity/order differs")
        require(result["status"] == "PASS", f"Board action failed: {result}")
        return result

    def capture(self, scenario):
        directory = self.output / scenario
        directory.mkdir()
        self.action(f"{scenario}/prepare")
        command = [str(self.args.vivado), "-mode", "batch", "-notrace", "-source",
                   str(self.package / "host/stage2_board_capture_pair.tcl"), "-log", str(directory / "vivado.log"),
                   "-journal", str(directory / "vivado.jou"), "-tclargs",
                   str(self.package / "artifacts/protection_system.bit"), str(self.package / "artifacts/protection_system.ltx"),
                   str(directory), *MODES[scenario], self.execution_id]
        result = None
        with (directory / "run.log").open("xb") as log:
            process = subprocess.Popen(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 120
                while not (directory / "armed.txt").exists():
                    if process.poll() is not None:
                        raise RuntimeError(f"Vivado failed before arming: {scenario}; inspect run.log")
                    if time.monotonic() > deadline:
                        raise RuntimeError("ILA arm timeout")
                    time.sleep(0.1)
                require((directory / "armed.txt").read_text().strip() == self.execution_id, "ILA arm identity differs")
                action_error = None
                try:
                    result = self.action(f"{scenario}/execute")
                except Exception as exc:
                    action_error = exc
                # Export a triggered window even when the board assertion fails.
                (directory / "collect.txt").write_text(self.execution_id + "\n")
                code = process.wait(timeout=120)
                write_json(directory / "tool_exit.json", {"exit_code": code, "execution_id": self.execution_id})
                require(code == 0, f"Vivado capture failed: {scenario}")
                if action_error is not None:
                    raise action_error
            finally:
                if process.poll() is None:
                    if os.name == "nt":
                        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                       stdout=log, stderr=subprocess.STDOUT, check=False, timeout=15)
                    else:
                        process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
        if scenario != "legacy_c2":
            proof = analyze_scenario(directory, scenario, self.execution_id)
        else:
            board = result["result"]
            analyzer.verify_board_result(board)
            write_json(self.output / "legacy_c2_result.json", board)
            proof = analyzer.analyze(self.output / "legacy_c2_result.json", {
                "source_stall": self.output / "source_protocol/source.csv",
                "source_accept": directory / "source.csv", "destination_fault": directory / "destination.csv",
            })
        files = {p.name: identity(p) for p in directory.iterdir() if p.is_file()}
        receipt = {"execution_id": self.execution_id, "scenario": scenario, "status": "PASS",
                   "board_action_index": result["index"], "analysis": proof, "files": files}
        write_json(directory / "scenario_receipt.json", receipt)
        return receipt

    def run(self):
        scenarios = {name: {"status": "NOT_RUN"} for name in SCENARIOS + EXTRA_SCENARIOS}
        failure = None
        try:
            self.action("load")
            for name in SCENARIOS + EXTRA_SCENARIOS:
                print(f"SCENARIO_START={name}", flush=True)
                try:
                    scenarios[name] = self.capture(name)
                except Exception as exc:
                    scenarios[name] = {"status": "FAIL", "reason": str(exc)}
                    raise
                print(f"SCENARIO_PASS={name}", flush=True)
            self.action("finish")
        except Exception as exc:
            failure = str(exc)
            cleanup_confirmed = self.actions and self.actions[-1].get("cleanup", {}).get("status") == "PASS"
            if not cleanup_confirmed:
                try:
                    self.action("abort")
                except Exception as abort_error:
                    write_json(self.output / "abort_failure.json", {"reason": str(abort_error)})
        passed = failure is None and all(record["status"] == "PASS" for record in scenarios.values())
        receipt = {"execution_id": self.execution_id, "status": "PASS" if passed else "BLOCKED",
                   "evidence_state": "BOARD_VERIFIED" if passed else "NOT_FORMALLY_ACCEPTED",
                   "formal_acceptance": "NOT_FORMALLY_ACCEPTED", "final_release": "NOT_RUN",
                   "package_manifest": identity(self.package / "session_manifest.json"),
                   "physical_execution_id": self.manifest["physical_execution_id"],
                   "source_commit": self.manifest["physical_source_commit"], "source_tree": self.manifest["physical_source_tree"],
                   "tooling_commit": self.manifest["tooling_commit"], "scenarios": scenarios, "failure": failure,
                   "scope": "READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS; physical analog ADC removal NOT_RUN",
                   "files": {p.relative_to(self.output).as_posix(): identity(p) for p in sorted(self.output.rglob("*")) if p.is_file()}}
        write_json(self.output / "board_verification_receipt.json", receipt)
        print(json.dumps({"status": receipt["status"], "execution_id": self.execution_id, "failure": failure}), flush=True)
        return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--vivado", type=Path, required=True)
    parser.add_argument("--port", type=int, default=18765)
    args = parser.parse_args()
    raise SystemExit(HostSession(args).run())


if __name__ == "__main__":
    main()
