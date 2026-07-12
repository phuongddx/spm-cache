import Foundation

struct BinariesCache {
    let dir: URL

    init(dir: URL) {
        self.dir = dir
    }

    func update(modules: [String], artifacts: [URL]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for artifact in artifacts {
            let dest = dir.appendingPathComponent(artifact.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: artifact, to: dest)
        }
    }

    func hit(module: String) -> URL? {
        let xcframework = dir.appendingPathComponent("\(module).xcframework")
        return FileManager.default.fileExists(atPath: xcframework.path) ? xcframework : nil
    }

    func binaryPath(for module: String) -> URL? {
        let macro = dir.appendingPathComponent("\(module).macro")
        return FileManager.default.fileExists(atPath: macro.path) ? macro : nil
    }

    func cachedModules() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        return entries.compactMap { entry in
            if entry.hasSuffix(".xcframework") {
                return String(entry.dropLast(".xcframework".count))
            }
            return nil
        }
    }
}
