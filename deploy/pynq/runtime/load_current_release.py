#!/usr/bin/env python3
"""Load and verify the selected Stage 1G release exactly once per boot."""

from __future__ import annotations

import argparse
import errno
import hashlib
import json
import os
import platform
import re
import selectors
import signal
import subprocess
import sys
import time
import traceback
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, BinaryIO, Callable, Iterator

from verify_installed_release import (
    CURRENT_LINK,
    DEPLOYMENT_ROOT,
    EXPECTED_DEVICE,
    EXPECTED_GPIO,
    EXPECTED_IP,
    EXPECTED_REGISTERS,
    EXPECTED_RUNTIME,
    RELEASES_ROOT,
    ReleaseVerificationError,
    atomic_write_json,
    canonical_json_bytes,
    fsync_directory,
    verify_release,
)


BOOT_ID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
EVIDENCE_REVIEW_ID = (
    "S1G-AUTOLOAD-PHASE-IPC-RECONCILIATION-IMPLEMENTATION-REVIEW-"
    "20260727T161148062Z"
)
EVIDENCE_PACKAGE_ID = (
    "NO-EXECUTABLE-PACKAGE-IMPLEMENTATION-REVIEW-20260727T161148062Z"
)
PHASE_SCHEMA_VERSION = "stage1g-phase-evidence-v2"
TERMINAL_SCHEMA_VERSION = "stage1g-terminal-result-v3"
ATTEMPT_SCHEMA_VERSION = "stage1g-boot-attempt-marker-v2"
PROTOCOL_VERSION = 1
IPC_PREFIX = "S1G_WORKER_PROTOCOL\t"
IPC_PREFIX_BYTES = IPC_PREFIX.encode("ascii")
MAX_PROTOCOL_FRAME_BYTES = 65_536
PROTOCOL_READ_BYTES = 16_384
SYSTEMD_TIMEOUT_START_SECONDS = 90.0
SUPERVISOR_POLL_SECONDS = 0.01
SUPERVISOR_TERM_WAIT_SECONDS = 0.5
SUPERVISOR_CLEANUP_SECONDS = 1.0
SIGKILL_NUMBER = int(getattr(signal, "SIGKILL", 9))
TERMINAL_RESULTS = frozenset(
    {
        "SUCCESS",
        "PYTHON_EXCEPTION",
        "SIGTERM",
        "SIGINT",
        "INTERNAL_VALIDATION_FAILURE",
        "PHASE_INCOMPLETE",
    }
)
PHASES = (
    "supervisor_entry",
    "attempt_commit",
    "python_entry",
    "release_verification",
    "imports",
    "pynq_import",
    "pynq_symbol_imports",
    "device_enumeration",
    "active_device_selection",
    "overlay_constructor",
    "overlay_programming",
    "fpga_manager_validation",
    "overlay_metadata",
    "ip_discovery",
    "clock_validation",
    "mmio_snapshot_1",
    "mmio_snapshot_2",
    "gpio_snapshot",
    "normal_exit",
)
IMPORT_SUBPHASES = (
    "pynq_import",
    "pynq_symbol_imports",
    "device_enumeration",
    "active_device_selection",
)
PHASE_EVENTS = frozenset({"ENTER", "EXIT", "FAIL"})
EXPECTED_DEVICE_TYPE = "pynq.pl_server.embedded_device.EmbeddedDevice"
STABILIZATION_SECONDS = 0.25
CLOCK_SAMPLE_INTERVAL_SECONDS = 0.05
REGISTER_DEFS = (
    ("CTRL", 0x00),
    ("STATUS", 0x04),
    ("FAULT_CODE", 0x08),
    ("I_CH1", 0x0C),
    ("I_CH2", 0x10),
    ("TH_OC1", 0x14),
    ("TH_OC2", 0x18),
    ("TH_DIFF", 0x1C),
    ("PWM_PERIOD", 0x20),
    ("PWM_DUTY", 0x24),
)


@dataclass(frozen=True)
class LoaderPaths:
    deployment_root: Path = DEPLOYMENT_ROOT
    releases_root: Path = RELEASES_ROOT
    current_link: Path = CURRENT_LINK
    run_root: Path = Path("/run/current-sensing-protection-ip")
    boot_log_root: Path = Path("/var/log/current-sensing-protection-ip/boot")
    boot_id_path: Path = Path("/proc/sys/kernel/random/boot_id")
    uptime_path: Path = Path("/proc/uptime")
    fpga_manager_state_path: Path = Path("/sys/class/fpga_manager/fpga0/state")
    fpga_manager_flags_path: Path = Path("/sys/class/fpga_manager/fpga0/flags")
    clock_synchronized_path: Path = Path("/run/systemd/timesync/synchronized")

    def attempt_marker(self, boot_id: str) -> Path:
        return self.run_root / f"attempt-{boot_id}.json"

    def readiness_marker(self, boot_id: str) -> Path:
        return self.run_root / f"ready-{boot_id}.json"

    def terminal_result(self, boot_id: str) -> Path:
        return self.boot_log_root / f"{boot_id}.json"

    def phase_root(self, boot_id: str, attempt_id: str) -> Path:
        return self.boot_log_root / "phase_evidence" / boot_id / attempt_id


class BootLoadError(RuntimeError):
    def __init__(self, message: str, classification: str):
        super().__init__(message)
        self.classification = classification


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def read_optional_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return None


def read_boot_id(path: Path) -> str:
    value = read_optional_text(path)
    if value is None or not BOOT_ID_RE.fullmatch(value):
        raise BootLoadError(f"invalid or missing boot ID: {value!r}", "BOOT_ID_INVALID")
    return value


def require_root() -> None:
    if not hasattr(os, "geteuid") or os.getuid() != 0 or os.geteuid() != 0:
        raise BootLoadError("loader requires root uid/euid 0/0", "ROOT_REQUIRED")


def clock_synchronization_status(path: Path) -> str:
    """Return an advisory status without invoking timedatectl or using UTC."""

    try:
        return "SYNCHRONIZED" if path.is_file() else "UNKNOWN"
    except OSError:
        return "UNKNOWN"


def atomic_create_bytes(path: Path, payload: bytes, mode: int = 0o600) -> None:
    """Atomically publish complete bytes only when *path* does not yet exist."""

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / f".{path.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp"
    descriptor = os.open(
        str(temporary), os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode
    )
    published = False
    try:
        offset = 0
        while offset < len(payload):
            offset += os.write(descriptor, payload[offset:])
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    try:
        os.link(temporary, path)
        published = True
        fsync_directory(path.parent)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        if published:
            fsync_directory(path.parent)


def write_json_exclusive(
    path: Path, payload: dict[str, Any], mode: int = 0o600
) -> None:
    atomic_create_bytes(path, canonical_json_bytes(payload), mode)


def load_json_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise BootLoadError(
            f"JSON evidence root is not an object: {path}",
            "EVIDENCE_PARSE_FAILED",
        )
    return value


@dataclass(frozen=True)
class EvidenceIdentity:
    review_id: str
    package_id: str
    boot_id: str
    attempt_id: str


class PhaseTracker:
    def __init__(self) -> None:
        self.last_entered_phase: str | None = None
        self.last_completed_phase: str | None = None
        self.last_failed_phase: str | None = None
        self.current_phase: str | None = None
        self.current_enter_monotonic_ns: int | None = None
        self.completed_phases: list[str] = []
        self._last_entered_index = -1
        self._suspended_import_enter_monotonic_ns: int | None = None

    def adopt_entered(self, phase: str, monotonic_ns: int) -> None:
        self._last_entered_index = PHASES.index(phase)
        self.last_entered_phase = phase
        self.current_phase = phase
        self.current_enter_monotonic_ns = monotonic_ns

    def observe(self, event: dict[str, Any]) -> None:
        phase = str(event["phase"])
        transition = str(event["event"])
        monotonic_ns = int(event["monotonic_ns"])
        if transition == "ENTER":
            if self.current_phase is not None:
                if self.current_phase == "imports" and phase in IMPORT_SUBPHASES:
                    self._suspended_import_enter_monotonic_ns = (
                        self.current_enter_monotonic_ns
                    )
                else:
                    raise BootLoadError(
                        f"phase {phase} entered while {self.current_phase} is active",
                        "PHASE_SEQUENCE_INVALID",
                    )
            phase_index = PHASES.index(phase)
            if phase_index <= self._last_entered_index:
                raise BootLoadError(
                    f"phase {phase} is out of order or repeated",
                    "PHASE_SEQUENCE_INVALID",
                )
            self._last_entered_index = phase_index
            self.last_entered_phase = phase
            self.current_phase = phase
            self.current_enter_monotonic_ns = monotonic_ns
        elif transition in {"EXIT", "FAIL"}:
            if self.current_phase != phase:
                raise BootLoadError(
                    f"phase {phase} {transition} does not close {self.current_phase}",
                    "PHASE_SEQUENCE_INVALID",
                )
            if transition == "EXIT":
                self.last_completed_phase = phase
                self.completed_phases.append(phase)
                completed = set(self.completed_phases)
                self.completed_phases = [
                    candidate for candidate in PHASES if candidate in completed
                ]
            else:
                self.last_failed_phase = phase
            if (
                phase in IMPORT_SUBPHASES
                and self._suspended_import_enter_monotonic_ns is not None
            ):
                self.current_phase = "imports"
                self.current_enter_monotonic_ns = (
                    self._suspended_import_enter_monotonic_ns
                )
                self._suspended_import_enter_monotonic_ns = None
            else:
                self.current_phase = None
                self.current_enter_monotonic_ns = None

    def snapshot(self, monotonic_ns: int | None = None) -> dict[str, Any]:
        now_ns = time.monotonic_ns() if monotonic_ns is None else monotonic_ns
        duration_ns = None
        if self.current_enter_monotonic_ns is not None:
            duration_ns = max(0, now_ns - self.current_enter_monotonic_ns)
        return {
            "last_entered_phase": self.last_entered_phase,
            "last_completed_phase": self.last_completed_phase,
            "last_failed_phase": self.last_failed_phase,
            "current_phase": self.current_phase,
            "current_phase_enter_monotonic_ns": self.current_enter_monotonic_ns,
            "current_phase_duration_ns": duration_ns,
            "completed_phases": list(self.completed_phases),
        }


class PhaseEmitter:
    def __init__(self, identity: EvidenceIdentity, clock_status: str):
        self.identity = identity
        self.clock_status = clock_status
        self.tracker = PhaseTracker()

    def emit(
        self,
        phase: str,
        event: str,
        *,
        exception_type: str | None = None,
        exception_message: str | None = None,
        signal_name: str | None = None,
        pid: int | None = None,
        monotonic_ns: int | None = None,
        utc_advisory: str | None = None,
        clock_status: str | None = None,
        event_source: str = "SUPERVISOR",
        worker_protocol_sequence: int | None = None,
    ) -> dict[str, Any]:
        raise NotImplementedError

    def _event_payload(
        self,
        phase: str,
        event: str,
        *,
        exception_type: str | None,
        exception_message: str | None,
        signal_name: str | None,
        pid: int | None,
        monotonic_ns: int | None,
        utc_advisory: str | None,
        clock_status: str | None,
    ) -> dict[str, Any]:
        if phase not in PHASES or event not in PHASE_EVENTS:
            raise BootLoadError(
                f"invalid phase transition: {phase}/{event}",
                "PHASE_EVENT_INVALID",
            )
        return {
            "schema_version": PHASE_SCHEMA_VERSION,
            "review_id": self.identity.review_id,
            "package_id": self.identity.package_id,
            "boot_id": self.identity.boot_id,
            "attempt_id": self.identity.attempt_id,
            "phase": phase,
            "event": event,
            "pid": os.getpid() if pid is None else int(pid),
            "monotonic_ns": (
                time.monotonic_ns() if monotonic_ns is None else int(monotonic_ns)
            ),
            "utc_advisory": utc_now() if utc_advisory is None else utc_advisory,
            "clock_synchronized_or_unknown": clock_status or self.clock_status,
            "exception_type": exception_type,
            "exception_message": exception_message,
            "signal": signal_name,
        }


class PhaseLedger(PhaseEmitter):
    """Single-writer immutable event ledger with strict contiguous sequence."""

    def __init__(
        self,
        root: Path,
        identity: EvidenceIdentity,
        clock_status: str,
    ):
        super().__init__(identity, clock_status)
        self.root = root
        self.events_root = root / "events"
        self.events_root.mkdir(parents=True, exist_ok=True)
        if any(self.events_root.iterdir()):
            raise BootLoadError(
                f"phase ledger is not empty: {self.events_root}",
                "PHASE_LEDGER_NOT_EMPTY",
            )
        self.sequence = 0

    def emit(
        self,
        phase: str,
        event: str,
        *,
        exception_type: str | None = None,
        exception_message: str | None = None,
        signal_name: str | None = None,
        pid: int | None = None,
        monotonic_ns: int | None = None,
        utc_advisory: str | None = None,
        clock_status: str | None = None,
        event_source: str = "SUPERVISOR",
        worker_protocol_sequence: int | None = None,
    ) -> dict[str, Any]:
        payload = self._event_payload(
            phase,
            event,
            exception_type=exception_type,
            exception_message=exception_message,
            signal_name=signal_name,
            pid=pid,
            monotonic_ns=monotonic_ns,
            utc_advisory=utc_advisory,
            clock_status=clock_status,
        )
        next_sequence = self.sequence + 1
        payload["sequence"] = next_sequence
        payload["event_source"] = event_source
        payload["worker_protocol_sequence"] = worker_protocol_sequence
        self.tracker.observe(payload)
        write_json_exclusive(
            self.events_root / f"{next_sequence:06d}.json", payload
        )
        self.sequence = next_sequence
        return payload

    def event_records(self) -> list[dict[str, Any]]:
        return [
            load_json_object(path)
            for path in sorted(self.events_root.glob("*.json"))
        ]


class PhaseStreamEmitter(PhaseEmitter):
    """Worker-side binary protocol; the supervisor owns all durable evidence."""

    def __init__(
        self,
        stream: BinaryIO,
        identity: EvidenceIdentity,
        clock_status: str,
    ):
        super().__init__(identity, clock_status)
        self.stream = stream
        self.protocol_sequence = 0

    def _write_frame(
        self,
        frame_type: str,
        *,
        monotonic_ns: int,
        utc_advisory: str,
        clock_status: str,
        fields: dict[str, Any],
    ) -> dict[str, Any]:
        self.protocol_sequence += 1
        frame = {
            "type": frame_type,
            "protocol_version": PROTOCOL_VERSION,
            "protocol_sequence": self.protocol_sequence,
            "review_id": self.identity.review_id,
            "package_id": self.identity.package_id,
            "boot_id": self.identity.boot_id,
            "attempt_id": self.identity.attempt_id,
            "worker_pid": os.getpid(),
            "monotonic_ns": int(monotonic_ns),
            "utc_advisory": utc_advisory,
            "clock_sync_state": clock_status,
            **fields,
        }
        encoded = IPC_PREFIX_BYTES + canonical_json_bytes(frame) + b"\n"
        if len(encoded) > MAX_PROTOCOL_FRAME_BYTES:
            raise BootLoadError(
                f"worker protocol frame exceeds {MAX_PROTOCOL_FRAME_BYTES} bytes",
                "PHASE_PROTOCOL_FRAME_OVERSIZED",
            )
        view = memoryview(encoded)
        offset = 0
        while offset < len(view):
            written = self.stream.write(view[offset:])
            if written is None:
                written = len(view) - offset
            if written <= 0:
                raise BootLoadError(
                    "worker protocol stream made no write progress",
                    "PHASE_PROTOCOL_WRITE_FAILED",
                )
            offset += int(written)
        self.stream.flush()
        return frame

    def emit(
        self,
        phase: str,
        event: str,
        *,
        exception_type: str | None = None,
        exception_message: str | None = None,
        signal_name: str | None = None,
        pid: int | None = None,
        monotonic_ns: int | None = None,
        utc_advisory: str | None = None,
        clock_status: str | None = None,
        event_source: str = "WORKER",
        worker_protocol_sequence: int | None = None,
    ) -> dict[str, Any]:
        payload = self._event_payload(
            phase,
            event,
            exception_type=exception_type,
            exception_message=exception_message,
            signal_name=signal_name,
            pid=pid,
            monotonic_ns=monotonic_ns,
            utc_advisory=utc_advisory,
            clock_status=clock_status,
        )
        self.tracker.observe(payload)
        self._write_frame(
            "PHASE",
            monotonic_ns=int(payload["monotonic_ns"]),
            utc_advisory=str(payload["utc_advisory"]),
            clock_status=str(payload["clock_synchronized_or_unknown"]),
            fields={
                "phase": payload["phase"],
                "event": payload["event"],
                "exception_type": payload["exception_type"],
                "exception_message": payload["exception_message"],
                "signal": payload["signal"],
            },
        )
        return payload

    def emit_terminal_candidate(self, candidate: dict[str, Any]) -> dict[str, Any]:
        monotonic_ns = time.monotonic_ns()
        return self._write_frame(
            "TERMINAL_CANDIDATE",
            monotonic_ns=monotonic_ns,
            utc_advisory=utc_now(),
            clock_status=self.clock_status,
            fields={"candidate": candidate},
        )


@contextmanager
def phase_transition(emitter: PhaseEmitter, phase: str) -> Iterator[None]:
    emitter.emit(phase, "ENTER")
    try:
        yield
    except BaseException as exc:
        emitter.emit(
            phase,
            "FAIL",
            exception_type=type(exc).__name__,
            exception_message=str(exc)[:2048],
        )
        raise
    else:
        emitter.emit(phase, "EXIT")


@contextmanager
def optional_phase(
    emitter: PhaseEmitter | None, phase: str
) -> Iterator[None]:
    if emitter is None:
        yield
    else:
        with phase_transition(emitter, phase):
            yield


@dataclass(frozen=True)
class TerminalCommit:
    won: bool
    payload: dict[str, Any]


class TerminalArbiter:
    """Create-new terminal result arbitration: the first legal commit wins."""

    def __init__(self, path: Path, identity: EvidenceIdentity):
        self.path = path
        self.identity = identity

    def read(self) -> dict[str, Any] | None:
        try:
            value = load_json_object(self.path)
        except FileNotFoundError:
            return None
        for field, expected in (
            ("schema_version", TERMINAL_SCHEMA_VERSION),
            ("review_id", self.identity.review_id),
            ("package_id", self.identity.package_id),
            ("boot_id", self.identity.boot_id),
        ):
            if value.get(field) != expected:
                raise BootLoadError(
                    f"terminal result {field} mismatch: {value.get(field)!r}",
                    "TERMINAL_RESULT_INVALID",
                )
        if value.get("terminal_result") not in TERMINAL_RESULTS:
            raise BootLoadError(
                f"terminal result class is invalid: {value.get('terminal_result')!r}",
                "TERMINAL_RESULT_INVALID",
            )
        return value

    def commit(self, payload: dict[str, Any]) -> TerminalCommit:
        terminal_result = payload.get("terminal_result")
        if terminal_result not in TERMINAL_RESULTS:
            raise BootLoadError(
                f"invalid terminal result: {terminal_result!r}",
                "TERMINAL_RESULT_INVALID",
            )
        candidate = {
            **payload,
            "schema_version": TERMINAL_SCHEMA_VERSION,
            "review_id": self.identity.review_id,
            "package_id": self.identity.package_id,
            "boot_id": self.identity.boot_id,
            "attempt_id": self.identity.attempt_id,
            "persistent_result_path": str(self.path),
        }
        try:
            write_json_exclusive(self.path, candidate)
            return TerminalCommit(True, candidate)
        except FileExistsError:
            existing = self.read()
            if existing is None:
                raise BootLoadError(
                    "terminal result disappeared during arbitration",
                    "TERMINAL_RESULT_ARBITRATION_FAILED",
                )
            return TerminalCommit(False, existing)


def create_attempt_marker(
    paths: LoaderPaths,
    boot_id: str,
    attempt_id: str,
    attempt_utc: str,
    attempt_monotonic: float,
    attempt_monotonic_ns: int,
) -> Path:
    marker = paths.attempt_marker(boot_id)
    try:
        write_json_exclusive(
            marker,
            {
                "schema_version": ATTEMPT_SCHEMA_VERSION,
                "review_id": EVIDENCE_REVIEW_ID,
                "package_id": EVIDENCE_PACKAGE_ID,
                "boot_id": boot_id,
                "attempt_id": attempt_id,
                "attempt_utc": attempt_utc,
                "attempt_monotonic_seconds": attempt_monotonic,
                "attempt_monotonic_ns": attempt_monotonic_ns,
                "terminal_state": "ATTEMPT_MARKER_CREATED_NO_RETRY_PERMITTED",
            },
        )
    except FileExistsError as exc:
        raise BootLoadError(
            f"an attempt marker already exists for boot {boot_id}",
            "DUPLICATE_BOOT_ATTEMPT_REJECTED",
        ) from exc
    return marker


class PynqRuntime:
    """Thin production adapter around the accepted PYNQ 3.1.1 APIs."""

    def __init__(self, paths: LoaderPaths):
        self.paths = paths
        self._MMIO: Any = None
        self._PL: Any = None
        self._Clocks: Any = None

    def verify_environment_and_device(
        self, emitter: PhaseEmitter | None = None
    ) -> dict[str, Any]:
        runtime = {
            "uid": os.getuid(),
            "euid": os.geteuid(),
            "xilinx_xrt": os.environ.get("XILINX_XRT"),
            "python_executable": sys.executable,
            "python_version": platform.python_version(),
        }
        if runtime["uid"] != 0 or runtime["euid"] != 0:
            raise BootLoadError("root uid/euid 0/0 required", "ROOT_REQUIRED")
        for key in ("xilinx_xrt", "python_executable", "python_version"):
            if runtime[key] != EXPECTED_RUNTIME[key]:
                raise BootLoadError(
                    f"runtime {key} mismatch: {runtime[key]!r}",
                    "PYNQ_RUNTIME_ENVIRONMENT_MISMATCH",
                )
        try:
            with optional_phase(emitter, "pynq_import"):
                import pynq  # type: ignore
            with optional_phase(emitter, "pynq_symbol_imports"):
                from pynq import Clocks, MMIO, PL  # type: ignore
                from pynq.pl_server.device import Device, DeviceMeta  # type: ignore
                from pynq.pl_server.embedded_device import EmbeddedDevice  # type: ignore
                from pynq.pl_server.xrt_device import XrtDevice  # type: ignore
        except Exception as exc:
            raise BootLoadError(
                f"PYNQ import failed: {exc}", "PYNQ_RUNTIME_ENVIRONMENT_MISMATCH"
            ) from exc
        runtime["pynq_version"] = getattr(pynq, "__version__", None)
        if runtime["pynq_version"] != EXPECTED_RUNTIME["pynq_version"]:
            raise BootLoadError(
                f"PYNQ version mismatch: {runtime['pynq_version']!r}",
                "PYNQ_RUNTIME_ENVIRONMENT_MISMATCH",
            )

        with optional_phase(emitter, "device_enumeration"):
            devices = list(Device.devices)
        with optional_phase(emitter, "active_device_selection"):
            active = Device.active_device
        inventory = [
            {
                "type": f"{type(device).__module__}.{type(device).__qualname__}",
                "name": getattr(device, "name", None),
                "tag": getattr(device, "tag", None),
                "active_same_object": device is active,
            }
            for device in devices
        ]
        checks = {
            "device_count_one": len(devices) == 1,
            "device_type_exact": len(devices) == 1
            and inventory[0]["type"] == EXPECTED_DEVICE_TYPE,
            "device_name_exact": len(devices) == 1
            and inventory[0]["name"] == EXPECTED_DEVICE["board_name"],
            "device_tag_exact": len(devices) == 1
            and inventory[0]["tag"] == EXPECTED_DEVICE["device_tag"],
            "active_device_same_object": len(devices) == 1 and devices[0] is active,
            "embedded_priority_50": DeviceMeta._subclasses.get(50) is EmbeddedDevice,
            "xrt_priority_200": DeviceMeta._subclasses.get(200) is XrtDevice,
        }
        if not all(checks.values()):
            raise BootLoadError(
                f"PYNQ device gate failed: {checks}", "PYNQ_DEVICE_MISMATCH"
            )
        self._MMIO = MMIO
        self._PL = PL
        self._Clocks = Clocks
        return {**runtime, "device_inventory": inventory, "device_checks": checks}

    def construct_overlay(self, bit_path: Path) -> Any:
        from pynq import Overlay  # type: ignore

        return Overlay(str(bit_path), download=False)

    @staticmethod
    def program_overlay(overlay: Any) -> None:
        overlay.download()

    def fpga_manager(self) -> dict[str, str]:
        try:
            state = self.paths.fpga_manager_state_path.read_text(encoding="utf-8").strip()
            flags = self.paths.fpga_manager_flags_path.read_text(encoding="utf-8").strip()
        except OSError as exc:
            raise BootLoadError(
                f"FPGA manager status unavailable: {exc}", "FPGA_MANAGER_STATE_MISMATCH"
            ) from exc
        if state != "operating" or flags != "0":
            raise BootLoadError(
                f"FPGA manager state/flags mismatch: {state}/{flags}",
                "FPGA_MANAGER_STATE_MISMATCH",
            )
        return {"state": state, "flags": flags}

    def active_bit_path(self) -> str:
        return str(self._PL.bitfile_name)

    @staticmethod
    def overlay_is_loaded(overlay: Any) -> dict[str, Any]:
        checker = getattr(overlay, "is_loaded", None)
        if checker is None:
            return {"supported": False, "loaded": None}
        loaded = bool(checker())
        if not loaded:
            raise BootLoadError(
                "Overlay.is_loaded() returned false", "OVERLAY_NOT_LOADED"
            )
        return {"supported": True, "loaded": True}

    @staticmethod
    def ip_dict(overlay: Any) -> dict[str, Any]:
        value = getattr(overlay, "ip_dict", None)
        if not isinstance(value, dict):
            raise BootLoadError("Overlay ip_dict is unavailable", "IP_DICTIONARY_MISMATCH")
        return value

    def make_mmio(self, base: int, address_range: int) -> Any:
        return self._MMIO(base, address_range)

    def read_fclk0_mhz(self) -> float:
        return float(self._Clocks.fclk0_mhz)


def verify_ip_dictionary(ip_dict: dict[str, Any]) -> dict[str, Any]:
    observed: dict[str, Any] = {}
    for instance, expected in EXPECTED_IP.items():
        entry = ip_dict.get(instance)
        if not isinstance(entry, dict):
            raise BootLoadError(
                f"required IP is missing: {instance}", "IP_DICTIONARY_MISMATCH"
            )
        try:
            actual = {
                "phys_addr": int(entry["phys_addr"]),
                "addr_range": int(entry["addr_range"]),
            }
        except (KeyError, TypeError, ValueError) as exc:
            raise BootLoadError(
                f"invalid IP metadata for {instance}: {entry}",
                "IP_DICTIONARY_MISMATCH",
            ) from exc
        if actual != expected:
            raise BootLoadError(
                f"IP address mismatch for {instance}: {actual}",
                "IP_DICTIONARY_MISMATCH",
            )
        observed[instance] = actual
    return observed


def read_snapshot(mmio: Any, counts: dict[str, int]) -> dict[str, int]:
    snapshot: dict[str, int] = {}
    for name, offset in REGISTER_DEFS:
        snapshot[name] = int(mmio.read(offset, 4))
        counts["mmio_reads"] += 1
    return snapshot


def verify_safe_state(
    runtime: Any,
    counts: dict[str, int],
    emitter: PhaseEmitter | None = None,
) -> dict[str, Any]:
    with optional_phase(emitter, "mmio_snapshot_1"):
        protection = runtime.make_mmio(
            EXPECTED_IP["protection_ip_axi_lite_0"]["phys_addr"],
            EXPECTED_IP["protection_ip_axi_lite_0"]["addr_range"],
        )
        first_snapshot = read_snapshot(protection, counts)

    with optional_phase(emitter, "mmio_snapshot_2"):
        second_snapshot = read_snapshot(protection, counts)
        snapshots = [first_snapshot, second_snapshot]
        if first_snapshot != second_snapshot:
            raise BootLoadError(
                f"protection snapshots are incoherent: {snapshots}",
                "PROTECTION_SNAPSHOT_INCOHERENT",
            )
        if first_snapshot != EXPECTED_REGISTERS:
            raise BootLoadError(
                f"protection safe-state mismatch: {first_snapshot}",
                "PROTECTION_SAFE_STATE_MISMATCH",
            )

    with optional_phase(emitter, "gpio_snapshot"):
        gpio = runtime.make_mmio(
            EXPECTED_IP["axi_gpio_stage1d_0"]["phys_addr"],
            EXPECTED_IP["axi_gpio_stage1d_0"]["addr_range"],
        )
        gpio_data = int(gpio.read(0x00, 4))
        counts["mmio_reads"] += 1
        counts["gpio_reads"] += 1
        gpio_tri = int(gpio.read(0x04, 4))
        counts["mmio_reads"] += 1
        counts["gpio_reads"] += 1
        if gpio_data != EXPECTED_GPIO["DATA"]:
            raise BootLoadError(
                f"GPIO DATA mismatch: 0x{gpio_data:08X}", "GPIO_DATA_MISMATCH"
            )
        if gpio_tri != EXPECTED_GPIO["TRI"]:
            raise BootLoadError(
                f"GPIO TRI mismatch: 0x{gpio_tri:08X}", "GPIO_TRI_MISMATCH"
            )
    return {
        "protection_snapshots": snapshots,
        "protection_snapshots_coherent": True,
        "gpio": {"DATA": gpio_data, "TRI": gpio_tri},
    }


def verify_fclk0(
    runtime: Any,
    counts: dict[str, int],
    sleeper: Callable[[float], None],
) -> dict[str, Any]:
    samples: list[float] = []
    for index in range(5):
        samples.append(float(runtime.read_fclk0_mhz()))
        counts["fclk_reads"] += 1
        if index < 4:
            sleeper(CLOCK_SAMPLE_INTERVAL_SECONDS)
    spread = max(samples) - min(samples)
    if not all(99.0 <= sample <= 101.0 for sample in samples) or spread > 0.1:
        raise BootLoadError(
            f"FCLK0 observations outside contract: {samples}, spread={spread}",
            "FCLK0_MISMATCH",
        )
    return {
        "samples_mhz": samples,
        "minimum_mhz": min(samples),
        "maximum_mhz": max(samples),
        "spread_mhz": spread,
    }


def new_attempt_id(boot_id: str, monotonic_ns: int | None = None) -> str:
    timestamp = time.monotonic_ns() if monotonic_ns is None else monotonic_ns
    return f"{boot_id}-{timestamp}-{os.getpid()}"


def build_readiness_payload(
    identity: EvidenceIdentity,
    release_id: str,
    ready_utc: str,
    ready_monotonic: float,
    ready_monotonic_ns: int,
) -> dict[str, Any]:
    return {
        "schema_version": "stage1g-readiness-marker-v2",
        "review_id": identity.review_id,
        "package_id": identity.package_id,
        "boot_id": identity.boot_id,
        "attempt_id": identity.attempt_id,
        "release_id": release_id,
        "ready_utc": ready_utc,
        "ready_monotonic_seconds": ready_monotonic,
        "ready_monotonic_ns": ready_monotonic_ns,
        "boot_to_protection_ready_seconds": ready_monotonic,
        "terminal_state": "PROTECTION_READY",
    }


def ensure_readiness_marker(
    paths: LoaderPaths, terminal: dict[str, Any]
) -> Path:
    if terminal.get("terminal_result") != "SUCCESS":
        raise BootLoadError(
            "readiness is forbidden for a non-success terminal result",
            "READINESS_FOR_FAILURE_FORBIDDEN",
        )
    payload = terminal.get("readiness_payload")
    if not isinstance(payload, dict):
        raise BootLoadError(
            "success terminal result lacks readiness payload",
            "READINESS_PAYLOAD_MISSING",
        )
    path = paths.readiness_marker(str(terminal["boot_id"]))
    try:
        write_json_exclusive(path, payload)
    except FileExistsError:
        if load_json_object(path) != payload:
            raise BootLoadError(
                "pre-existing readiness marker differs from success terminal",
                "READINESS_MARKER_CONFLICT",
            )
    return path


def terminal_result_class(exc: BaseException) -> str:
    if isinstance(exc, (BootLoadError, ReleaseVerificationError)):
        return "INTERNAL_VALIDATION_FAILURE"
    return "PYTHON_EXCEPTION"


def _run_boot_attempt(
    *,
    paths: LoaderPaths = LoaderPaths(),
    runtime: Any | None = None,
    sleeper: Callable[[float], None] = time.sleep,
    enforce_root: bool = True,
    identity: EvidenceIdentity | None = None,
    emitter: PhaseEmitter | None = None,
    terminal_candidate_sink: Callable[[dict[str, Any]], None] | None = None,
    attempt_precommitted: bool = False,
    python_entry_preentered_ns: int | None = None,
) -> tuple[int, dict[str, Any]]:
    if enforce_root:
        require_root()
    observed_boot_id = read_boot_id(paths.boot_id_path)
    if identity is not None and identity.boot_id != observed_boot_id:
        raise BootLoadError(
            f"worker boot ID changed: {observed_boot_id} != {identity.boot_id}",
            "BOOT_ID_CHANGED_DURING_ATTEMPT",
        )
    boot_id = observed_boot_id
    attempt_monotonic_ns = time.monotonic_ns()
    attempt_utc = utc_now()
    if identity is None:
        identity = EvidenceIdentity(
            EVIDENCE_REVIEW_ID,
            EVIDENCE_PACKAGE_ID,
            boot_id,
            new_attempt_id(boot_id, attempt_monotonic_ns),
        )
    clock_status = clock_synchronization_status(paths.clock_synchronized_path)
    paths.run_root.mkdir(parents=True, exist_ok=True)
    paths.boot_log_root.mkdir(parents=True, exist_ok=True)
    if emitter is None:
        emitter = PhaseLedger(
            paths.phase_root(boot_id, identity.attempt_id), identity, clock_status
        )

    attempt_marker_path = paths.attempt_marker(boot_id)
    attempt_error: Exception | None = None
    if attempt_precommitted:
        attempt_record = load_json_object(attempt_marker_path)
        if (
            attempt_record.get("attempt_id") != identity.attempt_id
            or attempt_record.get("boot_id") != boot_id
        ):
            raise BootLoadError(
                "precommitted attempt marker identity mismatch",
                "ATTEMPT_MARKER_IDENTITY_MISMATCH",
            )
        attempt_utc = str(attempt_record["attempt_utc"])
        attempt_monotonic_ns = int(attempt_record["attempt_monotonic_ns"])
    else:
        with phase_transition(emitter, "supervisor_entry"):
            pass
        try:
            with phase_transition(emitter, "attempt_commit"):
                create_attempt_marker(
                    paths,
                    boot_id,
                    identity.attempt_id,
                    attempt_utc,
                    attempt_monotonic_ns / 1_000_000_000,
                    attempt_monotonic_ns,
                )
        except Exception as exc:
            attempt_error = exc

    if python_entry_preentered_ns is None:
        with phase_transition(emitter, "python_entry"):
            pass
    else:
        emitter.tracker.adopt_entered("python_entry", python_entry_preentered_ns)
        emitter.emit("python_entry", "EXIT")

    attempt_monotonic = attempt_monotonic_ns / 1_000_000_000
    result: dict[str, Any] = {
        "schema_version": TERMINAL_SCHEMA_VERSION,
        "review_id": identity.review_id,
        "package_id": identity.package_id,
        "attempt_id": identity.attempt_id,
        "terminal_state": "RUNNING",
        "terminal_result": None,
        "first_failure_classification": None,
        "error": None,
        "signal": None,
        "boot_id": boot_id,
        "release_id": None,
        "attempt_utc": attempt_utc,
        "attempt_monotonic_seconds": attempt_monotonic,
        "attempt_monotonic_ns": attempt_monotonic_ns,
        "attempt_marker": str(attempt_marker_path),
        "phase_evidence_root": str(paths.phase_root(boot_id, identity.attempt_id)),
        "clock_synchronized_or_unknown": clock_status,
        "proc_uptime_at_attempt": read_optional_text(paths.uptime_path),
        "overlay_load_start_monotonic_seconds": None,
        "overlay_load_end_monotonic_seconds": None,
        "ready_monotonic_seconds": None,
        "boot_to_protection_ready_seconds": None,
        "operation_counts": {
            "overlay_load_attempts": 0,
            "overlay_constructor_attempts": 0,
            "overlay_programming_attempts": 0,
            "overlay_constructor_download_true": 0,
            "overlay_download_method_calls": 0,
            "mmio_reads": 0,
            "mmio_writes": 0,
            "gpio_reads": 0,
            "gpio_writes": 0,
            "fclk_reads": 0,
            "automatic_retries": 0,
        },
    }
    try:
        if attempt_error is not None:
            raise attempt_error
        with phase_transition(emitter, "release_verification"):
            try:
                release = verify_release(paths.current_link, paths.releases_root)
            except ReleaseVerificationError as exc:
                raise BootLoadError(str(exc), exc.classification) from exc
        result["release_id"] = release["release_id"]
        result["artifact_identities"] = {
            "artifact_manifest_sha256": release["artifact_manifest_sha256"],
            "release_manifest_sha256": release["manifest_sha256"],
            "bit": release["artifacts"]["bit"],
            "hwh": release["artifacts"]["hwh"],
        }
        bit_path = Path(release["artifacts"]["bit"]["path"])

        runtime = runtime if runtime is not None else PynqRuntime(paths)
        with phase_transition(emitter, "imports"):
            result["runtime"] = runtime.verify_environment_and_device(emitter)
        result["overlay_load_start_utc"] = utc_now()
        result["overlay_load_start_monotonic_seconds"] = time.monotonic()
        result["operation_counts"]["overlay_load_attempts"] = 1
        result["operation_counts"]["overlay_constructor_attempts"] = 1
        try:
            with phase_transition(emitter, "overlay_constructor"):
                overlay = runtime.construct_overlay(bit_path)
        except Exception as exc:
            if isinstance(exc, BootLoadError):
                raise
            raise BootLoadError(
                f"Overlay construction failed: {exc}",
                "OVERLAY_CONSTRUCTION_FAILED",
            ) from exc

        result["operation_counts"]["overlay_programming_attempts"] = 1
        result["operation_counts"]["overlay_download_method_calls"] = 1
        try:
            with phase_transition(emitter, "overlay_programming"):
                runtime.program_overlay(overlay)
        except Exception as exc:
            if isinstance(exc, BootLoadError):
                raise
            raise BootLoadError(
                f"Overlay programming failed: {exc}",
                "OVERLAY_PROGRAMMING_FAILED",
            ) from exc
        result["overlay_load_end_utc"] = utc_now()
        result["overlay_load_end_monotonic_seconds"] = time.monotonic()

        with phase_transition(emitter, "fpga_manager_validation"):
            sleeper(STABILIZATION_SECONDS)
            result["bounded_stabilization_seconds"] = STABILIZATION_SECONDS
            result["fpga_manager"] = runtime.fpga_manager()

        with phase_transition(emitter, "overlay_metadata"):
            active_bit = os.path.realpath(runtime.active_bit_path())
            expected_bit = os.path.realpath(str(bit_path))
            if active_bit != expected_bit:
                raise BootLoadError(
                    f"active BIT path mismatch: {active_bit!r}",
                    "ACTIVE_BIT_PATH_MISMATCH",
                )
            result["active_bit_path"] = active_bit
            result["overlay_loaded"] = runtime.overlay_is_loaded(overlay)

        with phase_transition(emitter, "ip_discovery"):
            result["ip_dict"] = verify_ip_dictionary(runtime.ip_dict(overlay))

        with phase_transition(emitter, "clock_validation"):
            result["fclk0"] = verify_fclk0(
                runtime, result["operation_counts"], sleeper
            )
        result["post_load_verification"] = verify_safe_state(
            runtime, result["operation_counts"], emitter
        )

        ready_monotonic_ns = time.monotonic_ns()
        ready_monotonic = ready_monotonic_ns / 1_000_000_000
        result["ready_utc"] = utc_now()
        result["ready_monotonic_seconds"] = ready_monotonic
        result["ready_monotonic_ns"] = ready_monotonic_ns
        result["proc_uptime_at_ready"] = read_optional_text(paths.uptime_path)
        result["boot_to_protection_ready_seconds"] = ready_monotonic
        result["terminal_state"] = "PROTECTION_READY"
        result["terminal_result"] = "SUCCESS"
        result["status"] = "PASS"
        result["readiness_marker"] = str(paths.readiness_marker(boot_id))
        result["readiness_expected_count"] = 1
        result["readiness_payload"] = build_readiness_payload(
            identity,
            str(result["release_id"]),
            str(result["ready_utc"]),
            ready_monotonic,
            ready_monotonic_ns,
        )
        with phase_transition(emitter, "normal_exit"):
            pass
        result["phase_state_at_worker_candidate"] = emitter.tracker.snapshot(
            ready_monotonic_ns
        )
        result["terminal_utc_advisory"] = utc_now()
        result["terminal_monotonic_ns"] = time.monotonic_ns()
        if terminal_candidate_sink is not None:
            terminal_candidate_sink(result)
        return 0, result
    except Exception as exc:
        if isinstance(exc, BootLoadError):
            classification = exc.classification
        elif isinstance(exc, ReleaseVerificationError):
            classification = exc.classification
        else:
            classification = "UNEXPECTED_LOADER_FAILURE"
        result["status"] = "FAIL"
        result["terminal_state"] = classification
        result["terminal_result"] = terminal_result_class(exc)
        result["first_failure_classification"] = classification
        result["error"] = f"{type(exc).__name__}: {exc}"
        result["traceback"] = traceback.format_exc()
        result["readiness_expected_count"] = 0
        result["phase_state_at_worker_candidate"] = emitter.tracker.snapshot()
        result["terminal_utc_advisory"] = utc_now()
        result["terminal_monotonic_ns"] = time.monotonic_ns()
        if terminal_candidate_sink is not None:
            terminal_candidate_sink(result)
        return 1, result


def run_boot(
    *,
    paths: LoaderPaths = LoaderPaths(),
    runtime: Any | None = None,
    sleeper: Callable[[float], None] = time.sleep,
    enforce_root: bool = True,
) -> tuple[int, dict[str, Any]]:
    """Board-free/direct compatibility path with a local sole publisher.

    Production worker mode calls ``_run_boot_attempt`` and can only emit a
    TERMINAL_CANDIDATE. This wrapper exists for direct unit validation and keeps
    terminal publication outside the worker-attempt function.
    """

    exit_code, candidate = _run_boot_attempt(
        paths=paths,
        runtime=runtime,
        sleeper=sleeper,
        enforce_root=enforce_root,
    )
    identity = EvidenceIdentity(
        str(candidate["review_id"]),
        str(candidate["package_id"]),
        str(candidate["boot_id"]),
        str(candidate["attempt_id"]),
    )
    arbiter = TerminalArbiter(paths.terminal_result(identity.boot_id), identity)
    candidate["phase_state_at_terminal"] = candidate[
        "phase_state_at_worker_candidate"
    ]
    try:
        committed = arbiter.commit(candidate)
        candidate["terminal_commit_won"] = committed.won
        if exit_code == 0:
            if (
                not committed.won
                and committed.payload.get("terminal_result") != "SUCCESS"
            ):
                candidate.update(
                    {
                        "status": "FAIL",
                        "terminal_result": "INTERNAL_VALIDATION_FAILURE",
                        "terminal_state": "TERMINAL_RESULT_ALREADY_COMMITTED",
                        "first_failure_classification": "TERMINAL_RESULT_ALREADY_COMMITTED",
                        "error": "a failure terminal result won before success",
                        "readiness_expected_count": 0,
                    }
                )
                return 1, candidate
            ensure_readiness_marker(paths, committed.payload)
            return 0, committed.payload
        if committed.won:
            return 1, committed.payload
        candidate["existing_terminal_result"] = committed.payload.get(
            "terminal_result"
        )
        candidate["existing_terminal_path"] = str(arbiter.path)
    except Exception as log_exc:
        candidate["persistent_log_error"] = str(log_exc)
    return 1, candidate


class SignalLatch:
    """Minimal first-signal latch; all reconciliation stays in the event loop."""

    def __init__(self) -> None:
        self.signum: int | None = None

    def trigger(self, signum: int) -> None:
        if self.signum is None:
            self.signum = int(signum)

    def handler(self, signum: int, _frame: Any) -> None:
        self.trigger(signum)

    def is_set(self) -> bool:
        return self.signum is not None


def signal_name(signum: int) -> str:
    try:
        return signal.Signals(signum).name
    except ValueError:
        return f"SIGNAL_{signum}"


def classify_supervisor_signal(signum: int, elapsed_seconds: float) -> str:
    """Classify only the observed signal; elapsed time is non-authoritative."""

    del elapsed_seconds
    if signum == signal.SIGINT:
        return "SIGINT"
    return "SIGTERM"


@dataclass(frozen=True)
class TransportRead:
    kind: str
    data: bytes = b""


class PosixPipeTransport:
    """Main-thread-owned nonblocking POSIX pipe transport."""

    def __init__(
        self,
        stream: BinaryIO,
        *,
        selector_factory: Callable[[], Any] = selectors.DefaultSelector,
    ) -> None:
        if os.name != "posix":
            raise BootLoadError(
                "production worker transport requires POSIX selector semantics",
                "POSIX_WORKER_TRANSPORT_REQUIRED",
            )
        self.stream = stream
        self.fd = int(stream.fileno())
        self.selector = selector_factory()
        self.closed = False
        os.set_blocking(self.fd, False)
        self.selector.register(self.fd, selectors.EVENT_READ)

    def read(self, timeout_seconds: float) -> TransportRead:
        if self.closed:
            return TransportRead("EOF")
        timeout = max(0.0, float(timeout_seconds))
        try:
            ready = self.selector.select(timeout)
        except InterruptedError:
            return TransportRead("INTERRUPTED")
        except OSError as exc:
            if exc.errno == errno.EINTR:
                return TransportRead("INTERRUPTED")
            raise
        if not ready:
            return TransportRead("WOULD_BLOCK")
        try:
            data = os.read(self.fd, PROTOCOL_READ_BYTES)
        except BlockingIOError:
            return TransportRead("WOULD_BLOCK")
        except InterruptedError:
            return TransportRead("INTERRUPTED")
        except OSError as exc:
            if exc.errno in {errno.EAGAIN, errno.EWOULDBLOCK}:
                return TransportRead("WOULD_BLOCK")
            if exc.errno == errno.EINTR:
                return TransportRead("INTERRUPTED")
            raise
        if not data:
            return TransportRead("EOF")
        return TransportRead("DATA", data)

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        try:
            self.selector.unregister(self.fd)
        except Exception:
            pass
        self.selector.close()
        self.stream.close()


def _forward_nonprotocol_output(data: bytes) -> None:
    target = getattr(sys.stderr, "buffer", None)
    if target is not None:
        target.write(data)
        target.flush()
    else:
        sys.stderr.write(data.decode("utf-8", errors="backslashreplace"))
        sys.stderr.flush()


class WorkerProtocolReceiver:
    """Bounded frame parser, validator, and sole worker-ledger bridge."""

    def __init__(
        self,
        *,
        ledger: PhaseLedger,
        identity: EvidenceIdentity,
        worker_pid: int,
        output_sink: Callable[[bytes], None] | None = None,
        maximum_frame_bytes: int = MAX_PROTOCOL_FRAME_BYTES,
    ) -> None:
        self.ledger = ledger
        self.identity = identity
        self.worker_pid = int(worker_pid)
        self.output_sink = output_sink or _forward_nonprotocol_output
        self.maximum_frame_bytes = int(maximum_frame_bytes)
        self.buffer = bytearray()
        self.expected_protocol_sequence = 1
        self.last_protocol_sequence = 0
        self.last_monotonic_ns: int | None = None
        self.protocol_errors: list[dict[str, Any]] = []
        self.candidates: list[dict[str, Any]] = []
        self.non_protocol_bytes = 0
        self.non_protocol_records = 0
        self.non_protocol_sha256 = hashlib.sha256()
        self.output_forward_errors: list[str] = []
        self.partial_tail: dict[str, Any] | None = None
        self.eof_without_trailing_newline = 0
        self.utc_advisory_backwards = 0
        self._last_utc_advisory: str | None = None
        self._discarding_oversized = False
        self._oversized_bytes = 0
        self._oversized_sha256 = hashlib.sha256()
        self.eof = False
        self.finished = False

    def _error(
        self,
        code: str,
        message: str,
        raw: bytes | None = None,
        **details: Any,
    ) -> None:
        record: dict[str, Any] = {"code": code, "message": message, **details}
        if raw is not None:
            record["frame_bytes"] = len(raw)
            record["frame_sha256"] = hashlib.sha256(raw).hexdigest()
        self.protocol_errors.append(record)

    def _emit_nonprotocol(self, data: bytes) -> None:
        if not data:
            return
        self.non_protocol_bytes += len(data)
        self.non_protocol_records += 1
        self.non_protocol_sha256.update(data)
        try:
            self.output_sink(data)
        except Exception as exc:
            self.output_forward_errors.append(f"{type(exc).__name__}: {exc}")

    def feed(self, data: bytes, *, signal_latched: bool) -> None:
        if self.finished:
            self._error("DATA_AFTER_PROTOCOL_FINISH", "bytes arrived after protocol finish")
            return
        if not isinstance(data, bytes):
            self._error("TRANSPORT_DATA_TYPE_INVALID", "transport did not return bytes")
            return
        pending = data
        while pending:
            if self._discarding_oversized:
                newline = pending.find(b"\n")
                if newline < 0:
                    self._oversized_bytes += len(pending)
                    self._oversized_sha256.update(pending)
                    return
                fragment = pending[:newline]
                self._oversized_bytes += len(fragment) + 1
                self._oversized_sha256.update(fragment + b"\n")
                self._error(
                    "OVERSIZED_FRAME",
                    "worker protocol frame exceeded the fixed limit",
                    frame_bytes=self._oversized_bytes,
                    frame_sha256=self._oversized_sha256.hexdigest(),
                )
                self._discarding_oversized = False
                self._oversized_bytes = 0
                self._oversized_sha256 = hashlib.sha256()
                pending = pending[newline + 1 :]
                continue

            self.buffer.extend(pending)
            pending = b""
            while True:
                newline = self.buffer.find(b"\n")
                if newline < 0:
                    break
                raw = bytes(self.buffer[:newline])
                del self.buffer[: newline + 1]
                terminated = raw + b"\n"
                if len(terminated) > self.maximum_frame_bytes:
                    if raw.startswith(IPC_PREFIX_BYTES):
                        self._error(
                            "OVERSIZED_FRAME",
                            "worker protocol frame exceeded the fixed limit",
                            terminated,
                        )
                    else:
                        self._emit_nonprotocol(terminated)
                    continue
                self._process_line(raw, signal_latched=signal_latched, terminated=True)

            if len(self.buffer) > self.maximum_frame_bytes:
                if self.buffer.startswith(IPC_PREFIX_BYTES):
                    self._discarding_oversized = True
                    self._oversized_bytes = len(self.buffer)
                    self._oversized_sha256.update(self.buffer)
                    self.buffer.clear()
                else:
                    self._emit_nonprotocol(bytes(self.buffer))
                    self.buffer.clear()

    def _process_line(
        self,
        raw: bytes,
        *,
        signal_latched: bool,
        terminated: bool,
    ) -> bool:
        original = raw + (b"\n" if terminated else b"")
        if not raw.startswith(IPC_PREFIX_BYTES):
            self._emit_nonprotocol(original)
            return False
        encoded = raw[len(IPC_PREFIX_BYTES) :]
        try:
            decoded = encoded.decode("utf-8", errors="strict")
        except UnicodeDecodeError as exc:
            self._error("MALFORMED_UTF8", str(exc), original)
            return False
        try:
            frame = json.loads(decoded)
        except json.JSONDecodeError as exc:
            self._error("MALFORMED_JSON", str(exc), original)
            return False
        if not isinstance(frame, dict):
            self._error("FRAME_ROOT_NOT_OBJECT", "protocol frame root is not an object", original)
            return False
        self._handle_frame(frame, raw=original, signal_latched=signal_latched)
        return True

    @staticmethod
    def _strict_int(value: Any) -> int | None:
        if isinstance(value, bool) or not isinstance(value, int):
            return None
        return value

    def _handle_frame(
        self,
        frame: dict[str, Any],
        *,
        raw: bytes,
        signal_latched: bool,
    ) -> None:
        required = {
            "type",
            "protocol_version",
            "protocol_sequence",
            "review_id",
            "package_id",
            "boot_id",
            "attempt_id",
            "worker_pid",
            "monotonic_ns",
            "utc_advisory",
            "clock_sync_state",
        }
        missing = sorted(required - set(frame))
        if missing:
            self._error("FRAME_FIELDS_MISSING", f"missing fields: {missing}", raw)
            return
        if frame.get("protocol_version") != PROTOCOL_VERSION:
            self._error(
                "PROTOCOL_VERSION_UNSUPPORTED",
                f"unsupported protocol version: {frame.get('protocol_version')!r}",
                raw,
            )
            return
        sequence = self._strict_int(frame.get("protocol_sequence"))
        if sequence != self.expected_protocol_sequence:
            self._error(
                "PROTOCOL_SEQUENCE_INVALID",
                f"expected sequence {self.expected_protocol_sequence}, observed {sequence!r}",
                raw,
            )
            return
        for field, expected in (
            ("review_id", self.identity.review_id),
            ("package_id", self.identity.package_id),
            ("boot_id", self.identity.boot_id),
            ("attempt_id", self.identity.attempt_id),
            ("worker_pid", self.worker_pid),
        ):
            if frame.get(field) != expected:
                self._error(
                    "PROTOCOL_IDENTITY_MISMATCH",
                    f"{field} mismatch: {frame.get(field)!r}",
                    raw,
                    field=field,
                    expected=expected,
                    observed=frame.get(field),
                )
                return
        monotonic_ns = self._strict_int(frame.get("monotonic_ns"))
        if monotonic_ns is None or monotonic_ns < 0:
            self._error("PROTOCOL_MONOTONIC_INVALID", "monotonic_ns is invalid", raw)
            return
        if self.last_monotonic_ns is not None and monotonic_ns < self.last_monotonic_ns:
            self._error(
                "PROTOCOL_MONOTONIC_BACKWARDS",
                f"monotonic_ns moved backwards: {monotonic_ns} < {self.last_monotonic_ns}",
                raw,
            )
            return
        utc_advisory = frame.get("utc_advisory")
        if not isinstance(utc_advisory, str):
            self._error("PROTOCOL_UTC_INVALID", "utc_advisory is not a string", raw)
            return
        if self._last_utc_advisory is not None and utc_advisory < self._last_utc_advisory:
            self.utc_advisory_backwards += 1
        self._last_utc_advisory = utc_advisory
        clock_status = frame.get("clock_sync_state")
        if clock_status not in {"SYNCHRONIZED", "UNKNOWN"}:
            self._error(
                "PROTOCOL_CLOCK_STATE_INVALID",
                f"invalid clock_sync_state: {clock_status!r}",
                raw,
            )
            return

        self.expected_protocol_sequence += 1
        self.last_protocol_sequence = sequence
        self.last_monotonic_ns = monotonic_ns
        frame_type = frame.get("type")
        if frame_type == "PHASE":
            try:
                self.ledger.emit(
                    str(frame.get("phase")),
                    str(frame.get("event")),
                    exception_type=frame.get("exception_type"),
                    exception_message=frame.get("exception_message"),
                    signal_name=frame.get("signal"),
                    pid=self.worker_pid,
                    monotonic_ns=monotonic_ns,
                    utc_advisory=utc_advisory,
                    clock_status=str(clock_status),
                    event_source="WORKER",
                    worker_protocol_sequence=sequence,
                )
            except Exception as exc:
                self._error(
                    "INVALID_PHASE_TRANSITION",
                    f"{type(exc).__name__}: {exc}",
                    raw,
                )
        elif frame_type == "TERMINAL_CANDIDATE":
            candidate = frame.get("candidate")
            if not isinstance(candidate, dict):
                self._error(
                    "TERMINAL_CANDIDATE_INVALID",
                    "terminal candidate is not an object",
                    raw,
                )
                return
            for field, expected in (
                ("review_id", self.identity.review_id),
                ("package_id", self.identity.package_id),
                ("boot_id", self.identity.boot_id),
                ("attempt_id", self.identity.attempt_id),
            ):
                if candidate.get(field) != expected:
                    self._error(
                        "TERMINAL_CANDIDATE_IDENTITY_MISMATCH",
                        f"candidate {field} mismatch: {candidate.get(field)!r}",
                        raw,
                    )
                    return
            if candidate.get("terminal_result") not in {
                "SUCCESS",
                "PYTHON_EXCEPTION",
                "INTERNAL_VALIDATION_FAILURE",
                "PHASE_INCOMPLETE",
            }:
                self._error(
                    "TERMINAL_CANDIDATE_CLASS_INVALID",
                    f"invalid worker terminal class: {candidate.get('terminal_result')!r}",
                    raw,
                )
                return
            if self.candidates:
                self._error(
                    "DUPLICATE_TERMINAL_CANDIDATE",
                    "worker sent more than one terminal candidate",
                    raw,
                )
                return
            self.candidates.append(
                {
                    "candidate": candidate,
                    "protocol_sequence": sequence,
                    "received_after_signal_latch": bool(signal_latched),
                }
            )
        else:
            self._error(
                "PROTOCOL_FRAME_TYPE_UNSUPPORTED",
                f"unsupported frame type: {frame_type!r}",
                raw,
            )

    def finish(self, *, eof: bool, signal_latched: bool) -> None:
        if self.finished:
            return
        self.finished = True
        self.eof = self.eof or eof
        if self._discarding_oversized:
            self._error(
                "OVERSIZED_FRAME",
                "oversized worker frame did not terminate before transport finish",
                frame_bytes=self._oversized_bytes,
                frame_sha256=self._oversized_sha256.hexdigest(),
            )
            self._discarding_oversized = False
        if not self.buffer:
            return
        raw = bytes(self.buffer)
        self.buffer.clear()
        self.partial_tail = {
            "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "protocol_prefix": raw.startswith(IPC_PREFIX_BYTES),
        }
        if not raw.startswith(IPC_PREFIX_BYTES):
            self._emit_nonprotocol(raw)
            return
        if eof and len(raw) <= self.maximum_frame_bytes:
            before_errors = len(self.protocol_errors)
            accepted = self._process_line(
                raw,
                signal_latched=signal_latched,
                terminated=False,
            )
            if accepted and len(self.protocol_errors) == before_errors:
                self.eof_without_trailing_newline += 1
                self.partial_tail["accepted_complete_frame_at_eof"] = True
                return
        if not self.protocol_errors or self.protocol_errors[-1].get("frame_sha256") != hashlib.sha256(raw).hexdigest():
            self._error(
                "PARTIAL_PROTOCOL_FRAME",
                "transport ended with an incomplete protocol frame",
                raw,
            )

    def summary(self) -> dict[str, Any]:
        return {
            "protocol_version": PROTOCOL_VERSION,
            "last_protocol_sequence": self.last_protocol_sequence,
            "next_expected_protocol_sequence": self.expected_protocol_sequence,
            "protocol_errors": self.protocol_errors,
            "candidate_count": len(self.candidates),
            "non_protocol_output": {
                "records": self.non_protocol_records,
                "bytes": self.non_protocol_bytes,
                "sha256": self.non_protocol_sha256.hexdigest(),
                "forward_errors": self.output_forward_errors,
            },
            "partial_tail": self.partial_tail,
            "eof": self.eof,
            "eof_without_trailing_newline": self.eof_without_trailing_newline,
            "utc_advisory_backwards": self.utc_advisory_backwards,
        }


def _supervisor_terminal_payload(
    *,
    identity: EvidenceIdentity,
    paths: LoaderPaths,
    ledger: PhaseLedger,
    terminal_result: str,
    terminal_state: str,
    child_pid: int | None,
    child_returncode: int | None,
    received_signal: str | None,
    service_elapsed_seconds: float,
    error: str,
    signal_latch_monotonic_ns: int | None = None,
) -> dict[str, Any]:
    terminal_ns = time.monotonic_ns()
    return {
        "status": "FAIL",
        "terminal_result": terminal_result,
        "terminal_state": terminal_state,
        "first_failure_classification": terminal_state,
        "error": error,
        "signal": received_signal,
        "terminal_utc_advisory": utc_now(),
        "terminal_monotonic_ns": terminal_ns,
        "clock_synchronized_or_unknown": ledger.clock_status,
        "attempt_marker": str(paths.attempt_marker(identity.boot_id)),
        "phase_evidence_root": str(ledger.root),
        "phase_state_at_terminal": ledger.tracker.snapshot(terminal_ns),
        "readiness_expected_count": 0,
        "readiness_marker": None,
        "supervisor_pid": os.getpid(),
        "worker_pid": child_pid,
        "worker_returncode": child_returncode,
        "supervisor_relative_elapsed_seconds": service_elapsed_seconds,
        "service_elapsed_seconds": service_elapsed_seconds,
        "signal_latch_monotonic_ns": signal_latch_monotonic_ns,
        "systemd_timeout_start_seconds": SYSTEMD_TIMEOUT_START_SECONDS,
        "systemd_timeout_inferred": False,
        "timeout_inference_hint": {
            "non_authoritative": True,
            "requires_offline_systemd_result": True,
            "required_systemd_fields": ["Result", "ExecMainStatus", "journal_monotonic_timestamps"],
        },
        "operation_counts": {
            "worker_processes_started": 1 if child_pid is not None else 0,
            "automatic_retries": 0,
            "second_executions": 0,
        },
    }


def _remaining_seconds(deadline_ns: int, clock_ns: Callable[[], int]) -> float:
    return max(0.0, (deadline_ns - clock_ns()) / 1_000_000_000)


def _read_transport_once(
    transport: Any,
    receiver: WorkerProtocolReceiver,
    *,
    timeout_seconds: float,
    signal_latched: bool | Callable[[], bool],
) -> str:
    try:
        observed = transport.read(max(0.0, timeout_seconds))
    except Exception as exc:
        receiver._error(
            "TRANSPORT_READ_FAILED",
            f"{type(exc).__name__}: {exc}",
        )
        return "ERROR"
    if observed.kind == "DATA":
        latched = signal_latched() if callable(signal_latched) else signal_latched
        receiver.feed(observed.data, signal_latched=latched)
    elif observed.kind == "EOF":
        receiver.eof = True
    elif observed.kind not in {"WOULD_BLOCK", "INTERRUPTED"}:
        receiver._error(
            "TRANSPORT_STATUS_INVALID",
            f"invalid transport status: {observed.kind!r}",
        )
        return "ERROR"
    return observed.kind


def _drain_available(
    transport: Any,
    receiver: WorkerProtocolReceiver,
    *,
    signal_latched: bool,
    deadline_ns: int | None = None,
    clock_ns: Callable[[], int] = time.monotonic_ns,
) -> None:
    for _ in range(1024):
        if receiver.eof:
            return
        if deadline_ns is not None and clock_ns() >= deadline_ns:
            receiver._error(
                "IMMEDIATE_DRAIN_DEADLINE",
                "immediate drain reached the shared cleanup deadline",
            )
            return
        kind = _read_transport_once(
            transport,
            receiver,
            timeout_seconds=0.0,
            signal_latched=signal_latched,
        )
        if kind in {"WOULD_BLOCK", "EOF", "ERROR"}:
            return
    receiver._error(
        "IMMEDIATE_DRAIN_ITERATION_LIMIT",
        "immediate drain exceeded its deterministic iteration bound",
    )


def _candidate_summary(record: dict[str, Any]) -> dict[str, Any]:
    candidate = record["candidate"]
    return {
        "protocol_sequence": record["protocol_sequence"],
        "received_after_signal_latch": record["received_after_signal_latch"],
        "terminal_result": candidate.get("terminal_result"),
        "terminal_state": candidate.get("terminal_state"),
    }


def _reconciled_terminal_payload(
    *,
    identity: EvidenceIdentity,
    paths: LoaderPaths,
    ledger: PhaseLedger,
    receiver: WorkerProtocolReceiver,
    child_pid: int,
    process_group_id: int,
    child_returncode: int | None,
    child_reaped: bool,
    signal_signum: int | None,
    signal_latch_monotonic_ns: int | None,
    supervisor_entry_monotonic_ns: int,
    cleanup: dict[str, Any],
    clock_ns: Callable[[], int],
) -> dict[str, Any]:
    reconciliation_ns = clock_ns()
    signal_recorded = signal_name(signal_signum) if signal_signum is not None else None
    before_signal = next(
        (
            record
            for record in receiver.candidates
            if not record["received_after_signal_latch"]
        ),
        None,
    )
    any_candidate = receiver.candidates[0] if receiver.candidates else None
    protocol_failed = bool(receiver.protocol_errors)
    cleanup_failed = (not child_reaped) or bool(cleanup.get("pipe_eof_timeout"))

    selected: dict[str, Any] | None = None
    selected_source = "SUPERVISOR"
    if signal_signum is not None and before_signal is not None:
        selected = dict(before_signal["candidate"])
        selected_source = "WORKER_CANDIDATE_BEFORE_SIGNAL"
    elif signal_signum is None and any_candidate is not None:
        selected = dict(any_candidate["candidate"])
        selected_source = "WORKER_CANDIDATE"

    if selected is None:
        if signal_signum is not None:
            result_class = classify_supervisor_signal(
                signal_signum,
                (reconciliation_ns - supervisor_entry_monotonic_ns) / 1_000_000_000,
            )
            selected = {
                "status": "FAIL",
                "terminal_result": result_class,
                "terminal_state": result_class,
                "first_failure_classification": result_class,
                "error": f"supervisor received {signal_recorded}",
            }
            selected_source = "SUPERVISOR_SIGNAL"
        elif protocol_failed:
            selected = {
                "status": "FAIL",
                "terminal_result": "INTERNAL_VALIDATION_FAILURE",
                "terminal_state": "PHASE_PROTOCOL_INVALID",
                "first_failure_classification": "PHASE_PROTOCOL_INVALID",
                "error": "worker protocol validation failed",
            }
            selected_source = "SUPERVISOR_PROTOCOL"
        else:
            selected = {
                "status": "FAIL",
                "terminal_result": "PHASE_INCOMPLETE",
                "terminal_state": "PHASE_INCOMPLETE",
                "first_failure_classification": "PHASE_INCOMPLETE",
                "error": "worker exited without a terminal candidate",
            }
            selected_source = "SUPERVISOR_INCOMPLETE"

    selected_result = selected.get("terminal_result")
    selected_worker_failure = selected_result not in {None, "SUCCESS"} and selected_source.startswith("WORKER")
    success_phase_incomplete = (
        selected_result == "SUCCESS"
        and (
            ledger.tracker.current_phase is not None
            or ledger.tracker.last_completed_phase != "normal_exit"
            or tuple(ledger.tracker.completed_phases) != PHASES
        )
    )
    returncode_mismatch = child_returncode != 0 and not (
        signal_signum is not None
        and selected_source == "WORKER_CANDIDATE_BEFORE_SIGNAL"
    )
    if selected_result == "SUCCESS" and (
        protocol_failed
        or cleanup_failed
        or returncode_mismatch
        or success_phase_incomplete
    ):
        if cleanup.get("pipe_eof_timeout"):
            failure_state = "PIPE_EOF_TIMEOUT"
            failure_result = "PHASE_INCOMPLETE"
        elif not child_reaped:
            failure_state = "WORKER_REAP_TIMEOUT"
            failure_result = "PHASE_INCOMPLETE"
        elif returncode_mismatch:
            failure_state = "WORKER_SUCCESS_EXIT_MISMATCH"
            failure_result = "INTERNAL_VALIDATION_FAILURE"
        elif success_phase_incomplete:
            failure_state = "PHASE_SUCCESS_SEQUENCE_INCOMPLETE"
            failure_result = "PHASE_INCOMPLETE"
        else:
            failure_state = "PHASE_PROTOCOL_INVALID"
            failure_result = "INTERNAL_VALIDATION_FAILURE"
        selected["worker_success_candidate_suppressed"] = True
        selected.pop("readiness_payload", None)
        selected.update(
            {
                "status": "FAIL",
                "terminal_result": failure_result,
                "terminal_state": failure_state,
                "first_failure_classification": failure_state,
                "error": f"worker success candidate rejected: {failure_state}",
            }
        )
        selected_source = "SUPERVISOR_CONSERVATIVE_FAILURE"
    elif selected_worker_failure:
        selected["status"] = "FAIL"

    terminal_result = str(selected["terminal_result"])
    if terminal_result not in TERMINAL_RESULTS:
        selected.update(
            {
                "status": "FAIL",
                "terminal_result": "INTERNAL_VALIDATION_FAILURE",
                "terminal_state": "TERMINAL_CANDIDATE_CLASS_INVALID",
                "first_failure_classification": "TERMINAL_CANDIDATE_CLASS_INVALID",
                "error": f"invalid selected terminal result: {terminal_result!r}",
            }
        )
        terminal_result = "INTERNAL_VALIDATION_FAILURE"
    success = terminal_result == "SUCCESS"
    if not success:
        selected.pop("readiness_payload", None)

    elapsed_seconds = (
        reconciliation_ns - supervisor_entry_monotonic_ns
    ) / 1_000_000_000
    selected.update(
        {
            "schema_version": TERMINAL_SCHEMA_VERSION,
            "review_id": identity.review_id,
            "package_id": identity.package_id,
            "boot_id": identity.boot_id,
            "attempt_id": identity.attempt_id,
            "status": "PASS" if success else "FAIL",
            "terminal_source": selected_source,
            "signal": signal_recorded,
            "signal_latch_monotonic_ns": signal_latch_monotonic_ns,
            "supervisor_pid": os.getpid(),
            "worker_pid": child_pid,
            "worker_process_group_id": process_group_id,
            "worker_returncode": child_returncode,
            "worker_reaped": child_reaped,
            "supervisor_entry_monotonic_ns": supervisor_entry_monotonic_ns,
            "supervisor_relative_elapsed_seconds": elapsed_seconds,
            "service_elapsed_seconds": elapsed_seconds,
            "terminal_monotonic_ns": reconciliation_ns,
            "terminal_utc_advisory": utc_now(),
            "clock_synchronized_or_unknown": ledger.clock_status,
            "attempt_marker": str(paths.attempt_marker(identity.boot_id)),
            "phase_evidence_root": str(ledger.root),
            "phase_state_at_terminal": ledger.tracker.snapshot(reconciliation_ns),
            "ledger_sequence_at_terminal": ledger.sequence,
            "worker_protocol": receiver.summary(),
            "worker_terminal_candidates": [
                _candidate_summary(record) for record in receiver.candidates
            ],
            "cleanup": cleanup,
            "readiness_expected_count": 1 if success else 0,
            "readiness_marker": (
                str(paths.readiness_marker(identity.boot_id)) if success else None
            ),
            "systemd_timeout_start_seconds": SYSTEMD_TIMEOUT_START_SECONDS,
            "systemd_timeout_inferred": False,
            "timeout_inference_hint": {
                "non_authoritative": True,
                "requires_offline_systemd_result": True,
                "required_systemd_fields": [
                    "Result",
                    "ExecMainStatus",
                    "journal_monotonic_timestamps",
                ],
            },
            "supervisor_operation_counts": {
                "worker_processes_started": 1,
                "automatic_retries": 0,
                "second_executions": 0,
                "soft_group_signals": int(cleanup.get("soft_group_signals", 0)),
                "sigkill_group_signals": int(cleanup.get("sigkill_group_signals", 0)),
            },
        }
    )
    return selected


def _finalize_bootstrap_failure(
    *,
    identity: EvidenceIdentity,
    paths: LoaderPaths,
    ledger: PhaseLedger,
    arbiter: TerminalArbiter,
    supervisor_entry_monotonic_ns: int,
    terminal_result: str,
    terminal_state: str,
    error: str,
    clock_ns: Callable[[], int],
    child: Any | None = None,
    process_group_id: int | None = None,
    process_group_signaler: Callable[[int, int], None] | None = None,
    term_wait_seconds: float = SUPERVISOR_TERM_WAIT_SECONDS,
    cleanup_seconds: float = SUPERVISOR_CLEANUP_SECONDS,
) -> tuple[int, dict[str, Any]]:
    """Conservatively finalize failures before a usable transport exists."""

    cleanup_start_ns = clock_ns()
    cleanup_deadline_ns = cleanup_start_ns + int(cleanup_seconds * 1_000_000_000)
    cleanup: dict[str, Any] = {
        "reason": terminal_state,
        "absolute_deadline_monotonic_ns": cleanup_deadline_ns,
        "soft_group_signals": 0,
        "sigkill_group_signals": 0,
        "soft_signal_process_lookup_race": False,
        "sigkill_process_lookup_race": False,
        "pipe_eof_timeout": child is not None,
    }
    if child is not None and process_group_id is not None and process_group_signaler is not None:
        if child.poll() is None:
            try:
                process_group_signaler(process_group_id, signal.SIGTERM)
                cleanup["soft_group_signals"] = 1
            except ProcessLookupError:
                cleanup["soft_signal_process_lookup_race"] = True
        term_timeout = min(
            max(0.0, term_wait_seconds),
            _remaining_seconds(cleanup_deadline_ns, clock_ns),
        )
        if child.poll() is None:
            try:
                child.wait(timeout=term_timeout)
            except subprocess.TimeoutExpired:
                pass
        if child.poll() is None:
            try:
                process_group_signaler(process_group_id, SIGKILL_NUMBER)
                cleanup["sigkill_group_signals"] = 1
            except ProcessLookupError:
                cleanup["sigkill_process_lookup_race"] = True
        if child.poll() is None:
            try:
                child.wait(timeout=_remaining_seconds(cleanup_deadline_ns, clock_ns))
            except subprocess.TimeoutExpired:
                pass

    child_returncode = child.poll() if child is not None else None
    child_reaped = child is None or child_returncode is not None
    if child is not None and child_reaped:
        try:
            child.wait(timeout=0)
        except (subprocess.TimeoutExpired, ProcessLookupError):
            child_reaped = False
    cleanup.update(
        {
            "child_reaped": child_reaped,
            "child_returncode": child_returncode,
            "deadline_exhausted": clock_ns() >= cleanup_deadline_ns,
            "completed_monotonic_ns": clock_ns(),
        }
    )
    if ledger.tracker.current_phase is not None:
        ledger.emit(
            ledger.tracker.current_phase,
            "FAIL",
            exception_type="SupervisorBootstrapFailure",
            exception_message=error,
            monotonic_ns=clock_ns(),
            event_source="SUPERVISOR_RECONCILIATION",
        )
    reconciliation_ns = clock_ns()
    terminal = _supervisor_terminal_payload(
        identity=identity,
        paths=paths,
        ledger=ledger,
        terminal_result=terminal_result,
        terminal_state=terminal_state,
        child_pid=(int(child.pid) if child is not None else None),
        child_returncode=child_returncode,
        received_signal=None,
        service_elapsed_seconds=(
            reconciliation_ns - supervisor_entry_monotonic_ns
        )
        / 1_000_000_000,
        error=error,
    )
    terminal.update(
        {
            "worker_process_group_id": process_group_id,
            "worker_reaped": child_reaped,
            "cleanup": cleanup,
            "ledger_sequence_at_terminal": ledger.sequence,
            "phase_state_at_terminal": ledger.tracker.snapshot(reconciliation_ns),
        }
    )
    committed = arbiter.commit(terminal)
    terminal_commit_ns = clock_ns()
    write_json_exclusive(
        ledger.root / "supervisor_finalization.json",
        {
            "schema_version": "stage1g-supervisor-finalization-v2",
            "review_id": identity.review_id,
            "package_id": identity.package_id,
            "boot_id": identity.boot_id,
            "attempt_id": identity.attempt_id,
            "worker_pid": int(child.pid) if child is not None else None,
            "worker_process_group_id": process_group_id,
            "child_reaped": child_reaped,
            "child_returncode": child_returncode,
            "cleanup": cleanup,
            "reconciliation_completed_monotonic_ns": reconciliation_ns,
            "terminal_commit_completed_monotonic_ns": terminal_commit_ns,
            "terminal_commit_after_reconciliation": terminal_commit_ns >= reconciliation_ns,
            "terminal_commit_won": committed.won,
            "terminal_result": committed.payload.get("terminal_result"),
            "readiness_count": 0,
            "automatic_retries": 0,
            "owner_fd_close_pending": child is not None,
            "monotonic_ns": clock_ns(),
            "utc_advisory": utc_now(),
            "clock_synchronized_or_unknown": ledger.clock_status,
        },
    )
    if child is not None and child.stdout is not None:
        try:
            child.stdout.close()
        except Exception as exc:
            print(
                f"owner fd close failed after finalization: {type(exc).__name__}: {exc}",
                file=sys.stderr,
            )
    return 1, committed.payload


def supervise_child(
    *,
    command: list[str],
    paths: LoaderPaths,
    identity: EvidenceIdentity,
    ledger: PhaseLedger,
    arbiter: TerminalArbiter,
    latch: SignalLatch,
    service_entry_monotonic_ns: int,
    environment: dict[str, str] | None = None,
    poll_seconds: float = SUPERVISOR_POLL_SECONDS,
    term_wait_seconds: float = SUPERVISOR_TERM_WAIT_SECONDS,
    cleanup_seconds: float = SUPERVISOR_CLEANUP_SECONDS,
    popen_factory: Callable[..., Any] = subprocess.Popen,
    transport_factory: Callable[[BinaryIO], Any] | None = None,
    process_group_getter: Callable[[int], int] | None = None,
    process_group_signaler: Callable[[int, int], None] | None = None,
    clock_ns: Callable[[], int] = time.monotonic_ns,
    output_sink: Callable[[bytes], None] | None = None,
) -> tuple[int, dict[str, Any]]:
    if cleanup_seconds <= 0 or term_wait_seconds < 0 or poll_seconds <= 0:
        raise ValueError("cleanup deadlines must be non-negative and bounded")
    if transport_factory is None and os.name != "posix":
        return _finalize_bootstrap_failure(
            identity=identity,
            paths=paths,
            ledger=ledger,
            arbiter=arbiter,
            supervisor_entry_monotonic_ns=service_entry_monotonic_ns,
            terminal_result="INTERNAL_VALIDATION_FAILURE",
            terminal_state="POSIX_WORKER_TRANSPORT_REQUIRED",
            error="production worker transport requires POSIX selector semantics",
            clock_ns=clock_ns,
            term_wait_seconds=term_wait_seconds,
            cleanup_seconds=cleanup_seconds,
        )

    python_entry_ns = clock_ns()
    ledger.emit("python_entry", "ENTER", monotonic_ns=python_entry_ns)
    command = [
        str(python_entry_ns) if item == "{python_entry_monotonic_ns}" else item
        for item in command
    ]
    child_environment = dict(os.environ if environment is None else environment)
    child_environment["PYTHONDONTWRITEBYTECODE"] = "1"
    try:
        child = popen_factory(
            command,
            stdout=subprocess.PIPE,
            stderr=None,
            text=False,
            bufsize=0,
            env=child_environment,
            start_new_session=True,
        )
    except Exception as exc:
        ledger.emit(
            "python_entry",
            "FAIL",
            exception_type=type(exc).__name__,
            exception_message=str(exc),
        )
        return _finalize_bootstrap_failure(
            identity=identity,
            paths=paths,
            ledger=ledger,
            arbiter=arbiter,
            supervisor_entry_monotonic_ns=service_entry_monotonic_ns,
            terminal_result="PYTHON_EXCEPTION",
            terminal_state="WORKER_SPAWN_FAILED",
            error=f"{type(exc).__name__}: {exc}",
            clock_ns=clock_ns,
            term_wait_seconds=term_wait_seconds,
            cleanup_seconds=cleanup_seconds,
        )

    group_getter = process_group_getter or os.getpgid
    group_signaler = process_group_signaler or os.killpg
    if child.stdout is None:
        return _finalize_bootstrap_failure(
            identity=identity,
            paths=paths,
            ledger=ledger,
            arbiter=arbiter,
            supervisor_entry_monotonic_ns=service_entry_monotonic_ns,
            terminal_result="INTERNAL_VALIDATION_FAILURE",
            terminal_state="PHASE_IPC_MISSING",
            error="worker stdout pipe is missing",
            clock_ns=clock_ns,
            child=child,
            process_group_id=int(child.pid),
            process_group_signaler=group_signaler,
            term_wait_seconds=term_wait_seconds,
            cleanup_seconds=cleanup_seconds,
        )
    try:
        observed_process_group_id = int(group_getter(int(child.pid)))
    except ProcessLookupError:
        observed_process_group_id = int(child.pid)
    process_group_id = int(child.pid)
    if observed_process_group_id != process_group_id:
        return _finalize_bootstrap_failure(
            identity=identity,
            paths=paths,
            ledger=ledger,
            arbiter=arbiter,
            supervisor_entry_monotonic_ns=service_entry_monotonic_ns,
            terminal_result="INTERNAL_VALIDATION_FAILURE",
            terminal_state="WORKER_PROCESS_GROUP_INVALID",
            error=(
                f"worker process group mismatch: {observed_process_group_id} "
                f"!= {process_group_id}"
            ),
            clock_ns=clock_ns,
            child=child,
            process_group_id=process_group_id,
            process_group_signaler=group_signaler,
            term_wait_seconds=term_wait_seconds,
            cleanup_seconds=cleanup_seconds,
        )

    try:
        transport = (
            PosixPipeTransport(child.stdout)
            if transport_factory is None
            else transport_factory(child.stdout)
        )
    except Exception as exc:
        return _finalize_bootstrap_failure(
            identity=identity,
            paths=paths,
            ledger=ledger,
            arbiter=arbiter,
            supervisor_entry_monotonic_ns=service_entry_monotonic_ns,
            terminal_result="INTERNAL_VALIDATION_FAILURE",
            terminal_state="WORKER_TRANSPORT_INITIALIZATION_FAILED",
            error=f"{type(exc).__name__}: {exc}",
            clock_ns=clock_ns,
            child=child,
            process_group_id=process_group_id,
            process_group_signaler=group_signaler,
            term_wait_seconds=term_wait_seconds,
            cleanup_seconds=cleanup_seconds,
        )
    receiver = WorkerProtocolReceiver(
        ledger=ledger,
        identity=identity,
        worker_pid=int(child.pid),
        output_sink=output_sink,
    )
    cleanup_reason: str | None = None
    cleanup_origin_ns: int | None = None
    signal_signum: int | None = None
    signal_latch_ns: int | None = None

    while cleanup_reason is None:
        if latch.is_set():
            signal_signum = latch.signum if latch.signum is not None else signal.SIGTERM
            signal_latch_ns = clock_ns()
            cleanup_origin_ns = signal_latch_ns
            _drain_available(
                transport,
                receiver,
                signal_latched=True,
                deadline_ns=(
                    cleanup_origin_ns + int(cleanup_seconds * 1_000_000_000)
                ),
                clock_ns=clock_ns,
            )
            cleanup_reason = "SIGNAL_LATCHED"
            break
        if receiver.eof:
            try:
                child.wait(timeout=max(0.0, poll_seconds))
            except subprocess.TimeoutExpired:
                pass
        else:
            _read_transport_once(
                transport,
                receiver,
                timeout_seconds=poll_seconds,
                signal_latched=latch.is_set,
            )
        if latch.is_set():
            continue
        if receiver.protocol_errors:
            cleanup_origin_ns = clock_ns()
            cleanup_reason = "PROTOCOL_VALIDATION_FAILURE"
            break
        if child.poll() is not None:
            cleanup_origin_ns = clock_ns()
            _drain_available(
                transport,
                receiver,
                signal_latched=False,
                deadline_ns=(
                    cleanup_origin_ns + int(cleanup_seconds * 1_000_000_000)
                ),
                clock_ns=clock_ns,
            )
            cleanup_reason = "WORKER_EXITED"

    cleanup_start_ns = cleanup_origin_ns if cleanup_origin_ns is not None else clock_ns()
    cleanup_deadline_ns = cleanup_start_ns + int(cleanup_seconds * 1_000_000_000)
    term_deadline_ns = min(
        cleanup_deadline_ns,
        cleanup_start_ns + int(term_wait_seconds * 1_000_000_000),
    )
    cleanup: dict[str, Any] = {
        "reason": cleanup_reason,
        "absolute_deadline_monotonic_ns": cleanup_deadline_ns,
        "soft_group_signals": 0,
        "sigkill_group_signals": 0,
        "soft_signal": None,
        "soft_signal_process_lookup_race": False,
        "sigkill_process_lookup_race": False,
        "pipe_eof_timeout": False,
    }

    needs_group_cleanup = (
        cleanup_reason in {"SIGNAL_LATCHED", "PROTOCOL_VALIDATION_FAILURE"}
        or (cleanup_reason == "WORKER_EXITED" and not receiver.eof)
    )
    soft_signum = signal_signum if signal_signum is not None else signal.SIGTERM
    if needs_group_cleanup:
        try:
            group_signaler(process_group_id, soft_signum)
            cleanup["soft_group_signals"] = 1
            cleanup["soft_signal"] = signal_name(soft_signum)
        except ProcessLookupError:
            cleanup["soft_signal_process_lookup_race"] = True

    def pump_until(deadline_ns: int) -> None:
        while clock_ns() < deadline_ns:
            child_exited = child.poll() is not None
            if child_exited and receiver.eof:
                return
            remaining = _remaining_seconds(deadline_ns, clock_ns)
            timeout = min(max(0.0, poll_seconds), remaining)
            if receiver.eof and not child_exited:
                try:
                    child.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    pass
            elif not receiver.eof:
                _read_transport_once(
                    transport,
                    receiver,
                    timeout_seconds=timeout,
                    signal_latched=signal_signum is not None,
                )
            else:
                return

    pump_until(term_deadline_ns)
    if needs_group_cleanup and (child.poll() is None or not receiver.eof):
        try:
            group_signaler(process_group_id, SIGKILL_NUMBER)
            cleanup["sigkill_group_signals"] = 1
        except ProcessLookupError:
            cleanup["sigkill_process_lookup_race"] = True
    pump_until(cleanup_deadline_ns)
    _drain_available(
        transport,
        receiver,
        signal_latched=signal_signum is not None,
        deadline_ns=cleanup_deadline_ns,
        clock_ns=clock_ns,
    )

    child_returncode = child.poll()
    child_reaped = child_returncode is not None
    if child_reaped:
        try:
            child.wait(timeout=0)
        except (subprocess.TimeoutExpired, ProcessLookupError):
            child_reaped = False
    cleanup["child_reaped"] = child_reaped
    cleanup["child_returncode"] = child_returncode
    cleanup["pipe_eof_timeout"] = not receiver.eof
    cleanup["deadline_exhausted"] = clock_ns() >= cleanup_deadline_ns
    cleanup["completed_monotonic_ns"] = clock_ns()
    receiver.finish(
        eof=receiver.eof,
        signal_latched=signal_signum is not None,
    )

    if ledger.tracker.current_phase is not None:
        if signal_signum is not None:
            failure_type = "SupervisorSignal"
            failure_message = f"supervisor received {signal_name(signal_signum)}"
        elif receiver.protocol_errors:
            failure_type = "WorkerProtocolFailure"
            failure_message = "worker protocol validation failed"
        else:
            failure_type = "WorkerExit"
            failure_message = f"worker exited {child_returncode} before closing the phase"
        ledger.emit(
            ledger.tracker.current_phase,
            "FAIL",
            exception_type=failure_type,
            exception_message=failure_message,
            signal_name=(signal_name(signal_signum) if signal_signum is not None else None),
            monotonic_ns=clock_ns(),
            event_source="SUPERVISOR_RECONCILIATION",
        )

    reconciliation_completed_ns = clock_ns()
    terminal = _reconciled_terminal_payload(
        identity=identity,
        paths=paths,
        ledger=ledger,
        receiver=receiver,
        child_pid=int(child.pid),
        process_group_id=process_group_id,
        child_returncode=child_returncode,
        child_reaped=child_reaped,
        signal_signum=signal_signum,
        signal_latch_monotonic_ns=signal_latch_ns,
        supervisor_entry_monotonic_ns=service_entry_monotonic_ns,
        cleanup=cleanup,
        clock_ns=clock_ns,
    )
    committed = arbiter.commit(terminal)
    terminal_commit_completed_ns = clock_ns()
    readiness_path: Path | None = None
    if committed.payload.get("terminal_result") == "SUCCESS":
        readiness_path = ensure_readiness_marker(paths, committed.payload)
    readiness_commit_completed_ns = clock_ns()
    finalization = {
        "schema_version": "stage1g-supervisor-finalization-v2",
        "review_id": identity.review_id,
        "package_id": identity.package_id,
        "boot_id": identity.boot_id,
        "attempt_id": identity.attempt_id,
        "worker_pid": int(child.pid),
        "worker_process_group_id": process_group_id,
        "child_reaped": child_reaped,
        "child_returncode": child_returncode,
        "signal": signal_name(signal_signum) if signal_signum is not None else None,
        "signal_latch_monotonic_ns": signal_latch_ns,
        "cleanup": cleanup,
        "protocol": receiver.summary(),
        "reconciliation_completed_monotonic_ns": reconciliation_completed_ns,
        "terminal_commit_completed_monotonic_ns": terminal_commit_completed_ns,
        "terminal_commit_after_reconciliation": (
            terminal_commit_completed_ns >= reconciliation_completed_ns
        ),
        "terminal_commit_won": committed.won,
        "terminal_result": committed.payload.get("terminal_result"),
        "readiness_commit_completed_monotonic_ns": readiness_commit_completed_ns,
        "readiness_path": str(readiness_path) if readiness_path is not None else None,
        "readiness_count": 1 if readiness_path is not None else 0,
        "automatic_retries": 0,
        "owner_fd_close_pending": True,
        "monotonic_ns": clock_ns(),
        "utc_advisory": utc_now(),
        "clock_synchronized_or_unknown": ledger.clock_status,
    }
    write_json_exclusive(ledger.root / "supervisor_finalization.json", finalization)
    try:
        transport.close()
    except Exception as exc:
        print(
            f"owner fd close failed after finalization: {type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
    if committed.payload.get("terminal_result") == "SUCCESS":
        return 0, committed.payload
    return 1, committed.payload


def supervise(paths: LoaderPaths = LoaderPaths()) -> tuple[int, dict[str, Any]]:
    require_root()
    supervisor_entry_ns = time.monotonic_ns()
    boot_id = read_boot_id(paths.boot_id_path)
    identity = EvidenceIdentity(
        EVIDENCE_REVIEW_ID,
        EVIDENCE_PACKAGE_ID,
        boot_id,
        new_attempt_id(boot_id, supervisor_entry_ns),
    )
    paths.run_root.mkdir(parents=True, exist_ok=True)
    paths.boot_log_root.mkdir(parents=True, exist_ok=True)
    clock_status = clock_synchronization_status(paths.clock_synchronized_path)
    ledger = PhaseLedger(paths.phase_root(boot_id, identity.attempt_id), identity, clock_status)
    arbiter = TerminalArbiter(paths.terminal_result(boot_id), identity)
    latch = SignalLatch()
    previous_handlers = {
        signal.SIGTERM: signal.signal(signal.SIGTERM, latch.handler),
        signal.SIGINT: signal.signal(signal.SIGINT, latch.handler),
    }
    try:
        with phase_transition(ledger, "supervisor_entry"):
            pass
        attempt_ns = time.monotonic_ns()
        attempt_utc = utc_now()
        try:
            with phase_transition(ledger, "attempt_commit"):
                create_attempt_marker(
                    paths,
                    boot_id,
                    identity.attempt_id,
                    attempt_utc,
                    attempt_ns / 1_000_000_000,
                    attempt_ns,
                )
        except Exception as exc:
            return _finalize_bootstrap_failure(
                identity=identity,
                paths=paths,
                ledger=ledger,
                arbiter=arbiter,
                supervisor_entry_monotonic_ns=supervisor_entry_ns,
                terminal_result=terminal_result_class(exc),
                terminal_state=getattr(exc, "classification", "ATTEMPT_COMMIT_FAILED"),
                error=f"{type(exc).__name__}: {exc}",
                clock_ns=time.monotonic_ns,
            )

        command = [
            sys.executable,
            "-B",
            str(Path(__file__).resolve()),
            "--worker",
            "--boot-id",
            boot_id,
            "--attempt-id",
            identity.attempt_id,
            "--python-entry-monotonic-ns",
            "{python_entry_monotonic_ns}",
        ]
        return supervise_child(
            command=command,
            paths=paths,
            identity=identity,
            ledger=ledger,
            arbiter=arbiter,
            latch=latch,
            service_entry_monotonic_ns=supervisor_entry_ns,
        )
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--supervise", action="store_true")
    mode.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--boot-id", help=argparse.SUPPRESS)
    parser.add_argument("--attempt-id", help=argparse.SUPPRESS)
    parser.add_argument("--python-entry-monotonic-ns", type=int, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def worker_main(args: argparse.Namespace) -> int:
    if (
        not args.boot_id
        or not args.attempt_id
        or args.python_entry_monotonic_ns is None
    ):
        raise BootLoadError("worker identity arguments missing", "WORKER_IDENTITY_MISSING")
    identity = EvidenceIdentity(
        EVIDENCE_REVIEW_ID,
        EVIDENCE_PACKAGE_ID,
        str(args.boot_id),
        str(args.attempt_id),
    )
    paths = LoaderPaths()
    emitter = PhaseStreamEmitter(
        sys.stdout.buffer,
        identity,
        clock_synchronization_status(paths.clock_synchronized_path),
    )
    exit_code, _ = _run_boot_attempt(
        paths=paths,
        identity=identity,
        emitter=emitter,
        terminal_candidate_sink=emitter.emit_terminal_candidate,
        attempt_precommitted=True,
        python_entry_preentered_ns=int(args.python_entry_monotonic_ns),
    )
    return exit_code


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.worker:
        return worker_main(args)
    exit_code, result = supervise()
    print(json.dumps(result, indent=2, sort_keys=True))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
