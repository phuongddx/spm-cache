# frozen_string_literal: true

require "set"

module SPMCache
  module SPM
    module Desc
      class Target
        attr_reader :name, :module_name, :type, :pkg_dir, :raw

        def initialize(name: nil, module_name: nil, type: nil, raw: {}, pkg_dir:)
          @raw = raw
          @name = name || raw["name"]
          @module_name = module_name || raw["module_name"] || @name
          @type = type || raw["type"]
          @pkg_dir = pkg_dir
        end

        def self.from_raw(raw, pkg_dir:)
          type = raw["type"]
          case type
          when "binary"
            BinaryTarget.new(raw: raw, pkg_dir: pkg_dir)
          when "macro"
            MacroTarget.new(raw: raw, pkg_dir: pkg_dir)
          else
            new(raw: raw, pkg_dir: pkg_dir)
          end
        end

        def source_paths
          (raw["sources"] || []).map { |s| File.join(pkg_dir, s) }
        end

        def header_paths
          ((raw["publicHeadersPath"] ? [raw["publicHeadersPath"]] : []) +
           (raw["headers"] || [])).map { |h| File.join(pkg_dir, h) }
        end

        def resource_paths
          ((raw["resources"] || []).map { |r| r["path"] rescue r }).map { |r| File.join(pkg_dir, r.to_s) }
        end

        def direct_dependencies
          (raw["dependencies"] || []).map do |dep|
            dep["target"] || dep["byName"] || dep["product"]
          end.compact
        end

        def recursive_targets(desc)
          result = []
          visited = Set.new
          collect_recursive(name, result, visited, desc)
          result
        end

        def binary?
          false
        end

        def macro?
          false
        end

        def regular?
          type == "regular" || type.nil?
        end

        def to_h
          { name: @name, module_name: @module_name, type: @type }.compact
        end

        private

        def collect_recursive(target_name, result, visited, desc)
          return if visited.include?(target_name)

          visited.add(target_name)
          target = desc.get_target(target_name)
          return unless target

          result << target
          target.direct_dependencies.each { |dep| collect_recursive(dep, result, visited, desc) }
        end
      end
    end
  end
end

require "spm_cache/spm/desc/target_types/binary"
require "spm_cache/spm/desc/target_types/macro"
