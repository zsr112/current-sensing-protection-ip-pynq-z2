"""Recovery contract tests migrated from the PYNQ demo interface.

These tests were originally introduced during Stage 1B-A for the recovery
contract of the PYNQ demo. They were migrated in Stage 1B-B to validate the
extracted protection interface.
"""

import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "protection_ip_interface.py"
spec = importlib.util.spec_from_file_location("protection_ip_interface", MODULE_PATH)
demo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(demo)


class FakeMMIO:
    """Minimal register backend for software-sequence tests only."""

    def __init__(self, ctrl=0, status=0, fault_code=0):
        self.registers = {
            demo.REG_CTRL: ctrl,
            demo.REG_STATUS: status,
            demo.REG_FAULT_CODE: fault_code,
        }
        self.reads = []
        self.writes = []

    def read(self, offset):
        value = self.registers.get(offset, 0)
        self.reads.append((offset, value))
        return value

    def write(self, offset, value):
        self.writes.append((offset, value))
        if offset == demo.REG_CTRL:
            # CTRL[1] is a write-one pulse and reads back as zero.
            self.registers[offset] = value & demo.CTRL_PWM_ENABLE
        else:
            self.registers[offset] = value

    def ctrl_writes(self):
        return [value for offset, value in self.writes if offset == demo.REG_CTRL]


class ProtectionIPInterfaceContractTests(unittest.TestCase):
    def test_apply_demo_configuration_keeps_pwm_disabled(self):
        mmio = FakeMMIO(ctrl=demo.CTRL_PWM_ENABLE)

        demo.apply_demo_configuration(mmio)

        self.assertEqual(mmio.writes[0], (demo.REG_CTRL, 0x00))
        self.assertEqual(mmio.registers[demo.REG_CTRL], 0x00)
        self.assertNotIn(demo.CTRL_PWM_ENABLE, mmio.ctrl_writes())

    def test_recovery_success_uses_clear_only_sequence(self):
        mmio = FakeMMIO(status=0, fault_code=demo.FAULT_NONE)

        recovered = demo.recover_after_external_safety_confirmation(
            mmio, timeout_polls=1
        )

        self.assertTrue(recovered)
        self.assertEqual(mmio.ctrl_writes(), [0x00, 0x02])
        self.assertEqual(mmio.ctrl_writes().count(0x02), 1)
        self.assertNotIn(0x03, mmio.ctrl_writes())
        self.assertNotIn(0x01, mmio.ctrl_writes())

    def test_persistent_fault_times_out(self):
        fault_status = (
            demo.STATUS_FAULT_VALID | demo.STATUS_FAULT_LATCHED
        )
        mmio = FakeMMIO(status=fault_status, fault_code=0x01)

        recovered = demo.recover_after_external_safety_confirmation(
            mmio, timeout_polls=2
        )

        self.assertFalse(recovered)
        self.assertEqual(mmio.ctrl_writes(), [0x00, 0x02, 0x00])
        self.assertEqual(mmio.registers[demo.REG_CTRL], 0x00)

    def test_successful_recovery_returns_true(self):
        mmio = FakeMMIO(status=0, fault_code=demo.FAULT_NONE)

        recovered = demo.recover_after_external_safety_confirmation(
            mmio, timeout_polls=1
        )

        self.assertTrue(recovered)
        read_offsets = [offset for offset, _ in mmio.reads]
        self.assertIn(demo.REG_STATUS, read_offsets)
        self.assertIn(demo.REG_FAULT_CODE, read_offsets)
        self.assertEqual(mmio.registers[demo.REG_CTRL], 0x00)

    def test_enable_only_after_successful_recovery(self):
        mmio = FakeMMIO(status=0, fault_code=demo.FAULT_NONE)

        recovered = demo.recover_after_external_safety_confirmation(
            mmio, timeout_polls=1
        )
        enabled = demo.enable_pwm_after_recovery(mmio) if recovered else False

        self.assertTrue(recovered)
        self.assertTrue(enabled)
        self.assertEqual(mmio.ctrl_writes(), [0x00, 0x02, 0x01])
        self.assertGreater(
            mmio.ctrl_writes().index(0x01),
            mmio.ctrl_writes().index(0x02),
        )

    def test_zero_timeout_does_not_clear(self):
        mmio = FakeMMIO(status=0, fault_code=demo.FAULT_NONE)

        recovered = demo.recover_after_external_safety_confirmation(
            mmio, timeout_polls=0
        )

        self.assertFalse(recovered)
        self.assertEqual(mmio.ctrl_writes(), [0x00])
        self.assertNotIn(demo.CTRL_CLEAR_FAULT, mmio.ctrl_writes())

    def test_failure_ends_with_pwm_disabled(self):
        mmio = FakeMMIO(
            ctrl=demo.CTRL_PWM_ENABLE,
            status=demo.STATUS_FAULT_VALID,
            fault_code=0x01,
        )

        enabled = demo.enable_pwm_after_recovery(mmio)

        self.assertFalse(enabled)
        self.assertEqual(mmio.writes[-1], (demo.REG_CTRL, 0x00))
        self.assertEqual(mmio.registers[demo.REG_CTRL], 0x00)


if __name__ == "__main__":
    unittest.main()
