"""Purpose: reusable guarded receiver for committed Decky Git bundles.
Location/runtime: decky/scripts/sync_checkout.py, Python 3 standard library plus Git.
Inputs: bundle path, destination path, expected commit; no environment options.
Outputs: a new clone or fast-forwarded checkout; .git/outbreak-tracker-sync marker.
Safety: changes only the named development checkout; refuses unrelated, dirty,
symlinked or diverged checkouts. No sudo, plugin installation, PINE or recordings.
Run from repo-merged/: python3 decky/scripts/deck.py sync (sends this committed script).
Check: printed HEAD matches the local commit; refusal leaves working files intact.
"""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile

BASE_COMMIT = "ec990de8879abc683ea9e854705baede323a7013"
MARKER = "outbreak-tracker-decky-v1\n"


def git(repo, *args, capture=False):
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
    ).stdout


def receive(bundle: Path, destination: Path, expected: str):
    if not bundle.is_file() or len(expected) != 40 or any(c not in "0123456789abcdef" for c in expected):
        raise RuntimeError("Invalid bundle or expected commit")
    heads = subprocess.check_output(["git", "bundle", "list-heads", str(bundle)], text=True)
    if f"{expected} refs/heads/Decky" not in heads.splitlines():
        raise RuntimeError("Bundle Decky branch differs from expected commit")
    if destination.is_symlink():
        raise RuntimeError("Refusing a symlink destination")

    if destination.exists():
        marker = destination / ".git/outbreak-tracker-sync"
        if not marker.is_file() or marker.read_text() != MARKER:
            raise RuntimeError("Destination is not a checkout created by this workflow")
        top = Path(git(destination, "rev-parse", "--show-toplevel", capture=True).strip())
        if top.resolve() != destination.resolve():
            raise RuntimeError("Destination is not the repository root")
        if git(destination, "branch", "--show-current", capture=True).strip() != "Decky":
            raise RuntimeError("Remote checkout must be on Decky")
        if git(destination, "status", "--porcelain", "--untracked-files=all", capture=True).strip():
            raise RuntimeError("Remote checkout has edits; commit or move them before synchronization")
        git(destination, "bundle", "verify", str(bundle))
        git(destination, "fetch", "--no-tags", str(bundle), "refs/heads/Decky")
        if git(destination, "rev-parse", "FETCH_HEAD", capture=True).strip() != expected:
            raise RuntimeError("Fetched commit differs from requested commit")
        ancestor = subprocess.run(["git", "-C", str(destination), "merge-base", "--is-ancestor", "HEAD", expected])
        if ancestor.returncode != 0:
            raise RuntimeError("Remote history diverged or is ahead; refusing to replace it")
        git(destination, "merge", "--ff-only", "--no-edit", expected)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".outbreak-clone-", dir=destination.parent) as temporary:
            staging = Path(temporary) / "checkout"
            subprocess.run(["git", "clone", "--branch", "Decky", str(bundle), str(staging)], check=True)
            git(staging, "merge-base", "--is-ancestor", BASE_COMMIT, expected)
            git(staging, "remote", "remove", "origin")
            (staging / ".git/outbreak-tracker-sync").write_text(MARKER)
            os.rename(staging, destination)
    actual = git(destination, "rev-parse", "HEAD", capture=True).strip()
    if actual != expected:
        raise RuntimeError("Checkout HEAD verification failed")
    print(f"Synchronized Decky at {actual}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("expected")
    options = parser.parse_args()
    try:
        receive(options.bundle.resolve(), options.destination, options.expected)
    except (RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Synchronization refused: {error}\n")
