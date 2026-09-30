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

The tracker still requires PCSX2 running the Japanese game with **PINE enabled on TCP port `28011`**.
