# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Unit-tests Installer::Build target-selection logic with a stubbed Cachemap.
# No real xcodebuild is invoked; the build pipeline is not exercised here.
RSpec.describe SPMCache::Installer::Build do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }

  before do
    FileUtils.mkdir_p(project_path)
    # Stub out the heavy Installer#perform_install steps so we can isolate
    # the selection logic added in Phase 2.
    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *args, &block|
      me = original.receiver
      me.instance_variable_set(:@cachemap, cachemap) if me.respond_to?(:cachemap)
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return({})
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target).and_return(nil)
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return("iphonesimulator")
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(
      graph_data: [
        { "module" => "Alamofire", "status" => "missed" },
        { "module" => "SnapKit", "status" => "missed" },
        { "module" => "CachedLib", "status" => "hit" },
        { "module" => "VolatileLib", "status" => "ignored" },
      ],
    )
  end

  def make_installer(targets: [])
    described_class.new(project: project_path, targets: targets)
  end

  it "builds all missed targets when no TARGETS given" do
    inst = make_installer(targets: [])
    expect { inst.perform_install }.to output(%r{Building 2 target.*Alamofire.*SnapKit}m).to_stdout
  end

  it "filters to only requested missed targets" do
    inst = make_installer(targets: ["Alamofire"])
    expect { inst.perform_install }.to output(/Building 1 target.*: Alamofire/).to_stdout
  end

  it "warns on unknown target" do
    inst = make_installer(targets: ["Nonexistent"])
    expect {
      expect { inst.perform_install }.to output(/No targets to build/).to_stdout
    }.to output(/unknown target 'Nonexistent'/).to_stderr
  end

  it "warns when requested target is ignored" do
    inst = make_installer(targets: ["VolatileLib"])
    expect { inst.perform_install }.to output(/'VolatileLib' is in the ignore list; skipping/).to_stderr
  end

  it "does not build already-hit targets" do
    inst = make_installer(targets: ["CachedLib"])
    expect { inst.perform_install }.to output(/unknown target 'CachedLib'|No targets to build/).to_stdout
  end
end

# Exercises the umbrella resolve fallback (issue #3) with a fresh top-level
# describe so it does NOT inherit the outer spec's
# `resolve_umbrella_checkouts` stub - the whole point here is to drive the
# real rescue/fallback path.
RSpec.describe SPMCache::Installer::Build, "umbrella resolve fallback (issue #3)" do
  let(:project_tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(project_tmpdir, "Fake.xcodeproj") }
  let(:fake_home) { Dir.mktmpdir }
  let(:derived_data_dir) { File.join(fake_home, "Library", "Developer", "Xcode", "DerivedData") }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(derived_data_dir)
    @original_home = ENV["HOME"]
    ENV["HOME"] = fake_home
    allow(SPMCache::Core::Sh).to receive(:run).and_raise(SPMCache::Core::GeneralError.new("resolve boom"))
  end

  after do
    ENV["HOME"] = @original_home
    FileUtils.rm_rf(project_tmpdir)
    FileUtils.rm_rf(fake_home)
  end

  def make_installer
    described_class.new(project: project_path)
  end

  def umbrella_checkouts_dir(installer)
    File.join(installer.config.umbrella_dir, ".build", "checkouts")
  end

  def write_derived_data_checkout(derived_data_dir_name, marker_content, mtime:)
    dd_dir = File.join(derived_data_dir, derived_data_dir_name)
    checkout_dir = File.join(dd_dir, "SourcePackages", "checkouts", "Alamofire")
    FileUtils.mkdir_p(checkout_dir)
    File.write(File.join(checkout_dir, "marker.txt"), marker_content)
    File.utime(mtime, mtime, dd_dir)
    dd_dir
  end

  it "copies checkouts from the newest matching DerivedData dir, not the first glob match" do
    write_derived_data_checkout("Fake-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "stale", mtime: Time.now - 3600)
    write_derived_data_checkout("Fake-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "fresh", mtime: Time.now)

    inst = make_installer
    expect { inst.send(:resolve_umbrella_checkouts) }.to output(/Umbrella resolve failed/).to_stderr

    copied_marker = File.join(umbrella_checkouts_dir(inst), "Alamofire", "marker.txt")
    expect(File.read(copied_marker)).to eq("fresh")
  end

  it "escalates the warning when no DerivedData checkouts match the project" do
    inst = make_installer

    expect { inst.send(:resolve_umbrella_checkouts) }.to output(
      /Umbrella resolve failed and no DerivedData checkouts found; all targets will be skipped/,
    ).to_stderr
    expect(Dir.glob(File.join(umbrella_checkouts_dir(inst), "*"))).to be_empty
  end

  it "does not escalate the warning when the fallback finds checkouts" do
    write_derived_data_checkout("Fake-cccccccccccccccccccccccccccccccc", "ok", mtime: Time.now)

    inst = make_installer

    expect { inst.send(:resolve_umbrella_checkouts) }.not_to output(
      /no DerivedData checkouts found/,
    ).to_stderr
  end
end
