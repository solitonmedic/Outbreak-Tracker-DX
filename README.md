# Outbreak Status Tracker DX


<img width="872" height="880" alt="image" src="https://github.com/user-attachments/assets/9cc3a915-ee4b-4750-bec3-59fcdd78e6e0" />


> [!WARNING]
> **Restrictions on code reuse**
>
> Outbreak Status Tracker DX is developed for the Resident Evil Outbreak community, particularly OBSRV and other fan servers dedicated to preserving the original games.
>
> I do not grant permission for webslop projects such as Outbreak.web, browser-based recompilations, or similar projects to incorporate, redistribute, adapt or claim any of my original code, research or mapping work as their own.
>
> This project exists to support the original Outbreak games and their fan-server communities. Please respect that.

Outbreak Status Tracker DX is a companion application for *Resident Evil Outbreak* and *Resident Evil Outbreak File #2* on PCSX2, based on the original OutbreakTracker.

DX expands upon the original tracker with support for Windows, macOS, Linux and Steam Deck, SP item tracking, and an interactive mapping system that lets you see where your teammates, enemies and items are in real time.

The tracker only reads game memory. It does not modify the game.

[Downloads](https://github.com/solitonmedic/Outbreak-Tracker-DX/releases) | [Development Builds](https://github.com/solitonmedic/Outbreak-Tracker-DX/actions/workflows/build-all.yml) | [Report an Issue](https://github.com/solitonmedic/Outbreak-Tracker-DX/issues)

## Features

### Live Mapping

All ten main scenarios across File #1 and File #2 have interactive maps.

You can follow your teammates as they move through the scenario, check which rooms you've already visited, keep track of enemies and find your way back to items you've left behind.

- Live player positions and facing directions.
- Player following, floor switching, zooming and panning.
- Enemy positions and HP percentages.
- Item, key item and SP item locations.
- Previously discovered items remain on the map throughout the run.
- Flashing indicators for teammates in Danger or Down.
- Gas room indicators for Desperate Times.
- A navigation guide through Flashback's forest maze.

Maps use the game's original map layouts alongside artwork from Evil Resource, where available. They load automatically.

#### Reading the map

| Room color | Meaning |
| --- | --- |
| Red | Your current room |
| Light blue | Rooms occupied by teammates |
| Green | Previously visited rooms |
| Yellow (pulsing) | Rooms affected by gas |

Players are color-coded by their respective slots: P1 (red), P2 (blue), P3 (yellow) and P4 (green).

Regular enemies appear as white diamonds, bosses as red diamonds and SP items as green diamonds. Hover or tap an item to see its name.

### Elimination & Showdown

Since Elimination and Showdown don't have maps of their own in-game, I've added dedicated maps for these modes as well.

There are two ways to view them:

- **Room View:** Shows the current room, including players, enemies and items.
- **Grid View:** Shows the entire scenario, room connections and remaining enemy counts.

### Player Information

- HP and health condition.
- Virus infection percentage.
- Power and antivirus meters.
- Current room.
- Inventory and equipped items.
- Character-specific inventories, such as Yoko's backpack and Cindy's herb case.
- Animated Danger and Down indicators.
- Alyssa's lock-picking hints and real-time UNLOCK progress bar.

### Enemies, Items & Doors

The original tracker views are still available alongside the new maps.

- Enemy lists and HP readings.
- Enemy filtering by player.
- Room item lists and item set information.
- Door HP and durability.

### SP Item Tracking

For those working on collecting every SP item, the tracker now has a dedicated SP counter and radar.

The radar points toward the nearest SP item for your character and changes color when you're close enough to pick it up. An optional sound plays when the radar detects an SP item after entering a room.

File #1 also displays the current SP item set (A or B).

SP tracking is disabled in Elimination and Showdown.

### Puzzle Hints & Timers

View passwords, puzzle hints, scenario timers and elapsed play time. Puzzle hints turn green when the corresponding clue has been learned in-game.

Available hints depend on the scenario and game version.

### Online Room Information

- Online room listings.
- Scenario and difficulty.
- Room countdowns and player capacity.
- Current player counts where supported.
- Host information and room-master indicators.

The tracker can only read information that the game has loaded into memory. It does not communicate directly with the server.

## Game Support

| Game | Region | Support |
| --- | --- | --- |
| Resident Evil Outbreak | Japan | Supported |
| Resident Evil Outbreak File #2 | Japan | Supported |
| Resident Evil Outbreak | USA | Partial support |
| Resident Evil Outbreak File #2 | USA | Not yet supported |

U.S. File #1 support was developed using the Ver2.162 community update. Stock U.S. v2.00 has not been tested.

Player information, maps, inventories, SP tracking, room listings and several puzzle hints are available in the U.S. release. The Hive's updated puzzle codes are now read directly from memory.

Some multiplayer information still needs testing, and certain puzzle hints remain unavailable due to changes made in Ver2.162.

The tracker automatically uses the English interface artwork for U.S. File #1. Japanese File #1 and File #2 retain the original artwork.

## Installation

Download the package for your platform from [GitHub Releases](https://github.com/solitonmedic/Outbreak-Tracker-DX/releases).

If you want to try a newer build, download an artifact from a successful [Build all platforms](https://github.com/solitonmedic/Outbreak-Tracker-DX/actions/workflows/build-all.yml) workflow instead.

GitHub wraps workflow artifacts in ZIP archives, so extract them first.

| Platform | Application | PCSX2 connection |
| --- | --- | --- |
| Windows (x64) | `OutbreakTracker.exe` | Direct memory reading |
| macOS (Apple Silicon / Intel) | `Outbreak Status Tracker.app` | PINE, TCP port `28011` |
| Linux (x86_64) | `OutbreakStatusTracker-x86_64.AppImage` | PINE, `pcsx2.sock` |

Windows users should keep all extracted files together. Linux users must make the AppImage executable before running it.

### Configuring PCSX2

macOS, Linux and Steam Deck users must enable PINE in PCSX2 before running the tracker.

- Enable **Tools → Show Advanced Settings** if necessary.
- Navigate to **Settings → Advanced → PINE Settings**.
- Enable PINE and set the slot to `28011`.

Windows users do not need to enable PINE.

### Opening the tracker on macOS

macOS may block the tracker upon first launch because the application has not been notarized by Apple.

If this happens:

1. Attempt to open `Outbreak Status Tracker.app`.
2. Open **System Settings → Privacy & Security**.
3. Scroll down and select **Open Anyway**.
4. Authenticate and confirm.

Alternatively, just use the following command on `Terminal.app`.

`xattr -dr com.apple.quarantine "/Applications/Outbreak Status Tracker.app"`

You should only need to do this once per downloaded build.

Only download the tracker from this repository or its official GitHub releases.

## Steam Deck & Mobile

DX is also available as a Decky Loader plugin.

If you're playing Outbreak on your Steam Deck, you can keep the tracker open on your phone, tablet or computer instead of taking up space on the game's screen.

### Installing the Decky plugin

1. Install Decky Loader on your Steam Deck.
2. Download the plugin from the [Build Decky plugin](https://github.com/solitonmedic/Outbreak-Tracker-DX/actions/workflows/build-decky.yml) workflow.
3. Enable Developer mode in Decky's settings.
4. Select **Install Plugin from ZIP File** and install the plugin ZIP.
5. Enable PINE in PCSX2 and launch Outbreak.
6. Open Outbreak Tracker from the Decky menu.
7. Scan the QR code with your phone.

Both devices must be on the same network.

The mobile view includes touch controls, pinch-to-zoom, vertical and horizontal layouts, and SP radar audio notifications.

iPhone and iPad users can also install the tracker to their home screen through Safari's **Add to Home Screen** option.

The plugin only reads game memory while a connected device is viewing the tracker. All connected devices share the same tracker view.

The service uses port `28080` and does not require a login. Please do not expose this port to the public internet.

See the [Decky documentation](decky/README.md) for more information.

## Controls

Click or tap **CONTROLS** to open the tracker's menu. Keyboard shortcuts are also available.

| Key | Function |
| --- | --- |
| Tab | Open or close the controls menu |
| F1 | Help |
| F2 | Cycle item views |
| F3 | Switch rooms in the item view |
| F4 | Toggle enemy list |
| N | Map with compact player cards |
| B | Player cards beside map |
| F | Follow player |
| I | Toggle room items |
| E | Cycle enemy HP display |
| T | Toggle timers |
| Q | Toggle puzzle hints |
| M | Toggle SP radar sound |
| V | Vertical layout |
| H | Horizontal layout |
| L | Switch language |
| Esc | Close menu or quit |

### Map controls

- Click or tap a player's card or name to follow them.
- Drag to move around the map.
- Scroll or pinch to zoom.
- Select a floor or area to switch maps.
- Use Room View or Grid View in Elimination and Showdown.

SP radar sound is enabled at the start of each session. Muting it does not disable the radar itself.

## Known Issues & Limitations

- U.S. File #1 support is still incomplete.
- U.S. File #2 has not been mapped yet.
- Stock U.S. v2.00 has not been tested.
- Some player positions can only be displayed at room level.
- Some Elimination and Showdown map details need further gameplay testing.
- Nightmare and Infinity detection are not yet confirmed.
- PINE only supports one client at a time.

If you encounter incorrect readings, misplaced map markers or anything else that doesn't seem right, please [let me know](https://github.com/solitonmedic/Outbreak-Tracker-DX/issues).

Include your game region, scenario, difficulty, platform and tracker version when reporting an issue.

## Building from Source

See [BUILDING.md](BUILDING.md) for instructions on building the tracker yourself.

Additional documentation:

- [Windows](windows/README.md)
- [Linux](linux/README.md)
- [Steam Deck / Decky](decky/README.md)

## Credits

DX is based on the original [OutbreakTracker](https://github.com/madgamer98/OutbreakTracker), which credits Fothsid, killme, phoe-nix and madgamer98.

Additional thanks to:

- Jeferes_Soares for sharing the U.S. File #1 interface atlas.
- [Evil Resource](https://www.evilresource.com) for scenario map artwork.
- Steam Deck Homebrew for the [Decky plugin template](https://github.com/SteamDeckHomebrew/decky-plugin-template), distributed under the BSD 3-Clause license.

Resident Evil Outbreak, its characters and original game artwork belong to Capcom. This is an unofficial fan project and is not affiliated with Capcom.

Happy surviving!
made with lots of love by an orange cat 🏳️‍🌈🐈
