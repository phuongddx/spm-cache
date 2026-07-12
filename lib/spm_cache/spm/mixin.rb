# frozen_string_literal: true

module SPMCache
  module SPM
    module PkgMixin
      def umbrella_pkg
        @umbrella_pkg
      end

      def umbrella_pkg=(pkg)
        @umbrella_pkg = pkg
      end

      def proxy_pkg
        @proxy_pkg
      end

      def proxy_pkg=(pkg)
        @proxy_pkg = pkg
      end
    end
  end
end
