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

The shared UI loads `assets/ui.png` and `assets/ui-us.png`. After the reader identifies U.S. File 1, it selects the English atlas; Japanese File 1 and File 2 use the original atlas. All platform packages copy both files from `assets/`.

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

## Steam Deck (Decky plugin)

The plugin is in `decky/` on the `Decky` branch. The native reader has to be built for Linux x86_64, so the build runs on the Deck. A script on your Mac or Linux computer sends the committed source to the Deck over SSH, builds it there and copies the ZIP back. See [decky/README.md](decky/README.md) for the full procedure, rollback and logs.

**On the Deck**, you need SSH access as `deck` with key login (the scripts never prompt for a password), Git, Python 3, Decky Loader, and Node.js 24.19.0 installed with nvm at `/home/deck/.nvm/versions/node/v24.19.0/`. Corepack comes with that Node and downloads pnpm 9.15.9 on the first build. SteamOS provides `/usr/bin/luajit`, which the plugin runs at runtime. The first build also needs network access for the pnpm packages, a pinned micromamba download and the PINE source. Nothing is installed system-wide.

**On your computer**, you need Git, Python 3, `ssh` and `scp`, and an SSH host alias named `steamdeck` for the Deck in `~/.ssh/config`. Pass `--host` to use another name.

From the repository root, on the `Decky` branch:

```sh
git checkout Decky
python3 decky/scripts/deck.py doctor
python3 decky/scripts/deck.py sync
python3 decky/scripts/deck.py native-setup
python3 decky/scripts/deck.py build
python3 decky/scripts/deck.py fetch
```

`doctor` only reads and reports what the Deck has. `sync` sends the committed `Decky` history as a Git bundle to `/home/deck/Projects/Outbreak-Tracker-DX` and refuses to run if `decky/` has uncommitted changes, so commit first. It refuses to touch a destination that is dirty, unrelated or diverged, and it never resets or cleans anything. `native-setup` creates a compiler, CMake and Pillow environment under the Deck user's home from `decky/native-toolchain.lock`. Run it once per Deck. `build` type-checks and builds the frontend, links the Linux reader against a pinned PINE revision, generates the font metrics and packs the ZIP. `fetch` copies it to your computer and checks its SHA-256. Both copies are named `outbreak-tracker-<version>-<commit>.zip` in `decky/.artifacts/`. Use `--checkout` to put the Deck's copy somewhere else.

**GitHub Actions.** The [Build Decky plugin workflow](https://github.com/solitonmedic/Outbreak-Tracker-DX/actions/workflows/build-decky.yml) builds the same ZIP on an `ubuntu-24.04` runner and uploads it, with `build-report.json`, as the `Outbreak-Tracker-Decky-Plugin` artifact. GitHub wraps an artifact in another ZIP, so extract that first. The workflow installs Node.js 24.19.0, runs `decky/scripts/bootstrap_native.py` and `decky/scripts/build.py` as they run on the Deck, and then checks the ZIP's contents and commit. It starts only when manually dispatched and is not part of Build all platforms. GitHub lists a manual workflow only after its file is on the default branch; once it is, you can choose which branch to build when you run it.

To install, copy the ZIP to the Deck, for example `scp decky/.artifacts/outbreak-tracker-*.zip steamdeck:Downloads/`. On the Deck, turn on Developer mode in Decky's settings, open Developer and choose **Install Plugin from ZIP File**. The scripts never install the plugin or restart Decky for you. Reopen the plugin panel after installing a new ZIP and compare the commit it shows with the one in the file name.

### How the Decky build works

`decky/main.py` is the Decky backend. It starts `decky/tracker_service.py`, a standard-library HTTP server on port `28080`, and a `luajit reader.lua` child process. `reader.lua` loads the shared `sources/` Lua UI behind a small LÖVE graphics adapter that writes drawing commands as JSON frames instead of drawing, and reads the game through the same native module built from `linux/CMakeLists.txt` and its patched copy of `sources/main.c`. `decky/web/app.js` draws those frames on a canvas with the original atlases and fonts and sends control keys back. The React panel in `decky/src/` shows the QR code and the start and stop buttons.

The ZIP holds the native module, the shared Lua, everything in `assets/`, the web files and the backend. `decky/scripts/make_icons.py` makes the home-screen icons from `sources/outbreak-tracker-icon-hd.png`; the PNGs are committed in `decky/web/icons/`, so a build does not need it. The plugin keeps the original Decky template's BSD 3-Clause license in `decky/LICENSE`.

## Build checks

The manual GitHub workflow builds and verifies the macOS app, Linux AppImage and Windows distribution, then uploads each as an artifact. Its checks establish that the packages were built and contain the expected files. They do not test gameplay. The Decky plugin has its own workflow, which checks the TypeScript, the frontend, the reader link, the Python syntax and the ZIP contents. It does not test gameplay either. The ZIP built on the Deck was installed and run there with an iPhone; the workflow's own run is separate. The local reader and recorder offline checks are in the workspace's ignored `tools-n-shit/tracker-tests/` directory; they are not part of a fresh Git clone.
