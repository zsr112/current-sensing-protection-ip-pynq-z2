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
        elif offset == demo.REG_OBS_STATUS_W1C:
            self.registers[offset] = self.registers.get(offset, 0) & ~value
        else:
            self.registers[offset] = value

    def ctrl_writes(self):
        return [value for offset, value in self.writes if offset == demo.REG_CTRL]


class ProtectionIPInterfaceContractTests(unittest.TestCase):
    @staticmethod
    def explicit_mmio(
        *,
        version=None,
        capabilities_0=None,
        capabilities_1=None,
        policy_status=None,
    ):
        mmio = FakeMMIO()
        mmio.registers.update(
            {
                demo.REG_REGISTER_MAP_VERSION: (
                    demo.REGISTER_MAP_VERSION_VALUE
                    if version is None
                    else version
                ),
                demo.REG_CAPABILITIES_0: (
                    demo.CAPABILITIES_0_ABI_1_1_VALUE
                    if capabilities_0 is None
                    else capabilities_0
                ),
                demo.REG_CAPABILITIES_1: (
                    demo.CAPABILITIES_1_WIDTH32
                    if capabilities_1 is None
                    else capabilities_1
                ),
                demo.REG_POLICY_STATUS: (
                    demo.POLICY_STATUS_RESET_WAIT_STATE
                    if policy_status is None
                    else policy_status
                ),
            }
        )
        return mmio

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

    def test_observability_snapshot_reads_complete_map(self):
        mmio = FakeMMIO()
        observability_offsets = [
            demo.REG_OBS_CAPABILITY,
            demo.REG_OBS_STATUS_W1C,
            demo.REG_OBS_SOURCE_ACCEPT_COUNT,
            demo.REG_OBS_DESTINATION_DELIVERY_COUNT,
            demo.REG_OBS_BACKPRESSURE_CYCLE_COUNT,
            demo.REG_OBS_SOURCE_PROTOCOL_VIOLATION_COUNT,
            demo.REG_OBS_SOURCE_DROP_COUNT,
            demo.REG_OBS_FIFO_OVERFLOW_ATTEMPT_COUNT,
            demo.REG_OBS_FIFO_UNDERFLOW_ATTEMPT_COUNT,
            demo.REG_OBS_DUPLICATE_DELIVERY_COUNT,
            demo.REG_OBS_SEQUENCE_GAP_COUNT,
            demo.REG_OBS_REORDER_OR_STALE_COUNT,
            demo.REG_OBS_AGGREGATE_ERROR_COUNT,
            demo.REG_OBS_LAST_SOURCE_SEQUENCE,
            demo.REG_OBS_LAST_DESTINATION_SEQUENCE,
        ]
        for index, offset in enumerate(observability_offsets, start=1):
            mmio.registers[offset] = index

        snapshot = demo.read_observability(mmio)

        self.assertEqual(snapshot.capability, 1)
        self.assertEqual(snapshot.status, 2)
        self.assertEqual(snapshot.source_accept_count, 3)
        self.assertEqual(snapshot.aggregate_error_count, 13)
        self.assertEqual(snapshot.last_destination_sequence, 15)
        self.assertEqual(
            [offset for offset, _ in mmio.reads], observability_offsets
        )

    def test_observability_status_clear_is_masked_w1c(self):
        mmio = FakeMMIO()
        mmio.registers[demo.REG_OBS_STATUS_W1C] = demo.OBS_STATUS_MASK

        demo.clear_observability_status(mmio, 0xFFFF_FC05)

        self.assertEqual(
            mmio.writes[-1], (demo.REG_OBS_STATUS_W1C, 0x005)
        )
        self.assertEqual(
            mmio.registers[demo.REG_OBS_STATUS_W1C],
            demo.OBS_STATUS_MASK & ~0x005,
        )

    def test_observability_any_error_is_not_in_w1c_mask(self):
        mmio = FakeMMIO()

        demo.clear_observability_status(mmio, demo.OBS_STATUS_MASK)

        self.assertEqual(
            mmio.writes[-1],
            (demo.REG_OBS_STATUS_W1C, demo.OBS_STATUS_W1C_MASK),
        )
        self.assertEqual(
            demo.OBS_STATUS_W1C_MASK & demo.OBS_ANY_ERROR,
            0,
        )

    def test_explicit_discovery_and_higher_minor_known_prefix(self):
        for width, word in (
            (16, demo.CAPABILITIES_1_WIDTH16),
            (24, demo.CAPABILITIES_1_WIDTH24),
            (32, demo.CAPABILITIES_1_WIDTH32),
        ):
            with self.subTest(width=width):
                capabilities = demo.read_capabilities(
                    self.explicit_mmio(capabilities_1=word)
                )
                self.assertTrue(capabilities.version.explicit)
                self.assertEqual(capabilities.version.major, 1)
                self.assertEqual(capabilities.version.minor, 1)
                self.assertEqual(
                    capabilities.armed_ready, demo.FeatureState.PRESENT
                )
                self.assertEqual(
                    capabilities.normalized_telemetry,
                    demo.FeatureState.ABSENT,
                )
                self.assertEqual(capabilities.implemented_sequence_width, width)
                self.assertEqual(capabilities.fault_bitmap_width, 6)

        higher_minor = demo.REGISTER_MAP_VERSION_VALUE + 1
        capabilities = demo.read_capabilities(
            self.explicit_mmio(
                version=higher_minor,
                capabilities_0=(
                    demo.CAPABILITIES_0_ABI_1_1_VALUE | (1 << 12)
                ),
            )
        )
        self.assertEqual(capabilities.version.minor, 2)
        self.assertEqual(capabilities.armed_ready, demo.FeatureState.PRESENT)

    def test_legacy_stage2e_fallback_is_exact_and_other_features_unknown(self):
        mmio = FakeMMIO()
        mmio.registers[demo.REG_OBS_CAPABILITY] = demo.OBS_CAPABILITY_DEFAULT

        capabilities = demo.read_capabilities(mmio)

        self.assertFalse(capabilities.version.explicit)
        self.assertEqual(
            capabilities.stage2e_transaction_observability,
            demo.FeatureState.PRESENT,
        )
        self.assertEqual(capabilities.stage2g_policy, demo.FeatureState.UNKNOWN)
        self.assertEqual(capabilities.armed_ready, demo.FeatureState.UNKNOWN)

        mmio.registers[demo.REG_OBS_CAPABILITY] ^= 1 << 20
        capabilities = demo.read_capabilities(mmio)
        self.assertEqual(
            capabilities.stage2e_transaction_observability,
            demo.FeatureState.UNKNOWN,
        )

    def test_incompatible_explicit_version_and_metadata_are_rejected(self):
        cases = (
            ("bad magic", {"version": 0x1234_0101}),
            ("unsupported major", {"version": 0x524D_0201}),
            (
                "reserved capability bit",
                {
                    "capabilities_0": (
                        demo.CAPABILITIES_0_ABI_1_1_VALUE | (1 << 7)
                    )
                },
            ),
            (
                "normalized telemetry bit",
                {
                    "capabilities_0": (
                        demo.CAPABILITIES_0_ABI_1_1_VALUE | (1 << 4)
                    )
                },
            ),
            (
                "sequence width",
                {"capabilities_1": demo.capabilities_1_value(15)},
            ),
        )
        for label, values in cases:
            with self.subTest(label=label):
                with self.assertRaises(demo.IncompatibleRegisterMapError):
                    demo.read_capabilities(self.explicit_mmio(**values))

    def test_startup_ready_requires_explicit_capability_and_policy_state(self):
        with self.assertRaises(demo.IndeterminateFeatureError):
            demo.startup_ready(FakeMMIO(status=0, fault_code=demo.FAULT_NONE))

        capabilities_without_armed = (
            demo.CAPABILITIES_0_ABI_1_1_VALUE
            & ~demo.CAPABILITIES_0_ARMED_READY
        )
        with self.assertRaises(demo.UnsupportedFeatureError):
            demo.startup_ready(
                self.explicit_mmio(capabilities_0=capabilities_without_armed)
            )

        mmio = self.explicit_mmio(
            policy_status=demo.POLICY_STATUS_ARMED_READY
        )
        self.assertTrue(demo.startup_ready(mmio))
        self.assertTrue(demo.is_armed(mmio))
        self.assertFalse(demo.recovery_is_verified(
            demo.ProtectionSnapshot(
                ctrl=0,
                status=demo.STATUS_FAULT_LATCHED,
                fault_code=demo.FAULT_OVERCURRENT,
                i_ch1=0,
                i_ch2=0,
            )
        ))

    def test_policy_status_decodes_levels_and_rejects_broken_invariants(self):
        raw = (
            demo.POLICY_STATUS_FAULT_LATCHED_STATE
            | demo.POLICY_STATUS_CLEAR_PENDING
        )
        status = demo.read_policy_status(
            self.explicit_mmio(policy_status=raw)
        )
        self.assertTrue(status.fault_latched_state)
        self.assertTrue(status.clear_pending)
        self.assertFalse(status.armed_ready)

        invalid_values = (
            0,
            demo.POLICY_STATUS_ARMED_READY
            | demo.POLICY_STATUS_RESET_WAIT_STATE,
            demo.POLICY_STATUS_RESET_WAIT_STATE
            | demo.POLICY_STATUS_CLEAR_PENDING,
            demo.POLICY_STATUS_RESET_WAIT_STATE | (1 << 5),
        )
        for value in invalid_values:
            with self.subTest(value=value):
                with self.assertRaises(demo.IncompatibleRegisterMapError):
                    demo.read_policy_status(
                        self.explicit_mmio(policy_status=value)
                    )

    def test_fault_bitmap_forward_compatibility_and_width_boundary(self):
        known = demo.FAULT_CAUSE_CH1_OVERCURRENT | demo.FAULT_CAUSE_SENSOR_OPEN
        mmio = self.explicit_mmio()
        mmio.registers[demo.REG_FIRST_FAULT_BITMAP] = known
        value = demo.read_first_fault_bitmap(mmio)
        self.assertEqual(value.raw_value, known)
        self.assertEqual(
            value.known_flags,
            demo.FaultCause.CH1_OVERCURRENT | demo.FaultCause.SENSOR_OPEN,
        )
        self.assertEqual(value.unknown_mask, 0)
        self.assertEqual(value.advertised_width, 6)

        future_width_7 = (
            demo.CAPABILITIES_1_WIDTH32
            & ~demo.CAPABILITIES_1_FAULT_BITMAP_WIDTH_MASK
        ) | 7
        future_version = demo.REGISTER_MAP_VERSION_VALUE + 1
        mmio = self.explicit_mmio(
            version=future_version,
            capabilities_1=future_width_7,
        )
        mmio.registers[demo.REG_LIVE_FAULT_BITMAP] = known | (1 << 6)
        value = demo.read_live_fault_bitmap(mmio)
        self.assertEqual(value.known_flags, demo.FaultCause(known))
        self.assertEqual(value.unknown_mask, 1 << 6)

        mmio.registers[demo.REG_FAULT_SEEN_BITMAP] = 1 << 7
        with self.assertRaises(demo.IncompatibleRegisterMapError):
            demo.read_fault_seen_bitmap(mmio)

    def test_policy_evaluation_identity_is_diagnostic_only(self):
        mmio = self.explicit_mmio()
        mmio.registers[demo.REG_POLICY_EVALUATION_SEQUENCE] = 0xFEDC_BA98

        self.assertEqual(
            demo.read_policy_evaluation_identity(mmio), 0xFEDC_BA98
        )
        self.assertFalse(hasattr(demo, "read_policy_snapshot"))


if __name__ == "__main__":
    unittest.main()
