#!/bin/sh
set -eu

script_directory="$(CDPATH= cd "$(dirname "$0")" && pwd)"
repository_directory="$(dirname "$script_directory")"

xcodebuild \
    -project "$repository_directory/Thoughtbox.xcodeproj" \
    -scheme Thoughtbox \
    -destination 'platform=macOS' \
    test
