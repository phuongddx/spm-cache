import Foundation

struct ProxyGenerator {
    let cache: BinariesCache
    let outputDir: URL

    init(cache: BinariesCache, outputDir: URL) {
        self.cache = cache
        self.outputDir = outputDir
    }

    struct GraphEntry: Codable {
        enum Status: String, Codable {
            case hit, missed, ignored
        }
        let module: String
        let status: Status
        let dependencies: [String]
        let hasMacro: Bool
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

            let cachedBinary = cache.hit(module: productName)
            let status: GraphEntry.Status = cachedBinary != nil ? .hit : .missed

            let packageSwift = generateProxyManifest(pkg: pkg, productName: productName, cacheHit: cachedBinary, artifactsDir: artifactsDir)
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
                // Create stub source for cache misses
                let sourcesDir = proxyDir.appendingPathComponent("Sources").appendingPathComponent("\(slug)_source")
                try sourcesDir.mkdir()
                try "".write(to: sourcesDir.appendingPathComponent("\(slug)_source.swift"), atomically: true, encoding: .utf8)
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

    private func generateProxyManifest(pkg: Lockfile.PackageRef, productName: String, cacheHit: URL?, artifactsDir: URL) -> String {
        let slug = pkg.slug

        if cacheHit != nil {
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
            return """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "\(slug)_proxy",
                products: [
                    .library(name: "\(productName)", targets: ["\(slug)_source"]),
                ],
                targets: [
                    .target(name: "\(slug)_source"),
                ]
            )
            """
        }
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
