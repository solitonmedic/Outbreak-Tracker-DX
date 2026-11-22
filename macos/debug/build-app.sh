#!/bin/sh
# Purpose: build "Outbreak Status Tracker Debug.app" (dev branch only), a test
# build whose reader also records EE-RAM runs. It runs macos/build-app.sh with
# this folder's CMake project (the normal reader plus sources/PineRecorder.cpp),
# then installs macos/debug/main.lua as the game's main.lua and renames the app.
# Prerequisites and checks: macos/debug/README.md.
# Run from the repository root: ./macos/debug/build-app.sh
set -eu
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
[ $# -eq 0 ] || { echo "Usage: $0" >&2; exit 2; }
app_dir="${OUTBREAK_APP_DIR:-$root_dir/Outbreak Status Tracker Debug.app}"

OUTBREAK_APP_DIR="$app_dir" \
OUTBREAK_BUILD_PREFIX="$root_dir/macos/build-debug" \
OUTBREAK_BUILD_TYPE=RelWithDebInfo \
OUTBREAK_CMAKE_SOURCE="$root_dir/macos/debug" \
  "$root_dir/macos/build-app.sh"

game_dir="$app_dir/Contents/Resources/game"
mv "$game_dir/main.lua" "$game_dir/main_mac.lua"
cp "$root_dir/macos/debug/main.lua" "$game_dir/main.lua"
plist="$app_dir/Contents/Info.plist"
plutil -replace CFBundleName -string "Outbreak Status Tracker Debug" "$plist"
plutil -replace CFBundleDisplayName -string "Outbreak Status Tracker Debug" "$plist"
plutil -replace CFBundleIdentifier -string "org.outbreaktracker.macos.debug" "$plist"
plutil -lint "$plist"
echo "Built debug app: $app_dir"
