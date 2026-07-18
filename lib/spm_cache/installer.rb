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
      refresh_consumed_dependencies
    end

    # Records, per target, the product names the Xcode project directly
    # links right now (before spm-cache rewires anything) into the
    # lockfile's `dependencies` field. UmbrellaGenerator uses this to tell a
    # directly-consumed package (must be pinned at the umbrella root) apart
    # from one that's only pulled in transitively by another package in the
    # graph (e.g. realm-core, which the app never links itself -- only
    # realm-swift's Realm/RealmSwift products are). Pinning a transitive-only
    # package independently at its own last-resolved version can conflict
    # with the version its parent's manifest actually requires, breaking
    # `swift package resolve` for the whole graph even though the real
    # dependency graph is perfectly consistent.
    def refresh_consumed_dependencies
      return unless @lockfile

      proj_data = @lockfile.projects[File.basename(@project_path)]
      return unless proj_data

      project = Xcodeproj::Project.open(@project_path)
      deps = {}
      project.targets.each do |target|
        products = target.package_product_dependencies.to_a.map(&:product_name).compact
        deps[target.name] = products unless products.empty?
      end
      proj_data["dependencies"] = deps
      @lockfile.save
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
        resolved_cleanly = resolve_umbrella_checkouts
        enrich_lockfile_products
        retry_umbrella_resolve_after_enrichment unless resolved_cleanly
      end
    end

    # The umbrella's first resolve can fail with a version conflict when it
    # independently pins a package that's only a transitive dependency of
    # another package already in the graph (e.g. realm-core, pulled in
    # solely via realm-swift) at a stale snapshot version that no longer
    # matches what the consuming package's own manifest requires -- see
    # UmbrellaGenerator. At that point in the flow `products[]` metadata
    # doesn't exist yet for anyone, so the generator has no way to tell a
    # transitive-only package apart from a directly-consumed one and pins
    # everything, same as before.
    #
    # `enrich_lockfile_products` (which just ran) now knows every package's
    # real products, so regenerating the umbrella lets the generator
    # correctly exclude transitive-only packages this time, and resolving
    # again gives `swift package resolve` a real chance to succeed on its
    # own rather than leaving the run permanently dependent on Xcode's
    # DerivedData checkouts (absent on CI or after a "clean derived data").
    # `gen_umbrella` recreates `umbrella_dir` from scratch, so any checkouts
    # copied in by the first attempt's DerivedData fallback are wiped before
    # this retry, avoiding stale/inconsistent leftovers.
    def retry_umbrella_resolve_after_enrichment
      @proxy_pkg.gen_umbrella(@config.lockfile_path, @config.umbrella_dir)
      resolve_umbrella_checkouts
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
          products = products_from_manifest_fallback(checkout_dir) if products.empty?
          if products.empty?
            Core::UI.warn "'swift package describe' returned no products for '#{pkg_data['name'] || slug_for(pkg_data)}'; product metadata not enriched (legacy fallback applies)"
            next
          end

          pkg_data["products"] = products
        end
      end

      @lockfile.save
    end

    # `swift package describe` can come back empty (or fail outright) for a
    # package that otherwise resolves fine -- e.g. a private package whose
    # local-path binaryTarget artifact isn't present in this checkout copy
    # (field case: eh_xcframework, `describe` errors with "couldn't be
    # opened" because the DerivedData-fallback checkout copy only mirrors
    # SourcePackages/checkouts, not SourcePackages/artifacts). Without a
    # fallback, such a package silently falls back to its lockfile identity
    # as the assumed product name downstream, reintroducing the original
    # wrong-product-name bug for exactly the packages `describe` can't fully
    # introspect. Parses `.library(name:)` declarations straight out of
    # Package.swift's source text as a last resort.
    #
    # Only `.library(name:)` counts -- a `.binaryTarget` is a TARGET, never a
    # product on its own; SwiftPM requires an explicit product to make
    # anything importable cross-package, and that product is always caught
    # by the `.library(name:)` match above regardless of whether its backing
    # target is a plain Swift target or a binaryTarget. Treating scanned
    # binaryTarget names as their own products fabricates products that were
    # never declared (field bug: eh_xcframework's `abcd` binaryTarget is an
    # internal dependency of the `eHealth` target, wrapped by the single real
    # product `eHealth` -- inventing an `abcd` product broke the whole
    # project's proxy resolution with "product 'abcd' ... not found").
    #
    # Captures each `.library(...)`'s own `targets:` array rather than
    # assuming it always equals `[name]` -- SwiftPM allows a product name to
    # differ from the target(s) backing it (`.library(name: "Foo", targets:
    # ["Bar", "Baz"])`); falls back to `[name]` only when no `targets:` is
    # present in that `.library(...)` call (the common `.library(name: "Foo")`
    # shorthand where the target shares the product's name). Known limitation:
    # the `[^)]*` scan stops at the first `)`, so a `)` inside a comment or
    # nested expression between `name:` and `targets:` in the same call
    # truncates the match and falls back to `targets: [name]` for that one
    # entry -- fails safe (no crash, no cross-entry corruption), acceptable
    # for a last-resort text-scraping path only hit when `describe` fails.
    def products_from_manifest_fallback(checkout_dir)
      manifest_path = File.join(checkout_dir, "Package.swift")
      return [] unless File.exist?(manifest_path)

      text = File.read(manifest_path)
      text.scan(/\.library\(([^)]*)\)/m).filter_map do |(args)|
        name = args[/name:\s*"([^"]+)"/, 1]
        next unless name

        targets_str = args[/targets:\s*\[([^\]]*)\]/, 1]
        targets = targets_str ? targets_str.scan(/"([^"]+)"/).flatten : []
        targets = [name] if targets.empty?
        { "name" => name, "type" => "library", "targets" => targets }
      end.uniq { |p| p["name"] }
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
