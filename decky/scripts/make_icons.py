"""Make the phone-view home-screen icons from the Outbreak Tracker HD icon.

Purpose: reusable one-time generator; the PNGs it writes are committed in web/icons/, so
  builds do not need it. Re-run only when the source icon changes.
Location/runtime: decky/scripts/make_icons.py; Python 3 with Pillow (the Mac has none on its
  default PATH; use /Users/adjule/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3).
Inputs: sources/outbreak-tracker-icon-hd.png (transparent RGBA triangle, 845x777).
Outputs: web/icons/apple-touch-icon.png (180), icon-192.png, icon-512.png and
  icon-512-maskable.png (smaller glyph so Android's circular mask keeps it whole), each the
  icon centred on opaque black (#000000) so iOS and Android do not fill transparency themselves.
Safety: reads one repository image, writes four files under web/icons/; no network, no device access.
Run from repo-merged/:
  /Users/adjule/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 decky/scripts/make_icons.py
Check: four PNGs of the stated sizes exist; open one and confirm the triangle is centred on black.
"""
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "sources/outbreak-tracker-icon-hd.png"
OUTPUT = REPO / "decky/web/icons"
ICONS = [("apple-touch-icon.png", 180, 0.74), ("icon-192.png", 192, 0.74),
         ("icon-512.png", 512, 0.74), ("icon-512-maskable.png", 512, 0.56)]

glyph = Image.open(SOURCE).convert("RGBA")
OUTPUT.mkdir(parents=True, exist_ok=True)
for name, size, fill in ICONS:
    scale = size * fill / max(glyph.size)
    resized = glyph.resize((round(glyph.width * scale), round(glyph.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    canvas.alpha_composite(resized, ((size - resized.width) // 2, (size - resized.height) // 2))
    canvas.convert("RGB").save(OUTPUT / name, optimize=True)
    print("wrote", OUTPUT / name)
