# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'spm_cache/cache/fingerprint'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::SPM::BuildPipeline do
  let(:dir) { Dir.mktmpdir }
  let(:out_dir) { File.join(dir, 'cache') }
  let(:pipeline) { described_class }
  let(:pin) { { 'identity' => 'alamofire', 'state' => { 'version' => '5.9.1', 'revision' => 'abc' } } }
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }
  let(:config_stub) do
    double('config', run_sdk: 'iphonesimulator', run_config: 'debug',
                     run_merge_slices: true, run_library_evolution: true)
  end
  let(:fingerprint_context) do
    SPMCache::Cache::Fingerprint.context(config: config_stub, toolchain: toolchain)
  end

  after { FileUtils.remove_entry(dir) }

  def stub_plain_build(name)
    allow(pipeline).to receive(:perform_build).and_wrap_original do |_m, *_args|
      fw = File.join(out_dir, "#{name}.xcframework")
      FileUtils.mkdir_p(fw)
      fw
    end
  end

  it 'renames the stored artifact and records cache_key inputs' do
    stub_plain_build('Alamofire')
    hash8 = SPMCache::Cache::Fingerprint.for(package: 'Alamofire', pin: pin,
                                             dependencies: {}, context: fingerprint_context)
    result = pipeline.run(name: 'Alamofire', pkg_dir: dir, destinations: ['iphonesimulator'],
                          out_dir: out_dir, config: 'debug',
                          graph_entries: [{ 'module' => 'Alamofire', 'dependencies' => [] }],
                          fingerprint_context: fingerprint_context,
                          pins_override: { 'Alamofire' => pin })
    hashed = File.join(out_dir, "Alamofire-#{hash8}.xcframework")
    expect(File.directory?(hashed)).to be(true)
    expect(result).to eq(hashed)
    sidecar = JSON.parse(File.read("#{hashed}.provenance.json"))
    expect(sidecar['cache_key']).to eq(hash8)
    expect(sidecar['cache_key_inputs']['pin']['version']).to eq('5.9.1')
    expect(sidecar['last_used_at']).to be_a(Integer)
  end

  it 'fail-opens when fingerprinting raises' do
    stub_plain_build('Broken')
    allow(SPMCache::Cache::Fingerprint).to receive(:map_for).and_raise(StandardError.new('boom'))
    result = pipeline.run(name: 'Broken', pkg_dir: dir, destinations: ['iphonesimulator'],
                          out_dir: out_dir, config: 'debug',
                          graph_entries: [], fingerprint_context: fingerprint_context,
                          pins_override: {})
    expect(result).to eq(File.join(out_dir, 'Broken.xcframework'))
    expect(File.directory?(File.join(out_dir, 'Broken.xcframework'))).to be(true)
  end

  it 'skips fingerprinting and keeps the plain name without a context' do
    stub_plain_build('Legacy')
    allow(SPMCache::Cache::Fingerprint).to receive(:map_for)

    result = pipeline.run(name: 'Legacy', pkg_dir: dir, destinations: ['iphonesimulator'],
                          out_dir: out_dir, config: 'debug',
                          graph_entries: [{ 'module' => 'Legacy', 'dependencies' => [] }],
                          fingerprint_context: nil, pins_override: nil)

    expect(result).to eq(File.join(out_dir, 'Legacy.xcframework'))
    expect(SPMCache::Cache::Fingerprint).not_to have_received(:map_for)
  end
end
# rubocop:enable Metrics/BlockLength
