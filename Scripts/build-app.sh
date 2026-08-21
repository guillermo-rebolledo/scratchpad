#!/bin/sh
set -eu

script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
case "$script_path" in
    /*) ;;
    *) script_path="$PWD/$script_path" ;;
esac
while [ -L "$script_path" ]; do
    link_target="$(readlink "$script_path")"
    case "$link_target" in
        /*) script_path="$link_target" ;;
        *) script_path="$(dirname "$script_path")/$link_target" ;;
    esac
done
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
repository_directory="$(dirname "$script_directory")"
cd "$repository_directory"

configuration="${CONFIGURATION:-debug}"
output_directory="${THOUGHTBOX_OUTPUT_DIRECTORY:-$repository_directory/.build/app}"
app_path="$output_directory/Thoughtbox.app"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
marketing_version="${MARKETING_VERSION:-1.0-dev}"
build_number="${CURRENT_PROJECT_VERSION:-1}"

swift build -c "$configuration"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
cp "$binary_directory/Thoughtbox" "$app_path/Contents/MacOS/Thoughtbox"
ditto "$binary_directory/Sparkle.framework" "$app_path/Contents/Frameworks/Sparkle.framework"
xcrun xcstringstool compile Sources/Thoughtbox/Localizable.xcstrings \
    --output-directory "$app_path/Contents/Resources"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$marketing_version" "$app_path/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$app_path/Contents/Info.plist"
codesign --force --sign - --entitlements Resources/Thoughtbox.entitlements "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

printf '%s\n' "$app_path"
