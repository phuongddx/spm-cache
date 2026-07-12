import Foundation

struct Lockfile: Codable {
    struct PackageRef: Codable {
        let repositoryURL: String?
        let pathFromRoot: String?
        let name: String?
        let productName: String?
        let version: String?

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

        var versionRequirement: String {
            guard let version = version, !version.isEmpty else {
                return "from: \"0.1.0\""
            }
            let parts = version.split(separator: ".").map(String.init)
            let major = Int(parts[0]) ?? 1
            if major >= 1 {
                return "from: \"\(version)\""
            } else {
                return "from: \"\(version)\""
            }
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
    init(from dict: [String: Any]) {
        let pkgList = (dict["packages"] as? [[String: Any]]) ?? []
        self.packages = pkgList.compactMap { pkgDict in
            guard let name = pkgDict["name"] as? String else { return nil }
            return PackageRef(
                repositoryURL: pkgDict["repositoryURL"] as? String,
                pathFromRoot: pkgDict["path_from_root"] as? String,
                name: name,
                productName: pkgDict["product_name"] as? String,
                version: pkgDict["version"] as? String
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
