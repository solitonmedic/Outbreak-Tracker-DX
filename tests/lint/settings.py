"""Which files tests/lint.py treats differently, and why.

Purpose: keep every exception to the lint rules in one readable list, each with
  its reason, instead of scattering them through the script or the tools'
  configuration files.
Location/language: tests/lint/settings.py; Python 3 data, imported by tests/lint.py.
Paths are relative to the repository root and use "/". An entry ending in "/"
  covers everything below that folder.
Check: python3 tests/lint.py reports a stale entry (a path that no longer exists).
"""

# Written by a program, never edited by hand: no formatter or code checks run on
# them (reformatting would be undone the next time they are generated), but they
# must still be valid UTF-8 with LF line endings and no trailing whitespace.
GENERATED = {
    "sources/MapGeometry.lua": "room outlines exported from the game's map files",
    "sources/MapER.lua": "Evil Resource map art fitted to the game's map coordinates",
    "sources/MapLayout.lua": "map screen layout exported from the tracker's Penpot design",
    "sources/layout.lua": "SP layout exported from the tracker's Penpot design",
    "sources/icondata.lua": "sprite sheet coordinates for assets/icons.png",
    "sources/icondata2.lua": "sprite sheet coordinates for the second icon sheet",
    "sources/uidata.lua": "sprite sheet coordinates exported with TexturePacker",
    "decky/pnpm-lock.yaml": "written by pnpm",
    "decky/native-toolchain.lock": "written by decky/scripts/bootstrap_native.py",
}

# Other projects' files, kept exactly as they were released.
THIRD_PARTY = {
    "windows/Outbreak Tracker/include/": "LuaJIT's public headers",
    "windows/Outbreak Tracker/love2d/": "LÖVE's license and readme texts",
    "decky/LICENSE": "the Decky plugin template's license",
}

# Files whose layout belongs to Visual Studio: only the encoding and line-ending
# rules apply.
VISUAL_STUDIO = (".sln", ".vcxproj", ".filters")

# Binary files are recognised by these endings (and by a zero byte in the
# first 8 KiB); no text rule applies to them.
BINARY_ENDINGS = (
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".ico",
    ".icns",
    ".ttf",
    ".otf",
    ".woff",
    ".woff2",
    ".wav",
    ".ogg",
    ".mp3",
    ".gpg",
    ".zip",
    ".gz",
    ".so",
    ".dll",
    ".exe",
    ".pdb",
    ".dylib",
)

# Files larger than this outside assets/ are reported: anything that big is
# usually a build output, a memory image or a recording.
MAX_BYTES_OUTSIDE_ASSETS = 1024 * 1024

# Files that must never be committed. Recordings, memory images and game files
# hold the game's data (and sometimes login or network data); keys are secrets.
# Each entry is (description, test on the path relative to the root).
FORBIDDEN = [
    ("a run recording or memory image", lambda path: path.endswith((".bin", ".bin.gz", ".raw"))),
    ("a disc image", lambda path: path.lower().endswith((".iso", ".bin.cue", ".chd", ".cso"))),
    ("a PlayStation 2 memory card", lambda path: path.lower().endswith((".ps2", ".mcd", ".mc2"))),
    ("a game file sampled from the disc", lambda path: path.startswith("assets/maps/game/")),
    (
        "a key or secrets file",
        lambda path: (
            path.rsplit("/", 1)[-1] in {".env", "tracker-test-key.txt"} or path.endswith((".pem", ".key", ".p12"))
        ),
    ),
]

# Frame files (memory for the gameplay tests) start with these bytes; they are
# only ever committed inside the encrypted tests/fixtures.tar.gz.gpg.
FRAME_MAGIC = b"OTFRAME1"

# Home folders in paths give away a user name and only work on one computer.
# The Steam Deck's own account, /home/deck, is the same on every Deck.
HOME_PATH_ALLOWED = ("/home/deck/",)

# Scripts must start with a comment (or a Python docstring) saying what they
# do and how to run them.
SCRIPT_ENDINGS = (".py", ".sh", ".ps1")
