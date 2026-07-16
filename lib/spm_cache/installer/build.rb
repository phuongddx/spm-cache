# frozen_string_literal: true

require "fileutils"

require "spm_cache/installer"
require "spm_cache/spm/build_pipeline"

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

        resolve_umbrella_checkouts
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
      # emits warnings for unknown or ignored names.
      def filter_requested_targets!(missed)
        all_known = missed + @cachemap.hit + @cachemap.ignored + @cachemap.excluded
        (@requested_targets - all_known).each do |t|
          Core::UI.warn "unknown target '#{t}' (not in dependency graph)"
        end
        @requested_targets.select { |t| @cachemap.ignored.include?(t) }.each do |t|
          Core::UI.warn "'#{t}' is in the ignore list; skipping"
        end
        @requested_targets.select { |t| @cachemap.excluded.include?(t) }.each do |t|
          Core::UI.warn "'#{t}' is excluded by cache_only; skipping"
        end
        missed.replace(missed & @requested_targets)
      end

      # Resolves umbrella dependencies so checkouts are materialized under
      # {umbrella_dir}/.build/checkouts/<slug>.
      def resolve_umbrella_checkouts
        Core::UI.info "Resolving umbrella checkouts..."
        Core::Sh.run("swift package resolve", cwd: @config.umbrella_dir)
      rescue => e
        Core::UI.warn "Umbrella resolve failed: #{e.message}"
        fallback_xcode_checkouts

        checkouts_root = File.join(@config.umbrella_dir, ".build", "checkouts")
        if Dir.glob(File.join(checkouts_root, "*")).empty?
          Core::UI.warn "Umbrella resolve failed and no DerivedData checkouts found; all targets will be skipped"
        end
      end

      # Falls back to Xcode's own resolved checkouts under DerivedData when
      # `swift package resolve` fails on the umbrella package. Xcode caches
      # its own SwiftPM checkouts at
      # DerivedData/<Project>-<hash>/SourcePackages/checkouts, so reusing the
      # most recently built one lets targets still be located instead of
      # leaving {umbrella_dir}/.build/checkouts empty.
      #
      # Multiple DerivedData directories can exist for the same project
      # (stale entries from prior Xcode versions/configs, workspace vs.
      # project-level builds); `Dir.glob` order is filesystem-dependent, not
      # mtime-sorted, so the newest one must be picked explicitly via
      # `max_by { File.mtime }` rather than `.first`.
      def fallback_xcode_checkouts
        project_name = File.basename(project_path, File.extname(project_path))
        derived_data_root = File.expand_path("~/Library/Developer/Xcode/DerivedData")
        candidates = Dir.glob(File.join(derived_data_root, "#{project_name}-*"))
        latest = candidates.max_by { |d| File.mtime(d) }
        return unless latest

        source_checkouts = File.join(latest, "SourcePackages", "checkouts")
        return unless File.directory?(source_checkouts)

        dest_checkouts = File.join(@config.umbrella_dir, ".build", "checkouts")
        FileUtils.mkdir_p(dest_checkouts)

        Core::UI.info "Falling back to DerivedData checkouts: #{latest}"
        Dir.glob(File.join(source_checkouts, "*")).each do |pkg_dir|
          next unless File.directory?(pkg_dir)

          FileUtils.cp_r(pkg_dir, dest_checkouts, remove_destination: true)
        end
      end

      # Maps module/product name → checkout directory by matching the lockfile
      # package slug against checkout directory names.
      def checkout_map
        checkouts_root = File.join(@config.umbrella_dir, ".build", "checkouts")
        return {} unless File.directory?(checkouts_root)

        map = {}
        @lockfile&.projects&.each_value do |proj_data|
          (proj_data["packages"] || []).each do |pkg|
            name = pkg["name"] || File.basename(pkg["repositoryURL"] || pkg["path_from_root"] || "", ".git")
            slug = slug_for(pkg)
            checkout_dir = File.join(checkouts_root, slug)
            map[name] = checkout_dir if File.directory?(checkout_dir)
            # Also index by product_name if present
            if pkg["product_name"] && pkg["product_name"] != name
              map[pkg["product_name"]] = checkout_dir if File.directory?(checkout_dir)
            end
          end
        end
        map
      end

      def slug_for(pkg)
        url = pkg["repositoryURL"]
        path = pkg["path_from_root"] || pkg["path"]
        name = pkg["name"]
        if url
          base = url.dup
          base.sub!(/\.git$/, "")
          File.basename(base)
        elsif name
          name
        elsif path
          File.basename(path)
        else
          "unknown"
        end
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
