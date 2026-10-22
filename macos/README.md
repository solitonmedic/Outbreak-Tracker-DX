# macOS build files

This folder contains the files used to build and test the macOS version of Outbreak Status Tracker.

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
