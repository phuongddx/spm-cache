import Foundation

struct ProxyPackage: ProxyPackageProtocol {
    let pkg: Lockfile.PackageRef
    let cache: BinariesCache

    var reachableProducts: [String] {
        [pkg.name ?? pkg.slug]
    }

    func recursiveDependencies() -> [String] {
        []
    }

    func generate(in proxiesDir: URL) throws {
        let slug = pkg.slug.c99extidentifier
        let proxyDir = proxiesDir.appendingPathComponent(slug)
        try proxyDir.mkdir()

        let manifest = generateManifest()
        try manifest.write(
            to: proxyDir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        if cache.hit(module: pkg.name ?? slug) == nil {
            let srcDir = proxyDir.appendingPathComponent("src")
            try srcDir.mkdir()
            try "".write(to: srcDir.appendingPathComponent("dummy.swift"), atomically: true, encoding: .utf8)
        }
    }

    private func generateManifest() -> String {
        let slug = pkg.slug.c99extidentifier
        let name = pkg.name ?? slug

        if cache.hit(module: name) != nil {
            return """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(
                name: "\(slug)_proxy",
                products: [.library(name: "\(name)", targets: ["\(slug).binary"])],
                targets: [.binaryTarget(name: "\(slug).binary", path: "../.build/artifacts/\(name).xcframework")]
            )
            """
        } else {
            return """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(
                name: "\(slug)_proxy",
                products: [.library(name: "\(name)", targets: ["\(slug).source"])],
                targets: [.target(name: "\(slug).source", path: "src")]
            )
            """
        }
    }
}
