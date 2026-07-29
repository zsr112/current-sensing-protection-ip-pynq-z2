# Safety Contract

The real-time protection path is implemented in RTL and does not depend on processing-system software. Raw compare and health flags feed fixed-priority classification, first-fault latching, and a safe-low PWM gate.

## Required Invariants

- A live fault keeps protection active.
- The first visible fault code remains latched until a valid recovery sequence.
- fault_latched forces pwm_out low even if pwm_raw is active.
- Software configuration and MMIO transport do not replace the RTL protection path.
- Clear requests cannot establish physical input safety.

## Prototype Boundary

The design is an engineering, research, and teaching prototype. It is not a commercial protection product, certified safety controller, airworthiness-ready item, production-ready power protection system, or complete motor controller.
