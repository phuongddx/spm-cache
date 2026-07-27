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
        try cacheDir.appendingPathComponent("AppAuthCore.xcframework").mkdir()

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
}
