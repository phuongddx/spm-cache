# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'xcodeproj'
require 'spm_cache/core/diagnostics'

# DIAG-01 -- reconciliation happens silently inside a `use` run, so without a
# static check a user has no way to ask "is my lock telling the truth?" before
# spending a build on it. The zero-overlap example encodes the measured
# reference-project state: lock and host graph sharing NO packages, which a
# version-only comparison over the intersection reports as "0 drifted".
RSpec.describe SPMCache::Core::Diagnostics, 'lock_graph_fidelity (DIAG-01)' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:lockfile_path) { File.join(tmpdir, 'spm-cache.lock') }
  let(:alpha_url) { 'https://github.com/example/alpha.git' }
  let(:beta_url) { 'https://github.com/example/beta.git' }

  before do
    SPMCache::Core::Config.instance.reset!
    SPMCache::Core::Config.instance.project_dir = tmpdir
  end

  after { FileUtils.rm_rf(tmpdir) }

  # Only the check under test runs, so the other seven checks' environment
  # dependence cannot decide this file's verdicts.
  def result
    saved = described_class.registry.dup
    begin
      described_class.instance_variable_set(:@registry, saved.select { |c| c.name == 'lock_graph_fidelity' })
      described_class.run_all(config: nil).first
    ensure
      described_class.instance_variable_set(:@registry, saved)
    end
  end

  def build_project
    project = Xcodeproj::Project.new(project_path)
    project.new_target(:application, 'MyApp', :ios)
    project.save
  end

  def pin(identity, url, version: nil, revision: nil)
    { 'identity' => identity, 'kind' => 'remoteSourceControl', 'location' => url,
      'state' => { 'version' => version, 'revision' => revision }.compact }
  end

  def write_canonical_resolved(pins)
    path = File.join(project_path, SPMCache::Core::PackageResolved::CANONICAL_RELATIVE_PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate('version' => 3, 'pins' => pins))
    path
  end

  def lock_pkg(name, url: nil, path_from_root: nil, version: nil, revision: nil)
    { 'name' => name, 'repositoryURL' => url, 'path_from_root' => path_from_root,
      'version' => version, 'revision' => revision }.compact
  end

  def write_lock(packages)
    File.write(lockfile_path, JSON.pretty_generate(
                                'Fake.xcodeproj' => {
                                  'packages' => packages, 'dependencies' => {}, 'platforms' => {}
                                }
                              ))
  end

  # The measured reference-project shape: 8 locked packages, 17 host pins,
  # intersection zero.
  def write_disjoint_fixture
    write_lock((1..8).map do |i|
      lock_pkg("locked#{i}", url: "https://github.com/example/locked#{i}.git", version: '1.0.0')
    end)
    write_canonical_resolved((1..17).map do |i|
      pin("hosted#{i}", "https://github.com/example/hosted#{i}.git", version: '2.0.0')
    end)
  end

  it 'warns on zero overlap between the lock and the host graph' do
    build_project
    write_disjoint_fixture

    expect(result.status).to eq(:warn)
    expect(result.message).to include('locked1')
    expect(result.message).to include('hosted1')
    expect(result.message).to include('8')
    expect(result.message).to include('17')
  end

  it 'warns on a version drift for a shared package' do
    build_project
    write_lock([lock_pkg('alpha', url: alpha_url, version: '1.0.0')])
    write_canonical_resolved([pin('alpha', alpha_url, version: '2.4.0')])

    expect(result.status).to eq(:warn)
    expect(result.message).to include('alpha')
  end

  it 'compares revision before version — an agreeing version with a differing revision is drift' do
    build_project
    write_lock([lock_pkg('alpha', url: alpha_url, version: '1.0.0', revision: 'a' * 40)])
    write_canonical_resolved([pin('alpha', alpha_url, version: '1.0.0', revision: 'b' * 40)])

    expect(result.status).to eq(:warn)
    expect(result.message).to include('alpha')
  end

  it 'compares revision before version — a differing version with an agreeing revision is not drift' do
    build_project
    write_lock([lock_pkg('alpha', url: alpha_url, version: '1.0.0', revision: 'a' * 40)])
    write_canonical_resolved([pin('alpha', alpha_url, version: '9.9.9', revision: 'a' * 40)])

    expect(result.status).to eq(:ok)
  end

  it 'reports ok when no lockfile exists' do
    build_project
    write_canonical_resolved([pin('alpha', alpha_url, version: '2.0.0')])

    expect(result.status).to eq(:ok)
  end

  it 'reports ok when lock and host graph agree' do
    build_project
    write_lock([lock_pkg('alpha', url: alpha_url, version: '1.0.0', revision: 'a' * 40),
                lock_pkg('beta', url: beta_url, version: '3.1.0', revision: 'c' * 40)])
    write_canonical_resolved([pin('alpha', alpha_url, version: '1.0.0', revision: 'a' * 40),
                              pin('beta', beta_url, version: '3.1.0', revision: 'c' * 40)])

    expect(result.status).to eq(:ok)
    expect(result.message).to include('2')
  end

  it 'does not shell out' do
    build_project
    write_disjoint_fixture
    expect(SPMCache::Core::Sh).not_to receive(:capture_output)

    expect(result.status).to eq(:warn)
  end

  it 'does not treat a local package as drift' do
    build_project
    write_lock([lock_pkg('alpha', url: alpha_url, version: '1.0.0', revision: 'a' * 40),
                lock_pkg('LocalKit', path_from_root: 'Modules/LocalKit')])
    write_canonical_resolved([pin('alpha', alpha_url, version: '1.0.0', revision: 'a' * 40)])

    expect(result.status).to eq(:ok)
    expect(result.message).not_to include('LocalKit')
  end

  it 'reports ok rather than raising when the host Package.resolved is unreadable' do
    build_project
    write_lock([lock_pkg('alpha', url: alpha_url, version: '1.0.0')])
    path = File.join(project_path, SPMCache::Core::PackageResolved::CANONICAL_RELATIVE_PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, '{"pins": [{"identity": "alpha"')

    expect(result.status).not_to eq(:fail)
    expect(result.message).to be_a(String)
  end

  it 'reports ok rather than raising when spm-cache.lock is unreadable' do
    build_project
    File.write(lockfile_path, '{"Fake.xcodeproj": {"packages"')
    write_canonical_resolved([pin('alpha', alpha_url, version: '2.0.0')])

    expect(result.status).not_to eq(:fail)
  end

  it 'reports ok when no xcodeproj is present' do
    write_lock([lock_pkg('alpha', url: alpha_url, version: '1.0.0')])

    expect(result.status).to eq(:ok)
  end

  it 'reports ok when the host Package.resolved cannot be located' do
    build_project
    write_lock([lock_pkg('alpha', url: alpha_url, version: '1.0.0')])

    expect(result.status).to eq(:ok)
  end

  it 'does not report whole-lock drift when the host graph parses to zero pins' do
    build_project
    write_lock((1..8).map do |i|
      lock_pkg("locked#{i}", url: "https://github.com/example/locked#{i}.git", version: '1.0.0')
    end)
    write_canonical_resolved([])

    expect(result.status).to eq(:warn)
    expect(result.message).to include('zero pins')
    expect(result.message).not_to match(/only in lock/)
  end
end
