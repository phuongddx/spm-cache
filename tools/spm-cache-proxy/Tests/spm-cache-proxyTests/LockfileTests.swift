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
