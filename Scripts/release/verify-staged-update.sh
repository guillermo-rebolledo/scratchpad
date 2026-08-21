#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    printf '%s\n' "Usage: $0 PREVIOUS_RELEASE_ZIP STAGED_HTTPS_APPCAST EXPECTED_VERSION" >&2
    exit 64
fi

previous_zip="$1"
staged_appcast="$2"
expected_version="$3"
case "$staged_appcast" in
    https://*) ;;
    *)
        printf '%s\n' "The staged appcast must use HTTPS." >&2
        exit 64
        ;;
esac

script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
repository_directory="$(dirname "$(dirname "$script_directory")")"
test_directory="$(mktemp -d /tmp/thoughtbox-clean-update.XXXXXX)"
installed_directory=""
cleanup() {
    rm -rf "$test_directory"
    if [ -n "$installed_directory" ]; then
        rm -rf "$installed_directory"
    fi
}
trap cleanup EXIT HUP INT TERM
installed_directory="$(mktemp -d '/Applications/Thoughtbox-Update-Test.XXXXXX')"
installed_app="$installed_directory/Thoughtbox.app"

ditto -x -k "$previous_zip" "$test_directory"
source_app="$(find "$test_directory" -maxdepth 2 -type d -name 'Thoughtbox.app' -print -quit)"
[ -n "$source_app" ] || {
    printf '%s\n' "The previous release archive does not contain Thoughtbox.app." >&2
    exit 1
}
ditto "$source_app" "$installed_app"
xattr -dr com.apple.quarantine "$installed_app" 2>/dev/null || true

xcodebuild \
    -project "$repository_directory/Thoughtbox.xcodeproj" \
    -scheme Thoughtbox \
    -destination 'platform=macOS' \
    -clonedSourcePackagesDirPath "${XCODE_CLONED_SOURCE_PACKAGES_DIRECTORY:-$repository_directory/.build/xcode-release-packages}" \
    -disableAutomaticPackageResolution \
    -only-testing:ThoughtboxUITests/ThoughtboxRealAppAcceptanceTests/testStagedSparkleUpdatePreservesAllLocalData \
    THOUGHTBOX_RUN_UPDATE_TEST=1 \
    THOUGHTBOX_APP_PATH="$installed_app" \
    THOUGHTBOX_STAGED_APPCAST_URL="$staged_appcast" \
    THOUGHTBOX_EXPECTED_UPDATE_VERSION="$expected_version" \
    test
