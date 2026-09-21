# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'spm_cache/cache/fingerprint'
require 'spm_cache/command/pkg/build'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Command::Pkg::Build do
  let(:project_dir) { Dir.mktmpdir }
  let(:config) { SPMCache::Core::Config.instance }
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }

  before do
    config.reset!
    allow(SPMCache::Cache::Fingerprint).to receive(:toolchain).and_return(toolchain)
  end
  after do
    FileUtils.remove_entry(project_dir)
    config.reset!
  end

  it 'publishes the custom SDK and evolution context to fingerprinting' do
    Dir.chdir(project_dir) do
      argv = CLAide::ARGV.new(['Alamofire', '--sdk=iphoneos', '--no-library-evolution',
                               '--out=/nonexistent'])
      command = described_class.new(argv)
      pipeline_args = nil
      fingerprint_context = nil

      allow(SPMCache::SPM::BuildPipeline).to receive(:run) do |**kwargs|
        pipeline_args = kwargs
        fingerprint_context = SPMCache::Cache::Fingerprint.context(
          config: SPMCache::Core::Config.instance, toolchain: toolchain
        )
        '/nonexistent/Alamofire.xcframework'
      end

      command.run

      expect(pipeline_args[:destinations]).to eq(['iphoneos'])
      expect(pipeline_args[:library_evolution]).to be(false)
      expect(fingerprint_context['sdk']).to eq('iphoneos')
      expect(fingerprint_context['destinations']).to eq(['iphoneos'])
      expect(fingerprint_context['library_evolution']).to be(false)
    end
  end
end
# rubocop:enable Metrics/BlockLength
