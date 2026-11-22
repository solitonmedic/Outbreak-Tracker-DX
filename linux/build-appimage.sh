#!/bin/sh
# Builds OutbreakStatusTracker-x86_64.AppImage: the shared Lua UI, the assets and
# the native reader from linux/build go into the official LÖVE AppImage, which is
# renamed, given the tracker icon and the version from VERSION, and repacked.
# Build the reader first (BUILDING.md), then run: ./linux/build-appimage.sh
# LOVE_APPIMAGE and APPIMAGETOOL point at those downloads; OUTBREAK_APPIMAGE at the output.
# Check: the last line is "Built: <AppImage>".
set -eu

root_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${BUILD_DIR:-$root_dir/linux/build}
love_appimage=${LOVE_APPIMAGE:-$root_dir/linux/love-11.5-x86_64.AppImage}
appimagetool=${APPIMAGETOOL:-$root_dir/linux/appimagetool-x86_64.AppImage}
module="$build_dir/luaoutbreaktracker.so"
game_file="$build_dir/OutbreakStatusTracker.love"
output_file=${OUTBREAK_APPIMAGE:-$root_dir/OutbreakStatusTracker-x86_64.AppImage}
version=$(tr -d '[:space:]' < "$root_dir/VERSION")  # one release number for every platform

[ -x "$love_appimage" ] || { echo "LÖVE AppImage not found or not executable: $love_appimage" >&2; exit 1; }
[ -x "$appimagetool" ] || { echo "appimagetool not found or not executable: $appimagetool" >&2; exit 1; }
[ -f "$module" ] || { echo "Native reader not built: $module" >&2; exit 1; }

work_dir=$(mktemp -d "$root_dir/.outbreak-appimage.XXXXXX")
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT INT TERM

game_dir="$work_dir/game"
app_dir="$work_dir/squashfs-root"
mkdir -p "$game_dir"
cp "$root_dir"/sources/*.lua "$game_dir/"
cp "$root_dir/sources/main.lua" "$game_dir/main_base.lua"
cp "$root_dir/linux/overrides/main.lua" "$game_dir/main.lua"
cp -R "$root_dir/assets" "$game_dir/assets"
# The game's own map files (sampled locally, git-ignored) are not shipped: maps
# come from sources/MapGeometry.lua and the Evil Resource art.
rm -rf "${game_dir:?}/assets/maps/game"
cp "$module" "$game_dir/luaoutbreaktracker.so"
cmake -E chdir "$game_dir" cmake -E tar cf "$game_file" --format=zip .

(cd "$work_dir" && "$love_appimage" --appimage-extract >/dev/null)
cat "$app_dir/bin/love" "$game_file" > "$app_dir/bin/OutbreakStatusTracker"
chmod +x "$app_dir/bin/OutbreakStatusTracker"
rm -f "$app_dir/bin/love"
cp "$module" "$app_dir/bin/OutbreakStatusTracker.so"
cp "$module" "$app_dir/bin/luaoutbreaktracker.so"

sed -i 's#bin/love#bin/OutbreakStatusTracker#g' "$app_dir/AppRun"
sed -i 's#Exec=love#Exec=OutbreakStatusTracker#g; s#Icon=love#Icon=outbreak-tracker#g' "$app_dir/love.desktop"
sed -i '/^X-AppImage-Version=/d' "$app_dir/love.desktop"
sed -i "/^\[Desktop Entry\]/a X-AppImage-Version=$version" "$app_dir/love.desktop"
grep -qx "X-AppImage-Version=$version" "$app_dir/love.desktop" || { echo "Version not set in love.desktop" >&2; exit 1; }
cp "$root_dir/sources/outbreak-tracker-icon-hd.png" "$app_dir/outbreak-tracker.png"

rm -f "$output_file"
APPIMAGE_EXTRACT_AND_RUN=1 VERSION="$version" "$appimagetool" "$app_dir" "$output_file"
chmod +x "$output_file"
echo "Built: $output_file"
