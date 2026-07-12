# frozen_string_literal: true

require "spm_cache/installer/integration/build"
require "spm_cache/installer/integration/descs"
require "spm_cache/installer/integration/supporting_files"
require "spm_cache/installer/integration/viz"

module SPMCache
  class Installer
    module IntegrationMixin
      include BuildIntegrationMixin
      include DescsIntegrationMixin
      include SupportingFilesIntegrationMixin
      include VizIntegrationMixin
    end
  end
end
