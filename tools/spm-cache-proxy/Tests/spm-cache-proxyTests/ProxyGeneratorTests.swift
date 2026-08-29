import Foundation
import Testing
@testable import spm_cache_proxy

// Field bug: a package with a MIXED hit+missed status (one product cached,
// a sibling still pending/unbuildable) put both a .binaryTarget AND a shim
// re-declaring a dependency on the real upstream package in the SAME
// sub-proxy manifest. Xcode's PIF loader chokes on that co-existence
// regardless of whether anything actually consumes the missed sibling --
// confirmed for three unrelated packages in one session: AppAuth-iOS
// (AppAuthCore hit / AppAuth missed -> "already been registered"),
// realm-swift (Realm hit / RealmSwift missed -> same), and PhoneNumberKit
// (PhoneNumberKit hit / PhoneNumberKit-Static+Dynamic missed, and NOT even
// independently buildable -- no dedicated scheme exists for those variants
// -> "multiple targets with the same GUID"). Fix: once a package has ANY
// cached product, every OTHER still-missed sibling is downgraded to
// `.excluded` -- same no-shim, restore-to-real-ref treatment a genuinely
// config-excluded product gets (see the eh_oauth_sdk_ios tests below), so
// the diamond never forms. A package with NO hit products yet is
// unaffected: its missed products still get shims as normal, since nothing
// conflicts until the first sibling is actually cached.
@Suite("ProxyGenerator ignored/excluded product handling")
struct ProxyGeneratorTests {
    func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try dir.mkdir()
        return dir
    }

    @Test("a mixed hit+missed package (AppAuthCore cached, AppAuth not yet built) downgrades the missed sibling to excluded: no shim, no proxy entry")
    func mixedHitAndMissedDowngradesMissedSibling() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cacheDir = tmp.appendingPathComponent("cache")
        try cacheDir.mkdir()
        // AppAuthCore is cached (a real xcframework dir exists); AppAuth has none.
        // An empty-pins sidecar keeps this fixture's hit() decision
        // unaffected by CACHE-02's identity/pin check (not-graph-pinned
        // steady state -- intersection-only, no evidence of drift).
        try cacheDir.appendingPathComponent("AppAuthCore.xcframework").mkdir()
        try JSONSerialization.data(withJSONObject: ["pins": [String: String]()])
            .write(to: cacheDir.appendingPathComponent("AppAuthCore.xcframework.provenance.json"))

        let outputDir = tmp.appendingPathComponent("proxy")
        let pkg = Lockfile.PackageRef(
            repositoryURL: "https://github.com/openid/AppAuth-iOS.git",
            pathFromRoot: nil,
            name: "AppAuth-iOS",
            productName: nil,
            version: nil,
            revision: "01131d68346c8ae552961c768d583c715fbe1410",
            products: [
                .init(name: "AppAuthCore", type: "library", targets: ["AppAuthCore"]),
                .init(name: "AppAuth", type: "library", targets: ["AppAuth"]),
            ]
        )

        // cache_only matches ONE of this package's products (AppAuthCore),
        // which -- per matchesAnyPattern's package-level semantics -- keeps
        // the WHOLE package out of `.excluded`; AppAuth starts as `.missed`
        // but is then downgraded to `.excluded` because AppAuthCore is hit.
        let generator = ProxyGenerator(
            cache: BinariesCache(dir: cacheDir),
            outputDir: outputDir,
            cacheOnlyPatterns: ["AppAuthCore"]
        )
        let entries = try generator.generate(for: [pkg])

        let appAuthCoreEntry = entries.first { $0.module == "AppAuthCore" }
        let appAuthEntry = entries.first { $0.module == "AppAuth" }
        #expect(appAuthCoreEntry?.status == .hit)
        #expect(appAuthEntry?.status == .excluded)

        let proxyDir = outputDir.appendingPathComponent(".proxies").appendingPathComponent("AppAuth-iOS_proxy")
        let manifest = try String(contentsOf: proxyDir.appendingPathComponent("Package.swift"), encoding: .utf8)

        // AppAuth (downgraded to excluded) gets no shim at all now.
        let shimDir = proxyDir.appendingPathComponent("Sources").appendingPathComponent("AppAuth-iOS_AppAuth_shim")
        #expect(!shimDir.exists)
        #expect(!manifest.contains("\"AppAuth\""))
        #expect(manifest.contains("\"AppAuthCore\""))

        let rootManifest = try String(contentsOf: outputDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!rootManifest.contains(".product(name: \"AppAuth\","))
        #expect(rootManifest.contains(".product(name: \"AppAuthCore\","))
    }

    @Test("a package with NO hit products yet keeps normal shims for all its missed products")
    func noHitProductsKeepsShimsForAllMissed() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cacheDir = tmp.appendingPathComponent("cache")
        try cacheDir.mkdir()
        // Nothing cached yet for either product.

        let outputDir = tmp.appendingPathComponent("proxy")
        let pkg = Lockfile.PackageRef(
            repositoryURL: "https://github.com/openid/AppAuth-iOS.git",
            pathFromRoot: nil,
            name: "AppAuth-iOS",
            productName: nil,
            version: nil,
            revision: "01131d68346c8ae552961c768d583c715fbe1410",
            products: [
                .init(name: "AppAuthCore", type: "library", targets: ["AppAuthCore"]),
                .init(name: "AppAuth", type: "library", targets: ["AppAuth"]),
            ]
        )

        let generator = ProxyGenerator(
            cache: BinariesCache(dir: cacheDir),
            outputDir: outputDir,
            cacheOnlyPatterns: ["AppAuthCore"]
        )
        let entries = try generator.generate(for: [pkg])

        // Neither is hit yet, so neither gets downgraded -- both stay missed
        // with a normal shim, exactly as before this fix.
        #expect(entries.first { $0.module == "AppAuthCore" }?.status == .missed)
        #expect(entries.first { $0.module == "AppAuth" }?.status == .missed)

        let proxyDir = outputDir.appendingPathComponent(".proxies").appendingPathComponent("AppAuth-iOS_proxy")
        let appAuthShimDir = proxyDir.appendingPathComponent("Sources").appendingPathComponent("AppAuth-iOS_AppAuth_shim")
        let appAuthCoreShimDir = proxyDir.appendingPathComponent("Sources").appendingPathComponent("AppAuth-iOS_AppAuthCore_shim")
        #expect(appAuthShimDir.exists)
        #expect(appAuthCoreShimDir.exists)
    }

    // Reproduces swift-numerics' RealModule -> _NumericsShims shape: a hit
    // product whose own `.swiftinterface` needs a private (non-product)
    // Clang-target dependency resolvable on its own. The Ruby build
    // pipeline builds a companion `_NumericsShims.xcframework` alongside
    // the main one and records it in a `<module>.xcframework.shims.json`
    // sidecar (see BinariesCache.shims(for:)); the proxy generator must
    // wire the shim in as an EXTRA `.binaryTarget` combined into the SAME
    // `.library` product as the main binary, so Xcode's package graph adds
    // both xcframeworks' framework search paths to any consumer.
    @Test("a hit product with a companion shim xcframework gets an extra binaryTarget combined into the same library product")
    func hitProductWithShimGetsMultiTargetProduct() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cacheDir = tmp.appendingPathComponent("cache")
        try cacheDir.mkdir()
        try cacheDir.appendingPathComponent("RealModule.xcframework").mkdir()
        try cacheDir.appendingPathComponent("_NumericsShims.xcframework").mkdir()
        let sidecar = cacheDir.appendingPathComponent("RealModule.xcframework.shims.json")
        try JSONEncoder().encode(["_NumericsShims"]).write(to: sidecar)
        // Empty-pins provenance sidecar: not-graph-pinned steady state, no
        // evidence of drift against this fixture's CACHE-02 hit() decision.
        try JSONSerialization.data(withJSONObject: ["pins": [String: String]()])
            .write(to: cacheDir.appendingPathComponent("RealModule.xcframework.provenance.json"))

        let outputDir = tmp.appendingPathComponent("proxy")
        let pkg = Lockfile.PackageRef(
            repositoryURL: "https://github.com/apple/swift-numerics.git",
            pathFromRoot: nil,
            name: "swift-numerics",
            productName: nil,
            version: nil,
            revision: "0a5bc04",
            products: [
                .init(name: "RealModule", type: "library", targets: ["RealModule"]),
            ]
        )

        let generator = ProxyGenerator(
            cache: BinariesCache(dir: cacheDir),
            outputDir: outputDir,
            cacheOnlyPatterns: ["RealModule"]
        )
        let entries = try generator.generate(for: [pkg])
        #expect(entries.first { $0.module == "RealModule" }?.status == .hit)

        let proxyDir = outputDir.appendingPathComponent(".proxies").appendingPathComponent("swift-numerics_proxy")
        let manifest = try String(contentsOf: proxyDir.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(manifest.contains(".binaryTarget(name: \"swift-numerics_RealModule_binary\""))
        #expect(manifest.contains(".binaryTarget(name: \"swift-numerics_RealModule__NumericsShims_shim_binary\""))
        #expect(manifest.contains(".library(name: \"RealModule\", targets: [\"swift-numerics_RealModule_binary\", \"swift-numerics_RealModule__NumericsShims_shim_binary\"])"))

        // Both the main binary and the companion shim get symlinked into
        // the shared artifacts dir the proxy manifests reference.
        let artifactsDir = outputDir.appendingPathComponent(".build").appendingPathComponent("artifacts")
        #expect(artifactsDir.appendingPathComponent("RealModule.xcframework").exists)
        #expect(artifactsDir.appendingPathComponent("_NumericsShims.xcframework").exists)
    }

    @Test("a hit product with no shim sidecar gets a single binaryTarget, unchanged from before this feature")
    func hitProductWithoutShimGetsSingleTarget() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cacheDir = tmp.appendingPathComponent("cache")
        try cacheDir.mkdir()
        try cacheDir.appendingPathComponent("Alamofire.xcframework").mkdir()
        // Empty-pins provenance sidecar: not-graph-pinned steady state, no
        // evidence of drift against this fixture's CACHE-02 hit() decision.
        try JSONSerialization.data(withJSONObject: ["pins": [String: String]()])
            .write(to: cacheDir.appendingPathComponent("Alamofire.xcframework.provenance.json"))

        let outputDir = tmp.appendingPathComponent("proxy")
        let pkg = Lockfile.PackageRef(
            repositoryURL: "https://github.com/Alamofire/Alamofire.git",
            pathFromRoot: nil,
            name: "Alamofire",
            productName: nil,
            version: nil,
            revision: "abc123",
            products: [
                .init(name: "Alamofire", type: "library", targets: ["Alamofire"]),
            ]
        )

        let generator = ProxyGenerator(
            cache: BinariesCache(dir: cacheDir),
            outputDir: outputDir,
            cacheOnlyPatterns: ["Alamofire"]
        )
        _ = try generator.generate(for: [pkg])

        let proxyDir = outputDir.appendingPathComponent(".proxies").appendingPathComponent("Alamofire_proxy")
        let manifest = try String(contentsOf: proxyDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(manifest.contains(".library(name: \"Alamofire\", targets: [\"Alamofire_Alamofire_binary\"])"))
        #expect(!manifest.contains("shim_binary"))
    }

    @Test("a package excluded by cache_only (matches none of its patterns) gets no proxy wrapper at all")
    func cacheOnlyExcludedPackageNoWrapper() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cacheDir = tmp.appendingPathComponent("cache")
        try cacheDir.mkdir()
        let outputDir = tmp.appendingPathComponent("proxy")

        let pkg = Lockfile.PackageRef(
            repositoryURL: "git@bitbucket.org:axonivy-prod/eh_oauth_sdk_ios.git",
            pathFromRoot: nil,
            name: "eh_oauth_sdk_ios",
            productName: nil,
            version: nil,
            revision: "305f5b544615af8aabc97625d878363b323d16dd",
            products: [
                .init(name: "eh_oauth_sdk_ios", type: "library", targets: ["eh_oauth_sdk_ios"]),
            ]
        )

        // cache_only is active but doesn't match this package at all --
        // exactly the real eh_oauth_sdk_ios scenario (`ignore:` is skipped
        // entirely once cache_only is non-empty; see Package::Proxy#prepare).
        let generator = ProxyGenerator(
            cache: BinariesCache(dir: cacheDir),
            outputDir: outputDir,
            cacheOnlyPatterns: ["AppAuthCore"]
        )
        let entries = try generator.generate(for: [pkg])

        #expect(entries.first { $0.module == "eh_oauth_sdk_ios" }?.status == .excluded)

        let proxyDir = outputDir.appendingPathComponent(".proxies").appendingPathComponent("eh_oauth_sdk_ios_proxy")
        #expect(!proxyDir.exists)

        let rootManifest = try String(contentsOf: outputDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!rootManifest.contains("eh_oauth_sdk_ios_proxy"))
    }

    @Test("a package whose products are ALL ignored (ignore-list path) gets no proxy wrapper at all")
    func fullyIgnoredPackageNoWrapper() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cacheDir = tmp.appendingPathComponent("cache")
        try cacheDir.mkdir()
        let outputDir = tmp.appendingPathComponent("proxy")

        let pkg = Lockfile.PackageRef(
            repositoryURL: "git@bitbucket.org:axonivy-prod/eh_oauth_sdk_ios.git",
            pathFromRoot: nil,
            name: "eh_oauth_sdk_ios",
            productName: nil,
            version: nil,
            revision: "305f5b544615af8aabc97625d878363b323d16dd",
            products: [
                .init(name: "eh_oauth_sdk_ios", type: "library", targets: ["eh_oauth_sdk_ios"]),
            ]
        )

        let generator = ProxyGenerator(
            cache: BinariesCache(dir: cacheDir),
            outputDir: outputDir,
            ignoredPatterns: ["eh_oauth_sdk_ios"]
        )
        _ = try generator.generate(for: [pkg])

        let proxyDir = outputDir.appendingPathComponent(".proxies").appendingPathComponent("eh_oauth_sdk_ios_proxy")
        #expect(!proxyDir.exists)

        let rootManifest = try String(contentsOf: outputDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!rootManifest.contains("eh_oauth_sdk_ios_proxy"))
    }

    // Regression guard for Pitfall 3: the provenance sidecar's `pins` hash is
    // keyed by PACKAGE identity (pkg.name), never by product name. A
    // two-product package (realm-swift -> Realm + RealmSwift) with a sidecar
    // whose `pins` records an AGREEING entry for the real identity
    // ("realm-swift") but DISAGREEING entries for each product name ("Realm",
    // "RealmSwift") must report BOTH products as hit: a correct
    // implementation looks up pins["realm-swift"] and finds agreement, while
    // a buggy implementation that looked up pins[product.name] instead would
    // find a disagreeing entry and wrongly report both as missed. (A
    // simpler "wrong key = identity totally absent" fixture would NOT
    // distinguish the two implementations here, since this phase's
    // intersection-only comparison rule treats an absent identity as a hit,
    // not a miss -- see the `hit()` cases in CacheTests.swift and this
    // plan's own must_haves.)
    @Test("two-product package hit()s using the package identity (pkg.name), never a product name, as the pins lookup key")
    func hitLooksUpByPackageIdentityNotProductName() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cacheDir = tmp.appendingPathComponent("cache")
        try cacheDir.mkdir()
        try cacheDir.appendingPathComponent("Realm.xcframework").mkdir()
        try cacheDir.appendingPathComponent("RealmSwift.xcframework").mkdir()

        let pkg = Lockfile.PackageRef(
            repositoryURL: "https://github.com/realm/realm-swift",
            pathFromRoot: nil,
            name: "realm-swift",
            productName: nil,
            version: "10.47.0",
            revision: nil,
            products: [
                .init(name: "Realm", type: "library", targets: ["Realm"]),
                .init(name: "RealmSwift", type: "library", targets: ["Realm", "RealmSwift"]),
            ]
        )

        // Each product's own sidecar records the whole host graph's pins:
        // the real package identity ("realm-swift") agrees with pkg.pinValue
        // ("10.47.0"), but the product names themselves are ALSO present,
        // recorded with a disagreeing value -- a lookup keyed on
        // product.name (the bug) would find and disagree with these;
        // a lookup keyed on pkg.name (correct) never sees them.
        let pins: [String: String] = ["realm-swift": "10.47.0", "Realm": "1.0.0", "RealmSwift": "1.0.0"]
        let sidecarPath = cacheDir.appendingPathComponent("Realm.xcframework.provenance.json")
        try JSONSerialization.data(withJSONObject: ["pins": pins]).write(to: sidecarPath)
        let sidecarPath2 = cacheDir.appendingPathComponent("RealmSwift.xcframework.provenance.json")
        try JSONSerialization.data(withJSONObject: ["pins": pins]).write(to: sidecarPath2)

        let outputDir = tmp.appendingPathComponent("proxy")
        let generator = ProxyGenerator(cache: BinariesCache(dir: cacheDir), outputDir: outputDir)
        let entries = try generator.generate(for: [pkg])

        #expect(entries.first { $0.module == "Realm" }?.status == .hit)
        #expect(entries.first { $0.module == "RealmSwift" }?.status == .hit)
    }
}
