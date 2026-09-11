from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
from typing import Any

from sw import stage2i_board_runtime as board_runtime
from tools import build_current_release as builder
from tools import stage2i_physical_authority as physical_authority


SOURCE_COMMIT = "1" * 40
SOURCE_TREE = "2" * 40
ENGINEERING_COMMIT = "3" * 40
EXECUTION_ID = "B1-TEST-EXECUTION"
REQUEST_IDENTITY = "4" * 64
PROJECT_IDENTITY = "s1e_444444444444"
DESIGN_IDENTITY = "protection_system"


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def minimal_hwh(profile: str = physical_authority.PRODUCTION_PROFILE) -> bytes:
    modules = [
        '<MODULE INSTANCE="axi_gpio_stage1d_0"/>',
        '<MODULE INSTANCE="protection_ip_axi_lite_0"/>',
    ]
    if profile == physical_authority.BOARD_TEST_PROFILE:
        modules.append('<MODULE INSTANCE="stage2i_b2_ready_aware_stimulus_0"/>')
    module_text = "\n  ".join(modules)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<SYSTEM>
  {module_text}
  <MEMRANGE INSTANCE="axi_gpio_stage1d_0" BASEVALUE="0x41200000" HIGHVALUE="0x4120FFFF"/>
  <MEMRANGE INSTANCE="protection_ip_axi_lite_0" BASEVALUE="0x43C00000" HIGHVALUE="0x43C00FFF"/>
</SYSTEM>
""".encode("utf-8")


def minimal_ltx(profile: str) -> bytes:
    cores = []
    next_pin_id = 0
    for role, contract in board_runtime.debug_core_contract(profile).items():
        pins = []
        native_ports = []
        for raw_index, probe in contract["probes"].items():
            width = int(probe["width"])
            name = f"probe{raw_index}"
            pin_id = next_pin_id
            next_pin_id += 1
            pin = {
                "id": pin_id,
                "name": name,
                "portIndex": int(raw_index),
                "isVector": width > 1,
            }
            if width > 1:
                pin.update({"leftIndex": width - 1, "rightIndex": 0})
            pins.append(pin)
            native_port = {
                "name": name,
                "protocol": "PROBE",
                "port_maps": [
                    {
                        "logical_port": name,
                        "physical_pin": {
                            "id": pin_id,
                            "name": name,
                            "leftBit": 0,
                            "width": width,
                        },
                    }
                ],
            }
            if (
                profile == physical_authority.PRODUCTION_PROFILE
                and role == "destination"
                and str(raw_index) == "1"
            ):
                del native_port["protocol"]
            native_ports.append(native_port)
        bus_interfaces = []
        if role == "destination":
            interface_id = next_pin_id
            next_pin_id += 1
            pins.append(
                {
                    "id": interface_id,
                    "name": f"probe{len(pins)}",
                    "portIndex": len(pins),
                    "isVector": True,
                    "leftIndex": 0,
                    "rightIndex": 1,
                }
            )
            bus_interfaces.append(
                {
                    "name": "SLOT_0_AXI",
                    "protocol": "AXI4LITE",
                    "port_maps": [
                        {
                            "logical_port": "ARVALID",
                            "physical_pin": {
                                "id": interface_id,
                                "name": f"probe{len(pins) - 1}",
                                "leftBit": 0,
                                "width": 1,
                            },
                        }
                    ],
                }
            )
        cores.append(
            {
                "type": "ILA_V3",
                "name": "protection_system_i/" + contract["cell_name_suffix"],
                "uuid": f"stage2i-{role}-fixture",
                "pins": pins,
                "native_ports": native_ports,
                "bus_interfaces": bus_interfaces,
            }
        )
    payload = {"ltx_root": {"ltx_data": [{"debug_cores": cores}]}}
    return (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode("utf-8")


def write_artifact_manifest_fixture(
    root: Path,
    profile: str,
    *,
    source_commit: str = SOURCE_COMMIT,
    source_tree: str = SOURCE_TREE,
) -> dict[str, Any]:
    root.mkdir(parents=True, exist_ok=True)
    payloads = {
        "bit": f"stage2i-{profile}-test-bit".encode("ascii"),
        "hwh": minimal_hwh(profile),
        "ltx": minimal_ltx(profile),
        "xsa": f"stage2i-{profile}-test-xsa".encode("ascii"),
    }
    filenames = {
        "bit": "protection_system.bit",
        "hwh": "protection_system.hwh",
        "ltx": "protection_system.ltx",
        "xsa": "protection_system.xsa",
    }
    artifacts: dict[str, dict[str, Any]] = {}
    for key, payload in payloads.items():
        path = root / filenames[key]
        path.write_bytes(payload)
        artifacts[key] = {
            "role": physical_authority.ARTIFACT_ROLES[key],
            "path": str(path.resolve()),
            "bytes": len(payload),
            "sha256": sha256_bytes(payload),
        }

    manifest_path = root / "artifact-manifest.tsv"
    with manifest_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, dialect="excel-tab", lineterminator="\n")
        writer.writerow(physical_authority.MANIFEST_HEADER)
        for key in ("bit", "xsa", "hwh", "ltx"):
            artifact = artifacts[key]
            writer.writerow(
                [
                    "artifact",
                    artifact["role"],
                    artifact["path"],
                    artifact["bytes"],
                    artifact["sha256"],
                    profile,
                    EXECUTION_ID,
                    source_commit,
                    source_tree,
                    PROJECT_IDENTITY,
                    DESIGN_IDENTITY,
                ]
            )
    return {
        "manifest_path": manifest_path,
        "artifact_paths": {
            key: Path(record["path"]) for key, record in artifacts.items()
        },
    }


def write_physical_fixture(root: Path) -> dict[str, Any]:
    root.mkdir(parents=True, exist_ok=True)
    payloads = {
        "bit": b"stage2i-test-bit",
        "hwh": minimal_hwh(),
        "ltx": b"stage2i-test-ltx",
        "xsa": b"stage2i-test-xsa",
    }
    filenames = {
        "bit": "protection_system.bit",
        "hwh": "protection_system.hwh",
        "ltx": "protection_system.ltx",
        "xsa": "protection_system.xsa",
    }
    roles = {"bit": "BITSTREAM", "hwh": "HWH", "ltx": "LTX", "xsa": "XSA"}
    artifacts: dict[str, dict[str, Any]] = {}
    for key, payload in payloads.items():
        path = root / filenames[key]
        path.write_bytes(payload)
        artifacts[key] = {
            "role": roles[key],
            "path": str(path.resolve()),
            "bytes": len(payload),
            "sha256": sha256_bytes(payload),
            "delivery_policy": physical_authority.DELIVERY_POLICIES[key],
        }

    manifest_path = root / "artifact-manifest.tsv"
    with manifest_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, dialect="excel-tab", lineterminator="\n")
        writer.writerow(physical_authority.MANIFEST_HEADER)
        for key in ("bit", "xsa", "hwh", "ltx"):
            artifact = artifacts[key]
            writer.writerow(
                [
                    "artifact",
                    artifact["role"],
                    artifact["path"],
                    artifact["bytes"],
                    artifact["sha256"],
                    physical_authority.PRODUCTION_PROFILE,
                    EXECUTION_ID,
                    SOURCE_COMMIT,
                    SOURCE_TREE,
                    PROJECT_IDENTITY,
                    DESIGN_IDENTITY,
                ]
            )
    manifest_payload = manifest_path.read_bytes()
    receipt = {
        "schema_version": physical_authority.SCHEMA_VERSION,
        "authority_state": physical_authority.AUTHORITY_STATE,
        "implementation_profile": physical_authority.PRODUCTION_PROFILE,
        "source_commit": SOURCE_COMMIT,
        "source_tree": SOURCE_TREE,
        "execution_id": EXECUTION_ID,
        "request_identity": REQUEST_IDENTITY,
        "artifact_manifest": {
            "path": str(manifest_path.resolve()),
            "bytes": len(manifest_payload),
            "sha256": sha256_bytes(manifest_payload),
        },
        "artifacts": artifacts,
    }
    receipt_path = root / "physical-authority.json"
    receipt_path.write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return {
        "receipt_path": receipt_path,
        "receipt": receipt,
        "manifest_path": manifest_path,
        "artifact_paths": {
            key: Path(record["path"]) for key, record in artifacts.items()
        },
    }


def build_test_release(root: Path, repo_root: Path) -> tuple[Path, dict[str, Any]]:
    fixture = write_physical_fixture(root / "physical")
    authority = physical_authority.load_physical_authority(
        fixture["receipt_path"], expected_tree=SOURCE_TREE
    )
    release_root = root / "release"
    release_root.mkdir()
    builder.write_release_tree(
        release_root,
        repo_root,
        ENGINEERING_COMMIT,
        SOURCE_TREE,
        "2026-08-09T00:00:00Z",
        authority,
    )
    return release_root, fixture
