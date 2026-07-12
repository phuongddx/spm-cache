# frozen_string_literal: true

require "json"

module SPMCache
  module Cache
    class Cachemap
      attr_reader :graph_data, :cache_data

      def initialize(graph_data: [], cache_data: {})
        @graph_data = graph_data
        @cache_data = cache_data
      end

      def missed
        @graph_data.select { |e| e["status"] == "missed" }.map { |e| e["module"] }
      end

      def hit
        @graph_data.select { |e| e["status"] == "hit" }.map { |e| e["module"] }
      end

      def ignored
        @graph_data.select { |e| e["status"] == "ignored" }.map { |e| e["module"] }
      end

      def missed?
        !missed.empty?
      end

      def stats
        {
          total: @graph_data.size,
          hit: hit.size,
          missed: missed.size,
          ignored: ignored.size,
        }
      end

      def update_from_graph(graph)
        @graph_data = graph
        self
      end

      def print_stats
        s = stats
        puts "\nCache Stats:"
        puts "  Total:   #{s[:total]}"
        puts "  Hit:     #{s[:hit]}"
        puts "  Missed:  #{s[:missed]}"
        puts "  Ignored: #{s[:ignored]}"
      end

      def depgraph_for_viz
        @graph_data.map do |entry|
          {
            data: {
              id: entry["module"],
              module: entry["module"],
              status: entry["status"],
              hasMacro: entry["hasMacro"] || false,
            },
          }
        end
      end

      def self.load(graph_path)
        return new unless File.exist?(graph_path)

        data = JSON.parse(File.read(graph_path))
        new(graph_data: data)
      end
    end
  end
end
