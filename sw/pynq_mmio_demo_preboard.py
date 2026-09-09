# Pre-board draft. Not validated on PYNQ-Z2 hardware yet.
#
# PYNQ MMIO draft for the current protection IP register map.
# This script has not been run on PYNQ-Z2 and contains no hardware evidence.

# Local interface module: this script and protection_ip_interface.py are expected
# to remain in the same directory. This is intentionally not a package structure yet.
import protection_ip_interface as protection

BITSTREAM = "current_protection.bit"  # Replace after real Vivado export.
BASE_ADDR = 0x43C00000  # Placeholder only; confirm in Vivado Address Editor.
ADDR_RANGE = 0x1000


def main():
    from pynq import MMIO, Overlay

    overlay = Overlay(BITSTREAM)
    _ = overlay  # Keep reference so the overlay remains loaded.
    mmio = MMIO(BASE_ADDR, ADDR_RANGE)
    protection.apply_demo_configuration(mmio)
    print(protection.read_status(mmio))
    # Source-domain values are eventually consistent and these independent
    # reads are not an atomic multi-register snapshot.
    print(protection.read_observability(mmio))


if __name__ == "__main__":
    main()
