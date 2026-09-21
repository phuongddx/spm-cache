# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'

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
end
