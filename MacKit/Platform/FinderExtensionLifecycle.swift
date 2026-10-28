import AppKit
import FinderSync
import Darwin

/// Only controls our own extension. System-hosted Finder extensions otherwise
/// outlive their containing app. Remember only changes made by MacKit itself.
@MainActor
final class FinderExtensionLifecycle {
    private let pausedKey = "finderExtension.pausedByMacKit"
    private var operation: Task<Bool, Never>?

    func resumeIfNeeded() async -> Bool {
        guard UserDefaults.standard.bool(forKey: pausedKey) else { return true }
        let success = await election("use")
        if success { UserDefaults.standard.removeObject(forKey: pausedKey) }
        return success
    }
    func pauseForQuit() async -> Bool {
        if let operation { _ = await operation.value }
        guard FIFinderSyncController.isExtensionEnabled else {
            await terminateOwnedInstances()
            return true
        }
        // Persist intent before changing the system election, for interrupted quits.
        UserDefaults.standard.set(true, forKey: pausedKey)
        let success = await election("ignore")
        if !success { UserDefaults.standard.removeObject(forKey: pausedKey) }
        await terminateOwnedInstances()
        return success
    }
    func reload(afterPause: @MainActor () -> Void, beforeResume: @MainActor () -> Void) async -> Bool {
        guard operation == nil, FIFinderSyncController.isExtensionEnabled else { return false }
        UserDefaults.standard.set(true, forKey: pausedKey)
        guard await election("ignore") else {
            UserDefaults.standard.removeObject(forKey: pausedKey); return false
        }
        afterPause()
        try? await Task.sleep(for: .milliseconds(500))
        await terminateOwnedInstances()
        beforeResume()
        return await resumeIfNeeded()
    }
    private func terminateOwnedInstances() async {
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/MacKitFinderExtension.appex/Contents/MacOS/MacKitFinderExtension")
            .resolvingSymlinksInPath().path
        await Task.detached(priority: .utility) {
            let capacity = Int(proc_listallpids(nil, 0)) + 128
            guard capacity > 128 else { return }
            var pids = [Int32](repeating: 0, count: capacity)
            let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride))
            guard count > 0 else { return }
            for pid in pids.prefix(min(Int(count), pids.count)) where pid > 1 {
                var info = proc_bsdinfo()
                guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
                      info.pbi_uid == getuid() else { continue }
                var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
                      String(cString: path) == executable else { continue }
                // Exact executable inside this installed bundle and current UID only.
                // Never kill Finder, another app's extension, or a same-name process elsewhere.
                kill(pid, SIGTERM)
            }
        }.value
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func election(_ value: String) async -> Bool {
        let work = Task.detached(priority: .utility) { Self.runElection(value) }
        operation = work
        let result = await work.value
        operation = nil
        return result
    }
    nonisolated private static func runElection(_ value: String) -> Bool {
        guard ["use", "ignore"].contains(value) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-e", value, "-i", "com.mackit.app.finder"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.025) }
        if process.isRunning { process.terminate(); Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
