# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# Binary-gated spec for the Swift companion's root-level --version flag. The
# Ruby doctor's companion_binary check probes `spm-cache-proxy --version` and
# appends the output as a ' (version)' suffix, so the flag must exist, exit 0,
# and print a bare semver (the single proxyVersion constant in CLI.swift,
# bumped in lockstep with the repo VERSION file). Skipped gracefully when the
# binary is not built (run make proxy.build).
RSpec.describe 'spm-cache-proxy --version (binary-gated)' do
  let(:binary) do
    local = SPMCache::ROOT.join('tools', 'spm-cache-proxy',
                                '.build', 'release', 'spm-cache-proxy').to_s
    File.executable?(local) ? local : nil
  end

  before do
    skip 'spm-cache-proxy binary not built (run make proxy.build)' unless binary
  end

  it 'prints its version with --version (exit 0), in lockstep with the repo VERSION file' do
    stdout, _stderr, status = Open3.capture3(binary, '--version')
    expect(status.exitstatus).to eq(0)
    expect(stdout.strip).to match(/\A\d+\.\d+\.\d+\z/)
    expect(stdout.strip).to eq(File.read(SPMCache::ROOT.join('VERSION')).strip)
  end

  it 'lists --version in --help' do
    stdout, stderr, status = Open3.capture3(binary, '--help')
    expect(status.exitstatus).to eq(0)
    expect(stdout + stderr).to include('--version')
  end
end
