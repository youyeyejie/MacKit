import Foundation
import Carbon

@main struct ShortcutSettingsChecks {
    @MainActor static func main() {
        let suite = "com.mackit.test.shortcuts." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        precondition(settings.show == .showDefault && settings.clean == .cleanDefault)
        settings.save(show: nil, clean: .cleanDefault)
        let reloaded = ShortcutSettings(defaults: defaults)
        precondition(reloaded.show == nil && reloaded.clean == .cleanDefault)
        reloaded.save(show: .showDefault, clean: nil)
        let single = ShortcutSettings(defaults: defaults)
        precondition(single.show == .showDefault && single.clean == nil)
        single.save(show: nil, clean: nil)
        let cleared = ShortcutSettings(defaults: defaults)
        precondition(cleared.show == nil && cleared.clean == nil)
        let custom = AppShortcut(keyCode: 8, modifiers: UInt32(controlKey | optionKey), key: "C")
        cleared.save(show: custom, clean: nil)
        let customReloaded = ShortcutSettings(defaults: defaults)
        precondition(customReloaded.show == custom && customReloaded.clean == nil)
        defaults.set(Data("invalid".utf8), forKey: "shortcut.show")
        precondition(ShortcutSettings(defaults: defaults).show == .showDefault)
        print("6 shortcut persistence checks passed")
    }
}
