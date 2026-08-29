# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe SPMCache::Command::Cache::Clean do
  let(:debug_dir) { Dir.mktmpdir("spm-cache-clean-debug") }
  let(:release_dir) { Dir.mktmpdir("spm-cache-clean-release") }
  let(:config) { instance_double(SPMCache::Core::Config) }

  before do
    allow(SPMCache::Core::Config).to receive(:instance).and_return(config)
    allow(config).to receive(:cache_dir).with("debug").and_return(debug_dir)
    allow(config).to receive(:cache_dir).with("release").and_return(release_dir)
  end

  after do
    FileUtils.rm_rf(debug_dir)
    FileUtils.rm_rf(release_dir)
  end

  def write_xcframework(dir, name)
    FileUtils.mkdir_p(File.join(dir, "#{name}.xcframework"))
  end

  def write_sidecar(dir, name, suffix)
    File.write(File.join(dir, "#{name}.xcframework.#{suffix}.json"), JSON.generate({}))
  end

  describe "#run" do
    it "removes an orphaned .provenance.json sidecar (no matching .xcframework) on a bare invocation" do
      write_sidecar(debug_dir, "Orphaned", "provenance")

      SPMCache::Command.parse(["cache", "clean"]).run

      expect(File.exist?(File.join(debug_dir, "Orphaned.xcframework.provenance.json"))).to be false
    end

    it "also removes an orphaned .shims.json sidecar" do
      write_sidecar(debug_dir, "Orphaned", "shims")

      SPMCache::Command.parse(["cache", "clean"]).run

      expect(File.exist?(File.join(debug_dir, "Orphaned.xcframework.shims.json"))).to be false
    end

    it "leaves a .provenance.json sidecar in place when its matching .xcframework still exists" do
      write_xcframework(debug_dir, "Paired")
      write_sidecar(debug_dir, "Paired", "provenance")

      SPMCache::Command.parse(["cache", "clean"]).run

      expect(File.exist?(File.join(debug_dir, "Paired.xcframework.provenance.json"))).to be true
      expect(File.directory?(File.join(debug_dir, "Paired.xcframework"))).to be true
    end

    it "reports the would-be-removed orphan sidecar under --dry without deleting it" do
      write_sidecar(debug_dir, "Orphaned", "provenance")

      output = capture_stdout { SPMCache::Command.parse(["cache", "clean", "--dry"]).run }

      expect(output).to match(/\[dry\] Would remove orphaned sidecar:.*Orphaned\.xcframework\.provenance\.json/)
      expect(File.exist?(File.join(debug_dir, "Orphaned.xcframework.provenance.json"))).to be true
    end

    it "sweeps a named target's own now-orphaned sidecars in the same invocation" do
      write_xcframework(debug_dir, "SomePkg")
      write_sidecar(debug_dir, "SomePkg", "provenance")
      write_sidecar(debug_dir, "SomePkg", "shims")

      SPMCache::Command.parse(["cache", "clean", "SomePkg.xcframework"]).run

      expect(File.directory?(File.join(debug_dir, "SomePkg.xcframework"))).to be false
      expect(File.exist?(File.join(debug_dir, "SomePkg.xcframework.provenance.json"))).to be false
      expect(File.exist?(File.join(debug_dir, "SomePkg.xcframework.shims.json"))).to be false
    end

    it "sweeps orphaned sidecars across both the debug and release cache dirs" do
      write_sidecar(debug_dir, "DebugOrphan", "provenance")
      write_sidecar(release_dir, "ReleaseOrphan", "provenance")

      SPMCache::Command.parse(["cache", "clean"]).run

      expect(File.exist?(File.join(debug_dir, "DebugOrphan.xcframework.provenance.json"))).to be false
      expect(File.exist?(File.join(release_dir, "ReleaseOrphan.xcframework.provenance.json"))).to be false
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
