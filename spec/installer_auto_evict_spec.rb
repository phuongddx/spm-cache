# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

# The integrated build-flow fixtures intentionally stay in one focused spec.
# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Installer::Build, 'opt-in auto-eviction' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:checkout_dir) { File.join(tmpdir, 'checkouts') }
  let(:written_artifacts) do
    {
      'Alpha' => File.join(tmpdir, 'Alpha-aaaaaaaa.xcframework'),
      'Beta' => File.join(tmpdir, 'Beta-bbbbbbbb.xcframework')
    }
  end
  let(:hit_artifact) { File.join(tmpdir, 'Gamma-dddddddd.xcframework') }
  let(:hit_pointer) { File.join(tmpdir, 'Gamma.xcframework') }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(
      graph_data: [
        { 'module' => 'Alpha', 'status' => 'missed' },
        { 'module' => 'Beta', 'status' => 'missed' },
        { 'module' => 'Gamma', 'status' => 'hit' }
      ]
    )
  end

  before do
    FileUtils.mkdir_p(project_path)
    written_artifacts.each do |name, path|
      FileUtils.mkdir_p(path)
      FileUtils.mkdir_p(File.join(checkout_dir, name))
    end
    FileUtils.mkdir_p(File.join(hit_artifact, 'iphonesimulator'))
    File.symlink(hit_artifact, hit_pointer)

    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *_args|
      receiver = original.receiver
      receiver.instance_variable_set(:@cachemap, cachemap)
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return(
      written_artifacts.keys.to_h { |name| [name, File.join(checkout_dir, name)] }
    )
    allow(SPMCache::Core::Config.instance).to receive_messages(
      ignore_build_errors?: false,
      default_sdk: 'iphonesimulator',
      cache_dir: tmpdir,
      cache_auto_evict?: auto_evict,
      cache_max_size_gb: max_size_gb
    )
    allow(SPMCache::Cache::Fingerprint).to receive(:context).and_return({})
    allow(SPMCache::SPM::BuildPipeline).to receive(:run) do |**kwargs|
      written_artifacts.fetch(kwargs.fetch(:name))
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  let(:auto_evict) { false }
  let(:max_size_gb) { 20 }

  def make_installer
    described_class.new(project: project_path)
  end

  it 'does not plan eviction when auto-eviction is disabled' do
    allow(SPMCache::Cache::GC).to receive(:watermark_plan)

    make_installer.perform_install

    expect(SPMCache::Cache::GC).not_to have_received(:watermark_plan)
    expect(written_artifacts.values).to all(satisfy { |path| File.exist?(path) })
    expect(File.symlink?(File.join(tmpdir, 'Alpha.xcframework'))).to be(true)
  end

  context 'when auto-eviction is enabled and usage is below the watermark' do
    let(:auto_evict) { true }
    let(:max_size_gb) { 1 }

    it 'plans against the written hashes but removes nothing' do
      allow(SPMCache::Cache::GC).to receive(:watermark_plan).and_call_original
      allow(SPMCache::Cache::GC).to receive(:execute!)

      make_installer.perform_install

      expect(SPMCache::Cache::GC).to have_received(:watermark_plan).with(
        cache_dir: tmpdir,
        budget_bytes: 1024 * 1024 * 1024,
        protect: %w[aaaaaaaa bbbbbbbb dddddddd]
      )
      expect(SPMCache::Cache::GC).not_to have_received(:execute!)
      expect(written_artifacts.values).to all(satisfy { |path| File.exist?(path) })
      expect(File.directory?(hit_artifact)).to be(true)
    end
  end

  context 'when auto-eviction is enabled and the cache is over budget' do
    let(:auto_evict) { true }
    let(:max_size_gb) { 1 }
    let(:old_artifact) { File.join(tmpdir, 'Old-cccccccc.xcframework') }
    let(:old_sidecar) { "#{old_artifact}.provenance.json" }

    before do
      FileUtils.mkdir_p(old_artifact)
      File.write(old_sidecar, JSON.generate(last_used_at: 1))
      written_artifacts.each_value do |path|
        File.write("#{path}.provenance.json", JSON.generate(last_used_at: 100))
      end
    end

    it 'evicts the LRU artifact and protects every hash written by this run' do
      plan = SPMCache::Cache::GC::Plan.new(
        entries: [{ path: old_artifact, bytes: 16, reason: :over_budget_lru }],
        reclaimed_bytes: 16,
        usage_bytes: 32
      )
      allow(SPMCache::Cache::GC).to receive(:watermark_plan).and_return(plan)
      allow(SPMCache::Cache::GC).to receive(:execute!).and_call_original

      make_installer.perform_install

      expect(SPMCache::Cache::GC).to have_received(:watermark_plan).with(
        cache_dir: tmpdir,
        budget_bytes: 1024 * 1024 * 1024,
        protect: %w[aaaaaaaa bbbbbbbb dddddddd]
      )
      expect(SPMCache::Cache::GC).to have_received(:execute!).with(plan)
      expect(written_artifacts.values).to all(satisfy { |path| File.exist?(path) })
      expect(File.directory?(hit_artifact)).to be(true)
      expect(File.exist?(old_artifact)).to be(false)
      expect(File.exist?(old_sidecar)).to be(false)
    end
  end

  context 'when auto-eviction raises' do
    let(:auto_evict) { true }
    let(:max_size_gb) { 1 }

    it 'does not fail the build' do
      allow(SPMCache::Cache::GC).to receive(:watermark_plan).and_raise(StandardError, 'plan boom')

      expect { make_installer.perform_install }.to output(/auto-evict failed \(ignored\): plan boom/).to_stderr
      expect(written_artifacts.values).to all(satisfy { |path| File.exist?(path) })
    end
  end
end
# rubocop:enable Metrics/BlockLength
