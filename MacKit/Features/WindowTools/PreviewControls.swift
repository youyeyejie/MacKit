import SwiftUI

/// Separate buttons, never nested inside a window's activation button.
struct PreviewControls: View {
    var hasWindow: Bool
    var canMinimize: Bool
    let quit: () -> Void
    let close: () -> Void
    let minimize: () -> Void
    var canQuit: Bool = true
    var body: some View {
        HStack(spacing: 6) {
            control("power", color: .blue, help: "退出应用（⌘Q）", enabled: canQuit, action: quit)
            control("xmark", color: .red, help: "关闭窗口（⌘W）", enabled: hasWindow, action: close)
            control("minus", color: .yellow, help: "最小化窗口（⌘M）", enabled: canMinimize, action: minimize)
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
    }
    private func control(_ symbol: String, color: Color, help: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                .foregroundStyle(.black.opacity(0.75)).frame(width: 14, height: 14)
                .background(enabled ? color : Color.gray.opacity(0.6), in: Circle()).overlay(Circle().strokeBorder(.black.opacity(0.15)))
        }.buttonStyle(.plain).disabled(!enabled).help(help).accessibilityLabel(help)
    }
}

struct PreviewStateBadge: View {
    let minimized: Bool
    let fullscreen: Bool
    var body: some View {
        HStack(spacing: 4) {
            if minimized { badge("minus.rectangle", label: "最小化") }
            if fullscreen { badge("arrow.up.left.and.arrow.down.right", label: "全屏") }
        }.padding(5)
    }
    private func badge(_ name: String, label: String) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .semibold))
            .padding(5).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5)).help(label)
    }
}

struct PreviewHeader: View {
    let title: String
    let description: String
    let hasWindow: Bool
    let canMinimize: Bool
    let quit: () -> Void
    let close: () -> Void
    let minimize: () -> Void
    var showsControls: Bool = true
    var canQuit: Bool = true
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if showsControls {
                PreviewControls(hasWindow: hasWindow, canMinimize: canMinimize, quit: quit, close: close, minimize: minimize, canQuit: canQuit)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(description).font(.system(size: 9)).foregroundStyle(.secondary)
            }.lineLimit(1).multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
        }.frame(height: 30, alignment: .top)
    }
}
