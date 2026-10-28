import SwiftUI

struct ShortcutRecorder: View {
    let shortcut: AppShortcut
    let save: (AppShortcut) -> String?
    let recordingChanged: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button(recording ? "按下新组合键…" : shortcut.label) {
                if recording { finish() } else { start() }
            }.monospaced().frame(minWidth: 128, alignment: .trailing)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).frame(maxWidth: 240, alignment: .trailing) }
            if recording { Text("Esc 取消 · 含 ⌘ / ⌃ / ⌥").font(.caption2).foregroundStyle(.secondary) }
        }.onDisappear { finish() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in finish() }
    }
    private func start() {
        error = nil; recording = true; recordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 { finish(); return }
                guard let value = AppShortcut.from(event) else { error = "请包含 ⌘、⌃ 或 ⌥ 修饰键"; return }
                error = save(value)
                finish()
            }
            return nil
        }
    }
    private func finish() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = false; recordingChanged(false)
    }
}
