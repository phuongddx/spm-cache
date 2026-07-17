import Foundation
import Testing
@testable import spm_cache_proxy

@Suite("PackageRef.versionRequirement")
struct PackageRefVersionRequirementTests {
    @Test("version-only pin emits from: requirement")
    func versionOnly() {
        let ref = Lockfile.PackageRef(
            repositoryURL: "https://github.com/example/pkg.git",
            pathFromRoot: nil,
            name: "pkg",
            productName: nil,
            version: "1.2.3",
            revision: nil
        )
        #expect(ref.versionRequirement == "from: \"1.2.3\"")
    }

    @Test("revision-only pin emits revision: requirement, not .revision(...)")
    func revisionOnly() {
        let ref = Lockfile.PackageRef(
            repositoryURL: "https://github.com/example/pkg.git",
            pathFromRoot: nil,
            name: "pkg",
            productName: nil,
            version: nil,
            revision: "abc123def456"
        )
        #expect(ref.versionRequirement == "revision: \"abc123def456\"")
    }

    @Test("no version and no revision falls back to 0.1.0")
    func neitherVersionNorRevision() {
        let ref = Lockfile.PackageRef(
            repositoryURL: "https://github.com/example/pkg.git",
            pathFromRoot: nil,
            name: "pkg",
            productName: nil,
            version: nil,
            revision: nil
        )
        #expect(ref.versionRequirement == "from: \"0.1.0\"")
    }

    @Test("version takes precedence over revision when both are set")
    func versionWinsOverRevision() {
        let ref = Lockfile.PackageRef(
            repositoryURL: "https://github.com/example/pkg.git",
            pathFromRoot: nil,
            name: "pkg",
            productName: nil,
            version: "2.0.0",
            revision: "abc123def456"
        )
        #expect(ref.versionRequirement == "from: \"2.0.0\"")
    }
}

@Suite("UmbrellaGenerator transitive-only package skip")
struct UmbrellaGeneratorTransitiveSkipTests {
    private func makePackage(
        name: String,
        url: String,
        version: String,
        products: [Lockfile.ProductRef]?
    ) -> Lockfile.PackageRef {
        Lockfile.PackageRef(
            repositoryURL: url,
            pathFromRoot: nil,
            name: name,
            productName: nil,
            version: version,
            revision: nil,
            products: products
        )
    }

    private func generatedPackageSwift(lockfile: Lockfile) throws -> String {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let generator = UmbrellaGenerator(lockfile: lockfile, outputDir: outputDir)
        try generator.generate()
        return try String(contentsOf: outputDir.appendingPathComponent("Package.swift"), encoding: .utf8)
    }

    // Reproduces the real-world realm-swift/realm-core case: realm-core is
    // resolved (Package.resolved records it as a pin) but the host project
    // never links any of its products directly -- only realm-swift's
    // Realm/RealmSwift products are consumed. Regression: the umbrella used
    // to pin both independently, which could conflict with the version
    // realm-swift's own manifest requires and fail `swift package resolve`.
    @Test("skips a package whose products are never directly consumed")
    func skipsTransitiveOnlyPackage() throws {
        let realmCore = makePackage(
            name: "realm-core",
            url: "https://github.com/realm/realm-core.git",
            version: "13.26.0",
            products: [Lockfile.ProductRef(name: "RealmCore", type: "library", targets: ["RealmCore"])]
        )
        let realmSwift = makePackage(
            name: "realm-swift",
            url: "https://github.com/realm/realm-swift",
            version: "10.47.0",
            products: [Lockfile.ProductRef(name: "RealmSwift", type: "library", targets: ["Realm", "RealmSwift"])]
        )
        let lockfile = Lockfile(
            packages: [realmCore, realmSwift],
            dependencies: ["AppTarget": ["RealmSwift"]],
            platforms: ["ios": "16.0"]
        )

        let content = try generatedPackageSwift(lockfile: lockfile)

        #expect(!content.contains("realm-core"))
        #expect(content.contains("realm-swift"))
    }

    @Test("keeps a package when consumedProducts data is empty (legacy lockfile)")
    func keepsEverythingWhenNoConsumptionDataAvailable() throws {
        let realmCore = makePackage(
            name: "realm-core",
            url: "https://github.com/realm/realm-core.git",
            version: "13.26.0",
            products: [Lockfile.ProductRef(name: "RealmCore", type: "library", targets: ["RealmCore"])]
        )
        let lockfile = Lockfile(packages: [realmCore], dependencies: [:], platforms: ["ios": "16.0"])

        let content = try generatedPackageSwift(lockfile: lockfile)

        #expect(content.contains("realm-core"))
    }

    @Test("keeps a package that has no product metadata yet (unenriched)")
    func keepsUnenrichedPackage() throws {
        let pkg = makePackage(
            name: "some-pkg",
            url: "https://github.com/example/some-pkg.git",
            version: "1.0.0",
            products: nil
        )
        let lockfile = Lockfile(packages: [pkg], dependencies: ["AppTarget": ["Unrelated"]], platforms: ["ios": "16.0"])

        let content = try generatedPackageSwift(lockfile: lockfile)

        #expect(content.contains("some-pkg"))
    }
}

@Suite("ProxyGenerator transitive-only package skip")
struct ProxyGeneratorTransitiveSkipTests {
    private func makePackage(
        name: String,
        url: String,
        version: String,
        products: [Lockfile.ProductRef]?
    ) -> Lockfile.PackageRef {
        Lockfile.PackageRef(
            repositoryURL: url,
            pathFromRoot: nil,
            name: name,
            productName: nil,
            version: version,
            revision: nil,
            products: products
        )
    }

    private func generate(
        packages: [Lockfile.PackageRef],
        consumedProducts: Set<String>
    ) throws -> (entries: [ProxyGenerator.GraphEntry], outputDir: URL) {
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let generator = ProxyGenerator(cache: BinariesCache(dir: cacheDir), outputDir: outputDir)
        let entries = try generator.generate(for: packages, consumedProducts: consumedProducts)
        return (entries, outputDir)
    }

    // Reproduces the real-world realm-swift/realm-core case at the PROXY
    // layer (not just the umbrella): the root proxy used to reference every
    // lockfile package's own sub-proxy unconditionally, so realm-core_proxy
    // (pinning realm-core independently) got wired into the real Xcode
    // project's package graph even though the app only ever links
    // Realm/RealmSwift -- reproducing the exact same version conflict
    // UmbrellaGenerator was fixed to avoid, just one layer deeper.
    @Test("does not generate a sub-proxy or root-proxy reference for a transitive-only package")
    func skipsTransitiveOnlyPackage() throws {
        let realmCore = makePackage(
            name: "realm-core",
            url: "https://github.com/realm/realm-core.git",
            version: "13.26.0",
            products: [Lockfile.ProductRef(name: "RealmCore", type: "library", targets: ["RealmCore"])]
        )
        let realmSwift = makePackage(
            name: "realm-swift",
            url: "https://github.com/realm/realm-swift",
            version: "10.47.0",
            products: [Lockfile.ProductRef(name: "RealmSwift", type: "library", targets: ["Realm", "RealmSwift"])]
        )

        let (entries, outputDir) = try generate(
            packages: [realmCore, realmSwift],
            consumedProducts: ["RealmSwift"]
        )
        defer { try? FileManager.default.removeItem(at: outputDir) }

        #expect(!FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(".proxies/realm-core_proxy").path))
        #expect(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(".proxies/realm-swift_proxy").path))
        #expect(!entries.contains { $0.module == "RealmCore" })

        let rootProxy = try String(contentsOf: outputDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!rootProxy.contains("realm-core_proxy"))
        #expect(rootProxy.contains("realm-swift_proxy"))
    }

    @Test("keeps every package when consumedProducts is empty (legacy lockfile)")
    func keepsEverythingWhenNoConsumptionDataAvailable() throws {
        let realmCore = makePackage(
            name: "realm-core",
            url: "https://github.com/realm/realm-core.git",
            version: "13.26.0",
            products: [Lockfile.ProductRef(name: "RealmCore", type: "library", targets: ["RealmCore"])]
        )

        let (entries, outputDir) = try generate(packages: [realmCore], consumedProducts: [])
        defer { try? FileManager.default.removeItem(at: outputDir) }

        #expect(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(".proxies/realm-core_proxy").path))
        #expect(entries.contains { $0.module == "RealmCore" })
    }
}
