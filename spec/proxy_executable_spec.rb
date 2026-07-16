# frozen_string_literal: true

require "spec_helper"

# Glob-semantics parity cases are mirrored in spec/config_spec.rb.
RSpec.describe SPMCache::SPM::Package::ProxyExecutable do
  subject(:exec) { described_class.new(version: "0.0.0-test") }

  let(:captured_cmds) { [] }

  before do
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, _opts = {}|
      captured_cmds << cmd
      { output: "", status: 0 }
    end
    # Bypass binary lookup so we never shell out to swift build.
    allow(exec).to receive(:path).and_return("/fake/spm-cache-proxy")
  end

  describe "#gen_proxy with ignore list" do
    it "appends single-quoted --ignore CSV" do
      exec.gen_proxy(
        umbrella_dir: "/u",
        output_dir: "/o",
        cache_dir: "/c",
        lockfile_path: "/l.lock",
        ignore: ["VolatileLib", "MyCompany*"],
      )
      cmd = captured_cmds.first
      expect(cmd).to include("--ignore 'VolatileLib,MyCompany*'")
    end

    it "omits --ignore when list is empty" do
      exec.gen_proxy(
        umbrella_dir: "/u",
        output_dir: "/o",
        cache_dir: "/c",
        lockfile_path: "/l.lock",
        ignore: [],
      )
      cmd = captured_cmds.first
      expect(cmd).not_to include("--ignore")
    end

    it "omits --ignore when kwarg not passed" do
      exec.gen_proxy(
        umbrella_dir: "/u",
        output_dir: "/o",
        cache_dir: "/c",
        lockfile_path: "/l.lock",
      )
      cmd = captured_cmds.first
      expect(cmd).not_to include("--ignore")
    end

    it "single-quotes patterns so shell glob chars survive" do
      exec.gen_proxy(
        umbrella_dir: "/u",
        output_dir: "/o",
        cache_dir: "/c",
        ignore: ["Foo*"],
      )
      cmd = captured_cmds.first
      expect(cmd).to include("--ignore 'Foo*'")
    end
  end

  describe "#gen_proxy with cache_only list" do
    it "appends single-quoted --cache-only CSV" do
      exec.gen_proxy(
        umbrella_dir: "/u",
        output_dir: "/o",
        cache_dir: "/c",
        lockfile_path: "/l.lock",
        cache_only: ["Alamofire", "SnapKit"],
      )
      cmd = captured_cmds.first
      expect(cmd).to include("--cache-only 'Alamofire,SnapKit'")
    end

    it "omits --cache-only when list is empty" do
      exec.gen_proxy(
        umbrella_dir: "/u",
        output_dir: "/o",
        cache_dir: "/c",
        lockfile_path: "/l.lock",
        cache_only: [],
      )
      cmd = captured_cmds.first
      expect(cmd).not_to include("--cache-only")
    end

    it "omits --cache-only when kwarg not passed" do
      exec.gen_proxy(
        umbrella_dir: "/u",
        output_dir: "/o",
        cache_dir: "/c",
        lockfile_path: "/l.lock",
      )
      cmd = captured_cmds.first
      expect(cmd).not_to include("--cache-only")
    end

    it "sends --cache-only and omits --ignore when only cache_only is passed (precedence contract)" do
      exec.gen_proxy(
        umbrella_dir: "/u",
        output_dir: "/o",
        cache_dir: "/c",
        lockfile_path: "/l.lock",
        cache_only: ["Alamofire"],
      )
      cmd = captured_cmds.first
      expect(cmd).to include("--cache-only 'Alamofire'")
      expect(cmd).not_to include("--ignore")
    end
  end
end
