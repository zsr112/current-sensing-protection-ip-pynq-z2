#!/usr/bin/env python3
"""Shared Stage2I C1/C2 package, Overlay, ABI, and B2 control helpers."""

from __future__ import annotations

import hashlib
import json
import re
import time
import xml.etree.ElementTree as ET
from dataclasses import asdict
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

try:
    from sw.generated.protection_register_map import RegisterOffset
    from sw.protection_ip_interface import (
        read_capabilities,
        read_fault_seen_bitmap,
        read_first_fault_bitmap,
        read_live_fault_bitmap,
        read_observability,
        read_policy_evaluation_identity,
        read_policy_status,
        read_register_map_version,
        read_status,
    )
except ModuleNotFoundError:  # Board package layout places dependencies beside this file.
    from generated.protection_register_map import RegisterOffset  # type: ignore
    from protection_ip_interface import (  # type: ignore
        read_capabilities,
        read_fault_seen_bitmap,
        read_first_fault_bitmap,
        read_live_fault_bitmap,
        read_observability,
        read_policy_evaluation_identity,
        read_policy_status,
        read_register_map_version,
        read_status,
    )


PROFILE_SCHEMA = "stage2i-board-execution-profile-v1"
SAFE_INERT = "SAFE_INERT"
READY_AWARE = "READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS"
SUPPORTED_PROFILES = (SAFE_INERT, READY_AWARE)
PROFILE_FILENAME = "stage2i_board_profile.json"
PROTECTION_IP = "protection_ip_axi_lite_0"
GPIO_IP = "axi_gpio_stage1d_0"
EXPECTED_IP = {
    GPIO_IP: {"phys_addr": 0x41200000, "addr_range": 0x10000},
    PROTECTION_IP: {"phys_addr": 0x43C00000, "addr_range": 0x1000},
}
ARTIFACT_CONTRACT = {
    "bit": ("BITSTREAM", "artifacts/protection_system.bit", "PACKAGE_REQUIRED"),
    "hwh": ("HWH", "artifacts/protection_system.hwh", "PACKAGE_REQUIRED"),
    "ltx": ("LTX", "artifacts/protection_system.ltx", "PACKAGE_REQUIRED"),
    "xsa": ("XSA", None, "PROVENANCE_ONLY_REQUIRED"),
}
SAFE_INERT_DESTINATION_PROBES = {
    0: (1, "aresetn"),
    1: (1, "adc_sample_valid"),
    2: (12, "adc_sample_ch1"),
    3: (12, "adc_sample_ch2"),
    4: (1, "pwm_raw"),
    5: (1, "pwm_out"),
    6: (1, "fault_valid"),
    7: (1, "fault_latched"),
    8: (8, "fault_code"),
    9: (8, "fault_code_latched"),
    10: (4, "fsm_state"),
    11: (1, "adc_sample_ready"),
}
READY_AWARE_DESTINATION_PROBES = {
    0: (1, "aresetn"),
    1: (1, "pwm_raw"),
    2: (1, "pwm_out"),
    3: (1, "fault_valid"),
    4: (1, "fault_latched"),
    5: (8, "fault_code"),
    6: (8, "fault_code_latched"),
    7: (4, "fsm_state"),
}
# Historical callers use this name for the SAFE_INERT production map.
DESTINATION_PROBES = SAFE_INERT_DESTINATION_PROBES
SOURCE_PROBES = {
    0: (1, "adc_sample_valid"),
    1: (1, "adc_sample_ready"),
    2: (12, "adc_sample_ch1"),
    3: (12, "adc_sample_ch2"),
    4: (1, "producer_active"),
    5: (7, "producer_remaining"),
    6: (1, "producer_accept"),
    7: (1, "command_pending"),
}
DESTINATION_CORE_SUFFIX = "system_ila_stage2b_0/inst/ila_lib"
SOURCE_CORE_SUFFIX = "system_ila_stage2i_b2_source_0/inst/ila_lib"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9._:+-]{1,160}$")

GPIO_DATA = 0x0
GPIO_TRI = 0x4
GPIO2_DATA = 0x8
GPIO2_TRI = 0xC
B2_STATUS_MARKER = 0xB2
B2_MAX_BURST = 127


class Stage2IBoardError(RuntimeError):
    """A Stage2I board package or runtime condition failed closed."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _reject_duplicate_keys(pairs: Iterable[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise Stage2IBoardError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=lambda value: (_ for _ in ()).throw(
                Stage2IBoardError(f"non-finite JSON value: {value}")
            ),
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Stage2IBoardError(f"invalid JSON {path}: {exc}") from exc


def _exact_dict(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise Stage2IBoardError(f"{label} fields differ")
    return value


def _safe_relative(value: Any, label: str) -> str:
    text = str(value)
    path = PurePosixPath(text)
    if (
        not text
        or "\\" in text
        or path.is_absolute()
        or any(part in {"", ".", ".."} for part in path.parts)
    ):
        raise Stage2IBoardError(f"unsafe {label}: {text!r}")
    return path.as_posix()


def debug_core_contract(profile: str) -> dict[str, Any]:
    if profile not in SUPPORTED_PROFILES:
        raise Stage2IBoardError(f"unsupported implementation profile: {profile}")

    def record(suffix: str, probes: dict[int, tuple[int, str]]) -> dict[str, Any]:
        return {
            "cell_name_suffix": suffix,
            "probes": {
                str(index): {"width": width, "signal": signal}
                for index, (width, signal) in probes.items()
            },
        }

    destination_probes = (
        READY_AWARE_DESTINATION_PROBES
        if profile == READY_AWARE
        else SAFE_INERT_DESTINATION_PROBES
    )
    cores = {"destination": record(DESTINATION_CORE_SUFFIX, destination_probes)}
    if profile == READY_AWARE:
        cores["source"] = record(SOURCE_CORE_SUFFIX, SOURCE_PROBES)
    return cores


def control_contract(profile: str) -> dict[str, Any]:
    if profile == SAFE_INERT:
        return {
            "mode": "SAFE_INERT",
            "gpio_control": "UNUSED",
            "source_clock_mhz": 100,
            "destination_clock_mhz": 100,
        }
    if profile == READY_AWARE:
        return {
            "mode": "READY_AWARE_BUNDLED_DATA_REQUEST_ACK",
            "gpio_control": "DUAL_CHANNEL_AXI_GPIO",
            "source_clock_mhz": 125,
            "destination_clock_mhz": 100,
            "maximum_burst_count": B2_MAX_BURST,
            "status_marker": B2_STATUS_MARKER,
            "channel_1_data_offset": GPIO_DATA,
            "channel_1_tri_offset": GPIO_TRI,
            "channel_2_data_offset": GPIO2_DATA,
            "channel_2_tri_offset": GPIO2_TRI,
        }
    raise Stage2IBoardError(f"unsupported implementation profile: {profile}")


def load_profile(package_root: Path, expected_profile: str | None = None) -> dict[str, Any]:
    package_root = package_root.resolve(strict=True)
    profile = _exact_dict(
        load_json(package_root / PROFILE_FILENAME),
        {
            "schema_version",
            "implementation_profile",
            "source_commit",
            "source_tree",
            "execution_id",
            "artifact_manifest",
            "artifacts",
            "expected_ip",
            "debug_cores",
            "control",
            "register_map_abi",
        },
        "board profile",
    )
    if profile["schema_version"] != PROFILE_SCHEMA:
        raise Stage2IBoardError("board profile schema mismatch")
    implementation_profile = str(profile["implementation_profile"])
    if implementation_profile not in SUPPORTED_PROFILES:
        raise Stage2IBoardError("board implementation profile is unsupported")
    if expected_profile is not None and implementation_profile != expected_profile:
        raise Stage2IBoardError("board implementation profile differs from caller")
    if not COMMIT_RE.fullmatch(str(profile["source_commit"])):
        raise Stage2IBoardError("board source commit is invalid")
    if not COMMIT_RE.fullmatch(str(profile["source_tree"])):
        raise Stage2IBoardError("board source tree is invalid")
    if not TOKEN_RE.fullmatch(str(profile["execution_id"])):
        raise Stage2IBoardError("board execution ID is invalid")
    manifest = _exact_dict(
        profile["artifact_manifest"],
        {"package_path", "bytes", "sha256"},
        "artifact manifest",
    )
    manifest_relative = _safe_relative(
        manifest["package_path"], "artifact manifest path"
    )
    if manifest_relative != "provenance/artifact-manifest.tsv":
        raise Stage2IBoardError("artifact manifest package path differs")
    if (
        isinstance(manifest["bytes"], bool)
        or not isinstance(manifest["bytes"], int)
        or manifest["bytes"] <= 0
        or not SHA256_RE.fullmatch(str(manifest["sha256"]))
    ):
        raise Stage2IBoardError("artifact manifest identity is invalid")
    manifest_path = package_root / Path(manifest_relative)
    if (
        not manifest_path.is_file()
        or manifest_path.stat().st_size != manifest["bytes"]
        or sha256_file(manifest_path) != manifest["sha256"]
    ):
        raise Stage2IBoardError("packaged artifact manifest identity mismatch")
    if profile["expected_ip"] != EXPECTED_IP:
        raise Stage2IBoardError("board expected IP/address map differs")
    if profile["debug_cores"] != debug_core_contract(implementation_profile):
        raise Stage2IBoardError("board debug-core contract differs")
    if profile["control"] != control_contract(implementation_profile):
        raise Stage2IBoardError("board control contract differs")
    abi = _exact_dict(
        profile["register_map_abi"],
        {"major", "minor", "schema_version", "canonical_sha256"},
        "register-map ABI",
    )
    if abi["major"] != 1 or abi["minor"] != 1 or abi["schema_version"] != "1.1.0":
        raise Stage2IBoardError("board package is not bound to ABI 1.1")
    if not SHA256_RE.fullmatch(str(abi["canonical_sha256"])):
        raise Stage2IBoardError("register-map canonical identity is invalid")

    artifacts = _exact_dict(profile["artifacts"], set(ARTIFACT_CONTRACT), "artifacts")
    for key, (role, expected_path, policy) in ARTIFACT_CONTRACT.items():
        record = _exact_dict(
            artifacts[key],
            {"role", "bytes", "sha256", "package_path", "delivery_policy"},
            f"artifact {key}",
        )
        if record["role"] != role or record["delivery_policy"] != policy:
            raise Stage2IBoardError(f"artifact policy mismatch: {key}")
        if isinstance(record["bytes"], bool) or not isinstance(record["bytes"], int) or record["bytes"] <= 0:
            raise Stage2IBoardError(f"artifact size is invalid: {key}")
        if not SHA256_RE.fullmatch(str(record["sha256"])):
            raise Stage2IBoardError(f"artifact identity is invalid: {key}")
        if expected_path is None:
            if record["package_path"] is not None:
                raise Stage2IBoardError(f"provenance-only artifact is packaged: {key}")
            continue
        relative = _safe_relative(record["package_path"], f"artifact path: {key}")
        if relative != expected_path:
            raise Stage2IBoardError(f"artifact package path mismatch: {key}")
        path = package_root / Path(relative)
        if not path.is_file():
            raise Stage2IBoardError(f"packaged artifact is missing: {key}")
        if path.stat().st_size != record["bytes"] or sha256_file(path) != record["sha256"]:
            raise Stage2IBoardError(f"packaged artifact identity mismatch: {key}")
    return profile


def validate_hwh(path: Path, profile: dict[str, Any]) -> dict[str, Any]:
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError) as exc:
        raise Stage2IBoardError(f"cannot parse HWH: {exc}") from exc
    modules = {
        str(module.get("INSTANCE"))
        for module in root.iter("MODULE")
        if module.get("INSTANCE")
    }
    required = set(EXPECTED_IP)
    if profile["implementation_profile"] == READY_AWARE:
        required.add("stage2i_b2_ready_aware_stimulus_0")
    missing = sorted(required - modules)
    if missing:
        raise Stage2IBoardError(f"HWH expected modules are missing: {missing}")
    if (
        profile["implementation_profile"] == SAFE_INERT
        and "stage2i_b2_ready_aware_stimulus_0" in modules
    ):
        raise Stage2IBoardError("B2 test producer leaked into SAFE_INERT HWH")
    ranges: dict[str, dict[str, int]] = {}
    for item in root.iter("MEMRANGE"):
        instance = item.get("INSTANCE")
        if instance not in EXPECTED_IP:
            continue
        try:
            base = int(str(item.get("BASEVALUE")), 0)
            high = int(str(item.get("HIGHVALUE")), 0)
        except ValueError as exc:
            raise Stage2IBoardError(f"invalid HWH address metadata: {instance}") from exc
        ranges[str(instance)] = {"phys_addr": base, "addr_range": high - base + 1}
    if ranges != profile["expected_ip"]:
        raise Stage2IBoardError(f"HWH address metadata differs: {ranges}")
    return {"modules": sorted(modules), "address_map": ranges}


def _core_name_matches(actual: str, suffix: str) -> bool:
    return actual.strip("/").split("/")[-len(suffix.strip("/").split("/")) :] == suffix.strip("/").split("/")


def _ltx_ila_cores(payload: Any) -> list[dict[str, Any]]:
    try:
        datasets = payload["ltx_root"]["ltx_data"]
    except (KeyError, TypeError) as exc:
        raise Stage2IBoardError("LTX root structure differs") from exc
    cores: list[dict[str, Any]] = []
    for dataset in datasets:
        if not isinstance(dataset, dict):
            continue
        for core in dataset.get("debug_cores", []):
            if isinstance(core, dict) and str(core.get("type", "")).startswith("ILA"):
                cores.append(core)
    return cores


def _ltx_pin_width(pin: dict[str, Any], label: str) -> int:
    try:
        if bool(pin.get("isVector")):
            return abs(int(pin["leftIndex"]) - int(pin["rightIndex"])) + 1
        return 1
    except (KeyError, TypeError, ValueError) as exc:
        raise Stage2IBoardError(f"LTX {label} pin width is invalid") from exc


def _ltx_native_probe_map(core: dict[str, Any], role: str) -> dict[str, dict[str, int]]:
    native_ports = core.get("native_ports")
    pins = core.get("pins")
    if not isinstance(native_ports, list) or not isinstance(pins, list):
        raise Stage2IBoardError(f"LTX {role} native probe structure differs")

    pins_by_id: dict[int, dict[str, Any]] = {}
    for pin in pins:
        if not isinstance(pin, dict) or "id" not in pin:
            continue
        try:
            pin_id = int(pin["id"])
        except (TypeError, ValueError) as exc:
            raise Stage2IBoardError(f"LTX {role} pin identity is invalid") from exc
        if pin_id in pins_by_id:
            raise Stage2IBoardError(f"LTX {role} pin identity is duplicated")
        pins_by_id[pin_id] = pin

    probes: dict[str, dict[str, int]] = {}
    used_pin_ids: set[int] = set()
    for port in native_ports:
        if not isinstance(port, dict):
            raise Stage2IBoardError(f"LTX {role} native port is not a probe")
        if "protocol" in port and port["protocol"] != "PROBE":
            raise Stage2IBoardError(f"LTX {role} native port is not a probe")
        name = str(port.get("name", ""))
        match = re.fullmatch(r"probe(0|[1-9][0-9]*)", name)
        maps = port.get("port_maps")
        if match is None or not isinstance(maps, list) or len(maps) != 1:
            raise Stage2IBoardError(f"LTX {role} native probe mapping differs")
        mapping = maps[0]
        if not isinstance(mapping, dict) or mapping.get("logical_port") != name:
            raise Stage2IBoardError(f"LTX {role} native logical port differs")
        physical = mapping.get("physical_pin")
        if not isinstance(physical, dict) or str(physical.get("name", "")) != name:
            raise Stage2IBoardError(f"LTX {role} native physical pin differs")
        try:
            pin_id = int(physical["id"])
            width = int(physical["width"])
            left_bit = int(physical["leftBit"])
        except (KeyError, TypeError, ValueError) as exc:
            raise Stage2IBoardError(f"LTX {role} native physical pin is invalid") from exc
        if width <= 0 or left_bit < 0 or pin_id in used_pin_ids:
            raise Stage2IBoardError(f"LTX {role} native physical pin is invalid")
        actual_pin = pins_by_id.get(pin_id)
        if (
            actual_pin is None
            or str(actual_pin.get("name", "")) != name
            or _ltx_pin_width(actual_pin, role) != width
        ):
            raise Stage2IBoardError(f"LTX {role} native pin cross-check differs")
        index = match.group(1)
        if index in probes:
            raise Stage2IBoardError(f"LTX {role} native probe index is duplicated")
        probes[index] = {"width": width}
        used_pin_ids.add(pin_id)
    return probes


def validate_ltx(path: Path, profile: dict[str, Any]) -> dict[str, Any]:
    payload = load_json(path)
    cores = _ltx_ila_cores(payload)
    expected = profile["debug_cores"]
    if len(cores) != len(expected):
        raise Stage2IBoardError(
            f"LTX ILA core count differs: {len(cores)} != {len(expected)}"
        )
    observed: dict[str, Any] = {}
    for role, contract in expected.items():
        matches = [
            core
            for core in cores
            if _core_name_matches(str(core.get("name", "")), contract["cell_name_suffix"])
        ]
        if len(matches) != 1:
            raise Stage2IBoardError(f"LTX {role} core identity is not singular")
        core = matches[0]
        probes = _ltx_native_probe_map(core, role)
        expected_widths = {
            index: {"width": record["width"]}
            for index, record in contract["probes"].items()
        }
        if probes != expected_widths:
            raise Stage2IBoardError(f"LTX {role} probe map differs: {probes}")
        observed[role] = {
            "name": core["name"],
            "uuid": core.get("uuid"),
            "probe_count": len(probes),
            "probes": probes,
        }
    return observed


def validate_package(
    package_root: Path, expected_profile: str | None = None
) -> dict[str, Any]:
    package_root = package_root.resolve(strict=True)
    profile = load_profile(package_root, expected_profile=expected_profile)
    hwh = validate_hwh(package_root / ARTIFACT_CONTRACT["hwh"][1], profile)
    ltx = validate_ltx(package_root / ARTIFACT_CONTRACT["ltx"][1], profile)
    return {
        "status": "PASS_OFFLINE",
        "implementation_profile": profile["implementation_profile"],
        "source_commit": profile["source_commit"],
        "source_tree": profile["source_tree"],
        "execution_id": profile["execution_id"],
        "hwh": hwh,
        "ltx": ltx,
        "board_hardware_execution": "NOT_RUN",
    }


def resolve_overlay_ip(overlay: Any, name: str, expected: dict[str, int]) -> dict[str, int]:
    ip_dict = getattr(overlay, "ip_dict", None)
    if not isinstance(ip_dict, dict):
        raise Stage2IBoardError("Overlay IP metadata is unavailable")
    record = ip_dict.get(name)
    if not isinstance(record, dict):
        raise Stage2IBoardError(f"Overlay IP is missing: {name}")
    try:
        observed = {
            "phys_addr": int(record["phys_addr"]),
            "addr_range": int(record["addr_range"]),
        }
    except (KeyError, TypeError, ValueError) as exc:
        raise Stage2IBoardError(f"Overlay IP metadata is invalid: {name}") from exc
    if observed != expected:
        raise Stage2IBoardError(f"Overlay IP metadata mismatch: {name}: {observed}")
    return observed


def open_overlay_mmio(
    package_root: Path, profile: dict[str, Any]
) -> tuple[Any, Any, Any, str]:
    try:
        import pynq  # type: ignore
        from pynq import MMIO, Overlay  # type: ignore
    except Exception as exc:
        raise Stage2IBoardError(f"PYNQ runtime import failed: {exc}") from exc
    bit_path = package_root / ARTIFACT_CONTRACT["bit"][1]
    overlay = Overlay(str(bit_path), download=True)
    checker = getattr(overlay, "is_loaded", None)
    if checker is None or not bool(checker()):
        raise Stage2IBoardError("Overlay did not confirm the requested Stage2I BIT")
    protection = resolve_overlay_ip(overlay, PROTECTION_IP, EXPECTED_IP[PROTECTION_IP])
    gpio = resolve_overlay_ip(overlay, GPIO_IP, EXPECTED_IP[GPIO_IP])
    return (
        overlay,
        MMIO(protection["phys_addr"], protection["addr_range"]),
        MMIO(gpio["phys_addr"], gpio["addr_range"]),
        getattr(pynq, "__version__", "UNKNOWN"),
    )


def read_current_state(mmio: Any) -> dict[str, Any]:
    version = read_register_map_version(mmio)
    if not version.explicit or (version.major, version.minor) != (1, 1):
        raise Stage2IBoardError("live protection IP is not explicit ABI 1.1")
    capabilities = read_capabilities(mmio)
    status = read_status(mmio)
    observability = read_observability(mmio)
    policy = read_policy_status(mmio)
    first = read_first_fault_bitmap(mmio)
    live = read_live_fault_bitmap(mmio)
    seen = read_fault_seen_bitmap(mmio)
    sequence = read_policy_evaluation_identity(mmio)
    return {
        "register_map_version": asdict(version),
        "capabilities": {
            key: (value.value if hasattr(value, "value") else value)
            for key, value in asdict(capabilities).items()
        },
        "status": asdict(status),
        "observability": asdict(observability),
        "policy_status": asdict(policy),
        "first_fault_bitmap": {
            "raw_value": first.raw_value,
            "known_flags": int(first.known_flags),
            "unknown_mask": first.unknown_mask,
            "advertised_width": first.advertised_width,
        },
        "live_fault_bitmap": {
            "raw_value": live.raw_value,
            "known_flags": int(live.known_flags),
            "unknown_mask": live.unknown_mask,
            "advertised_width": live.advertised_width,
        },
        "fault_seen_bitmap": {
            "raw_value": seen.raw_value,
            "known_flags": int(seen.known_flags),
            "unknown_mask": seen.unknown_mask,
            "advertised_width": seen.advertised_width,
        },
        "policy_evaluation_sequence": int(sequence),
    }


def read_all_registers(mmio: Any) -> dict[str, int]:
    return {register.name: int(mmio.read(int(register))) for register in RegisterOffset}


def encode_b2_command(ch1: int, ch2: int, burst_count: int, epoch: int) -> int:
    if not (0 <= ch1 <= 0xFFF and 0 <= ch2 <= 0xFFF):
        raise Stage2IBoardError("B2 sample values must be unsigned 12-bit values")
    if not (0 <= burst_count <= B2_MAX_BURST):
        raise Stage2IBoardError("B2 burst count is outside 0..127")
    if epoch not in {0, 1}:
        raise Stage2IBoardError("B2 command epoch must be 0 or 1")
    return ch1 | (ch2 << 12) | (burst_count << 24) | (epoch << 31)


def decode_b2_status(value: int) -> dict[str, Any]:
    value = int(value) & 0xFFFFFFFF
    return {
        "raw": value,
        "profile_marker": (value >> 24) & 0xFF,
        "accepted_count": (value >> 11) & 0xFF,
        "remaining": (value >> 4) & 0x7F,
        "overwrite_error": bool(value & (1 << 3)),
        "request_pending": bool(value & (1 << 2)),
        "active": bool(value & (1 << 1)),
        "ack_epoch": value & 1,
    }


def read_b2_status(gpio_mmio: Any) -> dict[str, Any]:
    status = decode_b2_status(gpio_mmio.read(GPIO2_DATA))
    if status["profile_marker"] != B2_STATUS_MARKER:
        raise Stage2IBoardError(
            f"B2 GPIO status marker mismatch: {status['profile_marker']:#x}"
        )
    if status["overwrite_error"]:
        raise Stage2IBoardError("B2 producer reports a command overwrite error")
    return status


def issue_b2_command(
    gpio_mmio: Any, ch1: int, ch2: int, burst_count: int
) -> dict[str, Any]:
    before = read_b2_status(gpio_mmio)
    if before["request_pending"] or before["active"]:
        raise Stage2IBoardError("B2 producer is not idle before command issue")
    epoch = before["ack_epoch"] ^ 1
    word = encode_b2_command(ch1, ch2, burst_count, epoch)
    gpio_mmio.write(GPIO_TRI, 0)
    gpio_mmio.write(GPIO_DATA, word)
    return {"control_word": word, "epoch": epoch, "status_before": before}


def wait_b2_idle(
    gpio_mmio: Any, epoch: int, timeout_seconds: float = 5.0, poll_seconds: float = 0.001
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    last: dict[str, Any] | None = None
    while time.monotonic() < deadline:
        last = read_b2_status(gpio_mmio)
        if (
            last["ack_epoch"] == epoch
            and not last["request_pending"]
            and not last["active"]
            and last["remaining"] == 0
        ):
            return last
        time.sleep(poll_seconds)
    raise Stage2IBoardError(f"B2 producer did not return idle: {last}")
