// MacKit display topology for optional built-in lyric shelf, GPL-3.0-or-later.
import CoreGraphics

nonisolated enum BuiltinLyricAvailability {
    static var hasOnlyBuiltinDisplay: Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).allSatisfy { CGDisplayIsBuiltin($0) != 0 }
    }
}
