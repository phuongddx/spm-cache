import Foundation

struct RootProxyPackage: ProxyPackageProtocol {
    let packages: [Lockfile.PackageRef]

    var reachableProducts: [String] {
        packages.map { $0.name ?? $0.slug }
    }

    func recursiveDependencies() -> [String] {
        []
    }

    func generate(in outputDir: URL, proxiesDir: URL) throws {
        var deps: [String] = []
        var products: [String] = []
        var targets: [String] = []

        for pkg in packages {
            let slug = pkg.slug.c99extidentifier
            let name = pkg.name ?? slug

            deps.append(".package(path: \".proxies/\(slug)\")")
            products.append(".library(name: \"\(name)\", targets: [\"\(name)_proxy\"])")
            targets.append(".target(name: \"\(name)_proxy\", dependencies: .product(name: \"\(name)\", package: \"\(slug)\"), path: \"src/\(slug)\")")
        }

        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "spm_cache_proxy",
            dependencies: [
                \(deps.joined(separator: ",\n        "))
            ],
            products: [
                \(products.joined(separator: ",\n        "))
            ],
            targets: [
                \(targets.joined(separator: ",\n        "))
            ]
        )
        """

        try content.write(
            to: outputDir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let headersDir = outputDir.appendingPathComponent(".headers")
        try headersDir.mkdir()
    }
}
