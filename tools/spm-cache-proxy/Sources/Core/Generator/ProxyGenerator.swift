import Foundation

struct ProxyGenerator {
    let cache: BinariesCache
    let outputDir: URL
    let ignoredPatterns: [String]
    let cacheOnlyPatterns: [String]

    init(cache: BinariesCache, outputDir: URL, ignoredPatterns: [String] = [], cacheOnlyPatterns: [String] = []) {
        self.cache = cache
        self.outputDir = outputDir
        self.ignoredPatterns = ignoredPatterns
        self.cacheOnlyPatterns = cacheOnlyPatterns
    }

    struct GraphEntry: Codable {
        enum Status: String, Codable {
            case hit, missed, ignored, excluded, plugin
        }
        let module: String
        let status: Status
        let dependencies: [String]
        let hasMacro: Bool
    }

    /// One library product of a package, with the cache/build decision already
    /// made for it (each product has its own independent hit/miss status).
    private struct ProductBuild {
        let product: Lockfile.ResolvedProduct
        let status: GraphEntry.Status
        let cachedBinary: URL?
    }

    /// Returns true when any glob pattern matches one of the package's real
    /// library product names OR its lockfile identity (`name`). Mirrors the
    /// Ruby `File.fnmatch` default semantics via POSIX `fnmatch`. This is a
    /// package-level decision: the resulting ignored/excluded status applies
    /// uniformly to every product of the package.
    private func matchesAnyPattern(_ pkg: Lockfile.PackageRef, _ patterns: [String]) -> Bool {
        let candidates = pkg.libraryProducts.map { $0.name } + [pkg.name].compactMap { $0 }
        for pattern in patterns {
            for candidate in candidates {
                if fnmatch(pattern, candidate, 0) == 0 {
                    return true
                }
            }
        }
        return false
    }

    /// True when `ignoredPatterns` matches the package (denylist).
    private func isIgnored(_ pkg: Lockfile.PackageRef) -> Bool {
        guard !ignoredPatterns.isEmpty else { return false }
        return matchesAnyPattern(pkg, ignoredPatterns)
    }

    /// True when `cacheOnlyPatterns` is active (non-empty) and the package
    /// matches NONE of its patterns (allowlist, inverted match).
    private func isCacheOnlyExcluded(_ pkg: Lockfile.PackageRef) -> Bool {
        guard !cacheOnlyPatterns.isEmpty else { return false }
        return !matchesAnyPattern(pkg, cacheOnlyPatterns)
    }

    func generate(for packages: [Lockfile.PackageRef], consumedProducts: Set<String> = []) throws -> [GraphEntry] {
        try outputDir.recreate()
        let proxiesDir = outputDir.appendingPathComponent(".proxies")
        try proxiesDir.mkdir()
        let artifactsDir = outputDir.appendingPathComponent(".build").appendingPathComponent("artifacts")
        try artifactsDir.mkdir()

        var entries: [GraphEntry] = []
        // Plugin-only packages (build-tool plugins, e.g. SwiftGenPlugin) get
        // no wrapper folder and no root-proxy dependency: they have no
        // library product to proxy, and keeping a stale reference around
        // would recreate the identity-collision bug at the Xcode layer.
        // Xcode integration (Ruby side) preserves their original package
        // reference directly instead.
        var proxiedPackages: [Lockfile.PackageRef] = []

        for pkg in packages {
            if pkg.isPluginOnly {
                for product in pkg.products ?? [] {
                    entries.append(GraphEntry(
                        module: product.name,
                        status: .plugin,
                        dependencies: [],
                        hasMacro: false
                    ))
                }
                continue
            }

            // A package whose products are provably never linked directly by
            // the host project (transitive-only -- e.g. realm-core, pulled in
            // solely via realm-swift) gets no wrapper folder and no root-proxy
            // dependency either: referencing it here would make the ROOT
            // PROXY's own manifest independently pin it alongside whatever
            // package actually needs it, at a version that can conflict with
            // what that package's own manifest requires -- the same failure
            // mode UmbrellaGenerator avoids, but this time baked into the real
            // Xcode project's package graph instead of spm-cache's internal
            // umbrella. Nothing needs to import it directly, so nothing is
            // lost: whichever package does consume it pulls it in transitively
            // through its own manifest, resolved consistently by SwiftPM.
            if pkg.isTransitiveOnly(consumedProducts: consumedProducts) { continue }

            proxiedPackages.append(pkg)

            let slug = pkg.slug
            let proxyDir = proxiesDir.appendingPathComponent("\(slug)_proxy")
            try proxyDir.mkdir()

            let ignored = isIgnored(pkg)
            let excluded = isCacheOnlyExcluded(pkg)

            // Each library product gets its own independent hit/miss status;
            // ignored/excluded packages are always source, even when a cached
            // binary exists for one of their products.
            let productBuilds: [ProductBuild] = pkg.libraryProducts.map { product in
                let cachedBinary = (ignored || excluded) ? nil : cache.hit(module: product.name)
                let status: GraphEntry.Status
                if excluded {
                    status = .excluded
                } else if ignored {
                    status = .ignored
                } else if cachedBinary != nil {
                    status = .hit
                } else {
                    status = .missed
                }
                return ProductBuild(product: product, status: status, cachedBinary: cachedBinary)
            }

            let packageSwift = generateProxyManifest(pkg: pkg, products: productBuilds)
            let packageSwiftPath = proxyDir.appendingPathComponent("Package.swift")
            try packageSwift.write(to: packageSwiftPath, atomically: true, encoding: .utf8)

            for build in productBuilds {
                let productSlug = "\(slug)_\(build.product.name.c99extidentifier)"

                if let binary = build.cachedBinary {
                    let dest = artifactsDir.appendingPathComponent(binary.lastPathComponent)
                    try? FileManager.default.removeItem(at: dest)
                    try? FileManager.default.createSymbolicLink(
                        at: dest,
                        withDestinationURL: binary
                    )
                } else {
                    // Source fallback (miss or ignored): emit a shim that
                    // re-exports the real package module(s) so `import
                    // <module>` resolves.
                    let sourcesDir = proxyDir.appendingPathComponent("Sources").appendingPathComponent("\(productSlug)_shim")
                    try sourcesDir.mkdir()
                    let shim = generateShimSource(targets: build.product.targets)
                    try shim.write(to: sourcesDir.appendingPathComponent("\(productSlug)_shim.swift"), atomically: true, encoding: .utf8)
                }

                entries.append(GraphEntry(
                    module: build.product.name,
                    status: build.status,
                    dependencies: [],
                    hasMacro: false
                ))
            }
        }

        let rootProxy = generateRootProxy(packages: proxiedPackages)
        let rootProxyPath = outputDir.appendingPathComponent("Package.swift")
        try rootProxy.write(to: rootProxyPath, atomically: true, encoding: .utf8)

        // Create source stub for root proxy target
        let rootSrcDir = outputDir.appendingPathComponent("src").appendingPathComponent("root")
        try rootSrcDir.mkdir()
        try "".write(to: rootSrcDir.appendingPathComponent("spm_cache_root.swift"), atomically: true, encoding: .utf8)

        return entries
    }

    func generateGraphJSON(entries: [GraphEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(entries)
        let path = outputDir.appendingPathComponent("graph.json")
        try data.write(to: path)
        Logger.info("Generated graph.json at \(path.path)")
    }

    /// Emits ONE Package.swift for the package's proxy folder, exporting every
    /// library product by its real name. Each product gets its own target
    /// (binary on cache hit, source shim otherwise); the underlying real
    /// package dependency is declared at most once even when multiple
    /// products fall back to source.
    private func generateProxyManifest(pkg: Lockfile.PackageRef, products: [ProductBuild]) -> String {
        let slug = pkg.slug
        var productLines: [String] = []
        var targetLines: [String] = []
        var depLines: [String] = []
        var sharedDepEmitted = false

        for build in products {
            let productSlug = "\(slug)_\(build.product.name.c99extidentifier)"

            if build.status == .hit, build.cachedBinary != nil {
                let relativePath = "../../.build/artifacts/\(build.product.name).xcframework"
                productLines.append(".library(name: \"\(build.product.name)\", targets: [\"\(productSlug)_binary\"])")
                targetLines.append(".binaryTarget(name: \"\(productSlug)_binary\", path: \"\(relativePath)\")")
            } else {
                let (depLine, targetDep) = sourceDependencyLines(pkg: pkg, productName: build.product.name)
                if !sharedDepEmitted {
                    depLines.append(depLine)
                    sharedDepEmitted = true
                }
                productLines.append(".library(name: \"\(build.product.name)\", targets: [\"\(productSlug)_shim\"])")
                targetLines.append("""
                .target(name: "\(productSlug)_shim", dependencies: [
                                \(targetDep)
                            ], path: "Sources/\(productSlug)_shim")
                """)
            }
        }

        return """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(slug)_proxy",
            products: [
                \(productLines.joined(separator: ",\n        "))
            ],
            dependencies: [
                \(depLines.joined(separator: ",\n        "))
            ],
            targets: [
                \(targetLines.joined(separator: ",\n        "))
            ]
        )
        """
    }

    /// Emits the `.package(...)` dependency line and the `.product(...)` target
    /// dependency line for source fallback (miss/ignored). Remote packages use
    /// `url:from:`; local packages use `path:` resolved relative to the proxy dir.
    private func sourceDependencyLines(pkg: Lockfile.PackageRef, productName: String) -> (dep: String, targetDep: String) {
        let packageIdentity = pkg.slug
        if pkg.isLocal, let path = pkg.pathFromRoot {
            // Proxy Package.swift lives at .proxies/<slug>_proxy/Package.swift;
            // the project root is two levels up.
            let depLine = ".package(path: \"../../\(path)\")"
            let targetDep = ".product(name: \"\(productName)\", package: \"\(packageIdentity)\")"
            return (depLine, targetDep)
        } else {
            let url = pkg.repositoryURL ?? ""
            let req = pkg.versionRequirement
            let depLine = ".package(url: \"\(url)\", \(req))"
            let targetDep = ".product(name: \"\(productName)\", package: \"\(packageIdentity)\")"
            return (depLine, targetDep)
        }
    }

    /// Shim source that re-exports the real module(s) so app-level
    /// `import <productName>` resolves to source compilation. A product can
    /// bundle more than one target module, so one `@_exported import` line is
    /// emitted per target.
    private func generateShimSource(targets: [String]) -> String {
        let imports = targets.map { "@_exported import \($0)" }.joined(separator: "\n")
        return """
        // Auto-generated by spm-cache-proxy: re-exports the source package module(s).
        \(imports)
        """
    }

    private func generateRootProxy(packages: [Lockfile.PackageRef]) -> String {
        var deps: [String] = []
        var targetDeps: [String] = []

        for pkg in packages {
            let slug = pkg.slug
            deps.append(".package(path: \".proxies/\(slug)_proxy\")")
            // Reference EVERY real library product the sub-proxy actually
            // declares (Phase 2: a package can export more than one, e.g.
            // Realm -> Realm + RealmSwift) — referencing just one guessed
            // name here would make `swift build` fail with "product ... not
            // found in package" for any multi-product package.
            for product in pkg.libraryProducts {
                targetDeps.append(".product(name: \"\(product.name)\", package: \"\(slug)_proxy\")")
            }
        }

        return """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "spm_cache_proxy",
            products: [
                .library(name: "spm_cache_proxy", targets: ["spm_cache_root"])
            ],
            dependencies: [
                \(deps.joined(separator: ",\n        "))
            ],
            targets: [
                .target(name: "spm_cache_root", dependencies: [
                    \(targetDeps.joined(separator: ",\n                    "))
                ], path: "src/root")
            ]
        )
        """
    }
}
