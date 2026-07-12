import Foundation
import Rainbow

struct Logger {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    static func debug(_ message: String) {
        print("[\(Level.debug.rawValue)] \(message)".lightBlack)
    }

    static func info(_ message: String) {
        print("[\(Level.info.rawValue)] \(message)".green)
    }

    static func warning(_ message: String) {
        print("[\(Level.warning.rawValue)] \(message)".yellow)
    }

    static func error(_ message: String) {
        fputs("[\(Level.error.rawValue)] \(message)\n".red, stderr)
    }
}
