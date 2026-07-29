# Register Map

The canonical implementation is rtl/protection_reg_bank.v. AXI-Lite byte addresses match the internal register offsets.

| Address | Name | Access | Reset | Meaning |
|---:|---|---|---:|---|
| 0x00 | CTRL | RW/W1P | 0 | bit 0 pwm_enable; bit 1 one-clock clear request |
| 0x04 | STATUS | RO | live 0 | bit 0 fault_valid; bit 1 fault_latched |
| 0x08 | FAULT_CODE | RO | 0 | low 8 bits are the latched code |
| 0x0C | I_CH1 | RO | live | low 12 bits are channel 1 |
| 0x10 | I_CH2 | RO | live | low 12 bits are channel 2 |
| 0x14 | TH_OC1 | RW | 3000 | low 12 bits |
| 0x18 | TH_OC2 | RW | 3000 | low 12 bits |
| 0x1C | TH_DIFF | RW | 200 | low 12 bits |
| 0x20 | PWM_PERIOD | RW | 1000 | low 16 bits |
| 0x24 | PWM_DUTY | RW | 500 | low 16 bits |

Comparison is strict greater-than, so equality is not a fault. CTRL bit 1 reads as zero because it is a write-one pulse. STATUS value 0x3 is the combination of fault_valid and fault_latched. PWM_PERIOD zero forces the raw PWM low; duty zero stays low; duty greater than or equal to period is clamped to period. A latched fault always forces pwm_out low.
