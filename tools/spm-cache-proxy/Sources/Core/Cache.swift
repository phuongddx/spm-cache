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

    /// Provenance-aware cache-hit decision (CACHE-02): a hit now requires the
    /// sidecar's recorded pin for `identity` to agree with `currentPin`, not
    /// just artifact presence on disk. A totally-absent or unparsable
    /// sidecar is an unconditional miss (fail-safe, matches `cache
    /// list`'s existing `fidelity_status_for` tolerant-fallback philosophy).
    /// Intersection-only: `identity` absent from `pins` (empty pins, or a
    /// non-empty hash that simply doesn't mention this identity -- the
    /// not-graph-pinned/Class E steady state) is NOT evidence of drift and
    /// still hits.
    func hit(module: String, identity: String, currentPin: String?) -> URL? {
        let xcframework = dir.appendingPathComponent("\(module).xcframework")
        guard FileManager.default.fileExists(atPath: xcframework.path) else { return nil }

        let sidecar = dir.appendingPathComponent("\(module).xcframework.provenance.json")
        guard let data = try? Data(contentsOf: sidecar),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let pins = parsed["pins"] as? [String: String] else { return nil }

        if let recorded = pins[identity] {
            // A recorded pin with no readable currentPin is inconclusive, not
            // "no evidence of drift" -- treat it the same as a disagreement
            // (fail-safe) rather than falling back to pre-CACHE-02,
            // fileExists-only semantics for exactly the lockfile entries
            // whose data is least trustworthy.
            guard let current = currentPin, recorded == current else { return nil }
        }
        return xcframework
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
