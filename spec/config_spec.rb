# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'

RSpec.describe SPMCache::Core::Config do
  subject(:config) { described_class.instance }

  before do
    config.reset!
    config.project_dir = '/tmp/test-project'
  end

  describe '#sandbox_dir' do
    it 'returns project_dir/spm-cache' do
      expect(config.sandbox_dir).to eq('/tmp/test-project/spm-cache')
    end
  end

  describe '#cache_dir' do
    it 'returns global cache without args' do
      expect(config.cache_dir).to match(/\.spm-cache$/)
    end

    it 'returns config-specific dir with args' do
      expect(config.cache_dir('debug')).to match(%r{\.spm-cache/debug$})
    end
  end

  describe '#default_sdk' do
    it 'returns iphonesimulator by default' do
      expect(config.default_sdk).to eq('iphonesimulator')
    end
  end

  # Retention budgets (D-06: keep the newest runs_keep run logs, then prune
  # oldest until the total is under runs_max_mb MB; defaults 50 / 500).
  # Config is a Singleton -- the outer before's reset! keeps raw at
  # DEFAULT_CONFIG for every example.
  describe '#runs_keep and #runs_max_mb' do
    def write_yml(keys)
      dir = Dir.mktmpdir
      path = File.join(dir, 'spm-cache.yml')
      File.write(path, YAML.dump(keys))
      config.config_path = path
      config.load
    ensure
      FileUtils.remove_entry(dir)
    end

    it 'default to 50 runs / 500 MB with no yml keys' do
      expect(config.runs_keep).to eq(50)
      expect(config.runs_max_mb).to eq(500)
    end

    it 'read overrides from a written spm-cache.yml' do
      write_yml('runs_keep' => 3, 'runs_max_mb' => 12)
      expect(config.runs_keep).to eq(3)
      expect(config.runs_max_mb).to eq(12)
    end

    it 'coerces a non-integer runs_keep back to 50 (yml is user-authored, not adversarial — research V5)' do
      config.raw['runs_keep'] = 'many'
      expect(config.runs_keep).to eq(50)
    end

    it 'coerces a nil runs_max_mb back to 500' do
      config.raw['runs_max_mb'] = nil
      expect(config.runs_max_mb).to eq(500)
    end
  end

  # Dashboard state-table auto-poll interval (13-UI-SPEC
  # "server-configurable"). Same Integer-coercion posture as runs_keep:
  # spm-cache.yml is user-authored, not adversarial (research V5).
  describe '#web_poll_seconds' do
    def write_yml(keys)
      dir = Dir.mktmpdir
      path = File.join(dir, 'spm-cache.yml')
      File.write(path, YAML.dump(keys))
      config.config_path = path
      config.load
    ensure
      FileUtils.remove_entry(dir)
    end

    it 'defaults to 5' do
      expect(config.web_poll_seconds).to eq(5)
    end

    it 'reads an override from a written spm-cache.yml' do
      write_yml('web_poll_seconds' => 12)
      expect(config.web_poll_seconds).to eq(12)
    end

    it 'coerces a non-integer back to 5' do
      config.raw['web_poll_seconds'] = 'often'
      expect(config.web_poll_seconds).to eq(5)
    end

    it 'coerces nil back to 5' do
      config.raw['web_poll_seconds'] = nil
      expect(config.web_poll_seconds).to eq(5)
    end
  end

  describe 'spm-cache.yml template' do
    it 'documents the retention keys as commented defaults (discoverability surface, D-06)' do
      template = SPMCache::ROOT.join('lib/spm_cache/assets/templates/spm-cache.yml.template').read
      expect(template).to include('# runs_keep: 50')
      expect(template).to include('# runs_max_mb: 500')
    end

    it 'documents web_poll_seconds as a commented default (dashboard poll interval)' do
      template = SPMCache::ROOT.join('lib/spm_cache/assets/templates/spm-cache.yml.template').read
      expect(template).to include('# web_poll_seconds: 5')
    end
  end

  describe '#ignore_list' do
    it 'returns empty array by default' do
      expect(config.ignore_list).to eq([])
    end
  end

  describe '#cache_only_list' do
    it 'returns empty array by default' do
      expect(config.cache_only_list).to eq([])
    end

    it 'reads from config.raw' do
      config.raw['cache_only'] = ['Alamofire']
      expect(config.cache_only_list).to eq(['Alamofire'])
    end
  end

  # Glob-semantics parity cases (mirrored in spec/proxy_executable_spec.rb
  # Swift fixture check and spec/fixtures/ignore-lockfile.json). Keep these in
  # sync so Ruby File.fnmatch and Swift fnmatch agree.
  describe '#should_ignore?' do
    before { config.raw['ignore'] = ['Test*', 'MyCompany?', 'ExactName'] }

    it 'matches prefix glob' do
      expect(config.should_ignore?('TestPackage')).to be true
    end

    it 'matches single-char wildcard' do
      expect(config.should_ignore?('MyCompanyX')).to be true
    end

    it 'matches exact name' do
      expect(config.should_ignore?('ExactName')).to be true
    end

    it 'does not match unrelated names' do
      expect(config.should_ignore?('OtherPackage')).to be false
    end

    it 'does not match single-char wildcard with wrong length' do
      expect(config.should_ignore?('MyCompany')).to be false
      expect(config.should_ignore?('MyCompanyXX')).to be false
    end

    context 'with empty ignore list' do
      before { config.raw['ignore'] = [] }

      it 'ignores nothing' do
        expect(config.should_ignore?('Anything')).to be false
      end
    end
  end
end
