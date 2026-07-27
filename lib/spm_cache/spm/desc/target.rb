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
          # First try the swift package describe fields
          describe_paths = ((raw["publicHeadersPath"] ? [raw["publicHeadersPath"]] : []) +
                           (raw["headers"] || [])).map { |h| File.join(pkg_dir, h) }
          return describe_paths if describe_paths.any?

          # Fallback: parse Package.swift for publicHeadersPath declaration when
          # swift package describe doesn't provide it (known limitation in Swift 6.2.4+).
          # This mirrors the products_from_manifest_fallback pattern in installer.rb.
          manifest_paths = header_paths_from_manifest
          return manifest_paths if manifest_paths.any?

          []
        end

        private

        def header_paths_from_manifest
          manifest_path = File.join(pkg_dir, "Package.swift")
          return [] unless File.exist?(manifest_path)

          target_name = @name || raw["name"]
          return [] unless target_name

          text = File.read(manifest_path)

          # More robust approach: find the .target block by name first, then extract publicHeadersPath
          # Split into lines and find the target block
          lines = text.lines
          target_start = nil

          lines.each_with_index do |line, idx|
            if line.include?(".target(") && lines[idx..idx+5].join.include?(%("#{target_name}"))
              target_start = idx
              break
            end
          end

          return [] unless target_start

          # Scan from target_start to find publicHeadersPath, stopping at the closing paren
          # that ends the .target(...) block
          paren_depth = 0
          target_block_lines = []

          lines[target_start..].each do |line|
            target_block_lines << line
            paren_depth += line.count("(")
            paren_depth -= line.count(")")

            # We've found the end of the .target(...) block
            break if paren_depth == 0 && target_block_lines.length > 1
          end

          target_block_text = target_block_lines.join

          # Extract publicHeadersPath from the target block
          public_headers_path = target_block_text[/publicHeadersPath:\s*"([^"]+)"/, 1]
          return [] unless public_headers_path

          # Compute the absolute path: target's root dir + publicHeadersPath
          target_root = raw["path"] || "Sources/#{target_name}"
          absolute_headers_dir = File.join(pkg_dir, target_root, public_headers_path)

          # Normalize paths like "./" or "." to just the target root
          absolute_headers_dir = File.join(pkg_dir, target_root) if public_headers_path == "./" || public_headers_path == "."

          [absolute_headers_dir]
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
