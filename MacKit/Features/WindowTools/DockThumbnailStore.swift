import AppKit
import Darwin
import ScreenCaptureKit

@MainActor
final class DockThumbnailStore {
    private final class Entry {
        let image: CGImage
        let date = Date()
        init(_ image: CGImage) { self.image = image }
    }
    private let cache = NSCache<NSString, Entry>()
    private var busy = false
    private static let captureQueue = DispatchQueue(label: "MacKit.Dock.Capture", qos: .userInitiated)

    init() {
        cache.totalCostLimit = 8 * 1024 * 1024
        cache.countLimit = 24
    }

    private func key(_ window: DockWindow) -> NSString { "\(window.pid):\(window.id)" as NSString }
    func cached(_ window: DockWindow) -> CGImage? {
        guard let entry = cache.object(forKey: key(window)), Date().timeIntervalSince(entry.date) < 90 else { return nil }
        return entry.image
    }
    func clear() { cache.removeAllObjects() }

    /// A single capture batch owns the lane even if its caller is cancelled.
    /// This prevents cancelled hovers from piling up WindowServer requests.
    func refresh(_ windows: [DockWindow], receive: (CGWindowID, CGImage) -> Void) async {
        for _ in 0..<60 {
            if !busy { break }
            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled else { return }
        }
        guard !busy, !Task.isCancelled else { return }
        busy = true
        defer { busy = false }
        let permitted = await Task.detached(priority: .userInitiated) { CGPreflightScreenCaptureAccess() }.value
        guard permitted, !Task.isCancelled else { return }
        var missing: [DockWindow] = []
        for window in windows {
            guard !Task.isCancelled else { return }
            let image: CGImage? = await withCheckedContinuation { continuation in
                Self.captureQueue.async {
                    autoreleasepool { continuation.resume(returning: Self.windowServerImage(window.id)) }
                }
            }
            guard !Task.isCancelled else { return }
            if let image {
                cache.setObject(Entry(image), forKey: key(window), cost: image.bytesPerRow * image.height)
                receive(window.id, image)
            } else { missing.append(window) }
        }
        guard !missing.isEmpty, !Task.isCancelled,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
        for window in missing {
            guard !Task.isCancelled else { return }
            guard let target = content.windows.first(where: { $0.windowID == window.id }) else { continue }
            let configuration = SCStreamConfiguration()
            let ratio = min(360 / max(target.frame.width, 1), 220 / max(target.frame.height, 1), 1)
            configuration.width = max(1, Int(target.frame.width * ratio))
            configuration.height = max(1, Int(target.frame.height * ratio))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            guard let surface = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration),
                  !Task.isCancelled, let image = Self.bitmap(surface) else { continue }
            cache.setObject(Entry(image), forKey: key(window), cost: image.bytesPerRow * image.height)
            receive(window.id, image)
        }
    }

    /// Optional private symbols are resolved at runtime; ScreenCaptureKit is
    /// the fallback when they are absent or a window has no backing surface.
    private nonisolated static func windowServerImage(_ id: CGWindowID) -> CGImage? {
        typealias Connection = @convention(c) () -> UInt32
        typealias Capture = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
              let captureSymbol = dlsym(handle, "CGSHWCaptureWindowList") else { return nil }
        let connection = unsafeBitCast(connectionSymbol, to: Connection.self)()
        guard connection != 0 else { return nil }
        var number = id
        let capture = unsafeBitCast(captureSymbol, to: Capture.self)
        guard let images = capture(connection, &number, 1, 0x900)?.takeRetainedValue(), CFArrayGetCount(images) > 0,
              let pointer = CFArrayGetValueAtIndex(images, 0) else { return nil }
        let value = unsafeBitCast(pointer, to: CFTypeRef.self)
        guard CFGetTypeID(value) == CGImage.typeID else { return nil }
        return bitmap(value as! CGImage)
    }

    private nonisolated static func bitmap(_ image: CGImage) -> CGImage? {
        guard image.width > 1, image.height > 1 else { return nil }
        let ratio = min(360 / CGFloat(image.width), 220 / CGFloat(image.height), 1)
        let width = max(1, Int(CGFloat(image.width) * ratio)), height = max(1, Int(CGFloat(image.height) * ratio))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var visible = false
        for y in stride(from: 0, to: height, by: max(1, height / 20)) {
            for x in stride(from: 0, to: width, by: max(1, width / 20)) {
                let offset = y * context.bytesPerRow + x * 4
                if pixels[offset + 3] > 8 && max(pixels[offset], pixels[offset + 1], pixels[offset + 2]) > 6 { visible = true }
            }
        }
        return visible ? context.makeImage() : nil
    }
}
