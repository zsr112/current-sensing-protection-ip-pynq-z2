from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.path_safety import path_below_root, regular_files


class PathSafetyTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt', 'Windows junction behavior')
    def test_link_replacement_is_rechecked_before_read(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            root, outside = base / 'source', base / 'outside'
            child = root / 'child'
            child.mkdir(parents=True)
            outside.mkdir()
            (child / 'data').write_text('inside')
            (outside / 'data').write_text('outside')
            self.assertIn('child/data', regular_files(root))
            (child / 'data').unlink()
            child.rmdir()
            subprocess.run(['cmd.exe', '/d', '/c', 'mklink', '/J', str(child), str(outside)],
                           check=True, capture_output=True)
            try:
                with self.assertRaisesRegex(ValueError, 'Link or reparse point'):
                    path_below_root(root, 'child/data')
            finally:
                child.rmdir()

    def test_manifest_traversal_and_noncanonical_paths_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative in ('../escape', '/absolute', 'D:/drive', 'a\\b', 'a//b'):
                with self.subTest(relative=relative), self.assertRaises(ValueError):
                    path_below_root(root, relative, require_exists=False)

    @unittest.skipUnless(hasattr(os, 'symlink'), 'symbolic link support')
    def test_internal_directory_link_is_rejected_without_following_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outside = root.parent / (root.name + '-outside')
            outside.mkdir()
            (outside / 'secret.txt').write_text('outside')
            try:
                (root / 'linked').symlink_to(outside, target_is_directory=True)
            except OSError as error:
                self.skipTest('symbolic links unavailable: ' + str(error))
            with self.assertRaisesRegex(ValueError, 'Link or reparse point'):
                regular_files(root)
            (root / 'linked').unlink()
            (outside / 'secret.txt').unlink()
            outside.rmdir()

    @unittest.skipUnless(os.name == 'nt', 'Windows junction behavior')
    def test_windows_junction_to_outside_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outside = root.parent / (root.name + '-junction-target')
            outside.mkdir()
            junction = root / 'junction'
            subprocess.run(
                ['cmd.exe', '/d', '/c', 'mklink', '/J', str(junction), str(outside)],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            with self.assertRaisesRegex(ValueError, 'Link or reparse point'):
                regular_files(root)
            junction.rmdir()
            outside.rmdir()


if __name__ == '__main__':
    unittest.main()
