import Foundation

public enum AssociationMatcher {
    public static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    public static func match(name: String, ids: Set<String>, aliases: Set<String>) -> Association? {
        let lower = name.lowercased()
        for id in ids {
            let id = id.lowercased()
            if lower == id || [".plist", ".savedstate", ".binarycookies"].contains(where: { lower == id + $0 }) { return .exact }
            // A namespace boundary is required: com.acme.AppOther must not match App.
            if lower.hasPrefix(id + ".") || lower.hasPrefix(id + "-") || lower.hasPrefix(id + "_") { return .related }
        }
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let candidates = [normalized(name), normalized(stem)]
        let ignored: Set<String> = ["app", "application", "helper", "electron", "launcher", "updater", "update", "crashpad"]
        for alias in aliases {
            let key = normalized(alias)
            guard key.count >= 3, !ignored.contains(key) else { continue }
            if candidates.contains(key) { return .name }
            if lower.hasPrefix(alias.lowercased() + "_") || lower.hasPrefix(alias.lowercased() + "-") { return .name }
        }
        return nil
    }
}

public enum SystemAssociationKind: String, Codable, Sendable { case privacy = "隐私权限", login = "登录与后台项", receipt = "安装收据", systemExtension = "系统扩展" }
public enum SystemAssociationAction: String, Codable, Sendable { case resetPermissions, loginSettings, privacySettings, vendorUninstaller }
public struct SystemAssociation: Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: SystemAssociationKind
    public let action: SystemAssociationAction
    public let bundleID: String?
    public let confirmed: Bool
    public var selectable: Bool { action == .resetPermissions }
}
