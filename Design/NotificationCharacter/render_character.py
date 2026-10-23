#!/usr/bin/env python3
"""Render notification character portraits from the chibi PSD.

A character is a set of PSD layer paths chosen in characters.json (no layer numbers), composited over
a named background, cropped with a named preset, and written as a flattened 8-bit sRGB PNG with no
alpha channel and no other metadata. The pipeline never uses generative AI: every pixel comes from the
PSD's own layers or from a gradient described in the config.

    python3 render_character.py --list                               # characters, crops, backgrounds, layer choices
    python3 render_character.py --character canonical --crop close-up
    python3 render_character.py --examples                           # rewrite the committed example PNGs
    python3 render_character.py --assets                             # rewrite the app's notification images, data set, docs
    python3 render_character.py --check                              # fail if an example or generated asset is stale

Needs psd-tools and Pillow from requirements.txt; `make notification-character` sets up a venv for them.
"""

import argparse
import hashlib
import json
import re
import shutil
import string
import sys
from pathlib import Path

DESIGN_DIR = Path(__file__).resolve().parent
REPO_ROOT = DESIGN_DIR.parent.parent
CONFIG_PATH = DESIGN_DIR / "characters.json"
DEFAULT_OUT_DIR = REPO_ROOT / "build/notification-character"

# The sibling module is imported by path so the tests, which load this file by path, find it too.
sys.path.insert(0, str(DESIGN_DIR))
import notification_scenarios as scenarios  # noqa: E402

TOP_LEVEL_KEYS = ("source", "layerMap", "backgrounds", "crops", "characters", "examples")
HEX_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")


class RenderError(Exception):
    """A configuration, source, or rendering problem with a message meant for the user."""


def load_config(path=CONFIG_PATH):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def source_path(config):
    return DESIGN_DIR / config["source"]["file"]


def verify_source(config):
    path = source_path(config)
    if not path.is_file():
        raise RenderError(f"Source PSD not found at {path}. See Source/README.md.")
    actual = sha256_of(path)
    if actual != config["source"]["sha256"]:
        raise RenderError(
            f"{path.name} does not match the pinned SHA-256.\n"
            f"  expected {config['source']['sha256']}\n  actual   {actual}"
        )


def parse_hex(color):
    if not isinstance(color, str) or not HEX_COLOR.match(color):
        raise RenderError(f"'{color}' is not a #RRGGBB color.")
    return tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))


def placeholders(template):
    return tuple(field for _, field, _, _ in string.Formatter().parse(template) if field)


def is_placeholder(segment):
    return segment.startswith("{") and segment.endswith("}")


def resolve_character(config, name, _seen=()):
    """The character's settings with `extends` chains merged, child values winning."""
    characters = config["characters"]
    if name not in characters:
        raise RenderError(f"Unknown character '{name}'. Choices: {', '.join(characters)}.")
    if name in _seen:
        raise RenderError(f"Character '{name}' extends itself: {' -> '.join(_seen + (name,))}.")
    spec = dict(characters[name])
    parent = spec.pop("extends", None)
    if parent is None:
        return spec
    merged = resolve_character(config, parent, _seen + (name,))
    merged.update(spec)
    return merged


def slot_paths(config, slot, value):
    """PSD layer paths a slot's value selects. null and [] select nothing; a list selects several."""
    template = config["layerMap"][slot]
    fields = placeholders(template)
    if value is None:
        return []
    items = value if isinstance(value, list) else [value]
    paths = []
    for item in items:
        if isinstance(item, str):
            item = {"name": item}
        if not isinstance(item, dict) or set(item) != set(fields):
            raise RenderError(
                f"Slot '{slot}' ({template}) needs values for {', '.join(fields)}; got {json.dumps(value)}."
            )
        if not all(isinstance(part, str) and part for part in item.values()):
            raise RenderError(f"Slot '{slot}' values must be non-empty strings; got {json.dumps(value)}.")
        paths.append(template.format(**item))
    return paths


def character_layer_paths(config, spec):
    """All PSD layer paths for a resolved character, in layerMap order."""
    slots = config["layerMap"]
    unknown = set(spec) - set(slots) - {"background"}
    if unknown:
        raise RenderError(f"Unknown character setting(s): {', '.join(sorted(unknown))}.")
    missing = [slot for slot in slots if slot not in spec]
    if missing:
        raise RenderError(f"Character is missing setting(s): {', '.join(missing)} (use null for none).")
    if spec.get("background") not in config["backgrounds"]:
        raise RenderError(
            f"Unknown background '{spec.get('background')}'. Choices: {', '.join(config['backgrounds'])}."
        )
    return [path for slot in slots for path in slot_paths(config, slot, spec[slot])]


def validate_config(config):
    """Check characters.json for internal consistency without opening the PSD."""
    for key in TOP_LEVEL_KEYS:
        if key not in config:
            raise RenderError(f"characters.json is missing '{key}'.")
    canvas = config["source"].get("canvas")
    if not (isinstance(canvas, list) and len(canvas) == 2 and all(isinstance(n, int) and n > 0 for n in canvas)):
        raise RenderError("source.canvas must be [width, height].")

    for slot, template in config["layerMap"].items():
        segments = template.split("/")
        if is_placeholder(segments[0]) or not any(is_placeholder(s) for s in segments):
            raise RenderError(f"layerMap.{slot} must start with a group name and contain a {{placeholder}}.")
        for segment in segments:
            if ("{" in segment or "}" in segment) and not (is_placeholder(segment) and len(placeholders(segment)) == 1):
                raise RenderError(f"layerMap.{slot}: '{segment}' must be a whole {{placeholder}} or plain text.")

    for name, background in config["backgrounds"].items():
        kind = background.get("type")
        if kind == "solid":
            parse_hex(background.get("color"))
        elif kind == "linear-gradient":
            for key in ("from", "to"):
                point = background.get(key)
                if not (isinstance(point, list) and len(point) == 2):
                    raise RenderError(f"backgrounds.{name}.{key} must be [x, y] in 0-1 crop coordinates.")
            if background["from"] == background["to"]:
                raise RenderError(f"backgrounds.{name}: 'from' and 'to' must differ.")
            offsets = [stop[0] for stop in background.get("stops", [])]
            if len(offsets) < 2 or offsets[0] != 0 or offsets[-1] != 1 or offsets != sorted(offsets):
                raise RenderError(f"backgrounds.{name}.stops must ascend from 0 to 1 with at least two stops.")
            for stop in background["stops"]:
                parse_hex(stop[1])
        else:
            raise RenderError(f"backgrounds.{name}.type must be 'solid' or 'linear-gradient'.")

    width, height = canvas
    for name, crop in config["crops"].items():
        box, size = crop.get("box"), crop.get("size")
        if not (isinstance(box, list) and len(box) == 4 and all(isinstance(n, int) for n in box)):
            raise RenderError(f"crops.{name}.box must be [x, y, width, height].")
        x, y, w, h = box
        if w != h or w <= 0:
            raise RenderError(f"crops.{name}.box must be square.")
        if x < 0 or y < 0 or x + w > width or y + h > height:
            raise RenderError(f"crops.{name}.box leaves the {width}x{height} canvas.")
        if not (isinstance(size, int) and size > 0):
            raise RenderError(f"crops.{name}.size must be a positive integer (square output).")

    for name in config["characters"]:
        character_layer_paths(config, resolve_character(config, name))

    for example in config["examples"]:
        if example.get("character") not in config["characters"] or example.get("crop") not in config["crops"]:
            raise RenderError(f"Example {json.dumps(example)} names an unknown character or crop.")
        if not str(example.get("file", "")).endswith(".png"):
            raise RenderError(f"Example {json.dumps(example)} needs a .png file path.")


def require_imaging():
    try:
        import numpy  # noqa: F401
        import PIL  # noqa: F401
        import psd_tools  # noqa: F401
    except ModuleNotFoundError as error:
        raise RenderError(
            f"Missing Python package '{error.name}'. Run `make notification-character` to build the venv, "
            "or `pip install -r Design/NotificationCharacter/requirements.txt`."
        )


def open_psd(config):
    require_imaging()
    from psd_tools import PSDImage

    verify_source(config)
    psd = PSDImage.open(source_path(config))
    if list(psd.size) != config["source"]["canvas"]:
        raise RenderError(f"PSD canvas is {psd.width}x{psd.height}, not {config['source']['canvas']}.")
    return psd


def index_layers(psd):
    """Map each layer's full group path (for example 'hair back/long/silver') to its layer.

    Names repeat across groups, so paths, not bare names, are the stable identity."""
    index = {}

    def walk(group, prefix):
        for layer in group:
            path = prefix + layer.name
            if path in index:
                raise RenderError(f"The PSD has two layers at '{path}'.")
            index[path] = layer
            if layer.is_group():
                walk(layer, path + "/")

    walk(psd, "")
    return index


def children_of(index, prefix):
    depth = prefix.count("/") + 1 if prefix else 0
    return [
        path.rsplit("/", 1)[-1]
        for path in reversed(index)  # top to bottom, as the Photoshop Layers panel shows them
        if path.count("/") == depth and (not prefix or path.startswith(prefix + "/"))
    ]


def require_layers(index, paths):
    for path in paths:
        layer = index.get(path)
        if layer is not None and not layer.is_group():
            continue
        if layer is not None:
            raise RenderError(f"'{path}' is a group, not a layer. Choices: {', '.join(children_of(index, path))}.")
        parts = path.split("/")
        known = ""
        for i in range(len(parts)):
            candidate = "/".join(parts[:i + 1])
            if candidate not in index or not index[candidate].is_group():
                break
            known = candidate
        where = f"under '{known}'" if known else "at the top level"
        raise RenderError(f"No PSD layer '{path}'. Choices {where}: {', '.join(children_of(index, known))}.")


def make_background(background, size):
    """An opaque RGBA image of the background at `size` (width, height)."""
    import numpy as np
    from PIL import Image

    width, height = size
    if background["type"] == "solid":
        return Image.new("RGBA", size, parse_hex(background["color"]) + (255,))
    x0, y0 = background["from"]
    x1, y1 = background["to"]
    gx, gy = np.meshgrid((np.arange(width) + 0.5) / width, (np.arange(height) + 0.5) / height)
    dx, dy = x1 - x0, y1 - y0
    t = np.clip(((gx - x0) * dx + (gy - y0) * dy) / (dx * dx + dy * dy), 0, 1)
    offsets = [stop[0] for stop in background["stops"]]
    colors = np.array([parse_hex(stop[1]) for stop in background["stops"]], dtype=float)
    rgb = np.stack([np.interp(t, offsets, colors[:, channel]) for channel in range(3)], axis=-1)
    rgba = np.dstack([np.rint(rgb).astype(np.uint8), np.full((height, width), 255, dtype=np.uint8)])
    return Image.fromarray(rgba)


def render(config, psd, index, character, crop):
    """Flattened RGB portrait for a character name and crop name."""
    return render_spec(config, psd, index, resolve_character(config, character), crop)


def render_spec(config, psd, index, spec, crop):
    """Flattened RGB portrait for resolved character settings and a crop name."""
    from PIL import Image

    if crop not in config["crops"]:
        raise RenderError(f"Unknown crop '{crop}'. Choices: {', '.join(config['crops'])}.")
    paths = character_layer_paths(config, spec)
    require_layers(index, paths)

    selected = set(paths)
    for path, layer in index.items():
        # Ignore the PSD's saved visibility: groups open, only the chosen leaves on.
        layer.visible = layer.is_group() or path in selected

    x, y, w, h = config["crops"][crop]["box"]
    size = config["crops"][crop]["size"]
    figure = psd.composite(viewport=(x, y, x + w, y + h), force=True).convert("RGBA")
    # Flatten onto the opaque background first, then resize, so transparent edge pixels never fringe.
    flat = Image.alpha_composite(make_background(config["backgrounds"][spec["background"]], (w, h)), figure)
    flat = flat.convert("RGB")
    if (w, h) != (size, size):
        flat = flat.resize((size, size), Image.Resampling.LANCZOS)
    return flat


def save_png(image, path):
    """8-bit RGB PNG with an sRGB chunk and nothing else, matching the app icon export."""
    from PIL import PngImagePlugin

    info = PngImagePlugin.PngInfo()
    info.add(b"sRGB", b"\x00")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", pnginfo=info, optimize=False, compress_level=9)


def list_choices(config, index):
    print("Characters:")
    for name in config["characters"]:
        spec = resolve_character(config, name)
        print(f"  {name}: {json.dumps(spec)}")
    print("Crops:")
    for name, crop in config["crops"].items():
        print(f"  {name}: box {crop['box']} -> {crop['size']}x{crop['size']}")
    print("Backgrounds:")
    for name, background in config["backgrounds"].items():
        print(f"  {name}: {background['type']}")
    print("Layer choices per slot (a PSD path is the template with each {placeholder} filled in):")
    for slot, template in config["layerMap"].items():
        segments = template.split("/")
        open_at = [i for i, segment in enumerate(segments) if is_placeholder(segment)]
        grouped = {}
        for path, layer in reversed(index.items()):  # top to bottom, as the Photoshop Layers panel shows them
            parts = path.split("/")
            if layer.is_group() or len(parts) != len(segments):
                continue
            if all(is_placeholder(s) or s == p for s, p in zip(segments, parts)):
                values = [parts[i] for i in open_at]
                grouped.setdefault("/".join(values[:-1]), []).append(values[-1])
        print(f"  {slot}  ({template})")
        for label, leaves in grouped.items():
            print(f"    {label + ': ' if label else ''}{', '.join(leaves)}")


def write_examples(config, psd, index):
    for example in config["examples"]:
        image = render(config, psd, index, example["character"], example["crop"])
        out = DESIGN_DIR / example["file"]
        save_png(image, out)
        print(f"Wrote {out.relative_to(REPO_ROOT)}")


def check_examples(config, psd, index):
    """Compare decoded pixels, not bytes, so a different zlib build cannot fail the check."""
    from PIL import Image, ImageChops

    stale = []
    for example in config["examples"]:
        committed = DESIGN_DIR / example["file"]
        if not committed.is_file():
            stale.append(f"{example['file']} is missing")
            continue
        fresh = render(config, psd, index, example["character"], example["crop"])
        with Image.open(committed) as existing:
            existing = existing.convert("RGB")
        if existing.size != fresh.size or ImageChops.difference(existing, fresh).getbbox() is not None:
            stale.append(f"{example['file']} does not match a fresh render")
    if stale:
        raise RenderError("Stale examples:\n  " + "\n  ".join(stale) + "\nRun with --examples and commit the result.")
    return len(config["examples"])


def load_scenario_data(config):
    """The validated notification scenarios and the exact bytes of their source file."""
    try:
        data = scenarios.load_scenarios()
        scenarios.validate(data, crop_presets=list(config["crops"]))
    except scenarios.ScenarioError as error:
        raise RenderError(str(error))
    return data, scenarios.SCENARIOS_PATH.read_bytes()


def asset_render_inputs(config, data, asset):
    """Resolved settings and crop preset for one app image: the canonical character in that expression and outfit."""
    spec = resolve_character(config, "canonical")
    spec["expression"] = asset["expression"]
    spec["outfit"] = data["outfits"][asset["outfit"]]
    return spec, data["cropPresets"][asset["crop"]]


def asset_png_path(asset):
    return scenarios.IMAGE_FOLDER / f"{asset['name']}.imageset" / f"{asset['name']}.png"


def write_assets(config, psd, index, data, source_bytes):
    """Write the app's notification images, scenario data set, and docs, removing images no scenario uses."""
    assets = scenarios.required_assets(data)
    expected_folders = {f"{asset['name']}.imageset" for asset in assets}
    if scenarios.IMAGE_FOLDER.is_dir():
        for folder in scenarios.IMAGE_FOLDER.glob("*.imageset"):
            if folder.name not in expected_folders:
                shutil.rmtree(folder)
    for path, content in scenarios.text_artifacts(data, source_bytes).items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    for asset in assets:
        spec, crop = asset_render_inputs(config, data, asset)
        save_png(render_spec(config, psd, index, spec, crop), asset_png_path(asset))
    print(f"Wrote {len(assets)} images, the scenario data set, and {scenarios.DOCS_PATH.relative_to(REPO_ROOT)}")


def check_assets(config, psd, index, data, source_bytes):
    """Compare generated text files exactly and images by decoded pixels. Returns the image count."""
    from PIL import Image, ImageChops

    stale = scenarios.stale_text_artifacts(data, source_bytes)
    assets = scenarios.required_assets(data)
    for asset in assets:
        committed = asset_png_path(asset)
        if not committed.is_file():
            stale.append(f"{committed.relative_to(REPO_ROOT)} is missing")
            continue
        spec, crop = asset_render_inputs(config, data, asset)
        fresh = render_spec(config, psd, index, spec, crop)
        with Image.open(committed) as existing:
            existing = existing.convert("RGB")
        if existing.size != fresh.size or ImageChops.difference(existing, fresh).getbbox() is not None:
            stale.append(f"{committed.relative_to(REPO_ROOT)} does not match a fresh render")
    if stale:
        raise RenderError("Stale generated assets:\n  " + "\n  ".join(stale) + "\nRun with --assets and commit the result.")
    return len(assets)


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="list characters, crops, backgrounds, and layer choices")
    parser.add_argument("--character", help="character name from characters.json")
    parser.add_argument("--crop", help="crop preset name from characters.json")
    parser.add_argument("--out", type=Path, help="output PNG path (default build/notification-character/<character>-<crop>.png)")
    parser.add_argument("--examples", action="store_true", help="rewrite the committed example PNGs")
    parser.add_argument("--assets", action="store_true",
                        help="rewrite the app's notification images, scenario data set, and docs from notification-scenarios.json")
    parser.add_argument("--check", action="store_true",
                        help="fail if a committed example or generated asset differs from a fresh render")
    args = parser.parse_args(argv)
    modes = [args.list, args.examples, args.assets, args.check, bool(args.character or args.crop)]
    if sum(modes) != 1:
        parser.error("choose exactly one of --list, --examples, --assets, --check, or --character with --crop")
    if (args.character or args.crop) and not (args.character and args.crop):
        parser.error("--character and --crop go together")
    if args.out and not args.character:
        parser.error("--out only applies to --character/--crop")
    return args


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        config = load_config()
        validate_config(config)
        psd = open_psd(config)
        index = index_layers(psd)
        if args.list:
            list_choices(config, index)
        elif args.examples:
            write_examples(config, psd, index)
        elif args.assets:
            data, source_bytes = load_scenario_data(config)
            write_assets(config, psd, index, data, source_bytes)
        elif args.check:
            count = check_examples(config, psd, index)
            data, source_bytes = load_scenario_data(config)
            image_count = check_assets(config, psd, index, data, source_bytes)
            print(f"{count} example(s) match the PSD and characters.json.")
            print(f"{image_count} notification image(s), the scenario data set, and the docs match notification-scenarios.json.")
        else:
            out = args.out or DEFAULT_OUT_DIR / f"{args.character}-{args.crop}.png"
            save_png(render(config, psd, index, args.character, args.crop), out)
            print(f"Wrote {out}")
    except RenderError as error:
        sys.exit(f"Error: {error}")


if __name__ == "__main__":
    main()
