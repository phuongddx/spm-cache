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
            // A transitive-only package is still declared when we hold its exact
            // revision: a revision pin reproduces the host's resolved graph and
            // stops the isolated resolve from floating it to a newer release.
            // That reproduction holds only on two conditions, both of them
            // properties of the lockfile handed to this generator, not of
            // Package.resolved's own internal consistency: the pin must have
            // been reconciled from the host's Package.resolved on this run (a
            // lock frozen at first creation carries a commit that no longer
            // satisfies any parent's range), and the file reconciliation read
            // must have been the canonical
            // project.xcworkspace/xcshareddata/swiftpm/Package.resolved rather
            // than whichever copy a recursive search answered with first.
            // Skip only when there's no revision to pin -- the float-pin
            // conflict that motivated skipping arose with open-ended `from:`
            // pins, which a parent's own range can disagree with.
            if pkg.isTransitiveOnly(consumedProducts: consumedProducts),
               pkg.revision == nil || pkg.repositoryURL == nil {
                continue
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
            // Each PackageDescription platform enum declares a different set
            // of version members (watchOS tops out at .v11, iOS/tvOS at .v18,
            // macOS at .v15, visionOS at .v2); clamp the project's deployment
            // target into the range the target enum actually defines or the
            // generated manifest won't compile (e.g. watchOS 11.6 previously
            // fell through to an invalid .v13).
            let floor: Int, ceiling: Int
            switch platform.lowercased() {
            case "ios", "tvos": floor = 13; ceiling = 18
            case "macos": floor = 13; ceiling = 15
            case "watchos": floor = 4; ceiling = 11
            case "visionos": floor = 1; ceiling = 2
            default: floor = 13; ceiling = 18
            }
            let clamped = min(max(major, floor), ceiling)
            return ".\(pName)(.v\(clamped))"
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
