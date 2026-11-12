/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See THIRD_PARTY_NOTICES.md for the original NOTICE and attribution.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Cocoa
import SwiftUI

class DynamicIslandWindow: NSPanel {
    private var interactionFrame: NSRect = .zero
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?

    func updateInteractionFrame(_ frame: NSRect) {
        interactionFrame = frame
        updatePointerRouting()
    }

    func containsInteractionPoint(_ point: NSPoint, exitPadding: CGFloat = 0) -> Bool {
        guard isVisible, alphaValue >= 0.01 else { return false }
        return interactionFrame.insetBy(dx: -exitPadding, dy: -exitPadding)
            .contains(convertPoint(fromScreen: point))
    }

    private func updatePointerRouting() {
        let local = convertPoint(fromScreen: NSEvent.mouseLocation)
        ignoresMouseEvents = !isVisible || alphaValue < 0.01 || !interactionFrame.contains(local)
    }

    private func installPointerRouting() {
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] _ in
            self?.updatePointerRouting()
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] event in
            self?.updatePointerRouting()
            return event
        }
    }

    override func close() {
        ignoresMouseEvents = true
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        globalPointerMonitor = nil
        localPointerMonitor = nil
        super.close()
    }
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        // Fail open until the visible SwiftUI content reports its hit region.
        ignoresMouseEvents = true
        installPointerRouting()
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false

        collectionBehavior = [
            .fullScreenAuxiliary,
            .canJoinAllSpaces,
            .ignoresCycle,
            .stationary,
        ]

        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false

        ScreenCaptureVisibilityManager.shared.register(self, scope: .entireInterface)
    }

    // Nonactivating panels can send keys straight to their first responder
    // without consulting the app menu's key equivalents (notably the terminal).
    override func sendEvent(_ event: NSEvent) {
        if handleQuitShortcut(event) { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleQuitShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleQuitShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard event.type == .keyDown, modifiers == .command,
              isKeyWindow,
              event.charactersIgnoringModifiers?.lowercased() == "q" || event.keyCode == 12
        else { return false }
        NSApp.terminate(nil)
        return true
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool { false }

}

/// Reports the visible notch, rather than the oversized transparent hosting area.
struct NotchInteractionRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> RegionView { RegionView() }
    func updateNSView(_ view: RegionView, context: Context) {
        DispatchQueue.main.async { [weak view] in view?.publish() }
    }
    final class RegionView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            publish()
        }
        override func layout() {
            super.layout()
            publish()
        }
        func publish() {
            guard let window = window as? DynamicIslandWindow else { return }
            window.updateInteractionFrame(convert(bounds, to: nil))
        }
    }
}
