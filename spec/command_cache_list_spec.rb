# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe SPMCache::Command::Cache::List do
  let(:debug_dir) { Dir.mktmpdir('spm-cache-list-debug') }
  let(:release_dir) { Dir.mktmpdir('spm-cache-list-release') }
  let(:config) { instance_double(SPMCache::Core::Config) }

  before do
    allow(SPMCache::Core::Config).to receive(:instance).and_return(config)
    allow(config).to receive(:cache_dir).with('debug').and_return(debug_dir)
    allow(config).to receive(:cache_dir).with('release').and_return(release_dir)
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

  describe '#run' do
    it "prints a cached package's fidelity status read from its provenance sidecar" do
      write_xcframework(debug_dir, 'CachedLib')
      write_sidecar(debug_dir, 'CachedLib', JSON.generate(
                                              fidelity_status: 'host-pinned',
                                              pins: {},
                                              spm_cache_version: '0.4.0',
                                              config: 'debug',
                                              destinations: ['iphonesimulator']
                                            ))

      expect { SPMCache::Command.parse(%w[cache list]).run }.to output(/CachedLib.*host-pinned/m).to_stdout
    end

    it 'reports not-graph-pinned for a cached package with no sidecar at all' do
      write_xcframework(debug_dir, 'NoSidecarLib')

      expect { SPMCache::Command.parse(%w[cache list]).run }.to output(/NoSidecarLib.*not-graph-pinned/m).to_stdout
    end

    it 'reports not-graph-pinned for a malformed (truncated) sidecar without raising' do
      write_xcframework(debug_dir, 'MalformedLib')
      write_sidecar(debug_dir, 'MalformedLib', '{"fidelity_status": "host-pinned"')

      expect { SPMCache::Command.parse(%w[cache list]).run }.not_to raise_error
      expect { SPMCache::Command.parse(%w[cache list]).run }.to output(/MalformedLib.*not-graph-pinned/m).to_stdout
    end

    it 'reports not-graph-pinned when the sidecar is valid JSON but missing fidelity_status' do
      write_xcframework(debug_dir, 'NoStatusKeyLib')
      write_sidecar(debug_dir, 'NoStatusKeyLib', JSON.generate(pins: {}, config: 'debug'))

      expect { SPMCache::Command.parse(%w[cache list]).run }.to output(/NoStatusKeyLib.*not-graph-pinned/m).to_stdout
    end

    it 'reports not-graph-pinned for a sidecar that is valid JSON but not a Hash (e.g. a truncated-but-valid array)' do
      write_xcframework(debug_dir, 'ArrayPayloadLib')
      write_sidecar(debug_dir, 'ArrayPayloadLib', JSON.generate(%w[not a hash]))

      expect { SPMCache::Command.parse(%w[cache list]).run }.not_to raise_error
      expect do
        SPMCache::Command.parse(%w[cache list]).run
      end.to output(/ArrayPayloadLib.*not-graph-pinned/m).to_stdout
    end

    it 'reports not-graph-pinned instead of crashing the whole listing when the sidecar disappears between the exist? check and the read (TOCTOU race)' do
      write_xcframework(debug_dir, 'RacyLib')
      write_xcframework(debug_dir, 'ZAfterRacy')
      write_sidecar(debug_dir, 'ZAfterRacy', JSON.generate(fidelity_status: 'host-pinned'))
      racy_sidecar = File.join(debug_dir, 'RacyLib.xcframework.provenance.json')
      write_sidecar(debug_dir, 'RacyLib', JSON.generate(fidelity_status: 'host-pinned'))

      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(racy_sidecar).and_raise(Errno::ENOENT)

      output = capture_stdout { SPMCache::Command.parse(%w[cache list]).run }

      expect(output).to match(/RacyLib.*not-graph-pinned/)
      expect(output).to match(/ZAfterRacy.*host-pinned/)
    end

    it 'never prints a sidecar file as its own spurious package entry' do
      write_xcframework(debug_dir, 'CachedLib')
      write_sidecar(debug_dir, 'CachedLib', JSON.generate(fidelity_status: 'host-pinned'))

      output = capture_stdout { SPMCache::Command.parse(%w[cache list]).run }

      expect(output).not_to match(/provenance\.json/)
      expect(output).not_to match(/shims\.json/)
    end

    it 'lists multiple cached modules across both debug and release configs, sorted alphabetically per config' do
      write_xcframework(debug_dir, 'Zebra')
      write_sidecar(debug_dir, 'Zebra', JSON.generate(fidelity_status: 'host-pinned'))
      write_xcframework(debug_dir, 'Alpha')
      write_sidecar(debug_dir, 'Alpha', JSON.generate(fidelity_status: 'resolution-incompatible'))

      write_xcframework(release_dir, 'Beta')
      write_sidecar(release_dir, 'Beta', JSON.generate(fidelity_status: 'host-pinned'))

      output = capture_stdout { SPMCache::Command.parse(%w[cache list]).run }

      debug_section = output[/Debug:.*(?=\nRelease:)/m] || output[/Debug:.*/m]
      expect(debug_section.index('Alpha')).to be < debug_section.index('Zebra')
      expect(output).to match(/Release:\n\s*Beta \(host-pinned\)/)
    end

    it 'prints byte-identical output sourced from the shared Cache::Inventory scan (13-02 refactor pin)' do
      write_xcframework(debug_dir, 'Alpha')
      write_sidecar(debug_dir, 'Alpha', JSON.generate(fidelity_status: 'host-pinned'))
      write_xcframework(debug_dir, 'Zebra')
      write_xcframework(release_dir, 'Beta')
      write_sidecar(release_dir, 'Beta', JSON.generate(fidelity_status: 'resolution-incompatible'))

      output = capture_stdout { SPMCache::Command.parse(%w[cache list]).run }

      expect(output).to eq("\nDebug:\n  Alpha (host-pinned)\n  Zebra (not-graph-pinned)\n\nRelease:\n  Beta (resolution-incompatible)\n")
    end

    it 'still prints the config header with no rows when a cache_dir has zero cached xcframeworks' do
      output = capture_stdout { SPMCache::Command.parse(%w[cache list]).run }

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

RSpec.describe SPMCache::Cache::Inventory do
  # 13-02: the shared cache-dir scan (one source of truth for `cache
  # list` and the web state read model). The cache_root seam keeps these
  # specs off the real ~/.spm-cache.
  let(:cache_root) { Dir.mktmpdir('spm-cache-inventory-root') }

  after { FileUtils.rm_rf(cache_root) }

  def write_xcframework(cfg, name, nested_bytes: 0)
    fw = File.join(cache_root, cfg, "#{name}.xcframework")
    FileUtils.mkdir_p(fw)
    File.write(File.join(fw, 'binary.dat'), 'x' * nested_bytes) if nested_bytes.positive?
    fw
  end

  def write_sidecar(cfg, name, content)
    File.write(File.join(cache_root, cfg, "#{name}.xcframework.provenance.json"), content)
  end

  def scan
    described_class.scan(cache_root: cache_root)
  end

  it 'returns one entry per cached xcframework across debug and release, sorted by config then name' do
    write_xcframework('debug', 'Ziph')
    write_sidecar('debug', 'Ziph', JSON.generate(fidelity_status: 'resolution-incompatible'))
    write_xcframework('debug', 'Alamofire', nested_bytes: 100)
    write_xcframework('release', 'Alamofire')

    entries = scan

    expect(entries.map { |e| [e.config, e.name] }).to eq(
      [%w[debug Alamofire], %w[debug Ziph], %w[release Alamofire]]
    )
    expect(entries.map(&:fidelity)).to eq(%w[not-graph-pinned resolution-incompatible not-graph-pinned])
  end

  it 'exposes keyword-struct entries answering name, config, size_bytes, and fidelity' do
    write_xcframework('debug', 'Alamofire')

    entry = scan.first

    expect(entry).to respond_to(:name, :config, :size_bytes, :fidelity)
    expect(entry.name).to eq('Alamofire')
    expect(entry.config).to eq('debug')
    expect(entry.size_bytes).to be_an(Integer)
  end

  it "sums size_bytes recursively: the framework dir's own lstat plus every nested entry's lstat" do
    fw = write_xcframework('debug', 'Alamofire', nested_bytes: 100)
    nested_dir = File.join(fw, 'ios-arm64')
    FileUtils.mkdir_p(nested_dir)
    File.write(File.join(nested_dir, 'slice.bin'), 'y' * 250)

    expected = File.lstat(fw).size +
               [File.join(fw, 'binary.dat'), nested_dir, File.join(nested_dir, 'slice.bin')].sum do |p|
                 File.lstat(p).size
               end

    expect(scan.first.size_bytes).to eq(expected)
    expect(scan.first.size_bytes).to be > 350
  end

  it 'counts a symlinked entry at its link size, never following it (cache dirs may hold symlinked slices)' do
    fw = write_xcframework('debug', 'Alamofire')
    big_target = File.join(cache_root, 'big-target.bin')
    File.write(big_target, 'z' * 4096)
    FileUtils.ln_s(big_target, File.join(fw, 'symlinked-slice'))

    link_size = File.lstat(File.join(fw, 'symlinked-slice')).size

    expect(scan.first.size_bytes).to eq(File.lstat(fw).size + link_size)
    expect(scan.first.size_bytes).to be < File.lstat(fw).size + 4096
  end

  it 'reports not-graph-pinned for an absent sidecar' do
    write_xcframework('debug', 'NoSidecar')

    expect(scan.first.fidelity).to eq('not-graph-pinned')
  end

  it 'reports not-graph-pinned for a malformed (truncated) sidecar' do
    write_xcframework('debug', 'Malformed')
    write_sidecar('debug', 'Malformed', '{"fidelity_status": "host-pinned"')

    expect(scan.first.fidelity).to eq('not-graph-pinned')
  end

  it 'reports not-graph-pinned for a sidecar that is valid JSON but not a Hash' do
    write_xcframework('debug', 'ArrayPayload')
    write_sidecar('debug', 'ArrayPayload', JSON.generate(%w[not a hash]))

    expect(scan.first.fidelity).to eq('not-graph-pinned')
  end

  it 'reports not-graph-pinned for a sidecar missing the fidelity_status key' do
    write_xcframework('debug', 'NoStatusKey')
    write_sidecar('debug', 'NoStatusKey', JSON.generate(pins: {}, config: 'debug'))

    expect(scan.first.fidelity).to eq('not-graph-pinned')
  end

  it "reads the sidecar's fidelity_status verbatim when present" do
    write_xcframework('debug', 'Pinned')
    write_sidecar('debug', 'Pinned', JSON.generate(fidelity_status: 'host-pinned'))

    expect(scan.first.fidelity).to eq('host-pinned')
  end

  it 'returns an empty array without raising when the cache root has no config dirs at all' do
    expect(scan).to eq([])
  end
end
