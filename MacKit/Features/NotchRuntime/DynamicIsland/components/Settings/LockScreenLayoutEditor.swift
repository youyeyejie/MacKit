// MacKit addition, 2026-11-08. GPL-3.0-or-later.
import SwiftUI
import Defaults
import CoreGraphics

struct LockScreenLayoutEditor: View {
    @Default(.lockScreenWeatherVerticalOffset) private var weatherOffset
    @Default(.lockScreenMusicVerticalOffset) private var musicOffset
    @Default(.lockScreenReminderWidgetVerticalOffset) private var reminderOffset
    @Default(.lockScreenLiveActivityVerticalOffset) private var activityOffset
    @ObservedObject private var weather = LockScreenWeatherManager.shared
    @ObservedObject private var reminder = LockScreenReminderWidgetManager.shared
    @StateObject private var animator = LockScreenPanelAnimator()
    @State private var sizes: [String: CGSize] = [:]
    @State private var activeDrag: String?
    @State private var startOffset: Double = 0

    var body: some View {
        GeometryReader { proxy in
            if let screen = LockScreenPreviewScreen.screen {
                let area = screen.frame.size
                let scale = min(proxy.size.width / area.width, proxy.size.height / area.height)
                ZStack(alignment: .topLeading) {
                    AtollWallpaperPreview().frame(width: area.width, height: area.height)
                    widget("activity", offset: $activityOffset, scale: scale) {
                        Capsule().fill(.black).frame(width: 220, height: 38)
                            .overlay { Image(systemName: "lock.fill").foregroundStyle(.white) }
                    }.position(x: area.width / 2, y: 19 - activityOffset)
                    if Defaults[.enableLockScreenMediaWidget] {
                        let rect = LockScreenPanelManager.shared.previewFrame(on: screen)
                        widget("music", offset: $musicOffset, scale: scale) {
                            LockScreenMusicPanel(animator: animator).fixedSize()
                        }.position(x: area.width / 2, y: area.height - (rect.midY - screen.frame.minY))
                    }
                    if Defaults[.enableLockScreenWeatherWidget] {
                        let snapshot = weather.snapshot ?? LockScreenPreviewData.weather()
                        let rect = LockScreenWeatherPanelManager.shared.previewFrame(size: sizes["weather"] ?? CGSize(width: 460, height: 130), snapshot: snapshot, on: screen)
                        widget("weather", offset: $weatherOffset, scale: scale) {
                            LockScreenWeatherWidget(snapshot: snapshot).fixedSize()
                        }.position(x: area.width / 2, y: area.height - (rect.midY - screen.frame.minY))
                    }
                    if Defaults[.enableLockScreenReminderWidget] {
                        let snapshot = reminder.snapshot ?? LockScreenReminderWidgetSnapshot(title: "提醒事项", eventTimeText: "10:00", relativeDescription: "即将开始", accent: .init(nsColor: .systemOrange), chipStyle: .eventColor, isCritical: false, iconName: "checklist")
                        let rect = LockScreenReminderWidgetPanelManager.shared.previewFrame(size: sizes["reminder"] ?? CGSize(width: 320, height: 50), on: screen)
                        widget("reminder", offset: $reminderOffset, scale: scale) {
                            LockScreenReminderWidget(snapshot: snapshot).fixedSize()
                        }.position(x: area.width / 2, y: area.height - (rect.midY - screen.frame.minY))
                    }
                }
                .frame(width: area.width, height: area.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: area.width * scale, height: area.height * scale, alignment: .topLeading)
                .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                .coordinateSpace(name: "lock-preview")
                .onAppear { animator.isPresented = true }
            }
        }
    }
    private func widget<V: View>(_ id: String, offset: Binding<Double>, scale: CGFloat, @ViewBuilder content: () -> V) -> some View {
        // Suppress playback controls inside the preview, but leave the outer
        // surface hit-testable so its drag gesture can receive mouse events.
        ZStack { content().allowsHitTesting(false) }
            .background { GeometryReader { geometry in Color.clear.onAppear { sizes[id] = geometry.size }.onChange(of: geometry.size) { _, size in sizes[id] = size } } }
            .contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .named("lock-preview"))
                .onChanged { value in
                    if activeDrag != id { activeDrag = id; startOffset = offset.wrappedValue }
                    offset.wrappedValue = min(160, max(-160, startOffset - value.translation.height / max(scale, 0.01)))
                    apply(id)
                }
                .onEnded { _ in activeDrag = nil; apply(id) })
    }
    private func apply(_ id: String) {
        switch id {
        case "music": LockScreenPanelManager.shared.applyOffsetAdjustment(animated: false)
        case "weather": LockScreenWeatherPanelManager.shared.refreshPositionForOffsets(animated: false)
        case "reminder": LockScreenReminderWidgetPanelManager.shared.refreshPosition(animated: false)
        default: LockScreenLiveActivityWindowManager.shared.refreshPositionForOffsets()
        }
    }
}

@MainActor enum LockScreenPreviewScreen {
    static var screen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
    static var aspectRatio: CGFloat {
        guard let size = screen?.frame.size, size.height > 0 else { return 16.0 / 10.0 }
        return size.width / size.height
    }
}

@MainActor enum LockScreenLayoutActions {
    static func reset() {
        Defaults[.lockScreenWeatherVerticalOffset] = 0
        Defaults[.lockScreenMusicVerticalOffset] = 0
        Defaults[.lockScreenReminderWidgetVerticalOffset] = 0
        Defaults[.lockScreenLiveActivityVerticalOffset] = 0
        LockScreenPanelManager.shared.applyOffsetAdjustment(animated: false)
        LockScreenWeatherPanelManager.shared.refreshPositionForOffsets(animated: false)
        LockScreenReminderWidgetPanelManager.shared.refreshPosition(animated: false)
        LockScreenLiveActivityWindowManager.shared.refreshPositionForOffsets()
    }
}
