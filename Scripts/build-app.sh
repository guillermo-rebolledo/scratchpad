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
case "$configuration" in
    debug)
        signing_identity="-"
        ;;
    release)
        : "${DEVELOPER_ID_APPLICATION:?Set the full Developer ID Application identity for release assembly}"
        security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID_APPLICATION" >/dev/null || {
            printf '%s\n' "Developer ID Application identity is not installed: $DEVELOPER_ID_APPLICATION" >&2
            exit 1
        }
        signing_identity="$DEVELOPER_ID_APPLICATION"
        ;;
    *)
        printf '%s\n' "CONFIGURATION must be debug or release." >&2
        exit 64
        ;;
esac
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
marketing_version="${MARKETING_VERSION:-1.0-dev}"
build_number="${CURRENT_PROJECT_VERSION:-1}"

swift build -c "$configuration"
rm -rf "$app_path"
helper_path="$app_path/Contents/XPCServices/ThoughtboxSelectionHelper.xpc"
mkdir -p \
    "$app_path/Contents/MacOS" \
    "$app_path/Contents/Resources" \
    "$app_path/Contents/Frameworks" \
    "$helper_path/Contents/MacOS"
cp "$binary_directory/Thoughtbox" "$app_path/Contents/MacOS/Thoughtbox"
cp "$binary_directory/ThoughtboxSelectionHelper" \
    "$helper_path/Contents/MacOS/ThoughtboxSelectionHelper"
cp Resources/SelectionHelper-Info.plist "$helper_path/Contents/Info.plist"
plutil -replace CFBundleDevelopmentRegion -string en "$helper_path/Contents/Info.plist"
plutil -replace CFBundleExecutable -string ThoughtboxSelectionHelper "$helper_path/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.memoji.Thoughtbox.SelectionHelper "$helper_path/Contents/Info.plist"
plutil -replace CFBundleName -string ThoughtboxSelectionHelper "$helper_path/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$marketing_version" "$helper_path/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$helper_path/Contents/Info.plist"
ditto "$binary_directory/Sparkle.framework" "$app_path/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$app_path/Contents/MacOS/Thoughtbox"
xcrun xcstringstool compile Sources/Thoughtbox/Localizable.xcstrings \
    --output-directory "$app_path/Contents/Resources"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$marketing_version" "$app_path/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$app_path/Contents/Info.plist"
if [ "$configuration" = "release" ]; then
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$helper_path"
    codesign --force --options runtime --timestamp --sign "$signing_identity" \
        --entitlements Resources/Thoughtbox.entitlements "$app_path"
    helper_team="$(codesign -d --verbose=4 "$helper_path" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
    app_team="$(codesign -d --verbose=4 "$app_path" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
    if [ -z "$app_team" ] || [ "$helper_team" != "$app_team" ]; then
        printf '%s\n' "Release app and selection helper must share a non-empty Team ID." >&2
        exit 1
    fi
else
    codesign --force --sign "$signing_identity" "$helper_path"
    codesign --force --sign "$signing_identity" \
        --entitlements Resources/Thoughtbox.entitlements "$app_path"
fi
codesign --verify --deep --strict --verbose=2 "$app_path"

printf '%s\n' "$app_path"
