import Foundation

protocol ProxyPackageProtocol {
    var reachableProducts: [String] { get }
    func recursiveDependencies() -> [String]
    func buildSettings() -> [String: String]
    func macroBuildSettings() -> [String: String]
    func headerSearchPathSettings() -> [String: String]
}

extension ProxyPackageProtocol {
    func buildSettings() -> [String: String] {
        ["DEFINES_MODULE": "YES"]
    }

    func macroBuildSettings() -> [String: String] {
        [:]
    }

    func headerSearchPathSettings() -> [String: String] {
        [:]
    }
}
