// MacKit built-in lyric shelf when the main island is on another display. GPL-3.0-or-later.
import AppKit
import SwiftUI

struct BuiltinLyricFallbackPresenter: NSViewRepresentable {
    let isVisible: Bool
    let color: Color

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isVisible: isVisible, color: color)
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.panel?.close()
        coordinator.panel = nil
    }

    final class Coordinator {
        var panel: NSPanel?

        func update(isVisible: Bool, color: Color) {
            guard isVisible, let screen = NSScreen.screens.first(where: { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                else { return false }
                return CGDisplayIsBuiltin(number.uint32Value) != 0
            }) else {
                panel?.orderOut(nil)
                return
            }
            let notch = getClosedNotchSize(screen: screen.localizedName)
            let width = max(180, notch.width + 2 * max(0, notch.height - 12))
            if panel == nil {
                let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.level = .mainMenu + 3
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                ScreenCaptureVisibilityManager.shared.register(panel, scope: .entireInterface)
                self.panel = panel
            }
            let content = TimedLyricLine(width: width - 20, color: color)
                .frame(width: width, height: 28)
                .background(.black)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
            panel?.contentView = NSHostingView(rootView: content)
            panel?.setFrame(NSRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - notch.height - 28,
                width: width, height: 28), display: true)
            if panel?.isVisible != true { panel?.orderFrontRegardless() }
        }
    }
}
