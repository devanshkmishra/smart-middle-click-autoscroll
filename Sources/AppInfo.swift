import Foundation

enum AppInfo {
    static let name = "Smart Middle Click Autoscroll"
    static let showSettingsNotification = Notification.Name("io.github.devanshkmishra.smartmiddleclickautoscroll.showSettings")
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}
