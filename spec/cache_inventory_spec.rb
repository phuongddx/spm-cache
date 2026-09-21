# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Cache::Inventory do
  let(:root) { Dir.mktmpdir }
  after { FileUtils.remove_entry(root) }

  it 'reports hash8 and last_used, resolves pointers, skips double-count' do
    dir = File.join(root, 'debug')
    FileUtils.mkdir_p(dir)
    fw = File.join(dir, 'Alamofire-a1b2c3d4.xcframework')
    FileUtils.mkdir_p(fw)
    File.write("#{fw}.provenance.json",
               JSON.generate('fidelity_status' => 'host-pinned', 'cache_key' => 'a1b2c3d4',
                             'last_used_at' => 123))
    FileUtils.ln_s('Alamofire-a1b2c3d4.xcframework', File.join(dir, 'Alamofire.xcframework'))
    entries = described_class.scan(cache_root: root)
    entry = entries.find { |e| e.name == 'Alamofire' }
    expect(entry.hash8).to eq('a1b2c3d4')
    expect(entry.last_used).to eq(123)
    expect(entry.fidelity).to eq('host-pinned')
    expect(entries.count).to eq(1)
  end

  it 'keeps legacy artifacts visible with nil hash8' do
    FileUtils.mkdir_p(File.join(root, 'debug', 'legacy-Old.xcframework'))
    entry = described_class.scan(cache_root: root).find { |e| e.name == 'legacy-Old' }
    expect(entry.hash8).to be_nil
  end

  it 'keeps hash-suffixed legacy artifacts visible with nil hash8' do
    dir = File.join(root, 'debug')
    FileUtils.mkdir_p(dir)
    FileUtils.mkdir_p(File.join(dir, 'legacy-Old-a1b2c3d4.xcframework'))
    entry = described_class.scan(cache_root: root).find { |e| e.name == 'legacy-Old-a1b2c3d4' }
    expect(entry.hash8).to be_nil
  end

  it 'skips a dangling pointer without crashing the remaining scan' do
    dir = File.join(root, 'debug')
    FileUtils.mkdir_p(dir)
    FileUtils.ln_s('Missing-a1b2c3d4.xcframework', File.join(dir, 'Dangling.xcframework'))
    FileUtils.mkdir_p(File.join(dir, 'Present-a1b2c3d4.xcframework'))

    entries = described_class.scan(cache_root: root)

    expect(entries.map(&:name)).to eq(%w[Present-a1b2c3d4])
  end

  it 'resolves pointer-first glob order to the target size without double-counting' do
    dir = File.join(root, 'debug')
    FileUtils.mkdir_p(dir)
    target = File.join(dir, 'Zebra-a1b2c3d4.xcframework')
    FileUtils.mkdir_p(target)
    File.write(File.join(target, 'binary.dat'), 'x' * 100)
    File.write("#{target}.provenance.json",
               JSON.generate('cache_key' => 'a1b2c3d4', 'last_used_at' => 123))
    FileUtils.ln_s('Zebra-a1b2c3d4.xcframework', File.join(dir, 'Alpha.xcframework'))

    entries = described_class.scan(cache_root: root)

    expect(entries.count).to eq(1)
    expect(entries.first.name).to eq('Alpha')
    expect(entries.first.hash8).to eq('a1b2c3d4')
    expect(entries.first.last_used).to eq(123)
    expected_size = File.lstat(target).size + File.lstat(File.join(target, 'binary.dat')).size
    expect(entries.first.size_bytes).to eq(expected_size)
  end
end
# rubocop:enable Metrics/BlockLength
