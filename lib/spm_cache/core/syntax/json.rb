# frozen_string_literal: true

require "json"
require "spm_cache/core/syntax/hash"

module SPMCache
  module Core
    module Syntax
      module JSONRepresentable
        include HashRepresentable

        def load(path = nil)
          @path = path if path
          return @raw = {} unless @path && File.exist?(@path)

          content = File.read(@path)
          @raw = content.strip.empty? ? {} : JSON.parse(content)
          @raw
        end

        def save(path = nil)
          @path = path if path
          return unless @path

          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, JSON.pretty_generate(raw))
        end

        private

        def read_file(path)
          content = File.read(path)
          content.strip.empty? ? {} : JSON.parse(content)
        end

        def write_file(path, data)
          File.write(path, JSON.pretty_generate(data))
        end
      end
    end
  end
end
