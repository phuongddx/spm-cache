# frozen_string_literal: true

require "xcodeproj"

module SPMCache
  module XcodeprojExt
    module PkgRefMixin
      def slug
        if respond_to?(:repositoryURL) && repositoryURL
          File.basename(repositoryURL, ".git")
        elsif respond_to?(:relativePath) && relativePath
          File.basename(relativePath)
        else
          uuid
        end
      end

      def local?
        is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
      end

      def spmcache_pkg?
        respond_to?(:spmcache_proxy?) && spmcache_proxy?
      end

      def to_h
        result = { uuid: uuid }
        result[:repositoryURL] = repositoryURL if respond_to?(:repositoryURL) && repositoryURL
        result[:relativePath] = relativePath if respond_to?(:relativePath) && relativePath
        result
      end
    end
  end
end

Xcodeproj::Project::Object::XCRemoteSwiftPackageReference.send(:include, SPMCache::XcodeprojExt::PkgRefMixin)
Xcodeproj::Project::Object::XCLocalSwiftPackageReference.send(:include, SPMCache::XcodeprojExt::PkgRefMixin)
