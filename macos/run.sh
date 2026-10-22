#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
love_bin="${LOVE_BIN:-/Applications/love.app/Contents/MacOS/love}"

# --debug runs the recording reader built in macos/terminal-build-debug-arm64
# (cmake -DOUTBREAK_DEBUG_RECORDER=ON); lines typed here become run markers.
debug=0
case "${1:-}" in
  "") ;;
  --debug) debug=1 ;;
  *) echo "Usage: $0 [--debug]" >&2; exit 2 ;;
esac
if [ "$debug" = 1 ]; then
  build_dir="$root_dir/macos/terminal-build-debug-arm64"
else
  build_dir="$root_dir/macos/terminal-build-arm64"
fi
module="$build_dir/luaoutbreaktracker.so"

[ -x "$love_bin" ] || { echo "LÖVE not found: $love_bin" >&2; exit 1; }
[ -f "$module" ] || {
  echo "Native reader not built. Run: cmake --build ${build_dir#"$root_dir/"}" >&2
  exit 1
}

game_dir=$(mktemp -d "${TMPDIR:-/tmp}/outbreak-tracker.XXXXXX")
cleanup() { rm -rf "$game_dir"; }
trap cleanup EXIT INT TERM

cp "$root_dir"/sources/*.lua "$game_dir/"
chmod -R u+w "$game_dir"
cp "$root_dir/sources/main.lua" "$game_dir/main_base.lua"
if [ "$debug" = 1 ]; then
  cp "$root_dir/macos/overrides/main.lua" "$game_dir/main_mac.lua"
  cp "$root_dir/macos/overrides/debug.lua" "$game_dir/main.lua"
else
  cp "$root_dir/macos/overrides/main.lua" "$game_dir/main.lua"
fi
cp -R "$root_dir/assets" "$game_dir/assets"
cp "$module" "$game_dir/luaoutbreaktracker.so"

exec "$love_bin" "$game_dir"
