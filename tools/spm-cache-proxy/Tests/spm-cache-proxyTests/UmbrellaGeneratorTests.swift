import Foundation
import Testing
@testable import spm_cache_proxy

@Suite("UmbrellaGenerator platform mapping")
struct UmbrellaGeneratorTests {
    func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try dir.mkdir()
        return dir
    }

    func generateManifest(platforms: [String: String]) throws -> String {
        let dir = try makeTempDir()
        let lockfile = Lockfile(packages: [], dependencies: [:], platforms: platforms)
        let generator = UmbrellaGenerator(lockfile: lockfile, outputDir: dir)
        try generator.generate()
        return try String(contentsOf: dir.appendingPathComponent("Package.swift"), encoding: .utf8)
    }

    @Test("watchOS 11.6 maps to .v11, not the invalid .v13 that broke manifest compilation")
    func watchOSClampsToValidMember() throws {
        let manifest = try generateManifest(platforms: ["ios": "18.6", "watchos": "11.6"])
        #expect(manifest.contains(".watchOS(.v11)"))
        #expect(!manifest.contains(".v13"))
    }

    @Test("iOS 18.6 maps to .v18")
    func iOSMapsToV18() throws {
        let manifest = try generateManifest(platforms: ["ios": "18.6"])
        #expect(manifest.contains(".iOS(.v18)"))
    }

    @Test("a not-yet-released iOS version (26.1) clamps down to the highest valid member")
    func futureIOSClampsDown() throws {
        let manifest = try generateManifest(platforms: ["ios": "26.1"])
        #expect(manifest.contains(".iOS(.v18)"))
        #expect(!manifest.contains(".iOS(.v26)"))
    }

    @Test("macOS is always emitted for swift-build compatibility")
    func macOSAlwaysPresent() throws {
        let manifest = try generateManifest(platforms: ["ios": "18.6", "watchos": "11.6"])
        #expect(manifest.contains(".macOS(."))
    }
}
