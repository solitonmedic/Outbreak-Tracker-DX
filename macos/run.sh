#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
love_bin="${LOVE_BIN:-/Applications/love.app/Contents/MacOS/love}"
module="$root_dir/macos/terminal-build-arm64/luaoutbreaktracker.so"

[ -x "$love_bin" ] || { echo "LÖVE not found: $love_bin" >&2; exit 1; }
[ -f "$module" ] || {
  echo "Native reader not built. Run: cmake --build macos/terminal-build-arm64" >&2
  exit 1
}

game_dir=$(mktemp -d "${TMPDIR:-/tmp}/outbreak-tracker.XXXXXX")
cleanup() { rm -rf "$game_dir"; }
trap cleanup EXIT INT TERM

cp "$root_dir"/sources/*.lua "$game_dir/"
chmod -R u+w "$game_dir"
cp "$root_dir/sources/main.lua" "$game_dir/main_base.lua"
cp "$root_dir/macos/overrides/main.lua" "$game_dir/main.lua"
cp -R "$root_dir/assets" "$game_dir/assets"
cp "$module" "$game_dir/luaoutbreaktracker.so"

exec "$love_bin" "$game_dir"
