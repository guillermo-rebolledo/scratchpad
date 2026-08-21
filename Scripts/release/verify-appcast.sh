#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    printf '%s\n' "Usage: $0 APPCAST EXPECTED_BUILD HTTPS_DOWNLOAD_PREFIX" >&2
    exit 64
fi

appcast_path="$1"
expected_build="$2"
download_prefix="$3"
case "$download_prefix" in
    https://*/) ;;
    *)
        printf '%s\n' "The expected Sparkle download prefix must use HTTPS and end in a slash." >&2
        exit 64
        ;;
esac
script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"

xmllint --noout "$appcast_path"
builds="$(ruby "$script_directory/read-appcast-builds.rb" "$appcast_path")"
latest_build="$(printf '%s\n' "$builds" | tail -1)"
[ "$latest_build" = "$expected_build" ] || {
    printf '%s\n' "Latest appcast build is $latest_build, expected $expected_build." >&2
    exit 1
}

ruby -r rexml/document -e '
  path, expected_build, prefix = ARGV
  document = REXML::Document.new(File.read(path))
  matching = REXML::XPath.match(document, "//*[local-name()=\"item\"]").select do |item|
    version_element = item.elements.to_a.find { |child| child.name == "version" }
    enclosure = item.elements.to_a.find { |child| child.name == "enclosure" }
    attribute = enclosure&.attributes&.to_a&.find { |candidate| candidate.name == "version" }
    (version_element&.text || attribute&.value).to_s.strip == expected_build
  end
  abort "Expected exactly one appcast item for build #{expected_build}." unless matching.length == 1
  enclosure = matching.first.elements.to_a.find { |child| child.name == "enclosure" }
  abort "Build #{expected_build} has no enclosure." unless enclosure
  url = enclosure.attributes["url"].to_s
  abort "Update URL does not use the expected prefix." unless url.start_with?(prefix)
  signature = enclosure.attributes.to_a.find { |attribute| attribute.name == "edSignature" }&.value.to_s
  abort "Update archive has no EdDSA signature." if signature.empty?
  length = enclosure.attributes["length"].to_s
  abort "Update archive has no valid length." unless length.match?(/\A[1-9][0-9]*\z/)
' "$appcast_path" "$expected_build" "$download_prefix"

grep -F 'sparkle-signatures:' "$appcast_path" >/dev/null
grep -E 'edSignature: [A-Za-z0-9+/]+=*' "$appcast_path" >/dev/null
printf '%s\n' "Signed appcast verified: build $expected_build"
