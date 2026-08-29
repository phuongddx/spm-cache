# frozen_string_literal: true

require "json"
require "spm_cache/command/cache"

module SPMCache
  class Command
    class Cache
      class List < Cache
        self.summary = "List cached packages"

        def run
          config = Core::Config.instance
          ["debug", "release"].each do |cfg|
            cache_dir = config.cache_dir(cfg)
            next unless File.directory?(cache_dir)

            puts "\n#{cfg.capitalize}:"
            Dir.glob(File.join(cache_dir, "*.xcframework")).sort.each do |fw_path|
              name = File.basename(fw_path, ".xcframework")
              status = fidelity_status_for("#{fw_path}.provenance.json")
              puts "  #{name} (#{status})"
            end
          end
        end

        private

        def fidelity_status_for(sidecar_path)
          return "not-graph-pinned" unless File.exist?(sidecar_path)

          JSON.parse(File.read(sidecar_path))["fidelity_status"] || "not-graph-pinned"
        rescue JSON::ParserError
          "not-graph-pinned"
        end
      end
    end
  end
end
