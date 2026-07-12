# frozen_string_literal: true

require "cfpropertylist"
require "spm_cache/core/syntax/hash"

module SPMCache
  module Core
    module Syntax
      module PlistRepresentable
        include HashRepresentable

        def load(path = nil)
          @path = path if path
          return @raw = {} unless @path && File.exist?(@path)

          plist = CFPropertyList::List.new(file: @path)
          @raw = CFPropertyList.native_types(plist.value)
          @raw
        end

        def save(path = nil)
          @path = path if path
          return unless @path

          FileUtils.mkdir_p(File.dirname(@path))
          plist = CFPropertyList::List.new
          plist.value = CFPropertyList.guess(raw)
          plist.save(@path, CFPropertyList::List::FORMAT_BINARY)
        end

        def save_xml(path = nil)
          @path = path if path
          return unless @path

          FileUtils.mkdir_p(File.dirname(@path))
          plist = CFPropertyList::List.new
          plist.value = CFPropertyList.guess(raw)
          plist.save(@path, CFPropertyList::List::FORMAT_XML)
        end

        private

        def read_file(path)
          plist = CFPropertyList::List.new(file: path)
          CFPropertyList.native_types(plist.value)
        end

        def write_file(path, data)
          plist = CFPropertyList::List.new
          plist.value = CFPropertyList.guess(data)
          plist.save(path, CFPropertyList::List::FORMAT_XML)
        end
      end
    end
  end
end
