# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'rubygems/package'
require 'fileutils'
require 'open3'

# Packaging pins for the web dashboard (13-04): what ships in
# spec.files is what users run, so a dropped asset or a missing
# dependency is a silent shipping bug, not just a regression. Two
# load-bearing facts from the research are made checkable here:
#   - the {lib,…}/**/* glob actually ships lib/spm_cache/web/assets/**
#     (13-CONTEXT "Frontend Architecture" — "gemspec glob ships the
#     dir"; T-13-19), plus a real `gem build` smoke proving a built
#     .gem carries the four assets;
#   - webrick is declared as a runtime dependency pinned >= 1.8, < 2
#     (research CP8 — `require` fails on every target ruby without
#     the declaration; the require smoke runs under the bundler
#     context, the gemspec pin is the load-bearing half).
# The offline-set twin re-asserts 13-03's gate over the PACKAGED set:
# first-party assets byte-grepped, the vendored cytoscape pinned
# structurally only (its bundled MIT attribution legitimately names
# external hosts).
ASSET_DIR = 'lib/spm_cache/web/assets'
FOUR_ASSETS = %w[index.html app.js styles.css cytoscape.min.js]
              .map { |name| "#{ASSET_DIR}/#{name}" }.freeze
FIRST_PARTY = %w[index.html app.js styles.css]
              .map { |name| "#{ASSET_DIR}/#{name}" }.freeze

RSpec.describe 'spm-cache gem packaging' do
  let(:gemspec_path) { File.join(SPMCache::ROOT, 'spm_cache.gemspec') }
  let(:spec) { Gem::Specification.load(gemspec_path) }

  describe 'spec.files ships the dashboard (T-13-19)' do
    it 'includes all four dashboard assets' do
      expect(spec.files).to include(*FOUR_ASSETS)
    end

    it 'glob-ships the dir: every file on disk under web/assets is packaged' do
      on_disk = Dir.glob("#{ASSET_DIR}/*", base: SPMCache::ROOT.to_s)
                   .select { |f| File.file?(File.join(SPMCache::ROOT, f)) }
      expect(on_disk).not_to be_empty
      expect(spec.files).to include(*on_disk),
                            "files under #{ASSET_DIR} missing from the gemspec glob — " \
                            'a future narrowing silently drops the dashboard'
    end
  end

  describe 'webrick runtime declaration (CP8)' do
    it 'declares webrick >= 1.8, < 2 as a runtime dependency' do
      dep = spec.runtime_dependencies.find { |d| d.name == 'webrick' }
      expect(dep).not_to be_nil,
                         'webrick must be a declared runtime dependency — require fails on ' \
                         'every target ruby without it (research CP8)'

      requirement = dep.requirement
      expect(requirement.satisfied_by?(Gem::Version.new('1.8'))).to be(true)
      expect(requirement.satisfied_by?(Gem::Version.new('1.9.2'))).to be(true)
      expect(requirement.satisfied_by?(Gem::Version.new('2.0'))).to be(false)
      expect(requirement.satisfied_by?(Gem::Version.new('2.1'))).to be(false)
    end

    it "require 'webrick' succeeds in-process (CP8 smoke)" do
      expect { require 'webrick' }.not_to raise_error
    end
  end

  describe 'real gem build smoke' do
    it 'packages the four dashboard assets into a built .gem' do
      skip 'gem CLI unavailable' unless system('gem', '--version', out: File::NULL, err: File::NULL)

      Dir.mktmpdir('spm-cache-gemspec-build') do |tmp|
        # The gemspec's Dir[] globs evaluate relative to the CWD, so a
        # minimal packaging tree stands in for the repo: lib + bin +
        # the top-level entries the files list names (tools/ and
        # assets/ match nothing there — nothing asserted on lives in
        # them). No network, no working-tree pollution; the .gem dies
        # with the tmpdir.
        FileUtils.cp_r(File.join(SPMCache::ROOT, 'lib'), tmp)
        FileUtils.cp_r(File.join(SPMCache::ROOT, 'bin'), tmp)
        FileUtils.mkdir_p(File.join(tmp, 'tools'))
        FileUtils.mkdir_p(File.join(tmp, 'assets'))
        %w[Gemfile LICENSE.txt README.md VERSION Makefile spm_cache.gemspec].each do |f|
          FileUtils.cp(File.join(SPMCache::ROOT, f), tmp)
        end

        out, err, status = Open3.capture3('gem', 'build', 'spm_cache.gemspec', chdir: tmp)
        expect(status.success?).to be(true), "gem build failed:\n#{out}\n#{err}"

        gems = Dir.glob(File.join(tmp, '*.gem'))
        expect(gems.size).to eq(1), "expected exactly one built .gem, found #{gems.size}"
        built = Gem::Package.new(gems.first).spec
        expect(built.files).to include(*FOUR_ASSETS)
      end
    end
  end

  describe 'offline set twin over the packaged first-party assets (SC3)' do
    it 'carries zero scheme-absolute URLs and zero cdn. references' do
      FIRST_PARTY.each do |rel|
        expect(spec.files).to include(rel)
        content = File.read(File.join(SPMCache::ROOT, rel))
        expect(content).not_to match(%r{https?://}i),
                               "#{rel} must stay offline — scheme-absolute URL found"
        expect(content).not_to match(/cdn\./i),
                               "#{rel} must stay offline — cdn. reference found"
      end
    end

    it 'ships cytoscape.min.js with structural pins only (never byte-gated)' do
      rel = "#{ASSET_DIR}/cytoscape.min.js"
      expect(spec.files).to include(rel)

      path = File.join(SPMCache::ROOT, rel)
      first_line = File.readlines(path).first
      expect(first_line).to match(/cytoscape.*\d+\.\d+\.\d+/),
                            'vendored cytoscape records its version in a first-line comment'
      expect(first_line).not_to match(%r{https?://}i)
      expect(File.size(path)).to be > 300 * 1024
    end
  end
end
