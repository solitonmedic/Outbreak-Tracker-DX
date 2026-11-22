# Gameplay-frame tests

These tests run each platform's built tracker against short "frames" of real
gameplay memory and compare what it reads and draws with checked expected
results. The GitHub workflows run them after every build (`dev` only: this
folder is not copied to `main`, and the workflow steps skip when it is absent).

## What is tested

For every frame, on every platform:

- **The native reader.** The whole Lua API after 40 warm-up frames: game info,
  lobby and room list, players, enemies and the enemy list, items, map items,
  doors, room masters and the SP map state.
- **The UI.** The text drawn in each view after each control: main tracker,
  help, item views, room list, language, room items, timers, puzzle hints,
  enemy HP, enemy list, SP sound, layouts and window sizes, players shown, the
  maps (map with cards, cards beside the map, follow) and the CONTROLS menu.
  The map state and the positions of the player and enemy markers are
  recorded too, and so is the CONTROLS button's fade: the wrapper ignores the
  system's pointer events and moves its own pointer (hover, leave, 3 s rest),
  so the button must be hidden until the pointer arrives, fade out after it
  leaves and be gone after 3 s without movement.
- **Facts.** Hand-checked values per frame (scenario, difficulty, character,
  room, clock) and text that must appear (for example a puzzle answer that
  was confirmed in game).
- **The shipped program itself** (`--launch-check`). The unchanged `.app`,
  AppImage or `OutbreakTracker.exe` runs for a few seconds and must stay up
  and keep reading memory.

Expected results come in three families:

- `pine` is macOS, Linux and the Decky native reader, which use the patched C++ build over PINE.
- `windows` is the C build that reads process memory.
- `decky` is the phone page's own views.

The `pine` and `windows` families read exactly the same values. Their views
differ only in the F2 item views, where the macOS/Linux build lists the items
of the current room only.

## Files

| File | What it does |
|---|---|
| `run_frames.py` | Desktop runner: lays out the shipped game files and runtime per platform, serves each frame, compares the results; also builds the test reader and the encrypted bundle |
| `decky_frames.py` | Decky runner: the plugin's native reader (against `expected/pine`) and its `reader.lua` views (against `expected/decky`) |
| `frames.py` | Frame file format, the fake PINE server, result comparison and facts |
| `automation/main.lua` | Wrapper around the platform's own `main.lua`: fixed 1/30 s steps, warm-up, one control per 3 frames, a synthetic pointer for the CONTROLS fade, JSON result |
| `automation/frames_dump.lua`, `frames_json.lua` | Reader API dump and a deterministic JSON encoder |
| `reader/` | Stand-in Windows headers: `sources/main.c` built as C (the Windows code path) into a Lua module that reads a frame file; used for the Windows family on macOS/Linux and for tracing reads |
| `fakes/fake_pcsx2.c` | Windows stand-in `pcsx2-qt.exe` exporting `EEmem`, built in the Windows workflow |
| `fixtures.tar.gz.gpg` | Encrypted frames, expected results and facts (added once reviewed) |

## Frames and their protection

Each frame holds only the bytes of one recorded checkpoint that the tracker
reads. They are made by the local tool
`tools-n-shit/research/extract-test-frames.py`, which:

1. traces every read while the UI goes through every control;
2. keeps those bytes only;
3. refuses any printable text that is not a game constant, a code guard, a
   listed numeric structure (File 2 inventories and positions) or a
   number whose bytes happen to be printable. Printable bytes inside a block
   the reader reads only to reject it (the File 2 room-crown table in
   Flashback) are blanked to zeros while the block stays rejected;
4. proves that the trimmed frame gives exactly the same results as the full
   checkpoint on both reader families.

The fixtures are encrypted with gpg (AES-256) using the passphrase in the
repository secret `TRACKER_TEST_KEY`. The workflows decrypt them into a
temporary folder. They upload only a pass/fail report, never frames or
results. Logs show only the fields that differ.

## Running locally

From `repo-merged/`:

```sh
./macos/build-app.sh
python3 tests/run_frames.py --platform mac --app "Outbreak Status Tracker.app" --fixtures ../local-tools/frame-fixtures
python3 tests/run_frames.py --platform linux-layout --app "Outbreak Status Tracker.app" --fixtures ../local-tools/frame-fixtures
python3 tests/run_frames.py --build-test-reader /tmp/test-reader.so
python3 tests/run_frames.py --platform windows-layout --app "Outbreak Status Tracker.app" --test-reader /tmp/test-reader.so --fixtures ../local-tools/frame-fixtures
python3 tests/run_frames.py --platform windows-api --test-reader /tmp/test-reader.so --fixtures ../local-tools/frame-fixtures
python3 tests/decky_frames.py --layout --reader-so "Outbreak Status Tracker.app/Contents/Resources/game/luaoutbreaktracker.so" --fixtures ../local-tools/frame-fixtures
```

`--synthetic` replaces the fixtures with two generated frames, a blank one and
a synthetic U.S. File 1 one. Add `--no-expected` for a check of errors and
facts only.

`windows-api` opens no window: it loads the test reader (the Windows code path)
into plain LuaJIT and compares only the reader API, in about a second for all
frames. Use it to check a change to `sources/main.c` quickly; the views still
need one of the other platforms.

## Adding a frame or refreshing expected results

1. Add an entry to `tools-n-shit/research/test-frame-selection.json`, then run
   the extraction tool:
   - File 1 frames on the Mac.
   - File 2 frames on the Deck with `--via decky`, using the plugin's toolchain
     (`CC`, `LUAJIT_INCLUDE` and `ZLIB_PREFIX`, as in the tool's header). Recordings
     never leave the Deck; only the trimmed frames are copied back.
2. Add its facts to `facts.json` in the fixtures folder.
3. Regenerate the expected results:
   - `--write-expected` for `mac` (pine family);
   - `--write-expected` for `windows-layout` (windows family);
   - `decky_frames.py --layout --write-expected` (decky).
4. Review the changes, including screenshots of the views.
5. With `TRACKER_TEST_KEY` set, run
   `python3 tests/run_frames.py --fixtures ../local-tools/frame-fixtures --make-bundle tests/fixtures.tar.gz.gpg`
   and commit the bundle.

An intended change to what the tracker shows also needs refreshed expected
results, reviewed the same way.

## Coverage

| Version | Frames |
|---|---|
| Japanese File 1 (SLPM-65428) | room list, room just created, Outbreak gameplay |
| U.S. File 1 (SLUS-20765 with Ver2.162) | room list, created room, Outbreak (early, J's BAR, result screen), The Hive (Cindy's bag, door attack, rooftop code), Decisions, Decisions (clock answer, code answer) |
| Japanese File 2 (SLPM-65692) | Wild Things (before the start, Very Hard run), Desperate Times Very Hard, Underbelly, Flashback Easy (forest), Elimination 1, 2 and 3, Showdown 3 Very Hard |

Not covered yet:

- Japanese File 1 Hive, Hellfire, Below Freezing Point and Decisions, Decisions.
- U.S. Hellfire, U.S. Below Freezing Point and stock U.S. v2.00.
- File 2 End of the Road, Showdown 1 and 2, and Flashback Hard and Very Hard.
- The Nightmare and Duplicate Characters options.
- The live SP radar (private provider, not in public builds).

Short recordings of any of these can be added as frames.
