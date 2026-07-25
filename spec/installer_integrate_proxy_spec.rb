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

  # graph.json is read directly from disk by `never_cached_product_names`
  # (it exists by the time `integrate_proxy_into_project` runs, written
  # earlier in `perform_install` by `prepare_proxy`); write it at the same
  # path `Core::Config.instance.proxy_dir` will resolve to for this project.
  def write_graph_json(entries)
    proxy_dir = File.join(tmpdir, "spm-cache", "packages", "proxy")
    FileUtils.mkdir_p(proxy_dir)
    File.write(File.join(proxy_dir, "graph.json"), JSON.generate(entries))
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

  # Field bug: a product with graph.json status excluded/ignored (permanently
  # falling back to source, never cached -- e.g. eh_oauth_sdk_ios, which
  # doesn't match cache_only at all) used to still get its dependency
  # rewired onto the proxy, pointing at a shim the Swift-side generator no
  # longer creates for such products. That shim re-declared its OWN
  # dependency on the real upstream package -- when a SEPARATE, independently
  # excluded package happened to share a transitive dependency with another
  # partially-cached package (AppAuth-iOS's own excluded/missed AppAuth
  # product), Xcode's PIF loader registered a duplicate GUID for the shared
  # product. Fix: exempt by product name (not package ref -- a ref can be
  # shared by sibling products with different statuses), leaving the
  # excluded product's dependency untouched, pointing at its real package
  # reference exactly as it always did.
  it "leaves an excluded product's dependency untouched (pointing at its real package ref), while still rewiring a sibling cached product sharing the same ref" do
    project, target = build_project
    # Both products share ONE package ref -- the exact AppAuth-iOS shape
    # (AppAuthCore cached, AppAuth excluded/never-cached) that a purely
    # ref-based exemption would get wrong.
    shared_ref = remote_ref(project, "https://github.com/example/SharedPkg.git")
    cached_dep = product_dep(project, target, "CachedProduct", shared_ref)
    excluded_dep = product_dep(project, target, "ExcludedProduct", shared_ref)
    project.save

    write_lockfile([
      { "repositoryURL" => "https://github.com/example/SharedPkg.git", "name" => "SharedPkg",
        "products" => [
          { "name" => "CachedProduct", "type" => "library", "targets" => ["CachedProduct"] },
          { "name" => "ExcludedProduct", "type" => "library", "targets" => ["ExcludedProduct"] },
        ] },
    ])
    write_graph_json([
      { "module" => "CachedProduct", "status" => "hit", "dependencies" => [], "hasMacro" => false },
      { "module" => "ExcludedProduct", "status" => "excluded", "dependencies" => [], "hasMacro" => false },
    ])

    make_installer.send(:integrate_proxy_into_project)

    saved = reloaded_project
    saved_target = saved.targets.first
    deps_by_product = saved_target.package_product_dependencies.each_with_object({}) { |d, h| h[d.product_name] = d }

    proxy_ref = saved.root_object.package_references.grep(Xcodeproj::Project::Object::XCLocalSwiftPackageReference).first
    real_ref = saved.root_object.package_references.grep(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference).first

    # The cached sibling gets rewired onto the proxy as normal.
    expect(deps_by_product["CachedProduct"].package).to eq(proxy_ref)
    # The excluded product's original dependency survives untouched, still
    # pointing at the real package reference -- no shim, no proxy detour.
    expect(deps_by_product["ExcludedProduct"].package).to eq(real_ref)
    expect(real_ref.repositoryURL).to eq("https://github.com/example/SharedPkg.git")
  end

  # Field bug: a discarded product dep / package ref was only ever unlinked
  # from its containing array (ObjectList#delete just calls remove_referrer
  # -- see Xcodeproj source), never purged from the project's object table,
  # so `project.save` kept silently re-serializing the orphaned PBXObject on
  # every run. Every prior test here only inspected the *reachable* graph
  # from root_object.package_references, so the orphan went unnoticed --
  # until a partially-cached package (AppAuthCore cached, AppAuth excluded/
  # fallback, both from the same underlying remote package) made Xcode's
  # build system actually resolve the leftover orphaned ref ALONGSIDE the
  # proxy's own shim dependency on that identical remote package+revision,
  # producing a duplicate PIF GUID registration that failed the real app
  # build. This test inspects the raw pbxproj file content directly, not
  # just the reachable object graph, to catch that blind spot.
  it "purges a discarded package ref from the raw pbxproj file, not just from root_object.package_references" do
    project, target = build_project
    alamofire_ref = remote_ref(project, "https://github.com/Alamofire/Alamofire.git")
    product_dep(project, target, "Alamofire", alamofire_ref)
    project.save

    write_lockfile([
      { "repositoryURL" => "https://github.com/Alamofire/Alamofire.git", "name" => "Alamofire",
        "products" => [{ "name" => "Alamofire", "type" => "library", "targets" => ["Alamofire"] }] },
    ])

    make_installer.send(:integrate_proxy_into_project)

    raw = File.read(File.join(project_path, "project.pbxproj"))
    expect(raw).not_to include("Alamofire.git")
  end

  # Field bug (part 2): fixing the delete-vs-remove_from_project logic only
  # stops NEW orphans from accumulating going forward. A project that
  # already accumulated orphans under the old buggy code across many prior
  # runs still has them physically in the file -- and they are NOT
  # zero-referrer from Xcodeproj's perspective (an orphaned product
  # dependency's `package` to-one attribute still points at its ref, giving
  # the ref a nonzero referrer count even though nothing in any target
  # actually uses it), so `.referrers.empty?` alone cannot find them.
  # Verified against the real corrupted project this bug was found in: 113
  # of 223 product-dependency objects and 33 of 34 package-reference
  # objects were unreachable from root_object/targets despite nonzero
  # referrer counts on the ref side.
  it "purges refs/deps present in the object table but unreachable from root_object/targets (pre-existing corruption from before this fix)" do
    project, target = build_project

    orphaned_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    orphaned_ref.repositoryURL = "https://github.com/openid/AppAuth-iOS.git"
    orphaned_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    orphaned_dep.product_name = "AppAuth"
    orphaned_dep.package = orphaned_ref
    # Register directly in the object table WITHOUT adding to
    # root_object.package_references / target.package_product_dependencies --
    # reproduces exactly the state left behind by the old buggy code: present
    # in the file, unreachable from anything a real build actually walks.
    project.objects_by_uuid[orphaned_ref.uuid] = orphaned_ref
    project.objects_by_uuid[orphaned_dep.uuid] = orphaned_dep
    project.save

    write_lockfile([])

    make_installer.send(:integrate_proxy_into_project)

    raw = File.read(File.join(project_path, "project.pbxproj"))
    expect(raw).not_to include("AppAuth-iOS.git")
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
