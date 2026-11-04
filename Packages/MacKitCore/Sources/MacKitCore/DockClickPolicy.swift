// SPDX-License-Identifier: GPL-3.0-or-later
// Based in part on implementation mechanisms from Vorssaint.
// Copyright (C) 2026 Vorssaint; modifications Copyright (C) 2026 youyeyejie.
// Adapted for MacKit; provenance and license update: 2026-11-04.
// See THIRD_PARTY_NOTICES.md and LICENSES/Vorssaint-GPL-3.0.txt.
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
