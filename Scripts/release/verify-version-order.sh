#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf '%s\n' "Usage: $0 APPCAST CANDIDATE_BUILD" >&2
    exit 64
fi

appcast_path="$1"
candidate_build="$2"
case "$candidate_build" in
    ''|*[!0-9]*)
        printf '%s\n' "Release build number must be a positive integer." >&2
        exit 64
        ;;
esac
if [ "$candidate_build" -le 0 ]; then
    printf '%s\n' "Release build number must be greater than zero." >&2
    exit 64
fi

xmllint --noout "$appcast_path"
script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
builds="$(ruby "$script_directory/read-appcast-builds.rb" "$appcast_path")"
highest_build="$(printf '%s\n' "$builds" | tail -1)"
highest_build="${highest_build:-0}"

if [ "$candidate_build" -le "$highest_build" ]; then
    printf '%s\n' "Build $candidate_build must be newer than appcast build $highest_build." >&2
    exit 1
fi

printf '%s\n' "Version ordering verified: $candidate_build > $highest_build"
