#!/bin/sh
set -eu

script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
case "$script_path" in
    /*) ;;
    *) script_path="$PWD/$script_path" ;;
esac
while [ -L "$script_path" ]; do
    link_target="$(readlink "$script_path")"
    case "$link_target" in
        /*) script_path="$link_target" ;;
        *) script_path="$(dirname "$script_path")/$link_target" ;;
    esac
done
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
repository_directory="$(dirname "$script_directory")"

set -- xcodebuild \
    -project "$repository_directory/Thoughtbox.xcodeproj" \
    -scheme Thoughtbox \
    -destination 'platform=macOS' \
    -retry-tests-on-failure \
    -test-iterations 3

if [ -n "${XCODE_CLONED_SOURCE_PACKAGES_DIRECTORY:-}" ]; then
    set -- "$@" -clonedSourcePackagesDirPath "$XCODE_CLONED_SOURCE_PACKAGES_DIRECTORY"
fi

set -- "$@" test
"$@"
