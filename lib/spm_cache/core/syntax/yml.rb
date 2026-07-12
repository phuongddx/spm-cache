# frozen_string_literal: true

require "yaml"
require "spm_cache/core/syntax/hash"

module SPMCache
  module Core
    module Syntax
      module YAMLRepresentable
        include HashRepresentable

        def load(path = nil)
          @path = path if path
          return @raw = {} unless @path && File.exist?(@path)

          content = File.read(@path)
          @raw = content.strip.empty? ? {} : YAML.safe_load(content, aliases: true) || {}
          @raw
        end

        def save(path = nil)
          @path = path if path
          return unless @path

          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, YAML.dump(raw))
        end

        private

        def read_file(path)
          content = File.read(path)
          content.strip.empty? ? {} : YAML.safe_load(content, aliases: true) || {}
        end

        def write_file(path, data)
          File.write(path, YAML.dump(data))
        end
      end
    end
  end
end
