#!/bin/sh
set -eu

if [ "$#" -ne 3 ] && [ "$#" -ne 5 ]; then
    printf '%s\n' "Usage: $0 APPCAST EXPECTED_BUILD HTTPS_DOWNLOAD_PREFIX [ARCHIVE_BASENAME EXPECTED_VERSION]" >&2
    exit 64
fi

appcast_path="$1"
expected_build="$2"
download_prefix="$3"
archive_basename="${4:-}"
expected_version="${5:-}"
script_path="$0"
case "$script_path" in
    */*) ;;
    *) script_path="$(command -v "$script_path")" ;;
esac
script_directory="$(CDPATH= cd "$(dirname "$script_path")" && pwd)"
ruby "$script_directory/validate-https-prefix.rb" "$download_prefix"

xmllint --noout "$appcast_path"
builds="$(ruby "$script_directory/read-appcast-builds.rb" "$appcast_path")"
latest_build="$(printf '%s\n' "$builds" | tail -1)"
[ "$latest_build" = "$expected_build" ] || {
    printf '%s\n' "Latest appcast build is $latest_build, expected $expected_build." >&2
    exit 1
}

ruby -r rexml/document -r base64 -r uri -e '
  path, expected_build, prefix, archive_basename, expected_version = ARGV
  document = REXML::Document.new(File.read(path))
  sparkle_namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
  matching = REXML::XPath.match(document, "//*[local-name()=\"item\"]").select do |item|
    version_element = item.elements.to_a.find do |child|
      child.name == "version" && child.namespace == sparkle_namespace
    end
    enclosure = item.elements.to_a.find { |child| child.name == "enclosure" }
    attribute = enclosure&.attributes&.to_a&.find do |candidate|
      candidate.name == "version" && candidate.namespace == sparkle_namespace
    end
    (version_element&.text || attribute&.value).to_s.strip == expected_build
  end
  abort "Expected exactly one appcast item for build #{expected_build}." unless matching.length == 1
  enclosure = matching.first.elements.to_a.find { |child| child.name == "enclosure" }
  abort "Build #{expected_build} has no enclosure." unless enclosure
  url = enclosure.attributes["url"].to_s
  abort "Update URL does not use the expected prefix." unless url.start_with?(prefix)
  unless archive_basename.empty?
    begin
      url_basename = File.basename(URI.parse(url).path)
    rescue URI::InvalidURIError
      abort "Update URL is invalid."
    end
    abort "Update URL does not name the expected archive." unless url_basename == archive_basename
    version_element = matching.first.elements.to_a.find do |child|
      child.name == "shortVersionString" && child.namespace == sparkle_namespace
    end
    abort "Appcast item does not match the expected marketing version." unless
      version_element&.text.to_s.strip == expected_version
  end
  signature = enclosure.attributes.to_a.find do |attribute|
    attribute.name == "edSignature" && attribute.namespace == sparkle_namespace
  end&.value.to_s
  abort "Update archive has no EdDSA signature." if signature.empty?
  begin
    decoded_signature = Base64.strict_decode64(signature)
  rescue ArgumentError
    abort "Update archive has an invalid EdDSA signature."
  end
  abort "Update archive has an invalid EdDSA signature." unless decoded_signature.bytesize == 64
  length = enclosure.attributes["length"].to_s
  abort "Update archive has no valid length." unless length.match?(/\A[1-9][0-9]*\z/)
' "$appcast_path" "$expected_build" "$download_prefix" "$archive_basename" "$expected_version"

grep -F 'sparkle-signatures:' "$appcast_path" >/dev/null
grep -E 'edSignature: [A-Za-z0-9+/]{86}==' "$appcast_path" >/dev/null
printf '%s\n' "Signed appcast verified: build $expected_build"
