#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="$project_root/../outputs"
zsh "$project_root/Tools/build.sh"
zsh "$project_root/Tools/build.sh" --intel
for arch in Apple-Silicon Intel; do
  if [[ "$arch" == Apple-Silicon ]]; then app_name=CiBar.app; else app_name=CiBar-Intel.app; fi
  codesign --verify --deep --strict "$output_root/$app_name"
  ditto -c -k --sequesterRsrc --keepParent "$output_root/$app_name" "$output_root/CiBar-$arch.zip"
done
(cd "$output_root" && shasum -a 256 CiBar-Apple-Silicon.zip CiBar-Intel.zip > CiBar-SHA256SUMS.txt)
echo "Public app-only ZIPs and checksums created in $output_root. Personal state is not included."
