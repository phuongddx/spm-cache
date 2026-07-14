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
