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
    // Single source of the companion binary version. Bump in lockstep with
    // the repo VERSION file at release — `spm-cache doctor` displays the
    // companion version (drift made visible) but never compares or gates on it.
    static let proxyVersion = "0.4.0"

    static let configuration = CommandConfiguration(
        commandName: "spm-cache-proxy",
        abstract: "Proxy package generator for spm-cache",
        version: proxyVersion,
        subcommands: [GenUmbrella.self, GenProxy.self, Resolve.self]
    )
}
