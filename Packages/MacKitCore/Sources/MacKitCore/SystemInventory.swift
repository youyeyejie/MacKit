import Foundation
import SQLite3
import Darwin

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
}

public enum SystemCommand {
    /// Fixed system tools, argv only, bounded lifetime; never invokes a shell.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 8) throws -> CommandResult {
        guard ["/usr/bin/sfltool", "/usr/sbin/pkgutil", "/usr/bin/tccutil", "/bin/launchctl"].contains(executable) else {
            throw CocoaError(.executableNotLoadable)
        }
        try Task.checkCancellation()
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".command")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        var interrupted = false
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                interrupted = true; process.terminate()
                Thread.sleep(forTimeInterval: 0.1)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                break
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        process.waitUntilExit()
        try Task.checkCancellation()
        let reader = try FileHandle(forReadingFrom: log)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 2_000_000) ?? Data()
        return CommandResult(status: interrupted ? -1 : process.terminationStatus,
                             output: String(decoding: data, as: UTF8.self))
    }
}

public enum SystemInventory {
    public static func inspect(app: AppIdentity, home: URL, includeHostSystem: Bool) -> (items: [SystemAssociation], warnings: [String]) {
        guard includeHostSystem, !Task.isCancelled else { return ([], []) }
        var items: [SystemAssociation] = [], warnings: [String] = []
        let databases = [home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
                         URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")]
        for id in app.relatedIDs.sorted() {
            var services: Set<String> = []
            var readable = 0
            for database in databases {
                if let found = readPermissions(database: database, client: id) { readable += 1; services.formUnion(found) }
            }
            let detail: String
            if !services.isEmpty { detail = "已读取：" + services.sorted().joined(separator: "、") + (readable < databases.count ? "；其他数据库未能读取" : "") }
            else if readable < databases.count { detail = "权限数据库未能完整读取。可选择仅重置该标识的权限；不代表已确认存在权限记录。" }
            else { detail = "已读取数据库中未发现该标识的权限记录。" }
            items.append(SystemAssociation(id: "privacy:" + id, title: id, detail: detail, kind: .privacy,
                                           action: .resetPermissions, bundleID: id, confirmed: !services.isEmpty))
        }
        if let result = try? SystemCommand.run("/usr/bin/sfltool", ["dumpbtm"]), result.status == 0 {
            let records = backgroundRecords(result.output, app: app)
            for (index, record) in records.enumerated() {
                items.append(SystemAssociation(id: "login:\(index)", title: record.0, detail: record.1,
                                               kind: .login, action: .loginSettings, bundleID: nil, confirmed: true))
            }
            if records.isEmpty { warnings.append("后台项清单未匹配到此应用；系统版本的输出格式或权限可能影响识别。") }
        } else { warnings.append("无法读取系统登录与后台项清单。请在系统设置中核对，不代表没有启动项。") }
        if let result = try? SystemCommand.run("/usr/sbin/pkgutil", ["--pkgs"]), result.status == 0 {
            for id in result.output.split(separator: "\n").map(String.init) {
                guard AssociationMatcher.match(name: id, ids: app.relatedIDs, aliases: []) != nil else { continue }
                items.append(SystemAssociation(id: "receipt:" + id, title: id,
                    detail: "安装收据候选。收据不等于文件归属，移除收据不会卸载文件；请使用厂商卸载器处理共享安装内容。",
                    kind: .receipt, action: .vendorUninstaller, bundleID: nil, confirmed: false))
            }
        } else { warnings.append("无法读取安装收据清单。") }
        // Always expose the manual follow-up even if BTM is unavailable; do not invent a found item.
        if !items.contains(where: { $0.kind == .login }) {
            items.append(SystemAssociation(id: "login:manual", title: "核对登录与后台项", detail: "未能确认关联项；打开系统设置检查。不能使用全局重置代替卸载单个应用。",
                                           kind: .login, action: .loginSettings, bundleID: nil, confirmed: false))
        }
        return (items, warnings)
    }

    /// TCC has no public inventory API. This optional, read-only query tolerates schema/access failures.
    private static func readPermissions(database: URL, client: String) -> Set<String>? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT service FROM access WHERE client = ? AND client_type = 0", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, client, -1, transient)
        var services: Set<String> = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return services }
            guard status == SQLITE_ROW else { return nil }
            if let text = sqlite3_column_text(statement, 0) {
                services.insert(String(cString: text).replacingOccurrences(of: "kTCCService", with: ""))
            }
        }
    }

    public static func backgroundRecords(_ text: String, app: AppIdentity) -> [(String, String)] {
        var records: [[String: String]] = [], current: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("UUID:") || line.hasPrefix("#") || line.hasPrefix("Item ") {
                if !current.isEmpty { records.append(current); current = [:] }
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if ["Name", "Identifier", "Parent Identifier", "URL", "Executable Path", "Type", "Disposition"].contains(key) { current[key] = value }
        }
        if !current.isEmpty { records.append(current) }
        return records.compactMap { record in
            let identifierMatch = [record["Identifier"], record["Parent Identifier"]].compactMap { $0 }.contains { app.relatedIDs.contains($0) }
            let pathMatch = [record["URL"], record["Executable Path"]].compactMap { $0 }.contains { value in
                let url = value.hasPrefix("file:") ? URL(string: value) : (value.hasPrefix("/") ? URL(fileURLWithPath: value) : nil)
                return url.map { PathPolicy.contains(app.url, $0) } ?? false
            }
            guard identifierMatch || pathMatch else { return nil }
            let name = record["Name"] ?? record["Identifier"] ?? "后台项"
            let details = [record["URL"], record["Executable Path"], record["Disposition"]].compactMap { $0 }.joined(separator: " · ")
            return (name, details + "；由 macOS 管理，请在登录项设置中关闭或移除。")
        }
    }
}

public enum SystemCleanup {
    public static func resetPermissions(bundleID: String, allowedIDs: Set<String>) throws -> CommandResult {
        guard allowedIDs.contains(bundleID), !bundleID.hasPrefix("com.apple."),
              bundleID != "com.mackit.app", !bundleID.isEmpty else { throw UninstallError.protectedApplication }
        return try SystemCommand.run("/usr/bin/tccutil", ["reset", "All", bundleID])
    }
    public static func unloadUserAgent(_ item: ScanItem) throws {
        guard let label = item.serviceLabel else { return }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        guard !label.isEmpty, label.unicodeScalars.allSatisfy(allowed.contains), !label.hasPrefix("com.apple.") else {
            throw UninstallError.unsafePath(item.url.path)
        }
        let target = "gui/\(getuid())/\(label)"
        let present = try SystemCommand.run("/bin/launchctl", ["print", target])
        if present.status != 0 {
            if present.output.contains("Could not find service") || present.status == 113 { return }
            throw NSError(domain: "MacKit.LaunchAgent", code: Int(present.status), userInfo: [NSLocalizedDescriptionKey: "无法确认启动服务状态，已保留文件"])
        }
        let result = try SystemCommand.run("/bin/launchctl", ["bootout", target])
        guard result.status == 0 else {
            throw NSError(domain: "MacKit.LaunchAgent", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: "未能停止启动服务，已保留：" + result.output.prefix(300)])
        }
    }
}
