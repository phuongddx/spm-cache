# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe SPMCache::SPM::ResolvedGraph do
  let(:tmpdir) { Dir.mktmpdir }
  let(:umbrella_dir) { File.join(tmpdir, "umbrella") }
  let(:pkg_dir) { File.join(tmpdir, "pkg") }

  before do
    FileUtils.mkdir_p(umbrella_dir)
    FileUtils.mkdir_p(pkg_dir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe ".source_for" do
    it "prefers the umbrella's own Package.resolved over host_graph_path when both exist" do
      umbrella_resolved = File.join(umbrella_dir, "Package.resolved")
      File.write(umbrella_resolved, '{"umbrella": true}')
      host_graph_path = File.join(tmpdir, "host", "Package.resolved")
      FileUtils.mkdir_p(File.dirname(host_graph_path))
      File.write(host_graph_path, '{"host": true}')

      result = described_class.source_for(umbrella_dir: umbrella_dir, host_graph_path: host_graph_path)

      expect(result).to eq(umbrella_resolved)
    end

    it "falls back to host_graph_path when the umbrella file is absent" do
      host_graph_path = File.join(tmpdir, "host", "Package.resolved")
      FileUtils.mkdir_p(File.dirname(host_graph_path))
      File.write(host_graph_path, '{"host": true}')

      result = described_class.source_for(umbrella_dir: umbrella_dir, host_graph_path: host_graph_path)

      expect(result).to eq(host_graph_path)
    end

    it "returns nil when neither the umbrella file nor host_graph_path exist" do
      result = described_class.source_for(umbrella_dir: umbrella_dir, host_graph_path: File.join(tmpdir, "nope", "Package.resolved"))

      expect(result).to be_nil
    end

    it "returns nil when host_graph_path itself is nil and the umbrella file is absent" do
      result = described_class.source_for(umbrella_dir: umbrella_dir, host_graph_path: nil)

      expect(result).to be_nil
    end
  end

  describe ".seed!" do
    it "copies the source file's bytes verbatim into pkg_dir/Package.resolved" do
      source_path = File.join(tmpdir, "source-Package.resolved")
      File.write(source_path, '{"pins": [{"identity": "below-floor"}]}')

      described_class.seed!(source_path, pkg_dir)

      expect(File.read(File.join(pkg_dir, "Package.resolved"))).to eq(File.read(source_path))
    end

    it "writes atomically via a temp file in the same directory, never leaving a partial file behind" do
      source_path = File.join(tmpdir, "source-Package.resolved")
      File.write(source_path, '{"pins": []}')

      described_class.seed!(source_path, pkg_dir)

      leftover_tmp = Dir.glob(File.join(pkg_dir, "*")).reject { |f| File.basename(f) == "Package.resolved" }
      expect(leftover_tmp).to be_empty
    end

    it "returns a snapshot marking no prior file existed, when pkg_dir had none" do
      source_path = File.join(tmpdir, "source-Package.resolved")
      File.write(source_path, '{"pins": []}')

      snapshot = described_class.seed!(source_path, pkg_dir)

      expect(snapshot[:existed]).to be false
    end

    it "returns a snapshot capturing the prior file's content, when pkg_dir already had one" do
      destination = File.join(pkg_dir, "Package.resolved")
      File.write(destination, '{"pins": ["prior-content"]}')
      source_path = File.join(tmpdir, "source-Package.resolved")
      File.write(source_path, '{"pins": ["new-content"]}')

      snapshot = described_class.seed!(source_path, pkg_dir)

      expect(snapshot[:existed]).to be true
      expect(snapshot[:content]).to eq('{"pins": ["prior-content"]}')
    end
  end

  describe ".restore!" do
    it "removes pkg_dir/Package.resolved when the snapshot marks no prior file existed" do
      destination = File.join(pkg_dir, "Package.resolved")
      File.write(destination, '{"pins": ["seeded"]}')

      described_class.restore!(pkg_dir, { existed: false })

      expect(File.exist?(destination)).to be false
    end

    it "writes back the snapshot's captured content when a prior file existed" do
      destination = File.join(pkg_dir, "Package.resolved")
      File.write(destination, '{"pins": ["seeded"]}')

      described_class.restore!(pkg_dir, { existed: true, content: '{"pins": ["prior-content"]}' })

      expect(File.read(destination)).to eq('{"pins": ["prior-content"]}')
    end
  end

  describe ".vendored_xcodeproj?" do
    it "is true when pkg_dir contains at least one *.xcodeproj entry" do
      FileUtils.mkdir_p(File.join(pkg_dir, "CryptoSwift.xcodeproj"))

      expect(described_class.vendored_xcodeproj?(pkg_dir)).to be true
    end

    it "is false when pkg_dir contains no *.xcodeproj entry" do
      expect(described_class.vendored_xcodeproj?(pkg_dir)).to be false
    end
  end
end
