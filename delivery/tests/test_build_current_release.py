from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import build_current_release as builder
from tools import stage2i_physical_authority as physical_authority
from tools import verify_current_release as verifier

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stage2i_release_test_support import (  # noqa: E402
    ENGINEERING_COMMIT,
    SOURCE_TREE,
    build_test_release,
    write_physical_fixture,
)


class BuildCurrentReleaseTests(unittest.TestCase):
    @staticmethod
    def run_packaged_runtime(release_root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(release_root / "pynq" / "runtime" / "stage2i_current_release.py"),
                "--release-root",
                str(release_root),
            ],
            cwd=release_root,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_active_worktree_source_inventory_is_current_and_complete(self) -> None:
        repo_root = Path(builder.__file__).resolve().parents[1]
        self.assertEqual(
            {
                "fpga/pynq/deployment/stage1g/stage2i_current_release.py",
                "sw/protection_ip_interface.py",
                "sw/generated/protection_register_map.py",
            },
            set(builder.ACTIVE_WORKTREE_PACKAGE_SOURCES),
        )
        self.assertTrue(
            all((repo_root / path).is_file() for path in builder.ACTIVE_WORKTREE_PACKAGE_SOURCES)
        )
        source_text = "\n".join(
            (repo_root / path).read_text(encoding="utf-8")
            for path in builder.ACTIVE_WORKTREE_PACKAGE_SOURCES
        )
        self.assertNotIn("systemctl", source_text)
        self.assertNotIn("stage1g-release-manifest-v1", source_text)

    def test_generated_abi_is_exactly_1_1(self) -> None:
        repo_root = Path(builder.__file__).resolve().parents[1]
        abi = builder.current_register_map_abi(repo_root)
        self.assertEqual(1, abi["major"])
        self.assertEqual(1, abi["minor"])
        self.assertEqual("1.1.0", abi["schema_version"])

    def test_fixture_release_builds_and_verifies(self) -> None:
        repo_root = Path(builder.__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporary:
            release_root, _fixture = build_test_release(Path(temporary), repo_root)
            result = verifier.verify_release(release_root)
        self.assertEqual("PASS", result["status"])
        self.assertEqual("PASS", result["tree_equivalence"])
        self.assertEqual("NOT_CLAIMED", result["persistent_deployment_claim"])
        self.assertEqual(0, result["release_ltx_copy_count"])
        self.assertEqual(0, result["release_xsa_copy_count"])

    def test_packaged_runtime_accepts_canonical_manifest_identities(self) -> None:
        repo_root = Path(builder.__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporary:
            release_root, _fixture = build_test_release(Path(temporary), repo_root)
            completed = self.run_packaged_runtime(release_root)
        self.assertEqual(0, completed.returncode, completed.stdout + completed.stderr)
        self.assertEqual("PASS_OFFLINE", json.loads(completed.stdout)["status"])

    def test_packaged_runtime_rejects_noncanonical_manifest_identities(self) -> None:
        repo_root = Path(builder.__file__).resolve().parents[1]
        for field in ("project_identity", "design_identity"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                release_root, _fixture = build_test_release(Path(temporary), repo_root)
                authority_path = release_root / verifier.AUTHORITY_PATH
                authority = json.loads(authority_path.read_text(encoding="utf-8"))
                authority["artifact_manifest"][field] = "not a canonical token"
                authority_path.write_text(
                    json.dumps(authority, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8",
                )
                completed = self.run_packaged_runtime(release_root)
            self.assertNotEqual(0, completed.returncode)
            self.assertIn(f"artifact manifest {field} is not a canonical token", completed.stdout)

    def test_packaged_runtime_keeps_manifest_sha256_validation(self) -> None:
        repo_root = Path(builder.__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporary:
            release_root, _fixture = build_test_release(Path(temporary), repo_root)
            authority_path = release_root / verifier.AUTHORITY_PATH
            authority = json.loads(authority_path.read_text(encoding="utf-8"))
            authority["artifact_manifest"]["sha256"] = "not-a-sha256"
            authority_path.write_text(
                json.dumps(authority, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            completed = self.run_packaged_runtime(release_root)
        self.assertNotEqual(0, completed.returncode)
        self.assertIn(
            "artifact manifest sha256 is not a lowercase SHA-256", completed.stdout
        )

    def test_release_authority_distinguishes_commit_and_tree_identities(self) -> None:
        repo_root = Path(builder.__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporary:
            release_root, _fixture = build_test_release(Path(temporary), repo_root)
            authority = json.loads(
                (release_root / verifier.AUTHORITY_PATH).read_text(encoding="utf-8")
            )
        self.assertEqual(ENGINEERING_COMMIT, authority["engineering_main_commit"])
        self.assertEqual(SOURCE_TREE, authority["engineering_main_tree"])
        self.assertEqual(SOURCE_TREE, authority["physical_artifact_source_tree"])
        self.assertNotEqual(
            authority["engineering_main_commit"],
            authority["physical_artifact_source_commit"],
        )

    def test_physical_tree_mismatch_is_rejected_before_release_write(self) -> None:
        repo_root = Path(builder.__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporary:
            fixture = write_physical_fixture(Path(temporary) / "physical")
            authority = physical_authority.load_physical_authority(fixture["receipt_path"])
            with self.assertRaisesRegex(builder.ReleaseBuildError, "differs from final main"):
                builder.release_authority_record(
                    authority,
                    ENGINEERING_COMMIT,
                    "9" * 40,
                    builder.current_register_map_abi(repo_root),
                    builder.runtime_source_records(repo_root),
                )

    def test_main_only_clean_git_gate_is_unchanged(self) -> None:
        clean = {
            ("branch", "--show-current"): "main",
            ("rev-parse", "HEAD"): "a" * 40,
            ("rev-parse", "HEAD^{tree}"): "b" * 40,
            ("rev-parse", "main"): "a" * 40,
            ("rev-parse", "origin/main"): "a" * 40,
            ("status", "--porcelain", "--untracked-files=all"): "",
        }

        def fake_git(_root: Path, *args: str) -> str:
            return clean[args]

        with mock.patch.object(builder, "run_git", side_effect=fake_git):
            self.assertEqual(("a" * 40, "b" * 40), builder.verify_git_gate(Path("repo")))
        clean[("branch", "--show-current")] = "feature"
        with mock.patch.object(builder, "run_git", side_effect=fake_git):
            with self.assertRaisesRegex(builder.ReleaseBuildError, "main must be clean"):
                builder.verify_git_gate(Path("repo"))

    def test_atomic_build_publishes_once_and_removes_staging(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = parent / "release"

            def populate(staging: Path) -> dict:
                (staging / "payload.txt").write_text("payload", encoding="utf-8")
                return {"build": "PASS"}

            def validate(root: Path) -> dict:
                self.assertEqual("payload", (root / "payload.txt").read_text(encoding="utf-8"))
                return {"status": "PASS"}

            result = builder.atomic_build(output, populate, validate)
            self.assertTrue(output.is_dir())
            self.assertEqual("PASS", result["final_verification"]["status"])
            self.assertEqual([], list(parent.glob(".release.staging-*")))

    def test_atomic_build_failure_leaves_no_target_or_staging(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = parent / "release"

            def populate(staging: Path) -> dict:
                (staging / "partial.txt").write_text("partial", encoding="utf-8")
                raise builder.ReleaseBuildError("expected failure")

            with self.assertRaises(builder.ReleaseBuildError):
                builder.atomic_build(output, populate, lambda _: {})
            self.assertFalse(output.exists())
            self.assertEqual([], list(parent.glob(".release.staging-*")))


if __name__ == "__main__":
    unittest.main()
