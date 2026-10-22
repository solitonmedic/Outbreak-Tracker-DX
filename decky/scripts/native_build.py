"""Reusable native reader build; Python 3, user CMake/GCC/Pillow toolchain on Deck.
Inputs: existing shared sources/, linux/ build and assets; pinned PINE revision.
Outputs: ignored .artifacts/native/ module/metrics/license and cmake-build/ inside the checkout
(CMake caches the source path, so each checkout needs its own build folder); the PINE source
and LuaJIT headers are cached under ~/.cache/outbreak-tracker/native.
Safety: offline compilation only; no running game, PINE connection or recordings.
Run from repo root: python3 decky/scripts/native_build.py (also called by build.py).
Check: native module links and fontmetrics.lua plus PINE license are produced.
"""
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

PINE_REVISION = "d2fddf7e4c1c155b1bc0d37f2dbf2da8754387a7"


def build_native():
    plugin = Path(__file__).resolve().parents[1]
    repo = plugin.parent
    prefix = Path.home() / ".local/share/outbreak-tracker/toolchain"
    cache = Path.home() / ".cache/outbreak-tracker/native"
    cache.mkdir(parents=True, exist_ok=True)
    pine = cache / ("pine-" + PINE_REVISION)
    if not pine.is_dir():
        data = urllib.request.urlopen("https://codeload.github.com/GovanifY/pine/tar.gz/" + PINE_REVISION, timeout=120).read()
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            archive.extractall(cache, filter="data")
    headers = cache / "luajit-headers/src"
    if not headers.exists():
        shutil.copytree(prefix / "include/luajit-2.1", headers)
    output = plugin / ".artifacts/native"
    output.mkdir(parents=True, exist_ok=True)
    build = output / "cmake-build"
    env = dict(os.environ)
    env["PATH"] = str(prefix / "bin") + os.pathsep + env.get("PATH", "")
    subprocess.run([
        str(prefix / "bin/cmake"), "-S", str(repo / "linux"), "-B", str(build),
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_CXX_COMPILER=" + str(prefix / "bin/x86_64-conda-linux-gnu-c++"),
        "-DCMAKE_MAKE_PROGRAM=" + str(prefix / "bin/make"),
        "-DCMAKE_MODULE_LINKER_FLAGS=-static-libstdc++ -static-libgcc",
        "-DFETCHCONTENT_SOURCE_DIR_PINE=" + str(pine),
        "-DFETCHCONTENT_SOURCE_DIR_LUAJIT=" + str(headers.parent),
    ], env=env, check=True)
    with (output / "build.log").open("w") as log:
        result = subprocess.run([str(prefix / "bin/cmake"), "--build", str(build), "--parallel", "2"], env=env, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((output / "build.log").read_text()[-6000:])
        raise RuntimeError("Native build failed; see .artifacts/native/build.log")
    shutil.copy2(build / "luaoutbreaktracker.so", output)
    license_file = next(p for p in pine.iterdir() if p.name.lower().startswith("license"))
    shutil.copy2(license_file, output / "PINE-LICENSE")
    subprocess.run([str(prefix / "bin/python"), str(plugin / "scripts/font_metrics.py"), str(repo / "assets"), str(output / "fontmetrics.lua")], check=True)


if __name__ == "__main__":
    build_native()
