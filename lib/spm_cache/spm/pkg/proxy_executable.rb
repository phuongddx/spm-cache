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
          local_path = SPMCache::ROOT.join("tools", "spm-cache-proxy")
          return nil unless File.directory?(local_path)

          binary_path = File.join(local_path, ".build", "release", "spm-cache-proxy")
          File.executable?(binary_path) ? binary_path : nil
        end

        def build_from_source
          tools_dir = SPMCache::ROOT.join("tools", "spm-cache-proxy")
          raise "Swift proxy tool source not found at #{tools_dir}" unless File.directory?(tools_dir)

          Sh.run("swift build -c release", cwd: tools_dir.to_s)
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
          Sh.run(cmd)
        end

        def gen_umbrella(lockfile_path:, output_dir:)
          run("gen-umbrella", ["--lockfile #{lockfile_path}", "--output #{output_dir}"])
        end

        def gen_proxy(umbrella_dir:, output_dir:, cache_dir:)
          run("gen-proxy", ["--umbrella #{umbrella_dir}", "--output #{output_dir}", "--cache #{cache_dir}"])
        end

        def resolve(package_dir:, metadata_dir:)
          run("resolve", ["--package #{package_dir}", "--output #{metadata_dir}"])
        end
      end
    end
  end
end
