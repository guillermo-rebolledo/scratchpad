#!/bin/sh
set -eu

: "${THOUGHTBOX_ALLOW_LOCAL_UPDATE_TEST:?Set THOUGHTBOX_ALLOW_LOCAL_UPDATE_TEST=1 on an isolated CI runner}"
: "${RELEASE_VERSION:?Set RELEASE_VERSION}"
: "${RELEASE_BUILD:?Set RELEASE_BUILD}"
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${SPARKLE_PRIVATE_KEY_PATH:?Set SPARKLE_PRIVATE_KEY_PATH}"
: "${SPARKLE_TOOLS_DIRECTORY:?Set SPARKLE_TOOLS_DIRECTORY}"
: "${THOUGHTBOX_RELEASE_KEYCHAIN:?Set THOUGHTBOX_RELEASE_KEYCHAIN}"
[ "$THOUGHTBOX_ALLOW_LOCAL_UPDATE_TEST" = "1" ]

case "$RELEASE_BUILD" in
    ''|*[!0-9]*|0*)
        printf '%s\n' "RELEASE_BUILD must not contain leading zeroes." >&2
        exit 64
        ;;
esac
if [ "$RELEASE_BUILD" -le 1 ]; then
    printf '%s\n' "RELEASE_BUILD must be at least 2 so the update fixture can use a lower build." >&2
    exit 64
fi

script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
repository_directory="$(dirname "$(dirname "$script_directory")")"
package_directory="${XCODE_CLONED_SOURCE_PACKAGES_DIRECTORY:-$repository_directory/.build/xcode-release-packages}"
release_directory="${RELEASE_OUTPUT_DIRECTORY:-$repository_directory/.build/release}"
candidate_zip="$release_directory/channel/Thoughtbox-$RELEASE_VERSION.zip"
[ -f "$candidate_zip" ] || {
    printf '%s\n' "Verified candidate archive not found: $candidate_zip" >&2
    exit 66
}

test_directory="$(mktemp -d /tmp/thoughtbox-update-pipeline.XXXXXX)"
fixture_archive="$test_directory/Previous.xcarchive"
fixture_zip="$test_directory/Thoughtbox-previous.zip"
stage_directory="$test_directory/stage"
tls_key="$test_directory/localhost.key"
tls_certificate="$test_directory/localhost.pem"
server_log="$test_directory/https-server.log"
server_pid=""
certificate_hash=""

cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
    fi
    if [ -n "$certificate_hash" ]; then
        security delete-certificate -Z "$certificate_hash" "$THOUGHTBOX_RELEASE_KEYCHAIN" >/dev/null 2>&1 || true
    fi
    rm -rf "$test_directory"
}
trap cleanup EXIT HUP INT TERM

fixture_build=$((RELEASE_BUILD - 1))
xcodebuild archive \
    -project "$repository_directory/Thoughtbox.xcodeproj" \
    -scheme Thoughtbox \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$fixture_archive" \
    -clonedSourcePackagesDirPath "$package_directory" \
    MARKETING_VERSION="0.0.0-update-fixture" \
    CURRENT_PROJECT_VERSION="$fixture_build" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"

fixture_app="$fixture_archive/Products/Applications/Thoughtbox.app"
codesign --verify --deep --strict --verbose=2 "$fixture_app"
ditto -c -k --sequesterRsrc --keepParent "$fixture_app" "$fixture_zip"

mkdir -p "$stage_directory"
cp "$repository_directory/appcast.xml" "$stage_directory/appcast.xml"
cp "$candidate_zip" "$stage_directory/$(basename "$candidate_zip")"
"$script_directory/sign-appcast.sh" \
    "$stage_directory" \
    "https://localhost:18443/" \
    "$SPARKLE_PRIVATE_KEY_PATH" \
    "$SPARKLE_TOOLS_DIRECTORY"
"$script_directory/verify-appcast.sh" \
    "$stage_directory/appcast.xml" \
    "$RELEASE_BUILD" \
    "https://localhost:18443/"

openssl req \
    -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -nodes \
    -days 1 \
    -subj '/CN=localhost' \
    -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
    -addext 'keyUsage=digitalSignature,keyEncipherment' \
    -addext 'extendedKeyUsage=serverAuth' \
    -keyout "$tls_key" \
    -out "$tls_certificate"
certificate_hash="$(
    openssl x509 -in "$tls_certificate" -noout -fingerprint -sha1 |
        cut -d= -f2 |
        tr -d :
)"
security add-trusted-cert \
    -r trustRoot \
    -k "$THOUGHTBOX_RELEASE_KEYCHAIN" \
    "$tls_certificate"

(
    cd "$stage_directory"
    exec openssl s_server \
        -accept 18443 \
        -cert "$tls_certificate" \
        -key "$tls_key" \
        -WWW \
        -quiet
) >"$server_log" 2>&1 &
server_pid=$!

attempt=0
until curl --fail --silent --show-error --cacert "$tls_certificate" \
    https://localhost:18443/appcast.xml >/dev/null
do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        printf '%s\n' "Local HTTPS update channel did not start:" >&2
        sed -n '1,120p' "$server_log" >&2
        exit 1
    fi
    sleep 1
done

"$script_directory/verify-staged-update.sh" \
    "$fixture_zip" \
    "https://localhost:18443/appcast.xml" \
    "$RELEASE_VERSION"
