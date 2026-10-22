# Outbreak Status Tracker

Outbreak Status Tracker is a companion window for *Resident Evil Outbreak* in PCSX2. It reads the game's memory and shows character health, infection and status, inventory, nearby items, enemies, doors, timers, puzzle hints and online room information. It does not change the game.

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

## Credits

The original [OutbreakTracker](https://github.com/madgamer98/OutbreakTracker) credits Fothsid, killme, phoe-nix and madgamer98. This repository brings the tracker to Windows, macOS and Linux.

The U.S. File 1 UI atlas was shared by Jeferes_Soares in the *Outbreak Status Tracker for File 1 US* package.
