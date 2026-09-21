# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Storage::GitStorage do
  subject(:storage) do
    described_class.new(remote_url: 'https://example.test/cache.git', branch: 'main', cache_dir: cache_dir)
  end

  let(:cache_dir) { Dir.mktmpdir }
  let(:git) { instance_double(SPMCache::Core::Git) }
  let(:calls) { [] }
  let(:observations) { { symlink_at_add: nil } }

  before do
    hash_artifact = File.join(cache_dir, 'Alamofire-a1b2c3d4.xcframework')
    pointer = File.join(cache_dir, 'Alamofire.xcframework')
    FileUtils.mkdir(hash_artifact)
    File.symlink('Alamofire-a1b2c3d4.xcframework', pointer)

    allow(SPMCache::Core::Git).to receive(:new).with(cache_dir).and_return(git)
    allow(SPMCache::Core::Git).to receive(:git?).with(cache_dir).and_return(false)
    allow(git).to receive(:init) { calls << :init }
    allow(git).to receive(:ensure_remote).with('origin', 'https://example.test/cache.git') do
      calls << :ensure_remote
    end
    allow(git).to receive(:add).with('.') do
      calls << :add
      observations[:symlink_at_add] = File.symlink?(pointer)
    end
    allow(git).to receive(:commit).with('Update cache') { calls << :commit }
    allow(git).to receive(:push).with('origin', 'main') { calls << :push }
  end

  after { FileUtils.remove_entry(cache_dir) }

  it 'clears local pointers before staging the cache for push' do
    storage.push

    expect(calls).to eq(%i[init ensure_remote add commit push])
    expect(observations[:symlink_at_add]).to be(false)
    expect(File.directory?(File.join(cache_dir, 'Alamofire-a1b2c3d4.xcframework'))).to be(true)
    expect(File.exist?(File.join(cache_dir, 'Alamofire.xcframework'))).to be(false)
  end
end
# rubocop:enable Metrics/BlockLength

RSpec.describe SPMCache::Storage::S3Storage do
  subject(:storage) do
    described_class.new(uri: 's3://example-bucket/cache', cache_dir: cache_dir)
  end

  let(:cache_dir) { Dir.mktmpdir }
  let(:commands) { [] }

  before do
    allow(SPMCache::Core::SystemExt::SystemFunctions).to receive(:which).with('aws').and_return('/usr/bin/aws')
    allow(SPMCache::Core::Sh).to receive(:run) { |command, **_env| commands << command }
  end

  after { FileUtils.remove_entry(cache_dir) }

  it 'does not follow local or remote symlinks during S3 sync' do
    storage.pull
    storage.push

    expect(commands).to all(include('--no-follow-symlinks'))
    expect(commands.first).to include("aws s3 sync s3://example-bucket/cache/ #{cache_dir}/ --exact-timestamps")
    expect(commands.last).to include("aws s3 sync #{cache_dir}/ s3://example-bucket/cache/ --delete")
  end
end
