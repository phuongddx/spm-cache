# frozen_string_literal: true

require "fileutils"
require "open3"
require "spm_cache/core/sh"
require "spm_cache"

module SPMCache
  module SPM
    class Package
      class ProxyExecutable
        attr_reader :version

        def initialize(version: SPMCache::VERSION)
          @version = version
        end

        def lookup_local
          # Check env var first
          env_path = ENV["SPM_CACHE_PROXY_BIN"]
          return env_path if env_path && File.executable?(env_path)

          # Check gem root
          local_path = SPMCache::ROOT.join("tools", "spm-cache-proxy")
          return nil unless local_path.exist?

          binary_path = local_path.join(".build", "release", "spm-cache-proxy").to_s
          File.executable?(binary_path) ? binary_path : nil
        end

        def build_from_source
          tools_dir = SPMCache::ROOT.join("tools", "spm-cache-proxy")
          raise "Swift proxy tool source not found at #{tools_dir}" unless File.directory?(tools_dir)

          SPMCache::Core::Sh.run("swift build -c release", cwd: tools_dir.to_s)
          binary_path = File.join(tools_dir.to_s, ".build", "release", "spm-cache-proxy")
          raise "Build failed: #{binary_path} not found" unless File.executable?(binary_path)

          binary_path
        end

        def download
          raise "Download not yet implemented. Build from source instead."
        end

        def path
          @path ||= lookup_local || build_from_source
        end

        def run(subcommand, args = [])
          cmd = "#{path} #{subcommand}"
          cmd += " " + args.join(" ") unless args.empty?
          SPMCache::Core::Sh.run(cmd)
        end

        def gen_umbrella(lockfile_path:, output_dir:)
          run("gen-umbrella", ["--lockfile #{lockfile_path}", "--output #{output_dir}"])
        end

        def gen_proxy(umbrella_dir:, output_dir:, cache_dir:, lockfile_path: nil, ignore: [], cache_only: [])
          args = ["--umbrella #{umbrella_dir}", "--output #{output_dir}", "--cache #{cache_dir}"]
          args << "--lockfile #{lockfile_path}" if lockfile_path
          args << "--ignore '#{ignore.join(",")}'" if ignore.any?
          args << "--cache-only '#{cache_only.join(",")}'" if cache_only.any?
          run("gen-proxy", args)
        end

        def resolve(package_dir:, metadata_dir:)
          run("resolve", ["--package #{package_dir}", "--output #{metadata_dir}"])
        end
      end
    end
  end
end
