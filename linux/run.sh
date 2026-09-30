#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
love_bin=${LOVE_BIN:-love}
build_dir=${BUILD_DIR:-$root_dir/linux/build}
module="$build_dir/luaoutbreaktracker.so"
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

if [ "${LOVE_FLATPAK:-0}" = 1 ]; then
  love_runner="flatpak run --user --filesystem=home --filesystem=$runtime_dir org.love2d.love2d"
else
  command -v "$love_bin" >/dev/null 2>&1 || { echo "LÖVE was not found: $love_bin (set LOVE_BIN to its executable)" >&2; exit 1; }
  love_runner="$love_bin"
fi
[ -f "$module" ] || { echo "Native reader not built. Run: cmake --build $build_dir --config Release" >&2; exit 1; }

if [ "${LOVE_FLATPAK:-0}" = 1 ]; then
  game_dir=$(mktemp -d "$root_dir/.outbreak-tracker.XXXXXX")
else
  game_dir=$(mktemp -d "${TMPDIR:-/tmp}/outbreak-tracker.XXXXXX")
fi
cleanup() { rm -rf "$game_dir"; }
trap cleanup EXIT INT TERM

cp "$root_dir"/sources/*.lua "$game_dir/"
chmod -R u+w "$game_dir"
cp "$root_dir/sources/main.lua" "$game_dir/main_base.lua"
cp "$root_dir/linux/overrides/main.lua" "$game_dir/main.lua"
cp -R "$root_dir/assets" "$game_dir/assets"
cp "$module" "$game_dir/luaoutbreaktracker.so"
if [ "${LOVE_FLATPAK:-0}" = 1 ]; then
  exec flatpak run --user --filesystem=home --filesystem="$runtime_dir" org.love2d.love2d "$game_dir"
else
  exec "$love_runner" "$game_dir"
fi
