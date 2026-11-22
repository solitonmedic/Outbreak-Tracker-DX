#!/usr/bin/env python3
"""Run the lint and every offline check: what to run before a pull request.

Purpose: one command, the same on macOS, Linux and Windows, for the checks that
  need no game, recording or encrypted test key: tests/lint.py, then every
  tests/unit/**/check-*.lua, check-*.py and check-*.js, each with the program
  it needs (LuaJIT, this Python, Node.js). The gameplay-frame tests need a built
  tracker and are run separately (tests/README.md).
Location/language: tests/check.py; Python 3.9 or later, standard library only.
  LuaJIT comes from the PATH or from the Windows build (windows/luajit/src).
Options: --skip-lint runs only the checks; --strict makes a skipped check (its
  program or a Python package is missing) a failure, as on GitHub.
Outputs: PASS, FAIL or SKIP per check, the output of each failed check, and a
  summary. Exit status 1 if anything failed (or, with --strict, was skipped).
  A check exits with status 77 to say it was skipped and why.
Safety: the checks use synthetic data and the repository's own files and write
  only to temporary folders.
Run from the repository root: python3 tests/check.py
Check: the last line says "all checks passed".
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
SKIPPED = 77  # exit status of a check that could not run here


def luajit():
    built = REPOSITORY / "windows" / "luajit" / "src" / "luajit.exe"
    return shutil.which("luajit") or (str(built) if built.exists() else None)


def command_for(check):
    """The command that runs one check, or (None, reason) when its program is missing."""
    if check.suffix == ".lua":
        program = luajit()
        return ([program, str(check), "."], None) if program else (None, "LuaJIT is not installed")
    if check.suffix == ".js":
        program = shutil.which("node")
        return ([program, str(check)], None) if program else (None, "Node.js is not installed")
    return [sys.executable, str(check)], None


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--skip-lint", action="store_true", help="only the checks in tests/unit")
    parser.add_argument("--strict", action="store_true", help="a skipped check is a failure")
    args = parser.parse_args()
    results = []
    if not args.skip_lint:
        lint = [sys.executable, str(HERE / "lint.py")] + (["--strict"] if args.strict else [])
        status = subprocess.run(lint, cwd=REPOSITORY).returncode
        results.append(("tests/lint.py", "PASS" if status == 0 else "FAIL", ""))
    checks = sorted(
        path for path in (HERE / "unit").rglob("check-*") if path.suffix in (".lua", ".py", ".js") and path.is_file()
    )
    for check in checks:
        name = check.relative_to(REPOSITORY).as_posix()
        command, reason = command_for(check)
        if command is None:
            results.append((name, "SKIP", reason))
            continue
        environment = dict(os.environ, PYTHONUTF8="1")
        run = subprocess.run(
            command,
            cwd=REPOSITORY,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        lines = run.stdout.strip().splitlines()
        if run.returncode == SKIPPED:
            results.append((name, "SKIP", lines[-1] if lines else "skipped"))
        elif run.returncode == 0:
            results.append((name, "PASS", ""))
        else:
            results.append((name, "FAIL", "\n".join(lines[-25:])))
    for name, verdict, detail in results:
        print("%s %s%s" % (verdict, name, (": " + detail) if verdict == "SKIP" else ""))
        if verdict == "FAIL" and detail:
            print("    " + detail.replace("\n", "\n    "))
    failed = [r for r in results if r[1] == "FAIL" or (args.strict and r[1] == "SKIP")]
    skipped = [r for r in results if r[1] == "SKIP"]
    if failed:
        print("%d of %d checks failed%s." % (len(failed), len(results), " or were skipped" if args.strict else ""))
    else:
        print("all checks passed%s." % (" (%d skipped)" % len(skipped) if skipped else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
