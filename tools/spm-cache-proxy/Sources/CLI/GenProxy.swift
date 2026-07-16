import Foundation
import ArgumentParser

struct GenProxy: AsyncParsableCommand, CommandRunning {
    static let configuration = CommandConfiguration(
        commandName: "gen-proxy",
        abstract: "Generate proxy packages from umbrella"
    )

    @Option(help: "Path to umbrella directory")
    var umbrella: String

    @Option(help: "Output directory for proxy packages")
    var output: String

    @Option(help: "Cache directory for xcframeworks")
    var cache: String

    @Option(help: "Path to spm-cache.lock file")
    var lockfile: String

    @Option(help: "Comma-separated glob patterns of modules to exclude from caching")
    var ignore: String?

    @Option(help: "Comma-separated glob patterns of the ONLY modules to cache; all others excluded")
    var cacheOnly: String?

    func run() async throws {
        let umbrellaDir = URL(fileURLWithPath: umbrella)
        let outputDir = URL(fileURLWithPath: output)
        let cacheDir = URL(fileURLWithPath: cache)

        let lockfiles = Lockfile.load(from: lockfile)

        var allPackages: [Lockfile.PackageRef] = []
        for (_, lf) in lockfiles {
            allPackages.append(contentsOf: lf.packages)
        }

        let ignoredPatterns = ignore?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []

        let cacheOnlyPatterns = cacheOnly?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []

        let binCache = BinariesCache(dir: cacheDir)
        let generator = ProxyGenerator(cache: binCache, outputDir: outputDir, ignoredPatterns: ignoredPatterns, cacheOnlyPatterns: cacheOnlyPatterns)
        let entries = try generator.generate(for: allPackages)
        try generator.generateGraphJSON(entries: entries)

        Logger.info("Proxy generation complete at \(outputDir.path)")
    }
}
