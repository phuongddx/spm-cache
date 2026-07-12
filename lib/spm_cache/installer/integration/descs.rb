# frozen_string_literal: true

module SPMCache
  class Installer
    module DescsIntegrationMixin
      def spmcache_desc
        @lockfile.raw
      end

      def targets_of_products(project_name)
        data = @lockfile.raw[project_name] || {}
        data["dependencies"] || {}
      end

      def binary_targets
        return [] unless @cachemap

        @cachemap.hit
      end
    end
  end
end
