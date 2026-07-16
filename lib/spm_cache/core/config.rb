# frozen_string_literal: true

require "singleton"
require "fileutils"
require "yaml"

require "spm_cache/core/syntax/yml"

module SPMCache
  module Core
    class Config
      include Singleton
      include Syntax::YAMLRepresentable

      DEFAULT_CONFIG = {
        "ignore" => [],
        "cache_only" => [],
        "ignore_local" => false,
        "ignore_build_errors" => false,
        "keep_pkgs_in_project" => false,
        "default_sdk" => "iphonesimulator",
      }.freeze

      SANDBOX_DIR = "spm-cache"
      CACHE_DIR = File.expand_path("~/.spm-cache")
      CONFIG_FILENAME = "spm-cache.yml"
      LOCKFILE_FILENAME = "spm-cache.lock"

      attr_accessor :project_dir, :config_path

      def initialize
        @project_dir = Dir.pwd
        @config_path = File.join(@project_dir, CONFIG_FILENAME)
        @raw = DEFAULT_CONFIG.dup
      end

      def self.instance
        @@instance ||= super
      end

      def self.configure(project_dir: nil, config_path: nil)
        inst = instance
        inst.project_dir = project_dir if project_dir
        inst.config_path = config_path if config_path
        inst
      end

      def load(path = nil)
        @config_path = path if path
        if @config_path && File.exist?(@config_path)
          @raw = DEFAULT_CONFIG.merge(YAML.safe_load(File.read(@config_path)) || {})
        end
        @raw
      end

      def save(path = nil)
        @config_path = path || @config_path
        return unless @config_path

        FileUtils.mkdir_p(File.dirname(@config_path))
        File.write(@config_path, YAML.dump(@raw))
      end

      def sandbox_dir
        File.join(project_dir, SANDBOX_DIR)
      end

      def cache_dir(config = nil)
        config ? File.join(CACHE_DIR, config) : CACHE_DIR
      end

      def umbrella_dir
        File.join(sandbox_dir, "packages", "umbrella")
      end

      def proxy_dir
        File.join(sandbox_dir, "packages", "proxy")
      end

      def metadata_dir
        File.join(sandbox_dir, "metadata")
      end

      def binaries_dir
        File.join(sandbox_dir, "packages", "proxy", ".build", "artifacts")
      end

      def local_packages_dir
        File.join(sandbox_dir, "local-packages")
      end

      def xcconfigs_dir
        File.join(sandbox_dir, "xcconfigs")
      end

      def lockfile_path
        File.join(project_dir, LOCKFILE_FILENAME)
      end

      def remote_config(config)
        remote = raw["remote"] || {}
        remote[config] || remote[config.to_s]
      end

      def ignore_list
        raw["ignore"] || []
      end

      def cache_only_list
        raw["cache_only"] || []
      end

      def ignore_local?
        raw["ignore_local"]
      end

      def ignore_build_errors?
        raw["ignore_build_errors"]
      end

      def keep_pkgs_in_project?
        raw["keep_pkgs_in_project"]
      end

      def default_sdk
        raw["default_sdk"] || "iphonesimulator"
      end

      def should_ignore?(package_name)
        ignore_list.any? { |pattern| File.fnmatch(pattern, package_name) }
      end

      def reset!
        @raw = DEFAULT_CONFIG.dup
      end
    end
  end
end
