#!/usr/bin/env python3
"""Read the current ABI 1.1 status without loading an Overlay or writing MMIO."""
import argparse
import json
import sys
from pathlib import Path

from pynq import MMIO

RUNTIME_ROOT = Path(__file__).resolve().parents[1] / "pynq" / "runtime"
sys.path.insert(0, str(RUNTIME_ROOT))

from protection_ip_interface import (  # noqa: E402
    read_capabilities,
    read_observability,
    read_policy_status,
    read_register_map_version,
    read_status,
)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base-address", type=lambda value: int(value, 0), default=0x43C00000)
args = parser.parse_args()
mmio = MMIO(args.base_address, 0x1000)
version = read_register_map_version(mmio)
capabilities = read_capabilities(mmio)
status = read_status(mmio)
policy = read_policy_status(mmio)
observability = read_observability(mmio)
print(json.dumps({
    "register_map_version": {"raw": version.raw_value, "major": version.major, "minor": version.minor},
    "capabilities": {
        "raw_capabilities_0": capabilities.raw_capabilities_0,
        "raw_capabilities_1": capabilities.raw_capabilities_1,
    },
    "status": {"ctrl": status.ctrl, "status": status.status, "fault_code": status.fault_code},
    "policy_status": policy.raw_value,
    "observability": {
        "source_accept_count": observability.source_accept_count,
        "destination_delivery_count": observability.destination_delivery_count,
        "backpressure_cycle_count": observability.backpressure_cycle_count,
    },
}, indent=2, sort_keys=True))
