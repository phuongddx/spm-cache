import Foundation
import Logging

public struct FixtureGreeting {
    public let message: String

    public init(message: String = "FixtureKit is ready") {
        self.message = message
    }
}

public enum FixtureKit {
    public static let logger = Logger(label: "com.nextlabs.fixturekit")

    public static func greeting() -> FixtureGreeting {
        logger.info("Generating fixture greeting")
        return FixtureGreeting()
    }
}
