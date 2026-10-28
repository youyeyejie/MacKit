import AppKit
import Carbon

@MainActor
final class GlobalHotKeys {
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let show: () -> Void
    private let clean: () -> Void
    private(set) var error: String?

    init(show: @escaping () -> Void, clean: @escaping () -> Void) {
        self.show = show; self.clean = clean
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
                if id.id == 1 { owner.show() } else if id.id == 2 { owner.clean() }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { error = "无法注册全局快捷键处理器。"; return }
    }

    /// Replace both registrations atomically from the user's perspective.
    /// If either shortcut is occupied, restore the previous pair.
    @discardableResult
    func configure(show: AppShortcut, clean: AppShortcut) -> Bool {
        let previous = current
        unregister()
        if register([show, clean]) { current = [show, clean]; error = nil; return true }
        let failure = error
        unregister()
        if !previous.isEmpty { _ = register(previous) }
        error = failure
        return false
    }
    private var current: [AppShortcut] = []
    func suspend() { unregister() }
    func resume() { unregister(); _ = register(current) }
    private func unregister() { hotkeys.forEach { UnregisterEventHotKey($0) }; hotkeys.removeAll() }
    private func register(_ shortcuts: [AppShortcut]) -> Bool {
        guard handler != nil else { return false }
        for (index, shortcut) in shortcuts.enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x4D4B4954, id: UInt32(index + 1))
            let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                             GetApplicationEventTarget(), 0, &reference)
            guard result == noErr, let reference else {
                error = "快捷键已被占用或无法注册（\(result)），请换一个组合。"; return false
            }
            hotkeys.append(reference)
        }
        return true
    }

    func stop() {
        hotkeys.forEach { UnregisterEventHotKey($0) }; hotkeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
