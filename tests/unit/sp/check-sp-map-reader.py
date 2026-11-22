#!/usr/bin/env python3
"""Build and run the synthetic SP map-reader check (check-sp-map-reader.c).

Purpose: reusable check of the native SP map reader in sources/main.c. It
  compiles check-sp-map-reader.c, which includes main.c with the stand-in
  Windows headers in tests/unit/memory-stub/ (memory comes from a zeroed 32 MiB
  buffer the check fills), links it with LuaJIT and runs it.
Location/language: tests/unit/sp/check-sp-map-reader.py; Python 3 standard
  library, a C compiler (CC, or clang/cc/gcc) and LuaJIT's headers and library
  (Homebrew luajit, or Debian/Ubuntu libluajit-5.1-dev; LUAJIT_INCLUDE and
  LUAJIT_LIB point at other folders).
Outputs: the check's PASS line; the executable goes to a temporary folder.
  Skipped (exit status 77) where no C compiler or LuaJIT headers are found, as
  on Windows without a Unix-style compiler.
Safety: synthetic memory only; no PINE, recordings or file writes.
Run from the repository root: python3 tests/unit/sp/check-sp-map-reader.py
Check: the last line starts with "PASS SP map native reader".
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parents[2]


def first_existing(candidates):
    return next((Path(c) for c in candidates if c and Path(c).exists()), None)


def main():
    compiler = os.environ.get("CC") or shutil.which("clang") or shutil.which("cc") or shutil.which("gcc")
    include = first_existing(
        [
            os.environ.get("LUAJIT_INCLUDE"),
            "/opt/homebrew/opt/luajit/include/luajit-2.1",
            "/usr/local/opt/luajit/include/luajit-2.1",
            "/usr/include/luajit-2.1",
        ]
    )
    if not compiler or not include or not (include / "lua.h").exists():
        print("SKIP: check-sp-map-reader needs a C compiler and LuaJIT's headers")
        sys.exit(77)
    library = first_existing(
        [os.environ.get("LUAJIT_LIB"), "/opt/homebrew/opt/luajit/lib", "/usr/local/opt/luajit/lib"]
    )
    # The legacy reader is old C; newer GCC versions make these warnings errors.
    legacy = ["-Wno-incompatible-pointer-types", "-Wno-int-conversion", "-Wno-implicit-function-declaration"]
    with tempfile.TemporaryDirectory(prefix="sp-map-check-") as folder:
        executable = Path(folder) / "check"
        command = [compiler, "-x", "c", "-std=c11", "-w"] + legacy
        command += ["-I", str(REPOSITORY / "tests/unit/memory-stub"), "-I", str(REPOSITORY / "sources")]
        command += ["-I", str(include), str(HERE / "check-sp-map-reader.c")]
        command += (["-L", str(library)] if library else []) + ["-lluajit-5.1", "-lm", "-o", str(executable)]
        subprocess.run(command, check=True)
        sys.exit(subprocess.run([str(executable)]).returncode)


if __name__ == "__main__":
    main()
