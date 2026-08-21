#!/usr/bin/env ruby
# frozen_string_literal: true

require "uri"

abort "Usage: #{$PROGRAM_NAME} HTTPS_DOWNLOAD_PREFIX" unless ARGV.length == 1

prefix = ARGV.fetch(0)
begin
  uri = URI.parse(prefix)
rescue URI::InvalidURIError
  abort "The Sparkle download prefix is not a valid URL."
end

valid = uri.scheme == "https" &&
  !uri.host.to_s.empty? &&
  uri.userinfo.nil? &&
  uri.query.nil? &&
  uri.fragment.nil? &&
  uri.path.end_with?("/")
abort "The Sparkle download prefix must be a host-qualified HTTPS directory URL." unless valid
