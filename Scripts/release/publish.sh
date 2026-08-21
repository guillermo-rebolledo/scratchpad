#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    printf '%s\n' "Usage: $0 VERSION UPDATE_ZIP APPCAST" >&2
    exit 64
fi

version="$1"
update_zip="$2"
generated_appcast="$3"
tag="thoughtbox-v$version"

for artifact in "$update_zip" "$generated_appcast"; do
    [ -f "$artifact" ] || {
        printf '%s\n' "Artifact not found: $artifact" >&2
        exit 66
    }
done
xmllint --noout "$generated_appcast"
grep -F 'sparkle:edSignature=' "$generated_appcast" >/dev/null

branch="$(git branch --show-current)"
[ "$branch" = "main" ] || {
    printf '%s\n' "Publish from main, not $branch." >&2
    exit 1
}
[ -z "$(git status --porcelain)" ] || {
    printf '%s\n' "Publish requires a clean worktree." >&2
    exit 1
}

gh release create "$tag" "$update_zip" \
    --repo guillermo-rebolledo/scratchpad \
    --title "Thoughtbox $version" \
    --generate-notes \
    --draft

printf '%s\n' "Draft release $tag created. Review it before publishing."
printf '%s\n' "After the archive URL is final, regenerate and commit $generated_appcast as appcast.xml."
