from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

from tools import stage2i_physical_authority as authority

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stage2i_release_test_support import (  # noqa: E402
    DESIGN_IDENTITY,
    PROJECT_IDENTITY,
    SOURCE_TREE,
    write_physical_fixture,
)


class Stage2IPhysicalAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.fixture = write_physical_fixture(Path(self.temp.name))

    def tearDown(self) -> None:
        self.temp.cleanup()

    def rewrite_receipt(self, payload: dict) -> None:
        self.fixture["receipt_path"].write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    def test_valid_authority_passes(self) -> None:
        result = authority.load_physical_authority(
            self.fixture["receipt_path"], expected_tree=SOURCE_TREE
        )
        self.assertEqual(authority.PRODUCTION_PROFILE, result.implementation_profile)
        self.assertEqual(SOURCE_TREE, result.source_tree)
        self.assertEqual(PROJECT_IDENTITY, result.project_identity)
        self.assertEqual(DESIGN_IDENTITY, result.design_identity)
        self.assertEqual(set(authority.ARTIFACT_KEYS), set(result.artifacts))

    def test_noncanonical_project_identity_is_rejected(self) -> None:
        manifest_path = self.fixture["manifest_path"]
        with manifest_path.open("r", encoding="utf-8", newline="") as stream:
            rows = list(csv.reader(stream, dialect="excel-tab"))
        rows[1][9] = "not a canonical token"
        with manifest_path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, dialect="excel-tab", lineterminator="\n")
            writer.writerows(rows)
        with self.assertRaisesRegex(authority.PhysicalAuthorityError, "canonical token"):
            authority.load_artifact_manifest(manifest_path)

    def test_wrong_profile_is_rejected(self) -> None:
        payload = self.fixture["receipt"]
        payload["implementation_profile"] = authority.BOARD_TEST_PROFILE
        self.rewrite_receipt(payload)
        with self.assertRaisesRegex(authority.PhysicalAuthorityError, "not SAFE_INERT"):
            authority.load_physical_authority(self.fixture["receipt_path"])

    def test_wrong_expected_tree_is_rejected(self) -> None:
        with self.assertRaisesRegex(authority.PhysicalAuthorityError, "differs from final main"):
            authority.load_physical_authority(
                self.fixture["receipt_path"], expected_tree="9" * 40
            )

    def test_wrong_artifact_hash_is_rejected(self) -> None:
        payload = self.fixture["receipt"]
        payload["artifacts"]["bit"]["sha256"] = "9" * 64
        self.rewrite_receipt(payload)
        with self.assertRaisesRegex(authority.PhysicalAuthorityError, "identity mismatch"):
            authority.load_physical_authority(self.fixture["receipt_path"])

    def test_wrong_artifact_size_is_rejected(self) -> None:
        payload = self.fixture["receipt"]
        payload["artifacts"]["hwh"]["bytes"] += 1
        self.rewrite_receipt(payload)
        with self.assertRaisesRegex(authority.PhysicalAuthorityError, "identity mismatch"):
            authority.load_physical_authority(self.fixture["receipt_path"])

    def test_missing_artifact_is_rejected(self) -> None:
        self.fixture["artifact_paths"]["xsa"].unlink()
        with self.assertRaisesRegex(authority.PhysicalAuthorityError, "is missing"):
            authority.load_physical_authority(self.fixture["receipt_path"])

    def test_wrong_ltx_policy_is_rejected(self) -> None:
        payload = self.fixture["receipt"]
        payload["artifacts"]["ltx"]["delivery_policy"] = "DEPLOY_REQUIRED"
        self.rewrite_receipt(payload)
        with self.assertRaisesRegex(authority.PhysicalAuthorityError, "policy mismatch"):
            authority.load_physical_authority(self.fixture["receipt_path"])


if __name__ == "__main__":
    unittest.main()
