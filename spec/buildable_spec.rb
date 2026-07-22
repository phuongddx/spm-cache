# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe SPMCache::SPM::Buildable do
  describe "#create_framework" do
    let(:pkg_dir) { Dir.mktmpdir }
    let(:output_dir) { Dir.mktmpdir }
    let(:buildable) { described_class.new(name: "eHealth", pkg_dir: pkg_dir) }

    after { FileUtils.rm_rf([pkg_dir, output_dir]) }

    def modules_dir_for(fw_dir)
      File.join(fw_dir, "Modules")
    end

    it "copies a flat-file swiftmodule/swiftdoc/swiftsourceinfo (baseline, unchanged behavior)" do
      swiftmodule = File.join(pkg_dir, "eHealth.swiftmodule")
      swiftdoc = File.join(pkg_dir, "eHealth.swiftdoc")
      File.write(swiftmodule, "flat swiftmodule contents")
      File.write(swiftdoc, "flat swiftdoc contents")

      fw_dir = buildable.create_framework(
        { swiftmodule: swiftmodule, swiftdoc: swiftdoc },
        output_dir,
      )

      expect(File.read(File.join(modules_dir_for(fw_dir), "eHealth.swiftmodule"))).to eq("flat swiftmodule contents")
      expect(File.read(File.join(modules_dir_for(fw_dir), "eHealth.swiftdoc"))).to eq("flat swiftdoc contents")
    end

    # Field regression: eh_xcframework's build produced a `.swiftmodule`
    # DIRECTORY bundle (per-arch files inside it) rather than a flat file --
    # find_file's glob matched it anyway, and the old FileUtils.cp call
    # crashed with Errno::EISDIR trying to copy a directory as a file.
    it "recursively copies a directory-shaped swiftmodule instead of raising Errno::EISDIR" do
      swiftmodule_dir = File.join(pkg_dir, "eHealth.swiftmodule")
      FileUtils.mkdir_p(swiftmodule_dir)
      File.write(File.join(swiftmodule_dir, "arm64-apple-ios.swiftmodule"), "arch-specific contents")
      File.write(File.join(swiftmodule_dir, "arm64-apple-ios.swiftdoc"), "arch-specific doc")

      fw_dir = nil
      expect do
        fw_dir = buildable.create_framework({ swiftmodule: swiftmodule_dir }, output_dir)
      end.not_to raise_error

      copied_dir = File.join(modules_dir_for(fw_dir), "eHealth.swiftmodule")
      expect(File.directory?(copied_dir)).to be true
      expect(File.read(File.join(copied_dir, "arm64-apple-ios.swiftmodule"))).to eq("arch-specific contents")
      expect(File.read(File.join(copied_dir, "arm64-apple-ios.swiftdoc"))).to eq("arch-specific doc")
    end

    it "merges a directory-shaped swiftmodule into the same dir already created from swiftinterface, without clobbering it" do
      swiftinterface = File.join(pkg_dir, "eHealth.swiftinterface")
      File.write(swiftinterface, "public interface contents")

      swiftmodule_dir = File.join(pkg_dir, "eHealth.swiftmodule")
      FileUtils.mkdir_p(swiftmodule_dir)
      File.write(File.join(swiftmodule_dir, "arm64-apple-ios.swiftdoc"), "arch-specific doc")

      fw_dir = buildable.create_framework(
        { swiftinterface: swiftinterface, swiftmodule: swiftmodule_dir, derived_data: "/DerivedData" },
        output_dir,
      )

      sm_dir = File.join(modules_dir_for(fw_dir), "eHealth.swiftmodule")
      expect(File.read(File.join(sm_dir, "arm64-apple-ios.swiftinterface"))).to eq("public interface contents")
      expect(File.read(File.join(sm_dir, "arm64-apple-ios.swiftdoc"))).to eq("arch-specific doc")
    end
  end

  # Field bug: CryptoSwift's checkout carries its own committed .xcodeproj
  # (Xcode "Framework" target type), so xcodebuild links a genuine
  # CryptoSwift.framework bundle directly -- no raw .o exists anywhere under
  # DerivedData for this target (verified against a real build). The normal
  # SPM-package path (create_framework assembling a framework from a raw
  # .o) never applies here, so find_object_file's glob found nothing and the
  # successful build was reported as a failure.
  describe "#find_framework and #use_existing_framework" do
    let(:pkg_dir) { Dir.mktmpdir }
    let(:output_dir) { Dir.mktmpdir }
    let(:buildable) { described_class.new(name: "CryptoSwift", pkg_dir: pkg_dir) }

    after { FileUtils.rm_rf([pkg_dir, output_dir]) }

    it "finds an already-built .framework bundle under Products when no .o exists" do
      dd = Dir.mktmpdir
      fw_dir = File.join(dd, "Build", "Products", "Debug-iphonesimulator", "CryptoSwift.framework")
      FileUtils.mkdir_p(fw_dir)
      File.write(File.join(fw_dir, "CryptoSwift"), "binary contents")

      expect(buildable.find_framework(dd)).to eq(fw_dir)
      FileUtils.rm_rf(dd)
    end

    it "copies the existing framework bundle as-is via use_existing_framework" do
      source_fw = File.join(pkg_dir, "CryptoSwift.framework")
      FileUtils.mkdir_p(source_fw)
      File.write(File.join(source_fw, "CryptoSwift"), "binary contents")

      fw_dir = buildable.use_existing_framework({ framework: source_fw }, output_dir)

      expect(fw_dir).to eq(File.join(output_dir, "CryptoSwift.framework"))
      expect(File.read(File.join(fw_dir, "CryptoSwift"))).to eq("binary contents")
    end
  end

  # Field bug: SkeletonView's real schemes are named "SkeletonView iOS" /
  # "SkeletonView tvOS" -- containing a literal space. The unquoted
  # `-scheme #{@scheme}` interpolation let the shell split it into separate
  # arguments, so xcodebuild saw "-scheme SkeletonView iOS" as 3 tokens and
  # misread the trailing "iOS" as an unknown build action ("Unknown build
  # action 'iOS'"). Every other dynamic value (-destination, -project) was
  # already quoted; the scheme was the one place that wasn't.
  describe "#build_command scheme quoting" do
    it "quotes a scheme name containing a space" do
      buildable = described_class.new(name: "SkeletonView", scheme: "SkeletonView iOS", pkg_dir: "/tmp")
      cmd = buildable.build_command("platform=iOS Simulator,name=iPhone 17", "/dd")
      expect(cmd).to include("-scheme 'SkeletonView iOS'")
      expect(cmd).not_to include("-scheme SkeletonView iOS ")
    end

    it "still works for a plain scheme name with no special characters (common case)" do
      buildable = described_class.new(name: "Alamofire", pkg_dir: "/tmp")
      cmd = buildable.build_command("platform=iOS Simulator,name=iPhone 17", "/dd")
      expect(cmd).to include("-scheme 'Alamofire'")
    end
  end

  describe "#build_for_destination" do
    let(:pkg_dir) { Dir.mktmpdir }
    let(:buildable) { described_class.new(name: "CryptoSwift", pkg_dir: pkg_dir) }

    after { FileUtils.rm_rf(pkg_dir) }

    it "only looks for a framework when no .o file was found (common case unaffected)" do
      allow(buildable).to receive(:xcodebuild).and_return("/dd")
      allow(buildable).to receive(:find_object_file).and_return("/dd/CryptoSwift.o")
      allow(buildable).to receive(:find_file).and_return(nil)
      expect(buildable).not_to receive(:find_framework)

      artifacts = buildable.build_for_destination("iphonesimulator", derived_data_path: "/dd")
      expect(artifacts[:object_file]).to eq("/dd/CryptoSwift.o")
      expect(artifacts[:framework]).to be_nil
    end

    it "falls back to find_framework when no .o file was found" do
      allow(buildable).to receive(:xcodebuild).and_return("/dd")
      allow(buildable).to receive(:find_object_file).and_return(nil)
      allow(buildable).to receive(:find_framework).and_return("/dd/CryptoSwift.framework")
      allow(buildable).to receive(:find_file).and_return(nil)

      artifacts = buildable.build_for_destination("iphonesimulator", derived_data_path: "/dd")
      expect(artifacts[:object_file]).to be_nil
      expect(artifacts[:framework]).to eq("/dd/CryptoSwift.framework")
    end
  end

  # Field bug: some vendored checkouts (AppAuth-iOS, FSPagerView) carry
  # their own committed .xcodeproj with IPHONEOS_DEPLOYMENT_TARGET
  # hardcoded to 8.0. Same root cause, two different symptoms: modern Xcode
  # dropped `libarclite` support for pre-~iOS 11 targets (AppAuth-iOS's
  # linker error), and FSPagerView hits a Swift availability-check error on
  # unguarded real API usage the compiler treats as unavailable given the
  # project's own too-low target ("'layoutSublayers(of:)' is only available
  # in iOS 10.0 or newer"). Both are genuine toolchain/source
  # incompatibilities in the vendored project. Verified fix empirically for
  # both: retrying with IPHONEOS_DEPLOYMENT_TARGET=13.0 appended succeeds.
  describe "#xcodebuild low deployment target retry" do
    let(:pkg_dir) { Dir.mktmpdir }
    let(:buildable) { described_class.new(name: "AppAuthCore", pkg_dir: pkg_dir) }

    after { FileUtils.rm_rf(pkg_dir) }

    it "retries once with a bumped IPHONEOS_DEPLOYMENT_TARGET when the libarclite error occurs" do
      libarclite_error = SPMCache::Core::GeneralError.new(
        "Command failed (exit 65): xcodebuild build ...\n" \
        "clang: error: SDK does not contain 'libarclite' at the path " \
        "'.../libarclite_iphonesimulator.a'; try increasing the minimum deployment target",
      )
      call_count = 0
      allow(SPMCache::Core::Sh).to receive(:run) do |cmd, _opts|
        call_count += 1
        raise libarclite_error if call_count == 1
        expect(cmd).to include("IPHONEOS_DEPLOYMENT_TARGET=13.0")
      end

      buildable.xcodebuild("platform=iOS Simulator,name=iPhone 17", derived_data_path: "/dd")
      expect(call_count).to eq(2)
    end

    it "retries once with a bumped IPHONEOS_DEPLOYMENT_TARGET when a Swift availability-check error occurs" do
      availability_error = SPMCache::Core::GeneralError.new(
        "Command failed (exit 65): xcodebuild build ...\n" \
        "FSPageControl.swift:105:15: error: 'layoutSublayers(of:)' is only available in iOS 10.0 or newer",
      )
      call_count = 0
      allow(SPMCache::Core::Sh).to receive(:run) do |cmd, _opts|
        call_count += 1
        raise availability_error if call_count == 1
        expect(cmd).to include("IPHONEOS_DEPLOYMENT_TARGET=13.0")
      end

      buildable.xcodebuild("platform=iOS Simulator,name=iPhone 17", derived_data_path: "/dd")
      expect(call_count).to eq(2)
    end

    it "does not retry and re-raises for an unrelated build failure" do
      other_error = SPMCache::Core::GeneralError.new("Command failed (exit 65): some unrelated compile error")
      allow(SPMCache::Core::Sh).to receive(:run).and_raise(other_error)

      expect {
        buildable.xcodebuild("platform=iOS Simulator,name=iPhone 17", derived_data_path: "/dd")
      }.to raise_error(SPMCache::Core::GeneralError, /unrelated compile error/)
      expect(SPMCache::Core::Sh).to have_received(:run).once
    end

    it "only invokes xcodebuild once when the first attempt succeeds (common case unaffected)" do
      allow(SPMCache::Core::Sh).to receive(:run)

      buildable.xcodebuild("platform=iOS Simulator,name=iPhone 17", derived_data_path: "/dd")
      expect(SPMCache::Core::Sh).to have_received(:run).once
    end
  end

  # Field bug: SVGKit's checkout carries THREE committed .xcodeproj files
  # at its root (the library plus two demo apps) alongside Package.swift.
  # xcodebuild refuses to guess which to use ("contains 3 projects ...
  # Specify the project to use with the -project option") and fails before
  # even resolving a scheme. CryptoSwift/AppAuth-iOS only ever had exactly
  # one .xcodeproj each, which Xcode's own implicit detection already
  # resolves fine on its own -- verified empirically, so the 0-or-1 cases
  # must stay untouched (returns "" immediately, same command as before).
  describe "#build_command project disambiguation" do
    let(:pkg_dir) { Dir.mktmpdir }
    let(:buildable) { described_class.new(name: "SVGKit", pkg_dir: pkg_dir) }

    after { FileUtils.rm_rf(pkg_dir) }

    it "adds no -project flag when the checkout has zero .xcodeproj files (pure SPM package, common case)" do
      cmd = buildable.build_command("platform=iOS Simulator,name=iPhone 17", "/dd")
      expect(cmd).not_to include("-project")
    end

    it "adds no -project flag when the checkout has exactly one .xcodeproj (Xcode's own detection already works)" do
      FileUtils.mkdir_p(File.join(pkg_dir, "SVGKit-iOS.xcodeproj"))
      cmd = buildable.build_command("platform=iOS Simulator,name=iPhone 17", "/dd")
      expect(cmd).not_to include("-project")
    end

    it "picks the matching .xcodeproj by scheme when multiple exist" do
      lib_proj = File.join(pkg_dir, "SVGKit-iOS.xcodeproj")
      demo_proj = File.join(pkg_dir, "Demo-iOS.xcodeproj")
      FileUtils.mkdir_p(lib_proj)
      FileUtils.mkdir_p(demo_proj)

      allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd|
        if cmd.include?(lib_proj)
          "Schemes:\nSVGKit\nSVGKitSwift"
        else
          "Schemes:\nDemo-iOS"
        end
      end

      cmd = buildable.build_command("platform=iOS Simulator,name=iPhone 17", "/dd")
      expect(cmd).to include("-project '#{lib_proj}'")
    end

    it "adds no -project flag when multiple .xcodeproj exist but none match the scheme (no worse than before)" do
      FileUtils.mkdir_p(File.join(pkg_dir, "Demo-OSX.xcodeproj"))
      FileUtils.mkdir_p(File.join(pkg_dir, "Demo-iOS.xcodeproj"))
      allow(SPMCache::Core::Sh).to receive(:capture_output).and_return("Schemes:\nDemo-iOS")

      cmd = buildable.build_command("platform=iOS Simulator,name=iPhone 17", "/dd")
      expect(cmd).not_to include("-project")
    end
  end

  describe "#initialize" do
    it "sets name and module_name" do
      b = described_class.new(name: "Alamofire", pkg_dir: "/tmp")
      expect(b.name).to eq("Alamofire")
      expect(b.module_name).to eq("Alamofire")
    end

    it "allows overriding module_name" do
      b = described_class.new(name: "test", module_name: "CustomModule", pkg_dir: "/tmp")
      expect(b.module_name).to eq("CustomModule")
    end
  end

  describe "#library_evolution" do
    it "defaults to true" do
      b = described_class.new(name: "test", pkg_dir: "/tmp")
      expect(b.library_evolution).to be true
    end

    it "can be disabled" do
      b = described_class.new(name: "test", pkg_dir: "/tmp", library_evolution: false)
      expect(b.library_evolution).to be false
    end
  end

  describe "DESTINATIONS" do
    it "includes iphonesimulator and iphoneos" do
      expect(described_class::DESTINATIONS).to include("iphonesimulator", "iphoneos")
    end
  end
end

RSpec.describe SPMCache::SPM::Package do
  describe "DEFAULT_DESTINATIONS" do
    it "includes both simulator and device" do
      expect(described_class::DEFAULT_DESTINATIONS).to eq(["iphonesimulator", "iphoneos"])
    end
  end
end
