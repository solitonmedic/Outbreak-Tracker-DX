#!/usr/bin/env python3
"""Run a built tracker against gameplay frames and compare what it reads and draws.

Purpose: reusable release test, run by the GitHub workflows and locally. For
  each frame it lays out the shipped game files and runtime of one platform,
  serves the frame's memory through that platform's fake (PINE socket, or a
  stand-in pcsx2-qt.exe on Windows), runs tests/automation/main.lua around the
  platform's own main.lua, and compares the result with the expected JSON for
  that platform family and with the frame's hand-checked facts.
Location/language: tests/run_frames.py; Python 3 standard library (gpg for
  --bundle, clang/gcc, zlib and LuaJIT headers for --build-test-reader; CC,
  LUAJIT_INCLUDE and ZLIB_PREFIX point at a compiler, headers or a zlib folder
  outside the default paths, as on the Steam Deck).
Platforms (--platform):
  mac             a built "Outbreak Status Tracker.app" (--app); family pine
  linux           an extracted AppImage folder, squashfs-root (--appdir); its
                  AppRun starts plain LÖVE cut from the fused binary; family pine
  windows         the Windows distribution folder (--dist) and the stand-in
                  pcsx2-qt.exe (--fake-pcsx2); runs the LÖVE part of the fused
                  OutbreakTracker.exe with --fused; optional --opengl folder
                  (Mesa opengl32.dll for runners without a GPU); family windows
  linux-layout    on a Mac: the Linux file arrangement with the .app's LÖVE and
                  reader (--app); family pine
  windows-layout  on a Mac or Linux: the Windows arrangement with the test reader
                  built from main.c as C (--test-reader); family windows
  windows-api     on a Mac or Linux, headless: the test reader (--test-reader)
                  under plain LuaJIT, compared on the reader API only (no views,
                  no LÖVE window); family windows
Inputs: --fixtures DIR (frames/*.otf, expected/<family>/*.json, facts.json) or
  --bundle FILE.gpg with the passphrase in TRACKER_TEST_KEY; --synthetic uses
  two generated frames instead (blank, synthetic U.S. File 1).
Options: --no-expected checks facts and errors only (synthetic smoke runs);
  --launch-check SECONDS also starts the real shipped program unchanged (the
  .app launcher, the AppImage's AppRun, OutbreakTracker.exe) against the first
  frame with a game loaded and checks that it stays up and, over PINE, keeps
  reading memory. The shipped program keeps vsync on, so on a machine whose
  display is asleep it stalls and this check fails; run it with the display on.
Outputs: PASS/FAIL per frame with differing fields (path, expected, actual);
  optional --report JSON with pass/fail only; --write-expected writes the
  expected JSON of the chosen family into --fixtures. On GitHub Actions the
  failures (first 8 fields per frame) also go into one error annotation.
Safety: memory comes only from the frames; sockets and processes are temporary
  and the real PCSX2 is never contacted. Decrypted fixtures stay in a temporary
  folder that is deleted afterwards; nothing from them is uploaded.
Run from repo-merged/, for example:
  python3 tests/run_frames.py --platform mac --app "Outbreak Status Tracker.app" --synthetic --write-expected --fixtures /tmp/fx
  python3 tests/run_frames.py --platform mac --app "Outbreak Status Tracker.app" --fixtures /tmp/fx
  python3 tests/run_frames.py --build-test-reader /tmp/test-reader.so
  TRACKER_TEST_KEY=... python3 tests/run_frames.py --platform linux --appdir squashfs-root --bundle tests/fixtures.tar.gz.gpg
Check: exit status 0 and one PASS line per frame; a changed frame byte or a
  broken Lua view makes it fail with the differing fields.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(HERE))
import frames  # noqa: E402

FAMILY = {
    "mac": "pine",
    "linux": "pine",
    "linux-layout": "pine",
    "windows": "windows",
    "windows-layout": "windows",
    "windows-api": "windows",
}
API_ONLY = {"windows-api"}  # headless platforms that check the reader API without the UI
AUTOMATION = ["main.lua", "frames_dump.lua", "frames_json.lua"]


# ---------------------------------------------------------------- fixtures --


def synthetic(folder):
    """Two generated frames: blank memory and the synthetic U.S. File 1 state
    of tools-n-shit/tracker-tests/decky/check-live.py (marker, Hive, player 1)."""
    (folder / "frames").mkdir(parents=True, exist_ok=True)
    frames.write_frame(folder / "frames" / "synthetic-blank.otf", [])
    frames.write_frame(
        folder / "frames" / "synthetic-us.otf",
        [
            (0x250510, b"BASLUS-20765"),
            (0x3243DA, struct.pack("<H", 28)),
            (0x4A5C30, b"\x01"),
            (0x4BADE8, struct.pack("<I", 9000)),
        ],
    )
    facts = {
        "frames": {
            "synthetic-blank": {"description": "no game", "facts": {"api.game.currentFile": 255}},
            "synthetic-us": {
                "description": "synthetic U.S. File 1 marker",
                "facts": {"api.game.currentFile": 1, "api.game.release": "us"},
            },
        }
    }
    if not (folder / "facts.json").exists():
        (folder / "facts.json").write_text(json.dumps(facts, indent=1) + "\n", encoding="utf-8")


def decrypt(bundle, folder):
    key = os.environ.get("TRACKER_TEST_KEY")
    if not key:
        sys.exit("FAIL: the TRACKER_TEST_KEY secret is not set (GitHub: Settings > Secrets and variables > Actions)")
    archive = folder / "fixtures.tar.gz"
    decrypted = subprocess.run(
        [
            "gpg",
            "--batch",
            "--yes",
            "--quiet",
            "--pinentry-mode",
            "loopback",
            "--passphrase-fd",
            "0",
            "--output",
            str(archive),
            "--decrypt",
            str(bundle),
        ],
        input=key.encode(),
    )
    if decrypted.returncode != 0:
        sys.exit("FAIL: gpg could not decrypt %s (is TRACKER_TEST_KEY the passphrase it was made with?)" % bundle.name)
    with tarfile.open(archive) as tar:
        tar.extractall(folder / "fixtures", filter="data")
    archive.unlink()
    return folder / "fixtures"


def make_bundle(fixtures, bundle):
    """Encrypt a fixtures folder (frames/, expected/, facts.json) into bundle."""
    key = os.environ.get("TRACKER_TEST_KEY")
    if not key:
        sys.exit("set TRACKER_TEST_KEY to the passphrase")

    def clean(info):
        # No owner names or times in the archive (same bytes for the same content).
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        info.mtime = 0
        return info

    with tempfile.TemporaryDirectory(prefix="ot-bundle-") as temporary:
        archive = Path(temporary) / "fixtures.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            for name in ("facts.json", "frames", "expected"):
                tar.add(fixtures / name, arcname=name, filter=clean)
        subprocess.run(
            [
                "gpg",
                "--batch",
                "--yes",
                "--quiet",
                "--pinentry-mode",
                "loopback",
                "--passphrase-fd",
                "0",
                # RFC 4880 packets (no AEAD) so any gpg 2.x on a runner can decrypt.
                "--rfc4880",
                "--symmetric",
                "--cipher-algo",
                "AES256",
                "--output",
                str(bundle),
                str(archive),
            ],
            input=key.encode(),
            check=True,
        )
    print("wrote", bundle)


# ------------------------------------------------------------ game layout --


def zip_offset(data):
    """Offset where a zip appended to an executable starts (fused LÖVE)."""
    end = data.rfind(b"PK\x05\x06")
    if end < 0:
        raise ValueError("no appended game archive")
    size_cd, offset_cd = struct.unpack_from("<II", data, end + 12)
    return end - size_cd - offset_cd


def unfuse(fused, game, runtime_out):
    """Split a fused LÖVE executable into its game folder and plain LÖVE."""
    data = Path(fused).read_bytes()
    start = zip_offset(data)
    archive = game.parent / "embedded.love"
    archive.write_bytes(data[start:])
    with zipfile.ZipFile(archive) as z:
        z.extractall(game)
    runtime_out.write_bytes(data[:start])
    runtime_out.chmod(0o755)
    return archive


def copy_assets(game):
    shutil.copytree(
        REPO / "assets",
        game / "assets",
        ignore=lambda folder, names: ["game"] if Path(folder) == REPO / "assets" / "maps" else [],
    )


def arrange(args, work):
    """Return (command, game folder, environment additions) for one platform."""
    base = work / "base"
    game = base / "game"
    base.mkdir()
    platform = args.platform
    if platform == "mac":
        shipped = args.app / "Contents" / "Resources" / "game"
        shutil.copytree(shipped, game)
        love = args.app / "Contents" / "Frameworks" / "love.app" / "Contents" / "MacOS" / "love"
        command = [str(love), str(game)]
    elif platform == "linux":
        root = work / "appdir"
        shutil.copytree(args.appdir, root, symlinks=True)
        unfuse(root / "bin" / "OutbreakStatusTracker", game, root / "bin" / "OutbreakStatusTracker")
        command = [str(root / "AppRun"), str(game)]
    elif platform == "windows":
        shutil.copytree(args.dist, base, dirs_exist_ok=True)
        unfuse(base / "OutbreakTracker.exe", game, base / "love-test.exe")
        if args.opengl:
            for dll in Path(args.opengl).glob("*.dll"):
                shutil.copy2(dll, base)
        command = [str(base / "love-test.exe"), "--fused", str(game)]
    elif platform == "linux-layout":
        game.mkdir()
        for source in (REPO / "sources").glob("*.lua"):
            shutil.copy2(source, game)
        copy_assets(game)
        shutil.copy2(REPO / "sources" / "main.lua", game / "main_base.lua")
        shutil.copy2(REPO / "linux" / "overrides" / "main.lua", game / "main.lua")
        shutil.copy2(args.app / "Contents" / "Resources" / "game" / "luaoutbreaktracker.so", game)
        love = args.app / "Contents" / "Frameworks" / "love.app" / "Contents" / "MacOS" / "love"
        command = [str(love), str(game)]
    elif platform == "windows-layout":
        game.mkdir()
        for source in (REPO / "sources").glob("*.lua"):
            shutil.copy2(source, game)
        copy_assets(game)
        shutil.copy2(REPO / "windows" / "overrides" / "language.lua", game / "language.lua")
        (game / "main.lua").rename(game / "tracker-main.lua")
        shutil.copy2(REPO / "windows" / "overrides" / "main.lua", game / "main.lua")
        shutil.copy2(args.test_reader, base / "luaoutbreaktracker.so")
        love = shutil.which("love") or "/Applications/love.app/Contents/MacOS/love"
        if args.app:
            love = str(args.app / "Contents" / "Frameworks" / "love.app" / "Contents" / "MacOS" / "love")
        command = [love, "--fused", str(game)]
    else:
        raise SystemExit("unknown platform " + platform)
    if sys.platform == "darwin":
        # After any crash macOS asks, invisibly, whether to reopen windows and
        # LÖVE waits for the answer; this argument skips that prompt.
        command += ["-ApplePersistenceIgnoreState", "YES"]
    (game / "main.lua").rename(game / "frames-target.lua")
    for name in AUTOMATION:
        shutil.copy2(HERE / "automation" / name, game / name)
    return command, game


# ---------------------------------------------------------------- running --


def run_reader_api(args, frame_path, work):
    """windows-api: the test reader under plain LuaJIT; returns ({"api": ...} or None, problems)."""
    folder = work / "reader"
    (folder / "bin").mkdir(parents=True)
    shutil.copy2(args.test_reader, folder / "bin" / "luaoutbreaktracker.so")
    for name in ("frames_dump.lua", "frames_json.lua"):
        shutil.copy2(HERE / "automation" / name, folder / name)
    env = dict(os.environ, TRACKER_FRAME=str(frame_path))
    try:
        dump = subprocess.run(
            ["luajit", "-e", frames.READER_API_SCRIPT],
            cwd=folder,
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=args.timeout,
        )
    except subprocess.TimeoutExpired:
        return None, ["timed out after %d s" % args.timeout]
    if dump.returncode != 0:
        return None, ["reader API dump failed: " + dump.stderr[-600:]]
    return {"api": json.loads(dump.stdout)}, []


def run_frame(args, name, frame_path, work):
    """Run one frame; return (result dict or None, problems list)."""
    if args.platform in API_ONLY:
        return run_reader_api(args, frame_path, work)
    command, game = arrange(args, work)
    runtime = work / "s"
    runtime.mkdir()
    out, log = work / "result.json", work / "log.txt"
    env = dict(os.environ, FRAMES_OUT=str(out), FRAMES_LOG=str(log), TMPDIR=str(runtime), XDG_RUNTIME_DIR=str(runtime))
    if args.shots:
        env.update(FRAMES_SHOTS=str(args.shots), FRAMES_NAME=name)
    fake = process = None
    problems = []
    try:
        if args.platform in ("mac", "linux", "linux-layout"):
            fake = frames.FakePine(runtime, frames.read_frame(frame_path))
        elif args.platform == "windows-layout":
            env["TRACKER_FRAME"] = str(frame_path)
        elif args.platform == "windows":
            fake = subprocess.Popen(
                [str(args.fake_pcsx2), str(frame_path)],
                stdout=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            ready = fake.stdout.readline().strip()
            if ready != "ready":
                problems.append("stand-in pcsx2-qt.exe did not start: %r" % ready)
                return None, problems
        process = subprocess.run(
            command,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=args.timeout,
        )
        if process.returncode != 0:
            problems.append("exit status %d" % process.returncode)
    except subprocess.TimeoutExpired:
        problems.append("timed out after %d s" % args.timeout)
    finally:
        if isinstance(fake, frames.FakePine):
            fake.stop()
            problems += ["fake PINE: " + e for e in fake.errors]
        elif fake is not None:
            fake.kill()
            fake.wait()
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines() if log.exists() else []
    errors = [i for i, line in enumerate(lines) if line.startswith("ERROR")]
    if errors:
        problems.append("\n    ".join(lines[errors[0] : errors[0] + 20]))
    if "DONE" not in lines:
        problems.append(
            "did not finish (%d log lines)%s" % (len(lines), ("; output: " + process.stdout[-800:]) if process else "")
        )
    if not out.exists():
        return None, problems
    return frames.load_json(out), problems


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--platform", choices=sorted(FAMILY))
    parser.add_argument("--app", type=Path)
    parser.add_argument("--appdir", type=Path)
    parser.add_argument("--dist", type=Path)
    parser.add_argument("--fake-pcsx2", type=Path)
    parser.add_argument("--opengl", type=Path)
    parser.add_argument("--test-reader", type=Path)
    parser.add_argument("--fixtures", type=Path)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--synthetic", action="store_true")
    parser.add_argument("--frame", action="append", help="run only these frames")
    parser.add_argument("--write-expected", action="store_true")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--shots", type=Path, help="local review: save a PNG of every recorded view here (never in CI)")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--no-expected", action="store_true", help="check facts and errors only (no expected JSON)")
    parser.add_argument(
        "--launch-check",
        type=int,
        metavar="SECONDS",
        help="also start the real shipped program unchanged for SECONDS against the first frame",
    )
    parser.add_argument("--build-test-reader", type=Path, metavar="OUTPUT.so")
    parser.add_argument("--make-bundle", type=Path, metavar="BUNDLE.gpg")
    args = parser.parse_args()
    if args.shots:
        args.shots.mkdir(parents=True, exist_ok=True)
    for name in ("app", "appdir", "dist", "fake_pcsx2", "opengl", "test_reader", "fixtures", "bundle", "shots"):
        if getattr(args, name):
            setattr(args, name, getattr(args, name).resolve())

    if args.build_test_reader:
        build_test_reader(args.build_test_reader)
        return
    if args.make_bundle:
        make_bundle(args.fixtures, args.make_bundle)
        return
    if not args.platform:
        parser.error("--platform is required")
    family = FAMILY[args.platform]
    if args.platform in API_ONLY:
        if not args.test_reader:
            parser.error("--platform %s needs --test-reader" % args.platform)
        if args.write_expected or args.launch_check or args.shots:
            # Its results hold no views, so they must never replace an expected result.
            parser.error(
                "--platform %s only compares; it cannot write expected results, shots or launch" % args.platform
            )
    with tempfile.TemporaryDirectory(prefix="ot-frames-") as temporary:
        temporary = Path(temporary)
        if args.bundle:
            fixtures = decrypt(args.bundle, temporary)
        elif args.fixtures:
            fixtures = args.fixtures
            if args.synthetic:
                synthetic(fixtures)
        elif args.synthetic:
            fixtures = temporary / "fixtures"
            synthetic(fixtures)
        else:
            parser.error("give --fixtures, --bundle or --synthetic")
        facts = frames.load_json(fixtures / "facts.json").get("frames", {})
        names = sorted(p.stem for p in (fixtures / "frames").glob("*.otf"))
        if args.frame:
            names = [n for n in names if n in args.frame]
        report, failed = {"platform": args.platform, "family": family, "frames": {}}, 0
        summary = []  # failures, for the GitHub annotation
        loaded = []  # frames with a game loaded, for --launch-check
        for index, name in enumerate(names):
            # Short folder names: Unix socket paths are limited to about 104 bytes.
            work = temporary / ("r%d" % index)
            work.mkdir()
            result, problems = run_frame(args, name, fixtures / "frames" / (name + ".otf"), work)
            if result is not None and (result.get("api") or {}).get("game", {}).get("currentFile") in (1, 2):
                loaded.append(name)
            if result is not None:
                api_only = args.platform in API_ONLY
                problems += frames.check_facts(facts.get(name, {}), result, api_only=api_only)
                expected_path = fixtures / "expected" / family / (name + ".json")
                if args.write_expected:
                    expected_path.parent.mkdir(parents=True, exist_ok=True)
                    expected_path.write_text(json.dumps(result, indent=1, sort_keys=True) + "\n", encoding="utf-8")
                elif expected_path.exists() and not args.no_expected:
                    expected = frames.load_json(expected_path)
                    if api_only:
                        problems += frames.compare({"api": expected["api"]}, result)
                    else:
                        problems += frames.compare(frames.compared(expected), frames.compared(result))
                elif not args.no_expected:
                    problems.append("no expected result for family %s" % family)
            shutil.rmtree(work, ignore_errors=True)
            report["frames"][name] = "PASS" if not problems else "FAIL"
            if problems:
                failed += 1
                print("FAIL %s (%s): %d problem(s)" % (name, args.platform, len(problems)))
                summary += ["%s: %d problem(s)" % (name, len(problems))] + ["  " + line for line in problems[:8]]
                for line in problems[:40]:
                    print("    " + line)
                if len(problems) > 40:
                    print("    ... %d more" % (len(problems) - 40))
            else:
                print("PASS %s (%s)%s" % (name, args.platform, " expected written" if args.write_expected else ""))
        if args.launch_check and loaded:
            work = temporary / "launch"
            work.mkdir()
            problems = launch_check(args, fixtures / "frames" / (loaded[0] + ".otf"), work)
            report["launch"] = "PASS" if not problems else "FAIL"
            if problems:
                failed += 1
                print("FAIL shipped program (%s): %s" % (args.platform, "; ".join(problems)))
                summary.append("shipped program: " + "; ".join(problems))
            else:
                print("PASS shipped program (%s) ran %d s unchanged" % (args.platform, args.launch_check))
        if args.report:
            args.report.write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
        print("%d of %d frames passed on %s" % (len(names) - failed, len(names), args.platform))
        if not names:
            summary.append("no frames were found")
        frames.annotate("Gameplay frame tests failed on %s" % args.platform, summary)
        sys.exit(1 if failed or not names else 0)


def launch_check(args, frame_path, work):
    """Start the real shipped program, unchanged, against one frame and check it
    stays up; on macOS and Linux it must also keep reading memory (a Lua error
    leaves LÖVE on its error screen, which stops the reads)."""
    import time

    runtime = work / "s"
    runtime.mkdir()
    env = dict(os.environ, TMPDIR=str(runtime), XDG_RUNTIME_DIR=str(runtime))
    if args.platform == "mac":
        command = [str(args.app / "Contents" / "MacOS" / "OutbreakStatusTracker")]
    elif args.platform == "linux":
        root = work / "appdir"
        shutil.copytree(args.appdir, root, symlinks=True)
        command = [str(root / "AppRun")]
    elif args.platform == "windows":
        base = work / "dist"
        shutil.copytree(args.dist, base)
        if args.opengl:
            for dll in Path(args.opengl).glob("*.dll"):
                shutil.copy2(dll, base)
        command = [str(base / "OutbreakTracker.exe")]
    else:
        return []
    fake = process = None
    problems = []
    try:
        if args.platform == "windows":
            fake = subprocess.Popen(
                [str(args.fake_pcsx2), str(frame_path)],
                stdout=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            if fake.stdout.readline().strip() != "ready":
                return ["stand-in pcsx2-qt.exe did not start"]
        else:
            fake = frames.FakePine(runtime, frames.read_frame(frame_path))
        process = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(max(2, args.launch_check - 3))
        before = getattr(fake, "messages", None)
        time.sleep(3)
        if process.poll() is not None:
            problems.append("exited early with status %s" % process.returncode)
        elif before is not None and fake.messages <= before:
            problems.append("stopped reading memory (%d PINE messages)" % fake.messages)
        elif before is not None and fake.messages == 0:
            problems.append("never read memory")
    finally:
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
        if isinstance(fake, frames.FakePine):
            fake.stop()
            problems += ["fake PINE: " + e for e in fake.errors]
        elif fake is not None:
            fake.kill()
            fake.wait()
    return problems


def build_test_reader(output):
    """Build tests/reader/module.c (main.c as C with stand-in Windows headers)."""
    luajit = None
    for candidate in [
        os.environ.get("LUAJIT_INCLUDE"),
        "/opt/homebrew/opt/luajit/include/luajit-2.1",
        "/usr/local/opt/luajit/include/luajit-2.1",
        "/usr/include/luajit-2.1",
    ]:
        if candidate and Path(candidate, "lua.h").exists():
            luajit = candidate
            break
    if not luajit:
        sys.exit("LuaJIT headers not found; set LUAJIT_INCLUDE")
    compiler = os.environ.get("CC") or shutil.which("clang") or shutil.which("cc") or shutil.which("gcc")
    # GCC 14 makes these legacy-C diagnostics errors; MSVC and clang only warn.
    legacy = ["-Wno-incompatible-pointer-types", "-Wno-int-conversion", "-Wno-implicit-function-declaration"]
    command = (
        [compiler, "-shared", "-fPIC", "-x", "c", "-std=c11", "-w"]
        + legacy
        + ["-I", str(HERE / "reader"), "-I", str(REPO / "sources"), "-I", luajit]
    )
    zlib = os.environ.get("ZLIB_PREFIX")  # zlib outside the compiler's default paths
    if zlib:
        command += ["-I", str(Path(zlib, "include")), "-L", str(Path(zlib, "lib"))]
    command += [str(HERE / "reader" / "module.c"), "-lz", "-o", str(output)]
    if sys.platform == "darwin":
        command[1:1] = ["-undefined", "dynamic_lookup"]
    subprocess.run(command, check=True)
    print("built", output)


if __name__ == "__main__":
    frames.run_main(main, "Gameplay frame tests")
