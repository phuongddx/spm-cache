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
            let slug = pkg.slug
            let productName = pkg.resolvedProductName
            let packageIdentity = slug
            let targetName = "\(slug.c99extidentifier)_spm_cache"

            if pkg.isLocal, let path = pkg.pathFromRoot {
                dependencies.append(".package(path: \"\(path)\")")
            } else if let url = pkg.repositoryURL {
                let req = pkg.versionRequirement
                dependencies.append(".package(url: \"\(url)\", \(req))")
            }
            targets.append("""
                .target(
                    name: "\(targetName)",
                    dependencies: [.product(name: "\(productName)", package: "\(packageIdentity)")]
                )
            """)

            // Create stub source directory
            let sourcesDir = outputDir.appendingPathComponent("Sources").appendingPathComponent(targetName)
            try sourcesDir.mkdir()
            try "".write(to: sourcesDir.appendingPathComponent("\(targetName).swift"), atomically: true, encoding: .utf8)
        }

        let platformStrings = lockfile.platforms.map { platform, version -> String in
            let parts = version.split(separator: ".").map(String.init)
            let major = Int(parts[0]) ?? 15
            let pName: String
            switch platform.lowercased() {
            case "ios": pName = "iOS"
            case "macos": pName = "macOS"
            case "tvos": pName = "tvOS"
            case "watchos": pName = "watchOS"
            case "visionos": pName = "visionOS"
            default: pName = platform
            }
            let versionEnum: String
            switch major {
            case 13: versionEnum = "v13"
            case 14: versionEnum = "v14"
            case 15: versionEnum = "v15"
            case 16: versionEnum = "v16"
            case 17: versionEnum = "v17"
            case 18: versionEnum = "v18"
            default:
                if major >= 18 { versionEnum = "v18" }
                else if major >= 15 { versionEnum = "v15" }
                else { versionEnum = "v13" }
            }
            return ".\(pName)(.\(versionEnum))"
        }

        // Always include macOS for swift build compatibility
        var allPlatforms = platformStrings
        if !lockfile.platforms.keys.contains(where: { $0.lowercased() == "macos" }) {
            allPlatforms.append(".macOS(.v14)")
        }
        let platforms = allPlatforms.joined(separator: ", ")

        let content = """
        // swift-tools-version: 6.0
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
