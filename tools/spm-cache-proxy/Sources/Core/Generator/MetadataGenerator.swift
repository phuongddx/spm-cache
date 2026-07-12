import Foundation

struct MetadataGenerator {
    let metadataDir: URL

    init(metadataDir: URL) {
        self.metadataDir = metadataDir
    }

    func generate(for package: String, targets: [String], platforms: [String: String]) throws {
        try metadataDir.mkdir()
        let metadata: [String: Any] = [
            "package": package,
            "targets": targets,
            "platforms": platforms,
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        let path = metadataDir.appendingPathComponent("\(package).json")
        try data.write(to: path)
        Logger.info("Generated metadata for \(package) at \(path.path)")
    }
}
