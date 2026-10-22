"""Reusable native build-tool setup; Python 3 standard library, on Steam Deck.
Inputs: pinned micromamba download/hash, optional sibling native-toolchain.lock.
Outputs: ~/.local/share/outbreak-tracker/toolchain and ~/.cache/outbreak-tracker/.
Safety: installs only user development tools; no sudo, OS changes, PINE or recordings.
Run from repo root on Deck: python3 decky/scripts/bootstrap_native.py
Check: prints compiler/CMake versions; writes toolchain.explicit.txt to the cache.
"""
import hashlib
import io
from pathlib import Path
import subprocess
import tarfile
import urllib.request


def setup():
    cache = Path.home() / ".cache/outbreak-tracker"
    cache.mkdir(parents=True, exist_ok=True)
    executable = cache / "micromamba-2.9.0"
    if not executable.exists():
        url = "https://api.anaconda.org/download/conda-forge/micromamba/2.9.0/linux-64/micromamba-2.9.0-0.tar.bz2"
        data = urllib.request.urlopen(url, timeout=120).read()
        if hashlib.sha256(data).hexdigest() != "8761c382127e6363bd9e0a2451aa3ef90d071a79133f736e2f759a3bf13040dd":
            raise RuntimeError("Micromamba download checksum mismatch")
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:bz2") as archive:
            executable.write_bytes(archive.extractfile("bin/micromamba").read())
        executable.chmod(0o755)
    prefix = Path.home() / ".local/share/outbreak-tracker/toolchain"
    lock = Path(__file__).resolve().parents[1] / "native-toolchain.lock"
    if not (prefix / "conda-meta/history").is_file():
        arguments = [str(executable), "--no-rc", "--root-prefix", str(cache / "mamba"), "create", "-y", "-p", str(prefix)]
        if lock.is_file():
            if "@EXPLICIT" not in lock.read_text().splitlines():
                raise RuntimeError("native-toolchain.lock must be an explicit lock: a line '@EXPLICIT', then one package URL per line")
            arguments += ["--file", str(lock)]
        else:
            arguments += ["-c", "conda-forge", "gxx_linux-64=14", "cmake=3.31", "make=4.4", "luajit=2.1", "python=3.12", "pillow=11"]
        subprocess.run(arguments, check=True)
    explicit = subprocess.check_output([str(executable), "--no-rc", "list", "-p", str(prefix), "--explicit"], text=True)
    (cache / "toolchain.explicit.txt").write_text(explicit)
    subprocess.run([str(prefix / "bin/x86_64-conda-linux-gnu-c++"), "--version"], check=True)
    subprocess.run([str(prefix / "bin/cmake"), "--version"], check=True)


if __name__ == "__main__":
    setup()
