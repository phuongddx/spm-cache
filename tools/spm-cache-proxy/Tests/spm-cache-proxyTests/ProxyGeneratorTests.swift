import Foundation
import Testing
@testable import spm_cache_proxy

// Field bug: two INDEPENDENTLY generated proxy sub-packages transitively
// depending on the same real upstream package caused Xcode's PIF loader to
// register a duplicate GUID for the shared product ("has already been
// registered"). Concretely: category 3's AppAuth-iOS has a MIXED status
// (AppAuthCore cached -> `.hit`; AppAuth not in cache_only -> `.missed`,
// still gets a shim, unchanged), while category 14's eh_oauth_sdk_ios
// doesn't match cache_only at all -> `.excluded` for its own product. Before
// this fix, eh_oauth_sdk_ios_proxy's shim declared its OWN dependency on the
// real eh_oauth_sdk_ios package, which itself depends on the real
// AppAuth-iOS package -- a SECOND, independent local-package path to the
// exact same real dependency AppAuth-iOS_proxy's own shim already needs.
// Fix: `.excluded`/`.ignored` products get no shim and no proxy-wrapper
// participation at all (mirroring the existing plugin-only treatment),
// eliminating the second path. `.missed` products are untouched -- they are
// legitimately pending caching and still need the shim so `import
// <product>` keeps resolving until they're actually built.
@Suite("ProxyGenerator ignored/excluded product handling")
struct ProxyGeneratorTests {
    func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try dir.mkdir()
        return dir
    }

    @Test("a mixed hit+missed package (AppAuthCore cached, AppAuth not yet built) is unaffected: both keep their proxy entries")
    func mixedHitAndMissedUnaffected() throws {
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
        // the WHOLE package out of `.excluded`; AppAuth is simply `.missed`.
        let generator = ProxyGenerator(
            cache: BinariesCache(dir: cacheDir),
            outputDir: outputDir,
            cacheOnlyPatterns: ["AppAuthCore"]
        )
        let entries = try generator.generate(for: [pkg])

        let appAuthCoreEntry = entries.first { $0.module == "AppAuthCore" }
        let appAuthEntry = entries.first { $0.module == "AppAuth" }
        #expect(appAuthCoreEntry?.status == .hit)
        #expect(appAuthEntry?.status == .missed)

        let proxyDir = outputDir.appendingPathComponent(".proxies").appendingPathComponent("AppAuth-iOS_proxy")
        let manifest = try String(contentsOf: proxyDir.appendingPathComponent("Package.swift"), encoding: .utf8)

        // Unchanged behavior: AppAuth (missed) still gets its shim so the
        // build keeps working until it's actually cached.
        let shimDir = proxyDir.appendingPathComponent("Sources").appendingPathComponent("AppAuth-iOS_AppAuth_shim")
        #expect(shimDir.exists)
        #expect(manifest.contains("\"AppAuth\""))
        #expect(manifest.contains("\"AppAuthCore\""))

        let rootManifest = try String(contentsOf: outputDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(rootManifest.contains(".product(name: \"AppAuth\","))
        #expect(rootManifest.contains(".product(name: \"AppAuthCore\","))
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
