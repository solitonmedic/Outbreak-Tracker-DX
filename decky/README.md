# Outbreak Tracker for Decky

Outbreak Tracker for Decky lets you monitor your Resident Evil Outbreak sessions from your phone while playing on the Steam Deck.

The plugin reads game data through PCSX2's PINE interface and displays the existing Outbreak Tracker UI in your browser, complete with its original sprites, fonts, player cards, maps, puzzle hints and SP radar.

## Installation

1. Download the plugin ZIP from the GitHub Actions **Build Decky plugin** workflow or build it yourself.
2. Open Decky settings on your Steam Deck.
3. Enable Developer mode.
4. Select **Install Plugin from ZIP File** and locate the ZIP.
5. Open Outbreak Tracker from the Decky menu.
6. Launch PCSX2 with PINE enabled and start a supported game.
7. Scan the QR code with your phone.

Your phone and Steam Deck must be on the same network. You can also open the tracker directly at:

`http://<deck address>:28080/`

No account or access token is required. The address remains the same across restarts unless the Deck's IP address changes.

## Using the tracker

The tracker fills your browser window without scrolling. Vertical mode works best on phones, while horizontal mode remains available for wider displays.

Tap the screen or move your pointer to reveal the **CONTROLS** button. It disappears after three seconds of inactivity or when the pointer leaves the page.

The controls menu uses the same options as the desktop tracker:

- Views
- Show
- Sound
- Layout
- Map
- Players shown
- Enemy list

Touch controls mirror the desktop keyboard shortcuts. All connected devices share the same tracker view and settings.

Connection status appears at the top of the screen whenever live game data is unavailable.

## Map views

Open Controls and select **Map + compact cards** or **Cards beside map**. Keyboard users can press `N` or `B`.

Maps are included for the five main scenarios of each Japanese release of File 1 and File 2. U.S. File 1 uses the same maps as the Japanese release.

Maps load automatically. No game discs, external downloads, imports or additional setup are required.

### Navigation

- Drag to move around the map.
- Pinch, scroll or double-tap to zoom.
- Select a floor from the floor selector.
- Tap a player card, portrait or legend entry to follow that player.
- Press `F` to follow a player using the keyboard.

The Controls button remains visible while viewing the map. Floor selectors support swiping and scrolling when additional floors are available.

### Reading the map

Floors use artwork from Evil Resource where available, with blue walls and yellow doors. Other floors use room outlines traced from the game's layout.

| Indicator | Meaning |
|---|---|
| Red room | Your current room |
| Light blue room | Room occupied by another player |
| Pulsing yellow room | Gas-filled room in Desperate Times |
| Player chevron | Player position and facing direction |
| Ringed portrait | Player's room is known, but precise placement is unavailable |
| White diamond | Enemy and its remaining HP percentage |
| Item icon | Item in your current room |
| YOU | Your local player |

Player colors correspond to their respective slots:

- P1: Red
- P2: Blue
- P3: Yellow
- P4: Green

The legend displays each player's in-game name. Puzzle hints, medals, passwords and scenario timers remain visible.

Height tracking is not yet supported. Rooms with ambiguous height ranges require manual floor selection.

Extra File 2 scenarios are not currently supported.

### Layout dimensions

| Layout | Dimensions |
|---|---|
| Wide | 760 × 740 |
| Desktop vertical | 300 × 740 |
| Phone | 390 × 844 |

## SP counter and radar

The SP radar displays the direction of an SP item relative to your character.

When the radar first detects an SP item after entering a room, it plays an alert. The alert will not repeat until you change rooms.

To mute the alert, select **SP RADAR SOUND: ON/OFF** in Controls or press `M`.

The alert is enabled by default whenever the reader starts. Changing this setting affects every connected device. The radar continues working while muted, and missed alerts will not replay when sound is restored.

### Sound on mobile devices

Browsers require a tap or key press before they can play audio. Opening the Controls menu satisfies this requirement.

On iPhones:

- Silent mode also mutes radar alerts.
- Returning from the lock screen or another app may require another tap to restore audio.

The SP counter and radar remain hidden whenever valid tracking data is unavailable.

## Add to your home screen

Outbreak Tracker can run as a standalone home-screen web app.

In Safari on your iPhone:

1. Open the tracker.
2. Tap Share.
3. Select Add to Home Screen.

The tracker opens without Safari's address bar or navigation toolbar and uses the Outbreak Tracker HD icon.

The web app requires an active connection to your Steam Deck. Offline mode and service workers are unavailable because the tracker uses a local HTTP connection.

If your Deck's IP address changes, add the tracker to your home screen again. Setting a DHCP reservation on your router can prevent this.

## Reader behavior

The plugin starts a read-only PCSX2 PINE reader and polls game data five times per second.

The reader starts when the first device requests data and stops 15 seconds after the last device disconnects. PCSX2 receives no PINE traffic while the reader is idle.

The service marks delayed data as stale and attempts to reconnect if the reader becomes unavailable.

PINE supports only one client at a time. Before opening another tracker or recorder, select **Stop phone view and reader** in Decky.

No RAM snapshots, frame files or game data are saved.

## Network access and security

The phone view runs on TCP port `28080`.

The service accepts connections from private, link-local, loopback and Tailscale addresses. Requests must address the Deck using an IP address, single-label hostname or `.local` hostname to prevent DNS rebinding.

Browser controls require same-origin JSON requests. The service exposes packaged web files, artwork and the tracker endpoints without providing direct access to raw game memory.

Anyone on your local network can open the tracker and change its shared view.

The plugin does not modify firewall or router settings. **Do not forward port 28080 to the internet.**

## Building from source

The plugin source is located in `decky/`.

The native reader targets Linux x86_64. You can build the plugin on a Steam Deck, another x86_64 Linux machine or through GitHub Actions.

### Prerequisites

- Git
- Python 3
- Internet access
- Node.js 24.19.0 with Corepack
- pnpm 9.15.9

Install Node.js through nvm at:

`~/.nvm/versions/node/v24.19.0/`

The build script calls this Node installation directly, so loading an interactive nvm shell profile is unnecessary.

Corepack downloads the pinned pnpm version automatically. The native toolchain uses a user-local micromamba environment containing GCC, CMake and Pillow, with versions pinned in `native-toolchain.lock`.

No system package installation is required.

At runtime, the plugin uses the Steam Deck's existing `/usr/bin/luajit`.

### Local build

Run the following commands from the repository root:

```sh
python3 decky/scripts/bootstrap_native.py
python3 decky/scripts/build.py --expect-commit "$(git rev-parse HEAD)"
```

Only run `bootstrap_native.py` once per machine.

The build requires a clean Git checkout at the specified commit. It:

- Uses the committed pnpm lockfile.
- Checks TypeScript and builds the frontend.
- Compiles the native Linux reader using pinned PINE sources.
- Generates font metrics.
- Checks Python syntax.
- Verifies the plugin ZIP contents.

Building does not require a running PCSX2 instance or perform live PINE reads.

### Build output

Files are written to `decky/.artifacts/`:

- `outbreak-tracker-<version>-<commit>.zip`
- `build-report.json`

The build report records the commit, tool versions and SHA-256 checksum.

The ZIP contains an `outbreak-tracker/` directory with the native reader, shared Lua UI, original assets, browser frontend, backend, package metadata, licenses and `build-info.json`.

Git ignores generated build files and dependencies. Keep previous ZIPs if you need to roll back.

The output directory is hidden. Enable hidden files when browsing for the ZIP in Decky or copy it to another directory.

The build process never writes to Decky's root-owned installed-plugin directory or restarts the loader.

### GitHub Actions

Run the **Build Decky plugin** workflow:

`.github/workflows/build-decky.yml`

The workflow publishes an artifact named `Outbreak-Tracker-Decky-Plugin`.

GitHub packages the `outbreak-tracker/` directory directly, so the downloaded artifact is already an installable ZIP.

When `GITHUB_ACTIONS=true`, the build uses the Node installation provided by `actions/setup-node` on `PATH`.

## Updating and troubleshooting

To update the plugin, install the new ZIP and reopen the Decky panel. Use Decky's Developer reload option if available.

The plugin panel displays its version and Git commit so you can confirm which revision is running.

### PCSX2 connection

The native reader connects to:

`/run/user/1000/pcsx2.sock`

The default PINE slot is `28011`.

If the tracker remains in a waiting state, verify that PCSX2 is running, PINE is enabled, a supported game is loaded and another PINE client is not connected.

Enabling PINE alone does not confirm a successful connection. Waiting, error, stale and live states are reported separately.

Existing U.S. release mapping and puzzle limitations still apply.

### Logs

View logs through Decky or inspect:

`/home/deck/homebrew/logs/Outbreak Tracker/`

The backend uses Decky's logger. Log filenames depend on the installed loader version.

### Rollback and removal

To roll back, install a previous plugin ZIP and verify its displayed commit.

To remove the plugin, use Decky's uninstall option. Unloading or uninstalling stops both the reader and HTTP service.

Development tools and previously built ZIPs remain in their original directories.

## Implementation

The Decky plugin uses the existing Outbreak Tracker Lua interface rather than maintaining a separate browser UI.

`reader.lua` runs `sources/main.lua` and its card modules through a small LÖVE graphics adapter. Drawing commands and typed game status travel through a private child-process pipe.

`web/app.js` renders those commands on a high-resolution Canvas using the original textures, fonts and image-font separators.

Phone browser and desktop visual parity still requires testing against a running game.

Native compilation reuses `linux/CMakeLists.txt` and the existing source patcher.

The bridge does not expose raw RAM, duplicate memory-address maps or execute browser-supplied code.

### SP radar implementation

The drawing bridge supports ellipses, polygons, rotation and line widths for the shared SP counter and radar.

Penpot generates the component layout in `sources/layout.lua`. The component uses the existing password-hint font.

`sources/SPTracking.lua` draws the counter and player-relative compass using validated room records from `sources/SPMapReader.h`.

When the radar detects an SP item, it plays `assets/sp-found.wav`. The reader sends sound play counts with each frame, allowing connected browsers to play new alerts without repeating previous ones.

### HTTP endpoints

| Endpoint | Purpose |
|---|---|
| `GET /api/frame` | Retrieve tracker frames and status |
| `POST /api/key` | Submit an allowed tracker keyboard command |

Decky exposes `get_status` and `set_running` for reader status, service controls and the phone link.

### Web app assets

The web app includes a manifest, Apple touch icon and standalone display metadata.

Its icons are stored in `web/icons/` and generated from:

`sources/outbreak-tracker-icon-hd.png`

The browser skips hidden-toolbar margin adjustments when running as a standalone home-screen app.

## License and credits

The plugin scaffold is adapted from the [Steam Deck Homebrew Decky plugin template](https://github.com/SteamDeckHomebrew/decky-plugin-template/tree/90d0780e882a17f5714fc6de044c645f22608290).

The frontend entry point, Decky API integration, Rollup configuration, Python lifecycle and package structure follow that template.

The original sample actions and root/debug flags have been replaced with a setup and status panel running under normal plugin privileges.

The scaffold retains its BSD 3-Clause license in `LICENSE`. This license does not replace the licenses of other repository code or assets.

Map artwork is provided by Evil Resource where available.

See the [script index](scripts/README.md) for build and synchronization scripts.
