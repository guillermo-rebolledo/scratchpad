#!/usr/bin/env ruby
# frozen_string_literal: true

require "rexml/document"
require "uri"

abort "Usage: #{$PROGRAM_NAME} APPCAST BUILD ARCHIVE_BASENAME" unless ARGV.length == 3

path, expected_build, archive_basename = ARGV
sparkle_namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
document = REXML::Document.new(File.read(path))
matching = []
REXML::XPath.each(document, "//*[local-name()='item']") do |item|
  version_element = item.elements.to_a.find do |child|
    child.name == "version" && child.namespace == sparkle_namespace
  end
  enclosure = item.elements.to_a.find { |child| child.name == "enclosure" }
  version_attribute = enclosure&.attributes&.to_a&.find do |attribute|
    attribute.name == "version" && attribute.namespace == sparkle_namespace
  end
  next unless enclosure
  next unless (version_element&.text || version_attribute&.value).to_s.strip == expected_build
  next unless File.basename(URI.parse(enclosure.attributes["url"].to_s).path) == archive_basename

  signature = enclosure.attributes.to_a.find do |attribute|
    attribute.name == "edSignature" && attribute.namespace == sparkle_namespace
  end&.value
  matching << signature if signature
end

abort "Expected exactly one matching signed appcast enclosure." unless matching.length == 1
puts matching.first
