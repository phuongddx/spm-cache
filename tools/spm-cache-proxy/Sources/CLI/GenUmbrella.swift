import Foundation
import ArgumentParser

struct GenUmbrella: AsyncParsableCommand, CommandRunning {
    static let configuration = CommandConfiguration(
        commandName: "gen-umbrella",
        abstract: "Generate umbrella Package.swift from lockfile"
    )

    @Option(help: "Path to spm-cache.lock file")
    var lockfile: String

    @Option(help: "Output directory for umbrella package")
    var output: String

    func run() async throws {
        let lockfilePath = URL(fileURLWithPath: lockfile)
        let outputDir = URL(fileURLWithPath: output)

        guard FileManager.default.fileExists(atPath: lockfilePath.path) else {
            Logger.error("Lockfile not found: \(lockfilePath.path)")
            throw ExitCode.failure
        }

        let lockfiles = Lockfile.load(from: lockfilePath.path)
        var allPackages: [Lockfile.PackageRef] = []
        var allPlatforms: [String: String] = [:]

        for (_, lf) in lockfiles {
            allPackages.append(contentsOf: lf.packages)
            allPlatforms.merge(lf.platforms) { _, new in new }
        }

        let combinedLockfile = Lockfile(
            packages: allPackages,
            dependencies: [:],
            platforms: allPlatforms
        )

        let generator = UmbrellaGenerator(lockfile: combinedLockfile, outputDir: outputDir)
        try generator.generate()
    }
}
