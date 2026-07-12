# frozen_string_literal: true

require "fileutils"
require "json"
require "spm_cache/utils/template"

module SPMCache
  class Installer
    module VizIntegrationMixin
      def gen_cachemap_viz
        return unless @cachemap && !@cachemap.graph_data.empty?

        viz_dir = File.join(@config.sandbox_dir, "cachemap")
        FileUtils.mkdir_p(viz_dir)

        depgraph_data = @cachemap.depgraph_for_viz.to_json

        html = Utils::Template.render("cachemap.html", { data: depgraph_data })
        File.write(File.join(viz_dir, "index.html"), html)

        Core::UI.info "Generated cachemap visualization at #{viz_dir}/index.html"
      end
    end
  end
end
