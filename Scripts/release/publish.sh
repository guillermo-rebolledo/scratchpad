#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
    printf '%s\n' "Usage: $0 VERSION UPDATE_ZIP APPCAST SOURCE_COMMIT_FILE" >&2
    exit 64
fi

version="$1"
update_zip="$2"
generated_appcast="$3"
source_commit_file="$4"
tag="thoughtbox-v$version"
script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
repository_directory="$(dirname "$(dirname "$script_directory")")"
release_notes="$repository_directory/docs/releases/$version.md"
case "$version" in
    ''|*[!0-9A-Za-z.-]*|.*|*..*|*.)
        printf '%s\n' "VERSION must contain only letters, numbers, dots, and hyphens without empty path-like segments." >&2
        exit 64
        ;;
esac

for artifact in "$update_zip" "$generated_appcast" "$source_commit_file"; do
    [ -f "$artifact" ] || {
        printf '%s\n' "Artifact not found: $artifact" >&2
        exit 66
    }
done
[ -f "$release_notes" ] || {
    printf '%s\n' "Reviewed release notes not found: $release_notes" >&2
    exit 66
}
verification_directory="$(mktemp -d /tmp/thoughtbox-publish-verification.XXXXXX)"
trap 'rm -rf "$verification_directory"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
ditto -x -k "$update_zip" "$verification_directory"
archived_app="$(find "$verification_directory" -maxdepth 2 -type d -name 'Thoughtbox.app' -print -quit)"
[ -n "$archived_app" ] || {
    printf '%s\n' "The update archive does not contain Thoughtbox.app." >&2
    exit 1
}
archive_info="$archived_app/Contents/Info.plist"
archive_version="$(plutil -extract CFBundleShortVersionString raw "$archive_info")"
archive_build="$(plutil -extract CFBundleVersion raw "$archive_info")"
[ "$archive_version" = "$version" ] || {
    printf '%s\n' "The update archive version is $archive_version, expected $version." >&2
    exit 1
}
"$script_directory/verify-appcast.sh" \
    "$generated_appcast" \
    "$archive_build" \
    "https://github.com/guillermo-rebolledo/scratchpad/releases/download/$tag/" \
    "$update_zip" \
    "$archive_version"
archive_signature="$(
    ruby "$script_directory/read-appcast-update-signature.rb" \
        "$generated_appcast" \
        "$archive_build" \
        "$(basename "$update_zip")"
)"
archive_public_key="$(plutil -extract SUPublicEDKey raw "$archive_info")"
"$script_directory/verify-update-signature.sh" \
    "$update_zip" \
    "$archive_signature" \
    "$archive_public_key"
"$script_directory/verify-appcast-signature.sh" "$generated_appcast" "$archive_public_key"
source_commit="$(tr -d '\r\n' <"$source_commit_file" | tr 'A-F' 'a-f')"
case "$source_commit" in
    *[!0-9a-fA-F]*|'')
        printf '%s\n' "The source commit evidence is not a hexadecimal Git commit ID." >&2
        exit 64
        ;;
esac
[ "${#source_commit}" -eq 40 ] || {
    printf '%s\n' "The source commit evidence must contain a full 40-character commit ID." >&2
    exit 64
}

branch="$(git branch --show-current)"
[ "$branch" = "main" ] || {
    printf '%s\n' "Publish from main, not $branch." >&2
    exit 1
}
[ -z "$(git status --porcelain)" ] || {
    printf '%s\n' "Publish requires a clean worktree." >&2
    exit 1
}
resolved_source_commit="$(git rev-parse --verify "$source_commit^{commit}")"
[ "$resolved_source_commit" = "$source_commit" ] || {
    printf '%s\n' "The source commit evidence does not resolve exactly in this checkout." >&2
    exit 1
}
git merge-base --is-ancestor "$source_commit" main || {
    printf '%s\n' "The artifact source commit is not part of local main." >&2
    exit 1
}
remote_source_commit="$(gh api "repos/guillermo-rebolledo/scratchpad/commits/$source_commit" --jq .sha)"
[ "$remote_source_commit" = "$source_commit" ] || {
    printf '%s\n' "GitHub does not contain the exact artifact source commit." >&2
    exit 1
}
remote_main_commit="$(gh api repos/guillermo-rebolledo/scratchpad/branches/main --jq .commit.sha)"
remote_main_status="$(
    gh api "repos/guillermo-rebolledo/scratchpad/compare/$source_commit...$remote_main_commit" --jq .status
)"
case "$remote_main_status" in
    ahead|identical) ;;
    *)
        printf '%s\n' "The artifact source commit is not part of GitHub's main branch." >&2
        exit 1
        ;;
esac

gh release create "$tag" "$update_zip" \
    --repo guillermo-rebolledo/scratchpad \
    --target "$source_commit" \
    --title "Thoughtbox $version" \
    --notes-file "$release_notes" \
    --draft

printf '%s\n' "Draft release $tag created. Review it before publishing."
printf '%s\n' "After publishing the draft and confirming the archive URL works, commit $generated_appcast as appcast.xml."
