#!/usr/bin/env ruby
# frozen_string_literal: true

require "rexml/document"

abort "Usage: #{$PROGRAM_NAME} APPCAST" unless ARGV.length == 1

document = REXML::Document.new(File.read(ARGV.fetch(0)))
builds = []
REXML::XPath.each(document, "//*") do |element|
  if element.name == "version"
    value = element.text.to_s.strip
    builds << Integer(value, 10) if value.match?(/\A[0-9]+\z/)
  end
  element.attributes.each_attribute do |attribute|
    next unless attribute.name == "version"

    value = attribute.value.to_s.strip
    builds << Integer(value, 10) if value.match?(/\A[0-9]+\z/)
  end
end
puts builds.uniq.sort
