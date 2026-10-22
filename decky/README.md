# Outbreak Tracker for Decky

This is the development foundation for a Decky Loader plugin. It currently shows
setup status, package version, source commit, PCSX2 AppImage presence and the PINE
configuration setting. Refresh reads that status again. Live tracker data and the
responsive phone view are the next milestone. An enabled setting does not prove
that PINE is reachable or that a game is running.

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
installation needs internet access. No system package installation is required.
The Mac driver needs Python 3, Git, SSH and SCP, using the existing `steamdeck` alias.

## Commit, synchronize, build, retrieve

Run every command below from the repository root (`repo-merged/` in the workspace).

```sh
python3 decky/scripts/deck.py doctor
git add decky
git commit -m "Describe the plugin change"
python3 decky/scripts/deck.py sync
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
parses the Python backend and verifies ZIP contents. It requires a clean Deck
checkout at exactly the Mac's commit. No live PINE reads occur.

Deck outputs are under `decky/.artifacts/` inside its checkout. Fetch copies the
ZIP and `build-report.json` to the Mac's `decky/.artifacts/`, verifying source
commit, version and SHA-256. The ZIP contains an `outbreak-tracker/` directory
with frontend, backend, package metadata, README, license and `build-info.json`.
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

Open **Outbreak Tracker** from the Decky menu. Check the displayed version and
commit against the build report, then press Refresh. The status should say live
tracker data and the phone view are pending. This foundation opens no HTTP listener
and does not connect to PINE or modify PCSX2 settings.

For another revision, install its ZIP again and reopen the plugin panel. Use
Decky's Developer reload control if available. Inspect Decky's logs view or the
plugin log under `/home/deck/homebrew/logs/Outbreak Tracker/`. The backend uses
Decky's logger; exact filenames follow the installed loader version. To remove
the plugin, use Decky's installed-plugin uninstall control. To roll back, install
the prior ZIP and compare its displayed commit. No plugin-specific persistent
settings or background processes are created by this foundation.

## Next milestone

Expose structured data from the existing shared reader and Linux PINE transport,
then build a responsive browser tracker that retains the desktop tracker's cards,
views, localized assets and controls. Define the LAN service lifecycle and access
model as part of that change. Preserve existing release support limits and keep
build, offline checks, user-run and in-game verification distinct.

## Template provenance and license

Adapted from Steam Deck Homebrew's [Decky plugin template at
90d0780e882a17f5714fc6de044c645f22608290](https://github.com/SteamDeckHomebrew/decky-plugin-template/tree/90d0780e882a17f5714fc6de044c645f22608290).
The frontend entry point, Decky API/UI integration, Rollup setup, Python lifecycle
and package layout follow that template. Its BSD 3-Clause license is retained in
`LICENSE`; this license applies to this plugin scaffold, without relicensing other
repository code or assets. Original sample actions and root/debug flags were
replaced with a setup-status panel running with normal plugin privileges.

The [script index](scripts/README.md) explains build and synchronization entrypoints.
