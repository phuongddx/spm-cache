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

        // The umbrella's only job is checkout materialization: `swift package
        // resolve` fetches every dependency's checkout from the
        // `dependencies:` array alone and does not validate product/target
        // references (that only happens at build time). So no per-package
        // stub target/product reference is emitted here — that also makes
        // resolve immune to wrong product names, regardless of whether
        // `spm-cache.lock` has been enriched with real product metadata yet.
        //
        // A package already known to be plugin-only (enriched `products[]`
        // metadata present, none of type `library`) is skipped entirely: it
        // has nothing to proxy and its original Xcode reference is kept
        // as-is during integration. A package with no `products` metadata
        // yet (unenriched) is NOT skipped here even if it will turn out to
        // be plugin-only — its checkout must still be resolved once so
        // `enrich_lockfile_products` can run `swift package describe`
        // against it and learn that in the first place.
        for pkg in lockfile.packages {
            if pkg.isPluginOnly { continue }

            if pkg.isLocal, let path = pkg.pathFromRoot {
                dependencies.append(".package(path: \"\(path)\")")
            } else if let url = pkg.repositoryURL {
                let req = pkg.versionRequirement
                dependencies.append(".package(url: \"\(url)\", \(req))")
            }
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
            targets: []
        )
        """

        let packageSwiftPath = outputDir.appendingPathComponent("Package.swift")
        try content.write(to: packageSwiftPath, atomically: true, encoding: .utf8)
        Logger.info("Generated umbrella Package.swift at \(outputDir.path)")
    }
}
