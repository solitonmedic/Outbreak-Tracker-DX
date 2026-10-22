"""Purpose: reusable Mac-to-Steam-Deck development driver for doctor/sync/build/fetch.
Location/runtime: decky/scripts/deck.py; Python 3 standard library, Git, SSH and SCP.
Inputs: command, --host (default steamdeck), --checkout (absolute remote path),
committed Decky HEAD and source; uses configured SSH authentication, never passwords.
Outputs: guarded Deck checkout; ignored local .artifacts bundle, ZIP and build report.
Safety: doctor is read-only; sync/build write only development paths and user caches.
No sudo, plugin installation, PINE connection, recordings or workbook access.
Run from repo-merged/: python3 decky/scripts/deck.py doctor|sync|build|fetch
Check: sync prints matching HEAD; build passes; fetch validates the ZIP SHA-256.
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shlex
import subprocess
import tempfile
import uuid

PLUGIN = Path(__file__).resolve().parents[1]
REPO = PLUGIN.parent
SSH_OPTIONS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]


def local_git(*args):
    return subprocess.check_output(["git", "-C", str(REPO), *args], text=True).strip()


def clean_commit():
    if local_git("branch", "--show-current") != "Decky":
        raise RuntimeError("Local checkout must be on Decky")
    if local_git("status", "--porcelain", "--untracked-files=all", "--", "decky"):
        raise RuntimeError("Commit plugin changes before synchronization or builds")
    return local_git("rev-parse", "HEAD")


def remote(options, args, **kwargs):
    return subprocess.run(["ssh", *SSH_OPTIONS, options.host, shlex.join(map(str, args))], check=True, **kwargs)


def main(options):
    if not options.checkout.startswith("/") or ".." in PurePosixPath(options.checkout).parts:
        raise RuntimeError("Use an absolute remote checkout path without '..'")
    if options.host.startswith("-"):
        raise RuntimeError("Invalid SSH host")
    if options.command == "doctor":
        source = '''import json, pathlib, platform, shutil, subprocess
h = pathlib.Path.home()
n = h / ".nvm/versions/node/v24.19.0/bin"
print(json.dumps({"home": str(h), "system": platform.system(), "architecture": platform.machine(),
"node": subprocess.check_output([str(n / "node"), "--version"], text=True).strip() if (n / "node").is_file() else None,
"corepack": (n / "corepack").is_file(), "git": shutil.which("git"),
"python": platform.python_version(), "freeGiB": round(shutil.disk_usage(h).free / 2**30, 1),
"pcsx2AppImage": (h / "Applications/pcsx2-Qt.AppImage").is_file(),
"loader": subprocess.run(["systemctl", "is-active", "plugin_loader.service"], capture_output=True, text=True).stdout.strip()}, indent=2))
'''
        remote(options, ["python3", "-c", source])
        return
    commit = clean_commit()
    checkout = PurePosixPath(options.checkout)
    if options.command == "sync":
        output = PLUGIN / ".artifacts"
        output.mkdir(exist_ok=True)
        remote_bundle = f"/home/deck/.cache/outbreak-tracker-sync/{uuid.uuid4().hex}.bundle.part"
        with tempfile.TemporaryDirectory(prefix="sync-", dir=output) as temporary:
            bundle = Path(temporary) / "Decky.bundle"
            subprocess.run(["git", "-C", str(REPO), "bundle", "create", str(bundle), "refs/heads/Decky"], check=True)
            helper = local_git("show", "HEAD:decky/scripts/sync_checkout.py")
            remote(options, ["mkdir", "-p", str(PurePosixPath(remote_bundle).parent)])
            try:
                subprocess.run(["scp", *SSH_OPTIONS, str(bundle), f"{options.host}:{remote_bundle}"], check=True)
                remote(options, ["python3", "-", remote_bundle, checkout, commit], input=helper, text=True)
            finally:
                remote(options, ["rm", "-f", remote_bundle])
    elif options.command == "build":
        remote(options, ["python3", checkout / "decky/scripts/build.py", "--expect-commit", commit])
    elif options.command == "fetch":
        remote_output = checkout / "decky/.artifacts"
        result = remote(options, ["cat", remote_output / "build-report.json"], capture_output=True, text=True)
        report = json.loads(result.stdout)
        name = report["archive"]
        expected_name = f"outbreak-tracker-0.1.0-{commit[:12]}.zip"
        version = json.loads((PLUGIN / "package.json").read_text())["version"]
        expected_name = f"outbreak-tracker-{version}-{commit[:12]}.zip"
        if report["sourceCommit"] != commit or name != expected_name:
            raise RuntimeError("Remote artifact does not match the local source commit/version")
        output = PLUGIN / ".artifacts"
        output.mkdir(exist_ok=True)
        partial = output / (name + ".partial")
        try:
            subprocess.run(["scp", *SSH_OPTIONS, f"{options.host}:{remote_output / name}", str(partial)], check=True)
            if hashlib.sha256(partial.read_bytes()).hexdigest() != report["sha256"]:
                raise RuntimeError("Downloaded archive SHA-256 mismatch")
            partial.replace(output / name)
        finally:
            partial.unlink(missing_ok=True)
        (output / "build-report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Verified archive: {output / name}\nSource commit: {commit}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["doctor", "sync", "build", "fetch"])
    parser.add_argument("--host", default="steamdeck")
    parser.add_argument("--checkout", default="/home/deck/Projects/Outbreak-Tracker-DX")
    try:
        main(parser.parse_args())
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        parser.exit(1, f"Deck workflow stopped: {error}\n")
