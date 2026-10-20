#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
output_dir="${SMART_MIDDLE_OUTPUT_DIR:-$project_dir/dist}"
version="$(<"$project_dir/VERSION")"
archive="Smart-Middle-Click-Autoscroll-$version-universal.zip"
"$project_dir/scripts/build.sh"
ditto -c -k --sequesterRsrc --keepParent "$output_dir/Smart Middle Click Autoscroll.app" "$output_dir/$archive"
(cd "$output_dir" && shasum -a 256 "$archive" > SHA256SUMS.txt)
print "Packaged: $output_dir/$archive"
