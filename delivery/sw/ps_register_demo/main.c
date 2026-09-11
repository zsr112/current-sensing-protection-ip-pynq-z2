#include "protection_ip_regs.h"

#define PROTECTION_RECOVERY_TIMEOUT_POLLS 1000u

/*
 * Stage 2 bare-metal style skeleton.
 *
 * This file documents the expected PS-side register flow. It is not yet tied
 * to a board support package, UART driver, interrupt controller, or real ADC.
 */

static void protection_configure_defaults(void)
{
    /* PWM remains disabled after configuration until explicit enable. */
    protection_write(PROTECTION_REG_CTRL, 0u);
    protection_write(PROTECTION_REG_TH_OC1, 2500u);
    protection_write(PROTECTION_REG_TH_OC2, 2500u);
    protection_write(PROTECTION_REG_TH_DIFF, 200u);
    /* PWM registers configure only the low-voltage observable demo carrier. */
    protection_write(PROTECTION_REG_PWM_PERIOD, 1000u);
    protection_write(PROTECTION_REG_PWM_DUTY, 500u);
}

static void protection_disable_pwm(void)
{
    protection_write(PROTECTION_REG_CTRL, 0u);
}

static void protection_clear_fault(void)
{
    /*
     * clear_fault is a request pulse. RTL keeps the fault latched and the
     * protected output disabled if the fault condition is still active.
     */
    protection_write(PROTECTION_REG_CTRL, PROTECTION_CTRL_CLEAR_FAULT);
}

static int protection_recovery_is_verified(void)
{
    uint32_t status = protection_read(PROTECTION_REG_STATUS);
    uint32_t fault_code = protection_read(PROTECTION_REG_FAULT_CODE);
    uint32_t ctrl = protection_read(PROTECTION_REG_CTRL);
    uint32_t fault_mask = PROTECTION_STATUS_FAULT_VALID |
                          PROTECTION_STATUS_FAULT_LATCHED;

    return ((status & fault_mask) == 0u) &&
           (fault_code == PROTECTION_FAULT_NONE) &&
           ((ctrl & PROTECTION_CTRL_PWM_ENABLE) == 0u);
}

/*
 * Example recovery API. The caller must externally confirm physical input
 * safety before invoking this function.
 */
int protection_recover_after_external_safety_confirmation(void)
{
    uint32_t polls_remaining = PROTECTION_RECOVERY_TIMEOUT_POLLS;

    protection_disable_pwm();
    if ((protection_read(PROTECTION_REG_CTRL) &
         PROTECTION_CTRL_PWM_ENABLE) != 0u) {
        protection_disable_pwm();
        return 0;
    }

    protection_clear_fault();

    while (polls_remaining != 0u) {
        if (protection_recovery_is_verified()) {
            return 1;
        }
        polls_remaining--;
    }

    protection_disable_pwm();
    return 0;
}

int protection_enable_pwm_after_recovery(void)
{
    if (!protection_recovery_is_verified()) {
        protection_disable_pwm();
        return 0;
    }

    protection_write(PROTECTION_REG_CTRL, PROTECTION_CTRL_PWM_ENABLE);
    if ((protection_read(PROTECTION_REG_CTRL) &
         PROTECTION_CTRL_PWM_ENABLE) == 0u) {
        protection_disable_pwm();
        return 0;
    }

    return 1;
}

static void protection_poll_once(void)
{
    uint32_t status = protection_read(PROTECTION_REG_STATUS);
    uint32_t fault_code = protection_read(PROTECTION_REG_FAULT_CODE);
    uint32_t i_ch1 = protection_read(PROTECTION_REG_I_CH1);
    uint32_t i_ch2 = protection_read(PROTECTION_REG_I_CH2);

    (void)status;
    (void)fault_code;
    (void)i_ch1;
    (void)i_ch2;

    /* Observation only. A board application may report this snapshot. */
}

int main(void)
{
    /*
     * Confirm PROTECTION_IP_BASEADDR against Vivado Address Editor before
     * using this skeleton on hardware.
     */
    protection_configure_defaults();

    while (1) {
        protection_poll_once();
    }

    return 0;
}
