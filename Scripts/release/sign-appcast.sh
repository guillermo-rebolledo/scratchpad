#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
    printf '%s\n' "Usage: $0 ARCHIVES_DIRECTORY HTTPS_DOWNLOAD_PREFIX PRIVATE_KEY SPARKLE_TOOLS_DIRECTORY" >&2
    exit 64
fi

archives_directory="$1"
download_prefix="$2"
private_key_path="$3"
sparkle_tools_directory="$4"

case "$download_prefix" in
    https://*/) ;;
    *)
        printf '%s\n' "The Sparkle download prefix must use HTTPS and end in a slash." >&2
        exit 64
        ;;
esac
[ -d "$archives_directory" ]
[ -f "$private_key_path" ]
[ -x "$sparkle_tools_directory/generate_appcast" ]
[ -x "$sparkle_tools_directory/sign_update" ]

if ! generation_output="$(
    "$sparkle_tools_directory/generate_appcast" \
        --ed-key-file "$private_key_path" \
        --download-url-prefix "$download_prefix" \
        "$archives_directory" 2>&1
)"; then
    printf '%s\n' "$generation_output" >&2
    exit 1
fi
printf '%s\n' "$generation_output"
if printf '%s\n' "$generation_output" | grep -F 'does not match key EdDSA' >/dev/null; then
    printf '%s\n' "The protected Sparkle private key does not match SUPublicEDKey in the archived app." >&2
    exit 1
fi

"$sparkle_tools_directory/sign_update" \
    --ed-key-file "$private_key_path" \
    "$archives_directory/appcast.xml"
"$sparkle_tools_directory/sign_update" \
    --verify \
    --ed-key-file "$private_key_path" \
    "$archives_directory/appcast.xml"
