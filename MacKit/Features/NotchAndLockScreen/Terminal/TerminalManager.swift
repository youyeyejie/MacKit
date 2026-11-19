/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 * Adapted from SwiftTerm (https://github.com/migueldeicaza/SwiftTerm)
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
import Defaults
import Foundation
import SwiftTerm
import SwiftUI

// MARK: - Stable Container

/// Container NSView that shields its terminal child from zero-sized frames.
///
/// When the notch closes, SwiftUI removes the `NSViewRepresentable` from the
/// hierarchy — but later re-adds the same `containerView` on reopen.  During
/// that insertion, SwiftUI momentarily sets the frame to `.zero`.  Without
/// protection, AppKit's autoresizing mask propagates the zero frame to the
/// terminal child, causing SwiftTerm's `processSizeChange` to resize the
/// emulator to 2 cols × 1 row (the enforced minimum), which destroys the
/// scrollback buffer.
///
/// We bypass `super.resizeSubviews(withOldSize:)` entirely and manually set
/// children to fill the container's bounds.  This avoids the autoresizing
/// calculation which produces corrupt geometry when `oldSize` was `.zero`
/// (recorded during the transient removal) but the child kept its previous
/// large frame.
final class StableTerminalContainerView: NSView {
    /// Identifies the gutter tint view so `resizeSubviews` can keep its ring mask in sync.
    static let gutterTintIdentifier = NSUserInterfaceItemIdentifier("terminalGutterTint")

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let size = bounds.size
        // Block degenerate sizes — the terminal would collapse to 2×1
        guard size.width >= 10, size.height >= 10 else { return }
        // Manually fill children to bounds — bypasses autoresizing math
        // that breaks when oldSize was zero but child kept its old frame.
        // The terminal view gets an inner inset so glyphs don't hug the edge;
        // the frosted blur underlay and the gutter tint stay full-bleed to the
        // rounded clip (the tint is masked to the ring so it only fills the inset
        // gutter, matching the terminal background without doubling over it).
        let inset = notchTerminalInnerTextInset
        let terminalFrame = bounds.insetBy(dx: inset, dy: inset)
        for child in subviews {
            if let terminal = child as? MacKitTerminalView {
                terminal.layoutText(in: terminalFrame)
            } else {
                child.frame = bounds
                if child.identifier == Self.gutterTintIdentifier {
                    Self.applyGutterMask(to: child, bounds: bounds, hole: terminalFrame)
                }
            }
        }
    }

    /// Masks `view` to the gutter ring: the full bounds minus the inset `hole`
    /// where the terminal sits, using the even-odd fill rule.
    static func applyGutterMask(to view: NSView, bounds: CGRect, hole: CGRect) {
        let localBounds = CGRect(origin: .zero, size: bounds.size)
        let mask = (view.layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.fillRule = .evenOdd
        let path = CGMutablePath()
        path.addRect(localBounds)
        path.addRect(CGRect(x: hole.minX, y: hole.minY, width: hole.width, height: hole.height))
        mask.path = path
        mask.frame = localBounds
        view.layer?.mask = mask
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // When re-inserted into a window (notch reopened), force a full
        // redraw so SwiftTerm re-renders the terminal buffer contents.
        for child in subviews {
            child.needsDisplay = true
        }
        Task { @MainActor in
            TerminalManager.shared.refreshTerminalAppearanceIfNeeded()
        }
    }
}

// Keep the fixed caret even when a shell theme or full-screen program sends DECSCUSR.
final class MacKitTerminalView: LocalProcessTerminalView {
    private let textClip = CAShapeLayer()

    func layoutText(in textFrame: NSRect) {
        // SwiftTerm subtracts the legacy scroller width when sizing the grid,
        // even with the scroller hidden. Clip the extra frame to the text area.
        let reservedWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        frame = NSRect(
            origin: textFrame.origin,
            size: NSSize(width: textFrame.width + reservedWidth, height: textFrame.height)
        )
        let visibleBounds = NSRect(origin: bounds.origin, size: textFrame.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textClip.frame = bounds
        textClip.path = CGPath(rect: visibleBounds, transform: nil)
        layer?.mask = textClip
        CATransaction.commit()
    }

    var selectionDragChanged: ((Bool) -> Void)?
    private var selectionDragEvent: NSEvent?
    private var selectionScrollTimer: Timer?

    private var selectionEventMonitor: Any?
    private var selectionMouseDown = false

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            endSelectionDrag()
            if let selectionEventMonitor { NSEvent.removeMonitor(selectionEventMonitor) }
            selectionEventMonitor = nil
            if newWindow != nil {
                selectionEventMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]
                ) { [weak self] event in
                    guard let self else { return event }
                    return self.handleSelectionEvent(event)
                }
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func handleSelectionEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            endSelectionDrag()
            if let window, event.window === window, let superview {
                let point = superview.convert(event.locationInWindow, from: nil)
                let pointInParent = superview.convert(point, to: superview.superview)
                selectionMouseDown = superview.hitTest(pointInParent) === self
            }
        case .leftMouseDragged:
            if selectionMouseDown, !allowMouseReporting || getTerminal().mouseMode == .off {
                selectionDragEvent = event
                startSelectionScroll()
            }
        case .leftMouseUp:
            endSelectionDrag()
        case .scrollWheel:
            if selectionDragEvent != nil, NSEvent.pressedMouseButtons & 1 != 0, let window,
                !allowMouseReporting || getTerminal().mouseMode == .off {
                scrollWheel(with: event)
                extendSelection(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
                return nil
            }
        default:
            break
        }
        return event
    }

    private func startSelectionScroll() {
        guard selectionScrollTimer == nil else { return }
        selectionDragChanged?(true)
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.scrollSelectionAtEdge()
            }
        }
        selectionScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func endSelectionDrag() {
        selectionMouseDown = false
        guard let selectionScrollTimer else { return }
        selectionScrollTimer.invalidate()
        self.selectionScrollTimer = nil
        selectionDragEvent = nil
        selectionDragChanged?(false)
    }

    private func scrollSelectionAtEdge() {
        guard let window, window.isVisible, NSEvent.pressedMouseButtons & 1 != 0,
            !allowMouseReporting || getTerminal().mouseMode == .off
        else {
            endSelectionDrag()
            return
        }

        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let edgeInset: CGFloat = 3
        if point.y >= bounds.maxY - edgeInset {
            scrollUp(lines: min(8, 1 + Int(max(0, point.y - bounds.maxY) / 12)))
        } else if point.y <= bounds.minY + edgeInset {
            scrollDown(lines: min(8, 1 + Int(max(0, bounds.minY - point.y) / 12)))
        } else {
            return
        }
        extendSelection(at: point)
    }

    private func extendSelection(at point: NSPoint) {
        guard let event = selectionDragEvent, let window, bounds.height > 2 else { return }
        // Re-hit-test the pointer against the new scrollback position. Clamp to
        // a visible row so dragging far past the edge never skips hidden text.
        let visiblePoint = NSPoint(x: point.x, y: min(bounds.maxY - 1, max(bounds.minY + 1, point.y)))
        guard let drag = NSEvent.mouseEvent(
            with: .leftMouseDragged, location: convert(visiblePoint, to: nil),
            modifierFlags: event.modifierFlags, timestamp: event.timestamp,
            windowNumber: window.windowNumber, context: nil, eventNumber: event.eventNumber,
            clickCount: event.clickCount, pressure: event.pressure
        ) else { return }
        mouseDragged(with: drag)
    }

    override func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
        super.cursorStyleChanged(source: source, newStyle: .blinkBar)
        if newStyle != .blinkBar {
            DispatchQueue.main.async { [weak self] in self?.getTerminal().setCursorStyle(.blinkBar) }
        }
    }
}

// MARK: - Terminal Manager

/// Manages the Guake-style dropdown terminal session lifecycle.
/// The terminal is lazily created when the user first switches to the terminal tab,
/// and the process is kept alive across notch open/close cycles.
///
/// Uses a stable `StableTerminalContainerView` as the host so that SwiftUI's
/// `NSViewRepresentable` lifecycle (make/update/dismantle) never tears down
/// the actual terminal.  The `LocalProcessTerminalView` is added as a subview
/// of the container and survives notch close/open cycles.
@MainActor
class TerminalManager: ObservableObject {
    static let shared = TerminalManager()

    /// Whether a shell process is currently running.
    @Published var isProcessRunning: Bool = false

    /// The current terminal title reported by the shell.
    @Published var terminalTitle: String = "Terminal"

    /// Stable container returned to SwiftUI — never deallocated.
    /// Uses `StableTerminalContainerView` to prevent zero-frame transients
    /// from destroying the scrollback buffer.
    let containerView: StableTerminalContainerView = {
        let v = StableTerminalContainerView(frame: .zero)
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        return v
    }()

    /// The actual terminal view (child of `containerView`).
    private(set) var terminalView: LocalProcessTerminalView?

    /// Frosted blur of desktop/content behind the terminal; always below `terminalView`.
    private lazy var terminalBackdropView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.autoresizingMask = [.width, .height]
        return view
    }()

    /// Tinted ring that fills the inset gutter with the terminal's background color
    /// so the inset text isn't surrounded by a bare-blur "ring".  Sits above the
    /// blur and below `terminalView`; masked to the gutter so it never doubles the
    /// translucent background over the terminal's own cells.
    private lazy var terminalGutterTintView: NSView = {
        let v = NSView()
        v.identifier = StableTerminalContainerView.gutterTintIdentifier
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        v.autoresizingMask = [.width, .height]
        return v
    }()

    private init() {}

    // MARK: - Lifecycle

    /// Ensures the terminal view exists inside the container and returns the container.
    /// Call this from the `NSViewRepresentable` wrapper.
    func ensureTerminalView(delegate: LocalProcessTerminalViewDelegate) {
        if let existing = terminalView, existing.superview === containerView {
            // Already mounted — just re-wire the delegate in case the coordinator changed.
            existing.processDelegate = delegate
            // Re-apply opacity/translucency after hide/show cycles (e.g. shortcut toggle).
            refreshSystemTerminalAppearance(for: existing)
            return
        }

        // Use the container's current bounds if valid, otherwise a reasonable
        // default.  SwiftTerm's init calls setupOptions() which reads the
        // frame — a zero frame creates a 2×1 terminal that is corrected
        // once the container gets its proper layout size.
        let initialFrame =
            containerView.bounds.size.width >= 10
            ? containerView.bounds
            : CGRect(x: 0, y: 0, width: 400, height: 300)

        // Replace only the terminal view - keep the blur underlay between restarts.
        terminalView?.removeFromSuperview()

        let view = MacKitTerminalView(frame: initialFrame)
        view.autoresizingMask = [.width, .height]

        // Apply all settings from Defaults
        applyAllSettings(to: view)

        view.processDelegate = delegate

        if terminalBackdropView.superview == nil {
            containerView.addSubview(terminalBackdropView)
        }
        if terminalGutterTintView.superview == nil {
            containerView.addSubview(
                terminalGutterTintView,
                positioned: .above,
                relativeTo: terminalBackdropView
            )
        }
        updateGutterTintColor()
        containerView.addSubview(view)
        terminalView = view

        containerView.resizeSubviews(withOldSize: containerView.bounds.size)

        // Apply translucency immediately and again on the next run loop tick.
        // The deferred pass handles AppKit/SwiftUI mount timing where layer
        // changes can otherwise be lost on first open.
        refreshSystemTerminalAppearance(for: view)
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view, self.terminalView === view else { return }
            self.refreshSystemTerminalAppearance(for: view)
        }
    }

    /// Starts the shell process if not already running.
    func startShellProcess() {
        guard let view = terminalView, !isProcessRunning else { return }

        let configuredShell = Defaults[.terminalShellPath].trimmingCharacters(in: .whitespacesAndNewlines)
        let shell = configuredShell.isEmpty ? "/bin/zsh" : configuredShell
        let execName = "-" + (shell as NSString).lastPathComponent  // login shell convention

        view.startProcess(
            executable: shell,
            args: [],
            environment: buildEnvironment(),
            execName: execName,
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        isProcessRunning = true
    }

    /// Called when the shell process terminates.
    func processDidTerminate(exitCode: Int32?) {
        isProcessRunning = false
    }

    /// Restarts the shell by tearing down the old terminal and creating a fresh one.
    ///
    /// Instead of bumping a generation counter (which forced SwiftUI to destroy
    /// and recreate the `NSViewRepresentable` — recycling the same `containerView`
    /// across identities which broke layout), we simply nil out `terminalView`
    /// and change `@Published` state.  SwiftUI's `updateNSView` will fire,
    /// see the nil terminal, and call `ensureTerminalView` to mount a new one.
    func restartShell() {
        // Terminate the running process gracefully
        terminalView?.terminate()
        // Remove old terminal from container
        terminalView?.removeFromSuperview()
        terminalView = nil
        isProcessRunning = false
        terminalTitle = "Terminal"
    }

    /// Updates the terminal title from the shell escape sequence.
    func updateTitle(_ title: String) {
        terminalTitle = title
    }

    // MARK: - Font Resolution

    /// Resolves the terminal font from the user's chosen family and size.
    ///
    /// - If `family` is empty, returns the system monospaced font.
    /// - Otherwise tries `NSFont(name:size:)` and falls back to system monospaced
    ///   when the name is invalid or the font is not installed.
    private func resolveFont(family: String, size: CGFloat) -> NSFont {
        if !family.isEmpty, let custom = NSFont(name: family, size: size) {
            return custom
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Background color with opacity slider applied to alpha only (glyphs stay fully opaque).
    private func resolvedTerminalBackgroundNSColor() -> NSColor { .black }

    /// Composites the terminal buffer over `terminalBackdropView` without dimming glyphs.
    /// SwiftTerm’s `TerminalView.isOpaque` is read-only; translucency relies on alpha in `nativeBackgroundColor`.
    private func applyTerminalBackgroundAppearance(to view: LocalProcessTerminalView) {
        view.layer?.opacity = 1
        view.nativeBackgroundColor = resolvedTerminalBackgroundNSColor()
    }

    /// Upstream `TerminalView.setupOptions()` assigns `layer.backgroundColor` from `nativeBackgroundColor`, which
    /// prevents the `NSVisualEffectView` under the terminal from showing through. Re-clear after our color updates.
    /// Default-cell alpha and attribute-cache invalidation on native color changes may still need a SwiftTerm PR
    private func applyOpaqueTerminalLayer(to view: LocalProcessTerminalView) {
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.isOpaque = true
    }

    /// Best-effort redraw. `TerminalView.installColors(_:)` could clear SwiftTerm color caches but needs 16
    /// `SwiftTerm.Color` values; `Terminal.ansiColors` is not public, so we do not duplicate a palette here.
    private func synchronizeTerminalTranslucencyPresentation(to view: LocalProcessTerminalView) {
        applyOpaqueTerminalLayer(to: view)
        view.setNeedsDisplay(view.bounds)
    }

    /// Re-applies backdrop opacity + translucency hacks after remount/reopen paths.
    private func refreshSystemTerminalAppearance(for view: LocalProcessTerminalView) {
        applyTerminalBackgroundAppearance(to: view)
        synchronizeTerminalTranslucencyPresentation(to: view)
        updateGutterTintColor()
    }

    /// Keeps the gutter tint ring matching the terminal's resolved (translucent)
    /// background color so the inset gutter blends seamlessly with the cells.
    private func updateGutterTintColor() {
        terminalGutterTintView.layer?.backgroundColor = resolvedTerminalBackgroundNSColor().cgColor
    }

    // MARK: - Settings Application

    /// Applies all persisted settings to a terminal view at creation time.
    private func applyAllSettings(to view: LocalProcessTerminalView) {
        // Font
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        let fontFamily = Defaults[.terminalFontFamily]
        view.font = resolveFont(family: fontFamily, size: fontSize)

        // Colors (background opacity is separate from terminal opacity slider — see `applyTerminalBackgroundAppearance`)
        applyTerminalBackgroundAppearance(to: view)
        view.nativeForegroundColor = NSColor(NotchConfiguration.terminalForegroundColor)
        view.caretColor = NSColor(NotchConfiguration.terminalCursorColor)

        // Cursor style
        view.getTerminal().setCursorStyle(.blinkBar)

        // Keep drawing the selected cursor style when TerminalView.hasFocus is false; SwiftTerm
        // otherwise uses an unfocused/outline caret while tracksFocus is true.
        view.caretViewTracksFocus = false

        // Scrollback
        let scrollback = NotchConfiguration.terminalScrollbackLines
        view.getTerminal().buffer.changeHistorySize(scrollback)
        view.getTerminal().options.scrollback = scrollback

        // Input behavior
        view.optionAsMetaKey = NotchConfiguration.terminalOptionAsMeta
        view.allowMouseReporting = NotchConfiguration.terminalMouseReporting

        // Rendering
        view.useBrightColors = true

        refreshSystemTerminalAppearance(for: view)
        view.subviews.first { $0 is NSScroller }?.isHidden = true
    }

    /// Updates font size on the live terminal view.
    func applyFontSize(_ size: Double) {
        guard let view = terminalView else { return }
        let fontFamily = Defaults[.terminalFontFamily]
        view.font = resolveFont(family: fontFamily, size: CGFloat(size))
        view.setFrameSize(view.frame.size)
    }

    /// Updates font family on the live terminal view.
    func applyFontFamily(_ family: String) {
        guard let view = terminalView else { return }
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        view.font = resolveFont(family: family, size: fontSize)
        view.setFrameSize(view.frame.size)
    }

    /// Updates background opacity on the live terminal view (glyphs stay fully opaque).

    /// Updates cursor style on the live terminal view.

    /// Updates scrollback buffer size on the live terminal view.

    /// Updates option-as-meta on the live terminal view.

    /// Updates mouse reporting on the live terminal view.

    /// Updates bold-as-bright on the live terminal view.

    /// Updates background color on the live terminal view.

    /// Updates foreground color on the live terminal view.

    /// Called by UI lifecycle hooks after tab re-appearance to keep opacity stable.
    func refreshTerminalAppearanceIfNeeded() {
        guard let view = terminalView else { return }
        refreshSystemTerminalAppearance(for: view)
    }

    /// Makes terminal view first responder when terminal tab opens.
    /// Retries a few times to cover mount/animation timing so typing works immediately.
    func focusTerminalIfPossible() {
        focusTerminalIfPossible(attemptsRemaining: 3)
    }

    private func focusTerminalIfPossible(attemptsRemaining: Int) {
        guard let view = terminalView else { return }
        guard let window = containerView.window ?? view.window else {
            guard attemptsRemaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.focusTerminalIfPossible(attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }

        guard window.firstResponder !== view else { return }
        if !window.makeFirstResponder(view), attemptsRemaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.focusTerminalIfPossible(attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    /// Resigns terminal focus before closing notch to avoid stale responder state.
    func resignTerminalFirstResponderIfNeeded() {
        guard let view = terminalView else { return }
        guard let window = containerView.window ?? view.window else { return }
        guard window.firstResponder === view else { return }
        _ = window.makeFirstResponder(nil)
    }

    /// True when the terminal view is currently first responder.
    func isTerminalFirstResponder() -> Bool {
        guard let view = terminalView else { return false }
        guard let window = containerView.window ?? view.window else { return false }
        return window.firstResponder === view
    }

    /// Updates cursor color on the live terminal view.

    // MARK: - Environment

    /// Builds the environment for the child shell process.
    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        // Remove TERM_PROGRAM if set by a parent terminal
        env.removeValue(forKey: "TERM_PROGRAM")
        return env.map { "\($0.key)=\($0.value)" }
    }
}

// MARK: - Cursor Style Bridge

/// Codable-friendly cursor style enum that bridges to SwiftTerm's `CursorStyle`.
