import AppKit
import CoreGraphics
import Observation
import SwiftUI

@MainActor @Observable
final class WindowSwitcherService: FeatureModule {
    enum Mode { case applications, applicationWindows }

    let id = FeatureID.windowSwitcher
    private(set) var enabled = UserDefaults.standard.bool(forKey: "windowSwitcher.enabled")
    private(set) var buttonsEnabled = (UserDefaults.standard.object(forKey: "windowSwitcher.buttonsEnabled") as? Bool) ?? true
    private var quitConfirmation: NSPanel?
    private var bulkQuitChordHeld = false
    private(set) var running = false
    private(set) var items: [WindowItem] = []
    private(set) var selectedIndex = 0
    private(set) var mode: Mode = .applications
    private(set) var previews: [CGWindowID: NSImage] = [:]
    private(set) var message: String?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var panel: NSPanel?
    private var suspended = false
    private var sessionTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private let thumbnails = DockThumbnailStore()
    private var pendingCommit = false
    private var suppressCommit = false
    private var steps = 0
    private(set) var columns = 4
    private var sessionID = UUID()
    private var selectedPID: pid_t?
    private var lastHoverPoint = CGPoint.zero


    var isAvailable: Bool { AXIsProcessTrusted() }

    init() {
        if enabled { start() }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "windowSwitcher.enabled")
        if value { start() } else { stop() }
    }

    func setButtonsEnabled(_ value: Bool) {
        buttonsEnabled = value
        UserDefaults.standard.set(value, forKey: "windowSwitcher.buttonsEnabled")
    }

    func canQuit(_ item: WindowItem) -> Bool {
        AppQuitPolicy.allows(bundleID: NSRunningApplication(processIdentifier: item.ownerPID)?.bundleIdentifier,
                             ownBundleID: Bundle.main.bundleIdentifier)
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        if value { stop() }
        sync()
    }

    func hover(index: Int) {
        let point = NSEvent.mouseLocation
        guard point != lastHoverPoint else { return }
        lastHoverPoint = point
        select(index: index)
    }

    func select(index: Int) {
        guard items.indices.contains(index) else { return }
        if selectedIndex != index { suppressCommit = false }
        selectedIndex = index
        if previews[items[index].id] == nil { schedulePreviews() }

    }

    func start() {
        guard enabled, !suspended, tap == nil else { return }
        guard AXIsProcessTrusted() else {
            message = "需要辅助功能权限才能监听 ⌘Tab。"
            return
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<WindowSwitcherService>.fromOpaque(info).takeUnretainedValue()
            let consumed = MainActor.assumeIsolated { service.handle(type: type, event: event) == nil }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            message = "无法建立窗口切换输入监听。"
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        message = nil
    }

    func sync() {
        if enabled, !suspended { start() } else if !enabled { stop() }
    }

    func stop() {
        closeSession()
        quitConfirmation?.close(); quitConfirmation = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        running = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard enabled, !suspended else { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let command = event.flags.contains(.maskCommand)

        if type == .keyUp, keyCode == 12, bulkQuitChordHeld {
            bulkQuitChordHeld = false
            return nil
        }
        if type == .keyDown {
            if (bulkQuitChordHeld || quitConfirmation != nil), command, event.flags.contains(.maskShift), keyCode == 12 { return nil }
            if running, command, [12, 13, 46].contains(keyCode) {
                guard buttonsEnabled else { return nil }
                if keyCode == 12, event.flags.contains(.maskShift) {
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        suppressCommit = true
                        bulkQuitChordHeld = true
                        DispatchQueue.main.async { [weak self] in self?.confirmQuitAll() }
                    }
                    return nil
                }
            }
            if running, !items.isEmpty {
                if keyCode == 123 { advance(by: -1); return nil }
                if keyCode == 124 { advance(by: 1); return nil }
                if keyCode == 126 { advance(by: -columns); return nil }
                if keyCode == 125 { advance(by: columns); return nil }
                if command, keyCode == 13 { closeSelected(); return nil }
                if command, keyCode == 46 { minimizeSelected(); return nil }
                if command, keyCode == 12 { quit(items[selectedIndex]); return nil }
            }
            guard command, !event.flags.contains(.maskControl), !event.flags.contains(.maskAlternate) else { return Unmanaged.passUnretained(event) }
            if keyCode == 48 {
                if running { advance(by: event.flags.contains(.maskShift) ? -1 : 1) } else { begin(.applications, backwards: event.flags.contains(.maskShift)) }
                return nil
            }
            if keyCode == 50 {
                if running { restrictToSelectedApplication(backwards: event.flags.contains(.maskShift)) } else { begin(.applicationWindows, backwards: event.flags.contains(.maskShift)) }
                return nil
            }
        } else if type == .keyUp {
            if (keyCode == 48 || keyCode == 50), running { return nil }
            if keyCode == 55, running {
                commitSelection()
                return nil
            }
            if running, !command, keyCode != 55 {
                commitSelection()
                return nil
            }
        } else if type == .flagsChanged, running, !command {
            commitSelection()
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func snapshot(mode: Mode, pid: pid_t?) async -> [WindowItem] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid()
                && (mode == .applications || $0.processIdentifier == pid)
        }
        var result: [WindowItem] = []
        for app in apps {
            guard !Task.isCancelled else { return [] }
            let windows = await DockWindowAccess.windows(pid: app.processIdentifier)
            let name = app.localizedName ?? "应用"
            for window in windows {
                let item = WindowItem(id: window.id, ownerPID: app.processIdentifier, ownerName: name,
                                      title: window.title.isEmpty ? name : window.title, bounds: window.bounds,
                                      isOnscreen: !app.isHidden && !window.minimized,
                                      isMinimized: app.isHidden || window.minimized,
                                      isFullscreen: window.fullscreen, appIcon: app.icon)
                item.window = window
                result.append(item)
            }
            if windows.isEmpty, mode == .applications {
                result.append(WindowItem(id: 0, ownerPID: app.processIdentifier, ownerName: name,
                                         title: "没有打开的窗口", bounds: .zero, isOnscreen: false,
                                         isMinimized: app.isHidden, isFullscreen: false, appIcon: app.icon))
            }
        }
        return result.enumerated().sorted { lhs, rhs in
            let left = WindowPresence.orderGroup(windowless: lhs.element.isWindowless, minimized: lhs.element.isMinimized)
            let right = WindowPresence.orderGroup(windowless: rhs.element.isWindowless, minimized: rhs.element.isMinimized)
            if left != right { return left < right }
            if (lhs.element.ownerPID == pid) != (rhs.element.ownerPID == pid) { return lhs.element.ownerPID == pid }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func begin(_ requestedMode: Mode, backwards: Bool) {
        selectedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        mode = requestedMode
        running = true
        pendingCommit = false
        suppressCommit = false
        steps = backwards ? -1 : 1
        sessionID = UUID()
        let token = sessionID
        sessionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = ProcessInfo.processInfo.systemUptime
            let result = await self.snapshot(mode: requestedMode, pid: self.selectedPID)
            guard !Task.isCancelled, self.sessionID == token else { return }
            self.items = result
            guard !result.isEmpty else { self.closeSession(); return }
            self.selectedIndex = (self.steps % result.count + result.count) % result.count
            if self.pendingCommit { self.commitSelection(); return }
            let delay = 0.1 - (ProcessInfo.processInfo.systemUptime - started)
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, self.sessionID == token else { return }
            self.showPanel()
            self.schedulePreviews()
            self.monitorSession()
        }
    }

    private func restrictToSelectedApplication(backwards: Bool) {
        guard items.indices.contains(selectedIndex) else { return }
        if mode == .applicationWindows { advance(by: backwards ? -1 : 1); return }
        let pid = items[selectedIndex].ownerPID
        items = items.filter { $0.ownerPID == pid && !$0.isWindowless }
        selectedPID = pid
        mode = .applicationWindows
        selectedIndex = 0
        schedulePreviews()
    }

    private func advance(by offset: Int) {
        lastHoverPoint = NSEvent.mouseLocation
        guard !items.isEmpty else { steps += offset; return }
        suppressCommit = false
        selectedIndex = (selectedIndex + offset % items.count + items.count) % items.count
        if previews[items[selectedIndex].id] == nil && !items[selectedIndex].isWindowless { schedulePreviews() }
    }

    private var previewTask: Task<Void, Never>?
    private func schedulePreviews() {
        previewTask?.cancel()
        let token = sessionID
        let windows = Array(items.dropFirst(max(0, selectedIndex - columns * 2)).prefix(24)).compactMap(\.window)
        for item in items { if let window = item.window, let image = thumbnails.cached(window) { previews[item.id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) } }
        previewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.thumbnails.refresh(windows) { id, image in
                guard self.running, self.sessionID == token else { return }
                if self.previews.count >= 24, self.previews[id] == nil,
                   let victim = self.previews.keys.max(by: { a, b in
                       abs((self.items.firstIndex { $0.id == a } ?? 0) - self.selectedIndex) < abs((self.items.firstIndex { $0.id == b } ?? 0) - self.selectedIndex)
                   }) { self.previews[victim] = nil }
                self.previews[id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
    }

    private func monitorSession() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, let self, self.running else { return }
                let current = await self.snapshot(mode: self.mode, pid: self.selectedPID)
                guard !Task.isCancelled, self.running else { return }
                let live = Set(current.map(\.stableID))
                let selected = self.items.indices.contains(self.selectedIndex) ? self.items[self.selectedIndex].stableID : ""
                let existing = Set(self.items.map(\.stableID))
                for item in self.items {
                    if let fresh = current.first(where: { $0.stableID == item.stableID }) { item.isMinimized = fresh.isMinimized }
                }
                self.items = self.items.filter { live.contains($0.stableID) } + current.filter { !existing.contains($0.stableID) }
                self.items = self.items.enumerated().sorted {
                    if $0.element.isWindowless != $1.element.isWindowless { return !$0.element.isWindowless }
                    return $0.offset < $1.offset
                }.map(\.element)
                guard !self.items.isEmpty else { self.closeSession(); return }
                self.selectedIndex = self.items.firstIndex { $0.stableID == selected } ?? min(self.selectedIndex, self.items.count - 1)
                let ids = Set(self.items.map(\.id))
                self.previews = self.previews.filter { ids.contains($0.key) }
            }
        }
    }

    func closeSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        close(items[selectedIndex])
    }

    func quit(_ item: WindowItem) {
        guard buttonsEnabled, canQuit(item) else { return }
        suppressCommit = true
        NSRunningApplication(processIdentifier: item.ownerPID)?.terminate()
    }

    func close(_ item: WindowItem) {
        guard buttonsEnabled, let window = item.window else { return }
        suppressCommit = true
        Task { await DockWindowAccess.close(window) }
    }

    func minimize(_ item: WindowItem) {
        guard buttonsEnabled, let window = item.window, !window.fullscreen else { return }
        suppressCommit = true
        Task { @MainActor in
            await DockWindowAccess.setMinimized(true, windows: [window])
            item.isMinimized = true
        }
    }

    func minimizeSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        minimize(items[selectedIndex])
    }

    private func confirmQuitAll() {
        guard buttonsEnabled, quitConfirmation == nil else { return }
        let targets = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated &&
            AppQuitPolicy.allows(bundleID: $0.bundleIdentifier, ownBundleID: Bundle.main.bundleIdentifier)
        }
        closeSession()
        guard !targets.isEmpty else { return }
        let display = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = display?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        let panel = NSPanel(contentRect: NSRect(x: frame.midX - 240, y: frame.midY - 160, width: 480, height: 320),
                            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = PreviewHostingView(rootView: QuitAllConfirmation(
            names: targets.compactMap(\.localizedName).sorted().joined(separator: "、"),
            cancel: { [weak self] in self?.quitConfirmation?.close(); self?.quitConfirmation = nil },
            confirm: { [weak self] in
                self?.quitConfirmation?.close(); self?.quitConfirmation = nil
                for app in targets where !app.isTerminated {
                    if AppQuitPolicy.allows(bundleID: app.bundleIdentifier, ownBundleID: Bundle.main.bundleIdentifier) { app.terminate() }
                }
            }))
        quitConfirmation = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func commitSelection() {
        if suppressCommit { closeSession(); return }
        guard !items.isEmpty else { pendingCommit = true; return }
        guard running, items.indices.contains(selectedIndex) else { closeSession(); return }
        let selected = items[selectedIndex]
        closeSession()
        Task { @MainActor in
            guard let app = NSRunningApplication(processIdentifier: selected.ownerPID) else { return }
            if app.isHidden { app.unhide() }
            if let window = selected.window { await DockWindowAccess.raise(window) }
            app.activate(options: [])
            if selected.isWindowless, let url = app.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: { _, _ in })
            }
            if let window = selected.window {
                try? await Task.sleep(for: .milliseconds(120))
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == selected.ownerPID { await DockWindowAccess.raise(window) }
            }
        }
    }

    private func showPanel() {
        if panel == nil {
            let panel = NSPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .popUpMenu
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = PreviewHostingView(rootView: WindowSwitcherPanel(service: self))
            self.panel = panel
        }
        let point = NSEvent.mouseLocation
        lastHoverPoint = point
        let screen = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let builtin = NSScreen.screens.first { display in
            guard let number = display.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
        let reference = builtin?.frame ?? NSScreen.screens.first?.frame ?? screen
        columns = SwitcherLayout.columns(count: items.count, available: screen.size,
                                         targetAspect: reference.width / max(1, reference.height))
        let rows = (items.count + columns - 1) / columns
        let size = NSSize(width: CGFloat(columns) * 224 + 32, height: min(screen.height - 80, CGFloat(rows) * 184 + 64))
        panel?.setFrame(NSRect(x: screen.midX - size.width / 2,
                               y: screen.midY - size.height / 2,
                               width: size.width, height: size.height), display: true)
        panel?.orderFrontRegardless()
    }

    private func closeSession() {
        sessionID = UUID()
        sessionTask?.cancel(); sessionTask = nil
        refreshTask?.cancel(); refreshTask = nil
        previewTask?.cancel(); previewTask = nil
        panel?.orderOut(nil)
        running = false
        items.removeAll(keepingCapacity: false)
        previews.removeAll(keepingCapacity: false)
        selectedIndex = 0
        panel?.contentView = nil
        panel = nil
    }
}

private struct WindowSwitcherPanel: View {
    @Bindable var service: WindowSwitcherService

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                Text(service.mode == .applications ? "窗口切换" : "应用内窗口")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(service.buttonsEnabled ? "松开 ⌘ 确定 · ⌘Q 退出 · ⌘W 关闭 · ⌘M 最小化" : "松开 ⌘ 确定")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(216), spacing: 8), count: service.columns), spacing: 12) {
                        ForEach(Array(service.items.enumerated()), id: \.element.stableID) { index, item in
                            WindowSwitcherCard(item: item, image: service.previews[item.id], selected: index == service.selectedIndex,
                                               buttonsEnabled: service.buttonsEnabled, canQuit: service.canQuit(item),
                                               quit: { service.quit(item) }, close: { service.close(item) }, minimize: { service.minimize(item) })
                                .id(item.stableID)
                                .onTapGesture { service.select(index: index) }
                                .onContinuousHover { phase in if case .active = phase { service.hover(index: index) } }
                        }
                    }
                }
                .onChange(of: service.selectedIndex) { _, _ in
                    if service.items.indices.contains(service.selectedIndex) { proxy.scrollTo(service.items[service.selectedIndex].stableID) }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.14)))
        .padding(8)
    }
}

private struct WindowSwitcherCard: View {
    let item: WindowItem
    let image: NSImage?
    let selected: Bool
    let buttonsEnabled: Bool
    let canQuit: Bool
    let quit: () -> Void
    let close: () -> Void
    let minimize: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            PreviewHeader(title: item.title, description: item.ownerName, hasWindow: !item.isWindowless,
                          canMinimize: !item.isWindowless && !item.isFullscreen && !item.isMinimized,
                          quit: quit, close: close, minimize: minimize,
                          showsControls: buttonsEnabled, canQuit: canQuit)
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.12))
                if let image { Image(nsImage: image).resizable().scaledToFit().padding(2).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let icon = item.appIcon { Image(nsImage: icon).resizable().scaledToFit().padding(32) }
                else { Image(systemName: "macwindow").font(.system(size: 28)).foregroundStyle(.secondary) }
            }.frame(width: 204, height: 124)
                .overlay(alignment: .bottomTrailing) { PreviewStateBadge(minimized: item.isMinimized, fullscreen: item.isFullscreen) }
        }.frame(width: 204)

        .padding(6)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
    }
}

private final class PreviewHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct QuitAllConfirmation: View {
    let names: String
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("退出所有应用？", systemImage: "power").font(.title2.bold())
            Text("将请求退出以下应用。未保存的内容仍由各应用提示处理，Finder 和系统组件会保留。")
                .foregroundStyle(.secondary)
            ScrollView { Text(names).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100)
            HStack {
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("退出所有应用", role: .destructive, action: confirm)
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(GlassSurface(radius: 22))
    }
}
