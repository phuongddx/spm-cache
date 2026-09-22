# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Storage::GitStorage do
  subject(:storage) do
    described_class.new(remote_url: 'https://example.test/cache.git', branch: 'main', cache_dir: cache_dir)
  end

  let(:cache_dir) { Dir.mktmpdir }
  let(:git) { instance_double(SPMCache::Core::Git) }
  let(:calls) { [] }
  let(:observations) { { symlink_at_add: nil } }
  let(:added_paths) { [] }
  let(:removed_paths) { [] }

  before do
    hash_artifact = File.join(cache_dir, 'Alamofire-a1b2c3d4.xcframework')
    hash_sidecar = "#{hash_artifact}.provenance.json"
    pointer = File.join(cache_dir, 'Alamofire.xcframework')
    legacy_artifact = File.join(cache_dir, 'legacy-Alamofire.xcframework')
    temporary_symlink = File.join(cache_dir, 'tmp-Alamofire.xcframework')
    FileUtils.mkdir(hash_artifact)
    File.write(hash_sidecar, '{}')
    FileUtils.mkdir(legacy_artifact)
    File.symlink('Alamofire-a1b2c3d4.xcframework', pointer)
    File.symlink('Alamofire-a1b2c3d4.xcframework', temporary_symlink)

    allow(SPMCache::Core::Git).to receive(:new).with(cache_dir).and_return(git)
    allow(SPMCache::Core::Git).to receive(:git?).with(cache_dir).and_return(false)
    allow(git).to receive(:init) { calls << :init }
    allow(git).to receive(:ensure_remote).with('origin', 'https://example.test/cache.git') do
      calls << :ensure_remote
    end
    allow(git).to receive(:add) do |*paths|
      calls << :add
      added_paths.concat(paths)
      observations[:symlink_at_add] = File.symlink?(pointer)
    end
    allow(git).to receive(:rm) do |*paths|
      calls << :rm
      removed_paths.concat(paths)
    end
    allow(git).to receive(:commit).with('Update cache') { calls << :commit }
    allow(git).to receive(:push).with('origin', 'main') { calls << :push }
  end

  after { FileUtils.remove_entry(cache_dir) }

  it 'clears local pointers before staging the cache for push' do
    storage.push

    expect(calls).to eq(%i[init ensure_remote add rm commit push])
    expect(observations[:symlink_at_add]).to be(false)
    expect(added_paths).to eq(['--ignore-removal', '--',
                               File.join(cache_dir, 'Alamofire-a1b2c3d4.xcframework'),
                               File.join(cache_dir, 'Alamofire-a1b2c3d4.xcframework.provenance.json')])
    expect(removed_paths).to eq(['--cached', '-r', '--ignore-unmatch', '--',
                                 File.join(cache_dir, 'legacy-Alamofire.xcframework')])
    expect(File.directory?(File.join(cache_dir, 'Alamofire-a1b2c3d4.xcframework'))).to be(true)
    expect(File.exist?(File.join(cache_dir, 'Alamofire.xcframework'))).to be(false)
  end
end
# rubocop:enable Metrics/BlockLength

RSpec.describe SPMCache::Storage::GitStorage, 'real non-canonical git cleanup' do
  it 'cleans non-canonical entries with the real git command used by push' do
    repo_dir = Dir.mktmpdir('spm-cache-git-rm-real')
    legacy_file = File.join(repo_dir, 'legacy-Alamofire', 'Alamofire.xcframework', 'marker')
    canonical_file = File.join(repo_dir, 'Alamofire-a1b2c3d4.xcframework', 'marker')

    SPMCache::Core::Git.new(repo_dir).init
    run_git(repo_dir, 'config', 'user.name', 'spm-cache-spec')
    run_git(repo_dir, 'config', 'user.email', 'spec@example.test')
    FileUtils.mkdir_p(File.dirname(legacy_file))
    File.write(legacy_file, 'legacy')
    run_git(repo_dir, 'add', File.join(repo_dir, 'legacy-Alamofire'))
    run_git(repo_dir, 'commit', '-m', 'seed legacy cache')
    FileUtils.mkdir_p(File.dirname(canonical_file))
    File.write(canonical_file, 'canonical')
    File.write("#{File.dirname(canonical_file)}.provenance.json", '{}')

    storage = described_class.new(remote_url: 'https://example.test/cache.git',
                                  branch: 'main', cache_dir: repo_dir)
    allow_any_instance_of(SPMCache::Core::Git).to receive(:push)

    expect { storage.push }.not_to raise_error

    tracked = run_git(repo_dir, 'ls-files')
    aggregate_failures do
      expect(tracked).not_to include('legacy-Alamofire/Alamofire.xcframework/marker')
      expect(File.file?(legacy_file)).to be(true)
      expect(tracked).to include('Alamofire-a1b2c3d4.xcframework/marker')
      expect(tracked).to include('Alamofire-a1b2c3d4.xcframework.provenance.json')
    end
  ensure
    FileUtils.remove_entry(repo_dir)
  end

  def run_git(repo_dir, *arguments)
    output, error, status = Open3.capture3('git', '-C', repo_dir, *arguments)
    raise "git #{arguments.join(' ')} failed: #{error}#{output}" unless status.success?

    output
  end
end

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
    hash_artifact = File.join(cache_dir, 'Alamofire-a1b2c3d4.xcframework')
    FileUtils.mkdir_p(hash_artifact)
    File.write("#{hash_artifact}.provenance.json", '{}')

    storage.pull
    storage.push

    expect(commands).to all(include('--no-follow-symlinks'))
    expect(commands.first).to include("aws s3 sync s3://example-bucket/cache/ #{cache_dir}/ --exact-timestamps")
    expect(commands.last).to include("aws s3 sync #{cache_dir}/ s3://example-bucket/cache/")
    expect(commands.last).not_to include('--delete')
    expect(commands.last).to include("--exclude '*'")
    expect(commands.last).to include('--include Alamofire-a1b2c3d4.xcframework/*')
    expect(commands.last).to include('--include Alamofire-a1b2c3d4.xcframework.provenance.json')
  end
end
