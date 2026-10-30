import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class DockPreviewController {
    private(set) var windows: [DockWindow] = []
    private(set) var images: [CGWindowID: CGImage] = [:]
    private(set) var appName = ""
    private(set) var visible = false
    private var panel: NSPanel?
    private var refreshTask: Task<Void, Never>?
    private(set) var columns = 4
    private var session: DockHit?
    private var pendingHit: DockHit?
    private var enteredPanel = false
    private var hoverTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?
    private var trailingPoint: CGPoint?
    private var sampledAt: TimeInterval = 0
    private var sessionToken = UUID()
    private let thumbnails = DockThumbnailStore()
    private let hitTest: DockHitTest

    init(hitTest: DockHitTest) { self.hitTest = hitTest }

    func covers(_ axPoint: CGPoint) -> Bool { visible && panel?.frame.contains(DockHitTest.point(axPoint)) == true }

    /// Called by the tap. Keep AX, window enumeration and rendering out of it;
    /// coalesce moves, retaining the final point when the pointer stops.
    func moved(_ point: CGPoint) {
        if !visible, pendingHit == nil, !hitTest.nearDock(DockHitTest.point(point)) { return }
        trailingPoint = point
        guard moveTask == nil else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - sampledAt
        moveTask = Task { @MainActor [weak self] in
            if elapsed < 1.0 / 60 { try? await Task.sleep(for: .milliseconds(16)) }
            guard !Task.isCancelled, let self else { return }
            self.moveTask = nil
            self.sampledAt = ProcessInfo.processInfo.systemUptime
            guard let latest = self.trailingPoint else { return }
            self.route(latest)
        }
    }

    func mouseDown(_ point: CGPoint) {
        if covers(point) { cancelHide(); cancelHover() }
        else { close() }
    }

    private func route(_ axPoint: CGPoint) {
        // A down event is owned by the Dock/click controller, never a hover.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let point = DockHitTest.point(axPoint)
        if visible, let panel, let session {
            if panel.frame.insetBy(dx: -6, dy: -6).contains(point) {
                enteredPanel = true
                cancelHover(); cancelHide()
                return
            }
            if let hit = hitTest.hit(axPoint) {
                if hit.app.processIdentifier != session.app.processIdentifier {
                    cancelHide(); schedule(hit, delay: 100)
                } else if !enteredPanel {
                    cancelHide(); cancelHover()
                } else { scheduleHide() }
                return
            }
            if !enteredPanel, DockGeometry.openingPath(point, icon: session.frame, panel: panel.frame, edge: session.edge) {
                cancelHide(); cancelHover()
                return
            }
            scheduleHide()
            return
        }
        if let pendingHit, pendingHit.frame.insetBy(dx: -6, dy: -6).contains(point) { return }
        guard let hit = hitTest.hit(axPoint) else { cancelHover(); return }
        schedule(hit, delay: 200)
    }

    private func schedule(_ hit: DockHit, delay: Int) {
        if pendingHit?.app.processIdentifier == hit.app.processIdentifier { return }
        cancelHover()
        pendingHit = hit
        hoverTask = Task { @MainActor [weak self] in
            // Prefetch midway through the initial hover delay. AX runs on its
            // worker, so input delivery remains responsive for busy apps.
            try? await Task.sleep(for: .milliseconds(delay / 2))
            guard !Task.isCancelled else { return }
            let started = ProcessInfo.processInfo.systemUptime
            let windows = await DockWindowAccess.windows(pid: hit.app.processIdentifier)
            let remaining = Double(delay / 2) / 1000 - (ProcessInfo.processInfo.systemUptime - started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled, let self else { return }
            guard self.pendingHit?.app.processIdentifier == hit.app.processIdentifier,
                  let current = self.hitTest.hit(DockHitTest.axPoint(NSEvent.mouseLocation), fresh: true),
                  current.app.processIdentifier == hit.app.processIdentifier else { self.cancelHover(); return }
            self.pendingHit = nil
            self.hoverTask = nil
            self.open(current, windows: windows)
        }
    }

    private func open(_ hit: DockHit, windows: [DockWindow]) {
        guard !windows.isEmpty else { close(); return }
        cancelHide()
        captureTask?.cancel()
        sessionToken = UUID()
        let token = sessionToken
        session = hit
        enteredPanel = false
        appName = hit.app.localizedName ?? "应用"
        self.windows = windows
        images = Dictionary(uniqueKeysWithValues: windows.compactMap { window in thumbnails.cached(window).map { (window.id, $0) } })
        showPanel(hit: hit)
        visible = true
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, let self, self.sessionToken == token else { return }
                let live = await DockWindowAccess.windows(pid: hit.app.processIdentifier)
                guard !Task.isCancelled, self.sessionToken == token else { return }
                let ids = Set(live.map(\.id))
                self.windows = live
                self.images = self.images.filter { ids.contains($0.key) }
                if self.windows.isEmpty { self.close(); return }
            }
        }
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.thumbnails.refresh(windows) { [weak self] id, image in
                guard let self, self.visible, self.sessionToken == token, self.windows.contains(where: { $0.id == id }) else { return }
                self.images[id] = image
            }
        }
    }

    private func showPanel(hit: DockHit) {
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: hit.frame.midX, y: hit.frame.midY)) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        let vertical = hit.edge != .bottom
        columns = vertical ? 1 : max(1, min(4, Int((available.width - 36) / 210)))
        let size = vertical ? CGSize(width: 228, height: min(CGFloat(windows.count) * 172 + 12, available.height - 16))
            : CGSize(width: min(CGFloat(min(windows.count, columns)) * 210 + 20, available.width - 16), height: min(CGFloat((windows.count + columns - 1) / columns) * 172 + 12, available.height - 16))
        let frame = DockGeometry.panel(anchor: hit.frame, size: size, screen: available, edge: hit.edge)
        let panel = self.panel ?? NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = DockHostingView(rootView: DockPreviewView(model: self))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func scheduleHide() {
        guard hideTask == nil else { return }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            let point = NSEvent.mouseLocation
            if let panel = self.panel, panel.frame.insetBy(dx: -6, dy: -6).contains(point) { return }
            if let session = self.session {
                if let hit = self.hitTest.hit(DockHitTest.axPoint(point), fresh: true) {
                    if hit.app.processIdentifier != session.app.processIdentifier { self.schedule(hit, delay: 100); return }
                    if !self.enteredPanel { return }
                } else if !self.enteredPanel, let panel = self.panel,
                          DockGeometry.openingPath(point, icon: session.frame, panel: panel.frame, edge: session.edge) { return }
            }
            self.close()
        }
    }

    func quit(_ window: DockWindow) {
        guard let app = NSRunningApplication(processIdentifier: window.pid),
              AppQuitPolicy.allows(bundleID: app.bundleIdentifier, ownBundleID: Bundle.main.bundleIdentifier) else { return }
        app.terminate()
    }
    func closeWindow(_ window: DockWindow) { Task { await DockWindowAccess.close(window) } }
    func minimize(_ window: DockWindow) {
        guard !window.fullscreen else { return }
        Task { @MainActor in
            await DockWindowAccess.setMinimized(true, windows: [window])
            let current = await DockWindowAccess.windows(pid: window.pid)
            guard self.visible, self.session?.app.processIdentifier == window.pid else { return }
            self.windows = current
        }
    }

    func activate(_ window: DockWindow) {
        close()
        Task { @MainActor in
            guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
            if app.isHidden { app.unhide() }
            app.activate(options: [.activateIgnoringOtherApps])
            await DockWindowAccess.raise(window)
            // Apps can restore their previous key window during activation.
            // Reassert just the requested window after that activation settles.
            try? await Task.sleep(for: .milliseconds(100))
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid else { return }
            await DockWindowAccess.raise(window)
        }
    }

    func close(clearCache: Bool = false) {
        sessionToken = UUID()
        refreshTask?.cancel(); refreshTask = nil
        cancelHover(); cancelHide()
        moveTask?.cancel(); moveTask = nil; trailingPoint = nil
        captureTask?.cancel(); captureTask = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        session = nil
        windows = []; images = [:]; enteredPanel = false
        visible = false
        if clearCache { thumbnails.clear() }
    }
    private func cancelHover() { hoverTask?.cancel(); hoverTask = nil; pendingHit = nil }
    private func cancelHide() { hideTask?.cancel(); hideTask = nil }
}

private final class DockHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct DockPreviewView: View {
    @Bindable var model: DockPreviewController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(202), spacing: 8), count: min(model.columns, max(1, model.windows.count))), spacing: 8) { cards }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15)))
    }
    @ViewBuilder private var cards: some View {
        ForEach(model.windows) { window in
            DockPreviewCard(window: window, image: model.images[window.id], appName: model.appName,
                            activate: { model.activate(window) }, quit: { model.quit(window) }, close: { model.closeWindow(window) }, minimize: { model.minimize(window) })
        }
    }
}

private struct DockPreviewCard: View {
    let window: DockWindow
    let image: CGImage?
    let appName: String
    let activate: () -> Void
    let quit: () -> Void
    let close: () -> Void
    let minimize: () -> Void
    @State private var hovered = false
    var body: some View {
        VStack(spacing: 6) {
            PreviewHeader(title: window.title.isEmpty ? appName : window.title, description: appName,
                          hasWindow: true, canMinimize: !window.minimized && !window.fullscreen,
                          quit: quit, close: close, minimize: minimize,
                          canQuit: AppQuitPolicy.allows(bundleID: NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier, ownBundleID: Bundle.main.bundleIdentifier))
            Button(action: activate) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.12))
                    if let image {
                        Image(decorative: image, scale: 2).resizable().scaledToFit().padding(3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        Image(systemName: "macwindow").font(.system(size: 26)).foregroundStyle(.secondary)
                    }
                }.frame(width: 190, height: 116)
                    .overlay(alignment: .bottomTrailing) {
                        PreviewStateBadge(minimized: window.minimized, fullscreen: window.fullscreen)
                    }
            }.buttonStyle(.plain)
        }
        .frame(width: 190)
        .padding(6)
        .background(hovered ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .onHover { hovered = $0 }
        .help(window.title)
    }
}
