import SwiftUI

struct AppVolumeButton: View {
    var iconSize: CGFloat = 18
    var buttonSize: CGFloat = 32
    @State private var presented = false
    @State private var suppressionToken = UUID()
    @State private var suppressedModels: [DynamicIslandViewModel] = []
    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.85)).frame(width: buttonSize, height: buttonSize)
        }.buttonStyle(.plain).help("应用音量")
            .onChange(of: presented) { _, active in setSuppressed(active) }
            .onDisappear { setSuppressed(false) }
            .popover(isPresented: $presented) {
                if #available(macOS 15.0, *) { AppVolumePanel() }
                else { Text("按应用调音需要 macOS 15 或更新版本。").padding() }
            }
    }
    private func setSuppressed(_ active: Bool) {
        if active {
            guard suppressedModels.isEmpty, let delegate = AtollIntegration.shared.delegate else { return }
            var seen: Set<ObjectIdentifier> = []
            suppressedModels = ([delegate.vm] + Array(delegate.viewModels.values)).filter { seen.insert(ObjectIdentifier($0)).inserted }
            for model in suppressedModels { model.setAutoCloseSuppression(true, token: suppressionToken) }
        } else {
            for model in suppressedModels {
                model.setAutoCloseSuppression(false, token: suppressionToken)
                model.shouldRecheckHover.toggle()
            }
            suppressedModels.removeAll()
        }
    }

}
@available(macOS 15.0, *)
private struct AppVolumePanel: View {
    @ObservedObject private var mixer = AppVolumeMixer.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("应用音量").font(.headline); Spacer(); Button("全部还原") { mixer.reset() } }
            Text("首次调整会请求系统音频访问；音频仅在本机处理，不保存或上传。恢复 100% 即释放该应用的处理链路。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if mixer.apps.isEmpty { Text("暂无正在输出声音的应用").foregroundStyle(.secondary).padding(.vertical, 12) }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(mixer.apps) { app in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                                Text(app.name).lineLimit(1)
                                Spacer()
                                Text("\(Int((mixer.volumes[app.id] ?? 1) * 100))%").monospacedDigit()
                            }
                            Slider(value: Binding(get: { mixer.volumes[app.id] ?? 1 }, set: { mixer.setVolume($0, for: app) }), in: 0...1)
                        }
                    }
                }
            }.frame(maxHeight: 300)
            if let message = mixer.message { Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.padding(16).frame(width: 340)
            .onAppear { mixer.open() }.onDisappear { mixer.close() }
    }
}
