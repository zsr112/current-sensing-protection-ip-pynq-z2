from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import check_external_data_authorities as checker


class ExternalAuthorityCheckerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.data = self.root / "data"
        self.data.mkdir()
        self.public = self.root / "public"
        self.config_dir = self.root / "repo" / "docs" / "project"
        self.config_dir.mkdir(parents=True)
        self.config = self.config_dir / "authorities.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def digest(data: bytes) -> str:
        return hashlib.sha256(data).hexdigest()

    def write_config(self, authorities: list[dict]) -> None:
        payload = {
            "schema_version": 1,
            "data_root_env": "AUTHORITY_TEST_DATA_ROOT",
            "default_data_root": str(self.data),
            "public_root_env": "AUTHORITY_TEST_PUBLIC_ROOT",
            "default_public_root": str(self.public),
            "authorities": authorities,
        }
        self.config.write_text(json.dumps(payload), encoding="utf-8")

    def run_checker(
        self,
        data_root: Path | None = None,
        public_root: Path | None = None,
    ) -> tuple[int, str]:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = checker.run(
                self.config,
                data_root=data_root,
                public_root=public_root,
            )
        return code, output.getvalue()

    def file_authority(self, data: bytes = b"authority") -> dict:
        return {
            "logical_id": "immutable-file",
            "root_scope": "data",
            "relative_path": "accepted/file.bin",
            "expected_type": "file",
            "bytes_if_immutable": len(data),
            "sha256_if_immutable": self.digest(data),
            "required": True,
        }

    def test_all_matching_and_optional_missing(self) -> None:
        data = b"authority"
        path = self.data / "accepted" / "file.bin"
        path.parent.mkdir()
        path.write_bytes(data)
        directory = self.data / "workspace"
        directory.mkdir()
        (directory / "receipt.md").write_text("ok", encoding="utf-8")
        self.write_config([
            self.file_authority(data),
            {"logical_id": "workspace", "root_scope": "data", "relative_path": "workspace", "expected_type": "directory", "markers": ["receipt.md"], "required": True},
            {"logical_id": "public", "root_scope": "public", "relative_path": ".", "expected_type": "directory", "required": False},
        ])
        code, output = self.run_checker()
        self.assertEqual(0, code)
        self.assertIn("SUMMARY PASS=2 FAIL=0 SKIP=1", output)

    def test_required_file_missing(self) -> None:
        self.write_config([self.file_authority()])
        code, output = self.run_checker()
        self.assertEqual(1, code)
        self.assertIn("FAIL immutable-file: missing file", output)

    def test_bytes_mismatch(self) -> None:
        path = self.data / "accepted" / "file.bin"
        path.parent.mkdir()
        path.write_bytes(b"wrong")
        authority = self.file_authority(b"authority")
        authority["sha256_if_immutable"] = None
        self.write_config([authority])
        code, output = self.run_checker()
        self.assertEqual(1, code)
        self.assertIn("bytes mismatch", output)

    def test_sha256_mismatch(self) -> None:
        path = self.data / "accepted" / "file.bin"
        path.parent.mkdir()
        path.write_bytes(b"wrongdata")
        authority = self.file_authority(b"authority")
        authority["bytes_if_immutable"] = None
        self.write_config([authority])
        code, output = self.run_checker()
        self.assertEqual(1, code)
        self.assertIn("SHA-256 mismatch", output)

    def test_data_root_environment_override(self) -> None:
        override = self.root / "override"
        path = override / "accepted" / "file.bin"
        path.parent.mkdir(parents=True)
        path.write_bytes(b"authority")
        self.write_config([self.file_authority()])
        with mock.patch.dict(os.environ, {"AUTHORITY_TEST_DATA_ROOT": str(override)}):
            code, output = self.run_checker()
        self.assertEqual(0, code)
        self.assertIn(str(path), output)

    def test_directory_marker_missing(self) -> None:
        (self.data / "workspace").mkdir()
        self.write_config([{"logical_id": "workspace", "root_scope": "data", "relative_path": "workspace", "expected_type": "directory", "markers": ["receipt.md"], "required": True}])
        code, output = self.run_checker()
        self.assertEqual(1, code)
        self.assertIn("required marker missing", output)

    def test_optional_authority_missing_is_skip(self) -> None:
        self.write_config([{"logical_id": "optional", "root_scope": "data", "relative_path": "missing", "expected_type": "directory", "required": False}])
        code, output = self.run_checker()
        self.assertEqual(0, code)
        self.assertIn("SKIP optional", output)

    def test_malformed_json(self) -> None:
        self.config.write_text("{not-json", encoding="utf-8")
        code, output = self.run_checker()
        self.assertEqual(2, code)
        self.assertIn("FAIL configuration", output)

    def test_public_git_json_artifact_and_verifier_contract(self) -> None:
        self.public.mkdir()
        artifact = self.public / "artifact.bin"
        artifact.write_bytes(b"public-artifact")
        provenance = self.public / "provenance.json"
        provenance.write_text(
            json.dumps({"status": "PRIVATE_REVIEW", "remote": "CREATED_PRIVATE"}),
            encoding="utf-8",
        )
        verifier = self.public / "verify.py"
        verifier.write_text("print('PASS public verifier')\n", encoding="utf-8")
        subprocess_commands = [
            ["git", "-C", str(self.public), "init", "-b", "main"],
            ["git", "-C", str(self.public), "config", "user.name", "Authority Test"],
            ["git", "-C", str(self.public), "config", "user.email", "authority@example.invalid"],
            ["git", "-C", str(self.public), "add", "--all"],
            ["git", "-C", str(self.public), "commit", "-m", "test authority"],
            [
                "git", "-C", str(self.public), "remote", "add", "origin",
                "https://github.com/example/public.git",
            ],
            [
                "git", "-C", str(self.public), "update-ref",
                "refs/remotes/origin/main", "HEAD",
            ],
        ]
        for command in subprocess_commands:
            subprocess.run(command, check=True, capture_output=True, text=True)
        head = subprocess.check_output(
            ["git", "-C", str(self.public), "rev-parse", "HEAD"],
            text=True,
        ).strip()
        tree = subprocess.check_output(
            ["git", "-C", str(self.public), "rev-parse", "HEAD^{tree}"],
            text=True,
        ).strip()
        authority = {
            "logical_id": "public",
            "root_scope": "public",
            "relative_path": ".",
            "expected_type": "directory",
            "required": True,
            "git_identity": {
                "head": head,
                "tree": tree,
                "branch": "main",
                "remote_count": 1,
                "origin_url": "https://github.com/example/public.git",
                "origin_main": head,
                "clean": True,
            },
            "json_checks": [
                {
                    "relative_path": "provenance.json",
                    "expected": {
                        "status": "PRIVATE_REVIEW",
                        "remote": "CREATED_PRIVATE",
                    },
                }
            ],
            "artifact_checks": [
                {
                    "name": "artifact",
                    "relative_path": "artifact.bin",
                    "bytes": len(b"public-artifact"),
                    "sha256": self.digest(b"public-artifact"),
                }
            ],
            "python_verifier_checks": [
                {
                    "relative_path": "verify.py",
                    "expected_output_prefix": "PASS ",
                }
            ],
        }
        self.write_config([authority])
        code, output = self.run_checker()
        self.assertEqual(0, code)
        self.assertIn("SUMMARY PASS=1 FAIL=0 SKIP=0", output)

    def test_public_git_identity_mismatch_fails(self) -> None:
        self.public.mkdir()
        self.write_config([
            {
                "logical_id": "public",
                "root_scope": "public",
                "relative_path": ".",
                "expected_type": "directory",
                "required": True,
                "git_identity": {"head": "0" * 40},
            }
        ])
        code, output = self.run_checker()
        self.assertEqual(1, code)
        self.assertIn("Git head query failed", output)

    def test_public_origin_url_mismatch_fails(self) -> None:
        self.public.mkdir()
        subprocess.run(
            ["git", "-C", str(self.public), "init", "-b", "main"],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            [
                "git", "-C", str(self.public), "remote", "add", "origin",
                "https://github.com/example/actual.git",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        self.write_config([
            {
                "logical_id": "public",
                "root_scope": "public",
                "relative_path": ".",
                "expected_type": "directory",
                "required": True,
                "git_identity": {
                    "remote_count": 1,
                    "origin_url": "https://github.com/example/expected.git",
                },
            }
        ])
        code, output = self.run_checker()
        self.assertEqual(1, code)
        self.assertIn("Git origin fetch URL mismatch", output)


if __name__ == "__main__":
    unittest.main()
