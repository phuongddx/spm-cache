# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'

require 'spm_cache/command/init'
require 'spm_cache/core/config'

RSpec.describe SPMCache::Command::Init do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_name) { 'TestApp.xcodeproj' }
  let(:project_path) { File.join(tmpdir, project_name) }

  before do
    FileUtils.mkdir_p(project_path)
    # Minimal Package.resolved so lockfile seeding has a source.

    FileUtils.mkdir_p(File.join(project_path, 'project.xcworkspace', 'xcshareddata', 'swiftpm'))
    File.write(File.join(project_path, 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved'),
               '{"pins":[{"identity":"Alamofire","kind":"remoteSourceControl","location":"https://github.com/Alamofire/Alamofire.git","state":{"revision":"deadbeef","version":"5.0.0"}}],"version":1}')
  end

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def parse_init(args)
    # parse returns an instance; argv is the remaining args.
    described_class.parse(args)
  end

  it 'generates spm-cache.yml + seeded lockfile + .gitignore entry (non-interactive)' do
    cmd = parse_init(["--project=#{project_path}",
                      '--platform=ios,macos',
                      '--default-config=debug',
                      '--remote=none'])
    # load_all may have wired Config to the real cwd; point at tmpdir.
    config = SPMCache::Core::Config.instance
    config.reset!
    cmd.run

    yml_path = File.join(tmpdir, 'spm-cache.yml')
    lock_path = File.join(tmpdir, 'spm-cache.lock')
    gitignore_path = File.join(tmpdir, '.gitignore')

    expect(File.exist?(yml_path)).to be true
    expect(File.exist?(lock_path)).to be true
    expect(File.exist?(gitignore_path)).to be true

    parsed = YAML.safe_load(File.read(yml_path))
    expect(parsed['platforms']).to eq(%w[ios macos])
    expect(parsed['default_config']).to eq('debug')

    lock = File.read(lock_path)
    expect(lock).to include('Alamofire')

    expect(File.read(gitignore_path)).to include('spm-cache/')
  end

  it 'is idempotent — re-running preserves user keys and does not duplicate .gitignore' do
    cmd1 = parse_init(["--project=#{project_path}", '--platform=ios', '--default-config=debug'])
    SPMCache::Core::Config.instance.reset!
    cmd1.run

    # User manually adds a key.
    yml_path = File.join(tmpdir, 'spm-cache.yml')
    parsed = YAML.safe_load(File.read(yml_path))
    parsed['custom_key'] = 'keep-me'
    File.write(yml_path, YAML.dump(parsed))

    cmd2 = parse_init(["--project=#{project_path}", '--platform=ios', '--default-config=release'])
    SPMCache::Core::Config.instance.reset!
    cmd2.run

    reparsed = YAML.safe_load(File.read(yml_path))
    expect(reparsed['custom_key']).to eq('keep-me') # preserved
    expect(reparsed['default_config']).to eq('release') # updated

    # .gitignore should contain the entry exactly once.
    gitignore = File.read(File.join(tmpdir, '.gitignore'))
    expect(gitignore.scan('spm-cache/').length).to eq(1)
  end

  it 'configures a git remote backend' do
    cmd = parse_init(["--project=#{project_path}", '--remote=git',
                      '--remote-url=https://github.com/example/cache.git',
                      '--branch=main'])
    SPMCache::Core::Config.instance.reset!
    cmd.run

    parsed = YAML.safe_load(File.read(File.join(tmpdir, 'spm-cache.yml')))
    expect(parsed['remote']).to include('git' => 'https://github.com/example/cache.git')
  end

  it 'fails gracefully with no .xcodeproj' do
    empty_dir = Dir.mktmpdir
    begin
      cmd = parse_init(["--project=#{File.join(empty_dir, 'Nope.xcodeproj')}"])
      SPMCache::Core::Config.instance.reset!
      expect { cmd.run }.to raise_error(SPMCache::Core::GeneralError, /No \.xcodeproj found/)
    ensure
      FileUtils.remove_entry(empty_dir)
    end
  end
end
