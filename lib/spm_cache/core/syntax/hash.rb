# frozen_string_literal: true

module SPMCache
  module Core
    module Syntax
      module HashRepresentable
        attr_accessor :path, :raw

        def load(path = nil)
          @path = path if path
          return {} unless @path && File.exist?(@path)
          @raw = read_file(@path)
          @raw
        end

        def save(path = nil)
          @path = path if path
          return unless @path
          FileUtils.mkdir_p(File.dirname(@path))
          write_file(@path, @raw)
        end

        def [](key)
          raw[key]
        end

        def []=(key, value)
          raw[key] = value
        end

        def to_h
          raw || {}
        end

        private

        def read_file(path)
          raise NotImplementedError, "#{self.class} must implement #read_file"
        end

        def write_file(path, data)
          raise NotImplementedError, "#{self.class} must implement #write_file"
        end
      end
    end
  end
end
