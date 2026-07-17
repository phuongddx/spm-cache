# frozen_string_literal: true

require "fileutils"
require "json"
require "xcodeproj"
require "spm_cache/core/config"
require "spm_cache/core/lockfile"
require "spm_cache/core/log"
require "spm_cache/spm/pkg/proxy"
require "spm_cache/spm/checkout_resolver"
require "spm_cache/spm/desc/desc"
require "spm_cache/cache/cachemap"

module SPMCache
  class Installer
    include SPM::CheckoutResolver

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
      @proxy_pkg.prepare do
        resolve_umbrella_checkouts
        enrich_lockfile_products
      end
    end

    # Enriches `spm-cache.lock` in place with real product metadata
    # (`products: [{name, type, targets}]`) sourced from `swift package
    # describe` against the materialized umbrella checkouts, so the proxy
    # generator never falls back to a package's lockfile identity as its
    # product name. Idempotent: only entries missing `products` are enriched,
    # and a package whose checkout can't be found is left unchanged (legacy
    # identity-fallback applies downstream) with a warning, rather than
    # aborting the whole run.
    def enrich_lockfile_products
      return unless @lockfile

      @lockfile.projects.each_value do |proj_data|
        (proj_data["packages"] || []).each do |pkg_data|
          next if pkg_data["products"]

          checkout_dir = checkout_dir_for(pkg_data)
          unless checkout_dir
            Core::UI.warn "No checkout found for '#{pkg_data['name'] || slug_for(pkg_data)}'; product metadata not enriched (legacy fallback applies)"
            next
          end

          desc = SPM::Desc::Description.new(name: pkg_data["name"] || slug_for(pkg_data), pkg_dir: checkout_dir)
          desc.fetch
          products = desc.products.map { |p| { "name" => p.name, "type" => p.type, "targets" => p.target_names } }
          if products.empty?
            Core::UI.warn "'swift package describe' returned no products for '#{pkg_data['name'] || slug_for(pkg_data)}'; product metadata not enriched (legacy fallback applies)"
            next
          end

          pkg_data["products"] = products
        end
      end

      @lockfile.save
    end

    def gen_supporting_files
      # Placeholder for xcconfig generation
    end

    def integrate_proxy_into_project
      Core::UI.info "Integrating proxy into #{@project_path}..."
      project = Xcodeproj::Project.open(@project_path)

      plugin_urls = plugin_only_lockfile_urls

      # Collect current product dependencies, including their package
      # association -- needed below to tell whether a dep is exempted
      # (points at a kept plugin-only ref) BEFORE anything is deleted.
      old_deps = []
      project.targets.each do |target|
        target.package_product_dependencies.to_a.each do |dep|
          old_deps << { target: target, product: dep.product_name, package: dep.package }
        end
      end

      # KEEP exactly the package references that URL-match a plugin-only
      # lockfile entry (re-decided fresh every run from the CURRENT project +
      # CURRENT lockfile, not by remembering object identity across runs).
      # Everything else -- including every XCLocalSwiftPackageReference,
      # i.e. a stale proxy ref from a prior run -- is stripped. Preserving an
      # unmatched library ref here would recreate the identity-collision bug
      # at the Xcode layer and accumulate proxy refs across runs.
      kept_refs = project.root_object.package_references.select { |ref| plugin_ref?(ref, plugin_urls) }
      warn_unmatched_plugin_entries(kept_refs, plugin_urls)

      project.root_object.package_references.to_a.each do |ref|
        next if kept_refs.include?(ref)

        project.root_object.package_references.delete(ref)
      end

      # Remove product deps, except those exempted: pointing at a kept
      # plugin-only ref, or carrying Xcode's own build-tool-plugin-dependency
      # naming convention (a cheap second belt against rewiring them onto
      # the proxy, which would silently break the plugin).
      project.targets.each do |target|
        target.package_product_dependencies.to_a.each do |dep|
          next if dep_exempted?(dep.product_name, dep.package, kept_refs)

          target.package_product_dependencies.delete(dep)
        end
      end

      # Add local proxy package
      proxy_rel_path = File.join("spm-cache", "packages", "proxy")
      proxy_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
      proxy_ref.relative_path = proxy_rel_path
      project.root_object.package_references << proxy_ref

      # Add product deps pointing to proxy, skipping exempted ones (their
      # original dependency object was left untouched above, still wired to
      # its kept package reference).
      rewired = 0
      old_deps.each do |info|
        next if dep_exempted?(info[:product], info[:package], kept_refs)

        prod_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
        prod_dep.product_name = info[:product]
        prod_dep.package = proxy_ref
        info[:target].package_product_dependencies << prod_dep
        rewired += 1
      end

      project.save
      Core::UI.info "Proxy integrated. #{rewired} product dependencies updated (#{old_deps.size - rewired} plugin dependencies preserved)."
    end

    # True when `dep`'s package is a kept plugin-only reference, or its
    # product name carries Xcode's build-tool-plugin-dependency prefix.
    # Exempted deps are left exactly as they are: never deleted, never
    # rewired onto the proxy.
    def dep_exempted?(product_name, package_ref, kept_refs)
      return true if package_ref && kept_refs.include?(package_ref)

      product_name.to_s.start_with?("plugin:")
    end

    # True when `ref` is a remote package reference whose (normalized)
    # repository URL matches a plugin-only lockfile entry.
    def plugin_ref?(ref, plugin_urls)
      return false unless ref.respond_to?(:repositoryURL)

      url = ref.repositoryURL
      return false unless url

      plugin_urls.include?(normalize_package_url(url))
    end

    # Normalized (scheme-agnostic, host-case-insensitive, `.git`-suffix-
    # stripped) repository URLs of every plugin-only lockfile entry (a
    # `products[]` entry present with no `library`-type product).
    def plugin_only_lockfile_urls
      urls = []
      @lockfile&.projects&.each_value do |proj_data|
        (proj_data["packages"] || []).each do |pkg|
          next unless plugin_only_package?(pkg)

          normalized = normalize_package_url(pkg["repositoryURL"])
          urls << normalized if normalized
        end
      end
      urls
    end

    # A "plugin-only" package has product metadata (from Phase 2 enrichment)
    # and none of its products are type `library`. A package with no
    # `products` metadata at all (legacy, unenriched) is never plugin-only --
    # it is treated as a library package (status quo: never silently drop a
    # package on missing data).
    def plugin_only_package?(pkg)
      products = pkg["products"]
      return false unless products && !products.empty?

      !products.any? { |p| p["type"] == "library" }
    end

    # Warns loudly (rather than silently preserving an arbitrary ref) when a
    # plugin-only lockfile entry has no matching package reference in the
    # Xcode project -- the plugin will not run.
    def warn_unmatched_plugin_entries(kept_refs, plugin_urls)
      kept_urls = kept_refs.filter_map { |ref| normalize_package_url(ref.repositoryURL) if ref.respond_to?(:repositoryURL) }
      (plugin_urls - kept_urls).each do |url|
        Core::UI.warn "Plugin-only package '#{url}' has no matching Xcode package reference; it will be dropped from the project and may not run"
      end
    end

    # Normalizes a repository URL so ssh/https forms of the same remote and
    # a trailing `.git` suffix compare equal; hostnames are compared
    # case-insensitively (paths are left as-is -- most git hosts are
    # case-sensitive on the org/repo path).
    def normalize_package_url(url)
      return nil unless url

      stripped = url.to_s.strip.sub(/\.git\z/i, "")
      case stripped
      when %r{\Agit@([^:]+):(.+)\z}
        "#{Regexp.last_match(1).downcase}/#{Regexp.last_match(2)}"
      when %r{\A(?:ssh|git|https?)://(?:[^@/]+@)?([^/]+)/(.+)\z}
        "#{Regexp.last_match(1).downcase}/#{Regexp.last_match(2)}"
      else
        stripped.downcase
      end
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
