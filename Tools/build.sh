#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/../outputs/CiBar-build"
build_arch="${1:-arm64}"
if [[ "$build_arch" == "arm64" ]]; then
  app_root="$project_root/../outputs/CiBar.app"
elif [[ "$build_arch" == "--intel" ]]; then
  build_arch="x86_64"
  app_root="$project_root/../outputs/CiBar-Intel.app"
else
  echo "Usage: build.sh [--intel]" >&2
  exit 1
fi
mkdir -p "$build_root" "$app_root/Contents/MacOS" "$app_root/Contents/Resources"
swiftc -swift-version 5 -O -target "$build_arch-apple-macos13.0" "$project_root"/Sources/*.swift -o "$build_root/CiBar-$build_arch" -framework AppKit -framework QuartzCore -framework ServiceManagement
cp "$build_root/CiBar-$build_arch" "$app_root/Contents/MacOS/CiBar"
cp "$project_root/Resources/words.json" "$project_root/Resources/ATTRIBUTIONS.txt" "$project_root/Resources/DATA-REVIEW.json" "$project_root/Resources/HSK4-CORRECTIONS-REVIEW.json" "$app_root/Contents/Resources/"
cp "$project_root/Info.plist" "$app_root/Contents/Info.plist"
if [[ "$build_arch" == "x86_64" ]]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.cibar.intel' "$app_root/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName CíBar Intel' "$app_root/Contents/Info.plist"
fi
if [[ -f "$project_root/Resources/AppIcon.icns" ]]; then cp "$project_root/Resources/AppIcon.icns" "$app_root/Contents/Resources/"; fi
codesign --force --deep --sign - "$app_root"
if [[ "$build_arch" == "arm64" ]]; then "$app_root/Contents/MacOS/CiBar" --self-test; fi
echo "Built $app_root"
