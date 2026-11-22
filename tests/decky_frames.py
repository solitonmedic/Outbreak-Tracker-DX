#!/usr/bin/env python3
"""Run the Decky plugin's reader against gameplay frames and compare the results.

Purpose: reusable release test for the Steam Deck plugin, run by the Decky
  workflow on the built ZIP. Per frame it serves the frame through the fake
  PINE socket and checks two things:
    1. the plugin's native reader (bin/luaoutbreaktracker.so) gives the same
       reader API as the macOS/Linux family (expected/pine, the "api" part);
    2. the plugin's reader.lua (the shared UI driving the phone page) draws the
       expected text and map state for each control (expected/decky).
Location/language: tests/decky_frames.py; Python 3 standard library and LuaJIT.
Inputs: --zip built plugin ZIP, or --layout to assemble the plugin files from
  this checkout with --reader-so (a macOS/Linux build of the reader) and
  fontmetrics from decky/scripts/font_metrics.py (needs Pillow), used to write
  the expected Decky results on a Mac. Fixtures as in tests/run_frames.py:
  --fixtures DIR, --bundle FILE.gpg with TRACKER_TEST_KEY, or --synthetic.
Outputs: PASS/FAIL per frame with differing fields; --write-expected writes
  expected/decky/<frame>.json; --report writes pass/fail only. On GitHub
  Actions the failures also go into one error annotation.
Safety: temporary plugin copy and socket folder; the real PCSX2 is never
  contacted; decrypted fixtures are deleted afterwards.
Run from repo-merged/:
  python3 tests/decky_frames.py --zip outbreak-tracker.zip --bundle tests/fixtures.tar.gz.gpg
  python3 tests/decky_frames.py --layout --reader-so "Outbreak Status Tracker.app/Contents/Resources/game/luaoutbreaktracker.so" --fixtures /tmp/fx --write-expected
Check: exit status 0 with one PASS line per frame.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(HERE))
import frames  # noqa: E402
import run_frames  # noqa: E402

# The desktop steps, without the CONTROLS click (the phone page has its own menu).
STEPS = [
    "main",
    "f1",
    "f1",
    "f2",
    "f2",
    "f2",
    "f3",
    "f3",
    "home",
    "l",
    "l",
    "i",
    "i",
    "t",
    "t",
    "q",
    "q",
    "e",
    "e",
    "f4",
    "f4",
    "m",
    "m",
    "v",
    "h",
    "d",
    "a",
    "1",
    "2",
    "3",
    "4",
    "kp1",
    "kp0",
    "n",
    "f",
    "f",
    "b",
    "home",
]
WARM, PER = 40, 3


def plugin_from_zip(path, work):
    with zipfile.ZipFile(path) as z:
        z.extractall(work)
    found = [p.parent for p in work.rglob("reader.lua") if (p.parent / "bin").is_dir()]
    if not found:
        sys.exit("FAIL: no plugin folder with reader.lua and bin/ in " + str(path))
    return found[0]


def plugin_from_repo(reader_so, work):
    plugin = work / "outbreak-tracker"
    (plugin / "shared").mkdir(parents=True)
    (plugin / "bin").mkdir()
    for source in (REPO / "sources").glob("*.lua"):
        shutil.copy2(source, plugin / "shared")
    shutil.copy2(REPO / "decky" / "reader.lua", plugin)
    run_frames.copy_assets(plugin)
    shutil.copy2(reader_so, plugin / "bin" / "luaoutbreaktracker.so")
    subprocess.run(
        [
            sys.executable,
            str(REPO / "decky" / "scripts" / "font_metrics.py"),
            str(REPO / "assets"),
            str(plugin / "fontmetrics.lua"),
        ],
        check=True,
    )
    return plugin


def run_frame(plugin, frame_path, work, timeout):
    return run_plugin(plugin, work, timeout, memory=frames.read_frame(frame_path))


def run_plugin(plugin, work, timeout, memory=None, env_extra=None):
    """Run the API dump and reader.lua once. memory is served over a fake PINE
    socket; without it the reader takes memory from env_extra (the test reader's
    TRACKER_FRAME / TRACKER_IMAGE)."""
    runtime = work / "s"
    runtime.mkdir(exist_ok=True)
    env = dict(os.environ, TMPDIR=str(runtime), XDG_RUNTIME_DIR=str(runtime))
    env.update(env_extra or {})
    fake = frames.FakePine(runtime, memory) if memory is not None else None
    problems, result = [], {"views": []}
    try:
        api = subprocess.run(
            ["luajit", "-e", frames.READER_API_SCRIPT],
            cwd=plugin,
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        if api.returncode != 0:
            problems.append("reader API dump failed: " + api.stderr[-600:])
        else:
            result["api"] = json.loads(api.stdout)
        lines = [""] * (WARM - 1)
        for step in STEPS:
            lines += [step if step != "main" else ""] + [""] * (PER - 1)
        ui = subprocess.run(
            ["luajit", "reader.lua"],
            cwd=plugin,
            env=env,
            input="\n".join(lines) + "\n",
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        outputs = ui.stdout.splitlines()
        if ui.returncode != 0 or len(outputs) != len(lines):
            problems.append(
                "reader.lua stopped after %d of %d frames: %s" % (len(outputs), len(lines), ui.stderr[-600:])
            )
        for index, step in enumerate(STEPS):
            line = WARM - 1 + index * PER + PER - 1
            if line >= len(outputs):
                break
            frame = json.loads(outputs[line])
            if frame.get("state") == "error":
                problems.append("step %s: %s" % (step, frame.get("message")))
            texts = [c[1] if isinstance(c[1], str) else str(c[1]) for c in frame["commands"] if c and c[0] == "text"]
            result["views"].append(
                {
                    "step": step,
                    "state": frame.get("state"),
                    "texts": texts,
                    "mapview": (frame.get("game") or {}).get("mapview"),
                }
            )
    except subprocess.TimeoutExpired:
        problems.append("timed out")
    finally:
        if fake:
            fake.stop()
            problems += ["fake PINE: " + e for e in fake.errors]
    return result, problems


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--zip", type=Path)
    parser.add_argument("--layout", action="store_true")
    parser.add_argument("--reader-so", type=Path)
    parser.add_argument("--fixtures", type=Path)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--synthetic", action="store_true")
    parser.add_argument("--frame", action="append")
    parser.add_argument("--write-expected", action="store_true")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    if not shutil.which("luajit"):
        sys.exit("FAIL: luajit is not installed")
    with tempfile.TemporaryDirectory(prefix="ot-decky-") as temporary:
        temporary = Path(temporary)
        if args.bundle:
            fixtures = run_frames.decrypt(args.bundle.resolve(), temporary)
        elif args.fixtures:
            fixtures = args.fixtures.resolve()
            if args.synthetic:
                run_frames.synthetic(fixtures)
        elif args.synthetic:
            fixtures = temporary / "fixtures"
            run_frames.synthetic(fixtures)
        else:
            parser.error("give --fixtures, --bundle or --synthetic")
        work = temporary / "plugin"
        work.mkdir()
        if args.zip:
            plugin = plugin_from_zip(args.zip.resolve(), work)
        elif args.layout and args.reader_so:
            plugin = plugin_from_repo(args.reader_so.resolve(), work)
        else:
            parser.error("give --zip, or --layout with --reader-so")
        for name in ("frames_dump.lua", "frames_json.lua"):
            shutil.copy2(HERE / "automation" / name, plugin / name)
        facts = frames.load_json(fixtures / "facts.json").get("frames", {})
        names = sorted(p.stem for p in (fixtures / "frames").glob("*.otf"))
        if args.frame:
            names = [n for n in names if n in args.frame]
        report, failed = {"platform": "decky", "frames": {}}, 0
        summary = []  # failures, for the GitHub annotation
        for index, name in enumerate(names):
            # Short folder names: Unix socket paths are limited to about 104 bytes.
            run = temporary / ("r%d" % index)
            run.mkdir()
            result, problems = run_frame(plugin, fixtures / "frames" / (name + ".otf"), run, args.timeout)
            if "api" in result:
                problems += frames.check_facts(facts.get(name, {}), result)
                pine = fixtures / "expected" / "pine" / (name + ".json")
                if pine.exists():
                    problems += frames.compare({"api": frames.load_json(pine)["api"]}, {"api": result["api"]})
                elif not args.write_expected:
                    problems.append("no expected pine result for the reader API")
            expected = fixtures / "expected" / "decky" / (name + ".json")
            if args.write_expected:
                expected.parent.mkdir(parents=True, exist_ok=True)
                expected.write_text(
                    json.dumps({"views": result["views"]}, indent=1, sort_keys=True) + "\n", encoding="utf-8"
                )
            elif expected.exists():
                problems += frames.compare(frames.load_json(expected), {"views": result["views"]})
            else:
                problems.append("no expected Decky result")
            shutil.rmtree(run, ignore_errors=True)
            report["frames"][name] = "PASS" if not problems else "FAIL"
            if problems:
                failed += 1
                print("FAIL %s (decky): %d problem(s)" % (name, len(problems)))
                summary += ["%s: %d problem(s)" % (name, len(problems))] + ["  " + line for line in problems[:8]]
                for line in problems[:40]:
                    print("    " + line)
            else:
                print("PASS %s (decky)%s" % (name, " expected written" if args.write_expected else ""))
        if args.report:
            args.report.write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
        print("%d of %d frames passed on decky" % (len(names) - failed, len(names)))
        if not names:
            summary.append("no frames were found")
        frames.annotate("Gameplay frame tests failed on decky", summary)
        sys.exit(1 if failed or not names else 0)


if __name__ == "__main__":
    frames.run_main(main, "Gameplay frame tests (decky)")
