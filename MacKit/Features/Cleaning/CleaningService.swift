import AppKit
import SwiftUI
import Observation
import ApplicationServices

@MainActor @Observable
final class CleaningService: FeatureModule {
    let id = FeatureID.cleaning
    private(set) var active = false
    private(set) var countdown: Int?
    private(set) var progress = 0
    private(set) var showHint = true
    var message: String?
    var useCurrentDisplay = false
    var onActivity: ((Bool) -> Void)?
    private var panels: [NSPanel] = []
    private var filter: CleaningFilter?
    private var worker: EventTapWorker?
    private var task: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var heartbeat: Timer?
    private var observers: [NSObjectProtocol] = []
    private var session = UUID()
    private var cursorHidden = false

    init() {
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active else { return }
                self.stop(); self.message = "显示器配置发生变化，已退出清洁模式。"
            }
        })
    }

    var hasBuiltinDisplay: Bool { NSScreen.screens.contains(where: isBuiltin) }
    private func isBuiltin(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }

    func begin() {
        guard !active, countdown == nil else { return }
        guard AXIsProcessTrusted() else { message = "请先授权辅助功能，再开始清洁。"; return }
        guard hasBuiltinDisplay || useCurrentDisplay else {
            message = "未发现可用内建显示器，请先选择使用当前屏幕。"; return
        }
        message = nil
        let token = UUID(); session = token
        task = Task { [weak self] in
            guard let self else { return }
            for value in (1...3).reversed() {
                self.countdown = value
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard self.session == token else { return }
            }
            self.countdown = nil
            // Do not swallow releases for keys which were pressed before the lock.
            let keysHeld = (0..<128).contains { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
            let buttonsHeld = (0..<3).contains { CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!) }
            guard !keysHeld, !buttonsHeld else { self.message = "请松开键盘和触控板后重试。"; return }
            self.activate(token: token)
        }
    }

    private func activate(token: UUID) {
        guard AXIsProcessTrusted() else { message = "辅助功能权限不可用。"; return }
        onActivity?(true)
        let filter = CleaningFilter { [weak self] count, done in
            Task { @MainActor in
                guard let self, self.session == token, self.active else { return }
                self.progress = count
                self.revealHint()
                if done { self.stop() }
            }
        }
        let worker = EventTapWorker(mask: CleaningFilter.eventMask, healthy: { filter.isHealthy() }, failed: { [weak self] in
            filter.deactivate()
            Task { @MainActor in
                guard let self, self.session == token else { return }
                self.stop(); self.message = "输入拦截已中断，清洁模式已退出。"
            }
        }, handler: { type, event in filter.handle(type, event) })
        guard worker.start() else {
            filter.deactivate(); worker.stop(); onActivity?(false)
            message = "无法建立输入拦截。请检查辅助功能权限，重新打开 MacKit 后重试。"
            return
        }
        self.filter = filter; self.worker = worker
        active = true; progress = 0; showHint = true
        let primary = NSScreen.screens.first(where: isBuiltin) ?? NSScreen.main
        for screen in NSScreen.screens {
            let full = screen == primary
            let frame = full ? screen.frame : NSRect(x: screen.frame.midX - 190, y: screen.frame.maxY - 120, width: 380, height: 80)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.backgroundColor = .black
            panel.isOpaque = true
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            panel.contentView = NSHostingView(rootView: CleaningOverlay(service: self, fullScreen: full))
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        NSCursor.hide(); cursorHidden = true
        heartbeat = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active else { return }
                guard AXIsProcessTrusted() else { self.stop(); self.message = "辅助功能权限被撤销。"; return }
                self.filter?.beat()
            }
        }
        revealHint()
    }

    private func revealHint() {
        showHint = true
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.showHint = false
        }
    }

    func stop() {
        session = UUID()
        task?.cancel(); task = nil
        hintTask?.cancel(); hintTask = nil
        countdown = nil
        filter?.deactivate(); worker?.stop()
        worker = nil; filter = nil
        heartbeat?.invalidate(); heartbeat = nil
        panels.forEach { $0.orderOut(nil) }; panels.removeAll()
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        active = false; progress = 0
        onActivity?(false)
    }
}

private struct CleaningOverlay: View {
    let service: CleaningService
    let fullScreen: Bool
    var body: some View {
        ZStack {
            Color.black
            if service.showHint || !fullScreen {
                VStack(spacing: 10) {
                    Text("键盘与触控板已锁定").font(.title3)
                    Text("连续按 5 次 Esc 退出 · \(service.progress)/5").foregroundStyle(.gray)
                }.foregroundStyle(.white)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
