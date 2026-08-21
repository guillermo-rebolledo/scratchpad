#!/bin/sh
set -eu

script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
repository_directory="$(dirname "$(dirname "$script_directory")")"

: "${RELEASE_VERSION:?Set RELEASE_VERSION, for example 1.0.0-beta.1}"
: "${RELEASE_BUILD:?Set RELEASE_BUILD to a monotonically increasing integer}"
: "${DEVELOPER_ID_APPLICATION:?Set the full Developer ID Application identity}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${NOTARY_KEY_PATH:?Set NOTARY_KEY_PATH to an App Store Connect API .p8 file}"
: "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID}"
: "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID}"
: "${SPARKLE_PRIVATE_KEY_PATH:?Set SPARKLE_PRIVATE_KEY_PATH to a protected EdDSA seed file}"
: "${THOUGHTBOX_DOWNLOAD_URL_PREFIX:?Set the HTTPS archive download URL prefix}"

case "$THOUGHTBOX_DOWNLOAD_URL_PREFIX" in
    https://*) ;;
    *)
        printf '%s\n' "THOUGHTBOX_DOWNLOAD_URL_PREFIX must use HTTPS." >&2
        exit 64
        ;;
esac

for secret_path in "$NOTARY_KEY_PATH" "$SPARKLE_PRIVATE_KEY_PATH"; do
    [ -f "$secret_path" ] || {
        printf '%s\n' "Protected release credential not found: $secret_path" >&2
        exit 66
    }
done

security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID_APPLICATION" >/dev/null || {
    printf '%s\n' "Developer ID Application identity is not installed: $DEVELOPER_ID_APPLICATION" >&2
    exit 1
}

output_directory="${RELEASE_OUTPUT_DIRECTORY:-$repository_directory/.build/release}"
package_directory="${XCODE_CLONED_SOURCE_PACKAGES_DIRECTORY:-$repository_directory/.build/xcode-release-packages}"
archive_path="$output_directory/Thoughtbox.xcarchive"
channel_directory="$output_directory/channel"
notary_json="$output_directory/notary.json"
notary_log="$output_directory/notary-log.json"
submission_zip="$output_directory/Thoughtbox-notarization.zip"
update_zip="$channel_directory/Thoughtbox-$RELEASE_VERSION.zip"
app_path="$archive_path/Products/Applications/Thoughtbox.app"

mkdir -p "$output_directory" "$channel_directory"
"$script_directory/verify-version-order.sh" "$repository_directory/appcast.xml" "$RELEASE_BUILD"

xcodebuild archive \
    -project "$repository_directory/Thoughtbox.xcodeproj" \
    -scheme Thoughtbox \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive_path" \
    -clonedSourcePackagesDirPath "$package_directory" \
    MARKETING_VERSION="$RELEASE_VERSION" \
    CURRENT_PROJECT_VERSION="$RELEASE_BUILD" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"

"$script_directory/verify-app.sh" "$app_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_zip"
xcrun notarytool submit "$submission_zip" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait \
    --output-format json >"$notary_json"

notary_status="$(plutil -extract status raw "$notary_json")"
submission_id="$(plutil -extract id raw "$notary_json")"
if [ "$notary_status" != "Accepted" ]; then
    xcrun notarytool log "$submission_id" \
        --key "$NOTARY_KEY_PATH" \
        --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER_ID" >"$notary_log" || true
    printf '%s\n' "Notarization was not accepted. See $notary_log" >&2
    exit 1
fi

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
"$script_directory/verify-app.sh" "$app_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$update_zip"
cp "$repository_directory/appcast.xml" "$channel_directory/appcast.xml"

sparkle_tool="$(find "$repository_directory/.build" -type d -path '*/Sparkle.framework/Versions/*' -prune -o -type f -name generate_appcast -perm -111 -print 2>/dev/null | head -1 || true)"
sparkle_tools_directory=""
if [ -n "$sparkle_tool" ]; then
    sparkle_tools_directory="$(dirname "$sparkle_tool")"
fi
if [ -z "$sparkle_tools_directory" ]; then
    sparkle_tools_directory="${SPARKLE_TOOLS_DIRECTORY:-}"
fi
[ -x "$sparkle_tools_directory/generate_appcast" ] || {
    printf '%s\n' "Sparkle generate_appcast tool was not found. Set SPARKLE_TOOLS_DIRECTORY." >&2
    exit 1
}

"$sparkle_tools_directory/generate_appcast" \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" \
    --download-url-prefix "$THOUGHTBOX_DOWNLOAD_URL_PREFIX" \
    "$channel_directory"
"$sparkle_tools_directory/sign_update" \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" \
    "$channel_directory/appcast.xml"
"$sparkle_tools_directory/sign_update" \
    --verify \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" \
    "$channel_directory/appcast.xml"

xmllint --noout "$channel_directory/appcast.xml"
grep -F 'sparkle:edSignature=' "$channel_directory/appcast.xml" >/dev/null
grep -F "sparkle:version=\"$RELEASE_BUILD\"" "$channel_directory/appcast.xml" >/dev/null
grep -F "$THOUGHTBOX_DOWNLOAD_URL_PREFIX" "$channel_directory/appcast.xml" >/dev/null

printf '%s\n' "Accepted notarization: $submission_id"
printf '%s\n' "Signed update archive: $update_zip"
printf '%s\n' "Signed appcast: $channel_directory/appcast.xml"
