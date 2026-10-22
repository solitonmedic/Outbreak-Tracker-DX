"""Reusable font metric generator; toolchain Python 3 with Pillow.
Inputs: assets directory and output Lua path as positional arguments.
Outputs: Lua table of original TTF advances/ascent and image-font glyph widths.
Safety: reads bundled artwork/fonts only; no PINE, recordings or shared source edits.
Run: invoked by native_build.py using the user toolchain's Python.
Check: output loads with LuaJIT and covers all fonts requested by shared assets.lua.
"""
import json
from pathlib import Path
import sys
from PIL import Image, ImageFont


def generate(assets, output):
    records = []
    for name, size in [("arialbd.ttf", 18), ("arialbd.ttf", 15), ("arialbd.ttf", 13), ("arialnb.ttf", 11)]:
        font = ImageFont.truetype(str(assets / name), size, layout_engine=ImageFont.Layout.BASIC)
        ascent, descent = font.getmetrics()
        widths = {cp: float(font.getlength(chr(cp))) for cp in range(32, 1280)}
        records.append((f"assets/{name}:{size}", ascent + descent, ascent, widths))
    for name, characters in [("ItemCountFont.png", "0123456789"), ("TimeFont.png", "0123456789:./"), ("VirusFont.png", "0123456789.%")]:
        image = Image.open(assets / name).convert("RGBA")
        separator = image.getpixel((0, 0))
        regions, start = [], None
        for x in range(image.width + 1):
            spacer = x == image.width or image.getpixel((x, 0)) == separator
            if not spacer and start is None:
                start = x
            if spacer and start is not None:
                regions.append(x - start)
                start = None
        widths = {ord(c): width for c, width in zip(characters, regions)}
        records.append((f"assets/{name}", image.height, image.height, widths))
    lines = ["return {"]
    for key, height, ascent, widths in records:
        encoded = ",".join(f"[{cp}]={width:g}" for cp, width in widths.items())
        lines.append(f"[{json.dumps(key)}]={{height={height},ascent={ascent},widths={{{encoded}}}}},")
    lines.append("}")
    output.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    generate(Path(sys.argv[1]), Path(sys.argv[2]))
