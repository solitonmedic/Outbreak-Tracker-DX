# Linux build files

This folder contains the files used to build and test the Linux version of Outbreak Status Tracker.

`patch_legacy_source.cmake` reads `INPUT` and writes a generated C++ reader to
`OUTPUT`. It preserves byte offsets when casting room-item state pointers and
keeps the shared reader's object-state filter, with an additional item-ID bounds
check. It does not read the game or modify `sources/main.c`; the build runs it.

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

If you are using the LÖVE Flatpak (`org.love2d.love2d`), run `LOVE_FLATPAK=1 ./linux/run.sh`. The launcher grants the Flatpak access to `$XDG_RUNTIME_DIR` so it can reach PINE. Otherwise, if LÖVE is installed somewhere other than your `PATH`, set `LOVE_BIN` to its executable before running `./linux/run.sh`.

## Building an AppImage

Download the official LÖVE 11.5 x86_64 AppImage and save it as `linux/love-11.5-x86_64.AppImage`. Download the x86_64 `appimagetool` AppImage and save it as `linux/appimagetool-x86_64.AppImage`. Then run:

```sh
chmod +x linux/love-11.5-x86_64.AppImage linux/appimagetool-x86_64.AppImage linux/build-appimage.sh
./linux/build-appimage.sh
```

The resulting `OutbreakStatusTracker-x86_64.AppImage` includes the tracker and LÖVE runtime. It uses Linux PINE's `pcsx2.sock` runtime socket directly and does not need Flatpak permissions.

The GitHub Actions workflow is manual-only and can be started from the repository's Actions page. The all-platform workflow can also call it after a manual dispatch.
