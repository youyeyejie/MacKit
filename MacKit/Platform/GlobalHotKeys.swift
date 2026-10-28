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
        for (index, key) in [kVK_ANSI_M, kVK_ANSI_K].enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x4D4B4954, id: UInt32(index + 1))
            let result = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey), id,
                                             GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotkeys.append(reference) }
            else { error = "快捷键注册失败或冲突（\(result)），可通过 Spotlight 打开 MacKit。" }
        }
    }

    func stop() {
        hotkeys.forEach { UnregisterEventHotKey($0) }; hotkeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
