// Derived from Atoll; GPL-3.0-or-later.
// Original settings by Richard Kunkli, 2024; MacKit host adaptation, 2026.
// See THIRD_PARTY_NOTICES.md.
import AppKit
import Defaults
import SwiftUI

struct NotchShelfSettingsView: View {
    @Default(.quickShareProvider) var quickShareProvider

    @Default(.copyOnDrag) var copyOnDrag
    @Default(.autoRemoveShelfItems) var autoRemoveShelfItems
    @StateObject private var quickShareService = QuickShareService.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared
    @ObservedObject private var shelfFolderAccessPermission = ShelfFolderAccessPermissionStore.shared

    private var hasDocumentsAndDownloadsAccess: Bool {
        shelfFolderAccessPermission.hasDocumentsAndDownloadsAccess
    }

    private var canEnableShelf: Bool {
        fullDiskAccessPermission.isAuthorized || hasDocumentsAndDownloadsAccess
    }

    init() {
        QuickShareService.shared.ensureDiscovered()
    }

    var body: some View {
        Group {
            if !canEnableShelf || !fullDiskAccessPermission.isAuthorized {
                UnifiedSettingsSection {
                    if !canEnableShelf {
                        SettingsPermissionCallout(
                            title: "需要访问文件夹的权限",
                            message: "请启用完全磁盘访问权限，或允许访问文稿和下载文件夹，以使用文件托盘。",
                            icon: "folder.badge.questionmark",
                            iconColor: .orange,
                            requestButtonTitle: "请求文件夹访问权限",
                            openSettingsButtonTitle: "打开隐私与安全性",
                            requestAction: { shelfFolderAccessPermission.requestAccessPrompt() },
                            openSettingsAction: { shelfFolderAccessPermission.openSystemSettings() }
                        )
                    }

                    if !fullDiskAccessPermission.isAuthorized {
                        SettingsPermissionCallout(
                            title: "全局模式需要完全磁盘访问权限",
                            message: "未授予完全磁盘访问权限时，文件托盘只能访问文稿与下载文件夹；授权后可处理其他位置的文件。",
                            icon: "externaldrive.fill",
                            iconColor: .purple,
                            requestButtonTitle: "请求完全磁盘访问",
                            openSettingsButtonTitle: "打开隐私与安全性",
                            requestAction: { fullDiskAccessPermission.requestAccessPrompt() },
                            openSettingsAction: { fullDiskAccessPermission.openSystemSettings() }
                        )
                    }
                } header: {
                    Text("权限")
                }
            }

            UnifiedSettingsSection {
                Defaults.Toggle(key: .dynamicShelf) {
                    Text("启用文件托盘")
                }
                .disabled(!canEnableShelf)

                Defaults.Toggle(key: .copyOnDrag) {
                    Text("拖动时复制项目")
                }

                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("拖出后从文件托盘移除")
                }
            } header: {
                HStack {
                    Text("文件托盘")
                }
            }

            UnifiedSettingsSection {
                SettingsRow(title: "快速分享服务", subtitle: "选择文件托盘使用的分享服务。拖入文件，或点击托盘按钮选择文件。") {
                    Picker("快速分享服务", selection: $quickShareProvider) {
                        ForEach(quickShareService.availableProviders, id: \.id) { provider in
                            HStack {
                                QuickShareProviderIconImage(provider: provider, size: 12)
                                Text(provider.settingsTitle)
                            }
                            .tag(provider.id)
                        }
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).labelsHidden().frame(
                        maxWidth: 200, alignment: .trailing)
                }
                .pickerStyle(.menu)

            } header: {
                HStack {
                    Text("快速分享")
                }
            }

            if quickShareProvider == "LocalSend" {
            }
        }
        .accentColor(.effectiveAccent)

        .onAppear {
            fullDiskAccessPermission.refreshStatus()
            shelfFolderAccessPermission.refreshStatus()
        }
    }
}

struct SettingsPermissionCallout: View {
    let title: String
    let message: String
    let icon: String
    let iconColor: Color
    let requestButtonTitle: String
    let openSettingsButtonTitle: String
    let requestAction: () -> Void
    let openSettingsAction: () -> Void

    init(
        title: String = "需要辅助功能权限",
        message: String,
        icon: String = "exclamationmark.triangle.fill",
        iconColor: Color = .orange,
        requestButtonTitle: String = "请求授权",
        openSettingsButtonTitle: String = "打开设置",
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.requestButtonTitle = requestButtonTitle
        self.openSettingsButtonTitle = openSettingsButtonTitle
        self.requestAction = requestAction
        self.openSettingsAction = openSettingsAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(requestButtonTitle) {
                    requestAction()
                }
                .buttonStyle(.borderedProminent)

                Button(openSettingsButtonTitle) {
                    openSettingsAction()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Reusable App Icon View

/// Fetches the real app icon from the system using bundle identifiers,
/// falling back to an asset catalog image or an SF Symbol.

struct AppIconImage: View {
    let bundleIdentifiers: [String]
    var assetFallback: String? = nil
    var symbolFallback: String = "app.fill"
    var symbolColor: Color = .accentColor
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let nsImage = resolvedIcon() ?? assetFallback.flatMap({ NSImage(named: NSImage.Name($0)) }) {
                Image(nsImage: compactMenuIcon(nsImage, size: size))
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: symbolFallback)
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolvedIcon() -> NSImage? {
        for bundleID in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                // NSWorkspace returns a valid icon even for generic apps;
                // resize to keep memory low.
                let thumb = NSImage(size: NSSize(width: 32, height: 32))
                thumb.lockFocus()
                icon.draw(
                    in: NSRect(origin: .zero, size: NSSize(width: 32, height: 32)),
                    from: NSRect(origin: .zero, size: icon.size),
                    operation: .copy, fraction: 1.0)
                thumb.unlockFocus()
                return thumb
            }
        }
        return nil
    }
}

private struct QuickShareProviderIconImage: View {
    let provider: QuickShareProvider
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                Image(nsImage: compactMenuIcon(nsImg, size: size))
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                AppIconImage(
                    bundleIdentifiers: provider.bundleIdentifiersFallback,
                    assetFallback: provider.assetFallbackName,
                    symbolFallback: provider.symbolFallbackName,
                    symbolColor: .accentColor,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
    }
}

extension QuickShareProvider {
    fileprivate var bundleIdentifiersFallback: [String] {
        switch id {
        case "LocalSend":
            return ["org.localsend.localsend_app", "org.localsend.localsend"]
        case "AirDrop":
            return ["com.apple.finder"]
        case "Mail":
            return ["com.apple.mail"]
        case "Messages":
            return ["com.apple.MobileSMS", "com.apple.iChat"]
        case "Notes":
            return ["com.apple.Notes"]
        case "Reminders":
            return ["com.apple.reminders"]
        case "Add to Safari Reading List":
            return ["com.apple.Safari"]
        default:
            return []
        }
    }

    fileprivate var assetFallbackName: String? {
        id == "LocalSend" ? "LocalSend" : nil
    }

    fileprivate var symbolFallbackName: String {
        id == "System Share Menu" ? "square.and.arrow.up.on.square" : "square.and.arrow.up"
    }
}

extension QuickShareProvider {
    fileprivate var settingsTitle: String {
        switch id {
        case "System Share Menu": "系统分享菜单"
        case "Mail": "邮件"
        case "Messages": "信息"
        case "Notes": "备忘录"
        case "Reminders": "提醒事项"
        case "Add to Safari Reading List": "添加到 Safari 阅读列表"
        default: id
        }
    }
}
