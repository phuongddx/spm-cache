# frozen_string_literal: true

require "json"
require "fileutils"
require "spm_cache/core/config"
require "spm_cache/spm/pkg/base"
require "spm_cache/spm/pkg/proxy_executable"

module SPMCache
  module SPM
    class Package
      class Proxy < Package
        attr_reader :executable, :graph

        def initialize(root_dir:, config: "debug")
          super(root_dir: root_dir, config: config)
          @executable = ProxyExecutable.new
          @graph = nil
        end

        def prepare
          umbrella_dir = Core::Config.instance.umbrella_dir
          proxy_dir = Core::Config.instance.proxy_dir
          cache_dir = Core::Config.instance.cache_dir(@config)
          metadata_dir = Core::Config.instance.metadata_dir
          lockfile_path = Core::Config.instance.lockfile_path

          FileUtils.mkdir_p(umbrella_dir)
          FileUtils.mkdir_p(proxy_dir)
          FileUtils.mkdir_p(metadata_dir)

          ignore = Core::Config.instance.ignore_list
          gen_umbrella(lockfile_path, umbrella_dir)
          invalidate_cache
          gen_proxy(umbrella_dir, proxy_dir, cache_dir, lockfile_path: lockfile_path, ignore: ignore)
          load_graph
        end

        def gen_umbrella(lockfile_path, output_dir)
          @executable.gen_umbrella(lockfile_path: lockfile_path, output_dir: output_dir)
        end

        def resolve(package_dir, metadata_dir)
          @executable.resolve(package_dir: package_dir, metadata_dir: metadata_dir)
        end

        def gen_proxy(umbrella_dir, output_dir, cache_dir, lockfile_path: nil, ignore: [])
          @executable.gen_proxy(umbrella_dir: umbrella_dir, output_dir: output_dir, cache_dir: cache_dir, lockfile_path: lockfile_path, ignore: ignore)
        end

        def invalidate_cache
          proxy_dir = Core::Config.instance.proxy_dir
          FileUtils.rm_rf(proxy_dir)
          FileUtils.mkdir_p(proxy_dir)
        end

        def load_graph
          graph_path = File.join(Core::Config.instance.proxy_dir, "graph.json")
          return @graph = nil unless File.exist?(graph_path)

          @graph = JSON.parse(File.read(graph_path))
        end

        def cache_hits
          return [] unless @graph

          @graph.select { |e| e["status"] == "hit" }.map { |e| e["module"] }
        end

        def cache_misses
          return [] unless @graph

          @graph.select { |e| e["status"] == "missed" }.map { |e| e["module"] }
        end

        def cache_ignored
          return [] unless @graph

          @graph.select { |e| e["status"] == "ignored" }.map { |e| e["module"] }
        end

        def packages_dir
          File.join(root_dir, "spm-cache", "packages")
        end

        def proxy_package_swift
          File.join(Core::Config.instance.proxy_dir, "Package.swift")
        end
      end
    end
  end
end
