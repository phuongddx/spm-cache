# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# D-06: a watch-triggered regenerate's recreate_dirs must not rm_rf checkouts
# out from under an in-flight build (Pitfall 15). Installer::Build holds a
# process-level flock across its whole build; Installer::Use's non-fast-path
# branch blocks on the SAME lock before its own recreate_dirs call, so it
# defers rather than interrupts.
RSpec.describe "process-level build lock" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:lock_path) { File.join(tmpdir, ".spm-cache-build.lock") }

  after { FileUtils.rm_rf(tmpdir) }

  # Real two-process contention, not a single-process mock: a forked child
  # genuinely holds the OS-level flock on the exact path both Installer::Build
  # and Installer::Use acquire, so a non-blocking trylock can only succeed
  # once the child has actually released it.
  it "a forked child holding the lock blocks a concurrent non-blocking trylock until it releases" do
    FileUtils.mkdir_p(File.dirname(lock_path))
    reader, writer = IO.pipe

    pid = fork do
      reader.close
      f = File.open(lock_path, File::CREAT | File::RDWR)
      f.flock(File::LOCK_EX)
      writer.write("locked")
      writer.close
      sleep 0.3
      f.flock(File::LOCK_UN)
      f.close
    end
    writer.close
    reader.read # blocks until the child confirms it holds the lock
    reader.close

    probe = File.open(lock_path, File::CREAT | File::RDWR)
    expect(probe.flock(File::LOCK_EX | File::LOCK_NB)).to eq(false)

    Process.wait(pid)

    expect(probe.flock(File::LOCK_EX | File::LOCK_NB)).to eq(0)
    probe.flock(File::LOCK_UN)
    probe.close
  end
end

RSpec.describe SPMCache::Installer::Build, "build lock" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }
  let(:lock_path) { File.join(tmpdir, ".spm-cache-build.lock") }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(graph_data: [{ "module" => "Alamofire", "status" => "missed" }])
  end

  before do
    FileUtils.mkdir_p(project_path)
    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *_args|
      me = original.receiver
      me.instance_variable_set(:@cachemap, cachemap) if me.respond_to?(:cachemap)
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return({})
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return("iphonesimulator")
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
    allow(SPMCache::Core::Config.instance).to receive(:build_lock_path).and_return(lock_path)
  end

  after { FileUtils.rm_rf(tmpdir) }

  def lock_currently_held?
    probe = File.open(lock_path, File::CREAT | File::RDWR)
    held = probe.flock(File::LOCK_EX | File::LOCK_NB) == false
    probe.flock(File::LOCK_UN) unless held
    probe.close
    held
  end

  it "holds the lock across super and every build_single_target call, releasing it on success" do
    held_during_build = nil
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target) do
      held_during_build = lock_currently_held?
    end

    described_class.new(project: project_path, targets: []).perform_install

    expect(held_during_build).to be true
    expect(lock_currently_held?).to be false
  end

  it "releases the lock even when a build raises" do
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target)
      .and_raise(StandardError, "boom")

    expect {
      described_class.new(project: project_path, targets: []).perform_install
    }.to raise_error(StandardError, "boom")

    expect(lock_currently_held?).to be false
  end
end

RSpec.describe SPMCache::Installer::Use, "build lock" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }
  let(:lock_path) { File.join(tmpdir, ".spm-cache-build.lock") }

  before do
    FileUtils.mkdir_p(project_path)
    allow(SPMCache::Core::Config.instance).to receive(:build_lock_path).and_return(lock_path)
    allow_any_instance_of(SPMCache::Installer).to receive(:verify_projects!)
    allow_any_instance_of(SPMCache::Installer).to receive(:detect_diff)
    allow_any_instance_of(SPMCache::Installer::Use).to receive(:fast_path?).and_return(false)
    allow_any_instance_of(SPMCache::Installer).to receive(:ensure_config_file)
    allow_any_instance_of(SPMCache::Installer).to receive(:sync_lockfile)
    allow_any_instance_of(SPMCache::Installer).to receive(:prepare_proxy)
    allow_any_instance_of(SPMCache::Installer).to receive(:gen_supporting_files)
    allow_any_instance_of(SPMCache::Installer).to receive(:integrate_proxy_into_project)
    allow_any_instance_of(SPMCache::Installer).to receive(:gen_cachemap_viz)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "blocks its non-fast-path recreate_dirs until a concurrently-held lock is released" do
    recreate_called_at = nil
    allow_any_instance_of(SPMCache::Installer).to receive(:recreate_dirs) { recreate_called_at = Time.now }

    FileUtils.mkdir_p(File.dirname(lock_path))
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      f = File.open(lock_path, File::CREAT | File::RDWR)
      f.flock(File::LOCK_EX)
      writer.write("locked")
      writer.close
      sleep 0.4
      f.flock(File::LOCK_UN)
      f.close
    end
    writer.close
    reader.read
    reader.close
    start = Time.now

    described_class.new(project: project_path).perform_install

    Process.wait(pid)
    expect(recreate_called_at).not_to be_nil
    expect(recreate_called_at - start).to be >= 0.3
  end

  it "blocks its fast-path trailing calls until a concurrently-held lock is released" do
    allow_any_instance_of(SPMCache::Installer::Use).to receive(:fast_path?).and_return(true)
    allow_any_instance_of(SPMCache::Installer).to receive(:recreate_dirs) { raise "must not be called" }

    gen_supporting_files_called_at = nil
    allow_any_instance_of(SPMCache::Installer).to receive(:gen_supporting_files) { gen_supporting_files_called_at = Time.now }

    FileUtils.mkdir_p(File.dirname(lock_path))
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      f = File.open(lock_path, File::CREAT | File::RDWR)
      f.flock(File::LOCK_EX)
      writer.write("locked")
      writer.close
      sleep 0.4
      f.flock(File::LOCK_UN)
      f.close
    end
    writer.close
    reader.read
    reader.close
    start = Time.now

    described_class.new(project: project_path).perform_install

    Process.wait(pid)
    expect(gen_supporting_files_called_at).not_to be_nil
    expect(gen_supporting_files_called_at - start).to be >= 0.3
  end
end
