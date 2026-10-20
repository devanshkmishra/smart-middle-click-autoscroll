#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
build_dir="${SMART_MIDDLE_BUILD_DIR:-${TMPDIR:-/tmp}/smart-middle-click-autoscroll-build}"
mkdir -p "$build_dir/module-cache"
iconset="$build_dir/AppIcon.iconset"
xcrun swiftc -module-cache-path "$build_dir/module-cache" -framework AppKit \
  "$project_dir/scripts/generate-icon.swift" -o "$build_dir/GenerateIcon"
"$build_dir/GenerateIcon" "$iconset"
iconutil -c icns "$iconset" -o "$project_dir/Resources/AppIcon.icns"
cp "$iconset/icon_512x512@2x.png" "$project_dir/Resources/AppIcon.png"
print "Generated Resources/AppIcon.icns and Resources/AppIcon.png"
