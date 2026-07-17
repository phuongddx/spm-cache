# frozen_string_literal: true

require "fileutils"
require "spm_cache/core/sh"
require "spm_cache/core/log"

module SPMCache
  module SPM
    # Materializes umbrella package checkouts so real package sources exist
    # on disk before anything (enrichment, per-package builds) needs to
    # inspect them. Included into `Installer` so every flow (use/build/
    # rollback) shares one implementation instead of only `Installer::Build`
    # running it, and only after Xcode integration.
    module CheckoutResolver
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
      # package slug against checkout directory names. Indexes by package
      # identity, and by every `products[]` real name (or the legacy singular
      # `product_name` when `products[]` metadata is absent).
      def checkout_map
        map = {}
        @lockfile&.projects&.each_value do |proj_data|
          (proj_data["packages"] || []).each do |pkg|
            checkout_dir = checkout_dir_for(pkg)
            next unless checkout_dir

            name = pkg["name"] || File.basename(pkg["repositoryURL"] || pkg["path_from_root"] || "", ".git")
            map[name] = checkout_dir
            products = pkg["products"]
            if products && !products.empty?
              products.each { |p| map[p["name"]] = checkout_dir if p["name"] }
            elsif pkg["product_name"] && pkg["product_name"] != name
              map[pkg["product_name"]] = checkout_dir
            end
          end
        end
        map
      end

      # The materialized checkout directory for `pkg` under the umbrella's
      # `.build/checkouts/{slug}`, or nil if it hasn't been resolved (or
      # doesn't exist on disk).
      def checkout_dir_for(pkg)
        checkout_dir = File.join(@config.umbrella_dir, ".build", "checkouts", slug_for(pkg))
        File.directory?(checkout_dir) ? checkout_dir : nil
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
    end
  end
end
