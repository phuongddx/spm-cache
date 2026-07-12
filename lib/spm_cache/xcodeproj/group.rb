# frozen_string_literal: true

require "xcodeproj"

module SPMCache
  module XcodeprojExt
    module GroupExt
      def synced_groups
        children.select { |c| c.is_a?(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup) }
      end

      def ensure_synced_group(name, path)
        existing = synced_groups.find { |g| g.display_name == name }
        return existing if existing

        group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
        group.path = path
        group.name = name
        children << group
        group
      end

      def new_synced_group(name, path)
        ensure_synced_group(name, path)
      end
    end
  end
end

Xcodeproj::Project::Object::PBXGroup.send(:include, SPMCache::XcodeprojExt::GroupExt)
