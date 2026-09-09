from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from tools.board_validation import stage2_board_session as board
from tools.board_validation import stage2_board_session_host as host
from tools.board_validation import build_stage2_board_session as builder


def capture(scenario):
    source = [{"adc_sample_valid": 0, "adc_sample_ready": 1, "adc_sample_ch1": 0,
               "adc_sample_ch2": 0, "producer_active": 0, "producer_remaining": 0,
               "producer_accept": 0, "command_pending": 0} for _ in range(4096)]
    pair = board.FAULTS.get(scenario, (1024, 1025, 0, 0))[:2]
    if scenario == "live_clear_rejected":
        pair = (1000, 1300)
    count = 127 if scenario == "normal_pwm" else 1
    if scenario != "sample_source_removal":
        for i in range(2048, 2048 + count):
            source[i].update(adc_sample_valid=1, producer_accept=1, producer_active=1,
                             adc_sample_ch1=pair[0], adc_sample_ch2=pair[1])
    destination = []
    for i in range(4096):
        state, latched, code = 0, 0, 0
        if scenario in board.FAULTS and i >= 2048:
            state, latched, code = 1, 1, board.FAULTS[scenario][3]
        elif scenario in ("live_clear_rejected", "sample_source_removal"):
            state, latched, code = 1, 1, 2
        elif scenario == "clear_recovery":
            state, latched, code = (1 if i < 2048 else 2), 1, 2
        elif scenario == "recovered_pwm" and i < 2048:
            state, latched, code = 2, 1, 2
        raw = int(i % 1000 < 500)
        destination.append({"aresetn": 1, "pwm_raw": raw, "pwm_out": raw if state == 0 else 0,
                            "fault_valid": int(i == 2048 and scenario in (*board.FAULTS, "live_clear_rejected")),
                            "fault_latched": latched, "fault_code": code,
                            "fault_code_latched": code, "fsm_state": state})
    return source, destination


class BoardSessionTests(unittest.TestCase):
    def test_windows_version_query_exit_is_preserved(self):
        banner = "vivado v2024.1 (64-bit)\nSW Build 5076996 on Wed May 22 18:37:14 MDT 2024\n"
        with patch.object(builder.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, banner)):
            self.assertEqual(1, builder.query_version("vivado.bat")["query_exit_code"])
        with patch.object(builder.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "ERROR: 2024.1 5076996")):
            with self.assertRaises(RuntimeError):
                builder.query_version("vivado.bat")

    def test_all_eight_waveform_contracts(self):
        for scenario in board.SCENARIOS:
            with self.subTest(scenario=scenario):
                host.analyze_rows(scenario, *capture(scenario))

    def test_disabled_raw_pwm_cannot_prove_fault_gating(self):
        source, destination = capture("ch1_overcurrent")
        for row in destination:
            row["pwm_raw"] = 0
            row["pwm_out"] = 0
        with self.assertRaisesRegex(host.analyzer.EvidenceError, "Raw PWM"):
            host.analyze_rows("ch1_overcurrent", source, destination)

    def test_fault_pulse_escape_is_rejected(self):
        source, destination = capture("ch2_overcurrent")
        destination[3000]["pwm_out"] = 1
        with self.assertRaisesRegex(host.analyzer.EvidenceError, "gating"):
            host.analyze_rows("ch2_overcurrent", source, destination)

    def test_missing_source_capture_cannot_prove_removal(self):
        _, destination = capture("sample_source_removal")
        with self.assertRaisesRegex(host.analyzer.EvidenceError, "depth"):
            host.analyze_rows("sample_source_removal", [], destination)

    def test_extra_sample_during_removal_is_rejected(self):
        source, destination = capture("sample_source_removal")
        source[3000].update(adc_sample_valid=1, producer_accept=1)
        with self.assertRaisesRegex(host.analyzer.EvidenceError, "removed"):
            host.analyze_rows("sample_source_removal", source, destination)

    def test_unexpected_reset_and_fault_code_are_rejected(self):
        for mutation in ("aresetn", "fault_code_latched"):
            source, destination = capture("differential_fault")
            destination[3000][mutation] = 0
            with self.subTest(mutation=mutation), self.assertRaises(host.analyzer.EvidenceError):
                host.analyze_rows("differential_fault", source, destination)

    def test_wrong_duty_and_no_recovery_are_rejected(self):
        source, destination = capture("recovered_pwm")
        destination[3001]["pwm_raw"] = destination[3001]["pwm_out"] = 0
        with self.assertRaises(host.analyzer.EvidenceError):
            host.analyze_rows("recovered_pwm", source, destination)

    def test_clear_preserves_pwm_enable(self):
        session = object.__new__(board.BoardSession)
        session.backend = Mock()
        session.clear_with_pwm()
        session.backend.protection.write.assert_called_once_with(
            int(board.RegisterOffset.CTRL), int(board.CTRL_CLEAR_FAULT | board.CTRL_PWM_ENABLE)
        )

    def test_wrong_order_and_replay_do_not_touch_hardware(self):
        session = object.__new__(board.BoardSession)
        session.failed, session.index = False, 0
        session.backend = Mock()
        with self.assertRaisesRegex(RuntimeError, "out of order"):
            session.action("ch1_overcurrent/execute")
        session.backend.assert_not_called()

    def test_first_clean_sample_must_not_claim_complete_recovery(self):
        session = object.__new__(board.BoardSession)
        session.backend = Mock()
        session.checked_state = Mock(return_value={"policy_status": {
            "reset_wait_state": False, "post_clear_recovery_pending": False, "armed_ready": True}})
        with self.assertRaisesRegex(RuntimeError, "RESET_WAIT"):
            session.execute("clear_recovery")

    def test_immutable_json_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "receipt.json"
            board.write_json(path, {"status": "FAIL"})
            with self.assertRaises(FileExistsError):
                board.write_json(path, {"status": "PASS"})


if __name__ == "__main__":
    unittest.main()
