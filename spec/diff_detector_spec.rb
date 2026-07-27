# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'xcodeproj'
require 'spm_cache/core/diff_detector'

# Auto-sync diff detection: spm-cache compares the current spm-cache.lock
# snapshot against the live Xcode project SPM graph (Package.resolved +
# project.pbxproj package references) and reports a human-readable diff.
# This is the structural moat vs Scipio, which requires a separate manifest
# the user must keep in sync by hand on every dependency change.
RSpec.describe SPMCache::Core::DiffDetector do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:lockfile_path) { File.join(tmpdir, 'spm-cache.lock') }

  after { FileUtils.rm_rf(tmpdir) }

  def build_project_with_refs(remote_urls: [], local_paths: [])
    project = Xcodeproj::Project.new(project_path)
    project.new_target(:application, 'MyApp', :ios)
    remote_urls.each do |url|
      ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
      ref.repositoryURL = url
      project.root_object.package_references << ref
    end
    local_paths.each do |path|
      ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
      ref.relative_path = path
      project.root_object.package_references << ref
    end
    project.save
  end

  def write_package_resolved(pins)
    resolved_path = File.join(project_path, 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved')
    FileUtils.mkdir_p(File.dirname(resolved_path))
    File.write(resolved_path, JSON.generate(
                                'version' => 3,
                                'pins' => pins.map do |p|
                                  {
                                    'identity' => p[:identity],
                                    'kind' => 'remoteSourceControl',
                                    'location' => p[:url],
                                    'state' => { 'revision' => p[:revision] || "rev-#{p[:identity]}",
                                                 'version' => p[:version] }
                                  }
                                end
                              ))
  end

  def write_lockfile(packages, project_name = 'Fake.xcodeproj')
    File.write(lockfile_path, JSON.generate(
                                project_name => {
                                  'packages' => packages,
                                  'dependencies' => {},
                                  'platforms' => { 'ios' => '16.0' }
                                }
                              ))
  end

  def detect
    described_class.new(project_path: project_path, lockfile_path: lockfile_path).detect
  end

  describe 'no-change fast path' do
    it 'reports an empty diff when lockfile matches Package.resolved exactly' do
      write_package_resolved([
                               { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.0.0' }
                             ])
      write_lockfile([
                       { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git', 'name' => 'Alamofire',
                         'version' => '5.0.0' }
                     ])

      diff = detect
      expect(diff).to be_empty
      expect(diff.summary).to eq('No changes detected. Proxy package up to date.')
    end

    it 'normalizes ssh vs https URL variants as the same package' do
      write_package_resolved([
                               { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.0.0' }
                             ])
      write_lockfile([
                       { 'repositoryURL' => 'git@github.com:Alamofire/Alamofire.git', 'name' => 'Alamofire',
                         'version' => '5.0.0' }
                     ])

      expect(detect).to be_empty
    end

    it 'treats .git suffix as optional for identity' do
      write_package_resolved([
                               { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.0.0' }
                             ])
      write_lockfile([
                       { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire', 'name' => 'Alamofire', 'version' => '5.0.0' }
                     ])

      expect(detect).to be_empty
    end
  end

  describe 'added packages' do
    it 'detects a new package added since last run' do
      write_package_resolved([
                               { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git',
                                 version: '5.0.0' },
                               { identity: 'SnapKit', url: 'https://github.com/SnapKit/SnapKit.git', version: '5.6.0' }
                             ])
      write_lockfile([
                       { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git', 'name' => 'Alamofire',
                         'version' => '5.0.0' }
                     ])

      diff = detect
      expect(diff.added).to eq(['SnapKit'])
      expect(diff.removed).to be_empty
      expect(diff.updated).to be_empty
      expect(diff).not_to be_empty
      expect(diff.summary).to include('+1 package')
      expect(diff.summary).to include('SnapKit')
    end

    it 'detects multiple added packages' do
      write_package_resolved([
                               { identity: 'Foo', url: 'https://github.com/foo/Foo.git', version: '1.0.0' },
                               { identity: 'Bar', url: 'https://github.com/bar/Bar.git', version: '2.0.0' }
                             ])
      write_lockfile([])

      diff = detect
      expect(diff.added.size).to eq(2)
      expect(diff.added).to include('Foo', 'Bar')
    end
  end

  describe 'removed packages' do
    it 'detects a package removed since last run' do
      write_package_resolved([
                               { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.0.0' }
                             ])
      write_lockfile([
                       { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git', 'name' => 'Alamofire',
                         'version' => '5.0.0' },
                       { 'repositoryURL' => 'https://github.com/SnapKit/SnapKit.git', 'name' => 'SnapKit', 'version' => '5.6.0' }
                     ])

      diff = detect
      expect(diff.removed).to eq(['SnapKit'])
      expect(diff.added).to be_empty
      expect(diff.summary).to include('-1 package')
      expect(diff.summary).to include('SnapKit')
    end
  end

  describe 'updated packages' do
    it 'detects a version bump since last run' do
      write_package_resolved([
                               { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.10.0' }
                             ])
      write_lockfile([
                       { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git', 'name' => 'Alamofire',
                         'version' => '5.0.0' }
                     ])

      diff = detect
      expect(diff.updated).to eq(['Alamofire: 5.0.0 -> 5.10.0'])
      expect(diff.added).to be_empty
      expect(diff.removed).to be_empty
      expect(diff.summary).to include('~1 updated')
    end

    it 'detects a revision change when version is absent' do
      write_package_resolved([
                               { identity: 'Local', url: 'https://github.com/foo/Local.git', version: nil, revision: 'abc123' }
                             ])
      write_lockfile([
                       { 'repositoryURL' => 'https://github.com/foo/Local.git', 'name' => 'Local', 'revision' => 'oldrev' }
                     ])

      diff = detect
      expect(diff.updated).to eq(['Local: oldrev -> abc123'])
    end
  end

  describe 'mixed diff' do
    it 'reports added + removed + updated together' do
      write_package_resolved([
                               { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git',
                                 version: '5.10.0' },
                               { identity: 'NewDep', url: 'https://github.com/new/NewDep.git', version: '1.0.0' }
                             ])
      write_lockfile([
                       { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git', 'name' => 'Alamofire',
                         'version' => '5.0.0' },
                       { 'repositoryURL' => 'https://github.com/old/Removed.git', 'name' => 'Removed', 'version' => '1.0.0' }
                     ])

      diff = detect
      expect(diff.added).to eq(['NewDep'])
      expect(diff.removed).to eq(['Removed'])
      expect(diff.updated).to eq(['Alamofire: 5.0.0 -> 5.10.0'])
      expect(diff.total).to eq(3)
    end
  end

  describe 'missing lockfile (first run)' do
    it 'reports everything as added when no lockfile exists' do
      write_package_resolved([
                               { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.0.0' }
                             ])

      diff = detect
      expect(diff.added).to eq(['Alamofire'])
      expect(diff).not_to be_empty
    end
  end

  describe 'project.pbxproj local package refs' do
    it 'supplements Package.resolved with local package refs from the project' do
      build_project_with_refs(local_paths: ['LocalPackages/core-utils'])
      # No Package.resolved -- local-only project
      write_lockfile([])

      diff = detect
      expect(diff.added).to include('core-utils')
    end

    it 'ignores the spm-cache proxy ref as a real dependency' do
      build_project_with_refs(local_paths: [
                                'LocalPackages/core-utils',
                                'spm-cache/packages/proxy'
                              ])
      write_lockfile([])

      diff = detect
      expect(diff.added).to include('core-utils')
      expect(diff.added).not_to include('proxy')
    end
  end

  describe 'Diff summary format (acceptance criteria)' do
    it 'matches the acceptance text for added packages' do
      write_package_resolved([
                               { identity: 'Foo', url: 'https://github.com/x/Foo.git', version: '1.0.0' },
                               { identity: 'Bar', url: 'https://github.com/x/Bar.git', version: '1.0.0' }
                             ])
      write_lockfile([])

      diff = detect
      expect(diff.summary).to eq('Detected: +2 packages (Foo, Bar). Regenerating proxy package.')
    end

    it 'matches the acceptance text for no changes' do
      write_package_resolved([
                               { identity: 'Foo', url: 'https://github.com/x/Foo.git', version: '1.0.0' }
                             ])
      write_lockfile([
                       { 'repositoryURL' => 'https://github.com/x/Foo.git', 'name' => 'Foo', 'version' => '1.0.0' }
                     ])

      expect(detect.summary).to eq('No changes detected. Proxy package up to date.')
    end
  end
end
