#!/usr/bin/env python3
"""Read defined protection registers without writing or loading an Overlay."""
import argparse
import json
from pynq import MMIO

REGISTERS = {
    "CTRL": 0x00, "STATUS": 0x04, "FAULT_CODE": 0x08,
    "I_CH1": 0x0C, "I_CH2": 0x10, "TH_OC1": 0x14,
    "TH_OC2": 0x18, "TH_DIFF": 0x1C, "PWM_PERIOD": 0x20,
    "PWM_DUTY": 0x24,
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base-address", type=lambda value: int(value, 0), default=0x43C00000)
args = parser.parse_args()
mmio = MMIO(args.base_address, 0x1000)
print(json.dumps({name: f"0x{mmio.read(offset):08X}" for name, offset in REGISTERS.items()}, indent=2))
