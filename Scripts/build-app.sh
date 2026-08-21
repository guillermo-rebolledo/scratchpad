#!/bin/sh
set -eu

script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
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
