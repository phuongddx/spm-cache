# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'spm_cache/cache/fingerprint'
require 'spm_cache/cache/pointer'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Cache::Pointer do
  let(:dir) { Dir.mktmpdir }
  let(:config_stub) do
    instance_double(SPMCache::Core::Config, run_sdk: 'iphonesimulator', run_config: 'debug',
                                            run_merge_slices: true, run_library_evolution: true)
  end
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }

  before { allow(SPMCache::Cache::Fingerprint).to receive(:toolchain).and_return(toolchain) }
  after { FileUtils.remove_entry(dir) }

  def make_artifact(name, extra_sidecar: {})
    framework = File.join(dir, name)
    FileUtils.mkdir_p(framework)
    File.write("#{framework}.provenance.json", JSON.generate(extra_sidecar))
    framework
  end

  describe '.materialize!' do
    it 'creates plain-name symlinks and records last-used time' do
      make_artifact('Alamofire-a1b2c3d4.xcframework')

      expect(described_class.materialize!(cache_dir: dir, module_name: 'Alamofire',
                                          hash8: 'a1b2c3d4')).to be(true)
      expect(File.symlink?(File.join(dir, 'Alamofire.xcframework'))).to be(true)
      expect(File.symlink?(File.join(dir, 'Alamofire.xcframework.provenance.json'))).to be(true)
      sidecar = JSON.parse(File.read(File.join(dir, 'Alamofire-a1b2c3d4.xcframework.provenance.json')))
      expect(sidecar['last_used_at']).to be_an(Integer)
    end

    it 'is a miss when the hash-suffixed artifact is absent' do
      expect(described_class.materialize!(cache_dir: dir, module_name: 'X',
                                          hash8: 'deadbeef')).to be(false)
      expect(File.exist?(File.join(dir, 'X.xcframework'))).to be(false)
    end
  end

  describe '.quarantine_legacy!' do
    it 'renames plain artifacts and sidecars into legacy misses' do
      make_artifact('Legacy.xcframework')

      expect(described_class.quarantine_legacy!(dir)).to eq(['Legacy'])
      expect(File.directory?(File.join(dir, 'legacy-Legacy.xcframework'))).to be(true)
      expect(File.exist?(File.join(dir, 'legacy-Legacy.xcframework.provenance.json'))).to be(true)
      expect(File.exist?(File.join(dir, 'Legacy.xcframework'))).to be(false)
    end

    it 'leaves hash-suffixed artifacts and pointers alone' do
      make_artifact('Alamofire-a1b2c3d4.xcframework')
      described_class.materialize!(cache_dir: dir, module_name: 'Alamofire', hash8: 'a1b2c3d4')

      expect(described_class.quarantine_legacy!(dir)).to eq([])
      expect(File.symlink?(File.join(dir, 'Alamofire.xcframework'))).to be(true)
    end
  end

  describe '.clear_all!' do
    it 'removes only plain-name pointers' do
      make_artifact('Alamofire-a1b2c3d4.xcframework')
      described_class.materialize!(cache_dir: dir, module_name: 'Alamofire', hash8: 'a1b2c3d4')
      make_artifact('Keep-99999999.xcframework')

      expect(described_class.clear_all!(dir)).to eq(1)
      expect(File.exist?(File.join(dir, 'Alamofire.xcframework'))).to be(false)
      expect(File.directory?(File.join(dir, 'Alamofire-a1b2c3d4.xcframework'))).to be(true)
      expect(File.directory?(File.join(dir, 'Keep-99999999.xcframework'))).to be(true)
    end
  end

  describe '.refresh_all!' do
    it 'materializes hits and recreates them idempotently' do
      pin = { 'identity' => 'alamofire', 'state' => { 'version' => '5.9.1', 'revision' => 'abc' } }
      graph_entries = [{ 'module' => 'Alamofire', 'dependencies' => [] }]
      expected = SPMCache::Cache::Fingerprint.map_for(
        graph_entries: graph_entries, pins: { 'Alamofire' => pin },
        config: config_stub, toolchain: toolchain
      )['Alamofire']
      make_artifact("Alamofire-#{expected}.xcframework")
      pins_path = File.join(dir, 'pins.json')
      File.write(pins_path, JSON.generate('Alamofire' => pin))
      graph_path = File.join(dir, 'graph.json')
      File.write(graph_path, JSON.generate(graph_entries))

      result = described_class.refresh_all!(cache_dir: dir, lockfile_path: nil,
                                            graph_path: graph_path, config: config_stub,
                                            pins_path: pins_path)
      expect(result).to eq('Alamofire' => expected)
      expect(File.symlink?(File.join(dir, 'Alamofire.xcframework'))).to be(true)

      2.times do
        described_class.refresh_all!(cache_dir: dir, lockfile_path: nil, graph_path: graph_path,
                                     config: config_stub, pins_path: pins_path)
      end
      expect(Dir.children(dir).count { |child| child == 'Alamofire.xcframework' }).to eq(1)
    end

    it 'fails open when fingerprinting raises' do
      allow(SPMCache::Cache::Fingerprint).to receive(:map_for).and_raise(StandardError, 'boom')

      expect(described_class.refresh_all!(cache_dir: dir, lockfile_path: nil, graph_path: nil,
                                          config: config_stub)).to eq({})
    end
  end
end
# rubocop:enable Metrics/BlockLength

RSpec.describe SPMCache::Core::Config do
  let(:config) { described_class.instance }

  after { config.reset! }

  it 'resets run scope to command defaults' do
    config.run_sdk = 'macosx'
    config.run_config = 'release'
    config.run_merge_slices = false
    config.run_library_evolution = false

    config.reset!

    aggregate_failures do
      expect(config.run_sdk).to eq('iphonesimulator')
      expect(config.run_config).to eq('debug')
      expect(config.run_merge_slices).to be(true)
      expect(config.run_library_evolution).to be(true)
    end
  end
end

RSpec.describe SPMCache::Command do
  let(:config) { SPMCache::Core::Config.instance }

  after { config.reset! }

  it 'publishes parsed global options to the run-scope config' do
    argv = CLAide::ARGV.new(['--sdk=macosx', '--config=release', '--no-merge-slices',
                             '--no-library-evolution'])
    SPMCache::Command::Use.new(argv)

    aggregate_failures do
      expect(config.run_sdk).to eq('macosx')
      expect(config.run_config).to eq('release')
      expect(config.run_merge_slices).to be(false)
      expect(config.run_library_evolution).to be(false)
    end
  end
end
