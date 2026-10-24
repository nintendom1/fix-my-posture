"""Validation and generated artifacts for the notification character's persona copy.

This module deliberately uses only the Python standard library. The JSON is the source of
truth for persona copy, its token samples, art overrides, the app data set, and its docs page.
"""

import json
import re
import sys
from pathlib import Path

DESIGN_DIR = Path(__file__).resolve().parent
REPO_ROOT = DESIGN_DIR.parent.parent
PERSONA_CONTENT_PATH = DESIGN_DIR / "persona-content.json"
ASSET_CATALOG = REPO_ROOT / "PostureAnalysisApp/Assets.xcassets"
DATASET_FOLDER = ASSET_CATALOG / "PersonaContent.dataset"
DOCS_PATH = REPO_ROOT / "docs/persona-content.md"
XCODE_JSON = {"indent": 2, "separators": (",", " : "), "ensure_ascii": False}

# Import the sibling module when this file is loaded directly by the unit tests too.
if str(DESIGN_DIR) not in sys.path:
    sys.path.insert(0, str(DESIGN_DIR))
import notification_scenarios as scenarios  # noqa: E402

TONES = (
    "proud", "pleased", "relieved", "annoyed", "disappointed", "smug",
    "competitive", "concerned", "warm",
)
FAMILIARITIES = ("new", "familiar", "established", "longTerm")
FAMILIES = {"achievement", "pattern", "lapse", "posture"}
NEGATIVE_TONES = {"annoyed", "disappointed"}
TOP_LEVEL_KEYS = (
    "version", "sampleValues", "tokens", "reservedTokens", "tones", "familiarities",
    "toneArt", "fragments", "content",
)
CONTENT_KEY_PATTERN = re.compile(r"^[a-z]+(\.[a-zA-Z]+)+$")
TOKEN_PATTERN = re.compile(r"\{([^{}]*)\}")
XCODE_INFO = {"author": "xcode", "version": 1}


class PersonaContentError(Exception):
    """A problem in persona-content.json, with a message meant for the author."""


class _DuplicateJSONKey(ValueError):
    """Internal signal used by the JSON object hook."""


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateJSONKey(f"duplicate key '{key}'")
        result[key] = value
    return result


def load_content(path=PERSONA_CONTENT_PATH, scenario_data=None, expression_choices=None):
    """Load, validate, and return persona data with its exact source bytes."""
    try:
        source_bytes = Path(path).read_bytes()
        data = json.loads(source_bytes.decode("utf-8"), object_pairs_hook=_unique_object)
    except _DuplicateJSONKey as error:
        raise PersonaContentError(f"{path}: {error}.") from error
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PersonaContentError(f"Could not read persona content at {path}: {error}.") from error

    if scenario_data is None:
        scenario_data = scenarios.load_scenarios()
    validate(data, scenario_data, expression_choices=expression_choices)
    return data, source_bytes


def _mapping(value, where):
    if not isinstance(value, dict):
        raise PersonaContentError(f"{where} must be an object.")
    return value


def _string(value, where, nonempty=True):
    if not isinstance(value, str) or (nonempty and not value.strip()):
        requirement = "non-empty text" if nonempty else "text"
        raise PersonaContentError(f"{where} must be {requirement}.")
    return value


def _string_list(value, where, *, nonempty=False):
    if not isinstance(value, list) or (nonempty and not value):
        suffix = " a non-empty list" if nonempty else " a list"
        raise PersonaContentError(f"{where} must be{suffix}.")
    for index, item in enumerate(value):
        _string(item, f"{where}[{index}]")
    return value


def _validate_art(art, where, outfits, crops, expressions):
    art = _mapping(art, where)
    if set(art) != {"expression", "outfit", "crop"}:
        raise PersonaContentError(f"{where} art needs exactly expression, outfit, and crop.")
    expression = _string(art["expression"], f"{where}.expression")
    if expression not in expressions:
        choices = ", ".join(sorted(expressions))
        raise PersonaContentError(f"{where}: unknown expression '{expression}'. Choices: {choices}.")
    outfit = _string(art["outfit"], f"{where}.outfit")
    if outfit not in outfits:
        raise PersonaContentError(f"{where}: unknown outfit '{outfit}'. Choices: {', '.join(sorted(outfits))}.")
    crop = _string(art["crop"], f"{where}.crop")
    if crop not in crops:
        raise PersonaContentError(f"{where}: unknown crop '{crop}'. Choices: {', '.join(sorted(crops))}.")


def _validate_variants(variants, where, tones, familiarity_order, declared_tokens, reserved_tokens,
                       max_length, *, fragments=False):
    if not isinstance(variants, list) or not variants:
        raise PersonaContentError(f"{where} must be a non-empty list of variants.")
    seen_text = set()
    normalized = []
    for index, variant in enumerate(variants):
        item_where = f"{where}[{index}]"
        variant = _mapping(variant, item_where)
        allowed = {"text", "tones", "minFamiliarity"}
        if not set(variant) <= allowed or "text" not in variant:
            raise PersonaContentError(f"{item_where} must contain text and may contain only tones and minFamiliarity.")
        text = _string(variant["text"], f"{item_where}.text")
        if text in seen_text:
            raise PersonaContentError(f"{where} texts must be distinct.")
        seen_text.add(text)
        if len(text) > max_length:
            noun = "fragment" if fragments else ("title" if max_length == 36 else "body")
            raise PersonaContentError(f"{item_where}: {noun} is longer than {max_length} characters.")

        variant_tones = None
        if "tones" in variant:
            variant_tones = _string_list(variant["tones"], f"{item_where}.tones", nonempty=True)
            if len(set(variant_tones)) != len(variant_tones):
                raise PersonaContentError(f"{item_where}.tones must not contain duplicates.")
            for tone in variant_tones:
                if tone not in tones:
                    raise PersonaContentError(f"{item_where}: unknown tone '{tone}'.")

        min_familiarity = variant.get("minFamiliarity", "new")
        if "minFamiliarity" in variant:
            min_familiarity = _string(min_familiarity, f"{item_where}.minFamiliarity")
            if min_familiarity not in familiarity_order:
                raise PersonaContentError(f"{item_where}: unknown familiarity '{min_familiarity}'.")

        used_tokens = set(TOKEN_PATTERN.findall(text))
        without_tokens = TOKEN_PATTERN.sub("", text)
        if "{" in without_tokens or "}" in without_tokens:
            raise PersonaContentError(f"{item_where}: unbalanced braces in \"{text}\".")
        if fragments and used_tokens:
            raise PersonaContentError(f"{item_where}: fragments must not use tokens.")
        for token in sorted(used_tokens):
            if token not in declared_tokens:
                raise PersonaContentError(f"{item_where}: unknown token '{{{token}}}'.")
            if token in reserved_tokens:
                raise PersonaContentError(f"{item_where}: reserved token '{{{token}}}' is not allowed in v1 copy.")
        normalized.append({
            "text": text,
            "tones": variant_tones,
            "minFamiliarity": min_familiarity,
            "usedTokens": used_tokens,
        })
    return normalized


def _eligible(variant, tone, familiarity, familiarity_order):
    return (
        (variant["tones"] is None or tone in variant["tones"])
        and familiarity_order[variant["minFamiliarity"]] <= familiarity_order[familiarity]
    )


def validate(data, scenario_data, expression_choices=None):
    """Validate persona content against the runtime contract and available notification art."""
    data = _mapping(data, "persona-content.json")
    missing = [key for key in TOP_LEVEL_KEYS if key not in data]
    if missing:
        raise PersonaContentError(f"persona-content.json is missing '{missing[0]}'.")
    if type(data["version"]) is not int or data["version"] != 1:
        raise PersonaContentError(f"Unsupported persona content version {data['version']}.")

    tones = _string_list(data["tones"], "tones", nonempty=True)
    if len(tones) != len(set(tones)) or set(tones) != set(TONES):
        raise PersonaContentError(f"'tones' must contain exactly: {', '.join(TONES)}.")
    familiarities = _string_list(data["familiarities"], "familiarities", nonempty=True)
    if len(familiarities) != len(set(familiarities)) or set(familiarities) != set(FAMILIARITIES):
        raise PersonaContentError("'familiarities' must contain exactly: new, familiar, established, longTerm.")
    familiarity_order = {name: index for index, name in enumerate(FAMILIARITIES)}

    tokens = _mapping(data["tokens"], "tokens")
    for token, description in tokens.items():
        _string(token, "token name")
        _string(description, f"tokens.{token}")
    reserved_tokens = _string_list(data["reservedTokens"], "reservedTokens")
    if len(reserved_tokens) != len(set(reserved_tokens)):
        raise PersonaContentError("reservedTokens must not contain duplicates.")
    unknown_reserved = set(reserved_tokens) - set(tokens)
    if unknown_reserved:
        raise PersonaContentError(f"reservedTokens names undeclared token '{sorted(unknown_reserved)[0]}'.")

    sample_values = _mapping(data["sampleValues"], "sampleValues")
    for token, sample in sample_values.items():
        if token not in tokens:
            raise PersonaContentError(f"sampleValues has unknown token '{token}'.")
        _string(sample, f"sampleValues.{token}")
        if token in reserved_tokens:
            raise PersonaContentError(f"sampleValues must not include reserved token '{token}'.")
    missing_samples = (set(tokens) - set(reserved_tokens)) - set(sample_values)
    if missing_samples:
        raise PersonaContentError(f"sampleValues is missing token '{sorted(missing_samples)[0]}'.")

    scenario_data = _mapping(scenario_data, "notification-scenarios.json")
    outfits = _mapping(scenario_data.get("outfits"), "notification-scenarios.json outfits")
    crops = _mapping(scenario_data.get("cropPresets"), "notification-scenarios.json cropPresets")
    expressions = set(expression_choices if expression_choices is not None else scenarios.known_expressions())

    tone_art = _mapping(data["toneArt"], "toneArt")
    if set(tone_art) != set(tones):
        missing_tone = set(tones) - set(tone_art)
        if missing_tone:
            raise PersonaContentError(f"toneArt is missing tone '{sorted(missing_tone)[0]}'.")
        raise PersonaContentError(f"toneArt has unknown tone '{sorted(set(tone_art) - set(tones))[0]}'.")
    for tone in tones:
        _validate_art(tone_art[tone], f"toneArt.{tone}", outfits, crops, expressions)

    fragments = _mapping(data["fragments"], "fragments")
    if set(fragments) != {"openers", "closers", "intro"}:
        raise PersonaContentError("fragments must contain exactly openers, closers, and intro.")
    validated_fragments = {}
    for name in ("openers", "closers", "intro"):
        if name not in fragments:
            raise PersonaContentError(f"fragments is missing '{name}'.")
        validated_fragments[name] = _validate_variants(
            fragments[name], f"fragments.{name}", set(tones), familiarity_order, set(tokens),
            set(reserved_tokens), 18, fragments=True,
        )
    # The first persona message can carry any tone at new familiarity, so an intro line must fit every tone there.
    for tone in tones:
        if not any(_eligible(variant, tone, "new", familiarity_order) for variant in validated_fragments["intro"]):
            raise PersonaContentError(f"fragments.intro: needs a line eligible for tone '{tone}' at new familiarity.")

    content = _mapping(data["content"], "content")
    seen_keys = set()
    for key, entry in content.items():
        if key in seen_keys:
            raise PersonaContentError(f"duplicate content key '{key}'.")
        seen_keys.add(key)
        where = f"content.{key}"
        if not isinstance(key, str) or not CONTENT_KEY_PATTERN.fullmatch(key):
            raise PersonaContentError(f"{where}: content key must match {CONTENT_KEY_PATTERN.pattern}.")
        entry = _mapping(entry, where)
        required = {"family", "defaultTone", "tokens", "title", "body", "art"}
        if set(entry) != required:
            raise PersonaContentError(f"{where} must have exactly: {', '.join(sorted(required))}.")
        family = _string(entry["family"], f"{where}.family")
        expected_family = key.split(".", 1)[0]
        if family not in FAMILIES or family != expected_family:
            raise PersonaContentError(f"{where}.family must be '{expected_family}' and one of {', '.join(sorted(FAMILIES))}.")
        default_tone = _string(entry["defaultTone"], f"{where}.defaultTone")
        if default_tone not in tones:
            raise PersonaContentError(f"{where}: unknown default tone '{default_tone}'.")
        if default_tone in {"annoyed", "disappointed"}:
            raise PersonaContentError(f"{where}: defaultTone must not be annoyed or disappointed.")

        entry_tokens = _string_list(entry["tokens"], f"{where}.tokens")
        if len(entry_tokens) != len(set(entry_tokens)):
            raise PersonaContentError(f"{where}.tokens must not contain duplicates.")
        for token in entry_tokens:
            if token not in tokens:
                raise PersonaContentError(f"{where}: unknown token '{token}' in entry tokens.")

        title_variants = _validate_variants(
            entry["title"], f"{where}.title", set(tones), familiarity_order, set(tokens),
            set(reserved_tokens), 36,
        )
        body_variants = _validate_variants(
            entry["body"], f"{where}.body", set(tones), familiarity_order, set(tokens),
            set(reserved_tokens), 70,
        )
        used_entry_tokens = set().union(*(variant["usedTokens"] for variant in title_variants + body_variants))
        unlisted_tokens = used_entry_tokens - set(entry_tokens)
        if unlisted_tokens:
            raise PersonaContentError(f"{where}: token '{sorted(unlisted_tokens)[0]}' is used but not listed in entry tokens.")

        default_title = any(_eligible(variant, default_tone, "new", familiarity_order) for variant in title_variants)
        default_body = any(_eligible(variant, default_tone, "new", familiarity_order) for variant in body_variants)
        if not default_title or not default_body:
            missing_field = "title" if not default_title else "body"
            raise PersonaContentError(f"{where}: needs a {missing_field} eligible at new familiarity for defaultTone '{default_tone}'.")
        # VOICE.md: annoyed and disappointed lines need history between the two of them.
        for field, variants in (("title", entry["title"]), ("body", entry["body"])):
            for index, variant in enumerate(variants):
                variant_tones = variant.get("tones") or []
                if variant_tones and set(variant_tones) <= NEGATIVE_TONES:
                    minimum = variant.get("minFamiliarity", "new")
                    if familiarity_order[minimum] < familiarity_order["established"]:
                        raise PersonaContentError(
                            f"{where}.{field}[{index}]: annoyed or disappointed lines need minFamiliarity established or later."
                        )

        art = _mapping(entry["art"], f"{where}.art")
        for tone, override in art.items():
            if tone not in tones:
                raise PersonaContentError(f"{where}.art: unknown tone '{tone}'.")
            _validate_art(override, f"{where}.art.{tone}", outfits, crops, expressions)


def string_count(data):
    """Count all authored titles, bodies, and fragments (before token substitution)."""
    count = sum(
        len(entry[field])
        for entry in data["content"].values()
        for field in ("title", "body")
    )
    return count + sum(len(variants) for variants in data["fragments"].values())


def required_assets(content, scenario_data):
    """Return every distinct persona portrait as sorted renderer input dictionaries."""
    wanted = {}
    arts = list(content["toneArt"].values())
    arts.extend(art for entry in content["content"].values() for art in entry["art"].values())
    for art in arts:
        name = scenarios.asset_name(**art)
        wanted[name] = (art["expression"], art["outfit"], art["crop"])
    return [
        {"name": name, "expression": expression, "outfit": outfit, "crop": crop}
        for name, (expression, outfit, crop) in sorted(wanted.items())
    ]


def xcode_json(value):
    return json.dumps(value, **XCODE_JSON) + "\n"


def text_artifacts(content, scenario_data, source_bytes):
    """Relative-to-repo path -> expected bytes for persona data, docs, and its image-set metadata."""
    files = {
        DATASET_FOLDER / "Contents.json": xcode_json({
            "data": [{
                "filename": PERSONA_CONTENT_PATH.name,
                "idiom": "universal",
                "universal-type-identifier": "public.json",
            }],
            "info": XCODE_INFO,
        }),
        DATASET_FOLDER / PERSONA_CONTENT_PATH.name: source_bytes,
        DOCS_PATH: render_docs(content, scenario_data),
    }
    for asset in required_assets(content, scenario_data):
        folder = scenarios.IMAGE_FOLDER / f"{asset['name']}.imageset"
        files[folder / "Contents.json"] = xcode_json({
            "images": [{"filename": f"{asset['name']}.png", "idiom": "universal"}],
            "info": XCODE_INFO,
        })
    return {
        path: (value.encode("utf-8") if isinstance(value, str) else value)
        for path, value in files.items()
    }


def _art_name(art):
    return scenarios.asset_name(**art)


def _variant_line(variant):
    tones = "all tones" if "tones" not in variant else ", ".join(f"`{tone}`" for tone in variant["tones"])
    familiarity = variant.get("minFamiliarity", "new")
    return f"- `{variant['text']}` — tones: {tones}; minimum familiarity: `{familiarity}`"


def render_docs(content, scenario_data):
    """Generate the readable persona-content reference page."""
    lines = [
        "# Persona content",
        "",
        "<!-- Generated from Design/NotificationCharacter/persona-content.json by render_character.py --assets."
        " Do not edit by hand: edit the JSON and re-run. -->",
        "",
        "The copy library used by the on-device persona planner. The JSON file is the source of truth; the app data set,"
        " character portraits, and this page are generated from it. To change copy or art, edit"
        " `Design/NotificationCharacter/persona-content.json` and run `make notification-character`.",
        "",
        f"- {len(content['content'])} content entries, {string_count(content)} authored strings.",
        "",
        "## Tokens",
        "",
        "| Token | Sample | Meaning |",
        "|---|---|---|",
    ]
    for token, meaning in content["tokens"].items():
        sample = content["sampleValues"].get(token, "—")
        lines.append(f"| `{{{token}}}` | {sample} | {meaning} |")

    lines += ["", "## Tone art", "", "| Tone | Image |", "|---|---|"]
    for tone in content["tones"]:
        art = content["toneArt"][tone]
        lines.append(f"| `{tone}` | `{_art_name(art)}` |")

    lines += ["", "## Content", ""]
    for key, entry in content["content"].items():
        lines += [
            f"### `{key}`",
            "",
            f"- **Family:** `{entry['family']}`",
            f"- **Default tone:** `{entry['defaultTone']}`",
            "- **Tokens:** " + (", ".join(f"`{token}`" for token in entry["tokens"]) or "none"),
        ]
        if entry["art"]:
            lines.append("- **Art overrides:** " + "; ".join(
                f"`{tone}` → `{_art_name(art)}`" for tone, art in entry["art"].items()
            ))
        else:
            lines.append("- **Art overrides:** none")
        for field in ("title", "body"):
            lines += ["", f"**{field.title()} variants**"]
            lines.extend(_variant_line(variant) for variant in entry[field])
        lines.append("")

    lines += ["## Fragments", ""]
    for name in ("openers", "closers", "intro"):
        lines += [f"### {name.title()}", ""]
        lines.extend(_variant_line(variant) for variant in content["fragments"][name])
        lines.append("")

    uses = {}
    for tone, art in content["toneArt"].items():
        uses.setdefault(_art_name(art), {"tones": set(), "content": set()})["tones"].add(tone)
    for key, entry in content["content"].items():
        for tone, art in entry["art"].items():
            uses.setdefault(_art_name(art), {"tones": set(), "content": set()})["content"].add(f"{key} ({tone})")
    lines += [
        "## Persona images",
        "",
        f"{len(uses)} distinct persona images, included in the shared notification character asset catalog:",
        "",
    ]
    for name in sorted(uses):
        use = uses[name]
        labels = []
        if use["tones"]:
            labels.append("tones: " + ", ".join(f"`{tone}`" for tone in sorted(use["tones"])))
        if use["content"]:
            labels.append("content: " + ", ".join(f"`{key}`" for key in sorted(use["content"])))
        lines.append(f"- `{name}` — " + "; ".join(labels))
    return "\n".join(lines) + "\n"
