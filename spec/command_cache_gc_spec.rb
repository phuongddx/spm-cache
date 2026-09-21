# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
# rubocop:disable Metrics/BlockLength

RSpec.describe SPMCache::Command::Cache::GC do
  let(:debug_dir) { Dir.mktmpdir('spm-cache-gc-debug') }
  let(:release_dir) { Dir.mktmpdir('spm-cache-gc-release') }
  let(:lock_path) { File.join(debug_dir, '.spm-cache-build.lock') }
  let(:config) { instance_double(SPMCache::Core::Config) }

  before do
    allow(SPMCache::Core::Config).to receive(:instance).and_return(config)
    allow(config).to receive(:build_lock_path).and_return(lock_path)
    allow(config).to receive(:cache_max_size_gb).and_return(20)
    allow(config).to receive(:cache_dir).with('debug').and_return(debug_dir)
    allow(config).to receive(:cache_dir).with('release').and_return(release_dir)
  end

  after do
    FileUtils.rm_rf(debug_dir)
    FileUtils.rm_rf(release_dir)
  end

  def plan_for(dir)
    SPMCache::Cache::GC::Plan.new(
      entries: [{ path: File.join(dir, 'Old.xcframework'), bytes: 7, reason: :legacy }],
      reclaimed_bytes: 7,
      usage_bytes: 7
    )
  end

  def stub_plans(max_size_bytes: 20 * 1024**3)
    allow(SPMCache::Cache::GC).to receive(:plan).with(
      cache_dirs: [debug_dir], max_size_bytes: max_size_bytes, protect: []
    ).and_return(plan_for(debug_dir))
    allow(SPMCache::Cache::GC).to receive(:plan).with(
      cache_dirs: [release_dir], max_size_bytes: max_size_bytes, protect: []
    ).and_return(plan_for(release_dir))
  end

  def run_gc(*arguments)
    capture_stdout { SPMCache::Command.parse(['cache', 'gc', *arguments]).run }
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  it 'refuses to run while the build lock is held' do
    FileUtils.mkdir_p(File.dirname(lock_path))
    File.write(lock_path, '')
    lock = File.open(lock_path, File::RDWR)
    lock.flock(File::LOCK_EX | File::LOCK_NB)

    expect do
      run_gc
    end.to raise_error(SPMCache::Core::GeneralError, /build lock/)
  ensure
    lock&.close
  end

  it 'plans both config directories with the configured budget' do
    stub_plans(max_size_bytes: 3 * 1024**3)
    allow(config).to receive(:cache_max_size_gb).and_return(3)

    run_gc

    aggregate_failures do
      [debug_dir, release_dir].each do |cache_dir|
        expect(SPMCache::Cache::GC).to have_received(:plan).with(
          cache_dirs: [cache_dir], max_size_bytes: 3 * 1024**3, protect: []
        )
      end
    end
  end

  it 'prints dry-run removals without deleting artifacts' do
    stub_plans
    paths = [File.join(debug_dir, 'Old.xcframework'), File.join(release_dir, 'Old.xcframework')]
    paths.each { |path| FileUtils.mkdir_p(path) }

    output = run_gc('--dry-run')

    aggregate_failures do
      paths.each do |path|
        expect(output).to include("[dry] #{path} (7 bytes)")
        expect(File.exist?(path)).to be(true)
      end
    end
  end

  it 'removes every planned artifact and reports reclaimed bytes' do
    stub_plans
    paths = [File.join(debug_dir, 'Old.xcframework'), File.join(release_dir, 'Old.xcframework')]
    paths.each { |path| FileUtils.mkdir_p(path) }

    output = run_gc('--max-size', '20')

    aggregate_failures do
      paths.each { |path| expect(File.directory?(path)).to be(false) }
      expect(output).to include('Reclaimed: 7 bytes')
    end
  end
end
# rubocop:enable Metrics/BlockLength
