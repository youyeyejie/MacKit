import Foundation

enum DockClickIntent: Sendable { case minimize, restore, ignore, native }

enum DockClickPolicy {
    static func intent(active: Bool, lastMinimized: Bool?, elapsed: TimeInterval) -> DockClickIntent {
        if let lastMinimized, elapsed < 1.5 {
            if elapsed < 0.25 { return .ignore }
            return lastMinimized ? .restore : .minimize
        }
        if active { return .minimize }
        return lastMinimized == true ? .restore : .native
    }
}
