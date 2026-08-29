import Foundation
import Testing
@testable import spm_cache_proxy

// CACHE-02: BinariesCache.hit(module:identity:currentPin:) is provenance-aware
// -- a cache hit now requires the sidecar's recorded pin for a package's
// identity to agree with the host's current pin, and a totally-absent or
// corrupt sidecar is an unambiguous miss (fail-safe). Real temp-dir
// fixtures, no protocol/mock layer -- mirrors ProxyGeneratorTests.swift's
// existing shape.
@Suite("BinariesCache.hit provenance-aware decision")
struct BinariesCacheHitTests {
    func makeCacheDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try dir.mkdir()
        return dir
    }

    func writeSidecar(_ json: Any, module: String, in dir: URL) throws {
        let path = dir.appendingPathComponent("\(module).xcframework.provenance.json")
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: path)
    }

    @Test("xcframework directory absent entirely -> miss regardless of any sidecar content")
    func absentXCFrameworkIsMiss() throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeSidecar(["pins": ["SomePkg": "aaa111"]], module: "SomePkg", in: dir)

        let cache = BinariesCache(dir: dir)
        let result = cache.hit(module: "SomePkg", identity: "SomePkg", currentPin: "aaa111")
        #expect(result == nil)
    }

    @Test("xcframework present, no sidecar file at all -> miss (D-01/SC1 upgrade scenario)")
    func noSidecarIsMiss() throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try dir.appendingPathComponent("SomePkg.xcframework").mkdir()

        let cache = BinariesCache(dir: dir)
        let result = cache.hit(module: "SomePkg", identity: "SomePkg", currentPin: "aaa111")
        #expect(result == nil)
    }

    @Test("xcframework present, sidecar is unparsable/malformed JSON -> miss (fail-safe)")
    func malformedJSONIsMiss() throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try dir.appendingPathComponent("SomePkg.xcframework").mkdir()
        let sidecar = dir.appendingPathComponent("SomePkg.xcframework.provenance.json")
        try "{ this is not valid json".data(using: .utf8)!.write(to: sidecar)

        let cache = BinariesCache(dir: dir)
        let result = cache.hit(module: "SomePkg", identity: "SomePkg", currentPin: "aaa111")
        #expect(result == nil)
    }

    @Test("xcframework present, sidecar root is a JSON array, not a Hash -> miss (V5 fail-safe)")
    func nonHashRootIsMiss() throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try dir.appendingPathComponent("SomePkg.xcframework").mkdir()
        try writeSidecar(["not", "a", "hash"], module: "SomePkg", in: dir)

        let cache = BinariesCache(dir: dir)
        let result = cache.hit(module: "SomePkg", identity: "SomePkg", currentPin: "aaa111")
        #expect(result == nil)
    }

    @Test("xcframework present, sidecar is a valid Hash but has no pins key at all -> miss")
    func missingPinsKeyIsMiss() throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try dir.appendingPathComponent("SomePkg.xcframework").mkdir()
        try writeSidecar(["fidelity_status": "host-pinned"], module: "SomePkg", in: dir)

        let cache = BinariesCache(dir: dir)
        let result = cache.hit(module: "SomePkg", identity: "SomePkg", currentPin: "aaa111")
        #expect(result == nil)
    }

    @Test("xcframework present, sidecar has pins: {} (empty, not-graph-pinned steady state) -> hit regardless of currentPin")
    func emptyPinsIsHit() throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try dir.appendingPathComponent("SomePkg.xcframework").mkdir()
        try writeSidecar(["pins": [String: String](), "fidelity_status": "not-graph-pinned"], module: "SomePkg", in: dir)

        let cache = BinariesCache(dir: dir)
        let result = cache.hit(module: "SomePkg", identity: "SomePkg", currentPin: "anything-at-all")
        #expect(result != nil)
    }

    @Test("xcframework present, sidecar's pins entry for this identity disagrees with currentPin -> miss (D-02)")
    func disagreeingPinIsMiss() throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try dir.appendingPathComponent("SomePkg.xcframework").mkdir()
        try writeSidecar(["pins": ["SomePkg": "aaa111"]], module: "SomePkg", in: dir)

        let cache = BinariesCache(dir: dir)
        let result = cache.hit(module: "SomePkg", identity: "SomePkg", currentPin: "bbb222")
        #expect(result == nil)
    }

    @Test("xcframework present, sidecar's pins entry for this identity agrees with currentPin -> hit")
    func agreeingPinIsHit() throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try dir.appendingPathComponent("SomePkg.xcframework").mkdir()
        try writeSidecar(["pins": ["SomePkg": "aaa111"]], module: "SomePkg", in: dir)

        let cache = BinariesCache(dir: dir)
        let result = cache.hit(module: "SomePkg", identity: "SomePkg", currentPin: "aaa111")
        #expect(result != nil)
    }

    @Test("xcframework present, sidecar's pins is non-empty but does not contain this identity -> hit (intersection-only, absence is not drift)")
    func absentIdentityInNonEmptyPinsIsHit() throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try dir.appendingPathComponent("SomePkg.xcframework").mkdir()
        try writeSidecar(["pins": ["OtherPkg": "ccc333"]], module: "SomePkg", in: dir)

        let cache = BinariesCache(dir: dir)
        let result = cache.hit(module: "SomePkg", identity: "SomePkg", currentPin: "aaa111")
        #expect(result != nil)
    }
}
