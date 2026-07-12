import Foundation

struct Resolver {
    let pkgDir: URL
    let metadataDir: URL

    init(pkgDir: URL, metadataDir: URL) {
        self.pkgDir = pkgDir
        self.metadataDir = metadataDir
    }

    func resolve() throws {
        try metadataDir.mkdir()
        Logger.info("Resolving package graph for \(pkgDir.lastPathComponent)...")
    }
}
