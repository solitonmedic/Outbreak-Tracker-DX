"""Purpose: reusable native Steam Deck frontend build and installable ZIP packager.
Location/runtime: decky/scripts/build.py; Python 3, Git, nvm Node 24.19.0/Corepack.
Inputs: clean committed checkout, --expect-commit, package/lockfile, frontend/backend;
network for pinned pnpm/dependencies. No environment options beyond normal home/cache.
Outputs: ignored decky/dist and decky/.artifacts/ZIP plus JSON build report.
Safety: writes build artifacts and user caches only; no sudo, installation, PINE,
settings edits, game memory, recordings or workbook access.
Run from repo-merged/ on Deck: python3 decky/scripts/build.py --expect-commit $(git rev-parse HEAD)
Check: compilation/typecheck pass; report and ZIP metadata identify expected HEAD.
"""

import argparse
import ast
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import zipfile

NODE_VERSION = "24.19.0"
PNPM_VERSION = "9.15.9"


def build(expected):
    plugin = Path(__file__).resolve().parents[1]
    repo = plugin.parent
    commit = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    branch = subprocess.check_output(["git", "-C", str(repo), "branch", "--show-current"], text=True).strip()
    dirty = subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain", "--untracked-files=all"], text=True)
    if commit != expected or branch != "Decky" or dirty.strip():
        raise RuntimeError("Build requires a clean Decky checkout at the expected commit")
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise RuntimeError("This build command targets the x86_64 Steam Deck")

    node_bin = Path.home() / f".nvm/versions/node/v{NODE_VERSION}/bin"
    node = node_bin / "node"
    corepack = node_bin / "corepack"
    env = dict(os.environ)
    env["PATH"] = str(node_bin) + os.pathsep + env.get("PATH", "")
    env["COREPACK_HOME"] = str(Path.home() / ".cache/outbreak-tracker/corepack")
    env["COREPACK_ENABLE_DOWNLOAD_PROMPT"] = "0"
    env["CI"] = "true"
    actual_node = subprocess.check_output([str(node), "--version"], text=True).strip()
    if actual_node != f"v{NODE_VERSION}" or not corepack.is_file():
        raise RuntimeError("Pinned Node/Corepack is unavailable; run the doctor command")
    pnpm = [str(corepack), f"pnpm@{PNPM_VERSION}"]
    actual_pnpm = subprocess.check_output([*pnpm, "--version"], cwd=plugin, env=env, text=True).strip()
    if actual_pnpm != PNPM_VERSION:
        raise RuntimeError("Unexpected pnpm version")
    for arguments in (("install", "--frozen-lockfile"), ("run", "typecheck"), ("run", "build")):
        subprocess.run([*pnpm, *arguments], cwd=plugin, env=env, check=True)
    ast.parse((plugin / "main.py").read_text(), filename="main.py")
    if subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain", "--untracked-files=all"], text=True).strip():
        raise RuntimeError("Build unexpectedly changed source files")

    package = json.loads((plugin / "package.json").read_text())
    metadata = {
        "version": package["version"], "sourceCommit": commit,
        "builtAtUtc": datetime.now(timezone.utc).isoformat(),
    }
    output = plugin / ".artifacts"
    output.mkdir(exist_ok=True)
    archive_name = f"outbreak-tracker-{package['version']}-{commit[:12]}.zip"
    archive_path = output / archive_name
    required = {"dist/index.js", "main.py", "plugin.json", "package.json", "LICENSE", "README.md", "build-info.json"}
    paths = [plugin / name for name in required - {"build-info.json", "dist/index.js"}]
    paths += sorted((plugin / "dist").rglob("*"))
    with tempfile.NamedTemporaryFile(dir=output, suffix=".zip.partial", delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        with zipfile.ZipFile(temporary_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in paths:
                if path.is_symlink():
                    raise RuntimeError("Refusing to package a symlink")
                if path.is_file():
                    archive.write(path, "outbreak-tracker/" + path.relative_to(plugin).as_posix())
            archive.writestr("outbreak-tracker/build-info.json", json.dumps(metadata, indent=2) + "\n")
        with zipfile.ZipFile(temporary_path) as archive:
            names = {name.removeprefix("outbreak-tracker/") for name in archive.namelist()}
            if not required.issubset(names) or archive.testzip() is not None:
                raise RuntimeError("ZIP content verification failed")
            if json.loads(archive.read("outbreak-tracker/build-info.json"))["sourceCommit"] != expected:
                raise RuntimeError("ZIP commit verification failed")
        temporary_path.replace(archive_path)
    finally:
        temporary_path.unlink(missing_ok=True)
    report = {
        **metadata, "platform": platform.platform(), "architecture": platform.machine(),
        "node": actual_node, "pnpm": actual_pnpm,
        "archive": archive_name, "sha256": hashlib.sha256(archive_path.read_bytes()).hexdigest(),
        "checks": ["frontend typecheck", "frontend build", "Python syntax", "ZIP contents and CRC", "source commit"],
        "installed": False, "userRun": False, "inGameVerified": False,
    }
    report_path = output / "build-report.json"
    partial_report = output / "build-report.json.partial"
    partial_report.write_text(json.dumps(report, indent=2) + "\n")
    partial_report.replace(report_path)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expect-commit", required=True)
    options = parser.parse_args()
    try:
        build(options.expect_commit)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Build stopped: {error}\n")
