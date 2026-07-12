# frozen_string_literal: true

require "fileutils"
require "spm_cache/core/config"
require "spm_cache/core/lockfile"
require "spm_cache/core/log"
require "spm_cache/spm/pkg/proxy"
require "spm_cache/cache/cachemap"
require "spm_cache/installer/integration"

module SPMCache
  class Installer
    include Core::Log
    include IntegrationMixin

    attr_reader :project, :config, :lockfile, :proxy_pkg, :cachemap

    def initialize(project:, config: "debug")
      @project = project
      @config_name = config
      @config = Core::Config.instance
      @lockfile = Core::Lockfile.new(@config.lockfile_path)
      @proxy_pkg = SPM::Package::Proxy.new(root_dir: @config.project_dir, config: config)
      @cachemap = nil
    end

    def perform_install
      verify_projects!
      recreate_dirs
      migrate_legacy
      ensure_config_file
      sync_lockfile
      proxy_pkg.prepare
      yield self if block_given?
      gen_supporting_files
      add_refs_to_project
      inject_xcconfig
      gen_cachemap_viz
    end

    private

    def verify_projects!
      raise "No project provided" unless @project
      Logger.info "Using project: #{@project}"
    end

    def recreate_dirs
      sandbox = @config.sandbox_dir
      FileUtils.rm_rf(sandbox)
      FileUtils.mkdir_p(sandbox)
      FileUtils.mkdir_p(@config.umbrella_dir)
      FileUtils.mkdir_p(@config.proxy_dir)
      FileUtils.mkdir_p(@config.metadata_dir)
    end

    def migrate_legacy
      # Migration from old format if needed
    end

    def ensure_config_file
      config_path = File.join(@config.project_dir, "spm-cache.yml")
      return if File.exist?(config_path)

      template_path = SPMCache::LIBEXEC.join("assets", "templates", "spm-cache.yml.template")
      FileUtils.cp(template_path.to_s, config_path) if template_path.exist?
    end

    def sync_lockfile
      Logger.info "Syncing lockfile..."
      @lockfile.load(@config.lockfile_path) if File.exist?(@config.lockfile_path)
      @lockfile.save(@config.lockfile_path)
    end

    def gen_supporting_files
      gen_xcconfigs
    end

    def add_refs_to_project
      # Implemented by integration - add proxy Package.swift to project
    end

    def inject_xcconfig
      # Implemented by integration
    end

    def gen_cachemap_viz
      graph_path = File.join(@config.proxy_dir, "graph.json")
      @cachemap = Cache::Cachemap.load(graph_path)
    end
  end
end

require "spm_cache/installer/build"
require "spm_cache/installer/use"
require "spm_cache/installer/rollback"
