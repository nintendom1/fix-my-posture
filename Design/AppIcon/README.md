# App Icon Source

`FixMyPosture-AppIcon-source.svg` is the source for the app icon. The PNG in
`PostureAnalysisApp/Assets.xcassets/AppIcon.appiconset/FixMyPosture-AppIcon-1024.png` is
exported from it. The artwork was written by hand as SVG and rendered programmatically,
without generative AI.

## Upstream glyph

The human-and-scanner glyph is Tabler Icons
[`icons/outline/body-scan.svg`](https://github.com/tabler/tabler-icons/blob/main/icons/outline/body-scan.svg).
It was taken from Tabler Icons v3.49.0 (commit `ab7315d`); the icon itself was added in v2.36.
Tabler Icons is MIT-licensed, Copyright (c) 2020-2026 Paweł Kuna. See
[`TABLER-LICENSE.txt`](TABLER-LICENSE.txt) and the repository's
[`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md). The icon is a **modified derivative**,
so the attribution stays even though the glyph is recolored, scaled, and rasterized.

Changes from upstream:

- The path data is kept verbatim. It is scaled 31× about the canvas center
  (`translate(140 140) scale(31)`), so the 24-unit grid fills the middle of the 1024 canvas.
- The stroke width goes from 2 to 1.52 (about 47 px). The head path is also filled, so the thinner
  stroke leaves no hole in the head.
- The stroke is near-white `#FAF9FF`, with round caps and joins.
- A gradient background is added, as described below.

## Color treatment

The background is four full-canvas layers, drawn bottom to top:

| Layer | Type | Stops | Purpose |
|---|---|---|---|
| `base` | linear, (90,60) → (960,970) | `#120B27` → `#211243` @0.42 → `#3A1E73` @0.74 → `#552CA2` | dark indigo to violet |
| `coolLift` | radial at (21%, 16%), r 72% | `#4A7CFF` 34% → `#545CFF` 12% @0.40 → `#27D8E8` 0% | cool blue highlight, top left |
| `violetLift` | radial at (88%, 80%), r 70% | `#A455E7` 28% → `#7D3EC9` 8% @0.55 → 0% | purple glow, bottom right |
| `edgeDepth` | radial at (50%, 45%), r 74% | clear until 0.62 → `#05030D` 30% | soft vignette |

These colors match the app's dark camera screens with their white, blue, and cyan tracking accents.

## Exporting the PNG

```bash
brew install resvg                                  # one-time; exported with resvg 0.48.1
python3 Design/AppIcon/export-app-icon.py           # writes the asset-catalog PNG
python3 Design/AppIcon/export-app-icon.py --check   # verifies the committed PNG matches the SVG
```

The script uses only the Python standard library apart from resvg. It renders at 1024×1024,
fails if any pixel is not fully opaque, drops the alpha channel, and writes an 8-bit RGB PNG with
an sRGB chunk and no other metadata. The same resvg version always produces the same pixels.

## Requirements for the production PNG

- 1024×1024, RGB, **no alpha channel**. App Store Connect rejects icons with alpha.
- **No rounded corners** or transparent margins. iOS applies the app-icon mask itself, so the
  artwork must fill the full square.
- Only one size is needed. The asset catalog uses a single 1024 universal iOS entry, and Xcode
  generates the smaller sizes.

After changing the SVG, re-run the export and commit the SVG and PNG together.
