#!/usr/bin/env ruby
# frozen_string_literal: true

require "rexml/document"

abort "Usage: #{$PROGRAM_NAME} APPCAST" unless ARGV.length == 1

document = REXML::Document.new(File.read(ARGV.fetch(0)))
sparkle_namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
builds = []
REXML::XPath.each(document, "//*[local-name()='item']") do |item|
  item.elements.each do |child|
    if child.name == "version" && child.namespace == sparkle_namespace
      value = child.text.to_s.strip
      builds << Integer(value, 10) if value.match?(/\A[0-9]+\z/)
    end
    next unless child.name == "enclosure"

    child.attributes.each_attribute do |attribute|
      next unless attribute.name == "version" && attribute.namespace == sparkle_namespace

      value = attribute.value.to_s.strip
      builds << Integer(value, 10) if value.match?(/\A[0-9]+\z/)
    end
  end
end
puts builds.uniq.sort
