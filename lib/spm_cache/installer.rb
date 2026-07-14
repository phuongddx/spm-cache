# frozen_string_literal: true

require "fileutils"
require "json"
require "xcodeproj"
require "spm_cache/core/config"
require "spm_cache/core/lockfile"
require "spm_cache/core/log"
require "spm_cache/spm/pkg/proxy"
require "spm_cache/cache/cachemap"

module SPMCache
  class Installer
    attr_reader :project_path, :config_name, :config, :lockfile, :proxy_pkg, :cachemap

    def initialize(project:, config: "debug")
      @project_path = File.expand_path(project)
      @config_name = config
      @config = Core::Config.instance
      @config.project_dir = File.dirname(@project_path)
      @lockfile = nil
      @proxy_pkg = nil
      @cachemap = nil
    end

    def perform_install
      Core::UI.section("spm-cache") do
        verify_projects!
        recreate_dirs
        ensure_config_file
        sync_lockfile
        prepare_proxy
        yield self if block_given?
        gen_supporting_files
        integrate_proxy_into_project
        gen_cachemap_viz
      end
    end

    private

    def verify_projects!
      raise "No project provided" unless @project_path
      raise "Project not found: #{@project_path}" unless File.exist?(@project_path)
      Core::UI.info "Using project: #{@project_path}"
    end

    def recreate_dirs
      sandbox = @config.sandbox_dir
      FileUtils.rm_rf(sandbox)
      FileUtils.mkdir_p(sandbox)
      FileUtils.mkdir_p(@config.umbrella_dir)
      FileUtils.mkdir_p(@config.proxy_dir)
      FileUtils.mkdir_p(@config.metadata_dir)
    end

    def ensure_config_file
      config_path = File.join(@config.project_dir, "spm-cache.yml")
      unless File.exist?(config_path)
        template_path = SPMCache::LIBEXEC.join("assets", "templates", "spm-cache.yml.template")
        FileUtils.cp(template_path.to_s, config_path) if template_path.exist?
      end
      @config.load(config_path)
    end

    def sync_lockfile
      Core::UI.info "Syncing lockfile..."
      lockfile_path = @config.lockfile_path

      # Generate lockfile from Package.resolved
      generate_lockfile_from_resolved

      @lockfile = Core::Lockfile.new(lockfile_path)
      @lockfile.load(lockfile_path) if File.exist?(lockfile_path)
    end

    def generate_lockfile_from_resolved
      lockfile_path = @config.lockfile_path
      return if File.exist?(lockfile_path)

      # Search recursively for Package.resolved
      resolved = Dir.glob(File.join(@project_path, "**/Package.resolved")).find { |f| File.exist?(f) }

      return unless resolved

      resolved_data = JSON.parse(File.read(resolved))
      pins = resolved_data["pins"] || []

      lockfile_data = {
        File.basename(@project_path) => {
          "packages" => pins.map do |pin|
            {
              "repositoryURL" => pin["location"],
              "name" => pin["identity"],
              "version" => pin.dig("state", "version"),
              "revision" => pin.dig("state", "revision"),
            }
          end,
          "dependencies" => {},
          "platforms" => detect_platforms,
        }
      }

      File.write(lockfile_path, JSON.pretty_generate(lockfile_data))
      Core::UI.info "Generated lockfile with #{pins.size} packages"
    end

    def detect_platforms
      project = Xcodeproj::Project.open(@project_path)
      platforms = {}
      project.targets.each do |target|
        platform_name = target.platform_name.to_s
        next if platform_name.empty?
        deployment_target = target.deployment_target
        next unless deployment_target
        key = platform_name == "ios" ? "ios" : platform_name
        current = platforms[key]
        platforms[key] = deployment_target if current.nil? || deployment_target > current
      end
      platforms["ios"] ||= "16.0"
      platforms
    end

    def prepare_proxy
      Core::UI.info "Preparing proxy packages..."
      @proxy_pkg = SPM::Package::Proxy.new(root_dir: @config.project_dir, config: @config_name)
      @proxy_pkg.prepare
    end

    def gen_supporting_files
      # Placeholder for xcconfig generation
    end

    def integrate_proxy_into_project
      Core::UI.info "Integrating proxy into #{@project_path}..."
      project = Xcodeproj::Project.open(@project_path)

      # Collect current product dependencies
      old_deps = []
      project.targets.each do |target|
        target.package_product_dependencies.to_a.each do |dep|
          old_deps << { target: target, product: dep.product_name }
        end
      end

      # Remove existing remote SPM refs
      project.root_object.package_references.to_a.each do |ref|
        project.root_object.package_references.delete(ref)
      end

      # Remove product deps
      project.targets.each do |target|
        target.package_product_dependencies.to_a.each do |dep|
          target.package_product_dependencies.delete(dep)
        end
      end

      # Add local proxy package
      proxy_rel_path = File.join("spm-cache", "packages", "proxy")
      proxy_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
      proxy_ref.relative_path = proxy_rel_path
      project.root_object.package_references << proxy_ref

      # Add product deps pointing to proxy
      old_deps.each do |info|
        prod_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
        prod_dep.product_name = info[:product]
        prod_dep.package = proxy_ref
        info[:target].package_product_dependencies << prod_dep
      end

      project.save
      Core::UI.info "Proxy integrated. #{old_deps.size} product dependencies updated."
    end

    def gen_cachemap_viz
      graph_path = File.join(@config.proxy_dir, "graph.json")
      @cachemap = Cache::Cachemap.load(graph_path)
      if @cachemap && !@cachemap.graph_data.empty?
        Core::UI.info "Cache: #{@cachemap.hit.size} hits, #{@cachemap.missed.size} missed"
      end
    end
  end
end

require "spm_cache/installer/build"
require "spm_cache/installer/use"
require "spm_cache/installer/rollback"
