#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    printf '%s\n' "Usage: $0 REPOSITORY_DIRECTORY" >&2
    exit 64
fi

repository_directory="$1"
for selection_source in \
    "$repository_directory/Sources/ThoughtboxSelectionHelper" \
    "$repository_directory/Sources/ThoughtboxSelectionSupport"
do
    if [ ! -d "$selection_source" ] || [ ! -r "$selection_source" ] || [ ! -x "$selection_source" ]; then
        printf '%s\n' "A required selection source directory is missing or unreadable: $selection_source" >&2
        exit 1
    fi
done

printf '%s\n' "Required selection source directories are readable."
