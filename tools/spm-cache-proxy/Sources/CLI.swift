import Foundation
import ArgumentParser
import Rainbow

protocol CommandRunning {
    var projectRootDir: URL { get }
    var defaultSandboxDir: URL { get }
}

extension CommandRunning {
    var projectRootDir: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    var defaultSandboxDir: URL {
        projectRootDir.appendingPathComponent("spm-cache")
    }
}

@main
struct CLI: AsyncParsableCommand, CommandRunning {
    static let configuration = CommandConfiguration(
        commandName: "spm-cache-proxy",
        abstract: "Proxy package generator for spm-cache",
        subcommands: [GenUmbrella.self, GenProxy.self, Resolve.self]
    )
}
