# Build Outbreak Status Tracker

Run these commands from the repository root. The source is shared across platforms, but each platform builds its own native reader and package. The GitHub [Build all platforms workflow](https://github.com/solitonmedic/Outbreak-Tracker-DX/actions/workflows/build-all.yml) can build all three on their native runners; it starts only when manually dispatched.

## macOS

Install the Xcode Command Line Tools, CMake and LuaJIT, and place LÖVE 11.5 at `/Applications/love.app`. The first CMake configure needs network access to fetch PINE unless `macos/pine-source/` is present. zlib comes from the macOS SDK.

```sh
brew install cmake luajit
./macos/build-app.sh
./macos/build-app.sh --debug
```

The first command builds `Outbreak Status Tracker.app`; `--debug` builds a separate `Outbreak Status Tracker Debug.app`. Each is universal for Apple Silicon and Intel. The release build uses `macos/build-arm64/` and `macos/build-x86_64/`; the debug build uses `macos/build-debug-arm64/` and `macos/build-debug-x86_64/`. Set `LOVE_APP` if LÖVE lives elsewhere, or `OUTBREAK_APP_DIR` to choose an output app path.

For a Terminal run without an app bundle, build the Apple Silicon reader and launch it through LÖVE:

```sh
cmake -S macos -B macos/terminal-build-arm64 -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build macos/terminal-build-arm64 --config Release
./macos/run.sh
```

For a Terminal debug reader:

```sh
cmake -S macos -B macos/terminal-build-debug-arm64 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_OSX_ARCHITECTURES=arm64 -DOUTBREAK_DEBUG_RECORDER=ON
cmake --build macos/terminal-build-debug-arm64 --config RelWithDebInfo
OUTBREAK_RECORD_AUTOSTART=0 ./macos/run.sh --debug
```

The debug build records compressed EE-RAM checkpoints. It normally starts recording when the app opens; `OUTBREAK_RECORD_AUTOSTART=0` waits for **F9**. **F9** stops or starts a run, and **F10** adds a marker. Set `OUTBREAK_RECORD_LABEL`, `OUTBREAK_RECORD_DIR` or `OUTBREAK_RECORD_INTERVAL` before launch to choose the first label, parent directory or interval. Terminal input also becomes markers. Runs go to `~/Documents/Outbreak Tracker Recordings/` by default. They can contain game login and network data, so keep them private. See [macOS build notes](macos/README.md) for use details.

### How the macOS build works

CMake copies the shared `sources/main.c` reader, applies `macos/patch_legacy_source.cmake` to that copy and compiles it as C++17. The macOS `windows.h` shim turns the reader's memory requests into PINE reads over TCP port `28011`. The release-specific File 1 address profile is shared with Windows and Linux.

`build-app.sh` compiles an arm64 and an x86_64 reader, combines them into one native module with `lipo`, and places that module, the shared Lua UI, assets and a copy of LÖVE inside the app bundle. The debug option also compiles `sources/PineRecorder.cpp` with zlib into the native module and loads `macos/overrides/debug.lua`. The normal app does not include the recorder.

## Linux

On Ubuntu 24.04, install the packages used by the Linux workflow. A local Terminal run also needs LÖVE 11.5. The first CMake configure downloads PINE and LuaJIT source for headers; use `-DFETCHCONTENT_SOURCE_DIR_PINE=/path/to/pine` and `-DFETCHCONTENT_SOURCE_DIR_LUAJIT=/path/to/LuaJIT` if you already have local copies.

```sh
sudo apt-get update
sudo apt-get install -y cmake g++ git curl squashfs-tools fuse3
cmake -S linux -B linux/build -DCMAKE_BUILD_TYPE=Release
cmake --build linux/build --config Release --parallel
./linux/run.sh
```

The native reader is `linux/build/luaoutbreaktracker.so`. If LÖVE is outside `PATH`, set `LOVE_BIN` to its executable. For the LÖVE Flatpak, run `LOVE_FLATPAK=1 ./linux/run.sh`; the launcher grants it access to the runtime socket.

To make the x86_64 AppImage, download the official LÖVE 11.5 and appimagetool AppImages, then package the reader:

```sh
curl -fsSL -o linux/love-11.5-x86_64.AppImage https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage
curl -fsSL -o linux/appimagetool-x86_64.AppImage https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x linux/love-11.5-x86_64.AppImage linux/appimagetool-x86_64.AppImage linux/build-appimage.sh
./linux/build-appimage.sh
```

The output is `OutbreakStatusTracker-x86_64.AppImage` in the repository root. `LOVE_APPIMAGE`, `APPIMAGETOOL` and `OUTBREAK_APPIMAGE` can override the input and output paths. See [Linux build notes](linux/README.md) for launch options.

### How the Linux build works

Linux also copies and patches `sources/main.c` before compiling it as C++17. Its `windows.h` shim translates the shared reader's memory requests into PINE reads through `$XDG_RUNTIME_DIR/pcsx2.sock`. The Lua UI and assets are the same files used on macOS and Windows. `linux/run.sh` assembles a temporary LÖVE game folder with the native module and starts LÖVE. `build-appimage.sh` instead extracts the official LÖVE AppImage, adds the game and reader, and repacks it as one executable AppImage.

## Windows

Use Windows 10 or newer with Visual Studio 2022's Desktop development with C++ workload, Git and PowerShell. The build needs LuaJIT v2.1, the official LÖVE 11.5 x64 ZIP and [rcedit v2.0.0 x64](https://github.com/electron/rcedit/releases/tag/v2.0.0). From the repository root, clone LuaJIT:

```powershell
git clone --depth 1 --branch v2.1 https://github.com/LuaJIT/LuaJIT.git windows/luajit
```

In an x64 Visual Studio Developer Command Prompt, from the repository root:

```bat
cd windows\luajit\src
msvcbuild.bat
mkdir "..\..\Outbreak Tracker\lib\x64"
copy lua51.lib "..\..\Outbreak Tracker\lib\x64\lua51.lib"
cd ..\..\..
msbuild "windows\Outbreak Tracker.sln" /m /p:Configuration=Release /p:Platform=x64
```

Extract the [LÖVE 11.5 Windows x64 ZIP](https://github.com/love2d/love/releases/tag/11.5), then package from PowerShell in the repository root:

```powershell
./windows/package.ps1 -LoveRuntimeDirectory 'C:\path\to\love-11.5-win64' -ResourceEditorPath 'C:\path\to\rcedit-x64.exe'
```

The DLL is `windows/Outbreak Tracker/Build/Release/x64/luaoutbreaktracker.dll`. The package is `windows/build/OutbreakTracker-Windows-x64.zip`; keep the extracted EXE and DLLs together. `-SkipArchive` leaves the distribution at `windows/build/stage/distribution/`, as the GitHub workflow does. Windows reads PCSX2 memory directly and does not use PINE. See [Windows build notes](windows/README.md).

## Build checks

The manual GitHub workflow builds and verifies the macOS app, Linux AppImage and Windows distribution, then uploads each as an artifact. Its checks establish that the packages were built and contain the expected files. They do not test gameplay. The local reader and recorder offline checks are in the workspace's ignored `tools-n-shit/tracker-tests/` directory; they are not part of a fresh Git clone.
