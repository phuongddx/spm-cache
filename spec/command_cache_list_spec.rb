# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe SPMCache::Command::Cache::List do
  let(:debug_dir) { Dir.mktmpdir("spm-cache-list-debug") }
  let(:release_dir) { Dir.mktmpdir("spm-cache-list-release") }
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

  def write_sidecar(dir, name, content)
    File.write(File.join(dir, "#{name}.xcframework.provenance.json"), content)
  end

  describe "#run" do
    it "prints a cached package's fidelity status read from its provenance sidecar" do
      write_xcframework(debug_dir, "CachedLib")
      write_sidecar(debug_dir, "CachedLib", JSON.generate(
                                               fidelity_status: "host-pinned",
                                               pins: {},
                                               spm_cache_version: "0.4.0",
                                               config: "debug",
                                               destinations: ["iphonesimulator"],
                                             ))

      expect { SPMCache::Command.parse(["cache", "list"]).run }.to output(/CachedLib.*host-pinned/m).to_stdout
    end

    it "reports not-graph-pinned for a cached package with no sidecar at all" do
      write_xcframework(debug_dir, "NoSidecarLib")

      expect { SPMCache::Command.parse(["cache", "list"]).run }.to output(/NoSidecarLib.*not-graph-pinned/m).to_stdout
    end

    it "reports not-graph-pinned for a malformed (truncated) sidecar without raising" do
      write_xcframework(debug_dir, "MalformedLib")
      write_sidecar(debug_dir, "MalformedLib", '{"fidelity_status": "host-pinned"')

      expect { SPMCache::Command.parse(["cache", "list"]).run }.not_to raise_error
      expect { SPMCache::Command.parse(["cache", "list"]).run }.to output(/MalformedLib.*not-graph-pinned/m).to_stdout
    end

    it "reports not-graph-pinned when the sidecar is valid JSON but missing fidelity_status" do
      write_xcframework(debug_dir, "NoStatusKeyLib")
      write_sidecar(debug_dir, "NoStatusKeyLib", JSON.generate(pins: {}, config: "debug"))

      expect { SPMCache::Command.parse(["cache", "list"]).run }.to output(/NoStatusKeyLib.*not-graph-pinned/m).to_stdout
    end

    it "never prints a sidecar file as its own spurious package entry" do
      write_xcframework(debug_dir, "CachedLib")
      write_sidecar(debug_dir, "CachedLib", JSON.generate(fidelity_status: "host-pinned"))

      output = capture_stdout { SPMCache::Command.parse(["cache", "list"]).run }

      expect(output).not_to match(/provenance\.json/)
      expect(output).not_to match(/shims\.json/)
    end

    it "lists multiple cached modules across both debug and release configs, sorted alphabetically per config" do
      write_xcframework(debug_dir, "Zebra")
      write_sidecar(debug_dir, "Zebra", JSON.generate(fidelity_status: "host-pinned"))
      write_xcframework(debug_dir, "Alpha")
      write_sidecar(debug_dir, "Alpha", JSON.generate(fidelity_status: "resolution-incompatible"))

      write_xcframework(release_dir, "Beta")
      write_sidecar(release_dir, "Beta", JSON.generate(fidelity_status: "host-pinned"))

      output = capture_stdout { SPMCache::Command.parse(["cache", "list"]).run }

      debug_section = output[/Debug:.*(?=\nRelease:)/m] || output[/Debug:.*/m]
      expect(debug_section.index("Alpha")).to be < debug_section.index("Zebra")
      expect(output).to match(/Release:\n\s*Beta \(host-pinned\)/)
    end

    it "still prints the config header with no rows when a cache_dir has zero cached xcframeworks" do
      output = capture_stdout { SPMCache::Command.parse(["cache", "list"]).run }

      expect(output).to match(/Debug:/)
      expect(output).to match(/Release:/)
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
