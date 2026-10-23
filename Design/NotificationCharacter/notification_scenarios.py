"""Notification scenario data: validation and the text artifacts generated from it.

notification-scenarios.json is the one source of truth for the character's notification states. This
module, which needs only the standard library, validates it and produces three things from it:

  - the list of portrait images the app needs (rendered by render_character.py),
  - the asset-catalog data set the app loads at runtime, and
  - docs/notification-scenarios.md, the readable table of every scenario.

render_character.py --assets writes them and --check fails when any is stale.
"""

import json
import re
from pathlib import Path

DESIGN_DIR = Path(__file__).resolve().parent
REPO_ROOT = DESIGN_DIR.parent.parent
SCENARIOS_PATH = DESIGN_DIR / "notification-scenarios.json"
ASSET_CATALOG = REPO_ROOT / "PostureAnalysisApp/Assets.xcassets"
IMAGE_FOLDER = ASSET_CATALOG / "NotificationCharacter"
DATASET_FOLDER = ASSET_CATALOG / "NotificationScenarios.dataset"
DOCS_PATH = REPO_ROOT / "docs/notification-scenarios.md"

KINDS = ("nudge", "acknowledgment")
TOKENS = ("suggestion", "streak", "record", "remaining", "days")
SAMPLE_TOKENS = tuple(token for token in TOKENS if token != "suggestion")
MAX_TITLE_LENGTH = 36
MAX_COPY_LENGTH = 110
TOKEN_PATTERN = re.compile(r"\{([^{}]*)\}")
ID_PATTERN = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
XCODE_JSON = {"indent": 2, "separators": (",", " : "), "ensure_ascii": False}


class ScenarioError(Exception):
    """A problem in notification-scenarios.json, with a message meant for the user."""


def load_scenarios(path=SCENARIOS_PATH):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def tokens_in(text):
    return TOKEN_PATTERN.findall(text)


def asset_name(expression, outfit, crop):
    return f"{expression}-{outfit}-{crop}"


def validate(data, crop_presets=None):
    """Check the scenario data for internal consistency. `crop_presets` are the renderer's crop names."""
    for key in ("version", "sampleSuggestion", "tokens", "cropPresets", "outfits", "baselineAssets", "scenarios"):
        if key not in data:
            raise ScenarioError(f"notification-scenarios.json is missing '{key}'.")
    if data["version"] != 1:
        raise ScenarioError(f"Unsupported scenario file version {data['version']}.")
    if set(data["tokens"]) != set(TOKENS):
        raise ScenarioError(f"'tokens' must document exactly: {', '.join(TOKENS)}.")

    crops, outfits = data["cropPresets"], data["outfits"]
    if set(crops) != {"portrait", "close"}:
        raise ScenarioError("'cropPresets' must map exactly 'portrait' and 'close'.")
    if crop_presets is not None:
        for name, preset in crops.items():
            if preset not in crop_presets:
                raise ScenarioError(f"cropPresets.{name} names unknown crop '{preset}'. Choices: {', '.join(crop_presets)}.")
    if not outfits or any(not isinstance(v, str) or not v for v in outfits.values()):
        raise ScenarioError("'outfits' must map each outfit name to a PSD outfit layer.")

    def check_art(art, where):
        if not isinstance(art, dict) or set(art) != {"expression", "outfit", "crop"}:
            raise ScenarioError(f"{where}: art needs exactly expression, outfit, and crop.")
        if not isinstance(art["expression"], str) or not art["expression"]:
            raise ScenarioError(f"{where}: expression must be a non-empty string.")
        if art["outfit"] not in outfits:
            raise ScenarioError(f"{where}: unknown outfit '{art['outfit']}'. Choices: {', '.join(outfits)}.")
        if art["crop"] not in crops:
            raise ScenarioError(f"{where}: unknown crop '{art['crop']}'. Choices: {', '.join(crops)}.")

    baseline = data["baselineAssets"]
    if set(baseline) != {"expressions", "outfit", "crops"} or not baseline["expressions"] or not baseline["crops"]:
        raise ScenarioError("baselineAssets needs expressions, outfit, and crops.")
    for crop in baseline["crops"]:
        for expression in baseline["expressions"]:
            check_art({"expression": expression, "outfit": baseline["outfit"], "crop": crop}, "baselineAssets")

    seen_ids = set()
    for scenario in data["scenarios"]:
        sid = scenario.get("id", "<missing id>")
        where = f"scenario '{sid}'"
        required = {"id", "name", "kind", "trigger", "tone", "art", "title", "copy", "sample"}
        if set(scenario) != required:
            raise ScenarioError(f"{where} must have exactly: {', '.join(sorted(required))}.")
        if not ID_PATTERN.match(sid) or sid in seen_ids:
            raise ScenarioError(f"{where}: id must be unique kebab-case.")
        seen_ids.add(sid)
        if scenario["kind"] not in KINDS:
            raise ScenarioError(f"{where}: kind must be one of {', '.join(KINDS)}.")
        for field in ("name", "trigger", "tone"):
            if not isinstance(scenario[field], str) or not scenario[field].strip():
                raise ScenarioError(f"{where}: {field} must be non-empty text.")
        if not scenario["art"]:
            raise ScenarioError(f"{where}: needs at least one art entry.")
        for art in scenario["art"]:
            check_art(art, where)
        if len({asset_name(**art) for art in scenario["art"]}) != len(scenario["art"]):
            raise ScenarioError(f"{where}: art entries must be distinct.")

        title, copy = scenario["title"], scenario["copy"]
        if not isinstance(title, str) or not title.strip():
            raise ScenarioError(f"{where}: title must be non-empty text.")
        if not isinstance(copy, list) or not copy or len(set(copy)) != len(copy):
            raise ScenarioError(f"{where}: copy needs one or more distinct lines.")
        if len(copy) < len(scenario["art"]):
            raise ScenarioError(f"{where}: needs at least as many copy lines as art entries.")

        sample = scenario["sample"]
        if not isinstance(sample, dict) or any(k not in SAMPLE_TOKENS or not isinstance(v, int) for k, v in sample.items()):
            raise ScenarioError(f"{where}: sample may only hold integer values for {', '.join(SAMPLE_TOKENS)}.")
        used = set()
        for text in [title, *copy]:
            if not isinstance(text, str) or not text.strip():
                raise ScenarioError(f"{where}: titles and copy must be non-empty text.")
            for token in tokens_in(text):
                if token not in TOKENS:
                    raise ScenarioError(f"{where}: unknown token '{{{token}}}' in \"{text}\".")
                used.add(token)
            if "{" in TOKEN_PATTERN.sub("", text) or "}" in TOKEN_PATTERN.sub("", text):
                raise ScenarioError(f"{where}: unbalanced braces in \"{text}\".")
        missing = used - {"suggestion"} - set(sample)
        if missing:
            raise ScenarioError(f"{where}: sample is missing values for {', '.join(sorted(missing))}.")
        if len(title) > MAX_TITLE_LENGTH:
            raise ScenarioError(f"{where}: title is longer than {MAX_TITLE_LENGTH} characters.")
        for line in copy:
            if len(line) > MAX_COPY_LENGTH:
                raise ScenarioError(f"{where}: copy is longer than {MAX_COPY_LENGTH} characters: \"{line}\".")


def required_assets(data):
    """Every image the app needs, sorted by name: the baseline expressions plus all scenario art."""
    baseline = data["baselineAssets"]
    wanted = {}
    for crop in baseline["crops"]:
        for expression in baseline["expressions"]:
            wanted[asset_name(expression, baseline["outfit"], crop)] = (expression, baseline["outfit"], crop)
    for scenario in data["scenarios"]:
        for art in scenario["art"]:
            wanted[asset_name(**art)] = (art["expression"], art["outfit"], art["crop"])
    return [
        {"name": name, "expression": e, "outfit": o, "crop": c}
        for name, (e, o, c) in sorted(wanted.items())
    ]


def xcode_json(value):
    return json.dumps(value, **XCODE_JSON) + "\n"


def text_artifacts(data, source_bytes):
    """Relative-to-repo path -> expected text/bytes for everything generated except the PNGs."""
    info = {"author": "xcode", "version": 1}
    files = {
        IMAGE_FOLDER / "Contents.json": xcode_json({"info": info, "properties": {"provides-namespace": True}}),
        DATASET_FOLDER / "Contents.json": xcode_json({
            "data": [{"filename": SCENARIOS_PATH.name, "idiom": "universal", "universal-type-identifier": "public.json"}],
            "info": info,
        }),
        DATASET_FOLDER / SCENARIOS_PATH.name: source_bytes,
        DOCS_PATH: render_docs(data),
    }
    for asset in required_assets(data):
        folder = IMAGE_FOLDER / f"{asset['name']}.imageset"
        files[folder / "Contents.json"] = xcode_json({
            "images": [{"filename": f"{asset['name']}.png", "idiom": "universal"}],
            "info": info,
        })
    return {path: (content.encode("utf-8") if isinstance(content, str) else content) for path, content in files.items()}


def stale_text_artifacts(data, source_bytes):
    """Paths whose committed content differs from what the scenario file generates."""
    stale = []
    for path, expected in text_artifacts(data, source_bytes).items():
        if not path.is_file() or path.read_bytes() != expected:
            stale.append(str(path.relative_to(REPO_ROOT)))
    expected_folders = {f"{a['name']}.imageset" for a in required_assets(data)}
    if IMAGE_FOLDER.is_dir():
        for folder in sorted(IMAGE_FOLDER.glob("*.imageset")):
            if folder.name not in expected_folders:
                stale.append(f"{folder.relative_to(REPO_ROOT)} (no scenario uses it)")
    return stale


def render_docs(data):
    names = {a["name"] for a in required_assets(data)}
    scenarios = data["scenarios"]
    lines = [
        "# Notification scenarios",
        "",
        "<!-- Generated from Design/NotificationCharacter/notification-scenarios.json by render_character.py --assets."
        " Do not edit by hand: edit the JSON and re-run. -->",
        "",
        "Every state the notification character can be in, with the art and copy it uses. The JSON file is the source of truth;"
        " the app loads it at runtime and this page, the portrait images and the app's data set are generated from it."
        " To add or change a scenario, edit `Design/NotificationCharacter/notification-scenarios.json` and run"
        " `make notification-character`.",
        "",
        "- **nudge**: scheduled ahead of time as a reminder.",
        "- **acknowledgment**: sent a few seconds after a workout is saved.",
        "- **crop**: `portrait` is head and shoulders. `close` is the tighter face crop used for heavier moments.",
        "- **art**: the first entry is the primary image. Other entries are alternates, chosen by variant.",
        f"- {len(scenarios)} scenarios, {len(names)} portrait images, "
        f"{sum(len(s['copy']) for s in scenarios)} copy lines.",
        "",
        "## Tokens",
        "",
        "| Token | Meaning |",
        "|---|---|",
    ]
    lines += [f"| `{{{token}}}` | {meaning} |" for token, meaning in data["tokens"].items()]
    lines += ["", "## Summary", "", "| # | Scenario | Kind | Crop | Expression | Outfit |", "|---|---|---|---|---|---|"]
    for number, scenario in enumerate(scenarios, 1):
        arts = scenario["art"]
        crops = " / ".join(dict.fromkeys(a["crop"] for a in arts))
        expressions = " / ".join(dict.fromkeys(a["expression"] for a in arts))
        outfits = " / ".join(dict.fromkeys(a["outfit"] for a in arts))
        lines.append(f"| {number} | [{scenario['name']}](#{number}-{scenario['id']}) | {scenario['kind']} |"
                     f" {crops} | {expressions} | {outfits} |")
    lines += ["", "## Scenarios", ""]
    for number, scenario in enumerate(scenarios, 1):
        lines += [
            f"### {number}. {scenario['id']}",
            "",
            f"**{scenario['name']}** · {scenario['kind']}",
            "",
            f"- **Trigger:** {scenario['trigger']}",
            f"- **Tone:** {scenario['tone']}",
            "- **Art:** " + ", ".join(f"`{asset_name(**art)}`" for art in scenario["art"]),
            f"- **Title:** `{scenario['title']}`",
        ]
        if scenario["sample"]:
            lines.append("- **Dev preview sample:** " + ", ".join(f"{k} = {v}" for k, v in scenario["sample"].items()))
        lines += ["- **Copy:**"] + [f"  {i}. {line}" for i, line in enumerate(scenario["copy"], 1)] + [""]
    lines += ["## Images", "", f"{len(names)} images in `PostureAnalysisApp/Assets.xcassets/NotificationCharacter/`:", ""]
    lines += [f"- `{name}`" for name in sorted(names)]
    return "\n".join(lines) + "\n"
