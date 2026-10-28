import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var color: Color = .blue
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white).frame(width: 54, height: 54)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 25, weight: .bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(.bottom, 8)
    }
}

struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title { Text(title).font(.headline) }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
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
            VStack(alignment: .leading, spacing: 18) { content }
                .frame(maxWidth: 800, alignment: .leading)
                .padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}
