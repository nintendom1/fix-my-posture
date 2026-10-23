import copy
import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CHARACTER_DIR = REPO_ROOT / "Design" / "NotificationCharacter"
SCRIPT = CHARACTER_DIR / "render_character.py"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
HAS_IMAGING = all(importlib.util.find_spec(name) for name in ("psd_tools", "PIL", "numpy"))


def load_renderer():
    spec = importlib.util.spec_from_file_location("render_character", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def png_chunks(path):
    data = Path(path).read_bytes()
    assert data[:8] == PNG_SIGNATURE, f"{path} is not a PNG"
    chunks, offset = [], 8
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        chunks.append((kind.decode(), data[offset + 8:offset + 8 + length]))
        offset += 12 + length
    return chunks


renderer = load_renderer()


class ConfigTests(unittest.TestCase):
    """Run everywhere: they need only the standard library."""

    def setUp(self):
        self.config = renderer.load_config()

    def assertInvalid(self, config, message):
        with self.assertRaisesRegex(renderer.RenderError, message):
            renderer.validate_config(config)

    def test_committed_config_is_valid(self):
        renderer.validate_config(self.config)

    def test_source_psd_matches_pinned_sha256(self):
        renderer.verify_source(self.config)

    def test_canonical_selects_the_documented_layers(self):
        spec = renderer.resolve_character(self.config, "canonical")
        self.assertEqual(
            renderer.character_layer_paths(self.config, spec),
            [
                "hair back/long/silver",
                "hair front/long/silver",
                "face/smile",
                "body/skin2",
                "body/blush/blush1",
                "outfit/hoodie",
            ],
        )

    def test_extends_overrides_only_what_it_names(self):
        sad = renderer.resolve_character(self.config, "canonical-sad")
        canonical = renderer.resolve_character(self.config, "canonical")
        self.assertEqual(sad["expression"], "sad")
        self.assertEqual({k: v for k, v in sad.items() if k != "expression"},
                         {k: v for k, v in canonical.items() if k != "expression"})

    def test_accessories_toggle_with_a_list(self):
        spec = renderer.resolve_character(self.config, "canonical")
        spec["accessories"] = ["choker", "flower"]
        paths = renderer.character_layer_paths(self.config, spec)
        self.assertEqual(paths[-2:], ["accessories/choker", "accessories/flower"])
        spec["accessories"] = None
        self.assertNotIn("accessories/choker", renderer.character_layer_paths(self.config, spec))

    def test_extends_cycle_is_rejected(self):
        self.config["characters"]["a"] = {"extends": "b"}
        self.config["characters"]["b"] = {"extends": "a"}
        with self.assertRaisesRegex(renderer.RenderError, "extends itself"):
            renderer.resolve_character(self.config, "a")

    def test_slot_value_must_match_the_template_fields(self):
        spec = renderer.resolve_character(self.config, "canonical")
        spec["hairBack"] = "silver"  # needs style and color
        with self.assertRaisesRegex(renderer.RenderError, "needs values for style, color"):
            renderer.character_layer_paths(self.config, spec)

    def test_character_must_set_every_slot_and_known_settings_only(self):
        spec = renderer.resolve_character(self.config, "canonical")
        del spec["outfit"]
        with self.assertRaisesRegex(renderer.RenderError, "missing setting.*outfit"):
            renderer.character_layer_paths(self.config, spec)
        spec = renderer.resolve_character(self.config, "canonical")
        spec["expresion"] = "smile"
        with self.assertRaisesRegex(renderer.RenderError, "Unknown character setting.*expresion"):
            renderer.character_layer_paths(self.config, spec)

    def test_validation_rejects_bad_references_and_geometry(self):
        config = copy.deepcopy(self.config)
        config["characters"]["canonical"]["background"] = "nope"
        self.assertInvalid(config, "Unknown background 'nope'")

        config = copy.deepcopy(self.config)
        config["crops"]["close-up"]["box"] = [300, 500, 180, 180]
        self.assertInvalid(config, "leaves the 400x600 canvas")

        config = copy.deepcopy(self.config)
        config["crops"]["close-up"]["box"] = [116, 150, 180, 120]
        self.assertInvalid(config, "must be square")

        config = copy.deepcopy(self.config)
        config["examples"][0]["crop"] = "nope"
        self.assertInvalid(config, "unknown character or crop")

        config = copy.deepcopy(self.config)
        config["backgrounds"]["fmp-app-dark"]["color"] = "purple"
        self.assertInvalid(config, "not a #RRGGBB color")

        config = copy.deepcopy(self.config)
        config["backgrounds"]["fmp-dark-purple"]["stops"][-1][0] = 0.9
        self.assertInvalid(config, "stops must ascend from 0 to 1")

        config = copy.deepcopy(self.config)
        config["layerMap"]["skin"] = "body/skin2"
        self.assertInvalid(config, "contain a \\{placeholder\\}")

    def test_committed_examples_are_flat_8_bit_rgb_pngs_with_only_an_srgb_chunk(self):
        for example in self.config["examples"]:
            chunks = png_chunks(CHARACTER_DIR / example["file"])
            kinds = [kind for kind, _ in chunks]
            self.assertEqual(kinds[:2], ["IHDR", "sRGB"], example["file"])
            self.assertEqual(set(kinds[2:]), {"IDAT", "IEND"}, example["file"])
            width, height, depth, color_type = struct.unpack(">IIBB", chunks[0][1][:10])
            size = self.config["crops"][example["crop"]]["size"]
            self.assertEqual((width, height, depth, color_type), (size, size, 8, 2), example["file"])


@unittest.skipUnless(HAS_IMAGING, "psd-tools, Pillow and numpy are not installed; run `make notification-character`")
class RenderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = renderer.load_config()
        cls.psd = renderer.open_psd(cls.config)
        cls.index = renderer.index_layers(cls.psd)

    def render(self, character, crop):
        return renderer.render(self.config, self.psd, self.index, character, crop)

    def test_every_character_resolves_to_real_psd_layers(self):
        for name in self.config["characters"]:
            paths = renderer.character_layer_paths(self.config, renderer.resolve_character(self.config, name))
            renderer.require_layers(self.index, paths)

    def test_repeated_names_are_told_apart_by_path(self):
        self.assertIn("hair back/long/silver", self.index)
        self.assertIn("hair front/long/silver", self.index)
        self.assertIsNot(self.index["hair back/long/silver"], self.index["hair front/long/silver"])

    def test_every_crop_renders_a_flat_square_rgb_image(self):
        for crop, settings in self.config["crops"].items():
            image = self.render("canonical", crop)
            self.assertEqual((image.mode, image.size), ("RGB", (settings["size"], settings["size"])), crop)

    def test_rendering_is_deterministic(self):
        from PIL import ImageChops

        first = self.render("canonical", "head-and-shoulders")
        second = self.render("canonical", "head-and-shoulders")
        self.assertIsNone(ImageChops.difference(first, second).getbbox())

    def test_a_different_expression_changes_the_pixels(self):
        from PIL import ImageChops

        smile = self.render("canonical", "close-up")
        sad = self.render("canonical-sad", "close-up")
        self.assertIsNotNone(ImageChops.difference(smile, sad).getbbox())
        # And rendering back is not polluted by the previous selection.
        self.assertIsNone(ImageChops.difference(smile, self.render("canonical", "close-up")).getbbox())

    def test_rendering_ignores_whatever_visibility_the_psd_was_left_in(self):
        from PIL import ImageChops

        x, y, w, h = self.config["crops"]["head-and-shoulders"]["box"]

        def composite_as_left():
            return self.psd.composite(viewport=(x, y, x + w, y + h), force=True).convert("RGBA")

        expected = self.render("canonical", "head-and-shoulders")
        selected_only = composite_as_left()
        for layer in self.index.values():
            layer.visible = True
        # The scramble must actually change what the PSD composites, or this test proves nothing.
        self.assertIsNotNone(ImageChops.difference(selected_only, composite_as_left()).getbbox())
        self.assertIsNone(ImageChops.difference(expected, self.render("canonical", "head-and-shoulders")).getbbox())

    def test_unknown_layers_list_the_valid_choices(self):
        with self.assertRaisesRegex(renderer.RenderError, "face/grin.*smile.*sad"):
            renderer.require_layers(self.index, ["face/grin"])
        with self.assertRaisesRegex(renderer.RenderError, "is a group, not a layer"):
            renderer.require_layers(self.index, ["body/blush"])

    def test_written_png_has_an_srgb_chunk_and_no_alpha(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "portrait.png"
            renderer.save_png(self.render("canonical", "head-and-shoulders"), out)
            chunks = png_chunks(out)
        kinds = [kind for kind, _ in chunks]
        self.assertEqual(kinds[:2], ["IHDR", "sRGB"])
        self.assertEqual(set(kinds[2:]), {"IDAT", "IEND"})
        self.assertEqual(chunks[0][1][9], 2)  # PNG color type 2: RGB, no alpha

    def test_committed_examples_match_a_fresh_render(self):
        renderer.check_examples(self.config, self.psd, self.index)


if __name__ == "__main__":
    unittest.main()
