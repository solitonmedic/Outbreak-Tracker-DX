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

These assets prepare [#10](https://github.com/solitonmedic/Outbreak-Tracker-DX/issues/10)
and [#16](https://github.com/solitonmedic/Outbreak-Tracker-DX/issues/16). They are
not connected to the tracker renderer yet. Keep the original GIFs as provenance
if the renderer needs a lossless format conversion later.

Room coordinates use the original image's pixels. Source location IDs are
Evil Resource identifiers, not game room IDs. An explicit room-ID crosswalk and
validated game-coordinate-to-image transforms are still needed. No calibration,
item-presence information, navigation graph, extra-mode coverage or new game
release support is implied by this download.
