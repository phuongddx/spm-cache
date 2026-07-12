# frozen_string_literal: true

module SPMCache
  module SPM
    module Desc
      class Dependency
        attr_reader :raw, :pkg_dir

        def initialize(raw:, pkg_dir:)
          @raw = raw
          @pkg_dir = pkg_dir
        end

        def name
          raw["identity"] || slug
        end

        def local?
          !raw["path"].nil?
        end

        def url
          raw["url"]
        end

        def path
          raw["path"]
        end

        def requirement
          raw["requirement"]
        end

        def slug
          if url
            File.basename(url, ".git")
          elsif path
            File.basename(path)
          else
            raw["identity"] || raw["name"]
          end
        end

        def product
          raw["product"]
        end

        def to_h
          result = {}
          result["url"] = url if url
          result["path"] = path if path
          result["slug"] = slug
          result
        end
      end
    end
  end
end
