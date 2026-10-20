#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
build_dir="${SMART_MIDDLE_BUILD_DIR:-${TMPDIR:-/tmp}/smart-middle-build}"
mkdir -p "$build_dir/module-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$build_dir/module-cache" \
  "$project_dir/Sources/Core.swift" "$project_dir/Tests/main.swift" -o "$build_dir/CoreTests"
"$build_dir/CoreTests"
xcrun swiftc -swift-version 5 -module-cache-path "$build_dir/module-cache" -framework AppKit \
  "$project_dir/Sources/ScrollEventFactory.swift" "$project_dir/Tests/ScrollEvents/main.swift" -o "$build_dir/ScrollEventTests"
"$build_dir/ScrollEventTests"
