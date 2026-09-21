# frozen_string_literal: true

require 'fileutils'
require 'json'

module SPMCache
  module Cache
    # Plans and executes local cache cleanup for structural garbage and LRU
    # watermark eviction.
    # rubocop:disable Metrics/ModuleLength, Metrics/ClassLength
    module GC
      HIGH_WATERMARK = 0.85
      LOW_WATERMARK = 0.70

      # rubocop:disable Lint/StructNewOverride
      Plan = Struct.new(:entries, :reclaimed_bytes, :usage_bytes, keyword_init: true)
      # rubocop:enable Lint/StructNewOverride

      class << self
        def plan(cache_dirs:, max_size_bytes:, protect: [])
          entries = cache_dirs.flat_map { |dir| structural_entries(dir, protect: protect) }
          usage = cache_dirs.sum { |dir| dir_bytes(dir) }
          over = cache_dirs.flat_map { |dir| lru_entries(dir, protect: protect, budget: max_size_bytes) }
          entries += over
          Plan.new(entries: entries, reclaimed_bytes: entries.sum { |e| e[:bytes] }, usage_bytes: usage)
        end

        def watermark_plan(cache_dir:, budget_bytes:, protect: [])
          usage = dir_bytes(cache_dir)
          empty = Plan.new(entries: [], reclaimed_bytes: 0, usage_bytes: usage)
          return empty if budget_bytes <= 0 || usage <= (budget_bytes * HIGH_WATERMARK).to_i

          target = (budget_bytes * LOW_WATERMARK).to_i
          candidates = lru_entries(cache_dir, protect: protect, budget: budget_bytes)
          picked = pick_lru(candidates, usage: usage, target: target)
          Plan.new(entries: picked, reclaimed_bytes: picked.sum { |p| p[:bytes] }, usage_bytes: usage)
        end

        def execute!(plan)
          plan.entries.count do |e|
            FileUtils.rm_rf(e[:path])
            FileUtils.rm_f("#{e[:path]}.provenance.json")
            FileUtils.rm_f("#{e[:path]}.shims.json")
            true
          end
        end

        def build_lock_held?(lock_path)
          return false unless File.exist?(lock_path)

          file = File.open(lock_path, File::RDWR)
          held = !file.flock(File::LOCK_EX | File::LOCK_NB)
          file.flock(File::LOCK_UN) unless held
          file.close
          held
        end

        private

        def structural_entries(dir, protect:)
          return [] unless File.directory?(dir)

          frameworks = Dir.glob(File.join(dir, '*.xcframework'))
          frameworks.filter_map { |path| framework_entry(path, protect) } + orphan_sidecars(dir)
        end

        def lru_entries(dir, protect:, budget:)
          usage = dir_bytes(dir)
          return [] if usage <= (budget * HIGH_WATERMARK).to_i

          target = (budget * LOW_WATERMARK).to_i
          candidates = lru_candidates(dir, protect)
          pick_lru(candidates, usage: usage, target: target)
        end

        def framework_entry(path, protect)
          if File.symlink?(path)
            return { path: path, bytes: 0, reason: :dangling_pointer } unless File.directory?(path)

            return nil
          end
          return legacy_entry(path) if File.basename(path).start_with?('legacy-')

          hash = hash8(path)
          return nil if !hash || protect.include?(hash)
          return nil if sidecar?(path)

          { path: path, bytes: dir_bytes(path), reason: :missing_sidecar }
        end

        def legacy_entry(path)
          { path: path, bytes: dir_bytes(path), reason: :legacy }
        end

        def orphan_sidecars(dir)
          sidecars = Dir.glob(File.join(dir, '*.xcframework.{provenance,shims}.json'))
          sidecars.filter_map do |sidecar|
            framework = sidecar.sub(/\.(provenance|shims)\.json\z/, '')
            next if File.exist?(framework)

            { path: sidecar, bytes: File.size(sidecar), reason: :orphan_sidecar }
          end
        end

        def lru_candidates(dir, protect)
          Dir.glob(File.join(dir, '*-????????.xcframework'))
             .filter_map { |path| lru_candidate(path, protect) }
             .sort_by { |candidate| candidate[:last_used] }
        end

        def lru_candidate(path, protect)
          hash = hash8(path)
          return nil if !hash || !sidecar?(path) || protect.include?(hash)

          { path: path, bytes: dir_bytes(path), last_used: last_used(path) }
        end

        def pick_lru(candidates, usage:, target:)
          picked = []
          candidates.each do |candidate|
            break if usage - picked.sum { |picked_entry| picked_entry[:bytes] } <= target

            picked << candidate.merge(reason: :over_budget_lru)
          end
          picked
        end

        def hash8(path)
          File.basename(path)[/-([0-9a-f]{8})\.xcframework\z/, 1]
        end

        def sidecar?(path)
          File.exist?("#{path}.provenance.json")
        end

        def last_used(path)
          JSON.parse(File.read("#{path}.provenance.json"))['last_used_at'] || 0
        rescue JSON::ParserError, SystemCallError
          0 # unreadable sidecar = evicted first
        end

        def dir_bytes(path)
          return 0 unless File.directory?(path)

          Dir.glob(File.join(path, '**', '*')).sum { |entry| File.lstat(entry).size } + File.lstat(path).size
        rescue SystemCallError
          0
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength, Metrics/ClassLength
  end
end
