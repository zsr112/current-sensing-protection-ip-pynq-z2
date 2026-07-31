# Board Validation Summary

Stage 1G establishes one real PYNQ-Z2 cold boot autoload with Overlay programming, device/clock/IP discovery, read-only MMIO/GPIO checks, one worker, one attempt, no retry, and clean terminal publication. The four persistent runtime files in deploy match the board-validated payload byte for byte.

The accepted Stage 1 board functional closure separately establishes the bounded internal digital
CH1-only, CH2-only, and differential fault responses; live-fault clear rejection; latch/code retention after
source removal; clear recovery; internal PWM shutdown; post-recovery PWM pass-through; final state
restoration; and an 8/8 ILA evidence set. Its terminal class is
`STAGE1_BOARD_FAULT_CLEAR_RECOVERY_FUNCTIONAL_CLOSURE_PASS`.

The board wall clock is untrusted; monotonic ordering is authoritative for sequence. This validation does not
represent a pass for a real power stage, external drive chain, load, thermal behavior, EMI, or production
safety. It does not establish repeated cold boots, power-cycle, soak, external ADC/AFE, calibrated current,
external-pin PWM, gate-driver behavior, motor/load behavior, electrical safety, production reliability, a
new Vivado implementation or artifact pair, or system/aviation certification.

Items outside this list are not proved, not reported as failed.
