#!/usr/bin/env python3
"""Export the app icon PNG from FixMyPosture-AppIcon-source.svg.

Renders the SVG with resvg (`brew install resvg`), rejects any transparency, and writes a
1024x1024 RGB PNG with no alpha channel and no metadata. The same resvg version always
produces the same pixels.

    python3 Design/AppIcon/export-app-icon.py          # write the asset-catalog PNG
    python3 Design/AppIcon/export-app-icon.py --check  # fail if the committed PNG is stale
"""

import argparse
import hashlib
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

SIZE = 1024
DESIGN_DIR = Path(__file__).resolve().parent
REPO_ROOT = DESIGN_DIR.parent.parent
SOURCE_SVG = DESIGN_DIR / "FixMyPosture-AppIcon-source.svg"
OUTPUT_PNG = REPO_ROOT / "PostureAnalysisApp/Assets.xcassets/AppIcon.appiconset/FixMyPosture-AppIcon-1024.png"


def fail(message):
    sys.exit(f"Error: {message}")


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path):
    """Returns (width, height, channels, pixel rows) for an 8-bit RGB or RGBA PNG."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        fail(f"{path} is not a PNG.")
    offset, idat, header = 8, bytearray(), None
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        offset += 12 + length
    width, height, depth, color_type, _, _, interlace = header
    channels = {2: 3, 6: 4}.get(color_type)
    if depth != 8 or channels is None or interlace:
        fail(f"{path} must be a non-interlaced 8-bit RGB or RGBA PNG.")

    raw, stride, rows = zlib.decompress(bytes(idat)), width * channels, []
    previous, position = bytearray(stride), 0
    for _ in range(height):
        kind = raw[position]
        line = bytearray(raw[position + 1:position + 1 + stride])
        position += 1 + stride
        for x in range(stride):
            left = line[x - channels] if x >= channels else 0
            up = previous[x]
            up_left = previous[x - channels] if x >= channels else 0
            if kind == 1:
                line[x] = (line[x] + left) & 0xFF
            elif kind == 2:
                line[x] = (line[x] + up) & 0xFF
            elif kind == 3:
                line[x] = (line[x] + (left + up) // 2) & 0xFF
            elif kind == 4:
                line[x] = (line[x] + paeth(left, up, up_left)) & 0xFF
        rows.append(bytes(line))
        previous = line
    return width, height, channels, rows


def opaque_rgb_rows(rows):
    """Drops the alpha channel, refusing any pixel that isn't fully opaque."""
    rgb_rows = []
    for y, row in enumerate(rows):
        if row[3::4].count(255) != len(row) // 4:
            fail(f"Rendered icon has transparent pixels on row {y}. App icons must be fully opaque.")
        rgb = bytearray(len(row) // 4 * 3)
        rgb[0::3], rgb[1::3], rgb[2::3] = row[0::4], row[1::4], row[2::4]
        rgb_rows.append(bytes(rgb))
    return rgb_rows


def encode_rgb_png(rows, width, height):
    """RGB PNG with an sRGB chunk, Paeth-filtered rows, and no metadata."""
    filtered, previous = bytearray(), bytes(width * 3)
    for row in rows:
        filtered.append(4)
        for x in range(len(row)):
            left = row[x - 3] if x >= 3 else 0
            up_left = previous[x - 3] if x >= 3 else 0
            filtered.append((row[x] - paeth(left, previous[x], up_left)) & 0xFF)
        previous = row

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"sRGB", b"\x00")
        + chunk(b"IDAT", zlib.compress(bytes(filtered), 9))
        + chunk(b"IEND", b"")
    )


def render():
    try:
        version = subprocess.run(["resvg", "--version"], capture_output=True, text=True, check=True).stdout.strip()
    except (FileNotFoundError, subprocess.CalledProcessError):
        fail("resvg is required. Install it with: brew install resvg")
    with tempfile.TemporaryDirectory() as temp:
        rendered = Path(temp) / "icon.png"
        subprocess.run(
            ["resvg", "--width", str(SIZE), "--height", str(SIZE), str(SOURCE_SVG), str(rendered)],
            check=True,
        )
        width, height, channels, rows = read_png(rendered)
    if (width, height, channels) != (SIZE, SIZE, 4):
        fail(f"resvg produced {width}x{height} with {channels} channels; expected {SIZE}x{SIZE} RGBA.")
    return version, opaque_rgb_rows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="compare the committed PNG with a fresh render")
    args = parser.parse_args()

    version, rows = render()
    if args.check:
        if not OUTPUT_PNG.exists():
            fail(f"{OUTPUT_PNG.relative_to(REPO_ROOT)} is missing.")
        width, height, channels, committed = read_png(OUTPUT_PNG)
        if (width, height, channels) != (SIZE, SIZE, 3) or committed != rows:
            fail(f"{OUTPUT_PNG.relative_to(REPO_ROOT)} does not match the SVG source. Re-run the export.")
        print(f"OK: committed icon matches the source (resvg {version}).")
        return

    png = encode_rgb_png(rows, SIZE, SIZE)
    OUTPUT_PNG.write_bytes(png)
    print(f"Wrote {OUTPUT_PNG.relative_to(REPO_ROOT)} with resvg {version}")
    print(f"SHA-256 {hashlib.sha256(png).hexdigest()}")


if __name__ == "__main__":
    main()
