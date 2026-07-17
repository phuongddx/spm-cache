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

        // Product names the host project's targets directly link, per
        // `Installer#refresh_consumed_dependencies`. Used below to tell a
        // directly-consumed package apart from one that's only reachable
        // transitively through another package already in this list (e.g.
        // realm-core, pulled in solely via realm-swift's own dependency
        // declaration, never linked by the app itself).
        let consumedProducts = Set(lockfile.dependencies.values.flatMap { $0 })

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

            // A package whose products are provably never linked directly by
            // the host project (transitive-only) is left out of the
            // umbrella's own dependency list. SwiftPM still resolves and
            // checks out such packages transitively through whichever
            // package actually consumes them, picking a version consistent
            // with the rest of the graph — pinning it again here at its own
            // last-resolved version can conflict with what its parent's
            // manifest requires and fail `swift package resolve` outright,
            // even though the real dependency graph has no conflict.
            // Skipped entirely when there's no consumption data to check
            // against (empty `consumedProducts`) or the package hasn't been
            // enriched with product metadata yet — both cases fall back to
            // today's pin-everything behavior rather than guessing.
            if !consumedProducts.isEmpty, let products = pkg.products, !products.isEmpty {
                let ownProductNames = Set(products.map { $0.name })
                if ownProductNames.isDisjoint(with: consumedProducts) {
                    continue
                }
            }

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
