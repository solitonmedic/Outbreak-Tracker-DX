# Outbreak Tracker for Decky

The plugin starts a read-only PCSX2 PINE reader and serves a phone view on
LAN port 28080. Scan the QR code in Decky or open its link on another device
on the same network. The page draws the original shared Lua tracker UI with its
existing sprite atlases, fonts, card logic, release limits and keyboard controls.
Touch buttons mirror those controls; every connected device shares one view.

The page has no header: the tracker is scaled to fit the visible screen (width and
height, no scrolling) on a high-resolution canvas. A round button at the bottom
right opens a sheet of controls grouped as Views, Show, Layout, Players shown and
Enemy list shows; status text appears on top only when not live. Vertical mode
suits phones; horizontal mode remains available. The reader polls at five updates per second, but only while a device
has the page open: it starts on the first request and stops 15 seconds after the last,
so PCSX2 gets no PINE traffic otherwise (the panel then shows the reader as idle). The
service marks delayed data stale and retries a lost reader. No RAM snapshots or frame files are
saved. PINE supports a single client: stop this reader before using another tracker
or a recorder. Use **Stop phone view and reader** in Decky to release it.

## Source and prerequisites

The plugin lives in this repository's `decky/` folder. Its native reader is built for
Linux x86_64, so build it on the Steam Deck, on another x86_64 Linux machine, or with
the manual GitHub workflow `.github/workflows/build-decky.yml` (`Build Decky plugin`),
which uploads the ZIP as the `Outbreak-Tracker-Decky-Plugin` artifact.

A local build needs Git, Python 3, internet access and Node **24.19.0** with Corepack,
installed with nvm at `~/.nvm/versions/node/v24.19.0/`. `build.py` calls that Node
directly, so an interactive shell or an nvm shell profile is not required. Corepack
downloads pinned **pnpm 9.15.9** into a user cache. The native build uses a user-only
micromamba GCC/CMake/Pillow environment made by `bootstrap_native.py` from the pinned
`native-toolchain.lock`. No system package installation is required. At runtime the
plugin uses the Deck's existing `/usr/bin/luajit`.

## Build

Run from the repository root:

```sh
python3 decky/scripts/bootstrap_native.py   # once per machine
python3 decky/scripts/build.py --expect-commit "$(git rev-parse HEAD)"
```

The build needs a clean checkout at the commit you pass. It uses the committed pnpm
lockfile, checks TypeScript, builds the frontend, compiles the existing Linux native
reader with pinned PINE sources, generates font metrics, parses Python, and verifies
the ZIP contents. No live PINE reads occur.

Outputs go to `decky/.artifacts/`: the ZIP `outbreak-tracker-<version>-<commit>.zip`
and `build-report.json` with the commit, tool versions and SHA-256. The ZIP contains an
`outbreak-tracker/` directory with the native reader, shared Lua UI, original assets,
browser frontend, backend, package metadata, licenses and `build-info.json`. Build
output and dependencies are ignored by Git. Keep older ZIPs to roll back.

In GitHub Actions, `build.py` uses the Node on `PATH` (from `actions/setup-node`)
because `GITHUB_ACTIONS=true`.

## Install, refresh, inspect and roll back

On the Deck, open Decky settings, enable Developer mode, and use **Install Plugin
from ZIP File** to browse to the ZIP (the build folder `decky/.artifacts/` is hidden,
so show hidden files or copy the ZIP somewhere else first). The build never writes
into the root-owned installed plugin directory or restarts the loader.

Open **Outbreak Tracker** from the Decky menu, check its version and commit, then
scan the QR code on your phone. There is no login and no token: the link is just
`http://<deck address>:28080/` and stays the same across restarts.

The service listens on port 28080 and exposes only packaged web/artwork files plus
the frame and control endpoints. It answers only clients on private, link-local,
loopback or Tailscale addresses, and only for requests addressed to an IP, a
single-label or a `.local` host name (this blocks DNS rebinding). Controls are
accepted only as same-origin JSON requests from the tracker page, so other websites
cannot press keys. Anyone on your local network can open the page and change the
shared view; they cannot read game memory or do anything else. It adds no firewall
or router rules; do not forward port 28080 from your router.

**Home-screen app (PWA).** The page has a web app manifest, an Apple touch icon and
standalone meta tags using the Outbreak Tracker HD icon. On iPhone Safari use Share →
Add to Home Screen; it then opens full screen without Safari's bars (the margin logic
for the hidden-toolbar case is skipped in that mode). The Deck's address is plain
`http://`, so browsers do not offer a service worker or offline mode; the app needs
the Deck and the phone view running. If your router changes the Deck's address, add
the app again (a DHCP reservation for the Deck avoids this). The icons are committed PNGs under
`web/icons/`, made from `sources/outbreak-tracker-icon-hd.png`.

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

New endpoints: `GET /api/frame` and `POST /api/key` with a whitelisted
key, both restricted as described above. Decky methods `get_status` and `set_running`
expose lifecycle state and the phone link. Waiting/error/stale states are distinct from live. Browser and native
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
