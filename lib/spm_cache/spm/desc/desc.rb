# frozen_string_literal: true

require "spm_cache/spm/desc/base"
require "spm_cache/spm/desc/product"
require "spm_cache/spm/desc/target"
require "spm_cache/spm/desc/dep"

module SPMCache
  module SPM
    module Desc
      class Description < BaseObject
        def platforms
          (raw["platforms"] || []).each_with_object({}) do |p, acc|
            acc[p["platformName"]] = p["version"]
          end
        end

        def dependencies
          (raw["dependencies"] || []).map do |dep|
            Dependency.new(raw: dep, pkg_dir: pkg_dir)
          end
        end

        def products
          (raw["products"] || []).map do |prod|
            Product.new(raw: prod, pkg_dir: pkg_dir)
          end
        end

        def targets
          (raw["targets"] || []).map do |target|
            Target.from_raw(target, pkg_dir: pkg_dir)
          end
        end

        def get_target(name)
          targets.find { |t| t.name == name }
        end

        def get_product(name)
          products.find { |p| p.name == name }
        end

        def traverse_graph(&block)
          visited = Set.new
          queue = targets.dup
          until queue.empty?
            target = queue.shift
            next if visited.include?(target.name)

            visited.add(target.name)
            block.call(target) if block_given?
            target.direct_dependencies.each do |dep|
              dep_target = get_target(dep)
              queue << dep_target if dep_target && !visited.include?(dep_target.name)
            end
          end
        end

        def recursive_targets_for(target_name)
          result = []
          visited = Set.new
          collect_recursive(target_name, result, visited)
          result
        end

        def self.combine_descs(descs)
          combined = { "targets" => [], "products" => [], "dependencies" => [], "platforms" => [] }
          descs.each do |desc|
            combined["targets"] += desc.raw["targets"] || []
            combined["products"] += desc.raw["products"] || []
            combined["dependencies"] += desc.raw["dependencies"] || []
            (desc.raw["platforms"] || []).each do |p|
              combined["platforms"] << p unless combined["platforms"].any? { |cp| cp["platformName"] == p["platformName"] }
            end
          end
          combined
        end

        private

        def collect_recursive(name, result, visited)
          return if visited.include?(name)

          visited.add(name)
          target = get_target(name)
          return unless target

          result << target
          target.direct_dependencies.each { |dep| collect_recursive(dep, result, visited) }
        end
      end
    end
  end
end

require "set"
