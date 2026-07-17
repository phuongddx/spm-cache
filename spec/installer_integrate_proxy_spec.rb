# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "xcodeproj"

# Unit-tests Installer#integrate_proxy_into_project's keep-set + dep-exemption
# logic for plugin-only packages (Phase 3): a plugin-only package's original
# Xcode package reference and product dependency must survive integration
# untouched, while every other reference (including a stale proxy ref left
# over from a prior run) is stripped and rewired onto the fresh local proxy.
RSpec.describe SPMCache::Installer, "#integrate_proxy_into_project" do
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

  def local_ref(project, relative_path)
    ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    ref.relative_path = relative_path
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

  def reloaded_project
    Xcodeproj::Project.open(project_path)
  end

  it "keeps a plugin-only package's ref and product dep, and rewires the library dep onto a fresh proxy ref" do
    project, target = build_project
    alamofire_ref = remote_ref(project, "https://github.com/Alamofire/Alamofire.git")
    swiftgen_ref = remote_ref(project, "https://github.com/SwiftGen/SwiftGenPlugin.git")
    stale_proxy_ref = local_ref(project, "spm-cache/packages/proxy")
    product_dep(project, target, "Alamofire", alamofire_ref)
    product_dep(project, target, "SwiftGenPlugin", swiftgen_ref)
    project.save

    write_lockfile([
      { "repositoryURL" => "https://github.com/Alamofire/Alamofire.git", "name" => "Alamofire",
        "products" => [{ "name" => "Alamofire", "type" => "library", "targets" => ["Alamofire"] }] },
      { "repositoryURL" => "https://github.com/SwiftGen/SwiftGenPlugin.git", "name" => "SwiftGenPlugin",
        "products" => [{ "name" => "SwiftGenPlugin", "type" => "plugin", "targets" => ["SwiftGenPlugin"] }] },
    ])

    make_installer.send(:integrate_proxy_into_project)

    saved = reloaded_project
    refs = saved.root_object.package_references
    remote_urls = refs.grep(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference).map(&:repositoryURL)
    local_paths = refs.grep(Xcodeproj::Project::Object::XCLocalSwiftPackageReference).map(&:relative_path)

    # The plugin ref survives untouched; the stale local proxy ref does not
    # (a fresh one is added instead -- exactly one local ref, no duplicates).
    expect(remote_urls).to eq(["https://github.com/SwiftGen/SwiftGenPlugin.git"])
    expect(local_paths).to eq(["spm-cache/packages/proxy"])

    saved_target = saved.targets.first
    deps_by_product = saved_target.package_product_dependencies.each_with_object({}) { |d, h| h[d.product_name] = d }

    # Alamofire's dep got rewired onto the (new) local proxy ref.
    proxy_ref = refs.grep(Xcodeproj::Project::Object::XCLocalSwiftPackageReference).first
    expect(deps_by_product["Alamofire"].package).to eq(proxy_ref)

    # SwiftGenPlugin's dep still points at the SAME kept remote ref, untouched.
    swiftgen_saved_ref = refs.grep(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference).first
    expect(deps_by_product["SwiftGenPlugin"].package).to eq(swiftgen_saved_ref)
  end

  it "produces no duplicate proxy refs across repeated runs" do
    project, target = build_project
    alamofire_ref = remote_ref(project, "https://github.com/Alamofire/Alamofire.git")
    product_dep(project, target, "Alamofire", alamofire_ref)
    project.save

    write_lockfile([
      { "repositoryURL" => "https://github.com/Alamofire/Alamofire.git", "name" => "Alamofire",
        "products" => [{ "name" => "Alamofire", "type" => "library", "targets" => ["Alamofire"] }] },
    ])

    2.times { make_installer.send(:integrate_proxy_into_project) }

    saved = reloaded_project
    local_refs = saved.root_object.package_references.grep(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    expect(local_refs.size).to eq(1)
    expect(saved.targets.first.package_product_dependencies.size).to eq(1)
  end

  it "warns loudly instead of preserving a ref when a plugin-only entry has no matching project reference" do
    project, target = build_project
    alamofire_ref = remote_ref(project, "https://github.com/Alamofire/Alamofire.git")
    product_dep(project, target, "Alamofire", alamofire_ref)
    project.save

    write_lockfile([
      { "repositoryURL" => "https://github.com/Alamofire/Alamofire.git", "name" => "Alamofire",
        "products" => [{ "name" => "Alamofire", "type" => "library", "targets" => ["Alamofire"] }] },
      { "repositoryURL" => "https://github.com/SwiftGen/SwiftGenPlugin.git", "name" => "SwiftGenPlugin",
        "products" => [{ "name" => "SwiftGenPlugin", "type" => "plugin", "targets" => ["SwiftGenPlugin"] }] },
    ])

    expect { make_installer.send(:integrate_proxy_into_project) }.to output(
      %r{Plugin-only package 'github\.com/SwiftGen/SwiftGenPlugin' has no matching Xcode package reference},
    ).to_stderr

    saved = reloaded_project
    expect(saved.root_object.package_references.grep(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)).to be_empty
  end

  it "never rewires a plugin:-prefixed product dependency onto the proxy" do
    project, target = build_project
    plugin_ref = remote_ref(project, "https://github.com/Unknown/UnknownPlugin.git")
    product_dep(project, target, "plugin:UnknownPlugin", plugin_ref)
    project.save

    write_lockfile([])

    make_installer.send(:integrate_proxy_into_project)

    saved = reloaded_project
    saved_target = saved.targets.first
    expect(saved_target.package_product_dependencies.size).to eq(1)
    dep = saved_target.package_product_dependencies.first
    expect(dep.product_name).to eq("plugin:UnknownPlugin")
    proxy_ref = saved.root_object.package_references.grep(Xcodeproj::Project::Object::XCLocalSwiftPackageReference).first
    expect(dep.package).not_to eq(proxy_ref)
  end
end

RSpec.describe SPMCache::Installer, "#normalize_package_url" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }

  before { FileUtils.mkdir_p(project_path) }
  after { FileUtils.rm_rf(tmpdir) }

  subject(:installer) { SPMCache::Installer.new(project: project_path) }

  it "treats https and ssh shorthand forms of the same remote as equal" do
    https = installer.send(:normalize_package_url, "https://github.com/SwiftGen/SwiftGenPlugin.git")
    ssh = installer.send(:normalize_package_url, "git@github.com:SwiftGen/SwiftGenPlugin.git")
    expect(https).to eq(ssh)
  end

  it "strips a trailing .git suffix" do
    with_git = installer.send(:normalize_package_url, "https://github.com/SwiftGen/SwiftGenPlugin.git")
    without_git = installer.send(:normalize_package_url, "https://github.com/SwiftGen/SwiftGenPlugin")
    expect(with_git).to eq(without_git)
  end

  it "is host-case-insensitive" do
    lower = installer.send(:normalize_package_url, "https://github.com/SwiftGen/SwiftGenPlugin.git")
    upper = installer.send(:normalize_package_url, "https://GitHub.com/SwiftGen/SwiftGenPlugin.git")
    expect(lower).to eq(upper)
  end

  it "distinguishes genuinely different repositories" do
    a = installer.send(:normalize_package_url, "https://github.com/SwiftGen/SwiftGenPlugin.git")
    b = installer.send(:normalize_package_url, "https://github.com/Alamofire/Alamofire.git")
    expect(a).not_to eq(b)
  end
end
