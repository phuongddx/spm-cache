# frozen_string_literal: true

require "fileutils"
require "spm_cache/utils/template"

module SPMCache
  class Installer
    module SupportingFilesIntegrationMixin
      def gen_xcconfigs
        xcconfigs_dir = @config.xcconfigs_dir
        FileUtils.mkdir_p(xcconfigs_dir)

        macros = @proxy_pkg.graph&.select { |e| e["hasMacro"] }&.map { |e| e["module"] } || []
        return if macros.empty?

        macros.each do |macro_name|
          xcconfig_content = "OTHER_SWIFT_FLAGS = -load-plugin-library $(SPM_CACHE_DIR)/#{macro_name}.macro\n"
          File.write(File.join(xcconfigs_dir, "#{macro_name}.xcconfig"), xcconfig_content)
        end
      end
    end
  end
end
