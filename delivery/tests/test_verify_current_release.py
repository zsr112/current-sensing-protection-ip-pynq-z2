from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

from tools import build_current_release as builder
from tools import verify_current_release as verifier

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stage2i_release_test_support import build_test_release  # noqa: E402


class VerifyCurrentReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo_root = Path(builder.__file__).resolve().parents[1]
        self.root, self.fixture = build_test_release(Path(self.temp.name), self.repo_root)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def rewrite_manifest(self) -> None:
        paths = [
            path
            for path in self.root.rglob("*")
            if path.is_file() and path.name != verifier.MANIFEST_NAME
        ]
        paths.sort(key=lambda path: path.relative_to(self.root).as_posix())
        with (self.root / verifier.MANIFEST_NAME).open(
            "w", encoding="utf-8", newline=""
        ) as stream:
            writer = csv.writer(stream, dialect="excel-tab", lineterminator="\n")
            writer.writerow(
                ["relative_path", "bytes", "sha256", "component", "source_authority"]
            )
            for path in paths:
                payload = path.read_bytes()
                writer.writerow(
                    [
                        path.relative_to(self.root).as_posix(),
                        len(payload),
                        verifier.hashlib.sha256(payload).hexdigest(),
                        "test",
                        "test",
                    ]
                )

    def rewrite_json_and_manifest(self, relative: str, payload: dict) -> None:
        (self.root / relative).write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        self.rewrite_manifest()

    def test_valid_release_passes(self) -> None:
        result = verifier.verify_release(self.root)
        self.assertEqual("PASS", result["status"])
        self.assertEqual(3, result["runtime_source_count"])
        self.assertEqual("PROVENANCE_ONLY_REQUIRED", result["ltx_policy"])
        self.assertEqual("PROVENANCE_ONLY_REQUIRED", result["xsa_policy"])

    def test_wrong_profile_fails(self) -> None:
        authority = json.loads((self.root / verifier.AUTHORITY_PATH).read_text(encoding="utf-8"))
        authority["implementation_profile"] = "READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS"
        self.rewrite_json_and_manifest(verifier.AUTHORITY_PATH, authority)
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "not SAFE_INERT"):
            verifier.verify_release(self.root)

    def test_wrong_tree_fails(self) -> None:
        authority = json.loads((self.root / verifier.AUTHORITY_PATH).read_text(encoding="utf-8"))
        authority["physical_artifact_source_tree"] = "9" * 40
        self.rewrite_json_and_manifest(verifier.AUTHORITY_PATH, authority)
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "source tree differs"):
            verifier.verify_release(self.root)

    def test_noncanonical_project_identity_fails(self) -> None:
        authority = json.loads((self.root / verifier.AUTHORITY_PATH).read_text(encoding="utf-8"))
        authority["artifact_manifest"]["project_identity"] = "not a canonical token"
        self.rewrite_json_and_manifest(verifier.AUTHORITY_PATH, authority)
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "canonical token"):
            verifier.verify_release(self.root)

    def test_wrong_bit_hash_fails(self) -> None:
        authority = json.loads((self.root / verifier.AUTHORITY_PATH).read_text(encoding="utf-8"))
        authority["artifacts"]["bit"]["sha256"] = "9" * 64
        self.rewrite_json_and_manifest(verifier.AUTHORITY_PATH, authority)
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "BIT identity mismatch"):
            verifier.verify_release(self.root)

    def test_wrong_hwh_size_fails(self) -> None:
        authority = json.loads((self.root / verifier.AUTHORITY_PATH).read_text(encoding="utf-8"))
        authority["artifacts"]["hwh"]["bytes"] += 1
        self.rewrite_json_and_manifest(verifier.AUTHORITY_PATH, authority)
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "HWH identity mismatch"):
            verifier.verify_release(self.root)

    def test_missing_artifact_fails(self) -> None:
        (self.root / "pynq" / "artifacts" / "protection_system.bit").unlink()
        self.rewrite_manifest()
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "copy inventory mismatch"):
            verifier.verify_release(self.root)

    def test_ltx_copy_violates_provenance_only_policy(self) -> None:
        (self.root / "pynq" / "artifacts" / "unexpected.ltx").write_bytes(b"ltx")
        self.rewrite_manifest()
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "forbidden file"):
            verifier.verify_release(self.root)

    def test_stale_stage1_runtime_payload_fails(self) -> None:
        stale = self.root / "pynq" / "runtime" / "load_current_release.py"
        stale.write_text("# stale\n", encoding="utf-8")
        self.rewrite_manifest()
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "runtime source inventory differs"):
            verifier.verify_release(self.root)

    def test_runtime_source_identity_fails_closed(self) -> None:
        path = self.root / "pynq" / "runtime" / "protection_ip_interface.py"
        path.write_text(path.read_text(encoding="utf-8") + "\n# mutation\n", encoding="utf-8")
        self.rewrite_manifest()
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "runtime source identity mismatch"):
            verifier.verify_release(self.root)

    def test_extra_file_fails_manifest_coverage(self) -> None:
        (self.root / "extra.txt").write_text("extra", encoding="utf-8")
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "coverage mismatch"):
            verifier.verify_release(self.root)

    def test_manifest_path_traversal_fails(self) -> None:
        manifest = self.root / verifier.MANIFEST_NAME
        text = manifest.read_text(encoding="utf-8")
        manifest.write_text(text.replace("README.md", "../README.md"), encoding="utf-8")
        with self.assertRaisesRegex(verifier.ReleaseVerificationError, "unsafe manifest path"):
            verifier.verify_release(self.root)


if __name__ == "__main__":
    unittest.main()
