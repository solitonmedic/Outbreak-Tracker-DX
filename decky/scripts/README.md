# Development commands

Run from `repo-merged/`. Python scripts use Python 3's standard library.

| Script | Purpose and invocation | Reads and writes |
| --- | --- | --- |
| `deck.py` | Mac driver: `python3 decky/scripts/deck.py doctor`, then `sync`, `build`, `fetch` after committing. Uses Git/SSH/SCP. | Doctor reads environment. Other commands synchronize committed Git history, build on the Deck and retrieve ignored artifacts. |
| `sync_checkout.py` | Guarded receiver, invoked by `deck.py sync` from the committed revision. Arguments: bundle, destination, expected commit. | Reads a Git bundle; creates or fast-forwards the named development clone. Refuses dirty, unrelated or diverged destinations. |
| `build.py` | Deck build: `python3 decky/scripts/build.py --expect-commit "$(git rev-parse HEAD)"`. Requires Node 24.19.0 and downloads pinned pnpm 9.15.9 via Corepack. | Reads committed source/lockfile, writes dependencies, frontend and package/report under ignored paths and user caches. |
| `../main.py` | Decky Python backend; loaded by installing the ZIP and opening its panel. | Reads package/build metadata and only relevant PCSX2 settings; returns setup status and writes lifecycle log messages through Decky. |
| `../rollup.config.js` | Node build configuration used by `pnpm run build` through `build.py`. | Reads frontend sources/dependencies and emits `dist/`. |

No command installs the plugin, restarts services, writes emulator settings, reads
live PINE memory, starts recording, or accesses saved recordings/workbooks. Each
script header includes its inputs, outputs, safety boundary and expected result.
See the parent README for the full build/install/rollback procedure.
