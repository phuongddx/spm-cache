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

    /// Companion "shim" xcframeworks a cached module needs to resolve a
    /// private (non-product) Clang-target import in its `.swiftinterface`
    /// -- see the Ruby build pipeline's `find_private_clang_shims` for the
    /// full root-cause story (e.g. swift-numerics' RealModule needs
    /// `_NumericsShims`). Read from the `<module>.xcframework.shims.json`
    /// sidecar the Ruby build pipeline writes alongside the main artifact;
    /// empty for the common case of no such sidecar.
    func shims(for module: String) -> [String] {
        let sidecar = dir.appendingPathComponent("\(module).xcframework.shims.json")
        guard let data = try? Data(contentsOf: sidecar),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return names
    }

    func shimXCFramework(named shim: String) -> URL? {
        let xcframework = dir.appendingPathComponent("\(shim).xcframework")
        return FileManager.default.fileExists(atPath: xcframework.path) ? xcframework : nil
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
