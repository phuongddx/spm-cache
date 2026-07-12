# frozen_string_literal: true

require "json"
require "spm_cache/core/sh"
require "spm_cache/core/syntax/json"
require "spm_cache/core/cacheable"

module SPMCache
  module SPM
    module Desc
      class BaseObject
        include SPMCache::Core::Syntax::JSONRepresentable
        include SPMCache::Core::Cacheable

        attr_reader :name, :pkg_dir

        def initialize(name:, pkg_dir:, raw: {})
          @name = name
          @pkg_dir = pkg_dir
          @raw = raw
          @path = nil
        end

        def full_name
          @name
        end

        def fetch
          @raw = self.class.describe(pkg_dir)
          @raw
        end

        def pkg_desc_of(pkg_name)
          return @raw if @name == pkg_name

          deps = raw["dependencies"] || []
          deps.each do |dep|
            next unless dep.is_a?(Hash)

            url = dep["url"]
            path = dep["path"]
            next unless url || path

            slug = dep["slug"] || File.basename(url || path, ".git")
            return self.class.describe(File.join(@pkg_dir, ".build", "checkouts", slug)) if url
            return self.class.describe(File.expand_path(path, @pkg_dir)) if path
          end
          nil
        end

        def self.describe(pkg_dir)
          result = Sh.run("swift package describe --type json", cwd: pkg_dir)
          JSON.parse(result[:output])
        rescue SPMCache::Core::GeneralError
          {}
        end
      end
    end
  end
end
