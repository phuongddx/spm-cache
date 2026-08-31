# frozen_string_literal: true

require "fileutils"
require "spm_cache/command/cache"

module SPMCache
  class Command
    class Cache
      class Clean < Cache
        self.summary = "Clean cached packages"

        def self.options
          [["--all", "Remove all cached packages"], ["--dry", "Dry run (show what would be removed)"]].concat(super)
        end

        def initialize(argv)
          @targets = argv.arguments!
          @all = argv.flag?("all", false)
          @dry = argv.flag?("dry", false)
          super
        end

        def run
          config = Core::Config.instance
          ["debug", "release"].each do |cfg|
            cache_dir = config.cache_dir(cfg)
            next unless File.directory?(cache_dir)

            if @all
              remove_path(cache_dir)
            elsif @targets.any?
              @targets.each { |t| remove_path(File.join(cache_dir, t)) }
            else
              puts "Specify --all or target names to clean"
            end

            sweep_orphaned_sidecars(cache_dir)
          end
        end

        private

        def remove_path(path)
          return unless File.exist?(path)

          if @dry
            puts "[dry] Would remove: #{path}"
          else
            FileUtils.rm_rf(path)
            puts "Removed: #{path}"
          end
        end

        # CACHE-03 (D-09, D-10): a .provenance.json/.shims.json sidecar must
        # never outlive the .xcframework it describes. Runs unconditionally,
        # independent of --all/target scope, and AFTER the removal branch
        # above so a named-target removal's own newly-orphaned sidecar is
        # caught in the SAME invocation (remove_path only rm_rf's the
        # .xcframework path itself, leaving its sidecars behind). For --all,
        # cache_dir is already gone by the time this runs, so the glob
        # returns [] -- a harmless no-op. Mirrors
        # copy_prebuilt_binary_target's suffix-stripped basename sidecar
        # cleanup (build_pipeline.rb) -- one matching convention across the
        # whole cache lifecycle. Never removes a sidecar with a matching
        # .xcframework directory (D-10) -- additive hygiene only.
        def sweep_orphaned_sidecars(cache_dir)
          Dir.glob(File.join(cache_dir, "*.{provenance,shims}.json")).each do |sidecar|
            basename = File.basename(sidecar).sub(/\.xcframework\.(provenance|shims)\.json\z/, "")
            fw_path = File.join(cache_dir, "#{basename}.xcframework")
            next if File.directory?(fw_path)

            if @dry
              puts "[dry] Would remove orphaned sidecar: #{sidecar}"
            else
              FileUtils.rm_f(sidecar)
              puts "Removed orphaned sidecar: #{sidecar}"
            end
          end
        end
      end
    end
  end
end
