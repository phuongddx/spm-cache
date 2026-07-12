import Foundation

struct UmbrellaGenerator {
    let lockfile: Lockfile
    let outputDir: URL

    init(lockfile: Lockfile, outputDir: URL) {
        self.lockfile = lockfile
        self.outputDir = outputDir
    }

    func generate() throws {
        try outputDir.recreate()

        var dependencies: [String] = []
        var targets: [String] = []

        for pkg in lockfile.packages {
            let slug = pkg.slug.c99extidentifier
            if pkg.isLocal, let path = pkg.pathFromRoot {
                dependencies.append(".package(path: \"\(path)\")")
            } else if let url = pkg.repositoryURL {
                dependencies.append(".package(url: \"\(url)\", from: \"0.0.0\")")
            }
            targets.append("""
                .target(
                    name: "\(slug).spm_cache",
                    dependencies: .product(name: "\(pkg.name ?? slug)", package: "\(slug)")
                )
            """)
        }

        let platforms = lockfile.platforms.map { platform, version in
            ".\(platform)(.v\(version.replacingOccurrences(of: ".", with: "_")))"
        }.joined(separator: ", ")

        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "spm_cache_umbrella",
            platforms: [\(platforms)],
            dependencies: [
                \(dependencies.joined(separator: ",\n        "))
            ],
            targets: [
                \(targets.joined(separator: ",\n        "))
            ]
        )
        """

        let packageSwiftPath = outputDir.appendingPathComponent("Package.swift")
        try content.write(to: packageSwiftPath, atomically: true, encoding: .utf8)
        Logger.info("Generated umbrella Package.swift at \(outputDir.path)")
    }
}
