import Foundation

/// Shell, session and background system services are never quit from previews.
enum AppQuitPolicy {
    static func allows(bundleID: String?, ownBundleID: String?) -> Bool {
        guard let bundleID, bundleID != ownBundleID else { return false }
        let protected: Set<String> = [
            "com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
            "com.apple.SystemUIServer", "com.apple.controlcenter", "com.apple.WindowManager",
            "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.SecurityAgent",
            "com.apple.systempreferences", "com.apple.ScreenSaver.Engine"
        ]
        return !protected.contains(bundleID)
    }
}
