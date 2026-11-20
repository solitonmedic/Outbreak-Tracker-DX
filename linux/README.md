# Linux build files

## Development test package

The 2026-11-06 `dev` test package `0.3.1-debug.dev1` is a separate Decky build
with the experimental SP provider and explicit-start recorder. Its x86_64 native
module was linked using GCC14.4.0/CMake3.31.8 and the frozen Decky toolchain lock
in a local Linux container. Normal Linux/AppImage build commands below do not
enable that private provider. Full preparation/build/check commands and artifact
hashes are recorded in the workspace build/recorder reference.

This round builds the Decky native module and frontend/ZIP, not a Linux desktop
AppImage, Windows package or macOS app. Runtime checks use synthetic memory;
installation and comparison with the live game remain separate verification.

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

The sampled Japanese File 1 and File 2 map assets are included in the application.
Maps load automatically for the five main scenarios in each game; there is no disc
selection, import, download or user-cache setup step.

Fitted floors use Evil Resource artwork with blue walls, yellow doors and room
tints. Floors without a reliable fit retain the game's artwork.

Players use red, blue, yellow and green by slot; YOU identifies the local gameplay
record. A dot marks a usable position. A portrait in a ring marks only the room,
including rooms spanning multiple height bands. Select the desired floor manually
in those cases. Player chevrons turn with each character's facing; height is not
read yet. YOU is the game's own local player. Desperate Times
highlights the current gas rooms in yellow. Existing puzzle hints and timers stay
visible. Enemies in play show as small white diamonds with their HP percentage,
and the items in your current room show as tracker item icons.
U.S. File 1 uses the same maps as the Japanese release; extra File 2 scenarios
are not enabled.
