// MacKit per-application gain. Uses public Core Audio process taps; GPL-3.0-or-later.
import AppKit
import CoreAudio
import AudioToolbox
import Combine
import Synchronization

@available(macOS 15.0, *)
@MainActor final class AppVolumeMixer: ObservableObject {
    static let shared = AppVolumeMixer()
    struct App: Identifiable {
        let id: String
        let name: String
        let icon: NSImage
        let processes: [AudioObjectID]
    }
    @Published private(set) var apps: [App] = []
    @Published private(set) var volumes: [String: Double] = [:]
    @Published var message: String?
    private var engines: [String: AppGainRoute] = [:]
    private var timer: Timer?
    private var visible = false
    private var output: AudioObjectID = 0
    private var formatObservers: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock] = [:]
    private var observers: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock] = [:]

    func open() {
        visible = true
        installObservers()
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    func close() {
        visible = false
        timer?.invalidate(); timer = nil
        if engines.isEmpty { removeObservers() }
    }
    func reset() {
        for engine in engines.values { engine.stop() }
        engines.removeAll(); volumes.removeAll()
        removeFormatObservers()
        if !visible { removeObservers() }
    }
    func setVolume(_ value: Double, for app: App) {
        let gain = min(1, max(0, value))
        if gain >= 0.999 {
            engines.removeValue(forKey: app.id)?.stop()
            volumes[app.id] = 1
            if engines.isEmpty {
                removeFormatObservers()
                if !visible { removeObservers() }
            }
            return
        }
        do {
            if let engine = engines[app.id] { engine.setGain(Float(gain)) }
            else {
                let engine = try AppGainRoute(processes: app.processes, gain: Float(gain))
                engines[app.id] = engine
                installObservers()
                observeOutputFormat()
            }
            volumes[app.id] = gain
            message = nil
        } catch {
            engines.removeValue(forKey: app.id)?.stop()
            volumes[app.id] = 1
            message = "无法调整“\(app.name)”：\(error.localizedDescription)"
        }
    }
    private func installObservers() {
        guard observers.isEmpty else { return }
        for key in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice] {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            var address = audioAddress(key)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr { observers[key] = block }
        }
    }
    private func observeOutputFormat() {
        guard formatObservers.isEmpty, output != 0 else { return }
        for key in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.engines.isEmpty else { return }
                    self.reset()
                    self.message = "音频设备格式已变化，已恢复原始输出，请重新调整。"
                }
            }
            var address = audioAddress(key)
            if AudioObjectAddPropertyListenerBlock(output, &address, .main, block) == noErr { formatObservers[key] = block }
        }
    }
    private func removeFormatObservers() {
        for (key, block) in formatObservers {
            var address = audioAddress(key)
            AudioObjectRemovePropertyListenerBlock(output, &address, .main, block)
        }
        formatObservers.removeAll()
    }
    private func removeObservers() {
        removeFormatObservers()
        for (key, block) in observers {
            var address = audioAddress(key)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        observers.removeAll()
    }
    func refresh() {
        let nextOutput: AudioObjectID = audioScalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: 0)
        if output != 0 && nextOutput != output {
            removeFormatObservers()
        }
        if output != 0 && nextOutput != output && !engines.isEmpty {
            reset()
            message = "输出设备已切换，已恢复原始音量，请重新调整。"
        }
        output = nextOutput
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
        var groups: [String: (String, NSImage, [AudioObjectID])] = [:]
        for process in audioIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            let pid: pid_t = audioScalar(process, kAudioProcessPropertyPID, initial: 0)
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            let bundle = audioString(process, kAudioProcessPropertyBundleID) ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid.\(pid)"
            guard bundle != Bundle.main.bundleIdentifier else { continue }
            let owner = running.filter { app in
                guard let id = app.bundleIdentifier else { return false }
                return bundle == id || bundle.hasPrefix(id + ".")
            }.min { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) } ?? NSRunningApplication(processIdentifier: pid)
            let id = owner?.bundleIdentifier ?? bundle
            let active: UInt32 = audioScalar(process, kAudioProcessPropertyIsRunningOutput, initial: 0)
            guard active != 0 || engines[id] != nil else { continue }
            var group = groups[id] ?? (owner?.localizedName ?? bundle, owner?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!, [])
            group.2.append(process); groups[id] = group
        }
        let next = groups.map { App(id: $0.key, name: $0.value.0, icon: $0.value.1, processes: $0.value.2.sorted()) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for id in Array(engines.keys) {
            guard let route = engines[id] else { continue }
            if next.first(where: { $0.id == id })?.processes != route.processes {
                route.stop(); engines.removeValue(forKey: id)
                let gain = volumes[id] ?? 1
                if let app = next.first(where: { $0.id == id }), gain < 0.999 {
                    do { engines[id] = try AppGainRoute(processes: app.processes, gain: Float(gain)) }
                    catch { volumes[id] = 1; message = "音频进程已变化，无法恢复该应用的音量，已恢复原始输出。" }
                } else { volumes.removeValue(forKey: id) }
            }
        }
        apps = next
    }
}

private func audioAddress(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}
private func audioScalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) -> T {
    var address = audioAddress(selector, scope: scope), value = initial
    var size = UInt32(MemoryLayout<T>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return initial }
    return value
}
private func audioIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var address = audioAddress(selector, scope: scope), size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!) }
    return status == noErr ? ids : []
}
private func audioString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = audioAddress(selector), value: CFString?, size = UInt32(MemoryLayout<CFString?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value as String?
}

@available(macOS 15.0, *)
private final class GainRenderState: @unchecked Sendable {
    let target: Atomic<UInt32>
    var current: Float
    let planar: Bool
    init(gain: Float, planar: Bool) { target = Atomic(gain.bitPattern); current = gain; self.planar = planar }
    func render(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
        guard let first = inputs.first else { return }
        let inputPlanar = inputs.count >= 2 && first.mNumberChannels == 1
        let count = inputPlanar ? 2 : 1
        guard inputs.count >= count else { return }
        let base = inputs.count - count
        guard inputPlanar || inputs[base].mNumberChannels == 2 else { return }
        let wanted = Float(bitPattern: target.load(ordering: .relaxed))
        let frames = Int(inputs[base].mDataByteSize) / MemoryLayout<Float>.size / (inputPlanar ? 1 : 2)
        guard frames > 0 else { return }
        var outputChannel = 0
        for buffer in outputs {
            guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let channels = Int(buffer.mNumberChannels)
            let available = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / max(1, channels))
            for frame in 0..<available {
                let gain = current + (wanted - current) * min(1, Float(frame + 1) / 256)
                for channel in 0..<channels {
                    let index = outputChannel + channel
                    guard index < 2 else { continue }
                    let source = inputs[base + (inputPlanar ? index : 0)]
                    if let samples = source.mData?.assumingMemoryBound(to: Float.self) {
                        pointer[frame * channels + channel] = samples[inputPlanar ? frame : frame * 2 + index] * gain
                    }
                }
            }
            outputChannel += channels
        }
        current += (wanted - current) * min(1, Float(frames) / 256)
    }
}

@available(macOS 15.0, *)
@MainActor private final class AppGainRoute {
    let processes: [AudioObjectID]
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var proc: AudioDeviceIOProcID?
    private var render: GainRenderState?
    private var description: CATapDescription?
    init(processes: [AudioObjectID], gain: Float) throws {
        self.processes = processes
        do {
            let output: AudioObjectID = audioScalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: 0)
            guard output != 0, let uid = audioString(output, kAudioDevicePropertyDeviceUID) else { throw MixerError.output }
            // Avoid opening a physical input stream or changing a multichannel route.
            guard audioIDs(output, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).isEmpty else { throw MixerError.format("当前设备含物理输入流，保持原始输出以避免开启麦克风") }
            // Capture the selected device stream at its own rate instead of the
            // system mixdown rate (which can be 48k while the output is 96k).
            let description = CATapDescription(processes: processes, deviceUID: uid, stream: 0)
            description.name = "MacKit 应用音量"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            self.description = description
            try check(AudioHardwareCreateProcessTap(description, &tap))
            let format = audioScalar(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32, format.mChannelsPerFrame == 2 else { throw MixerError.format("捕获流为 \(Int(format.mSampleRate))Hz / \(format.mChannelsPerFrame) 声道 / \(format.mBitsPerChannel) 位，暂不兼容") }
            let config: [String: Any] = [kAudioAggregateDeviceNameKey: "MacKit 应用音量", kAudioAggregateDeviceUIDKey: "com.mackit.app.volume.\(UUID().uuidString)", kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceIsStackedKey: false, kAudioAggregateDeviceMainSubDeviceKey: uid, kAudioAggregateDeviceClockDeviceKey: uid, kAudioAggregateDeviceTapAutoStartKey: true, kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]], kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &device))
            let out = audioScalar(device, kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeOutput, initial: AudioStreamBasicDescription())
            guard out.mFormatFlags & kAudioFormatFlagIsFloat != 0, out.mBitsPerChannel == 32, out.mChannelsPerFrame == 2, abs(out.mSampleRate - format.mSampleRate) < 1 else { throw MixerError.format("捕获流 \(Int(format.mSampleRate))Hz，输出流 \(Int(out.mSampleRate))Hz / \(out.mChannelsPerFrame) 声道 / \(out.mBitsPerChannel) 位，无法匹配") }
            let state = GainRenderState(gain: gain, planar: format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0)
            render = state
            try check(AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { _, input, _, output, _ in state.render(input, output) })
            try check(AudioDeviceStart(device, proc))
        } catch { stop(); throw error }
    }
    func setGain(_ value: Float) { render?.target.store(value.bitPattern, ordering: .relaxed) }
    func stop() {
        if let proc, device != 0 { AudioDeviceStop(device, proc); AudioDeviceDestroyIOProcID(device, proc) }
        proc = nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        render = nil
        description = nil
    }
    private func check(_ status: OSStatus) throws { if status != noErr { throw MixerError.system(status) } }
}
private enum MixerError: LocalizedError {
    case output, format(String), system(OSStatus)
    var errorDescription: String? {
        switch self {
        case .output: "未找到当前输出设备。"
        case .format(let detail): "\(detail)。已保持原始输出。"
        case .system(let status): "系统音频访问失败（\(status)），请检查系统音频录制权限。"
        }
    }
}
