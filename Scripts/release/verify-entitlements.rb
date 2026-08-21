#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

mode = ARGV.shift
entitlements = JSON.parse($stdin.read)
abort "Entitlements must be a dictionary." unless entitlements.is_a?(Hash)

get_task_allow = "com.apple.security.get-task-allow"

case mode
when "app"
  required = %w[
    com.apple.security.app-sandbox
    com.apple.security.files.user-selected.read-write
    com.apple.security.network.client
  ]
  required.each do |entitlement|
    abort "Required entitlement is missing: #{entitlement}" unless entitlements[entitlement] == true
  end

  abort "Release app must not include get-task-allow." if entitlements.key?(get_task_allow)

  mach_entitlement = "com.apple.security.temporary-exception.mach-lookup.global-name"
  expected_mach_names = %w[com.memoji.Thoughtbox-spki com.memoji.Thoughtbox-spks]
  actual_mach_names = entitlements[mach_entitlement]
  unless actual_mach_names.is_a?(Array) && actual_mach_names.sort == expected_mach_names
    abort "Unexpected Sparkle Mach service entitlement: #{actual_mach_names.inspect}"
  end

  allowed = required + [
    "com.apple.application-identifier",
    "com.apple.developer.team-identifier",
    mach_entitlement
  ]
  unexpected = entitlements.keys - allowed
  abort "Unexpected release entitlement: #{unexpected.first}" unless unexpected.empty?
when "nested"
  nested_code = ARGV.shift || "nested code"
  abort "Nested release code must not include get-task-allow: #{nested_code}" if entitlements.key?(get_task_allow)
else
  abort "Usage: verify-entitlements.rb app|nested [NESTED_CODE_PATH]"
end
