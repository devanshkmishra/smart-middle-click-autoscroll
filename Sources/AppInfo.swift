import Foundation

enum AppInfo {
    static let name = "Smart Middle Click Autoscroll"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}
