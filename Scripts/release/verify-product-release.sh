#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf '%s\n' "Usage: $0 DERIVED_DATA_DIRECTORY RELEASE_NOTES" >&2
    exit 64
fi

derived_data="$1"
release_notes="$2"
script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
repository_directory="$(dirname "$(dirname "$script_directory")")"
sources="$repository_directory/Sources/Thoughtbox"
catalog="$sources/Localizable.xcstrings"

[ -d "$derived_data" ] || {
    printf '%s\n' "Derived data directory not found: $derived_data" >&2
    exit 66
}
[ -f "$release_notes" ] || {
    printf '%s\n' "Release notes not found: $release_notes" >&2
    exit 66
}

strings_data_list="$(mktemp /tmp/thoughtbox-stringsdata.XXXXXX)"
temporary_directory="$(mktemp -d /tmp/thoughtbox-product-release.XXXXXX)"
trap 'rm -f "$strings_data_list"; rm -rf "$temporary_directory"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

find "$derived_data/Build/Intermediates.noindex/Thoughtbox.build" \
    -path '*/Thoughtbox.build/Objects-normal/*/*.stringsdata' \
    -type f \
    -print >"$strings_data_list"
[ -s "$strings_data_list" ] || {
    printf '%s\n' "No Thoughtbox compiler localization metadata was found." >&2
    exit 1
}

temporary_catalog="$temporary_directory/Localizable.xcstrings"
cp "$catalog" "$temporary_catalog"
set --
while IFS= read -r strings_data; do
    set -- "$@" "$strings_data"
done <"$strings_data_list"
xcrun xcstringstool sync "$temporary_catalog" --stringsdata "$@"
cmp -s "$catalog" "$temporary_catalog" || {
    printf '%s\n' "Localizable.xcstrings is stale. Build, sync the Thoughtbox .stringsdata files, and commit the result." >&2
    diff -u "$catalog" "$temporary_catalog" || true
    exit 1
}

python3 - "$catalog" <<'PY'
import json
import sys

catalog = json.load(open(sys.argv[1], encoding="utf-8"))
if catalog.get("sourceLanguage") != "en":
    raise SystemExit("The beta localization catalog must declare English as its source language.")
for key, value in catalog.get("strings", {}).items():
    localizations = value.get("localizations", {})
    unexpected = sorted(set(localizations) - {"en"})
    if unexpected:
        raise SystemExit(f"English-only beta contains unexpected localizations for {key!r}: {unexpected}")
PY

if grep -RInE 'URLSession|WKWebView|import[[:space:]]+(Network|WebKit)|NSSharingService|Telemetry|Analytics|Crashlytics|Sentry' \
    "$sources" --include='*.swift'; then
    printf '%s\n' "An unapproved network, telemetry, or sharing API was found in app source." >&2
    exit 1
fi
if grep -RInE 'Logger\(|os_log|NSLog\(|(^|[^[:alnum:]_])print\(' \
    "$sources" \
    "$repository_directory/Sources/ThoughtboxSelectionHelper" \
    "$repository_directory/Sources/ThoughtboxSelectionSupport" \
    --include='*.swift'; then
    printf '%s\n' "App source must not emit Thought content or other product data to logs." >&2
    exit 1
fi
if grep -RInE 'withAnimation|\.animation\(' "$sources" --include='*.swift'; then
    printf '%s\n' "Animation requires an explicit Reduce Motion implementation and release review." >&2
    exit 1
fi
if grep -RInE 'Color\((red:|hue:|#[0-9A-Fa-f])|NSColor\((red:|hue:)' \
    "$sources" --include='*.swift'; then
    printf '%s\n' "Custom colors require an explicit contrast audit before release." >&2
    exit 1
fi
if grep -RInE 'TODO|FIXME|Lorem ipsum|Coming soon|placeholder copy|TBD' \
    "$sources" "$catalog"; then
    printf '%s\n' "Placeholder or development copy was found in the shipped interface." >&2
    exit 1
fi

dependency_urls="$(grep -Eo 'https://[^" ]+' "$repository_directory/Package.swift" | sort -u)"
expected_dependency_urls="$(printf '%s\n' \
    'https://github.com/sparkle-project/Sparkle.git' \
    'https://github.com/swiftlang/swift-markdown.git' | sort -u)"
[ "$dependency_urls" = "$expected_dependency_urls" ] || {
    printf '%s\n' "The release dependency allowlist changed; perform a privacy and security review." >&2
    printf '%s\n' "$dependency_urls" >&2
    exit 1
}

for required_copy in \
    'macOS 14 or later' \
    'free, unlisted beta' \
    'stores its library locally' \
    'Portable Markdown export' \
    'Images' \
    'Import is not available' \
    'Sync between Macs is not available' \
    'Check for Updates'
do
    grep -Fqi "$required_copy" "$release_notes" || {
        printf '%s\n' "Release notes are missing required disclosure: $required_copy" >&2
        exit 1
    }
done

printf '%s\n' "Product release, localization, accessibility-policy, and privacy gates passed."
