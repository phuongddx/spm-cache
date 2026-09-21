# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'spm_cache/cache/gc'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Cache::GC do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  def write_artifact(name, last_used: nil, shims: false)
    path = File.join(dir, "#{name}.xcframework")
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'payload.bin'), 'x' * 100)

    if last_used
      provenance = "#{path}.provenance.json"
      File.write(provenance, JSON.generate({ 'last_used_at' => last_used }))
      File.write("#{path}.shims.json", JSON.generate([])) if shims
    end

    path
  end

  def build_fixture
    write_artifact('Alpha-11111111', last_used: 1, shims: true)
    write_artifact('Beta-22222222', last_used: 2)
    write_artifact('Gamma-33333333', last_used: 3)
    write_artifact('Delta-44444444')
    write_artifact('legacy-Old')
    File.symlink(File.join(dir, 'Missing-99999999.xcframework'),
                 File.join(dir, 'Pointer.xcframework'))
    File.write(File.join(dir, 'Orphan-55555555.xcframework.provenance.json'),
               JSON.generate({ 'last_used_at' => 4 }))
  end

  def reasons(plan)
    plan.entries.map { |entry| entry[:reason] }.tally
  end

  def watermark_budget
    usage = described_class.watermark_plan(cache_dir: dir, budget_bytes: 1_000_000).usage_bytes
    (usage * 0.9).floor
  end

  def over_budget
    described_class.plan(cache_dirs: [dir], max_size_bytes: 1_000_000).usage_bytes * 0.9
  end

  it 'plans every structural cleanup class' do
    build_fixture
    plan = described_class.plan(cache_dirs: [dir], max_size_bytes: 1_000_000)

    expect(plan).to be_a(described_class::Plan)
    expect(reasons(plan)).to eq(
      missing_sidecar: 1,
      legacy: 1,
      dangling_pointer: 1,
      orphan_sidecar: 1
    )
    expect(plan.usage_bytes).to be_positive
    expect(plan.reclaimed_bytes).to eq(plan.entries.sum { |entry| entry[:bytes] })
  end

  it 'adds each LRU artifact once when over budget' do
    build_fixture
    plan = described_class.plan(cache_dirs: [dir], max_size_bytes: over_budget)

    expect(plan.entries.map { |entry| entry[:path] }.uniq.size).to eq(plan.entries.size)
    expect(reasons(plan)).to include(over_budget_lru: 3)
  end

  it 'evicts hash artifacts in last-used order when over the watermark' do
    write_artifact('Alpha-11111111', last_used: 1)
    write_artifact('Beta-22222222', last_used: 2)
    write_artifact('Gamma-33333333', last_used: 3)

    plan = described_class.watermark_plan(cache_dir: dir, budget_bytes: watermark_budget)

    expect(plan.entries.map { |entry| File.basename(entry[:path]) }).to eq(
      ['Alpha-11111111.xcframework', 'Beta-22222222.xcframework']
    )
    expect(plan.entries.map { |entry| entry[:reason] }).to all eq(:over_budget_lru)
  end

  it 'returns an empty watermark plan at or below the high watermark' do
    write_artifact('Alpha-11111111', last_used: 1)
    plan = described_class.watermark_plan(cache_dir: dir, budget_bytes: 1_000_000)

    expect(plan.entries).to be_empty
    expect(plan.reclaimed_bytes).to eq(0)
  end

  it 'skips protected hashes even when they are oldest' do
    write_artifact('Alpha-11111111', last_used: 1)
    write_artifact('Beta-22222222', last_used: 2)
    write_artifact('Gamma-33333333', last_used: 3)

    plan = described_class.watermark_plan(
      cache_dir: dir, budget_bytes: watermark_budget, protect: ['11111111']
    )

    protected_paths = plan.entries.map { |entry| entry[:path] }.grep(/11111111/)
    expect(protected_paths).to be_empty
    expect(File.basename(plan.entries.first[:path])).to eq('Beta-22222222.xcframework')
  end

  it 'executes a plan and removes artifacts with provenance and shim sidecars' do
    write_artifact('Alpha-11111111', last_used: 1, shims: true)
    write_artifact('Beta-22222222', last_used: 2, shims: true)
    plan = described_class.watermark_plan(cache_dir: dir, budget_bytes: watermark_budget)

    expect(described_class.execute!(plan)).to eq(2)
    plan.entries.each do |entry|
      expect(File.exist?(entry[:path])).to be false
      expect(File.exist?("#{entry[:path]}.provenance.json")).to be false
      expect(File.exist?("#{entry[:path]}.shims.json")).to be false
    end
  end

  it 'probes a build lock without blocking' do
    lock_path = File.join(dir, '.spm-cache-build.lock')
    File.write(lock_path, '')
    expect(described_class.build_lock_held?(lock_path)).to be false

    lock = File.open(lock_path, File::RDWR)
    lock.flock(File::LOCK_EX | File::LOCK_NB)
    expect(described_class.build_lock_held?(lock_path)).to be true

    lock.flock(File::LOCK_UN)
    lock.close
    expect(described_class.build_lock_held?(lock_path)).to be false
  end
end
# rubocop:enable Metrics/BlockLength
