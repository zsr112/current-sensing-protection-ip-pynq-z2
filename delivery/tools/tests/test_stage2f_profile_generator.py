from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from tools.generate_stage2f_adc_profile import (
    _load_json,
    generate,
    render_include,
    validate_profile,
)
from tools.stage2f_normalization_reference import (
    LATENCY_ACLK,
    NormalizationPipelineModel,
    exhaustive_arithmetic,
    exhaustive_reference_verification,
    load_profile,
    normalize_code,
    verify_reference_mutations,
)


ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "spec/stage2f_adc_source_profile.schema.json"
PRODUCTION = ROOT / "spec/stage2f_adc_source_profile_unconfigured.json"
SIM_PROFILES = sorted((ROOT / "spec/stage2f_profiles").glob("*.json"))


class Stage2fProfileGeneratorTests(unittest.TestCase):
    def test_production_profile_generates_deterministically(self) -> None:
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        profile = json.loads(PRODUCTION.read_text(encoding="utf-8"))
        first = render_include(SCHEMA.read_bytes(), PRODUCTION.read_bytes(), profile)
        second = render_include(SCHEMA.read_bytes(), PRODUCTION.read_bytes(), profile)
        self.assertEqual(first, second)
        validate_profile(schema, profile)
        self.assertIn("PROFILE_IDENTITY=UNCONFIGURED", first)
        self.assertIn("`define STAGE2F_PROFILE_CONFIGURED 1'b0", first)

    def test_all_validation_profiles_pass_and_provenance_is_present(self) -> None:
        self.assertEqual(6, len(SIM_PROFILES))
        with tempfile.TemporaryDirectory(prefix="stage2f_generator_") as directory:
            for profile_path in SIM_PROFILES:
                output = Path(directory) / (profile_path.stem + ".svh")
                self.assertTrue(generate(SCHEMA, profile_path, output, False))
                generated = output.read_text(encoding="utf-8")
                self.assertIn("PROFILE_INPUT_SHA256=", generated)
                self.assertIn("PROFILE_IDENTITY=" + profile_path.stem, generated)
                self.assertTrue(generate(SCHEMA, profile_path, output, True))

    def test_reserved_identity_and_schema_mutations_fail_closed(self) -> None:
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        profile = json.loads((ROOT / "spec/stage2f_profiles/SIM_TWOS_COMPLEMENT_POSITIVE.json").read_text(encoding="utf-8"))
        reserved = copy.deepcopy(profile)
        reserved["profile_identity"] = "UNCONFIGURED"
        with self.assertRaises(ValueError):
            validate_profile(schema, reserved)
        broken_schema = copy.deepcopy(schema)
        broken_schema["properties"]["raw_width"]["const"] = 10
        with self.assertRaises(ValueError):
            validate_profile(broken_schema, profile)

    def test_reference_model_sign_boundaries_and_exhaustive_domains(self) -> None:
        twos_positive = load_profile(ROOT / "spec/stage2f_profiles/SIM_TWOS_COMPLEMENT_POSITIVE.json")
        twos_reversed = load_profile(ROOT / "spec/stage2f_profiles/SIM_TWOS_COMPLEMENT_REVERSED.json")
        self.assertEqual(0, normalize_code(0x000, twos_positive))
        self.assertEqual(2047, normalize_code(0x7FF, twos_positive))
        self.assertEqual(-2048, normalize_code(0x800, twos_positive))
        self.assertEqual(2048, normalize_code(0x800, twos_reversed))
        self.assertEqual(-1, normalize_code(0x001, twos_reversed))
        for profile_path in SIM_PROFILES:
            profile = load_profile(profile_path)
            self.assertEqual(8192, exhaustive_arithmetic(profile))

    def test_pipeline_latency_and_reset_flush(self) -> None:
        profile = load_profile(ROOT / "spec/stage2f_profiles/SIM_UNSIGNED_ZERO_MIDSCALE_CH2_REVERSED.json")
        model = NormalizationPipelineModel(profile, LATENCY_ACLK)
        self.assertIsNone(model.step(True, True, 7, 2049, 2047))
        output = model.step(True, False)
        self.assertEqual((7, 1, 1), output)
        model.step(True, True, 8, 2050, 2050)
        self.assertIsNone(model.step(False, False))
        self.assertIsNone(model.step(True, False))
        self.assertIsNone(model.step(True, False))

    def test_complete_reference_oracle_and_mutations(self) -> None:
        self.assertEqual(57344, exhaustive_reference_verification())
        self.assertEqual(5, verify_reference_mutations())
        print("PYTHON_REFERENCE_EXHAUSTIVE=PASS")
        print("PYTHON_REFERENCE_MUTATIONS=PASS_5_OF_5")

    def test_duplicate_json_keys_fail_closed(self) -> None:
        production_text = PRODUCTION.read_text(encoding="utf-8")
        mutations = {
            "encoding": production_text.replace(
                '"encoding": "UNKNOWN",',
                '"encoding": "UNKNOWN",\n  "encoding": "UNKNOWN",',
                1,
            ),
            "zero_code": production_text.replace(
                '"zero_code": null,',
                '"zero_code": null,\n  "zero_code": null,',
                1,
            ),
            "production_selection": production_text.replace(
                '"production_selection": false',
                '"production_selection": false,\n  "production_selection": false',
                1,
            ),
            "channel_polarity.channel_1": production_text.replace(
                '"channel_1": "UNKNOWN",',
                '"channel_1": "UNKNOWN",\n    "channel_1": "UNKNOWN",',
                1,
            ),
        }
        with tempfile.TemporaryDirectory(prefix="stage2f_duplicate_json_") as directory:
            temporary = Path(directory)
            for name, text in mutations.items():
                path = temporary / f"{name.replace('.', '_')}.json"
                path.write_text(text, encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                    _load_json(path)
                with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                    generate(SCHEMA, path, temporary / "profile.svh", False)
            schema_text = SCHEMA.read_text(encoding="utf-8").replace(
                '"type": "object",',
                '"type": "object",\n  "type": "object",',
                1,
            )
            duplicate_schema = temporary / "duplicate_schema.json"
            duplicate_schema.write_text(schema_text, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                generate(duplicate_schema, PRODUCTION, temporary / "schema.svh", False)
        print("DUPLICATE_JSON_KEY_REJECTION=PASS")


if __name__ == "__main__":
    unittest.main()
