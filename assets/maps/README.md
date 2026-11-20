# File 1 and File 2 map assets

Maps and source room regions by [Evil Resource](https://www.evilresource.com).
Used with permission: the project owner confirmed permission for both games on
2026-11-06. Preserve this credit and the per-map source URLs when using the assets.

Sources:

- [Resident Evil Outbreak maps](https://www.evilresource.com/resident-evil-outbreak/maps)
- [Resident Evil Outbreak File #2 maps](https://www.evilresource.com/resident-evil-outbreak-file-2/maps)

## Contents

The download contains **68 original GIF maps**, covering all ten main scenarios,
and **319 named room regions**. The images retain their downloaded bytes and
original dimensions. Item/enemy composite overlays and unrelated site images
are not included.

| Game | Scenario directory | Maps |
| --- | --- | ---: |
| File 1 | `file1/outbreak/` | 6 |
| File 1 | `file1/below-freezing-point/` | 6 |
| File 1 | `file1/the-hive/` | 6 |
| File 1 | `file1/hellfire/` | 3 |
| File 1 | `file1/decisions-decisions/` | 13 |
| File 2 | `file2/wild-things/` | 2 |
| File 2 | `file2/underbelly/` | 12 |
| File 2 | `file2/flashback/` | 12 |
| File 2 | `file2/desperate-times/` | 3 |
| File 2 | `file2/end-of-the-road/` | 5 |

`manifest.json` owns the source metadata: retrieval time, credit, permission
record and each map's game/scenario, source map ID, title, relative file path,
index/page/image URLs, width, height, byte count and SHA-256. Each map also has
the source room names, source location IDs/URLs, shape and pixel coordinates.
These region records are transcribed from the source page's HTML image maps.

## Integration status

The shared map views use recoloured PNGs under `er/` on fitted floors, with blue
walls, yellow doors and transparent room interiors. `sources/MapER.lua` holds
the generated room-ID crosswalk, room outlines and per-layer conversions from
the game's map coordinates. Fits use matching room names and room bounds;
they have been checked offline and still need in-game comparison. Floors without
a reliable fit retain the bundled game map artwork. The original GIFs and this
manifest remain the source provenance, including per-map URLs and permission.

Source location IDs identify Evil Resource locations. Runtime markers continue
to use the game's room IDs and coordinate data. These assets do not establish
item presence, navigation paths, extra-mode coverage or additional release support.
