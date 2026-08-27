# frozen_string_literal: true

require "fileutils"
require "json"
require "xcodeproj"
require "spm_cache/core/config"
require "spm_cache/core/lockfile"
require "spm_cache/core/log"
require "spm_cache/core/package_resolved"
require "spm_cache/spm/pkg/proxy"
require "spm_cache/spm/checkout_resolver"
require "spm_cache/spm/desc/desc"
require "spm_cache/cache/cachemap"

module SPMCache
  class Installer
    include SPM::CheckoutResolver

    attr_reader :project_path, :config_name, :config, :lockfile, :proxy_pkg, :cachemap, :diff

    def initialize(project:, config: "debug")
      @project_path = File.expand_path(project)
      @config_name = config
      @config = Core::Config.instance
      @config.project_dir = File.dirname(@project_path)
      @lockfile = nil
      @proxy_pkg = nil
      @cachemap = nil
      @diff = nil
      @host_graph_detector = nil
    end

    def perform_install
      Core::UI.section("spm-cache") do
        verify_projects!
        detect_diff
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

    # Compares the existing spm-cache.lock snapshot against the live Xcode
    # project state (Package.resolved + project.pbxproj SPM refs) and stores
    # the result in @diff. An empty diff means nothing has changed since the
    # last successful run -- Installer::Use takes the fast path and skips
    # regeneration entirely. Prints the human-readable diff summary so the
    # user sees exactly what changed (if anything). This is the structural
    # moat vs Scipio, which requires a separate manifest the user must keep
    # in sync by hand on every dependency change.
    def detect_diff
      @diff = host_graph_detector.detect
      Core::UI.info @diff.summary
      @diff
    end

    private

    # The run's single DiffDetector. Every host-graph consumer reads its located
    # path, so the pin source and the change detector that must agree with it
    # cannot answer with different files -- a project whose Package.resolved is
    # only reachable through the locator's parent tier used to have the detector
    # report drift the reconciler then declined to close. Lazy rather than built
    # in `initialize` because a caller can inject @diff and reach
    # `sync_lockfile` without `detect_diff` ever running.
    def host_graph_detector
      require "spm_cache/core/diff_detector"
      @host_graph_detector ||= Core::DiffDetector.new(project_path: @project_path,
                                                      lockfile_path: @config.lockfile_path)
    end

    # Field bug: even after fixing #integrate_proxy_into_project to properly
    # purge (rather than merely unlink) newly-discarded refs/deps going
    # forward, a project that already accumulated orphans under the OLD
    # buggy code (every prior run, before this fix existed) still has them
    # sitting in the file -- they are not zero-referrer from Xcodeproj's own
    # perspective (a dangling XCSwiftPackageProductDependency object still
    # holds a live `package` to-one attribute pointing at its ref, so the
    # ref shows nonzero referrers even though nothing in any target actually
    # uses it), so `.referrers.empty?` cannot detect them. Reachability must
    # instead be computed explicitly from the two roots that matter for a
    # working build: root_object.package_references and every target's own
    # package_product_dependencies. Verified empirically against a real
    # corrupted project: 113 of 223 product-dependency objects and 33 of 34
    # package-reference objects were unreachable this way despite nonzero
    # referrer counts on the ref side.
    def purge_orphaned_spm_objects(project)
      dep_class = Xcodeproj::Project::Object::XCSwiftPackageProductDependency
      all_deps = project.objects.select { |o| o.is_a?(dep_class) }
      reachable_deps = project.targets.flat_map { |t| t.package_product_dependencies.to_a }
      orphaned_deps = all_deps - reachable_deps

      ref_classes = [
        Xcodeproj::Project::Object::XCRemoteSwiftPackageReference,
        Xcodeproj::Project::Object::XCLocalSwiftPackageReference,
      ]
      all_refs = project.objects.select { |o| ref_classes.any? { |k| o.is_a?(k) } }
      reachable_refs = project.root_object.package_references.to_a
      orphaned_refs = all_refs - reachable_refs

      return if orphaned_deps.empty? && orphaned_refs.empty?

      Core::UI.info "  Purging #{orphaned_deps.size} orphaned product dependency(ies) and " \
                    "#{orphaned_refs.size} orphaned package reference(s) left over from a prior run..."
      orphaned_deps.each(&:remove_from_project)
      orphaned_refs.each { |ref| ref.remove_from_project if ref.referrers.empty? }
    end

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
      reconcile_lockfile_from_host_graph
      refresh_consumed_dependencies
    end

    # Field bug: `generate_lockfile_from_resolved` writes only when no lockfile
    # exists yet, so every package's `version`/`revision` stayed frozen at
    # first creation and the umbrella pinned an abandoned snapshot forever --
    # on the reference project, four packages linked strictly older than the
    # host's own contemporaneous pin. This refreshes those two fields in place
    # from the host's canonical Package.resolved, drops entries the project no
    # longer depends on and appends ones it newly does, touching nothing else --
    # enriched `products[]` and every identity field survive intact.
    #
    # Membership is decided against DiffDetector's live set (resolved pins
    # UNION project.pbxproj refs), not the pins alone: Package.resolved never
    # lists local/path packages, so a pins-only basis would misread every
    # local package as absent from the graph.
    def reconcile_lockfile_from_host_graph
      return unless @lockfile
      return unless @diff && !@diff.empty?

      resolved = host_graph_detector.host_graph_path
      unless resolved
        Core::UI.warn "No Package.resolved found for #{File.basename(@project_path)}; " \
                      "leaving #{Core::Config::LOCKFILE_FILENAME} untouched."
        return
      end

      # nil here means absent or unreadable, which is NOT "the host has no
      # packages" -- combined with the drop rule below, reading it that way
      # would erase the whole lock.
      host_pins = Core::PackageResolved.pins_or_nil(resolved)
      if host_pins.nil?
        Core::UI.warn "Package.resolved at #{resolved} is unreadable; " \
                      "leaving #{Core::Config::LOCKFILE_FILENAME} untouched."
        return
      end

      proj_data = lock_project_data
      return unless proj_data

      live = host_graph_detector.live_packages
      locked = proj_data["packages"] || []
      drop_missing = drop_pass_allowed?(host_pins, locked, resolved)

      surviving = locked.select do |pkg|
        live_pkg = live[lock_identity_key(pkg)]
        next !drop_missing unless live_pkg

        pkg["version"] = live_pkg["version"]
        # A transitive-only package can legitimately hold no revision; nilling
        # an existing one out would make the umbrella generator skip it.
        pkg["revision"] = live_pkg["revision"] if live_pkg["revision"]
        true
      end

      proj_data["packages"] = surviving + additions_for(live, locked)

      @lockfile.save
    end

    # A hand-written or workspace-era lock can key the project without its
    # `.xcodeproj` extension. `refresh_consumed_dependencies` matches the
    # basename strictly and early-returns on that shape, which is exactly why
    # reconciliation owns its own save rather than riding that one.
    def lock_project_data
      projects = @lockfile.projects
      key = File.basename(@project_path)
      return projects[key] if projects.key?(key)

      stem = File.basename(key, ".xcodeproj")
      match = projects.keys.find { |candidate| File.basename(candidate.to_s, ".xcodeproj") == stem }
      match && projects[match]
    end

    # A pre-v2 Package.resolved nests its pins under `object.pins`, so it parses
    # cleanly with a Hash root and yields zero pins -- indistinguishable from a
    # host that genuinely resolves nothing from source control. Dropping every
    # remote entry on that signal is the lock erasure this reconciler exists to
    # avoid, so retain instead and say so. A real removal of every remote
    # dependency is retained too; the next run with a non-empty pin list drops
    # the stale entries normally.
    def drop_pass_allowed?(host_pins, locked, resolved)
      return true unless host_pins.empty?
      return true unless locked.any? { |pkg| pkg["repositoryURL"] }

      Core::UI.warn "Package.resolved at #{resolved} parsed with zero pins while " \
                    "#{Core::Config::LOCKFILE_FILENAME} still holds remote packages; keeping them and " \
                    "skipping the removal pass. Re-resolve the project's packages in Xcode."
      false
    end

    def lock_identity_key(pkg)
      Core::DiffDetector.identity_key(pkg["repositoryURL"], pkg["path_from_root"] || pkg["path"], pkg["name"])
    end

    def additions_for(live, locked)
      known = locked.map { |pkg| lock_identity_key(pkg) }
      live.reject { |key, _| known.include?(key) }.map { |_, live_pkg| new_lock_entry(live_pkg) }
    end

    # The canonical four-field shape `generate_lockfile_from_resolved` writes.
    # `products` is omitted rather than seeded empty: enrichment guards with
    # `next if pkg_data["products"]` and `[]` is truthy in Ruby, so a
    # present-but-empty key would suppress this package's product metadata
    # permanently.
    def new_lock_entry(live_pkg)
      entry = {}
      if live_pkg["repositoryURL"]
        entry["repositoryURL"] = live_pkg["repositoryURL"]
      elsif live_pkg["path"]
        entry["path_from_root"] = live_pkg["path"]
      end
      entry["name"] = live_pkg["name"]
      entry["version"] = live_pkg["version"]
      entry["revision"] = live_pkg["revision"]
      entry
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

      resolved = host_graph_detector.host_graph_path

      return unless resolved

      # Strict on purpose: a malformed host graph must raise out of `use`
      # rather than seed a lock that claims the project has no packages.
      pins = Core::PackageResolved.pins(resolved)

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
    #
    # `invalidate_stale_products!` runs first so a bug fix to this method (or
    # `products_from_manifest_fallback`) actually takes effect for packages
    # already enriched by an older spm-cache version -- otherwise the
    # idempotency guard below (`next if pkg_data["products"]`) preserves
    # pre-fix, possibly-wrong `products[]` data forever across upgrades
    # (field bug: a fabricated `abcd` product written by a buggy 0.2.2 run
    # survived the 0.2.3 fix untouched, because nothing had invalidated it).
    def enrich_lockfile_products
      return unless @lockfile

      @lockfile.projects.each_value do |proj_data|
        invalidate_stale_products!(proj_data)

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

        proj_data["spm_cache_version"] = SPMCache::VERSION
      end

      @lockfile.save
    end

    # Clears every package's `products[]` once per spm-cache version bump,
    # so the enrichment loop above re-derives all of them fresh instead of
    # trusting data a previous (possibly buggy) version wrote. A lockfile
    # with no stamp at all (written before this field existed) is treated as
    # stale too -- it's exactly the case that needs re-deriving the most.
    # `spm_cache_version` is a per-project sibling of `packages`/
    # `dependencies`/`platforms`, not a new top-level lockfile key, so the
    # Swift-side proxy tool's `Lockfile.load(from:)` (which treats every
    # top-level key as its own project) is unaffected -- it already ignores
    # dict keys it doesn't read.
    def invalidate_stale_products!(proj_data)
      return if proj_data["spm_cache_version"] == SPMCache::VERSION

      (proj_data["packages"] || []).each { |pkg_data| pkg_data.delete("products") }
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

      purge_orphaned_spm_objects(project)

      plugin_urls = plugin_only_lockfile_urls
      never_cached_products = never_cached_product_names

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
      #
      plugin_kept_refs = project.root_object.package_references.select { |ref| plugin_ref?(ref, plugin_urls) }
      warn_unmatched_plugin_entries(plugin_kept_refs, plugin_urls)

      # Field bug: a product with status `.excluded`/`.ignored` (permanently
      # falling back to source, never cached -- e.g. eh_oauth_sdk_ios, which
      # doesn't match cache_only at all) used to still get its dependency
      # rewired onto the proxy, pointing at a shim the Swift-side generator
      # no longer creates for such products (see ProxyGenerator.swift). That
      # shim previously re-declared its OWN dependency on the real upstream
      # package -- and when TWO independently excluded/ignored packages
      # happened to share a transitive dependency (eh_oauth_sdk_ios and
      # AppAuth-iOS's own `AppAuth` product both transitively need the real
      # AppAuth-iOS package), Xcode's PIF loader registered a duplicate GUID
      # for the shared product. Fix: exempt these by PRODUCT NAME (see
      # `dep_exempted?`), not by package ref -- a package ref can be shared
      # by multiple products with different statuses (e.g. AppAuth-iOS:
      # AppAuthCore cached, AppAuth merely missed), so ref-based exemption
      # would wrongly exempt a sibling product that should still be rewired
      # onto the proxy. `never_cached_refs` below exists ONLY to keep the
      # ref itself alive in the removal pass further down (an exempted dep
      # still points at it), not to drive the exemption decision.
      never_cached_refs = old_deps.select { |info| never_cached_products.include?(info[:product]) }
                                   .filter_map { |info| info[:package] }
      kept_refs = (plugin_kept_refs + never_cached_refs).uniq

      # Field bug: discarded product deps and package refs were only ever
      # unlinked from their containing array (ObjectList#delete just calls
      # remove_referrer -- see Xcodeproj source), never purged from the
      # project's object table. The orphaned PBXObjects still got written
      # out by `project.save` on every single run, silently accumulating in
      # the pbxproj file. Existing tests only ever inspected the *reachable*
      # graph from root_object.package_references, so this went unnoticed --
      # until a partially-cached package (AppAuthCore cached, AppAuth
      # excluded/fallback, both from the same underlying remote package)
      # made Xcode's build system actually resolve the orphaned leftover
      # ref (still a syntactically valid XCRemoteSwiftPackageReference)
      # ALONGSIDE the proxy's own shim dependency on that identical remote
      # package+revision, producing two independent paths to the same
      # product and a duplicate PIF GUID registration ("has already been
      # registered") that failed the real app build outright. Fix: remove
      # product deps first (detaching their `package` to-one reference),
      # then remove refs -- using #remove_from_project, which actually
      # purges the object from the project, not just ObjectList#delete.
      project.targets.each do |target|
        target.package_product_dependencies.to_a.each do |dep|
          next if dep_exempted?(dep.product_name, dep.package, plugin_kept_refs, never_cached_products)

          dep.remove_from_project
        end
      end

      project.root_object.package_references.to_a.each do |ref|
        next if kept_refs.include?(ref)

        ref.remove_from_project
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
        next if dep_exempted?(info[:product], info[:package], plugin_kept_refs, never_cached_products)

        prod_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
        prod_dep.product_name = info[:product]
        prod_dep.package = proxy_ref
        info[:target].package_product_dependencies << prod_dep
        rewired += 1
      end

      project.save
      Core::UI.info "Proxy integrated. #{rewired} product dependencies updated (#{old_deps.size - rewired} plugin dependencies preserved)."
    end

    # True when `dep`'s package is a kept plugin-only reference, its product
    # name carries Xcode's build-tool-plugin-dependency prefix, or its
    # product name is permanently excluded/ignored (never cached, per
    # graph.json) -- checked by PRODUCT NAME rather than package ref, since a
    # ref can be shared by sibling products with different statuses. Exempted
    # deps are left exactly as they are: never deleted, never rewired onto
    # the proxy.
    def dep_exempted?(product_name, package_ref, plugin_kept_refs, never_cached_products)
      return true if package_ref && plugin_kept_refs.include?(package_ref)
      return true if never_cached_products.include?(product_name)

      product_name.to_s.start_with?("plugin:")
    end

    # Product names permanently excluded/ignored per graph.json -- i.e. that
    # will never be replaced by a cached binary given the current config.
    # Read directly from disk rather than `@cachemap` (populated later by
    # `gen_cachemap_viz`, which runs after this method in `perform_install`);
    # the file itself already exists by now, written during `prepare_proxy`.
    def never_cached_product_names
      graph_path = File.join(@config.proxy_dir, "graph.json")
      cachemap = Cache::Cachemap.load(graph_path)
      return [] unless cachemap

      cachemap.excluded + cachemap.ignored
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
