# frozen_string_literal: true

require "xcodeproj"

module SPMCache
  module XcodeprojExt
    module PkgProductDepExt
      def full_name
        "#{package&.slug}/#{product_name}"
      end

      def remove_alongside_related
        package_product_dependencies.delete(self) if package_product_dependencies
        package&.remove_from_project if package && package.respond_to?(:spmcache_pkg?) && package.spmcache_pkg?
      end
    end
  end
end

Xcodeproj::Project::Object::XCSwiftPackageProductDependency.send(:include, SPMCache::XcodeprojExt::PkgProductDepExt)
