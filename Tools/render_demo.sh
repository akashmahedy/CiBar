#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
demo_root="$project_root/../outputs/promo/Renderer.app"
mkdir -p "$demo_root/Contents/MacOS" "$demo_root/Contents/Resources"
cp "$project_root/Resources/words.json" "$demo_root/Contents/Resources/"
sources=("$project_root"/Sources/*.swift)
sources=("${(@)sources:#*/main.swift}")
swiftc -swift-version 5 -O "${sources[@]}" "$project_root/Tools/Demo/main.swift" -o "$demo_root/Contents/MacOS/Renderer" -framework AppKit -framework AVFoundation -framework QuartzCore -framework ServiceManagement
"$demo_root/Contents/MacOS/Renderer" "$project_root/../outputs/promo"
