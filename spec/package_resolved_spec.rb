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
  end
end
