# macOS build files

This folder contains the files used to build and test the macOS version of Outbreak Status Tracker.

`patch_legacy_source.cmake` reads `INPUT` and writes a generated C++ reader to
`OUTPUT`. It preserves byte offsets when casting room-item state pointers and
keeps the shared reader's object-state filter, with an additional item-ID bounds
check. It does not read the game or modify `sources/main.c`; the build runs it.
U.S. File 1 room authority refreshes on each update; the legacy releases keep
their existing room-authority polling interval.

## Build a Finder app

From the project’s main folder, run:

```sh
./macos/build-app.sh
```

The finished app is created as `Outbreak Status Tracker.app` in the main project folder. The app bundles its LÖVE runtime and native reader, so another person does not need to assemble the project files by hand.

The build creates a universal app for Apple Silicon and Intel Macs. It does not create a ZIP file.

## Run from Terminal

`run.sh` launches the tracker directly through LÖVE and is useful for testing. It expects the Apple Silicon native reader at `macos/terminal-build-arm64/luaoutbreaktracker.so`.

Build that reader with:

```sh
cmake -S macos -B macos/terminal-build-arm64 -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build macos/terminal-build-arm64 --config Release
./macos/run.sh
```

The tracker requires PCSX2 running a supported game with **PINE enabled on TCP port `28011`**. Japanese File 1 and File 2 are supported. U.S. File 1 is detected automatically, but support is partial; see the [project README](../README.md) for current limits.

The app switches to the English UI atlas for U.S. File 1 and keeps the original atlas for the Japanese games.

U.S. host rooms show the selected room's player count when its lobby data is
available. Hive puzzle hints read the current updated-game codes and hide while
the loaded code tables are unavailable; leading zeros are preserved.
In-game room-master crowns use the loaded U.S. authority table. Unavailable or
changing data suppresses the crown; a gameplay-screen comparison is pending.

## Debug build with run recording

The debug build is for testing and is not a release. It shows the same tracker and also records the run in the format of `record-pine-ee-run.py`: one compressed 32 MiB EE-RAM checkpoint every 10 seconds, extra checkpoints when player 1 settles in a new room or a marker is added, and a `manifest.json` with a JSON sidecar per checkpoint. It only reads memory. The reader detects Japanese and U.S. File 1 automatically. U.S. fields without a mapped address remain unavailable; some host, lobby and puzzle fields still need work.

```sh
./macos/build-app.sh --debug
```

This creates `Outbreak Status Tracker Debug.app`. Recording starts when the app opens and ends when it closes; nothing is saved until PCSX2 has a game loaded. In the app:

- **F9** stops the current recording, or starts a new one in a new folder.
- **F10** adds a marker.

The window title shows the recording state. Runs are saved under `~/Documents/Outbreak Tracker Recordings/<label>/`, by default labelled `tracker-debug-<date>-<time>`. These environment variables change that when the app is started from Terminal:

| Variable | Effect |
|---|---|
| `OUTBREAK_RECORD_LABEL` | Label of the first run |
| `OUTBREAK_RECORD_DIR` | Parent folder for run folders |
| `OUTBREAK_RECORD_INTERVAL` | Seconds between checkpoint start times (default 10) |
| `OUTBREAK_RECORD_AUTOSTART` | Set to `0` to wait for F9 before recording |

To run the debug reader from Terminal, where each line you type is saved as a marker:

```sh
cmake -S macos -B macos/terminal-build-debug-arm64 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_OSX_ARCHITECTURES=arm64 -DOUTBREAK_DEBUG_RECORDER=ON
cmake --build macos/terminal-build-debug-arm64
OUTBREAK_RECORD_LABEL=my-run ./macos/run.sh --debug
```

Recordings contain the game's login and network data. Keep them private.

The debug recorder recognizes U.S. File 1 `SLUS-20765` / `2.00` with retail CRC
`0245ef6d` or the alternate boot executable CRC `0244e76c`. Other fingerprints
retain periodic full-memory recording without inferred File 1 state fields.

The shared SP layout pilot uses generated `sources/layout.lua` and
`sources/SPTracking.lua`, both included by the existing app packager. Text uses
the same Arial Bold font as password hints. The display stays hidden until the
reader supplies valid SP state; this is not live SP detection yet.

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
tints. Your room is red; other occupied rooms use a lighter blue. Gas rooms
pulse with a yellow glow. Floors without a reliable fit retain the game's artwork.

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
existing reader connection (at most4 samples/second, supported profiles and
loaded-code guards). The private Deck provider replaces that sample and retains
its radar. Native renderer/reader source was C11/offline-checked on macOS; the
Linux debug module is built on the Deck. No macOS application, Windows MSVC build
or AppImage was produced by this presentation pass. These changes need user-run
in-game comparison; synthetic previews establish layout, not live accuracy.
