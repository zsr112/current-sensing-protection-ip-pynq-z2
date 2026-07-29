"""Reusable MMIO interface for the current-sensing protection IP."""

from dataclasses import dataclass


__all__ = [
    "ProtectionSnapshot",
    "apply_demo_configuration",
    "disable_pwm",
    "clear_fault_request",
    "read_status",
    "recovery_is_verified",
    "recover_after_external_safety_confirmation",
    "enable_pwm_after_recovery",
]


REG_CTRL = 0x00
REG_STATUS = 0x04
REG_FAULT_CODE = 0x08
REG_I_CH1 = 0x0C
REG_I_CH2 = 0x10
REG_TH_OC1 = 0x14
REG_TH_OC2 = 0x18
REG_TH_DIFF = 0x1C
REG_PWM_PERIOD = 0x20
REG_PWM_DUTY = 0x24

CTRL_PWM_ENABLE = 1 << 0
CTRL_CLEAR_FAULT = 1 << 1
STATUS_FAULT_VALID = 1 << 0
STATUS_FAULT_LATCHED = 1 << 1
FAULT_NONE = 0x00
RECOVERY_TIMEOUT_POLLS = 1000


@dataclass(frozen=True)
class ProtectionSnapshot:
    """Single readout of the active protection interface state."""

    ctrl: int
    status: int
    fault_code: int
    i_ch1: int
    i_ch2: int


def apply_demo_configuration(mmio):
    """Apply software demo values while keeping PWM disabled."""
    mmio.write(REG_CTRL, 0)
    mmio.write(REG_TH_OC1, 2500)
    mmio.write(REG_TH_OC2, 2500)
    mmio.write(REG_TH_DIFF, 200)
    mmio.write(REG_PWM_PERIOD, 1000)
    mmio.write(REG_PWM_DUTY, 500)


def disable_pwm(mmio):
    mmio.write(REG_CTRL, 0)
    return (mmio.read(REG_CTRL) & CTRL_PWM_ENABLE) == 0


def clear_fault_request(mmio):
    mmio.write(REG_CTRL, CTRL_CLEAR_FAULT)


def read_status(mmio):
    return ProtectionSnapshot(
        ctrl=mmio.read(REG_CTRL),
        status=mmio.read(REG_STATUS),
        fault_code=mmio.read(REG_FAULT_CODE),
        i_ch1=mmio.read(REG_I_CH1),
        i_ch2=mmio.read(REG_I_CH2),
    )


def recovery_is_verified(snapshot):
    fault_mask = STATUS_FAULT_VALID | STATUS_FAULT_LATCHED
    return (
        (snapshot.status & fault_mask) == 0
        and snapshot.fault_code == FAULT_NONE
        and (snapshot.ctrl & CTRL_PWM_ENABLE) == 0
    )


def recover_after_external_safety_confirmation(
    mmio, timeout_polls=RECOVERY_TIMEOUT_POLLS
):
    # Caller must externally confirm physical input safety first.
    if timeout_polls <= 0 or not disable_pwm(mmio):
        disable_pwm(mmio)
        return False

    clear_fault_request(mmio)

    for _ in range(timeout_polls):
        if recovery_is_verified(read_status(mmio)):
            return True

    disable_pwm(mmio)
    return False


def enable_pwm_after_recovery(mmio):
    if not recovery_is_verified(read_status(mmio)):
        disable_pwm(mmio)
        return False

    mmio.write(REG_CTRL, CTRL_PWM_ENABLE)
    if (mmio.read(REG_CTRL) & CTRL_PWM_ENABLE) == 0:
        disable_pwm(mmio)
        return False

    return True
