# Outbreak Tracker for Decky

The plugin starts a read-only PCSX2 PINE reader and serves a private phone view on
LAN port 8384. Scan the QR code in Decky or open its private link on another device
on the same network. The page draws the original shared Lua tracker UI with its
existing sprite atlases, fonts, card logic, release limits and keyboard controls.
Touch buttons mirror those controls; every connected device shares one view.

The browser preserves aspect ratio and uses a high-resolution canvas that fits
phone, tablet and desktop widths. Vertical mode suits phones; horizontal mode
remains available. The reader polls at five updates per second; the service marks
delayed data stale and retries a lost reader. No RAM snapshots or frame files are
saved. PINE supports a single client: stop this reader before using another tracker
or a recorder. Use **Stop phone view and reader** in Decky to release it.

## Source and prerequisites

The plugin lives in this repository's `decky/` folder on branch `Decky`. Keep the
Mac checkout authoritative. Commit source on the Mac, synchronize Git history over
SSH, then build on the Steam Deck. GitHub publication is a separate operation.
Do not edit both checkouts concurrently. Remote edits cause synchronization to stop;
bring useful edits back as Git commits before continuing.

The Deck needs Git, Python 3, SSH access as `deck`, and Node **24.19.0** with
Corepack at `/home/deck/.nvm/versions/node/v24.19.0/bin/`. Builds call that Node
installation explicitly, so an interactive shell or an nvm shell profile is not
required. Corepack downloads pinned **pnpm 9.15.9** into a user cache. Dependency
installation needs internet access. Native builds also use a user-only micromamba GCC/CMake/Pillow environment, created
by `native-setup` from the pinned `native-toolchain.lock`. No system package
installation is required. Runtime uses the Deck's existing `/usr/bin/luajit`.
The Mac driver needs Python 3, Git, SSH and SCP, using the existing `steamdeck` alias.

## Commit, synchronize, build, retrieve

Run every command below from the repository root (`repo-merged/` in the workspace).

```sh
python3 decky/scripts/deck.py doctor
git add decky
git commit -m "Describe the plugin change"
python3 decky/scripts/deck.py sync
python3 decky/scripts/deck.py native-setup  # once per Deck
python3 decky/scripts/deck.py build
python3 decky/scripts/deck.py fetch
```

The first synchronization clones a full Git bundle into
`/home/deck/Projects/Outbreak-Tracker-DX`. Later synchronizations fetch a bundle
and fast-forward its `Decky` branch. The clone has no configured origin: use this
workflow to update it. Its `.git/outbreak-tracker-sync` marker identifies the
checkout managed by the driver. The driver sends the receiver from the committed
revision, and refuses uncommitted plugin source. It ignores unrelated local edits
when deciding whether the plugin source is ready; none of those edits are copied.

Synchronization refuses a symlink destination, an unrelated directory, the wrong
branch, edits/untracked files on the Deck, or divergent/ahead history. Resolve the
reported state deliberately; the driver never resets or cleans a checkout.
The SSH host and absolute checkout path can be overridden with `--host` and
`--checkout`. These commands target the `deck` account and its home/cache layout.

The build uses the committed pnpm lockfile, checks TypeScript, builds the frontend,
compiles the existing Linux native reader with pinned PINE sources, generates font
metrics, parses Python, and verifies ZIP contents. It requires a clean Deck
checkout at exactly the Mac's commit. No live PINE reads occur.

Deck outputs are under `decky/.artifacts/` inside its checkout. Fetch copies the
ZIP and `build-report.json` to the Mac's `decky/.artifacts/`, verifying source
commit, version and SHA-256. The ZIP contains an `outbreak-tracker/` directory
with native reader, shared Lua UI, original assets, browser frontend, backend,
package metadata, licenses and `build-info.json`.
Build output and dependencies are ignored. Save older ZIPs to roll back a build.

To repeat a build directly over SSH, the equivalent command on the Deck is:

```sh
cd /home/deck/Projects/Outbreak-Tracker-DX
python3 decky/scripts/build.py --expect-commit "$(git rev-parse HEAD)"
```

## Install, refresh, inspect and roll back

On the Deck, open Decky settings, enable Developer mode, and use **Install Plugin
from ZIP File** to browse to the generated ZIP under
`/home/deck/Projects/Outbreak-Tracker-DX/decky/.artifacts/` (show hidden files if
needed). Installation is a separate user action. The development driver never
writes into the root-owned installed plugin directory or restarts the loader.

Open **Outbreak Tracker** from the Decky menu, check its version and commit, then
scan the QR code on your phone. The link includes a per-start access token in its
fragment; keep the full link private. The browser retains it in session storage
and sends it in an authorization header. A new service start invalidates old links.
The service listens on port 8384 and exposes only packaged web/artwork files plus
authenticated frame/control endpoints. It adds no firewall or router rules.

Start PCSX2 with PINE enabled and a supported game. The native reader uses
`/run/user/1000/pcsx2.sock` for default slot 28011. A waiting status means that a
supported game or endpoint is unavailable; enabling the setting alone does not
prove a connection. Existing U.S. mapping and puzzle limits remain in effect.

For another revision, install its ZIP again and reopen the plugin panel. Use
Decky's Developer reload control if available. Inspect Decky's logs view or the
plugin log under `/home/deck/homebrew/logs/Outbreak Tracker/`. The backend uses
Decky's logger; exact filenames follow the installed loader version. To remove
the plugin, use Decky's installed-plugin uninstall control. To roll back, install
the prior ZIP and compare its displayed commit. Unloading or uninstalling stops the child reader and HTTP service. No game data
is persisted; build tools and development ZIPs remain in user development paths.

## Reader and browser implementation

`reader.lua` runs the existing `sources/main.lua` and card modules using a small
LÖVE graphics adapter. It sends drawing commands and typed game status over a
private child-process pipe. `web/app.js` draws them on Canvas using original
textures and fonts, including image-font separators. The bridge does not export
raw RAM, duplicate memory-address maps, or execute browser-supplied code. Native
compilation reuses `linux/CMakeLists.txt` and its existing source patcher.

New endpoints: authorized `GET /api/frame` and `POST /api/key` with a whitelisted
key. Decky methods `get_status` and `set_running` expose lifecycle state and the
private link. Waiting/error/stale states are distinct from live. Browser and native
visual parity still require comparison in the user's game and phone browser.

## Template provenance and license

Adapted from Steam Deck Homebrew's [Decky plugin template at
90d0780e882a17f5714fc6de044c645f22608290](https://github.com/SteamDeckHomebrew/decky-plugin-template/tree/90d0780e882a17f5714fc6de044c645f22608290).
The frontend entry point, Decky API/UI integration, Rollup setup, Python lifecycle
and package layout follow that template. Its BSD 3-Clause license is retained in
`LICENSE`; this license applies to this plugin scaffold, without relicensing other
repository code or assets. Original sample actions and root/debug flags were
replaced with a setup-status panel running with normal plugin privileges.

The [script index](scripts/README.md) explains build and synchronization entrypoints.
