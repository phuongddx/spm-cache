import Foundation
import ArgumentParser

struct Resolve: AsyncParsableCommand, CommandRunning {
    static let configuration = CommandConfiguration(
        commandName: "resolve",
        abstract: "Resolve package graph and generate metadata"
    )

    @Option(help: "Package directory")
    var package: String

    @Option(help: "Output metadata directory")
    var output: String

    func run() async throws {
        let pkgDir = URL(fileURLWithPath: package)
        let metadataDir = URL(fileURLWithPath: output)

        let resolver = Resolver(pkgDir: pkgDir, metadataDir: metadataDir)
        try resolver.resolve()

        Logger.info("Resolve complete at \(metadataDir.path)")
    }
}
