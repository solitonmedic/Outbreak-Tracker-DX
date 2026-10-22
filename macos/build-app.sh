#!/bin/sh
set -eu
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# --debug builds a separate app whose reader also records EE-RAM checkpoints.
debug=0
case "${1:-}" in
  "") ;;
  --debug) debug=1 ;;
  *) echo "Usage: $0 [--debug]" >&2; exit 2 ;;
esac
if [ "$debug" = 1 ]; then
  app_dir="${OUTBREAK_APP_DIR:-$root_dir/Outbreak Status Tracker Debug.app}"
  build_prefix="$root_dir/macos/build-debug"
  build_type=RelWithDebInfo
  recorder_option=ON
else
  app_dir="${OUTBREAK_APP_DIR:-$root_dir/Outbreak Status Tracker.app}"
  build_prefix="$root_dir/macos/build"
  build_type=Release
  recorder_option=OFF
fi
love_app="${LOVE_APP:-/Applications/love.app}"
icon_source="$root_dir/sources/outbreak-tracker-icon-hd.png"
[ -d "$love_app" ] || { echo "LÖVE not found: $love_app" >&2; exit 1; }
[ -f "$icon_source" ] || { echo "App icon not found: $icon_source" >&2; exit 1; }

build_module() {
  arch="$1"
  build_dir="$build_prefix-$arch"
  pine_args=
  if [ -f "$build_dir/CMakeCache.txt" ]; then
    cached_source=$(sed -n 's#^CMAKE_HOME_DIRECTORY:INTERNAL=##p' "$build_dir/CMakeCache.txt")
    if [ "$cached_source" != "$root_dir/macos" ]; then
      rm -rf "$build_dir"
    fi
  fi
  if [ -d "$root_dir/macos/pine-source" ]; then
    pine_args="-DFETCHCONTENT_SOURCE_DIR_PINE=$root_dir/macos/pine-source"
  fi
  # shellcheck disable=SC2086
  cmake -S "$root_dir/macos" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE="$build_type" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DOUTBREAK_DEBUG_RECORDER="$recorder_option" \
    -DFETCHCONTENT_FULLY_DISCONNECTED="${FETCHCONTENT_FULLY_DISCONNECTED:-OFF}" \
    $pine_args
  cmake --build "$build_dir" --config "$build_type"
}

build_module arm64
build_module x86_64
native_module="$root_dir/macos/luaoutbreaktracker-universal.so"
lipo -create "$build_prefix-arm64/luaoutbreaktracker.so" \
  "$build_prefix-x86_64/luaoutbreaktracker.so" -output "$native_module"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/game" "$app_dir/Contents/Frameworks"
cp "$root_dir/macos/app/Info.plist" "$app_dir/Contents/Info.plist"
cp "$root_dir/macos/app/OutbreakStatusTracker" "$app_dir/Contents/MacOS/OutbreakStatusTracker"
chmod 755 "$app_dir/Contents/MacOS/OutbreakStatusTracker"
cp -R "$love_app" "$app_dir/Contents/Frameworks/love.app"
cp "$icon_source" "$app_dir/Contents/Resources/OutbreakTracker.png"
game_dir="$app_dir/Contents/Resources/game"
cp "$root_dir"/sources/*.lua "$game_dir/"
chmod -R u+w "$game_dir"
cp "$root_dir/sources/main.lua" "$game_dir/main_base.lua"
if [ "$debug" = 1 ]; then
  cp "$root_dir/macos/overrides/main.lua" "$game_dir/main_mac.lua"
  cp "$root_dir/macos/overrides/debug.lua" "$game_dir/main.lua"
  plutil -replace CFBundleName -string "Outbreak Status Tracker Debug" "$app_dir/Contents/Info.plist"
  plutil -replace CFBundleDisplayName -string "Outbreak Status Tracker Debug" "$app_dir/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "org.outbreaktracker.macos.debug" "$app_dir/Contents/Info.plist"
else
  cp "$root_dir/macos/overrides/main.lua" "$game_dir/main.lua"
fi
cp -R "$root_dir/assets" "$game_dir/assets"
cp "$native_module" "$game_dir/luaoutbreaktracker.so"
rm -f "$native_module"
plutil -lint "$app_dir/Contents/Info.plist"
echo "Built: $app_dir"
