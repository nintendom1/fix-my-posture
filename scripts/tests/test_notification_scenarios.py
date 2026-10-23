import copy
import importlib.util
import json
import struct
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


def png_header(path):
    data = Path(path).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG"
    kinds, offset = [], 8
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        kinds.append(kind.decode())
        if kind == b"IHDR":
            width, height, depth, color_type = struct.unpack(">IIBB", data[offset + 8:offset + 18])
        offset += 12 + length
    return kinds, (width, height, depth, color_type)


class ScenarioDataTests(unittest.TestCase):
    """Run everywhere: they need only the standard library."""

    def setUp(self):
        self.data = scenarios.load_scenarios()
        self.crops = list(json.loads((CHARACTER_DIR / "characters.json").read_text())["crops"])

    def assertInvalid(self, mutate, message):
        data = copy.deepcopy(self.data)
        mutate(data)
        with self.assertRaisesRegex(scenarios.ScenarioError, message):
            scenarios.validate(data, crop_presets=self.crops)

    def test_committed_scenarios_are_valid(self):
        scenarios.validate(self.data, crop_presets=self.crops)

    def test_every_row_of_the_issue_matrix_is_present(self):
        self.assertGreaterEqual(len(self.data["scenarios"]), 35)
        kinds = {scenario["kind"] for scenario in self.data["scenarios"]}
        self.assertEqual(kinds, {"nudge", "acknowledgment"})

    def test_close_crop_is_the_primary_art_for_exactly_the_heavier_moments(self):
        close = {s["id"] for s in self.data["scenarios"] if s["art"][0]["crop"] == "close"}
        self.assertEqual(close, {
            "established-streak-at-risk", "high-value-streak-at-risk", "first-ignored-reminder",
            "repeated-ignored-reminder", "strong-repeated-dismissal", "late-night-streak-at-risk",
            "final-streak-warning", "rare-escalation", "streak-broken",
        })

    def test_required_images_cover_every_expression_in_both_crops_plus_outfit_variants(self):
        names = {asset["name"] for asset in scenarios.required_assets(self.data)}
        for expression in ("normal", "smile", "smile2", "sad", "annoyed", "sleepy", "smug", "delighted", "laugh", "angry"):
            for crop in ("portrait", "close"):
                self.assertIn(f"{expression}-hoodie-{crop}", names)
        for name in ("sleepy-pajamas-portrait", "sleepy-pajamas-close", "sad-pajamas-close",
                     "smug-pe-uniform-portrait", "smile-coat-portrait",
                     "laugh-sundress-portrait", "delighted-sundress-portrait"):
            self.assertIn(name, names)
        self.assertEqual(len(names), 27)

    def test_every_scenario_image_is_in_the_required_list(self):
        names = {asset["name"] for asset in scenarios.required_assets(self.data)}
        for scenario in self.data["scenarios"]:
            for art in scenario["art"]:
                self.assertIn(scenarios.asset_name(**art), names)

    def test_generated_text_files_are_current(self):
        source_bytes = scenarios.SCENARIOS_PATH.read_bytes()
        self.assertEqual(scenarios.stale_text_artifacts(self.data, source_bytes), [])

    def test_generated_docs_name_every_scenario_and_line_of_copy(self):
        docs = scenarios.DOCS_PATH.read_text(encoding="utf-8")
        for scenario in self.data["scenarios"]:
            self.assertIn(scenario["id"], docs)
            for line in scenario["copy"]:
                self.assertIn(line, docs)

    def test_committed_images_are_flat_8_bit_rgb_pngs_with_only_an_srgb_chunk(self):
        for asset in scenarios.required_assets(self.data):
            path = scenarios.IMAGE_FOLDER / f"{asset['name']}.imageset" / f"{asset['name']}.png"
            kinds, (width, height, depth, color_type) = png_header(path)
            self.assertEqual(kinds[:2], ["IHDR", "sRGB"], asset["name"])
            self.assertEqual(set(kinds[2:]), {"IDAT", "IEND"}, asset["name"])
            self.assertEqual((width, height, depth, color_type), (512, 512, 8, 2), asset["name"])

    def test_validation_rejects_bad_data(self):
        self.assertInvalid(lambda d: d["scenarios"][0].update(id="Not Kebab"), "unique kebab-case")
        self.assertInvalid(lambda d: d["scenarios"][1].update(id=d["scenarios"][0]["id"]), "unique kebab-case")
        self.assertInvalid(lambda d: d["scenarios"][0].update(kind="shout"), "kind must be")
        self.assertInvalid(lambda d: d["scenarios"][0]["art"][0].update(outfit="tux"), "unknown outfit")
        self.assertInvalid(lambda d: d["scenarios"][0]["art"][0].update(crop="wide"), "unknown crop")
        self.assertInvalid(lambda d: d["scenarios"][0]["copy"].append("{streek} days"), "unknown token")
        self.assertInvalid(lambda d: d["scenarios"][0]["copy"].append("oops {"), "unbalanced braces")
        self.assertInvalid(lambda d: d["scenarios"][0]["copy"].append("x" * 200), "longer than")
        self.assertInvalid(lambda d: d["scenarios"][0]["copy"].__setitem__(1, d["scenarios"][0]["copy"][0]), "distinct")
        self.assertInvalid(lambda d: d["scenarios"][0].update(title="T" * 60), "title is longer")
        self.assertInvalid(lambda d: d["baselineAssets"].pop("crops"), "baselineAssets")
        self.assertInvalid(lambda d: d["cropPresets"].update(close="nope"), "unknown crop")
        self.assertInvalid(lambda d: d["tokens"].pop("days"), "document exactly")
        # early-streak-forming uses {streak}, so its sample must provide it.
        index = next(i for i, s in enumerate(self.data["scenarios"]) if s["id"] == "early-streak-forming")
        self.assertInvalid(lambda d: d["scenarios"][index].update(sample={}), "sample is missing")
        # Fewer copy lines than art entries would make an alternate image unreachable.
        index = next(i for i, s in enumerate(self.data["scenarios"]) if len(s["art"]) > 1)
        self.assertInvalid(lambda d: d["scenarios"][index].update(copy=d["scenarios"][index]["copy"][:1]), "as many copy lines")


@unittest.skipUnless(HAS_IMAGING, "psd-tools, Pillow and numpy are not installed; run `make notification-character`")
class GeneratedAssetTests(unittest.TestCase):
    def test_generated_images_match_a_fresh_render(self):
        renderer = load_module("render_character", "render_character.py")
        config = renderer.load_config()
        data, source_bytes = renderer.load_scenario_data(config)
        psd = renderer.open_psd(config)
        index = renderer.index_layers(psd)
        self.assertEqual(renderer.check_assets(config, psd, index, data, source_bytes), 27)


if __name__ == "__main__":
    unittest.main()
