import AppKit
import Carbon
import Observation

struct AppShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String
    var label: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") +
        (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") +
        (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") +
        (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + key
    }
    static let showDefault = AppShortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey | cmdKey), key: "M")
    static let cleanDefault = AppShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey | cmdKey), key: "K")
    static func from(_ event: NSEvent) -> AppShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option),
              !event.isARepeat, let text = event.charactersIgnoringModifiers, !text.isEmpty else { return nil }
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        let names: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        let key = names[event.keyCode] ?? text.uppercased()
        return AppShortcut(keyCode: UInt32(event.keyCode), modifiers: mask, key: key)
    }
    func conflicts(with other: AppShortcut) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
}

@MainActor @Observable
final class ShortcutSettings {
    private(set) var show: AppShortcut?
    private(set) var clean: AppShortcut?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        show = Self.read("shortcut.show", defaultValue: .showDefault, defaults: defaults)
        clean = Self.read("shortcut.clean", defaultValue: .cleanDefault, defaults: defaults)
    }
    private static func read(_ key: String, defaultValue: AppShortcut, defaults: UserDefaults) -> AppShortcut? {
        guard let data = defaults.data(forKey: key) else { return defaultValue }
        do {
            // A stored JSON null means intentionally disabled, not an absent preference.
            guard let shortcut = try JSONDecoder().decode(AppShortcut?.self, from: data) else { return nil }
            guard shortcut.keyCode < 128, shortcut.modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else { return defaultValue }
            return shortcut
        } catch { return defaultValue }
    }
    func save(show: AppShortcut?, clean: AppShortcut?) {
        self.show = show; self.clean = clean
        defaults.set(try? JSONEncoder().encode(show), forKey: "shortcut.show")
        defaults.set(try? JSONEncoder().encode(clean), forKey: "shortcut.clean")
    }
}
