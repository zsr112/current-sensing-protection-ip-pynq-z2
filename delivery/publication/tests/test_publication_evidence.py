import tempfile
import unittest
import importlib.util
import sys
from pathlib import Path
from unittest.mock import patch

test_root = Path(__file__).resolve().parents[1]
if test_root.name == 'publication':
    sys.path.insert(0, str(test_root.parent))
    spec = importlib.util.spec_from_file_location('publication_generator', test_root / 'tools/build_self_contained_release.py')
    release = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(release)
    verifier_spec = importlib.util.spec_from_file_location('publication_verifier', test_root / 'tools/self_contained_verify.py')
    verifier = importlib.util.module_from_spec(verifier_spec)
    verifier_spec.loader.exec_module(verifier)
else:
    from tools import build_self_contained_release as release
    from tools import self_contained_verify as verifier
from tools.verify_windows_board_release import PRIVATE_PATH


class PublicationEvidenceTests(unittest.TestCase):
    def test_windows_ci_uses_supported_icarus_13_package(self):
        workflow = (test_root / '.github/workflows/portable.yml').read_text(encoding='utf-8')
        self.assertIn('msys2/setup-msys2@v2', workflow)
        self.assertIn('mingw-w64-ucrt-x86_64-iverilog', workflow)
        self.assertIn("${{ steps.msys2.outputs.msys2-location }}\\ucrt64\\bin", workflow)
        self.assertNotIn('choco install iverilog', workflow)

    def test_mixed_log_preserves_bad_bytes_as_explicit_escapes(self):
        original = 'PASS 中文\n'.encode() + b'local=\xbf\xff\n'
        result = release.portable_log(original, {})
        self.assertEqual('PASS 中文\nlocal=\\xbf\\xff\n', result.decode('utf-8'))
        self.assertTrue(original.endswith(b'\xbf\xff\n'))

    def test_mixed_log_still_redacts_windows_paths(self):
        original = b'PASS D' + b':/private/source/a.py error=\xff\n'
        result = release.portable_log(original, {})
        self.assertEqual(b'PASS <EXTERNAL_PATH> error=\\xff\n', result)

    def test_later_tool_preserves_bound_source_and_gets_separate_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            engineering, output = root / 'engineering', root / 'output'
            for base in (engineering, output):
                (base / 'tools').mkdir(parents=True)
            (engineering / 'tools/generator.py').write_bytes(b'new committed tool')
            (output / 'tools/generator.py').write_bytes(b'physical build input')
            with patch.object(release, 'ROOT', engineering):
                destination, record = release.publish_file(output, 'tools/generator.py', 'tools/generator.py')
                self.assertEqual('publication/tools/generator.py', destination)
                self.assertEqual(b'physical build input', (output / 'tools/generator.py').read_bytes())
                self.assertEqual(b'new committed tool', (output / destination).read_bytes())
                self.assertEqual(release.identity(output / destination), record['identity'])
                with self.assertRaisesRegex(Exception, 'already exists'):
                    release.publish_file(output, 'tools/generator.py', 'tools/generator.py')

    def test_identical_tool_keeps_normal_location(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            engineering, output = root / 'engineering', root / 'output'
            for base in (engineering, output):
                base.mkdir()
                (base / 'tool.py').write_bytes(b'same bytes')
            with patch.object(release, 'ROOT', engineering):
                destination, _ = release.publish_file(output, 'tool.py', 'tool.py')
            self.assertEqual('tool.py', destination)
            self.assertFalse((output / 'publication').exists())

    def test_generic_literals_are_scoped_and_other_paths_still_rejected(self):
        for relative, literal in (
            ('.github/workflows/portable.yml', b"'C:" + b"\\iverilog\\bin'"),
            ('tests/test_path_safety.py', b"'D" + b":/drive'"),
        ):
            self.assertFalse(verifier.contains_private_path(relative, literal, PRIVATE_PATH))
            self.assertTrue(verifier.contains_private_path('unrelated.txt', literal, PRIVATE_PATH))
            self.assertTrue(verifier.contains_private_path(relative, literal + b' D' + b':/private/evidence', PRIVATE_PATH))

    def test_verifier_does_not_contain_a_private_path_literal(self):
        self.assertIsNone(PRIVATE_PATH.search(Path(verifier.__file__).read_bytes()))
        self.assertIsNone(PRIVATE_PATH.search(Path(__file__).read_bytes()))


if __name__ == '__main__':
    unittest.main()
