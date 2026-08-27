# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'xcodeproj'
require 'spm_cache/core/diff_detector'
require 'spm_cache/installer/use'

# FID-01 -- the lockfile the umbrella is generated from must describe the host
# project's CURRENT resolved graph. `generate_lockfile_from_resolved` writes
# only when no lock exists, so every package's version/revision stayed frozen
# at first creation and the umbrella pinned an abandoned snapshot forever.
RSpec.describe SPMCache::Installer::Use, '#sync_lockfile reconciliation' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:lockfile_path) { File.join(tmpdir, 'spm-cache.lock') }
  let(:alpha_url) { 'https://github.com/example/alpha.git' }
  let(:alpha_products) { [{ 'name' => 'Alpha', 'type' => 'library', 'targets' => ['Alpha'] }] }

  before do
    SPMCache::Core::Config.instance.reset!
    SPMCache::Core::Config.instance.project_dir = tmpdir
    build_project
  end

  after { FileUtils.rm_rf(tmpdir) }

  def build_project
    project = Xcodeproj::Project.new(project_path)
    project.new_target(:application, 'MyApp', :ios)
    project.save
  end

  def write_resolved(path, version:, revision:)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(
                       'version' => 3,
                       'pins' => [{
                         'identity' => 'alpha',
                         'kind' => 'remoteSourceControl',
                         'location' => alpha_url,
                         'state' => { 'revision' => revision, 'version' => version }
                       }]
                     ))
    path
  end

  def canonical_resolved(version:, revision:)
    write_resolved(File.join(project_path, SPMCache::Core::PackageResolved::CANONICAL_RELATIVE_PATH),
                   version: version, revision: revision)
  end

  # The stale nested bundle copy the legacy glob answered with.
  def nested_resolved(version:, revision:)
    write_resolved(
      File.join(project_path, 'Fake.xcodeproj', SPMCache::Core::PackageResolved::CANONICAL_RELATIVE_PATH),
      version: version, revision: revision
    )
  end

  def write_lockfile(version:, revision:, products: nil)
    pkg = { 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => version, 'revision' => revision }
    pkg['products'] = products if products
    File.write(lockfile_path, JSON.pretty_generate(
                                'Fake.xcodeproj' => {
                                  'packages' => [pkg],
                                  'dependencies' => {},
                                  'platforms' => { 'ios' => '16.0' }
                                }
                              ))
  end

  def locked_alpha
    JSON.parse(File.read(lockfile_path))['Fake.xcodeproj']['packages'].first
  end

  def run_sync
    installer = described_class.new(project: project_path)
    installer.detect_diff
    installer.send(:sync_lockfile)
    installer
  end

  it 'updates version and revision' do
    canonical_resolved(version: '2.0.0', revision: 'rev-new')
    write_lockfile(version: '1.0.0', revision: 'rev-old')

    run_sync

    expect(locked_alpha['version']).to eq('2.0.0')
    expect(locked_alpha['revision']).to eq('rev-new')
  end

  # The nested copy here agrees with the stale lock, so a reconciler reading it
  # would be a no-op AND would still leave DiffDetector reporting empty -- two
  # components agreeing on the wrong file. The version/revision assertions are
  # what make the empty-diff assertion non-vacuous.
  it 'reconciles a single drifted package end to end and leaves DiffDetector reporting an empty diff' do
    canonical_resolved(version: '2.0.0', revision: 'rev-new')
    nested_resolved(version: '1.0.0', revision: 'rev-old')
    write_lockfile(version: '1.0.0', revision: 'rev-old', products: alpha_products)

    installer = run_sync
    expect(installer.diff).not_to be_empty

    expect(locked_alpha['version']).to eq('2.0.0')
    expect(locked_alpha['revision']).to eq('rev-new')
    expect(locked_alpha['products']).to eq(alpha_products)

    fresh = SPMCache::Core::DiffDetector.new(project_path: project_path, lockfile_path: lockfile_path).detect
    expect(fresh).to be_empty
  end
end
