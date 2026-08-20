#!/bin/sh
set -eu

configuration="${CONFIGURATION:-debug}"
output_directory="${THOUGHTBOX_OUTPUT_DIRECTORY:-$PWD/.build/app}"
app_path="$output_directory/Thoughtbox.app"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"

swift build -c "$configuration"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_directory/Thoughtbox" "$app_path/Contents/MacOS/Thoughtbox"
cp Resources/Info.plist "$app_path/Contents/Info.plist"

printf '%s\n' "$app_path"

