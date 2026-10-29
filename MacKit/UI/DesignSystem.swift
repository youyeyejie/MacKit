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
            if let title { Text(title).font(AppStyle.sectionTitle).frame(minHeight: AppStyle.rowHeight, alignment: .leading) }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.cardInset)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
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
