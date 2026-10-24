import copy
import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CHARACTER_DIR = REPO_ROOT / "Design" / "NotificationCharacter"
HAS_IMAGING = all(importlib.util.find_spec(name) for name in ("psd_tools", "PIL", "numpy"))


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, CHARACTER_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


scenarios = load_module("notification_scenarios", "notification_scenarios.py")
persona = load_module("persona_content", "persona_content.py")


class PersonaContentTests(unittest.TestCase):
    """Schema, copy, and generated-text checks use only the standard library."""

    def setUp(self):
        self.committed_data = json.loads(persona.PERSONA_CONTENT_PATH.read_text(encoding="utf-8"))
        self.data = copy.deepcopy(self.committed_data)
        self.scenario_data = scenarios.load_scenarios()
        self.expressions = scenarios.known_expressions()

    def assertInvalid(self, mutate, message):
        data = copy.deepcopy(self.data)
        mutate(data)
        with self.assertRaisesRegex(persona.PersonaContentError, message):
            persona.validate(data, self.scenario_data, expression_choices=self.expressions)

    def test_committed_content_validates(self):
        persona.validate(self.committed_data, self.scenario_data, expression_choices=self.expressions)

    def test_every_swift_content_key_is_present(self):
        fixture = (REPO_ROOT / "PostureAnalysisApp/Tests/Support/PersonaFixtures.swift").read_text(encoding="utf-8")
        block = fixture.split("static let contentKeys = [", 1)[1].split("]", 1)[0]
        expected = set(re.findall(r'"([a-z]+(?:\.[a-zA-Z]+)+)"', block))
        self.assertTrue(expected)
        self.assertEqual(expected, set(self.data["content"]), "Swift content keys and persona-content.json must match")

    def test_swift_tone_and_family_enums_match_the_validator(self):
        types = (REPO_ROOT / "PostureAnalysisApp/Notifications/Persona/PersonaTypes.swift").read_text(encoding="utf-8")

        def cases(enum_name):
            body = types.split(f"enum {enum_name}:", 1)[1].split("\n}", 1)[0]
            return {name for line in re.findall(r"^\s*case ([a-zA-Z, ]+)$", body, re.M) for name in re.split(r",\s*", line)}

        self.assertEqual(cases("PersonaTone"), set(persona.TONES))
        self.assertEqual(cases("ObservationFamily"), set(persona.FAMILIES))
        self.assertEqual(cases("PersonaFamiliarity"), set(persona.FAMILIARITIES))

    def test_authored_string_count_stays_within_the_budget(self):
        count = persona.string_count(self.data)
        self.assertTrue(60 <= count <= 120, f"{count} authored strings; the v1 budget is about 80 (60–120)")

    def test_negative_lines_need_established_familiarity(self):
        def mutate(data):
            data["content"]["lapse.skippedExercise"]["body"].append(
                {"text": "{exercise} again. Really?", "tones": ["annoyed"], "minFamiliarity": "familiar"}
            )
        self.assertInvalid(mutate, "annoyed or disappointed lines need minFamiliarity established")

    def test_intro_must_fit_every_tone_at_new(self):
        def mutate(data):
            data["fragments"]["intro"] = [{"text": "I notice things.", "tones": ["proud"]}]
        self.assertInvalid(mutate, "intro: needs a line eligible for tone")

    def test_required_assets_include_persona_and_scenario_union(self):
        scenario_assets = scenarios.required_assets(self.scenario_data)
        persona_assets = persona.required_assets(self.data, self.scenario_data)
        scenario_names = {asset["name"] for asset in scenario_assets}
        union_names = scenario_names | {asset["name"] for asset in persona_assets}
        self.assertEqual(len(scenario_names), 27)
        self.assertEqual(len(union_names), 28)
        self.assertIn("shocked-hoodie-close", union_names)
        self.assertTrue(scenario_names <= union_names)

    def test_generated_dataset_and_docs_are_byte_exact(self):
        source_bytes = persona.PERSONA_CONTENT_PATH.read_bytes()
        expected = persona.text_artifacts(self.committed_data, self.scenario_data, source_bytes)
        for path, content in expected.items():
            with self.subTest(path=path.relative_to(REPO_ROOT)):
                self.assertTrue(path.is_file(), f"{path.relative_to(REPO_ROOT)} is missing")
                self.assertEqual(path.read_bytes(), content)
        self.assertEqual(
            (persona.DATASET_FOLDER / "persona-content.json").read_bytes(),
            source_bytes,
        )

    def test_unknown_expression_is_rejected(self):
        self.assertInvalid(
            lambda d: d["toneArt"]["proud"].update(expression="not-a-psd-expression"),
            "unknown expression",
        )

    def test_unknown_outfit_is_rejected(self):
        self.assertInvalid(lambda d: d["toneArt"]["proud"].update(outfit="spacesuit"), "unknown outfit")

    def test_unknown_crop_is_rejected(self):
        self.assertInvalid(lambda d: d["toneArt"]["proud"].update(crop="wide"), "unknown crop")

    def test_missing_tone_art_is_rejected(self):
        self.assertInvalid(lambda d: d["toneArt"].pop("warm"), "toneArt is missing tone 'warm'")

    def test_unknown_tone_in_variant_is_rejected(self):
        self.assertInvalid(
            lambda d: d["content"]["achievement.pr.weight"]["title"][0].update(tones=["cheery"]),
            "unknown tone",
        )

    def test_unknown_familiarity_is_rejected(self):
        self.assertInvalid(
            lambda d: d["content"]["achievement.pr.weight"]["title"][0].update(minFamiliarity="old"),
            "unknown familiarity",
        )

    def test_unknown_token_is_rejected(self):
        self.assertInvalid(
            lambda d: d["content"]["achievement.pr.weight"]["title"][0].update(text="A {unlisted}"),
            "unknown token",
        )

    def test_reserved_token_is_rejected(self):
        self.assertInvalid(
            lambda d: d["content"]["achievement.pr.weight"]["title"][0].update(text="Hi {name}"),
            "reserved token",
        )

    def test_used_token_must_be_listed_by_entry(self):
        self.assertInvalid(
            lambda d: d["content"]["achievement.pr.weight"]["title"][0].update(text="{count} reps"),
            "used but not listed",
        )

    def test_every_non_reserved_token_needs_a_sample(self):
        self.assertInvalid(lambda d: d["sampleValues"].pop("exercise"), "sampleValues is missing token 'exercise'")

    def test_duplicate_json_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "duplicate.json"
            path.write_text(
                '{"content": {"achievement.pr.weight": {}, "achievement.pr.weight": {}}}',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(persona.PersonaContentError, "duplicate key 'achievement.pr.weight'"):
                persona.load_content(path, scenario_data=self.scenario_data, expression_choices=self.expressions)

    def test_empty_body_list_is_rejected(self):
        self.assertInvalid(lambda d: d["content"]["achievement.pr.weight"].update(body=[]), "body must be a non-empty list")

    def test_overlong_title_is_rejected(self):
        self.assertInvalid(
            lambda d: d["content"]["achievement.pr.weight"]["title"][0].update(text="T" * 37),
            "title is longer than 36",
        )

    def test_overlong_body_is_rejected(self):
        self.assertInvalid(
            lambda d: d["content"]["achievement.pr.weight"]["body"][0].update(text="B" * 71),
            "body is longer than 70",
        )

    def test_overlong_fragment_is_rejected(self):
        self.assertInvalid(
            lambda d: d["fragments"]["intro"][0].update(text="F" * 19),
            "fragment is longer than 18",
        )

    def test_family_must_match_the_content_key(self):
        self.assertInvalid(lambda d: d["content"]["achievement.pr.weight"].update(family="lapse"), "family must be 'achievement'")

    def test_annoyed_cannot_be_the_default_tone(self):
        self.assertInvalid(
            lambda d: d["content"]["achievement.pr.weight"].update(defaultTone="annoyed"),
            "defaultTone must not be annoyed or disappointed",
        )

    def test_fragments_cannot_use_tokens(self):
        self.assertInvalid(lambda d: d["fragments"]["intro"][0].update(text="Count {count}"), "fragments must not use tokens")

    def test_unbalanced_braces_are_rejected(self):
        self.assertInvalid(
            lambda d: d["content"]["achievement.pr.weight"]["title"][0].update(text="Oops {"),
            "unbalanced braces",
        )


@unittest.skipUnless(HAS_IMAGING, "psd-tools, Pillow and numpy are not installed; run `make notification-character`")
class PersonaRenderedAssetTests(unittest.TestCase):
    def test_shared_images_match_a_fresh_render(self):
        renderer = load_module("render_character", "render_character.py")
        config = renderer.load_config()
        psd = renderer.open_psd(config)
        index = renderer.index_layers(psd)
        expressions = renderer.children_of(index, "face")
        scenario_data, scenario_bytes = renderer.load_scenario_data(config, expressions)
        content, content_bytes = renderer.load_persona_content(config, scenario_data, expressions)
        self.assertEqual(
            renderer.check_assets(
                config, psd, index, scenario_data, scenario_bytes, content, content_bytes, expressions,
            ),
            28,
        )


if __name__ == "__main__":
    unittest.main()
