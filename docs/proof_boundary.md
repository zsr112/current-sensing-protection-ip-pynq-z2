# Proof Boundary

## Proved

- Ten canonical RTL/SystemVerilog simulations pass in the validated Icarus environment.
- The deploy release is internally self-verifying and preserves the accepted BIT/HWH identities.
- Stage 1G proves one real PYNQ-Z2 cold boot autoload, Overlay load, discovery, read-only MMIO/GPIO checks, one worker, one attempt, and no retry.
- The four persistent deploy runtime files match the board-validated payload byte for byte.
- Accepted RERUN02 proves the bounded low-voltage internal digital CH1-only, CH2-only, and differential fault
  responses; live-fault clear rejection; source-removal latch/code retention; clear recovery; internal PWM
  shutdown; post-recovery PWM pass-through; final state restoration; and an 8/8 ILA capture set.

## Not Proved

Stage 1G does not prove repeated cold boots, power-cycle behavior, or soak. The later functional closeout
proves only PYNQ-Z2 low-voltage internal digital fault/clear/recovery behavior and the accepted ILA evidence
loop. `sample_valid` was fixed low, so sensor-health behavior is not proved.

This validation does not represent a pass for a real power stage, external drive chain, load, thermal
behavior, EMI, or production safety. It also does not prove external ADC/AFE, calibrated current,
external-pin PWM, gate-driver behavior, motor behavior, electrical safety, production reliability, a new
Vivado implementation or artifact pair, or system/aviation certification.

Not proved means outside the evidence boundary; it does not mean failed.
