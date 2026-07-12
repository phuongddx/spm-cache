import Foundation

struct Env {
    static var isRunningInsideXcode: Bool {
        ProcessInfo.processInfo.environment["XCODE_VERSION_ACTUAL"] != nil
    }

    static var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }
}
