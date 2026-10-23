# Development commands

Run from `repo-merged/`. Python scripts use Python 3's standard library.

| Script | Purpose and invocation | Reads and writes |
| --- | --- | --- |
| `build.py` | Build: `python3 decky/scripts/build.py --expect-commit "$(git rev-parse HEAD)"`. Requires Node 24.19.0 and downloads pinned pnpm 9.15.9 via Corepack. | Reads committed source/lockfile, writes dependencies, frontend and package/report under ignored paths and user caches. |
| `../main.py` | Decky Python backend; loaded by installing the ZIP and opening its panel. | Reads package/build metadata and only relevant PCSX2 settings; returns setup status and writes lifecycle log messages through Decky. |
| `../rollup.config.js` | Node build configuration used by `pnpm run build` through `build.py`. | Reads frontend sources/dependencies and emits `dist/`. |

Build commands do not install the plugin, restart services, write emulator
settings, start recording, or access saved recordings/workbooks. Each
script header includes its inputs, outputs, safety boundary and expected result.
See the parent README for the full build/install/rollback procedure.

## Live reader additions

- `bootstrap_native.py`: `python3 decky/scripts/bootstrap_native.py`, once per machine. Downloads checksum-pinned micromamba and installs a locked compiler/CMake/Pillow environment under the Deck user home (the GitHub workflow runs it directly on its runner). No OS or emulator changes.
- `native_build.py`: called by build.py; reuses the shared Linux build with a pinned PINE revision, emits native module and font metrics into ignored output; its CMake build folder is `.artifacts/native/cmake-build` inside each checkout.
- `font_metrics.py`: called with the user toolchain Python and Pillow; reads original fonts/images and writes the Lua metric table.
- `../reader.lua`: LuaJIT child running the shared UI and reader; reads live PINE and emits in-memory drawing frames.
- `../tracker_service.py`: standard-library Python HTTP/child lifecycle; serves LAN port 28080 to local-network clients only (no login), with same-origin JSON controls. Stops on plugin unload.
- `../web/app.js`: browser Canvas adapter and touch/keyboard controls, using original assets and fonts.

Build commands do not access PINE. The installed plugin's service and reader
do read live PINE when started; they never write game memory or create recordings.
- `../../.github/workflows/build-decky.yml`: manual workflow that runs `bootstrap_native.py` then `build.py` on `ubuntu-24.04` and uploads the ZIP; `build.py` allows any branch and the Node on PATH only when `GITHUB_ACTIONS=true`.
