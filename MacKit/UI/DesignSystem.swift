import SwiftUI

/// Shared typography and spacing for every main-panel page.
enum AppStyle {
    static let sectionTitle: Font = .title3.bold()
    static let body: Font = .body
    static let pageInset: CGFloat = 24
    static let pageSpacing: CGFloat = 18
    static let cardInset: CGFloat = 20
    static let contentSpacing: CGFloat = 14
    static let rowHeight: CGFloat = 44
    static let sectionHeight: CGFloat = 24
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var color: Color = .blue
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white).frame(width: 54, height: 54)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 23, weight: .bold))
                Text(subtitle).font(AppStyle.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(.bottom, 8)
    }
}

struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.contentSpacing) {
            if let title { Text(title).font(AppStyle.sectionTitle).frame(minHeight: AppStyle.sectionHeight, alignment: .leading) }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.cardInset)
            .modifier(GlassSurface())
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
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
                .frame(maxWidth: 800, alignment: .leading)
                .padding(AppStyle.pageInset).frame(maxWidth: .infinity, alignment: .topLeading)
        }.font(AppStyle.body).lineSpacing(3)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Keep actions at the title's trailing edge when space allows; stack on narrow windows.
struct PermissionCard<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions
    var body: some View {
        SettingsCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    Text(title).font(AppStyle.sectionTitle).fixedSize()
                    Spacer(minLength: 12)
                    HStack(spacing: 8) { actions }.fixedSize()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(AppStyle.sectionTitle)
                    HStack(spacing: 8) { actions }
                }
            }.frame(minHeight: AppStyle.rowHeight)
            Text(subtitle).font(AppStyle.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            m.addCurve(to: CGPoint(x: 633, y: 155), control1: CGPoint(x: 662, y: 126), control2: CGPoint(x: 660, y: 138))
            m.addLine(to: CGPoint(x: 559, y: 200))
            m.addCurve(to: CGPoint(x: 465, y: 293), control1: CGPoint(x: 510, y: 231), control2: CGPoint(x: 493, y: 259))
            m.addLine(to: CGPoint(x: 393, y: 367))
            m.addQuadCurve(to: CGPoint(x: 282, y: 374), control: CGPoint(x: 338, y: 431))
            m.addLine(to: CGPoint(x: 170, y: 266))
            m.addLine(to: CGPoint(x: 170, y: 489))
            m.addCurve(to: CGPoint(x: 0, y: 489), control1: CGPoint(x: 170, y: 605), control2: CGPoint(x: 0, y: 605))
            m.closeSubpath()
            let stem = CGMutablePath()
            stem.move(to: CGPoint(x: 492, y: 353))
            stem.addCurve(to: CGPoint(x: 539, y: 249), control1: CGPoint(x: 492, y: 307), control2: CGPoint(x: 509, y: 273))
            stem.addLine(to: CGPoint(x: 636, y: 189))
            stem.addQuadCurve(to: CGPoint(x: 662, y: 201), control: CGPoint(x: 662, y: 176))
            stem.addLine(to: CGPoint(x: 662, y: 489))
            stem.addCurve(to: CGPoint(x: 492, y: 489), control1: CGPoint(x: 662, y: 605), control2: CGPoint(x: 492, y: 605))
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
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSApp.applicationIconImage
    }()
}

/// Settings use the same control height and inset across toggles and recorders.
struct SettingsRows<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        SettingsCard(title: title) {
            VStack(spacing: 0) { content }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title).font(.body)
            Spacer(minLength: 12)
            control.controlSize(.regular)
        }.frame(minHeight: AppStyle.rowHeight)
    }
}

/// Native Liquid Glass on macOS 26+, with a solid, accessible older-system fallback.
struct GlassSurface: ViewModifier {
    var radius: CGFloat = 14
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
        }
    }
}
