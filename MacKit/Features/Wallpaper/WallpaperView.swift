import SwiftUI

struct WallpaperView: View {
    @Bindable var service: WallpaperService
    var body: some View {
        PageLayout {
            SettingsRows(title: "壁纸管理") {
                VStack(spacing: 0) {
                    SettingsRow(title: "导入壁纸") {
                        Button(service.busy ? "正在导入…" : "导入本地视频", action: service.importVideos)
                            .disabled(service.busy || !service.supported)
                    }
                    Divider()
                    SettingsRow(title: "管理壁纸") {
                        Button("在访达中显示", action: service.revealLibrary).disabled(service.videos.isEmpty)
                    }
                }
                if !service.videos.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 12)], alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(service.videos) { video in
                            WallpaperLibraryCard(video: video, service: service)
                        }
                    }
                }
            }
            SettingsRows(title: "动态壁纸") {
                SettingsRow(title: "选择壁纸") { Button("前往系统设置", action: service.openSettings) }
                Divider()
                SettingsRow(title: "恢复动态壁纸", subtitle: "壁纸进程意外退出后，重新连接系统壁纸服务。") {
                    Button(service.recovering ? "正在恢复…" : "恢复动态壁纸", action: service.recoverWallpaper)
                        .disabled(service.recovering || !service.supported)
                }
                Divider()
                CompactSettingsSlider(
                    value: Binding(get: { service.routing.duration }, set: { service.routing.transitionSeconds = $0 }),
                    in: 0...2, step: 0.1, valueText: String(format: "%.1f 秒", service.routing.duration)
                ) {
                    Text("壁纸过渡")
                } onEditingChanged: { editing in
                    if !editing { service.saveOptions() }
                }
                Divider()
                SettingsRow(title: "被遮挡时暂停") {
                    Toggle(
                        "被遮挡时暂停",
                        isOn: Binding(
                            get: { service.pauseWhenCovered },
                            set: {
                                service.pauseWhenCovered = $0
                                service.saveOptions()
                            })
                    )
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                CompactSettingsSlider(
                    value: Binding(
                        get: { Double(service.routing.pollingStep) },
                        set: {
                            service.routing.detectionSeconds = WallpaperRouting.detectionIntervals[Int($0.rounded())]
                        }),
                    in: 0...Double(WallpaperRouting.detectionIntervals.count - 1), step: 1,
                    valueText: String(format: "%.1f 秒", service.routing.pollingInterval), uniform: false
                ) {
                    Text("遮挡检测频率")
                } onEditingChanged: { editing in
                    if !editing { service.saveOptions() }
                }
                .disabled(!service.pauseWhenCovered)
            }
            SettingsRows(title: "动态锁屏") {
                SettingsRow(title: "锁屏壁纸") {
                    Picker(
                        "锁屏壁纸",
                        selection: Binding(
                            get: { service.routing.lockedVideoID ?? "" },
                            set: {
                                service.routing.lockedVideoID = $0.isEmpty ? nil : $0
                                service.saveOptions()
                            })
                    ) {
                        Text("跟随系统选择").tag("")
                        ForEach(service.videos) { Text($0.name).tag($0.id) }
                    }.frame(minWidth: AppStyle.pickerMinimumWidth).pickerStyle(.menu).labelsHidden().fixedSize().frame(
                        width: 240, alignment: .trailing)
                }
            }
            if let message = service.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            if !service.supported { Text("原生墙纸扩展需要 macOS 26 或更新版本。").foregroundStyle(.orange) }
        }.onAppear { service.reload() }
    }
}

private struct WallpaperLibraryCard: View {
    let video: WallpaperVideo
    let service: WallpaperService
    @State private var thumbnail: NSImage?
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary).overlay(Image(systemName: "film").foregroundStyle(.secondary))
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }.aspectRatio(16.0 / 10.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 6) {
                Text(video.name).font(.caption).lineLimit(1).truncationMode(.middle).help(video.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    service.remove(video)
                } label: {
                    Image(systemName: "trash").frame(width: 16, height: 16)
                }
                .buttonStyle(.plain).controlSize(.small)
                .help("删除导入副本").disabled(service.busy)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .task(id: video.id) { thumbnail = await service.thumbnail(video) }
    }
}
