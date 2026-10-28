import Foundation
import Security

public struct AppScanner: Sendable {
    public let home: URL
    public let ownURL: URL?
    public let ownID: String?
    public let includeSystemLibrary: Bool

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                ownURL: URL? = Bundle.main.bundleURL, ownID: String? = Bundle.main.bundleIdentifier,
                includeSystemLibrary: Bool = true) {
        self.home = home.resolvingSymlinksInPath(); self.ownURL = ownURL; self.ownID = ownID
        self.includeSystemLibrary = includeSystemLibrary
    }

    public func identify(_ url: URL) throws -> AppIdentity {
        let url = PathPolicy.canonical(url)
        guard url.pathExtension.lowercased() == "app", !PathPolicy.hasSymlink(url),
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              validIdentifier(id) else { throw UninstallError.invalidApplication }
        guard !PathPolicy.isProtectedApplication(url: url, bundleID: id, ownURL: ownURL, ownID: ownID) else {
            throw UninstallError.protectedApplication
        }
        let snapshot = try FileIdentity.read(url)
        guard snapshot.kind == UInt16(S_IFDIR) else { throw UninstallError.invalidApplication }
        var ids: Set<String> = [id]
        var groups = signedGroups(url)
        // Only inspect explicitly nested component directories, never the full disk.
        for folder in ["Contents/PlugIns", "Contents/XPCServices", "Contents/Library/LoginItems"] {
            let root = url.appendingPathComponent(folder)
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children where ["app", "appex", "xpc"].contains(child.pathExtension) && !PathPolicy.hasSymlink(child) {
                if let childID = Bundle(url: child)?.bundleIdentifier, validIdentifier(childID) { ids.insert(childID) }
                groups.formUnion(signedGroups(child))
            }
        }
        return AppIdentity(url: url, name: url.deletingPathExtension().lastPathComponent,
                           bundleID: id, relatedIDs: ids, groups: groups, snapshot: snapshot)
    }

    private func validIdentifier(_ value: String) -> Bool {
        value.count > 3 && value.contains(".") && !value.contains("/") && !value.contains("..") &&
        value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0) }
    }

    private func signedGroups(_ url: URL) -> Set<String> {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return [] }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dict = information as? [String: Any],
              let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return [] }
        return Set((entitlements["com.apple.security.application-groups"] as? [String] ?? []).filter(validIdentifier))
    }

    public func scan(_ url: URL, progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> ScanReport {
        let fm = FileManager.default
        let app = try identify(url)
        var items: [ScanItem] = [], warnings: [String] = []
        let specs: [(String, FileCategory)] = [
            ("Caches", .cache), ("Preferences", .preferences), ("Preferences/ByHost", .preferences),
            ("Application Support", .support), ("Logs", .logs), ("Saved Application State", .state),
            ("HTTPStorages", .cache), ("WebKit", .cache), ("Containers", .container),
            ("Group Containers", .shared), ("LaunchAgents", .service)
        ]
        let library = home.appendingPathComponent("Library")
        let allowed = specs.filter { ![FileCategory.shared, .service].contains($0.1) }.map { library.appendingPathComponent($0.0) }

        func add(_ candidate: URL, category: FileCategory, association: Association, evidence: String,
                 removable: Bool, caution: String? = nil) throws {
            let candidate = PathPolicy.canonical(candidate)
            try Task.checkCancellation()
            guard !items.contains(where: { $0.url == candidate }) else { return }
            do {
                let identity = try FileIdentity.read(candidate)
                guard !identity.isSymbolicLink, !PathPolicy.hasSymlink(candidate) else {
                    warnings.append("跳过符号链接：\(candidate.path)"); return
                }
                let size = try directorySize(candidate)
                if size == nil { warnings.append("大小未能完整计算：\(candidate.path)") }
                items.append(ScanItem(url: candidate, category: category, association: association, evidence: evidence,
                                      identity: identity, bytes: size, removable: removable, caution: caution))
                progress(ScanProgress(path: candidate.path, count: items.count))
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("无法读取 \(candidate.path)：\(error.localizedDescription)") }
        }
        try add(app.url, category: .application, association: .exact, evidence: "用户选择的应用：\(app.bundleID)", removable: true)
        let bases = includeSystemLibrary ? [library, URL(fileURLWithPath: "/Library")] : [library]
        for base in bases {
            let system = base.path == "/Library"
            var locations = specs
            if system { locations += [("LaunchDaemons", .service), ("PrivilegedHelperTools", .service)] }
            for (folder, category) in locations {
                try Task.checkCancellation()
                let root = base.appendingPathComponent(folder)
                progress(ScanProgress(path: root.path, count: items.count))
                do {
                    if PathPolicy.hasSymlink(root) { warnings.append("跳过含符号链接的扫描范围：\(root.path)"); continue }
                    let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
                    for child in children {
                        try Task.checkCancellation()
                        let name = child.lastPathComponent
                        let exact = app.relatedIDs.contains { id in
                            name == id || name == id + ".plist" || name == id + ".savedState" ||
                            name == id + ".binarycookies" ||
                            (folder == "Preferences/ByHost" && isByHostPreference(name, id: id))
                        }
                        let group = category == .shared && app.groups.contains(name)
                        let named = [app.name, app.name + ".plist"].contains(name)
                        let launch = category == .service && launchItem(child, references: app.url)
                        guard exact || group || named || launch else { continue }
                        let relation: Association = group || category == .shared ? .shared : (exact || launch ? .exact : .name)
                        let canRemove = !system && exact && category != .shared && category != .service
                        let caution: String?
                        if system || category == .service { caution = "仅报告：系统位置或后台服务，请使用厂商卸载流程" }
                        else if relation == .shared { caution = "共享数据，不证明该应用独占；保留" }
                        else if relation == .name { caution = "仅名称匹配，归属不确定；保留" }
                        else if [.preferences, .support, .container].contains(category) { caution = "可能包含配置、账号状态或用户数据" }
                        else { caution = nil }
                        try add(child, category: category, association: relation,
                                evidence: group ? "签名 entitlement 声明使用此共享容器" : (launch ? "启动配置引用所选应用路径" : (exact ? "匹配 Bundle ID：\(name)" : "匹配应用名称：\(app.name)")),
                                removable: canRemove, caution: caution)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
                catch { warnings.append("未能扫描 \(root.path)：\(error.localizedDescription)") }
            }
        }
        warnings.append("扫描仅覆盖已列出的 Library 位置和应用本体；其他账户、文档、任意自定义位置及不可访问数据未覆盖。")
        return ScanReport(app: app, items: items, warnings: warnings, allowedRoots: allowed)
    }

    private func isByHostPreference(_ name: String, id: String) -> Bool {
        guard name.hasPrefix(id + "."), name.hasSuffix(".plist") else { return false }
        let middle = String(name.dropFirst(id.count + 1).dropLast(6))
        return UUID(uuidString: middle) != nil
    }
    private func launchItem(_ url: URL, references app: URL) -> Bool {
        guard url.pathExtension == "plist", !PathPolicy.hasSymlink(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? Int.max) < 1_000_000,
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        let path = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        guard let path, path.hasPrefix("/") else { return false }
        return PathPolicy.contains(app, URL(fileURLWithPath: path))
    }

    private func directorySize(_ url: URL) throws -> Int64? {
        let fm = FileManager.default
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values.isDirectory == true else { return values.fileSize.map(Int64.init) }
        var incomplete = false
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey], errorHandler: { _, _ in incomplete = true; return true }) else { return nil }
        var total: Int64 = 0, count = 0
        for case let entry as URL in enumerator {
            try Task.checkCancellation(); count += 1
            if count > 50_000 { return nil }
            do {
                let item = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey])
                if item.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if item.isDirectory != true { total += Int64(item.fileSize ?? 0) }
            } catch { incomplete = true }
        }
        return incomplete ? nil : total
    }
}
