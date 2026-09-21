import FixtureKit
import Logging
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private let logger = Logger(label: "com.nextlabs.fixtureapp")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        logger.info(FixtureKit.greeting().message)
        return true
    }
}
