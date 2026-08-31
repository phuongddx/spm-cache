# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'

require 'spm_cache/command/init'
require 'spm_cache/core/config'
require 'spm_cache/core/diff_detector'
require 'spm_cache/installer/use'
require 'xcodeproj'

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

    # D-02/LOGS-01: the sandbox entry AND the run-logs entry, each under its
    # own labeled comment.
    gitignore_lines = File.read(gitignore_path).lines.map(&:chomp)
    expect(gitignore_lines).to include('spm-cache/')
    expect(gitignore_lines).to include('.spm-cache/')
    expect(gitignore_lines).to include('# spm-cache sandbox')
    expect(gitignore_lines).to include('# spm-cache run logs')
  end

  it 'seeds spm-cache.lock in the canonical shape consumable by DiffDetector' do
    cmd = parse_init(["--project=#{project_path}", '--platform=ios', '--default-config=debug'])
    SPMCache::Core::Config.instance.reset!
    cmd.run

    lock_path = File.join(tmpdir, 'spm-cache.lock')

    # Consumption contract (Test 2): DiffDetector must parse the seeded lock
    # without raising and report an empty diff against the fixture's live graph.
    detector = SPMCache::Core::DiffDetector.new(project_path: project_path, lockfile_path: lock_path)
    diff = nil
    expect { diff = detector.detect }.not_to raise_error
    expect(diff).to be_empty

    # Canonical shape (Test 1): keyed by the project basename, pins mapped to
    # packages exactly as installer.rb's generate_lockfile_from_resolved does.
    data = JSON.parse(File.read(lock_path))
    expect(data.keys).to eq([project_name])
    proj_data = data[project_name]
    expect(proj_data['packages']).to be_an(Array)
    pkg = proj_data['packages'].first
    expect(pkg['repositoryURL']).to eq('https://github.com/Alamofire/Alamofire.git')
    expect(pkg['name']).to eq('Alamofire')
    expect(pkg['version']).to eq('5.0.0')
    expect(pkg['revision']).to eq('deadbeef')
    expect(proj_data['dependencies']).to eq({})
    expect(proj_data['platforms']).to eq({})
  end

  it 'writes a canonical empty-skeleton lock when Package.resolved is absent' do
    bare_tmpdir = Dir.mktmpdir
    begin
      bare_project = File.join(bare_tmpdir, project_name)
      FileUtils.mkdir_p(bare_project)

      cmd = parse_init(["--project=#{bare_project}", '--platform=ios', '--default-config=debug'])
      SPMCache::Core::Config.instance.reset!
      cmd.run

      lock_path = File.join(bare_tmpdir, 'spm-cache.lock')

      # Consumption contract: the skeleton must parse under DiffDetector too.
      detector = SPMCache::Core::DiffDetector.new(project_path: bare_project, lockfile_path: lock_path)
      diff = nil
      expect { diff = detector.detect }.not_to raise_error
      expect(diff).to be_empty

      # Canonical empty shape (Test 3).
      data = JSON.parse(File.read(lock_path))
      expect(data).to eq(project_name => { 'packages' => [], 'dependencies' => {}, 'platforms' => {} })
    ensure
      FileUtils.remove_entry(bare_tmpdir)
    end
  end

  it 'seeds an empty lock instead of aborting when Package.resolved is malformed' do
    bad_tmpdir = Dir.mktmpdir
    begin
      bad_project = File.join(bad_tmpdir, project_name)
      FileUtils.mkdir_p(File.join(bad_project, 'project.xcworkspace', 'xcshareddata', 'swiftpm'))
      # Truncated mid-document JSON: JSON.parse raises JSON::ParserError.
      File.write(File.join(bad_project, 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved'),
                 '{"pins":[{"identity":"Alamofire","kind":"remoteSour')

      cmd = parse_init(["--project=#{bad_project}", '--platform=ios', '--default-config=debug'])
      SPMCache::Core::Config.instance.reset!

      # Init completes (exit-0 equivalent): warns on stderr, takes the same
      # seeding-skipped message path as a missing Package.resolved, and the
      # run reaches ensure_gitignore instead of aborting mid-run.
      expect do
        expect { cmd.run }.to output(/Created empty spm-cache\.lock/).to_stdout
      end.to output(/\[warn\] Package\.resolved at .* is unreadable/).to_stderr

      lock_path = File.join(bad_tmpdir, 'spm-cache.lock')
      data = JSON.parse(File.read(lock_path))
      expect(data).to eq(project_name => { 'packages' => [], 'dependencies' => {}, 'platforms' => {} })
      expect(File.read(File.join(bad_tmpdir, '.gitignore'))).to include('spm-cache/')
    ensure
      FileUtils.remove_entry(bad_tmpdir)
    end
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

    # .gitignore: each entry exactly once. '.spm-cache/' contains
    # 'spm-cache/' as a substring, so scan() would double-count — assert
    # per-line with anchored regexes instead (D-02).
    gitignore = File.read(File.join(tmpdir, '.gitignore'))
    expect(gitignore.lines.map(&:chomp).grep(%r{\A\.spm-cache/\z}).length).to eq(1)
    expect(gitignore.lines.map(&:chomp).grep(%r{\Aspm-cache/\z}).length).to eq(1)
  end

  it 'appends .spm-cache/ to an existing .gitignore after a blank line with its own comment (D-02)' do
    gitignore_path = File.join(tmpdir, '.gitignore')
    File.write(gitignore_path, "node_modules/\n")

    cmd = parse_init(["--project=#{project_path}", '--platform=ios', '--default-config=debug'])
    SPMCache::Core::Config.instance.reset!
    cmd.run

    expect(File.read(gitignore_path).lines.map(&:chomp)).to eq(
      ['node_modules/', '', '# spm-cache sandbox', 'spm-cache/', '', '# spm-cache run logs', '.spm-cache/']
    )
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

RSpec.describe SPMCache::Command::Init, '→ Installer::Use seeded-lock compatibility' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'TestApp.xcodeproj') }
  let(:lockfile_path) { File.join(tmpdir, 'spm-cache.lock') }

  before { SPMCache::Core::Config.instance.reset! }
  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def build_project
    project = Xcodeproj::Project.new(project_path)
    project.new_target(:application, 'MyApp', :ios)
    project.save
  end

  def write_package_resolved
    resolved_path = File.join(project_path, 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved')
    FileUtils.mkdir_p(File.dirname(resolved_path))
    File.write(resolved_path,
               '{"pins":[{"identity":"Alamofire","kind":"remoteSourceControl","location":"https://github.com/Alamofire/Alamofire.git","state":{"revision":"deadbeef","version":"5.0.0"}}],"version":1}')
  end

  it 'runs init then Installer::Use#perform_install against the seeded lock without raising' do
    build_project
    write_package_resolved

    cmd = described_class.parse(["--project=#{project_path}", '--platform=ios', '--default-config=debug'])
    SPMCache::Core::Config.instance.reset!
    cmd.run
    expect(File.exist?(lockfile_path)).to be true

    installer = SPMCache::Installer::Use.new(project: project_path)
    # Heavy regeneration methods are stubbed (allow, not expect); detect_diff
    # and verify_projects! must run for real — they are the contract under test.
    allow(installer).to receive(:recreate_dirs)
    allow(installer).to receive(:ensure_config_file)
    allow(installer).to receive(:sync_lockfile)
    allow(installer).to receive(:prepare_proxy)
    allow(installer).to receive(:gen_supporting_files)
    allow(installer).to receive(:integrate_proxy_into_project)
    allow(installer).to receive(:gen_cachemap_viz)

    expect { installer.perform_install }.not_to raise_error
    expect(installer.diff).to be_empty
  end
end
