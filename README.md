# Outbreak Tracker DX

Unified source repository for the Windows, macOS, and Linux versions of Outbreak Status Tracker.

## Repository layout

- `sources/` holds the shared game reader, memory address maps, Lua UI, and data structures.
- `assets/` holds the shared artwork, fonts, and UI images.
- `windows/`, `macos/`, and `linux/` hold platform-specific build, launch, and packaging files.
- `.github/workflows/` contains the individual platform builds and the coordinated all-platform workflow.

Windows reads the PCSX2 process memory directly. macOS and Linux use PCSX2's PINE interface for memory reads.

## Supported game and emulator setup

Use the Japanese version of Resident Evil Outbreak File 1 or File 2 in PCSX2.

- macOS: enable PINE on TCP port `28011`.
- Linux: enable PINE and allow the tracker to access PCSX2's `pcsx2.sock` in the runtime directory.
- Windows: run PCSX2 and the tracker on the same Windows system; the native reader attaches to the PCSX2 process.

## Build the platform packages

The `Build macOS app` and `Build Linux AppImage` workflows preserve the existing platform build processes. `Build Windows package` builds the native DLL and stages the shared LÖVE game files. Run `Build all platforms` manually or push a `v*` tag to build all three artifacts in one workflow run.

Each artifact is uploaded to the workflow run. The Windows ZIP contains a `lua` folder and requires LÖVE 11.5 or newer; extract it and launch with `love lua`.

These are GitHub Actions workflows under `.github/workflows`. They run from `solitonmedic/Outbreak-Tracker-DX` using GitHub's macOS, Linux, and Windows runners. The platform workflows run on pushes to `main` or manual dispatch; `Build all platforms` runs manually or on `v*` tags. Keep this repository as the build source so its commits and tags trigger the workflows.

For local steps, see [macOS build notes](macos/README.md), [Linux build notes](linux/README.md), and [Windows build notes](windows/README.md).
