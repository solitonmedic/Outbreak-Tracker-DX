#!/bin/sh
# Purpose: run the Terminal debug reader (dev branch only) through LÖVE. Lines
# typed here become run markers. Build the reader first:
#   cmake -S macos/debug -B macos/terminal-build-debug-arm64 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_OSX_ARCHITECTURES=arm64
#   cmake --build macos/terminal-build-debug-arm64 --config RelWithDebInfo
# Run from the repository root: ./macos/debug/run.sh (see macos/debug/README.md).
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
love_bin="${LOVE_BIN:-/Applications/love.app/Contents/MacOS/love}"
build_dir="$root_dir/macos/terminal-build-debug-arm64"
module="$build_dir/luaoutbreaktracker.so"
[ $# -eq 0 ] || { echo "Usage: $0" >&2; exit 2; }

[ -x "$love_bin" ] || { echo "LÖVE not found: $love_bin" >&2; exit 1; }
[ -f "$module" ] || {
  echo "Debug reader not built. Run: cmake --build ${build_dir#"$root_dir/"}" >&2
  exit 1
}

game_dir=$(mktemp -d "${TMPDIR:-/tmp}/outbreak-tracker-debug.XXXXXX")
cleanup() { rm -rf "$game_dir"; }
trap cleanup EXIT INT TERM

cp "$root_dir"/sources/*.lua "$game_dir/"
chmod -R u+w "$game_dir"
cp "$root_dir/sources/main.lua" "$game_dir/main_base.lua"
cp "$root_dir/macos/overrides/main.lua" "$game_dir/main_mac.lua"
cp "$root_dir/macos/debug/main.lua" "$game_dir/main.lua"
cp -R "$root_dir/assets" "$game_dir/assets"
# The game's own map files (sampled locally, git-ignored) are not shipped.
rm -rf "${game_dir:?}/assets/maps/game"
cp "$module" "$game_dir/luaoutbreaktracker.so"

exec "$love_bin" "$game_dir"
