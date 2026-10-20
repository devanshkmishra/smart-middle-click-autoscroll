#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
output_dir="${SMART_MIDDLE_OUTPUT_DIR:-$project_dir/dist}"
build_dir="${SMART_MIDDLE_BUILD_DIR:-${TMPDIR:-/tmp}/smart-middle-click-autoscroll-build}"
app_name="Smart Middle Click Autoscroll"
executable="SmartMiddleClickAutoscroll"
version="$(<"$project_dir/VERSION")"
bundle="$output_dir/$app_name.app"
mkdir -p "$build_dir/module-cache" "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx13.0" \
    -module-cache-path "$build_dir/module-cache" \
    -framework AppKit -framework ApplicationServices -framework ServiceManagement \
    "$project_dir"/Sources/*.swift -o "$build_dir/$executable-$arch"
done
xcrun lipo -create "$build_dir/$executable-arm64" "$build_dir/$executable-x86_64" -output "$build_dir/$executable"
install -m 755 "$build_dir/$executable" "$bundle/Contents/MacOS/$executable.new"
mv -f "$bundle/Contents/MacOS/$executable.new" "$bundle/Contents/MacOS/$executable"
cp "$project_dir/Resources/Help.html" "$project_dir/TestPage.html" "$project_dir/LICENSE" "$bundle/Contents/Resources/"
cp "$project_dir/Resources/AppIcon.icns" "$bundle/Contents/Resources/"
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$executable</string>
<key>CFBundleIdentifier</key><string>io.github.devanshkmishra.smartmiddleclickautoscroll</string>
<key>CFBundleName</key><string>$app_name</string>
<key>CFBundleDisplayName</key><string>$app_name</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccessibilityUsageDescription</key><string>Preserve native middle clicks on links and controls, and autoscroll other content.</string>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
print "Built: $bundle"
