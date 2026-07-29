# Proof Boundary

## Proved

- Ten canonical RTL/SystemVerilog simulations pass in the validated Icarus environment.
- The deploy release is internally self-verifying and preserves the accepted BIT/HWH identities.
- Stage 1G proves one real PYNQ-Z2 cold boot autoload, Overlay load, discovery, read-only MMIO/GPIO checks, one worker, one attempt, and no retry.
- The four persistent deploy runtime files match the board-validated payload byte for byte.

## Not Proved

This evidence does not prove repeated cold boots, power-cycle behavior, soak, power-stage load, board fault injection or board clear/recovery, EMI, thermal behavior, electrical safety, a new Vivado implementation, a new BIT/HWH pair, or whole-board validation of the later development closeout commit.

Not proved means outside the evidence boundary; it does not mean failed.
