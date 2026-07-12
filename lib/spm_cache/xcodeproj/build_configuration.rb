# frozen_string_literal: true

require "xcodeproj"

module SPMCache
  module XcodeprojExt
    module BuildConfigExt
      def base_configuration_xcconfig_path
        return nil unless base_configuration_reference
        base_configuration_reference.real_path.to_s
      end

      def set_base_configuration_xcconfig(path)
        file_ref = project.files.find { |f| f.real_path.to_s == path }
        unless file_ref
          file_ref = project.new_file(path)
        end
        self.base_configuration_reference = file_ref
      end
    end
  end
end

Xcodeproj::Project::Object::XCBuildConfiguration.send(:include, SPMCache::XcodeprojExt::BuildConfigExt)
