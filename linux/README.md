# Linux build files

This folder contains the files used to build and test the Linux version of Outbreak Status Tracker.

`patch_legacy_source.cmake` reads `INPUT` and writes a generated C++ reader to
`OUTPUT`. It preserves byte offsets when casting room-item state pointers and
keeps the shared reader's object-state filter, with an additional item-ID bounds
check. It does not read the game or modify `sources/main.c`; the build runs it.
U.S. File 1 room authority refreshes on each update; the legacy releases keep
their existing room-authority polling interval.

## Building from Terminal

You will need a C++17 compiler, CMake, and LÖVE 11.5 or newer. The Linux build includes the Lua headers it needs, so a system LuaJIT development package is not required.

From the project folder, run:

```sh
cmake -S linux -B linux/build -DCMAKE_BUILD_TYPE=Release
cmake --build linux/build --config Release
./linux/run.sh
```

The first CMake configure downloads the PINE and LuaJIT headers. To use local checkouts, pass `-DFETCHCONTENT_SOURCE_DIR_PINE=/path/to/pine` and `-DFETCHCONTENT_SOURCE_DIR_LUAJIT=/path/to/LuaJIT`.

The tracker requires PCSX2 running a supported game with **PINE enabled**. Japanese File 1 and File 2 are supported; U.S. File 1 support is partial. On Linux, PINE uses a Unix socket named `pcsx2.sock` in `$XDG_RUNTIME_DIR` rather than TCP port `28011`. See the [project README](../README.md) for current limits.

The shared UI selects English art for U.S. File 1 and the original art for the Japanese games; both atlases are included in the AppImage.

U.S. host rooms show the selected room's player count when its lobby data is
available. Hive puzzle hints read the current updated-game codes and hide while
the loaded code tables are unavailable; leading zeros are preserved.
In-game room-master crowns use the loaded U.S. authority table. Unavailable or
changing data suppresses the crown; a gameplay-screen comparison is pending.

If you are using the LÖVE Flatpak (`org.love2d.love2d`), run `LOVE_FLATPAK=1 ./linux/run.sh`. The launcher grants the Flatpak access to `$XDG_RUNTIME_DIR` so it can reach PINE. Otherwise, if LÖVE is installed somewhere other than your `PATH`, set `LOVE_BIN` to its executable before running `./linux/run.sh`.

## Building an AppImage

Download the official LÖVE 11.5 x86_64 AppImage and save it as `linux/love-11.5-x86_64.AppImage`. Download the x86_64 `appimagetool` AppImage and save it as `linux/appimagetool-x86_64.AppImage`. Then run:

```sh
chmod +x linux/love-11.5-x86_64.AppImage linux/appimagetool-x86_64.AppImage linux/build-appimage.sh
./linux/build-appimage.sh
```

The resulting `OutbreakStatusTracker-x86_64.AppImage` includes the tracker and LÖVE runtime. It uses Linux PINE's `pcsx2.sock` runtime socket directly and does not need Flatpak permissions.

The GitHub Actions workflow is manual-only and can be started from the repository's Actions page. The all-platform workflow can also call it after a manual dispatch.

## Map views

Press **B** for the map beside the player cards, **N** for the map above compact
cards, and **F** to follow the selected player again. **V** returns to the normal
card view. Drag to pan, scroll to zoom, use Fit to see the floor, and use the floor
row to select another floor. Clicking a player follows that player. Manual pan
or floor selection stops follow.

Maps for the five main scenarios of Japanese File 1 and File 2 are built into the
application (the File 1 maps also serve the U.S. release). They load automatically;
there is no disc selection, import, download or user-cache setup step, and no game
files are needed.

Fitted floors use Evil Resource artwork with blue walls, yellow doors and room
tints. Your room is red; other occupied rooms use a lighter blue. Gas rooms
pulse with a yellow glow. Floors without Evil Resource artwork show their rooms as
dark shapes with blue outlines, traced from the game's room layout.

Players use red, blue, yellow and green by slot; YOU identifies the local gameplay
record. A dot marks a usable position. A portrait in a ring marks only the room,
including rooms spanning multiple height bands. Select the desired floor manually
in those cases. Player chevrons turn with each character's facing; height selects the matching floor band. YOU is the game's own local player. Desperate Times
highlights the current gas rooms in yellow. Existing puzzle hints and timers stay
visible. Enemies in play show as small white diamonds with their HP percentage,
and the items in your current room show as tracker item icons.
U.S. File 1 uses the same maps as the Japanese release; extra File 2 scenarios
are not enabled.


### Development map presentation (2026-11-20)

B/N map views show enabled remote players, keep the follow zoom across floors,
and use the actor height for rooms spanning multiple floors. YOU's room is red,
other occupied rooms light blue, previously visited rooms light green, and DT gas
rooms glow yellow. Only YOU's entries count as visits. Room-item observations and
SP markers are remembered in memory until the run resets; known scenario items
are orange until taken, personal SP markers blue, other SP markers green. Hover
or tap an item for its name. Boss markers are red. Timer, item/SP set and supported
puzzle/scenario hints remain visible on maps.

Danger cards glow red, Downed cards pulse red/black, dead portraits turn red and
voice events briefly glow green. Virus figures are larger; baseline100% power is
hidden. Timer badges and the room-master crown have separate positions. Click
CONTROLS (or right-click/Tab) for tracker-styled controls; MAIN TRACKER returns from
the map. The floor strip scrolls when more than five floor groups exist.

Shared `sources/SPMapReader.h` supplies bounded SP room records through the
existing reader connection (at most 4 samples/second, supported profiles and
loaded-code guards).

Map9 follow-up: both map layouts also show the SP compass/counter beside the
clock, labelled YOU because its bearing follows the local player's facing even
when following another player. Existing provider glow is retained. Native
room-only SP data derives direction from already-exported item positions and
player facing; unavailable direction remains hidden. The row keeps a fixed
height during dropped samples. English room labels use “Drawing Room”.

Map10 presentation: the two legacy ITEM values are stacked vertically. Floor
buttons separate labels from portraits, with wider cells and scrolling when
needed. Wild Things uses GF for the outside area and Zoo for the interior,
in the map heading and floor buttons; Wild Things compact cards omit floor text. The map9 SP radar remains
beside the clock and stays relative to YOU. These UI changes add no memory reads.

Map10-r2 overlay priority: player markers, ordinary items, SP, scenario objects,
then enemy HP text. Overlapping item tooltips select the top-priority object.
Nearby floating player labels hide with separation hysteresis; cards/legend stay
identified. Ad-lib circles are smaller on markers and floor portraits.
