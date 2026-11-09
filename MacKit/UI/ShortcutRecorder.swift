import SwiftUI

struct ShortcutRecorder: View {
    let shortcut: AppShortcut?
    let save: (AppShortcut?) -> String?
    let recordingChanged: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var error: String?
    var body: some View {
        HStack(spacing: 8) {
            Button {
                if recording { finish() } else { start() }
            } label: {
                Text(recording ? "按下组合键…" : (shortcut?.label ?? "点击设置"))
                    .lineLimit(1)
                    .frame(width: 100)
            }
            .buttonStyle(.bordered)
            .help(recording ? "Esc 取消；请包含 ⌘、⌃ 或 ⌥ 修饰键" : "点击录制快捷键")
            Button {
                finish()
                error = save(nil)
            } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 20, height: 24)
                .help("清空快捷键").accessibilityLabel("清空快捷键")
                .disabled(shortcut == nil && !recording)
        }
        .padding(.vertical, 8)
        .popover(isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Text(error ?? "").font(.callout).padding(12)
        }
        .onDisappear { finish() }
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
