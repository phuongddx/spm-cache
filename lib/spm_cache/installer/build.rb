# frozen_string_literal: true

require 'fileutils'

require 'spm_cache/installer'
require 'spm_cache/spm/build_pipeline'
require 'spm_cache/spm/checkout_resolver'
require 'spm_cache/spm/resolved_graph'

module SPMCache
  class Installer
    class Build < Installer
      def initialize(project:, config: 'debug', targets: [])
        super(project: project, config: config)
        @requested_targets = targets
      end

      def perform_install
        lock = acquire_build_lock
        begin
          super
          return unless @cachemap

          destinations = resolve_destinations
          cache_out = @config.cache_dir(@config_name)

          missed = @cachemap.missed.dup
          missed.concat(@cachemap.hit.select { |m| !slice_complete?(cache_out, m, destinations) })

          filter_requested_targets!(missed) if @requested_targets.any?
          missed.uniq!

          if missed.empty?
            Core::UI.info 'No targets to build.'
            return
          end

          checkouts = checkout_map
          # Resolved ONCE per run via the already-memoized `host_graph_detector`
          # (Phase 6 Plan 05's single per-run answer) -- never a second,
          # independent locator here, or the pin source and the change
          # detector could disagree again (06-05-SUMMARY.md).
          resolved_pins_file = SPM::ResolvedGraph.source_for(
            umbrella_dir: @config.umbrella_dir,
            host_graph_path: host_graph_detector.host_graph_path
          )
          FileUtils.mkdir_p(cache_out)

          Core::UI.info "Building #{missed.size} target(s): #{missed.join(', ')}..."
          missed.each do |target_name|
            build_single_target(target_name, checkouts, destinations, cache_out, resolved_pins_file, @config.clones_dir)
          end
        ensure
          release_build_lock(lock)
        end
      end

      private

      # D-06: held across `super` (recreate_dirs + resolve_umbrella_checkouts)
      # AND the entire build loop below, so a watch-triggered
      # Installer::Use#perform_install cannot rm_rf checkouts out from under
      # this run (Pitfall 15). A BLOCKING flock -- "defer rather than
      # interrupt" is satisfied by the OS's own blocking semantics, no
      # polling/backoff needed.
      def acquire_build_lock
        path = @config.build_lock_path
        FileUtils.mkdir_p(File.dirname(path))
        lock = File.open(path, File::CREAT | File::RDWR)
        lock.flock(File::LOCK_EX)
        lock
      end

      # Always releases, including when `super` or the build loop raises
      # (StandardError) or is interrupted -- the `ensure` in `perform_install`
      # calls this unconditionally.
      def release_build_lock(lock)
        return unless lock

        lock.flock(File::LOCK_UN)
        lock.close
      end

      # True when the cached xcframework for `module_name` carries a slice for
      # every requested destination. A sim-only artifact is not a complete hit
      # under --sdk=all, so it must be rebuilt instead of skipped.
      def slice_complete?(cache_dir, module_name, destinations)
        fw = File.join(cache_dir, "#{module_name}.xcframework")
        return false unless File.directory?(fw)

        slices = Dir.children(fw).select { |s| File.directory?(File.join(fw, s)) }
        destinations.all? { |d| slice_satisfies?(slices, d) }
      end

      def slice_satisfies?(slices, dest_key)
        case dest_key
        when 'iphonesimulator' then slices.any? { |s| s.include?('simulator') }
        when 'iphoneos' then slices.any? { |s| s.start_with?('ios') && !s.include?('simulator') }
        else false
        end
      end

      # Filters `missed` down to the intersection with requested targets and
      # emits warnings for unknown or ignored names. Requested names are
      # expanded first so a package identity (e.g. `realm-swift`) still
      # resolves to all of that package's real product names (`Realm`,
      # `RealmSwift`) now that the CLI/graph granularity is per-product.
      def filter_requested_targets!(missed)
        requested = expand_target_aliases(@requested_targets)
        all_known = missed + @cachemap.hit + @cachemap.ignored + @cachemap.excluded + @cachemap.plugin
        (requested - all_known).each do |t|
          Core::UI.warn "unknown target '#{t}' (not in dependency graph)"
        end
        requested.select { |t| @cachemap.ignored.include?(t) }.each do |t|
          Core::UI.warn "'#{t}' is in the ignore list; skipping"
        end
        requested.select { |t| @cachemap.excluded.include?(t) }.each do |t|
          Core::UI.warn "'#{t}' is excluded by cache_only; skipping"
        end
        requested.select { |t| @cachemap.plugin.include?(t) }.each do |t|
          Core::UI.warn "'#{t}' is a build-tool plugin (not cacheable); skipping"
        end
        missed.replace(missed & requested)
      end

      # Expands any requested name that matches a package identity (not a
      # product name) into all of that package's real LIBRARY product names
      # (plugin/other product types of a mixed package never reach
      # graph.json, so including them here would misreport a valid mixed-
      # package identity as an "unknown target"). Names that are already
      # product names, or unknown, pass through unchanged.
      def expand_target_aliases(requested)
        identity_to_products = {}
        @lockfile&.projects&.each_value do |proj_data|
          (proj_data['packages'] || []).each do |pkg|
            slug = slug_for(pkg)
            products = pkg['products']
            names = if products && !products.empty?
                      products.select { |p| p['type'] == 'library' }.map { |p| p['name'] }.compact
                    else
                      [pkg['product_name'] || pkg['name'] || slug]
                    end
            # A plugin-only package (no library product) has nothing to
            # expand to -- leave it unmapped so its identity passes through
            # unchanged, rather than vanishing from `requested` silently.
            next if names.empty?

            identity_to_products[pkg['name']] = names if pkg['name']
            identity_to_products[slug] = names
          end
        end

        requested.flat_map { |t| identity_to_products[t] || [t] }.uniq
      end

      def build_single_target(target_name, checkouts, destinations, cache_out, resolved_pins_file, clones_dir = nil)
        pkg_dir = checkouts[target_name]
        unless pkg_dir && File.directory?(pkg_dir)
          Core::UI.warn "checkout not found for '#{target_name}'; skipping"
          return
        end

        Core::UI.info "  Building #{target_name}..."
        begin
          result = SPM::BuildPipeline.run(
            name: target_name,
            pkg_dir: pkg_dir,
            destinations: destinations,
            out_dir: cache_out,
            library_evolution: true,
            resolved_pins_file: resolved_pins_file,
            clones_dir: clones_dir,
            config: @config_name,
            # D-04/LOGS-01: thread the active run log (nil when no run log is
            # open) so the pipeline brackets this package and activates the
            # xcodebuild live sinks.
            run_log: Core::RunLog.current
          )
          Core::UI.info "  Cached: #{result}"
        rescue StandardError => e
          raise unless @config.ignore_build_errors?

          Core::UI.warn "  #{target_name} build failed (continuing): #{e.message}"
        end
      end

      def resolve_destinations
        sdk = @config.default_sdk
        sdk == 'all' ? SPM::Package::DEFAULT_DESTINATIONS : [sdk]
      end
    end
  end
end
