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
            let slug = pkg.slug.c99extidentifier
            let proxyDir = proxiesDir.appendingPathComponent(slug)
            try proxyDir.mkdir()

            let cachedBinary = cache.hit(module: pkg.name ?? slug)
            let status: GraphEntry.Status = cachedBinary != nil ? .hit : .missed

            let packageSwift = generateProxyManifest(pkg: pkg, cacheHit: cachedBinary, artifactsDir: artifactsDir)
            let packageSwiftPath = proxyDir.appendingPathComponent("Package.swift")
            try packageSwift.write(to: packageSwiftPath, atomically: true, encoding: .utf8)

            if let binary = cachedBinary {
                let dest = artifactsDir.appendingPathComponent(binary.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.createSymbolicLink(
                    at: dest,
                    withDestinationURL: binary
                )
            }

            entries.append(GraphEntry(
                module: pkg.name ?? slug,
                status: status,
                dependencies: [],
                hasMacro: false
            ))
        }

        let rootProxy = generateRootProxy(packages: packages)
        let rootProxyPath = outputDir.appendingPathComponent("Package.swift")
        try rootProxy.write(to: rootProxyPath, atomically: true, encoding: .utf8)

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

    private func generateProxyManifest(pkg: Lockfile.PackageRef, cacheHit: URL?, artifactsDir: URL) -> String {
        let slug = pkg.slug.c99extidentifier
        let name = pkg.name ?? slug

        if let binary = cacheHit {
            let relativePath = ".build/artifacts/\(binary.lastPathComponent)"
            return """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(
                name: "\(slug)_proxy",
                products: [
                    .library(name: "\(name)", targets: ["\(slug).binary"]),
                ],
                targets: [
                    .binaryTarget(name: "\(slug).binary", path: "\(relativePath)"),
                ]
            )
            """
        } else
        {
            return """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(
                name: "\(slug)_proxy",
                products: [
                    .library(name: "\(name)", targets: ["\(slug).source"]),
                ],
                targets: [
                    .target(name: "\(slug).source"),
                ]
            )
            """
        }
    }

    private func generateRootProxy(packages: [Lockfile.PackageRef]) -> String {
        var deps: [String] = []
        var products: [String] = []

        for pkg in packages {
            let slug = pkg.slug.c99extidentifier
            deps.append(".package(path: \".proxies/\(slug)\")")
            products.append(".library(name: \"\(pkg.name ?? slug)\", targets: [\"\(pkg.name ?? slug)\"])")
        }

        return """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "spm_cache_proxy",
            dependencies: [
                \(deps.joined(separator: ",\n        "))
            ],
            products: [
                \(products.joined(separator: ",\n        "))
            ]
        )
        """
    }
}
