import AppKit
import ApplicationServices
import Observation

/// Owns one input tap and coordinates independent click/preview controllers.
/// Target-app AX work and captures never run inside the event callback.
@MainActor @Observable
final class DockEnhancementService: FeatureModule {
    let id = FeatureID.dockEnhancement
    private(set) var previewEnabled = (UserDefaults.standard.object(forKey: "dockEnhancement.previewEnabled") as? Bool)
        ?? UserDefaults.standard.bool(forKey: "dockEnhancement.enabled")
    private(set) var clickEnabled = (UserDefaults.standard.object(forKey: "dockEnhancement.clickEnabled") as? Bool)
        ?? UserDefaults.standard.bool(forKey: "dockEnhancement.enabled")
    var enabled: Bool { previewEnabled || clickEnabled }
    private(set) var running = false
    private(set) var status = "未启用"
    var message: String? { status == "未启用" ? nil : status }
    var available: Bool { AXIsProcessTrusted() }
    var isAvailable: Bool { available }
    var needsScreenRecording: Bool { !CGPreflightScreenCaptureAccess() }

    private let hitTest = DockHitTest()
    private let click = DockClickController()
    private var preview: DockPreviewController!
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var suspended = false
    private var sessionActive = true
    private var sessionObservers: [NSObjectProtocol] = []
    private var observers: [NSObjectProtocol] = []
    private var memoryPressure: DispatchSourceMemoryPressure?

    init() {
        preview = DockPreviewController(hitTest: hitTest)
        click.onHandled = { [weak self] in self?.preview.close() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            sessionObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let active = notification.name == NSWorkspace.sessionDidBecomeActiveNotification
                MainActor.assumeIsolated {
                    self?.sessionActive = active
                    self?.sync()
                }
            })
        }
        if enabled { start() }
    }

    func setPreviewEnabled(_ value: Bool) {
        previewEnabled = value
        UserDefaults.standard.set(value, forKey: "dockEnhancement.previewEnabled")
        stop()
        sync()
    }
    func setClickEnabled(_ value: Bool) {
        clickEnabled = value
        UserDefaults.standard.set(value, forKey: "dockEnhancement.clickEnabled")
        stop()
        sync()
    }
    /// A menu pause remembers the independent switches rather than enabling
    /// a feature the user previously left off when resuming.
    func toggleFromMenu() {
        let defaults = UserDefaults.standard
        if enabled {
            defaults.set(previewEnabled, forKey: "dockEnhancement.menuRestorePreview")
            defaults.set(clickEnabled, forKey: "dockEnhancement.menuRestoreClick")
            previewEnabled = false
            clickEnabled = false
        } else {
            previewEnabled = (defaults.object(forKey: "dockEnhancement.menuRestorePreview") as? Bool) ?? true
            clickEnabled = (defaults.object(forKey: "dockEnhancement.menuRestoreClick") as? Bool) ?? true
            if !previewEnabled && !clickEnabled { previewEnabled = true; clickEnabled = true }
        }
        defaults.set(previewEnabled, forKey: "dockEnhancement.previewEnabled")
        defaults.set(clickEnabled, forKey: "dockEnhancement.clickEnabled")
        stop()
        sync()
    }
    func setSuspended(_ value: Bool) { suspended = value; sync() }
    func sync() {
        if enabled && !suspended && sessionActive { start() } else { stop() }
    }

    func start() {
        guard enabled, !suspended, sessionActive else { return }
        guard available else { stop(); status = "需要辅助功能授权"; return }
        guard tap == nil else { return }
        var types: [CGEventType] = [.leftMouseDown]
        if previewEnabled { types += [.mouseMoved, .rightMouseDown, .otherMouseDown] }
        if clickEnabled { types += [.leftMouseDragged, .leftMouseUp] }
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            // Installed on the main run loop; no dispatch/synchronization is
            // required to make the click interception decision.
            let swallowed = MainActor.assumeIsolated {
                Unmanaged<DockEnhancementService>.fromOpaque(context).takeUnretainedValue().handle(type, event: event) == nil
            }
            return swallowed ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            status = "无法建立程序坞输入监听，请检查辅助功能权限"
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        running = true
        status = "已启用"
        observeWorkspace()
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            Task { @MainActor in self?.preview.close(clearCache: true) }
        }
        pressure.resume()
        memoryPressure = pressure
    }

    func stop() {
        running = false
        preview.close(clearCache: true)
        click.reset()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        memoryPressure?.cancel(); memoryPressure = nil
        hitTest.reset()
        status = enabled ? (suspended ? "已暂停" : "等待辅助功能授权") : "未启用"
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            click.reset(); preview.close()
            if running, available, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard running else { return Unmanaged.passUnretained(event) }
        if type == .mouseMoved {
            if previewEnabled { preview.moved(event.location) }
            return Unmanaged.passUnretained(event)
        }
        let covered = preview.covers(event.location)
        let consumed = clickEnabled && click.handle(type, event: event, hitTest: hitTest, panelContains: covered)
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
            let point = event.location
            // Native panel buttons must receive the event before teardown.
            if !covered { preview.mouseDown(point) }
        }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.preview.close() }
            })
        }
    }
}
