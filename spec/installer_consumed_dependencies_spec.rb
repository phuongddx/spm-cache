# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "xcodeproj"

# Field regression: the umbrella manifest independently pinned every package
# in spm-cache.lock -- including one that's only a transitive dependency of
# another package in the same graph (e.g. realm-core, pulled in solely via
# realm-swift) -- at its own last-resolved version. When that pin drifted
# from what the consuming package's own manifest required, `swift package
# resolve` failed outright for the whole graph.
#
# Installer#refresh_consumed_dependencies records, per target, the product
# names the Xcode project directly links -- so UmbrellaGenerator (Swift side)
# can tell a directly-consumed package apart from a transitive-only one and
# skip pinning the latter independently.
RSpec.describe SPMCache::Installer, "#refresh_consumed_dependencies" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }
  let(:lockfile_path) { File.join(tmpdir, "spm-cache.lock") }

  after { FileUtils.rm_rf(tmpdir) }

  def build_project
    project = Xcodeproj::Project.new(project_path)
    target = project.new_target(:application, "MyApp", :ios)
    project.save
    [project, target]
  end

  def remote_ref(project, url)
    ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    ref.repositoryURL = url
    project.root_object.package_references << ref
    ref
  end

  def product_dep(project, target, product_name, package_ref)
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.product_name = product_name
    dep.package = package_ref
    target.package_product_dependencies << dep
    dep
  end

  def write_lockfile(packages)
    File.write(lockfile_path, JSON.generate(
      "Fake.xcodeproj" => {
        "packages" => packages,
        "dependencies" => {},
        "platforms" => { "ios" => "16.0" },
      },
    ))
  end

  def make_installer
    installer = SPMCache::Installer.new(project: project_path)
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
    installer
  end

  it "records only the products the project's targets directly link" do
    project, target = build_project
    realm_swift_ref = remote_ref(project, "https://github.com/realm/realm-swift")
    product_dep(project, target, "RealmSwift", realm_swift_ref)
    project.save

    write_lockfile([
      { "repositoryURL" => "https://github.com/realm/realm-core.git", "name" => "realm-core" },
      { "repositoryURL" => "https://github.com/realm/realm-swift", "name" => "realm-swift" },
    ])

    make_installer.send(:refresh_consumed_dependencies)

    saved = JSON.parse(File.read(lockfile_path))
    deps = saved["Fake.xcodeproj"]["dependencies"]

    expect(deps["MyApp"]).to eq(["RealmSwift"])
  end

  it "overwrites stale dependency data left over from a prior run" do
    project, target = build_project
    alamofire_ref = remote_ref(project, "https://github.com/Alamofire/Alamofire.git")
    product_dep(project, target, "Alamofire", alamofire_ref)
    project.save

    File.write(lockfile_path, JSON.generate(
      "Fake.xcodeproj" => {
        "packages" => [{ "repositoryURL" => "https://github.com/Alamofire/Alamofire.git", "name" => "Alamofire" }],
        "dependencies" => { "MyApp" => ["SomeStaleProductNoLongerLinked"] },
        "platforms" => { "ios" => "16.0" },
      },
    ))

    make_installer.send(:refresh_consumed_dependencies)

    saved = JSON.parse(File.read(lockfile_path))
    expect(saved["Fake.xcodeproj"]["dependencies"]["MyApp"]).to eq(["Alamofire"])
  end

  it "omits a target with no product dependencies" do
    project, _target = build_project
    empty_target = project.new_target(:application, "EmptyTarget", :ios)
    project.save

    write_lockfile([])

    make_installer.send(:refresh_consumed_dependencies)

    saved = JSON.parse(File.read(lockfile_path))
    expect(saved["Fake.xcodeproj"]["dependencies"]).not_to have_key(empty_target.name)
    expect(saved["Fake.xcodeproj"]["dependencies"]).not_to have_key("MyApp")
  end
end
