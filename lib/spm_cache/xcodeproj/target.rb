# frozen_string_literal: true

require "xcodeproj"

module SPMCache
  module XcodeprojExt
    module TargetExt
      def pkg_product_dependencies
        package_product_dependencies || []
      end

      def add_product_dependency(product_name, package_ref)
        dep = project.new(XCSwiftPackageProductDependency)
        dep.product_name = product_name
        dep.package = package_ref
        package_product_dependencies << dep
        dep
      end

      def remove_product_dependency(dep)
        package_product_dependencies.delete(dep)
      end

      def spmcache_product_dependency(product_name)
        package_product_dependencies.find { |dep| dep.product_name == product_name }
      end
    end
  end
end

Xcodeproj::Project::Object::PBXNativeTarget.send(:include, SPMCache::XcodeprojExt::TargetExt)
