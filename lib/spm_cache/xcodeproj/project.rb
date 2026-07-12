# frozen_string_literal: true

require "xcodeproj"

module SPMCache
  module XcodeprojExt
    module ProjectExt
      def self.included(base)
        base.send(:alias_method, :display_name_orig, :display_name) rescue NoMethodError
      end

      def spmcache_pkgs
        root_object.project_references.select do |ref|
          ref.is_a?(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference) ||
            ref.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
        end
      end

      def spmcache_proxy_pkg
        spmcache_pkgs.find { |pkg| pkg.respond_to?(:spmcache_proxy?) && pkg.spmcache_proxy? }
      end

      def add_pkg(repository_url, requirement)
        ref = new(XCRemoteSwiftPackageReference)
        ref.repositoryURL = repository_url
        ref.requirement = requirement
        root_object.project_references << ref
        ref
      end

      def add_local_pkg(path)
        ref = new(XCLocalSwiftPackageReference)
        ref.relativePath = path
        root_object.project_references << ref
        ref
      end

      def add_spmcache_proxy(path)
        ref = add_local_pkg(path)
        ref.define_singleton_method(:spmcache_proxy?) { true }
        ref
      end

      def remove_pkgs(pkgs = nil)
        pkgs ||= spmcache_pkgs
        pkgs.each { |pkg| root_object.project_references.delete(pkg) }
      end

      def get_target(name)
        targets.find { |t| t.name == name }
      end

      def get_pkg(url_or_path)
        spmcache_pkgs.find do |pkg|
          if pkg.respond_to?(:repositoryURL)
            pkg.repositoryURL == url_or_path
          elsif pkg.respond_to?(:relativePath)
            pkg.relativePath == url_or_path
          end
        end
      end

      def spmcache_config_group
        group = main_group.find_subpath("spm-cache", true)
        group
      end
    end
  end
end

Xcodeproj::Project.send(:include, SPMCache::XcodeprojExt::ProjectExt)
