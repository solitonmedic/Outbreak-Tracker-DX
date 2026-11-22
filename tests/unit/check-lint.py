#!/usr/bin/env python3
"""Check that tests/lint.py reports every kind of problem it is meant to find.

Purpose: reusable self-test of the lint script. It builds a throwaway Git
  folder holding the repository's lint configuration and one bad example per
  rule, runs tests/lint.py on it, and expects each example to be reported under
  its rule, the clean examples to pass, and --fix to repair whitespace.
Location/language: tests/unit/check-lint.py; Python 3.9 or later, standard
  library; Git. Rules that need a tool (StyLua, selene, clang-format, Ruff,
  ShellCheck, Biome, actionlint, LuaJIT, PowerShell) are tested only where the
  tool is installed (python3 tests/lint.py --install-tools).
Inputs: none (--strict: a rule whose tool is missing is a failure).
Outputs: one PASS or FAIL line per rule and a summary; exit status 1 on failure.
Safety: writes only inside a temporary folder that is deleted afterwards.
Run from the repository root: python3 tests/unit/check-lint.py
Check: every line says PASS and the last line says "lint self-test passed".
"""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

REPOSITORY = Path(__file__).resolve().parents[2]
LINT = REPOSITORY / "tests" / "lint.py"
CONFIGURATION = [
    ".editorconfig",
    ".clang-format",
    "stylua.toml",
    ".styluaignore",
    "ruff.toml",
    "decky/biome.jsonc",
    "tests/lint/selene.toml",
    "tests/lint/tracker.yml",
]

# (file, content, rule it must trigger, tool the rule needs or None)
BAD = [
    ("notes/trailing.md", b"words  \n", "trailing-whitespace", None),
    ("notes/tabs.md", b"\tindented with a tab\n", "indentation", None),
    ("notes/no-newline.md", b"no newline at the end", "final-newline", None),
    ("notes/crlf.md", b"one\r\ntwo\r\n", "line-endings", None),
    ("notes/bom.md", "﻿byte-order mark\n".encode("utf-8"), "encoding", None),
    ("notes/latin1.md", b"caf\xe9\n", "encoding", None),
    ("notes/conflict.md", b"<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\n", "conflict-marker", None),
    # Built from two parts so that this file itself holds no home-folder path.
    ("notes/home.md", b"see /" + b"Users/someone/Documents/file\n", "personal-path", None),
    ("data/broken.json", b"{\n", "json", None),
    ("scripts/broken.py", b'"""Broken."""\ndef f(:\n', "python-syntax", None),
    ("scripts/no-header.sh", b"#!/bin/sh\nset -eu\n", "script-header", None),
    ("run.bin.gz", b"\x1f\x8b\x08\x00 recording", "forbidden-file", None),
    ("frame.otf", b"OTFRAME1\x00\x00\x00\x00", "forbidden-file", None),
    ("big.txt", b"x" * (1024 * 1024 + 1) + b"\n", "file-size", None),
    ("src/broken.lua", b"local value =\n", "lua-syntax", "luajit"),
    ("src/unformatted.lua", b"local a=1 local b=2\nreturn a+b\n", "lua-format", "stylua"),
    ("src/undefined.lua", b"print(undefined_global_name)\n", "lua-check", "selene"),
    ("src/unformatted.c", b"int main(){return 0;}\n", "c-format", "clang-format"),
    ("scripts/unused.py", b'"""Imports something it never uses."""\nimport os\n', "python-check", "ruff"),
    ("scripts/unformatted.py", b'"""Unformatted."""\nvalue = {"a":1}\n', "python-format", "ruff"),
    ("scripts/unquoted.sh", b"#!/bin/sh\n# Prints its first argument.\necho $1\n", "shell-check", "shellcheck"),
    ("decky/web/unformatted.js", b"const value = {a:1}\n", "web-check", "biome"),
    (
        ".github/workflows/bad.yml",
        b"name: Bad\non: push\njobs:\n  bad:\n    runs-on: ubuntu-24.04\n    steps:\n"
        b"      - run: echo ${{ github.no_such_property }}\n",
        "workflow-check",
        "actionlint",
    ),
    ("scripts/broken.ps1", b"# Broken on purpose.\nfunction {\n", "powershell-syntax", "powershell"),
]

GOOD = [
    ("notes/clean.md", b"Nothing wrong here.\n"),
    ("src/clean.lua", b"local value = 1\nreturn value\n"),
    ("scripts/clean.py", b'"""Does nothing."""\n\nVALUE = 1\n'),
]


def tool_available(tool):
    if tool is None:
        return True
    if tool == "luajit":
        return shutil.which("luajit") is not None
    if tool == "powershell":
        return shutil.which("pwsh") is not None or shutil.which("powershell") is not None
    sys.path.insert(0, str(REPOSITORY / "tests"))
    import lint  # noqa: E402  (imported here so the self-test can start without it)

    return lint.find_tool(tool)[0] is not None


def make_folder(folder):
    subprocess.run(["git", "init", "-q", str(folder)], check=True)
    for name in CONFIGURATION:
        target = folder / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPOSITORY / name, target)
    for name, content, _, _ in BAD:
        target = folder / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    for name, content in GOOD:
        (folder / name).parent.mkdir(parents=True, exist_ok=True)
        (folder / name).write_bytes(content)


def lint(folder, names, fix=False):
    command = (
        [sys.executable, str(LINT), "--root", str(folder)]
        + (["--fix"] if fix else [])
        + [str(folder / name) for name in names]
    )
    result = subprocess.run(command, cwd=folder, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    found = set()
    for line in result.stdout.splitlines():
        parts = line.split(": ", 2)
        if len(parts) == 3 and ":" in parts[0]:
            found.add((parts[0].rsplit(":", 1)[0], parts[1]))
    return found, result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--strict", action="store_true", help="a rule whose tool is missing is a failure")
    args = parser.parse_args()
    failures = 0
    with tempfile.TemporaryDirectory(prefix="lint-check-") as name:
        folder = Path(name)
        make_folder(folder)
        found, output = lint(folder, [n for n, *_ in BAD] + [n for n, _ in GOOD])
        for path, _, rule, tool in BAD:
            if not tool_available(tool):
                print("%s %s (%s): %s is not installed" % ("FAIL" if args.strict else "SKIP", rule, path, tool))
                failures += args.strict
            elif (path, rule) in found:
                print("PASS %s (%s)" % (rule, path))
            else:
                print("FAIL %s (%s) was not reported" % (rule, path))
                failures += 1
        for path, _ in GOOD:
            reported = sorted(rule for p, rule in found if p == path)
            if reported:
                print("FAIL clean file %s was reported: %s" % (path, ", ".join(reported)))
                failures += 1
            else:
                print("PASS clean file %s" % path)
        # --fix repairs the whitespace rules.
        fixable = ["notes/trailing.md", "notes/no-newline.md", "notes/crlf.md"]
        lint(folder, fixable, fix=True)
        expected = {
            "notes/trailing.md": b"words\n",
            "notes/no-newline.md": b"no newline at the end\n",
            "notes/crlf.md": b"one\ntwo\n",
        }
        for path, content in expected.items():
            if (folder / path).read_bytes() == content:
                print("PASS --fix repaired %s" % path)
            else:
                print("FAIL --fix left %s as %r" % (path, (folder / path).read_bytes()))
                failures += 1
        if failures:
            print("lint output:\n" + output)
    print("lint self-test %s" % ("failed (%d)" % failures if failures else "passed"))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
