#!/usr/bin/env python3
"""Ordered board actions served only on loopback through an operator SSH tunnel."""
from __future__ import annotations

import argparse
import json
import os
import platform
import signal
import socket
import sys
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if (ROOT / "sw").is_dir():
    sys.path.insert(0, str(ROOT))
    from sw import stage2i_board_runtime as runtime
    from sw.generated.protection_register_map import CTRL_CLEAR_FAULT, CTRL_PWM_ENABLE, RegisterOffset
    from tools.board_validation import stage1_board_functional_validation as functional
else:
    import stage2i_board_runtime as runtime
    from generated.protection_register_map import CTRL_CLEAR_FAULT, CTRL_PWM_ENABLE, RegisterOffset
    import stage1_board_functional_validation as functional

SCENARIOS = (
    "normal_pwm", "ch1_overcurrent", "ch2_overcurrent", "differential_fault",
    "live_clear_rejected", "sample_source_removal", "clear_recovery", "recovered_pwm",
)
EXTRA_SCENARIOS = ("source_protocol", "legacy_c2")
FAULTS = {
    "ch1_overcurrent": (3001, 2802, int(functional.FaultCause.CH1_OVERCURRENT), int(functional.FaultCode.OVERCURRENT)),
    "ch2_overcurrent": (2802, 3001, int(functional.FaultCause.CH2_OVERCURRENT), int(functional.FaultCode.OVERCURRENT)),
    "differential_fault": (1000, 1300, int(functional.FaultCause.SENSOR_MISMATCH_OR_DIFFERENTIAL), int(functional.FaultCode.SENSOR_MISMATCH)),
}
ACTIONS = ("load",) + tuple(
    f"{name}/{phase}" for name in SCENARIOS + EXTRA_SCENARIOS for phase in ("prepare", "execute")
) + ("finish",)


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    with Path(path).open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")


def identity(path):
    path = Path(path)
    return {"bytes": path.stat().st_size, "sha256": runtime.sha256_file(path)}


def verify_session_package(root):
    manifest = runtime.load_json(root / "session_manifest.json")
    for relative, expected in manifest["files"].items():
        path = (root / relative).resolve(strict=True)
        if not path.is_relative_to(root.resolve()) or path.is_symlink() or identity(path) != expected:
            raise RuntimeError(f"Session package identity mismatch: {relative}")
    runtime.validate_package(root, expected_profile=runtime.READY_AWARE)
    return manifest


class BoardSession:
    def __init__(self, package, output, board_model):
        self.package = package.resolve(strict=True)
        self.manifest = verify_session_package(self.package)
        self.execution_id = self.manifest["execution_id"]
        self.profile = runtime.load_profile(self.package, runtime.READY_AWARE)
        output.mkdir(parents=True, exist_ok=False)
        self.output = output
        self.backend = None
        self.index = 0
        self.failed = False
        self.records = []
        self.board_model = board_model
        self.last_activity = time.monotonic()

    def checked_state(self):
        state = self.backend.read_state()
        functional.require_no_integrity_errors(state, "session")
        return state

    def clear_with_pwm(self):
        self.backend.protection.write(int(RegisterOffset.CTRL), int(CTRL_PWM_ENABLE | CTRL_CLEAR_FAULT))

    def clean(self):
        self.clear_with_pwm()
        result = self.backend.issue(*functional.CLEAN_SAMPLE, 2)
        functional.require_clean_state(result["state_after"], "preparation")
        return result

    def load(self):
        import pynq
        identity_receipt = {
            "execution_id": self.execution_id, "board_model": self.board_model,
            "board_model_basis": "OPERATOR_DECLARATION; JTAG die checked separately",
            "hostname": socket.gethostname(), "kernel": platform.platform(),
            "python_version": platform.python_version(), "python_executable": sys.executable,
            "pynq_version": pynq.__version__, "os_release": platform.freedesktop_os_release(),
            "board_time_utc": utc_now(), "board_time_trusted": False,
            "chronology_authority": "HOST_UTC_AND_ORDERED_ACTION_INDEX",
            "effective_uid": os.geteuid(), "ssh_user": os.environ.get("SUDO_USER", "UNKNOWN"),
            "physical_execution_id": self.profile["execution_id"],
            "source_commit": self.profile["source_commit"], "source_tree": self.profile["source_tree"],
            "artifact_identities": self.profile["artifacts"],
            "package_manifest": identity(self.package / "session_manifest.json"),
        }
        write_json(self.output / "board_identity.json", identity_receipt)
        self.overlay, protection, gpio, pynq_version = runtime.open_overlay_mmio(self.package, self.profile)
        self.backend = functional.RealB2Backend(protection, gpio)
        state = self.checked_state()
        if state["status"]["ctrl"] != 0:
            raise RuntimeError("Overlay startup did not leave CTRL disabled")
        expected = {RegisterOffset.PWM_PERIOD: 1000, RegisterOffset.PWM_DUTY: 500,
                    RegisterOffset.TH_OC1: 3000, RegisterOffset.TH_OC2: 3000, RegisterOffset.TH_DIFF: 200}
        registers = runtime.read_all_registers(protection)
        for register, value in expected.items():
            if registers[register.name] != value:
                raise RuntimeError(f"Unexpected {register.name}: {registers[register.name]}")
        from pynq import Clocks
        clock_mhz = {"fclk0": float(Clocks.fclk0_mhz), "fclk1": float(Clocks.fclk1_mhz)}
        if abs(clock_mhz["fclk0"] - 100) > 0.1 or abs(clock_mhz["fclk1"] - 125) > 0.1:
            raise RuntimeError(f"Unexpected overlay clocks: {clock_mhz}")
        result = {"identity": identity_receipt, "loaded": bool(self.overlay.is_loaded()),
                  "clock_mhz": clock_mhz, "registers": registers, "state": state,
                  "ip_map": self.profile["expected_ip"], "pynq_version": pynq_version}
        write_json(self.output / "overlay_receipt.json", result)
        return result

    def prepare(self, scenario):
        operations = []
        if scenario in ("normal_pwm", "ch1_overcurrent", "ch2_overcurrent", "differential_fault"):
            operations.append(self.clean())
        if scenario == "sample_source_removal":
            self.clear_with_pwm()
            operations.append(self.backend.issue(*functional.CLEAN_SAMPLE, 0))
            time.sleep(0.1)
        if scenario == "legacy_c2":
            self.backend.protection.write(int(RegisterOffset.CTRL), 0)
        return {"operations": operations, "state": self.checked_state()}

    def execute(self, scenario):
        before = self.checked_state()
        transactions = []
        if scenario in ("normal_pwm", "source_protocol"):
            sample = functional.CLEAN_SAMPLE if scenario == "normal_pwm" else (1500, 1501)
            transactions.append(self.backend.issue(*sample, 127))
            functional.require_clean_state(self.checked_state(), scenario)
        elif scenario in FAULTS:
            ch1, ch2, bitmap, code = FAULTS[scenario]
            transactions.append(self.backend.issue(ch1, ch2, 1))
            functional.require_fault_state(self.checked_state(), bitmap, code, scenario)
        elif scenario == "live_clear_rejected":
            self.clear_with_pwm()
            pending = self.checked_state()
            if not pending["policy_status"]["clear_pending"]:
                raise RuntimeError("Clear request was not observed before the live-fault sample")
            transactions.append({"clear_request_state": pending})
            transactions.append(self.backend.issue(1000, 1300, 1))
            functional.require_fault_state(self.checked_state(), 4, 2, scenario)
            if self.checked_state()["policy_status"]["clear_pending"]:
                raise RuntimeError("Live-fault sample did not resolve the clear request")
        elif scenario == "sample_source_removal":
            time.sleep(0.1)
            after = self.checked_state()
            producer = runtime.read_b2_status(self.backend.gpio)
            if producer["active"] or producer["remaining"] or producer["request_pending"]:
                raise RuntimeError("Sample producer did not remain idle")
            for field in ("source_accept_count", "destination_delivery_count"):
                if before["observability"][field] != after["observability"][field]:
                    raise RuntimeError("A transaction appeared while sample source was removed")
            functional.require_fault_state(after, 4, 2, scenario)
            if not after["policy_status"]["clear_pending"]:
                raise RuntimeError("No-sample interval incorrectly resolved pending clear")
            transactions.append({"producer": producer, "no_sample_interval_seconds": 0.1})
        elif scenario == "clear_recovery":
            transactions.append(self.backend.issue(*functional.CLEAN_SAMPLE, 1))
            policy = self.checked_state()["policy_status"]
            if not policy["reset_wait_state"] or not policy["post_clear_recovery_pending"] or policy["armed_ready"]:
                raise RuntimeError(f"First clean transaction did not enter RESET_WAIT: {policy}")
        elif scenario == "recovered_pwm":
            transactions.append(self.backend.issue(*functional.CLEAN_SAMPLE, 1))
            functional.require_clean_state(self.checked_state(), scenario)
        elif scenario == "legacy_c2":
            try:
                result = functional.run_c2_sequence(self.backend)
            finally:
                cleanup = self.backend.cleanup()
            result.update({"schema_version": functional.SCHEMA_VERSION, "status": "PASS",
                           "implementation_profile": runtime.READY_AWARE,
                           "board_hardware_execution": "C2_FULL_DIGITAL_PATH_PASS", "cleanup": cleanup,
                           "execution_id": self.execution_id, "source_commit": self.profile["source_commit"],
                           "source_tree": self.profile["source_tree"]})
            write_json(self.output / "legacy_c2_result.json", result)
            return result
        else:
            raise RuntimeError(f"Unknown scenario: {scenario}")
        after = self.checked_state()
        if int(after["status"]["ctrl"]) != int(CTRL_PWM_ENABLE):
            raise RuntimeError("PWM enable was lost during scenario execution")
        return {"state_before": before, "transactions": transactions, "state_after": after}

    def action(self, name):
        if name != "abort" and (self.failed or self.index >= len(ACTIONS) or name != ACTIONS[self.index]):
            raise RuntimeError("Action is out of order, already executed, or session failed")
        record = {"execution_id": self.execution_id, "index": self.index, "action": name,
                  "board_time_utc": utc_now(), "monotonic_start": time.monotonic()}
        try:
            if name == "abort":
                self.failed = True
                result = self.backend.cleanup() if self.backend is not None else {"status": "PASS", "overlay_loaded": False}
            elif name == "load":
                result = self.load()
            elif name == "finish":
                result = self.backend.cleanup()
            else:
                scenario, phase = name.split("/")
                result = getattr(self, phase)(scenario)
            record.update(status="PASS", result=result)
        except Exception as exc:
            self.failed = True
            record.update(status="FAIL", error_type=type(exc).__name__, reason=str(exc))
            if self.backend is not None:
                try:
                    record["cleanup"] = self.backend.cleanup()
                except Exception as cleanup_error:
                    record["cleanup_error"] = str(cleanup_error)
        record["monotonic_end"] = time.monotonic()
        self.last_activity = time.monotonic()
        write_json(self.output / f"action_{self.index:02d}.json", record)
        self.records.append(record)
        self.index += 1
        print(f"ACTION {record['index']} {name} {record['status']}", flush=True)
        return record


def serve(args):
    session = BoardSession(args.package_root, args.output_root, args.board_model)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def respond(self, value, code=200):
            content = json.dumps(value, allow_nan=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        def do_GET(self):
            if self.path != "/status":
                return self.respond({"error": "unknown route"}, 404)
            self.respond({"execution_id": session.execution_id, "index": session.index,
                          "failed": session.failed, "records": session.records})

        def do_POST(self):
            try:
                self.connection.settimeout(5)
                length = int(self.headers.get("Content-Length", "0"))
                if self.path != "/action" or not 1 <= length <= 512:
                    raise ValueError("Invalid request")
                request = json.loads(self.rfile.read(length))
                if set(request) != {"execution_id", "action"} or request["execution_id"] != session.execution_id:
                    raise ValueError("Execution identity differs")
                self.respond(session.action(request["action"]))
            except Exception as exc:
                self.respond({"status": "FAIL", "reason": str(exc)}, 400)

    server = HTTPServer(("127.0.0.1", args.port), Handler)
    server.timeout = 1
    print(f"BOARD_SESSION_READY execution_id={session.execution_id} port={args.port}", flush=True)
    try:
        while time.monotonic() - session.last_activity < 1800:
            server.handle_request()
            if session.index == len(ACTIONS) or session.failed:
                break
    finally:
        server.server_close()
        if session.backend is not None:
            cleanup = session.backend.cleanup()
            write_json(session.output / "session_cleanup.json", cleanup)
    return 1 if session.failed or session.index != len(ACTIONS) else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--board-model", choices=("PYNQ-Z2",), required=True)
    parser.add_argument("--port", type=int, default=18765)
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    raise SystemExit(serve(args))


if __name__ == "__main__":
    main()
