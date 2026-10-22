# Development commands

Run from `repo-merged/`. Python scripts use Python 3's standard library.

| Script | Purpose and invocation | Reads and writes |
| --- | --- | --- |
| `deck.py` | Mac driver: `python3 decky/scripts/deck.py doctor`, then `sync`, `build`, `fetch` after committing. Uses Git/SSH/SCP. | Doctor reads environment. Other commands synchronize committed Git history, build on the Deck and retrieve ignored artifacts. |
| `sync_checkout.py` | Guarded receiver, invoked by `deck.py sync` from the committed revision. Arguments: bundle, destination, expected commit. | Reads a Git bundle; creates or fast-forwards the named development clone. Refuses dirty, unrelated or diverged destinations. |
| `build.py` | Deck build: `python3 decky/scripts/build.py --expect-commit "$(git rev-parse HEAD)"`. Requires Node 24.19.0 and downloads pinned pnpm 9.15.9 via Corepack. | Reads committed source/lockfile, writes dependencies, frontend and package/report under ignored paths and user caches. |
| `../main.py` | Decky Python backend; loaded by installing the ZIP and opening its panel. | Reads package/build metadata and only relevant PCSX2 settings; returns setup status and writes lifecycle log messages through Decky. |
| `../rollup.config.js` | Node build configuration used by `pnpm run build` through `build.py`. | Reads frontend sources/dependencies and emits `dist/`. |

Development commands do not install the plugin, restart services, write emulator
settings, start recording, or access saved recordings/workbooks. Each
script header includes its inputs, outputs, safety boundary and expected result.
See the parent README for the full build/install/rollback procedure.

## Live reader additions

- `bootstrap_native.py`: `python3 decky/scripts/deck.py native-setup` after sync. Downloads checksum-pinned micromamba and installs a locked compiler/CMake/Pillow environment under the Deck user home. No OS or emulator changes.
- `native_build.py`: called by build.py; reuses the shared Linux build with a pinned PINE revision, emits native module and font metrics into ignored output.
- `font_metrics.py`: called with the user toolchain Python and Pillow; reads original fonts/images and writes the Lua metric table.
- `../reader.lua`: LuaJIT child running the shared UI and reader; reads live PINE and emits in-memory drawing frames.
- `../tracker_service.py`: standard-library Python HTTP/child lifecycle; serves LAN port 28080 to local-network clients only (no login), with same-origin JSON controls. Stops on plugin unload.
- `../web/app.js`: browser Canvas adapter and touch/keyboard controls, using original assets and fonts.

Build/sync commands do not access PINE. The installed plugin's service and reader
do read live PINE when started; they never write game memory or create recordings.
- `make_icons.py`: reusable one-time generator for the home-screen icons in `web/icons/` (committed). Needs Pillow; run with the bundled Codex Python from `repo-merged/` (see its header).
