import Foundation
import Security

public struct AppScanner: Sendable {
    public let home: URL
    public let ownURL: URL?
    public let ownID: String?
    public let includeSystemLibrary: Bool
    public let extraRoots: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                ownURL: URL? = Bundle.main.bundleURL, ownID: String? = Bundle.main.bundleIdentifier,
                includeSystemLibrary: Bool = true, extraRoots: [URL] = []) {
        self.home = home.resolvingSymlinksInPath(); self.ownURL = ownURL; self.ownID = ownID
        self.includeSystemLibrary = includeSystemLibrary
        self.extraRoots = extraRoots.filter { PathPolicy.path($0) != "/" && !PathPolicy.contains(URL(fileURLWithPath: "/System"), $0) }
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
        var aliases: Set<String> = [url.deletingPathExtension().lastPathComponent]
        for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let value = bundle.object(forInfoDictionaryKey: key) as? String { aliases.insert(value) }
        }
        if let helpers = bundle.object(forInfoDictionaryKey: "SMPrivilegedExecutables") as? [String: String] {
            ids.formUnion(helpers.keys.filter(validIdentifier))
        }
        var groups = signedGroups(url)
        // Only inspect explicitly nested component directories, never the full disk.
        for folder in ["Contents/PlugIns", "Contents/XPCServices", "Contents/Library/LoginItems", "Contents/Library/SystemExtensions", "Contents/Library/LaunchServices", "Contents/Helpers"] {
            let root = url.appendingPathComponent(folder)
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children where ["app", "appex", "xpc", "systemextension"].contains(child.pathExtension) && !PathPolicy.hasSymlink(child) {
                if let childID = Bundle(url: child)?.bundleIdentifier, validIdentifier(childID) { ids.insert(childID) }
                groups.formUnion(signedGroups(child))
            }
        }
        return AppIdentity(url: url, name: url.deletingPathExtension().lastPathComponent,
                           bundleID: id, relatedIDs: ids, groups: groups, snapshot: snapshot, aliases: aliases)
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
        let specs: [(String, FileCategory, Int)] = [
            ("Caches", .cache, 3), ("Preferences", .preferences, 2),
            ("Application Support", .support, 4), ("Logs", .logs, 3),
            ("Saved Application State", .state, 1), ("HTTPStorages", .cache, 2),
            ("WebKit", .cache, 2), ("Cookies", .cache, 1),
            ("Containers", .container, 1), ("Group Containers", .shared, 1),
            ("Daemon Containers", .container, 1), ("Application Scripts", .support, 2),
            ("Autosave Information", .state, 2), ("LaunchAgents", .service, 1),
            ("Services", .support, 2), ("PreferencePanes", .support, 1),
            ("Internet Plug-Ins", .support, 1), ("QuickLook", .support, 1)
        ]
        let library = home.appendingPathComponent("Library")
        var locations: [(URL, FileCategory, Int, Bool)] = specs.map { (library.appendingPathComponent($0.0), $0.1, $0.2, false) }
        if includeSystemLibrary {
            locations += specs.map { (URL(fileURLWithPath: "/Library").appendingPathComponent($0.0), $0.1, $0.2, true) }
            locations += [(URL(fileURLWithPath: "/Library/LaunchDaemons"), .service, 1, true),
                          (URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), .service, 1, true),
                          (URL(fileURLWithPath: "/Library/SystemExtensions"), .service, 3, true)]
        }
        for folder in [".config", ".cache", ".local/share", ".local/state"] {
            locations.append((home.appendingPathComponent(folder), folder == ".cache" ? .cache : .support, 3, false))
        }
        if home == fm.homeDirectoryForCurrentUser.resolvingSymlinksInPath() {
            locations.append((fm.temporaryDirectory.resolvingSymlinksInPath(), .cache, 2, false))
        }
        locations += extraRoots.map { ($0, FileCategory.support, 4, false) }
        let allowed = locations.map { $0.0 }
        var visited = 0
        var exhausted = false

        func add(_ candidate: URL, category: FileCategory, association: Association, evidence: String,
                 removable: Bool, caution: String? = nil, label: String? = nil) throws {
            let candidate = PathPolicy.canonical(candidate)
            try Task.checkCancellation()
            guard !items.contains(where: { $0.id == candidate.path }) else { return }
            do {
                let identity = try FileIdentity.read(candidate)
                guard !identity.isSymbolicLink, !PathPolicy.hasSymlink(candidate) else {
                    warnings.append("跳过符号链接：\(candidate.path)"); return
                }
                let size = try directorySize(candidate)
                if size == nil { warnings.append("大小未能完整计算：\(candidate.path)") }
                items.append(ScanItem(url: candidate, category: category, association: association, evidence: evidence,
                                      identity: identity, bytes: size, removable: removable, caution: caution, serviceLabel: label))
                progress(ScanProgress(path: candidate.path, count: items.count))
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("无法读取 \(candidate.path)：\(error.localizedDescription)") }
        }
        try add(app.url, category: .application, association: .exact, evidence: "所选应用 · \(app.bundleID)", removable: true)

        func walk(_ root: URL, category: FileCategory, depth: Int, system: Bool) throws {
            try Task.checkCancellation()
            guard !exhausted else { return }
            if PathPolicy.hasSymlink(root) { warnings.append("跳过含符号链接的范围：\(root.path)"); return }
            let children: [URL]
            do { children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { return }
            catch { warnings.append("未能扫描 \(root.path)：\(error.localizedDescription)"); return }
            for child in children {
                try Task.checkCancellation()
                visited += 1
                if visited > 30_000 { exhausted = true; warnings.append("已达到本次 30,000 个目录条目的扫描上限，可添加更具体的位置重新扫描。"); return }
                if visited % 100 == 0 { progress(ScanProgress(path: root.path, count: items.count)) }
                let name = child.lastPathComponent
                var relation = AssociationMatcher.match(name: name, ids: app.relatedIDs, aliases: app.aliases)
                var evidence = relation == .exact ? "匹配应用或组件标识：\(name)" : "名称或标识关联：\(name)"
                if root.lastPathComponent == "ByHost", app.relatedIDs.contains(where: { isByHostPreference(name, id: $0) }) {
                    relation = .exact; evidence = "匹配设备专属配置标识"
                }
                if category == .container || category == .shared {
                    let metadata = child.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
                    if let identifier = smallPlist(metadata)?["MCMMetadataIdentifier"] as? String,
                       app.relatedIDs.contains(identifier) || app.groups.contains(identifier) {
                        relation = app.groups.contains(identifier) ? .shared : .exact
                        evidence = "容器元数据：\(identifier)"
                    }
                }
                if app.groups.contains(name) { relation = .shared; evidence = "应用签名声明使用此共享容器" }
                if ["app", "appex", "xpc", "systemextension", "bundle", "prefPane", "qlgenerator", "plugin"].contains(child.pathExtension),
                   let childID = Bundle(url: child)?.bundleIdentifier, app.relatedIDs.contains(childID) {
                    relation = .exact; evidence = "组件 Bundle ID：\(childID)"
                }
                let plist = category == .service ? smallPlist(child) : nil
                let label = plist?["Label"] as? String
                let launch = category == .service && launchItem(child, references: app.url)
                if launch || label.map({ app.relatedIDs.contains($0) }) == true {
                    relation = .exact; evidence = launch ? "启动配置引用所选应用路径" : "启动服务标识匹配"
                }
                if var relation {
                    if category == .shared { relation = .shared }
                    let userAgent = category == .service && !system && root.lastPathComponent == "LaunchAgents" && label != nil
                    let canRemove = category != .service || userAgent
                    var notes: [String] = []
                    if system { notes.append("系统位置，可能需要管理员权限") }
                    if category == .service { notes.append(userAgent ? "先卸载当前用户的启动服务，再移到废纸篓" : "系统管理的服务，请使用厂商卸载器或系统设置") }
                    if relation == .shared { notes.append("其他应用可能共享此数据，删除会影响它们") }
                    if relation == .name || relation == .related { notes.append("归属需人工核对，默认不选") }
                    if [.preferences, .support, .container].contains(category) { notes.append("可能包含设置、账号或用户数据") }
                    try add(child, category: category, association: relation, evidence: evidence, removable: canRemove,
                            caution: notes.isEmpty ? nil : notes.joined(separator: "；"), label: userAgent ? label : nil)
                    continue // Do not duplicate or recursively inspect contents of a matched result.
                }
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                if depth > 1, values?.isDirectory == true, values?.isSymbolicLink != true, values?.isPackage != true,
                   !name.hasPrefix("."), !["com.apple.TCC", "CloudStorage", "Mobile Documents", "Keychains"].contains(name) {
                    try walk(child, category: category, depth: depth - 1, system: system)
                }
            }
        }
        for (root, category, depth, system) in locations {
            progress(ScanProgress(path: root.path, count: items.count))
            try walk(root, category: category, depth: depth, system: system)
        }
        // Known app-specific dot-directories are probed directly, never a recursive home scan.
        for alias in app.aliases {
            let key = AssociationMatcher.normalized(alias)
            guard key.count >= 3, !["electron", "helper", "app", "updater"].contains(key) else { continue }
            let candidate = home.appendingPathComponent("." + key)
            if fm.fileExists(atPath: candidate.path) {
                try add(candidate, category: .support, association: .name, evidence: "应用名称对应的隐藏目录",
                        removable: true, caution: "可能包含用户数据，归属需人工核对")
            }
        }
        let roots = allowed
        // Explicitly matched dot directories are allowed themselves, without authorizing the entire home.
        let explicit = items.filter { $0.url.deletingLastPathComponent().path == home.path }.map { $0.url }
        let system = SystemInventory.inspect(app: app, home: home, includeHostSystem: includeSystemLibrary)
        warnings += system.warnings
        warnings.append("已扫描 \(visited) 个目录条目。任意自定义位置、未索引位置及受保护数据仍可能遗漏；可添加扫描位置。权限及后台项目的状态单独列出。")
        return ScanReport(app: app, items: items, warnings: warnings, allowedRoots: roots, systemItems: system.items, explicitPaths: explicit)
    }

    private func smallPlist(_ url: URL) -> [String: Any]? {
        guard !PathPolicy.hasSymlink(url), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size < 1_000_000, let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
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
