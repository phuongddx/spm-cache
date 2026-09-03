# frozen_string_literal: true

require 'time'

module SPMCache
  module Web
    module ReadModels
      # DASH-03: the dependency-graph panel's data, extracted verbatim
      # from the 13-01 tracer's inline router reader -- zero behavior
      # change. present flag from File.exist?, nodes via
      # Cache::Cachemap#depgraph_for_viz, generated stamp from the
      # file's mtime. A malformed graph.json raises JSON::ParserError on
      # purpose: the router converts it to the 500 error envelope whose
      # message the UI's "Couldn't load Dependency Graph: {message}"
      # copy renders.
      class Graph
        def self.call(config: Core::Config.instance)
          graph_path = File.join(config.proxy_dir, 'graph.json')
          return { 'present' => false, 'nodes' => [], 'graph_generated_at' => nil } unless File.exist?(graph_path)

          {
            'present' => true,
            'nodes' => Cache::Cachemap.load(graph_path).depgraph_for_viz,
            'graph_generated_at' => File.mtime(graph_path).utc.iso8601
          }
        end
      end
    end
  end
end
