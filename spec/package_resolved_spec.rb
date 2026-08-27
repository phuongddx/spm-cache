# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

# FID-06 regression coverage. The shared idiom this locator replaces --
# `Dir.glob(File.join(root, '**/Package.resolved')).find { |f| File.exist?(f) }`
# -- was measured returning a git-ignored nested copy of the file on the
# reference project (8 pins, frozen 2026-07-12) instead of the canonical file
# Xcode maintains (17 pins, 2026-08-13), purely because `S` sorts before `p`.
# Every example here pins a behavior byte order could not guarantee.
RSpec.describe SPMCache::Core::PackageResolved do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }

  after { FileUtils.rm_rf(tmpdir) }

  def write_resolved(path, identities)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(
                       'version' => 3,
                       'pins' => identities.map do |identity|
                         {
                           'identity' => identity,
                           'kind' => 'remoteSourceControl',
                           'location' => "https://github.com/example/#{identity}.git",
                           'state' => { 'revision' => "rev-#{identity}", 'version' => '1.0.0' }
                         }
                       end
                     ))
    path
  end

  def canonical_path(root = project_path)
    File.join(root, described_class::CANONICAL_RELATIVE_PATH)
  end

  # The measured reference-project shape: a second `.xcodeproj` bundle nested
  # inside the first, carrying its own stale `Package.resolved`.
  def nested_path(root = project_path)
    File.join(root, 'Fake.xcodeproj', described_class::CANONICAL_RELATIVE_PATH)
  end

  def legacy_glob(root)
    Dir.glob(File.join(root, '**/Package.resolved')).find { |f| File.exist?(f) }
  end

  describe '.locate' do
    it 'prefers the canonical Package.resolved over a nested duplicate' do
      write_resolved(canonical_path, ['alpha'])
      write_resolved(nested_path, ['beta'])

      expect(legacy_glob(project_path)).to eq(nested_path)
      expect(described_class.locate(project_path)).to eq(canonical_path)
    end

    it 'returns nil when no Package.resolved exists anywhere under the root' do
      FileUtils.mkdir_p(project_path)

      expect { described_class.locate(project_path) }.not_to raise_error
      expect(described_class.locate(project_path)).to be_nil
    end

    it 'falls back to the parent directory only when parent_fallback is true' do
      FileUtils.mkdir_p(project_path)
      parent_copy = write_resolved(File.join(tmpdir, 'Package.resolved'), ['alpha'])

      expect(described_class.locate(project_path)).to be_nil
      expect(described_class.locate(project_path, parent_fallback: true)).to eq(parent_copy)
    end

    # spm-cache writes these itself, one level above the .xcodeproj -- directly
    # inside the parent-fallback search space. Adopting its own generated
    # artifact as the host graph makes the tool authoritative over its input.
    it 'never returns a sandbox Package.resolved' do
      FileUtils.mkdir_p(project_path)
      sandbox = File.join(tmpdir, SPMCache::Core::Config::SANDBOX_DIR, 'packages')
      write_resolved(File.join(sandbox, 'umbrella', 'Package.resolved'), ['alpha'])
      write_resolved(File.join(sandbox, 'proxy', 'Package.resolved'), ['beta'])

      expect(described_class.locate(project_path, parent_fallback: true)).to be_nil
    end

    it 'excludes a candidate nested under a second .xcodeproj component' do
      write_resolved(nested_path, ['beta'])

      expect(legacy_glob(project_path)).to eq(nested_path)
      expect(described_class.locate(project_path)).to be_nil
    end

    # Scoping the .xcodeproj exclusion to the recursive-under-root tier must not
    # hand the project's own nested copy a second entrance via the parent.
    it "does not re-adopt the project's own nested copy via the parent fallback" do
      write_resolved(nested_path, ['beta'])

      expect(described_class.locate(project_path, parent_fallback: true)).to be_nil
    end

    it 'prefers a sibling xcworkspace resolved file over a recursive match' do
      workspace_copy = write_resolved(
        File.join(tmpdir, 'App.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved'), ['alpha']
      )
      write_resolved(File.join(project_path, 'deep', 'nest', 'Package.resolved'), ['beta'])

      expect(described_class.locate(project_path)).to eq(workspace_copy)
    end

    it 'breaks ties on newest mtime within the recursive tier' do
      older = write_resolved(File.join(project_path, 'a', 'Package.resolved'), ['alpha'])
      newer = write_resolved(File.join(project_path, 'b', 'deeper', 'Package.resolved'), ['beta'])
      File.utime(Time.now - 600, Time.now - 600, older)

      expect(described_class.locate(project_path)).to eq(newer)
    end

    # command/use.rb passes a relative root, prints the located path, and keys
    # its watch signature on it.
    it 'returns a path shaped like the root it was given' do
      write_resolved(canonical_path, ['alpha'])

      located = Dir.chdir(tmpdir) { described_class.locate('Fake.xcodeproj') }

      expect(located).to eq(File.join('Fake.xcodeproj', described_class::CANONICAL_RELATIVE_PATH))
      expect(located).not_to start_with('/')
    end
  end

  describe '.pins / .pins_or_nil' do
    it 'raises on malformed JSON via pins and returns nil via pins_or_nil' do
      truncated = File.join(tmpdir, 'Truncated.json')
      FileUtils.mkdir_p(tmpdir)
      File.write(truncated, '{"pins": [')

      expect { described_class.pins(truncated) }.to raise_error(JSON::ParserError)
      expect(described_class.pins_or_nil(truncated)).to be_nil
    end

    # Conflating these two turns "unreadable" into "the host has no packages",
    # which under the drop rule would erase the whole lock.
    it 'distinguishes an unreadable file from a readable empty pin list' do
      readable_empty = write_resolved(File.join(tmpdir, 'Empty.json'), [])
      absent = File.join(tmpdir, 'Absent.json')

      expect(described_class.pins_or_nil(readable_empty)).to eq([])
      expect(described_class.pins_or_nil(absent)).to be_nil
    end

    it 'rejects a resolved file whose pins are not an array' do
      wrong_shape = File.join(tmpdir, 'WrongShape.json')
      FileUtils.mkdir_p(tmpdir)
      File.write(wrong_shape, JSON.generate('version' => 3, 'pins' => 'nope'))

      expect(described_class.pins_or_nil(wrong_shape)).to be_nil
    end

    it 'skips a pin that is not an object' do
      mixed = File.join(tmpdir, 'Mixed.json')
      FileUtils.mkdir_p(tmpdir)
      valid_pin = {
        'identity' => 'alpha',
        'kind' => 'remoteSourceControl',
        'location' => 'https://github.com/example/alpha.git',
        'state' => { 'revision' => 'rev-alpha', 'version' => '1.0.0' }
      }
      File.write(mixed, JSON.generate('version' => 3, 'pins' => [valid_pin, 'not-a-pin']))

      expect(described_class.pins_or_nil(mixed)).to eq([valid_pin])
    end
  end
end
