# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "shellwords"

# TEST-02 bucket-partition meta-spec: every package in the declared universe
# of one synthetic all-classes project (the kitchen-sink lockfile fixture plus
# the Package.resolved pin identities the tier-1 legs seed) lands in exactly
# ONE fidelity bucket -- zero-bucket AND double-bucket both fail the partition
# assertion (SC2: no package's resolution outcome may be silently absent).
#
# The six buckets span TWO production surfaces, so the observation route is
# hybrid (RESEARCH Open Question 1, adopted):
#   - provenance sidecars via the tier-1 object-stub seam -- BuildPipeline.run
#     (including report_fidelity) stays real; Desc::Description, Buildable,
#     and XCFramework are stubbed exactly as in
#     spec/build_pipeline_provenance_spec.rb; the default-deny Core::Sh guard
#     makes "zero real shell-outs" an executable assertion (SC4);
#   - graph.json via the compiled spm-cache-proxy binary (tier-3, the
#     gen_proxy_* pattern) for the Swift-side classifications.
#
# The universe is ALWAYS the fixture's declared input set (lockfile packages,
# including the empty-repositoryURL local/path entry, plus the tier-1 legs'
# resolved pin identities) -- never the classifier outputs. Bucket names are
# never typed as a literal enumeration: every recorded bucket value is read
# back from a real sidecar's fidelity_status, a real graph.json status, or an
# input-side rule reusing one of those observed values. Which graph statuses
# are mere cache-availability outcomes (and therefore not buckets) is itself
# OBSERVED via the canary derivation below, not typed.
RSpec.describe "TEST-02: bucket-partition coverage over the declared universe" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:out_dir) { File.join(tmpdir, "out") }
  let(:resolved_pins_file) { File.join(tmpdir, "host-Package.resolved") }

  let(:fixture_lockfile) do
    SPMCache::ROOT.join("spec", "fixtures", "fidelity-kitchen-sink-lockfile.json").to_s
  end

  let(:binary) do
    local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                                ".build", "release", "spm-cache-proxy").to_s
    File.executable?(local) ? local : nil
  end

  let(:umbrella_dir) { File.join(tmpdir, "umbrella") }
  let(:output_dir) { File.join(tmpdir, "proxy") }
  let(:cache_dir) { File.join(tmpdir, "cache") }

  before do
    FileUtils.mkdir_p(umbrella_dir)
    FileUtils.mkdir_p(output_dir)
    FileUtils.mkdir_p(cache_dir)

    # SC4 executable hermeticity guard (default-deny, both Core::Sh entry
    # points): the tier-1 seam must need ZERO shell-outs, so any invocation
    # that survives the object stubs raises instead of running. Also armed
    # during the tier-3 legs -- they invoke the local proxy via plain
    # system(), which never routes through Core::Sh, so the guard stays
    # silent there while still catching any accidental real shell-out.
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  def stub_desc_products(products, pkg_dir)
    fake_desc = instance_double(SPMCache::SPM::Desc::Description)
    allow(SPMCache::SPM::Desc::Description).to receive(:new).and_return(fake_desc)
    allow(fake_desc).to receive(:fetch)
    allow(fake_desc).to receive(:products).and_return(
      products.map { |p| SPMCache::SPM::Desc::Product.new(raw: p, pkg_dir: pkg_dir) },
    )
    allow(fake_desc).to receive(:raw).and_return({ "targets" => [] })
    fake_desc
  end

  def write_resolved_pins(path, pin_map)
    File.write(path, JSON.generate(
      "pins" => pin_map.map { |identity, revision| { "identity" => identity, "state" => { "revision" => revision } } },
    ))
  end

  def write_resolved(path, identity, revision)
    write_resolved_pins(path, { identity => revision })
  end

  # Records one observed bucket value for a package identity and returns the
  # identity's collected bucket set (deduplicated). The partition classifier
  # COLLECTS every matching bucket instead of stopping at the first match, so
  # a package that lands in two buckets is visible as a two-member set --
  # that is how SC2's double-bucket arm is detectable at all.
  def observe_bucket(store, identity, bucket)
    collected = (store[identity] ||= [])
    collected << bucket unless bucket.nil?
    collected.uniq
  end

  # The partition-violation collector: computes BOTH arms' offending sets
  # over the declared universe. Zero-bucket members are silently-absent
  # packages; double-bucket members carry two or more distinct observed
  # buckets. Pure function of (universe, observations) -- identity-keyed
  # Hash lookups only, never positional, so universe order cannot change
  # the outcome.
  def partition_violations(universe, observations)
    zero_bucket = universe.select { |identity| observations[identity].to_a.uniq.empty? }
    double_bucket = universe.select { |identity| observations[identity].to_a.uniq.length > 1 }
    [zero_bucket, double_bucket]
  end

  # Drives one package through the REAL BuildPipeline.run + report_fidelity
  # on the tier-1 seam and returns the built output path. `seeded_pins` is
  # the host graph declared to resolved_pins_file; `realized_pins` is what
  # the stubbed build leaves in pkg_dir/Package.resolved (rewriting it is the
  # proven drift-injection idiom -- passing the same values as the seed
  # yields the agreeing-pins leg). `vendored: true` drops a `<name>.xcodeproj`
  # directory into pkg_dir so ResolvedGraph's glob classifies the checkout
  # before any seeding happens.
  def run_tier1_leg(name:, seeded_pins:, realized_pins:, vendored: false)
    pkg_dir = File.join(tmpdir, "pkg-#{name.downcase}")
    FileUtils.mkdir_p(pkg_dir)
    FileUtils.mkdir_p(out_dir)
    FileUtils.mkdir_p(File.join(pkg_dir, "#{name}.xcodeproj")) if vendored
    write_resolved_pins(resolved_pins_file, seeded_pins)

    stub_desc_products([{ "name" => name, "type" => { "library" => ["automatic"] } }], pkg_dir)

    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
      write_resolved_pins(File.join(pkg_dir, "Package.resolved"), realized_pins)
      {
        derived_data: "/dd",
        object_file: "/dd/#{name}.o",
        swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
      }
    end
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "#{name}.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, name), "stub")
      fw
    end

    allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
      double("XCFramework", build: File.join(out_dir, "#{name}.xcframework")),
    )

    SPMCache::SPM::BuildPipeline.run(
      name: name, pkg_dir: pkg_dir, destinations: ["iphonesimulator"],
      out_dir: out_dir, resolved_pins_file: resolved_pins_file, config: "debug",
    )
  end

  def write_lockfile(path, project_name:, packages:, dependencies: {})
    File.write(path, JSON.generate(
      project_name => {
        "packages" => packages,
        "dependencies" => dependencies,
        "platforms" => { "ios" => "16.0" },
      },
    ))
  end

  def ignore_pattern
    "Noise*"
  end

  def cache_only_patterns
    # Every package the graph leg should classify by cache availability
    # rather than by the inverted allowlist. SideCartKit is deliberately
    # absent so the --cache-only exclusion is observable; NoiseInjector is
    # deliberately present so the ignore decision is not shadowed by the
    # exclusion decision (excluded wins in ProxyGenerator's if/elsif).
    "Alamofire,NoiseInjector,PrimeKit"
  end

  # Fixture-authored ownership map: graph.json is per-PRODUCT (module) and
  # GraphEntry carries no package identity (ProxyGenerator.swift), so the
  # spec maps each module back to its owning lockfile package -- it can,
  # because it authored the kitchen sink. All partition lookups go through
  # this Hash, never through graph entry position.
  def ownership_map
    {
      "Alamofire" => "Alamofire",
      "SwiftGenPlugin" => "SwiftGenPlugin",
      "NoiseInjector" => "NoiseInjector",
      "SideCartKit" => "SideCartKit",
      "PrimeCore" => "PrimeKit",
      "PrimeExtras" => "PrimeKit",
      "TransitiveCore" => "TransitiveCore",
      "LocalDesignKit" => "LocalDesignKit",
    }
  end

  def run_gen_proxy(ignore: nil, cache_only: nil)
    cmd = "#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{fixture_lockfile} " \
          "--output #{output_dir} --cache #{cache_dir}"
    cmd += " --ignore #{Shellwords.escape(ignore)}" if ignore
    cmd += " --cache-only #{Shellwords.escape(cache_only)}" if cache_only
    system(cmd, out: File::NULL, err: File::NULL)
  end

  def statuses_from(dir)
    graph = JSON.parse(File.read(File.join(dir, "graph.json")))
    graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
  end

  # Per-package aggregation: collects the set of statuses of each package's
  # owned graph entries, keyed by lockfile package identity. graph.json is
  # per-product and a multi-product package legitimately emits several
  # entries -- partitioning per-product would misread that product
  # granularity as double-bucketing (RESEARCH Pitfall 3).
  def package_statuses_from(dir)
    statuses_from(dir).each_with_object({}) do |(module_name, status), per_package|
      owner = ownership_map[module_name]
      next unless owner

      (per_package[owner] ||= []) << status
    end
  end

  # Seeds one cached module for a hit decision: the xcframework directory
  # plus the provenance sidecar BinariesCache.hit() reads back. Only `pins`
  # is load-bearing for hit() -- the recorded pin must equal the lockfile
  # entry's revision-over-version pinValue for the owning identity.
  def seed_cache_hit(cache_root, module_name, identity, pin)
    FileUtils.mkdir_p(File.join(cache_root, "#{module_name}.xcframework"))
    File.write(
      File.join(cache_root, "#{module_name}.xcframework.provenance.json"),
      JSON.generate("pins" => { identity => pin }),
    )
  end

  # Which graph statuses are cache-availability outcomes (and therefore NOT
  # fidelity buckets) is OBSERVED from production, never typed: a config-
  # unconstrained canary package (library product, no --ignore/--cache-only
  # patterns) is run twice -- once against an empty cache, once against its
  # own cached artifact with an agreeing sidecar pin. The two statuses it
  # yields are exactly the ones ProxyGenerator computes from
  # BinariesCache.hit() rather than from the package's identity, so the
  # partition excludes them from its bucket vocabulary. Every other status
  # the generator can emit is decided by the package's config or type and
  # IS a bucket.
  def cache_availability_statuses
    canary_output = File.join(tmpdir, "canary-proxy")
    canary_cache = File.join(tmpdir, "canary-cache")
    canary_lockfile = File.join(tmpdir, "canary-lock.json")
    FileUtils.mkdir_p(canary_output)
    FileUtils.mkdir_p(canary_cache)
    write_lockfile(canary_lockfile, project_name: "CanaryApp.xcodeproj", packages: [
      {
        "repositoryURL" => "https://example.invalid/CanaryKit.git",
        "name" => "CanaryKit",
        "revision" => "can111",
      },
    ], dependencies: { "CanaryApp" => ["CanaryKit"] })

    cmd = "#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{canary_lockfile} " \
          "--output #{canary_output} --cache #{canary_cache}"
    system(cmd, out: File::NULL, err: File::NULL)
    empty_cache_status = statuses_from(canary_output)["CanaryKit"]

    seed_cache_hit(canary_cache, "CanaryKit", "CanaryKit", "can111")
    system(cmd, out: File::NULL, err: File::NULL)
    populated_cache_status = statuses_from(canary_output)["CanaryKit"]

    [empty_cache_status, populated_cache_status].compact.uniq
  end

  def fixture_project
    JSON.parse(File.read(fixture_lockfile)).fetch("FixtureApp.xcodeproj")
  end

  def fixture_packages_by_name
    fixture_project.fetch("packages").each_with_object({}) { |p, map| map[p.fetch("name")] = p }
  end

  def fixture_consumed_products
    fixture_project.fetch("dependencies").values.flatten
  end

  describe SPMCache::SPM::BuildPipeline, "tier-1 fidelity legs" do
    it "TEST-02: a pinned package is observed in exactly one bucket, read back from its sidecar" do
      expect(SPMCache::Core::UI).not_to receive(:warn)

      # WR-02: anchor the leg's identity to the DECLARED input universe -- the
      # kitchen-sink fixture's own package list, read from the fixture on
      # disk, never from this leg's output. The partition is only defined
      # over declared identities, so a fixture edit or leg rename that
      # orphaned the tracer from the universe fails HERE, before any bucket
      # is counted.
      identity = "Alamofire"
      expect(fixture_packages_by_name.keys).to include(identity)

      result = run_tier1_leg(
        name: identity,
        seeded_pins: { identity => "aaa111" },
        realized_pins: { identity => "aaa111" },
      )

      parsed = JSON.parse(File.read("#{result}.provenance.json"))
      status_read_from_sidecar = parsed.fetch("fidelity_status")
      expect(status_read_from_sidecar).to be_a(String), "sidecar must record a fidelity_status"
      expect(status_read_from_sidecar).not_to be_empty
      expect(parsed["pins"]).to eq(identity => "aaa111")

      # WR-02: the "exactly one bucket" claim, made non-tautological. The
      # identity's bucket set is collected from BOTH production surfaces that
      # classify it -- the sidecar status above plus the compiled proxy's
      # graph.json aggregated through the ownership map, with the
      # canary-observed cache-availability statuses filtered out (the same
      # semantics as the SC2 partition) -- and then checked through the real
      # partition classifier, both arms. The graph surface INDEPENDENTLY
      # re-classifies the identity, so a production change that drops its
      # graph classification (the not_to be_empty expectation below) or
      # emits a second, non-availability status for this consumed,
      # allowlisted package (the double-bucket arm) fails this example, as
      # does a dropped sidecar classification (the fetch above).
      skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary

      observations = {}
      observe_bucket(observations, identity, status_read_from_sidecar)

      run_gen_proxy(ignore: ignore_pattern, cache_only: cache_only_patterns)
      graph_statuses = package_statuses_from(output_dir).fetch(identity, [])
      expect(graph_statuses).not_to be_empty,
             "graph surface must classify the declared identity #{identity.inspect}"
      availability = cache_availability_statuses
      graph_statuses.each do |status|
        observe_bucket(observations, identity, status) unless availability.include?(status)
      end

      zero_bucket, double_bucket = partition_violations([identity], observations)
      expect(zero_bucket).to be_empty,
                             "TEST-02 zero-bucket members (silently absent): " +
                             zero_bucket.map { |i| "#{i} (observed #{observations[i].to_a.uniq.inspect})" }.join(", ")
      expect(double_bucket).to be_empty,
                               "TEST-02 double-bucket members: " +
                               double_bucket.map { |i| "#{i} (observed #{observations[i].to_a.uniq.inspect})" }.join(", ")
    end
  end

  # The Swift-side classifications (ignored / excluded / plugin) exist ONLY
  # in ProxyGenerator's graph.json output, so these legs run the actual
  # compiled spm-cache-proxy binary -- offline, via system() with output
  # redirected to File::NULL: no network, no xcodebuild (SC4). CI builds
  # the binary before RSpec on every matrix leg; locally the examples skip
  # when it is not built.
  describe "tier-3 graph legs via compiled spm-cache-proxy" do
    before do
      skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary
    end

    it "TEST-02: the ignore-glob-matched package's products report the ignored status" do
      run_gen_proxy(ignore: ignore_pattern, cache_only: cache_only_patterns)

      expect(statuses_from(output_dir)["NoiseInjector"]).to eq("ignored")
    end

    it "TEST-02: the package outside the --cache-only allowlist reports the excluded status" do
      run_gen_proxy(ignore: ignore_pattern, cache_only: cache_only_patterns)

      expect(statuses_from(output_dir)["SideCartKit"]).to eq("excluded")
    end

    it "TEST-02: the plugin-only package's plugin product reports the plugin status" do
      run_gen_proxy(ignore: ignore_pattern, cache_only: cache_only_patterns)

      expect(statuses_from(output_dir)["SwiftGenPlugin"]).to eq("plugin")
    end

    it "TEST-02: the transitive-only package contributes NO graph entry -- classified input-side, never silently absent" do
      run_gen_proxy(ignore: ignore_pattern, cache_only: cache_only_patterns)

      # Production skips transitive-only packages by design
      # (ProxyGenerator.swift: isTransitiveOnly -> continue): referencing
      # them from the root proxy would independently pin them at a
      # conflicting version. Their absence from graph.json is therefore
      # INTENTIONAL -- the partition classifies them from the input side
      # (pinned via their consumer), which is exactly why a graph-derived
      # universe would be vacuous.
      expect(statuses_from(output_dir)["TransitiveCore"]).to be_nil
    end

    it "TEST-02: the local/path lockfile entry never reaches gen-proxy -- its bucket is lockfile-side" do
      run_gen_proxy(ignore: ignore_pattern, cache_only: cache_only_patterns)

      # SwiftPM never lists a local/path package in Package.resolved, so
      # its fidelity outcome can only come from the lockfile side (the
      # empty repositoryURL rule, DIAG-01 precedent). The fixture keeps it
      # out of the consumed set, so the generator emits no entry for it
      # either -- the partition must not depend on gen-proxy mentioning it
      # at all.
      expect(statuses_from(output_dir)["LocalDesignKit"]).to be_nil
    end

    it "TEST-02: a multi-product package's product statuses collapse under ONE identity (aggregation)" do
      # One product cached (agreeing sidecar pin for the package identity),
      # its sibling not: the generator's mixed-status handling downgrades
      # the missed sibling so the package's entries diverge per product.
      seed_cache_hit(cache_dir, "PrimeCore", "PrimeKit", "prime111")
      run_gen_proxy(ignore: ignore_pattern, cache_only: cache_only_patterns)

      statuses = statuses_from(output_dir)
      expect(statuses["PrimeCore"]).to eq("hit")
      expect(statuses["PrimeExtras"]).to eq("excluded")

      per_package = package_statuses_from(output_dir)
      expect(per_package.keys).to include("PrimeKit")
      expect(per_package["PrimeKit"]).to contain_exactly("hit", "excluded")
      # Identity-keyed access, not positional: both product entries resolve
      # through the one ownership map to the one package key.
      expect(ownership_map.values.count("PrimeKit")).to eq(2)
    end
  end

  # The partition itself: both surfaces plus the input-side rules, asserted
  # over the declared universe with BOTH arms in one example.
  describe "the SC2 partition assertion (completeness + disjointness)" do
    before do
      skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary
    end

    it "TEST-02/SC2: every declared package lands in exactly one bucket -- none silently absent, none double-bucketed" do
      observations = {}

      # Surface 1 -- provenance sidecars via the tier-1 seam (real
      # report_fidelity): three legs, three sidecar-observable buckets. The
      # pinned leg's seed carries the transitive-only package's pin too,
      # because report_fidelity's realized pin map is the package's whole
      # transitive closure -- the consumer's sidecar is what attests the
      # transitive pin on record.
      pinned_seed = { "Alamofire" => "aaa111", "TransitiveCore" => "ttt111" }
      drifted_seed = { "DriftyKit" => "ddd111" }
      vendored_seed = { "CryptoSwift" => "ccc111" }

      pinned_result = run_tier1_leg(name: "Alamofire", seeded_pins: pinned_seed, realized_pins: pinned_seed)
      pinned_sidecar = JSON.parse(File.read("#{pinned_result}.provenance.json"))
      observe_bucket(observations, "Alamofire", pinned_sidecar.fetch("fidelity_status"))
      expect(pinned_sidecar.fetch("pins")).to include("TransitiveCore" => "ttt111")

      drifted_result = run_tier1_leg(name: "DriftyKit", seeded_pins: drifted_seed,
                                     realized_pins: { "DriftyKit" => "ddd222" })
      drifted_sidecar = JSON.parse(File.read("#{drifted_result}.provenance.json"))
      observe_bucket(observations, "DriftyKit", drifted_sidecar.fetch("fidelity_status"))

      vendored_result = run_tier1_leg(name: "CryptoSwift", seeded_pins: vendored_seed,
                                      realized_pins: vendored_seed, vendored: true)
      vendored_sidecar = JSON.parse(File.read("#{vendored_result}.provenance.json"))
      observe_bucket(observations, "CryptoSwift", vendored_sidecar.fetch("fidelity_status"))

      # Surface 2 -- graph.json via the compiled proxy, aggregated per
      # package identity through the ownership map, with the canary-observed
      # cache-availability statuses filtered out of the bucket vocabulary.
      seed_cache_hit(cache_dir, "PrimeCore", "PrimeKit", "prime111")
      run_gen_proxy(ignore: ignore_pattern, cache_only: cache_only_patterns)
      availability = cache_availability_statuses
      graph_statuses = package_statuses_from(output_dir)
      graph_statuses.each do |identity, statuses|
        statuses.each do |status|
          observe_bucket(observations, identity, status) unless availability.include?(status)
        end
      end

      # Input-side rules -- both reuse OBSERVED bucket values, never typed
      # names: the local/path entry (empty repositoryURL) joins the bucket
      # the --cache-only inversion produced for SideCartKit (DIAG-01
      # precedent extended: excluded from the drift comparison, but still
      # partitioned); a package whose products are provably unconsumed joins
      # its consumer's pinned bucket, because the generator's intentional
      # skip (cited above) means no graph entry will ever name it.
      excluded_bucket_value = graph_statuses["SideCartKit"].find { |s| !availability.include?(s) }
      transitive_bucket_value = pinned_sidecar.fetch("fidelity_status")
      packages_by_name = fixture_packages_by_name
      consumed = fixture_consumed_products
      packages_by_name.each_value do |entry|
        identity = entry.fetch("name")
        entry_products = (entry["products"] || []).map { |p| p["name"] }
        if entry["repositoryURL"].to_s.empty?
          observe_bucket(observations, identity, excluded_bucket_value)
        elsif !entry_products.empty? && entry_products.none? { |n| consumed.include?(n) }
          observe_bucket(observations, identity, transitive_bucket_value)
        end
      end

      # The universe is the declared INPUT set -- fixture lockfile packages
      # (the local/path entry included) plus the tier-1 legs' resolved pin
      # identities -- never derived from sidecar or graph.json iteration.
      universe = (packages_by_name.keys + pinned_seed.keys + drifted_seed.keys + vendored_seed.keys).uniq

      zero_bucket, double_bucket = partition_violations(universe, observations)
      expect(zero_bucket).to be_empty,
                             "TEST-02 zero-bucket members (silently absent): " +
                             zero_bucket.map { |i| "#{i} (observed #{observations[i].to_a.uniq.inspect})" }.join(", ")
      expect(double_bucket).to be_empty,
                               "TEST-02 double-bucket members: " +
                               double_bucket.map { |i| "#{i} (observed #{observations[i].to_a.uniq.inspect})" }.join(", ")

      # Completeness of the meta-spec itself: the bucket vocabulary this run
      # exercised, read back from production output only, spans at least the
      # six-bucket surface (three sidecar statuses + three graph statuses).
      observed_vocabulary = observations.values.flatten.uniq
      expect(observed_vocabulary.length).to be >= 6
    end
  end

  describe "SC2 edge probes" do
    it "TEST-02 (edge empty): an empty declared universe partitions without raising -- zero violations on both arms" do
      zero_bucket, double_bucket = partition_violations([], {})

      expect(zero_bucket).to be_empty
      expect(double_bucket).to be_empty
    end

    it "TEST-02 (edge empty): an empty-pins resolved file yields an empty drifted set and a single observed bucket" do
      expect(SPMCache::Core::UI).not_to receive(:warn)

      result = run_tier1_leg(name: "EmptyKit", seeded_pins: {}, realized_pins: {})

      parsed = JSON.parse(File.read("#{result}.provenance.json"))
      expect(parsed["pins"]).to eq({})

      observations = {}
      collected = observe_bucket(observations, "EmptyKit", parsed.fetch("fidelity_status"))
      expect(collected.length).to eq(1)
    end

    it "TEST-02 (edge ordering): violation lookups are identity-keyed -- universe order changes nothing" do
      observations = {}
      observe_bucket(observations, "PkgA", "one-bucket")
      observe_bucket(observations, "PkgC", "one-bucket")
      observe_bucket(observations, "PkgC", "another-bucket")

      forward = partition_violations(%w[PkgA PkgB PkgC], observations)
      reversed = partition_violations(%w[PkgC PkgB PkgA], observations)

      expect(forward).to eq([["PkgB"], ["PkgC"]])
      expect(reversed).to eq([["PkgB"], ["PkgC"]])
    end
  end
end
