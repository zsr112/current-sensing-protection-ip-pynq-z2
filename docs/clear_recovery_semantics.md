# Clear and Recovery Semantics

Live fault prevents false recovery. Clear is a recovery request, not an unconditional unlock. Fault removal and clear are separate actions. Clear-only does not automatically enable PWM.

## Safe Software Sequence

1. Observe the fault state and keep PWM disabled.
2. Obtain external confirmation that the physical input condition is safe.
3. Write CTRL value 0x2 exactly once to request clear while PWM stays disabled.
4. Poll with a finite bound until STATUS is 0, FAULT_CODE is 0, and CTRL bit 0 remains 0.
5. Enable PWM separately with CTRL value 0x1 only after recovery passes.

CTRL value 0x3 combines clear and enable, so it is not the safe recovery command. STATUS value 0x3 means the live and latched status bits are both set. A persistent fault keeps or re-enters the protected state.

Sensor history belongs to the health-monitor state machine and is not blindly cleared by the software clear request. Clearing the first-fault latch does not erase arbitrary detector history.
