#!/bin/sh
set -eu

xcodebuild \
    -project Thoughtbox.xcodeproj \
    -scheme Thoughtbox \
    -destination 'platform=macOS' \
    test
