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
trap 'rm -rf "$test_directory"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

"$script_directory/validate-https-prefix.rb" "https://updates.example.test/releases/"
for invalid_prefix in "https:///" "http://updates.example.test/" "https://user@updates.example.test/"; do
    if "$script_directory/validate-https-prefix.rb" "$invalid_prefix" >/dev/null 2>&1; then
        printf '%s\n' "Invalid download prefix unexpectedly passed: $invalid_prefix" >&2
        exit 1
    fi
done

fixture_archive="$test_directory/Thoughtbox.zip"
printf x >"$fixture_archive"

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
    if "$script_directory/verify-version-order.sh" "$fixture" 043 >/dev/null 2>&1; then
        printf '%s\n' "A leading-zero build unexpectedly passed: $fixture" >&2
        exit 1
    fi
    "$script_directory/verify-appcast.sh" \
        "$fixture" \
        42 \
        "https://updates.example.test/" >/dev/null
    "$script_directory/verify-appcast.sh" \
        "$fixture" \
        42 \
        "https://updates.example.test/" \
        "$fixture_archive" \
        "1.0.0" >/dev/null
done

printf xy >"$fixture_archive"
if "$script_directory/verify-appcast.sh" \
    "$repository_directory/Tests/ReleaseFixtures/appcast-element-version.xml" \
    42 \
    "https://updates.example.test/" \
    "$fixture_archive" \
    "1.0.0" >/dev/null 2>&1
then
    printf '%s\n' "A mismatched update archive length unexpectedly passed." >&2
    exit 1
fi

if "$script_directory/verify-appcast.sh" \
    "$repository_directory/Tests/ReleaseFixtures/appcast-element-version.xml" \
    42 \
    "" >/dev/null 2>&1
then
    printf '%s\n' "An empty download prefix unexpectedly passed." >&2
    exit 1
fi

invalid_signature_appcast="$test_directory/invalid-signature.xml"
cp "$repository_directory/Tests/ReleaseFixtures/appcast-element-version.xml" "$invalid_signature_appcast"
ruby -pi -e 'gsub(/sparkle:edSignature="[^"]+"/, %q[sparkle:edSignature="invalid"])' \
    "$invalid_signature_appcast"
if "$script_directory/verify-appcast.sh" \
    "$invalid_signature_appcast" \
    42 \
    "https://updates.example.test/" >/dev/null 2>&1
then
    printf '%s\n' "An invalid enclosure signature unexpectedly passed." >&2
    exit 1
fi

wrong_namespace_appcast="$test_directory/wrong-signature-namespace.xml"
cp "$repository_directory/Tests/ReleaseFixtures/appcast-element-version.xml" "$wrong_namespace_appcast"
ruby -pi -e 'gsub(/sparkle:edSignature=/, %q[other:edSignature=])' "$wrong_namespace_appcast"
if "$script_directory/verify-appcast.sh" \
    "$wrong_namespace_appcast" \
    42 \
    "https://updates.example.test/" >/dev/null 2>&1
then
    printf '%s\n' "A non-Sparkle signature attribute unexpectedly passed." >&2
    exit 1
fi

signed_archive="$test_directory/signed-archive.zip"
printf '%s\n' "signed artifact fixture" >"$signed_archive"
archive_signature="$(xcrun swift - "$signed_archive" <<'SWIFT'
import CryptoKit
import Foundation
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0, count: 32))
print(try key.signature(for: archive).base64EncodedString())
SWIFT
)"
"$script_directory/verify-update-signature.sh" \
    "$signed_archive" \
    "$archive_signature" \
    "O2onvM62pC1io6jQKm8Nc2UyFXcd4kOmOsBIoYtZ2ik=" >/dev/null
printf '%s\n' "tampered artifact" >>"$signed_archive"
if "$script_directory/verify-update-signature.sh" \
    "$signed_archive" \
    "$archive_signature" \
    "O2onvM62pC1io6jQKm8Nc2UyFXcd4kOmOsBIoYtZ2ik=" >/dev/null 2>&1
then
    printf '%s\n' "A tampered update archive unexpectedly passed signature verification." >&2
    exit 1
fi

signed_appcast="$test_directory/signed-appcast.xml"
printf '%s\n' '<rss version="2.0"><channel><title>Signed fixture</title></channel></rss>' >"$signed_appcast"
appcast_signature="$(xcrun swift - "$signed_appcast" <<'SWIFT'
import CryptoKit
import Foundation
let content = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0, count: 32))
print(try key.signature(for: content).base64EncodedString())
SWIFT
)"
appcast_length="$(stat -f '%z' "$signed_appcast")"
printf '%s\n' '<!-- sparkle-signatures:' "edSignature: $appcast_signature" \
    "length: $appcast_length" '-->' >>"$signed_appcast"
"$script_directory/verify-appcast-signature.sh" \
    "$signed_appcast" \
    "O2onvM62pC1io6jQKm8Nc2UyFXcd4kOmOsBIoYtZ2ik=" >/dev/null
appended_appcast="$test_directory/appended-signed-appcast.xml"
cp "$signed_appcast" "$appended_appcast"
printf '%s\n' '<!-- unauthenticated append -->' >>"$appended_appcast"
if "$script_directory/verify-appcast-signature.sh" \
    "$appended_appcast" \
    "O2onvM62pC1io6jQKm8Nc2UyFXcd4kOmOsBIoYtZ2ik=" >/dev/null 2>&1
then
    printf '%s\n' "Appended bytes after the signing block unexpectedly passed verification." >&2
    exit 1
fi
ruby -pi -e 'gsub(/Signed fixture/, "Tampered fixture")' "$signed_appcast"
if "$script_directory/verify-appcast-signature.sh" \
    "$signed_appcast" \
    "O2onvM62pC1io6jQKm8Nc2UyFXcd4kOmOsBIoYtZ2ik=" >/dev/null 2>&1
then
    printf '%s\n' "A tampered signed appcast unexpectedly passed verification." >&2
    exit 1
fi

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
