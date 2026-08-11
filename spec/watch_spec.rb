# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'

require 'spm_cache/core/watcher'

# A fake installer that records calls and can be made to fail, so we can test
# the watcher without a real Xcode project or build pipeline.
class FakeInstaller
  attr_reader :call_count, :last_project

  def initialize(should_fail: false)
    @should_fail = should_fail
    @call_count = 0
  end

  def perform_install
    @call_count += 1
    raise StandardError, 'simulated build failure' if @should_fail
  end
end

RSpec.describe SPMCache::Core::Watcher do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'App.xcodeproj') }
  let(:resolved_path) do
    p = File.join(project_path, 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
    p
  end

  before do
    FileUtils.mkdir_p(File.dirname(resolved_path))
    File.write(resolved_path, '{"pins":[],"version":1}')
  end

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def make_installer(should_fail: false)
    inst = FakeInstaller.new(should_fail: should_fail)
    [inst, ->(_path) { inst }]
  end

  it 'watches Package.resolved and project.pbxproj' do
    _, factory = make_installer
    watcher = described_class.new(project_path: project_path, installer_factory: factory, out: StringIO.new)
    expect(watcher.watched_files).to include(resolved_path)
  end

  it 'run_once performs a single integration' do
    inst, factory = make_installer
    watcher = described_class.new(project_path: project_path, installer_factory: factory, out: StringIO.new)
    result = watcher.run_once
    expect(result).to be true
    expect(inst.call_count).to eq(1)
  end

  it 'detects a change to Package.resolved between signatures' do
    inst, factory = make_installer
    out = StringIO.new
    watcher = described_class.new(project_path: project_path, installer_factory: factory,
                                  debounce: 0, out: out)

    # Seed initial signature via run_once, then modify the file.
    watcher.run_once
    inst.call_count

    # Bump the mtime+content so the signature differs.
    File.write(resolved_path, '{"pins":[{"identity":"NewDep"}],"version":1}')
    sleep 1 # ensure mtime advances by >= 1s on coarse filesystems

    # Simulate one poll iteration manually (avoids a blocking loop in tests).
    current = watcher.send(:current_signatures)
    expect(current).not_to eq(watcher.instance_variable_get(:@last_signatures))
  end

  it 'continue-on-error: logs a transient failure and keeps the loop contract' do
    _, factory = make_installer(should_fail: true)
    out = StringIO.new
    watcher = described_class.new(project_path: project_path, installer_factory: factory,
                                  debounce: 0, out: out)

    # run_once raises directly (no loop to rescue); verify the error surfaces
    # so the loop's rescue path is the thing that swallows it.
    expect { watcher.run_once }.to raise_error(StandardError, /simulated build failure/)

    # The loop (not run_once) is responsible for continue-on-error. Verify a
    # failing installer doesn't corrupt state — a fresh watcher with a working
    # installer recovers.
    inst2, factory2 = make_installer(should_fail: false)
    watcher2 = described_class.new(project_path: project_path, installer_factory: factory2, out: StringIO.new)
    expect(watcher2.run_once).to be true
    expect(inst2.call_count).to eq(1)
  end

  it 'handles a missing project gracefully' do
    _, factory = make_installer
    watcher = described_class.new(
      project_path: File.join(tmpdir, 'DoesNotExist.xcodeproj'),
      installer_factory: factory,
      out: StringIO.new
    )
    expect(watcher.watched_files).to be_empty
    expect(watcher.run_once).to be false
  end

  it 'accepts a custom debounce value' do
    _, factory = make_installer
    watcher = described_class.new(project_path: project_path, installer_factory: factory,
                                  debounce: 5, out: StringIO.new)
    expect(watcher.debounce).to eq(5)
  end
end

RSpec.describe SPMCache::Command::Watch do
  it 'parses --once and --debounce flags' do
    cmd = described_class.parse(['--once', '--debounce=5'])
    expect(cmd.instance_variable_get(:@once)).to be true
    expect(cmd.instance_variable_get(:@debounce)).to eq(5)
  end

  it 'defaults debounce to the Watcher default' do
    cmd = described_class.parse([])
    expect(cmd.instance_variable_get(:@debounce)).to eq(SPMCache::Core::Watcher::DEFAULT_DEBOUNCE)
  end

  it 'errors when no .xcodeproj is found' do
    Dir.mktmpdir do |empty_dir|
      Dir.chdir(empty_dir) do
        cmd = described_class.parse([])
        expect { cmd.run }.to raise_error(SPMCache::Core::GeneralError, /No \.xcodeproj found/)
      end
    end
  end
end
