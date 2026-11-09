// MacKit feature reduction, modified 2026-11-08.
// See THIRD_PARTY_NOTICES.md; GPL-3.0-or-later.
/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import AppKit
import SwiftUI
import SkyLightWindow
import QuartzCore
import Defaults

@MainActor
final class LockScreenReminderWidgetPanelManager {
    static let shared = LockScreenReminderWidgetPanelManager()

    private var window: NSWindow?
    private var hasDelegated = false
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    var isVisible: Bool {
        window?.isVisible == true
    }

    private init() {
        registerScreenChangeObservers()
    }

    func show(with snapshot: LockScreenReminderWidgetSnapshot) {
        render(snapshot: snapshot, makeVisible: true)
    }

    func update(with snapshot: LockScreenReminderWidgetSnapshot) {
        render(snapshot: snapshot, makeVisible: false)
    }

    func hide() {
        guard let window else { return }
        window.orderOut(nil)
        window.contentView = nil
    }

    func refreshPosition(animated: Bool) {
        guard let window, window.isVisible, let screen = currentScreen() else { return }
        let target = frame(for: window.frame.size, on: screen)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(target, display: true)
            }
        } else {
            window.setFrame(target, display: true)
        }
    }

    func previewFrame(size: CGSize, on screen: NSScreen) -> CGRect { frame(for: size, on: screen) }

    private func render(snapshot: LockScreenReminderWidgetSnapshot, makeVisible: Bool) {
        guard let screen = currentScreen() else { return }
        if !makeVisible, window == nil {
            return
        }

        let view = LockScreenReminderWidget(snapshot: snapshot)
        let hostingView = NSHostingView(rootView: view)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        let window = ensureWindow()
        window.setFrame(frame(for: fittingSize, on: screen), display: true)
        window.contentView = hostingView

        if makeVisible {
            window.orderFrontRegardless()
        }
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let frame = NSRect(origin: .zero, size: CGSize(width: 220, height: 48))
        let newWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newWindow.isReleasedWhenClosed = false
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = false
        newWindow.ignoresMouseEvents = true
        newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)

        window = newWindow
        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(newWindow)
            hasDelegated = true
        }
        return newWindow
    }

    private func frame(for size: CGSize, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let horizontalPadding: CGFloat = 24
        let originX = screenFrame.midX - size.width / 2
        // Anchor each component to its default screen layout, not another
        // component's dragged position. Its own offset is the only user input.
        let musicTop = LockScreenPanelManager.shared.previewFrame(on: screen, includeUserOffset: false).maxY

        let marginAboveMusic: CGFloat = 16
        let marginBelowWeather: CGFloat = 16

        let baseLowerBound = musicTop + marginAboveMusic
        let minYFloor = screenFrame.minY + 80
        let lowerBound = max(baseLowerBound, minYFloor)

        let defaultWeatherBottom = screenFrame.midY + (screenFrame.height * 0.14)
        let minimumWeatherBottom = lowerBound + size.height + marginBelowWeather
        let weatherBottom = min(screenFrame.maxY - 120, max(defaultWeatherBottom, minimumWeatherBottom))

        let upperBound = weatherBottom - marginBelowWeather - size.height
        let clampedUpperBound = max(upperBound, lowerBound)

        var proposedY: CGFloat

        proposedY = (lowerBound + clampedUpperBound) / 2

        let rawOffset = CGFloat(Defaults[.lockScreenReminderWidgetVerticalOffset])
        let clampedOffset = min(max(rawOffset, -160), 160)
        proposedY = max(lowerBound, min(proposedY + clampedOffset, clampedUpperBound))

        return NSRect(x: originX, y: proposedY, width: size.width, height: size.height)
    }

    private func registerScreenChangeObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenGeometryChange(reason: "screen-parameters")
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenGeometryChange(reason: "screens-did-wake")
        }

        workspaceObservers = [wakeObserver]
    }

    private func handleScreenGeometryChange(reason: String) {
        guard window?.isVisible == true else { return }
        refreshPosition(animated: false)
        print("LockScreenReminderWidgetPanelManager: realigned window due to \(reason)")
    }

    private func currentScreen() -> NSScreen? {
        LockScreenDisplayContextProvider.shared.contextSnapshot()?.screen ?? NSScreen.main
    }
}

