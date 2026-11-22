# macOS debug build with run recording (dev branch only)

This folder exists only on the `dev` branch. Releases on `main` leave it out, together with `sources/PineRecorder.cpp` and `tests/`, so release builds never contain the recorder.

The debug build is for testing and is not a release. It shows the same tracker and also records the run in the format of `record-pine-ee-run.py`: one compressed 32 MiB EE-RAM checkpoint every 10 seconds, extra checkpoints when player 1 settles in a new room or a marker is added, and a `manifest.json` with a JSON sidecar per checkpoint. It only reads memory. The reader detects Japanese and U.S. File 1 automatically. U.S. fields without a mapped address remain unavailable; some host, lobby and puzzle fields still need work.

## Files

| File | Role |
|---|---|
| `CMakeLists.txt` | The normal reader from `macos/CMakeLists.txt` plus `sources/PineRecorder.cpp`, linked with zlib |
| `build-app.sh` | Builds `Outbreak Status Tracker Debug.app` by running `macos/build-app.sh` with this CMake project, then installs `main.lua` and renames the app |
| `run.sh` | Runs the Terminal debug reader through LÖVE |
| `main.lua` | Lua entry point: loads the normal macOS tracker (`main_mac.lua`) and drives the recorder (F9, F10, window title) |

## Debug app

Prerequisites are the same as for the release app (see `BUILDING.md`): Xcode Command Line Tools, Homebrew `cmake` and `luajit`, LÖVE 11.5 at `/Applications/love.app` (or `LOVE_APP`), and network access the first time CMake fetches PINE. zlib comes from the macOS SDK. Run from the repository root:

```sh
./macos/debug/build-app.sh
```

This creates `Outbreak Status Tracker Debug.app` (universal, build folders `macos/build-debug-arm64/` and `macos/build-debug-x86_64/`; `OUTBREAK_APP_DIR` chooses another output path). Recording starts when the app opens and ends when it closes; nothing is saved until PCSX2 has a game loaded. In the app:

- **F9** stops the current recording, or starts a new one in a new folder.
- **F10** adds a marker.

The window title shows the recording state. Runs are saved under `~/Documents/Outbreak Tracker Recordings/<label>/`, by default labelled `tracker-debug-<date>-<time>`. These environment variables change that when the app is started from Terminal:

| Variable | Effect |
|---|---|
| `OUTBREAK_RECORD_LABEL` | Label of the first run |
| `OUTBREAK_RECORD_DIR` | Parent folder for run folders |
| `OUTBREAK_RECORD_INTERVAL` | Seconds between checkpoint start times (default 10) |
| `OUTBREAK_RECORD_AUTOSTART` | Set to `0` to wait for F9 before recording |

## Terminal debug reader

Each line typed into the Terminal is saved as a marker:

```sh
cmake -S macos/debug -B macos/terminal-build-debug-arm64 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build macos/terminal-build-debug-arm64 --config RelWithDebInfo
OUTBREAK_RECORD_LABEL=my-run ./macos/debug/run.sh
```

Set `OUTBREAK_RECORD_AUTOSTART=0` to wait for F9 instead of recording at once.

Recordings contain the game's login and network data. Keep them private.

The debug recorder recognizes U.S. File 1 `SLUS-20765` / `2.00` with retail CRC `0245ef6d` or the alternate boot executable CRC `0244e76c`. Other fingerprints retain periodic full-memory recording without inferred File 1 state fields.

## Check

The release app must not export the recorder, and the debug app must:

```sh
nm -arch all -gU "Outbreak Status Tracker.app/Contents/Resources/game/luaoutbreaktracker.so" | grep -c luaopen_luaoutbreakrecorder        # 0
nm -arch all -gU "Outbreak Status Tracker Debug.app/Contents/Resources/game/luaoutbreaktracker.so" | grep -c luaopen_luaoutbreakrecorder  # 2 (one per architecture)
```
