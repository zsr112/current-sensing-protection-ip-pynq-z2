import unittest
from tools.run_stage2f_generated_profile_rtl import has_width_warning


class DiagnosticPathTests(unittest.TestCase):
    def test_source_path_is_not_a_width_diagnostic(self):
        self.assertFalse(has_width_warning('warning: Some design elements have no explicit time unit\n'
            '       : module normalizer declared here: /portable/port/width/normalizer.sv:5\n'))

    def test_actual_width_warnings_remain_errors(self):
        self.assertTrue(has_width_warning('/source/path.sv:12: warning: Port 4 (raw) of normalizer expects 12 bits, got 13.'))
        self.assertTrue(has_width_warning('WARNING: [VRFC 10-3091] actual bit length 13 differs from formal bit length 12'))


if __name__ == '__main__':
    unittest.main()
