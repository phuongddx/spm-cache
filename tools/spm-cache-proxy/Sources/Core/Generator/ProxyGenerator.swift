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
            case hit, missed, ignored, excluded
        }
        let module: String
        let status: Status
        let dependencies: [String]
        let hasMacro: Bool
    }

    /// Returns true when any glob pattern matches the package's resolved
    /// product name OR its lockfile identity (`name`). Mirrors the Ruby
    /// `File.fnmatch` default semantics via POSIX `fnmatch`.
    private func matchesAnyPattern(_ pkg: Lockfile.PackageRef, _ patterns: [String]) -> Bool {
        let candidates = [pkg.resolvedProductName, pkg.name].compactMap { $0 }
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

    func generate(for packages: [Lockfile.PackageRef]) throws -> [GraphEntry] {
        try outputDir.recreate()
        let proxiesDir = outputDir.appendingPathComponent(".proxies")
        try proxiesDir.mkdir()
        let artifactsDir = outputDir.appendingPathComponent(".build").appendingPathComponent("artifacts")
        try artifactsDir.mkdir()

        var entries: [GraphEntry] = []

        for pkg in packages {
            let slug = pkg.slug
            let productName = pkg.resolvedProductName
            let proxyDir = proxiesDir.appendingPathComponent(slug)
            try proxyDir.mkdir()

            let ignored = isIgnored(pkg)
            let excluded = isCacheOnlyExcluded(pkg)
            // Ignored/excluded packages are always source, even when a cached binary exists.
            let cachedBinary = (ignored || excluded) ? nil : cache.hit(module: productName)
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

            let packageSwift = generateProxyManifest(pkg: pkg, productName: productName, status: status, cacheHit: cachedBinary, artifactsDir: artifactsDir)
            let packageSwiftPath = proxyDir.appendingPathComponent("Package.swift")
            try packageSwift.write(to: packageSwiftPath, atomically: true, encoding: .utf8)

            if let binary = cachedBinary {
                let dest = artifactsDir.appendingPathComponent(binary.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.createSymbolicLink(
                    at: dest,
                    withDestinationURL: binary
                )
            } else {
                // Source fallback (miss or ignored): emit a shim that re-exports
                // the real package source so `import <module>` resolves.
                let sourcesDir = proxyDir.appendingPathComponent("Sources").appendingPathComponent("\(slug)_shim")
                try sourcesDir.mkdir()
                let shim = generateShimSource(pkg: pkg, productName: productName)
                try shim.write(to: sourcesDir.appendingPathComponent("\(slug)_shim.swift"), atomically: true, encoding: .utf8)
            }

            entries.append(GraphEntry(
                module: productName,
                status: status,
                dependencies: [],
                hasMacro: false
            ))
        }

        let rootProxy = generateRootProxy(packages: packages)
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

    private func generateProxyManifest(pkg: Lockfile.PackageRef, productName: String, status: GraphEntry.Status, cacheHit: URL?, artifactsDir: URL) -> String {
        let slug = pkg.slug

        if status == .hit, cacheHit != nil {
            let relativePath = "../../.build/artifacts/\(productName).xcframework"
            return """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "\(slug)_proxy",
                products: [
                    .library(name: "\(productName)", targets: ["\(slug)_binary"]),
                ],
                targets: [
                    .binaryTarget(name: "\(slug)_binary", path: "\(relativePath)"),
                ]
            )
            """
        } else {
            // Miss or ignored: re-export the real package source via a shim target.
            let (depLine, targetDep) = sourceDependencyLines(pkg: pkg, productName: productName)
            return """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "\(slug)_proxy",
                products: [
                    .library(name: "\(productName)", targets: ["\(slug)_shim"]),
                ],
                dependencies: [
                    \(depLine)
                ],
                targets: [
                    .target(name: "\(slug)_shim", dependencies: [
                        \(targetDep)
                    ], path: "Sources/\(slug)_shim")
                ]
            )
            """
        }
    }

    /// Emits the `.package(...)` dependency line and the `.product(...)` target
    /// dependency line for source fallback (miss/ignored). Remote packages use
    /// `url:from:`; local packages use `path:` resolved relative to the proxy dir.
    private func sourceDependencyLines(pkg: Lockfile.PackageRef, productName: String) -> (dep: String, targetDep: String) {
        let packageIdentity = pkg.slug
        if pkg.isLocal, let path = pkg.pathFromRoot {
            // Proxy Package.swift lives at .proxies/<slug>/Package.swift; the
            // project root is two levels up.
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

    /// Shim source that re-exports the real module so app-level
    /// `import <productName>` resolves to source compilation.
    private func generateShimSource(pkg: Lockfile.PackageRef, productName: String) -> String {
        let moduleName = pkg.resolvedProductName
        return """
        // Auto-generated by spm-cache-proxy: re-exports the source package module.
        @_exported import \(moduleName)
        """
    }

    private func generateRootProxy(packages: [Lockfile.PackageRef]) -> String {
        var deps: [String] = []
        var targetDeps: [String] = []

        for pkg in packages {
            let slug = pkg.slug
            let productName = pkg.resolvedProductName
            deps.append(".package(path: \".proxies/\(slug)\")")
            targetDeps.append(".product(name: \"\(productName)\", package: \"\(slug)\")")
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
