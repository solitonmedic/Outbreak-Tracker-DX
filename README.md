# Outbreak Status Tracker DX

Outbreak Status Tracker is a companion window for *Resident Evil Outbreak* series in PCSX2. It reads the game's memory and shows character health, infection and status, inventory, nearby items, enemies, doors, timers, puzzle hints and online room information. It does not change the game.

## Game support

- Japanese File 1 and File 2 are supported.
- U.S. File 1 support is still in progress. The current mappings were developed with the Ver2.162 community update installed; stock U.S. v2.00 has not been checked. Player 1 gameplay has been compared with the game in Outbreak. Multiplayer and some lobby information still need testing.
- U.S. File 2 has not been mapped yet.

On U.S. File 1, the tracker cannot show the current number of players in your room, the room's player cards, or the room master indicator. The Room List works, but entries for other players' occupied rooms still need checking. Puzzle hints for The Hive and Below Freezing Point are hidden because Ver2.162 changes those puzzles. Decisions, Decisions codes were checked in game; the Hellfire hint still needs a live check. The tracker only reads what PCSX2 has loaded into memory, so it cannot query the server for information outside the game.

The tracker selects English scenario art and portraits for U.S. File 1. Japanese File 1 and File 2 keep the original atlas.

## Run it

Download the artifact for your platform from a successful [Build all platforms run](https://github.com/solitonmedic/Outbreak-Tracker-DX/actions/workflows/build-all.yml), or [build it from source](BUILDING.md). GitHub wraps each artifact in a ZIP, so extract that ZIP first.

| Platform | Launch | PCSX2 connection |
|---|---|---|
| Windows x64 | Keep the extracted distribution files together and open `OutbreakTracker.exe`. | The tracker reads the PCSX2 process directly. |
| macOS, Apple Silicon or Intel | Open `Outbreak Status Tracker.app`. | Enable PINE in PCSX2 on TCP port `28011`. |
| Linux x86_64 | Make `OutbreakStatusTracker-x86_64.AppImage` executable and run it. | Enable PINE in PCSX2. The tracker uses `pcsx2.sock` in your runtime directory. |

Start PCSX2 and load a supported game before opening the tracker. On macOS and Linux, PCSX2 and the tracker must be able to reach the same PINE endpoint. Windows does not use PINE.

Press **F1** in the tracker for its full key list. **F2** cycles the item views, **F3** changes the room shown in the room list, **F4** toggles the enemy view, **I** shows items in the current room, **T** toggles timers, **Q** toggles puzzle hints, and **Esc** quits.

## Phone view on a Steam Deck

The Decky plugin runs the tracker on a Steam Deck and shows it in a browser on your phone, so the tracker can sit on a second screen while you play in PCSX2 on the Deck. It runs the same Lua UI, fonts and sprite atlases as the desktop tracker and draws them on a canvas in the browser, so the cards, views and controls match. It reads through PINE and never writes to the game.

You need Decky Loader on the Deck, PCSX2 with PINE enabled (the default slot is `28011`), and a phone, tablet or computer on the same network. The plugin is not in the Decky store. Download the ZIP from the [Build Decky plugin workflow](https://github.com/solitonmedic/Outbreak-Tracker-DX/actions/workflows/build-decky.yml) (extract GitHub's wrapper ZIP first), or [build it yourself](BUILDING.md#steam-deck-decky-plugin). Then open Decky's settings, turn on Developer mode and choose **Install Plugin from ZIP File**.

Open **Outbreak Tracker** in the Decky menu. The panel shows a QR code and the address, `http://<Deck address>:28080/`. Scan it or type it into a browser. The page says it is waiting for a game until PCSX2 has a supported one loaded. Tap the tracker to open the controls: views, room, players shown, timers, puzzle hints, enemy list, size and layout. Every connected device shares one view. The plugin reads from PCSX2 only while a device has the page open and pauses 15 seconds after the last one closes it. The panel's **Stop phone view and reader** button releases the connection to PCSX2 entirely.

On an iPhone, use Share, then Add to Home Screen, to run it full screen with the Outbreak Tracker icon. There is no offline mode, so the Deck, PCSX2 and the plugin all have to be running. If your router gives the Deck a new address, add the app again. A DHCP reservation for the Deck avoids that.

There is no login. The plugin answers only devices on private, link-local or Tailscale addresses, but anyone on your Wi-Fi can open the page and change the shared view. They cannot read game memory. Do not forward port `28080` on your router. PINE accepts one client, so stop the phone view before you run the desktop tracker or the recorder against the same PCSX2.

The plugin uses the same reader and address profiles as the desktop tracker, so [game support](#game-support) is the same. So far it has been tested only with U.S. File 1 on one Steam Deck and an iPhone in Safari. Other phones, other browsers and the Japanese releases through the plugin have not been tried, and the phone's values have not been checked against the game screen the way player 1 gameplay was on desktop.

## Credits

The original [OutbreakTracker](https://github.com/madgamer98/OutbreakTracker) credits Fothsid, killme, phoe-nix and madgamer98. This repository brings the tracker to Windows, macOS and Linux.

The U.S. File 1 UI atlas was shared by Jeferes_Soares in the *Outbreak Status Tracker for File 1 US* package.

The Decky plugin started from Steam Deck Homebrew's [decky-plugin-template](https://github.com/SteamDeckHomebrew/decky-plugin-template) under its BSD 3-Clause license. Its home-screen icon is the Outbreak Tracker HD icon.
