# Linux build files

This folder contains the files used to build and test the Linux version of Outbreak Status Tracker.

## Building from Terminal

You will need a C++17 compiler, CMake, and LÖVE 11.5 or newer. The Linux build includes the Lua headers it needs, so a system LuaJIT development package is not required.

From the project folder, run:

```sh
cmake -S linux -B linux/build -DCMAKE_BUILD_TYPE=Release
cmake --build linux/build --config Release
./linux/run.sh
```

The first CMake configure downloads the PINE and LuaJIT headers. To use local checkouts, pass `-DFETCHCONTENT_SOURCE_DIR_PINE=/path/to/pine` and `-DFETCHCONTENT_SOURCE_DIR_LUAJIT=/path/to/LuaJIT`.

The tracker still requires PCSX2 running the Japanese game with **PINE enabled**. On Linux, PINE uses a Unix socket named `pcsx2.sock` in `$XDG_RUNTIME_DIR` rather than TCP port `28011`.

If you are using the LÖVE Flatpak (`org.love2d.love2d`), run `LOVE_FLATPAK=1 ./linux/run.sh`. The launcher grants the Flatpak access to `$XDG_RUNTIME_DIR` so it can reach PINE. Otherwise, if LÖVE is installed somewhere other than your `PATH`, set `LOVE_BIN` to its executable before running `./linux/run.sh`.

## Building an AppImage

Download the official LÖVE 11.5 x86_64 AppImage and save it as `linux/love-11.5-x86_64.AppImage`. Download the x86_64 `appimagetool` AppImage and save it as `linux/appimagetool-x86_64.AppImage`. Then run:

```sh
chmod +x linux/love-11.5-x86_64.AppImage linux/appimagetool-x86_64.AppImage linux/build-appimage.sh
./linux/build-appimage.sh
```

The resulting `OutbreakStatusTracker-x86_64.AppImage` includes the tracker and LÖVE runtime. It uses Linux PINE's `pcsx2.sock` runtime socket directly and does not need Flatpak permissions.

The GitHub Actions workflow builds this AppImage automatically on pushes to `main` and can also be started manually.
