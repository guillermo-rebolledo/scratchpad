#!/bin/sh
set -eu

script_directory="$(CDPATH= cd "$(dirname "$0")" && pwd)"
repository_directory="$(dirname "$script_directory")"
cd "$repository_directory"

configuration="${CONFIGURATION:-debug}"
output_directory="${THOUGHTBOX_OUTPUT_DIRECTORY:-$repository_directory/.build/app}"
app_path="$output_directory/Thoughtbox.app"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"

swift build -c "$configuration"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_directory/Thoughtbox" "$app_path/Contents/MacOS/Thoughtbox"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - --entitlements Resources/Thoughtbox.entitlements "$app_path"

printf '%s\n' "$app_path"
