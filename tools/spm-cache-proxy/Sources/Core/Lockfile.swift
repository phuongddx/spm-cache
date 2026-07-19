import Foundation

struct Lockfile: Codable {
    /// A single product entry from `swift package describe`, as enriched into
    /// `spm-cache.lock` by `Installer#enrich_lockfile_products`.
    struct ProductRef: Codable {
        let name: String
        let type: String
        let targets: [String]
    }

    /// A resolved library product ready to be proxied: real product `name`
    /// plus the module names (`targets`) a shim must `@_exported import`.
    /// Falls back to a single synthetic entry (name == module == legacy
    /// resolved name) when no `products` metadata is present.
    struct ResolvedProduct {
        let name: String
        let targets: [String]
    }

    struct PackageRef: Codable {
        let repositoryURL: String?
        let pathFromRoot: String?
        let name: String?
        let productName: String?
        let version: String?
        let revision: String?
        let products: [ProductRef]?

        init(
            repositoryURL: String?,
            pathFromRoot: String?,
            name: String?,
            productName: String?,
            version: String?,
            revision: String?,
            products: [ProductRef]? = nil
        ) {
            self.repositoryURL = repositoryURL
            self.pathFromRoot = pathFromRoot
            self.name = name
            self.productName = productName
            self.version = version
            self.revision = revision
            self.products = products
        }

        var isLocal: Bool {
            pathFromRoot != nil
        }

        var slug: String {
            if let url = repositoryURL {
                return (url as NSString).deletingPathExtension.components(separatedBy: "/").last ?? url
            }
            if let name = name { return name }
            if let path = pathFromRoot {
                return (path as NSString).lastPathComponent
            }
            return "unknown"
        }

        var resolvedProductName: String {
            productName ?? name ?? slug
        }

        /// Library products to proxy, sourced from `products[]` metadata when
        /// present; legacy lockfiles (no `products`) fall back to a single
        /// synthetic product derived from `resolvedProductName`.
        var libraryProducts: [ResolvedProduct] {
            if let products = products {
                return products
                    .filter { $0.type == "library" }
                    .map { ResolvedProduct(name: $0.name, targets: $0.targets.isEmpty ? [$0.name] : $0.targets) }
            }
            return [ResolvedProduct(name: resolvedProductName, targets: [resolvedProductName])]
        }

        /// True when `products` metadata exists and contains no `library`
        /// product — e.g. a build-tool plugin package (SwiftGenPlugin-like).
        /// Legacy entries with no `products` metadata are never plugin-only
        /// (status quo: treated as library packages so a package is never
        /// silently dropped on missing data).
        var isPluginOnly: Bool {
            guard let products = products, !products.isEmpty else { return false }
            return !products.contains { $0.type == "library" }
        }

        /// True when this package's real products are known (`products[]`
        /// enriched) and none of them appear in `consumedProducts` -- i.e.
        /// it's provably only a transitive dependency of another package
        /// already in the graph (e.g. realm-core, pulled in solely via
        /// realm-swift), never linked directly by the host project. False
        /// (safe default: treat as directly consumed) when there's no
        /// consumption data to check against, or `products[]` isn't
        /// enriched yet.
        func isTransitiveOnly(consumedProducts: Set<String>) -> Bool {
            guard !consumedProducts.isEmpty, let products = products, !products.isEmpty else { return false }
            let ownProductNames = Set(products.map { $0.name })
            return ownProductNames.isDisjoint(with: consumedProducts)
        }

        /// The exact commit (`revision:`) wins over `from: version` whenever
        /// both are recorded. `from:` is an open-ended lower bound ("this or
        /// anything newer below the next major"), so the umbrella's isolated
        /// `swift package resolve` was free to float to the newest compatible
        /// release instead of the commit the host project actually resolved
        /// -- and product enrichment then read the DRIFTED checkout's
        /// manifest as ground truth. Field bug: swift-collections pinned at
        /// 1.1.2 in Package.resolved floated to 1.6.0 in the umbrella,
        /// enrichment wrote 1.6.0-only products (TrailingElementsModule)
        /// into the lockfile, and the real Xcode graph -- whose other
        /// constraints unify back to 1.1.2 -- failed whole-graph resolution
        /// with "product 'TrailingElementsModule' ... not found". A
        /// `revision:` pin has no range to float within, so every resolve
        /// reproduces exactly what the host project's Package.resolved
        /// settled on.
        var versionRequirement: String {
            if let revision = revision, !revision.isEmpty {
                return "revision: \"\(revision)\""
            }
            if let version = version, !version.isEmpty {
                return "from: \"\(version)\""
            }
            return "from: \"0.1.0\""
        }
    }

    struct TargetDeps: Codable {
        let target: String
        let products: [String]
    }

    let packages: [PackageRef]
    let dependencies: [String: [String]]
    let platforms: [String: String]

    init(packages: [PackageRef], dependencies: [String: [String]], platforms: [String: String]) {
        self.packages = packages
        self.dependencies = dependencies
        self.platforms = platforms
    }
    private static func parseProducts(_ pkgDict: [String: Any]) -> [ProductRef]? {
        guard let productDicts = pkgDict["products"] as? [[String: Any]] else { return nil }
        var result: [ProductRef] = []
        for prodDict in productDicts {
            guard let prodName = prodDict["name"] as? String, let type = prodDict["type"] as? String else { continue }
            result.append(ProductRef(name: prodName, type: type, targets: (prodDict["targets"] as? [String]) ?? []))
        }
        return result
    }

    init(from dict: [String: Any]) {
        let pkgList = (dict["packages"] as? [[String: Any]]) ?? []
        self.packages = pkgList.compactMap { (pkgDict: [String: Any]) -> PackageRef? in
            guard let name = pkgDict["name"] as? String else { return nil }
            return PackageRef(
                repositoryURL: pkgDict["repositoryURL"] as? String,
                pathFromRoot: pkgDict["path_from_root"] as? String,
                name: name,
                productName: pkgDict["product_name"] as? String,
                version: pkgDict["version"] as? String,
                revision: pkgDict["revision"] as? String,
                products: Lockfile.parseProducts(pkgDict)
            )
        }
        self.dependencies = (dict["dependencies"] as? [String: [String]]) ?? [:]
        self.platforms = (dict["platforms"] as? [String: String]) ?? [:]
    }

    static func load(from path: String) -> [String: Lockfile] {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            return [:]
        }
        return json.mapValues { Lockfile(from: $0) }
    }
}
