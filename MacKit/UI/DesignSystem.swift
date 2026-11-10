import SwiftUI

/// System Settings uses opaque grouped surfaces above the window canvas.
enum SettingsPalette {
    static let canvas = adaptive(light: 0xF5F5F5, dark: 0x202124)
    static let group = adaptive(light: 0xFFFFFF, dark: 0x27282D)
    static let sidebar = adaptive(light: 0xFAFAFA, dark: 0x292A2E)
    static let separator = adaptive(light: 0xE1E1E3, dark: 0x37383D)
    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 255) / 255,
                    green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
            })
    }
}

/// Shared typography and spacing for every main-panel page.
enum AppStyle {
    static let windowRadius: CGFloat = 20
    static let sidebarInset: CGFloat = 8
    static var sidebarRadius: CGFloat { windowRadius - sidebarInset }
    static let sliderWidth: CGFloat = 170
    // Four ideographs plus native popup-button arrows and horizontal insets.
    static let pickerMinimumWidth: CGFloat =
        ceil(("四个汉字" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width) + 32
    static let sectionTitle: Font = .system(size: 13, weight: .semibold)
    static let body: Font = .system(size: 13)
    static let pageInset: CGFloat = 20
    static let pageSpacing: CGFloat = 10
    static let cardInset: CGFloat = 10
    static let contentSpacing: CGFloat = 10
    static let rowHeight: CGFloat = 42
    static let sectionHeight: CGFloat = 24
}

struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.contentSpacing) {
            if let title {
                Text(title).font(AppStyle.sectionTitle).frame(minHeight: AppStyle.sectionHeight, alignment: .leading)
            }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.cardInset)
            .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 10))

    }
}

struct StatusPill: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption.weight(.medium))
        }.padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.08), in: Capsule())
    }
}

struct PageLayout<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.pageSpacing) { content }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, AppStyle.pageInset).padding(.top, 0).padding(.bottom, 20).frame(
                    maxWidth: .infinity, alignment: .top)
        }.font(AppStyle.body)
            .background(SettingsPalette.canvas)
    }
}

@MainActor enum AppBrand {
    /// Vector silhouette of the app's M mark, without its white icon tile.
    /// A template adapts to light/dark menu bars and stays sharp at any scale.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x: 2.5, y: 2.5)
            context.scaleBy(x: 15 / 662, y: 13 / 576)
            let m = CGMutablePath()
            m.move(to: CGPoint(x: 0, y: 98))
            m.addCurve(to: CGPoint(x: 160, y: 34), control1: CGPoint(x: 0, y: 8), control2: CGPoint(x: 99, y: -35))
            m.addLine(to: CGPoint(x: 307, y: 181))
            m.addQuadCurve(to: CGPoint(x: 352, y: 181), control: CGPoint(x: 330, y: 204))
            m.addLine(to: CGPoint(x: 500, y: 34))
            m.addCurve(to: CGPoint(x: 662, y: 100), control1: CGPoint(x: 561, y: -34), control2: CGPoint(x: 662, y: 6))
            m.addCurve(
                to: CGPoint(x: 633, y: 155), control1: CGPoint(x: 662, y: 126), control2: CGPoint(x: 660, y: 138))
            m.addLine(to: CGPoint(x: 559, y: 200))
            m.addCurve(
                to: CGPoint(x: 465, y: 293), control1: CGPoint(x: 510, y: 231), control2: CGPoint(x: 493, y: 259))
            m.addLine(to: CGPoint(x: 393, y: 367))
            m.addQuadCurve(to: CGPoint(x: 282, y: 374), control: CGPoint(x: 338, y: 431))
            m.addLine(to: CGPoint(x: 170, y: 266))
            m.addLine(to: CGPoint(x: 170, y: 489))
            m.addCurve(to: CGPoint(x: 0, y: 489), control1: CGPoint(x: 170, y: 605), control2: CGPoint(x: 0, y: 605))
            m.closeSubpath()
            let stem = CGMutablePath()
            stem.move(to: CGPoint(x: 492, y: 353))
            stem.addCurve(
                to: CGPoint(x: 539, y: 249), control1: CGPoint(x: 492, y: 307), control2: CGPoint(x: 509, y: 273))
            stem.addLine(to: CGPoint(x: 636, y: 189))
            stem.addQuadCurve(to: CGPoint(x: 662, y: 201), control: CGPoint(x: 662, y: 176))
            stem.addLine(to: CGPoint(x: 662, y: 489))
            stem.addCurve(
                to: CGPoint(x: 492, y: 489), control1: CGPoint(x: 662, y: 605), control2: CGPoint(x: 492, y: 605))
            stem.closeSubpath()
            context.addPath(m)
            context.addPath(stem)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacKit"
        return image
    }()

    // Read our bundle resource directly; NSWorkspace may retain an older installed icon.
    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()
}

/// Settings use the same control height and inset across toggles and recorders.
struct SettingsRows<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(AppStyle.sectionTitle).padding(.leading, 5).padding(.top, 16).padding(.bottom, 5)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 10)
                .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct EmbeddedSettingsRowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var embeddedSettingsRow: Bool {
        get { self[EmbeddedSettingsRowKey.self] }
        set { self[EmbeddedSettingsRowKey.self] = newValue }
    }
}

struct SettingsRow<Control: View>: View {
    @Environment(\.embeddedSettingsRow) private var embedded
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppStyle.body)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.vertical, embedded ? 0 : 9)
            Spacer(minLength: 12)
            control.controlSize(.regular)
        }.frame(minHeight: embedded ? 24 : AppStyle.rowHeight)
    }
}

/// Sample the desktop behind the window, then apply the native glass container.
private struct SidebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct SidebarGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                SettingsPalette.sidebar, in: RoundedRectangle(cornerRadius: AppStyle.sidebarRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.sidebarRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
            }
    }
}

/// Shared section renderer for feature content with dynamic and conditional rows.
struct UnifiedSettingsSection<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }
    init(_ title: String, @ViewBuilder content: () -> Content) where Header == Text, Footer == EmptyView {
        self.content = content()
        header = Text(title)
        footer = EmptyView()
    }
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) where Footer == EmptyView {
        self.content = content()
        self.header = header()
        footer = EmptyView()
    }
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) where Header == EmptyView {
        self.content = content()
        header = EmptyView()
        self.footer = footer()
    }
    init(@ViewBuilder content: () -> Content) where Header == EmptyView, Footer == EmptyView {
        self.content = content()
        header = EmptyView()
        footer = EmptyView()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if Header.self != EmptyView.self {
                header.font(AppStyle.sectionTitle).padding(.leading, 5).padding(.top, 16).padding(.bottom, 5)
            }
            _VariadicView.Tree(SettingsSectionRows()) { content }
                .environment(\.embeddedSettingsRow, true)
                .padding(.horizontal, 10)
                .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 12))
            if Footer.self != EmptyView.self {
                footer.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSectionRows: _VariadicView.MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                if child.id != children.first?.id { Divider() }
                child.frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .padding(.vertical, 9)
            }
        }
    }
}

struct SettingsTrailingToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

/// A separate value column precedes the track. Uniform ranges snap without tick marks.
struct CompactSettingsSlider<Value: BinaryFloatingPoint, Label: View>: View where Value.Stride: BinaryFloatingPoint {
    @Environment(\.embeddedSettingsRow) private var embedded
    @Binding var value: Value
    let bounds: ClosedRange<Value>
    let step: Value.Stride
    let valueText: String
    let uniform: Bool
    let label: Label
    let onEditingChanged: (Bool) -> Void

    init(
        value: Binding<Value>, in bounds: ClosedRange<Value>, step: Value.Stride,
        valueText: String, uniform: Bool = true,
        @ViewBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _value = value
        self.bounds = bounds
        self.step = step
        self.valueText = valueText
        self.uniform = uniform
        self.label = label()
        self.onEditingChanged = onEditingChanged
    }
    var body: some View {
        HStack(spacing: 12) {
            label
            Spacer(minLength: 12)
            Text(valueText).foregroundStyle(.secondary).monospacedDigit()
            if uniform {
                Slider(
                    value: Binding(
                        get: { value },
                        set: { raw in
                            let offset = Double(raw - bounds.lowerBound)
                            let snapped = bounds.lowerBound + Value((offset / Double(step)).rounded() * Double(step))
                            value = min(bounds.upperBound, max(bounds.lowerBound, snapped))
                        }), in: bounds
                ) {
                    label
                } onEditingChanged: {
                    onEditingChanged($0)
                }
                .labelsHidden().frame(width: AppStyle.sliderWidth)
            } else {
                Slider(value: $value, in: bounds, step: step) {
                    label
                } onEditingChanged: {
                    onEditingChanged($0)
                }
                .labelsHidden().frame(width: AppStyle.sliderWidth)
            }
        }
        .frame(minHeight: embedded ? 24 : AppStyle.rowHeight)
    }
}

struct SettingsDescription: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The complete padded row is an interactive navigation target.
struct SettingsDestinationRow: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: AppStyle.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
