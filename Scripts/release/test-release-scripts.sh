#!/bin/sh
set -eu

script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
repository_directory="$(dirname "$(dirname "$script_directory")")"
test_directory="$(mktemp -d /tmp/thoughtbox-release-script-tests.XXXXXX)"
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

for fixture in \
    "$repository_directory/Tests/ReleaseFixtures/appcast-attribute-version.xml" \
    "$repository_directory/Tests/ReleaseFixtures/appcast-element-version.xml"
do
    "$script_directory/verify-version-order.sh" "$fixture" 43 >/dev/null
    if "$script_directory/verify-version-order.sh" "$fixture" 42 >/dev/null 2>&1; then
        printf '%s\n' "Duplicate build unexpectedly passed: $fixture" >&2
        exit 1
    fi
    if "$script_directory/verify-version-order.sh" "$fixture" 41 >/dev/null 2>&1; then
        printf '%s\n' "Decreasing build unexpectedly passed: $fixture" >&2
        exit 1
    fi
    "$script_directory/verify-appcast.sh" \
        "$fixture" \
        42 \
        "https://updates.example.test/" >/dev/null
done

test_app="$test_directory/Thoughtbox.app"
mkdir -p "$test_app/Contents"
cp "$repository_directory/Resources/Info.plist" "$test_app/Contents/Info.plist"
plutil -replace SUPublicEDKey -string 'O2onvM62pC1io6jQKm8Nc2UyFXcd4kOmOsBIoYtZ2ik=' \
    "$test_app/Contents/Info.plist"
printf '%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' >"$test_directory/matching-key"
printf '%s\n' 'AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' >"$test_directory/wrong-key"
"$script_directory/verify-update-key.sh" \
    "$test_app" \
    "$test_directory/matching-key" >/dev/null
if "$script_directory/verify-update-key.sh" \
    "$test_app" \
    "$test_directory/wrong-key" >/dev/null 2>&1
then
    printf '%s\n' "Mismatched Sparkle key unexpectedly passed." >&2
    exit 1
fi

printf '%s\n' "Release script regression tests passed."
