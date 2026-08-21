#!/bin/sh
set -eu

script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"

if [ "$#" -ne 1 ]; then
    printf '%s\n' "Usage: $0 PATH_TO_THOUGHTBOX_APP" >&2
    exit 64
fi

app_path="$(CDPATH= cd "$(dirname "$1")" && pwd)/$(basename "$1")"
if [ ! -d "$app_path" ]; then
    printf '%s\n' "App not found: $app_path" >&2
    exit 66
fi

info_path="$app_path/Contents/Info.plist"
entitlements_path="$(mktemp /tmp/thoughtbox-entitlements.XXXXXX.plist)"
nested_entitlements_path="$entitlements_path.nested"
trap 'rm -f "$entitlements_path" "$nested_entitlements_path"' EXIT HUP INT TERM

codesign --verify --deep --strict --verbose=4 "$app_path"
signature_details="$(codesign -d --verbose=4 "$app_path" 2>&1)"
printf '%s\n' "$signature_details" | grep -F "Authority=Developer ID Application:" >/dev/null
printf '%s\n' "$signature_details" | grep -E 'flags=.*runtime' >/dev/null
expected_authority="$(printf '%s\n' "$signature_details" | sed -n 's/^Authority=//p' | head -1)"

codesign -d --entitlements :- "$app_path" >"$entitlements_path" 2>/dev/null
plutil -convert json -o - "$entitlements_path" |
    ruby "$script_directory/verify-entitlements.rb" app

feed_url="$(plutil -extract SUFeedURL raw "$info_path")"
case "$feed_url" in
    https://*) ;;
    *)
        printf '%s\n' "Sparkle feed URL must use HTTPS." >&2
        exit 1
        ;;
esac
public_key="$(plutil -extract SUPublicEDKey raw "$info_path")"
decoded_key_length="$(printf '%s' "$public_key" | base64 -D | wc -c | tr -d ' ')"
[ "$decoded_key_length" = "32" ] || {
    printf '%s\n' "Sparkle public EdDSA key is invalid." >&2
    exit 1
}
[ "$(plutil -extract SUEnableAutomaticChecks raw -expect bool "$info_path")" = "true" ]
[ "$(plutil -extract SUEnableInstallerLauncherService raw -expect bool "$info_path")" = "true" ]
[ "$(plutil -extract SUSendProfileInfo raw -expect bool "$info_path")" = "false" ]

verify_nested_code() {
    nested_code="$1"
    codesign --verify --strict --verbose=2 "$nested_code"
    nested_signature="$(codesign -d --verbose=4 "$nested_code" 2>&1)"
    printf '%s\n' "$nested_signature" | grep -F "Authority=$expected_authority" >/dev/null
    printf '%s\n' "$nested_signature" | grep -E 'flags=.*runtime' >/dev/null
    codesign -d --entitlements :- "$nested_code" >"$nested_entitlements_path" 2>/dev/null
    if [ -s "$nested_entitlements_path" ]; then
        plutil -convert json -o - "$nested_entitlements_path" |
            ruby "$script_directory/verify-entitlements.rb" nested "$nested_code"
    fi
}

find "$app_path/Contents" -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' \) -print |
while IFS= read -r nested_code; do
    verify_nested_code "$nested_code"
done

find "$app_path/Contents/Frameworks" -type f -perm -111 -print |
while IFS= read -r executable; do
    if file "$executable" | grep -F 'Mach-O' >/dev/null; then
        verify_nested_code "$executable"
    fi
done

printf '%s\n' "Release app security verified: $app_path"
