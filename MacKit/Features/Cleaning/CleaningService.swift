import AppKit
import SwiftUI
import Observation
import ApplicationServices

@MainActor @Observable
final class CleaningService: FeatureModule {
    let id = FeatureID.cleaning
    private(set) var active = false
    private(set) var progress = 0
    var message: String?
    var useCurrentDisplay = false
    var onActivity: ((Bool) -> Void)?
    private var panels: [NSPanel] = []
    private var filter: CleaningFilter?
    private var worker: EventTapWorker?
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
        guard !active else { return }
        guard AXIsProcessTrusted() else { message = "请先在权限页面授予辅助功能访问。"; return }
        guard hasBuiltinDisplay || useCurrentDisplay else {
            message = "未发现内建显示器，请先选择使用当前屏幕。"; return
        }
        message = nil
        let token = UUID(); session = token
        activate(token: token)
    }

    private func activate(token: UUID) {
        guard AXIsProcessTrusted() else { message = "辅助功能权限不可用。"; return }
        onActivity?(true)
        let filter = CleaningFilter { [weak self] count, done in
            Task { @MainActor in
                guard let self, self.session == token, self.active else { return }
                self.progress = count
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
        active = true; progress = 0
        let primary = NSScreen.screens.first(where: isBuiltin) ?? NSScreen.main
        for screen in NSScreen.screens {
            let full = screen == primary
            let frame = full ? screen.frame : NSRect(x: screen.frame.midX - 200, y: screen.frame.maxY - 210, width: 400, height: 170)
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
    }

    func stop() {
        session = UUID()
        filter?.deactivate(); worker?.stop()
        worker = nil; filter = nil
        heartbeat?.invalidate(); heartbeat = nil
        panels.forEach { $0.orderOut(nil) }; panels.removeAll()
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        active = false; progress = 0
        onActivity?(false)
    }
}

struct CleaningOverlay: View {
    let service: CleaningService
    let fullScreen: Bool
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 22) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                VStack(spacing: 9) {
                    Text("安心清洁").font(.system(size: 25, weight: .medium, design: .rounded))
                    HStack(spacing: 6) {
                        Text("连续按下")
                        Text("esc").font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                        Text("5 次退出")
                    }.font(.system(size: 13)).foregroundStyle(.white.opacity(0.58))
                }
                HStack(spacing: 12) {
                    ForEach(0..<5) { index in
                        Circle().fill(index < service.progress ? Color.mint : Color.white.opacity(0.16))
                            .frame(width: 9, height: 9)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: service.progress)
                .accessibilityLabel("退出进度：\(service.progress)/5")
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 44).padding(.vertical, fullScreen ? 32 : 16)
            .background(Color.white.opacity(fullScreen ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 24))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
