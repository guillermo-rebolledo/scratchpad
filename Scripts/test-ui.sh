#!/bin/sh
set -eu

script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
repository_directory="$(dirname "$script_directory")"

xcodebuild \
    -project "$repository_directory/Thoughtbox.xcodeproj" \
    -scheme Thoughtbox \
    -destination 'platform=macOS' \
    test
