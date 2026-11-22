# Windows build notes

The Windows native module reads PCSX2 process memory directly. It does not require PINE.

U.S. host rooms show the selected room's player count when its lobby data is
available. Hive puzzle hints read the current updated-game codes and hide while
the loaded code tables are unavailable; leading zeros are preserved.
In-game room-master crowns use the loaded U.S. authority table. Unavailable or
changing data suppresses the crown; a gameplay-screen comparison is pending.

## Requirements

- Windows 10 or newer.
- Visual Studio 2022 with the Desktop development with C++ workload (v143 toolset).
- Git and PowerShell.
- The official LÖVE 11.5 x64 ZIP runtime for packaging.
- The official [rcedit v2.0.0 x64 executable](https://github.com/electron/rcedit/releases/tag/v2.0.0), used to embed the tracker icon in the launcher before it is fused with the game archive.

## Build

From the repository root, build LuaJIT and the tracker DLL:

```powershell
git clone --depth 1 --branch v2.1 https://github.com/LuaJIT/LuaJIT.git windows/luajit
```

Open an x64 Visual Studio Developer Command Prompt, then run:

```bat
cd windows\luajit\src
msvcbuild.bat
mkdir "..\..\Outbreak Tracker\lib\x64"
copy lua51.lib "..\..\Outbreak Tracker\lib\x64\lua51.lib"
cd ..\..\..
msbuild "windows\Outbreak Tracker.sln" /m /p:Configuration=Release /p:Platform=x64
```

Download and extract [`love-11.5-win64.zip`](https://github.com/love2d/love/releases/tag/11.5), then package the shared UI, native reader, LÖVE runtime, and fused executable:

```powershell
$resourceEditor = 'C:\path\to\rcedit-x64.exe'
./windows/package.ps1 -LoveRuntimeDirectory 'C:\path\to\love-11.5-win64' -ResourceEditorPath $resourceEditor
```

The package is `windows/build/OutbreakTracker-Windows-x64.zip`. Extract it and launch `OutbreakTracker.exe`; LÖVE does not need to be separately installed. The ZIP contains the fused game executable, the native reader DLL, LÖVE's runtime DLLs, and LÖVE's license. The executable needs those adjacent runtime DLLs, so distribute the ZIP contents together.

The Windows Actions workflow is manual-only. It downloads the official LÖVE 11.5 x64 runtime, builds the distribution directory, checks the executable and required runtime files, then uploads that directory as an artifact. After downloading the artifact from GitHub, extract it once to get the Windows distribution files.

## PCSX2

Start PCSX2 with a supported game before launching the tracker. Japanese File 1 and File 2 are supported; U.S. File 1 support is partial. The Windows reader locates the PCSX2 process and reads its emulated EE memory directly. See the [project README](../README.md) for current limits.

The Windows package includes both UI atlases and selects the English one when U.S. File 1 is detected.

## Map views

Press **B** for the map beside the player cards, **N** for the map above compact
cards, and **F** to follow the selected player again. **V** returns to the normal
card view. Drag to pan, scroll to zoom, use Fit to see the floor, and use the floor
row to select another floor. Clicking a player follows that player. Manual pan
or floor selection stops follow.

Maps for the five main scenarios of Japanese File 1 and File 2 are built into the
application (the File 1 maps also serve the U.S. release). They load automatically;
there is no disc selection, import, download or user-cache setup step, and no game
files are needed.

Fitted floors use Evil Resource artwork with blue walls, yellow doors and room
tints. Your room is red; other occupied rooms use a lighter blue. Gas rooms
pulse with a yellow glow. Floors without Evil Resource artwork show their rooms as
dark shapes with blue outlines, traced from the game's room layout.

Players use red, blue, yellow and green by slot; YOU identifies the local gameplay
record. A dot marks a usable position. A portrait in a ring marks only the room,
including rooms spanning multiple height bands. Select the desired floor manually
in those cases. Player chevrons turn with each character's facing; height selects the matching floor band. YOU is the game's own local player. Desperate Times
highlights the current gas rooms in yellow. Existing puzzle hints and timers stay
visible. Enemies in play show as small white diamonds with their HP percentage,
and the items in your current room show as tracker item icons.
U.S. File 1 uses the same maps as the Japanese release; extra File 2 scenarios
are not enabled.


### Development map presentation (2026-11-20)

B/N map views show enabled remote players, keep the follow zoom across floors,
and use the actor height for rooms spanning multiple floors. YOU's room is red,
other occupied rooms light blue, previously visited rooms light green, and DT gas
rooms glow yellow. Only YOU's entries count as visits. Room-item observations and
SP markers are remembered in memory until the run resets; known scenario items
are orange until taken, personal SP markers blue, other SP markers green. Hover
or tap an item for its name. Boss markers are red. Timer, item/SP set and supported
puzzle/scenario hints remain visible on maps.

Danger cards glow red, Downed cards pulse red/black, dead portraits turn red and
voice events briefly glow green. Virus figures are larger; baseline100% power is
hidden. Timer badges and the room-master crown have separate positions. Click
CONTROLS (or right-click/Tab) for tracker-styled controls; MAIN TRACKER returns from
the map. The floor strip scrolls when more than five floor groups exist.

Shared `sources/SPMapReader.h` supplies bounded SP room records through the
existing reader connection (at most4 samples/second, supported profiles and
loaded-code guards). The private Deck provider replaces that sample and retains
its radar. Native renderer/reader source was C11/offline-checked on macOS; the
Linux debug module is built on the Deck. No macOS application, Windows MSVC build
or AppImage was produced by this presentation pass. These changes need user-run
in-game comparison; synthetic previews establish layout, not live accuracy.

Map9 follow-up: both map layouts also show the SP compass/counter beside the
clock, labelled YOU because its bearing follows the local player's facing even
when following another player. Existing provider glow is retained. Native
room-only SP data derives direction from already-exported item positions and
player facing; unavailable direction remains hidden. The row keeps a fixed
height during dropped samples. English room labels use “Drawing Room”.

Map10 presentation: the two legacy ITEM values are stacked vertically. Floor
buttons separate labels from portraits, with wider cells and scrolling when
needed. Wild Things uses GF for the outside area and Zoo for the interior,
in the map heading and floor buttons; Wild Things compact cards omit floor text. The map9 SP radar remains
beside the clock and stays relative to YOU. These UI changes add no memory reads.

Map10-r2 overlay priority: player markers, ordinary items, SP, scenario objects,
then enemy HP text. Overlapping item tooltips select the top-priority object.
Nearby floating player labels hide with separation hysteresis; cards/legend stay
identified. Ad-lib circles are smaller on markers and floor portraits.
