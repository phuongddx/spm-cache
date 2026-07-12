# frozen_string_literal: true

require "spm_cache/core/sh"

module SPMCache
  module Swift
    class Swiftc
      def self.version
        @version ||= Sh.capture_output("swiftc --version").split("\n").first
      end

      def self.swift_version
        match = version.match(/Swift (\d+\.\d+)/)
        match ? match[1] : nil
      end
    end
  end
end
