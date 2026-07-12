import Foundation

extension URL {
    var subPaths: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }

    static func pwd() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func recreate() throws {
        try? FileManager.default.removeItem(at: self)
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
    }

    func mkdir() throws {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
    }

    func symlink(to target: URL) throws {
        try? FileManager.default.removeItem(at: self)
        try FileManager.default.createSymbolicLink(at: self, withDestinationURL: target)
    }

    func touch() throws {
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

extension String {
    var c99extidentifier: String {
        self.replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }
}
