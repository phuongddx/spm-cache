# frozen_string_literal: true

require "fileutils"

require "spm_cache/installer"
require "spm_cache/spm/build_pipeline"
require "spm_cache/spm/checkout_resolver"

module SPMCache
  class Installer
    class Build < Installer
      def initialize(project:, config: "debug", targets: [])
        super(project: project, config: config)
        @requested_targets = targets
      end

      def perform_install
        super
        return unless @cachemap

        missed = @cachemap.missed
        if @requested_targets.any?
          filter_requested_targets!(missed)
        end

        if missed.empty?
          Core::UI.info "No targets to build."
          return
        end

        checkouts = checkout_map

        destinations = resolve_destinations
        cache_out = @config.cache_dir(@config_name)
        FileUtils.mkdir_p(cache_out)

        Core::UI.info "Building #{missed.size} target(s): #{missed.join(', ')}..."
        missed.each do |target_name|
          build_single_target(target_name, checkouts, destinations, cache_out)
        end
      end

      private

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
          (proj_data["packages"] || []).each do |pkg|
            slug = slug_for(pkg)
            products = pkg["products"]
            names = if products && !products.empty?
                      products.select { |p| p["type"] == "library" }.map { |p| p["name"] }.compact
                    else
                      [pkg["product_name"] || pkg["name"] || slug]
                    end
            # A plugin-only package (no library product) has nothing to
            # expand to -- leave it unmapped so its identity passes through
            # unchanged, rather than vanishing from `requested` silently.
            next if names.empty?

            identity_to_products[pkg["name"]] = names if pkg["name"]
            identity_to_products[slug] = names
          end
        end

        requested.flat_map { |t| identity_to_products[t] || [t] }.uniq
      end

      def build_single_target(target_name, checkouts, destinations, cache_out)
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
          )
          Core::UI.info "  Cached: #{result}"
        rescue => e
          if @config.ignore_build_errors?
            Core::UI.warn "  #{target_name} build failed (continuing): #{e.message}"
          else
            raise
          end
        end
      end

      def resolve_destinations
        sdk = @config.default_sdk
        case sdk
        when "all"
          SPM::Package::DEFAULT_DESTINATIONS
        when "iphonesimulator", "iphoneos"
          [sdk]
        else
          [sdk]
        end
      end
    end
  end
end
