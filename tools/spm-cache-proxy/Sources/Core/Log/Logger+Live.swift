import Foundation
import Rainbow

struct LiveLog: Sendable {
    static func section(_ title: String) {
        print("\n" + String(repeating: "=", count: 60))
        print(title.bold)
        print(String(repeating: "=", count: 60))
    }

    static func output(_ line: String) {
        print(line)
    }

    static func finish() {}
}
