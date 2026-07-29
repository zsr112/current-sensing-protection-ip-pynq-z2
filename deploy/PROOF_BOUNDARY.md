# Proof Boundary

## Proved

- One real PYNQ-Z2 cold-boot autoload.
- Overlay and device discovery.
- Read-only MMIO/GPIO checks.
- One worker and one attempt.
- No retry.

## Not Proved

- Repeated cold boots, power-cycle or soak.
- Power-stage load.
- Board fault injection, clear or recovery.
- EMI, thermal or electrical safety.
- A new Vivado implementation.
- A new BIT or HWH.

Not proved does not mean failed. Release management and self-validation tools are offline-reviewed utilities;
they do not extend the archived board proof.
